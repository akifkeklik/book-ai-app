from pathlib import Path

SCRIPTS_DIR = Path(__file__).parent.parent / "scripts"
CI_STUBS = Path(__file__).parent.parent / "ci_stubs.sql"

def test_migration_scripts_ordering_and_naming():
    """Ensure migrations follow strictly sequential numbering."""
    sql_files = sorted([f.name for f in SCRIPTS_DIR.glob("*.sql")])
    assert len(sql_files) >= 9
    assert sql_files[0] == "00_init_books.sql"
    assert sql_files[1] == "01_schema.sql"
    assert sql_files[2] == "02_phase3_migration.sql"
    assert sql_files[3] == "03_phase3_embeddings.sql"
    assert sql_files[4] == "04_phase3_hybrid.sql"
    assert sql_files[5] == "05_phase3_performance.sql"
    assert sql_files[6] == "06_phase2_rag.sql"
    assert sql_files[7] == "07_phase3_collections.sql"
    assert sql_files[8] == "08_user_profiles_and_activities.sql"

def test_vector_dimension_is_consistently_3072():
    """Verify that vector dimensions in all SQL migration scripts match gemini-embedding-2 (3072 dims)."""
    scripts = {
        "03_phase3_embeddings.sql": SCRIPTS_DIR / "03_phase3_embeddings.sql",
        "04_phase3_hybrid.sql": SCRIPTS_DIR / "04_phase3_hybrid.sql",
        "05_phase3_performance.sql": SCRIPTS_DIR / "05_phase3_performance.sql",
        "06_phase2_rag.sql": SCRIPTS_DIR / "06_phase2_rag.sql",
    }

    for name, path in scripts.items():
        content = path.read_text(encoding="utf-8")
        # Ensure 1536 is NOT used anywhere
        assert "1536" not in content, f"{name} contains outdated 1536 dimension"
        # Ensure 3072 is present
        assert "3072" in content, f"{name} does not reference required 3072 vector dimension"

def test_favorites_table_schema_consistency():
    """Verify that favorites table uses canonical column 'book_id' across all scripts."""
    # 00_init_books.sql
    init_sql = (SCRIPTS_DIR / "00_init_books.sql").read_text(encoding="utf-8")
    assert "book_id TEXT NOT NULL" in init_sql
    assert "UNIQUE(user_id, book_id)" in init_sql

    # 02_phase3_migration.sql
    mig_02_sql = (SCRIPTS_DIR / "02_phase3_migration.sql").read_text(encoding="utf-8")
    assert "SELECT user_id, book_id, 'like', added_at" in mig_02_sql
    assert "NEW.book_id" in mig_02_sql

    # ci_stubs.sql
    ci_stubs_sql = CI_STUBS.read_text(encoding="utf-8")
    assert "book_id TEXT" in ci_stubs_sql
    assert "UNIQUE(user_id, book_id)" in ci_stubs_sql

def test_init_books_defines_canonical_books_catalog():
    """Verify that 00_init_books.sql defines the complete public.books catalog table."""
    init_sql = (SCRIPTS_DIR / "00_init_books.sql").read_text(encoding="utf-8")
    assert "CREATE TABLE IF NOT EXISTS public.books" in init_sql
    for col in ["isbn13 TEXT PRIMARY KEY", "title TEXT NOT NULL", "authors TEXT", "categories TEXT", "description TEXT", "thumbnail TEXT", "average_rating NUMERIC"]:
        assert col in init_sql, f"Missing column {col} in 00_init_books.sql"


