-- =============================================================================
-- LIBRIS DATABASE HARDENING & RECONCILIATION — PREFLIGHT READ-ONLY AUDIT
-- =============================================================================
-- DOSYA: backend/scripts/preflight_database_hardening.sql
-- AMAÇ: Canlı Supabase veritabanında şema, yetkiler, RLS, trigger'lar,
--        kısıtlar ve vektör bütünlüğünü sıfır yan etkiyle (READ-ONLY) denetlemek.
-- 
-- ÖNEMLİ KULLANIM TALİMATI:
-- Supabase SQL Editor, çoklu sorgu içeren bir betik tek seferde çalıştırıldığında
-- yalnızca EN SONUNCU SELECT sorgusunun sonucunu ekranda görüntüler.
-- Bu nedenle:
--   - Tek tek detaylı inceleme için aşağıdaki bölümleri SIRAYLA VE AYRI AYRI çalıştırabilirsiniz.
--   - BÖLÜM 12: Tüm sistemik şema, katalog, TRUNCATE ve kısıt sağlık durumunu tek bir tabloda konsolide eder.
--   - KRİTİK UYARI: BÖLÜM 12 tek başına veri denetimi yerine GEÇMEZ. 
--     * Migration 02 canlı geçişi öncesinde, public.user_profiles satır bütünlüğü (yetim kullanıcılar ve kimlik çelişkileri) için
--       SOKU 11.1A ve SOKU 11.1B kapılarının MUTLAKA AYRI VE SIRAYLA çalıştırılması zorunludur!
--     * Migration 03 staging/canlı geçişi öncesinde, user_interactions ve favorites katalog ve veri bütünlüğü,
--       çelişkili like/dislike, yetim kayıtlar ve hacim mutabakatı için SOKU 11.2A ve SOKU 11.2B kapılarının
--       MUTLAKA AYRI VE SIRAYLA çalıştırılması zorunludur!
--
-- KESİN KURAL: Bu betik kesinlikle DDL, DML, GRANT, REVOKE içermez.
--              Sadece SELECT çalıştırır. Geçici tablo oluşturmaz, ayar değiştirmez.
-- =============================================================================


-- ─────────────────────────────────────────────────────────────────────────────
-- SOKU 1 / 11: TABLOLAR, SATIR TAHMİNLERİ VE RLS ETKİNLİK DURUMU
-- AMAÇ: 6 çekirdek tablonun tümünde RLS'in açık olup olmadığını denetlemek.
-- FAIL-CLOSED: Beklenen tablolardan herhangi biri eksikse açıkça 'FAIL: TABLO EKSİK' üretir.
-- ─────────────────────────────────────────────────────────────────────────────
SELECT 
    exp.table_name,
    COALESCE(c.relrowsecurity, false) AS rls_enabled,
    COALESCE(c.relforcerowsecurity, false) AS rls_forced,
    COALESCE(s.n_live_tup, -1) AS estimated_rows,
    CASE 
        WHEN c.relname IS NULL THEN 'FAIL: TABLO EKSİK (TABLE MISSING)'
        WHEN c.relrowsecurity = true THEN 'PASS: RLS Aktif'
        ELSE 'FAIL: RLS KAPALI (ACİL MÜDAHALE GEREKİR)'
    END AS rls_status
FROM (VALUES 
    ('books'), 
    ('book_embeddings'), 
    ('favorites'), 
    ('user_activities'), 
    ('user_interactions'), 
    ('user_profiles')
) AS exp(table_name)
LEFT JOIN (
    SELECT c.relname, c.relrowsecurity, c.relforcerowsecurity, c.oid
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
) c ON c.relname = exp.table_name
LEFT JOIN pg_stat_user_tables s ON s.relid = c.oid
ORDER BY exp.table_name;


-- ─────────────────────────────────────────────────────────────────────────────
-- SOKU 2 / 11: TABLO DÜZEYİ İZİNLER (KATALOG ACL VE ROL DENETİMİ)
-- AMAÇ: PUBLIC sözde rolü (grantee=0), anon, authenticated ve service_role
--       rollerinin izinlerini ve özellikle tehlikeli TRUNCATE yetkisini denetlemek.
-- GÜVENLİK GÜVENCESİ:
--   - PostgreSQL mimarisinde PUBLIC gerçek bir rol olmadığından has_table_privilege fonksiyonuna
--     'public' veya 'PUBLIC' rol argümanı ASLA verilmez (böyle bir çağrı 'role "public" does not exist' hatası verir).
--   - PUBLIC izinleri doğrudan c.relacl ve acldefault('r', c.relowner) üzerinden grantee=0 ile taranır.
--   - anon, authenticated ve service_role için rolün pg_roles'da varlığı doğrulanır ve has_table_privilege
--     ile hem doğrudan hem PUBLIC'ten miras alınan efektif izinler bağımsız raporlanır.
-- ─────────────────────────────────────────────────────────────────────────────
WITH target_tables AS (
    SELECT c.oid, c.relname AS table_name, c.relowner, c.relacl
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname IN ('books', 'book_embeddings', 'favorites', 'user_activities', 'user_interactions', 'user_profiles')
),
audit_entities AS (
    SELECT 'PUBLIC' AS entity_name, 'PSEUDO_ROLE' AS entity_type, 0::oid AS role_oid, true AS role_exists
    UNION ALL
    SELECT r.rolname, 'ROLE', r.oid, true
    FROM pg_roles r
    WHERE r.rolname IN ('anon', 'authenticated', 'service_role')
    UNION ALL
    SELECT missing.rolname, 'ROLE', 0::oid, false
    FROM (VALUES ('anon'), ('authenticated'), ('service_role')) AS missing(rolname)
    WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = missing.rolname)
),
entity_table_privileges AS (
    SELECT 
        tt.table_name,
        ae.entity_name,
        ae.entity_type,
        ae.role_exists,
        -- SELECT
        CASE 
            WHEN NOT ae.role_exists THEN false
            WHEN ae.entity_name = 'PUBLIC' THEN 
                EXISTS (SELECT 1 FROM aclexplode(COALESCE(tt.relacl, acldefault('r', tt.relowner))) a WHERE a.grantee = 0 AND a.privilege_type = 'SELECT')
            ELSE has_table_privilege(ae.entity_name, tt.oid, 'SELECT')
        END AS can_select,
        -- INSERT
        CASE 
            WHEN NOT ae.role_exists THEN false
            WHEN ae.entity_name = 'PUBLIC' THEN 
                EXISTS (SELECT 1 FROM aclexplode(COALESCE(tt.relacl, acldefault('r', tt.relowner))) a WHERE a.grantee = 0 AND a.privilege_type = 'INSERT')
            ELSE has_table_privilege(ae.entity_name, tt.oid, 'INSERT')
        END AS can_insert,
        -- UPDATE
        CASE 
            WHEN NOT ae.role_exists THEN false
            WHEN ae.entity_name = 'PUBLIC' THEN 
                EXISTS (SELECT 1 FROM aclexplode(COALESCE(tt.relacl, acldefault('r', tt.relowner))) a WHERE a.grantee = 0 AND a.privilege_type = 'UPDATE')
            ELSE has_table_privilege(ae.entity_name, tt.oid, 'UPDATE')
        END AS can_update,
        -- DELETE
        CASE 
            WHEN NOT ae.role_exists THEN false
            WHEN ae.entity_name = 'PUBLIC' THEN 
                EXISTS (SELECT 1 FROM aclexplode(COALESCE(tt.relacl, acldefault('r', tt.relowner))) a WHERE a.grantee = 0 AND a.privilege_type = 'DELETE')
            ELSE has_table_privilege(ae.entity_name, tt.oid, 'DELETE')
        END AS can_delete,
        -- TRUNCATE
        CASE 
            WHEN NOT ae.role_exists THEN false
            WHEN ae.entity_name = 'PUBLIC' THEN 
                EXISTS (SELECT 1 FROM aclexplode(COALESCE(tt.relacl, acldefault('r', tt.relowner))) a WHERE a.grantee = 0 AND a.privilege_type = 'TRUNCATE')
            ELSE has_table_privilege(ae.entity_name, tt.oid, 'TRUNCATE')
        END AS can_truncate,
        -- TRUNCATE yetkisi doğrudan PUBLIC hibesinden mi miras alındı?
        CASE 
            WHEN ae.entity_name = 'PUBLIC' THEN false
            ELSE EXISTS (SELECT 1 FROM aclexplode(COALESCE(tt.relacl, acldefault('r', tt.relowner))) a WHERE a.grantee = 0 AND a.privilege_type = 'TRUNCATE')
        END AS truncate_inherited_from_public
    FROM target_tables tt
    CROSS JOIN audit_entities ae
)
SELECT 
    table_name,
    entity_name,
    entity_type,
    role_exists,
    can_select,
    can_insert,
    can_update,
    can_delete,
    can_truncate,
    truncate_inherited_from_public,
    CASE 
        WHEN NOT role_exists THEN 'FAIL: Gerekli Supabase rolü veritabanında bulunamadı!'
        WHEN can_truncate = true AND entity_name IN ('PUBLIC', 'anon', 'authenticated') THEN 
            CASE 
                WHEN truncate_inherited_from_public THEN 'FAIL: P0 - TRUNCATE PUBLIC hibesi üzerinden devralındı (RLS baypas edilebilir)'
                ELSE 'FAIL: P0 - Doğrudan TRUNCATE açık (RLS baypas edilebilir)'
            END
        WHEN entity_name IN ('PUBLIC', 'anon') AND table_name IN ('books', 'book_embeddings') AND (can_insert OR can_update OR can_delete) THEN
            'FAIL: Kitap veya embedding kataloğuna anonim/public yazma izni açık'
        WHEN entity_name = 'authenticated' AND table_name IN ('books', 'book_embeddings') AND (can_insert OR can_update OR can_delete) THEN
            'FAIL: Kitap kataloğuna authenticated yazma izni açık'
        WHEN entity_name = 'authenticated' AND table_name = 'user_activities' AND (can_update OR can_delete) THEN
            'FAIL: Etkinlik log tablosunda update/delete izni açık (İmmutable olmalı)'
        ELSE 'PASS'
    END AS security_verdict
FROM entity_table_privileges
ORDER BY table_name, entity_name;


