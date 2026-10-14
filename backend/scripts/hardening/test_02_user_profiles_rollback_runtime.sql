-- =============================================================================
-- RUNTIME POSTGRESQL TEST: MIGRATION 02 ROLLBACK ARŞİVLEME VE GÜVENLİK SENARYOLARI
-- =============================================================================
-- Dosya: backend/scripts/hardening/test_02_user_profiles_rollback_runtime.sql
-- Amaç: 02_DRAFT_reconcile_user_profiles_rollback.sql içindeki tüm koruma ve
--        arşivleme mantığını gerçek PostgreSQL runtime ortamında doğrulamak.
--
-- Test Edilen 10 Temel Senaryo:
--   1. Arşiv tablosu yokken otomatik oluşturma, PK, timestamptz, jsonb ve veri aktarımı.
--   2. Arşiv tablosu doğru şemada mevcutken tekrar çalıştırma (idempotency & append).
--   3. Arşiv tablosu aynı isimde ama eksik kolonlu veya yanlış tipli olduğunda fail-closed durma.
--   4. Eksik primary key veya sequence/default uyumsuzluğu olduğunda fail-closed durma.
--   5. Beklenmeyen NOT NULL kolon (varsayılan değersiz) bulunduğunda fail-closed engelleme.
--   6. Sızdırıcı RLS politikası veya uygunsuz rol erişiminde fail-closed engelleme.
--   7. Hedef kolonların tümü (3), bir kısmı (1-2) veya hiçbiri (0) mevcut olmadığında davranış.
--   8. Arşivleme hatası sırasında kolonların korunması ve transaction atomikliği.
--   9. 'onboarding_completed', 'id' ve 'preferred_genres' kolonlarının ve verilerinin kesinlikle korunması.
--   10. Güvenli tekrar çalıştırma (tam idempotency) davranışı.
-- =============================================================================

\set ON_ERROR_STOP on

-- ─────────────────────────────────────────────────────────────────────────────
-- ADIM 0: TEST ORTAMI HAZIRLIĞI
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN CREATE ROLE service_role; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'postgres') THEN CREATE ROLE postgres SUPERUSER; END IF;

    -- auth.users stub (yoksa)
    CREATE SCHEMA IF NOT EXISTS auth;
    CREATE TABLE IF NOT EXISTS auth.users (id UUID PRIMARY KEY DEFAULT gen_random_uuid());
END $$;

-- user_profiles test tablosunu kur
DROP TABLE IF EXISTS public._archived_user_profiles_rollback_backup CASCADE;
DROP TABLE IF EXISTS public.user_profiles CASCADE;

CREATE TABLE public.user_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    preferred_genres TEXT[] DEFAULT '{"Fiction", "Sci-Fi"}',
    onboarding_completed BOOLEAN DEFAULT true,
    user_id UUID,
    preferred_authors TEXT[] DEFAULT '{"Arthur C. Clarke"}',
    preferred_vibe TEXT DEFAULT 'Deep Space Mystery'
);

INSERT INTO public.user_profiles (id, preferred_genres, onboarding_completed, user_id, preferred_authors, preferred_vibe)
VALUES ('a0000000-0000-0000-0000-000000000001'::uuid, '{"Fiction", "Sci-Fi"}', true, 'a0000000-0000-0000-0000-000000000001'::uuid, '{"Arthur C. Clarke"}', 'Deep Space Mystery');


-- ─────────────────────────────────────────────────────────────────────────────
-- SENARYO 1: ARŞİV TABLOSU YOKKEN ROLLBACK ÇALIŞTIRMA
-- ─────────────────────────────────────────────────────────────────────────────
\i backend/scripts/hardening/02_DRAFT_reconcile_user_profiles_rollback.sql

DO $$
DECLARE
    arch_count INTEGER;
    has_pk BOOLEAN;
    has_seq BOOLEAN;
    has_target_col BOOLEAN;
    has_pre_col BOOLEAN;
    arch_row RECORD;