def test_hardening_02_rollback_archive_comprehensive_schema_validation():
    """Verify 02 rollback validates all columns, types, and constraints rather than just a single column."""
    hardening_dir = SCRIPTS_DIR / "hardening"
    rollback_02 = (hardening_dir / "02_DRAFT_reconcile_user_profiles_rollback.sql").read_text(encoding="utf-8")

    # Multi-column and type checks
    assert "column_name = 'archive_id'" in rollback_02
    assert "data_type IN ('bigint', 'integer')" in rollback_02
    assert "c.contype = 'p'" in rollback_02
    assert "a.attname = 'archive_id'" in rollback_02
    assert "column_name = 'user_profile_snapshot'" in rollback_02
    assert "data_type = 'jsonb'" in rollback_02
    assert "is_nullable = 'NO'" in rollback_02
    assert "column_name = 'archived_at'" in rollback_02
    assert "data_type IN ('timestamp with time zone', 'timestamp without time zone')" in rollback_02

    # Incompatible NOT NULL without default constraint check
    assert "is_nullable = 'NO'" in rollback_02
    assert "column_default IS NULL" in rollback_02
    assert "column_name NOT IN ('archive_id', 'archived_at', 'user_profile_snapshot')" in rollback_02

    # Leaky RLS policy check
    assert "FROM pg_policies" in rollback_02
    assert "tablename = '_archived_user_profiles_rollback_backup'" in rollback_02

    # Fail-closed exceptions for incompatible existing archive schemas
    assert "archive_id PRIMARY KEY kısıtı eksik" in rollback_02
    assert "archive_id otomatik artış (sequence/default/identity) kuralı eksik" in rollback_02
    assert "(column_default IS NOT NULL OR is_identity = 'YES')" in rollback_02
    assert "user_profile_snapshot JSONB NOT NULL kolonu eksik veya nullability kuralı ihlal edilmiş" in rollback_02
    assert "archived_at kolonu eksik veya veri tipi uyumsuz" in rollback_02
    assert "varsayılan değeri olmayan uyumsuz zorunlu (NOT NULL) harici kolonlar mevcut" in rollback_02


def test_hardening_02_rollback_archive_creation_when_table_absent():
    """Verify archive table is created with proper PK and timestamp defaults when absent."""
    hardening_dir = SCRIPTS_DIR / "hardening"
    rollback_02 = (hardening_dir / "02_DRAFT_reconcile_user_profiles_rollback.sql").read_text(encoding="utf-8")

    assert "CREATE TABLE public._archived_user_profiles_rollback_backup" in rollback_02
    assert "archive_id BIGSERIAL PRIMARY KEY" in rollback_02
    assert "archived_at TIMESTAMPTZ NOT NULL DEFAULT now()" in rollback_02
    assert "user_profile_snapshot JSONB NOT NULL" in rollback_02


def test_hardening_02_rollback_target_column_permutations_and_idempotency():
    """Verify rollback handles all target column combinations (all 3, some, none) idempotently."""
    hardening_dir = SCRIPTS_DIR / "hardening"
    rollback_02 = (hardening_dir / "02_DRAFT_reconcile_user_profiles_rollback.sql").read_text(encoding="utf-8")

    # Evaluates any of the 3 migration target columns
    assert "column_name IN ('user_id', 'preferred_authors', 'preferred_vibe')" in rollback_02
    # Individual IF EXISTS drops
    assert "ALTER TABLE public.user_profiles DROP COLUMN IF EXISTS user_id;" in rollback_02
    assert "ALTER TABLE public.user_profiles DROP COLUMN IF EXISTS preferred_authors;" in rollback_02
    assert "ALTER TABLE public.user_profiles DROP COLUMN IF EXISTS preferred_vibe;" in rollback_02
    # Idempotent skip message when columns are already gone
    assert "user_profiles hedef kolonları zaten silinmiş olduğundan yeni snapshot eklenmedi (Idempotent)" in rollback_02


def test_hardening_02_rollback_preserves_preexisting_columns():
    """Verify rollback strictly preserves onboarding_completed, id, and other pre-migration columns."""
    hardening_dir = SCRIPTS_DIR / "hardening"
    rollback_02 = (hardening_dir / "02_DRAFT_reconcile_user_profiles_rollback.sql").read_text(encoding="utf-8")

    assert "DROP COLUMN IF EXISTS onboarding_completed" not in rollback_02
    assert "DROP COLUMN IF EXISTS id" not in rollback_02
    assert "DROP COLUMN IF EXISTS preferred_genres" not in rollback_02
    assert "DROP COLUMN IF EXISTS created_at" not in rollback_02
    assert "DROP TABLE" not in rollback_02


