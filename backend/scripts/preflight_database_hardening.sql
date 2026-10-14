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
--   - VEYA dosyanın en sonundaki "BÖLÜM 12: TEK TIKLA ÇALIŞTIRILABİLİR KONSOLİDE ÖZET SORGUSU"nu
--     doğrudan yapıştırarak tüm sistem sağlık durumunu tek bir tabloda görebilirsiniz.
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
-- BÖLÜM 12: TEK TIKLA ÇALIŞTIRILABİLİR KONSOLİDE PREFLIGHT ÖZET SORGUSU
-- AMAÇ: Supabase SQL Editor'da tek sorgu ile tüm kritik kapıları kontrol etmek.
--       Hiçbir UNION tip uyumsuzluğu içermez, tüm tipler açıkça text'e dökülmüştür.
-- ─────────────────────────────────────────────────────────────────────────────
SELECT 
    '1. TRUNCATE_LEAKS'::text AS check_name,
    count(*)::text AS actual_value,
    CASE WHEN count(*) = 0 THEN 'PASS: Sıfır TRUNCATE Sızıntısı' ELSE 'FAIL: P0 - TRUNCATE İzni Açık!' END::text AS verdict
FROM (
    SELECT c.oid, c.relname, c.relowner, c.relacl
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' 
      AND c.relname IN ('books', 'book_embeddings', 'favorites', 'user_activities', 'user_interactions', 'user_profiles')
) c
CROSS JOIN (
    SELECT 'PUBLIC'::text AS entity_name
    UNION ALL
    SELECT r.rolname::text FROM pg_roles r WHERE r.rolname IN ('anon', 'authenticated')
) e
WHERE (
    (e.entity_name = 'PUBLIC' AND EXISTS (SELECT 1 FROM aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) a WHERE a.grantee = 0 AND a.privilege_type = 'TRUNCATE'))
    OR
    (e.entity_name <> 'PUBLIC' AND has_table_privilege(e.entity_name, c.oid, 'TRUNCATE') = true)
)

UNION ALL

SELECT 
    '2. USER_PROFILES_USER_ID_EXISTS'::text,
    EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='user_profiles' AND column_name='user_id')::text,
    CASE 
        WHEN EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='user_profiles' AND column_name='user_id') 
            THEN 'PASS: user_id kolonu mevcut' 
        ELSE 'EXPECTED_PREFLIGHT: user_id eksik (02_DRAFT ile eklenecektir)' 
    END::text

UNION ALL

SELECT 
    '3. INTERACTIONS_DUPLICATE_PAIRS'::text,
    (SELECT count(*)::text FROM (SELECT user_id, book_id FROM public.user_interactions GROUP BY user_id, book_id HAVING count(*) > 1) d),
    CASE 
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
        JOIN pg_class c ON c.oid = con.conrelid 
        WHERE c.relname = 'user_interactions' AND con.contype = 'c'
        LIMIT 1
    ), 'EKSİK')::text,
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM pg_constraint con JOIN pg_class c ON c.oid = con.conrelid 
            WHERE c.relname = 'user_interactions' AND con.contype = 'c' AND pg_get_constraintdef(con.oid) LIKE '%favorite%'
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
    END::text;
