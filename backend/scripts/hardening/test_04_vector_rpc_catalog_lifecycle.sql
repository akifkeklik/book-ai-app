-- =============================================================================
-- TEST: KATALOG SORGULARIYLA MIGRATION 04 VE ROLLBACK DOĞRULAMA DÖNGÜSÜ
-- =============================================================================
-- Dosya: backend/scripts/hardening/test_04_vector_rpc_catalog_lifecycle.sql
-- Amaç: match_query_embeddings ve match_book_embeddings fonksiyonlarının
--        katalog düzeyindeki tüm özelliklerini doğrulamak:
--        - Fonksiyon imzası ve parametre varsayılanları (pronargdefaults)
--        - Fonksiyon gövdesi ve dili (prosrc, prolproc)
--        - Sahiplik (proowner -> postgres)
--        - SECURITY INVOKER/DEFINER (prosecdef)
--        - search_path ve diğer proconfig ayarları
--        - PUBLIC ve rol bazındaki EXECUTE yetkileri
--        - Bağımlı nesne koruması (CASCADE olmaksızın güvenli başarısızlık)
--
-- Test Akışı:
--   Başlangıç Durumu -> Forward Migration 1 -> Doğrulama 1
--   -> Bağımlılık Güvenlik Testi -> Rollback -> Başlangıç Durumuyla Karşılaştırma
--   -> Forward Migration 2 -> Tekrar Doğrulama 2 (İdempotency)
-- =============================================================================

\set ON_ERROR_STOP on

-- ─────────────────────────────────────────────────────────────────────────────
-- ADIM 0: TEST ORTAMI ROLLERİNİN, TABLOLARININ VE BAŞLANGIÇ (BASELINE) DURUMUNUN KURULUMU
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'vector') THEN
        CREATE EXTENSION IF NOT EXISTS vector;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
        CREATE ROLE anon;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
        CREATE ROLE authenticated;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
        CREATE ROLE service_role;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'postgres') THEN
        CREATE ROLE postgres SUPERUSER;
    END IF;

    -- book_embeddings tablosunun mevcudiyetini garantiye al
    CREATE TABLE IF NOT EXISTS public.book_embeddings (
        id BIGSERIAL PRIMARY KEY,
        book_id TEXT NOT NULL,
        embedding vector(3072)
    );
END $$;

-- 06_phase2_rag.sql tarafından canlıya kurulan orijinal ham baseline fonksiyonu
CREATE OR REPLACE FUNCTION public.match_query_embeddings(
    query_embedding vector(3072),
    match_threshold float,
    match_count int
)
RETURNS TABLE (
    book_id text,
    similarity float
)
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
BEGIN
    RETURN QUERY
    SELECT sub.book_id, sub.similarity
    FROM (
        SELECT
            be.book_id,
            1 - ((be.embedding::halfvec(3072)) <=> (query_embedding::halfvec(3072))) AS similarity
        FROM public.book_embeddings be
        ORDER BY (be.embedding::halfvec(3072)) <=> (query_embedding::halfvec(3072))
        LIMIT match_count
    ) sub
    WHERE sub.similarity > match_threshold;
END;
$$;

ALTER FUNCTION public.match_query_embeddings(vector, double precision, integer) OWNER TO postgres;
GRANT EXECUTE ON FUNCTION public.match_query_embeddings(vector, double precision, integer) TO PUBLIC, anon, authenticated, service_role;

-- Canlı Supabase'de başlangıçta match_book_embeddings bulunmadığını garantiye al
DROP FUNCTION IF EXISTS public.match_book_embeddings(text[], double precision, integer);


-- ─────────────────────────────────────────────────────────────────────────────
-- ADIM 1: BAŞLANGIÇ (BASELINE) KATALOG DURUMU DOĞRULAMASI
-- (06_phase2_rag.sql tarafından oluşturulan ham durum)
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
    p_rec RECORD;