def test_hardening_02_rollback_atomic_transaction_prevents_silent_drops():
    """Verify archive failures fail closed inside an atomic transaction, preventing silent column drops."""
    hardening_dir = SCRIPTS_DIR / "hardening"
    rollback_02 = (hardening_dir / "02_DRAFT_reconcile_user_profiles_rollback.sql").read_text(encoding="utf-8")

    # Transaction boundaries
    assert "BEGIN;" in rollback_02
    assert rollback_02.strip().endswith("COMMIT;")

    # Strict ordering: archive DO block must appear before any DROP COLUMN
    archive_pos = rollback_02.find("_archived_user_profiles_rollback_backup")
    drop_pos = rollback_02.find("ALTER TABLE public.user_profiles DROP COLUMN IF EXISTS user_id;")
    assert archive_pos != -1 and drop_pos != -1
    assert archive_pos < drop_pos, "Archival must occur strictly before DROP COLUMN"


def test_hardening_02_rollback_archive_ownership_and_rls_security():
    """Verify archive table has strict RLS, no PUBLIC access, and assigned ownership."""
    hardening_dir = SCRIPTS_DIR / "hardening"
    rollback_02 = (hardening_dir / "02_DRAFT_reconcile_user_profiles_rollback.sql").read_text(encoding="utf-8")

    assert "REVOKE ALL ON TABLE public._archived_user_profiles_rollback_backup FROM PUBLIC, anon, authenticated;" in rollback_02
    assert "GRANT SELECT, INSERT ON TABLE public._archived_user_profiles_rollback_backup TO service_role;" in rollback_02
    assert "ALTER TABLE public._archived_user_profiles_rollback_backup ENABLE ROW LEVEL SECURITY;" in rollback_02
    assert "ALTER TABLE public._archived_user_profiles_rollback_backup OWNER TO postgres;" in rollback_02


def test_hardening_04_rollback_rpc_restoration_integrity():
    """Verify 04 rollback uses atomic DROP before CREATE, cleans match_book_embeddings, and restores exact live ACL."""
    hardening_dir = SCRIPTS_DIR / "hardening"
    rollback_04 = (hardening_dir / "04_DRAFT_harden_vector_rpcs_rollback.sql").read_text(encoding="utf-8")

    # Must drop match_book_embeddings since it didn't exist in live Supabase
    assert "DROP FUNCTION IF EXISTS public.match_book_embeddings(text[], double precision, integer);" in rollback_04
    # Must atomically drop match_query_embeddings before recreating to remove parameter defaults & proconfig
    drop_rpc = "DROP FUNCTION IF EXISTS public.match_query_embeddings(vector, double precision, integer);"
    create_rpc = "CREATE FUNCTION public.match_query_embeddings("
    assert drop_rpc in rollback_04
    assert create_rpc in rollback_04
    assert rollback_04.find(drop_rpc) < rollback_04.find(create_rpc)
    # Must restore exact original ACL
    assert "GRANT EXECUTE ON FUNCTION public.match_query_embeddings(vector, double precision, integer) TO PUBLIC, anon, authenticated, service_role;" in rollback_04
    # Must NOT have DEFAULT expressions in rollback definition
    create_section = rollback_04[rollback_04.find(create_rpc):rollback_04.find("RETURNS TABLE")]
    assert "DEFAULT" not in create_section, "Rollback signature must not contain DEFAULT parameter expressions"
    # Must NOT use CASCADE (avoids silent dropping of dependent objects)
    assert "CASCADE" not in rollback_04
    # Must preserve ownership to postgres
    assert "OWNER TO postgres" in rollback_04


def test_hardening_01_rollback_failsafe_truncate_exclusion():
    """Verify 01 rollback never grants TRUNCATE privilege back to any client roles."""
    hardening_dir = SCRIPTS_DIR / "hardening"
    rollback_01 = (hardening_dir / "01_DRAFT_revoke_dangerous_privileges_rollback.sql").read_text(encoding="utf-8")

    assert "GRANT TRUNCATE" not in rollback_01
    assert "GRANT ALL" not in rollback_01
    assert "python_ekleme_izni" in rollback_01
    assert "python_guncelleme_izni" in rollback_01


