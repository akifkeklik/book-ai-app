-- =============================================================================
-- 15_reader_catalog_contributions.sql
--
-- Lets signed-in readers add a book that is missing from the shared catalog,
-- without making public.books writable by clients.
--
-- Design:
--   * public.books stays SELECT-only for anon/authenticated (hardening 01/01b).
--   * add_catalog_book() is SECURITY DEFINER, callable only by `authenticated`,
--     validates every field, records who added the book, and never overwrites an
--     existing catalog row (ON CONFLICT DO NOTHING).
--   * A per-user daily cap limits abuse.
--
-- Idempotent and non-destructive: safe to run more than once.
-- =============================================================================

BEGIN;

-- Columns the RPC writes. They already exist in Supabase (00_init_books); these are no-ops
-- there and only fill gaps in minimal schemas such as the CI stub.
ALTER TABLE public.books ADD COLUMN IF NOT EXISTS thumbnail TEXT;
ALTER TABLE public.books ADD COLUMN IF NOT EXISTS average_rating NUMERIC DEFAULT 0;
ALTER TABLE public.books ADD COLUMN IF NOT EXISTS ratings_count NUMERIC DEFAULT 0;
ALTER TABLE public.books ADD COLUMN IF NOT EXISTS published_date TEXT;
ALTER TABLE public.books ADD COLUMN IF NOT EXISTS page_count NUMERIC DEFAULT 0;
ALTER TABLE public.books ADD COLUMN IF NOT EXISTS added_by UUID;
ALTER TABLE public.books ADD COLUMN IF NOT EXISTS added_at TIMESTAMPTZ;
CREATE INDEX IF NOT EXISTS idx_books_added_by_added_at ON public.books (added_by, added_at);

CREATE OR REPLACE FUNCTION public.add_catalog_book(
    p_isbn13 TEXT,
    p_title TEXT,
    p_authors TEXT,
    p_categories TEXT DEFAULT '',
    p_description TEXT DEFAULT '',
    p_thumbnail TEXT DEFAULT '',
    p_page_count INTEGER DEFAULT 0,
    p_published_date TEXT DEFAULT ''
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_user UUID := auth.uid();
    v_today_count INTEGER;
    v_inserted INTEGER;
BEGIN
    IF v_user IS NULL THEN
        RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
    END IF;

    IF p_isbn13 IS NULL OR p_isbn13 !~ '^(97[89][0-9]{10}|lb[0-9a-f]{16})$' THEN
        RAISE EXCEPTION 'invalid catalog id' USING ERRCODE = '22023';
    END IF;
    IF length(btrim(coalesce(p_title, ''))) = 0 OR length(p_title) > 300 THEN
        RAISE EXCEPTION 'invalid title' USING ERRCODE = '22023';
    END IF;
    IF length(btrim(coalesce(p_authors, ''))) = 0 OR length(p_authors) > 300 THEN
        RAISE EXCEPTION 'invalid authors' USING ERRCODE = '22023';
    END IF;
    IF length(coalesce(p_categories, '')) > 120
       OR length(coalesce(p_description, '')) > 5000
       OR length(coalesce(p_published_date, '')) > 20
       OR coalesce(p_page_count, 0) NOT BETWEEN 0 AND 20000 THEN
        RAISE EXCEPTION 'invalid book fields' USING ERRCODE = '22023';
    END IF;
    IF coalesce(p_thumbnail, '') <> ''
       AND p_thumbnail !~ '^https://(books\.google\.com|covers\.openlibrary\.org)/' THEN
        RAISE EXCEPTION 'invalid cover url' USING ERRCODE = '22023';
    END IF;

    SELECT count(*) INTO v_today_count
    FROM public.books
    WHERE added_by = v_user AND added_at > now() - interval '1 day';
    IF v_today_count >= 20 THEN
        RAISE EXCEPTION 'daily contribution limit reached' USING ERRCODE = '54000';
    END IF;

    INSERT INTO public.books (
        isbn13, title, authors, categories, description, thumbnail,
        page_count, published_date, average_rating, ratings_count, added_by, added_at
    ) VALUES (
        p_isbn13, btrim(p_title), btrim(p_authors), coalesce(nullif(btrim(p_categories), ''), 'General'),
        coalesce(p_description, ''), coalesce(p_thumbnail, ''),
        coalesce(p_page_count, 0), coalesce(p_published_date, ''), 0, 0, v_user, now()
    )
    ON CONFLICT (isbn13) DO NOTHING;

    GET DIAGNOSTICS v_inserted = ROW_COUNT;
    RETURN v_inserted = 1;
END;
$$;

-- Only signed-in users may call it. Guarded so the migration also runs where the
-- Supabase roles do not exist (plain PostgreSQL in CI).
REVOKE ALL ON FUNCTION public.add_catalog_book(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, INTEGER, TEXT) FROM PUBLIC;
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
        REVOKE ALL ON FUNCTION public.add_catalog_book(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, INTEGER, TEXT) FROM anon;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
        GRANT EXECUTE ON FUNCTION public.add_catalog_book(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, INTEGER, TEXT) TO authenticated;
    END IF;
END $$;

COMMIT;