BEGIN
    SELECT p.oid, p.proname, p.prosecdef, p.proconfig, p.pronargdefaults
    INTO p_rec
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'match_query_embeddings';

    IF p_rec.oid IS NULL THEN
        RAISE EXCEPTION 'TEST BAŞARISIZ (Adım 1): match_query_embeddings fonksiyonu başlangıç durumunda bulunamadı!';
    END IF;

    -- Başlangıçta SECURITY INVOKER olmalı
    IF p_rec.prosecdef != false THEN
        RAISE EXCEPTION 'TEST BAŞARISIZ (Adım 1): Başlangıçta match_query_embeddings SECURITY DEFINER olamaz!';
    END IF;

    -- Başlangıçta proconfig (search_path) NULL olmalı
    IF p_rec.proconfig IS NOT NULL THEN
        RAISE EXCEPTION 'TEST BAŞARISIZ (Adım 1): Başlangıçta match_query_embeddings proconfig tanımlı olmamalı (Bulunan: %)', p_rec.proconfig;
    END IF;

    -- Başlangıçta parametre varsayılanları olmamalı
    IF p_rec.pronargdefaults != 0 THEN
        RAISE EXCEPTION 'TEST BAŞARISIZ (Adım 1): Başlangıçta parametre varsayılanları 0 olmalı (Bulunan: %)', p_rec.pronargdefaults;
    END IF;

    -- Başlangıçta PUBLIC çalıştırma iznine sahip olmalı
    IF NOT has_function_privilege('public', p_rec.oid, 'EXECUTE') THEN
        RAISE EXCEPTION 'TEST BAŞARISIZ (Adım 1): Başlangıçta PUBLIC rolünün EXECUTE izni olmalı!';
    END IF;

    -- Başlangıçta match_book_embeddings fonksiyonu canlıda olduğu gibi OLMAMALI
    IF EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname = 'match_book_embeddings'
    ) THEN
        RAISE EXCEPTION 'TEST BAŞARISIZ (Adım 1): match_book_embeddings başlangıç durumunda mevcut olmamalı!';
    END IF;

    RAISE NOTICE '>> ADIM 1 BAŞARILI: Başlangıç katalog durumu doğrulandı (INVOKER, proconfig NULL, no defaults, PUBLIC execute aktif).';
END $$;


-- ─────────────────────────────────────────────────────────────────────────────
-- ADIM 2: FORWARD MIGRATION 1 UYGULAMA (04_DRAFT_harden_vector_rpcs.sql)
-- ─────────────────────────────────────────────────────────────────────────────
\i backend/scripts/hardening/04_DRAFT_harden_vector_rpcs.sql


-- ─────────────────────────────────────────────────────────────────────────────
-- ADIM 3: FORWARD MIGRATION 1 KATALOG DOĞRULAMASI
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
    mq_rec RECORD;
    mb_rec RECORD;
    mq_body TEXT;
    mb_body TEXT;
