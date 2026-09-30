-- migration: Optimize vector similarity search RPC
-- Description: Fixes HNSW index usage by removing distance filter from the main query body.

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

  -- 2. Find nearest neighbors to the centroid using HNSW index efficiently
  RETURN QUERY
  SELECT sub.book_id, sub.similarity
  FROM (
    SELECT
      be.book_id,
      1 - (be.embedding <=> centroid) AS similarity
    FROM public.book_embeddings be
    WHERE NOT (be.book_id = ANY(seed_book_ids)) -- Exclude the seeds themselves
    ORDER BY be.embedding <=> centroid
    LIMIT match_count
  ) sub
  WHERE sub.similarity > match_threshold;
END;
$$;