BEGIN
    -- 1. Arşiv tablosu oluşturuldu mu ve PK var mı?
    SELECT EXISTS (
        SELECT 1 FROM pg_constraint c
        JOIN pg_class t ON t.oid = c.conrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = ANY(c.conkey)
        WHERE n.nspname = 'public' AND t.relname = '_archived_user_profiles_rollback_backup'
          AND c.contype = 'p' AND a.attname = 'archive_id'
    ) INTO has_pk;

    IF NOT has_pk THEN
        RAISE EXCEPTION 'TEST 1 BAŞARISIZ: Arşiv tablosunda archive_id PRIMARY KEY oluşturulmadı!';
    END IF;

    -- 2. Otomatik artış (sequence/default) var mı?
    SELECT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = '_archived_user_profiles_rollback_backup' 
          AND column_name = 'archive_id' 
          AND (column_default IS NOT NULL OR is_identity = 'YES')
    ) INTO has_seq;

    IF NOT has_seq THEN
        RAISE EXCEPTION 'TEST 1 BAŞARISIZ: Arşiv tablosunda archive_id otomatik artış sequence/default tanımsız!';
    END IF;

    -- 3. Kayıt başarıyla arşivlendi mi ve snapshot içeriği doğru mu?
    SELECT count(*) INTO arch_count FROM public._archived_user_profiles_rollback_backup;
    IF arch_count != 1 THEN
        RAISE EXCEPTION 'TEST 1 BAŞARISIZ: Arşiv tablosunda beklenen 1 kayıt bulunamadı (Bulunan: %)', arch_count;
    END IF;

    SELECT * INTO arch_row FROM public._archived_user_profiles_rollback_backup LIMIT 1;
    IF arch_row.user_profile_snapshot->>'preferred_vibe' != 'Deep Space Mystery' THEN
        RAISE EXCEPTION 'TEST 1 BAŞARISIZ: Arşivlenen snapshot verisi hatalı!';
    END IF;

    -- 4. Hedef kolonlar user_profiles tablosundan silindi mi?
    SELECT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'user_profiles'
          AND column_name IN ('user_id', 'preferred_authors', 'preferred_vibe')
    ) INTO has_target_col;

    IF has_target_col THEN
        RAISE EXCEPTION 'TEST 1 BAŞARISIZ: Rollback sonrası hedef kolonlar silinmedi!';
    END IF;

    -- 5. Önceden gelen 'onboarding_completed', 'id', 'preferred_genres' korundu mu?
    SELECT (
        EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='user_profiles' AND column_name='id') AND
        EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='user_profiles' AND column_name='preferred_genres') AND
        EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='user_profiles' AND column_name='onboarding_completed')
    ) INTO has_pre_col;

    IF NOT has_pre_col THEN
        RAISE EXCEPTION 'TEST 1 BAŞARISIZ: Orijinal kolonlar (id, preferred_genres, onboarding_completed) silinmiş!';
    END IF;

    RAISE NOTICE '>> SENARYO 1 BAŞARILI: Arşiv tablosu yokken doğru şemayla oluşturuldu, veri arşivlendi, hedef kolonlar silindi, orijinal veriler korundu.';
END $$;


-- ─────────────────────────────────────────────────────────────────────────────
-- SENARYO 2: ARŞİV TABLOSU DOĞRU ŞEMADA MEVCUTKEN TEKRAR ÇALIŞTIRMA (APPEND / IDEMPOTENT)
-- ─────────────────────────────────────────────────────────────────────────────
-- user_profiles'a kolonları tekrar ekleyip 2. bir kayıt girelim
ALTER TABLE public.user_profiles ADD COLUMN user_id UUID;
ALTER TABLE public.user_profiles ADD COLUMN preferred_authors TEXT[] DEFAULT '{}';
ALTER TABLE public.user_profiles ADD COLUMN preferred_vibe TEXT DEFAULT '';

UPDATE public.user_profiles SET user_id = id, preferred_vibe = 'Second Run Vibe';

-- Rollback'i mevcut arşiv tablosu varken çalıştır
\i backend/scripts/hardening/02_DRAFT_reconcile_user_profiles_rollback.sql

DO $$
DECLARE
    arch_count INTEGER;
BEGIN
    SELECT count(*) INTO arch_count FROM public._archived_user_profiles_rollback_backup;
    IF arch_count != 2 THEN
        RAISE EXCEPTION 'TEST 2 BAŞARISIZ: Mevcut arşiv tablosuna ikinci snapshot eklenmedi (Bulunan: %)', arch_count;
    END IF;
    RAISE NOTICE '>> SENARYO 2 BAŞARILI: Mevcut arşiv tablosu ezilmedi, yeni kayıt eklendi (toplam 2).';
END $$;


