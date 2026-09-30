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
    isbn13 TEXT PRIMARY KEY
);

CREATE TABLE IF NOT EXISTS public.favorites (
    user_id UUID REFERENCES auth.users(id),
    isbn13 TEXT REFERENCES public.books(isbn13),
    added_at TIMESTAMPTZ DEFAULT now(),
    PRIMARY KEY (user_id, isbn13)
);
