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
-- Bu nedenle aşağıdaki bölümleri TÜMÜNÜ BİRDEN DEĞİL, SIRAYLA VE TEK TEK
-- (her bloğu ayrı ayrı kopyalayıp çalıştırarak) çalıştırmanız gerekmektedir.
--
-- KESİN KURAL: Bu betik kesinlikle DDL, DML, GRANT, REVOKE içermez.
--              Sadece SELECT çalıştırır. Geçici tablo oluşturmaz, ayar değiştirmez.
-- =============================================================================


-- ─────────────────────────────────────────────────────────────────────────────
-- SOKU 1 / 11: TABLOLAR, SATIR TAHMİNLERİ VE RLS ETKİNLİK DURUMU
-- AMAÇ: 6 çekirdek tablonun tümünde RLS'in açık olup olmadığını denetlemek.
-- BEKLENTİ: rls_enabled = true ve rls_status = 'PASS: RLS Aktif' olmalıdır.
-- ─────────────────────────────────────────────────────────────────────────────
SELECT 
    c.relname AS table_name,
    c.relrowsecurity AS rls_enabled,
    c.relforcerowsecurity AS rls_forced,
    COALESCE(s.n_live_tup, -1) AS estimated_rows,
    CASE 
        WHEN c.relrowsecurity = true THEN 'PASS: RLS Aktif'
        ELSE 'FAIL: RLS KAPALI (ACİL MÜDAHALE GEREKİR)'
    END AS rls_status
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
LEFT JOIN pg_stat_user_tables s ON s.relid = c.oid
WHERE n.nspname = 'public' 
  AND c.relname IN ('books', 'book_embeddings', 'favorites', 'user_activities', 'user_interactions', 'user_profiles')
ORDER BY c.relname;


-- ─────────────────────────────────────────────────────────────────────────────
-- SOKU 2 / 11: TABLO DÜZEYİ İZİNLER (PUBLIC DAHİL TÜM ROLLER)
-- AMAÇ: public, anon, authenticated ve service_role rollerinin tablo izinlerini
--       ve özellikle tehlikeli TRUNCATE yetkisini denetlemek.
-- KRİTİK: 'anon', 'authenticated' veya 'public' rollerinde can_truncate = true ise
--         RLS tamamen baypas edilebilir (Kritik Güvenlik Açığı).
-- ─────────────────────────────────────────────────────────────────────────────
SELECT 
    t.table_name,
    r.role_name,
    has_table_privilege(r.role_name, 'public.' || t.table_name, 'SELECT') AS can_select,
    has_table_privilege(r.role_name, 'public.' || t.table_name, 'INSERT') AS can_insert,
    has_table_privilege(r.role_name, 'public.' || t.table_name, 'UPDATE') AS can_update,
    has_table_privilege(r.role_name, 'public.' || t.table_name, 'DELETE') AS can_delete,
    has_table_privilege(r.role_name, 'public.' || t.table_name, 'TRUNCATE') AS can_truncate,
    CASE 
        WHEN has_table_privilege(r.role_name, 'public.' || t.table_name, 'TRUNCATE') = true 
            THEN 'FAIL: KRİTİK GÜVENLİK AÇIĞI (TRUNCATE açık, RLS baypas edilebilir)'
        WHEN r.role_name IN ('anon', 'public') AND t.table_name = 'books' AND has_table_privilege(r.role_name, 'public.' || t.table_name, 'INSERT') = true
            THEN 'WARNING: books tablosuna anon/public yazma izni açık'
        ELSE 'PASS'
    END AS security_verdict
FROM (VALUES 
    ('books'), 
    ('book_embeddings'), 
    ('favorites'), 
    ('user_activities'), 
    ('user_interactions'), 
    ('user_profiles')
) AS t(table_name)
CROSS JOIN (
    SELECT role_name
    FROM (VALUES ('public'), ('anon'), ('authenticated'), ('service_role')) AS v(role_name)
    WHERE role_name = 'public' OR EXISTS (SELECT 1 FROM pg_roles WHERE rolname = v.role_name)
) AS r(role_name)
ORDER BY t.table_name, r.role_name;


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
-- SOKU 4 / 11: ŞEMA SÜTUN TANIMLARI VE NULL KURALLARI
-- AMAÇ: Sütun isimlerini ve tiplerini incelemek.
-- KRİTİK: user_profiles tablosunda 'id' mi yoksa 'user_id' mi var?
-- ─────────────────────────────────────────────────────────────────────────────
SELECT 
    table_name,
    ordinal_position,
    column_name,
    data_type,
    udt_name,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_schema = 'public' 
  AND table_name IN ('books', 'book_embeddings', 'favorites', 'user_activities', 'user_interactions', 'user_profiles')
ORDER BY table_name, ordinal_position;


-- ─────────────────────────────────────────────────────────────────────────────
-- SOKU 5 / 11: KISITLAR (CONSTRAINTS), BİRİNCİL/YABANCI ANAHTARLAR VE CHECK
-- AMAÇ: PK, FK, UNIQUE ve CHECK kısıtlarını incelemek.
-- KRİTİK: user_interactions tablosunda CHECK kısıtı hangi türleri kabul ediyor?
--         UNIQUE(user_id, book_id) var mı?
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
            THEN 'INFO: UNIQUE(user_id, book_id) mevcut (Çift etkileşim çatışması riski)'
        ELSE 'PASS'
    END AS audit_note
