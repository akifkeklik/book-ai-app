import argparse
import logging
import os
import sys

from supabase import Client, create_client

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config import Config
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
    embedding_service = EmbeddingService(supabase_client=supabase)

    if not embedding_service.is_configured():
        logger.error("EmbeddingService is not configured (missing OPENAI_API_KEY).")
        sys.exit(1)

    logger.info("Starting embedding backfill...")

    # Pagination state
    processed = 0
    generated = 0
    skipped = 0
    last_id = "0"

    while True:
        if max_books and processed >= max_books:
            break

        limit = min(batch_size, max_books - processed) if max_books else batch_size

        # Cursor based pagination to avoid OFFSET issues
        resp = supabase.table("books").select("*").order("isbn13").gt("isbn13", last_id).limit(limit).execute()
        books = getattr(resp, "data", [])

        if not books:
            break

        for book in books:
            book_id = book["isbn13"]
            last_id = book_id
            processed += 1

            canonical_text = embedding_service.generate_canonical_text(book)
            if not canonical_text:
                logger.warning(f"Book {book_id} has empty canonical text. Skipping.")
                skipped += 1
                continue

            content_hash = embedding_service.generate_content_hash(canonical_text)

            # Check staleness
            if not force_recompute:
                if not embedding_service.is_stale(book_id, content_hash):
                    logger.debug(f"Book {book_id} is up-to-date. Skipping.")
                    skipped += 1
                    continue

            logger.info(f"Generating embedding for book {book_id}...")
            embedding = embedding_service.generate_embedding(canonical_text)

            if embedding:
                success = embedding_service.upsert_embedding(book_id, embedding, content_hash)
                if success:
                    generated += 1
                else:
                    logger.error(f"Failed to save embedding for {book_id}")
            else:
                logger.error(f"Failed to generate embedding for {book_id}")

    logger.info(f"Backfill complete! Processed: {processed}, Generated: {generated}, Skipped: {skipped}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Backfill book embeddings.")
    parser.add_argument("--batch-size", type=int, default=100, help="Batch size for fetching books")
    parser.add_argument("--max-books", type=int, default=None, help="Maximum number of books to process")
    parser.add_argument("--force-recompute", action="store_true", help="Force recomputation of embeddings")

    args = parser.parse_args()
    backfill_embeddings(batch_size=args.batch_size, max_books=args.max_books, force_recompute=args.force_recompute)
