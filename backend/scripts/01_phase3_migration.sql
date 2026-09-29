-- 1. Ensure user_interactions has unique constraint
-- Delete exact duplicates first if they exist
DELETE FROM public.user_interactions a USING public.user_interactions b
WHERE a.id < b.id AND a.user_id = b.user_id AND a.book_id = b.book_id;

-- Now add unique constraint
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 
    FROM pg_constraint 
    WHERE conname = 'unique_user_book_interaction'
  ) THEN
    ALTER TABLE public.user_interactions ADD CONSTRAINT unique_user_book_interaction UNIQUE (user_id, book_id);
  END IF;
END $$;

-- 2. Backfill existing favorites into user_interactions as 'like'
INSERT INTO public.user_interactions (user_id, book_id, interaction_type, created_at)
SELECT user_id, isbn13, 'like', added_at
FROM public.favorites
ON CONFLICT (user_id, book_id) DO UPDATE SET interaction_type = 'like';

-- 3. Create Trigger to keep user_interactions updated when Flutter app modifies favorites
CREATE OR REPLACE FUNCTION sync_favorites_to_interactions()
RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'INSERT') THEN
        INSERT INTO public.user_interactions (user_id, book_id, interaction_type, created_at)
        VALUES (NEW.user_id, NEW.isbn13, 'like', NEW.added_at)
        ON CONFLICT (user_id, book_id) DO UPDATE SET interaction_type = 'like';
        RETURN NEW;
    ELSIF (TG_OP = 'DELETE') THEN
        DELETE FROM public.user_interactions 
        WHERE user_id = OLD.user_id AND book_id = OLD.isbn13 AND interaction_type = 'like';
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_favorites ON public.favorites;
CREATE TRIGGER trg_sync_favorites
AFTER INSERT OR DELETE ON public.favorites
FOR EACH ROW EXECUTE FUNCTION sync_favorites_to_interactions();

-- 4. RLS Policies on user_interactions
ALTER TABLE public.user_interactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view their own interactions" ON public.user_interactions;
CREATE POLICY "Users can view their own interactions" 
ON public.user_interactions FOR SELECT 
USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert their own interactions" ON public.user_interactions;
CREATE POLICY "Users can insert their own interactions" 
ON public.user_interactions FOR INSERT 
WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update their own interactions" ON public.user_interactions;
CREATE POLICY "Users can update their own interactions" 
ON public.user_interactions FOR UPDATE 
USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete their own interactions" ON public.user_interactions;
CREATE POLICY "Users can delete their own interactions" 
ON public.user_interactions FOR DELETE 
USING (auth.uid() = user_id);