def test_hardening_04_catalog_lifecycle_test_script_completeness():
    """Verify test_04_vector_rpc_catalog_lifecycle.sql covers all required catalog assertions."""
    lifecycle_sql = (SCRIPTS_DIR / "hardening" / "test_04_vector_rpc_catalog_lifecycle.sql").read_text(encoding="utf-8")

    # Roles and vector setup
    assert "CREATE EXTENSION IF NOT EXISTS vector;" in lifecycle_sql
    assert "CREATE ROLE anon;" in lifecycle_sql
    assert "CREATE ROLE authenticated;" in lifecycle_sql
    assert "CREATE ROLE service_role;" in lifecycle_sql

    # Baseline check
    assert "p_rec.prosecdef != false" in lifecycle_sql
    assert "p_rec.proconfig IS NOT NULL" in lifecycle_sql
    assert "p_rec.pronargdefaults != 0" in lifecycle_sql
    assert "has_function_privilege('public', p_rec.oid, 'EXECUTE')" in lifecycle_sql

    # Forward migration verification
    assert "mq_rec.prosecdef != false" in lifecycle_sql
    assert "search_path=public, pg_temp" in lifecycle_sql
    assert "mq_rec.pronargdefaults != 2" in lifecycle_sql
    assert "mq_rec.prosrc NOT LIKE '%safe_limit%'" in lifecycle_sql
    assert "PUBLIC rolünden EXECUTE izni geri alınmış olmalı" in lifecycle_sql
    assert "match_book_embeddings" in lifecycle_sql

    # Invalid arguments and safe limits check
    assert "ADIM 3.1: GÜVENLİ LİMİTLER VE GEÇERSİZ ARGÜMANLAR RUNTIME TESTİ" in lifecycle_sql
    assert "NULL query_embedding 0 satır dönmeliydi" in lifecycle_sql
    assert "Boş seed_book_ids 0 satır dönmeliydi" in lifecycle_sql

    # Dependency check without CASCADE
    assert "dependent_objects_still_exist" in lifecycle_sql
    assert "DROP FUNCTION public.match_query_embeddings" in lifecycle_sql

    # Post-rollback verification against baseline
    assert "Rollback sonrası match_book_embeddings tablodan/katalogdan silinmemiş" in lifecycle_sql
    assert "Rollback sonrası match_query_embeddings proconfig temizlenmeliydi" in lifecycle_sql
    assert "Rollback sonrası parametre varsayılanları 0 olmalı" in lifecycle_sql
    assert "Rollback sonrası PUBLIC rolüne EXECUTE yetkisi geri verilmiş olmalı" in lifecycle_sql
    assert "Fonksiyon sahibi postgres olmalı" in lifecycle_sql


def test_hardening_02_rollback_runtime_test_script_completeness():
    """Verify test_02_user_profiles_rollback_runtime.sql covers all 10 required scenarios."""
    runtime_02_sql = (SCRIPTS_DIR / "hardening" / "test_02_user_profiles_rollback_runtime.sql").read_text(encoding="utf-8")

    # Scenario 1: Table absent
    assert "SENARYO 1: ARŞİV TABLOSU YOKKEN ROLLBACK ÇALIŞTIRMA" in runtime_02_sql
    assert "c.contype = 'p' AND a.attname = 'archive_id'" in runtime_02_sql
    assert "column_default IS NOT NULL OR is_identity = 'YES'" in runtime_02_sql

    # Scenario 2: Correct table exists
    assert "SENARYO 2: ARŞİV TABLOSU DOĞRU ŞEMADA MEVCUTKEN TEKRAR ÇALIŞTIRMA" in runtime_02_sql

    # Scenario 3: Wrong data type fail-closed
    assert "SENARYO 3: ARŞİV TABLOSU YANLIŞ VERİ TİPİNE VEYA EKSİK KOLONA SAHİP" in runtime_02_sql

    # Scenario 4: Missing PK and sequence/default mismatch
    assert "SENARYO 4: EKSİK PRIMARY KEY VEYA UYUMSUZ NOT NULL KISITI OLAN ARŞİV TABLOSU" in runtime_02_sql
    assert "Eksik Otomatik Artış (Sequence/Default Uyumsuzluğu)" in runtime_02_sql

    # Scenario 5: Unexpected NOT NULL column without default
    assert "SENARYO 5: BEKLENMEYEN NOT NULL KOLON BULUNDUĞUNDA FAIL-CLOSED ENGELLEME" in runtime_02_sql

    # Scenario 6: Leaky RLS policy or unauthorized client access
    assert "SENARYO 6: SIZDIRICI RLS POLİTİKASI VEYA UYGUNSUZ ROL ERİŞİMİNDE FAIL-CLOSED ENGELLEME" in runtime_02_sql

    # Scenario 7: Column subsets (all, partial, none)
    assert "SENARYO 7: HEDEF KOLONLARIN TÜMÜ, BİR KISMI VEYA HİÇBİRİ OLMADIĞINDA DAVRANIŞ" in runtime_02_sql

    # Scenario 8: Archiving error and transaction atomicity
    assert "SENARYO 8: ARŞİVLEME HATASI SIRASINDA KOLONLARIN KORUNMASI VE TRANSACTION ATOMİKLİĞİ" in runtime_02_sql

    # Scenario 9: Preservation of original data
    assert "SENARYO 9: 'onboarding_completed', 'id', 'preferred_genres' KORUNMA KONTROLÜ" in runtime_02_sql
    assert "prof_rec.onboarding_completed != true" in runtime_02_sql
    assert "prof_rec.preferred_genres != '{\"Fiction\", \"Sci-Fi\"}'::text[]" in runtime_02_sql

    # Scenario 10: Safe repeated execution (Idempotency)
    assert "SENARYO 10: GÜVENLİ TEKRAR ÇALIŞTIRMA (TAM İDEMPOTENCY)" in runtime_02_sql


