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
--   3. 'user_id' foreign key kısıtını (auth.users(id) ON DELETE CASCADE) ve UNIQUE indeksini
--      yalnızca isim bazında değil; hedef ilişki, kural ve tekillik açısından katalog seviyesinde doğrular.
--   4. Bir BEFORE trigger ile 'id' ve 'user_id' kolonlarını senkronize tutar (Hem eski hem yeni istemciler çalışır).
--   5. Eksik 'preferred_authors', 'preferred_vibe' ve 'onboarding_completed' alanlarını ekler.
--   6. Mevcut RLS politikalarını isim tahmin etmeksizin pg_policy kataloğundan dinamik olarak tespit edip kaldırır;
--      bilinmeyen bir ALL veya DELETE politikasının açıkta kalmasını engeller.
--   7. Tablo ve fonksiyon izinlerini en az yetki (least privilege) standardında sıkılaştırır (PUBLIC, anon, authenticated).
--      service_role için gereksiz ALL yerine SELECT, INSERT, UPDATE, DELETE izinleri tanımlar.
--   8. Trigger fonksiyonunun sahipliğini (postgres) ve EXECUTE izinlerini güvenli hale getirir.
--   9. İşlem öncesi ve sonrası tüm profil kayıtlarının değerlerini (SQL NULL değerleri dâhil) birebir doğrular
--      ve yeni eklenen alanları açıkça ayrıştırır.
--
-- VERİ KAYBI VE ROLLBACK RİSKİ:
--   Bu migration uygulandıktan sonra kullanıcılar tarafından 'preferred_authors' ve 'preferred_vibe'
--   alanlarına yazılan yeni veriler, olası bir rollback (02_DRAFT_reconcile_user_profiles_rollback.sql)
--   durumunda bu kolonlar DROP edildiğinde GERİ DÖNÜŞSÜZ OLARAK SİLİNİR.
--   Canlıdaki orijinal tek kaydın 'id' ve 'preferred_genres' verisi ise korunur.
-- =============================================================================

BEGIN;

-- Kilit kuyruğu tıkanmalarını önlemek için güvenli lock_timeout
SET LOCAL lock_timeout = '5s';

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

-- 1.1 MEVCUT PROFİL VERİLERİNİN İŞLEM ÖNCESİ SNAPSHOT'I (DEĞER DOĞRULAMA GÜVENCESİ)
-- NOT: DROP TABLE IF EXISTS kullanılmaz; ON COMMIT DROP ile geçici tablo transaction ömrüne bağlanır.
CREATE TEMP TABLE _pre_user_profiles_snapshot ON COMMIT DROP AS
SELECT 
    COALESCE(
        (to_jsonb(p.*)->>'id'),
        (to_jsonb(p.*)->>'user_id')
    ) AS row_identifier,
    to_jsonb(p.*) AS original_data
FROM public.user_profiles p;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM _pre_user_profiles_snapshot WHERE row_identifier IS NULL
    ) THEN
        RAISE EXCEPTION 'Ön koşul başarısız: user_profiles tablosunda hem id hem user_id alanı tanımsız (NULL) olan geçersiz profil kaydı tespit edildi!';
    END IF;
END $$;


-- 2. 'user_id' KOLONUNUN EKLENMESİ, FOREIGN KEY KISITININ VE UNIQUE İNDEKSİNİN DOĞRULANMASI
-- KRİTİK GÜVENCE: Yalnızca isim kontrolü yapılmaz; auth.users(id) hedefi, ON DELETE CASCADE kuralı
-- ve tekil (UNIQUE) indeks özellikleri katalog seviyesinde doğrulanır.
DO $$
DECLARE
    fk_record RECORD;
    fk_found BOOLEAN := false;