-- ─────────────────────────────────────────────────────────────────────────────
-- SOKU 2.1 / 11: VARSAYILAN ŞEMA İZİNLERİ (ALTER DEFAULT PRIVILEGES DENETİMİ)
-- AMAÇ: Gelecekte oluşturulacak tablolara TRUNCATE yetkisinin otomatik verilip
--       verilmeyeceğini pg_default_acl kataloğundan doğrulamak.
-- ─────────────────────────────────────────────────────────────────────────────
SELECT 
    rol.rolname AS target_owner,
    COALESCE(n.nspname, 'ALL SCHEMAS') AS schema_name,
    CASE acl.grantee WHEN 0 THEN 'PUBLIC' ELSE COALESCE(gr.rolname, 'UNKNOWN') END AS grantee_name,
    acl.privilege_type,
    CASE 
        WHEN acl.privilege_type = 'TRUNCATE' AND (acl.grantee = 0 OR gr.rolname IN ('anon', 'authenticated', 'public'))
            THEN 'FAIL: Gelecekteki tablolar için TRUNCATE varsayılan izni açık!'
        ELSE 'PASS'
    END AS default_privilege_verdict
FROM pg_default_acl d
JOIN pg_roles rol ON rol.oid = d.defaclrole
LEFT JOIN pg_namespace n ON n.oid = d.defaclnamespace
CROSS JOIN LATERAL aclexplode(d.defaclacl) acl
LEFT JOIN pg_roles gr ON gr.oid = acl.grantee
WHERE d.defaclobjtype = 'r'
  AND (n.nspname = 'public' OR d.defaclnamespace = 0)
  AND acl.privilege_type = 'TRUNCATE';


-- ─────────────────────────────────────────────────────────────────────────────
-- SOKU 3 / 11: MEVCUT RLS POLİTİKALARI VE AÇIK YAZMA KURALLARI
-- AMAÇ: Tablolardaki tüm RLS politikalarını ve books tablosundaki anonim yazma
--       izinlerini tespit etmek.
-- ─────────────────────────────────────────────────────────────────────────────
SELECT 
    schemaname,
    tablename,
    policyname,
    permissive,
    array_to_string(roles, ', ') AS target_roles,
    cmd,
    qual AS using_expression,
    with_check AS with_check_expression,
    CASE 
        WHEN tablename = 'books' AND cmd IN ('INSERT', 'UPDATE', 'ALL') AND (roles @> '{anon}'::name[] OR roles @> '{public}'::name[])
            THEN 'FAIL: TEHLİKELİ (Kitap kataloğuna anonim yazma izni açık)'
        ELSE 'INFO: Politika mevcut'
    END AS policy_safety_check
FROM pg_policies
WHERE schemaname = 'public'
ORDER BY tablename, policyname;


-- ─────────────────────────────────────────────────────────────────────────────
-- SOKU 4 / 11: ŞEMA SÜTUN TANIMLARI VE KRİTİK ALANLAR
-- AMAÇ: Sütun isimlerini, veri tiplerini ve null kurallarını incelemek.
-- KRİTİK: user_profiles tablosunda 'id' ve 'user_id' kolonlarının mevcudiyeti.
-- ─────────────────────────────────────────────────────────────────────────────
SELECT 
    table_name,
    ordinal_position,
    column_name,
    data_type,
    udt_name,
    is_nullable,
    column_default,
    CASE 
        WHEN table_name = 'user_profiles' AND column_name = 'id' THEN 'INFO: Canlıdaki birincil kimlik kolonu'
        WHEN table_name = 'user_profiles' AND column_name = 'user_id' THEN 'PASS: user_id kolonu mevcut (02_DRAFT uygulanmış)'
        WHEN table_name = 'user_profiles' AND column_name IN ('preferred_authors', 'preferred_vibe') THEN 'PASS: İlgi alanı kolonları mevcut'
        ELSE 'INFO'
    END AS column_role_note
FROM information_schema.columns
WHERE table_schema = 'public' 
  AND table_name IN ('books', 'book_embeddings', 'favorites', 'user_activities', 'user_interactions', 'user_profiles')
ORDER BY table_name, ordinal_position;


-- ─────────────────────────────────────────────────────────────────────────────
-- SOKU 5 / 11: KISITLAR (CONSTRAINTS) VE MÜKERRER KAYIT ANALİZİ
-- AMAÇ: PK, FK, UNIQUE ve CHECK kısıtlarını incelemek.
-- KRİTİK: user_interactions üzerinde UNIQUE(user_id, book_id) varlığı ve CHECK kapsamı.
-- ─────────────────────────────────────────────────────────────────────────────
SELECT 
    c.relname AS table_name,
    con.conname AS constraint_name,
    CASE con.contype
        WHEN 'c' THEN 'CHECK'
        WHEN 'u' THEN 'UNIQUE'
        WHEN 'p' THEN 'PRIMARY KEY'
        WHEN 'f' THEN 'FOREIGN KEY'
        ELSE con.contype::text
    END AS constraint_type,
    pg_get_constraintdef(con.oid) AS constraint_definition,
    CASE 
        WHEN c.relname = 'user_interactions' AND con.contype = 'c' AND pg_get_constraintdef(con.oid) NOT LIKE '%favorite%'
            THEN 'FAIL: CHECK kısıtı dar kapsamlı (Web favorite/reading durumları hata verir)'
        WHEN c.relname = 'user_interactions' AND con.contype = 'u'
            THEN 'PASS: UNIQUE(user_id, book_id) kısıtı aktif'
        ELSE 'INFO'
    END AS audit_note
FROM pg_constraint con
JOIN pg_class c ON c.oid = con.conrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' 
  AND c.relname IN ('books', 'book_embeddings', 'favorites', 'user_activities', 'user_interactions', 'user_profiles')
ORDER BY c.relname, con.contype;


-- ─────────────────────────────────────────────────────────────────────────────
-- SOKU 5.1 / 11: user_interactions MÜKERRER KAYIT (DUPLICATE) VE ÇELİŞKİ DENETİMİ
-- AMAÇ: Migration 03 çalıştırılmadan önce duplicate kayıt sayısını ve like/dislike
--       gibi çözümlenemez çelişkileri belirlemek.
-- ─────────────────────────────────────────────────────────────────────────────
SELECT 
    'user_interactions' AS table_name,
    count(*) AS total_duplicate_pairs,
    COALESCE(sum(dup_rows), 0) AS total_affected_rows,
    CASE 
        WHEN count(*) = 0 THEN 'PASS: Mükerrer kayıt yok, 03_DRAFT doğrudan kısıt ekleyebilir'
        ELSE 'WARNING: Mükerrer kayıtlar tespit edildi! 03_DRAFT güvenli arşivleme yapacaktır'
    END AS duplicate_verdict
FROM (
    SELECT user_id, book_id, count(*) AS dup_rows
    FROM public.user_interactions
    GROUP BY user_id, book_id
    HAVING count(*) > 1
) sub;


-- ─────────────────────────────────────────────────────────────────────────────
-- SOKU 6 / 11: İNDEKSLER (INDEXES)
-- AMAÇ: Tüm indeksleri ve özellikle vektör indeksini (hnsw halfvec) denetlemek.
-- ─────────────────────────────────────────────────────────────────────────────
SELECT 
    tablename,
    indexname,
    indexdef,
    CASE 
        WHEN tablename = 'book_embeddings' AND (indexdef LIKE '%halfvec_cosine_ops%' OR indexdef LIKE '%hnsw%')
            THEN 'PASS: HNSW halfvec vektör indeksi mevcut'
        WHEN tablename = 'user_profiles' AND indexname = 'idx_user_profiles_user_id'
            THEN 'PASS: user_profiles user_id indeks mevcut'
        ELSE 'INFO: Standart indeks'
    END AS index_note
FROM pg_indexes
WHERE schemaname = 'public' 
  AND tablename IN ('books', 'book_embeddings', 'favorites', 'user_activities', 'user_interactions', 'user_profiles')
ORDER BY tablename, indexname;


-- ─────────────────────────────────────────────────────────────────────────────
-- SOKU 7 / 11: TRIGGER VE TETİKLEYİCİ FONKSİYONLAR
-- AMAÇ: Tablolara bağlı trigger'ları ve fonksiyon tanımlarını tespit etmek.
-- ─────────────────────────────────────────────────────────────────────────────
SELECT 
    t.tgname AS trigger_name,
    c.relname AS table_name,
    p.proname AS function_name,
    pg_get_triggerdef(t.oid) AS trigger_definition
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
JOIN pg_proc p ON p.oid = t.tgfoid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' 
  AND c.relname IN ('favorites', 'user_interactions', 'user_profiles')
  AND NOT t.tgisinternal
ORDER BY c.relname, t.tgname;


-- ─────────────────────────────────────────────────────────────────────────────
-- SOKU 8 / 11: PGVECTOR UZANTISI ŞEMASI VE VERSİYONU
-- AMAÇ: pgvector eklentisinin kurulu olduğunu ve versiyonunu doğrulamak.
-- ─────────────────────────────────────────────────────────────────────────────
SELECT 
    exp.extname AS extension_name,
    e.extversion AS installed_version,
    n.nspname AS extension_schema,
    CASE 
        WHEN e.extname IS NULL THEN 'FAIL: pgvector eklentisi kurulu değil!'
        ELSE 'PASS: pgvector kurulu'
    END AS extension_status
FROM (VALUES ('vector')) AS exp(extname)
LEFT JOIN pg_extension e ON e.extname = exp.extname
LEFT JOIN pg_namespace n ON n.oid = e.extnamespace;


-- ─────────────────────────────────────────────────────────────────────────────
-- SOKU 9 / 11: VEKTÖR RPC FONKSİYONLARI, ARAMA YOLU VE EXECUTE İZİNLERİ
-- AMAÇ: match_query_embeddings ve match_book_embeddings fonksiyonlarının varlığı,
--       search_path güvenlik durumu ve anon/authenticated çalıştırma izinleri.
-- ─────────────────────────────────────────────────────────────────────────────
SELECT 
    exp.function_name,
    p.oid IS NOT NULL AS function_exists,
    pg_get_function_identity_arguments(p.oid) AS arguments,
    pg_get_function_result(p.oid) AS return_type,
    rol.rolname AS owner,
    p.prosecdef AS is_security_definer,
    p.proconfig AS configuration_settings,
    CASE WHEN p.oid IS NOT NULL AND EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN has_function_privilege('anon', p.oid, 'EXECUTE') ELSE false END AS anon_can_execute,
    CASE WHEN p.oid IS NOT NULL AND EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN has_function_privilege('authenticated', p.oid, 'EXECUTE') ELSE false END AS authenticated_can_execute,
    CASE WHEN p.oid IS NOT NULL AND EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN has_function_privilege('service_role', p.oid, 'EXECUTE') ELSE false END AS service_role_can_execute,
    CASE 
        WHEN p.oid IS NULL AND exp.function_name = 'match_book_embeddings' THEN 'EXPECTED_WARNING: Canlıda henüz mevcut değil (04_DRAFT ile eklenecektir)'
        WHEN p.oid IS NULL THEN 'FAIL: Fonksiyon bulunamadı'
        WHEN p.proconfig IS NULL THEN 'WARNING: search_path tanımsız (Search path hijacking riski, 04 ile düzeltilecek)'
        ELSE 'PASS: Fonksiyon tanımlı ve search_path yapılandırılmış'
    END AS rpc_status