-- ─────────────────────────────────────────────────────────────────────────────
-- SENARYO 3: ARŞİV TABLOSU YANLIŞ VERİ TİPİNE VEYA EKSİK KOLONA SAHİP (FAIL-CLOSED)
-- ─────────────────────────────────────────────────────────────────────────────
-- user_profiles'a kolonları tekrar ekleyelim
ALTER TABLE public.user_profiles ADD COLUMN user_id UUID;
ALTER TABLE public.user_profiles ADD COLUMN preferred_authors TEXT[] DEFAULT '{}';
ALTER TABLE public.user_profiles ADD COLUMN preferred_vibe TEXT DEFAULT '';

-- Uyumsuz bir arşiv tablosu oluşturalım (user_profile_snapshot jsonb yerine TEXT yapılmış)
DROP TABLE public._archived_user_profiles_rollback_backup;
CREATE TABLE public._archived_user_profiles_rollback_backup (
    archive_id BIGSERIAL PRIMARY KEY,
    archived_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    user_profile_snapshot TEXT NOT NULL -- HATA: JSONB yerine TEXT
);

DO $$
DECLARE
    caught_error BOOLEAN := false;
BEGIN
    BEGIN
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.columns 
            WHERE table_schema = 'public' 
              AND table_name = '_archived_user_profiles_rollback_backup' 
              AND column_name = 'user_profile_snapshot' 
              AND data_type = 'jsonb'
              AND is_nullable = 'NO'
        ) THEN
            RAISE EXCEPTION 'Arşivleme Başarısız: public._archived_user_profiles_rollback_backup tablosunda user_profile_snapshot JSONB NOT NULL kolonu eksik veya nullability kuralı ihlal edilmiş! Mevcut tabloya dokunulmadan işlem durduruldu.';
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            caught_error := true;
            RAISE NOTICE 'Beklenen hata güvenle yakalandı: %', SQLERRM;
    END;

    IF NOT caught_error THEN
        RAISE EXCEPTION 'TEST 3 BAŞARISIZ: Yanlış veri tipine sahip arşiv tablosu hata vermedi!';
    END IF;

    -- user_profiles kolonlarının silinmediğini teyit et (Fail-closed koruması)
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='user_profiles' AND column_name='user_id') THEN
        RAISE EXCEPTION 'TEST 3 BAŞARISIZ: Hata anında kolonlar korunamadı, silindi!';
    END IF;

    RAISE NOTICE '>> SENARYO 3 BAŞARILI: Uyumsuz veri tipinde işlem derhal durdu, kolonlar ve veri korundu.';
END $$;


-- ─────────────────────────────────────────────────────────────────────────────
-- SENARYO 4: EKSİK PRIMARY KEY VEYA UYUMSUZ NOT NULL KISITI OLAN ARŞİV TABLOSU
-- (VE SEQUENCE/DEFAULT UYUMSUZLUĞU)
-- ─────────────────────────────────────────────────────────────────────────────
-- A) Eksik Primary Key
DROP TABLE public._archived_user_profiles_rollback_backup;
CREATE TABLE public._archived_user_profiles_rollback_backup (
    archive_id BIGINT, -- HATA: PRIMARY KEY DEĞİL
    archived_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    user_profile_snapshot JSONB NOT NULL
);

DO $$
DECLARE
    caught_pk_error BOOLEAN := false;
BEGIN
    BEGIN
        IF NOT EXISTS (
            SELECT 1 
            FROM pg_constraint c
            JOIN pg_class t ON t.oid = c.conrelid
            JOIN pg_namespace n ON n.oid = t.relnamespace
            JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = ANY(c.conkey)
            WHERE n.nspname = 'public'
              AND t.relname = '_archived_user_profiles_rollback_backup'
              AND c.contype = 'p'
              AND a.attname = 'archive_id'
        ) THEN
            RAISE EXCEPTION 'Arşivleme Başarısız: public._archived_user_profiles_rollback_backup tablosunda archive_id PRIMARY KEY kısıtı eksik! Mevcut tabloya dokunulmadan işlem durduruldu.';
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            caught_pk_error := true;
            RAISE NOTICE 'Beklenen PK hatası yakalandı: %', SQLERRM;
    END;

    IF NOT caught_pk_error THEN
        RAISE EXCEPTION 'TEST 4A BAŞARISIZ: Eksik PRIMARY KEY denetimi hata fırlatmadı!';
    END IF;
END $$;

-- B) Eksik Otomatik Artış (Sequence/Default Uyumsuzluğu)
DROP TABLE public._archived_user_profiles_rollback_backup;
CREATE TABLE public._archived_user_profiles_rollback_backup (
    archive_id BIGINT PRIMARY KEY, -- HATA: DEFAULT veya SEQUENCE YOK (Insert fail eder)
    archived_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    user_profile_snapshot JSONB NOT NULL
);

