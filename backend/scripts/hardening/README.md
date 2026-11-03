# Libris Database Hardening Draft SQL Scripts

> [!CAUTION]
> **BU DİZİNDEKİ DOSYALAR HAZIRLANMIŞ MIGRATION ADAYLARIDIR (STAGING CANDIDATES / NOT AUTOMATICALLY EXECUTED ON PROD).**  
> Bu betikler henüz canlı üretim veritabanında çalıştırılmamıştır. Yetkilendirilmiş bakım penceresinde Supabase SQL Editor üzerinden kontrollü şekilde uygulanmalıdır.

---

## 1. Dizin İçeriği ve Durum Matrisi

| Dosya | Durum | Amaç | Rollback Dosyası | Doğrulama Testi | Risk Seviyesi |
|---|:---:|---|---|---|:---:|
| [`01_PROD_revoke_dangerous_privileges_stage1_stage2.sql`](file:///c:/Users/akifk/Desktop/book-ai-app/backend/scripts/hardening/01_PROD_revoke_dangerous_privileges_stage1_stage2.sql) | **PROD DEPLOYMENT (P0)** | Yalnızca Stage 1 (7 tabloda TRUNCATE yetkisi iptali) ve Stage 2 (`postgres` default ACL düzeltmesi). Stage 3 platform engelinden izole, bağımsız çalıştırılabilir. | `01_DRAFT_revoke_dangerous_privileges_rollback.sql` | CI Automated | Sıfır (Tam izole, P0) |
| [`01_DRAFT_revoke_dangerous_privileges.sql`](file:///c:/Users/akifk/Desktop/book-ai-app/backend/scripts/hardening/01_DRAFT_revoke_dangerous_privileges.sql) | **TASLAK (3 Aşamalı)** | 7 tabloda (`test_halfvec` dahil) `TRUNCATE` yetkilerinin kaldırılması; `postgres` ve `supabase_admin` sahip bağlamlarında varsayılan `TRUNCATE` engellenmesi. | `01_DRAFT_revoke_dangerous_privileges_rollback.sql` | CI Automated | Düşük (Sıfır veri riski) |
| [`01b_DRAFT_least_privilege_and_policy_cleanup.sql`](file:///c:/Users/akifk/Desktop/book-ai-app/backend/scripts/hardening/01b_DRAFT_least_privilege_and_policy_cleanup.sql) | **AYRI DEĞİŞİKLİK** | `books` anonim yazma politikalarının (`python_ekleme_izni`, `python_guncelleme_izni`) temizlenmesi; kullanıcı tablolarında en az yetki DML matrisi. | `01b_DRAFT_least_privilege_and_policy_cleanup_rollback.sql` | CI Automated | Düşük (Ayrı yetki temizliği) |
| [`02_DRAFT_reconcile_user_profiles.sql`](file:///c:/Users/akifk/Desktop/book-ai-app/backend/scripts/hardening/02_DRAFT_reconcile_user_profiles.sql) | **HAZIR** (Aşamalı) | Canlıdaki tek kayıt korunarak aşamalı çift-kolon (`user_id` + `id`) uyumluluğu ve eksik kolonların eklenmesi. | `02_DRAFT_reconcile_user_profiles_rollback.sql` | [`test_02_user_profiles_rollback_runtime.sql`](file:///c:/Users/akifk/Desktop/book-ai-app/backend/scripts/hardening/test_02_user_profiles_rollback_runtime.sql) (10 Senaryo) | Düşük (Geriye dönük uyumlu) |
| [`03_DRAFT_reconcile_interactions_and_trigger.sql`](file:///c:/Users/akifk/Desktop/book-ai-app/backend/scripts/hardening/03_DRAFT_reconcile_interactions_and_trigger.sql) | **HAZIR** (Model A) | Model A mimarisi: `favorites` kanonik tablosu ile `user_interactions` okuma durumlarının tam ayrıştırılması; okuma durumlarını ezmeyen/silmeyen koruyucu trigger; kayıpsız mükerrer kayıt arşivleme. | `03_DRAFT_reconcile_interactions_and_trigger_rollback.sql` | [`test_03_interactions_and_trigger_runtime.sql`](file:///c:/Users/akifk/Desktop/book-ai-app/backend/scripts/hardening/test_03_interactions_and_trigger_runtime.sql) (20 Senaryo) | Düşük (Kayıpsız uzlaştırma, Model A) |
| [`04_DRAFT_harden_vector_rpcs.sql`](file:///c:/Users/akifk/Desktop/book-ai-app/backend/scripts/hardening/04_DRAFT_harden_vector_rpcs.sql) | **HAZIR** | `match_query_embeddings`'e sabit `search_path` ve limit eklenmesi (`SECURITY INVOKER` korunur); canlıda eksik `match_book_embeddings` RPC'sinin tanımlanması. | `04_DRAFT_harden_vector_rpcs_rollback.sql` | [`test_04_vector_rpc_catalog_lifecycle.sql`](file:///c:/Users/akifk/Desktop/book-ai-app/backend/scripts/hardening/test_04_vector_rpc_catalog_lifecycle.sql) | Düşük (Fonksiyon DDL) |

---

## 2. Kritik Güvenlik ve Mimari Kararlar

1. **`01_DRAFT` TRUNCATE Sıkılaştırması (Üç Aşamalı Mimari):** 
   - **Aşama 1 (Mevcut Tablolar - P0):** 6 çekirdek uygulama tablosu (`books`, `book_embeddings`, `favorites`, `user_activities`, `user_interactions`, `user_profiles`) ve canlıdaki operasyonel test nesnesi `public.test_halfvec` olmak üzere toplam 7 tabloda `anon`, `authenticated` ve `PUBLIC` rollerinden `TRUNCATE` yetkisi tamamen kaldırılır ve bağımsız transaction ile kalıcılaştırılır (`COMMIT`).
   - **Aşama 2 (`postgres` Varsayılan ACL):** `postgres` rolü ve geçerli oturum bağlamında gelecekte oluşturulacak tablolar için hem `public` şemasında hem de global düzeyde (`defaclnamespace = 0`) varsayılan `TRUNCATE` izinleri iptal edilir ve bağımsız transaction ile doğrulanır (`COMMIT`).
   - **Aşama 3 (`supabase_admin` Platform Bağımlılığı):** `supabase_admin` rolü için varsayılan `TRUNCATE` iptalini hedefler. PostgreSQL kuralı gereği `postgres` rolü `supabase_admin` üyesi veya superuser olmadığından bu aşamayı çalıştıramaz. Yetki yükseltmesi (privilege escalation) yasağı nedeniyle `postgres` rolüne `supabase_admin` üyeliği devredilemez. Standart `postgres` çalıştırmasında açık sızıntılar tespit edildiğinde işlem fail-closed durarak platform engeli (`DEPLOYMENT_BLOCKED`) olarak raporlanır; ancak daha önce COMMIT edilen Aşama 1 ve 2 korunur.
   - İlgisiz sequence döngüleri ve şema değişiklikleri ayıklanarak en küçük güvenli değişiklik (minimal safe change) ilkesi uygulanmıştır.
   - Rollback betiği, RLS'i etkisiz kılan `TRUNCATE` yetkisini ASLA geri vermez (Fail-Safe Rollback).
2. **`01b_DRAFT` Ayrı İkincil Temizlik:**
   - Kitap tablosundaki anonim yazma politikaları ve kullanıcı tabloları DML kısıtlamaları, P0 TRUNCATE düzeltmesinden ayrılarak bağımsız bir değişiklik seti olarak yapılandırılmıştır.
3. **`02_DRAFT` Aşamalı Uyumluluğu:** Doğrudan `ALTER RENAME` yerine `user_id` kolonu eklenmiş, mevcut `id` ile doldurulmuş ve çift yönlü senkronizasyon trigger'ı kurulmuştur. Böylece eski `id` sorgulayan ve yeni `user_id` sorgulayan tüm istemciler sıfır kesintiyle çalışır.
4. **`03_DRAFT` Model A Mimarisi & Kayıpsız Arşivleme:**
   - `favorites` tablosu favori üyeliğinin kanonik deposudur. `user_interactions` okuma durumlarını (`want_to_read`, `reading`, `finished`) ve ML sinyallerini (`like`, `dislike`) bağımsız yönetir.
   - Olası mükerrer (duplicate) etkileşimler asla sessizce silinmez. Tüm mükerrer satırlar `_archived_user_interactions_duplicate_backup` tablosuna arşivlenir.
   - Favori sinyalleri `favorites` tablosuna aktarılır ve okuma durumları deterministik öncelikle (`finished` > `reading` > `want_to_read`) korunur.
   - Çözümlenemez çelişkili durumlarda (aynı kitap için hem `like` hem `dislike`) sistem fail-closed durarak veri kaybını önler.
   - Forward-recovery mekanizması 20 runtime senaryosuyla doğrulanmıştır: Yeni kullanıcı yazmaları korunur (`finished`, `dislike`), silinmiş satırlar diriltilmez, çoklu snapshot belirsizliğinde fail-closed durulur, tekil `rollback_attempt_id` oturum bazında tam izole edilir ve tam idempotency sağlanır.
5. **`04_DRAFT` Invoker Tercihi:** `match_query_embeddings` superuser haklarıyla çalıştırılmaması için `SECURITY INVOKER` olarak korunmuş; arama yolu ve bellek güvenliği `SET search_path` ve girdi tavanı (`safe_limit <= 100`) ile sağlanmıştır.
6. **Preflight 12-vs-14 Çelişkisinin Giderilmesi:**
   - Eski preflight konsolide sorgusu yalnızca 6 çekirdek tabloyu taradığı için 12 adet TRUNCATE sızıntısı sayıyordu. Detaylı katalog sorgusu ise `test_halfvec` dahil 7 tabloda 14 sızıntı tespit ediyordu.
   - Konsolide preflight sorgusu `test_halfvec` artefaktını da kapsayacak şekilde güncellenerek 14 hibe ile tam uyumlu hale getirilmiş; ayrıca varsayılan izinler için `1.1. TRUNCATE_DEFAULT_PRIVILEGES_LEAKS` kontrolü eklenmiştir.

---

## 3. Rollback İstemci Uyumluluk Sınırlamaları (Operatör Uyarısı)

> [!WARNING]
> **ROLLBACK DOSYALARI CANLI İSTEMCİLERLE GERİYE DÖNÜK UYUMLU DEĞİLDİR:**
> - **Rollback 02:** `user_id`, `preferred_authors` ve `preferred_vibe` kolonlarını tablodan siler. Bu durum, canlıda çalışan Flutter mobil uygulamasını (`supabase_service.dart`) ve backend profil sorgularını anında çökertir!
> - **Rollback 03:** `user_interactions` kısıtını 4 duruma (`like`, `dislike`, `want_to_read`, `finished`) geri çeker. Canlıda çalışan Web uygulaması (`web/src/app/actions/library.ts:336`) doğrudan `'reading'` ve `'favorite'` yazdığı için web kullanıcıları anında PostgreSQL check constraint hatası alır! Ayrıca 4'lü kısıtın doğası gereği favori silme işlemi `'like'` etkileşimini de sildiğinden bağımsız beğeni tavsiye sinyalleri kaybolur.
> - **Operasyonel İlke:** Canlıda sorun yaşandığında rastgele rollback çalıştırmak yerine **ileri onarım (forward-fix)** tercih edilmeli veya tam veritabanı yedeğinden kontrollü restore yapılmalıdır.

---

## 4. Uygulama Öncesi Zorunlu Kontroller (Gates)

1. **Yedekleme Kapısı:** Supabase Dashboard -> Database -> Backups üzerinden tam snapshot alınmalı, PITR durumu doğrulanmalıdır.
2. **Preflight Kapısı:** [`backend/scripts/preflight_database_hardening.sql`](file:///c:/Users/akifk/Desktop/book-ai-app/backend/scripts/preflight_database_hardening.sql) Bölüm 12'deki Tek Tıkla Konsolide Sorgu çalıştırılarak ön durum kanıtları kaydedilmelidir. Migration 02 öncesinde SOKU 11.1A/B, Migration 03 öncesinde ise SOKU 11.2A/B kapıları ayrı ve sıralı olarak doğrulanmalıdır.
3. **Kilit Güvenliği (Lock Timeout):** Her script başında `SET LOCAL lock_timeout = '5s';` kullanılarak lock queue tıkanmaları engellenmelidir.
4. **Sıralı Uygulama:** Dosyalar yetkilendirilmiş sırayla (01 -> 02 -> 03 -> 04) uygulanmalı ve her adım sonrası doğrulama sorguları çalıştırılmalıdır.

---

## 5. Canlı Üretim Durumu ve "supabase_admin" Varsayılan ACL Bulgusu Analizi

### 5.1 Doğrulanmış Canlı Durum ve Kanıtlar (Production Verification State)
Production Supabase SQL Editor (`postgres` oturumu) üzerinde icra edilen kontrollerin kanıtlanmış sonuçları:

1. **Mevcut 7 Hedef Tablo (Stage 1 - P0):**
   - `books`, `book_embeddings`, `favorites`, `user_activities`, `user_interactions`, `user_profiles`, `test_halfvec` tablolarında `anon` ve `authenticated` rolleri için `has_table_privilege(..., 'TRUNCATE')` denetimi: **0 SATIR (BAŞARILI / GEÇTİ)**.
   - Mevcut canlı tablolarda istemciler için RLS'i baypas eden TRUNCATE açığı **tamamen kapatılmıştır**.
2. **`postgres` Rolü Varsayılan ACL (Stage 2):**
   - `pg_default_acl` kataloğunda `defaclrole = postgres` için hem `public` şemasında hem global (`defaclnamespace = 0`) kapsamda `anon` ve `authenticated` TRUNCATE hibeleri: **0 SATIR (BAŞARILI / GEÇTİ)**.
   - `postgres` rolüyle (migration, SQL Editor veya DDL scriptleri) açılacak yeni uygulama tablolarına TRUNCATE yetkisi **kesinlikle atanmayacaktır**.
3. **`supabase_admin` Rolü Varsayılan ACL (Kalan Platform Bulgusu):**
   - `pg_default_acl` kataloğunda `defaclrole = supabase_admin` için `public` şemasında `anon` ve `authenticated` rollerine tanımlı **2 adet** varsayılan TRUNCATE kaydı mevcuttur.
   - Mevcut SQL Editor oturumu `postgres` rolüdür; `postgres` kullanıcısı `superuser` değildir ve `supabase_admin` rolünün üyesi değildir.

---

### 5.2 Gerçek Risk ve PostgreSQL Rol Modeli: Gerçekler vs. Yanlış Kanılar (Facts vs. Myths)

| İnceleme Boyutu | Yanlış Kanı / Tahmin (Myth) | Doğrulanmış Gerçek (Fact) | Güvenlik Etkisi |
|---|---|---|:---:|
| **Mevcut Veriler** | "Kullanıcı veya kitap verilerimiz şu anda anonim/oturum açmış kullanıcılar tarafından TRUNCATE ile silinebilir." | **YANLIŞ.** Canlıdaki 7 tablonun tamamında istemci TRUNCATE izni 0'dır. Mevcut verilerde RLS baypası imkansızdır. | **SIFIR RİSK (P0 Çözüldü)** |
| **Gelecekteki Uygulama Tabloları** | "Yeni bir migration veya tablo oluşturduğumuzda bu açık o tabloya da bulaşacak." | **YANLIŞ.** PostgreSQL mimarisinde varsayılan ACL'ler nesneyi oluşturan role (`defaclrole`) göre tetiklenir. Uygulama tabloları `postgres` tarafından açılır ve `postgres`'in varsayılan TRUNCATE hibesi 0'dır. | **SIFIR RİSK (İzole)** |
| **Yetki Yükseltme (Privilege Escalation)** | "`GRANT supabase_admin TO postgres;` vererek veya `SET ROLE` ile SQL Editor'dan bu kayıtları silebiliriz." | **YANLIŞ VE YASAK.** PostgreSQL `permission denied` verir. `postgres` kullanıcısı admin option'a sahip değildir. Yetki yükseltme girişimi güvenlik ilkelerine aykırıdır ve yasaktır. | **ENGEL (Platform Güvenliği)** |
| **Gerçek Artık Risk (Residual Risk)** | "Bu kayıtların hiçbir etkisi yoktur, tamamen göz ardı edilebilir." | **YANLIŞ.** İki somut artık risk vardır: <br>1. Supabase arka plan servisleri doğrudan `supabase_admin` kimliğiyle `public` şemasında yeni bir tablo yaratırsa, o tabloya otomatik TRUNCATE atanır.<br>2. Güvenlik denetim araçları (CIS PostgreSQL Benchmark, preflight Section 1.1) `pg_default_acl` taramasında 2 sızıntı görerek FAIL vermeye devam eder. | **ORTA (Denetim & Şema Hijyeni)** |

---

### 5.3 PostgreSQL Rol Modeli Sınırları ve Kalan Platform Engeli

- **PostgreSQL Spesifikasyonu (`ALTER DEFAULT PRIVILEGES`):**
  PostgreSQL resmi kuralı gereği:
  ```
  ALTER DEFAULT PRIVILEGES FOR ROLE target_role ...
  ```
  ifadesi **yalnızca** oturumu açan kullanıcının kendisi (`current_user = target_role`), oturum kullanıcısının üyesi olduğu bir rol (`pg_has_role(current_user, target_role, 'USAGE')`) veya bir `superuser` (`rolsuper = true`) tarafından çalıştırılabilir.
- **Supabase Cloud Mimarisi:**
  Supabase Cloud yönetilen PaaS mimarisinde:
  - `postgres`: Kiracı (tenant) veritabanı sahibidir; ancak `superuser` DEĞİLDİR.
  - `supabase_admin`: Supabase platform altyapısının kontrol düzlemi (control plane) rolüdür.
  - `postgres` kullanıcısı `supabase_admin` üyesi değildir ve `GRANT supabase_admin TO postgres` komutunu çalıştırma hakkına (`ADMIN OPTION`) sahip değildir.
- **Sonuç (Kalan Platform Engeli):**
  Bu 2 kayıt, veritabanı kiracı oturumu (`postgres`) üzerinden DDL ile kaldırılamaz. Bu bir uygulama açığı değil, **Supabase platformunun varsayılan şablonundan gelen bir platform seviyesi konfigürasyon artığıdır**.

---

### 5.4 Desteklenen ve En Az Riskli Çözüm Yolu

#### Yöntem 1: Supabase Platform Destek Bileti (Supabase Cloud İçin Tek Resmi Yol)
Supabase Cloud ortamında `supabase_admin` kimliğine doğrudan erişim sağlanamaz. En güvenli, desteklenen ve sıfır riskli yöntem Supabase Destek Ekibine bilet açmaktır.

**Supabase Destek Bileti Şablonu:**
```text
Başlık: Security Hardening: Revoke default TRUNCATE privileges from anon and authenticated in public schema for supabase_admin role

Proje Referansı: <PROJECT_REF>

Açıklama:
Veritabanı güvenlik sıkılaştırması kapsamında 'anon' ve 'authenticated' rollerinin mevcut tablolardaki ve 'postgres' rolü varsayılanlarındaki TRUNCATE yetkilerini başarıyla kaldırdık.
Ancak 'pg_default_acl' kataloğunda 'supabase_admin' sahibi altında 'public' şemasında iki adet varsayılan TRUNCATE hibesi bulunmaktadır:
- Owner: supabase_admin, Grantee: anon, Privilege: TRUNCATE, Schema: public
- Owner: supabase_admin, Grantee: authenticated, Privilege: TRUNCATE, Schema: public

'postgres' kullanıcısı superuser veya supabase_admin üyesi olmadığı için bu işlemi ALTER DEFAULT PRIVILEGES ile doğrudan yapamamaktayız.

Aşağıdaki komutun veritabanımızda 'supabase_admin' veya platform superuser bağlamında çalıştırılmasını rica ederiz:

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public REVOKE TRUNCATE ON TABLES FROM anon, authenticated, PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin REVOKE TRUNCATE ON TABLES FROM anon, authenticated, PUBLIC;
```

#### Yöntem 2: Self-Hosted / Yerel Geliştirme (Local Docker) Ortamı
Yerel veya self-hosted Supabase ortamlarında operatör doğrudan sunucu erişimine sahiptir:
```bash
# Docker container içinde doğrudan supabase_admin / superuser ile çalıştırma:
docker exec -i <supabase_db_container> psql -U supabase_admin -d postgres -c \
  "ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public REVOKE TRUNCATE ON TABLES FROM anon, authenticated, PUBLIC; \
   ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin REVOKE TRUNCATE ON TABLES FROM anon, authenticated, PUBLIC;"
```

#### Yasaklanan / Uygulanamaz Yöntemler (Strictly Prohibited):
- `GRANT supabase_admin TO postgres`: Yetki yükseltme girişimidir; PostgreSQL izin vermez ve repository güvenlik kurallarınca kesinlikle yasaktır.
- `DELETE FROM pg_default_acl`: Sistem kataloğunu doğrudan DML ile değiştirmek `allow_system_table_mods` kapalı olduğundan engellenir ve katalog tutarlılığını riske atar.

---

### 5.5 Canlı Doğrulama ve Denetim Sorguları (Runbook Queries)

Aşağıdaki sorgular Supabase SQL Editor'da (`postgres` rolüyle) güvenle çalıştırılarak mevcut durum kanıtlanabilir:

```sql
-- SOKU 1: 7 Hedef Tabloda TRUNCATE Kontrolü (Beklenen: 0 Satır)
SELECT 
    t.relname AS table_name,
    r.rolname AS client_role,
    has_table_privilege(r.rolname, t.oid, 'TRUNCATE') AS has_truncate
FROM pg_class t
JOIN pg_namespace n ON n.oid = t.relnamespace
CROSS JOIN (VALUES ('anon'), ('authenticated')) AS r(rolname)
WHERE n.nspname = 'public'
  AND t.relkind = 'r'
  AND t.relname IN ('books', 'book_embeddings', 'favorites', 'user_activities', 'user_interactions', 'user_profiles', 'test_halfvec')
  AND has_table_privilege(r.rolname, t.oid, 'TRUNCATE') = true;

-- SOKU 2: 'postgres' Varsayılan TRUNCATE Kontrolü (Beklenen: 0 Satır)
SELECT 
    rol.rolname AS default_privilege_owner,
    COALESCE(n.nspname, 'GLOBAL') AS schema_scope,
    CASE acl.grantee WHEN 0 THEN 'PUBLIC' ELSE COALESCE(gr.rolname, 'OID:' || acl.grantee::text) END AS grantee_role,
    acl.privilege_type
FROM pg_default_acl d
JOIN pg_roles rol ON rol.oid = d.defaclrole
LEFT JOIN pg_namespace n ON n.oid = d.defaclnamespace
CROSS JOIN LATERAL aclexplode(d.defaclacl) acl
LEFT JOIN pg_roles gr ON gr.oid = acl.grantee
WHERE d.defaclobjtype = 'r'
  AND (n.nspname = 'public' OR d.defaclnamespace = 0)
  AND acl.privilege_type = 'TRUNCATE'
  AND (acl.grantee = 0 OR gr.rolname IN ('anon', 'authenticated', 'public'))
  AND rol.rolname = 'postgres';

-- SOKU 3: 'supabase_admin' Varsayılan TRUNCATE Kontrolü (Mevcut Durum: 2 Satır - Platform Destek Bileti Bekleniyor)
SELECT 
    rol.rolname AS default_privilege_owner,
    COALESCE(n.nspname, 'GLOBAL') AS schema_scope,
    CASE acl.grantee WHEN 0 THEN 'PUBLIC' ELSE COALESCE(gr.rolname, 'OID:' || acl.grantee::text) END AS grantee_role,
    acl.privilege_type
FROM pg_default_acl d
JOIN pg_roles rol ON rol.oid = d.defaclrole
LEFT JOIN pg_namespace n ON n.oid = d.defaclnamespace
CROSS JOIN LATERAL aclexplode(d.defaclacl) acl
LEFT JOIN pg_roles gr ON gr.oid = acl.grantee
WHERE d.defaclobjtype = 'r'
  AND (n.nspname = 'public' OR d.defaclnamespace = 0)
  AND acl.privilege_type = 'TRUNCATE'
  AND (acl.grantee = 0 OR gr.rolname IN ('anon', 'authenticated', 'public'))
  AND rol.rolname = 'supabase_admin';
```