def test_hardening_02_reconcile_zero_data_loss_invariant():
    """Verify 02 migration enforces zero row loss invariant without rejecting empty test tables."""
    hardening_dir = SCRIPTS_DIR / "hardening"
    forward_02 = (hardening_dir / "02_DRAFT_reconcile_user_profiles.sql").read_text(encoding="utf-8")

    assert "libris.pre_profile_count" in forward_02
    assert "post_count < pre_count" in forward_02
    # Ensure spurious < 1 check is NOT present
    assert "current_count < 1" not in forward_02
    assert "post_count < 1" not in forward_02


def test_hardening_03_model_a_trigger_and_constraint_contract():
    """Verify 03 migration implements Model A: preserves reading status, safe backfill, safe trigger."""
    hardening_dir = SCRIPTS_DIR / "hardening"
    forward_03 = (hardening_dir / "03_DRAFT_reconcile_interactions_and_trigger.sql").read_text(encoding="utf-8")

    # Fail-closed approval barrier must be removed
    assert "MIGRATION 03 BLOKE EDİLMİŞTİR" not in forward_03
    assert "RAISE EXCEPTION" not in forward_03 or "Ön koşul başarısız" in forward_03

    # Expanded check constraint
    assert "CHECK (interaction_type IN ('like', 'dislike', 'want_to_read', 'reading', 'finished', 'favorite'))" in forward_03

    # Model A trigger implementation: DO NOTHING on insert conflict (preserves reading status)
    assert "ON CONFLICT (user_id, book_id) \n        DO NOTHING;" in forward_03 or "ON CONFLICT (user_id, book_id) DO NOTHING" in forward_03

    # Model A delete: only delete 'favorite' and 'like' (preserves reading status)
    assert "interaction_type IN ('favorite', 'like')" in forward_03

    # Safe function attributes
    assert "SECURITY DEFINER" in forward_03
    assert "SET search_path = public, pg_temp" in forward_03

    # Backfill with zero data loss
    assert "SELECT user_id, book_id, 'favorite', added_at" in forward_03


def test_hardening_03_rollback_safety_and_search_path():
    """Verify 03 rollback script safely downgrades while preserving security attributes."""
    hardening_dir = SCRIPTS_DIR / "hardening"
    rollback_03 = (hardening_dir / "03_DRAFT_reconcile_interactions_and_trigger_rollback.sql").read_text(encoding="utf-8")

    # Must have SECURITY DEFINER and search_path to prevent security regression
    assert "SECURITY DEFINER" in rollback_03
    assert "SET search_path = public, pg_temp" in rollback_03
    assert "OWNER TO postgres" in rollback_03

    # Must convert legacy types before restoring constraint
    assert "interaction_type = 'like'" in rollback_03
    assert "interaction_type = 'want_to_read'" in rollback_03
    assert "CHECK (interaction_type IN ('like', 'dislike', 'want_to_read', 'finished'))" in rollback_03


