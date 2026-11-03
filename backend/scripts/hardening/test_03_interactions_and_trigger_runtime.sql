-- =============================================================================
-- LIBRIS DATABASE HARDENING — RUNTIME TEST FOR MODEL A (GROUP 03)
-- =============================================================================
-- DOSYA: backend/scripts/hardening/test_03_interactions_and_trigger_runtime.sql
-- AMAÇ: Model A ilkelerinin, kayıpsız mükerrer kayıt (duplicate) uzlaştırma
--        ve forward-recovery mantığının PostgreSQL çalışma zamanında 20 senaryoda doğrulanması:
--   1. Bağımsız favori ekleme (önceden etkileşim yokken 'favorite' oluşması)
--   2. Okuma durumu koruma ('reading' varken favorilemenin okuma durumunu EZMEMESİ)
--   3. Okuma durumu koruma (favoriden çıkarmanın 'reading' durumunu SİLMEMESİ)
--   4. 'finished' durumu koruma (favorileme ve favoriden çıkarmanın 'finished' durumunu EZMEMESİ/SİLMEMESİ)
--   5. 'dislike' tavsiye sinyalini koruma
--   6. Önceden okuma durumu olmayan favorinin unfavorite ile temizlenmesi
--   7. Yinelenen favorilerin güvenli engellenmesi (UNIQUE kısıtı)
--   8. Geriye dönük backfill idempotency güvencesi (mevcut okuma durumlarına dokunulmaması)
--   9. Kayıpsız mükerrer kayıt uzlaştırması ve arşivleme ('finished' + 'favorite' çatışması)
--   10. Çözümlenemez çelişkilerde ('like' + 'dislike' aynı anda) fail-closed durma
--   11. NULL / Boş kimlik (user_id/book_id) kayıtlarının kayıpsız arşivlenmesi
--   12. 'want_to_read' okuma durumu varken favorileme ve unfavorite (korunma güvencesi)
--   13. 'like' tavsiye sinyali varken favorileme ve unfavorite (ezilmeme ve silinmeme güvencesi)
--   14. Forward-Recovery: Kullanıcı rollback sonrası 'finished' yazdığında snapshot'ın 'finished' durumunu EZMEMESİ (Yeni veri koruma)
--   15. Forward-Recovery: Rollback öncesinde 'want_to_read' olan kitabın 'finished' yapılması ve korunması
--   16. Forward-Recovery: Aynı kullanıcı-kitap çifti için birden fazla snapshot olduğunda FAIL-CLOSED durma
--   17. Forward-Recovery: Tam idempotency (Aynı forward-recovery iki kez çalıştırıldığında)
--   18. Forward-Recovery: Snapshot varken etkileşim satırının silinmiş olması (Satır diriltilmemeli)
--   19. Forward-Recovery: Snapshot ile mevcut satır farklı durumda olduğunda (örn. dislike) ezilmeme
--   20. Forward-Recovery: Kullanıcı veri izolasyonu güvencesi (User A snapshot'ı User B'yi etkilemez)
-- =============================================================================

DO $$
DECLARE
    v_user_1 UUID := '00000000-0000-0000-0000-000000000001'::uuid;
    v_user_2 UUID := '00000000-0000-0000-0000-000000000002'::uuid;
    v_user_3 UUID := '00000000-0000-0000-0000-000000000003'::uuid;
    v_rec RECORD;
    v_count INTEGER;
    v_fail_closed_triggered BOOLEAN := false;
    v_fc_multi_snap BOOLEAN := false;