FROM (VALUES ('match_query_embeddings'), ('match_book_embeddings')) AS exp(function_name)
LEFT JOIN (
    SELECT p.oid, p.proname, p.pronamespace, p.proowner, p.prosecdef, p.proconfig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
) p ON p.proname = exp.function_name
LEFT JOIN pg_roles rol ON rol.oid = p.proowner
ORDER BY exp.function_name;


-- ─────────────────────────────────────────────────────────────────────────────
-- SOKU 10 / 11: KİTAP VE EMBEDDING SAYILARI, YETİM KAYITLAR
-- AMAÇ: Kitap kataloğu ile embedding tablosu arasındaki veri bütünlüğü.
-- ─────────────────────────────────────────────────────────────────────────────
SELECT 
    (SELECT count(*) FROM public.books) AS total_books,
    (SELECT count(*) FROM public.book_embeddings) AS total_embeddings,
    (SELECT count(*) FROM public.books b WHERE NOT EXISTS (
        SELECT 1 FROM public.book_embeddings be WHERE be.book_id = b.isbn13
    )) AS books_without_embeddings,
    (SELECT count(*) FROM public.book_embeddings be WHERE NOT EXISTS (
        SELECT 1 FROM public.books b WHERE b.isbn13 = be.book_id
    )) AS orphaned_embeddings;


-- ─────────────────────────────────────────────────────────────────────────────
-- SOKU 11 / 11: KULLANICI PROFİLLERİ, ETKİLEŞİMLER VE FAVORİLER VERİ SAYIMI
-- AMAÇ: Canlıdaki tek user_profiles kaydını, favorites sayısını ve etkileşim türlerini
--       doğrulamak.
-- ─────────────────────────────────────────────────────────────────────────────
SELECT 
    'user_profiles'::text AS table_name,
    count(*)::bigint AS total_rows,
    count(DISTINCT id)::bigint AS distinct_keys,
    'Canlıdaki tek profilin korunması gerekiyor'::text AS note
FROM public.user_profiles
UNION ALL
SELECT 
    'favorites'::text AS table_name,
    count(*)::bigint AS total_rows,
    count(DISTINCT id)::bigint AS distinct_keys,
    'Favori kayıtları'::text AS note
FROM public.favorites
UNION ALL
SELECT 
    'user_interactions'::text AS table_name,
    count(*)::bigint AS total_rows,
    count(DISTINCT id)::bigint AS distinct_keys,
    'Toplam etkileşim satırı'::text AS note
FROM public.user_interactions;


-- ─────────────────────────────────────────────────────────────────────────────
-- SOKU 11.1A / 11: MIGRATION 02 ÖN KOŞUL VE KATALOG DENETİMİ (CATALOG PRE-CHECK GATE)
-- AMAÇ: public.user_profiles veya auth.users yokken veya erişilemezken parse hatasına
--       düşmeden doğrudan anlaşılır FAIL ve genel NO-GO sonucu üretmek.
-- GÜVENLİK GÜVENCESİ:
--   - Yalnızca sistem katalogları (pg_class, information_schema, pg_roles) taranır.
--   - Tablolara doğrudan FROM referansı vermez, bu sayede tablo yokken bile asla çökmez.
--   - auth.users erişim iznini yetim kayıt aramasından tamamen bağımsız olarak test eder.
--   - Tek bir BLOCKER/FAIL durumunda genel karar kesinlikle NO-GO olur.
-- ─────────────────────────────────────────────────────────────────────────────
WITH checks AS (
    SELECT 
        '1. USER_PROFILES_TABLE_EXISTS'::text AS check_name,
        COALESCE((to_regclass('public.user_profiles') IS NOT NULL)::text, 'false') AS actual_value,
        CASE 
            WHEN to_regclass('public.user_profiles') IS NULL THEN 'FAIL: BLOCKER - public.user_profiles tablosu bulunamadı!'
            ELSE 'PASS: user_profiles tablosu mevcut'
        END::text AS verdict

    UNION ALL

    SELECT 
        '2. AUTH_USERS_TABLE_EXISTS'::text,
        COALESCE((to_regclass('auth.users') IS NOT NULL)::text, 'false'),
        CASE 
            WHEN to_regclass('auth.users') IS NULL THEN 'FAIL: BLOCKER - auth.users tablosu bulunamadı!'
            ELSE 'PASS: auth.users tablosu mevcut'
        END::text

    UNION ALL

    SELECT 
        '2.1. AUTH_USERS_ACCESS_PERMISSION'::text,
        CASE 
            WHEN to_regclass('auth.users') IS NULL THEN 'TABLO_YOK'
            ELSE COALESCE(has_table_privilege(current_user, to_regclass('auth.users'), 'SELECT')::text, 'false')
        END,
        CASE 
            WHEN to_regclass('auth.users') IS NULL THEN 'FAIL: BLOCKER - auth.users tablosu eksik olduğundan erişim doğrulanamadı'
            WHEN has_table_privilege(current_user, to_regclass('auth.users'), 'SELECT') = true THEN 'PASS: auth.users tablosuna okuma yetkisi doğrulandı'
            ELSE 'FAIL: BLOCKER - auth.users tablosuna SELECT okuma izni yok!'
        END::text

    UNION ALL

    SELECT 
        '3. USER_ID_COLUMN_STATUS'::text,
        CASE 
            WHEN to_regclass('public.user_profiles') IS NULL THEN 'TABLO_YOK'
            WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='user_profiles' AND column_name='user_id') THEN 'MEVCUT'
            ELSE 'HENÜZ_EKLENMEMİŞ'
        END,
        CASE 
            WHEN to_regclass('public.user_profiles') IS NULL THEN 'FAIL: BLOCKER - public.user_profiles tablosu eksik'
            WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='user_profiles' AND column_name='user_id') THEN 'INFO: user_id kolonu mevcut'
            ELSE 'EXPECTED_PREFLIGHT: user_id kolonu henüz yok (02_DRAFT ile güvenle eklenecektir)'
        END::text

    UNION ALL

    SELECT 
        '4. USER_PROFILES_RLS_STATUS'::text,
        COALESCE((SELECT c.relrowsecurity::text FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relname='user_profiles'), 'TABLO_YOK'),
        CASE 
            WHEN to_regclass('public.user_profiles') IS NULL THEN 'FAIL: BLOCKER - public.user_profiles tablosu eksik'
            WHEN (SELECT c.relrowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relname='user_profiles') = true THEN 'PASS: RLS aktif'
            ELSE 'FAIL: BLOCKER - user_profiles RLS KAPALI!'
        END::text

    UNION ALL

    SELECT 
        '5. CLIENT_TRUNCATE_PERMISSIONS'::text,
        CASE 
            WHEN to_regclass('public.user_profiles') IS NULL THEN 'TABLO_YOK'
            ELSE (
                SELECT count(*)::text 
                FROM pg_class c 
                JOIN pg_namespace n ON n.oid=c.relnamespace 
                WHERE n.nspname='public' AND c.relname='user_profiles'
                  AND (
                      EXISTS (
                          SELECT 1 
                          FROM (VALUES ('anon'), ('authenticated')) AS r(rolname)
                          WHERE EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r.rolname)
                            AND has_table_privilege(r.rolname, c.oid, 'TRUNCATE') = true
                      )
                      OR EXISTS (
                          SELECT 1 
                          FROM aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a 
                          WHERE a.grantee = 0 AND a.privilege_type = 'TRUNCATE'
                      )
                  )
            )
        END,
        CASE 
            WHEN to_regclass('public.user_profiles') IS NULL THEN 'FAIL: BLOCKER - public.user_profiles tablosu eksik'
            WHEN (
                SELECT count(*) 
                FROM pg_class c 
                JOIN pg_namespace n ON n.oid=c.relnamespace 
                WHERE n.nspname='public' AND c.relname='user_profiles'
                  AND (
                      EXISTS (
                          SELECT 1 
                          FROM (VALUES ('anon'), ('authenticated')) AS r(rolname)
                          WHERE EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r.rolname)
                            AND has_table_privilege(r.rolname, c.oid, 'TRUNCATE') = true
                      )
                      OR EXISTS (
                          SELECT 1 
                          FROM aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a 
                          WHERE a.grantee = 0 AND a.privilege_type = 'TRUNCATE'
                      )
                  )
            ) = 0 THEN 'PASS: İstemci rollerinde TRUNCATE yetkisi yok'
            ELSE 'FAIL: P0 - İstemci rollerinde TRUNCATE yetkisi açık!'
        END::text
)
SELECT check_name, actual_value, verdict FROM checks
UNION ALL
SELECT 
    '6. OVERALL_CATALOG_GATE_DECISION'::text,
    (SELECT count(*)::text FROM checks) || ' kontroller denetlendi (' || 
    (SELECT count(*) FILTER (WHERE verdict LIKE 'FAIL%' OR verdict LIKE '%BLOCKER%' OR verdict LIKE '%P0%')::text FROM checks) || ' FAIL, ' ||
    (SELECT count(*) FILTER (WHERE verdict LIKE 'PASS%')::text FROM checks) || ' PASS, ' ||
    (SELECT count(*) FILTER (WHERE verdict LIKE 'EXPECTED%' OR verdict LIKE 'INFO%')::text FROM checks) || ' INFO/EXPECTED)',
    CASE 
        WHEN (SELECT count(*) FROM checks) = 0 
            THEN 'NO-GO: Hiçbir kontrol çalıştırılamadı!'
        WHEN (SELECT count(*) FROM checks WHERE verdict IS NULL) > 0 
            THEN 'NO-GO: Belirsiz veya NULL kontrol durumu (verdict IS NULL) tespit edildi! Migration 02 çalıştırılamaz.'
        WHEN (SELECT count(*) FROM checks WHERE verdict LIKE 'FAIL%' OR verdict LIKE '%BLOCKER%' OR verdict LIKE '%P0%') > 0 
            THEN 'NO-GO: Bloklayıcı katalog/yetki hataları var! Migration 02 çalıştırılamaz.'
        WHEN (SELECT count(*) FROM checks WHERE verdict IS NULL OR (verdict NOT LIKE 'PASS%' AND verdict NOT LIKE 'INFO%' AND verdict NOT LIKE 'EXPECTED%')) > 0 
            THEN 'NO-GO: Bilinmeyen veya geçersiz kontrol durumu tespit edildi! Migration 02 çalıştırılamaz.'
        WHEN (SELECT count(*) FILTER (WHERE verdict LIKE 'PASS%') FROM checks) = 0 
            THEN 'NO-GO: Başarılı (PASS) kabul edilen hiçbir kontrol yok! Migration 02 çalıştırılamaz.'
        ELSE 'GO: Tüm katalog ve yetki ön koşulları başarılı.'
    END::text;


