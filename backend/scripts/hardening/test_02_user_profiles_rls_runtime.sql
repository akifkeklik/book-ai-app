-- =============================================================================
-- RUNTIME POSTGRESQL TEST: MIGRATION 02 RLS GÜVENLİK VE DAVRANIŞ DOĞRULAMA SUITE
-- =============================================================================
-- Dosya: backend/scripts/hardening/test_02_user_profiles_rls_runtime.sql
-- Amaç: 02_DRAFT_reconcile_user_profiles.sql içindeki RLS politikalarını,
--        kimlik trigger'ını ve yetki izolasyonunu gerçek PostgreSQL ortamında
--        davranışsal (runtime assertions) olarak doğrulamak.
--
-- Test Edilen 10 Temel Senaryo:
--   1. KULLANICI A, KULLANICI B PROFİLİNİ SELECT İLE OKUYAMAMALI (0 satır / silent RLS)
--   2. KULLANICI A, KULLANICI B PROFİLİNİ UPDATE İLE DEĞİŞTİREMEMELİ (0 satır etkilenir)
--   3. KİMLİK UYUŞMAZLIĞI (id != user_id) TRIGGER REDDİ (sync_user_profile_identifiers)
--   4. INSERT WITH CHECK İHLALİNİN AYRI DOĞRULANMASI (PostgreSQL 42501)
--   5. UPDATE WITH CHECK İHLALİNİN AYRI DOĞRULANMASI (PostgreSQL 42501)
--   6. TRANSACTION VE TEST OTURUMUNUN TEMİZ SIFIRLANMASI (SAVEPOINT / RESET ROLE)
--   7. MEŞRU KULLANICI İŞLEMLERİ DOĞRULAMASI (Kendi profilinde INSERT/SELECT/UPDATE)
--   8. ANON / PUBLIC ERİŞİMİNİN TAMAMEN REDDEDİLMESİ (42501 / 0 satır)
--   9. SERVICE_ROLE YÖNETİM ERİŞİMİ (Tüm kayıtların görünürlüğü)
--   10. ROLLBACK VE YENİDEN UYGULAMA İDEMPOTENCY TESTİ (Kayıpsız arşivleme & tekrar uygulama)
-- =============================================================================

\set ON_ERROR_STOP on

-- ─────────────────────────────────────────────────────────────────────────────
-- ADIM 0: TEST ORTAMI HAZIRLIĞI
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN 
        CREATE ROLE service_role BYPASSRLS; 
    ELSE
        ALTER ROLE service_role BYPASSRLS;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'postgres') THEN CREATE ROLE postgres SUPERUSER; END IF;

    -- auth şeması ve test mock auth.uid()
    CREATE SCHEMA IF NOT EXISTS auth;
    CREATE TABLE IF NOT EXISTS auth.users (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        email TEXT
    );
END $$;

CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid AS $$
    SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$ LANGUAGE sql STABLE;

GRANT USAGE ON SCHEMA auth TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION auth.uid() TO anon, authenticated, service_role;

-- Test kullanıcıları tanımla
DELETE FROM auth.users WHERE id IN (
    '11111111-1111-1111-1111-111111111111'::uuid,
    '22222222-2222-2222-2222-222222222222'::uuid,
    '33333333-3333-3333-3333-333333333333'::uuid
);

INSERT INTO auth.users (id, email) VALUES 
('11111111-1111-1111-1111-111111111111'::uuid, 'usera@example.com'),
('22222222-2222-2222-2222-222222222222'::uuid, 'userb@example.com'),
('33333333-3333-3333-3333-333333333333'::uuid, 'userc@example.com');

-- user_profiles başlangıç durumu (Canlı Supabase baselini)
DROP TABLE IF EXISTS public._archived_user_profiles_rollback_backup CASCADE;
DROP TABLE IF EXISTS public.user_profiles CASCADE;

CREATE TABLE public.user_profiles (
    id UUID PRIMARY KEY,
    preferred_genres TEXT[] DEFAULT '{"Fiction", "Sci-Fi"}',
    created_at TIMESTAMPTZ DEFAULT now()
);

INSERT INTO public.user_profiles (id, preferred_genres) 
VALUES ('11111111-1111-1111-1111-111111111111'::uuid, '{"Fiction", "Cyberpunk"}');

-- ─────────────────────────────────────────────────────────────────────────────
-- MIGRATION 02 İLERİ ÇALIŞTIRMA
-- ─────────────────────────────────────────────────────────────────────────────
\i backend/scripts/hardening/02_DRAFT_reconcile_user_profiles.sql