def test_hardening_03_runtime_test_script_completeness():
    """Verify test_03_interactions_and_trigger_runtime.sql covers all 10 Model A and deduplication scenarios."""
    runtime_03_sql = (SCRIPTS_DIR / "hardening" / "test_03_interactions_and_trigger_runtime.sql").read_text(encoding="utf-8")

    assert "SENARYO 1: Önceden etkileşimi olmayan kitabı favorileme" in runtime_03_sql
    assert "SENARYO 2: \"reading\" varken favorileme (Ezilmeme Kontrolü)" in runtime_03_sql
    assert "SENARYO 3: \"reading\" olan kitabı favoriden çıkarma" in runtime_03_sql
    assert "SENARYO 4: \"finished\" durumu koruma" in runtime_03_sql
    assert "SENARYO 5: \"dislike\" sinyali koruma" in runtime_03_sql
    assert "SENARYO 6: Saf favorinin silinmesi" in runtime_03_sql
    assert "SENARYO 7: Yinelenen favori engelleme" in runtime_03_sql
    assert "SENARYO 8: Backfill sırasında okuma durumlarına dokunulmaması" in runtime_03_sql
    assert "SENARYO 9: Kayıpsız mükerrer kayıt uzlaştırması ve arşivleme" in runtime_03_sql
    assert "SENARYO 10: Like ve Dislike çelişkisinde Fail-Closed denetimi" in runtime_03_sql
    assert "SENARYO 11: NULL veya boş book_id/user_id kayıtlarının kayıpsız arşivlenmesi" in runtime_03_sql


def test_preflight_script_no_has_table_privilege_public():
    """Verify preflight SQL never passes 'public' to has_table_privilege (which would fail in PostgreSQL)."""
    preflight_sql = (SCRIPTS_DIR / "preflight_database_hardening.sql").read_text(encoding="utf-8")

    assert "has_table_privilege('public'" not in preflight_sql
    assert "has_table_privilege('PUBLIC'" not in preflight_sql
    assert "has_table_privilege(\"public\"" not in preflight_sql
    assert "has_table_privilege(\"PUBLIC\"" not in preflight_sql


def test_preflight_script_uses_aclexplode_for_public_grantee_zero():
    """Verify preflight SQL uses aclexplode and grantee = 0 for catalog-level PUBLIC privileges."""
    preflight_sql = (SCRIPTS_DIR / "preflight_database_hardening.sql").read_text(encoding="utf-8")

    assert "aclexplode(COALESCE(tt.relacl, acldefault('r', tt.relowner)))" in preflight_sql
    assert "a.grantee = 0" in preflight_sql
    assert "truncate_inherited_from_public" in preflight_sql
    assert "pg_default_acl" in preflight_sql


def test_preflight_script_fails_clearly_on_missing_objects():
    """Verify preflight SQL has explicit fail-closed notices for missing tables, roles, and extensions."""
    preflight_sql = (SCRIPTS_DIR / "preflight_database_hardening.sql").read_text(encoding="utf-8")

    assert "FAIL: TABLO EKSİK (TABLE MISSING)" in preflight_sql
    assert "FAIL: Gerekli Supabase rolü veritabanında bulunamadı!" in preflight_sql
    assert "FAIL: pgvector eklentisi kurulu değil!" in preflight_sql
    assert "EXPECTED_WARNING: Canlıda henüz mevcut değil (04_DRAFT ile eklenecektir)" in preflight_sql


def test_preflight_script_consolidated_query_clean_union_types():
    """Verify section 12 consolidated preflight query explicitly casts all union columns to text."""
    preflight_sql = (SCRIPTS_DIR / "preflight_database_hardening.sql").read_text(encoding="utf-8")

    assert "BÖLÜM 12: TEK TIKLA ÇALIŞTIRILABİLİR KONSOLİDE PREFLIGHT ÖZET SORGUSU" in preflight_sql
    assert "'1. TRUNCATE_LEAKS'::text AS check_name" in preflight_sql
    assert "'2. USER_PROFILES_USER_ID_EXISTS'::text" in preflight_sql
    assert "'3. INTERACTIONS_DUPLICATE_PAIRS'::text" in preflight_sql
    assert "'4. INTERACTIONS_CHECK_STATUS'::text" in preflight_sql
    assert "'5. VECTOR_RPC_MATCH_BOOK_EMBEDDINGS'::text" in preflight_sql


