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
