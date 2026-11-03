import os
import subprocess
import sys
import tempfile
from pathlib import Path

# Ensure LC_ALL and LANG are set to C to avoid Windows Turkish locale initdb crash
os.environ["LC_ALL"] = "C"
os.environ["LANG"] = "C"

import pgserver
import pgserver._commands
import psycopg2

WORKSPACE_ROOT = Path(__file__).parent.parent.parent

def run_sql_file_via_psql(psql_path: Path, db_uri: str, sql_file: Path) -> subprocess.CompletedProcess:
    env = os.environ.copy()
    env["PGDATABASE"] = "postgres"
    cmd = [
        str(psql_path),
        "-d", db_uri,
        "-v", "ON_ERROR_STOP=1",
        "-f", str(sql_file)
    ]
    print(f"\n--- [PSQL EXECUTING]: {sql_file.name} ---")
    res = subprocess.run(cmd, cwd=str(WORKSPACE_ROOT), capture_output=True, text=True, encoding="utf-8", errors="replace")
    return res

def test_preflight_query_scenarios(conn):
    print("\n--- [TESTING PREFLIGHT SQL SCENARIOS ON REAL POSTGRESQL] ---")
    cur = conn.cursor()

    # Load actual SQL queries directly from backend/scripts/preflight_database_hardening.sql
    preflight_file = (WORKSPACE_ROOT / "backend" / "scripts" / "preflight_database_hardening.sql").read_text(encoding="utf-8")

    # Extract SOKU 1 (Tables and RLS status)
    soku_1_start = preflight_file.find("SELECT \n    exp.table_name,")
    soku_1_end = preflight_file.find("ORDER BY exp.table_name;", soku_1_start) + len("ORDER BY exp.table_name;")
    soku_1_sql = preflight_file[soku_1_start:soku_1_end]

    # Extract SOKU 11.1A (Catalog Pre-check Gate)
    start_a = preflight_file.find("WITH checks AS (\n    SELECT \n        '1. USER_PROFILES_TABLE_EXISTS'::text AS check_name,")
    end_a = preflight_file.find("END::text;", start_a) + len("END::text;")
    soku_11_1a_sql = preflight_file[start_a:end_a]

    # Extract SOKU 11.1B (Data Audit Gate)
    start_b = preflight_file.find("WITH profile_data AS (\n    SELECT \n        p.id AS raw_id,")
    end_b = preflight_file.find("END::text;", start_b) + len("END::text;")
    soku_11_1b_sql = preflight_file[start_b:end_b]

    # Extract SOKU 12 (Consolidated Gate)
    start_12 = preflight_file.find("WITH consolidated_checks AS (\n    SELECT \n        '1. TRUNCATE_LEAKS'::text AS check_name,")
    end_12 = preflight_file.find("END::text;", start_12) + len("END::text;")
    soku_12_sql = preflight_file[start_12:end_12]

    # Extract SOKU 11.2A (Migration 03 Catalog Gate)
    start_2a = preflight_file.find("WITH checks_03_catalog AS (")
    end_2a = preflight_file.find("END::text;", start_2a) + len("END::text;")
    soku_11_2a_sql = preflight_file[start_2a:end_2a]

    # Setup baseline tables needed for preflight testing (auth.users, public.user_interactions)
    cur.execute("CREATE SCHEMA IF NOT EXISTS auth;")
    cur.execute("CREATE TABLE IF NOT EXISTS auth.users (id UUID PRIMARY KEY);")
    cur.execute("""
        CREATE TABLE IF NOT EXISTS public.user_interactions (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            user_id UUID,
            book_id TEXT,
            interaction_type TEXT
        );
    """)
    conn.commit()

    # --- SENARYO 1: public.user_profiles Tablosu Yokken (Parse Hatasız Açık FAIL ve NO-GO) ---
    print("\n[Scenario 1]: Testing when public.user_profiles table does NOT exist...")
    cur.execute("DROP TABLE IF EXISTS public.user_profiles CASCADE;")
    conn.commit()

    # SOKU 11.1A must report explicit FAIL: BLOCKER and overall NO-GO without throwing UndefinedTable!
    cur.execute(soku_11_1a_sql)
    rows_s1_a = cur.fetchall()
    print("  SOKU 11.1A Catalog Gate (Missing user_profiles):")
    for r in rows_s1_a:
        print(f"    {r[0]}: {r[1]} -> {r[2]}")
    assert 'FAIL: BLOCKER' in rows_s1_a[0][2], f"Expected FAIL: BLOCKER on missing table, got {rows_s1_a[0][2]}"
    assert 'NO-GO' in rows_s1_a[-1][2], f"Expected NO-GO on missing user_profiles, got {rows_s1_a[-1][2]}"

    # SOKU 1 must report FAIL: TABLO EKSİK
    cur.execute(soku_1_sql)
    up_soku1 = [r for r in cur.fetchall() if r[0] == 'user_profiles'][0]
    print(f"  SOKU 1 for user_profiles: {up_soku1[0]} -> {up_soku1[4]}")
    assert 'FAIL: TABLO EKSİK' in up_soku1[4]

    # BÖLÜM 12 must report FAIL: BLOCKER and overall NO-GO without throwing
    cur.execute(soku_12_sql)
    rows_s1_12 = cur.fetchall()
    check_2_12 = [r for r in rows_s1_12 if '2. USER_PROFILES_USER_ID_EXISTS' in r[0]][0]
    decision_12 = [r for r in rows_s1_12 if '6. OVERALL_CONSOLIDATED_GATE_DECISION' in r[0]][0]
    assert 'FAIL: BLOCKER' in check_2_12[2]
    assert 'NO-GO' in decision_12[2]
    print(f"  BÖLÜM 12 Consolidated Gate Decision: {decision_12[2]}")

    # --- SENARYO 2: auth.users Tablosu Yokken (Parse Hatasız Açık FAIL ve NO-GO) ---
    print("\n[Scenario 2]: Testing when auth.users table is missing...")
    cur.execute("CREATE TABLE public.user_profiles (id UUID PRIMARY KEY, preferred_genres TEXT[]);")
    cur.execute("DROP SCHEMA IF EXISTS auth CASCADE;")
    conn.commit()

    cur.execute(soku_11_1a_sql)
    rows_s2 = cur.fetchall()
    row_auth_table = [r for r in rows_s2 if '2. AUTH_USERS_TABLE_EXISTS' in r[0]][0]
    row_auth_perm = [r for r in rows_s2 if '2.1. AUTH_USERS_ACCESS_PERMISSION' in r[0]][0]
    decision_s2 = rows_s2[-1]
    print(f"  {row_auth_table[0]}: {row_auth_table[1]} -> {row_auth_table[2]}")
    print(f"  {row_auth_perm[0]}: {row_auth_perm[1]} -> {row_auth_perm[2]}")
    print(f"  {decision_s2[0]}: {decision_s2[1]} -> {decision_s2[2]}")
    assert 'FAIL: BLOCKER' in row_auth_table[2]
    assert 'FAIL: BLOCKER' in row_auth_perm[2]
    assert 'NO-GO' in decision_s2[2]

    # BÖLÜM 12 must also report FAIL: BLOCKER and overall NO-GO without throwing
    cur.execute(soku_12_sql)
    rows_s2_12 = cur.fetchall()
    row_auth_12 = [r for r in rows_s2_12 if '2.1. AUTH_USERS_STATUS' in r[0]][0]
    decision_s2_12 = rows_s2_12[-1]
    print(f"  BÖLÜM 12 {row_auth_12[0]}: {row_auth_12[1]} -> {row_auth_12[2]}")
    print(f"  BÖLÜM 12 Decision: {decision_s2_12[2]}")
    assert 'FAIL: BLOCKER' in row_auth_12[2]
    assert 'NO-GO' in decision_s2_12[2]

    # SOKU 11.2A must also report FAIL: BLOCKER and overall NO-GO without throwing
    cur.execute(soku_11_2a_sql)
    rows_s2_2a = cur.fetchall()
    row_auth_table_2a = [r for r in rows_s2_2a if '4. AUTH_USERS_TABLE_EXISTS' in r[0]][0]
    row_auth_perm_2a = [r for r in rows_s2_2a if '4.1. AUTH_USERS_ACCESS_PERMISSION' in r[0]][0]
    decision_s2_2a = rows_s2_2a[-1]
    print(f"  SOKU 11.2A {row_auth_table_2a[0]}: {row_auth_table_2a[1]} -> {row_auth_table_2a[2]}")
    print(f"  SOKU 11.2A {row_auth_perm_2a[0]}: {row_auth_perm_2a[1]} -> {row_auth_perm_2a[2]}")
    print(f"  SOKU 11.2A Decision: {decision_s2_2a[2]}")
    assert 'FAIL: BLOCKER' in row_auth_table_2a[2]
    assert 'FAIL: BLOCKER' in row_auth_perm_2a[2]
    assert 'NO-GO' in decision_s2_2a[2]

    # --- SENARYO 3: auth.users Erişim İzni Yokken (Erişim Hatası vs Yetim Kayıt Ayrımı) ---
    print("\n[Scenario 3]: Testing auth.users access permission separation from orphan checks...")
    cur.execute("CREATE SCHEMA IF NOT EXISTS auth;")
    cur.execute("CREATE TABLE auth.users (id UUID PRIMARY KEY);")
    cur.execute("REVOKE ALL ON auth.users FROM PUBLIC;")
    cur.execute("DROP ROLE IF EXISTS test_auditor_role;")
    cur.execute("CREATE ROLE test_auditor_role NOSUPERUSER NOCREATEDB NOCREATEROLE;")
    cur.execute("GRANT USAGE ON SCHEMA public TO test_auditor_role;")
    cur.execute("GRANT SELECT ON ALL TABLES IN SCHEMA public TO test_auditor_role;")
    cur.execute("GRANT USAGE ON SCHEMA auth TO test_auditor_role;")
    # Note: test_auditor_role is NOT granted SELECT on auth.users
    conn.commit()

    # 1. When running under unprivileged auditor role without SELECT privilege on auth.users:
    cur.execute("SET ROLE test_auditor_role;")
    cur.execute(soku_11_1a_sql)
    rows_s3_unprivileged = cur.fetchall()
    row_auth_table_s3 = [r for r in rows_s3_unprivileged if '2. AUTH_USERS_TABLE_EXISTS' in r[0]][0]
    row_perm_s3 = [r for r in rows_s3_unprivileged if '2.1. AUTH_USERS_ACCESS_PERMISSION' in r[0]][0]
    decision_s3 = rows_s3_unprivileged[-1]
    print(f"  [Unprivileged Role] {row_auth_table_s3[0]}: {row_auth_table_s3[1]} -> {row_auth_table_s3[2]}")
    print(f"  [Unprivileged Role] {row_perm_s3[0]}: {row_perm_s3[1]} -> {row_perm_s3[2]}")
    print(f"  [Unprivileged Role] {decision_s3[0]}: {decision_s3[1]} -> {decision_s3[2]}")
    assert 'PASS' in row_auth_table_s3[2], "Table exists in catalog"
    assert 'FAIL: BLOCKER - auth.users tablosuna SELECT okuma izni yok!' in row_perm_s3[2]
    assert 'NO-GO' in decision_s3[2], "Access permission failure must result in strict NO-GO!"

    # BÖLÜM 12 under unprivileged role must report permission blocker and NO-GO
    cur.execute(soku_12_sql)
    rows_s3_12 = cur.fetchall()
    row_auth_12_s3 = [r for r in rows_s3_12 if '2.1. AUTH_USERS_STATUS' in r[0]][0]
    decision_12_s3 = rows_s3_12[-1]
    assert 'FAIL: BLOCKER - auth.users tablosuna SELECT okuma izni yok!' in row_auth_12_s3[2]
    assert 'NO-GO' in decision_12_s3[2]

    # SOKU 11.2A under unprivileged role must report permission blocker and NO-GO
    cur.execute(soku_11_2a_sql)
    rows_s3_2a = cur.fetchall()
    row_auth_table_s3_2a = [r for r in rows_s3_2a if '4. AUTH_USERS_TABLE_EXISTS' in r[0]][0]
    row_perm_s3_2a = [r for r in rows_s3_2a if '4.1. AUTH_USERS_ACCESS_PERMISSION' in r[0]][0]
    decision_s3_2a = rows_s3_2a[-1]
    print(f"  [Unprivileged Role] SOKU 11.2A {row_auth_table_s3_2a[0]}: {row_auth_table_s3_2a[1]} -> {row_auth_table_s3_2a[2]}")
    print(f"  [Unprivileged Role] SOKU 11.2A {row_perm_s3_2a[0]}: {row_perm_s3_2a[1]} -> {row_perm_s3_2a[2]}")
    print(f"  [Unprivileged Role] SOKU 11.2A Decision: {decision_s3_2a[2]}")
    assert 'PASS' in row_auth_table_s3_2a[2]
    assert 'FAIL: BLOCKER - auth.users tablosuna SELECT okuma izni yok!' in row_perm_s3_2a[2]
    assert 'NO-GO' in decision_s3_2a[2]

    # Reset role back to postgres superuser and cleanup temporary test role
    cur.execute("RESET ROLE;")
    cur.execute("DROP OWNED BY test_auditor_role;")
    cur.execute("DROP ROLE test_auditor_role;")
    conn.commit()

    # 2. Check that access permission check reflects PASS under authorized role (postgres / service_role)
    cur.execute(soku_11_1a_sql)
    rows_s3_priv = cur.fetchall()
    row_perm_priv = [r for r in rows_s3_priv if '2.1. AUTH_USERS_ACCESS_PERMISSION' in r[0]][0]
    print(f"  [Privileged Role] {row_perm_priv[0]}: {row_perm_priv[1]} -> {row_perm_priv[2]}")
    assert 'PASS' in row_perm_priv[2]

    cur.execute(soku_11_2a_sql)
    rows_s3_priv_2a = cur.fetchall()
    row_perm_priv_2a = [r for r in rows_s3_priv_2a if '4.1. AUTH_USERS_ACCESS_PERMISSION' in r[0]][0]
    print(f"  [Privileged Role] SOKU 11.2A {row_perm_priv_2a[0]}: {row_perm_priv_2a[1]} -> {row_perm_priv_2a[2]}")
    assert 'PASS' in row_perm_priv_2a[2]

    # --- SENARYO 4: Canlı Başlangıç Durumu (Temiz Pre-Migration Baseline: user_id yok) ---
    print("\n[Scenario 4]: Testing clean pre-migration baseline (user_id column absent)...")
    cur.execute("DROP TABLE IF EXISTS public.user_profiles CASCADE;")
    cur.execute("CREATE TABLE public.user_profiles (id UUID PRIMARY KEY, preferred_genres TEXT[]);")
    cur.execute("ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;")
    cur.execute("DELETE FROM auth.users WHERE id = '11111111-1111-1111-1111-111111111111'::uuid;")
    cur.execute("INSERT INTO auth.users (id) VALUES ('11111111-1111-1111-1111-111111111111'::uuid);")
    cur.execute("INSERT INTO public.user_profiles (id, preferred_genres) VALUES ('11111111-1111-1111-1111-111111111111'::uuid, '{\"Sci-Fi\"}');")
    conn.commit()

    # SOKU 11.1A must report GO
    cur.execute(soku_11_1a_sql)
    rows_s4_a = cur.fetchall()
    assert 'EXPECTED_PREFLIGHT' in rows_s4_a[3][2]
    assert 'GO' in rows_s4_a[-1][2]
    print(f"  SOKU 11.1A Catalog Gate: {rows_s4_a[-1][2]}")

    # SOKU 11.1B Data Gate must report GO
    cur.execute(soku_11_1b_sql)
    rows_s4_b = cur.fetchall()
    for r in rows_s4_b:
        print(f"    [DATA] {r[0]}: {r[1]} -> {r[2]}")
    assert 'PASS' in rows_s4_b[0][2]
    assert 'PASS' in rows_s4_b[1][2]
    assert 'EXPECTED_PREFLIGHT' in rows_s4_b[2][2]
    assert 'GO' in rows_s4_b[-1][2]

    # BÖLÜM 12 must report GO
    cur.execute(soku_12_sql)
    rows_s4_12 = cur.fetchall()
    decision_s4_12 = rows_s4_12[-1]
    assert 'GO' in decision_s4_12[2]
    print(f"  BÖLÜM 12 Consolidated Gate: {decision_s4_12[2]}")

    # --- SENARYO 5: user_id Kolonu Mevcut ama NULL Değerler Var (Pre-Backfill) ---
    print("\n[Scenario 5]: Testing user_id column present with NULL values (pre-backfill)...")
    cur.execute("ALTER TABLE public.user_profiles ADD COLUMN user_id UUID;")
    conn.commit()

    cur.execute(soku_11_1b_sql)
    rows_s5_b = cur.fetchall()
    check_mismatch = rows_s5_b[2]
    print(f"  {check_mismatch[0]}: {check_mismatch[1]} -> {check_mismatch[2]}")
    assert 'null_user_id: 1' in check_mismatch[1]
    assert 'INFO: user_id kolonu mevcut ancak 1 adet NULL kayıt var' in check_mismatch[2]
    assert 'GO' in rows_s5_b[-1][2] # NULL is safe before backfill

    # --- SENARYO 6: Yetim Profil Kaydı (auth.users'ta Karşılığı Olmayan Profil) ---
    print("\n[Scenario 6]: Testing orphaned profile record (id not in auth.users)...")
    cur.execute("INSERT INTO public.user_profiles (id) VALUES ('99999999-9999-9999-9999-999999999999'::uuid);")
    conn.commit()

    cur.execute(soku_11_1b_sql)
    rows_s6_b = cur.fetchall()
    orphan_row = rows_s6_b[1]
    data_decision_s6 = rows_s6_b[-1]
    print(f"  {orphan_row[0]}: {orphan_row[1]} -> {orphan_row[2]}")
    print(f"  {data_decision_s6[0]}: {data_decision_s6[1]} -> {data_decision_s6[2]}")
    assert 'FAIL: BLOCKER' in orphan_row[2]
    assert 'NO-GO' in data_decision_s6[2], "Orphan profile must result in strict NO-GO!"
    cur.execute("DELETE FROM public.user_profiles WHERE id = '99999999-9999-9999-9999-999999999999'::uuid;")
    conn.commit()

    # --- SENARYO 7: Çelişkili Kimlik Durumu (id != user_id) ---
    print("\n[Scenario 7]: Testing identity mismatch (id != user_id)...")
    cur.execute("UPDATE public.user_profiles SET user_id = '88888888-8888-8888-8888-888888888888'::uuid WHERE id = '11111111-1111-1111-1111-111111111111'::uuid;")
    conn.commit()

    cur.execute(soku_11_1b_sql)
    rows_s7_b = cur.fetchall()
    mismatch_row = rows_s7_b[2]
    data_decision_s7 = rows_s7_b[-1]
    print(f"  {mismatch_row[0]}: {mismatch_row[1]} -> {mismatch_row[2]}")
    print(f"  {data_decision_s7[0]}: {data_decision_s7[1]} -> {data_decision_s7[2]}")
    assert 'FAIL: BLOCKER' in mismatch_row[2]
    assert 'uyuşmazlık: 1' in mismatch_row[1]
    assert 'NO-GO' in data_decision_s7[2], "Identity mismatch must result in strict NO-GO!"

    # --- SENARYO 8: RLS Kapalı Durumu ---
    print("\n[Scenario 8]: Testing disabled RLS status...")
    cur.execute("ALTER TABLE public.user_profiles DISABLE ROW LEVEL SECURITY;")
    conn.commit()

    cur.execute(soku_11_1a_sql)
    rows_s8_a = cur.fetchall()
    rls_row = [r for r in rows_s8_a if '4. USER_PROFILES_RLS_STATUS' in r[0]][0]
    cat_decision_s8 = rows_s8_a[-1]
    print(f"  {rls_row[0]}: {rls_row[1]} -> {rls_row[2]}")
    print(f"  {cat_decision_s8[0]}: {cat_decision_s8[1]} -> {cat_decision_s8[2]}")
    assert 'FAIL: BLOCKER' in rls_row[2]
    assert 'NO-GO' in cat_decision_s8[2], "Disabled RLS must result in strict NO-GO!"
    cur.execute("ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;")
    conn.commit()

    # --- SENARYO 9: İstemci Rollerinde TRUNCATE Yetkisi Açık ---
    print("\n[Scenario 9]: Testing client TRUNCATE leak...")
    cur.execute("GRANT TRUNCATE ON public.user_profiles TO anon;")
    conn.commit()

    cur.execute(soku_11_1a_sql)
    rows_s9_a = cur.fetchall()
    trunc_row = [r for r in rows_s9_a if '5. CLIENT_TRUNCATE_PERMISSIONS' in r[0]][0]
    cat_decision_s9 = rows_s9_a[-1]
    print(f"  {trunc_row[0]}: {trunc_row[1]} -> {trunc_row[2]}")
    print(f"  {cat_decision_s9[0]}: {cat_decision_s9[1]} -> {cat_decision_s9[2]}")
    assert 'FAIL: P0' in trunc_row[2]
    assert 'NO-GO' in cat_decision_s9[2], "TRUNCATE leak must result in strict NO-GO!"
    cur.execute("REVOKE TRUNCATE ON public.user_profiles FROM anon;")
    conn.commit()

    # --- SENARYO 10: Temiz Post-Migration Şeması (id == user_id) ---
    print("\n[Scenario 10]: Testing clean post-migration schema (id == user_id)...")
    cur.execute("UPDATE public.user_profiles SET user_id = id WHERE id = '11111111-1111-1111-1111-111111111111'::uuid;")
    conn.commit()

    cur.execute(soku_11_1a_sql)
    assert 'GO' in cur.fetchall()[-1][2]
    cur.execute(soku_11_1b_sql)
    rows_s10_b = cur.fetchall()
    assert 'PASS' in rows_s10_b[2][2]
    assert 'GO' in rows_s10_b[-1][2]
    cur.execute(soku_12_sql)
    assert 'GO' in cur.fetchall()[-1][2]
    print("  All gates (11.1A, 11.1B, 12) produced clean GO on synchronized schema.")

    # --- SENARYO 11: Salt-Okunurluk Doğrulaması (SET TRANSACTION READ ONLY) ---
    print("\n[Scenario 11]: Verifying strict read-only execution under SET TRANSACTION READ ONLY...")
    conn.rollback()
    cur.execute("BEGIN TRANSACTION READ ONLY;")
    cur.execute(soku_1_sql)
    r1 = cur.fetchall()
    cur.execute(soku_11_1a_sql)
    r2 = cur.fetchall()
    cur.execute(soku_11_1b_sql)
    r3 = cur.fetchall()
    cur.execute(soku_12_sql)
    r4 = cur.fetchall()
    cur.execute("COMMIT;")
    assert len(r1) > 0 and len(r2) > 0 and len(r3) > 0 and len(r4) > 0
    print(f"  Preflight queries successfully executed in READ ONLY transaction (r1={len(r1)}, r2={len(r2)}, r3={len(r3)}, r4={len(r4)}).")

    # --- SENARYO 12: Hiçbir Kontrol Çalışmadığında Kesin NO-GO Güvencesi (0 checks != PASS/GO) ---
    print("\n[Scenario 12]: Testing empty checks guard (0 checks must NEVER evaluate to PASS or GO)...")
    empty_catalog_gate_sql = """
        WITH checks AS (
            SELECT 'dummy'::text AS check_name, 'val'::text AS actual_value, 'PASS'::text AS verdict
            WHERE 1 = 0
        )
        SELECT
            '6. OVERALL_CATALOG_GATE_DECISION'::text,
            (SELECT count(*)::text FROM checks) || ' kontroller denetlendi (' ||
            (SELECT count(*) FILTER (WHERE verdict LIKE 'FAIL%' OR verdict LIKE '%BLOCKER%' OR verdict LIKE '%P0%')::text FROM checks) || ' FAIL, ' ||
            (SELECT count(*) FILTER (WHERE verdict LIKE 'PASS%')::text FROM checks) || ' PASS, ' ||
            (SELECT count(*) FILTER (WHERE verdict LIKE 'EXPECTED%' OR verdict LIKE 'INFO%')::text FROM checks) || ' INFO/EXPECTED)',
            CASE
                WHEN (SELECT count(*) FROM checks) = 0
                    THEN 'NO-GO: Hiçbir kontrol çalıştırılamadı!'
                WHEN (SELECT count(*) FROM checks WHERE verdict IS NULL) > 0
                    THEN 'NO-GO: Belirsiz veya NULL kontrol durumu (verdict IS NULL) tespit edildi! Migration 02 çalıştırılamaz.'
                WHEN (SELECT count(*) FROM checks WHERE verdict LIKE 'FAIL%' OR verdict LIKE '%BLOCKER%' OR verdict LIKE '%P0%') > 0
                    THEN 'NO-GO: Bloklayıcı katalog/yetki hataları var! Migration 02 çalıştırılamaz.'
                WHEN (SELECT count(*) FROM checks WHERE verdict IS NULL OR (verdict NOT LIKE 'PASS%' AND verdict NOT LIKE 'INFO%' AND verdict NOT LIKE 'EXPECTED%')) > 0
                    THEN 'NO-GO: Bilinmeyen veya geçersiz kontrol durumu tespit edildi! Migration 02 çalıştırılamaz.'
                WHEN (SELECT count(*) FILTER (WHERE verdict LIKE 'PASS%') FROM checks) = 0
                    THEN 'NO-GO: Başarılı (PASS) kabul edilen hiçbir kontrol yok! Migration 02 çalıştırılamaz.'
                ELSE 'GO: Tüm katalog ve yetki ön koşulları başarılı.'
            END::text;
    """
    cur.execute(empty_catalog_gate_sql)
    res_empty = cur.fetchone()
    print(f"  Empty checks result: {res_empty[1]} -> {res_empty[2]}")
    assert 'NO-GO: Hiçbir kontrol çalıştırılamadı!' in res_empty[2]
    assert 'PASS' not in res_empty[2]
    assert res_empty[2].startswith('NO-GO:')
    assert not res_empty[2].startswith('GO:')

    # --- SENARYO 13: Tek Bir Kontrol Bile FAIL/BLOCKER ise Kesin NO-GO Güvencesi ---
    print("\n[Scenario 13]: Testing single blocker invariant (even 1 BLOCKER/FAIL guarantees NO-GO)...")
    single_blocker_gate_sql = """
        WITH checks AS (
            SELECT 'check_1'::text AS check_name, 'PASS: Ok'::text AS verdict
            UNION ALL
            SELECT 'check_2'::text, 'PASS: Ok'::text
            UNION ALL
            SELECT 'check_3'::text, 'PASS: Ok'::text
            UNION ALL
            SELECT 'check_4'::text, 'FAIL: BLOCKER - Kritik şema hatası!'::text
            UNION ALL
            SELECT 'check_5'::text, 'PASS: Ok'::text
        )
        SELECT
            'OVERALL_GATE_DECISION'::text,
            (SELECT count(*)::text FROM checks) || ' kontroller denetlendi (' ||
            (SELECT count(*) FILTER (WHERE verdict LIKE 'FAIL%' OR verdict LIKE '%BLOCKER%' OR verdict LIKE '%P0%')::text FROM checks) || ' FAIL, ' ||
            (SELECT count(*) FILTER (WHERE verdict LIKE 'PASS%')::text FROM checks) || ' PASS, ' ||
            (SELECT count(*) FILTER (WHERE verdict LIKE 'EXPECTED%' OR verdict LIKE 'INFO%')::text FROM checks) || ' INFO/EXPECTED)',
            CASE
                WHEN (SELECT count(*) FROM checks) = 0
                    THEN 'NO-GO: Hiçbir kontrol çalıştırılamadı!'
                WHEN (SELECT count(*) FROM checks WHERE verdict IS NULL) > 0
                    THEN 'NO-GO: Belirsiz veya NULL kontrol durumu (verdict IS NULL) tespit edildi! Migration 02 çalıştırılamaz.'
                WHEN (SELECT count(*) FROM checks WHERE verdict LIKE 'FAIL%' OR verdict LIKE '%BLOCKER%' OR verdict LIKE '%P0%') > 0
                    THEN 'NO-GO: Bloklayıcı katalog/yetki hataları var! Migration 02 çalıştırılamaz.'
                WHEN (SELECT count(*) FROM checks WHERE verdict IS NULL OR (verdict NOT LIKE 'PASS%' AND verdict NOT LIKE 'INFO%' AND verdict NOT LIKE 'EXPECTED%')) > 0
                    THEN 'NO-GO: Bilinmeyen veya geçersiz kontrol durumu tespit edildi! Migration 02 çalıştırılamaz.'
                WHEN (SELECT count(*) FILTER (WHERE verdict LIKE 'PASS%') FROM checks) = 0
                    THEN 'NO-GO: Başarılı (PASS) kabul edilen hiçbir kontrol yok! Migration 02 çalıştırılamaz.'
                ELSE 'GO: Tüm katalog ve yetki ön koşulları başarılı.'
            END::text;
    """
    cur.execute(single_blocker_gate_sql)
    res_blocker = cur.fetchone()
    print(f"  Single blocker result: {res_blocker[1]} -> {res_blocker[2]}")
    assert 'NO-GO: Bloklayıcı' in res_blocker[2]
    assert res_blocker[2].startswith('NO-GO:')
    assert not res_blocker[2].startswith('GO:')

    # --- SENARYO 14: PUBLIC (Grantee 0) Üzerinden TRUNCATE Sızıntısı Tespiti ---
    print("\n[Scenario 14]: Testing TRUNCATE leak granted via PUBLIC pseudo-role (grantee=0)...")
    cur.execute("GRANT TRUNCATE ON public.user_profiles TO PUBLIC;")
    conn.commit()

    cur.execute(soku_11_1a_sql)
    rows_s14_a = cur.fetchall()
    trunc_row_s14 = [r for r in rows_s14_a if '5. CLIENT_TRUNCATE_PERMISSIONS' in r[0]][0]
    cat_decision_s14 = rows_s14_a[-1]
    print(f"  SOKU 11.1A: {trunc_row_s14[0]}: {trunc_row_s14[1]} -> {trunc_row_s14[2]}")
    print(f"  SOKU 11.1A Decision: {cat_decision_s14[2]}")
    assert 'FAIL: P0' in trunc_row_s14[2]
    assert 'NO-GO' in cat_decision_s14[2]

    cur.execute(soku_12_sql)
    rows_s14_12 = cur.fetchall()
    trunc_12_s14 = [r for r in rows_s14_12 if '1. TRUNCATE_LEAKS' in r[0]][0]
    decision_14_12 = rows_s14_12[-1]
    print(f"  BÖLÜM 12: {trunc_12_s14[0]}: {trunc_12_s14[1]} -> {trunc_12_s14[2]}")
    print(f"  BÖLÜM 12 Decision: {decision_14_12[2]}")
    assert 'FAIL: P0' in trunc_12_s14[2]
    assert 'NO-GO' in decision_14_12[2]

    cur.execute("REVOKE TRUNCATE ON public.user_profiles FROM PUBLIC;")
    conn.commit()

    # Extract decision subqueries from the actual preflight queries for isolated evaluation
    dec_11_1a_start = soku_11_1a_sql.find("SELECT \n    '6. OVERALL_CATALOG_GATE_DECISION'::text,")
    dec_11_1a_sql = soku_11_1a_sql[dec_11_1a_start:]

    dec_11_1b_start = soku_11_1b_sql.find("SELECT \n    '4. OVERALL_DATA_GATE_DECISION'::text,")
    dec_11_1b_sql = soku_11_1b_sql[dec_11_1b_start:]

    dec_12_start = soku_12_sql.find("SELECT \n    '6. OVERALL_CONSOLIDATED_GATE_DECISION'::text,")
    dec_12_sql = soku_12_sql[dec_12_start:]

    # --- SENARYO 15: 4 PASS + 1 NULL Verdict -> Kesin NO-GO Güvencesi (Fail-Closed NULL Guard) ---
    print("\n[Scenario 15]: Testing 4 PASS + 1 NULL verdict fail-closed invariant...")
    # 15.1: SOKU 11.1A Catalog Gate
    s15_cat_sql = f"""
        WITH checks AS (
            SELECT '1. USER_PROFILES_TABLE_EXISTS'::text AS check_name, 'PASS: Mevcut'::text AS verdict UNION ALL
            SELECT '2. AUTH_USERS_TABLE_EXISTS'::text, 'PASS: Mevcut'::text UNION ALL
            SELECT '2.1. AUTH_USERS_ACCESS_PERMISSION'::text, 'PASS: Yetkili'::text UNION ALL
            SELECT '4. USER_PROFILES_RLS_STATUS'::text, 'PASS: RLS Aktif'::text UNION ALL
            SELECT '5. UNKNOWN_CHECK'::text, NULL::text
        )
        {dec_11_1a_sql}
    """
    cur.execute(s15_cat_sql)
    res_s15_cat = cur.fetchone()
    print(f"  SOKU 11.1A (4 PASS + 1 NULL): {res_s15_cat[1]} -> {res_s15_cat[2]}")
    assert res_s15_cat[2].startswith('NO-GO:')
    assert not res_s15_cat[2].startswith('GO:')
    assert 'NULL' in res_s15_cat[2]

    # 15.2: SOKU 11.1B Data Gate
    s15_data_sql = f"""
        WITH checks AS (
            SELECT '1. PROFILE_ROW_COUNT'::text AS check_name, 'PASS: 1 profil'::text AS verdict UNION ALL
            SELECT '2. ORPHAN_USER_CHECK'::text, 'PASS: Yetim yok'::text UNION ALL
            SELECT '3. IDENTITY_MISMATCH_CHECK'::text, 'PASS: Senkron'::text UNION ALL
            SELECT '4. EXTRA_CHECK_1'::text, 'PASS: Ok'::text UNION ALL
            SELECT '5. UNKNOWN_CHECK'::text, NULL::text
        )
        {dec_11_1b_sql}
    """
    cur.execute(s15_data_sql)
    res_s15_data = cur.fetchone()
    print(f"  SOKU 11.1B (4 PASS + 1 NULL): {res_s15_data[1]} -> {res_s15_data[2]}")
    assert res_s15_data[2].startswith('NO-GO:')
    assert not res_s15_data[2].startswith('GO:')
    assert 'NULL' in res_s15_data[2]

    # 15.3: BÖLÜM 12 Consolidated Gate
    s15_12_sql = f"""
        WITH consolidated_checks AS (
            SELECT '1. TRUNCATE_LEAKS'::text AS check_name, 'PASS: Sıfır TRUNCATE'::text AS verdict UNION ALL
            SELECT '2. USER_ID_EXISTS'::text, 'PASS: Mevcut'::text UNION ALL
            SELECT '2.1. AUTH_USERS'::text, 'PASS: Mevcut'::text UNION ALL
            SELECT '2.2. RLS_STATUS'::text, 'PASS: Aktif'::text UNION ALL
            SELECT '3. FAULTY_CHECK'::text, NULL::text
        )
        {dec_12_sql}
    """
    cur.execute(s15_12_sql)
    res_s15_12 = cur.fetchone()
    print(f"  BÖLÜM 12 (4 PASS + 1 NULL): {res_s15_12[1]} -> {res_s15_12[2]}")
    assert res_s15_12[2].startswith('NO-GO:')
    assert not res_s15_12[2].startswith('GO:')
    assert 'NULL' in res_s15_12[2]

    # --- SENARYO 16: 4 PASS + 1 Beklenmeyen / Geçersiz Verdict -> Kesin NO-GO Güvencesi ---
    print("\n[Scenario 16]: Testing 4 PASS + 1 unexpected/invalid verdict fail-closed invariant...")
    # 16.1: SOKU 11.1A Catalog Gate
    s16_cat_sql = f"""
        WITH checks AS (
            SELECT '1. USER_PROFILES_TABLE_EXISTS'::text AS check_name, 'PASS: Mevcut'::text AS verdict UNION ALL
            SELECT '2. AUTH_USERS_TABLE_EXISTS'::text, 'PASS: Mevcut'::text UNION ALL
            SELECT '2.1. AUTH_USERS_ACCESS_PERMISSION'::text, 'PASS: Yetkili'::text UNION ALL
            SELECT '4. USER_PROFILES_RLS_STATUS'::text, 'PASS: RLS Aktif'::text UNION ALL
            SELECT '5. UNKNOWN_CHECK'::text, 'UNEXPECTED_CUSTOM_STRING_123'::text
        )
        {dec_11_1a_sql}
    """
    cur.execute(s16_cat_sql)
    res_s16_cat = cur.fetchone()
    print(f"  SOKU 11.1A (4 PASS + 1 UNEXPECTED): {res_s16_cat[1]} -> {res_s16_cat[2]}")
    assert res_s16_cat[2].startswith('NO-GO:')
    assert not res_s16_cat[2].startswith('GO:')
    assert 'Bilinmeyen veya geçersiz' in res_s16_cat[2]

    # 16.2: SOKU 11.1B Data Gate
    s16_data_sql = f"""
        WITH checks AS (
            SELECT '1. PROFILE_ROW_COUNT'::text AS check_name, 'PASS: 1 profil'::text AS verdict UNION ALL
            SELECT '2. ORPHAN_USER_CHECK'::text, 'PASS: Yetim yok'::text UNION ALL
            SELECT '3. IDENTITY_MISMATCH_CHECK'::text, 'PASS: Senkron'::text UNION ALL
            SELECT '4. EXTRA_CHECK_1'::text, 'PASS: Ok'::text UNION ALL
            SELECT '5. UNKNOWN_CHECK'::text, 'ANOMALY_STATUS'::text
        )
        {dec_11_1b_sql}
    """
    cur.execute(s16_data_sql)
    res_s16_data = cur.fetchone()
    print(f"  SOKU 11.1B (4 PASS + 1 UNEXPECTED): {res_s16_data[1]} -> {res_s16_data[2]}")
    assert res_s16_data[2].startswith('NO-GO:')
    assert not res_s16_data[2].startswith('GO:')
    assert 'Bilinmeyen veya geçersiz' in res_s16_data[2]

    # 16.3: BÖLÜM 12 Consolidated Gate
    s16_12_sql = f"""
        WITH consolidated_checks AS (
            SELECT '1. TRUNCATE_LEAKS'::text AS check_name, 'PASS: Sıfır TRUNCATE'::text AS verdict UNION ALL
            SELECT '2. USER_ID_EXISTS'::text, 'PASS: Mevcut'::text UNION ALL
            SELECT '2.1. AUTH_USERS'::text, 'PASS: Mevcut'::text UNION ALL
            SELECT '2.2. RLS_STATUS'::text, 'PASS: Aktif'::text UNION ALL
            SELECT '3. FAULTY_CHECK'::text, 'MYSTERIOUS_RESULT'::text
        )
        {dec_12_sql}
    """
    cur.execute(s16_12_sql)
    res_s16_12 = cur.fetchone()
    print(f"  BÖLÜM 12 (4 PASS + 1 UNEXPECTED): {res_s16_12[1]} -> {res_s16_12[2]}")
    assert res_s16_12[2].startswith('NO-GO:')
    assert not res_s16_12[2].startswith('GO:')
    assert 'Bilinmeyen veya geçersiz' in res_s16_12[2]

    # --- SENARYO 17: 0 Kontrol -> Kesin NO-GO Güvencesi (Empty Checks Across All Gates) ---
    print("\n[Scenario 17]: Testing 0 checks across all gates (empty checks must evaluate to NO-GO)...")
    # 17.1: SOKU 11.1A
    s17_cat_sql = f"""
        WITH checks AS (
            SELECT 'dummy'::text AS check_name, 'val'::text AS actual_value, 'PASS'::text AS verdict WHERE 1 = 0
        )
        {dec_11_1a_sql}
    """
    cur.execute(s17_cat_sql)
    res_s17_cat = cur.fetchone()
    print(f"  SOKU 11.1A empty checks: {res_s17_cat[1]} -> {res_s17_cat[2]}")
    assert res_s17_cat[2].startswith('NO-GO:')
    assert 'Hiçbir kontrol çalıştırılamadı!' in res_s17_cat[2]

    # 17.2: SOKU 11.1B
    s17_data_sql = f"""
        WITH checks AS (
            SELECT 'dummy'::text AS check_name, 'val'::text AS actual_value, 'PASS'::text AS verdict WHERE 1 = 0
        )
        {dec_11_1b_sql}
    """
    cur.execute(s17_data_sql)
    res_s17_data = cur.fetchone()
    print(f"  SOKU 11.1B empty checks: {res_s17_data[1]} -> {res_s17_data[2]}")
    assert res_s17_data[2].startswith('NO-GO:')
    assert 'Hiçbir veri kontrolü çalıştırılamadı!' in res_s17_data[2]

    # 17.3: BÖLÜM 12
    s17_12_sql = f"""
        WITH consolidated_checks AS (
            SELECT 'dummy'::text AS check_name, 'val'::text AS actual_value, 'PASS'::text AS verdict WHERE 1 = 0
        )
        {dec_12_sql}
    """
    cur.execute(s17_12_sql)
    res_s17_12 = cur.fetchone()
    print(f"  BÖLÜM 12 empty checks: {res_s17_12[1]} -> {res_s17_12[2]}")
    assert res_s17_12[2].startswith('NO-GO:')
    assert 'Hiçbir kontrol çalıştırılamadı!' in res_s17_12[2]

    # --- SENARYO 18: Tüm Geçerli Kontroller PASS / İzin Verilen Durumlarda -> GO ---
    print("\n[Scenario 18]: Testing all valid checks produce expected GO verdict...")
    # 18.1: SOKU 11.1A
    s18_cat_sql = f"""
        WITH checks AS (
            SELECT '1. USER_PROFILES_TABLE_EXISTS'::text AS check_name, 'PASS: Mevcut'::text AS verdict UNION ALL
            SELECT '2. AUTH_USERS_TABLE_EXISTS'::text, 'PASS: Mevcut'::text UNION ALL
            SELECT '2.1. AUTH_USERS_ACCESS_PERMISSION'::text, 'PASS: Yetkili'::text UNION ALL
            SELECT '3. USER_ID_COLUMN_STATUS'::text, 'EXPECTED_PREFLIGHT: user_id kolonu henüz yok'::text UNION ALL
            SELECT '4. USER_PROFILES_RLS_STATUS'::text, 'PASS: RLS Aktif'::text UNION ALL
            SELECT '5. CLIENT_TRUNCATE_PERMISSIONS'::text, 'INFO: Truncate kapalı'::text
        )
        {dec_11_1a_sql}
    """
    cur.execute(s18_cat_sql)
    res_s18_cat = cur.fetchone()
    print(f"  SOKU 11.1A all valid checks: {res_s18_cat[1]} -> {res_s18_cat[2]}")
    assert res_s18_cat[2].startswith('GO:')
    assert 'Tüm katalog ve yetki ön koşulları başarılı.' in res_s18_cat[2]

    # 18.2: SOKU 11.1B
    s18_data_sql = f"""
        WITH checks AS (
            SELECT '1. PROFILE_ROW_COUNT'::text AS check_name, 'PASS: Canlıdaki beklenen 1 adet profil kaydı doğrulandı'::text AS verdict UNION ALL
            SELECT '2. ORPHAN_USER_CHECK'::text, 'PASS: Tüm profil id değerleri auth.users ile tam uyumlu'::text UNION ALL
            SELECT '3. IDENTITY_MISMATCH_CHECK'::text, 'EXPECTED_PREFLIGHT: user_id kolonu henüz eklenmemiş'::text
        )
        {dec_11_1b_sql}
    """
    cur.execute(s18_data_sql)
    res_s18_data = cur.fetchone()
    print(f"  SOKU 11.1B all valid checks: {res_s18_data[1]} -> {res_s18_data[2]}")
    assert res_s18_data[2].startswith('GO:')
    assert 'Veri bütünlüğü ve kimlik uzlaştırması doğrulandı.' in res_s18_data[2]

    # 18.3: BÖLÜM 12
    s18_12_sql = f"""
        WITH consolidated_checks AS (
            SELECT '1. TRUNCATE_LEAKS'::text AS check_name, 'PASS: Sıfır TRUNCATE Sızıntısı'::text AS verdict UNION ALL
            SELECT '2. USER_PROFILES_USER_ID_EXISTS'::text, 'EXPECTED_PREFLIGHT: user_id eksik'::text UNION ALL
            SELECT '2.1. AUTH_USERS_STATUS'::text, 'PASS: auth.users tablosu mevcut ve erişilebilir'::text UNION ALL
            SELECT '2.2. USER_PROFILES_RLS_STATUS'::text, 'PASS: RLS aktif'::text UNION ALL
            SELECT '3. INTERACTIONS_DUPLICATE_PAIRS'::text, 'WARNING: Mükerrer kayıtlar var'::text UNION ALL
            SELECT '4. INTERACTIONS_CHECK_STATUS'::text, 'EXPECTED_PREFLIGHT: Dar kısıt'::text UNION ALL
            SELECT '5. VECTOR_RPC_MATCH_BOOK_EMBEDDINGS'::text, 'PASS: RPC Mevcut'::text
        )
        {dec_12_sql}
    """
    cur.execute(s18_12_sql)
    res_s18_12 = cur.fetchone()
    print(f"  BÖLÜM 12 all valid checks: {res_s18_12[1]} -> {res_s18_12[2]}")
    assert res_s18_12[2].startswith('GO:')
    assert 'Tüm sistemik güvenlik ve şema ön koşulları onaylandı.' in res_s18_12[2]

    cur.close()
    print("\nSUCCESS: All 18 real PostgreSQL preflight scenarios verified successfully!\n")

