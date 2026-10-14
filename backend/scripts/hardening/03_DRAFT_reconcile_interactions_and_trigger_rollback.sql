-- =============================================================================
-- [DRAFT / NOT FOR IMMEDIATE EXECUTION]
-- ROLLBACK: GRUP 3 ETKİLEŞİM KISITI VE TRIGGER GERİ ALMA
-- =============================================================================
-- Dosya: backend/scripts/hardening/03_DRAFT_reconcile_interactions_and_trigger_rollback.sql
-- Amaç: 03_DRAFT_reconcile_interactions_and_trigger.sql ile yapılan değişiklikleri
--        önceki canlı durumuna geri getirmek.
-- 
-- DİKKAT VE VERİ KAYBI UYARISI:
-- Eğer migration sonrasında 'user_interactions' tablosuna 'favorite' veya 'reading'
-- durumunda satırlar kaydedilmişse, eski dar kısıt ('like', 'dislike', 'want_to_read', 'finished')
-- doğrudan uygulanamaz (PostgreSQL constraint violation hatası verir). Bu nedenle
-- rollback betiği önce bu satırları 'like' ve 'want_to_read' değerlerine dönüştürmek
-- zorunda kalabilir. Bu işlem geri alınamaz bir veri dönüşümüdür.
-- =============================================================================

BEGIN;

-- 1. Eski Trigger Fonksiyonuna Geri Dönüş (Güvenli search_path ve SECURITY DEFINER ile)
CREATE OR REPLACE FUNCTION public.sync_favorites_to_interactions()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
BEGIN
    IF (TG_OP = 'INSERT') THEN
        INSERT INTO public.user_interactions
            (user_id, book_id, interaction_type, created_at)
        VALUES
            (NEW.user_id, NEW.book_id, 'like', NEW.added_at)
        ON CONFLICT (user_id, book_id)
        DO UPDATE SET interaction_type = 'like';

        RETURN NEW;
    ELSIF (TG_OP = 'DELETE') THEN
        DELETE FROM public.user_interactions
        WHERE user_id = OLD.user_id
          AND book_id = OLD.book_id
          AND interaction_type = 'like';

        RETURN OLD;
    END IF;

    RETURN NULL;
END;
$function$;

ALTER FUNCTION public.sync_favorites_to_interactions() OWNER TO postgres;

-- 2. Eğer 'favorite' veya 'reading' satırları varsa eski kısıta uydurmak için dönüştür
UPDATE public.user_interactions 
SET interaction_type = 'like' 
WHERE interaction_type = 'favorite';

UPDATE public.user_interactions 
SET interaction_type = 'want_to_read' 
WHERE interaction_type = 'reading';

-- 3. Eski Dar Kısıtı Geri Kur
ALTER TABLE public.user_interactions 
DROP CONSTRAINT IF EXISTS user_interactions_interaction_type_check;

ALTER TABLE public.user_interactions 
ADD CONSTRAINT user_interactions_interaction_type_check 
CHECK (interaction_type IN ('like', 'dislike', 'want_to_read', 'finished'));

COMMIT;