-- ─────────────────────────────────────────────────────────────────────────────
-- SOKU 11.1B / 11: MIGRATION 02 VERİ BÜTÜNLÜĞÜ VE KİMLİK UZLAŞTIRMA DENETİMİ (DATA AUDIT GATE)
-- AMAÇ: public.user_profiles ve auth.users tabloları mevcutken satır düzeyinde
--       yetim kayıtları, id != user_id uyuşmazlıklarını ve NULL kolonları ayrık raporlamak.
-- ÖN KOŞUL: SOKU 11.1A Katalog Kapısı GO vermelidir.
-- ─────────────────────────────────────────────────────────────────────────────
WITH profile_data AS (
    SELECT 
        p.id AS raw_id,
        to_jsonb(p.*)->>'id' AS str_id,
        to_jsonb(p.*)->>'user_id' AS str_user_id
    FROM public.user_profiles p
),
checks AS (
    SELECT 
        '1. PROFILE_ROW_COUNT'::text AS check_name,
        (SELECT count(*)::text FROM profile_data) AS actual_value,
        CASE 
            WHEN (SELECT count(*) FROM profile_data) = 1 THEN 'PASS: Canlıdaki beklenen 1 adet profil kaydı doğrulandı'
            WHEN (SELECT count(*) FROM profile_data) = 0 THEN 'INFO: user_profiles tablosu boş'
            ELSE 'INFO: user_profiles tablosunda ' || (SELECT count(*)::text FROM profile_data) || ' adet kayıt var'
        END::text AS verdict

    UNION ALL

    SELECT 
        '2. ORPHAN_USER_CHECK (auth.users BÜTÜNLÜĞÜ)'::text,
        (SELECT count(*) FILTER (WHERE u.id IS NULL)::text FROM public.user_profiles p LEFT JOIN auth.users u ON u.id = p.id),
        CASE 
            WHEN (SELECT count(*) FILTER (WHERE u.id IS NULL) FROM public.user_profiles p LEFT JOIN auth.users u ON u.id = p.id) = 0 
                THEN 'PASS: Tüm profil id değerleri auth.users ile tam uyumlu (FK eklenebilir)'
            ELSE 'FAIL: BLOCKER - auth.users içinde karşılığı olmayan ' || 
                 (SELECT count(*) FILTER (WHERE u.id IS NULL)::text FROM public.user_profiles p LEFT JOIN auth.users u ON u.id = p.id) || 
                 ' adet yetim profil var! FK ekleme işlemi patlar!'
        END::text

    UNION ALL

    SELECT 
        '3. IDENTITY_MISMATCH_CHECK (id != user_id)'::text,
        CASE 
            WHEN NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='user_profiles' AND column_name='user_id') 
                THEN 'KOLON_HENÜZ_YOK'
            ELSE (
                SELECT 
                    'uyuşmazlık: ' || count(*) FILTER (WHERE (str_user_id IS NOT NULL AND (str_id IS NULL OR str_id <> str_user_id)))::text || 
                    ', null_user_id: ' || count(*) FILTER (WHERE str_user_id IS NULL)::text
                FROM profile_data
            )
        END,
        CASE 
            WHEN NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='user_profiles' AND column_name='user_id') 
                THEN 'EXPECTED_PREFLIGHT: user_id kolonu henüz eklenmemiş (Tekil kimlik id; uyuşmazlık riski yok, backfill 02 ile yapılacak)'
            WHEN (SELECT count(*) FILTER (WHERE (str_user_id IS NOT NULL AND (str_id IS NULL OR str_id <> str_user_id))) FROM profile_data) > 0 
                THEN 'FAIL: BLOCKER - Mevcut satırlarda id ile user_id uyuşmazlığı var (' || 
                     (SELECT count(*) FILTER (WHERE (str_user_id IS NOT NULL AND (str_id IS NULL OR str_id <> str_user_id))) FROM profile_data) || 
                     ' adet)! Migration durdurulur.'
            WHEN (SELECT count(*) FILTER (WHERE str_user_id IS NULL) FROM profile_data) > 0 
                THEN 'INFO: user_id kolonu mevcut ancak ' || 
                     (SELECT count(*) FILTER (WHERE str_user_id IS NULL)::text FROM profile_data) || 
                     ' adet NULL kayıt var (02 backfill uygulayacak)'
            ELSE 'PASS: user_id mevcut ve tüm satırlarda id ile tam senkronize'
        END::text
)
SELECT check_name, actual_value, verdict FROM checks
UNION ALL
SELECT 
    '4. OVERALL_DATA_GATE_DECISION'::text,
    (SELECT count(*)::text FROM checks) || ' veri kontrolleri denetlendi (' || 
    (SELECT count(*) FILTER (WHERE verdict LIKE 'FAIL%' OR verdict LIKE '%BLOCKER%' OR verdict LIKE '%P0%')::text FROM checks) || ' FAIL, ' ||
    (SELECT count(*) FILTER (WHERE verdict LIKE 'PASS%')::text FROM checks) || ' PASS, ' ||
    (SELECT count(*) FILTER (WHERE verdict LIKE 'EXPECTED%' OR verdict LIKE 'INFO%')::text FROM checks) || ' INFO/EXPECTED)',
    CASE 
        WHEN (SELECT count(*) FROM checks) = 0 
            THEN 'NO-GO: Hiçbir veri kontrolü çalıştırılamadı!'
        WHEN (SELECT count(*) FROM checks WHERE verdict IS NULL) > 0 
            THEN 'NO-GO: Belirsiz veya NULL veri kontrol durumu (verdict IS NULL) tespit edildi! Migration 02 çalıştırılamaz.'
        WHEN (SELECT count(*) FROM checks WHERE verdict LIKE 'FAIL%' OR verdict LIKE '%BLOCKER%' OR verdict LIKE '%P0%') > 0 
            THEN 'NO-GO: Bloklayıcı veri bütünlüğü veya yetim kayıt hataları var! Migration 02 çalıştırılamaz.'
        WHEN (SELECT count(*) FROM checks WHERE verdict IS NULL OR (verdict NOT LIKE 'PASS%' AND verdict NOT LIKE 'INFO%' AND verdict NOT LIKE 'EXPECTED%')) > 0 
            THEN 'NO-GO: Bilinmeyen veya geçersiz veri kontrol durumu tespit edildi! Migration 02 çalıştırılamaz.'
        WHEN (SELECT count(*) FILTER (WHERE verdict LIKE 'PASS%') FROM checks) = 0 
            THEN 'NO-GO: Başarılı (PASS) kabul edilen hiçbir veri kontrolü yok! Migration 02 çalıştırılamaz.'
        ELSE 'GO: Veri bütünlüğü ve kimlik uzlaştırması doğrulandı. Migration 02 güvenle uygulanabilir.'
    END::text;


