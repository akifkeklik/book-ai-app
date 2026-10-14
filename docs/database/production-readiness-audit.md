# Libris Database Production Readiness & Reconciliation Audit

**Tarih:** 2026-10-13  
**Repository:** `akifkeklik/book-ai-app`  
**Git Commit:** `9188d3e6cfca0c89aac202471be4274fee788c3b` (Branch: `main`)  
**Denetim Rolü:** Senior Database Engineer, PostgreSQL/Supabase Security Engineer, Production Reliability Engineer  
**Erişim Modeli:** Read-Only Audit & Drafting (Canlı Supabase üzerinde doğrudan SQL çalıştırılmamıştır; canlı bulgular kullanıcının sağladığı doğrulanmış SQL Editor çıktılarına dayanmaktadır).

---

## 1. YÖNETİCİ ÖZETİ (EXECUTIVE SUMMARY)

Libris V1 veritabanı altyapısının kod tabanı (`backend/scripts/`, `backend/infrastructure/`, `mobile/flutter_app/`, `web/src/app/actions/library.ts`) ile canlı Supabase PostgreSQL bulguları arasındaki uzlaştırma ve güvenlik denetimi tamamlanmıştır.

Yapılan inceleme sonucunda, **5 kritik mimari ve operasyonel açık** tespit edilmiştir:

1. **Katastrofik Yetki Sızıntısı (P0 - TRUNCATE & Anon Write):**
   Canlı veritabanındaki tüm tablolarda (`books`, `book_embeddings`, `favorites`, `user_activities`, `user_interactions`, `user_profiles`), `anon` ve `authenticated` rollerine `TRUNCATE` izni verilmiştir. PostgreSQL mimarisinde **`TRUNCATE` komutları RLS (Row Level Security) kurallarını tamamen baypas eder**. Anonim veya giriş yapmış herhangi bir istemci tek bir HTTP/SQL komutuyla tüm veri tabanını sıfırlayabilir. Ayrıca `books` tablosunda `python_ekleme_izni` ve `python_guncelleme_izni` adlı politikalarla anonim kullanıcılara açık katalog manipülasyon hakkı tanınmıştır.
2. **Koleksiyon Durumu & Check Constraint Uyuşmazlığı (P1 - Runtime Error):**
   Canlı `public.user_interactions` tablosundaki CHECK kısıtı yalnızca `('like', 'dislike', 'want_to_read', 'finished')` değerlerini kabul etmektedir. `07_phase3_collections.sql` migration'ı canlıya uygulanmamıştır. Ancak Web uygulaması (`web/src/app/actions/library.ts`) doğrudan `'favorite'` ve `'reading'` durumlarını yazmaktadır. Bu durum, web kullanıcılarının kitap koleksiyonu güncellemelerinde anında PostgreSQL seviyesinde `check constraint violation` hatası almasına neden olmaktadır.
3. **Yıkıcı Favori Trigger'ı & Mimari Çıkmaz (P1 - Silent Data Destruction & Bloke Durum):**
   Canlıdaki `trg_sync_favorites` trigger'ı (`sync_favorites_to_interactions()` fonksiyonu), kullanıcı bir kitabı favorilediğinde `user_interactions` tablosunda mevcut olan durumu (`want_to_read`, `reading`, `finished`) sormadan üzerine `'like'` yazmaktadır (`ON CONFLICT (user_id, book_id) DO UPDATE SET interaction_type = 'like'`). Kullanıcı favoriden çıkardığında ise yalnızca `interaction_type = 'like'` ise silmekte; eski okuma durumu kalıcı olarak kaybolmaktadır. Tek bir `(user_id, book_id)` çifti için hem okuma durumu hem favori tutulamadığı için bu düzeltme operatör tasarım kararına kadar **BLOKE** edilmiştir.
