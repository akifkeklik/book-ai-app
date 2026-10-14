-- =============================================================================
-- [DRAFT / NOT FOR IMMEDIATE EXECUTION]
-- ROLLBACK: GRUP 4 VEKTÖR RPC GÜÇLENDİRMESİ GERİ ALMA
-- =============================================================================
-- Dosya: backend/scripts/hardening/04_DRAFT_harden_vector_rpcs_rollback.sql
-- Amaç: 04_DRAFT_harden_vector_rpcs.sql ile yapılan RPC değişikliklerini
--        önceki canlı durumuna geri getirmek.
-- =============================================================================

BEGIN;

-- 1. Canlıda Daha Önce Bulunmayan 'match_book_embeddings' RPC'sini Kaldır
DROP FUNCTION IF EXISTS public.match_book_embeddings(text[], double precision, integer);

-- 2. 'match_query_embeddings' Varsayılan Argümanlarını ve proconfig Ayarını Temizlemek İçin DROP Et
-- DİKKAT: PostgreSQL, CREATE OR REPLACE FUNCTION ile mevcut varsayılan parametrelerin
-- (DEFAULT 0.0, DEFAULT 50) kaldırılmasına izin vermez (ERROR: cannot remove parameter defaults).
-- Ayrıca CREATE OR REPLACE SET cümlesi içermediğinde proconfig (search_path) ayarını silmez.
-- Bu nedenle atomik transaction içinde DROP FUNCTION ardından CREATE FUNCTION stratejisi zorunludur.
-- Not: PostgreSQL'de vector(3072) ile vector aynı temel tip OID'sine sahip olduğundan typmod farkı imza overload'ı yaratmaz.
DROP FUNCTION IF EXISTS public.match_query_embeddings(vector, double precision, integer);

CREATE FUNCTION public.match_query_embeddings(
    query_embedding vector,
    match_threshold double precision,
    match_count integer
)
RETURNS TABLE (
    book_id text,
    similarity double precision
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

-- 3. Fonksiyon Sahipliğini Güvenceye Al (DROP + CREATE sonrası sahiplik sapmasını önle)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'postgres') THEN
        ALTER FUNCTION public.match_query_embeddings(vector, double precision, integer) OWNER TO postgres;
    END IF;
END $$;

-- 4. Canlıdaki Orijinal ACL İzinlerini Geri Yükle
-- (Canlı ACL dökümünde raw_acl dolu olduğundan, DROP sonrası yetkiler açıkça yeniden tesis edilir)
GRANT EXECUTE ON FUNCTION public.match_query_embeddings(vector, double precision, integer) TO PUBLIC, anon, authenticated, service_role;

COMMIT;