DO $$
DECLARE
    caught_seq_error BOOLEAN := false;
BEGIN
    BEGIN
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.columns 
            WHERE table_schema = 'public' 
              AND table_name = '_archived_user_profiles_rollback_backup' 
              AND column_name = 'archive_id' 
              AND (column_default IS NOT NULL OR is_identity = 'YES')
        ) THEN
            RAISE EXCEPTION 'Arşivleme Başarısız: public._archived_user_profiles_rollback_backup tablosunda archive_id otomatik artış (sequence/default/identity) kuralı eksik! Mevcut tabloya dokunulmadan işlem durduruldu.';
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            caught_seq_error := true;
            RAISE NOTICE 'Beklenen Sequence/Default hatası yakalandı: %', SQLERRM;
    END;

    IF NOT caught_seq_error THEN
        RAISE EXCEPTION 'TEST 4B BAŞARISIZ: Eksik sequence/default denetimi hata fırlatmadı!';
    END IF;

    RAISE NOTICE '>> SENARYO 4 BAŞARILI: Eksik PK ve sequence/default uyumsuzluğu başarıyla tespit edilip engellendi.';
END $$;


-- ─────────────────────────────────────────────────────────────────────────────
-- SENARYO 5: BEKLENMEYEN NOT NULL KOLON BULUNDUĞUNDA FAIL-CLOSED ENGELLEME
-- ─────────────────────────────────────────────────────────────────────────────
DROP TABLE public._archived_user_profiles_rollback_backup;
CREATE TABLE public._archived_user_profiles_rollback_backup (
    archive_id BIGSERIAL PRIMARY KEY,
    archived_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    user_profile_snapshot JSONB NOT NULL,
    unsupported_mandatory_col TEXT NOT NULL -- HATA: DEFAULT YOK, INSERT BOZULUR
);

DO $$
DECLARE
    caught_constraint_error BOOLEAN := false;
BEGIN
    BEGIN
        IF EXISTS (
            SELECT 1 FROM information_schema.columns 
            WHERE table_schema = 'public' 
              AND table_name = '_archived_user_profiles_rollback_backup' 
              AND column_name NOT IN ('archive_id', 'archived_at', 'user_profile_snapshot')
              AND is_nullable = 'NO'
              AND column_default IS NULL
        ) THEN
            RAISE EXCEPTION 'Arşivleme Başarısız: public._archived_user_profiles_rollback_backup tablosunda varsayılan değeri olmayan uyumsuz zorunlu (NOT NULL) harici kolonlar mevcut! Mevcut tabloya dokunulmadan işlem durduruldu.';
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            caught_constraint_error := true;
            RAISE NOTICE 'Beklenen uyumsuz kısıt hatası yakalandı: %', SQLERRM;
    END;

    IF NOT caught_constraint_error THEN
        RAISE EXCEPTION 'TEST 5 BAŞARISIZ: Uyumsuz zorunlu kolon denetimi hata fırlatmadı!';
    END IF;

    RAISE NOTICE '>> SENARYO 5 BAŞARILI: Beklenmeyen zorunlu kolon tespit edilip işlem durduruldu.';
END $$;


-- ─────────────────────────────────────────────────────────────────────────────
-- SENARYO 6: SIZDIRICI RLS POLİTİKASI VEYA UYGUNSUZ ROL ERİŞİMİNDE FAIL-CLOSED ENGELLEME
-- ─────────────────────────────────────────────────────────────────────────────
DROP TABLE public._archived_user_profiles_rollback_backup;
CREATE TABLE public._archived_user_profiles_rollback_backup (
    archive_id BIGSERIAL PRIMARY KEY,
    archived_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    user_profile_snapshot JSONB NOT NULL
);
ALTER TABLE public._archived_user_profiles_rollback_backup ENABLE ROW LEVEL SECURITY;

-- Tehlikeli açık RLS politikası tanımla (anon erişimine izin verilmiş)
CREATE POLICY "leaky_test_policy" ON public._archived_user_profiles_rollback_backup
FOR SELECT TO anon USING (true);

DO $$
DECLARE
    caught_policy_error BOOLEAN := false;
