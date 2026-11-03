-- =============================================================================
-- [DRAFT / NOT FOR IMMEDIATE EXECUTION]
-- ROLLBACK: GRUP 1B İKİNCİL EN AZ YETKİ VE POLİTİKA GERİ ALMA
-- =============================================================================
-- Dosya: backend/scripts/hardening/01b_DRAFT_least_privilege_and_policy_cleanup_rollback.sql
-- =============================================================================

BEGIN;

SET LOCAL lock_timeout = '5s';

-- 1. 'books' Tablosuna Geri Dönüş
GRANT INSERT, UPDATE, DELETE ON public.books TO anon, authenticated;

-- 'python_ekleme_izni' ve 'python_guncelleme_izni' politikalarını geri oluştur
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE schemaname = 'public' AND tablename = 'books' AND policyname = 'python_ekleme_izni'
    ) THEN
        CREATE POLICY "python_ekleme_izni"
        ON public.books FOR INSERT
        WITH CHECK (true);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE schemaname = 'public' AND tablename = 'books' AND policyname = 'python_guncelleme_izni'
    ) THEN
        CREATE POLICY "python_guncelleme_izni"
        ON public.books FOR UPDATE
        USING (true)
        WITH CHECK (true);
    END IF;
END $$;

-- 2. Kullanıcı Tabloları Anon Yazma Yetkilerini Geri Getir
GRANT INSERT, UPDATE, DELETE ON public.favorites TO anon;
GRANT INSERT, UPDATE, DELETE ON public.user_activities TO anon;
GRANT INSERT, UPDATE, DELETE ON public.user_interactions TO anon;
GRANT INSERT, UPDATE, DELETE ON public.user_profiles TO anon;

GRANT UPDATE, DELETE ON public.user_activities TO authenticated;

COMMIT;
