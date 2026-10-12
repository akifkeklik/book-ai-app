-- migration: Canonical initialization for books and favorites tables
-- Description: Establishes base catalog and user favorites schema if not already present.
-- Safe for existing databases (uses CREATE TABLE IF NOT EXISTS and non-destructive reconciliation).

-- ── 1. Books Table ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.books (
    isbn13 TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    authors TEXT,
    categories TEXT,
    description TEXT,
    thumbnail TEXT,
    average_rating NUMERIC DEFAULT 0,
    ratings_count NUMERIC DEFAULT 0,
    published_date TEXT,
    page_count NUMERIC DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Indexes for search and category filtering
CREATE INDEX IF NOT EXISTS idx_books_title ON public.books(title);
CREATE INDEX IF NOT EXISTS idx_books_categories ON public.books(categories);

-- Enable RLS for public read access
ALTER TABLE public.books ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Books are viewable by everyone" ON public.books;
CREATE POLICY "Books are viewable by everyone"
ON public.books FOR SELECT
USING (true);

-- ── 2. Favorites Table ─────────────────────────────────────────────────────────
-- Canonical schema used by both Flutter (SupabaseService) and Web (LibraryActions).
CREATE TABLE IF NOT EXISTS public.favorites (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    book_id TEXT NOT NULL REFERENCES public.books(isbn13) ON DELETE CASCADE,
    book_title TEXT NOT NULL DEFAULT '',
    book_author TEXT NOT NULL DEFAULT '',
    book_image_url TEXT NOT NULL DEFAULT '',
    added_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(user_id, book_id)
);

-- Reconcile legacy column name if an existing database created 'isbn13' instead of 'book_id'
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'favorites' AND column_name = 'isbn13'
    ) AND NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'favorites' AND column_name = 'book_id'
    ) THEN
        ALTER TABLE public.favorites RENAME COLUMN isbn13 TO book_id;
    END IF;
END $$;

-- Ensure additional display columns exist if favorites was created from older minimal schema
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'favorites' AND column_name = 'book_author'
    ) THEN
        ALTER TABLE public.favorites ADD COLUMN book_author TEXT NOT NULL DEFAULT '';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'favorites' AND column_name = 'book_image_url'
    ) THEN
        ALTER TABLE public.favorites ADD COLUMN book_image_url TEXT NOT NULL DEFAULT '';
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_favorites_user_id ON public.favorites(user_id);

ALTER TABLE public.favorites ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view their own favorites" ON public.favorites;
CREATE POLICY "Users can view their own favorites"
ON public.favorites FOR SELECT
USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert their own favorites" ON public.favorites;
CREATE POLICY "Users can insert their own favorites"
ON public.favorites FOR INSERT
WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update their own favorites" ON public.favorites;
CREATE POLICY "Users can update their own favorites"
ON public.favorites FOR UPDATE
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete their own favorites" ON public.favorites;
CREATE POLICY "Users can delete their own favorites"
ON public.favorites FOR DELETE
USING (auth.uid() = user_id);
