-- ==============================================================================
-- 12_knowledge_graph.sql
-- LIBRIS: Personal Knowledge Graph & Evidence-Backed Relationships
--
-- Creates tables, constraints, indexes, and RLS policies for user knowledge graph.
-- ==============================================================================

-- 1. Create knowledge_relationships table
CREATE TABLE IF NOT EXISTS public.knowledge_relationships (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    source_id TEXT NOT NULL,
    source_type TEXT NOT NULL CHECK (source_type IN ('book', 'concept', 'note', 'learning_path')),
    target_id TEXT NOT NULL,
    target_type TEXT NOT NULL CHECK (target_type IN ('book', 'concept', 'note', 'learning_path')),
    relationship_type TEXT NOT NULL,
    source TEXT NOT NULL DEFAULT 'user_explicit' CHECK (source IN ('user_explicit', 'reading_note', 'book_metadata', 'system_inference')),
    evidence_ref TEXT DEFAULT NULL,
    confidence TEXT NOT NULL DEFAULT 'high' CHECK (confidence IN ('high', 'medium', 'suggested')),
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    CONSTRAINT unique_user_relationship UNIQUE (user_id, source_id, target_id, relationship_type)
);

-- 2. Indexes for fast graph queries and account isolation
CREATE INDEX IF NOT EXISTS idx_knowledge_relationships_user_id ON public.knowledge_relationships(user_id);
CREATE INDEX IF NOT EXISTS idx_knowledge_relationships_source ON public.knowledge_relationships(user_id, source_id);
CREATE INDEX IF NOT EXISTS idx_knowledge_relationships_target ON public.knowledge_relationships(user_id, target_id);
CREATE INDEX IF NOT EXISTS idx_knowledge_relationships_rel_type ON public.knowledge_relationships(user_id, relationship_type);
CREATE INDEX IF NOT EXISTS idx_knowledge_relationships_created_at ON public.knowledge_relationships(user_id, created_at DESC);

-- 3. Enable Row Level Security (RLS)
ALTER TABLE public.knowledge_relationships ENABLE ROW LEVEL SECURITY;

-- 4. RLS Policies for knowledge_relationships (strict user isolation)
DROP POLICY IF EXISTS "Users can view their own knowledge relationships" ON public.knowledge_relationships;
CREATE POLICY "Users can view their own knowledge relationships"
    ON public.knowledge_relationships FOR SELECT
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert their own knowledge relationships" ON public.knowledge_relationships;
CREATE POLICY "Users can insert their own knowledge relationships"
    ON public.knowledge_relationships FOR INSERT
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update their own knowledge relationships" ON public.knowledge_relationships;
CREATE POLICY "Users can update their own knowledge relationships"
    ON public.knowledge_relationships FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete their own knowledge relationships" ON public.knowledge_relationships;
CREATE POLICY "Users can delete their own knowledge relationships"
    ON public.knowledge_relationships FOR DELETE
    USING (auth.uid() = user_id);

