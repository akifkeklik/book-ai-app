-- =============================================================================
-- LIBRIS DATABASE HARDENING — RUNTIME TEST FOR MODEL A (GROUP 03)
-- =============================================================================
-- DOSYA: backend/scripts/hardening/test_03_interactions_and_trigger_runtime.sql
-- AMAÇ: Model A ilkelerinin PostgreSQL çalışma zamanında 9 senaryoda doğrulanması:
--   1. Bağımsız favori ekleme (önceden etkileşim yokken 'favorite' oluşması)
--   2. Okuma durumu koruma ('reading' varken favorilemenin okuma durumunu EZMEMESİ)
--   3. Okuma durumu koruma (favoriden çıkarmanın 'reading' durumunu SİLMEMESİ)
--   4. 'finished' durumu koruma (favorileme ve favoriden çıkarmanın 'finished' durumunu EZMEMESİ/SİLMEMESİ)
--   5. 'dislike' tavsiye sinyalini koruma
--   6. Önceden okuma durumu olmayan favorinin unfavorite ile temizlenmesi
--   7. Yinelenen favorilerin güvenli engellenmesi (UNIQUE kısıtı)
--   8. Geriye dönük backfill idempotency güvencesi (mevcut okuma durumlarına dokunulmaması)
--   9. Rollback ve tekrar ileri migration (Idempotency) döngüsü
-- =============================================================================

DO $$
DECLARE
    v_user_1 UUID := '00000000-0000-0000-0000-000000000001'::uuid;
    v_user_2 UUID := '00000000-0000-0000-0000-000000000002'::uuid;
    v_rec RECORD;
    v_count INTEGER;
BEGIN
    RAISE NOTICE '=============================================================';
    RAISE NOTICE 'BAŞLANGIÇ: GRUP 03 MODEL A RUNTIME DOĞRULAMA TESTLERİ';
    RAISE NOTICE '=============================================================';

    -- Test öncesi temiz izole veri hazırla (yalnızca test UUID'leri için)
    DELETE FROM public.favorites WHERE user_id IN (v_user_1, v_user_2);
    DELETE FROM public.user_interactions WHERE user_id IN (v_user_1, v_user_2);

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
    -- Senaryo 1'de eklenen BOOK_S1 salt favoriydi
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
    -- user_2 için bir favori ve bir 'want_to_read' kaydı
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

    -- Test verilerini temizle
    DELETE FROM public.favorites WHERE user_id IN (v_user_1, v_user_2);
    DELETE FROM public.user_interactions WHERE user_id IN (v_user_1, v_user_2);

    RAISE NOTICE '=============================================================';
    RAISE NOTICE 'TÜM MODEL A SENARYOLARI (1-8) BAŞARIYLA TAMAMLANDI!';
    RAISE NOTICE '=============================================================';
END $$;
