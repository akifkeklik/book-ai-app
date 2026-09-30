-- migration: Expand user interactions for smart collections
-- Description: Expand interaction_type to support 'want_to_read', 'reading', 'finished'

-- Drop the existing constraint
ALTER TABLE public.user_interactions DROP CONSTRAINT IF EXISTS user_interactions_interaction_type_check;

-- Add the new constraint with expanded types
ALTER TABLE public.user_interactions ADD CONSTRAINT user_interactions_interaction_type_check 
CHECK (interaction_type IN ('like', 'dislike', 'want_to_read', 'reading', 'finished', 'favorite'));
