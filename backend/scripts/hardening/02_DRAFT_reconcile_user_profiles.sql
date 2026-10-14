-- =============================================================================
-- [DRAFT / NOT FOR IMMEDIATE EXECUTION]
-- GRUP 2: `user_profiles` AŞAMALI ŞEMA UZLAŞTIRMASI (STAGED COMPATIBILITY)
-- =============================================================================
-- Dosya: backend/scripts/hardening/02_DRAFT_reconcile_user_profiles.sql
-- Strateji: Aşamalı Uyumluluk Modeli (Staged Dual-Column Compatibility)
--
-- Neden Doğrudan Kolon Yeniden Adlandırma (id -> user_id) Seçilmedi?
--   Doğrudan 'id' kolonunu silmek veya yeniden adlandırmak, daha önce yayınlanmış
--   veya 'id' kolonunu kullanan harici istemcileri, Supabase Edge Function'larını
--   veya panel görünümlerini anında kırabilir.
--
-- Bu Betiğin Sağladığı Güvenceler:
--   1. Canlıdaki tek profil kaydının mevcut 'id' ve 'preferred_genres' değerlerini korur.
--   2. 'user_id' kolonunu ekler ve mevcut 'id' ile doldurur (Backfill).
--   3. 'user_id' üzerinde UNIQUE indeks kurarak 'on_conflict="user_id"' upsert'lerini çalıştırır.
--   4. Bir BEFORE trigger ile 'id' ve 'user_id' kolonlarını senkronize tutar (Hem eski hem yeni istemciler çalışır).
--   5. Eksik 'preferred_authors' ve 'preferred_vibe' alanlarını ekler.
--   6. RLS politikalarını hem 'user_id' hem 'id' kimliğini kabul edecek şekilde günceller.
--
-- VERİ KAYBI VE ROLLBACK RİSKİ:
--   Bu migration uygulandıktan sonra kullanıcılar tarafından 'preferred_authors' ve 'preferred_vibe'
--   alanlarına yazılan yeni veriler, olası bir rollback (02_DRAFT_reconcile_user_profiles_rollback.sql)
--   durumunda bu kolonlar DROP edildiğinde GERİ DÖNÜŞSÜZ OLARAK SİLİNİR.
--   Canlıdaki orijinal tek kaydın 'id' ve 'preferred_genres' verisi ise korunur.
-- =============================================================================

BEGIN;

-- 1. ÖN KOŞUL KONTROLÜ VE BAŞLANGIÇ SATIR SAYISI GÜVENCESİ (FAIL-CLOSED)
DO $$
DECLARE
    current_count INTEGER;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name = 'user_profiles'
    ) THEN
        RAISE EXCEPTION 'Ön koşul başarısız: public.user_profiles tablosu bulunamadı!';
    END IF;

    SELECT count(*) INTO current_count FROM public.user_profiles;
    -- Başlangıç satır sayısını transaction seviyesinde sakla (Post-check ile sıfır veri kaybı güvencesi)
    PERFORM set_config('libris.pre_profile_count', current_count::text, true);
    RAISE NOTICE 'user_profiles tablosunda işlem öncesi % adet kayıt doğrulandı.', current_count;
END $$;


-- 2. 'user_id' KOLONUNUN EKLENMESİ VE GERİYE DÖNÜK DOLDURULMASI
-- KRİTİK GÜVENCE: Canlıdaki 'id' kolonu 'REFERENCES auth.users(id) ON DELETE CASCADE' kısıtına sahiptir.
-- Yeni eklenen 'user_id' kolonuna da açıkça 'ON DELETE CASCADE' verilmelidir; aksi halde bir kullanıcı
-- Auth sisteminden silindiğinde PostgreSQL foreign key kısıt hatası (RESTRICT) verir ve kullanıcı silinemez.
DO $$
BEGIN
    -- user_id kolonu yoksa ekle (Canlı Supabase uyumluluğu)
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'user_profiles' AND column_name = 'user_id'
    ) THEN
        ALTER TABLE public.user_profiles ADD COLUMN user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE;
    END IF;

    -- id kolonu yoksa ekle (CI ve dual-column aşamalı uyumluluk güvencesi)
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'user_profiles' AND column_name = 'id'
    ) THEN
        ALTER TABLE public.user_profiles ADD COLUMN id UUID REFERENCES auth.users(id) ON DELETE CASCADE;
    END IF;

    -- Mevcut kayıtlar için karşılıklı backfill (id -> user_id ve user_id -> id)
    EXECUTE 'UPDATE public.user_profiles SET user_id = id WHERE user_id IS NULL AND id IS NOT NULL';
    EXECUTE 'UPDATE public.user_profiles SET id = user_id WHERE id IS NULL AND user_id IS NOT NULL';
