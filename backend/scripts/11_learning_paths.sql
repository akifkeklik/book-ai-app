-- ==============================================================================
-- 11_learning_paths.sql
-- LIBRIS: Personalized Learning Paths & Progress Intelligence
--
-- Creates tables, constraints, indexes, and RLS policies for user learning paths.
-- ==============================================================================

-- 1. Create learning_paths table
CREATE TABLE IF NOT EXISTS public.learning_paths (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT DEFAULT '',
    category TEXT DEFAULT '',
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'completed', 'archived')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- 2. Create learning_path_items table
CREATE TABLE IF NOT EXISTS public.learning_path_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    path_id UUID NOT NULL REFERENCES public.learning_paths(id) ON DELETE CASCADE,
    book_id TEXT NOT NULL,
    order_index INTEGER NOT NULL DEFAULT 0,
    added_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    CONSTRAINT unique_path_book UNIQUE (path_id, book_id)
);

-- 3. Indexes for fast path queries and account isolation
CREATE INDEX IF NOT EXISTS idx_learning_paths_user_id ON public.learning_paths(user_id);
CREATE INDEX IF NOT EXISTS idx_learning_paths_status ON public.learning_paths(status);
CREATE INDEX IF NOT EXISTS idx_learning_path_items_path_id ON public.learning_path_items(path_id);
CREATE INDEX IF NOT EXISTS idx_learning_path_items_book_id ON public.learning_path_items(book_id);

-- 4. Enable Row Level Security (RLS)
ALTER TABLE public.learning_paths ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.learning_path_items ENABLE ROW LEVEL SECURITY;

-- 5. RLS Policies for learning_paths
DROP POLICY IF EXISTS "Users can view their own learning paths" ON public.learning_paths;
CREATE POLICY "Users can view their own learning paths"
    ON public.learning_paths FOR SELECT
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert their own learning paths" ON public.learning_paths;
CREATE POLICY "Users can insert their own learning paths"
    ON public.learning_paths FOR INSERT
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update their own learning paths" ON public.learning_paths;
CREATE POLICY "Users can update their own learning paths"
    ON public.learning_paths FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete their own learning paths" ON public.learning_paths;
CREATE POLICY "Users can delete their own learning paths"
    ON public.learning_paths FOR DELETE
    USING (auth.uid() = user_id);

-- 6. RLS Policies for learning_path_items (inherits ownership from parent path)
DROP POLICY IF EXISTS "Users can view items of their own learning paths" ON public.learning_path_items;
CREATE POLICY "Users can view items of their own learning paths"
    ON public.learning_path_items FOR SELECT
    USING (EXISTS (
        SELECT 1 FROM public.learning_paths p
        WHERE p.id = learning_path_items.path_id AND p.user_id = auth.uid()
    ));

DROP POLICY IF EXISTS "Users can insert items into their own learning paths" ON public.learning_path_items;
CREATE POLICY "Users can insert items into their own learning paths"
    ON public.learning_path_items FOR INSERT
    WITH CHECK (EXISTS (
        SELECT 1 FROM public.learning_paths p
        WHERE p.id = learning_path_items.path_id AND p.user_id = auth.uid()
    ));

DROP POLICY IF EXISTS "Users can update items in their own learning paths" ON public.learning_path_items;
CREATE POLICY "Users can update items in their own learning paths"
    ON public.learning_path_items FOR UPDATE
    USING (EXISTS (
        SELECT 1 FROM public.learning_paths p
        WHERE p.id = learning_path_items.path_id AND p.user_id = auth.uid()
    ));

DROP POLICY IF EXISTS "Users can delete items from their own learning paths" ON public.learning_path_items;
CREATE POLICY "Users can delete items from their own learning paths"
    ON public.learning_path_items FOR DELETE
    USING (EXISTS (
        SELECT 1 FROM public.learning_paths p
        WHERE p.id = learning_path_items.path_id AND p.user_id = auth.uid()
    ));

