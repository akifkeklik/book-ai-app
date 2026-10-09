import argparse
import logging
import os
import sys

from supabase import Client, create_client

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config import Config
from infrastructure.persistence.supabase_adapters import SupabaseBookDataPort
from services.embedding_service import EmbeddingService

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger(__name__)

def backfill_embeddings(batch_size: int = 100, max_books: int = None, force_recompute: bool = False):
    url = Config.SUPABASE_URL
    key = Config.SUPABASE_ANON_KEY
    if not url or not key:
        logger.error("SUPABASE_URL or SUPABASE_ANON_KEY not set.")
        sys.exit(1)

    supabase: Client = create_client(url, key)
    book_data_port = SupabaseBookDataPort(supabase)
    embedding_service = EmbeddingService(book_data_port=book_data_port)

    if not embedding_service.is_configured():
        logger.error("EmbeddingService is not configured (missing OPENAI_API_KEY).")
        sys.exit(1)

    logger.info("Starting embedding backfill...")

    # Pagination state
    processed = 0
    generated = 0
    skipped = 0

    consecutive_failures = 0

    import psycopg2
    from dotenv import load_dotenv
    load_dotenv(os.path.join(os.path.dirname(os.path.dirname(__file__)), ".env"))
    db_url = os.environ.get("SUPABASE_DB_URL")
    if not db_url:
        logger.error("SUPABASE_DB_URL not set.")
        sys.exit(1)

    conn = psycopg2.connect(db_url)
    conn.autocommit = True
    cursor = conn.cursor()

    cursor.execute("""
        SELECT b.*, be.content_hash as current_hash
        FROM books b
        LEFT JOIN book_embeddings be ON b.isbn13 = be.book_id
        ORDER BY b.isbn13
    """)
    columns = [desc[0] for desc in cursor.description]
    books = [dict(zip(columns, row)) for row in cursor.fetchall()]

    for book in books:
        if max_books and processed >= max_books:
            break

        book_id = book["isbn13"]
        current_hash = book.pop("current_hash", None)
        processed += 1

        canonical_text = embedding_service.generate_canonical_text(book)
        if not canonical_text:
            logger.warning(f"Book {book_id} has empty canonical text. Skipping.")
            skipped += 1
            continue

        content_hash = embedding_service.generate_content_hash(canonical_text)

        # Check staleness
        if not force_recompute:
            if current_hash == content_hash:
                skipped += 1
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
                        model_version = EXCLUDED.model_version
                """, (book_id, embedding_str, content_hash, embedding_service._model))
                success = True
            except Exception as e:
                logger.error(f"Error upserting embedding directly: {e}")
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
                sys.exit(1)

    logger.info(f"Backfill complete! Processed: {processed}, Generated: {generated}, Skipped: {skipped}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Backfill book embeddings.")
    parser.add_argument("--batch-size", type=int, default=100, help="Batch size for fetching books")
    parser.add_argument("--max-books", type=int, default=None, help="Maximum number of books to process")
    parser.add_argument("--force-recompute", action="store_true", help="Force recomputation of embeddings")

    args = parser.parse_args()
    backfill_embeddings(batch_size=args.batch_size, max_books=args.max_books, force_recompute=args.force_recompute)