4. **`user_profiles` Şema Uyuşmazlığı & Aşamalı Çözüm (P1 - Schema Divergence):**
   Canlıdaki `user_profiles` tablosu `id UUID PRIMARY KEY REFERENCES auth.users(id)` kolonuna sahipken; repo kodları (Flutter `supabase_service.dart`, Flask `supabase_adapters.py`, SQL `08_user_profiles_and_activities.sql`) `user_id` kolonunu sorgulamakta ve upsert etmektedir. Ayrıca canlı tabloda `preferred_authors` ve `preferred_vibe` kolonları bulunmamaktadır. Canlıda bulunan mevcut 1 adet profil kaydının korunması ve eski/yeni istemcilerin kırılmaması için aşamalı çift-kolon (`user_id` + `id`) modeli tasarlanmıştır.
5. **Eksik Vektör RPC'si Nedeniyle Hibrit Önerilerin Sessizce Çökmesi (P2 - Feature Degradation):**
   Canlı veritabanında `match_query_embeddings` fonksiyonu mevcuttur; ancak `match_book_embeddings` RPC'si (`04_phase3_hybrid.sql` / `05_phase3_performance.sql`) canlı fonksiyon kataloğunda **bulunmamaktadır**. Backend `SupabaseBookDataPort.get_semantic_candidates` çağrısı istisna fırlatmakta ve sessizce boş sözlük dönmektedir (`fallback to non-semantic`). Mevcut `match_query_embeddings` ise `search_path` manipülasyonuna ve bellek aşımına açıktır.

---

## 2. KANIT SINIFLANDIRMASI VE METODOLOJİ

| Kategori | Kanıt / Durum | Detay |
|---|---|---|
| **Doğrulanmış Canlı Bulgular (Operator-Verified)** | SQL Editor Çıktıları | 6 tablonun varlığı; relrowsecurity=true; TRUNCATE izinleri; `books` python politikaları; `user_profiles` 1 satır ve `id` PK kolonu; `user_interactions` 4 türlü CHECK kısıtı; `match_query_embeddings` varlığı; `match_book_embeddings` yokluğu. |
| **Doğrulanmış Repo Gerçekleri (Repo-Verified)** | Kod Analizi (`git: 9188d3e`) | Flutter ve Flask'ın `user_profiles.user_id` kullanması; Web `library.ts`'nin `favorite` ve `reading` yazması; backend testlerinin (198 test) ve web testlerinin (37 test) geçerliliği. |
| **Çıkarılmış Riskler (Inferred Risks)** | Veritabanı & Mimari Analizi | RLS'in TRUNCATE'i engelleyememesi; trigger'ın okuma durumlarını ezmesi; arama yolunun (`search_path`) superuser fonksiyonlarında manipüle edilebilmesi. |
| **Doğrulanamayan Noktalar (Unverified)** | Canlı DB Erişim Yokluğu | Canlı tablolardaki gerçek yabancı anahtar kısıtlarının (`ON DELETE CASCADE`) canlı katalogdaki tam durumu; canlıda çalışmış geçmiş migration tablosu (`supabase_migrations.schema_migrations`). |
| **Bekleyen Kararlar (Pending Operator Decisions)** | Mimari Seçimler | Favori ve okuma durumunun bağımsızlığı (Model A vs Model B). |

---

## 3. ŞEMA VE NESNE UZLAŞTIRMASI (SCHEMA RECONCILIATION)

### 3.1 `user_profiles` Detaylı İncelemesi
- **Canlı Kolonlar:** `id UUID PK REFERENCES auth.users(id)`, `preferred_genres TEXT[]`, `reading_frequency INTEGER`, `onboarding_completed BOOLEAN`, `updated_at TIMESTAMPTZ`.
- **Repo Beklentisi:** `user_id UUID PK`, `preferred_genres TEXT[]`, `reading_frequency INTEGER`, `preferred_authors TEXT[]`, `preferred_vibe TEXT`, `updated_at TIMESTAMPTZ`.
- **Çözüm:** Körlemesine kolon yeniden adlandırma (`RENAME COLUMN id TO user_id`) eski istemcileri kırabileceği için, **Aşamalı Çift-Kolon Uyumluluğu (Staged Compatibility)** uygulanacaktır. `user_id` eklenip mevcut `id` ile doldurulacak, bir senkronizasyon trigger'ı her iki kolonu senkronize tutacaktır. Mevcut tek canlı profil kaydı sıfır kayıpla korunacaktır.

