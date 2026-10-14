-- =============================================================================
-- [DRAFT / NOT FOR IMMEDIATE EXECUTION]
-- ROLLBACK: GRUP 2 `user_profiles` AŞAMALI UYUMLULUK GERİ ALMA
-- =============================================================================
-- Dosya: backend/scripts/hardening/02_DRAFT_reconcile_user_profiles_rollback.sql
-- Amaç: 02_DRAFT_reconcile_user_profiles.sql ile kurulan aşamalı uyumluluk
--        yapısını kaldırıp orijinal 'id' bazlı tekil duruma geri dönmek.
-- 
-- VERİ KAYBI UYARISI:
-- Rollback çalıştırıldığında 'user_id', 'preferred_authors' ve 'preferred_vibe'
-- kolonları tablodan kaldırılırsa, bu kolonlara migration sonrası yazılmış yeni veriler
-- silinir. Orijinal 'id' ve 'preferred_genres' verileri korunur.
-- =============================================================================

BEGIN;

-- 1. Senkronizasyon Trigger'ını ve Fonksiyonunu Kaldır
DROP TRIGGER IF EXISTS trg_sync_user_profile_identifiers ON public.user_profiles;
DROP FUNCTION IF EXISTS public.sync_user_profile_identifiers();

-- 2. UNIQUE İndeksi Kaldır
DROP INDEX IF EXISTS public.idx_user_profiles_user_id;

-- 3. Politikaları Orijinal 'id' Şekline Döndür
DROP POLICY IF EXISTS "Users can view their own profile" ON public.user_profiles;
DROP POLICY IF EXISTS "Users can insert their own profile" ON public.user_profiles;
DROP POLICY IF EXISTS "Users can update their own profile" ON public.user_profiles;
DROP POLICY IF EXISTS "Enable all for users based on id" ON public.user_profiles;

CREATE POLICY "Enable all for users based on id" 
ON public.user_profiles FOR ALL 
USING (auth.uid() = id) 
WITH CHECK (auth.uid() = id);

-- 4. GERİ ALINAMAYACAK KULLANICI VERİLERİNİ GÜVENLİ VE TEKRAR ÇALIŞTIRILABİLİR ŞEKİLDE ARŞİVLE
-- Risk Analizi:
--   - Önceden oluşturulmuş arşiv tablosu uyumsuz şemaya sahipse sessizce kabul edilmemeli veya ezilmemelidir.
--   - Arşivleme kararı yalnızca tek bir kolona bağlanmamalı; 'user_id', 'preferred_authors' veya 'preferred_vibe'
--     kolonlarından herhangi biri mevcutsa veri korunmalıdır.
--   - RLS ve yetki kısıtı ile hassas profil verilerinin istemcilere sızması engellenmelidir.
DO $$
DECLARE
    has_target_columns BOOLEAN;
    current_count INTEGER;
