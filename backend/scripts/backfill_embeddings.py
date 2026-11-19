import argparse
import logging
import os
import sys

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import config  # noqa: F401  (loads the project-root .env, real environment variables win)
from infrastructure.persistence.supabase_config import classify_db_error, redact
from services.embedding_service import EmbeddingService

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger(__name__)

def resolve_db_url(environ=None) -> str:
    """Direct PostgreSQL URL for this script.

    Precedence: SUPABASE_DB_URL (developer-script URL), then DATABASE_URL (the URL the API itself
    uses; also what docker compose provides). Blank or whitespace-only values count as unset, so
    docker compose's empty ``SUPABASE_DB_URL=`` falls through to DATABASE_URL. Returns "" if neither
    is set. Mirrors export_embedding_snapshot.py.
    """
    env = os.environ if environ is None else environ
    for name in ("SUPABASE_DB_URL", "DATABASE_URL"):
        value = (env.get(name) or "").strip()
        if value:
            return value
    return ""


_DB_FAILURE_HINTS = {
    "auth": "database authentication failed; check the user and password in SUPABASE_DB_URL "
            "(Supabase pooler user names look like postgres.<project-ref>).",
    "network": "could not reach the database host; check the host/port in SUPABASE_DB_URL and your network.",
    "permission": "the database role lacks a required privilege (see the preflight report).",
    "database": "unexpected database error.",
}


def _db_failure(exc: BaseException, db_url: str) -> str:
    """One-line, secret-free description of a database failure."""
    category = classify_db_error(exc)
    detail = redact(" ".join(str(exc).split()), db_url)[:300]
    return f"[{category}] {_DB_FAILURE_HINTS[category]} ({type(exc).__name__}: {detail})"


def preflight(cursor) -> dict:
    """Read-only checks of what the backfill needs: SELECT on books, SELECT/INSERT/UPDATE on
    book_embeddings, and whether Row Level Security applies to the connected role. Writes nothing."""
    cursor.execute("""
        SELECT current_user,
               has_table_privilege('public.books', 'SELECT'),
               has_table_privilege('public.book_embeddings', 'SELECT'),
               has_table_privilege('public.book_embeddings', 'INSERT'),
               has_table_privilege('public.book_embeddings', 'UPDATE')
    """)
    row = cursor.fetchone()
    report = {
        "role": row[0],
        "books_select": bool(row[1]),
        "embeddings_select": bool(row[2]),
        "embeddings_insert": bool(row[3]),
        "embeddings_update": bool(row[4]),
    }
    # RLS applies unless the role is superuser/BYPASSRLS, or owns the table without FORCE RLS.
    cursor.execute("""
        SELECT c.relrowsecurity
               AND NOT (r.rolsuper OR r.rolbypassrls
                        OR (pg_has_role(current_user, c.relowner, 'USAGE') AND NOT c.relforcerowsecurity))
        FROM pg_class c, pg_roles r
        WHERE c.oid = 'public.book_embeddings'::regclass AND r.rolname = current_user
    """)
    rls_row = cursor.fetchone()
    report["embeddings_rls_applies"] = bool(rls_row[0]) if rls_row else False
    missing = [name for name in ("books_select", "embeddings_select", "embeddings_insert", "embeddings_update")
               if not report[name]]
    report["missing_privileges"] = missing
    return report


def _log_preflight(report: dict) -> None:
    logger.info("Preflight: connected as role %r", report["role"])
    for name in report["missing_privileges"]:
        table, action = name.split("_")
        table = "books" if table == "books" else "book_embeddings"
        logger.error("Preflight: role %r lacks %s on public.%s (GRANT %s ON public.%s TO %s;)",
                     report["role"], action.upper(), table, action.upper(), table, report["role"])
    if report["embeddings_rls_applies"]:
        logger.warning(
            "Preflight: Row Level Security applies to role %r on public.book_embeddings. Upserts need "
            "INSERT and UPDATE policies (USING and WITH CHECK) for this role, otherwise rows are "
            "rejected or silently filtered. Connect as the table owner (the default 'postgres' "
            "connection string) rather than weakening the policies.", report["role"])
    if not report["missing_privileges"] and not report["embeddings_rls_applies"]:
        logger.info("Preflight: all required privileges present; RLS does not restrict this role.")