FROM pg_constraint con
JOIN pg_class c ON c.oid = con.conrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' 
  AND c.relname IN ('books', 'book_embeddings', 'favorites', 'user_activities', 'user_interactions', 'user_profiles')
ORDER BY c.relname, con.contype;


-- ─────────────────────────────────────────────────────────────────────────────
-- SOKU 6 / 11: İNDEKSLER (INDEXES)
-- AMAÇ: Tüm indeksleri ve özellikle vektör indeksini (ivfflat / hnsw) denetlemek.
-- ─────────────────────────────────────────────────────────────────────────────
SELECT 
    tablename,
    indexname,
    indexdef,
    CASE 
        WHEN tablename = 'book_embeddings' AND (indexdef LIKE '%ivfflat%' OR indexdef LIKE '%hnsw%')
            THEN 'PASS: Vektör indeksi mevcut'
        WHEN tablename = 'book_embeddings' AND indexname LIKE '%embedding%'
            THEN 'INFO: Standart embedding indeksi'
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
-- AMAÇ: pgvector eklentisinin hangi şemada (public mi extensions mı?) kurulu olduğunu
--       ve versiyonunu doğrulamak.
-- ─────────────────────────────────────────────────────────────────────────────
SELECT 
    e.extname AS extension_name,
    e.extversion AS installed_version,
    n.nspname AS extension_schema
FROM pg_extension e
JOIN pg_namespace n ON n.oid = e.extnamespace
WHERE e.extname = 'vector';


-- ─────────────────────────────────────────────────────────────────────────────
-- SOKU 9 / 11: VEKTÖR RPC FONKSİYONLARI, ARAMA YOLU VE EXECUTE İZİNLERİ
-- AMAÇ: match_query_embeddings ve match_book_embeddings fonksiyonlarının varlığı,
--       search_path güvenlik durumu ve anon/authenticated çalıştırma izinleri.
-- ─────────────────────────────────────────────────────────────────────────────
SELECT 
    p.proname AS function_name,
    pg_get_function_identity_arguments(p.oid) AS arguments,
    pg_get_function_result(p.oid) AS return_type,
    rol.rolname AS owner,
    p.prosecdef AS is_security_definer,
    p.proconfig AS configuration_settings,
    CASE WHEN EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN has_function_privilege('anon', p.oid, 'EXECUTE') ELSE false END AS anon_can_execute,
    CASE WHEN EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN has_function_privilege('authenticated', p.oid, 'EXECUTE') ELSE false END AS authenticated_can_execute,
    CASE WHEN EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN has_function_privilege('service_role', p.oid, 'EXECUTE') ELSE false END AS service_role_can_execute,
    CASE 
        WHEN p.proconfig IS NULL THEN 'WARNING: search_path tanımsız (Search path hijacking riski)'
        ELSE 'PASS: search_path yapılandırılmış'
    END AS search_path_safety
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
JOIN pg_roles rol ON rol.oid = p.proowner
WHERE n.nspname = 'public' 
  AND p.proname IN ('match_query_embeddings', 'match_book_embeddings')
ORDER BY p.proname;


-- ─────────────────────────────────────────────────────────────────────────────
-- SOKU 10 / 11: KİTAP VE EMBEDDING SAYILARI, YETİM KAYITLAR VE BOYUT ANALİZİ
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

-- (Not: Embedding boyut ve model sürüm detayını görmek için 10. sorgudan hemen sonra
-- aşağıdaki alt sorguyu çalıştırabilirsiniz):
SELECT 
    vector_dims(embedding) AS embedding_dimension,
    model_version,
    count(*) AS record_count,
    count(*) FILTER (WHERE embedding IS NULL) AS null_embeddings,
    count(*) FILTER (WHERE content_hash IS NULL OR content_hash = '') AS empty_hashes
FROM public.book_embeddings
GROUP BY vector_dims(embedding), model_version;


-- ─────────────────────────────────────────────────────────────────────────────
-- SOKU 11 / 11: KULLANICI PROFİLLERİ, ETKİLEŞİMLER VE FAVORİLER VERİ SAYIMI
-- AMAÇ: Canlıdaki tek user_profiles kaydını, favorites sayısını ve interaction türlerini
--       doğrulamak.
-- ─────────────────────────────────────────────────────────────────────────────
SELECT 
    'user_profiles' AS table_name,
    count(*) AS total_rows,
    count(DISTINCT id) AS distinct_keys,
    'Canlıdaki tek profilin korunması gerekiyor' AS note
FROM public.user_profiles
UNION ALL
SELECT 
    'favorites' AS table_name,
    count(*) AS total_rows,
    count(DISTINCT id) AS distinct_keys,
    'Favori kayıtları' AS note
FROM public.favorites
UNION ALL
SELECT 
    'user_interactions' AS table_name,
    count(*) AS total_rows,
    count(DISTINCT id) AS distinct_keys,
    'Toplam etkileşim satırı' AS note
FROM public.user_interactions;
