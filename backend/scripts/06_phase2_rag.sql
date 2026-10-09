-- migration: RAG Vector Matcher
-- Description: Adds a new RPC for generic semantic search by query embedding

CREATE OR REPLACE FUNCTION match_query_embeddings(
  query_embedding vector(3072),
  match_threshold float,
  match_count int
)
RETURNS TABLE (
  book_id text,
  similarity float
)
LANGUAGE plpgsql
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