BEGIN
    -- user_id kolonu yoksa ekle (Canlı Supabase uyumluluğu)
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'user_profiles' AND column_name = 'user_id'
    ) THEN
        ALTER TABLE public.user_profiles ADD COLUMN user_id UUID;
    END IF;

    -- id kolonu yoksa ekle (CI ve dual-column aşamalı uyumluluk güvencesi)
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'user_profiles' AND column_name = 'id'
    ) THEN
        ALTER TABLE public.user_profiles ADD COLUMN id UUID;
    END IF;

    -- user_id üzerindeki mevcut foreign key kısıtlarını katalogdan incele
    FOR fk_record IN (
        SELECT 
            c.conname,
            c.confdeltype,
            cardinality(c.conkey) AS src_col_count,
            cardinality(c.confkey) AS ref_col_count,
            (SELECT attname FROM pg_attribute WHERE attrelid = cl.oid AND attnum = c.conkey[1]) AS src_col,
            ref_ns.nspname AS ref_schema,
            ref_cl.relname AS ref_table,
            (SELECT attname FROM pg_attribute WHERE attrelid = c.confrelid AND attnum = c.confkey[1]) AS ref_col
        FROM pg_constraint c
        JOIN pg_class cl ON cl.oid = c.conrelid
        JOIN pg_namespace ns ON ns.oid = cl.relnamespace
        JOIN pg_class ref_cl ON ref_cl.oid = c.confrelid
        JOIN pg_namespace ref_ns ON ref_ns.oid = ref_cl.relnamespace
        WHERE ns.nspname = 'public' 
          AND cl.relname = 'user_profiles'
          AND c.contype = 'f'
          AND array_position(c.conkey, (
              SELECT attnum FROM pg_attribute 
              WHERE attrelid = cl.oid AND attname = 'user_id'
          )) IS NOT NULL
    ) LOOP
        -- Mevcut kısıtın tek kolonlu, hedefinin auth.users(id) ve silme kuralının ON DELETE CASCADE olduğu doğrulanır
        -- Bileşik veya yanlış hedefli/davranışlı kısıtlar kesinlikle reddedilir (Fail-Closed)
        IF fk_record.src_col_count = 1 
           AND fk_record.src_col = 'user_id'
           AND fk_record.ref_col_count = 1
           AND fk_record.ref_schema = 'auth' 
           AND fk_record.ref_table = 'users' 
           AND fk_record.ref_col = 'id' 
           AND fk_record.confdeltype = 'c' THEN
            fk_found := true;
            RAISE NOTICE 'user_id foreign key kısıtı zaten geçerli ve uyumlu: % -> auth.users(id) ON DELETE CASCADE', fk_record.conname;
        ELSE
            RAISE EXCEPTION 'Uyumsuz foreign key kısıtı tespit edildi: "%" kısıtı user_id üzerinde ancak tek kolonlu public.user_profiles(user_id) -> auth.users(id) ON DELETE CASCADE kuralına uymuyor (kaynak_kolon_sayısı=%, hedef_kolon_sayısı=%, hedef=%.%(%), silme_kuralı=%)!',
                fk_record.conname, fk_record.src_col_count, fk_record.ref_col_count, fk_record.ref_schema, fk_record.ref_table, fk_record.ref_col, fk_record.confdeltype;
        END IF;
    END LOOP;

    -- Uyumlu bir foreign key yoksa ekle
    IF NOT fk_found THEN
        ALTER TABLE public.user_profiles 
        ADD CONSTRAINT fk_user_profiles_user_id 
        FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
        RAISE NOTICE 'user_id kolonu için foreign key kısıtı eklendi: fk_user_profiles_user_id -> auth.users(id) ON DELETE CASCADE';
    END IF;

    -- Backfill öncesi: mevcut kimlik çelişkilerini reddet
    IF EXISTS (
        SELECT 1
        FROM public.user_profiles
        WHERE id IS NOT NULL
          AND user_id IS NOT NULL
          AND id <> user_id
    ) THEN
        RAISE EXCEPTION 'Migration durduruldu: user_profiles içinde id/user_id uyuşmazlığı var.';
    END IF;

    -- Mevcut kayıtlar için karşılıklı backfill (id -> user_id ve user_id -> id)
    EXECUTE 'UPDATE public.user_profiles SET user_id = id WHERE user_id IS NULL AND id IS NOT NULL';
    EXECUTE 'UPDATE public.user_profiles SET id = user_id WHERE id IS NULL AND user_id IS NOT NULL';
END $$;

-- 2.1 UNIQUE İNDEKS DENETİMİ VE OLUŞTURULMASI
DO $$
DECLARE
    idx_rec RECORD;
    idx_found BOOLEAN := false;