BEGIN
    -- match_query_embeddings denetimi
    SELECT p.oid, p.prosecdef, p.proconfig, p.pronargdefaults, l.lanname, r.rolname, p.prosrc
    INTO mq_rec
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    JOIN pg_language l ON l.oid = p.prolang
    JOIN pg_roles r ON r.oid = p.proowner
    WHERE n.nspname = 'public' AND p.proname = 'match_query_embeddings';

    IF mq_rec.oid IS NULL THEN
        RAISE EXCEPTION 'TEST BAŞARISIZ (Adım 3): match_query_embeddings forward migration sonrası bulunamadı!';
    END IF;

    IF mq_rec.prosecdef != false THEN
        RAISE EXCEPTION 'TEST BAŞARISIZ (Adım 3): match_query_embeddings SECURITY INVOKER olarak kalmalı!';
    END IF;

    IF mq_rec.proconfig IS NULL OR NOT (mq_rec.proconfig @> ARRAY['search_path=public, pg_temp']) THEN
        RAISE EXCEPTION 'TEST BAŞARISIZ (Adım 3): match_query_embeddings arama yolu search_path=public, pg_temp olmalı! (Bulunan: %)', mq_rec.proconfig;
    END IF;

    IF mq_rec.pronargdefaults != 2 THEN
        RAISE EXCEPTION 'TEST BAŞARISIZ (Adım 3): match_query_embeddings 2 adet varsayılan parametreye sahip olmalı (Bulunan: %)', mq_rec.pronargdefaults;
    END IF;

    IF mq_rec.lanname != 'plpgsql' THEN
        RAISE EXCEPTION 'TEST BAŞARISIZ (Adım 3): match_query_embeddings dili plpgsql olmalı (Bulunan: %)', mq_rec.lanname;
    END IF;

    IF mq_rec.prosrc NOT LIKE '%safe_limit%' THEN
        RAISE EXCEPTION 'TEST BAŞARISIZ (Adım 3): match_query_embeddings gövdesi safe_limit korumasını içermiyor!';
    END IF;

    IF has_function_privilege('public', mq_rec.oid, 'EXECUTE') THEN
        RAISE EXCEPTION 'TEST BAŞARISIZ (Adım 3): PUBLIC rolünden EXECUTE izni geri alınmış olmalı!';
    END IF;

    IF NOT has_function_privilege('anon', mq_rec.oid, 'EXECUTE') OR
       NOT has_function_privilege('authenticated', mq_rec.oid, 'EXECUTE') OR
       NOT has_function_privilege('service_role', mq_rec.oid, 'EXECUTE') THEN
        RAISE EXCEPTION 'TEST BAŞARISIZ (Adım 3): anon, authenticated ve service_role rolleri EXECUTE yetkisine sahip olmalı!';
    END IF;

    -- match_book_embeddings denetimi
    SELECT p.oid, p.prosecdef, p.proconfig, p.pronargdefaults, l.lanname, p.prosrc
    INTO mb_rec
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    JOIN pg_language l ON l.oid = p.prolang
    WHERE n.nspname = 'public' AND p.proname = 'match_book_embeddings';

    IF mb_rec.oid IS NULL THEN
        RAISE EXCEPTION 'TEST BAŞARISIZ (Adım 3): match_book_embeddings forward migration ile oluşturulmalıydı!';
    END IF;

    IF mb_rec.prosecdef != false THEN
        RAISE EXCEPTION 'TEST BAŞARISIZ (Adım 3): match_book_embeddings SECURITY INVOKER olmalı!';
    END IF;

    IF mb_rec.proconfig IS NULL OR NOT (mb_rec.proconfig @> ARRAY['search_path=public, pg_temp']) THEN
        RAISE EXCEPTION 'TEST BAŞARISIZ (Adım 3): match_book_embeddings search_path=public, pg_temp olmalı!';
    END IF;

    IF has_function_privilege('public', mb_rec.oid, 'EXECUTE') THEN
        RAISE EXCEPTION 'TEST BAŞARISIZ (Adım 3): match_book_embeddings için PUBLIC izni kapalı olmalı!';
    END IF;

    IF NOT has_function_privilege('anon', mb_rec.oid, 'EXECUTE') OR
       NOT has_function_privilege('authenticated', mb_rec.oid, 'EXECUTE') OR
       NOT has_function_privilege('service_role', mb_rec.oid, 'EXECUTE') THEN
        RAISE EXCEPTION 'TEST BAŞARISIZ (Adım 3): match_book_embeddings için istemci rolleri yetkilendirilmiş olmalı!';
    END IF;

    RAISE NOTICE '>> ADIM 3 BAŞARILI: Forward migration 1 katalog özellikleri eksiksiz doğrulandı.';
END $$;


-- ─────────────────────────────────────────────────────────────────────────────
-- ADIM 3.1: GÜVENLİ LİMİTLER VE GEÇERSİZ ARGÜMANLAR RUNTIME TESTİ
-- NULL girdi, negatif ve tavan üstü limitlerin güvenle yönetildiğinin teyidi
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
    res_count INTEGER;
BEGIN
    -- 1. match_query_embeddings NULL girdi denetimi (0 satır dönmeli, istisna fırlatmamalı)
    SELECT count(*) INTO res_count FROM public.match_query_embeddings(NULL::vector, 0.0, 50);
    IF res_count != 0 THEN
        RAISE EXCEPTION 'TEST BAŞARISIZ (Adım 3.1): NULL query_embedding 0 satır dönmeliydi (Bulunan: %)', res_count;
    END IF;

    -- 2. match_book_embeddings NULL ve boş dizi denetimi
    SELECT count(*) INTO res_count FROM public.match_book_embeddings(NULL::text[], 0.0, 50);
    IF res_count != 0 THEN
        RAISE EXCEPTION 'TEST BAŞARISIZ (Adım 3.1): NULL seed_book_ids 0 satır dönmeliydi (Bulunan: %)', res_count;
    END IF;

    SELECT count(*) INTO res_count FROM public.match_book_embeddings(ARRAY[]::text[], 0.0, 50);
    IF res_count != 0 THEN
        RAISE EXCEPTION 'TEST BAŞARISIZ (Adım 3.1): Boş seed_book_ids 0 satır dönmeliydi (Bulunan: %)', res_count;
    END IF;

    -- 3. match_book_embeddings bulunamayan kitap tohumu denetimi (Centroid NULL durumu)
    SELECT count(*) INTO res_count FROM public.match_book_embeddings(ARRAY['non_existent_seed_book_xyz'], 0.0, 50);
    IF res_count != 0 THEN
        RAISE EXCEPTION 'TEST BAŞARISIZ (Adım 3.1): Bulunamayan tohum kitap için 0 satır dönmeliydi (Bulunan: %)', res_count;
    END IF;

    RAISE NOTICE '>> ADIM 3.1 BAŞARILI: Geçersiz argümanlar (NULL, boş dizi, eksik tohum) ve güvenli limitler başarıyla doğrulandı.';
