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

-- Lock timeout to prevent lock queue blocking on busy tables
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';
SET LOCAL idle_in_transaction_session_timeout = '30s';

-- Eşzamanlı iki migration çalıştırmasını önlemek için fail-closed advisory lock
DO $$
BEGIN
    IF NOT pg_try_advisory_xact_lock(hashtext('libris_migration_03')) THEN
        RAISE EXCEPTION 'Eşzamanlı çalışma koruması (Advisory Lock): Migration 03 şu anda başka bir oturumda yürütülüyor! Çakışmayı önlemek için işlem durduruldu.';
    END IF;
END $$;

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
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = '_archived_user_interactions_duplicate_backup' 
          AND policyname = 'service_role_manage_duplicate_backup'
    ) THEN
        CREATE POLICY "service_role_manage_duplicate_backup" 
        ON public._archived_user_interactions_duplicate_backup 
        FOR ALL TO service_role 
        USING (true) WITH CHECK (true);
    END IF;
END $$;

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

-- 3.1. FORWARD-RECOVERY: Önceki bir rollback arşivinden 'favorite' ve 'reading' kayıtlarını güvenli,
--                        idempotent, attempt-izole ve kullanıcı verisini ezmeyen (conflict-aware) şekilde geri yükle

-- 3.1.0. Şema Hazırlığı ve Güvenlik İlkeleri (Idempotent DDL)
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name = '_archived_user_interactions_rollback_backup'
    ) THEN
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.columns 
            WHERE table_schema = 'public' 
              AND table_name = '_archived_user_interactions_rollback_backup' 
              AND column_name = 'recovery_applied_at'
        ) THEN
            ALTER TABLE public._archived_user_interactions_rollback_backup 
            ADD COLUMN recovery_applied_at TIMESTAMPTZ;
        END IF;

        IF NOT EXISTS (
            SELECT 1 FROM information_schema.columns 
            WHERE table_schema = 'public' 
              AND table_name = '_archived_user_interactions_rollback_backup' 
              AND column_name = 'rollback_attempt_id'
        ) THEN
            ALTER TABLE public._archived_user_interactions_rollback_backup 
            ADD COLUMN rollback_attempt_id UUID NOT NULL DEFAULT gen_random_uuid();
        END IF;
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS public._archived_user_interactions_recovery_conflicts (
    conflict_id BIGSERIAL PRIMARY KEY,
    detected_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    rollback_attempt_id UUID,
    user_id UUID NOT NULL,
    book_id TEXT NOT NULL,
    snapshot_interaction_type TEXT NOT NULL,
    current_interaction_type TEXT,
    resolution_action TEXT NOT NULL,
    details TEXT NOT NULL,
    CONSTRAINT uq_recovery_conflict UNIQUE (user_id, book_id, snapshot_interaction_type, resolution_action)
);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND table_name = '_archived_user_interactions_recovery_conflicts' 
          AND column_name = 'rollback_attempt_id'
    ) THEN
        ALTER TABLE public._archived_user_interactions_recovery_conflicts 
        ADD COLUMN rollback_attempt_id UUID;
    END IF;
END $$;

REVOKE ALL ON TABLE public._archived_user_interactions_recovery_conflicts FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT ON TABLE public._archived_user_interactions_recovery_conflicts TO service_role;
ALTER TABLE public._archived_user_interactions_recovery_conflicts ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = '_archived_user_interactions_recovery_conflicts' 
          AND policyname = 'service_role_manage_recovery_conflicts'
    ) THEN
        CREATE POLICY "service_role_manage_recovery_conflicts" 
        ON public._archived_user_interactions_recovery_conflicts 
        FOR ALL TO service_role 
        USING (true) WITH CHECK (true);
    END IF;
END $$;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'postgres') THEN
        ALTER TABLE public._archived_user_interactions_recovery_conflicts OWNER TO postgres;
    END IF;
END $$;