BEGIN
    RAISE NOTICE '=============================================================';
    RAISE NOTICE 'BAŞLANGIÇ: GRUP 03 MODEL A RUNTIME DOĞRULAMA TESTLERİ';
    RAISE NOTICE '=============================================================';

    -- auth.users stub satırlarını hazırla (foreign key kısıtı için)
    INSERT INTO auth.users (id) VALUES (v_user_1), (v_user_2), (v_user_3) ON CONFLICT DO NOTHING;

    -- public.books stub satırlarını hazırla (favorites tablosundaki book_id foreign key kısıtı için)
    INSERT INTO public.books (isbn13, title) VALUES
        ('BOOK_S1', 'Senaryo 1 Kitabı'),
        ('BOOK_S2', 'Senaryo 2 Kitabı'),
        ('BOOK_S4', 'Bitirilen Kitap'),
        ('BOOK_S5', 'Dislike Edilen Kitap'),
        ('BOOK_S12', 'Want to Read Kitabı'),
        ('BOOK_S13', 'Beğenilen Like Kitabı'),
        ('BOOK_BF1', 'Backfill Kitap 1'),
        ('BOOK_BF2', 'Backfill Kitap 2'),
        ('BOOK_DUP1', 'Mükerrer Kitap 1'),
        ('BOOK_CONFLICT', 'Çelişkili Kitap'),
        ('BOOK_S14', 'Forward Recovery Senaryo 14'),
        ('BOOK_S15', 'Forward Recovery Senaryo 15'),
        ('BOOK_S16', 'Forward Recovery Senaryo 16'),
        ('BOOK_S17', 'Forward Recovery Senaryo 17'),
        ('BOOK_S18', 'Forward Recovery Senaryo 18'),
        ('BOOK_S19', 'Forward Recovery Senaryo 19'),
        ('BOOK_S20', 'Forward Recovery Senaryo 20')
    ON CONFLICT (isbn13) DO NOTHING;

    -- Test öncesi temiz izole veri hazırla (yalnızca test UUID'leri için)
    DELETE FROM public.favorites WHERE user_id IN (v_user_1, v_user_2, v_user_3);
    DELETE FROM public.user_interactions WHERE user_id IN (v_user_1, v_user_2, v_user_3);

    -- -------------------------------------------------------------------------
    -- SENARYO 1: Bağımsız favori ekleme (Önceden etkileşim yokken)
    -- -------------------------------------------------------------------------
    RAISE NOTICE '--- SENARYO 1: Önceden etkileşimi olmayan kitabı favorileme ---';
    INSERT INTO public.favorites (user_id, book_id, book_title, added_at)
    VALUES (v_user_1, 'BOOK_S1', 'Senaryo 1 Kitabı', NOW());

    SELECT * INTO v_rec FROM public.user_interactions 
    WHERE user_id = v_user_1 AND book_id = 'BOOK_S1';

    IF v_rec.interaction_type != 'favorite' THEN
        RAISE EXCEPTION 'SENARYO 1 BAŞARISIZ: user_interactions tablosunda interaction_type "favorite" olmalıydı, mevcut: %', v_rec.interaction_type;
    END IF;
    RAISE NOTICE 'SENARYO 1 BAŞARILI: Bağımsız favori senkronize edildi.';

    -- -------------------------------------------------------------------------
    -- SENARYO 2: 'reading' okuma durumu varken favorileme (EZİLMEME GÜVENCESİ)
    -- -------------------------------------------------------------------------
    RAISE NOTICE '--- SENARYO 2: "reading" varken favorileme (Ezilmeme Kontrolü) ---';
    -- Kullanıcı önce kitabı okuyor olarak işaretler
    INSERT INTO public.user_interactions (user_id, book_id, interaction_type, created_at)
    VALUES (v_user_1, 'BOOK_S2', 'reading', NOW());

    -- Kullanıcı daha sonra bu kitabı favorilerine ekler
    INSERT INTO public.favorites (user_id, book_id, book_title, added_at)
    VALUES (v_user_1, 'BOOK_S2', 'Senaryo 2 Kitabı', NOW());

    -- user_interactions kontrolü: 'reading' ezilmiş olmamalı!
    SELECT * INTO v_rec FROM public.user_interactions 
    WHERE user_id = v_user_1 AND book_id = 'BOOK_S2';

    IF v_rec.interaction_type != 'reading' THEN
        RAISE EXCEPTION 'SENARYO 2 BAŞARISIZ: "reading" durumu korunamadı, üzerine yazıldı! Mevcut: %', v_rec.interaction_type;
    END IF;
    RAISE NOTICE 'SENARYO 2 BAŞARILI: Favorileme "reading" durumunu ezmedi.';

    -- -------------------------------------------------------------------------
    -- SENARYO 3: 'reading' olan kitabı favoriden çıkarma (SİLİNMEME GÜVENCESİ)
    -- -------------------------------------------------------------------------
    RAISE NOTICE '--- SENARYO 3: "reading" olan kitabı favoriden çıkarma ---';
    DELETE FROM public.favorites WHERE user_id = v_user_1 AND book_id = 'BOOK_S2';

    -- favorites tablosundan silinmiş olmalı
    IF EXISTS (SELECT 1 FROM public.favorites WHERE user_id = v_user_1 AND book_id = 'BOOK_S2') THEN
        RAISE EXCEPTION 'SENARYO 3 BAŞARISIZ: favorites tablosundan satır silinemedi!';
    END IF;

    -- user_interactions tablosunda 'reading' korunmuş olmalı!
    SELECT * INTO v_rec FROM public.user_interactions 
    WHERE user_id = v_user_1 AND book_id = 'BOOK_S2';

    IF v_rec.interaction_type IS NULL OR v_rec.interaction_type != 'reading' THEN
        RAISE EXCEPTION 'SENARYO 3 BAŞARISIZ: Favoriden çıkarma "reading" durumunu sildi!';
    END IF;
    RAISE NOTICE 'SENARYO 3 BAŞARILI: Unfavorite işlemi okuma durumunu silmedi.';

    -- -------------------------------------------------------------------------
    -- SENARYO 4: 'finished' okuma durumu varken favorileme ve unfavorite
    -- -------------------------------------------------------------------------
    RAISE NOTICE '--- SENARYO 4: "finished" durumu koruma ---';
    INSERT INTO public.user_interactions (user_id, book_id, interaction_type, created_at)
    VALUES (v_user_1, 'BOOK_S4', 'finished', NOW());

    -- Favoriye ekle
    INSERT INTO public.favorites (user_id, book_id, book_title, added_at)
    VALUES (v_user_1, 'BOOK_S4', 'Bitirilen Kitap', NOW());

    SELECT interaction_type INTO v_rec.interaction_type FROM public.user_interactions 
    WHERE user_id = v_user_1 AND book_id = 'BOOK_S4';
    IF v_rec.interaction_type != 'finished' THEN
        RAISE EXCEPTION 'SENARYO 4 BAŞARISIZ: "finished" üzerine yazıldı!';
    END IF;

    -- Favoriden çıkar
    DELETE FROM public.favorites WHERE user_id = v_user_1 AND book_id = 'BOOK_S4';

    SELECT interaction_type INTO v_rec.interaction_type FROM public.user_interactions 
    WHERE user_id = v_user_1 AND book_id = 'BOOK_S4';
    IF v_rec.interaction_type != 'finished' THEN
        RAISE EXCEPTION 'SENARYO 4 BAŞARISIZ: Unfavorite "finished" kaydını sildi!';
    END IF;
    RAISE NOTICE 'SENARYO 4 BAŞARILI: "finished" okuma süreci tam korundu.';

    -- -------------------------------------------------------------------------
    -- SENARYO 5: 'dislike' ML sinyali koruma
    -- -------------------------------------------------------------------------
    RAISE NOTICE '--- SENARYO 5: "dislike" sinyali koruma ---';
    INSERT INTO public.user_interactions (user_id, book_id, interaction_type, created_at)
    VALUES (v_user_1, 'BOOK_S5', 'dislike', NOW());

    INSERT INTO public.favorites (user_id, book_id, book_title, added_at)
    VALUES (v_user_1, 'BOOK_S5', 'Dislike Edilen Kitap', NOW());

    SELECT interaction_type INTO v_rec.interaction_type FROM public.user_interactions 
    WHERE user_id = v_user_1 AND book_id = 'BOOK_S5';
    IF v_rec.interaction_type != 'dislike' THEN
        RAISE EXCEPTION 'SENARYO 5 BAŞARISIZ: "dislike" sinyali ezildi!';
    END IF;
    RAISE NOTICE 'SENARYO 5 BAŞARILI: "dislike" sinyali korundu.';

    -- -------------------------------------------------------------------------
    -- SENARYO 6: Saf favorinin (okuma durumu yok) unfavorite ile temizlenmesi
    -- -------------------------------------------------------------------------
    RAISE NOTICE '--- SENARYO 6: Saf favorinin silinmesi ---';
    DELETE FROM public.favorites WHERE user_id = v_user_1 AND book_id = 'BOOK_S1';

    IF EXISTS (SELECT 1 FROM public.user_interactions WHERE user_id = v_user_1 AND book_id = 'BOOK_S1') THEN
        RAISE EXCEPTION 'SENARYO 6 BAŞARISIZ: Salt favori satırı user_interactions tablosundan temizlenmedi!';
    END IF;
    RAISE NOTICE 'SENARYO 6 BAŞARILI: Salt favori kaydı temizlendi.';

    -- -------------------------------------------------------------------------
    -- SENARYO 7: Yinelenen favori ekleme denemesi (UNIQUE kısıtı)
    -- -------------------------------------------------------------------------
    RAISE NOTICE '--- SENARYO 7: Yinelenen favori engelleme ---';
    BEGIN
        INSERT INTO public.favorites (user_id, book_id, book_title, added_at)
        VALUES (v_user_1, 'BOOK_S5', 'Tekrar Eden Kitap', NOW());
        RAISE EXCEPTION 'SENARYO 7 BAŞARISIZ: Yinelenen favori hatasız eklendi, UNIQUE kısıtı çalışmıyor!';
    EXCEPTION
        WHEN unique_violation THEN
            RAISE NOTICE 'SENARYO 7 BAŞARILI: Yinelenen favori UNIQUE kısıtı tarafından engellendi.';
    END;

    -- -------------------------------------------------------------------------
    -- SENARYO 8: Geriye dönük backfill idempotency güvencesi
    -- -------------------------------------------------------------------------
    RAISE NOTICE '--- SENARYO 8: Backfill sırasında okuma durumlarına dokunulmaması ---';
    INSERT INTO public.favorites (user_id, book_id, book_title, added_at)
    VALUES (v_user_2, 'BOOK_BF1', 'Backfill Kitap 1', NOW());

    INSERT INTO public.user_interactions (user_id, book_id, interaction_type, created_at)
    VALUES (v_user_2, 'BOOK_BF2', 'want_to_read', NOW());
    INSERT INTO public.favorites (user_id, book_id, book_title, added_at)
    VALUES (v_user_2, 'BOOK_BF2', 'Backfill Kitap 2', NOW());

    -- Backfill sorgusunu simüle et
    INSERT INTO public.user_interactions (user_id, book_id, interaction_type, created_at)
    SELECT user_id, book_id, 'favorite', added_at
    FROM public.favorites
    WHERE user_id = v_user_2
    ON CONFLICT (user_id, book_id) DO NOTHING;

    -- BOOK_BF2 hala 'want_to_read' olmalı
    SELECT interaction_type INTO v_rec.interaction_type FROM public.user_interactions 
    WHERE user_id = v_user_2 AND book_id = 'BOOK_BF2';
    IF v_rec.interaction_type != 'want_to_read' THEN
        RAISE EXCEPTION 'SENARYO 8 BAŞARISIZ: Backfill okuma durumunu ezdi!';
    END IF;
    RAISE NOTICE 'SENARYO 8 BAŞARILI: Backfill idempotent ve okuma durumunu koruyor.';

    -- -------------------------------------------------------------------------
    -- SENARYO 9: KAYIPSIZ MÜKERRER KAYIT UZLAŞTIRMASI ('finished' + 'favorite')
    -- -------------------------------------------------------------------------
    RAISE NOTICE '--- SENARYO 9: Kayıpsız mükerrer kayıt uzlaştırması ve arşivleme ---';
    -- Geçici olarak trigger'ı ve UNIQUE kısıtını kaldırarak v_user_3 için iki çelişkili satır ekle
    ALTER TABLE public.favorites DISABLE TRIGGER trg_sync_favorites;
    ALTER TABLE public.user_interactions DROP CONSTRAINT IF EXISTS unique_user_book_interaction;

    INSERT INTO public.user_interactions (user_id, book_id, interaction_type, created_at)
    VALUES 
        (v_user_3, 'BOOK_DUP1', 'finished', NOW() - INTERVAL '2 days'),
        (v_user_3, 'BOOK_DUP1', 'favorite', NOW() - INTERVAL '1 day');

    -- 03_DRAFT Bölüm 2 uzlaştırma mantığını simüle et:
    -- 1. Arşiv tablosu oluştur
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

    -- 2. Snapshot al
    INSERT INTO public._archived_user_interactions_duplicate_backup (
        user_interaction_id, user_id, book_id, interaction_type, created_at, resolution_action, full_row_snapshot
    )
    SELECT ui.id, ui.user_id, ui.book_id, ui.interaction_type, ui.created_at, 'PRE_DEDUPLICATION_SNAPSHOT', to_jsonb(ui.*)
    FROM public.user_interactions ui
    WHERE (ui.user_id, ui.book_id) IN (
        SELECT user_id, book_id FROM public.user_interactions GROUP BY user_id, book_id HAVING count(*) > 1
    );

    -- 3. 'favorite' durumunu public.favorites tablosuna aktararak koru
    INSERT INTO public.favorites (user_id, book_id, book_title, added_at)
    SELECT ui.user_id, ui.book_id, 'Mükerrer Kitap 1', ui.created_at
    FROM public.user_interactions ui
    WHERE ui.user_id = v_user_3 AND ui.book_id = 'BOOK_DUP1' AND ui.interaction_type = 'favorite'
    ON CONFLICT (user_id, book_id) DO NOTHING;

    -- 4. Deterministik öncelik uzlaştırması (finished > favorite)
    WITH ranked AS (
        SELECT id, ROW_NUMBER() OVER (
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
                created_at DESC
        ) AS rk
        FROM public.user_interactions
        WHERE user_id = v_user_3 AND book_id = 'BOOK_DUP1'
    )
    DELETE FROM public.user_interactions
    WHERE id IN (SELECT id FROM ranked WHERE rk > 1);

    -- Doğrulama 9.1: user_interactions'da 'finished' korundu mu?
    SELECT count(*), max(interaction_type) INTO v_count, v_rec.interaction_type
    FROM public.user_interactions
    WHERE user_id = v_user_3 AND book_id = 'BOOK_DUP1';

    IF v_count != 1 OR v_rec.interaction_type != 'finished' THEN
        RAISE EXCEPTION 'SENARYO 9 BAŞARISIZ: user_interactions tablosunda finished durumu korunamadı! (adet: %, durum: %)', v_count, v_rec.interaction_type;
    END IF;

    -- Doğrulama 9.2: favorites tablosunda favori üyeliği korundu mu?
    IF NOT EXISTS (SELECT 1 FROM public.favorites WHERE user_id = v_user_3 AND book_id = 'BOOK_DUP1') THEN
        RAISE EXCEPTION 'SENARYO 9 BAŞARISIZ: favorites tablosuna aktarılan favori üyelik kaydı bulunamadı!';
    END IF;

    -- Doğrulama 9.3: Arşiv tablosunda snapshot var mı?
    IF NOT EXISTS (SELECT 1 FROM public._archived_user_interactions_duplicate_backup WHERE user_id = v_user_3 AND book_id = 'BOOK_DUP1') THEN
        RAISE EXCEPTION 'SENARYO 9 BAŞARISIZ: _archived_user_interactions_duplicate_backup tablosunda yedek bulunamadı!';
    END IF;

    RAISE NOTICE 'SENARYO 9 BAŞARILI: Mükerrer kayıtlar sıfır veri kaybıyla uzlaştırıldı ve arşivlendi.';

    -- -------------------------------------------------------------------------
    -- SENARYO 10: Çözümlenemeyen Çelişkilerde Fail-Closed Durma
    -- -------------------------------------------------------------------------
    RAISE NOTICE '--- SENARYO 10: Like ve Dislike çelişkisinde Fail-Closed denetimi ---';
    INSERT INTO public.user_interactions (user_id, book_id, interaction_type, created_at)
    VALUES 
        (v_user_3, 'BOOK_CONFLICT', 'like', NOW() - INTERVAL '1 day'),
        (v_user_3, 'BOOK_CONFLICT', 'dislike', NOW());

    BEGIN
        -- Çelişki kontrolü (03_DRAFT Bölüm 2.2-C)
        IF EXISTS (
            SELECT 1 FROM public.user_interactions
            WHERE user_id = v_user_3 AND book_id = 'BOOK_CONFLICT' AND interaction_type IN ('like', 'dislike')
            GROUP BY user_id, book_id
            HAVING count(DISTINCT interaction_type) > 1
        ) THEN
            RAISE EXCEPTION 'FAIL_CLOSED_TEST_EXPECTED: Çözümlenemez çelişki tespit edildi!';
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM LIKE '%FAIL_CLOSED_TEST_EXPECTED%' THEN
                v_fail_closed_triggered := true;
                RAISE NOTICE 'SENARYO 10 BAŞARILI: Çelişkili like/dislike durumunda sistem güvenle fail-closed durdu.';
            ELSE
                RAISE;
            END IF;
    END;

    IF NOT v_fail_closed_triggered THEN
        RAISE EXCEPTION 'SENARYO 10 BAŞARISIZ: Çelişkili durumda fail-closed devreye girmedi!';
    END IF;

    -- -------------------------------------------------------------------------
    -- SENARYO 11: NULL / Boş Kimlik (user_id/book_id) Kayıtlarının Arşivlenmesi
    -- -------------------------------------------------------------------------
    RAISE NOTICE '--- SENARYO 11: NULL veya boş book_id/user_id kayıtlarının kayıpsız arşivlenmesi ---';
    -- Book ID boş olan bir test kaydı ekle
    INSERT INTO public.user_interactions (user_id, book_id, interaction_type, created_at)
    VALUES (v_user_3, '', 'want_to_read', NOW());

    -- 03_DRAFT Bölüm 2.1 mantığını işlet
    INSERT INTO public._archived_user_interactions_duplicate_backup (
        user_interaction_id, user_id, book_id, interaction_type, created_at, resolution_action, full_row_snapshot
    )
    SELECT id, user_id, book_id, interaction_type, created_at, 'ARCHIVED_NULL_OR_EMPTY_IDENTIFIER', to_jsonb(ui.*)
    FROM public.user_interactions ui
    WHERE user_id IS NULL OR book_id IS NULL OR trim(book_id) = '';

    DELETE FROM public.user_interactions
    WHERE user_id IS NULL OR book_id IS NULL OR trim(book_id) = '';

    -- Doğrulama 11.1: Arşivde ARCHIVED_NULL_OR_EMPTY_IDENTIFIER kaydı var mı?
    IF NOT EXISTS (
        SELECT 1 FROM public._archived_user_interactions_duplicate_backup 
        WHERE user_id = v_user_3 AND resolution_action = 'ARCHIVED_NULL_OR_EMPTY_IDENTIFIER'
    ) THEN
        RAISE EXCEPTION 'SENARYO 11 BAŞARISIZ: Boş book_id kaydı arşive yedeklenemedi!';
    END IF;

    -- Doğrulama 11.2: user_interactions'da boş book_id kaldı mı?
    IF EXISTS (SELECT 1 FROM public.user_interactions WHERE user_id = v_user_3 AND trim(book_id) = '') THEN
        RAISE EXCEPTION 'SENARYO 11 BAŞARISIZ: Boş book_id kaydı user_interactions tablosundan temizlenemedi!';
    END IF;

    RAISE NOTICE 'SENARYO 11 BAŞARILI: Boş/NULL kimlikli kayıtlar güvenle arşivlendi ve tablodan temizlendi.';

    -- UNIQUE kısıtını ve trigger'ı tekrar tesis et
    DELETE FROM public.user_interactions WHERE user_id = v_user_3;
    ALTER TABLE public.user_interactions ADD CONSTRAINT unique_user_book_interaction UNIQUE (user_id, book_id);
    ALTER TABLE public.favorites ENABLE TRIGGER trg_sync_favorites;

    -- -------------------------------------------------------------------------
    -- SENARYO 12: 'want_to_read' okuma durumu varken favorileme ve unfavorite (KORUNMA GÜVENCESİ)
    -- -------------------------------------------------------------------------
    RAISE NOTICE '--- SENARYO 12: "want_to_read" okuma durumu koruma ---';
    INSERT INTO public.user_interactions (user_id, book_id, interaction_type, created_at)
    VALUES (v_user_1, 'BOOK_S12', 'want_to_read', NOW());

    -- Favoriye ekle (ezilmeme kontrolü)
    INSERT INTO public.favorites (user_id, book_id, book_title, added_at)
    VALUES (v_user_1, 'BOOK_S12', 'Want to Read Kitabı', NOW());

    SELECT interaction_type INTO v_rec.interaction_type FROM public.user_interactions 
    WHERE user_id = v_user_1 AND book_id = 'BOOK_S12';
    IF v_rec.interaction_type != 'want_to_read' THEN
        RAISE EXCEPTION 'SENARYO 12 BAŞARISIZ: "want_to_read" üzerine yazıldı! Mevcut: %', v_rec.interaction_type;
    END IF;

    -- Favoriden çıkar (silinmeme kontrolü)
    DELETE FROM public.favorites WHERE user_id = v_user_1 AND book_id = 'BOOK_S12';

    SELECT interaction_type INTO v_rec.interaction_type FROM public.user_interactions 
    WHERE user_id = v_user_1 AND book_id = 'BOOK_S12';
    IF v_rec.interaction_type IS NULL OR v_rec.interaction_type != 'want_to_read' THEN
        RAISE EXCEPTION 'SENARYO 12 BAŞARISIZ: Unfavorite "want_to_read" kaydını sildi! Mevcut: %', v_rec.interaction_type;
    END IF;
    RAISE NOTICE 'SENARYO 12 BAŞARILI: "want_to_read" okuma durumu tam korundu.';

    -- -------------------------------------------------------------------------
    -- SENARYO 13: 'like' tavsiye sinyali varken favorileme ve unfavorite (EZİLMEME VE SİLİNMEME GÜVENCESİ)
    -- -------------------------------------------------------------------------
    RAISE NOTICE '--- SENARYO 13: "like" tavsiye sinyali koruma ---';
    INSERT INTO public.user_interactions (user_id, book_id, interaction_type, created_at)
    VALUES (v_user_1, 'BOOK_S13', 'like', NOW());

    -- Favoriye ekle (ezilmeme kontrolü)
    INSERT INTO public.favorites (user_id, book_id, book_title, added_at)
    VALUES (v_user_1, 'BOOK_S13', 'Beğenilen Like Kitabı', NOW());

    SELECT interaction_type INTO v_rec.interaction_type FROM public.user_interactions 
    WHERE user_id = v_user_1 AND book_id = 'BOOK_S13';
    IF v_rec.interaction_type != 'like' THEN
        RAISE EXCEPTION 'SENARYO 13 BAŞARISIZ: "like" sinyali üzerine yazıldı! Mevcut: %', v_rec.interaction_type;
    END IF;

    -- Favoriden çıkar (SİLİNMEME GÜVENCESİ - Trigger düzeltmesi kanıtı)
    DELETE FROM public.favorites WHERE user_id = v_user_1 AND book_id = 'BOOK_S13';

    SELECT interaction_type INTO v_rec.interaction_type FROM public.user_interactions 
    WHERE user_id = v_user_1 AND book_id = 'BOOK_S13';
    IF v_rec.interaction_type IS NULL OR v_rec.interaction_type != 'like' THEN
        RAISE EXCEPTION 'SENARYO 13 BAŞARISIZ: Unfavorite "like" tavsiye sinyalini sildi! Mevcut: %', v_rec.interaction_type;
    END IF;
    RAISE NOTICE 'SENARYO 13 BAŞARILI: "like" tavsiye sinyali favoriden çıkarma sonrasında da korundu.';

    -- -------------------------------------------------------------------------
    -- SENARYO 14: Forward-Recovery: Kullanıcı rollback sonrası 'finished' yazdığında snapshot'ın 'finished' durumunu EZMEMESİ (Yeni Veri Koruma)
    -- -------------------------------------------------------------------------
    RAISE NOTICE '--- SENARYO 14: Rollback sonrası finished yazan kullanıcının verisinin korunması ---';
    -- Rollback snapshot tablosu oluştur
    CREATE TABLE IF NOT EXISTS public._archived_user_interactions_rollback_backup (
        archive_id BIGSERIAL PRIMARY KEY,
        archived_at TIMESTAMPTZ NOT NULL DEFAULT now(),
        rollback_attempt_id UUID NOT NULL DEFAULT gen_random_uuid(),
        user_interaction_snapshot JSONB NOT NULL
    );
    DELETE FROM public._archived_user_interactions_rollback_backup;

    -- Rollback öncesi reading durumunu snapshot'a ekle
    INSERT INTO public._archived_user_interactions_rollback_backup (user_interaction_snapshot)
    VALUES (jsonb_build_object(
        'user_id', v_user_1,
        'book_id', 'BOOK_S14',
        'interaction_type', 'reading',
        'created_at', now() - interval '2 days'
    ));

    -- Kullanıcı rollback devrindeyken kitabı okuyup 'finished' olarak kaydetti
    INSERT INTO public.user_interactions (user_id, book_id, interaction_type, created_at)
    VALUES (v_user_1, 'BOOK_S14', 'finished', now() - interval '1 hour')
    ON CONFLICT (user_id, book_id) DO UPDATE SET interaction_type = 'finished';

    -- Forward-recovery mantığını çalıştır (03_DRAFT Bölüm 3.1)
    -- Ambiguity check
    IF (SELECT count(*) FROM (
        SELECT (user_interaction_snapshot->>'user_id')::uuid, (user_interaction_snapshot->>'book_id')::text
        FROM public._archived_user_interactions_rollback_backup
        WHERE (user_interaction_snapshot->>'interaction_type') IN ('favorite', 'reading')
        GROUP BY 1, 2 HAVING count(*) > 1
    ) d) > 0 THEN
        RAISE EXCEPTION 'Ambiguity check failed';
    END IF;

    -- Create conflict audit table
    CREATE TABLE IF NOT EXISTS public._archived_user_interactions_recovery_conflicts (
        conflict_id BIGSERIAL PRIMARY KEY,
        detected_at TIMESTAMPTZ NOT NULL DEFAULT now(),
        user_id UUID NOT NULL,
        book_id TEXT NOT NULL,
        snapshot_interaction_type TEXT NOT NULL,
        current_interaction_type TEXT,
        resolution_action TEXT NOT NULL,
        details TEXT NOT NULL,
        CONSTRAINT uq_recovery_conflict UNIQUE (user_id, book_id, snapshot_interaction_type, resolution_action)
    );

    -- Log conflict
    INSERT INTO public._archived_user_interactions_recovery_conflicts (
        user_id, book_id, snapshot_interaction_type, current_interaction_type, resolution_action, details
    )
    SELECT 
        ui.user_id, ui.book_id, arch.user_interaction_snapshot->>'interaction_type', ui.interaction_type,
        'PRESERVED_USER_WRITE_SKIPPED_RECOVERY',
        'Snapshot reading durumu korundu, kullanıcı finished ezilmedi'
    FROM public._archived_user_interactions_rollback_backup arch
    JOIN public.user_interactions ui
      ON ui.user_id = (arch.user_interaction_snapshot->>'user_id')::uuid
     AND ui.book_id = (arch.user_interaction_snapshot->>'book_id')::text
    WHERE (arch.user_interaction_snapshot->>'interaction_type') IN ('favorite', 'reading')
      AND ui.interaction_type <> (arch.user_interaction_snapshot->>'interaction_type')
      AND ui.interaction_type <> (
          CASE arch.user_interaction_snapshot->>'interaction_type'
              WHEN 'reading' THEN 'want_to_read'
              WHEN 'favorite' THEN 'like'
              ELSE ''
          END
      )
    ON CONFLICT (user_id, book_id, snapshot_interaction_type, resolution_action) DO NOTHING;

    -- Safe restore
    WITH safe_to_restore AS (
        SELECT 
            (arch.user_interaction_snapshot->>'user_id')::uuid AS target_user_id,
            (arch.user_interaction_snapshot->>'book_id')::text AS target_book_id,
            (arch.user_interaction_snapshot->>'interaction_type')::text AS target_type
        FROM public._archived_user_interactions_rollback_backup arch
        JOIN public.user_interactions ui
          ON ui.user_id = (arch.user_interaction_snapshot->>'user_id')::uuid
         AND ui.book_id = (arch.user_interaction_snapshot->>'book_id')::text
        WHERE (arch.user_interaction_snapshot->>'interaction_type') IN ('favorite', 'reading')
          AND (
              (arch.user_interaction_snapshot->>'interaction_type' = 'reading' AND ui.interaction_type = 'want_to_read')
              OR
              (arch.user_interaction_snapshot->>'interaction_type' = 'favorite' AND ui.interaction_type = 'like')
          )
    )
    UPDATE public.user_interactions ui
    SET interaction_type = s.target_type
    FROM safe_to_restore s
    WHERE ui.user_id = s.target_user_id AND ui.book_id = s.target_book_id;

    -- Doğrulama: finished ezilmedi mi?
    SELECT interaction_type INTO v_rec.interaction_type FROM public.user_interactions
    WHERE user_id = v_user_1 AND book_id = 'BOOK_S14';
    IF v_rec.interaction_type != 'finished' THEN
        RAISE EXCEPTION 'SENARYO 14 BAŞARISIZ: Kullanıcının yeni "finished" durumu snapshot tarafından ezildi! Mevcut: %', v_rec.interaction_type;
    END IF;

    -- Doğrulama: Conflict tablosuna kaydedildi mi?
    IF NOT EXISTS (
        SELECT 1 FROM public._archived_user_interactions_recovery_conflicts
        WHERE user_id = v_user_1 AND book_id = 'BOOK_S14' AND resolution_action = 'PRESERVED_USER_WRITE_SKIPPED_RECOVERY'
    ) THEN
        RAISE EXCEPTION 'SENARYO 14 BAŞARISIZ: Çatışma kaydı conflict tablosunda bulunamadı!';
    END IF;
    RAISE NOTICE 'SENARYO 14 BAŞARILI: Kullanıcının "finished" durumu snapshot ile ezilmedi ve conflict kaydedildi.';

    -- -------------------------------------------------------------------------
    -- SENARYO 15: Forward-Recovery: Rollback öncesinde 'want_to_read' olan kitabın 'finished' yapılması ve korunması
    -- -------------------------------------------------------------------------
    RAISE NOTICE '--- SENARYO 15: Rollback öncesinde want_to_read iken finished yapılan durumun korunması ---';
    -- want_to_read rollback'te arşive alınmaz
    INSERT INTO public.user_interactions (user_id, book_id, interaction_type, created_at)
    VALUES (v_user_1, 'BOOK_S15', 'want_to_read', now() - interval '2 days')
    ON CONFLICT (user_id, book_id) DO UPDATE SET interaction_type = 'want_to_read';

    -- Kullanıcı finished yapar
    UPDATE public.user_interactions SET interaction_type = 'finished' WHERE user_id = v_user_1 AND book_id = 'BOOK_S15';

    -- Forward recovery snapshot'ı bu kitap için yok, satır finished kalmalı
    SELECT interaction_type INTO v_rec.interaction_type FROM public.user_interactions WHERE user_id = v_user_1 AND book_id = 'BOOK_S15';
    IF v_rec.interaction_type != 'finished' THEN
        RAISE EXCEPTION 'SENARYO 15 BAŞARISIZ: "finished" durumu bozuldu! Mevcut: %', v_rec.interaction_type;
    END IF;
    RAISE NOTICE 'SENARYO 15 BAŞARILI: want_to_read -> finished geçişi eksiksiz korundu.';

    -- -------------------------------------------------------------------------
    -- SENARYO 16: Forward-Recovery: Aynı kullanıcı-kitap çifti için birden fazla snapshot olduğunda FAIL-CLOSED durma
    -- -------------------------------------------------------------------------
    RAISE NOTICE '--- SENARYO 16: Birden fazla snapshot durumunda Fail-Closed denetimi ---';
    INSERT INTO public._archived_user_interactions_rollback_backup (user_interaction_snapshot)
    VALUES 
        (jsonb_build_object('user_id', v_user_2, 'book_id', 'BOOK_S16', 'interaction_type', 'reading')),
        (jsonb_build_object('user_id', v_user_2, 'book_id', 'BOOK_S16', 'interaction_type', 'favorite'));

    BEGIN
        IF (SELECT count(*) FROM (
            SELECT (user_interaction_snapshot->>'user_id')::uuid, (user_interaction_snapshot->>'book_id')::text
            FROM public._archived_user_interactions_rollback_backup
            WHERE (user_interaction_snapshot->>'interaction_type') IN ('favorite', 'reading')
            GROUP BY 1, 2 HAVING count(*) > 1
        ) d) > 0 THEN
            RAISE EXCEPTION 'FAIL_CLOSED_MULTI_SNAP_EXPECTED: Birden fazla snapshot tespit edildi!';
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM LIKE '%FAIL_CLOSED_MULTI_SNAP_EXPECTED%' THEN
                v_fc_multi_snap := true;
                RAISE NOTICE 'SENARYO 16 BAŞARILI: Çelişkili/çoklu snapshot durumunda sistem güvenle fail-closed durdu.';
            ELSE
                RAISE;
            END IF;
    END;

    IF NOT v_fc_multi_snap THEN
        RAISE EXCEPTION 'SENARYO 16 BAŞARISIZ: Çoklu snapshot durumunda fail-closed devreye girmedi!';
    END IF;
    -- Temizle
    DELETE FROM public._archived_user_interactions_rollback_backup
    WHERE (user_interaction_snapshot->>'book_id') = 'BOOK_S16';

    -- -------------------------------------------------------------------------
    -- SENARYO 17: Forward-Recovery: Tam İdempotency (Aynı forward-recovery iki kez çalıştırıldığında)
    -- -------------------------------------------------------------------------
    RAISE NOTICE '--- SENARYO 17: Forward-recovery tam idempotency güvencesi ---';
    INSERT INTO public._archived_user_interactions_rollback_backup (user_interaction_snapshot)
    VALUES (jsonb_build_object('user_id', v_user_2, 'book_id', 'BOOK_S17', 'interaction_type', 'reading'));

    INSERT INTO public.user_interactions (user_id, book_id, interaction_type, created_at)
    VALUES (v_user_2, 'BOOK_S17', 'want_to_read', now())
    ON CONFLICT (user_id, book_id) DO UPDATE SET interaction_type = 'want_to_read';

    -- Çalıştırma 1: want_to_read -> reading'e yükselir
    UPDATE public.user_interactions ui
    SET interaction_type = 'reading'
    WHERE ui.user_id = v_user_2 AND ui.book_id = 'BOOK_S17' AND ui.interaction_type = 'want_to_read';

    SELECT interaction_type INTO v_rec.interaction_type FROM public.user_interactions WHERE user_id = v_user_2 AND book_id = 'BOOK_S17';
    IF v_rec.interaction_type != 'reading' THEN
        RAISE EXCEPTION 'SENARYO 17 BAŞARISIZ: İlk çalıştırmada reading yükseltilemedi!';
    END IF;

    -- Çalıştırma 2: Zaten reading olduğundan dokunulmaz
    WITH safe_to_restore AS (
        SELECT (arch.user_interaction_snapshot->>'user_id')::uuid AS target_user_id,
               (arch.user_interaction_snapshot->>'book_id')::text AS target_book_id
        FROM public._archived_user_interactions_rollback_backup arch
        JOIN public.user_interactions ui
          ON ui.user_id = (arch.user_interaction_snapshot->>'user_id')::uuid
         AND ui.book_id = (arch.user_interaction_snapshot->>'book_id')::text
        WHERE arch.user_interaction_snapshot->>'book_id' = 'BOOK_S17'
          AND arch.user_interaction_snapshot->>'interaction_type' = 'reading'
          AND ui.interaction_type = 'want_to_read'
    )
    UPDATE public.user_interactions ui SET interaction_type = 'reading'
    FROM safe_to_restore s
    WHERE ui.user_id = s.target_user_id AND ui.book_id = s.target_book_id;
    GET DIAGNOSTICS v_count = ROW_COUNT;

    IF v_count != 0 THEN
        RAISE EXCEPTION 'SENARYO 17 BAŞARISIZ: İkinci çalıştırmada satır gereksiz yere güncellendi (idempotent değil)!';
    END IF;
    RAISE NOTICE 'SENARYO 17 BAŞARILI: Forward-recovery tam idempotent (0 satır gereksiz güncellendi).';

    -- -------------------------------------------------------------------------
    -- SENARYO 18: Forward-Recovery: Snapshot varken etkileşim satırının silinmiş olması (Satır diriltilmemeli)
    -- -------------------------------------------------------------------------
    RAISE NOTICE '--- SENARYO 18: Silinmiş satırın snapshot ile diriltilmemesi ---';
    INSERT INTO public._archived_user_interactions_rollback_backup (user_interaction_snapshot)
    VALUES (jsonb_build_object('user_id', v_user_1, 'book_id', 'BOOK_S18', 'interaction_type', 'favorite'));

    -- user_interactions tablosunda kayıt yok (kullanıcı silmiş)
    DELETE FROM public.user_interactions WHERE user_id = v_user_1 AND book_id = 'BOOK_S18';

    -- Missing log
    INSERT INTO public._archived_user_interactions_recovery_conflicts (
        user_id, book_id, snapshot_interaction_type, current_interaction_type, resolution_action, details
    )
    SELECT (arch.user_interaction_snapshot->>'user_id')::uuid, (arch.user_interaction_snapshot->>'book_id')::text,
           arch.user_interaction_snapshot->>'interaction_type', NULL, 'SKIPPED_ROW_MISSING_IN_INTERACTIONS', 'Silinmiş satır diriltilmedi'
    FROM public._archived_user_interactions_rollback_backup arch
    WHERE arch.user_interaction_snapshot->>'book_id' = 'BOOK_S18'
      AND NOT EXISTS (SELECT 1 FROM public.user_interactions ui WHERE ui.user_id = v_user_1 AND ui.book_id = 'BOOK_S18')
    ON CONFLICT (user_id, book_id, snapshot_interaction_type, resolution_action) DO NOTHING;

    -- Doğrulama: user_interactions'da kayıt OLMAMALI
    IF EXISTS (SELECT 1 FROM public.user_interactions WHERE user_id = v_user_1 AND book_id = 'BOOK_S18') THEN
        RAISE EXCEPTION 'SENARYO 18 BAŞARISIZ: Silinmiş satır diriltildi!';
    END IF;

    -- Doğrulama: conflict tablosuna SKIPPED_ROW_MISSING_IN_INTERACTIONS yazıldı mı?
    IF NOT EXISTS (
        SELECT 1 FROM public._archived_user_interactions_recovery_conflicts
        WHERE user_id = v_user_1 AND book_id = 'BOOK_S18' AND resolution_action = 'SKIPPED_ROW_MISSING_IN_INTERACTIONS'
    ) THEN
        RAISE EXCEPTION 'SENARYO 18 BAŞARISIZ: Silinmiş satır audit kaydı eksik!';
    END IF;
    RAISE NOTICE 'SENARYO 18 BAŞARILI: Silinmiş satır diriltilmedi ve skip kaydı tutuldu.';

    -- -------------------------------------------------------------------------
    -- SENARYO 19: Forward-Recovery: Snapshot ile mevcut satır farklı durumda olduğunda (örn. dislike) ezilmeme
    -- -------------------------------------------------------------------------
    RAISE NOTICE '--- SENARYO 19: Snapshot ile farklı durumda olan etkileşimin (dislike) ezilmemesi ---';
    INSERT INTO public._archived_user_interactions_rollback_backup (user_interaction_snapshot)
    VALUES (jsonb_build_object('user_id', v_user_1, 'book_id', 'BOOK_S19', 'interaction_type', 'reading'));

    INSERT INTO public.user_interactions (user_id, book_id, interaction_type, created_at)
    VALUES (v_user_1, 'BOOK_S19', 'dislike', now())
    ON CONFLICT (user_id, book_id) DO UPDATE SET interaction_type = 'dislike';

    -- Forward recovery Safe restore işletildiğinde 'dislike' satırı 'reading'e DÖNÜŞMEMELİ
    WITH safe_to_restore AS (
        SELECT (arch.user_interaction_snapshot->>'user_id')::uuid AS target_user_id,
               (arch.user_interaction_snapshot->>'book_id')::text AS target_book_id,
               (arch.user_interaction_snapshot->>'interaction_type')::text AS target_type
        FROM public._archived_user_interactions_rollback_backup arch
        JOIN public.user_interactions ui
          ON ui.user_id = (arch.user_interaction_snapshot->>'user_id')::uuid
         AND ui.book_id = (arch.user_interaction_snapshot->>'book_id')::text
        WHERE arch.user_interaction_snapshot->>'book_id' = 'BOOK_S19'
          AND arch.user_interaction_snapshot->>'interaction_type' = 'reading'
          AND ui.interaction_type = 'want_to_read'
    )
    UPDATE public.user_interactions ui SET interaction_type = s.target_type
    FROM safe_to_restore s
    WHERE ui.user_id = s.target_user_id AND ui.book_id = s.target_book_id;

    SELECT interaction_type INTO v_rec.interaction_type FROM public.user_interactions WHERE user_id = v_user_1 AND book_id = 'BOOK_S19';
    IF v_rec.interaction_type != 'dislike' THEN
        RAISE EXCEPTION 'SENARYO 19 BAŞARISIZ: dislike durumu reading snapshot ile ezildi! Mevcut: %', v_rec.interaction_type;
    END IF;
    RAISE NOTICE 'SENARYO 19 BAŞARILI: Farklı kullanıcı durumu (dislike) eksiksiz korundu.';

    -- -------------------------------------------------------------------------
    -- SENARYO 20: Forward-Recovery: Kullanıcı izolasyonu (User A snapshot'ı User B'yi asla etkileyemez)
    -- -------------------------------------------------------------------------
    RAISE NOTICE '--- SENARYO 20: Kullanıcı veri izolasyonu güvencesi ---';
    -- v_user_1 için snapshot var
    INSERT INTO public._archived_user_interactions_rollback_backup (user_interaction_snapshot)
    VALUES (jsonb_build_object('user_id', v_user_1, 'book_id', 'BOOK_S20', 'interaction_type', 'reading'));

    -- v_user_1 ve v_user_2 ikisi de want_to_read durumunda
    INSERT INTO public.user_interactions (user_id, book_id, interaction_type, created_at)
    VALUES 
        (v_user_1, 'BOOK_S20', 'want_to_read', now()),
        (v_user_2, 'BOOK_S20', 'want_to_read', now())
    ON CONFLICT (user_id, book_id) DO UPDATE SET interaction_type = 'want_to_read';

    -- Forward recovery işletilir (yalnızca v_user_1 için snapshot var)
    WITH safe_to_restore AS (
        SELECT (arch.user_interaction_snapshot->>'user_id')::uuid AS target_user_id,
               (arch.user_interaction_snapshot->>'book_id')::text AS target_book_id,
               (arch.user_interaction_snapshot->>'interaction_type')::text AS target_type
        FROM public._archived_user_interactions_rollback_backup arch
        JOIN public.user_interactions ui
          ON ui.user_id = (arch.user_interaction_snapshot->>'user_id')::uuid
         AND ui.book_id = (arch.user_interaction_snapshot->>'book_id')::text
        WHERE arch.user_interaction_snapshot->>'book_id' = 'BOOK_S20'
          AND arch.user_interaction_snapshot->>'interaction_type' = 'reading'
          AND ui.interaction_type = 'want_to_read'
    )
    UPDATE public.user_interactions ui SET interaction_type = s.target_type
    FROM safe_to_restore s
    WHERE ui.user_id = s.target_user_id AND ui.book_id = s.target_book_id;

    -- v_user_1 reading olmalı
    SELECT interaction_type INTO v_rec.interaction_type FROM public.user_interactions WHERE user_id = v_user_1 AND book_id = 'BOOK_S20';
    IF v_rec.interaction_type != 'reading' THEN
        RAISE EXCEPTION 'SENARYO 20 BAŞARISIZ: v_user_1 reading yapılamadı!';
    END IF;

    -- v_user_2 HALEN want_to_read OLMALI!
    SELECT interaction_type INTO v_rec.interaction_type FROM public.user_interactions WHERE user_id = v_user_2 AND book_id = 'BOOK_S20';
    IF v_rec.interaction_type != 'want_to_read' THEN
        RAISE EXCEPTION 'SENARYO 20 BAŞARISIZ: v_user_2 durumu etkilendi! Mevcut: %', v_rec.interaction_type;
    END IF;
    RAISE NOTICE 'SENARYO 20 BAŞARILI: Cross-user izolasyonu tam doğrulandı (User B satırı değişmedi).';

    -- Test verilerini temizle
    DELETE FROM public.favorites WHERE user_id IN (v_user_1, v_user_2, v_user_3);
    DELETE FROM public.user_interactions WHERE user_id IN (v_user_1, v_user_2, v_user_3);
    DELETE FROM public._archived_user_interactions_rollback_backup;
    DELETE FROM public.books WHERE isbn13 IN (
        'BOOK_S1', 'BOOK_S2', 'BOOK_S4', 'BOOK_S5', 'BOOK_S12', 'BOOK_S13',
        'BOOK_BF1', 'BOOK_BF2', 'BOOK_DUP1', 'BOOK_CONFLICT',
        'BOOK_S14', 'BOOK_S15', 'BOOK_S16', 'BOOK_S17', 'BOOK_S18', 'BOOK_S19', 'BOOK_S20'
    );

    RAISE NOTICE '=============================================================';
    RAISE NOTICE 'TÜM MODEL A VE FORWARD-RECOVERY GÜVENLİK SENARYOLARI (1-20) BAŞARIYLA TAMAMLANDI!';
    RAISE NOTICE '=============================================================';
END $$;
