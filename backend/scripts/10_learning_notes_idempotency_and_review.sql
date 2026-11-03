-- migration: 10_learning_notes_idempotency_and_review.sql
-- Description: Adds client_id idempotency support to user_notes and introduces note_reviews table for Spaced Repetition (Smart Review).

-- 1. Add client_id for offline-first idempotency and deduplication
ALTER TABLE public.user_notes
ADD COLUMN IF NOT EXISTS client_id TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS uq_user_notes_user_client_id
ON public.user_notes (user_id, client_id)
WHERE client_id IS NOT NULL;

-- 2. Create note_reviews table for Spaced Repetition & Smart Review
CREATE TABLE IF NOT EXISTS public.note_reviews (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    note_id UUID NOT NULL REFERENCES public.user_notes(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    stage INT NOT NULL DEFAULT 1 CHECK (stage >= 1 AND stage <= 4),
    interval_days INT NOT NULL DEFAULT 1,
    next_review_at TIMESTAMPTZ NOT NULL DEFAULT (now() + INTERVAL '1 day'),
    last_reviewed_at TIMESTAMPTZ,
    review_count INT NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'completed', 'paused')),
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    CONSTRAINT uq_note_review_user_note UNIQUE (user_id, note_id)
);

-- Index for querying due reviews efficiently
CREATE INDEX IF NOT EXISTS idx_note_reviews_user_due
ON public.note_reviews (user_id, status, next_review_at);

-- 3. Row Level Security (RLS)
ALTER TABLE public.note_reviews ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view their own note reviews" ON public.note_reviews;
CREATE POLICY "Users can view their own note reviews"
ON public.note_reviews FOR SELECT
USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert their own note reviews" ON public.note_reviews;
CREATE POLICY "Users can insert their own note reviews"
ON public.note_reviews FOR INSERT
WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update their own note reviews" ON public.note_reviews;
CREATE POLICY "Users can update their own note reviews"
ON public.note_reviews FOR UPDATE
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete their own note reviews" ON public.note_reviews;
CREATE POLICY "Users can delete their own note reviews"
ON public.note_reviews FOR DELETE
USING (auth.uid() = user_id);