def test_03_lossless_duplicate_reconciliation_and_archiving():
    """Verify 03 migration replaces silent delete with lossless archiving, favorite preservation, and fail-closed logic."""
    hardening_dir = SCRIPTS_DIR / "hardening"
    forward_03 = (hardening_dir / "03_DRAFT_reconcile_interactions_and_trigger.sql").read_text(encoding="utf-8")

    # Must NOT have unarchived arbitrary delete (a.id < b.id)
    assert "DELETE FROM public.user_interactions a USING public.user_interactions b\n        WHERE a.id < b.id" not in forward_03
    assert "a.id < b.id" not in forward_03

    # Must define dedicated duplicate archive table with security hardening
    assert "CREATE TABLE IF NOT EXISTS public._archived_user_interactions_duplicate_backup" in forward_03
    assert "full_row_snapshot JSONB NOT NULL" in forward_03
    assert "REVOKE ALL ON TABLE public._archived_user_interactions_duplicate_backup FROM PUBLIC, anon, authenticated;" in forward_03
    assert "GRANT SELECT, INSERT ON TABLE public._archived_user_interactions_duplicate_backup TO service_role;" in forward_03

    # Must snapshot duplicates before deduplication
    assert "PRE_DEDUPLICATION_SNAPSHOT" in forward_03

    # Must preserve favorite relationship into public.favorites
    assert "INSERT INTO public.favorites (user_id, book_id, book_title, added_at)" in forward_03

    # Must fail closed on irreconcilable like + dislike conflicts
    assert "Çözümlenemez çelişki kontrolü" in forward_03
    assert "count(DISTINCT interaction_type) > 1" in forward_03
    assert "çözümlenemeyen çelişkili etkileşim kaydı (like ve dislike aynı anda)" in forward_03

    # Must rank interactions deterministically (finished > reading > want_to_read > ...)
    assert "WHEN 'finished' THEN 1" in forward_03
    assert "WHEN 'reading' THEN 2" in forward_03
    assert "WHEN 'want_to_read' THEN 3" in forward_03


def test_deployment_checklist_uses_service_role_key_and_procedure_a1():
    """Verify deployment checklist requires SUPABASE_SERVICE_ROLE_KEY and references hardening Procedure A.1."""
    docs_dir = Path(__file__).parent.parent.parent / "docs"
    checklist_md = (docs_dir / "V1_DEPLOYMENT_EXECUTION_CHECKLIST.md").read_text(encoding="utf-8")

    assert "SUPABASE_ANON_KEY=\"<SERVICE_ROLE_KEY>\"" not in checklist_md
    assert "SUPABASE_SERVICE_ROLE_KEY=\"<SERVICE_ROLE_KEY>\"" in checklist_md
    assert "$env:SUPABASE_SERVICE_ROLE_KEY=\"<SERVICE_ROLE_KEY>\"" in checklist_md
    assert "Procedure A.1: Production Database Hardening & Reconciliation" in checklist_md
    assert "01_DRAFT_revoke_dangerous_privileges.sql" in checklist_md
    assert "02_DRAFT_reconcile_user_profiles.sql" in checklist_md
    assert "03_DRAFT_reconcile_interactions_and_trigger.sql" in checklist_md
    assert "04_DRAFT_harden_vector_rpcs.sql" in checklist_md


def test_validation_checklist_group_3_model_a_not_blocked():
    """Verify validation checklist does not mark Group 3 Model A as BLOKE."""
    docs_dir = Path(__file__).parent.parent.parent / "docs"
    validation_md = (docs_dir / "database" / "validation-checklist.md").read_text(encoding="utf-8")

    assert "[ ] **BLOKE**" not in validation_md
    assert "Grup 3 (user_interactions Model A / B) kararı verildi mi? | [ ]" not in validation_md
    assert "Grup 3 (Model A Mimarisi & Kayıpsız Arşivleme) onaylandı mı? | [x] ONAYLANDI" in validation_md
    assert "DÖRT AŞAMALI DOĞRULAMA MODELİ" in validation_md