END $$;

-- Flutter ve Flask upsert ('on_conflict=user_id') işlemleri için UNIQUE kısıtı/indeksi
CREATE UNIQUE INDEX IF NOT EXISTS idx_user_profiles_user_id ON public.user_profiles(user_id);


-- 3. ÇİFT TARAFLI KİMLİK SENKRONİZASYON TRIGGER'I (Dual-Write Compatibility)
-- Eski istemci 'id' yazarsa 'user_id' otomatik dolar. Yeni istemci 'user_id' yazarsa 'id' otomatik dolar.
CREATE OR REPLACE FUNCTION public.sync_user_profile_identifiers()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    -- Kimlik uyuşmazlığı koruması (id ve user_id farklı UUID'ler olarak verilemez)
    IF NEW.user_id IS NOT NULL AND NEW.id IS NOT NULL AND NEW.user_id <> NEW.id THEN
        RAISE EXCEPTION 'user_profiles kimlik uyuşmazlığı: id (%) ile user_id (%) farklı olamaz!', NEW.id, NEW.user_id;
    END IF;

    IF NEW.user_id IS NULL AND NEW.id IS NOT NULL THEN
        NEW.user_id := NEW.id;
    ELSIF NEW.id IS NULL AND NEW.user_id IS NOT NULL THEN
        NEW.id := NEW.user_id;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_user_profile_identifiers ON public.user_profiles;
CREATE TRIGGER trg_sync_user_profile_identifiers
BEFORE INSERT OR UPDATE ON public.user_profiles
FOR EACH ROW EXECUTE FUNCTION public.sync_user_profile_identifiers();


-- 4. EKSİK KOLONLARIN GÜVENLİ ŞEKİLDE EKLENMESİ
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS preferred_authors TEXT[] DEFAULT '{}';
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS preferred_vibe TEXT DEFAULT '';
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS onboarding_completed BOOLEAN DEFAULT false;


-- 5. RLS POLİTİKALARININ GENİŞLETİLMESİ (Hem user_id hem id destekli)
ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view their own profile" ON public.user_profiles;
DROP POLICY IF EXISTS "Users can insert their own profile" ON public.user_profiles;
DROP POLICY IF EXISTS "Users can update their own profile" ON public.user_profiles;
DROP POLICY IF EXISTS "Enable read access for own profile" ON public.user_profiles;
DROP POLICY IF EXISTS "Enable all for users based on id" ON public.user_profiles;

CREATE POLICY "Users can view their own profile" 
ON public.user_profiles FOR SELECT 
USING (auth.uid() = user_id OR auth.uid() = id);

CREATE POLICY "Users can insert their own profile" 
ON public.user_profiles FOR INSERT 
WITH CHECK (auth.uid() = user_id OR auth.uid() = id);

CREATE POLICY "Users can update their own profile" 
ON public.user_profiles FOR UPDATE 
USING (auth.uid() = user_id OR auth.uid() = id) 
WITH CHECK (auth.uid() = user_id OR auth.uid() = id);


-- 6. UYGULAMA SONRASI DOĞRULAMA (Post-check)
DO $$
DECLARE
    pre_count INTEGER;
    post_count INTEGER;
    null_user_ids INTEGER;
BEGIN
    pre_count := current_setting('libris.pre_profile_count', true)::integer;
    SELECT count(*), count(*) FILTER (WHERE user_id IS NULL) 
    INTO post_count, null_user_ids 
    FROM public.user_profiles;

    IF post_count < pre_count THEN
        RAISE EXCEPTION 'Uygulama sonrası doğrulama başarısız: Profil kayıt sayısı azaldı! (Önce: %, Sonra: %)', pre_count, post_count;
    END IF;

    IF null_user_ids > 0 THEN
        RAISE EXCEPTION 'Uygulama sonrası doğrulama başarısız: user_id alanı NULL olan kayıtlar var!';
    END IF;
    
    RAISE NOTICE 'Doğrulama başarılı: % adet profil kaydı korundu (Önce: %, Sonra: %), çift kolon uyumluluğu aktif.', post_count, pre_count, post_count;
END $$;

COMMIT;
