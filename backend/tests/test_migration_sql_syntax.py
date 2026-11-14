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


def test_hardening_02_reconcile_table_privileges_least_privilege():
    """Verify 02 migration enforces least privilege on public.user_profiles for PUBLIC, anon, and authenticated."""
    hardening_dir = SCRIPTS_DIR / "hardening"
    forward_02 = (hardening_dir / "02_DRAFT_reconcile_user_profiles.sql").read_text(encoding="utf-8")

    # PUBLIC and anon must be completely revoked
    assert "REVOKE ALL PRIVILEGES ON TABLE public.user_profiles FROM PUBLIC, anon;" in forward_02
    # authenticated must have permissions reset, then only SELECT, INSERT, UPDATE granted
    assert "REVOKE ALL PRIVILEGES ON TABLE public.user_profiles FROM authenticated;" in forward_02
    assert "GRANT SELECT, INSERT, UPDATE ON TABLE public.user_profiles TO authenticated;" in forward_02
    # Dangerous DDL/DML explicitly revoked
    assert "REVOKE DELETE, TRUNCATE, REFERENCES, TRIGGER ON TABLE public.user_profiles FROM PUBLIC, anon, authenticated;" in forward_02
    # service_role granted least privilege (SELECT, INSERT, UPDATE, DELETE - not ALL)
    assert "GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.user_profiles TO service_role;" in forward_02
    assert "GRANT ALL ON TABLE public.user_profiles TO service_role;" not in forward_02


def test_hardening_02_reconcile_trigger_function_security():
    """Verify 02 trigger function ownership is postgres and EXECUTE is revoked from PUBLIC/anon."""
    hardening_dir = SCRIPTS_DIR / "hardening"
    forward_02 = (hardening_dir / "02_DRAFT_reconcile_user_profiles.sql").read_text(encoding="utf-8")

    # Ownership
    assert "ALTER FUNCTION public.sync_user_profile_identifiers() OWNER TO postgres;" in forward_02
    # EXECUTE restrictions
    assert "REVOKE ALL ON FUNCTION public.sync_user_profile_identifiers() FROM PUBLIC, anon;" in forward_02
    assert "GRANT EXECUTE ON FUNCTION public.sync_user_profile_identifiers() TO authenticated;" in forward_02
    assert "GRANT EXECUTE ON FUNCTION public.sync_user_profile_identifiers() TO service_role;" in forward_02
    # Search path
    assert "SET search_path = pg_catalog, pg_temp" in forward_02


def test_hardening_02_reconcile_pre_post_data_value_integrity():
    """Verify 02 migration validates pre/post profile values including SQL NULLs and separates new vs changed columns."""
    hardening_dir = SCRIPTS_DIR / "hardening"
    forward_02 = (hardening_dir / "02_DRAFT_reconcile_user_profiles.sql").read_text(encoding="utf-8")

    # Temporary snapshot table with ON COMMIT DROP, NO DROP TABLE IF EXISTS
    assert "CREATE TEMP TABLE _pre_user_profiles_snapshot ON COMMIT DROP" in forward_02
    assert "DROP TABLE IF EXISTS _pre_user_profiles_snapshot" not in forward_02
    assert "to_jsonb(p.*)" in forward_02

    # Pre-condition check for orphan records
    assert "_pre_user_profiles_snapshot WHERE row_identifier IS NULL" in forward_02

    # Post-check value comparison using jsonb_each and IS DISTINCT FROM
    assert "FOR col_name, orig_val IN SELECT key, value FROM jsonb_each(snap_rec.original_data)" in forward_02
    assert "curr_val IS DISTINCT FROM orig_val" in forward_02
    assert "Uygulama sonrası veri bütünlüğü doğrulaması başarısız" in forward_02

    # SQL NULL handling must be explicit (not skipping 'null'::jsonb)
    assert "orig_val = 'null'::jsonb" in forward_02
    assert "orig_val <> 'null'::jsonb" not in forward_02

    # Explicit separation of allowed backfill columns vs unchanged columns
    assert "IF col_name = 'user_id' THEN" in forward_02
    assert "ELSIF col_name = 'id' THEN" in forward_02
    assert "ELSE" in forward_02

    # Verification of newly added columns
    assert "current_row_data ? 'preferred_authors'" in forward_02
    assert "current_row_data ? 'preferred_vibe'" in forward_02
    assert "current_row_data ? 'onboarding_completed'" in forward_02

    # Dual-column sync check
    assert "(current_row_data->>'id') <> (current_row_data->>'user_id')" in forward_02


def test_hardening_02_reconcile_snapshot_lifecycle_and_transaction_safety():
    """Verify 02 migration snapshot is strictly transaction-bound without persistent DROP statements."""
    hardening_dir = SCRIPTS_DIR / "hardening"
    forward_02 = (hardening_dir / "02_DRAFT_reconcile_user_profiles.sql").read_text(encoding="utf-8")

    # Strictly 1 top-level transaction boundary
    lines = [line.strip() for line in forward_02.splitlines()]
    begin_lines = [i for i, line in enumerate(lines) if line == "BEGIN;"]
    commit_lines = [i for i, line in enumerate(lines) if line == "COMMIT;"]
    assert len(begin_lines) == 1, f"Expected exactly 1 BEGIN, found {len(begin_lines)}"
    assert len(commit_lines) == 1, f"Expected exactly 1 COMMIT, found {len(commit_lines)}"
    assert begin_lines[0] < commit_lines[0]

    # Lock timeout safety
    assert "SET LOCAL lock_timeout = '5s';" in forward_02

    # No un-scoped or dangerous DROP TABLE
    assert "DROP TABLE IF EXISTS _pre_user_profiles_snapshot" not in forward_02
    assert "DROP TABLE public.user_profiles" not in forward_02


def test_hardening_02_reconcile_foreign_key_and_unique_index_catalog_verification():
    """Verify 02 migration validates FK definition and UNIQUE index via system catalogs rather than name guessing."""
    hardening_dir = SCRIPTS_DIR / "hardening"
    forward_02 = (hardening_dir / "02_DRAFT_reconcile_user_profiles.sql").read_text(encoding="utf-8")

    # Foreign key catalog query must check auth.users(id) and CASCADE rule
    assert "pg_constraint" in forward_02
    assert "ref_ns.nspname = 'auth'" in forward_02
    assert "ref_cl.relname = 'users'" in forward_02
    assert "confdeltype = 'c'" in forward_02
    assert "ON DELETE CASCADE" in forward_02
    assert "Uyumsuz foreign key kısıtı tespit edildi" in forward_02

    # Foreign key source and target must be strictly single column in pre-check and post-check
    assert "cardinality(c.conkey) = 1" in forward_02
    assert "cardinality(c.confkey) = 1" in forward_02
    assert "public.user_profiles.user_id -> auth.users.id ON DELETE CASCADE" in forward_02

    # Unique index catalog query must check indisunique, single column, not partial
    assert "pg_index" in forward_02
    assert "idx_c.relname = 'idx_user_profiles_user_id'" in forward_02
    assert "i.indisunique = true" in forward_02
    assert "i.indisvalid = true" in forward_02
    assert "i.indnatts = 1" in forward_02
    assert "i.indpred IS NULL" in forward_02
    assert "Uyumsuz mevcut indeks:" in forward_02

    # Consistent unique index verification: post-check accepts valid unique index without rollback on name variance
    assert "user_profiles(user_id) üzerinde geçerli ve tekil (UNIQUE) bir indeks katalogda doğrulanamadı" in forward_02


