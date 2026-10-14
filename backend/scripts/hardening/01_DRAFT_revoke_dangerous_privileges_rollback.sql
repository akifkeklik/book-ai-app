-- =============================================================================
-- [DRAFT / NOT FOR IMMEDIATE EXECUTION]
-- ROLLBACK: GRUP 1 YETKİ AZALTIMI GERİ ALMA
-- =============================================================================
-- Dosya: backend/scripts/hardening/01_DRAFT_revoke_dangerous_privileges_rollback.sql
-- Amaç: 01_DRAFT_revoke_dangerous_privileges.sql ile yapılan yetki değişikliklerini
--        kontrollü olarak geri getirmek.
-- 
-- GÜVENLİK KURALI:
-- Bu rollback betiği 'TRUNCATE' yetkisini ASLA geri vermez. TRUNCATE izni canlıda
-- kazara açık unutulmuş bir güvenlik açığıdır; hiçbir istemci akışı TRUNCATE gerektirmez.
-- Sadece DML (SELECT, INSERT, UPDATE, DELETE) ve eski test politikaları geri getirilir.
-- =============================================================================

BEGIN;

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

-- NOT: TRUNCATE yetkisi ve gelecekteki tablolar için TRUNCATE varsayılan izni güvenliği
-- tehlikeye atacağı için bu rollback script'i tarafından kesinlikle geri verilmez (Fail-Safe Rollback).

COMMIT;
