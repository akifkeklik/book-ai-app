-- =============================================================================
-- [PRODUCTION DEPLOYMENT]
-- GRUP 1: TRUNCATE YETKİ SIZINTISI GİDERME (STAGE 1 & STAGE 2)
-- =============================================================================
-- Dosya: backend/scripts/hardening/01_PROD_revoke_dangerous_privileges_stage1_stage2.sql
-- Ortam: Production (Supabase SQL Editor / psql -U postgres)
--
-- KAPSAM VE MİMARİ:
--   AŞAMA 1 (STAGE 1): 7 Hedef Tabloda TRUNCATE İzinlerinin Kaldırılması (P0)
--     - 6 çekirdek uygulama tablosu: books, book_embeddings, favorites,
--       user_activities, user_interactions, user_profiles.
--     - 1 operasyonel/test artefaktı: test_halfvec (varsa güvenle işlenir, yoksa atlanır).
--     - 'anon', 'authenticated' ve 'PUBLIC' rollerinden TRUNCATE yetkisi tamamen alınır.
--     - PostgreSQL'de TRUNCATE komutu RLS (Row Level Security) kurallarını baypas ettiği
--       için istemci rollerinde bulunması kritik güvenlik açığıdır.
--     - Bağımsız transaction içinde uygulanır ve gerçek katalog kontrolleriyle doğrulanır.
--
--   AŞAMA 2 (STAGE 2): 'postgres' Rolü Varsayılan ACL (DEFAULT PRIVILEGES) Düzeltmesi
--     - 'postgres' ve geçerli oturum rolü bağlamında gelecekte oluşturulacak tablolar
--       için varsayılan TRUNCATE hibelerini iptal eder.
--     - Hem 'public' şemasını (IN SCHEMA public) hem de global düzeydeki
--       (defaclnamespace = 0 / tüm şemalar) varsayılan şablonları kapsar.
--     - 'postgres' rolü kendi varsayılan haklarını değiştirmeye tam yetkilidir.
--     - Bağımsız transaction içinde uygulanır ve gerçek katalog kontrolleriyle doğrulanır.
--
--   STAGE 3 KAPSAM DIŞI BIRAKILMA GEREKÇESİ (AYRI BELGELENMİŞ PLATFORM ENGELİ):
--     - Supabase yönetilen mimarisinde 'postgres' kullanıcısı superuser değildir ve
--       'supabase_admin' rolünün üyesi değildir.
--     - PostgreSQL güvenlik kuralları gereği (ALTER DEFAULT PRIVILEGES FOR ROLE) bir rol
--       yalnızca kendisinin veya üyesi olduğu rolün varsayılan yetkilerini değiştirebilir.
--     - Rol yetkisi devri veya yetki yükseltmesi (privilege escalation) yapılması
--       güvenlik ilkeleri nedeniyle KESİNLİKLE YASAKTIR.
--     - Bu sebeple Stage 3 bu dosyada yer almaz; Stage 1 ve Stage 2 sıfır yetki sorunuyla,
--       bağımsız ve güvenli olarak 'postgres' rolüyle uygulanabilir.
--     - 'supabase_admin' için kalan 2 adet varsayılan TRUNCATE kaydı, doğrudan
--       'supabase_admin' / superuser bağlantısı veya Supabase platform destek bileti
--       aracılığıyla ayrı bir operasyon olarak ele alınmalıdır.
--
-- OPERASYONEL GÜVENCELER:
--   - DDL Atomikliği: Her aşama kendi BEGIN ... COMMIT bloğuna sahiptir.
--   - Veri Kaybı Riski: Sıfır (DML DELETE/TRUNCATE içermez; veri silinmez).
--   - Kesinti Riski: Sıfır (İstemciler TRUNCATE kullanmaz; SELECT/INSERT/UPDATE/DELETE etkilenmez).
--   - Kilit Güvenliği: Her aşama SET LOCAL lock_timeout = '5s' ile korunur.
--   - Fail-Closed Denetim: Her aşama sonunda gerçek katalog sorgularıyla doğrulama yapılır;
--     herhangi bir sızıntı tespit edilirse açık hata fırlatılarak transaction geri alınır.
-- =============================================================================


-- =============================================================================
-- AŞAMA 1: MEVCUT 7 TABLODAKİ TRUNCATE YETKİLERİNİN GERİ ALINMASI (P0 GÜVENLİK)
-- =============================================================================
BEGIN;

-- Kilit kuyruğu tıkanmalarını önlemek için güvenli lock_timeout
SET LOCAL lock_timeout = '5s';