def backfill_embeddings(batch_size: int = 100, max_books: int = None, force_recompute: bool = False,
                        allow_profile_migration: bool = False, check_only: bool = False):
    """
    Embeds books whose vector is missing or stale. Stale = the canonical text changed (content
    hash) OR the stored vector was produced under another embedding profile (model, dimension,
    document text format or document task type; see EmbeddingService.document_profile).

    Safe profile migration: if any stored vector has a different profile, the job refuses to
    start unless allow_profile_migration is set. While a migration runs the table holds two
    profiles, and EmbeddingService.embed_query refuses semantic queries until every row matches
    (RAG then serves its labelled fallback instead of mixing vector spaces). Run it in a
    maintenance window, then re-run without the flag to confirm nothing is left to migrate.

    All reads and writes go through the direct PostgreSQL connection (SUPABASE_DB_URL or
    DATABASE_URL); the Supabase REST API and its API key are not used. check_only runs the
    read-only preflight and reports how many books would be embedded, without calling Gemini
    or writing anything.
    """
    # No data port: the methods used below (profile, canonical text, hash, generate_embedding)
    # never read the store; this job reads and writes book_embeddings itself.
    embedding_service = EmbeddingService(book_data_port=None)

    if not check_only and not embedding_service.is_configured():
        logger.error("EmbeddingService is not configured (missing GEMINI_API_KEY).")
        sys.exit(1)

    profile = embedding_service.document_profile()
    logger.info("Starting embedding backfill with configuration %s", embedding_service.describe())

    # Pagination state
    processed = 0
    generated = 0
    skipped = 0
    would_embed = 0

    consecutive_failures = 0

    import psycopg2
    from dotenv import load_dotenv
    load_dotenv(os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(__file__))), ".env"), override=False)
    db_url = resolve_db_url()
    if not db_url:
        logger.error("Neither SUPABASE_DB_URL nor DATABASE_URL is set.")
        sys.exit(1)

    try:
        conn = psycopg2.connect(db_url)
    except Exception as e:
        logger.error("Could not connect to PostgreSQL: %s", _db_failure(e, db_url))
        sys.exit(1)
    conn.autocommit = True
    cursor = conn.cursor()

    try:
        try:
            report = preflight(cursor)
        except Exception as e:
            logger.error("Preflight failed: %s", _db_failure(e, db_url))
            raise SystemExit(1)
        _log_preflight(report)
        if report["missing_privileges"]:
            raise SystemExit(3)

        cursor.execute("""
            SELECT b.*, be.content_hash as current_hash, be.model_version as current_model
            FROM books b
            LEFT JOIN book_embeddings be ON b.isbn13 = be.book_id
            ORDER BY b.isbn13
        """)
        columns = [desc[0] for desc in cursor.description]
        books = [dict(zip(columns, row)) for row in cursor.fetchall()]

        foreign = sorted({
            str(b.get("current_model")) for b in books
            if b.get("current_model") and embedding_service.normalize_profile(b.get("current_model")) != profile
        })
        if foreign:
            n_foreign = sum(1 for b in books if b.get("current_model")
                            and embedding_service.normalize_profile(b.get("current_model")) != profile)
            if check_only:
                logger.warning("Check: %d stored vectors use other embedding profile(s) %s; the configured "
                               "profile is %r (a real run would refuse without --allow-profile-migration).",
                               n_foreign, foreign, profile)
            elif not allow_profile_migration:
                logger.error(
                    "%d stored vectors use other embedding profile(s) %s; the configured profile is %r. "
                    "Re-embedding them is a full migration (semantic search is disabled until it "
                    "finishes). Re-run with --allow-profile-migration to proceed, or restore the "
                    "EMBEDDING_* settings that match the stored vectors.", n_foreign, foreign, profile)
                raise SystemExit(2)
            logger.warning("Migrating %d vectors from profile(s) %s to %r.", n_foreign, foreign, profile)

        for book in books:
            if max_books and processed >= max_books:
                break

            book_id = book["isbn13"]
            current_hash = book.pop("current_hash", None)
            current_model = book.pop("current_model", None)
            processed += 1

            canonical_text = embedding_service.generate_canonical_text(book)
            if not canonical_text:
                logger.warning(f"Book {book_id} has empty canonical text. Skipping.")
                skipped += 1
                continue

            content_hash = embedding_service.generate_content_hash(canonical_text)

            # Stale when the text changed OR the vector came from another embedding profile
            # (different models, dimensions or task types give incompatible vector spaces).
            if not force_recompute:
                if current_hash == content_hash and embedding_service.normalize_profile(current_model) == profile:
                    skipped += 1
                    continue

            if check_only:
                would_embed += 1
                continue

            logger.info(f"Generating embedding for book {book_id}...")
            embedding = embedding_service.generate_embedding(canonical_text)

            if embedding:
                try:
                    embedding_str = "[" + ",".join(map(str, embedding)) + "]"
                    cursor.execute("""
                        INSERT INTO book_embeddings (book_id, embedding, content_hash, model_version)
                        VALUES (%s, %s, %s, %s)
                        ON CONFLICT (book_id) DO UPDATE SET
                            embedding = EXCLUDED.embedding,
                            content_hash = EXCLUDED.content_hash,
                            model_version = EXCLUDED.model_version,
                            updated_at = now()
                    """, (book_id, embedding_str, content_hash, profile))
                    success = True
                except Exception as e:
                    logger.error("Error upserting embedding directly: %s", _db_failure(e, db_url))
                    success = False

                if success:
                    generated += 1
                    consecutive_failures = 0
                else:
                    logger.error(f"Failed to save embedding for {book_id}")
            else:
                consecutive_failures += 1
                logger.error(f"Failed to generate embedding for {book_id}")
                if consecutive_failures >= 3:
                    logger.error("Too many consecutive failures. Aborting backfill due to possible quota limits.")
                    break

        if check_only:
            logger.info(f"Check complete (nothing written). Books: {processed}, up to date: {skipped}, "
                        f"would embed: {would_embed}")
            return {"processed": processed, "up_to_date": skipped, "would_embed": would_embed,
                    "preflight": report}
        logger.info(f"Backfill complete! Processed: {processed}, Generated: {generated}, Skipped: {skipped}")
    finally:
        cursor.close()
        conn.close()

    if consecutive_failures >= 3:
        sys.exit(1)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Backfill book embeddings.")
    parser.add_argument("--batch-size", type=int, default=100, help="Batch size for fetching books")
    parser.add_argument("--max-books", type=int, default=None, help="Maximum number of books to process")
    parser.add_argument("--force-recompute", action="store_true", help="Force recomputation of embeddings")
    parser.add_argument("--allow-profile-migration", action="store_true",
                        help="Re-embed vectors stored under a different embedding profile")
    parser.add_argument("--check", action="store_true",
                        help="Read-only: verify connectivity and privileges and count books that would be "
                             "embedded; no Gemini calls, no writes")

    args = parser.parse_args()
    backfill_embeddings(batch_size=args.batch_size, max_books=args.max_books, force_recompute=args.force_recompute,
                        allow_profile_migration=args.allow_profile_migration, check_only=args.check)