-- ─────────────────────────────────────────────────────────────────────────────
-- SOKU 11.2A / 11: MIGRATION 03 ÖN KOŞUL VE KATALOG DENETİMİ (CATALOG PRE-CHECK GATE)
-- AMAÇ: public.user_interactions, public.favorites, public.books veya auth.users yokken
--       veya erişilemezken parse hatasına düşmeden doğrudan anlaşılır FAIL ve genel NO-GO üretmek.
-- GÜVENLİK GÜVENCESİ:
--   - Yalnızca sistem katalogları (pg_class, information_schema, pg_roles, pg_constraint, pg_trigger) taranır.
--   - Tablolara doğrudan FROM referansı vermez, bu sayede tablo yokken bile asla çökmez.
--   - auth.users ve public.books erişim izinlerini veri sorgularından tamamen bağımsız olarak test eder.
--   - Tek bir BLOCKER/FAIL durumunda genel karar kesinlikle NO-GO olur.
-- ─────────────────────────────────────────────────────────────────────────────
WITH checks_03_catalog AS (
    SELECT 
        '1. USER_INTERACTIONS_TABLE_EXISTS'::text AS check_name,
        COALESCE((to_regclass('public.user_interactions') IS NOT NULL)::text, 'false') AS actual_value,
        CASE 
            WHEN to_regclass('public.user_interactions') IS NULL THEN 'FAIL: BLOCKER - public.user_interactions tablosu bulunamadı!'
            ELSE 'PASS: user_interactions tablosu mevcut'
        END::text AS verdict

    UNION ALL

    SELECT 
        '1.1. USER_INTERACTIONS_COLUMNS_VALID'::text,
        (SELECT count(*)::text FROM information_schema.columns 
         WHERE table_schema = 'public' AND table_name = 'user_interactions' 
           AND column_name IN ('id', 'user_id', 'book_id', 'interaction_type', 'created_at')),
        CASE 
            WHEN to_regclass('public.user_interactions') IS NULL THEN 'FAIL: BLOCKER - user_interactions tablosu eksik'
            WHEN (SELECT count(*) FROM information_schema.columns 
                  WHERE table_schema = 'public' AND table_name = 'user_interactions' 
                    AND column_name IN ('id', 'user_id', 'book_id', 'interaction_type', 'created_at')) = 5 
                THEN 'PASS: user_interactions gerekli 5 çekirdek kolona sahip'
            ELSE 'FAIL: BLOCKER - user_interactions tablosunda beklenen kolonlar eksik!'
        END::text

    UNION ALL

    SELECT 
        '2. FAVORITES_TABLE_EXISTS'::text,
        COALESCE((to_regclass('public.favorites') IS NOT NULL)::text, 'false'),
        CASE 
            WHEN to_regclass('public.favorites') IS NULL THEN 'FAIL: BLOCKER - public.favorites tablosu bulunamadı!'
            ELSE 'PASS: favorites tablosu mevcut'
        END::text

    UNION ALL

    SELECT 
        '2.1. FAVORITES_COLUMNS_VALID'::text,
        (SELECT count(*)::text FROM information_schema.columns 
         WHERE table_schema = 'public' AND table_name = 'favorites' 
           AND column_name IN ('user_id', 'book_id', 'book_title', 'added_at')),
        CASE 
            WHEN to_regclass('public.favorites') IS NULL THEN 'FAIL: BLOCKER - favorites tablosu eksik'
            WHEN (SELECT count(*) FROM information_schema.columns 
                  WHERE table_schema = 'public' AND table_name = 'favorites' 
                    AND column_name IN ('user_id', 'book_id', 'book_title', 'added_at')) >= 4 
                THEN 'PASS: favorites gerekli 4 çekirdek kolona sahip'
            ELSE 'FAIL: BLOCKER - favorites tablosunda beklenen kolonlar eksik!'
        END::text

    UNION ALL

    SELECT 
        '3. BOOKS_TABLE_EXISTS'::text,
        COALESCE((to_regclass('public.books') IS NOT NULL)::text, 'false'),
        CASE 
            WHEN to_regclass('public.books') IS NULL THEN 'FAIL: BLOCKER - public.books tablosu bulunamadı!'
            ELSE 'PASS: books tablosu mevcut'
        END::text

    UNION ALL

    SELECT 
        '3.1. BOOKS_ISBN13_COLUMN_EXISTS'::text,
        CASE 
            WHEN to_regclass('public.books') IS NULL THEN 'TABLO_YOK'
            WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='books' AND column_name='isbn13') THEN 'MEVCUT'
            ELSE 'EKSİK'
        END,
        CASE 
            WHEN to_regclass('public.books') IS NULL THEN 'FAIL: BLOCKER - books tablosu eksik'
            WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='books' AND column_name='isbn13') THEN 'PASS: books.isbn13 kolonu mevcut'
            ELSE 'FAIL: BLOCKER - books.isbn13 kolonu eksik!'
        END::text

    UNION ALL

    SELECT 
        '4. AUTH_USERS_TABLE_EXISTS'::text,
        COALESCE((to_regclass('auth.users') IS NOT NULL)::text, 'false'),
        CASE 
            WHEN to_regclass('auth.users') IS NULL THEN 'FAIL: BLOCKER - auth.users tablosu bulunamadı!'
            ELSE 'PASS: auth.users tablosu mevcut'
        END::text

    UNION ALL

    SELECT 
        '4.1. AUTH_USERS_ACCESS_PERMISSION'::text,
        CASE 
            WHEN to_regclass('auth.users') IS NULL THEN 'TABLO_YOK'
            ELSE COALESCE(has_table_privilege(current_user, to_regclass('auth.users'), 'SELECT')::text, 'false')
        END,
        CASE 
            WHEN to_regclass('auth.users') IS NULL THEN 'FAIL: BLOCKER - auth.users tablosu eksik olduğundan erişim doğrulanamadı'
            WHEN has_table_privilege(current_user, to_regclass('auth.users'), 'SELECT') = true THEN 'PASS: auth.users tablosuna okuma yetkisi doğrulandı'
            ELSE 'FAIL: BLOCKER - auth.users tablosuna SELECT okuma izni yok! (Yetkili kullanıcı veya ek sorgu sözleşmesi gereklidir)'
        END::text

    UNION ALL

    SELECT 
        '5. INTERACTIONS_CHECK_CONSTRAINT_STATUS'::text,
        COALESCE((
            SELECT pg_get_constraintdef(con.oid) 
            FROM pg_constraint con 
            WHERE con.conrelid = to_regclass('public.user_interactions') AND con.contype = 'c'
            LIMIT 1
        ), 'EKSİK')::text,
        CASE 
            WHEN to_regclass('public.user_interactions') IS NULL THEN 'FAIL: BLOCKER - user_interactions tablosu eksik'
            WHEN EXISTS (
                SELECT 1 FROM pg_constraint con 
                WHERE con.conrelid = to_regclass('public.user_interactions') AND con.contype = 'c' AND pg_get_constraintdef(con.oid) LIKE '%favorite%'
            ) THEN 'PASS: Model A 6-Durumlu Kısıt Aktif (Önceden uygulanmış)'
            ELSE 'EXPECTED_PREFLIGHT: Dar kısıt (03_DRAFT ile reading/favorite durumları güvenle eklenecektir)'
        END::text

    UNION ALL

    SELECT 
        '6. LEGACY_TRIGGER_STATUS'::text,
        COALESCE((
            SELECT tgname 
            FROM pg_trigger 
            WHERE tgrelid = to_regclass('public.favorites') AND tgname = 'trg_sync_favorites' AND NOT tgisinternal
            LIMIT 1
        ), 'YOK')::text,
        CASE 
            WHEN EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = to_regclass('public.favorites') AND tgname = 'trg_sync_favorites' AND NOT tgisinternal) 
                THEN 'INFO: trg_sync_favorites mevcut (03_DRAFT ile Model A trigger ile değiştirilecektir)'
            ELSE 'INFO: trg_sync_favorites henüz tanımlı değil (03_DRAFT sıfırdan kuracaktır)'
        END::text
)
SELECT check_name, actual_value, verdict FROM checks_03_catalog
UNION ALL
SELECT 
    '7. OVERALL_MIGRATION_03_CATALOG_GATE_DECISION'::text,
    (SELECT count(*)::text FROM checks_03_catalog) || ' kontroller denetlendi (' || 
    (SELECT count(*) FILTER (WHERE verdict LIKE 'FAIL%' OR verdict LIKE '%BLOCKER%' OR verdict LIKE '%P0%')::text FROM checks_03_catalog) || ' FAIL, ' ||
    (SELECT count(*) FILTER (WHERE verdict LIKE 'PASS%')::text FROM checks_03_catalog) || ' PASS, ' ||
    (SELECT count(*) FILTER (WHERE verdict LIKE 'EXPECTED%' OR verdict LIKE 'INFO%')::text FROM checks_03_catalog) || ' INFO/EXPECTED)',
    CASE 
        WHEN (SELECT count(*) FROM checks_03_catalog) = 0 
            THEN 'NO-GO: Hiçbir katalog kontrolü çalıştırılamadı!'
        WHEN (SELECT count(*) FROM checks_03_catalog) != 10
            THEN 'NO-GO: Beklenen 10 katalog kontrolü yerine ' || (SELECT count(*)::text FROM checks_03_catalog) || ' kontrol çalıştırıldı! Eksik kontrol riski.'
        WHEN (SELECT count(DISTINCT check_name) FROM checks_03_catalog) != 10
            THEN 'NO-GO: Mükerrer veya çakışan katalog kontrol adı tespit edildi! Kontrol bütünlüğü bozulmuş.'
        WHEN (SELECT count(*) FROM checks_03_catalog WHERE verdict IS NULL) > 0 
            THEN 'NO-GO: Belirsiz veya NULL kontrol durumu (verdict IS NULL) tespit edildi! Migration 03 çalıştırılamaz.'
        WHEN (SELECT count(*) FROM checks_03_catalog WHERE verdict LIKE 'FAIL%' OR verdict LIKE '%BLOCKER%' OR verdict LIKE '%P0%') > 0 
            THEN 'NO-GO: Bloklayıcı katalog/ön koşul hataları var! Migration 03 çalıştırılamaz.'
        WHEN (SELECT count(*) FROM checks_03_catalog WHERE verdict IS NULL OR (verdict NOT LIKE 'PASS%' AND verdict NOT LIKE 'INFO%' AND verdict NOT LIKE 'EXPECTED%')) > 0 
            THEN 'NO-GO: Bilinmeyen veya geçersiz katalog kontrol durumu tespit edildi! Migration 03 çalıştırılamaz.'
        WHEN (SELECT count(*) FILTER (
            WHERE check_name IN (
                '1. USER_INTERACTIONS_TABLE_EXISTS',
                '1.1. USER_INTERACTIONS_COLUMNS_VALID',
                '2. FAVORITES_TABLE_EXISTS',
                '2.1. FAVORITES_COLUMNS_VALID',
                '3. BOOKS_TABLE_EXISTS',
                '3.1. BOOKS_ISBN13_COLUMN_EXISTS',
                '4. AUTH_USERS_TABLE_EXISTS',
                '4.1. AUTH_USERS_ACCESS_PERMISSION'
            ) AND verdict LIKE 'PASS%'
        ) FROM checks_03_catalog) != 8
            THEN 'NO-GO: Zorunlu katalog ön koşullarının tamamı (8/8) PASS durumunda değil! Migration 03 çalıştırılamaz.'
        WHEN (SELECT count(*) FILTER (WHERE verdict LIKE 'PASS%') FROM checks_03_catalog) = 0 
            THEN 'NO-GO: Başarılı (PASS) kabul edilen hiçbir katalog kontrolü yok! Migration 03 çalıştırılamaz.'
        ELSE 'GO: Tüm Migration 03 şema ve katalog ön koşulları başarılı.'
    END::text;