def test_hardening_02_reconcile_rls_policy_dynamic_catalog_inspection():
    """Verify 02 migration queries pg_policy dynamically and prevents surviving ALL or DELETE policies."""
    hardening_dir = SCRIPTS_DIR / "hardening"
    forward_02 = (hardening_dir / "02_DRAFT_reconcile_user_profiles.sql").read_text(encoding="utf-8")

    # Dynamic catalog inspection without name guessing
    assert "FROM pg_policy p" in forward_02
    assert "DROP POLICY IF EXISTS %I ON public.user_profiles" in forward_02

    # Guessed policy names list must NOT exist
    assert 'DROP POLICY IF EXISTS "Enable read access for own profile"' not in forward_02
    assert 'DROP POLICY IF EXISTS "Enable all for users based on id"' not in forward_02

    # Post-check catalog validation must block surviving ALL ('*') or DELETE ('d')
    assert "p.polcmd IN ('*', 'd')" in forward_02
    assert "yetkisiz ALL veya DELETE" in forward_02

    # Fail-closed command isolation: exactly 1 SELECT, 1 INSERT, 1 UPDATE and total 3
    assert "p.polcmd NOT IN ('r', 'a', 'w')" in forward_02
    assert "total_pol_count <> 3" in forward_02
    assert "select_pol_count <> 1" in forward_02
    assert "insert_pol_count <> 1" in forward_02
    assert "update_pol_count <> 1" in forward_02

    # Policy conditions inspection via pg_get_expr and semantic normalization (not naive LIKE)
    assert "pg_get_expr(p.polqual, p.polrelid)" in forward_02
    assert "pg_get_expr(p.polwithcheck, p.polrelid)" in forward_02
    assert "clean_qual :=" in forward_02
    assert "clean_check :=" in forward_02
    assert "'auth.uid=user_idorauth.uid=id'" in forward_02


def test_hardening_02_reconcile_unique_index_non_regression_on_custom_name():
    """Verify 02 migration handles valid unique indexes with custom names consistently without rollback."""
    hardening_dir = SCRIPTS_DIR / "hardening"
    forward_02 = (hardening_dir / "02_DRAFT_reconcile_user_profiles.sql").read_text(encoding="utf-8")

    # Pre-check must recognize any valid unique index on user_id
    assert "user_id üzerinde farklı bir UNIQUE indeks mevcut" in forward_02
    assert "CREATE UNIQUE INDEX idx_user_profiles_user_id" in forward_02

    # Post-check must verify that a valid UNIQUE index exists on user_profiles(user_id)
    # without forcing relname = 'idx_user_profiles_user_id', preventing unwarranted rollback
    assert "user_profiles(user_id) üzerinde geçerli ve tekil (UNIQUE) bir indeks katalogda doğrulanamadı!" in forward_02
    assert "idx_user_profiles_user_id indeksi katalogda mevcut ancak geçersiz veya uyumsuz tanıma sahip!" in forward_02


def test_hardening_02_reconcile_foreign_key_composite_rejection_and_cascade_rule():
    """Verify 02 migration strictly rejects composite or invalid foreign keys and enforces ON DELETE CASCADE."""
    hardening_dir = SCRIPTS_DIR / "hardening"
    forward_02 = (hardening_dir / "02_DRAFT_reconcile_user_profiles.sql").read_text(encoding="utf-8")

    # Pre-condition: must check both source column count and target column count
    assert "cardinality(c.conkey) AS src_col_count" in forward_02
    assert "cardinality(c.confkey) AS ref_col_count" in forward_02
    assert "fk_record.src_col_count = 1" in forward_02
    assert "fk_record.ref_col_count = 1" in forward_02
    assert "fk_record.ref_schema = 'auth'" in forward_02
    assert "fk_record.ref_table = 'users'" in forward_02
    assert "fk_record.ref_col = 'id'" in forward_02
    assert "fk_record.confdeltype = 'c'" in forward_02

    # Post-check: must verify single-column source & target, and reject surviving composite/mismatched FKs
    assert "cardinality(c.conkey) = 1" in forward_02
    assert "cardinality(c.confkey) = 1" in forward_02
    assert "user_profiles.user_id üzerinde uyumsuz veya bileşik foreign key kısıtı tespit edildi!" in forward_02


def test_hardening_02_reconcile_rls_conditions_and_exact_policy_types():
    """Verify 02 migration enforces exact (1 SELECT, 1 INSERT, 1 UPDATE) RLS policy structure and conditions."""
    hardening_dir = SCRIPTS_DIR / "hardening"
    forward_02 = (hardening_dir / "02_DRAFT_reconcile_user_profiles.sql").read_text(encoding="utf-8")

    # Command filtering and counts
    assert "count(*) FILTER (WHERE p.polcmd = 'r')" in forward_02
    assert "count(*) FILTER (WHERE p.polcmd = 'a')" in forward_02
    assert "count(*) FILTER (WHERE p.polcmd = 'w')" in forward_02
    assert "total_pol_count <> 3 OR select_pol_count <> 1 OR insert_pol_count <> 1 OR update_pol_count <> 1" in forward_02

    # Policy conditions and command isolation (strict semantic equivalence rather than LIKE)
    assert "SELECT politikasında (\"%\") beklenen USING koşulu (\"auth.uid() = user_id OR auth.uid() = id\") bulunamadı veya mantıksal olarak eşdeğer değil" in forward_02
    assert "SELECT politikasında (\"%\") beklenmeyen WITH CHECK koşulu mevcut" in forward_02
    assert "INSERT politikasında (\"%\") beklenen WITH CHECK koşulu (\"auth.uid() = user_id OR auth.uid() = id\") bulunamadı veya mantıksal olarak eşdeğer değil" in forward_02
    assert "INSERT politikasında (\"%\") beklenmeyen USING koşulu mevcut" in forward_02
    assert "UPDATE politikasında (\"%\") beklenen USING koşulu (\"auth.uid() = user_id OR auth.uid() = id\") bulunamadı veya mantıksal olarak eşdeğer değil" in forward_02
    assert "UPDATE politikasında (\"%\") beklenen WITH CHECK koşulu (\"auth.uid() = user_id OR auth.uid() = id\") bulunamadı veya mantıksal olarak eşdeğer değil" in forward_02


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

    # Model A delete: only delete 'favorite' (preserves reading status and like/dislike signals)
    assert "interaction_type = 'favorite'" in forward_03

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
    """Verify test_03_interactions_and_trigger_runtime.sql covers all Model A and deduplication scenarios."""
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
    assert "SENARYO 12: \"want_to_read\" okuma durumu koruma" in runtime_03_sql
    assert "SENARYO 13: \"like\" tavsiye sinyali koruma" in runtime_03_sql
    assert "SENARYO 14: Rollback sonrası finished yazan kullanıcının verisinin korunması" in runtime_03_sql
    assert "SENARYO 15: Rollback öncesinde want_to_read iken finished yapılan durumun korunması" in runtime_03_sql
    assert "SENARYO 16: Birden fazla snapshot durumunda Fail-Closed denetimi" in runtime_03_sql
    assert "SENARYO 17: Forward-recovery tam idempotency güvencesi" in runtime_03_sql
    assert "SENARYO 18: Silinmiş satırın snapshot ile diriltilmemesi" in runtime_03_sql
    assert "SENARYO 19: Snapshot ile farklı durumda olan etkileşimin (dislike) ezilmemesi" in runtime_03_sql
    assert "SENARYO 20: Kullanıcı veri izolasyonu güvencesi" in runtime_03_sql


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


