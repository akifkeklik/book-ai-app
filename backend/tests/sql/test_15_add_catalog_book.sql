-- Runtime checks for migration 15 (add_catalog_book). Run after all migrations in CI.
-- Any failed check raises an exception and fails the job.
DO $$
DECLARE
    ok BOOLEAN;
    v_title TEXT;
    v_added_by UUID;
BEGIN
    -- 1. A new book is inserted and attributed to the caller.
    ok := public.add_catalog_book('9781234567897', 'A Book', 'An Author', 'Science', '', '', 120, '2020');
    IF ok IS NOT TRUE THEN RAISE EXCEPTION 'expected insert to return true'; END IF;
    SELECT title, added_by INTO v_title, v_added_by FROM public.books WHERE isbn13 = '9781234567897';
    IF v_title <> 'A Book' OR v_added_by IS NULL THEN RAISE EXCEPTION 'book not stored with added_by'; END IF;

    -- 2. An existing catalog row is never overwritten.
    ok := public.add_catalog_book('9781234567897', 'Changed', 'Someone', '', '', '', 0, '');
    IF ok IS NOT FALSE THEN RAISE EXCEPTION 'duplicate should return false'; END IF;
    SELECT title INTO v_title FROM public.books WHERE isbn13 = '9781234567897';
    IF v_title <> 'A Book' THEN RAISE EXCEPTION 'existing row was overwritten'; END IF;

    -- 3. Generated ids for books without an ISBN are accepted.
    ok := public.add_catalog_book('lb0123456789abcdef', 'No ISBN Book', 'Writer', '', '', '', 0, '');
    IF ok IS NOT TRUE THEN RAISE EXCEPTION 'generated id rejected'; END IF;

    -- 4. Invalid input is rejected.
    BEGIN
        PERFORM public.add_catalog_book('12345', 'T', 'A', '', '', '', 0, '');
        RAISE EXCEPTION 'bad id accepted';
    EXCEPTION WHEN invalid_parameter_value THEN NULL;
    END;
    BEGIN
        PERFORM public.add_catalog_book('9781234567880', '   ', 'A', '', '', '', 0, '');
        RAISE EXCEPTION 'empty title accepted';
    EXCEPTION WHEN invalid_parameter_value THEN NULL;
    END;
    BEGIN
        PERFORM public.add_catalog_book('9781234567881', 'T', 'A', '', '', 'https://evil.example/x.png', 0, '');
        RAISE EXCEPTION 'foreign cover url accepted';
    EXCEPTION WHEN invalid_parameter_value THEN NULL;
    END;

    -- Clean up so later CI steps see the original catalog.
    DELETE FROM public.books WHERE isbn13 IN ('9781234567897', 'lb0123456789abcdef');
    RAISE NOTICE 'migration 15 runtime checks passed';
END $$;