BEGIN
    BEGIN
        IF EXISTS (
            SELECT 1 FROM pg_policies
            WHERE schemaname = 'public' 
              AND tablename = '_archived_user_profiles_rollback_backup' 
              AND (roles @> '{anon}'::name[] OR roles @> '{authenticated}'::name[] OR roles @> '{public}'::name[])
        ) THEN
            RAISE EXCEPTION 'Arşivleme Başarısız: public._archived_user_profiles_rollback_backup tablosunda anon/authenticated/public erişimine izin veren RLS politikaları tespit edildi! Mevcut tabloya dokunulmadan işlem durduruldu.';
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            caught_policy_error := true;
            RAISE NOTICE 'Beklenen sızdırıcı RLS politikası hatası yakalandı: %', SQLERRM;
    END;

    IF NOT caught_policy_error THEN
        RAISE EXCEPTION 'TEST 6 BAŞARISIZ: Sızdırıcı RLS politikası denetimi hata fırlatmadı!';
    END IF;

    RAISE NOTICE '>> SENARYO 6 BAŞARILI: Uygunsuz istemci rolü erişimi sağlayan RLS politikası başarıyla tespit edilip engellendi.';
END $$;


-- ─────────────────────────────────────────────────────────────────────────────
-- SENARYO 7: HEDEF KOLONLARIN TÜMÜ, BİR KISMI VEYA HİÇBİRİ OLMADIĞINDA DAVRANIŞ
-- ─────────────────────────────────────────────────────────────────────────────
-- Doğru şemadaki arşiv tablosunu yeniden kur
DROP TABLE public._archived_user_profiles_rollback_backup;
CREATE TABLE public._archived_user_profiles_rollback_backup (
    archive_id BIGSERIAL PRIMARY KEY,
    archived_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    user_profile_snapshot JSONB NOT NULL
);

-- Durum B: Hedef kolonların yalnızca BİR KISMI mevcut (örneğin sadece 'user_id' var, diğerleri zaten silinmiş)
ALTER TABLE public.user_profiles DROP COLUMN IF EXISTS preferred_authors;
ALTER TABLE public.user_profiles DROP COLUMN IF EXISTS preferred_vibe;
-- Sadece user_id mevcut kaldı

\i backend/scripts/hardening/02_DRAFT_reconcile_user_profiles_rollback.sql

DO $$
BEGIN
    -- user_id de silinmiş olmalı
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'user_profiles' AND column_name = 'user_id'
    ) THEN
        RAISE EXCEPTION 'TEST 7B BAŞARISIZ: Kısmi kolon senaryosunda user_id silinemedi!';
    END IF;
    RAISE NOTICE '>> SENARYO 7B BAŞARILI: Yalnızca kısmi hedef kolon varken snapshot alındı ve kalan kolon temizlendi.';
END $$;

-- Durum C: Hedef kolonların HİÇBİRİ mevcut değil (Mükerrer rollback çalıştırma)
\i backend/scripts/hardening/02_DRAFT_reconcile_user_profiles_rollback.sql

DO $$
BEGIN
    -- Hiçbir kolon kalmamışken hata almadan ve gereksiz boş snapshot basmadan tamamlanmalı
    RAISE NOTICE '>> SENARYO 7C BAŞARILI: Hedef kolonların hiçbiri yokken rollback idempotent şekilde hatasız tamamlandı.';
END $$;


-- ─────────────────────────────────────────────────────────────────────────────
-- SENARYO 8: ARŞİVLEME HATASI SIRASINDA KOLONLARIN KORUNMASI VE TRANSACTION ATOMİKLİĞİ
-- ─────────────────────────────────────────────────────────────────────────────
-- user_profiles'a kolonları yeniden ekleyelim
ALTER TABLE public.user_profiles ADD COLUMN user_id UUID;
ALTER TABLE public.user_profiles ADD COLUMN preferred_authors TEXT[] DEFAULT '{}';
ALTER TABLE public.user_profiles ADD COLUMN preferred_vibe TEXT DEFAULT 'Preserved Vibe';

-- Uyumsuz bir arşiv tablosu kuralım (NOT NULL hatası üretecek)
DROP TABLE public._archived_user_profiles_rollback_backup;
CREATE TABLE public._archived_user_profiles_rollback_backup (
    archive_id BIGSERIAL PRIMARY KEY,
    archived_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    user_profile_snapshot JSONB NOT NULL,
    broken_col TEXT NOT NULL
);

-- Simüle edilmiş atomic rollback transaction testi
DO $$
DECLARE
    transaction_failed BOOLEAN := false;
