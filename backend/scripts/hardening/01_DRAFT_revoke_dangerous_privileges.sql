-- =============================================================================
-- [DRAFT / NOT FOR IMMEDIATE EXECUTION]
-- GRUP 1: YETKİ AZALTIMI VE TEHLİKELİ RLS POLİTİKALARININ KALDIRILMASI
-- =============================================================================
-- Dosya: backend/scripts/hardening/01_DRAFT_revoke_dangerous_privileges.sql
-- Amaç: 
--   1. RLS'i baypas eden TRUNCATE yetkisini 'anon', 'authenticated' ve 'PUBLIC' rollerinden almak.
--   2. 'public.books' tablosundaki tehlikeli anonim yazma politikalarını ('python_ekleme_izni', 'python_guncelleme_izni') kaldırmak.
--   3. Kullanıcı tablolarından 'anon' yazma izinlerini kaldırmak.
--   4. 'book_embeddings' tablosunda 'anon' ve 'authenticated' SELECT yetkisini korumak (match_query_embeddings INVOKER çalışır).
--
-- Ön Koşullar:
--   - Hedef tabloların (books, book_embeddings, favorites, user_activities, user_interactions, user_profiles) var olması.
--
-- DDL Transaction Atomikliği: Yüksek (Hata durumunda tüm blok geri alınır, kısmi durum oluşmaz).
-- Veri Silinme Riski: Düşük (DML DELETE/TRUNCATE içermez; hiçbir satır silinmez).
-- İstemci Çalışma Zamanı Riski: Yönetilmeli (Yetkisi kısıtlanan rollerde beklenmeyen istemci çağrıları 403 alabilir; duman testleri zorunludur).
-- Lock / Downtime Riski: Minimum (Hızlı catalog lock alır, bekleme yapmaz).
-- =============================================================================

BEGIN;

-- 1. ÖN KOŞUL KONTROLÜ (FAIL-CLOSED)
DO $$
DECLARE
    missing_tables TEXT;
BEGIN
    SELECT string_agg(t, ', ') INTO missing_tables
    FROM (
        SELECT unnest(ARRAY['books', 'book_embeddings', 'favorites', 'user_activities', 'user_interactions', 'user_profiles']) AS t
    ) expected
    WHERE NOT EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'public' AND table_name = expected.t
    );

    IF missing_tables IS NOT NULL THEN
        RAISE EXCEPTION 'Ön koşul başarısız: Eksik tablolar var: %', missing_tables;
    END IF;
END $$;


-- 2. TRUNCATE YETKİLERİNİN GERİ ALINMASI (KRİTİK GÜVENLİK - P0)
-- TRUNCATE komutu RLS kurallarını tamamen baypas ettiğinden, hiçbir istemci rolüne verilmemelidir.
REVOKE TRUNCATE ON public.books FROM anon, authenticated, PUBLIC;
REVOKE TRUNCATE ON public.book_embeddings FROM anon, authenticated, PUBLIC;
REVOKE TRUNCATE ON public.favorites FROM anon, authenticated, PUBLIC;
REVOKE TRUNCATE ON public.user_activities FROM anon, authenticated, PUBLIC;
REVOKE TRUNCATE ON public.user_interactions FROM anon, authenticated, PUBLIC;
REVOKE TRUNCATE ON public.user_profiles FROM anon, authenticated, PUBLIC;


-- 3. 'books' KATALOĞUNDAKİ AÇIK ANONİM YAZMA POLİTİKALARININ KALDIRILMASI
DROP POLICY IF EXISTS "python_ekleme_izni" ON public.books;
DROP POLICY IF EXISTS "python_guncelleme_izni" ON public.books;

-- Genel okuma politikasının varlığını teyit et
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE schemaname = 'public' AND tablename = 'books' AND policyname = 'Books are viewable by everyone'
    ) THEN
        CREATE POLICY "Books are viewable by everyone"
        ON public.books FOR SELECT
        USING (true);
    END IF;
END $$;

-- 'books' üzerinde 'anon' ve 'authenticated' için INSERT, UPDATE, DELETE yetkilerini kaldır, SELECT'i koru
REVOKE INSERT, UPDATE, DELETE ON public.books FROM anon, authenticated, PUBLIC;
GRANT SELECT ON public.books TO anon, authenticated;