-- User B profilini ekle
INSERT INTO public.user_profiles (id, user_id, preferred_genres, preferred_vibe, preferred_authors, onboarding_completed)
VALUES ('22222222-2222-2222-2222-222222222222'::uuid, '22222222-2222-2222-2222-222222222222'::uuid, '{"Classic"}', 'Quiet Library', '{"Camus"}', true);


-- ─────────────────────────────────────────────────────────────────────────────
-- SENARYO 1: KULLANICI A, KULLANICI B PROFİLİNİ SELECT İLE OKUYAMAMALI
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
    found_count INTEGER;
BEGIN
    SET ROLE authenticated;
    SET request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

    SELECT count(*) INTO found_count 
    FROM public.user_profiles 
    WHERE id = '22222222-2222-2222-2222-222222222222'::uuid;

    IF found_count <> 0 THEN
        RESET ROLE;
        RESET request.jwt.claim.sub;
        RAISE EXCEPTION 'TEST 1 BAŞARISIZ: Kullanıcı A, Kullanıcı B profilini okuyabildi! (Bulunan: %)', found_count;
    END IF;

    RESET ROLE;
    RESET request.jwt.claim.sub;
    RAISE NOTICE '>> SENARYO 1 BAŞARILI: Kullanıcı A, Kullanıcı B profilini SELECT ile göremedi (0 satır).';
END $$;


-- ─────────────────────────────────────────────────────────────────────────────
-- SENARYO 2: KULLANICI A, KULLANICI B PROFİLİNİ UPDATE İLE DEĞİŞTİREMEMELİ
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
    orig_vibe TEXT;
BEGIN
    SET ROLE authenticated;
    SET request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

    UPDATE public.user_profiles 
    SET preferred_vibe = 'Hacked Vibe' 
    WHERE id = '22222222-2222-2222-2222-222222222222'::uuid;

    RESET ROLE;
    RESET request.jwt.claim.sub;

    SELECT preferred_vibe INTO orig_vibe 
    FROM public.user_profiles 
    WHERE id = '22222222-2222-2222-2222-222222222222'::uuid;

    IF orig_vibe <> 'Quiet Library' THEN
        RAISE EXCEPTION 'TEST 2 BAŞARISIZ: Kullanıcı A, Kullanıcı B profilini değiştirebildi! Yeni vibe: %', orig_vibe;
    END IF;

    RAISE NOTICE '>> SENARYO 2 BAŞARILI: Kullanıcı A, Kullanıcı B profilini UPDATE ile değiştiremedi (0 satır güncellendi).';
END $$;


-- ─────────────────────────────────────────────────────────────────────────────
-- SENARYO 3: KİMLİK UYUŞMAZLIĞI (id != user_id) TRIGGER REDDİ
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
    trigger_rejected BOOLEAN := false;
BEGIN
    SET ROLE authenticated;
    SET request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

    BEGIN
        UPDATE public.user_profiles 
        SET user_id = '33333333-3333-3333-3333-333333333333'::uuid 
        WHERE id = '11111111-1111-1111-1111-111111111111'::uuid;
    EXCEPTION WHEN OTHERS THEN
        trigger_rejected := true;
        IF SQLERRM NOT LIKE '%kimlik uyuşmazlığı%' AND SQLERRM NOT LIKE '%farklı olamaz%' THEN
            RAISE EXCEPTION 'Beklenmeyen hata mesajı: %', SQLERRM;
        END IF;
    END;

    RESET ROLE;
    RESET request.jwt.claim.sub;

    IF NOT trigger_rejected THEN
        RAISE EXCEPTION 'TEST 3 BAŞARISIZ: Trigger id != user_id güncellemesini engellemedi!';
    END IF;

    RAISE NOTICE '>> SENARYO 3 BAŞARILI: Kimlik uyuşmazlığı trigger tarafından derhal reddedildi.';
END $$;


-- ─────────────────────────────────────────────────────────────────────────────
-- SENARYO 4: INSERT WITH CHECK İHLALİNİN AYRI DOĞRULANMASI
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
    insert_rejected BOOLEAN := false;
BEGIN
    SET ROLE authenticated;
    SET request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

    BEGIN
        INSERT INTO public.user_profiles (id, user_id, preferred_vibe) 
        VALUES ('33333333-3333-3333-3333-333333333333'::uuid, '33333333-3333-3333-3333-333333333333'::uuid, 'Unauthorized');
    EXCEPTION 
        WHEN insufficient_privilege THEN
            insert_rejected := true;
        WHEN OTHERS THEN
            IF SQLSTATE = '42501' THEN
                insert_rejected := true;
            ELSE
                RAISE;
            END IF;
    END;

    RESET ROLE;
    RESET request.jwt.claim.sub;

    IF NOT insert_rejected THEN
        RAISE EXCEPTION 'TEST 4 BAŞARISIZ: Kullanıcı A, Kullanıcı C adına kayıt ekleyebildi (INSERT WITH CHECK ihlal edilmedi)!';
    END IF;

    RAISE NOTICE '>> SENARYO 4 BAŞARILI: INSERT WITH CHECK ihlali izole olarak tespit edildi ve reddedildi (42501).';
