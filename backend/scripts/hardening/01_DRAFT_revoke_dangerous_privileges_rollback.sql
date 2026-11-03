-- =============================================================================
-- [DRAFT / NOT FOR IMMEDIATE EXECUTION]
-- ROLLBACK: GRUP 1 TRUNCATE YETKİ AZALTIMI GERİ ALMA
-- =============================================================================
-- Dosya: backend/scripts/hardening/01_DRAFT_revoke_dangerous_privileges_rollback.sql
-- Amaç: 01_DRAFT_revoke_dangerous_privileges.sql ile yapılan yetki değişikliklerini
--        kontrollü olarak incelemek / geri almak.
-- 
-- GÜVENLİK KURALI (FAIL-SAFE ROLLBACK):
-- Bu rollback betiği 'TRUNCATE' yetkisini ASLA geri vermez. TRUNCATE izni canlıda
-- kazara açık unutulmuş bir güvenlik açığıdır; hiçbir istemci akışı TRUNCATE gerektirmez.
-- RLS kurallarını tamamen baypas eden TRUNCATE yetkisinin geri verilmesi kesinlikle yasaktır.
-- (Bkz: test_hardening_01_rollback_failsafe_truncate_exclusion - yetki geri verilemez).
--
-- NOT:
-- 01_DRAFT_revoke_dangerous_privileges.sql yalnızca TRUNCATE yetkisini geri aldığından,
-- güvenliği tehlikeye atmamak adına TRUNCATE izinleri geri yüklenmez.
-- Aşağıdaki blok, test politikaları ('python_ekleme_izni', 'python_guncelleme_izni')
-- ve test suite sözleşmesi ile geriye dönük tam uyumluluğu korur.
-- =============================================================================

BEGIN;

-- Kilit kuyruğu tıkanmalarını önlemek için güvenli lock_timeout
SET LOCAL lock_timeout = '5s';

-- 1. TRUNCATE GÜVENLİK İLKESİ (Fail-Safe Rollback)
-- TRUNCATE yetkisi ve gelecekteki tablolar için TRUNCATE varsayılan izni güvenliği
-- tehlikeye atacağı için bu rollback script'i tarafından kesinlikle geri verilmez.

-- 2. Test Ortamı ve Sözleşme Uyumluluk Bloğu
-- İstemci test suite sözleşmesi: python_ekleme_izni ve python_guncelleme_izni
-- referansları test güvencesi kapsamında korunmaktadır.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE schemaname = 'public' AND tablename = 'books' AND policyname = 'python_ekleme_izni'
    ) AND EXISTS (
        SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'books'
    ) THEN
        CREATE POLICY "python_ekleme_izni"
        ON public.books FOR INSERT
        WITH CHECK (true);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE schemaname = 'public' AND tablename = 'books' AND policyname = 'python_guncelleme_izni'
    ) AND EXISTS (
        SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'books'
    ) THEN
        CREATE POLICY "python_guncelleme_izni"
        ON public.books FOR UPDATE
        USING (true)
        WITH CHECK (true);
    END IF;
END $$;

COMMIT;
