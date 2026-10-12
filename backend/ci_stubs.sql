-- Stub out Supabase schemas and functions for CI migration testing
CREATE SCHEMA IF NOT EXISTS auth;

CREATE TABLE IF NOT EXISTS auth.users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid()
);

CREATE OR REPLACE FUNCTION auth.uid() RETURNS UUID AS $$
BEGIN
  RETURN '00000000-0000-0000-0000-000000000000'::UUID;
END;
$$ LANGUAGE plpgsql;

CREATE TABLE IF NOT EXISTS public.books (
    isbn13 TEXT PRIMARY KEY,
    title TEXT DEFAULT '',
    authors TEXT DEFAULT '',
    categories TEXT DEFAULT '',
    description TEXT DEFAULT ''
);

CREATE TABLE IF NOT EXISTS public.favorites (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id),
    book_id TEXT REFERENCES public.books(isbn13),
    book_title TEXT DEFAULT '',
    book_author TEXT DEFAULT '',
    book_image_url TEXT DEFAULT '',
    added_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(user_id, book_id)
);