def test_hardening_02_custom_named_unique_index_handling_and_no_redundant_index():
    """Verify 02 migration handles valid unique indexes with custom names without creating redundant duplicates."""
    hardening_dir = SCRIPTS_DIR / "hardening"
    forward_02 = (hardening_dir / "02_DRAFT_reconcile_user_profiles.sql").read_text(encoding="utf-8")

    # Catalog inspection queries any single-column unique index on user_id
    assert "idx_c.relname = 'idx_user_profiles_user_id'" in forward_02
    assert "i.indnatts = 1" in forward_02
    assert "user_id üzerinde farklı bir UNIQUE indeks mevcut: %" in forward_02
    assert "idx_found := true;" in forward_02

    # Do not create duplicate index if valid index is found
    assert "IF NOT idx_found THEN" in forward_02
    assert "CREATE UNIQUE INDEX idx_user_profiles_user_id ON public.user_profiles(user_id);" in forward_02

    # Post-check validates that a valid UNIQUE index exists without hardcoding relname
    assert "WHERE n.nspname = 'public'" in forward_02
    assert "c.relname = 'user_profiles'" in forward_02
    assert "i.indisunique = true" in forward_02
    assert "i.indisvalid = true" in forward_02
    assert "user_profiles(user_id) üzerinde geçerli ve tekil (UNIQUE) bir indeks katalogda doğrulanamadı!" in forward_02


def test_hardening_02_composite_and_mismatched_fk_fail_closed_assertions():
    """Verify 02 migration enforces fail-closed assertions for composite, wrong target, or non-CASCADE foreign keys."""
    hardening_dir = SCRIPTS_DIR / "hardening"
    forward_02 = (hardening_dir / "02_DRAFT_reconcile_user_profiles.sql").read_text(encoding="utf-8")

    # Pre-check catalog query checks all FKs referencing or defined on user_id
    assert "array_position(c.conkey, (" in forward_02
    assert "SELECT attnum FROM pg_attribute" in forward_02
    assert "WHERE attrelid = cl.oid AND attname = 'user_id'" in forward_02

    # Pre-check strict validation
    assert "fk_record.src_col_count = 1" in forward_02
    assert "fk_record.src_col = 'user_id'" in forward_02
    assert "fk_record.ref_col_count = 1" in forward_02
    assert "fk_record.ref_schema = 'auth'" in forward_02
    assert "fk_record.ref_table = 'users'" in forward_02
    assert "fk_record.ref_col = 'id'" in forward_02
    assert "fk_record.confdeltype = 'c'" in forward_02
    assert "Uyumsuz foreign key kısıtı tespit edildi:" in forward_02

    # Post-check catalog validation
    assert "cardinality(c.conkey) = 1" in forward_02
    assert "cardinality(c.confkey) = 1" in forward_02
    assert "ref_ns.nspname = 'auth'" in forward_02
    assert "ref_cl.relname = 'users'" in forward_02
    assert "c.confdeltype = 'c'" in forward_02
    assert "user_profiles.user_id üzerinde uyumsuz veya bileşik foreign key kısıtı tespit edildi!" in forward_02


def test_hardening_02_unexpected_rls_policies_fail_closed_assertions():
    """Verify 02 migration enforces fail-closed isolation against surviving ALL/DELETE policies and command leaks."""
    hardening_dir = SCRIPTS_DIR / "hardening"
    forward_02 = (hardening_dir / "02_DRAFT_reconcile_user_profiles.sql").read_text(encoding="utf-8")

    # Dynamic pre-drop of existing policies regardless of name
    assert "FROM pg_policy p" in forward_02
    assert "EXECUTE format('DROP POLICY IF EXISTS %I ON public.user_profiles', pol_rec.polname);" in forward_02

    # Post-check strict policy count and commands
    assert "p.polcmd IN ('*', 'd') OR p.polcmd NOT IN ('r', 'a', 'w')" in forward_02
    assert "yetkisiz ALL veya DELETE ya da bilinmeyen RLS politikası tespit edildi!" in forward_02
    assert "total_pol_count <> 3 OR select_pol_count <> 1 OR insert_pol_count <> 1 OR update_pol_count <> 1" in forward_02

    # Command condition isolation (USING vs WITH CHECK)
    assert "SELECT politikasında (\"%\") beklenmeyen WITH CHECK koşulu mevcut" in forward_02
    assert "INSERT politikasında (\"%\") beklenmeyen USING koşulu mevcut" in forward_02
    assert "UPDATE politikasında (\"%\") beklenen USING koşulu" in forward_02
    assert "UPDATE politikasında (\"%\") beklenen WITH CHECK koşulu" in forward_02


def test_hardening_02_policy_normalization_limits_and_catalog_primacy_documented():
    """Verify 02 migration documents the limitations of parenthesis removal / text comparison and establishes catalog & runtime primacy."""
    hardening_dir = SCRIPTS_DIR / "hardening"
    forward_02 = (hardening_dir / "02_DRAFT_reconcile_user_profiles.sql").read_text(encoding="utf-8")

    assert "METİN NORMALİZASYONUNUN SINIRLARI VE GÜVENLİK MİMARİSİ" in forward_02
    assert "Boşluk ve parantez temizleme ('(', ')') metin karşılaştırması PostgreSQL" in forward_02
    assert "Güvenlik omurgası katalog kontrolleridir" in forward_02
    assert "polcmd IN ('r','a','w')" in forward_02
    assert "surviving ALL/DELETE bulunmaması" in forward_02
    assert "Nihai doğrulama esası: Yetki sızdırmazlığı, gerçek PostgreSQL runtime ortamında" in forward_02