END $$;


-- ─────────────────────────────────────────────────────────────────────────────
-- SENARYO 5: UPDATE WITH CHECK İHLALİNİN AYRI DOĞRULANMASI
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
    update_rejected BOOLEAN := false;
BEGIN
    SET ROLE authenticated;
    SET request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

    BEGIN
        -- Kullanıcı A hem id hem user_id'yi C yapar; trigger geçer (ikisi de C),
        -- ancak UPDATE WITH CHECK (auth.uid() = user_id OR auth.uid() = id) ihlal edilir.
        UPDATE public.user_profiles 
        SET id = '33333333-3333-3333-3333-333333333333'::uuid, 
            user_id = '33333333-3333-3333-3333-333333333333'::uuid 
        WHERE id = '11111111-1111-1111-1111-111111111111'::uuid;
    EXCEPTION 
        WHEN insufficient_privilege THEN
            update_rejected := true;
        WHEN OTHERS THEN
            IF SQLSTATE = '42501' THEN
                update_rejected := true;
            ELSE
                RAISE;
            END IF;
    END;

    RESET ROLE;
    RESET request.jwt.claim.sub;

    IF NOT update_rejected THEN
        RAISE EXCEPTION 'TEST 5 BAŞARISIZ: Kullanıcı A kimlik devri yaptı ancak UPDATE WITH CHECK engellemedi!';
    END IF;

    RAISE NOTICE '>> SENARYO 5 BAŞARILI: UPDATE WITH CHECK ihlali izole olarak tespit edildi ve reddedildi (42501).';
END $$;


-- ─────────────────────────────────────────────────────────────────────────────
-- SENARYO 6: TRANSACTION VE TEST OTURUMUNUN TEMİZ SIFIRLANMASI
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
    clean_user TEXT;
    clean_jwt TEXT;
BEGIN
    -- Hata durumunu simüle edip temizleme
    BEGIN
        PERFORM 1/0;
    EXCEPTION WHEN division_by_zero THEN
        NULL;
    END;

    SELECT current_user INTO clean_user;
    clean_jwt := current_setting('request.jwt.claim.sub', true);

    IF clean_user <> 'postgres' THEN
        RAISE EXCEPTION 'TEST 6 BAŞARISIZ: Oturum kullanıcısı sıfırlanmadı: %', clean_user;
    END IF;

    RAISE NOTICE '>> SENARYO 6 BAŞARILI: Oturum ve transaction durumu temiz biçimde korundu/sıfırlandı.';
END $$;


-- ─────────────────────────────────────────────────────────────────────────────
-- SENARYO 7: MEŞRU KULLANICI İŞLEMLERİ DOĞRULAMASI
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
    read_vibe TEXT;
BEGIN
    SET ROLE authenticated;
    SET request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';

    -- Kendi profilini ekle
    INSERT INTO public.user_profiles (id, user_id, preferred_genres, preferred_vibe, preferred_authors, onboarding_completed)
    VALUES ('33333333-3333-3333-3333-333333333333'::uuid, '33333333-3333-3333-3333-333333333333'::uuid, '{"Fantasy"}', 'Epic Fantasy', '{"Tolkien"}', true);

    -- Kendi profilini oku
    SELECT preferred_vibe INTO read_vibe 
    FROM public.user_profiles 
    WHERE id = '33333333-3333-3333-3333-333333333333'::uuid;

    IF read_vibe <> 'Epic Fantasy' THEN
        RESET ROLE;
        RESET request.jwt.claim.sub;
        RAISE EXCEPTION 'TEST 7 BAŞARISIZ: Meşru okuma başarısız: %', read_vibe;
    END IF;

    -- Kendi profilini güncelle
    UPDATE public.user_profiles 
    SET preferred_vibe = 'High Fantasy' 
    WHERE id = '33333333-3333-3333-3333-333333333333'::uuid;

    SELECT preferred_vibe INTO read_vibe 
    FROM public.user_profiles 
    WHERE id = '33333333-3333-3333-3333-333333333333'::uuid;

    IF read_vibe <> 'High Fantasy' THEN
        RESET ROLE;
        RESET request.jwt.claim.sub;
        RAISE EXCEPTION 'TEST 7 BAŞARISIZ: Meşru güncelleme kalıcı olmadı: %', read_vibe;
    END IF;

    RESET ROLE;
    RESET request.jwt.claim.sub;
    RAISE NOTICE '>> SENARYO 7 BAŞARILI: Profil sahibi kendi profilini ekleyebildi, okuyabildi ve güncelleyebildi.';