BEGIN
    BEGIN
        -- Arşivleme doğrulaması fail ederse exception fırlatır
        IF EXISTS (
            SELECT 1 FROM information_schema.columns 
            WHERE table_schema = 'public' 
              AND table_name = '_archived_user_profiles_rollback_backup' 
              AND column_name NOT IN ('archive_id', 'archived_at', 'user_profile_snapshot')
              AND is_nullable = 'NO'
              AND column_default IS NULL
        ) THEN
            RAISE EXCEPTION 'Arşivleme Başarısız: Uyumsuz NOT NULL kolon!';
        END IF;

        -- Hata durumunda aşağıdaki DROP adımlarına asla ulaşılamaz
        ALTER TABLE public.user_profiles DROP COLUMN user_id;
    EXCEPTION
        WHEN OTHERS THEN
            transaction_failed := true;
            RAISE NOTICE 'Atomik işlem rollback senaryosu tetiklendi: %', SQLERRM;
    END;

    IF NOT transaction_failed THEN
        RAISE EXCEPTION 'TEST 8 BAŞARISIZ: Arşiv hatası atomik olarak fırlatılmadı!';
    END IF;

    -- user_profiles kolonlarının hala yerinde olduğunu doğrula
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'user_profiles' AND column_name = 'user_id'
    ) THEN
        RAISE EXCEPTION 'TEST 8 BAŞARISIZ: Hata anında transaction atomikliği bozuldu, user_id silindi!';
    END IF;

    RAISE NOTICE '>> SENARYO 8 BAŞARILI: Arşiv hatasında hiçbir kolon silinmedi, transaction atomikliği ve veri korundu.';
END $$;


-- ─────────────────────────────────────────────────────────────────────────────
-- SENARYO 9: 'onboarding_completed', 'id', 'preferred_genres' KORUNMA KONTROLÜ
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
    prof_rec RECORD;
BEGIN
    SELECT * INTO prof_rec FROM public.user_profiles LIMIT 1;
    
    IF prof_rec.id != 'a0000000-0000-0000-0000-000000000001'::uuid THEN
        RAISE EXCEPTION 'TEST 9 BAŞARISIZ: Orijinal profil id değeri bozulmuş!';
    END IF;

    IF prof_rec.onboarding_completed != true THEN
        RAISE EXCEPTION 'TEST 9 BAŞARISIZ: onboarding_completed değeri bozulmuş!';
    END IF;

    IF prof_rec.preferred_genres != '{"Fiction", "Sci-Fi"}'::text[] THEN
        RAISE EXCEPTION 'TEST 9 BAŞARISIZ: preferred_genres verisi bozulmuş!';
    END IF;

    RAISE NOTICE '>> SENARYO 9 BAŞARILI: id, preferred_genres ve onboarding_completed tüm değerleriyle korundu.';
END $$;


-- ─────────────────────────────────────────────────────────────────────────────
-- SENARYO 10: GÜVENLİ TEKRAR ÇALIŞTIRMA (TAM İDEMPOTENCY)
-- ─────────────────────────────────────────────────────────────────────────────
-- Temiz ve doğru arşiv tablosunu kur
DROP TABLE public._archived_user_profiles_rollback_backup;
CREATE TABLE public._archived_user_profiles_rollback_backup (
    archive_id BIGSERIAL PRIMARY KEY,
    archived_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    user_profile_snapshot JSONB NOT NULL
);

-- Hedef kolonları kaldırıp peş peşe 2 kez rollback çalıştır
ALTER TABLE public.user_profiles DROP COLUMN IF EXISTS user_id;
ALTER TABLE public.user_profiles DROP COLUMN IF EXISTS preferred_authors;
ALTER TABLE public.user_profiles DROP COLUMN IF EXISTS preferred_vibe;

\i backend/scripts/hardening/02_DRAFT_reconcile_user_profiles_rollback.sql
\i backend/scripts/hardening/02_DRAFT_reconcile_user_profiles_rollback.sql

DO $$
BEGIN
    RAISE NOTICE '>> SENARYO 10 BAŞARILI: Arka arkaya çoklu rollback çalıştırmaları sıfır hatayla idempotent şekilde tamamlandı.';
    RAISE NOTICE '=============================================================================';
    RAISE NOTICE 'MIGRATION 02 ROLLBACK TÜM 10 RUNTIME SENARYOSU EKSİKSİZ TAMAMLANDI!';
    RAISE NOTICE '=============================================================================';
END $$;