def test_hardening_02_dual_column_trigger_identity_mismatch_protection():
    """Verify 02 sync trigger rejects updates when id and user_id are set to different identities."""
    hardening_dir = SCRIPTS_DIR / "hardening"
    forward_02 = (hardening_dir / "02_DRAFT_reconcile_user_profiles.sql").read_text(encoding="utf-8")

    assert "NEW.user_id IS NOT NULL AND NEW.id IS NOT NULL AND NEW.user_id <> NEW.id" in forward_02
    assert "user_profiles kimlik uyuşmazlığı: id (%) ile user_id (%) farklı olamaz!" in forward_02
    assert "SECURITY INVOKER" in forward_02
    assert "SET search_path = pg_catalog, pg_temp" in forward_02


def test_hardening_02_runtime_rls_sql_test_script_completeness():
    """Verify test_02_user_profiles_rls_runtime.sql covers all required RLS behavioral scenarios."""
    runtime_rls_sql = (SCRIPTS_DIR / "hardening" / "test_02_user_profiles_rls_runtime.sql").read_text(encoding="utf-8")

    assert "SENARYO 1: KULLANICI A, KULLANICI B PROFİLİNİ SELECT İLE OKUYAMAMALI" in runtime_rls_sql
    assert "SENARYO 2: KULLANICI A, KULLANICI B PROFİLİNİ UPDATE İLE DEĞİŞTİREMEMELİ" in runtime_rls_sql
    assert "SENARYO 3: KİMLİK UYUŞMAZLIĞI (id != user_id) TRIGGER REDDİ" in runtime_rls_sql
    assert "SENARYO 4: INSERT WITH CHECK İHLALİNİN AYRI DOĞRULANMASI" in runtime_rls_sql
    assert "SENARYO 5: UPDATE WITH CHECK İHLALİNİN AYRI DOĞRULANMASI" in runtime_rls_sql
    assert "SENARYO 6: TRANSACTION VE TEST OTURUMUNUN TEMİZ SIFIRLANMASI" in runtime_rls_sql
    assert "SENARYO 7: MEŞRU KULLANICI İŞLEMLERİ DOĞRULAMASI" in runtime_rls_sql
    assert "SENARYO 8: ANON / PUBLIC ERİŞİMİNİN TAMAMEN REDDEDİLMESİ" in runtime_rls_sql
    assert "SENARYO 9: SERVICE_ROLE YÖNETİM ERİŞİMİ" in runtime_rls_sql
    assert "SENARYO 10: ROLLBACK VE YENİDEN UYGULAMA İDEMPOTENCY TESTİ" in runtime_rls_sql


def test_hardening_02_reconcile_atomic_transaction_and_lock_timeout():
    """Verify 02 migration uses strict lock_timeout and a single atomic transaction without intermediate commits."""
    hardening_dir = SCRIPTS_DIR / "hardening"
    forward_02 = (hardening_dir / "02_DRAFT_reconcile_user_profiles.sql").read_text(encoding="utf-8")

    # Lock timeout must be explicitly set to 5s
    assert "SET LOCAL lock_timeout = '5s';" in forward_02

    # Exactly 1 top-level BEGIN and 1 top-level COMMIT
    lines = [line.strip() for line in forward_02.splitlines() if line.strip() in ("BEGIN;", "COMMIT;")]
    assert lines == ["BEGIN;", "COMMIT;"], f"Expected exactly ['BEGIN;', 'COMMIT;'], found {lines}"


def test_hardening_02_reconcile_orphan_prevention_and_auth_fk():
    """Verify 02 migration strictly enforces auth.users foreign key and mutual backfill between id and user_id."""
    hardening_dir = SCRIPTS_DIR / "hardening"
    forward_02 = (hardening_dir / "02_DRAFT_reconcile_user_profiles.sql").read_text(encoding="utf-8")

    # References auth.users(id) with ON DELETE CASCADE
    assert "REFERENCES auth.users(id) ON DELETE CASCADE" in forward_02
    assert "fk_user_profiles_user_id" in forward_02

    # Mutual backfill without data loss
    assert "UPDATE public.user_profiles SET user_id = id WHERE user_id IS NULL AND id IS NOT NULL" in forward_02
    assert "UPDATE public.user_profiles SET id = user_id WHERE id IS NULL AND user_id IS NOT NULL" in forward_02


def test_hardening_02_preflight_script_safe_read_only_checks():
    """Verify preflight hardening script contains only read-only SELECT queries and uses safe catalog/jsonb inspection."""
    preflight_sql = (SCRIPTS_DIR / "preflight_database_hardening.sql").read_text(encoding="utf-8")

    # Filter out comments to check actual executable SQL
    executable_sql_lines = [
        line.strip() for line in preflight_sql.splitlines()
        if line.strip() and not line.strip().startswith("--")
    ]
    executable_sql = "\n".join(executable_sql_lines).upper()

    # Strictly read-only: no DDL or destructive DML in executable statements
    for forbidden in ["CREATE TABLE", "ALTER TABLE", "DROP TABLE", "INSERT INTO", "DELETE FROM", "GRANT ", "REVOKE "]:
        assert forbidden not in executable_sql, f"Forbidden non-read-only statement found: {forbidden}"


def test_preflight_gate_fail_closed_single_blocker_invariant():
    """Verify all preflight gates (11.1A, 11.1B, 12) enforce strict fail-closed NO-GO on even a single FAIL/BLOCKER/P0."""
    preflight_sql = (SCRIPTS_DIR / "preflight_database_hardening.sql").read_text(encoding="utf-8")

    # Check that each gate checks for FAIL, BLOCKER, and P0
    assert "verdict LIKE 'FAIL%' OR verdict LIKE '%BLOCKER%' OR verdict LIKE '%P0%'" in preflight_sql
    assert "NO-GO: Bloklayıcı katalog/yetki hataları var! Migration 02 çalıştırılamaz." in preflight_sql
    assert "NO-GO: Bloklayıcı veri bütünlüğü veya yetim kayıt hataları var! Migration 02 çalıştırılamaz." in preflight_sql
    assert "NO-GO: Bloklayıcı güvenlik/şema/izin hataları tespit edildi! Canlı geçiş durduruldu." in preflight_sql


def test_preflight_empty_checks_evaluated_as_no_go_not_pass():
    """Verify that when no checks run (count = 0), the gate strictly evaluates to NO-GO, never PASS or GO."""
    preflight_sql = (SCRIPTS_DIR / "preflight_database_hardening.sql").read_text(encoding="utf-8")

    assert "WHEN (SELECT count(*) FROM checks) = 0 \n            THEN 'NO-GO: Hiçbir kontrol çalıştırılamadı!'" in preflight_sql or \
           "WHEN (SELECT count(*) FROM checks) = 0" in preflight_sql
    assert "NO-GO: Hiçbir kontrol çalıştırılamadı!" in preflight_sql
    assert "NO-GO: Hiçbir veri kontrolü çalıştırılamadı!" in preflight_sql
    assert "Başarılı (PASS) kabul edilen hiçbir kontrol yok!" in preflight_sql