BEGIN
    -- 1. Arşiv tablosu tam şema, kısıt ve güvenlik doğrulaması / oluşturulması
    IF EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name = '_archived_user_profiles_rollback_backup'
    ) THEN
        -- A) 'archive_id' kolonu ve tamsayı veri tipi (bigint/integer) denetimi
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.columns 
            WHERE table_schema = 'public' 
              AND table_name = '_archived_user_profiles_rollback_backup' 
              AND column_name = 'archive_id' 
              AND data_type IN ('bigint', 'integer')
        ) THEN
            RAISE EXCEPTION 'Arşivleme Başarısız: public._archived_user_profiles_rollback_backup tablosunda archive_id kolonu eksik veya veri tipi uyumsuz (bigint/integer bekleniyor)! Mevcut tabloya dokunulmadan işlem durduruldu.';
        END IF;

        -- B) 'archive_id' üzerinde PRIMARY KEY kısıtı denetimi
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

        -- B.1) 'archive_id' otomatik artış (sequence / default / identity) denetimi
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.columns 
            WHERE table_schema = 'public' 
              AND table_name = '_archived_user_profiles_rollback_backup' 
              AND column_name = 'archive_id' 
              AND (column_default IS NOT NULL OR is_identity = 'YES')
        ) THEN
            RAISE EXCEPTION 'Arşivleme Başarısız: public._archived_user_profiles_rollback_backup tablosunda archive_id otomatik artış (sequence/default/identity) kuralı eksik! Mevcut tabloya dokunulmadan işlem durduruldu.';
        END IF;

        -- C) 'archived_at' kolonu ve timestamp veri tipi denetimi
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.columns 
            WHERE table_schema = 'public' 
              AND table_name = '_archived_user_profiles_rollback_backup' 
              AND column_name = 'archived_at' 
              AND data_type IN ('timestamp with time zone', 'timestamp without time zone')
        ) THEN
            RAISE EXCEPTION 'Arşivleme Başarısız: public._archived_user_profiles_rollback_backup tablosunda archived_at kolonu eksik veya veri tipi uyumsuz! Mevcut tabloya dokunulmadan işlem durduruldu.';
        END IF;

        -- D) 'user_profile_snapshot' kolonu, JSONB veri tipi ve NOT NULL kısıtı denetimi
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

        -- E) İnsert işlemini bozacak varsayılan değersiz zorunlu (NOT NULL without DEFAULT) harici kolon denetimi
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

        -- F) Yetkisiz istemci erişimi sağlayan RLS politikası denetimi
        IF EXISTS (
            SELECT 1 FROM pg_policies
            WHERE schemaname = 'public' 
              AND tablename = '_archived_user_profiles_rollback_backup' 
              AND (roles @> '{anon}'::name[] OR roles @> '{authenticated}'::name[] OR roles @> '{public}'::name[])
        ) THEN
            RAISE EXCEPTION 'Arşivleme Başarısız: public._archived_user_profiles_rollback_backup tablosunda anon/authenticated/public erişimine izin veren RLS politikaları tespit edildi! Mevcut tabloya dokunulmadan işlem durduruldu.';
        END IF;
    ELSE
        CREATE TABLE public._archived_user_profiles_rollback_backup (
            archive_id BIGSERIAL PRIMARY KEY,
            archived_at TIMESTAMPTZ NOT NULL DEFAULT now(),
            user_profile_snapshot JSONB NOT NULL
        );
    END IF;

    -- 2. HASSAS VERİ KORUMASI VE SAHİPLİK: İstemci rollerinin (anon, authenticated, PUBLIC) erişimini kapat
    REVOKE ALL ON TABLE public._archived_user_profiles_rollback_backup FROM PUBLIC, anon, authenticated;
    GRANT SELECT, INSERT ON TABLE public._archived_user_profiles_rollback_backup TO service_role;
    ALTER TABLE public._archived_user_profiles_rollback_backup ENABLE ROW LEVEL SECURITY;

    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'postgres') THEN
        ALTER TABLE public._archived_user_profiles_rollback_backup OWNER TO postgres;
    END IF;

    -- 3. Migration tarafından eklenen kolonlardan HERHANGİ BİRİ mevcutsa snapshot ekle
    SELECT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND table_name = 'user_profiles' 
          AND column_name IN ('user_id', 'preferred_authors', 'preferred_vibe')
    ) INTO has_target_columns;

    IF has_target_columns THEN
        SELECT count(*) INTO current_count FROM public.user_profiles;
        IF current_count > 0 THEN
            INSERT INTO public._archived_user_profiles_rollback_backup (archived_at, user_profile_snapshot)
            SELECT now(), to_jsonb(up.*) FROM public.user_profiles up;
            RAISE NOTICE 'Rollback Arşivi: % adet kullanıcı profili _archived_user_profiles_rollback_backup tablosuna güvenle snapshot alındı.', current_count;
        END IF;
    ELSE
        RAISE NOTICE 'Rollback Arşivi: user_profiles hedef kolonları zaten silinmiş olduğundan yeni snapshot eklenmedi (Idempotent).';
    END IF;
END $$;

-- 5. Yalnızca Bu Migration Tarafından Eklenen Kolonları Kaldır
-- DİKKAT: 'onboarding_completed' kolonu migration öncesinde canlıda zaten mevcuttu.
-- Bu nedenle rollback sırasında silinmemeli, yalnızca migration ile eklenen kolonlar kaldırılmalıdır.
ALTER TABLE public.user_profiles DROP COLUMN IF EXISTS user_id;
ALTER TABLE public.user_profiles DROP COLUMN IF EXISTS preferred_authors;
ALTER TABLE public.user_profiles DROP COLUMN IF EXISTS preferred_vibe;

COMMIT;