-- ─────────────────────────────────────────────────────────────────────────────
-- SOKU 11.2B / 11: MIGRATION 03 VERİ BÜTÜNLÜĞÜ, ÇELİŞKİ VE HACİM MUTABAKATI DENETİMİ (DATA AUDIT GATE)
-- AMAÇ: Migration 03 öncesinde çözümlenemez like/dislike çelişkilerini, duplicate kayıtları,
--       yetim kitap/kullanıcı referanslarını, favorites tablosu bütünlüğünü ve
--       matematiksel net hacim değişimini sıfır yan etkiyle (READ-ONLY SELECT) denetlemek.
-- ÖN KOŞUL: SOKU 11.2A Katalog Kapısı GO vermelidir.
-- EK SÖZLEŞME: Eğer çalıştıran kullanıcının auth.users tablosuna SELECT izni yoksa,
--              SOKU 11.2A 4.1 'FAIL: BLOCKER' verecektir. Bu durumda kullanıcı denetimleri
--              yetkili bir veritabanı yöneticisi tarafından ek sorgu sözleşmesiyle icra edilmelidir.
-- ─────────────────────────────────────────────────────────────────────────────
WITH checks_03_data AS (
    SELECT 
        '1. CONFLICTING_LIKE_DISLIKE_PAIRS'::text AS check_name,
        (SELECT count(*)::text FROM (
            SELECT user_id, book_id
            FROM public.user_interactions
            WHERE interaction_type IN ('like', 'dislike')
            GROUP BY user_id, book_id
            HAVING count(DISTINCT interaction_type) > 1
        ) c) AS actual_value,
        CASE 
            WHEN (SELECT count(*) FROM (
                SELECT user_id, book_id
                FROM public.user_interactions
                WHERE interaction_type IN ('like', 'dislike')
                GROUP BY user_id, book_id
                HAVING count(DISTINCT interaction_type) > 1
            ) c) = 0 THEN 'PASS: Sıfır like/dislike çelişkisi (Kriter: 0 satır)'
            ELSE 'FAIL: BLOCKER - ' || (SELECT count(*)::text FROM (
                SELECT user_id, book_id
                FROM public.user_interactions
                WHERE interaction_type IN ('like', 'dislike')
                GROUP BY user_id, book_id
                HAVING count(DISTINCT interaction_type) > 1
            ) c) || ' adet çözümlenemez like/dislike çelişkisi var! 03_DRAFT fail-closed exception fırlatır.'
        END::text AS verdict

    UNION ALL

    SELECT 
        '2.1. ORPHAN_BOOK_REFERENCES_IN_DUPLICATES'::text,
        (SELECT count(*)::text FROM public.user_interactions ui
         WHERE (ui.user_id, ui.book_id) IN (
             SELECT user_id, book_id FROM public.user_interactions GROUP BY user_id, book_id HAVING count(*) > 1
         )
         AND ui.interaction_type IN ('favorite', 'like')
         AND NOT EXISTS (SELECT 1 FROM public.books b WHERE b.isbn13 = ui.book_id)),
        CASE 
            WHEN (SELECT count(*) FROM public.user_interactions ui
                  WHERE (ui.user_id, ui.book_id) IN (
                      SELECT user_id, book_id FROM public.user_interactions GROUP BY user_id, book_id HAVING count(*) > 1
                  )
                  AND ui.interaction_type IN ('favorite', 'like')
                  AND NOT EXISTS (SELECT 1 FROM public.books b WHERE b.isbn13 = ui.book_id)) = 0 
                THEN 'PASS: Mükerrer favorilerde yetim kitap referansı yok (Kriter: 0 satır)'
            ELSE 'FAIL: BLOCKER - ' || (SELECT count(*)::text FROM public.user_interactions ui
                  WHERE (ui.user_id, ui.book_id) IN (
                      SELECT user_id, book_id FROM public.user_interactions GROUP BY user_id, book_id HAVING count(*) > 1
                  )
                  AND ui.interaction_type IN ('favorite', 'like')
                  AND NOT EXISTS (SELECT 1 FROM public.books b WHERE b.isbn13 = ui.book_id)) || 
                 ' adet yetim kitap referansı var! favorites tablosuna aktarım FK ihlali (23503) fırlatır.'
        END::text

    UNION ALL

    SELECT 
        '2.2. ORPHAN_USER_REFERENCES_IN_DUPLICATES'::text,
        (SELECT count(*)::text FROM public.user_interactions ui
         WHERE (ui.user_id, ui.book_id) IN (
             SELECT user_id, book_id FROM public.user_interactions GROUP BY user_id, book_id HAVING count(*) > 1
         )
         AND ui.interaction_type IN ('favorite', 'like')
         AND NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = ui.user_id)),
        CASE 
            WHEN (SELECT count(*) FROM public.user_interactions ui
                  WHERE (ui.user_id, ui.book_id) IN (
                      SELECT user_id, book_id FROM public.user_interactions GROUP BY user_id, book_id HAVING count(*) > 1
                  )
                  AND ui.interaction_type IN ('favorite', 'like')
                  AND NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = ui.user_id)) = 0 
                THEN 'PASS: Mükerrer favorilerde yetim kullanıcı referansı yok (Kriter: 0 satır)'
            ELSE 'FAIL: BLOCKER - ' || (SELECT count(*)::text FROM public.user_interactions ui
                  WHERE (ui.user_id, ui.book_id) IN (
                      SELECT user_id, book_id FROM public.user_interactions GROUP BY user_id, book_id HAVING count(*) > 1
                  )
                  AND ui.interaction_type IN ('favorite', 'like')
                  AND NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = ui.user_id)) || 
                 ' adet yetim kullanıcı referansı var! favorites tablosuna aktarım FK ihlali (23503) fırlatır.'
        END::text

    UNION ALL

    SELECT 
        '2.3. GENERAL_ORPHAN_INTERACTIONS_CATALOG'::text,
        (SELECT count(*)::text FROM public.user_interactions ui
         WHERE NOT EXISTS (SELECT 1 FROM public.books b WHERE b.isbn13 = ui.book_id)
            OR NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = ui.user_id)),
        CASE 
            WHEN (SELECT count(*) FROM public.user_interactions ui
                  WHERE NOT EXISTS (SELECT 1 FROM public.books b WHERE b.isbn13 = ui.book_id)
                     OR NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = ui.user_id)) = 0 
                THEN 'PASS: Sıfır yetim etkileşim referansı'
            ELSE 'INFO: ' || (SELECT count(*)::text FROM public.user_interactions ui
                  WHERE NOT EXISTS (SELECT 1 FROM public.books b WHERE b.isbn13 = ui.book_id)
                     OR NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = ui.user_id)) || 
                 ' adet etkileşim satırında yetim kitap veya kullanıcı var (Katalog temizliği için denetim bilgisi)'
        END::text

    UNION ALL

    SELECT 
        '3. INVALID_IDENTIFIERS_USER_INTERACTIONS'::text,
        (SELECT count(*)::text FROM public.user_interactions WHERE user_id IS NULL OR book_id IS NULL OR trim(book_id) = ''),
        CASE 
            WHEN (SELECT count(*) FROM public.user_interactions WHERE user_id IS NULL OR book_id IS NULL OR trim(book_id) = '') = 0 
                THEN 'PASS: user_interactions tablosunda geçersiz/NULL kimlik yok (Kriter: 0 satır)'
            ELSE 'INFO: ' || (SELECT count(*)::text FROM public.user_interactions WHERE user_id IS NULL OR book_id IS NULL OR trim(book_id) = '') || 
                 ' adet geçersiz kimlikli satır var (03_DRAFT güvenle arşivleyip tablodan silecektir)'
        END::text

    UNION ALL

    SELECT 
        '4. DUPLICATE_INTERACTION_PAIRS'::text,
        (SELECT 'çift: ' || count(*)::text || ', satır: ' || COALESCE(sum(cnt), 0)::text 
         FROM (
             SELECT user_id, book_id, count(*) AS cnt 
             FROM public.user_interactions 
             WHERE user_id IS NOT NULL AND book_id IS NOT NULL AND trim(book_id) <> ''
             GROUP BY user_id, book_id 
             HAVING count(*) > 1
         ) d),
        CASE 
            WHEN (SELECT count(*) FROM (
                SELECT user_id, book_id 
                FROM public.user_interactions 
                WHERE user_id IS NOT NULL AND book_id IS NOT NULL AND trim(book_id) <> ''
                GROUP BY user_id, book_id 
                HAVING count(*) > 1
            ) d) = 0 THEN 'PASS: user_interactions tablosunda mükerrer kayıt yok (Kriter: 0 çift)'
            ELSE 'INFO: ' || (SELECT count(*)::text FROM (
                SELECT user_id, book_id 
                FROM public.user_interactions 
                WHERE user_id IS NOT NULL AND book_id IS NOT NULL AND trim(book_id) <> ''
                GROUP BY user_id, book_id 
                HAVING count(*) > 1
            ) d) || ' adet mükerrer çift tespit edildi (03_DRAFT kayıpsız arşivleyecektir)'
        END::text

    UNION ALL

    SELECT 
        '5.1. DUPLICATE_FAVORITES'::text,
        (SELECT count(*)::text FROM (
            SELECT user_id, book_id FROM public.favorites GROUP BY user_id, book_id HAVING count(*) > 1
        ) dup_fav),
        CASE 
            WHEN (SELECT count(*) FROM (
                SELECT user_id, book_id FROM public.favorites GROUP BY user_id, book_id HAVING count(*) > 1
            ) dup_fav) = 0 THEN 'PASS: favorites tablosunda mükerrer kayıt yok (Kriter: 0 satır)'
            ELSE 'FAIL: BLOCKER - favorites tablosunda ' || (SELECT count(*)::text FROM (
                SELECT user_id, book_id FROM public.favorites GROUP BY user_id, book_id HAVING count(*) > 1
            ) dup_fav) || ' adet mükerrer çift var!'
        END::text

    UNION ALL

    SELECT 
        '5.2. INVALID_IDENTIFIERS_FAVORITES'::text,
        (SELECT count(*)::text FROM public.favorites WHERE user_id IS NULL OR book_id IS NULL OR trim(book_id) = ''),
        CASE 
            WHEN (SELECT count(*) FROM public.favorites WHERE user_id IS NULL OR book_id IS NULL OR trim(book_id) = '') = 0 
                THEN 'PASS: favorites tablosunda geçersiz/NULL kimlik yok (Kriter: 0 satır)'
            ELSE 'FAIL: BLOCKER - favorites tablosunda ' || (SELECT count(*)::text FROM public.favorites WHERE user_id IS NULL OR book_id IS NULL OR trim(book_id) = '') || ' adet geçersiz kimlik var!'
        END::text

    UNION ALL

    SELECT 
        '5.3. ORPHAN_BOOK_FAVORITES'::text,
        (SELECT count(*)::text FROM public.favorites f WHERE NOT EXISTS (SELECT 1 FROM public.books b WHERE b.isbn13 = f.book_id)),
        CASE 
            WHEN (SELECT count(*) FROM public.favorites f WHERE NOT EXISTS (SELECT 1 FROM public.books b WHERE b.isbn13 = f.book_id)) = 0 
                THEN 'PASS: favorites tablosunda yetim kitap yok (Kriter: 0 satır)'
            ELSE 'FAIL: BLOCKER - favorites tablosunda ' || (SELECT count(*)::text FROM public.favorites f WHERE NOT EXISTS (SELECT 1 FROM public.books b WHERE b.isbn13 = f.book_id)) || ' adet yetim kitap var!'
        END::text

    UNION ALL

    SELECT 
        '5.4. ORPHAN_USER_FAVORITES'::text,
        (SELECT count(*)::text FROM public.favorites f WHERE NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = f.user_id)),
        CASE 
            WHEN (SELECT count(*) FROM public.favorites f WHERE NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = f.user_id)) = 0 
                THEN 'PASS: favorites tablosunda yetim kullanıcı yok (Kriter: 0 satır)'
            ELSE 'FAIL: BLOCKER - favorites tablosunda ' || (SELECT count(*)::text FROM public.favorites f WHERE NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = f.user_id)) || ' adet yetim kullanıcı var!'
        END::text

    UNION ALL

    SELECT 
        '6. MIGRATION_03_VOLUME_SIMULATION'::text,
        (
            WITH null_rows AS (
                SELECT count(*) AS cnt FROM public.user_interactions WHERE user_id IS NULL OR book_id IS NULL OR trim(book_id) = ''
            ),
            dup_stats AS (
                SELECT 
                    count(*) AS dup_pairs,
                    COALESCE(sum(cnt), 0) AS total_dup_rows,
                    COALESCE(sum(cnt - 1), 0) AS rows_to_delete_from_dups
                FROM (
                    SELECT user_id, book_id, count(*) AS cnt 
                    FROM public.user_interactions 
                    WHERE user_id IS NOT NULL AND book_id IS NOT NULL AND trim(book_id) <> ''
                    GROUP BY user_id, book_id 
                    HAVING count(*) > 1
                ) d
            ),
            fav_transfer AS (
                SELECT count(DISTINCT (ui.user_id, ui.book_id)) AS new_favorites_to_insert
                FROM public.user_interactions ui
                WHERE (ui.user_id, ui.book_id) IN (
                    SELECT user_id, book_id FROM public.user_interactions 
                    WHERE user_id IS NOT NULL AND book_id IS NOT NULL AND trim(book_id) <> ''
                    GROUP BY user_id, book_id HAVING count(*) > 1
                )
                AND ui.interaction_type IN ('favorite', 'like')
                AND NOT EXISTS (
                    SELECT 1 FROM public.favorites f WHERE f.user_id = ui.user_id AND f.book_id = ui.book_id
                )
            ),
            backfill_fav AS (
                SELECT count(*) AS fav_to_backfill_count
                FROM public.favorites f
                WHERE NOT EXISTS (
                    SELECT 1 FROM public.user_interactions ui WHERE ui.user_id = f.user_id AND ui.book_id = f.book_id
                )
            ),
            base_counts AS (
                SELECT 
                    (SELECT count(*) FROM public.user_interactions) AS ui_init,
                    (SELECT count(*) FROM public.favorites) AS fav_init
            )
            SELECT 'UI: ' || b.ui_init::text || ' -> ' || (b.ui_init - n.cnt - d.rows_to_delete_from_dups + bf.fav_to_backfill_count)::text || 
                   ' (geçersiz_silinecek: ' || n.cnt::text || 
                   ', mükerrer_snapshot: ' || d.total_dup_rows::text || 
                   ', mükerrer_silinecek: ' || d.rows_to_delete_from_dups::text || 
                   ', favori_backfill: ' || bf.fav_to_backfill_count::text || '); ' ||
                   'FAV: ' || b.fav_init::text || ' -> ' || (b.fav_init + ft.new_favorites_to_insert)::text || 
                   ' (favori_aktarılacak: ' || ft.new_favorites_to_insert::text || '); ' ||
                   'Toplam_Arşivlenecek: ' || (n.cnt + d.total_dup_rows)::text
            FROM null_rows n, dup_stats d, fav_transfer ft, backfill_fav bf, base_counts b
        ),
        (
            WITH null_rows AS (
                SELECT count(*) AS cnt FROM public.user_interactions WHERE user_id IS NULL OR book_id IS NULL OR trim(book_id) = ''
            ),
            dup_stats AS (
                SELECT 
                    count(*) AS dup_pairs,
                    COALESCE(sum(cnt), 0) AS total_dup_rows,
                    COALESCE(sum(cnt - 1), 0) AS rows_to_delete_from_dups
                FROM (
                    SELECT user_id, book_id, count(*) AS cnt 
                    FROM public.user_interactions 
                    WHERE user_id IS NOT NULL AND book_id IS NOT NULL AND trim(book_id) <> ''
                    GROUP BY user_id, book_id 
                    HAVING count(*) > 1
                ) d
            ),
            fav_transfer AS (
                SELECT count(DISTINCT (ui.user_id, ui.book_id)) AS new_favorites_to_insert
                FROM public.user_interactions ui
                WHERE (ui.user_id, ui.book_id) IN (
                    SELECT user_id, book_id FROM public.user_interactions 
                    WHERE user_id IS NOT NULL AND book_id IS NOT NULL AND trim(book_id) <> ''
                    GROUP BY user_id, book_id HAVING count(*) > 1
                )
                AND ui.interaction_type IN ('favorite', 'like')
                AND NOT EXISTS (
                    SELECT 1 FROM public.favorites f WHERE f.user_id = ui.user_id AND f.book_id = ui.book_id
                )
            ),
            backfill_fav AS (
                SELECT count(DISTINCT (f.user_id, f.book_id)) AS fav_to_backfill_count
                FROM public.favorites f
                WHERE NOT EXISTS (
                    SELECT 1 FROM public.user_interactions ui WHERE ui.user_id = f.user_id AND ui.book_id = f.book_id
                )
            ),
            base_counts AS (
                SELECT 
                    (SELECT count(*) FROM public.user_interactions) AS ui_init,
                    (SELECT count(*) FROM public.favorites) AS fav_init
            )
            SELECT 
                CASE 
                    WHEN b.ui_init IS NULL OR b.fav_init IS NULL OR n.cnt IS NULL OR d.rows_to_delete_from_dups IS NULL 
                         OR d.total_dup_rows IS NULL OR ft.new_favorites_to_insert IS NULL OR bf.fav_to_backfill_count IS NULL 
                        THEN 'FAIL: BLOCKER - Hacim simülasyonunda NULL veya tanımsız sayaç tespit edildi!'
                    WHEN (b.ui_init - n.cnt - d.rows_to_delete_from_dups + bf.fav_to_backfill_count) < 0 
                        THEN 'FAIL: BLOCKER - Negatif nihai UI satır sayısı (' || (b.ui_init - n.cnt - d.rows_to_delete_from_dups + bf.fav_to_backfill_count)::text || ') öngörüldü!'
                    WHEN (b.fav_init + ft.new_favorites_to_insert) < b.fav_init 
                        THEN 'FAIL: BLOCKER - Negatif favorites artışı öngörüldü!'
                    WHEN (n.cnt + d.total_dup_rows) < 0 
                        THEN 'FAIL: BLOCKER - Negatif arşiv satır sayısı öngörüldü!'
                    ELSE 'PASS: Matematiksel hacim mutabakatı ve beklenen satır sayıları doğrulandı'
                END::text
            FROM null_rows n, dup_stats d, fav_transfer ft, backfill_fav bf, base_counts b
        )
)
SELECT check_name, actual_value, verdict FROM checks_03_data
UNION ALL
SELECT 
    '7. OVERALL_MIGRATION_03_DATA_GATE_DECISION'::text,
    (SELECT count(*)::text FROM checks_03_data) || ' veri kontrolleri denetlendi (' || 
    (SELECT count(*) FILTER (WHERE verdict LIKE 'FAIL%' OR verdict LIKE '%BLOCKER%' OR verdict LIKE '%P0%')::text FROM checks_03_data) || ' FAIL, ' ||
    (SELECT count(*) FILTER (WHERE verdict LIKE 'PASS%')::text FROM checks_03_data) || ' PASS, ' ||
    (SELECT count(*) FILTER (WHERE verdict LIKE 'EXPECTED%' OR verdict LIKE 'INFO%')::text FROM checks_03_data) || ' INFO/EXPECTED)',
    CASE 
        WHEN (SELECT count(*) FROM checks_03_data) = 0 
            THEN 'NO-GO: Hiçbir veri kontrolü çalıştırılamadı!'
        WHEN (SELECT count(*) FROM checks_03_data) != 11
            THEN 'NO-GO: Beklenen 11 veri bütünlüğü kontrolü yerine ' || (SELECT count(*)::text FROM checks_03_data) || ' kontrol çalıştırıldı! Eksik kontrol riski.'
        WHEN (SELECT count(DISTINCT check_name) FROM checks_03_data) != 11
            THEN 'NO-GO: Mükerrer veya çakışan veri kontrol adı tespit edildi! Kontrol bütünlüğü bozulmuş.'
        WHEN (SELECT count(*) FROM checks_03_data WHERE verdict IS NULL) > 0 
            THEN 'NO-GO: Belirsiz veya NULL veri kontrol durumu (verdict IS NULL) tespit edildi! Migration 03 çalıştırılamaz.'
        WHEN (SELECT count(*) FILTER (WHERE verdict LIKE 'FAIL%' OR verdict LIKE '%BLOCKER%' OR verdict LIKE '%P0%') FROM checks_03_data) > 0 
            THEN 'NO-GO: Bloklayıcı veri bütünlüğü veya çelişki hataları var! Migration 03 çalıştırılamaz.'
        WHEN (SELECT count(*) FROM checks_03_data WHERE verdict IS NULL OR (verdict NOT LIKE 'PASS%' AND verdict NOT LIKE 'INFO%' AND verdict NOT LIKE 'EXPECTED%')) > 0 
            THEN 'NO-GO: Bilinmeyen veya geçersiz veri kontrol durumu tespit edildi! Migration 03 çalıştırılamaz.'
        WHEN (SELECT count(*) FILTER (
            WHERE check_name IN (
                '1. CONFLICTING_LIKE_DISLIKE_PAIRS',
                '2.1. ORPHAN_BOOK_REFERENCES_IN_DUPLICATES',
                '2.2. ORPHAN_USER_REFERENCES_IN_DUPLICATES',
                '5.1. DUPLICATE_FAVORITES',
                '5.2. INVALID_IDENTIFIERS_FAVORITES',
                '5.3. ORPHAN_BOOK_FAVORITES',
                '5.4. ORPHAN_USER_FAVORITES',
                '6. MIGRATION_03_VOLUME_SIMULATION'
            ) AND verdict LIKE 'PASS%'
        ) FROM checks_03_data) != 8
            THEN 'NO-GO: Zorunlu veri bütünlüğü kontrollerinin tamamı (8/8) PASS durumunda değil! Migration 03 çalıştırılamaz.'
        WHEN (SELECT count(*) FILTER (WHERE verdict LIKE 'PASS%') FROM checks_03_data) = 0 
            THEN 'NO-GO: Başarılı (PASS) kabul edilen hiçbir veri kontrolü yok! Migration 03 çalıştırılamaz.'
        ELSE 'GO: Tüm Migration 03 veri bütünlüğü, çelişki ve hacim ön koşulları onaylandı. Migration 03 güvenle uygulanabilir.'
    END::text;