def main():
    tmp_dir = Path(tempfile.mkdtemp(prefix="pg_isolated_test_"))
    print(f"Creating isolated PostgreSQL cluster at: {tmp_dir}")

    # 1. Initialize cluster with --locale=C to avoid Windows locale crash
    pgserver._commands.initdb(
        ['--locale=C', '--auth=trust', '--auth-local=trust', '--encoding=utf8', '-U', 'postgres'],
        pgdata=tmp_dir
    )
    print("initdb completed successfully.")

    # 2. Start PostgreSQL server
    srv = pgserver.PostgresServer(tmp_dir)
    psql_path = pgserver._commands.POSTGRES_BIN_PATH / "psql.exe"
    db_uri = srv.get_uri()
    print(f"PostgreSQL server started. URI: {db_uri}")

    # Query version
    conn = psycopg2.connect(db_uri)
    cur = conn.cursor()
    cur.execute("SELECT version();")
    pg_version = cur.fetchone()[0]
    print(f"Running on Real PostgreSQL Version:\n  {pg_version}\n")
    cur.close()

    failures = []

    # 3. Run test_02_user_profiles_rls_runtime.sql
    rls_sql = WORKSPACE_ROOT / "backend" / "scripts" / "hardening" / "test_02_user_profiles_rls_runtime.sql"
    res1 = run_sql_file_via_psql(psql_path, db_uri, rls_sql)
    print(res1.stdout)
    if res1.returncode != 0:
        print("STDERR:\n", res1.stderr)
        failures.append((rls_sql.name, res1.stderr))
    else:
        print(f"SUCCESS: {rls_sql.name} passed completely!")

    # 4. Run test_02_user_profiles_rollback_runtime.sql
    rollback_sql = WORKSPACE_ROOT / "backend" / "scripts" / "hardening" / "test_02_user_profiles_rollback_runtime.sql"
    res2 = run_sql_file_via_psql(psql_path, db_uri, rollback_sql)
    print(res2.stdout)
    if res2.returncode != 0:
        print("STDERR:\n", res2.stderr)
        failures.append((rollback_sql.name, res2.stderr))
    else:
        print(f"SUCCESS: {rollback_sql.name} passed completely!")

    # 5. Run Preflight Scenarios Verification
    try:
        test_preflight_query_scenarios(conn)
    except Exception as e:
        print(f"Preflight Scenarios Verification FAILED: {e}")
        failures.append(("preflight_scenarios", str(e)))

    conn.close()

    # 6. Cleanup
    try:
        srv.cleanup()
        print("Isolated PostgreSQL cluster cleaned up.")
    except Exception as e:
        print(f"Warning during cleanup: {e}")

    if failures:
        print("\n===============================")
        print(f"FAILED: {len(failures)} test suite(s) failed!")
        for name, err in failures:
            print(f"- {name}:\n{err}")
        sys.exit(1)
    else:
        print("\n===============================")
        print("ALL REAL POSTGRESQL RUNTIME TESTS AND PREFLIGHT SCENARIOS PASSED (100%)!")
        sys.exit(0)

if __name__ == "__main__":
    main()
