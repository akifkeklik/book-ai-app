-- =============================================================================
-- [DRAFT / NOT FOR IMMEDIATE EXECUTION]
-- ROLLBACK: GRUP 3 ETKİLEŞİM KISITI VE TRIGGER GERİ ALMA
-- =============================================================================
-- Dosya: backend/scripts/hardening/03_DRAFT_reconcile_interactions_and_trigger_rollback.sql
-- Amaç: 03_DRAFT_reconcile_interactions_and_trigger.sql ile yapılan değişiklikleri
--        önceki canlı durumuna geri getirmek.
-- 
-- KRİTİK OPERASYONEL UYARI VE İSTEMCİ UYUMLULUK KISITI:
-- 1. Bu rollback betiği 'user_interactions_interaction_type_check' kısıtını eski dar
--    kapsamına ('like', 'dislike', 'want_to_read', 'finished') geri döndürür.
-- 2. CANLI WEB UYGULAMASI (web/src/app/actions/library.ts line 336) doğrudan 'reading'
--    ve 'favorite' durumlarını yazmaktadır.
-- 3. BU ROLLBACK CANLIDA ÇALIŞTIRILIRSA, WEB KULLANICILARININ KİTAPLARI 'READING' VEYA
--    'FAVORITE' OLARAK İŞARETLEMESİ ANINDA POSTGRESQL CHECK CONSTRAINT VIOLATION İLE ÇÖKER!
-- 4. Bu nedenle bu rollback canlıda istemciler etkinken güvenli bir geri dönüş (zero-downtime)
--    sağlamaz; yalnızca web uygulaması bakım moduna alındığında veya eski sürüme döndürüldüğünde
--    uygulanabilir.
-- 5. Geriye dönük 'favorite' ve 'reading' kayıtları '_archived_user_interactions_rollback_backup'
--    tablosuna eksiksiz snapshot alınır; 03_DRAFT tekrar çalıştırıldığında Bölüm 3.1
--    üzerinden kayıpsız olarak geri yüklenir (Forward-Recovery).
-- =============================================================================

BEGIN;

-- Lock timeout to prevent lock queue blocking on busy tables
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';
SET LOCAL idle_in_transaction_session_timeout = '30s';

-- Eşzamanlı iki rollback/migration çalıştırmasını önlemek için fail-closed advisory lock
DO $$
BEGIN
    IF NOT pg_try_advisory_xact_lock(hashtext('libris_migration_03')) THEN
        RAISE EXCEPTION 'Eşzamanlı çalışma koruması (Advisory Lock): Migration 03 veya Rollback şu anda başka bir oturumda yürütülüyor! Çakışmayı önlemek için işlem durduruldu.';
    END IF;
END $$;

-- 1. Güvenli Geri Dönüş Trigger'ı (Eski 4'lü kısıta dönülse dahi okuma durumlarını EZMEZ)
CREATE OR REPLACE FUNCTION public.sync_favorites_to_interactions()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
BEGIN
    IF (TG_OP = 'INSERT') THEN
        -- GÜVENLİK GÜVENCESİ: Rollback durumunda dahi mevcut okuma durumunu EZME
        INSERT INTO public.user_interactions
            (user_id, book_id, interaction_type, created_at)
        VALUES
            (NEW.user_id, NEW.book_id, 'like', NEW.added_at)
        ON CONFLICT (user_id, book_id)
        DO NOTHING;

        RETURN NEW;
    ELSIF (TG_OP = 'DELETE') THEN
        DELETE FROM public.user_interactions
        WHERE user_id = OLD.user_id
          AND book_id = OLD.book_id
          AND interaction_type IN ('favorite', 'like');

        RETURN OLD;
    END IF;

    RETURN NULL;
END;
$function$;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'postgres') THEN
        ALTER FUNCTION public.sync_favorites_to_interactions() OWNER TO postgres;
    END IF;
END $$;

REVOKE ALL ON FUNCTION public.sync_favorites_to_interactions() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.sync_favorites_to_interactions() TO authenticated, service_role;

-- 2. VERİ KAYBI KORUMASI: Geri alınamayacak 'favorite' ve 'reading' verilerini güvenle arşivle
CREATE TABLE IF NOT EXISTS public._archived_user_interactions_rollback_backup (
    archive_id BIGSERIAL PRIMARY KEY,
    archived_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    rollback_attempt_id UUID NOT NULL DEFAULT gen_random_uuid(),
    recovery_applied_at TIMESTAMPTZ,
    user_interaction_snapshot JSONB NOT NULL
);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND table_name = '_archived_user_interactions_rollback_backup' 
          AND column_name = 'rollback_attempt_id'
    ) THEN
        ALTER TABLE public._archived_user_interactions_rollback_backup 
        ADD COLUMN rollback_attempt_id UUID NOT NULL DEFAULT gen_random_uuid();
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND table_name = '_archived_user_interactions_rollback_backup' 
          AND column_name = 'recovery_applied_at'
    ) THEN
        ALTER TABLE public._archived_user_interactions_rollback_backup 
        ADD COLUMN recovery_applied_at TIMESTAMPTZ;
    END IF;
END $$;

REVOKE ALL ON TABLE public._archived_user_interactions_rollback_backup FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT ON TABLE public._archived_user_interactions_rollback_backup TO service_role;
ALTER TABLE public._archived_user_interactions_rollback_backup ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = '_archived_user_interactions_rollback_backup' 
          AND policyname = 'service_role_manage_rollback_backup'
    ) THEN
        CREATE POLICY "service_role_manage_rollback_backup" 
        ON public._archived_user_interactions_rollback_backup 
        FOR ALL TO service_role 
        USING (true) WITH CHECK (true);
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'postgres') THEN
        ALTER TABLE public._archived_user_interactions_rollback_backup OWNER TO postgres;
    END IF;
END $$;

DO $$
DECLARE
    v_rollback_attempt_id UUID := gen_random_uuid();
    v_archived_count INTEGER := 0;
BEGIN
    IF EXISTS (
        SELECT 1 FROM public.user_interactions
        WHERE interaction_type IN ('favorite', 'reading')
    ) THEN
        INSERT INTO public._archived_user_interactions_rollback_backup (archived_at, rollback_attempt_id, user_interaction_snapshot)
        SELECT now(), v_rollback_attempt_id, to_jsonb(ui.*)
        FROM public.user_interactions ui
        WHERE interaction_type IN ('favorite', 'reading');
        GET DIAGNOSTICS v_archived_count = ROW_COUNT;
        RAISE NOTICE 'Rollback Arşivi: user_interactions favorite/reading satırları snapshot tablosuna yedeklendi (attempt_id: %, adet: %).', v_rollback_attempt_id, v_archived_count;
    END IF;
END $$;

-- 3. Eğer 'favorite' veya 'reading' satırları varsa eski kısıta uydurmak için dönüştür
UPDATE public.user_interactions 
SET interaction_type = 'like' 
WHERE interaction_type = 'favorite';

UPDATE public.user_interactions 
SET interaction_type = 'want_to_read' 
WHERE interaction_type = 'reading';

-- 4. Eski Dar Kısıtı Geri Kur
ALTER TABLE public.user_interactions 
DROP CONSTRAINT IF EXISTS user_interactions_interaction_type_check;

ALTER TABLE public.user_interactions 
ADD CONSTRAINT user_interactions_interaction_type_check 
CHECK (interaction_type IN ('like', 'dislike', 'want_to_read', 'finished'));

COMMIT;