def test_preflight_auth_users_access_permission_separated_from_orphan_data_check():
    """Verify auth.users access permission check (catalog) is strictly isolated from orphan profile record queries (data)."""
    preflight_sql = (SCRIPTS_DIR / "preflight_database_hardening.sql").read_text(encoding="utf-8")

    # SOKU 11.1A must check access permission without reading profile data
    assert "'2.1. AUTH_USERS_ACCESS_PERMISSION'::text" in preflight_sql
    assert "has_table_privilege(current_user, to_regclass('auth.users'), 'SELECT')" in preflight_sql
    assert "FAIL: BLOCKER - auth.users tablosuna SELECT okuma izni yok!" in preflight_sql

    # SOKU 11.1B must check orphan profile rows independently
    assert "'2. ORPHAN_USER_CHECK (auth.users BÜTÜNLÜĞÜ)'::text" in preflight_sql
    assert "FAIL: BLOCKER - auth.users içinde karşılığı olmayan" in preflight_sql


def test_preflight_client_truncate_checks_both_roles_and_public_grantee_zero():
    """Verify TRUNCATE leak checks cover anon, authenticated, AND PUBLIC grantee = 0 in both 11.1A and 12."""
    preflight_sql = (SCRIPTS_DIR / "preflight_database_hardening.sql").read_text(encoding="utf-8")

    assert "a.grantee = 0 AND a.privilege_type = 'TRUNCATE'" in preflight_sql
    assert "WHERE a.grantee = 0 AND a.privilege_type = 'TRUNCATE'" in preflight_sql


def test_preflight_gate_fail_closed_null_verdict_invariant():
    """Verify all preflight gates (11.1A, 11.1B, 12) explicitly guard against NULL verdicts fail-closed."""
    preflight_sql = (SCRIPTS_DIR / "preflight_database_hardening.sql").read_text(encoding="utf-8")

    # 1. SOKU 11.1A Catalog Gate checks verdict IS NULL
    assert "WHEN (SELECT count(*) FROM checks WHERE verdict IS NULL) > 0" in preflight_sql
    assert "NO-GO: Belirsiz veya NULL kontrol durumu (verdict IS NULL) tespit edildi! Migration 02 çalıştırılamaz." in preflight_sql

    # 2. SOKU 11.1B Data Gate checks verdict IS NULL
    assert "NO-GO: Belirsiz veya NULL veri kontrol durumu (verdict IS NULL) tespit edildi! Migration 02 çalıştırılamaz." in preflight_sql

    # 3. BÖLÜM 12 Consolidated Gate checks verdict IS NULL
    assert "WHEN (SELECT count(*) FROM consolidated_checks WHERE verdict IS NULL) > 0" in preflight_sql
    assert "NO-GO: Belirsiz veya NULL konsolide kontrol durumu (verdict IS NULL) tespit edildi! Canlı geçiş durduruldu." in preflight_sql

    # 4. In all gates, the fallback NOT LIKE branch also explicitly guards with 'verdict IS NULL OR'
    assert "WHERE verdict IS NULL OR (verdict NOT LIKE 'PASS%' AND verdict NOT LIKE 'INFO%' AND verdict NOT LIKE 'EXPECTED%')" in preflight_sql
    assert "WHERE verdict IS NULL OR (verdict NOT LIKE 'PASS%' AND verdict NOT LIKE 'INFO%' AND verdict NOT LIKE 'EXPECTED%' AND verdict NOT LIKE 'WARNING%')" in preflight_sql


def test_hardening_03_forward_recovery_fail_closed_ambiguity_guard():
    """Verify 03 migration forward-recovery has fail-closed guard for multiple snapshots for the same user and book."""
    hardening_dir = SCRIPTS_DIR / "hardening"
    forward_03 = (hardening_dir / "03_DRAFT_reconcile_interactions_and_trigger.sql").read_text(encoding="utf-8")

    assert "Belirsiz (birden fazla) snapshot denetimi (Fail-Closed)" in forward_03
    assert "HAVING count(*) > 1" in forward_03
    assert "Forward-Recovery Güvenlik Hatası (Fail-Closed): _archived_user_interactions_rollback_backup tablosunda" in forward_03
    assert "birden fazla snapshot tespit edildi" in forward_03


def test_hardening_03_forward_recovery_preserves_new_user_writes():
    """Verify 03 migration forward-recovery preserves new user writes and never silently overwrites finished or dislike."""
    hardening_dir = SCRIPTS_DIR / "hardening"
    forward_03 = (hardening_dir / "03_DRAFT_reconcile_interactions_and_trigger.sql").read_text(encoding="utf-8")

    assert "YENİ KULLANICI VERİSİNİ KORUMA: Çatışma Tespiti" in forward_03
    assert "PRESERVED_USER_WRITE_SKIPPED_RECOVERY" in forward_03
    assert "kullanıcının yeni yazdığı durum korunarak snapshot ezmesi engellendi" in forward_03
    assert "(arch.user_interaction_snapshot->>'interaction_type' = 'reading' AND ui.interaction_type = 'want_to_read')" in forward_03
    assert "(arch.user_interaction_snapshot->>'interaction_type' = 'favorite' AND ui.interaction_type = 'like')" in forward_03


def test_hardening_03_forward_recovery_conflict_table_audit():
    """Verify 03 migration forward-recovery creates and audits in _archived_user_interactions_recovery_conflicts."""
    hardening_dir = SCRIPTS_DIR / "hardening"
    forward_03 = (hardening_dir / "03_DRAFT_reconcile_interactions_and_trigger.sql").read_text(encoding="utf-8")

    assert "CREATE TABLE IF NOT EXISTS public._archived_user_interactions_recovery_conflicts" in forward_03
    assert "conflict_id BIGSERIAL PRIMARY KEY" in forward_03
    assert "resolution_action TEXT NOT NULL" in forward_03
    assert "REVOKE ALL ON TABLE public._archived_user_interactions_recovery_conflicts FROM PUBLIC, anon, authenticated;" in forward_03
    assert "GRANT SELECT, INSERT ON TABLE public._archived_user_interactions_recovery_conflicts TO service_role;" in forward_03
    assert "ALTER TABLE public._archived_user_interactions_recovery_conflicts ENABLE ROW LEVEL SECURITY;" in forward_03
    assert "SKIPPED_ROW_MISSING_IN_INTERACTIONS" in forward_03


def test_hardening_03_rollback_attempt_id_tracking():
    """Verify 03 rollback script adds and tracks rollback_attempt_id for every rollback batch."""
    hardening_dir = SCRIPTS_DIR / "hardening"
    rollback_03 = (hardening_dir / "03_DRAFT_reconcile_interactions_and_trigger_rollback.sql").read_text(encoding="utf-8")

    assert "rollback_attempt_id UUID NOT NULL DEFAULT gen_random_uuid()" in rollback_03
    assert "v_rollback_attempt_id UUID := gen_random_uuid();" in rollback_03
    assert "rollback_attempt_id" in rollback_03
    assert "recovery_applied_at TIMESTAMPTZ" in rollback_03