-- 4. 'book_embeddings' TABLOSUNDA SELECT İZNİNİN KORUNMASI
-- Canlıdaki match_query_embeddings SECURITY INVOKER çalıştığı için, anon ve authenticated
-- rollerinin book_embeddings tablosunda SELECT iznine ihtiyacı vardır.
-- Doğrudan istemci yazmalarını engelle, SELECT yetkisini koru.
REVOKE INSERT, UPDATE, DELETE ON public.book_embeddings FROM anon, authenticated, PUBLIC;
GRANT SELECT ON public.book_embeddings TO anon, authenticated;


-- 5. KULLANICI TABLOLARINDAN 'anon' YAZMA YETKİLERİNİN KALDIRILMASI
REVOKE INSERT, UPDATE, DELETE ON public.favorites FROM anon, PUBLIC;
REVOKE INSERT, UPDATE, DELETE ON public.user_activities FROM anon, PUBLIC;
REVOKE INSERT, UPDATE, DELETE ON public.user_interactions FROM anon, PUBLIC;
REVOKE INSERT, UPDATE, DELETE ON public.user_profiles FROM anon, PUBLIC;

-- Authenticated rolleri için gerekli işlem izinleri (Trigger ve uygulama akışları için zorunludur)
GRANT SELECT, INSERT, UPDATE, DELETE ON public.favorites TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.user_interactions TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.user_profiles TO authenticated;
GRANT SELECT, INSERT ON public.user_activities TO authenticated;
REVOKE UPDATE, DELETE ON public.user_activities FROM authenticated;


-- 6. SEQUENCE VE SCHEMA USAGE GÜVENCESİ
GRANT USAGE ON SCHEMA public TO anon, authenticated;
-- Varsa tüm dizilerden (sequences) anon rollerinin değişiklik yapma yetkisini kaldır
DO $$
DECLARE
    seq_rec RECORD;
BEGIN
    FOR seq_rec IN (SELECT sequence_name FROM information_schema.sequences WHERE sequence_schema = 'public') LOOP
        EXECUTE format('REVOKE ALL ON SEQUENCE public.%I FROM anon, PUBLIC', seq_rec.sequence_name);
        EXECUTE format('GRANT USAGE, SELECT ON SEQUENCE public.%I TO authenticated', seq_rec.sequence_name);
    END LOOP;
END $$;

-- 6.1 GELECEKTE OLUŞTURULACAK TABLOLAR İÇİN VARSAYILAN TRUNCATE İZNİNİN ENGELLENMESİ
-- PostgreSQL mimarisinde ALTER DEFAULT PRIVILEGES mevcut tablolara dokunmaz; yalnızca bu komutu
-- çalıştıran rol tarafından (Supabase ortamında migration ve SQL Editor çalıştıran 'postgres' rolü)
-- gelecekte oluşturulacak yeni tablolar için geçerli varsayılan izin şablonunu belirler.
-- Körlemesine bir 'REVOKE ALL' yapılmamış; meşru okuma izinlerine dokunulmadan yalnızca RLS'i
-- tamamen baypas eden TRUNCATE yetkisi anon, authenticated ve PUBLIC rollerinden geri alınmıştır.
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE TRUNCATE ON TABLES FROM anon, authenticated, PUBLIC;

-- 6.2 NESNE GÖLGELEME VE ŞEMA ENJEKSİYONU KORUMASI (CVE-2018-1058)
-- İstemci rollerinin public şemasında nesne (fonksiyon, operatör, tablo) oluşturmasını engelle
REVOKE CREATE ON SCHEMA public FROM PUBLIC, anon, authenticated;


-- 7. DOĞRULAMA SORGUSU (Post-check)
DO $$
DECLARE
    truncate_leaks INTEGER;
BEGIN
    SELECT count(*) INTO truncate_leaks
    FROM (
        VALUES ('books'), ('book_embeddings'), ('favorites'), ('user_activities'), ('user_interactions'), ('user_profiles')
    ) AS t(tbl)
    CROSS JOIN (VALUES ('anon'), ('authenticated')) AS r(rol)
    WHERE has_table_privilege(r.rol, 'public.' || t.tbl, 'TRUNCATE') = true;

    IF truncate_leaks > 0 THEN
        RAISE EXCEPTION 'Uygulama sonrası doğrulama başarısız: % adet tabloda TRUNCATE yetkisi hala açık!', truncate_leaks;
    END IF;
END $$;

COMMIT;