### 3.2 `user_interactions` & `favorites` Çıkmazı
- Canlı CHECK kısıtı: `('like', 'dislike', 'want_to_read', 'finished')`.
- Web kütüphane kodları: `'favorite'`, `'reading'`, `'want_to_read'`, `'finished'`.
- `07_phase3_collections.sql` canlıya uygulanmadığı için Web'den gelen `'favorite'` ve `'reading'` durumları veritabanında `check constraint violation` üretmektedir.
- Ancak CHECK kısıtını genişletmek tek başına yeterli değildir; çünkü `UNIQUE(user_id, book_id)` kısıtı varken kullanıcı aynı anda hem favori hem okuma durumuna sahip olamaz. Bu nedenle Grup 3 migration'ı mimari karar verilene kadar **BLOKE** edilmiştir.

---

## 4. YETKİ VE GÜVENLİK DENETİMİ (PRIVILEGE & RLS AUDIT)

1. **`TRUNCATE` Açığı:** `anon` ve `authenticated` rollerinden tüm tablolarda `TRUNCATE` kaldırılmalıdır. Rollback betiğinde dahi bu yetki geri verilmeyecektir.
2. **Katalog Yazma Açığı:** `books` üzerindeki `python_ekleme_izni` ve `python_guncelleme_izni` politikaları derhal silinmelidir. `anon` rolünden `books` tablosunda INSERT, UPDATE, DELETE geri alınmalı, sadece `SELECT` bırakılmalıdır.
3. **`book_embeddings` İzni:** `match_query_embeddings` fonksiyonu canlıda `SECURITY INVOKER` çalıştığından, çağıran `anon` ve `authenticated` rollerinin `book_embeddings` tablosunda `SELECT` yetkisi korunmalıdır. Tabloya yazma yetkileri geri alınmalıdır.
4. **Kullanıcı Tabloları:** `favorites`, `user_activities`, `user_interactions`, `user_profiles` tablolarından `anon` yazma yetkileri tamamen geri alınmalıdır.

---

## 5. RPC VE VEKTÖR ARAMASI DENETİMİ

1. **`match_query_embeddings`:**
   - Canlıda mevcuttur.
   - Superuser haklarıyla çalıştırılmaması için canlıdaki **`SECURITY INVOKER`** özelliği korunmuştur.
   - `SET search_path = public, pg_temp;` eklenerek arama yolu manipülasyonu kapatılmıştır.
   - `safe_limit <= 100` tavanı konularak bellek şişmesi/DoS riski engellenmiştir.
2. **`match_book_embeddings`:**
   - Canlıda **YOKTUR**.
   - `04_DRAFT_harden_vector_rpcs.sql` ile tanımlanmış olup, canlıya uygulanana kadar hibrit tavsiye motoru sessizce fallback vermeye devam edecektir.

---

## 6. ÖNCELİKLENDİRİLMİŞ AKSİYON LİSTESİ

| No | Seviye | Dosya / Aksiyon | Durum |
|---|:---:|---|:---:|
| **1** | **P0** | `01_DRAFT_revoke_dangerous_privileges.sql` (TRUNCATE & Anon Write Revoke) | **UYGULANABİLİR (HAZIR)** |
| **2** | **P1** | `02_DRAFT_reconcile_user_profiles.sql` (Aşamalı Çift-Kolon Uyumluluğu) | **UYGULANABİLİR (HAZIR)** |
| **3** | **P1** | `03_DRAFT_reconcile_interactions_and_trigger.sql` (Etkileşim & Trigger - Model A) | **UYGULANABİLİR (HAZIR - Model A Onaylandı)** |
| **4** | **P2** | `04_DRAFT_harden_vector_rpcs.sql` (RPC Güçlendirmesi & Eksik match_book_embeddings) | **UYGULANABİLİR (HAZIR)** |
