-- =============================================================================
-- [DRAFT / PRODUCTION-GRADE STAGED REMEDIATION]
-- GRUP 1: TRUNCATE YETKİ SIZINTISI GİDERME VE GÜVENLİK SIKILAŞTIRMASI
-- =============================================================================
-- Dosya: backend/scripts/hardening/01_DRAFT_revoke_dangerous_privileges.sql
--
-- MİMARİ VE GÜVENLİK AŞAMALARI (THREE-STAGE ARCHITECTURE):
--   AŞAMA 1 (STAGE 1): Mevcut 7 Tabloda TRUNCATE İzinlerinin Kaldırılması (P0)
--     - 6 çekirdek uygulama tablosu (books, book_embeddings, favorites,
--       user_activities, user_interactions, user_profiles) + test_halfvec artefaktı.
--     - 'anon', 'authenticated' ve 'PUBLIC' rollerinden TRUNCATE kesin olarak alınır.
--     - 'postgres' rolü tablo sahibi olarak tam yetkilidir. Bağımsız transaction'da
--       çalışır; başarılı olduğunda kalıcılaşır (COMMIT).
--
--   AŞAMA 2 (STAGE 2): 'postgres' Rolü Varsayılan ACL (DEFAULT PRIVILEGES) Düzeltmesi
--     - 'postgres' ve geçerli oturum rolü bağlamında gelecekte oluşturulacak tablolar
--       için varsayılan TRUNCATE hibelerini iptal eder.
--     - Hem 'public' şemasını (IN SCHEMA public) hem de global düzeydeki
--       (defaclnamespace = 0 / tüm şemalar) varsayılan şablonları kapsar.
--     - 'postgres' rolü kendi varsayılan haklarını değiştirmeye tam yetkilidir.
--     - Bağımsız transaction'da çalışır ve doğrulanır (COMMIT).
--
--   AŞAMA 3 (STAGE 3): 'supabase_admin' Rolü Varsayılan ACL Düzeltmesi (Platform Engeli)
--     - 'supabase_admin' bağlamında varsayılan TRUNCATE hibelerini iptal etmeyi hedefler.
--     - SUPABASE POSTGRESQL YETKİ SINIRI:
--       * 'postgres' kullanıcısı yönetilen Supabase'de superuser DEĞİLDİR ve
--         'supabase_admin' rolünün üyesi DEĞİLDİR.
--       * PostgreSQL kuralları (ALTER DEFAULT PRIVILEGES FOR ROLE) gereği bir rol
--         yalnızca kendisinin veya üyesi olduğu rolün varsayılan yetkilerini değiştirebilir.
--       * Rol yetkisi devri veya yetki yükseltmesi (privilege escalation)
--         yapılması güvenlik ilkeleri nedeniyle KESİNLİKLE YASAKTIR.
--       * Aşama 3, Aşama 1 ve 2'den tamamen izoledir. Standart 'postgres' oturumunda
--         açık sızıntılar tespit edildiğinde hata fırlatarak (fail-closed) işlemi durdurur;
--         ancak daha önce COMMIT edilmiş olan Aşama 1 ve 2'yi GERİ ALMAZ.
--       * Aşama 3 ancak doğrudan 'supabase_admin' / superuser bağlantısı ile veya
--         Supabase platform destek bileti ile tamamlanabilir.
--
-- DOĞRULANMIŞ CANLI BULGULAR:
--   - 7 tabloda anon ve authenticated için toplam 14 adet açık TRUNCATE hibesi.
--   - pg_default_acl kataloğunda postgres (2 adet) ve supabase_admin (2 adet)
--     olmak üzere toplam 4 adet varsayılan TRUNCATE hibesi.
--
-- GÜVENCELER:
--   - DDL Transaction Atomikliği: Her aşama kendi bağımsız BEGIN...COMMIT bloğuna sahiptir.
--   - Veri Kaybı Riski: Sıfır (DML DELETE/TRUNCATE içermez; veri silinmez).
--   - İstemci Çalışma Riski: Sıfır (İstemciler TRUNCATE kullanmaz).
--   - Kilit Güvenliği: Her aşama başında SET LOCAL lock_timeout = '5s' ile korunur.
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
-- TRUNCATE komutu PostgreSQL mimarisinde RLS kurallarını tamamen baypas eder.
-- anon, authenticated ve PUBLIC rollerinden TRUNCATE yetkisi kesin olarak geri alınır.
REVOKE TRUNCATE ON public.books FROM anon, authenticated, PUBLIC;
REVOKE TRUNCATE ON public.book_embeddings FROM anon, authenticated, PUBLIC;
REVOKE TRUNCATE ON public.favorites FROM anon, authenticated, PUBLIC;
REVOKE TRUNCATE ON public.user_activities FROM anon, authenticated, PUBLIC;
REVOKE TRUNCATE ON public.user_interactions FROM anon, authenticated, PUBLIC;
REVOKE TRUNCATE ON public.user_profiles FROM anon, authenticated, PUBLIC;


-- 1.3 OPERASYONEL / TEST ARTEFAKTI (test_halfvec) TRUNCATE YETKİSİNİN GERİ ALINMASI
-- Canlı veritabanında pgvector halfvec desteğini test etmek amacıyla oluşturulmuş olan
-- public.test_halfvec tablosu operasyonel bir test artefaktıdır. Canlıda TRUNCATE sızıntısı
-- barındırmaktadır. Tablo silinmez veya bozulmaz; yetkisi sıkılaştırılır.
-- Temiz/CI ortamlarında yoksa güvenle atlanır.
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
-- AŞAMA 3: 'supabase_admin' ROLÜ VARSAYILAN ACL DÜZELTMESİ (PLATFORM ENGELİ)
-- =============================================================================
BEGIN;

