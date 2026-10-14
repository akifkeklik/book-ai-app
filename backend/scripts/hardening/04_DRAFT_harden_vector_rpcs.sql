-- =============================================================================
-- [DRAFT / NOT FOR IMMEDIATE EXECUTION]
-- GRUP 4: VEKTÖR RPC GÜÇLENDİRMESİ VE EKSİK FONKSİYON KURULUMU
-- =============================================================================
-- Dosya: backend/scripts/hardening/04_DRAFT_harden_vector_rpcs.sql
-- Amaç: 
--   1. Canlıdaki 'match_query_embeddings' fonksiyonuna sabit 'search_path = public, pg_temp',
--      ve bellek tüketimini engelleyici girdi tavanı ('match_count' <= 100) eklemek.
--      (Fonksiyon canlıdaki gibi 'SECURITY INVOKER' olarak tutulur; gereksiz superuser
--      yetkisi verilmez).
--   2. Canlıda eksik olduğu kanıtlanan 'match_book_embeddings' RPC'sini (05_phase3_performance.sql)
--      tanımlayarak hibrit öneri motorunun sessizce fallback vermesini çözmek.
--   3. PUBLIC rolünden EXECUTE iznini alıp, sadece 'anon', 'authenticated' ve 'service_role'
--      rollerine açıkça izin vermek.
--
-- DİKKAT: 'match_book_embeddings' canlıda şu anda YOKTUR. Bu taslak betik hazırlanmış
-- olsa dahi, operatör canlıda çalıştırmadan önce fonksiyonun onarıldığı varsayılamaz.
--
-- Ön Koşullar:
--   - 'vector' extension'ının (0.8.0) kurulu olması.
--   - 'public.book_embeddings' tablosunun mevcut ve 'anon'/'authenticated' için SELECT yetkisine sahip olması.
--
-- DDL Transaction Atomikliği: Yüksek (DDL fonksiyon tanımları tek transaction içindedir).
-- Veri Silinme Riski: Düşük (Yalnızca fonksiyon tanımı yapılır, tablo verilerine dokunulmaz).
-- İstemci Çalışma Zamanı Riski: Düşük (Parametre limitleri backend çağrı sınırları içindedir; safe_limit tavanı 100 olarak belirlenmiştir).
-- =============================================================================

BEGIN;

-- 1. ÖN KOŞUL KONTROLÜ (FAIL-CLOSED)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'vector') THEN
        RAISE EXCEPTION 'Ön koşul başarısız: vector extension kurulu değil!';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name = 'book_embeddings'
    ) THEN
        RAISE EXCEPTION 'Ön koşul başarısız: public.book_embeddings tablosu bulunamadı!';
    END IF;
END $$;


-- 2. `match_query_embeddings` GÜÇLENDİRMESİ (SECURITY INVOKER KORUNUR)
-- Superuser yetki yükseltme riskini önlemek için canlıdaki SECURITY INVOKER korunur.
-- Sabit search_path ve girdi doğrulaması eklenir.
CREATE OR REPLACE FUNCTION public.match_query_embeddings(
    query_embedding vector,
    match_threshold double precision DEFAULT 0.0,
    match_count integer DEFAULT 50
)
RETURNS TABLE (
    book_id text,
    similarity double precision
)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
    safe_limit integer;
    safe_threshold double precision;
BEGIN
    -- Girdi Güvenlik Denetimleri
    IF query_embedding IS NULL THEN
        RETURN;
    END IF;

    safe_limit := LEAST(GREATEST(COALESCE(match_count, 10), 1), 100);
    safe_threshold := GREATEST(COALESCE(match_threshold, 0.0), 0.0);

    -- HNSW index operator-compatible sorgu (halfvec(3072) cosine mesafe operatörü <=>)
    -- NOT: İndeks taramasının (index scan) fiilen seçilmesi tablonun boyutuna ve PostgreSQL CBO maliyetlerine
    -- bağlıdır; canlı ortamda EXPLAIN (ANALYZE, BUFFERS) ile doğrulanması gerekir.
    RETURN QUERY
    SELECT sub.book_id, sub.similarity
    FROM (
        SELECT
            be.book_id,
            1 - ((be.embedding::halfvec(3072)) <=> (query_embedding::halfvec(3072))) AS similarity
        FROM public.book_embeddings be
        ORDER BY (be.embedding::halfvec(3072)) <=> (query_embedding::halfvec(3072))
        LIMIT safe_limit
    ) sub
    WHERE sub.similarity > safe_threshold;