-- ─────────────────────────────────────────────────────────────────────────────
-- BÖLÜM 12: TEK TIKLA ÇALIŞTIRILABİLİR KONSOLİDE PREFLIGHT ÖZET SORGUSU
-- AMAÇ: Supabase SQL Editor'da tek sorgu ile tüm sistemik katalog ve güvenlik kapılarını kontrol etmek.
--       Hiçbir UNION tip uyumsuzluğu içermez, tüm tipler açıkça text'e dökülmüştür.
-- GÜVENCE: Tek bir FAIL durumunda genel karar kesinlikle NO-GO olur.
-- KAPSAM KISITI: Bu sorgu sistemik katalog, TRUNCATE ve kısıt kapısıdır. Migration 02
--   canlı veri bütünlüğü (yetim profiller ve kimlik uzlaştırması) için SOKU 11.1B Data Gate'in
--   çalıştırılması ve GO vermesi ZORUNLUDUR.
-- ─────────────────────────────────────────────────────────────────────────────
WITH consolidated_checks AS (
    SELECT 
        '1. TRUNCATE_LEAKS'::text AS check_name,
        count(*)::text AS actual_value,
        CASE WHEN count(*) = 0 THEN 'PASS: Sıfır TRUNCATE Sızıntısı' ELSE 'FAIL: P0 - TRUNCATE İzni Açık!' END::text AS verdict
    FROM (
        SELECT c.oid, c.relname, c.relowner, c.relacl
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' 
          AND c.relkind = 'r'
          AND c.relname IN ('books', 'book_embeddings', 'favorites', 'user_activities', 'user_interactions', 'user_profiles', 'test_halfvec')
    ) c
    WHERE (
        EXISTS (
            SELECT 1 
            FROM pg_roles r 
            WHERE r.rolname IN ('anon', 'authenticated') 
              AND has_table_privilege(r.rolname, c.oid, 'TRUNCATE') = true
        )
        OR EXISTS (
            SELECT 1 
            FROM aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a 
            WHERE a.grantee = 0 AND a.privilege_type = 'TRUNCATE'
        )
    )

    UNION ALL

    SELECT 
        '1.1. TRUNCATE_DEFAULT_PRIVILEGES_LEAKS'::text AS check_name,
        count(*)::text AS actual_value,
        CASE WHEN count(*) = 0 THEN 'PASS: Sıfır Varsayılan TRUNCATE Sızıntısı' ELSE 'FAIL: P0 - Varsayılan TRUNCATE İzni Açık!' END::text AS verdict
    FROM pg_default_acl d
    JOIN pg_roles rol ON rol.oid = d.defaclrole
    LEFT JOIN pg_namespace n ON n.oid = d.defaclnamespace
    CROSS JOIN LATERAL aclexplode(d.defaclacl) acl
    LEFT JOIN pg_roles gr ON gr.oid = acl.grantee
    WHERE d.defaclobjtype = 'r'
      AND (n.nspname = 'public' OR d.defaclnamespace = 0)
      AND acl.privilege_type = 'TRUNCATE'
      AND (acl.grantee = 0 OR gr.rolname IN ('anon', 'authenticated', 'public'))
      AND rol.rolname IN ('postgres', 'supabase_admin')

    UNION ALL

    SELECT 
        '2. USER_PROFILES_USER_ID_EXISTS'::text,
        CASE 
            WHEN to_regclass('public.user_profiles') IS NULL THEN 'TABLO_YOK'
            WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='user_profiles' AND column_name='user_id') THEN 'MEVCUT'
            ELSE 'HENÜZ_EKLENMEMİŞ'
        END,
        CASE 
            WHEN to_regclass('public.user_profiles') IS NULL THEN 'FAIL: BLOCKER - public.user_profiles tablosu eksik'
            WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='user_profiles' AND column_name='user_id') 
                THEN 'PASS: user_id kolonu mevcut' 
            ELSE 'EXPECTED_PREFLIGHT: user_id eksik (02_DRAFT ile eklenecektir)' 
        END::text

    UNION ALL

    SELECT 
        '2.1. AUTH_USERS_STATUS'::text,
        CASE 
            WHEN to_regclass('auth.users') IS NULL THEN 'TABLO_YOK'
            ELSE COALESCE(has_table_privilege(current_user, to_regclass('auth.users'), 'SELECT')::text, 'false')
        END,
        CASE 
            WHEN to_regclass('auth.users') IS NULL THEN 'FAIL: BLOCKER - auth.users tablosu bulunamadı!'
            WHEN has_table_privilege(current_user, to_regclass('auth.users'), 'SELECT') = true THEN 'PASS: auth.users tablosu mevcut ve erişilebilir'
            ELSE 'FAIL: BLOCKER - auth.users tablosuna SELECT okuma izni yok!'
        END::text

    UNION ALL

    SELECT 
        '2.2. USER_PROFILES_RLS_STATUS'::text,
        COALESCE((SELECT c.relrowsecurity::text FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relname='user_profiles'), 'TABLO_YOK'),
        CASE 
            WHEN to_regclass('public.user_profiles') IS NULL THEN 'FAIL: BLOCKER - public.user_profiles tablosu eksik'
            WHEN (SELECT c.relrowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relname='user_profiles') = true THEN 'PASS: RLS aktif'
            ELSE 'FAIL: BLOCKER - user_profiles RLS KAPALI!'
        END::text

    UNION ALL

    SELECT 
        '3. INTERACTIONS_DUPLICATE_PAIRS'::text,
        COALESCE((
            SELECT count(*)::text 
            FROM (
                SELECT user_id, book_id 
                FROM public.user_interactions 
                GROUP BY user_id, book_id 
                HAVING count(*) > 1
            ) d
        ), 'TABLO_YOK'),
        CASE 
            WHEN to_regclass('public.user_interactions') IS NULL THEN 'FAIL: BLOCKER - user_interactions tablosu eksik'
            WHEN (SELECT count(*) FROM (SELECT user_id, book_id FROM public.user_interactions GROUP BY user_id, book_id HAVING count(*) > 1) d) = 0 
                THEN 'PASS: Mükerrer kayıt yok' 
            ELSE 'WARNING: Mükerrer kayıtlar var (03_DRAFT güvenli arşivleyecektir)' 
        END::text

    UNION ALL

    SELECT 
        '4. INTERACTIONS_CHECK_STATUS'::text,
        COALESCE((
            SELECT pg_get_constraintdef(con.oid) 
            FROM pg_constraint con 
            WHERE con.conrelid = to_regclass('public.user_interactions') AND con.contype = 'c'
            LIMIT 1
        ), 'EKSİK')::text,
        CASE 
            WHEN to_regclass('public.user_interactions') IS NULL THEN 'FAIL: BLOCKER - user_interactions tablosu eksik'
            WHEN EXISTS (
                SELECT 1 FROM pg_constraint con 
                WHERE con.conrelid = to_regclass('public.user_interactions') AND con.contype = 'c' AND pg_get_constraintdef(con.oid) LIKE '%favorite%'
            ) THEN 'PASS: Model A 6-Durumlu Kısıt Aktif'
            ELSE 'EXPECTED_PREFLIGHT: Dar kısıt (03_DRAFT ile reading/favorite eklenecektir)'
        END::text

    UNION ALL

    SELECT 
        '5. VECTOR_RPC_MATCH_BOOK_EMBEDDINGS'::text,
        EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public' AND p.proname = 'match_book_embeddings')::text,
        CASE 
            WHEN EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public' AND p.proname = 'match_book_embeddings')
                THEN 'PASS: RPC Mevcut'
            ELSE 'EXPECTED_PREFLIGHT: Canlıda eksik (04_DRAFT ile kurulacaktır)'
        END::text
)
SELECT check_name, actual_value, verdict FROM consolidated_checks
UNION ALL
SELECT 
    '6. OVERALL_CONSOLIDATED_GATE_DECISION'::text,
    (SELECT count(*)::text FROM consolidated_checks) || ' kontroller denetlendi (' || 
    (SELECT count(*) FILTER (WHERE verdict LIKE 'FAIL%' OR verdict LIKE '%BLOCKER%' OR verdict LIKE '%P0%')::text FROM consolidated_checks) || ' FAIL, ' ||
    (SELECT count(*) FILTER (WHERE verdict LIKE 'PASS%')::text FROM consolidated_checks) || ' PASS, ' ||
    (SELECT count(*) FILTER (WHERE verdict LIKE 'EXPECTED%' OR verdict LIKE 'INFO%' OR verdict LIKE 'WARNING%')::text FROM consolidated_checks) || ' INFO/EXPECTED)',
    CASE 
        WHEN (SELECT count(*) FROM consolidated_checks) = 0 
            THEN 'NO-GO: Hiçbir kontrol çalıştırılamadı!'
        WHEN (SELECT count(*) FROM consolidated_checks WHERE verdict IS NULL) > 0 
            THEN 'NO-GO: Belirsiz veya NULL konsolide kontrol durumu (verdict IS NULL) tespit edildi! Canlı geçiş durduruldu.'
        WHEN (SELECT count(*) FROM consolidated_checks WHERE verdict LIKE 'FAIL%' OR verdict LIKE '%BLOCKER%' OR verdict LIKE '%P0%') > 0 
            THEN 'NO-GO: Bloklayıcı güvenlik/şema/izin hataları tespit edildi! Canlı geçiş durduruldu.'
        WHEN (SELECT count(*) FROM consolidated_checks WHERE verdict IS NULL OR (verdict NOT LIKE 'PASS%' AND verdict NOT LIKE 'INFO%' AND verdict NOT LIKE 'EXPECTED%' AND verdict NOT LIKE 'WARNING%')) > 0 
            THEN 'NO-GO: Bilinmeyen veya geçersiz konsolide kontrol durumu tespit edildi! Canlı geçiş durduruldu.'
        WHEN (SELECT count(*) FILTER (WHERE verdict LIKE 'PASS%') FROM consolidated_checks) = 0 
            THEN 'NO-GO: Başarılı (PASS) kabul edilen hiçbir kontrol yok! Canlı geçiş durduruldu.'
        ELSE 'GO: Tüm sistemik güvenlik ve şema ön koşulları onaylandı.'
    END::text;