def test_hardening_03_forward_recovery_attempt_id_batch_isolation():
    """Verify 03 migration forward-recovery implements attempt ID batch selection, validation and resolved tracking."""
    hardening_dir = SCRIPTS_DIR / "hardening"
    forward_03 = (hardening_dir / "03_DRAFT_reconcile_interactions_and_trigger.sql").read_text(encoding="utf-8")

    assert "current_setting('libris.recovery_attempt_id', true)" in forward_03
    assert "Belirtilen libris.recovery_attempt_id geçersiz UUID formatında" in forward_03
    assert "Belirtilen recovery attempt ID (%) arşiv tablosunda bulunamadı!" in forward_03
    assert "WHERE recovery_applied_at IS NULL" in forward_03
    assert "birden fazla bekleyen rollback attempt ID tespit edildi" in forward_03
    assert "SET recovery_applied_at = now()" in forward_03


def test_hardening_03_recovery_conflict_table_service_role_rls_policy():
    """Verify 03 migration creates an explicit RLS policy for service_role on the conflict table."""
    hardening_dir = SCRIPTS_DIR / "hardening"
    forward_03 = (hardening_dir / "03_DRAFT_reconcile_interactions_and_trigger.sql").read_text(encoding="utf-8")

    assert "CREATE POLICY \"service_role_manage_recovery_conflicts\"" in forward_03
    assert "ON public._archived_user_interactions_recovery_conflicts" in forward_03
    assert "FOR ALL TO service_role" in forward_03


def test_preflight_03_catalog_and_data_gates_exist_and_cover_all_checks():
    """Verify preflight SQL has clearly labeled Migration 03 catalog and data audit gates covering all runbook checks."""
    preflight_sql = (SCRIPTS_DIR / "preflight_database_hardening.sql").read_text(encoding="utf-8")

    # SOKU 11.2A: Catalog Pre-check Gate
    assert "SOKU 11.2A / 11: MIGRATION 03 ÖN KOŞUL VE KATALOG DENETİMİ" in preflight_sql
    assert "'1. USER_INTERACTIONS_TABLE_EXISTS'::text" in preflight_sql
    assert "'1.1. USER_INTERACTIONS_COLUMNS_VALID'::text" in preflight_sql
    assert "'2. FAVORITES_TABLE_EXISTS'::text" in preflight_sql
    assert "'2.1. FAVORITES_COLUMNS_VALID'::text" in preflight_sql
    assert "'3. BOOKS_TABLE_EXISTS'::text" in preflight_sql
    assert "'3.1. BOOKS_ISBN13_COLUMN_EXISTS'::text" in preflight_sql
    assert "'4. AUTH_USERS_TABLE_EXISTS'::text" in preflight_sql
    assert "'4.1. AUTH_USERS_ACCESS_PERMISSION'::text" in preflight_sql
    assert "'5. INTERACTIONS_CHECK_CONSTRAINT_STATUS'::text" in preflight_sql
    assert "'6. LEGACY_TRIGGER_STATUS'::text" in preflight_sql
    assert "'7. OVERALL_MIGRATION_03_CATALOG_GATE_DECISION'::text" in preflight_sql

    # SOKU 11.2B: Data Audit Gate
    assert "SOKU 11.2B / 11: MIGRATION 03 VERİ BÜTÜNLÜĞÜ, ÇELİŞKİ VE HACİM MUTABAKATI DENETİMİ" in preflight_sql
    # 1. Conflicting like/dislike
    assert "'1. CONFLICTING_LIKE_DISLIKE_PAIRS'::text" in preflight_sql
    assert "HAVING count(DISTINCT interaction_type) > 1" in preflight_sql
    # 2. Orphan interaction references (books and auth users)
    assert "'2.1. ORPHAN_BOOK_REFERENCES_IN_DUPLICATES'::text" in preflight_sql
    assert "'2.2. ORPHAN_USER_REFERENCES_IN_DUPLICATES'::text" in preflight_sql
    assert "'2.3. GENERAL_ORPHAN_INTERACTIONS_CATALOG'::text" in preflight_sql
    # 3. NULL / empty identifiers
    assert "'3. INVALID_IDENTIFIERS_USER_INTERACTIONS'::text" in preflight_sql
    assert "WHERE user_id IS NULL OR book_id IS NULL OR trim(book_id) = ''" in preflight_sql
    # 4. Duplicate interaction pairs
    assert "'4. DUPLICATE_INTERACTION_PAIRS'::text" in preflight_sql
    # 5. Duplicate or orphaned favorites
    assert "'5.1. DUPLICATE_FAVORITES'::text" in preflight_sql
    assert "'5.2. INVALID_IDENTIFIERS_FAVORITES'::text" in preflight_sql
    assert "'5.3. ORPHAN_BOOK_FAVORITES'::text" in preflight_sql
    assert "'5.4. ORPHAN_USER_FAVORITES'::text" in preflight_sql
    # 6. Volume simulation
    assert "'6. MIGRATION_03_VOLUME_SIMULATION'::text" in preflight_sql
    # 7. Overall Decision
    assert "'7. OVERALL_MIGRATION_03_DATA_GATE_DECISION'::text" in preflight_sql

    # Strict Fail-Closed Invariants for 11.2A and 11.2B
    assert "NO-GO: Bloklayıcı katalog/ön koşul hataları var! Migration 03 çalıştırılamaz." in preflight_sql
    assert "NO-GO: Bloklayıcı veri bütünlüğü veya çelişki hataları var! Migration 03 çalıştırılamaz." in preflight_sql


def test_preflight_03_volume_simulation_exact_semantics():
    """Verify volume simulation partitions null rows from duplicates to guarantee zero double-counting."""
    preflight_sql = (SCRIPTS_DIR / "preflight_database_hardening.sql").read_text(encoding="utf-8")

    # The simulation must filter out null/empty book_id in dup_stats so they aren't double-counted with null_rows
    assert "WHERE user_id IS NOT NULL AND book_id IS NOT NULL AND trim(book_id) <> ''" in preflight_sql
    # Transfer must use DISTINCT user_id, book_id and check not exists in favorites
    assert "count(DISTINCT (ui.user_id, ui.book_id)) AS new_favorites_to_insert" in preflight_sql
    # Backfill must check not exists in user_interactions
    assert "NOT EXISTS (\n                    SELECT 1 FROM public.user_interactions ui WHERE ui.user_id = f.user_id AND ui.book_id = f.book_id\n                )" in preflight_sql or \
           "WHERE NOT EXISTS (\n                    SELECT 1 FROM public.user_interactions ui WHERE ui.user_id = f.user_id AND ui.book_id = f.book_id" in preflight_sql


def test_rollback_03_delete_semantics_contract():
    """Verify rollback DELETE semantics match the legacy 4-state contract where favorite removal deletes ('favorite', 'like')."""
    hardening_dir = SCRIPTS_DIR / "hardening"
    rollback_03 = (hardening_dir / "03_DRAFT_reconcile_interactions_and_trigger_rollback.sql").read_text(encoding="utf-8")

    # Rollback trigger must explicitly delete both favorite and like on favorite deletion due to 4-state collapse
    assert "interaction_type IN ('favorite', 'like')" in rollback_03
    assert "DELETE FROM public.user_interactions" in rollback_03
    assert "WHERE user_id = OLD.user_id" in rollback_03
    assert "AND book_id = OLD.book_id" in rollback_03