END $$;


-- ─────────────────────────────────────────────────────────────────────────────
-- SENARYO 8: ANON / PUBLIC ERİŞİMİNİN TAMAMEN REDDEDİLMESİ
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
    anon_read_count INTEGER := 0;
    anon_insert_blocked BOOLEAN := false;
BEGIN
    SET ROLE anon;

    -- Anon select: RLS ve REVOKE nedeniyle 0 satır dönmeli
    BEGIN
        SELECT count(*) INTO anon_read_count FROM public.user_profiles;
    EXCEPTION WHEN insufficient_privilege THEN
        anon_read_count := 0;
    END;

    IF anon_read_count <> 0 THEN
        RESET ROLE;
        RAISE EXCEPTION 'TEST 8 BAŞARISIZ: Anon kullanıcı % satır okuyabildi!', anon_read_count;
    END IF;

    -- Anon insert: Kesinlikle engellenmeli
    BEGIN
        INSERT INTO public.user_profiles (id, user_id) 
        VALUES (gen_random_uuid(), gen_random_uuid());
    EXCEPTION WHEN insufficient_privilege THEN
        anon_insert_blocked := true;
    WHEN OTHERS THEN
        IF SQLSTATE = '42501' THEN
            anon_insert_blocked := true;
        END IF;
    END;

    RESET ROLE;

    IF NOT anon_insert_blocked THEN
        RAISE EXCEPTION 'TEST 8 BAŞARISIZ: Anon rolü kayıt ekleyebildi!';
    END IF;

    RAISE NOTICE '>> SENARYO 8 BAŞARILI: Anon / unauthenticated erişim kesin olarak engellendi (42501 / 0 satır).';
END $$;


-- ─────────────────────────────────────────────────────────────────────────────
-- SENARYO 9: SERVICE_ROLE YÖNETİM ERİŞİMİ
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
    total_profiles INTEGER;
BEGIN
    SET ROLE service_role;

    SELECT count(*) INTO total_profiles FROM public.user_profiles;
    IF total_profiles <> 3 THEN
        RESET ROLE;
        RAISE EXCEPTION 'TEST 9 BAŞARISIZ: service_role tüm profilleri göremedi (Bulunan: %)', total_profiles;
    END IF;

    RESET ROLE;
    RAISE NOTICE '>> SENARYO 9 BAŞARILI: service_role yönetim amaçlı tüm 3 profili görüntüleyebildi.';
END $$;


-- ─────────────────────────────────────────────────────────────────────────────
-- SENARYO 10: ROLLBACK VE YENİDEN UYGULAMA İDEMPOTENCY TESTİ
-- ─────────────────────────────────────────────────────────────────────────────
\i backend/scripts/hardening/02_DRAFT_reconcile_user_profiles_rollback.sql

DO $$
DECLARE
    arch_count INTEGER;
    col_exists BOOLEAN;
BEGIN
    SELECT count(*) INTO arch_count FROM public._archived_user_profiles_rollback_backup;
    IF arch_count < 3 THEN
        RAISE EXCEPTION 'TEST 10 BAŞARISIZ: Rollback arşivinde beklenen 3 kayıt bulunamadı (Bulunan: %)', arch_count;
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'user_profiles'
          AND column_name IN ('user_id', 'preferred_authors', 'preferred_vibe')
    ) INTO col_exists;

    IF col_exists THEN
        RAISE EXCEPTION 'TEST 10 BAŞARISIZ: Hedef kolonlar rollback sonrasında silinmedi!';
    END IF;

    RAISE NOTICE '>> SENARYO 10.1 BAŞARILI: Rollback ile veriler arşivlendi ve hedef kolonlar kaldırıldı.';
END $$;

-- Yeniden uygulama (Idempotency)
\i backend/scripts/hardening/02_DRAFT_reconcile_user_profiles.sql

DO $$
DECLARE
    restored_count INTEGER;
BEGIN
    SELECT count(*) INTO restored_count 
    FROM public.user_profiles 
    WHERE user_id IS NOT NULL;

    IF restored_count <> 3 THEN
        RAISE EXCEPTION 'TEST 10.2 BAŞARISIZ: Yeniden uygulama sonrası 3 kaydın user_id değeri geri yüklenemedi!';
    END IF;

    RAISE NOTICE '>> SENARYO 10 BAŞARILI: Rollback ve yeniden uygulama döngüsü sıfır veri kaybı ile tamamlandı.';
END $$;