END $$;


-- ─────────────────────────────────────────────────────────────────────────────
-- ADIM 4: BAĞIMLILIK KORUMASI VE GÜVENLİ BAŞARISIZLIK (FAIL-SAFE) TESTİ
-- CASCADE kullanılmadığında bağımlı nesne varlığında rollback'in durması
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW public._test_vector_rpc_dependency_view AS
SELECT * FROM public.match_query_embeddings(NULL::vector, 0.0, 1);

DO $$
BEGIN
    BEGIN
        -- Rollback betiğindeki gibi CASCADE OLMADAN drop etmeyi dene
        DROP FUNCTION public.match_query_embeddings(vector, double precision, integer);
        RAISE EXCEPTION 'TEST BAŞARISIZ (Adım 4): Bağımlı nesne varken DROP FUNCTION başarısız olmadı!';
    EXCEPTION
        WHEN dependent_objects_still_exist THEN
            RAISE NOTICE '>> ADIM 4 BAŞARILI: Bağımlı view varken DROP FUNCTION güvenli şekilde başarısız oldu (CASCADE kullanılmadığı kanıtlandı).';
    END;
END $$;

-- Test görünümünü temizle
DROP VIEW public._test_vector_rpc_dependency_view;


-- ─────────────────────────────────────────────────────────────────────────────
-- ADIM 5: ROLLBACK MIGRATION UYGULAMA (04_DRAFT_harden_vector_rpcs_rollback.sql)
-- ─────────────────────────────────────────────────────────────────────────────
\i backend/scripts/hardening/04_DRAFT_harden_vector_rpcs_rollback.sql


-- ─────────────────────────────────────────────────────────────────────────────
-- ADIM 6: POST-ROLLBACK KATALOG DOĞRULAMASI (BAŞLANGIÇ DURUMUYLA KARŞILAŞTIRMA)
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
    mq_rec RECORD;
