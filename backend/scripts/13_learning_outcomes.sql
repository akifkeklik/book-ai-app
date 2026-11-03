-- migration: 13_learning_outcomes.sql
-- Description: Creates review_items and review_attempts tables for Learning Outcomes Intelligence with RLS, indexes, and cascade constraints.

CREATE TABLE IF NOT EXISTS public.review_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    concept TEXT NOT NULL,
    question TEXT NOT NULL,
    answer TEXT NOT NULL,
    explanation TEXT DEFAULT '',
    source_type TEXT NOT NULL CHECK (source_type IN ('user_note', 'key_takeaway', 'concept', 'learning_path', 'user_created', 'book')),
    source_id TEXT DEFAULT NULL,
    book_id TEXT DEFAULT NULL,
    path_id TEXT DEFAULT NULL,
    stage INT NOT NULL DEFAULT 1 CHECK (stage >= 1 AND stage <= 5),
    interval_days INT NOT NULL DEFAULT 1,
    next_review_at TIMESTAMPTZ NOT NULL DEFAULT (now() + INTERVAL '1 day'),
    last_reviewed_at TIMESTAMPTZ DEFAULT NULL,
    total_reviews INT NOT NULL DEFAULT 0,
    successful_reviews INT NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'paused', 'archived')),
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE INDEX IF NOT EXISTS idx_review_items_user_due
ON public.review_items (user_id, status, next_review_at);

CREATE INDEX IF NOT EXISTS idx_review_items_user_concept
ON public.review_items (user_id, concept);

CREATE INDEX IF NOT EXISTS idx_review_items_source
ON public.review_items (user_id, source_type, source_id);

CREATE TABLE IF NOT EXISTS public.review_attempts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    item_id UUID NOT NULL REFERENCES public.review_items(id) ON DELETE CASCADE,
    outcome TEXT NOT NULL CHECK (outcome IN ('remembered', 'struggled')),
    response_text TEXT DEFAULT '',
    is_correct BOOLEAN NOT NULL DEFAULT false,
    stage_before INT NOT NULL DEFAULT 1,
    stage_after INT NOT NULL DEFAULT 1,
    reviewed_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE INDEX IF NOT EXISTS idx_review_attempts_user_date
ON public.review_attempts (user_id, reviewed_at DESC);

CREATE INDEX IF NOT EXISTS idx_review_attempts_item
ON public.review_attempts (item_id, reviewed_at DESC);

-- Row Level Security (RLS)
ALTER TABLE public.review_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.review_attempts ENABLE ROW LEVEL SECURITY;

-- Policies for review_items
DROP POLICY IF EXISTS "Users can view their own review items" ON public.review_items;
CREATE POLICY "Users can view their own review items"
ON public.review_items FOR SELECT
USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert their own review items" ON public.review_items;
CREATE POLICY "Users can insert their own review items"
ON public.review_items FOR INSERT
WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update their own review items" ON public.review_items;
CREATE POLICY "Users can update their own review items"
ON public.review_items FOR UPDATE
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete their own review items" ON public.review_items;
CREATE POLICY "Users can delete their own review items"
ON public.review_items FOR DELETE
USING (auth.uid() = user_id);

-- Policies for review_attempts
DROP POLICY IF EXISTS "Users can view their own review attempts" ON public.review_attempts;
CREATE POLICY "Users can view their own review attempts"
ON public.review_attempts FOR SELECT
USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert their own review attempts" ON public.review_attempts;
CREATE POLICY "Users can insert their own review attempts"
ON public.review_attempts FOR INSERT
WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete their own review attempts" ON public.review_attempts;
CREATE POLICY "Users can delete their own review attempts"
ON public.review_attempts FOR DELETE
USING (auth.uid() = user_id);

