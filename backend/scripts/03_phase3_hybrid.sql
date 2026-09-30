-- migration: RPC for vector similarity search
-- Description: Supports candidate generation for Phase 3.3 Hybrid Recommendation.

CREATE OR REPLACE FUNCTION match_book_embeddings(
  seed_book_ids text[],
  match_threshold float,
  match_count int
)
RETURNS TABLE (
  book_id text,
  similarity float
)
LANGUAGE plpgsql
AS $$
DECLARE
  centroid vector(1536);
BEGIN
  -- 1. Calculate centroid of seed books
  SELECT AVG(embedding) INTO centroid
  FROM public.book_embeddings be
  WHERE be.book_id = ANY(seed_book_ids);

  -- If no valid embeddings found for seeds, return empty
  IF centroid IS NULL THEN
    RETURN;
  END IF;

  -- 2. Find nearest neighbors to the centroid
  RETURN QUERY
  SELECT
    be.book_id,
    1 - (be.embedding <=> centroid) AS similarity
  FROM public.book_embeddings be
  WHERE 1 - (be.embedding <=> centroid) > match_threshold
    AND NOT (be.book_id = ANY(seed_book_ids)) -- Exclude the seeds themselves
  ORDER BY be.embedding <=> centroid
  LIMIT match_count;
END;
$$;
