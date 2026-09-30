-- migration: Enable pgvector and create book_embeddings table
-- Description: Stores book embeddings for Phase 3.2 Hybrid Recommendation.

CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE IF NOT EXISTS public.book_embeddings (
    book_id TEXT PRIMARY KEY REFERENCES public.books(isbn13) ON DELETE CASCADE,
    embedding vector(1536), -- Dimension for text-embedding-3-small
    content_hash TEXT NOT NULL,
    model_version TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Index for HNSW fast search. Using vector_cosine_ops for Cosine Similarity.
-- Note: In production with millions of rows, consider tweaking m and ef_construction.
CREATE INDEX IF NOT EXISTS book_embeddings_embedding_idx ON public.book_embeddings USING hnsw (embedding vector_cosine_ops);

-- Enable Row Level Security (RLS)
ALTER TABLE public.book_embeddings ENABLE ROW LEVEL SECURITY;

-- Allow public/authenticated read access to embeddings
CREATE POLICY "Embeddings are readable by everyone" 
ON public.book_embeddings FOR SELECT 
USING (true);

-- Service role operations bypass RLS by default. No additional policies needed for INSERT/UPDATE by backend.