DO $$
DECLARE
    v_param_attempt_str TEXT;
    v_target_attempt_id UUID := NULL;
    v_candidate_attempts UUID[];
    v_total_snapshots INTEGER := 0;
    v_dup_snapshot_count INTEGER := 0;
    v_restored_count INTEGER := 0;
    v_preserved_count INTEGER := 0;
    v_missing_count INTEGER := 0;
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name = '_archived_user_interactions_rollback_backup'
    ) THEN
        SELECT count(*) INTO v_total_snapshots FROM public._archived_user_interactions_rollback_backup;
        IF v_total_snapshots = 0 THEN
            RAISE NOTICE 'Rollback arşiv tablosunda snapshot bulunamadı (0 rows). Forward-Recovery atlandı.';
            RETURN;
        END IF;

        -- 3.1.1. ROLLBACK ATTEMPT ID SÖZLEŞMESİ VE BATCH İZOLASYONU
        v_param_attempt_str := current_setting('libris.recovery_attempt_id', true);

        IF v_param_attempt_str IS NOT NULL AND trim(v_param_attempt_str) <> '' THEN
            BEGIN
                v_target_attempt_id := trim(v_param_attempt_str)::uuid;
            EXCEPTION WHEN OTHERS THEN
                RAISE EXCEPTION 'Forward-Recovery Hatası: Belirtilen libris.recovery_attempt_id geçersiz UUID formatında: %', v_param_attempt_str;
            END;

            IF NOT EXISTS (
                SELECT 1 FROM public._archived_user_interactions_rollback_backup 
                WHERE rollback_attempt_id = v_target_attempt_id
            ) THEN
                RAISE EXCEPTION 'Forward-Recovery Hatası: Belirtilen recovery attempt ID (%) arşiv tablosunda bulunamadı!', v_target_attempt_id;
            END IF;

            RAISE NOTICE 'Forward-Recovery: Operatör tarafından belirlenen attempt ID (%) ile işlem yapılıyor.', v_target_attempt_id;
        ELSE
            -- Parametre verilmemişse: Çözümlenmemiş (bekleyen) attempt adaylarını tara
            SELECT array_agg(DISTINCT rollback_attempt_id)
            INTO v_candidate_attempts
            FROM public._archived_user_interactions_rollback_backup
            WHERE recovery_applied_at IS NULL;

            IF v_candidate_attempts IS NULL OR array_length(v_candidate_attempts, 1) IS NULL OR array_length(v_candidate_attempts, 1) = 0 THEN
                RAISE NOTICE 'Forward-Recovery: Arşivdeki tüm snapshot kayıtları daha önce çözümlenmiş (bekleyen attempt yok). Idempotent pas geçildi.';
                RETURN;
            ELSIF array_length(v_candidate_attempts, 1) = 1 THEN
                v_target_attempt_id := v_candidate_attempts[1];
                RAISE NOTICE 'Forward-Recovery: Tekil bekleyen rollback attempt ID (%) tespit edildi ve seçildi.', v_target_attempt_id;
            ELSE
                -- Birden fazla bekleyen attempt var -> Tahmin etme! FAIL-CLOSED DUR!
                RAISE EXCEPTION 'Forward-Recovery Güvenlik Hatası (Fail-Closed): _archived_user_interactions_rollback_backup tablosunda birden fazla bekleyen rollback attempt ID tespit edildi (% adet aday: %). Hangi denemenin geri yükleneceği belirsizdir. Otomatik seçim yapılmaz. Lütfen "SET libris.recovery_attempt_id = ''<UUID>'';" ile hedef attempt_id değerini belirterek çalıştırın.',
                    array_length(v_candidate_attempts, 1), array_to_string(v_candidate_attempts, ', ');
            END IF;
        END IF;

        -- 3.1.2. GÜVENLİK KAPISI: Belirsiz (birden fazla) snapshot denetimi (Fail-Closed)
        -- Seçilen attempt_id içinde aynı kullanıcı ve kitap çifti için birden fazla snapshot denetimi
        SELECT count(*) INTO v_dup_snapshot_count
        FROM (
            SELECT 
                (user_interaction_snapshot->>'user_id')::uuid AS u_id,
                (user_interaction_snapshot->>'book_id')::text AS b_id
            FROM public._archived_user_interactions_rollback_backup
            WHERE rollback_attempt_id = v_target_attempt_id
              AND (user_interaction_snapshot->>'interaction_type') IN ('favorite', 'reading')
            GROUP BY 
                (user_interaction_snapshot->>'user_id')::uuid,
                (user_interaction_snapshot->>'book_id')::text
            HAVING count(*) > 1
        ) dups;

        IF v_dup_snapshot_count > 0 THEN
            RAISE EXCEPTION 'Forward-Recovery Güvenlik Hatası (Fail-Closed): _archived_user_interactions_rollback_backup tablosunda (attempt_id: %) % adet kullanıcı-kitap çifti için birden fazla snapshot tespit edildi. Otomatik seçim belirsizlik yaratacağından ve kullanıcı verisini ezme riski taşıdığından migration durduruldu. Operatör arşiv mutabakatı gereklidir.', v_target_attempt_id, v_dup_snapshot_count;
        END IF;

        -- 3.1.3. Kullanıcı Tarafından Silinmiş / Mevcut Olmayan Satırların Tespiti
        -- Rollback sonrasında kullanıcı etkileşimi tamamen silmişse satır yeniden oluşturulmaz (resurrect edilmez).
        INSERT INTO public._archived_user_interactions_recovery_conflicts (
            rollback_attempt_id, user_id, book_id, snapshot_interaction_type, current_interaction_type, resolution_action, details
        )
        SELECT 
            v_target_attempt_id,
            (arch.user_interaction_snapshot->>'user_id')::uuid,
            (arch.user_interaction_snapshot->>'book_id')::text,
            arch.user_interaction_snapshot->>'interaction_type',
            NULL,
            'SKIPPED_ROW_MISSING_IN_INTERACTIONS',
            'Snapshot mevcut ancak user_interactions tablosunda aktif satır bulunamadı (kullanıcı silmiş olabilir). Satır yeniden oluşturulmadı.'
        FROM public._archived_user_interactions_rollback_backup arch
        WHERE arch.rollback_attempt_id = v_target_attempt_id
          AND NOT EXISTS (
            SELECT 1 FROM public.user_interactions ui
            WHERE ui.user_id = (arch.user_interaction_snapshot->>'user_id')::uuid
              AND ui.book_id = (arch.user_interaction_snapshot->>'book_id')::text
        )
        AND (arch.user_interaction_snapshot->>'interaction_type') IN ('favorite', 'reading')
        ON CONFLICT (user_id, book_id, snapshot_interaction_type, resolution_action) DO NOTHING;
        GET DIAGNOSTICS v_missing_count = ROW_COUNT;

        -- 3.1.4. YENİ KULLANICI VERİSİNİ KORUMA: Çatışma Tespiti
        -- Rollback sonrasında kullanıcı yeni bir durum yazmışsa (örn. 'want_to_read'e dönmüş kitabı 'finished' yapmışsa),
        -- bu durum snapshot ile EZİLMEZ; kullanıcının yeni ve geçerli durumu KORUNUR ve conflict tablosuna kaydedilir.
        INSERT INTO public._archived_user_interactions_recovery_conflicts (
            rollback_attempt_id, user_id, book_id, snapshot_interaction_type, current_interaction_type, resolution_action, details
        )
        SELECT 
            v_target_attempt_id,
            ui.user_id,
            ui.book_id,
            arch.user_interaction_snapshot->>'interaction_type',
            ui.interaction_type,
            'PRESERVED_USER_WRITE_SKIPPED_RECOVERY',
            format('Snapshot durumu (%s) ile güncel kullanıcı durumu (%s) farklı; kullanıcının yeni yazdığı durum korunarak snapshot ezmesi engellendi.',
                   arch.user_interaction_snapshot->>'interaction_type', ui.interaction_type)
        FROM public._archived_user_interactions_rollback_backup arch
        JOIN public.user_interactions ui
          ON ui.user_id = (arch.user_interaction_snapshot->>'user_id')::uuid
         AND ui.book_id = (arch.user_interaction_snapshot->>'book_id')::text
        WHERE arch.rollback_attempt_id = v_target_attempt_id
          AND (arch.user_interaction_snapshot->>'interaction_type') IN ('favorite', 'reading')
          AND ui.interaction_type <> (arch.user_interaction_snapshot->>'interaction_type')
          AND ui.interaction_type <> (
              CASE arch.user_interaction_snapshot->>'interaction_type'
                  WHEN 'reading' THEN 'want_to_read'
                  WHEN 'favorite' THEN 'like'
                  ELSE ''
              END
          )
        ON CONFLICT (user_id, book_id, snapshot_interaction_type, resolution_action) DO NOTHING;
        GET DIAGNOSTICS v_preserved_count = ROW_COUNT;

        -- 3.1.5. GÜVENLİ GERİ YÜKLEME (İDEMPOTENT & VERİ KORUYUCU)
        -- Yalnızca ve yalnızca güncel satır halen rollback'in dönüştürdüğü eski durumda kalmışsa
        -- (yani kullanıcı aradaki sürede satırı değiştirmemişse) orijinal duruma yükseltilir:
        --   'reading' snapshot'ı -> yalnızca satır halen 'want_to_read' ise 'reading'e çevrilir.
        --   'favorite' snapshot'ı -> yalnızca satır halen 'like' ise 'favorite'a çevrilir.
        -- Zaten 'reading' veya 'favorite' olan satırlara dokunulmaz (İdempotency).
        WITH safe_to_restore AS (
            SELECT 
                (arch.user_interaction_snapshot->>'user_id')::uuid AS target_user_id,
                (arch.user_interaction_snapshot->>'book_id')::text AS target_book_id,
                (arch.user_interaction_snapshot->>'interaction_type')::text AS target_type
            FROM public._archived_user_interactions_rollback_backup arch
            JOIN public.user_interactions ui
              ON ui.user_id = (arch.user_interaction_snapshot->>'user_id')::uuid
             AND ui.book_id = (arch.user_interaction_snapshot->>'book_id')::text
            WHERE arch.rollback_attempt_id = v_target_attempt_id
              AND (arch.user_interaction_snapshot->>'interaction_type') IN ('favorite', 'reading')
              AND (
                  (arch.user_interaction_snapshot->>'interaction_type' = 'reading' AND ui.interaction_type = 'want_to_read')
                  OR
                  (arch.user_interaction_snapshot->>'interaction_type' = 'favorite' AND ui.interaction_type = 'like')
              )
        )
        UPDATE public.user_interactions ui
        SET interaction_type = s.target_type
        FROM safe_to_restore s
        WHERE ui.user_id = s.target_user_id
          AND ui.book_id = s.target_book_id;
        GET DIAGNOSTICS v_restored_count = ROW_COUNT;

        -- 3.1.6. Çözümlenen snapshot satırlarını işaretle
        UPDATE public._archived_user_interactions_rollback_backup
        SET recovery_applied_at = now()
        WHERE rollback_attempt_id = v_target_attempt_id
          AND recovery_applied_at IS NULL;

        RAISE NOTICE 'Forward-Recovery Tamamlandı (attempt_id: %): % satır orijinal favorite/reading durumuna yükseltildi. (Yeni kullanıcı yazması korunan: %, silinmiş/eksik: %)',
            v_target_attempt_id, v_restored_count, v_preserved_count, v_missing_count;
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
        -- veya tavsiye/beğeni sinyallerini ('like', 'dislike') ASLA SİLME!
        -- Yalnızca bu trigger tarafından veya saf favori olarak eklenmiş satırı sil.
        DELETE FROM public.user_interactions
        WHERE user_id = OLD.user_id
          AND book_id = OLD.book_id
          AND interaction_type = 'favorite';

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
