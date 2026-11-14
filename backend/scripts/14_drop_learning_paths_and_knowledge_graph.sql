-- =============================================================================
-- 14_drop_learning_paths_and_knowledge_graph.sql
--
-- Removes the tables of two features that were deleted from the application in
-- November 2026 (learning paths and the personal knowledge graph). Migrations 11
-- and 12 stay in place as applied schema history; this migration retires their
-- tables so the schema matches the code.
--
-- DESTRUCTIVE: this permanently deletes any rows users created in these features.
-- Before applying to a real project:
--   1. take a backup (Supabase dashboard -> Database -> Backups, or pg_dump of the
--      three tables below);
--   2. apply on staging first and run the backend test suite against it;
--   3. apply to production inside a maintenance window.
--
-- Idempotent: safe to run more than once. Dropping a table also drops its indexes,
-- RLS policies and the learning_path_items -> learning_paths foreign key.
-- No other table references these tables.
-- =============================================================================

BEGIN;

DROP TABLE IF EXISTS public.learning_path_items;
DROP TABLE IF EXISTS public.learning_paths;
DROP TABLE IF EXISTS public.knowledge_relationships;

COMMIT;