-- 1.1 ÖN KOŞUL KONTROLÜ (FAIL-CLOSED)
-- Çekirdek uygulama tablolarının eksiksiz varlığı doğrulanır.
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
        RAISE EXCEPTION 'Aşama 1 Ön Koşul Başarısız: Eksik çekirdek tablolar var: %', missing_tables;
    END IF;
END $$;


-- 1.2 ÇEKİRDEK TABLOLARDA TRUNCATE YETKİLERİNİN GERİ ALINMASI
-- anon, authenticated ve PUBLIC rollerinden TRUNCATE yetkisi kesin olarak geri alınır.
REVOKE TRUNCATE ON public.books FROM anon, authenticated, PUBLIC;
REVOKE TRUNCATE ON public.book_embeddings FROM anon, authenticated, PUBLIC;
REVOKE TRUNCATE ON public.favorites FROM anon, authenticated, PUBLIC;
REVOKE TRUNCATE ON public.user_activities FROM anon, authenticated, PUBLIC;
REVOKE TRUNCATE ON public.user_interactions FROM anon, authenticated, PUBLIC;
REVOKE TRUNCATE ON public.user_profiles FROM anon, authenticated, PUBLIC;


-- 1.3 OPERASYONEL / TEST ARTEFAKTI (test_halfvec) TRUNCATE YETKİSİNİN GERİ ALINMASI
-- Canlı veritabanındaki test_halfvec tablosunun yetkisi güvenle sıkılaştırılır.
-- Tablo mevcut değilse (temiz CI / staging ortamı) güvenle atlanır.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND c.relname = 'test_halfvec' AND c.relkind = 'r'
    ) THEN
        EXECUTE 'REVOKE TRUNCATE ON public.test_halfvec FROM anon, authenticated, PUBLIC';
        RAISE NOTICE 'Aşama 1: test_halfvec operasyonel artefaktı üzerinde TRUNCATE yetkisi geri alındı.';
    ELSE
        RAISE NOTICE 'Aşama 1: test_halfvec tablosu mevcut değil (Temiz/CI ortamı), adım atlandı.';
    END IF;
END $$;


-- 1.4 AŞAMA 1 UYGULAMA SONRASI DOĞRULAMA (FAIL-CLOSED)
-- 7 hedef tablonun hiçbirinde anon, authenticated veya PUBLIC rollerine doğrudan
-- veya miras yoluyla TRUNCATE yetkisi kalmadığı katalogdan teyit edilir.
DO $$
DECLARE
    table_truncate_leaks INTEGER;
    public_truncate_leaks INTEGER;
    leaky_details TEXT;
BEGIN
    -- İstemci rolleri (anon, authenticated) efektif TRUNCATE yetkisi denetimi
    SELECT count(*), string_agg(t.relname || ' (' || r.rolname || ')', ', ')
    INTO table_truncate_leaks, leaky_details
    FROM pg_class t
    JOIN pg_namespace n ON n.oid = t.relnamespace
    CROSS JOIN (VALUES ('anon'), ('authenticated')) AS r(rolname)
    WHERE n.nspname = 'public'
      AND t.relkind = 'r'
      AND t.relname IN ('books', 'book_embeddings', 'favorites', 'user_activities', 'user_interactions', 'user_profiles', 'test_halfvec')
      AND has_table_privilege(r.rolname, t.oid, 'TRUNCATE') = true;

    IF table_truncate_leaks > 0 THEN
        RAISE EXCEPTION 'Uygulama sonrası doğrulama başarısız: [Aşama 1] % adet hedef tabloda istemci TRUNCATE yetkisi hala açık: %', table_truncate_leaks, leaky_details;
    END IF;

    -- Katalog düzeyinde PUBLIC sözde rolüne (grantee = 0) doğrudan hibe denetimi
    SELECT count(*), string_agg(t.relname || ' (PUBLIC)', ', ')
    INTO public_truncate_leaks, leaky_details
    FROM pg_class t
    JOIN pg_namespace n ON n.oid = t.relnamespace
    WHERE n.nspname = 'public'
      AND t.relkind = 'r'
      AND t.relname IN ('books', 'book_embeddings', 'favorites', 'user_activities', 'user_interactions', 'user_profiles', 'test_halfvec')
      AND EXISTS (
          SELECT 1 FROM aclexplode(COALESCE(t.relacl, acldefault('r', t.relowner))) a
          WHERE a.grantee = 0 AND a.privilege_type = 'TRUNCATE'
      );

    IF public_truncate_leaks > 0 THEN
        RAISE EXCEPTION 'Uygulama sonrası doğrulama başarısız: [Aşama 1] % adet hedef tabloda PUBLIC TRUNCATE hibesi tespit edildi: %', public_truncate_leaks, leaky_details;
    END IF;

    RAISE NOTICE 'BAŞARILI [AŞAMA 1]: 7 hedef tablodaki TRUNCATE yetkileri sıfırlandı ve doğrulandı.';