BEGIN
    -- Unique indeks öncesi: yinelenen user_id değerlerini reddet
    IF EXISTS (
        SELECT user_id
        FROM public.user_profiles
        WHERE user_id IS NOT NULL
        GROUP BY user_id
        HAVING COUNT(*) > 1
    ) THEN
        RAISE EXCEPTION 'Migration durduruldu: yinelenen user_id değerleri var.';
    END IF;

    -- idx_user_profiles_user_id veya user_id üzerindeki mevcut indeksleri incele
    FOR idx_rec IN (
        SELECT 
            idx_c.relname AS index_name,
            i.indisunique,
            i.indisvalid,
            i.indnatts,
            i.indpred IS NOT NULL AS is_partial,
            i.indexprs IS NOT NULL AS is_expression,
            (SELECT attname FROM pg_attribute WHERE attrelid = c.oid AND attnum = i.indkey[0]) AS indexed_col
        FROM pg_class idx_c
        JOIN pg_index i ON i.indexrelid = idx_c.oid
        JOIN pg_class c ON c.oid = i.indrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' 
          AND c.relname = 'user_profiles'
          AND (
              idx_c.relname = 'idx_user_profiles_user_id'
              OR (
                  i.indnatts = 1 
                  AND i.indkey[0] = (SELECT attnum FROM pg_attribute WHERE attrelid = c.oid AND attname = 'user_id')
              )
          )
    ) LOOP
        IF idx_rec.index_name = 'idx_user_profiles_user_id' THEN
            -- İsim eşleşiyorsa tanımının tekil, geçerli ve user_id üzerinde olduğunu doğrula
            IF idx_rec.indisunique AND idx_rec.indisvalid AND idx_rec.indnatts = 1 
               AND idx_rec.indexed_col = 'user_id' AND NOT idx_rec.is_partial AND NOT idx_rec.is_expression THEN
                idx_found := true;
                RAISE NOTICE 'idx_user_profiles_user_id indeksi zaten geçerli ve UNIQUE olarak mevcut.';
            ELSE
                RAISE EXCEPTION 'Uyumsuz mevcut indeks: "idx_user_profiles_user_id" mevcut ancak user_id üzerinde tekil (UNIQUE), geçerli veya tam kapsamlı değil (unique=%, valid=%, col=%, partial=%)!',
                    idx_rec.indisunique, idx_rec.indisvalid, idx_rec.indexed_col, idx_rec.is_partial;
            END IF;
        ELSIF idx_rec.indisunique AND idx_rec.indisvalid AND idx_rec.indnatts = 1 
              AND idx_rec.indexed_col = 'user_id' AND NOT idx_rec.is_partial AND NOT idx_rec.is_expression THEN
            idx_found := true;
            RAISE NOTICE 'user_id üzerinde farklı bir UNIQUE indeks mevcut: %', idx_rec.index_name;
        END IF;
    END LOOP;

    -- Geçerli bir UNIQUE indeks yoksa oluştur
    IF NOT idx_found THEN
        CREATE UNIQUE INDEX idx_user_profiles_user_id ON public.user_profiles(user_id);
        RAISE NOTICE 'idx_user_profiles_user_id UNIQUE indeksi başarıyla oluşturuldu.';
    END IF;
END $$;


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

-- 3.1. TRIGGER FONKSİYONU GÜVENLİK SIKILAŞTIRMASI (Sahiplik ve EXECUTE İzinleri)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'postgres') THEN
        ALTER FUNCTION public.sync_user_profile_identifiers() OWNER TO postgres;
    END IF;
END $$;

REVOKE ALL ON FUNCTION public.sync_user_profile_identifiers() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.sync_user_profile_identifiers() TO authenticated;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
        GRANT EXECUTE ON FUNCTION public.sync_user_profile_identifiers() TO service_role;
    END IF;
END $$;

DROP TRIGGER IF EXISTS trg_sync_user_profile_identifiers ON public.user_profiles;
CREATE TRIGGER trg_sync_user_profile_identifiers
BEFORE INSERT OR UPDATE ON public.user_profiles
FOR EACH ROW EXECUTE FUNCTION public.sync_user_profile_identifiers();


-- 4. EKSİK KOLONLARIN GÜVENLİ ŞEKİLDE EKLENMESİ
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS preferred_authors TEXT[] DEFAULT '{}';
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS preferred_vibe TEXT DEFAULT '';
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS onboarding_completed BOOLEAN DEFAULT false;


-- 5. RLS POLİTİKALARININ KATALOG SEVİYESİNDE YENİDEN YAPILANDIRILMASI VE TABLO İZİNLERİ
ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;

-- 5.1. Mevcut Politikaların Katalogdan Tespiti ve Güvenli Temizlenmesi (İsim Tahmin Etmeksizin)
DO $$
DECLARE
    pol_rec RECORD;
    dropped_count INTEGER := 0;
BEGIN
    FOR pol_rec IN (
        SELECT 
            p.polname,
            p.polcmd,
            CASE p.polcmd
                WHEN 'r' THEN 'SELECT'
                WHEN 'a' THEN 'INSERT'
                WHEN 'w' THEN 'UPDATE'
                WHEN 'd' THEN 'DELETE'
                WHEN '*' THEN 'ALL'
            END AS cmd_desc
        FROM pg_policy p
        JOIN pg_class c ON c.oid = p.polrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND c.relname = 'user_profiles'
    ) LOOP
        RAISE NOTICE 'Mevcut RLS politikası tespit edildi ve kaldırılıyor: "%" (Kapsam: %)', pol_rec.polname, pol_rec.cmd_desc;
        EXECUTE format('DROP POLICY IF EXISTS %I ON public.user_profiles', pol_rec.polname);
        dropped_count := dropped_count + 1;
    END LOOP;

    IF dropped_count > 0 THEN
        RAISE NOTICE 'user_profiles üzerinde toplam % adet mevcut politika güvenle temizlendi.', dropped_count;
    END IF;
