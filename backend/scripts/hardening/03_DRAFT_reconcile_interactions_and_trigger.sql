-- =============================================================================
-- [APPROVED FOR STAGING — MODEL A IMPLEMENTATION]
-- GRUP 3: `user_interactions` KISIT VE MODEL A TRIGGER DÜZELTMESİ
-- =============================================================================
-- Dosya: backend/scripts/hardening/03_DRAFT_reconcile_interactions_and_trigger.sql
-- DURUM: ONAYLANDI (MODEL A MİMARİSİ: BAĞIMSIZ FAVORİ VE OKUMA DURUMU)
--
-- Model A İlkeleri:
--   1. 'favorites' tablosu favori üyeliğinin kanonik ve bağımsız deposudur.
--   2. 'user_interactions' tablosu okuma durumlarını ('want_to_read', 'reading', 'finished')
--      ve tavsiye motoru beğeni sinyallerini ('like', 'dislike', 'favorite') ayrı olarak yönetir.
--   3. Bir kitabın favorilere eklenmesi, mevcut okuma durumunu ('reading', 'finished', vb.) ASLA EZMEZ.
--   4. Bir kitabın favorilerden çıkarılması, mevcut okuma durumunu ASLA SİLMEZ.
--   5. Yinelenen favoriler 'favorites' tablosundaki UNIQUE(user_id, book_id) ile engellenir.
--   6. Canlıdaki mevcut veriler sıfır kayıpla korunur.
-- =============================================================================

BEGIN;

-- 1. ÖN KOŞUL KONTROLLERİ (FAIL-CLOSED)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name = 'user_interactions'
    ) THEN
        RAISE EXCEPTION 'Ön koşul başarısız: public.user_interactions tablosu bulunamadı!';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name = 'favorites'
    ) THEN
        RAISE EXCEPTION 'Ön koşul başarısız: public.favorites tablosu bulunamadı!';
    END IF;
END $$;

-- 2. UNIQUE KISIT GÜVENCESİ
-- user_interactions üzerinde (user_id, book_id) tekilliğini sağla
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint 
        WHERE conrelid = 'public.user_interactions'::regclass 
          AND contype = 'u'
          AND (
              conname = 'unique_user_book_interaction'
              OR conname = 'user_interactions_user_id_book_id_key'
          )
    ) THEN
        -- Olası mükerrer kayıtları temizleyip kısıtı ekle
        DELETE FROM public.user_interactions a USING public.user_interactions b
        WHERE a.id < b.id 
          AND a.user_id = b.user_id 
          AND a.book_id = b.book_id;

        ALTER TABLE public.user_interactions 
        ADD CONSTRAINT unique_user_book_interaction UNIQUE (user_id, book_id);
    END IF;
END $$;

-- 3. CHECK CONSTRAINT GENİŞLETMESİ (Model A & Koleksiyon Raf Desteği)
-- 'reading' ve 'favorite' durumlarını kabul ederek Web ve mobil etkileşimleri destekle
ALTER TABLE public.user_interactions 
DROP CONSTRAINT IF EXISTS user_interactions_interaction_type_check;

ALTER TABLE public.user_interactions 
ADD CONSTRAINT user_interactions_interaction_type_check 
CHECK (interaction_type IN ('like', 'dislike', 'want_to_read', 'reading', 'finished', 'favorite'));

-- 3.1. FORWARD-RECOVERY: Önceki bir rollback arşivinden 'favorite' ve 'reading' kayıtlarını geri yükle
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name = '_archived_user_interactions_rollback_backup'
    ) THEN
        UPDATE public.user_interactions ui
        SET interaction_type = (arch.user_interaction_snapshot->>'interaction_type')::text
        FROM public._archived_user_interactions_rollback_backup arch
        WHERE ui.user_id = (arch.user_interaction_snapshot->>'user_id')::uuid
          AND ui.book_id = (arch.user_interaction_snapshot->>'book_id')::text
          AND (arch.user_interaction_snapshot->>'interaction_type') IN ('favorite', 'reading');

        RAISE NOTICE 'Forward-Recovery: Rollback arşivinden orijinal favorite/reading durumları başarıyla geri yüklendi.';
    END IF;
END $$;

-- 4. MODEL A KORUYUCU SENKRONİZASYON TRIGGER FONKSİYONU
CREATE OR REPLACE FUNCTION public.sync_favorites_to_interactions()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
BEGIN
    IF (TG_OP = 'INSERT') THEN
        -- MODEL A KURALI:
        -- Kullanıcı kitabı favorilediğinde, user_interactions tablosunda mevcut bir
        -- okuma durumu ('want_to_read', 'reading', 'finished') veya 'dislike' varsa ASLA EZME!
        -- Yalnızca bu kitap için önceden etkileşim yoksa 'favorite' olarak kaydet.
        INSERT INTO public.user_interactions
            (user_id, book_id, interaction_type, created_at)
        VALUES
            (NEW.user_id, NEW.book_id, 'favorite', NEW.added_at)
        ON CONFLICT (user_id, book_id) 
        DO NOTHING;

        RETURN NEW;
    ELSIF (TG_OP = 'DELETE') THEN
        -- MODEL A KURALI:
        -- Kullanıcı kitabı favorilerden çıkardığında, okuma durumunu ('reading', 'finished', 'want_to_read')
        -- veya dislike sinyalini ASLA SİLME!
        -- Yalnızca bu trigger tarafından veya favori olarak eklenmiş satırları sil.
        DELETE FROM public.user_interactions
        WHERE user_id = OLD.user_id
          AND book_id = OLD.book_id
          AND interaction_type IN ('favorite', 'like');

        RETURN OLD;
    END IF;

    RETURN NULL;
END;
$function$;

-- 5. TRIGGER'IN YENİDEN KURULMASI
DROP TRIGGER IF EXISTS trg_sync_favorites ON public.favorites;
CREATE TRIGGER trg_sync_favorites
AFTER INSERT OR DELETE ON public.favorites
FOR EACH ROW EXECUTE FUNCTION public.sync_favorites_to_interactions();

-- 6. GEÇMİŞ FAVORİ VERİLERİNİN SIFIR VERİ KAYBIYLA GERİYE DÖNÜK SENKRONİZASYONU
-- favorites tablosunda olup henüz user_interactions tablosunda hiç kaydı bulunmayan kitapları aktar.
-- Mevcut okuma durumlarını ('want_to_read', 'reading', 'finished') DO NOTHING ile korur.
INSERT INTO public.user_interactions (user_id, book_id, interaction_type, created_at)
SELECT user_id, book_id, 'favorite', added_at
FROM public.favorites
ON CONFLICT (user_id, book_id) DO NOTHING;

COMMIT;
