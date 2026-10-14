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
--   6. Canlıdaki mevcut veriler sıfır kayıpla korunur: Olası mükerrer (duplicate) etkileşimler
--      asla sessizce silinmez; '_archived_user_interactions_duplicate_backup' tablosuna
--      arşivlenir, favori sinyalleri 'favorites' tablosuna aktarılır ve okuma durumları
--      deterministik öncelikle ('finished' > 'reading' > 'want_to_read') korunur.
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


-- 2. KAYIPSIZ MÜKERRER KAYIT ARŞİVLEME VE UNIQUE KISIT GÜVENCESİ
-- Risk Önleme: Asla unarchived / rastgele DELETE (rastgele id karşılaştırmalı silme) yapılmaz.
-- Tüm mükerrer satırlar önce arşivlenir, favori sinyalleri favorites tablosuna aktarılır.
CREATE TABLE IF NOT EXISTS public._archived_user_interactions_duplicate_backup (
    archive_id BIGSERIAL PRIMARY KEY,
    archived_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    user_interaction_id UUID,
    user_id UUID,
    book_id TEXT,
    interaction_type TEXT,
    created_at TIMESTAMPTZ,
    resolution_action TEXT NOT NULL,
    full_row_snapshot JSONB NOT NULL
);

REVOKE ALL ON TABLE public._archived_user_interactions_duplicate_backup FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT ON TABLE public._archived_user_interactions_duplicate_backup TO service_role;
ALTER TABLE public._archived_user_interactions_duplicate_backup ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'postgres') THEN
        ALTER TABLE public._archived_user_interactions_duplicate_backup OWNER TO postgres;
    END IF;
END $$;

-- 2.1. Geçersiz (NULL veya boş) kimlik kontrolü ve arşivlenmesi
INSERT INTO public._archived_user_interactions_duplicate_backup (
    user_interaction_id, user_id, book_id, interaction_type, created_at, resolution_action, full_row_snapshot
)
SELECT id, user_id, book_id, interaction_type, created_at, 'ARCHIVED_NULL_OR_EMPTY_IDENTIFIER', to_jsonb(ui.*)
FROM public.user_interactions ui
WHERE user_id IS NULL OR book_id IS NULL OR trim(book_id) = '';

DELETE FROM public.user_interactions
WHERE user_id IS NULL OR book_id IS NULL OR trim(book_id) = '';

-- 2.1.1. Uzlaştırma sırasında eski trigger'ın çakışmasını önlemek için kaldır
DROP TRIGGER IF EXISTS trg_sync_favorites ON public.favorites;

-- 2.2. Mükerrer kayıtların deterministik ve kayıpsız uzlaştırılması
DO $$
DECLARE
    dup_count INTEGER;
    irreconcilable_count INTEGER;
BEGIN
    SELECT count(*) INTO dup_count
    FROM (
        SELECT user_id, book_id
        FROM public.user_interactions
        GROUP BY user_id, book_id
        HAVING count(*) > 1
    ) sub;

    IF dup_count > 0 THEN
        RAISE NOTICE 'user_interactions tablosunda % adet mükerrer (user_id, book_id) çifti tespit edildi. Kayıpsız arşivleme başlatılıyor...', dup_count;

        -- A. Tüm mükerrer kayıtları arşiv tablosuna eksiksiz snapshot al
        INSERT INTO public._archived_user_interactions_duplicate_backup (
            user_interaction_id, user_id, book_id, interaction_type, created_at, resolution_action, full_row_snapshot
        )
        SELECT 
            ui.id, ui.user_id, ui.book_id, ui.interaction_type, ui.created_at,
            'PRE_DEDUPLICATION_SNAPSHOT',
            to_jsonb(ui.*)
        FROM public.user_interactions ui
        WHERE (ui.user_id, ui.book_id) IN (
            SELECT user_id, book_id FROM public.user_interactions GROUP BY user_id, book_id HAVING count(*) > 1
        );

        -- B. Mükerrer satırlar arasında 'favorite' veya 'like' varsa bunu public.favorites tablosuna aktararak favori üyeliğini garantiye al
        INSERT INTO public.favorites (user_id, book_id, book_title, added_at)
        SELECT 
            ui.user_id, 
            ui.book_id, 
            COALESCE((SELECT b.title FROM public.books b WHERE b.isbn13 = ui.book_id), 'Favori Kitap'),
            ui.created_at
        FROM public.user_interactions ui
        WHERE (ui.user_id, ui.book_id) IN (
            SELECT user_id, book_id FROM public.user_interactions GROUP BY user_id, book_id HAVING count(*) > 1
        )
        AND ui.interaction_type IN ('favorite', 'like')
        ON CONFLICT (user_id, book_id) DO NOTHING;

        -- C. Çözümlenemez çelişki kontrolü: Aynı kullanıcı ve kitap için hem 'like' hem 'dislike' varsa fail-closed dur
        SELECT count(*) INTO irreconcilable_count
        FROM (
            SELECT user_id, book_id
            FROM public.user_interactions
            WHERE interaction_type IN ('like', 'dislike')
            GROUP BY user_id, book_id
            HAVING count(DISTINCT interaction_type) > 1
        ) conflicts;

        IF irreconcilable_count > 0 THEN
            RAISE EXCEPTION 'Ön koşul başarısız: % adet kitapta çözümlenemeyen çelişkili etkileşim kaydı (like ve dislike aynı anda) tespit edildi. Veriler _archived_user_interactions_duplicate_backup tablosuna arşivlendi. Manuel operatör incelemesi gereklidir.', irreconcilable_count;
        END IF;

        -- D. user_interactions için deterministik öncelik uzlaştırması:
        -- Öncelik: 1) finished (nihai okuma durumu), 2) reading (aktif okuma), 3) want_to_read, 4) dislike, 5) like, 6) favorite.
        -- Eşitlik durumunda en güncel created_at (en son id) korunur.
        WITH ranked_interactions AS (
            SELECT 
                id,
                ROW_NUMBER() OVER (
                    PARTITION BY user_id, book_id
                    ORDER BY 
                        CASE interaction_type
                            WHEN 'finished' THEN 1
                            WHEN 'reading' THEN 2
                            WHEN 'want_to_read' THEN 3
                            WHEN 'dislike' THEN 4
                            WHEN 'like' THEN 5
                            WHEN 'favorite' THEN 6
                            ELSE 7
                        END ASC,
                        created_at DESC,
                        id::text DESC
                ) AS rank_num
            FROM public.user_interactions
            WHERE (user_id, book_id) IN (
                SELECT user_id, book_id FROM public.user_interactions GROUP BY user_id, book_id HAVING count(*) > 1
            )
        )
        DELETE FROM public.user_interactions
        WHERE id IN (
            SELECT id FROM ranked_interactions WHERE rank_num > 1
        );

        RAISE NOTICE 'Mükerrer kayıtlar kayıpsız olarak uzlaştırıldı: Okuma durumları korundu, favoriler favorites tablosuna taşındı, yedekler _archived_user_interactions_duplicate_backup tablosuna yazıldı.';
    ELSE
        RAISE NOTICE 'user_interactions tablosunda mükerrer kayıt bulunmadı (0 duplicate).';
    END IF;
END $$;

-- 2.3. UNIQUE kısıtının eklenmesi
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