END $$;

-- 5.2. En Az Yetki (Least Privilege) Standardında İzin Sıkılaştırması
-- PUBLIC ve anon izinlerini sıfırla
REVOKE ALL PRIVILEGES ON TABLE public.user_profiles FROM PUBLIC, anon;

-- Authenticated rolleri için izinleri sıfırla ve yalnızca gereken SELECT, INSERT, UPDATE izinlerini ver
REVOKE ALL PRIVILEGES ON TABLE public.user_profiles FROM authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE public.user_profiles TO authenticated;

-- Tehlikeli operasyonların istemci rollerinden açıkça engellenmesi
REVOKE DELETE, TRUNCATE, REFERENCES, TRIGGER ON TABLE public.user_profiles FROM PUBLIC, anon, authenticated;

-- Supabase servis katmanı için en az yetki: ALL yerine yalnızca gerekli DML izinleri verilir (TRUNCATE/TRIGGER hariç)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
        REVOKE ALL PRIVILEGES ON TABLE public.user_profiles FROM service_role;
        GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.user_profiles TO service_role;
    END IF;
END $$;

-- 5.3. Yeni Doğrulanmış RLS Politikaları (Hem user_id hem id destekli, komut bazında izole)
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


-- 6. UYGULAMA SONRASI DOĞRULAMA (Post-check & Sıfır Veri Kaybı / Veri Değeri Güvencesi)
DO $$
DECLARE
    pre_count INTEGER;
    post_count INTEGER;
    null_user_ids INTEGER;
    null_ids INTEGER;
    snap_rec RECORD;
    current_row_data JSONB;
    col_name TEXT;
    orig_val JSONB;
    curr_val JSONB;
    fk_verified BOOLEAN := false;
    idx_verified BOOLEAN := false;
    total_pol_count INTEGER;
    select_pol_count INTEGER;
    insert_pol_count INTEGER;
    update_pol_count INTEGER;
    pol_check_rec RECORD;
    clean_qual TEXT;
    clean_check TEXT;
