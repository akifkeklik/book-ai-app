-- migration: Add user_interactions table for feedback loop
-- Description: Stores user likes/dislikes to influence the recommendation engine.

CREATE TABLE IF NOT EXISTS public.user_interactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    book_id TEXT NOT NULL, -- references isbn13 from books table
    interaction_type TEXT NOT NULL CHECK (interaction_type IN ('like', 'dislike')),
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Index for fast lookup of a user's interactions
CREATE INDEX IF NOT EXISTS idx_user_interactions_user_id ON public.user_interactions(user_id);

-- Enable Row Level Security (RLS)
ALTER TABLE public.user_interactions ENABLE ROW LEVEL SECURITY;

-- Allow users to see only their own interactions
CREATE POLICY "Users can view their own interactions" 
ON public.user_interactions FOR SELECT 
USING (auth.uid() = user_id);

-- Allow users to insert their own interactions
CREATE POLICY "Users can insert their own interactions" 
ON public.user_interactions FOR INSERT 
WITH CHECK (auth.uid() = user_id);

-- Provide the list of books selected during onboarding
-- We can reuse the user_profiles table or add a specific column if needed.
-- For now, we will store onboarding "likes" in user_interactions.
