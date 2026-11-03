-- =============================================================================
-- [DRAFT / NOT FOR IMMEDIATE EXECUTION - SEPARATE DISTINCT CHANGE]
-- GRUP 1B: İKİNCİL EN AZ YETKİ (LEAST PRIVILEGE) VE KATALOG POLİTİKA TEMİZLİĞİ
-- =============================================================================
-- Dosya: backend/scripts/hardening/01b_DRAFT_least_privilege_and_policy_cleanup.sql
-- Amaç: 
--   P0 TRUNCATE düzeltmesinden (01_DRAFT) bağımsız olarak, kitap kataloğundaki
--   eski anonim yazma politikalarını ('python_ekleme_izni', 'python_guncelleme_izni')
--   kaldırmak ve kullanıcı tablolarında en az yetki (least privilege) matrisini uygulamak.
--
-- Ayrı Değişiklik Gerekçesi (Explicit Justification):
--   TRUNCATE yetkisi RLS kurallarını baypas ettiği için tek başına bir P0 güvenlik
--   açığıdır ve 01_DRAFT ile izole olarak düzeltilmiştir.
--   Bu dosyadaki DML ve RLS politika temizlikleri ise TRUNCATE ile ilişkisizdir;
--   canlıdaki Python ingestion script'leri (upload_books_to_supabase.py) artık
--   SUPABASE_SERVICE_ROLE_KEY kullandığı için kitap tablosundaki anonim yazma politikaları
--   güvenle kaldırılabilir.
--
-- Güvenlik Notu:
--   Sequence-wide döngüsel yetki iptalleri (REVOKE ALL ON ALL SEQUENCES) ve kontrolsüz
--   şema değişiklikleri (REVOKE CREATE ON SCHEMA) istemci bağımlılıklarını kırabileceği
--   için bu script'e dahil edilmemiştir.
-- =============================================================================

BEGIN;

SET LOCAL lock_timeout = '5s';

-- 1. 'books' KATALOĞUNDAKİ AÇIK ANONİM YAZMA POLİTİKALARININ KALDIRILMASI
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

-- 2. 'book_embeddings' TABLOSUNDA SELECT İZNİNİN KORUNMASI
-- Canlıdaki match_query_embeddings SECURITY INVOKER çalıştığı için SELECT yetkisi korunur.
REVOKE INSERT, UPDATE, DELETE ON public.book_embeddings FROM anon, authenticated, PUBLIC;
GRANT SELECT ON public.book_embeddings TO anon, authenticated;

-- 3. KULLANICI TABLOLARINDAN 'anon' YAZMA YETKİLERİNİN KALDIRILMASI
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

COMMIT;
