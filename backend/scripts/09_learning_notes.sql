-- migration: Create user_notes table for learning companion and knowledge retention
-- Description: Stores personal notes, key takeaways, and research questions associated with books and users.

CREATE TABLE IF NOT EXISTS public.user_notes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    book_id TEXT NOT NULL, -- references isbn13 from books table
    note_type TEXT NOT NULL CHECK (note_type IN ('personal_note', 'key_takeaway', 'question')),
    content TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Index for fast lookup of a user's notes for a specific book
CREATE INDEX IF NOT EXISTS idx_user_notes_user_book ON public.user_notes(user_id, book_id);

-- Index for filtering a user's notes by note type
CREATE INDEX IF NOT EXISTS idx_user_notes_user_type ON public.user_notes(user_id, note_type);

-- Index for chronological ordering of notes
CREATE INDEX IF NOT EXISTS idx_user_notes_user_created ON public.user_notes(user_id, created_at DESC);

-- Enable Row Level Security (RLS)
ALTER TABLE public.user_notes ENABLE ROW LEVEL SECURITY;

-- Allow users to view only their own notes
DROP POLICY IF EXISTS "Users can view their own notes" ON public.user_notes;
CREATE POLICY "Users can view their own notes" 
ON public.user_notes FOR SELECT 
USING (auth.uid() = user_id);

-- Allow users to create their own notes
DROP POLICY IF EXISTS "Users can insert their own notes" ON public.user_notes;
CREATE POLICY "Users can insert their own notes" 
ON public.user_notes FOR INSERT 
WITH CHECK (auth.uid() = user_id);

-- Allow users to update their own notes
DROP POLICY IF EXISTS "Users can update their own notes" ON public.user_notes;
CREATE POLICY "Users can update their own notes" 
ON public.user_notes FOR UPDATE 
USING (auth.uid() = user_id) 
WITH CHECK (auth.uid() = user_id);

-- Allow users to delete their own notes
DROP POLICY IF EXISTS "Users can delete their own notes" ON public.user_notes;
CREATE POLICY "Users can delete their own notes" 
ON public.user_notes FOR DELETE 
USING (auth.uid() = user_id);