BEGIN
    pre_count := current_setting('libris.pre_profile_count', true)::integer;
    SELECT count(*), 
           count(*) FILTER (WHERE user_id IS NULL),
           count(*) FILTER (WHERE id IS NULL)
    INTO post_count, null_user_ids, null_ids 
    FROM public.user_profiles;

    IF post_count < pre_count THEN
        RAISE EXCEPTION 'Uygulama sonrası doğrulama başarısız: Profil kayıt sayısı azaldı! (Önce: %, Sonra: %)', pre_count, post_count;
    END IF;

    IF post_count <> pre_count THEN
        RAISE EXCEPTION 'Uygulama sonrası doğrulama başarısız: Profil kayıt sayısı eşleşmiyor! (Önce: %, Sonra: %)', pre_count, post_count;
    END IF;

    IF null_user_ids > 0 THEN
        RAISE EXCEPTION 'Uygulama sonrası doğrulama başarısız: user_id alanı NULL olan % adet kayıt var!', null_user_ids;
    END IF;

    IF null_ids > 0 THEN
        RAISE EXCEPTION 'Uygulama sonrası doğrulama başarısız: id alanı NULL olan % adet kayıt var!', null_ids;
    END IF;

    -- =========================================================================
    -- 6.1 MEVCUT VERİ DEĞERLERİNİN VE SQL NULL ALANLARININ KORUNMASI (VERİ BÜTÜNLÜĞÜ)
    -- =========================================================================
    -- Doğrulama Kuralı:
    -- 1. İşlem öncesi snapshot'ta yer alan tüm kolonlar kontrol edilir.
    -- 2. SQL NULL ('null'::jsonb) değerleri DÂHİL olmak üzere hiçbir pre-existing kolon değeri bozulamaz.
    -- 3. YALNIZCA bilerek uzlaştırılan kimlik kolonlarına (id / user_id) izin verilir:
    --    - 'user_id' öncesinde NULL ise, yeni değeri 'id' değerine eşit olmak zorundadır.
    --    - 'id' öncesinde NULL ise, yeni değeri 'user_id' değerine eşit olmak zorundadır.
    --    - Önceden dolu olan id/user_id değerleri asla değişemez.
    -- 4. Yeni eklenen kolonlar (preferred_authors, preferred_vibe, onboarding_completed)
    --    snapshot'ta bulunmayan yeni alanlar olarak doğrulanır.
    -- =========================================================================
    FOR snap_rec IN SELECT row_identifier, original_data FROM _pre_user_profiles_snapshot LOOP
        SELECT to_jsonb(p.*) INTO current_row_data
        FROM public.user_profiles p
        WHERE p.id::text = snap_rec.row_identifier OR p.user_id::text = snap_rec.row_identifier;

        IF current_row_data IS NULL THEN
            RAISE EXCEPTION 'Uygulama sonrası doğrulama başarısız: İşlem öncesi mevcut olan profil kaydı (%) bulunamadı!', snap_rec.row_identifier;
        END IF;

        -- Mevcut kolon değerlerinin birebir korunup korunmadığını doğrula (SQL NULL değerleri dâhil)
        FOR col_name, orig_val IN SELECT key, value FROM jsonb_each(snap_rec.original_data) LOOP
            curr_val := current_row_data->col_name;

            IF col_name = 'user_id' THEN
                -- user_id önceden NULL ise, id ile doldurulduğunu doğrula
                IF orig_val = 'null'::jsonb THEN
                    IF curr_val IS DISTINCT FROM (current_row_data->'id') THEN
                        RAISE EXCEPTION 'Uygulama sonrası doğrulama başarısız: % kaydında user_id backfill değeri id (%) ile eşleşmiyor: %',
                            snap_rec.row_identifier, current_row_data->'id', curr_val;
                    END IF;
                ELSE
                    -- Önceden dolu olan user_id kesinlikle değişemez
                    IF curr_val IS DISTINCT FROM orig_val THEN
                        RAISE EXCEPTION 'Uygulama sonrası doğrulama başarısız: % kaydında önceden tanımlı user_id değeri değişti! (Önce: %, Sonra: %)',
                            snap_rec.row_identifier, orig_val, curr_val;
                    END IF;
                END IF;

            ELSIF col_name = 'id' THEN
                -- id önceden NULL ise, user_id ile doldurulduğunu doğrula
                IF orig_val = 'null'::jsonb THEN
                    IF curr_val IS DISTINCT FROM (current_row_data->'user_id') THEN
                        RAISE EXCEPTION 'Uygulama sonrası doğrulama başarısız: % kaydında id backfill değeri user_id (%) ile eşleşmiyor: %',
                            snap_rec.row_identifier, current_row_data->'user_id', curr_val;
                    END IF;
                ELSE
                    -- Önceden dolu olan id kesinlikle değişemez
                    IF curr_val IS DISTINCT FROM orig_val THEN
                        RAISE EXCEPTION 'Uygulama sonrası doğrulama başarısız: % kaydında önceden tanımlı id değeri değişti! (Önce: %, Sonra: %)',
                            snap_rec.row_identifier, orig_val, curr_val;
                    END IF;
                END IF;

            ELSE
                -- Diğer TÜM kolonlar (preferred_genres, created_at vs.) SQL NULL dâhil BİREBİR KORUNMALIDIR!
                IF curr_val IS DISTINCT FROM orig_val THEN
                    RAISE EXCEPTION 'Uygulama sonrası veri bütünlüğü doğrulaması başarısız: % kimlikli profil kaydında ''%'' kolon değeri değişti! (Önceki değer: %, Şimdiki değer: %)',
                        snap_rec.row_identifier, col_name, orig_val, curr_val;
                END IF;
            END IF;
        END LOOP;

        -- Dual-column senkronizasyonunu doğrula
        IF (current_row_data->>'id') <> (current_row_data->>'user_id') THEN
            RAISE EXCEPTION 'Uygulama sonrası doğrulama başarısız: % kimlikli kayıtta id (%) ile user_id (%) senkronize değil!',
                snap_rec.row_identifier, current_row_data->>'id', current_row_data->>'user_id';
        END IF;

        -- Yeni eklenen kolonların varlığını ve tip güvenliğini doğrula
        IF NOT (current_row_data ? 'preferred_authors') THEN
            RAISE EXCEPTION 'Uygulama sonrası doğrulama başarısız: preferred_authors kolonu bulunamadı!';
        END IF;
        IF NOT (current_row_data ? 'preferred_vibe') THEN
            RAISE EXCEPTION 'Uygulama sonrası doğrulama başarısız: preferred_vibe kolonu bulunamadı!';
        END IF;
        IF NOT (current_row_data ? 'onboarding_completed') THEN
            RAISE EXCEPTION 'Uygulama sonrası doğrulama başarısız: onboarding_completed kolonu bulunamadı!';
        END IF;
    END LOOP;

    -- =========================================================================
    -- 6.2 FOREIGN KEY VE UNIQUE İNDEKS KATALOG DOĞRULAMASI
    -- =========================================================================
    -- user_id foreign key kısıtının tek kolonlu public.user_profiles(user_id) -> auth.users(id)
    -- ve ON DELETE CASCADE olduğunu katalogdan doğrula
    SELECT EXISTS (
        SELECT 1
        FROM pg_constraint c
        JOIN pg_class cl ON cl.oid = c.conrelid
        JOIN pg_namespace ns ON ns.oid = cl.relnamespace
        JOIN pg_class ref_cl ON ref_cl.oid = c.confrelid
        JOIN pg_namespace ref_ns ON ref_ns.oid = ref_cl.relnamespace
        WHERE ns.nspname = 'public' 
          AND cl.relname = 'user_profiles'
          AND c.contype = 'f'
          AND cardinality(c.conkey) = 1
          AND c.conkey[1] = (
              SELECT attnum FROM pg_attribute 
              WHERE attrelid = cl.oid AND attname = 'user_id'
          )
          AND cardinality(c.confkey) = 1
          AND ref_ns.nspname = 'auth'
          AND ref_cl.relname = 'users'
          AND c.confkey[1] = (
              SELECT attnum FROM pg_attribute 
              WHERE attrelid = ref_cl.oid AND attname = 'id'
          )
          AND c.confdeltype = 'c'
    ) INTO fk_verified;

    IF NOT fk_verified THEN
        RAISE EXCEPTION 'Uygulama sonrası doğrulama başarısız: public.user_profiles.user_id -> auth.users.id ON DELETE CASCADE tek kolonlu foreign key kısıtı katalogda doğrulanamadı!';
    END IF;

    -- user_id kolonu içeren herhangi bir uyumsuz veya bileşik yabancı anahtar kısıtı kalmadığını doğrula
    IF EXISTS (
        SELECT 1
        FROM pg_constraint c
        JOIN pg_class cl ON cl.oid = c.conrelid
        JOIN pg_namespace ns ON ns.oid = cl.relnamespace
        JOIN pg_class ref_cl ON ref_cl.oid = c.confrelid
        JOIN pg_namespace ref_ns ON ref_ns.oid = ref_cl.relnamespace
        WHERE ns.nspname = 'public' 
          AND cl.relname = 'user_profiles'
          AND c.contype = 'f'
          AND array_position(c.conkey, (
              SELECT attnum FROM pg_attribute 
              WHERE attrelid = cl.oid AND attname = 'user_id'
          )) IS NOT NULL
          AND NOT (
              cardinality(c.conkey) = 1
              AND c.conkey[1] = (SELECT attnum FROM pg_attribute WHERE attrelid = cl.oid AND attname = 'user_id')
              AND cardinality(c.confkey) = 1
              AND ref_ns.nspname = 'auth'
              AND ref_cl.relname = 'users'
              AND c.confkey[1] = (SELECT attnum FROM pg_attribute WHERE attrelid = ref_cl.oid AND attname = 'id')
              AND c.confdeltype = 'c'
          )
    ) THEN
        RAISE EXCEPTION 'Uygulama sonrası doğrulama başarısız: user_profiles.user_id üzerinde uyumsuz veya bileşik foreign key kısıtı tespit edildi!';
    END IF;

    -- user_id üzerinde tekil (UNIQUE), geçerli ve tam kapsamlı bir indeks olduğunu doğrula
    -- (idx_user_profiles_user_id veya önceden mevcut farklı isimli geçerli UNIQUE indeks)
    SELECT EXISTS (
        SELECT 1
        FROM pg_class idx_c
        JOIN pg_index i ON i.indexrelid = idx_c.oid
        JOIN pg_class c ON c.oid = i.indrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' 
          AND c.relname = 'user_profiles'
          AND i.indisunique = true
          AND i.indisvalid = true
          AND i.indnatts = 1
          AND i.indpred IS NULL
          AND i.indexprs IS NULL
          AND i.indkey[0] = (
              SELECT attnum FROM pg_attribute 
              WHERE attrelid = c.oid AND attname = 'user_id'
          )
    ) INTO idx_verified;

    IF NOT idx_verified THEN
        RAISE EXCEPTION 'Uygulama sonrası doğrulama başarısız: user_profiles(user_id) üzerinde geçerli ve tekil (UNIQUE) bir indeks katalogda doğrulanamadı!';
    END IF;

    -- idx_user_profiles_user_id indeksi mevcutsa geçerli ve tekil olduğunu doğrula
    IF EXISTS (
        SELECT 1
        FROM pg_class idx_c
        JOIN pg_index i ON i.indexrelid = idx_c.oid
        JOIN pg_class c ON c.oid = i.indrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' 
          AND c.relname = 'user_profiles'
          AND idx_c.relname = 'idx_user_profiles_user_id'
          AND NOT (
              i.indisunique = true
              AND i.indisvalid = true
              AND i.indnatts = 1
              AND i.indpred IS NULL
              AND i.indexprs IS NULL
              AND i.indkey[0] = (SELECT attnum FROM pg_attribute WHERE attrelid = c.oid AND attname = 'user_id')
          )
    ) THEN
        RAISE EXCEPTION 'Uygulama sonrası doğrulama başarısız: idx_user_profiles_user_id indeksi katalogda mevcut ancak geçersiz veya uyumsuz tanıma sahip!';
    END IF;

    -- =========================================================================
    -- 6.3 RLS POLİTİKALARI KATALOG DOĞRULAMASI (Kapsam, Koşul ve Yetkisiz ALL İzolasyonu)
    -- =========================================================================
    -- Bilinmeyen hiçbir ALL ('*') veya DELETE ('d') ya da yetkisiz politika kalmadığını doğrula (Fail-Closed)
    IF EXISTS (
        SELECT 1
        FROM pg_policy p
        JOIN pg_class c ON c.oid = p.polrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' 
          AND c.relname = 'user_profiles'
          AND (p.polcmd IN ('*', 'd') OR p.polcmd NOT IN ('r', 'a', 'w'))
    ) THEN
        RAISE EXCEPTION 'Uygulama sonrası doğrulama başarısız: user_profiles üzerinde yetkisiz ALL veya DELETE ya da bilinmeyen RLS politikası tespit edildi!';
    END IF;

    -- Tam olarak 1 SELECT ('r'), 1 INSERT ('a') ve 1 UPDATE ('w') politikası olduğunu doğrula
    SELECT 
        count(*),
        count(*) FILTER (WHERE p.polcmd = 'r'),
        count(*) FILTER (WHERE p.polcmd = 'a'),
        count(*) FILTER (WHERE p.polcmd = 'w')
    INTO total_pol_count, select_pol_count, insert_pol_count, update_pol_count
    FROM pg_policy p
    JOIN pg_class c ON c.oid = p.polrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' 
      AND c.relname = 'user_profiles';

    IF total_pol_count <> 3 OR select_pol_count <> 1 OR insert_pol_count <> 1 OR update_pol_count <> 1 THEN
        RAISE EXCEPTION 'Uygulama sonrası doğrulama başarısız: user_profiles üzerinde tam olarak 1 SELECT, 1 INSERT, 1 UPDATE politikası (toplam 3) bekleniyordu (Toplam: %, SELECT: %, INSERT: %, UPDATE: %)!',
            total_pol_count, select_pol_count, insert_pol_count, update_pol_count;
    END IF;

    -- Beklenen politika koşullarını pg_get_expr ile katalog seviyesinde doğrula
    FOR pol_check_rec IN (
        SELECT 
            p.polname,
            p.polcmd,
            pg_get_expr(p.polqual, p.polrelid) AS qual_expr,
            pg_get_expr(p.polwithcheck, p.polrelid) AS with_check_expr
        FROM pg_policy p
        JOIN pg_class c ON c.oid = p.polrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' 
          AND c.relname = 'user_profiles'
    ) LOOP
        -- =====================================================================
        -- METİN NORMALİZASYONUNUN SINIRLARI VE GÜVENLİK MİMARİSİ:
        -- 1. Boşluk ve parantez temizleme ('(', ')') metin karşılaştırması PostgreSQL
        --    sürümlerine göre (pg_get_expr ayrıştırma farkları, tip dönüşümü cast'leri örn: ::uuid)
        --    kırılgan olabilir ve parantezlerin silinmesi karmaşık mantıksal öncelikleri
        --    maskeleyebilir. Bu nedenle bu metin kontrolü tek başına nihai güvenlik kanıtı değildir.
        -- 2. Güvenlik omurgası katalog kontrolleridir: Komut izolasyonu (polcmd IN ('r','a','w')),
        --    surviving ALL/DELETE bulunmaması (polcmd NOT IN ('*', 'd')), kesin politika sayıları
        --    (1 SELECT, 1 INSERT, 1 UPDATE, toplam 3) ve rol izinleri (REVOKE ALL FROM PUBLIC, anon).
        -- 3. Nihai doğrulama esası: Yetki sızdırmazlığı, gerçek PostgreSQL runtime ortamında farklı
        --    kullanıcı oturumları (User A vs User B) ile yapılan davranışsal RLS testleriyle kanıtlanır.
        -- =====================================================================
        -- İfadeleri boşluk ve parantezlerden arındırarak semantik normalizasyona tabi tut
        clean_qual := replace(replace(regexp_replace(lower(COALESCE(pol_check_rec.qual_expr, '')), '\s+', '', 'g'), '(', ''), ')', '');
        clean_check := replace(replace(regexp_replace(lower(COALESCE(pol_check_rec.with_check_expr, '')), '\s+', '', 'g'), '(', ''), ')', '');

        IF pol_check_rec.polcmd = 'r' THEN
            -- SELECT: USING koşulu zorunlu (auth.uid() = user_id OR auth.uid() = id eşdeğeri), WITH CHECK olmamalı
            IF pol_check_rec.qual_expr IS NULL OR clean_qual NOT IN (
                'auth.uid=user_idorauth.uid=id',
                'auth.uid=idorauth.uid=user_id',
                'user_id=auth.uidorid=auth.uid',
                'id=auth.uidoruser_id=auth.uid',
                'user_id=auth.uidorauth.uid=id',
                'auth.uid=user_idorid=auth.uid',
                'id=auth.uidorauth.uid=user_id',
                'auth.uid=idoruser_id=auth.uid'
            ) THEN
                RAISE EXCEPTION 'Uygulama sonrası doğrulama başarısız: SELECT politikasında ("%") beklenen USING koşulu ("auth.uid() = user_id OR auth.uid() = id") bulunamadı veya mantıksal olarak eşdeğer değil: %',
                    pol_check_rec.polname, pol_check_rec.qual_expr;
            END IF;
            IF pol_check_rec.with_check_expr IS NOT NULL THEN
                RAISE EXCEPTION 'Uygulama sonrası doğrulama başarısız: SELECT politikasında ("%") beklenmeyen WITH CHECK koşulu mevcut: %',
                    pol_check_rec.polname, pol_check_rec.with_check_expr;
            END IF;

        ELSIF pol_check_rec.polcmd = 'a' THEN
            -- INSERT: WITH CHECK koşulu zorunlu (auth.uid() = user_id OR auth.uid() = id eşdeğeri), USING olmamalı
            IF pol_check_rec.with_check_expr IS NULL OR clean_check NOT IN (
                'auth.uid=user_idorauth.uid=id',
                'auth.uid=idorauth.uid=user_id',
                'user_id=auth.uidorid=auth.uid',
                'id=auth.uidoruser_id=auth.uid',
                'user_id=auth.uidorauth.uid=id',
                'auth.uid=user_idorid=auth.uid',
                'id=auth.uidorauth.uid=user_id',
                'auth.uid=idoruser_id=auth.uid'
            ) THEN
                RAISE EXCEPTION 'Uygulama sonrası doğrulama başarısız: INSERT politikasında ("%") beklenen WITH CHECK koşulu ("auth.uid() = user_id OR auth.uid() = id") bulunamadı veya mantıksal olarak eşdeğer değil: %',
                    pol_check_rec.polname, pol_check_rec.with_check_expr;
            END IF;
            IF pol_check_rec.qual_expr IS NOT NULL THEN
                RAISE EXCEPTION 'Uygulama sonrası doğrulama başarısız: INSERT politikasında ("%") beklenmeyen USING koşulu mevcut: %',
                    pol_check_rec.polname, pol_check_rec.qual_expr;
            END IF;

        ELSIF pol_check_rec.polcmd = 'w' THEN
            -- UPDATE: Hem USING hem WITH CHECK koşulu zorunlu (auth.uid() = user_id OR auth.uid() = id eşdeğeri)
            IF pol_check_rec.qual_expr IS NULL OR clean_qual NOT IN (
                'auth.uid=user_idorauth.uid=id',
                'auth.uid=idorauth.uid=user_id',
                'user_id=auth.uidorid=auth.uid',
                'id=auth.uidoruser_id=auth.uid',
                'user_id=auth.uidorauth.uid=id',
                'auth.uid=user_idorid=auth.uid',
                'id=auth.uidorauth.uid=user_id',
                'auth.uid=idoruser_id=auth.uid'
            ) THEN
                RAISE EXCEPTION 'Uygulama sonrası doğrulama başarısız: UPDATE politikasında ("%") beklenen USING koşulu ("auth.uid() = user_id OR auth.uid() = id") bulunamadı veya mantıksal olarak eşdeğer değil: %',
                    pol_check_rec.polname, pol_check_rec.qual_expr;
            END IF;
            IF pol_check_rec.with_check_expr IS NULL OR clean_check NOT IN (
                'auth.uid=user_idorauth.uid=id',
                'auth.uid=idorauth.uid=user_id',
                'user_id=auth.uidorid=auth.uid',
                'id=auth.uidoruser_id=auth.uid',
                'user_id=auth.uidorauth.uid=id',
                'auth.uid=user_idorid=auth.uid',
                'id=auth.uidorauth.uid=user_id',
                'auth.uid=idoruser_id=auth.uid'
            ) THEN
                RAISE EXCEPTION 'Uygulama sonrası doğrulama başarısız: UPDATE politikasında ("%") beklenen WITH CHECK koşulu ("auth.uid() = user_id OR auth.uid() = id") bulunamadı veya mantıksal olarak eşdeğer değil: %',
                    pol_check_rec.polname, pol_check_rec.with_check_expr;
            END IF;
        END IF;
    END LOOP;

    RAISE NOTICE 'Doğrulama başarılı: % adet profil kaydının SQL NULL dâhil tüm değerleri korundu, foreign key (CASCADE), UNIQUE indeks ve RLS politikaları katalog seviyesinde doğrulandı.', pre_count;
END $$;

COMMIT;