END $$;

COMMIT;


-- =============================================================================
-- AŞAMA 2: 'postgres' SAHİP BAĞLAMINDA VARSAYILAN TRUNCATE ACL DÜZELTMESİ
-- =============================================================================
BEGIN;

SET LOCAL lock_timeout = '5s';

-- 2.1 'postgres' Sahip Bağlamında 'public' Şeması Varsayılan TRUNCATE İptali
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE TRUNCATE ON TABLES FROM anon, authenticated, PUBLIC;

-- 2.2 'postgres' Sahip Bağlamında Global (defaclnamespace = 0) Varsayılan TRUNCATE İptali
ALTER DEFAULT PRIVILEGES FOR ROLE postgres REVOKE TRUNCATE ON TABLES FROM anon, authenticated, PUBLIC;

-- 2.3 Geçerli Oturum Rolü Bağlamında 'public' Şeması ve Global Varsayılan TRUNCATE İptali
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE TRUNCATE ON TABLES FROM anon, authenticated, PUBLIC;
ALTER DEFAULT PRIVILEGES REVOKE TRUNCATE ON TABLES FROM anon, authenticated, PUBLIC;

-- 2.4 AŞAMA 2 UYGULAMA SONRASI DOĞRULAMA (FAIL-CLOSED)
-- 'postgres' sahipliğinde hem public şemasında hem global düzeyde hiçbir TRUNCATE
-- varsayılan hibesi kalmadığı katalogdan teyit edilir.
DO $$
DECLARE
    postgres_default_leaks INTEGER;
    postgres_leaky_details TEXT;
BEGIN
    SELECT count(*), 
           COALESCE(string_agg(
               rol.rolname || ' -> ' || 
               CASE acl.grantee WHEN 0 THEN 'PUBLIC' ELSE COALESCE(gr.rolname, 'OID:' || acl.grantee::text) END || 
               ' (' || acl.privilege_type || ' in ' || COALESCE(n.nspname, 'GLOBAL') || ')', 
               '; '
           ), 'YOK')
    INTO postgres_default_leaks, postgres_leaky_details
    FROM pg_default_acl d
    JOIN pg_roles rol ON rol.oid = d.defaclrole
    LEFT JOIN pg_namespace n ON n.oid = d.defaclnamespace
    CROSS JOIN LATERAL aclexplode(d.defaclacl) acl
    LEFT JOIN pg_roles gr ON gr.oid = acl.grantee
    WHERE d.defaclobjtype = 'r'
      AND (n.nspname = 'public' OR d.defaclnamespace = 0)
      AND acl.privilege_type = 'TRUNCATE'
      AND (
          acl.grantee = 0 
          OR gr.rolname IN ('anon', 'authenticated', 'public')
      )
      AND rol.rolname = 'postgres';

    IF postgres_default_leaks > 0 THEN
        RAISE EXCEPTION 'Uygulama sonrası doğrulama başarısız: [Aşama 2] "postgres" rolü için % adet varsayılan (DEFAULT ACL) TRUNCATE sızıntısı hala açık: %', postgres_default_leaks, postgres_leaky_details;
    END IF;

    RAISE NOTICE 'BAŞARILI [AŞAMA 2]: "postgres" rolü için public ve global varsayılan TRUNCATE izinleri sıfırlandı ve doğrulandı.';
END $$;

COMMIT;

-- =============================================================================
-- STAGE 3 PLATFORM ENGELİ VE DOĞRULANMIŞ CANLI DURUM NOTU (UYGULAMA DIŞI):
-- 1. DOĞRULANMIŞ CANLI DURUM (PRODUCTION VERIFIED):
--    - Aşama 1 (7 hedef tabloda TRUNCATE yetkisi): 0 satır sızıntı (BAŞARILI).
--    - Aşama 2 ('postgres' rolü varsayılan TRUNCATE yetkileri): 0 satır sızıntı (BAŞARILI).
-- 2. KALAN PLATFORM BULGUSU:
--    - 'supabase_admin' rolü için public şemasında kalan 2 adet varsayılan TRUNCATE kaydı,
--      Supabase PostgreSQL yetki sınırları nedeniyle 'postgres' rolüyle değiştirilemez.
--    - 'postgres' kullanıcısı superuser değildir ve 'supabase_admin' rolünün üyesi değildir.
--    - Rol yetkisi devri veya yetki yükseltmesi yapılması güvenlik ilkeleri gereğince yasaktır.
--    - Bu işlem yalnızca doğrudan yetkili platform bağlantısı veya Supabase platform
--      destek bileti ile tamamlanmalıdır (Bkz: backend/scripts/hardening/README.md Bölüm 5).
-- =============================================================================