SET LOCAL lock_timeout = '5s';

DO $$
DECLARE
    admin_exists BOOLEAN;
    is_authorized BOOLEAN;
    admin_leaks INTEGER;
    admin_leaky_details TEXT;
BEGIN
    SELECT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'supabase_admin') INTO admin_exists;

    IF NOT admin_exists THEN
        RAISE NOTICE 'BİLGİ [AŞAMA 3]: "supabase_admin" rolü bu veritabanında mevcut değil (Temiz/CI ortamı), adım atlandı.';
        RETURN;
    END IF;

    -- Oturum yetkisinin denetimi: Rol supabase_admin üyesi mi veya superuser mı?
    SELECT (
        pg_has_role(current_user, 'supabase_admin', 'USAGE') 
        OR EXISTS (SELECT 1 FROM pg_roles WHERE rolname = current_user AND rolsuper = true)
    ) INTO is_authorized;

    -- Mevcut açık sızıntıların katalogdan taranması
    SELECT count(*), 
           COALESCE(string_agg(
               rol.rolname || ' -> ' || 
               CASE acl.grantee WHEN 0 THEN 'PUBLIC' ELSE COALESCE(gr.rolname, 'OID:' || acl.grantee::text) END || 
               ' (' || acl.privilege_type || ' in ' || COALESCE(n.nspname, 'GLOBAL') || ')', 
               '; '
           ), 'YOK')
    INTO admin_leaks, admin_leaky_details
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
      AND rol.rolname = 'supabase_admin';

    IF is_authorized THEN
        -- Yetkili bağlam (supabase_admin veya superuser): Hem public şemasında hem globalde iptal et
        BEGIN
            EXECUTE 'ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public REVOKE TRUNCATE ON TABLES FROM anon, authenticated, PUBLIC';
            EXECUTE 'ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin REVOKE TRUNCATE ON TABLES FROM anon, authenticated, PUBLIC';
            RAISE NOTICE 'SUCCESS: supabase_admin rolü için varsayılan TRUNCATE yetkisi kaldırıldı.';
        EXCEPTION WHEN insufficient_privilege THEN
            RAISE EXCEPTION 'DEPLOYMENT_BLOCKED: [AŞAMA 3] Yetki kontrolü başarılı görünmesine rağmen insufficient_privilege hatası alındı.';
        END;

        -- Düzeltme sonrası doğrulama (Fail-Closed)
        SELECT count(*), 
               COALESCE(string_agg(
                   rol.rolname || ' -> ' || 
                   CASE acl.grantee WHEN 0 THEN 'PUBLIC' ELSE COALESCE(gr.rolname, 'OID:' || acl.grantee::text) END || 
                   ' (' || acl.privilege_type || ' in ' || COALESCE(n.nspname, 'GLOBAL') || ')', 
                   '; '
               ), 'YOK')
        INTO admin_leaks, admin_leaky_details
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
          AND rol.rolname = 'supabase_admin';

        IF admin_leaks > 0 THEN
            RAISE EXCEPTION 'Uygulama sonrası doğrulama başarısız: [Aşama 3] "supabase_admin" için % adet varsayılan TRUNCATE sızıntısı hala açık: %', admin_leaks, admin_leaky_details;
        END IF;

        RAISE NOTICE 'BAŞARILI [AŞAMA 3]: "supabase_admin" rolü için public ve global varsayılan TRUNCATE izinleri sıfırlandı ve doğrulandı.';
    ELSE
        -- Yetkisiz bağlam ('postgres' rolü):
        -- PostgreSQL kuralı: ALTER DEFAULT PRIVILEGES FOR ROLE yalnızca o rolün üyeleri veya superuser tarafından çalıştırılabilir.
        -- Rol yetkisi devri veya yetki yükseltmesi yapılması KESİNLİKLE YASAKTIR.
        IF admin_leaks > 0 THEN
            -- Sızıntı açık ve çözümlenemiyor: Kesinlikle başarılı raporlanamaz!
            RAISE EXCEPTION 'DEPLOYMENT_BLOCKED: [AŞAMA 3 PLATFORM ENGELİ] "supabase_admin" varsayılan yetkileri (DEFAULT PRIVILEGES) değiştirilemedi: Geçerli oturum rolü (%) "supabase_admin" rolünün üyesi veya superuser değildir. PostgreSQL kuralları gereği (ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin) yalnızca o rolün üyeleri veya superuser tarafından çalıştırılabilir. Yetki yükseltmesi (privilege escalation) yapılması güvenlik kuralları gereği kesinlikle engellenmiştir. Aşama 1 (7 mevcut tablo) ve Aşama 2 (postgres varsayılan ACL) önceki bloklarda başarıyla COMMIT edilmiş ve kalıcıdır. Bu aşamada % adet varsayılan TRUNCATE sızıntısı açık kalmıştır (%) ve doğrudan supabase_admin / superuser bağlantısı veya Supabase platform destek bileti ile tamamlanmalıdır.', current_user, current_user, admin_leaks, admin_leaky_details;
        ELSE
            RAISE NOTICE 'BİLGİ [AŞAMA 3]: "supabase_admin" için açık varsayılan TRUNCATE sızıntısı tespit edilmedi.';
        END IF;
    END IF;
END $$;

COMMIT;