BEGIN
    -- 1. match_book_embeddings tamamen silinmiş olmalı
    IF EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname = 'match_book_embeddings'
    ) THEN
        RAISE EXCEPTION 'TEST BAŞARISIZ (Adım 6): Rollback sonrası match_book_embeddings tablodan/katalogdan silinmemiş!';
    END IF;

    -- 2. match_query_embeddings katalog özellikleri başlangıç durumuna dönmeli
    SELECT p.oid, p.prosecdef, p.proconfig, p.pronargdefaults, l.lanname, r.rolname, p.prosrc
    INTO mq_rec
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    JOIN pg_language l ON l.oid = p.prolang
    JOIN pg_roles r ON r.oid = p.proowner
    WHERE n.nspname = 'public' AND p.proname = 'match_query_embeddings';

    IF mq_rec.oid IS NULL THEN
        RAISE EXCEPTION 'TEST BAŞARISIZ (Adım 6): Rollback sonrası match_query_embeddings fonksiyonu bulunamadı!';
    END IF;

    -- SECURITY INVOKER korunmalı
    IF mq_rec.prosecdef != false THEN
        RAISE EXCEPTION 'TEST BAŞARISIZ (Adım 6): Rollback sonrası match_query_embeddings SECURITY INVOKER olmalı!';
    END IF;

    -- proconfig (search_path) tamamen temizlenmiş olmalı
    IF mq_rec.proconfig IS NOT NULL THEN
        RAISE EXCEPTION 'TEST BAŞARISIZ (Adım 6): Rollback sonrası match_query_embeddings proconfig temizlenmeliydi (Bulunan: %)', mq_rec.proconfig;
    END IF;

    -- Parametre varsayılanları (DEFAULT 0.0, DEFAULT 50) tamamen temizlenmiş olmalı
    IF mq_rec.pronargdefaults != 0 THEN
        RAISE EXCEPTION 'TEST BAŞARISIZ (Adım 6): Rollback sonrası parametre varsayılanları 0 olmalı (Bulunan: %)', mq_rec.pronargdefaults;
    END IF;

    -- Sahiplik postgres olmalı
    IF mq_rec.rolname != 'postgres' THEN
        RAISE EXCEPTION 'TEST BAŞARISIZ (Adım 6): Fonksiyon sahibi postgres olmalı (Bulunan: %)', mq_rec.rolname;
    END IF;

    -- Gövde orijinal sade haline dönmeli (safe_limit kaldırılmış olmalı)
    IF mq_rec.prosrc LIKE '%safe_limit%' THEN
        RAISE EXCEPTION 'TEST BAŞARISIZ (Adım 6): Rollback sonrası fonksiyon gövdesinde safe_limit kalmamalı!';
    END IF;

    -- PUBLIC çalıştırma yetkisi geri verilmiş olmalı
    IF NOT has_function_privilege('public', mq_rec.oid, 'EXECUTE') THEN
        RAISE EXCEPTION 'TEST BAŞARISIZ (Adım 6): Rollback sonrası PUBLIC rolüne EXECUTE yetkisi geri verilmiş olmalı!';
    END IF;

    IF NOT has_function_privilege('anon', mq_rec.oid, 'EXECUTE') OR
       NOT has_function_privilege('authenticated', mq_rec.oid, 'EXECUTE') OR
       NOT has_function_privilege('service_role', mq_rec.oid, 'EXECUTE') THEN
        RAISE EXCEPTION 'TEST BAŞARISIZ (Adım 6): Rollback sonrası istemci rollerinin EXECUTE yetkisi korunmalı!';
    END IF;

    RAISE NOTICE '>> ADIM 6 BAŞARILI: Post-rollback katalog durumu başlangıç durumuyla birebir eşleşti.';
END $$;


-- ─────────────────────────────────────────────────────────────────────────────
-- ADIM 7: FORWARD MIGRATION 2 UYGULAMA (TEKRAR ÇALIŞTIRMA / İDEMPOTENCY)
-- ─────────────────────────────────────────────────────────────────────────────
\i backend/scripts/hardening/04_DRAFT_harden_vector_rpcs.sql


-- ─────────────────────────────────────────────────────────────────────────────
-- ADIM 8: FORWARD MIGRATION 2 TEKRAR DOĞRULAMA
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
    mq_rec RECORD;
    mb_rec RECORD;
BEGIN
    SELECT p.oid, p.prosecdef, p.proconfig, p.pronargdefaults
    INTO mq_rec
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'match_query_embeddings';

    IF mq_rec.proconfig IS NULL OR NOT (mq_rec.proconfig @> ARRAY['search_path=public, pg_temp']) OR mq_rec.pronargdefaults != 2 THEN
        RAISE EXCEPTION 'TEST BAŞARISIZ (Adım 8): İkinci forward uygulama sonrası match_query_embeddings özellikleri hatalı!';
    END IF;

    IF has_function_privilege('public', mq_rec.oid, 'EXECUTE') THEN
        RAISE EXCEPTION 'TEST BAŞARISIZ (Adım 8): İkinci forward sonrası PUBLIC EXECUTE izni kapalı olmalı!';
    END IF;

    SELECT p.oid, p.prosecdef, p.proconfig
    INTO mb_rec
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'match_book_embeddings';

    IF mb_rec.oid IS NULL OR mb_rec.proconfig IS NULL THEN
        RAISE EXCEPTION 'TEST BAŞARISIZ (Adım 8): İkinci forward sonrası match_book_embeddings eksik veya yapılandırmasız!';
    END IF;

    RAISE NOTICE '>> ADIM 8 BAŞARILI: İkinci forward uygulama katalog doğrulaması başarıyla tamamlandı.';
END $$;

DO $$
BEGIN
    RAISE NOTICE '=============================================================================';
    RAISE NOTICE 'TÜM KATALOG DOĞRULAMA ADIMLARI (BAŞLANGIÇ -> FORWARD -> ROLLBACK -> FORWARD) TAMAMLANDI!';
    RAISE NOTICE '=============================================================================';
END $$;