def test_staging_readiness_standardized_db_url_and_single_session_psql():
    """Verify MIGRATION_03_STAGING_READINESS.md standardizes on STAGING_DB_URL and specifies single-session psql invocation."""
    readiness_md = (SCRIPTS_DIR / "hardening" / "MIGRATION_03_STAGING_READINESS.md").read_text(encoding="utf-8")

    # STAGING_DB_URL is the canonical variable
    assert "$STAGING_DB_URL" in readiness_md
    # STAGING_DB_URI must not be used in commands
    assert 'psql "$STAGING_DB_URI"' not in readiness_md

    # Single-session psql command structure for attempt-ID setting
    assert '-c "SET libris.recovery_attempt_id =' in readiness_md
    assert "-f backend/scripts/hardening/03_DRAFT_reconcile_interactions_and_trigger.sql" in readiness_md


def test_hardening_03_lock_timeout_and_function_security():
    """Verify lock_timeout and sync_favorites_to_interactions ownership/privilege boundaries in forward and rollback SQL."""
    hardening_dir = SCRIPTS_DIR / "hardening"
    forward_03 = (hardening_dir / "03_DRAFT_reconcile_interactions_and_trigger.sql").read_text(encoding="utf-8")
    rollback_03 = (hardening_dir / "03_DRAFT_reconcile_interactions_and_trigger_rollback.sql").read_text(encoding="utf-8")

    # Lock timeout, statement timeout, and idle timeout
    assert "SET LOCAL lock_timeout = '5s';" in forward_03
    assert "SET LOCAL lock_timeout = '5s';" in rollback_03
    assert "SET LOCAL statement_timeout = '60s';" in forward_03
    assert "SET LOCAL statement_timeout = '60s';" in rollback_03
    assert "SET LOCAL idle_in_transaction_session_timeout = '30s';" in forward_03
    assert "SET LOCAL idle_in_transaction_session_timeout = '30s';" in rollback_03

    # Advisory lock protection against concurrent migrations
    assert "pg_try_advisory_xact_lock(hashtext('libris_migration_03'))" in forward_03
    assert "pg_try_advisory_xact_lock(hashtext('libris_migration_03'))" in rollback_03

    # Function ownership must be set to postgres if exists
    assert "ALTER FUNCTION public.sync_favorites_to_interactions() OWNER TO postgres;" in forward_03
    assert "ALTER FUNCTION public.sync_favorites_to_interactions() OWNER TO postgres;" in rollback_03

    # Function execution must be revoked from public and anon
    assert "REVOKE ALL ON FUNCTION public.sync_favorites_to_interactions() FROM PUBLIC, anon;" in forward_03
    assert "REVOKE ALL ON FUNCTION public.sync_favorites_to_interactions() FROM PUBLIC, anon;" in rollback_03
    assert "GRANT EXECUTE ON FUNCTION public.sync_favorites_to_interactions() TO authenticated, service_role;" in forward_03
    assert "GRANT EXECUTE ON FUNCTION public.sync_favorites_to_interactions() TO authenticated, service_role;" in rollback_03

    # Duplicate backup table RLS policy
    assert 'CREATE POLICY "service_role_manage_duplicate_backup"' in forward_03


def test_preflight_03_catalog_queries_schema_qualified():
    """Verify constraint and trigger catalog queries in preflight 11.2A and Section 12 are strictly schema qualified."""
    preflight_sql = (SCRIPTS_DIR / "preflight_database_hardening.sql").read_text(encoding="utf-8")

    # Constraint queries must use to_regclass('public.user_interactions')
    assert "con.conrelid = to_regclass('public.user_interactions') AND con.contype = 'c'" in preflight_sql
    # Trigger queries must filter tgrelid = to_regclass('public.favorites')
    assert "tgrelid = to_regclass('public.favorites') AND tgname = 'trg_sync_favorites'" in preflight_sql


def test_preflight_03_volume_simulation_fail_closed_contract():
    """Verify volume simulation validates reconciliation equation balance and fails closed on negative counts."""
    preflight_sql = (SCRIPTS_DIR / "preflight_database_hardening.sql").read_text(encoding="utf-8")

    # Must verify the mathematical reconciliation formula
    assert "FAIL: BLOCKER - Negatif nihai UI satır sayısı" in preflight_sql
    assert "FAIL: BLOCKER - Negatif favorites artışı öngörüldü!" in preflight_sql
    assert "FAIL: BLOCKER - Negatif arşiv satır sayısı öngörüldü!" in preflight_sql
    assert "PASS: Matematiksel hacim mutabakatı ve beklenen satır sayıları doğrulandı" in preflight_sql


def test_preflight_03_complete_inventory_and_mandatory_pass_enforcement():
    """Verify SOKU 11.2A and 11.2B enforce complete inventory (10 and 11) and 8 mandatory PASS checks."""
    preflight_sql = (SCRIPTS_DIR / "preflight_database_hardening.sql").read_text(encoding="utf-8")

    # 11.2A
    assert "Beklenen 10 katalog kontrolü yerine" in preflight_sql
    assert "Mükerrer veya çakışan katalog kontrol adı tespit edildi!" in preflight_sql
    assert "Zorunlu katalog ön koşullarının tamamı (8/8) PASS durumunda değil!" in preflight_sql

    # 11.2B
    assert "Beklenen 11 veri bütünlüğü kontrolü yerine" in preflight_sql
    assert "Mükerrer veya çakışan veri kontrol adı tespit edildi!" in preflight_sql
    assert "Zorunlu veri bütünlüğü kontrollerinin tamamı (8/8) PASS durumunda değil!" in preflight_sql
    assert "Hacim simülasyonunda NULL veya tanımsız sayaç tespit edildi!" in preflight_sql


def test_staging_readiness_nine_state_operator_release_gate_lifecycle():
    """Verify MIGRATION_03_STAGING_READINESS.md formally specifies all 9 release gate states and bypass closures."""
    readiness_md = (SCRIPTS_DIR / "hardening" / "MIGRATION_03_STAGING_READINESS.md").read_text(encoding="utf-8")

    expected_states = [
        "LOCAL_VERIFICATION_PASS",
        "STAGING_PRECONDITIONS_PENDING",
        "STAGING_BACKUP_VERIFIED",
        "STAGING_RESTORE_VERIFIED",
        "STAGING_PREFLIGHT_PASS",
        "STAGING_MAINTENANCE_MODE_CONFIRMED",
        "STAGING_MIGRATION_EXECUTED",
        "STAGING_POSTCHECK_PASS",
        "RELEASE_APPROVED",
    ]
    for st in expected_states:
        assert st in readiness_md, f"Missing release gate state: {st}"

    # Bypass closures
    assert "Bayat Yedek (Stale Backup) Koruması" in readiness_md
    assert "Sağlama Toplamı (Checksum) Uyuşmazlığı Koruması" in readiness_md
    assert "Yanlış Hedef / Loopback Koruması" in readiness_md
    assert "Başarısız Restore Kabul Edilmeme Koruması" in readiness_md
    assert "Eksik Preflight Koruması" in readiness_md
    assert "Aktif İstemci Trafiği Koruması" in readiness_md
    assert "Post-Migration Sayaç Kayması Koruması" in readiness_md