END;
$$;


-- 3. CANLIDA EKSİK OLAN `match_book_embeddings` RPC'SİNİN KURULUMU
CREATE OR REPLACE FUNCTION public.match_book_embeddings(
    seed_book_ids text[],
    match_threshold double precision DEFAULT 0.0,
    match_count integer DEFAULT 50
)
RETURNS TABLE (
    book_id text,
    similarity double precision
)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
    centroid vector(3072);
    safe_limit integer;
    safe_threshold double precision;
BEGIN
    -- Girdi Güvenlik Denetimleri
    IF seed_book_ids IS NULL OR array_length(seed_book_ids, 1) = 0 THEN
        RETURN;
    END IF;

    safe_limit := LEAST(GREATEST(COALESCE(match_count, 10), 1), 100);
    safe_threshold := GREATEST(COALESCE(match_threshold, 0.0), 0.0);

    -- 1. Tohum kitapların ağırlık merkezini (centroid) hesapla
    SELECT AVG(be.embedding) INTO centroid
    FROM public.book_embeddings be
    WHERE be.book_id = ANY(seed_book_ids);

    -- Tohum kitapların embedding'i bulunamadıysa boş dön
    IF centroid IS NULL THEN
        RETURN;
    END IF;

    -- 2. Centroid'e en yakın komşuları getir (HNSW index operator-compatible sorgu)
    -- NOT: PostgreSQL sorgu planlayıcısının (CBO) HNSW indeks taraması mı yoksa ardışık tarama (seq scan) mı
    -- seçeceği tablodaki satır sayısına, sayfa maliyetlerine ve istatistiklere bağlıdır.
    -- İndeks kullanımı statik bir garanti olmayıp canlıda EXPLAIN (ANALYZE, BUFFERS) ile doğrulanmalıdır.
    RETURN QUERY
    SELECT sub.book_id, sub.similarity
    FROM (
        SELECT
            be.book_id,
            1 - ((be.embedding::halfvec(3072)) <=> (centroid::halfvec(3072))) AS similarity
        FROM public.book_embeddings be
        WHERE NOT (be.book_id = ANY(seed_book_ids)) -- Tohum kitapları hariç tut
        ORDER BY (be.embedding::halfvec(3072)) <=> (centroid::halfvec(3072))
        LIMIT safe_limit
    ) sub
    WHERE sub.similarity > safe_threshold;
END;
$$;


-- 4. YETKİLENDİRME (PUBLIC yerine açıkça rollere izin verilir)
REVOKE EXECUTE ON FUNCTION public.match_query_embeddings(vector, double precision, integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.match_book_embeddings(text[], double precision, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.match_query_embeddings(vector, double precision, integer) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.match_book_embeddings(text[], double precision, integer) TO anon, authenticated, service_role;


-- 5. DOĞRULAMA (Post-check)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc WHERE proname = 'match_query_embeddings'
    ) OR NOT EXISTS (
        SELECT 1 FROM pg_proc WHERE proname = 'match_book_embeddings'
    ) THEN
        RAISE EXCEPTION 'Uygulama sonrası doğrulama başarısız: Vektör RPC fonksiyonları bulunamadı!';
    END IF;
    RAISE NOTICE 'Doğrulama başarılı: match_query_embeddings ve match_book_embeddings aktif.';
END $$;

COMMIT;