def test_migration_09_learning_notes_schema_and_rls():
    """Verify 09_learning_notes.sql defines user_notes with required columns, indexes, and RLS."""
    sql = (SCRIPTS_DIR / "09_learning_notes.sql").read_text(encoding="utf-8")
    assert "CREATE TABLE IF NOT EXISTS public.user_notes" in sql
    assert "user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE" in sql
    assert "book_id TEXT NOT NULL" in sql
    assert "note_type TEXT NOT NULL CHECK (note_type IN ('personal_note', 'key_takeaway', 'question'))" in sql
    assert "content TEXT NOT NULL" in sql
    assert "ENABLE ROW LEVEL SECURITY" in sql
    assert "CREATE POLICY \"Users can view their own notes\"" in sql
    assert "auth.uid() = user_id" in sql
    assert "CREATE INDEX IF NOT EXISTS idx_user_notes_user_book" in sql


def test_migration_10_learning_notes_idempotency_and_review_schema():
    """Verify 10_learning_notes_idempotency_and_review.sql adds client_id and note_reviews table."""
    sql = (SCRIPTS_DIR / "10_learning_notes_idempotency_and_review.sql").read_text(encoding="utf-8")
    assert "ADD COLUMN IF NOT EXISTS client_id TEXT;" in sql
    assert "CREATE UNIQUE INDEX IF NOT EXISTS uq_user_notes_user_client_id" in sql
    assert "WHERE client_id IS NOT NULL;" in sql
    assert "CREATE TABLE IF NOT EXISTS public.note_reviews" in sql
    assert "REFERENCES public.user_notes(id) ON DELETE CASCADE" in sql
    assert "REFERENCES auth.users(id) ON DELETE CASCADE" in sql
    assert "CONSTRAINT uq_note_review_user_note UNIQUE (user_id, note_id)" in sql
    assert "ENABLE ROW LEVEL SECURITY" in sql
    assert "CREATE POLICY \"Users can view their own note reviews\"" in sql


def test_migration_11_learning_paths_schema_and_cascade():
    """Verify 11_learning_paths.sql defines learning_paths, items, cascade delete, and subquery RLS."""
    sql = (SCRIPTS_DIR / "11_learning_paths.sql").read_text(encoding="utf-8")
    assert "CREATE TABLE IF NOT EXISTS public.learning_paths" in sql
    assert "user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE" in sql
    assert "CREATE TABLE IF NOT EXISTS public.learning_path_items" in sql
    assert "path_id UUID NOT NULL REFERENCES public.learning_paths(id) ON DELETE CASCADE" in sql
    assert "CONSTRAINT unique_path_book UNIQUE (path_id, book_id)" in sql
    assert "ENABLE ROW LEVEL SECURITY" in sql
    assert "CREATE POLICY \"Users can view their own learning paths\"" in sql
    assert "CREATE POLICY \"Users can view items of their own learning paths\"" in sql
    assert "p.id = learning_path_items.path_id AND p.user_id = auth.uid()" in sql


def test_migration_12_knowledge_graph_schema_and_rls():
    """Verify 12_knowledge_graph.sql defines knowledge_relationships with unique constraints, indexes, and user-isolated RLS."""
    sql = (SCRIPTS_DIR / "12_knowledge_graph.sql").read_text(encoding="utf-8")
    assert "CREATE TABLE IF NOT EXISTS public.knowledge_relationships" in sql
    assert "user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE" in sql
    assert "source_type TEXT NOT NULL CHECK (source_type IN ('book', 'concept', 'note', 'learning_path'))" in sql
    assert "target_type TEXT NOT NULL CHECK (target_type IN ('book', 'concept', 'note', 'learning_path'))" in sql
    assert "CONSTRAINT unique_user_relationship UNIQUE (user_id, source_id, target_id, relationship_type)" in sql
    assert "ENABLE ROW LEVEL SECURITY" in sql
    assert "CREATE POLICY \"Users can view their own knowledge relationships\"" in sql
    assert "CREATE POLICY \"Users can insert their own knowledge relationships\"" in sql
    assert "CREATE POLICY \"Users can update their own knowledge relationships\"" in sql
    assert "CREATE POLICY \"Users can delete their own knowledge relationships\"" in sql
    assert "auth.uid() = user_id" in sql


def test_migration_13_learning_outcomes_schema_and_rls():
    """Verify 13_learning_outcomes.sql defines review_items, review_attempts, indexes, and user-isolated RLS."""
    sql = (SCRIPTS_DIR / "13_learning_outcomes.sql").read_text(encoding="utf-8")
    assert "CREATE TABLE IF NOT EXISTS public.review_items" in sql
    assert "user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE" in sql
    assert "source_type TEXT NOT NULL CHECK (source_type IN ('user_note', 'key_takeaway', 'concept', 'learning_path', 'user_created', 'book'))" in sql
    assert "stage INT NOT NULL DEFAULT 1 CHECK (stage >= 1 AND stage <= 5)" in sql
    assert "CREATE TABLE IF NOT EXISTS public.review_attempts" in sql
    assert "item_id UUID NOT NULL REFERENCES public.review_items(id) ON DELETE CASCADE" in sql
    assert "outcome TEXT NOT NULL CHECK (outcome IN ('remembered', 'struggled'))" in sql
    assert "ENABLE ROW LEVEL SECURITY" in sql
    assert "CREATE POLICY \"Users can view their own review items\"" in sql
    assert "CREATE POLICY \"Users can view their own review attempts\"" in sql
    assert "auth.uid() = user_id" in sql



def test_migration_14_retires_removed_feature_tables_safely():
    """14 drops only the tables of the removed features, idempotently, in one transaction."""
    sql = (SCRIPTS_DIR / "14_drop_learning_paths_and_knowledge_graph.sql").read_text(encoding="utf-8")
    statements = [s.strip() for s in sql.split(";") if s.strip() and not s.strip().startswith("--")]
    body = "\n".join(line for line in sql.splitlines() if not line.strip().startswith("--"))
    assert "BEGIN" in body and "COMMIT" in body
    drops = [line.strip() for line in body.splitlines() if line.strip().upper().startswith("DROP")]
    assert drops == [
        "DROP TABLE IF EXISTS public.learning_path_items;",
        "DROP TABLE IF EXISTS public.learning_paths;",
        "DROP TABLE IF EXISTS public.knowledge_relationships;",
    ]
    assert "CASCADE" not in body.upper(), "no CASCADE: nothing else may depend on these tables"
    assert statements
