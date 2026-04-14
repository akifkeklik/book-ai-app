#!/usr/bin/env python3
"""
enrich_with_google.py — Enrich books.csv with Google Books API metadata.

Fills in missing:
  - thumbnail (cover image URL)
  - description (book summary)
  - page_count
  - published_date

Usage:
    python scripts/enrich_with_google.py                        # enrich with defaults
    python scripts/enrich_with_google.py --csv data/books.csv   # custom path
    python scripts/enrich_with_google.py --dry-run              # preview only
    python scripts/enrich_with_google.py --limit 100            # process first 100
    python scripts/enrich_with_google.py --overwrite            # overwrite existing data

Requirements:
    - GOOGLE_BOOKS_API_KEY in `.env` (project root) or in your environment
    - OR pass as: python scripts/enrich_with_google.py --api-key AIzaSy...
"""

import argparse
import csv
import json
import logging
import os
import sys
import time
from pathlib import Path
from typing import Any, Dict, Optional

import requests

# ── Ensure backend package is importable ──────────────────────────────────────
_SCRIPT_DIR = Path(__file__).resolve().parent
_BACKEND_DIR = _SCRIPT_DIR.parent
if str(_BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(_BACKEND_DIR))

from config import Config

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger("enrich")

# ── ANSI colours ──────────────────────────────────────────────────────────────
_GREEN = "\033[92m"
_YELLOW = "\033[93m"
_RED = "\033[91m"
_CYAN = "\033[96m"
_BOLD = "\033[1m"
_DIM = "\033[2m"
_RESET = "\033[0m"

# ── Google Books API ──────────────────────────────────────────────────────────
API_BASE = "https://www.googleapis.com/books/v1/volumes"

# Rate limiting: Google free tier = 1,000 requests/day
# We'll do max 1 request per second to be safe.
REQUEST_DELAY_S = 1.0
MAX_RETRIES = 2


def search_google_books(
    title: str,
    authors: str,
    isbn: str,
    api_key: str,
) -> Optional[Dict[str, Any]]:
    """
    Query Google Books API for a book by title+author or ISBN.

    Returns the best matching volumeInfo dict, or None.
    """
    # Try ISBN first (most precise)
    queries = []
    if isbn and len(isbn) >= 10:
        queries.append(f"isbn:{isbn}")

    # Fallback: title + author
    first_author = authors.split(",")[0].strip() if authors else ""
    if title:
        q = f"intitle:{title}"
        if first_author and first_author.lower() != "unknown author":
            q += f"+inauthor:{first_author}"
        queries.append(q)

    for query in queries:
        for attempt in range(MAX_RETRIES + 1):
            try:
                resp = requests.get(
                    API_BASE,
                    params={
                        "q": query,
                        "key": api_key,
                        "maxResults": 1,
                        "fields": "items(volumeInfo)",
                    },
                    timeout=10,
                )

                if resp.status_code == 429:
                    # Rate limited — wait and retry
                    wait = 2 ** attempt * 5
                    logger.warning(f"  Rate limited. Waiting {wait}s...")
                    time.sleep(wait)
                    continue

                resp.raise_for_status()
                data = resp.json()
                items = data.get("items", [])

                if items:
                    return items[0].get("volumeInfo", {})

            except requests.exceptions.Timeout:
                logger.debug(f"  Timeout for '{title}' (attempt {attempt + 1})")
                time.sleep(1)
            except requests.exceptions.RequestException as exc:
                logger.debug(f"  API error for '{title}': {exc}")
                break

    return None


def extract_thumbnail(volume_info: Dict[str, Any]) -> str:
    """Extract the best available thumbnail URL from volumeInfo."""
    links = volume_info.get("imageLinks", {})
    # Prefer larger images
    for key in ["thumbnail", "smallThumbnail", "large", "medium"]:
        url = links.get(key, "")
        if url:
            # Use HTTPS and remove zoom parameter for highest quality
            return url.replace("http://", "https://")
    return ""


def extract_description(volume_info: Dict[str, Any]) -> str:
    """Extract description, preferring the longer one."""
    desc = volume_info.get("description", "")
    if not desc:
        desc = volume_info.get("textSnippet", "")
    # Clean HTML tags
    import re
    desc = re.sub(r"<[^>]+>", " ", desc)
    desc = re.sub(r"\s+", " ", desc).strip()
    return desc


def enrich_csv(
    csv_path: str,
    api_key: str,
    overwrite: bool = False,
    limit: int = 0,
    dry_run: bool = False,
) -> Dict[str, int]:
    """
    Read books.csv, query Google Books API for missing metadata,
    and write the enriched version back.

    Returns a stats dict with counts of fields filled.
    """
    import pandas as pd

    logger.info(f"Reading {csv_path}...")
    df = pd.read_csv(csv_path, encoding="utf-8")
    total = len(df)
    logger.info(f"Loaded {_BOLD}{total}{_RESET} books")

    # ── Identify what needs enrichment ────────────────────────────────────────
    needs_thumb = df["thumbnail"].fillna("").str.len() < 5
    needs_desc = df["description"].fillna("").str.len() < 10
    needs_pages = pd.to_numeric(df["page_count"], errors="coerce").fillna(0) <= 0
    needs_date = df["published_date"].fillna("").astype(str).str.len() < 4

    if overwrite:
        # Process all books
        needs_enrichment = pd.Series([True] * total, index=df.index)
    else:
        # Only books missing at least one field
        needs_enrichment = needs_thumb | needs_desc

    indices_to_process = df[needs_enrichment].index.tolist()
    if limit > 0:
        indices_to_process = indices_to_process[:limit]

    n_to_process = len(indices_to_process)

    logger.info(f"\n{_BOLD}Enrichment Summary (before):{_RESET}")
    logger.info(f"  Missing thumbnails  : {needs_thumb.sum()}")
    logger.info(f"  Missing descriptions: {needs_desc.sum()}")
    logger.info(f"  Missing page count  : {needs_pages.sum()}")
    logger.info(f"  Missing pub date    : {needs_date.sum()}")
    logger.info(f"  Books to process    : {_BOLD}{n_to_process}{_RESET}")

    if n_to_process == 0:
        logger.info(f"\n{_GREEN}All books already have complete metadata!{_RESET}")
        return {"processed": 0, "thumbnails_added": 0, "descriptions_added": 0}

    if dry_run:
        logger.info(f"\n{_YELLOW}DRY RUN — no API calls will be made.{_RESET}")
        sample = df.loc[indices_to_process[:5], ["title", "authors"]]
        logger.info(f"\n  Sample books to be enriched:")
        for _, row in sample.iterrows():
            logger.info(f"    • {row['title']}")
        return {"processed": 0, "thumbnails_added": 0, "descriptions_added": 0}

    # ── Process books ─────────────────────────────────────────────────────────
    stats = {
        "processed": 0,
        "api_hits": 0,
        "thumbnails_added": 0,
        "descriptions_added": 0,
        "pages_added": 0,
        "dates_added": 0,
        "errors": 0,
    }

    logger.info(f"\n{_BOLD}Enriching {n_to_process} books via Google Books API...{_RESET}")
    logger.info(f"  {_DIM}(~{n_to_process * REQUEST_DELAY_S:.0f}s estimated){_RESET}\n")

    t0 = time.perf_counter()

    for i, idx in enumerate(indices_to_process):
        row = df.iloc[idx]
        title = str(row.get("title", ""))
        authors = str(row.get("authors", ""))
        isbn = str(row.get("isbn13", ""))

        pct = (i + 1) / n_to_process * 100
        progress = f"[{i + 1}/{n_to_process}] ({pct:.0f}%)"

        # ── Query API ─────────────────────────────────────────────────────────
        info = search_google_books(title, authors, isbn, api_key)
        stats["processed"] += 1

        if info:
            stats["api_hits"] += 1

            # Thumbnail
            current_thumb = str(row.get("thumbnail", ""))
            if overwrite or len(current_thumb) < 5:
                new_thumb = extract_thumbnail(info)
                if new_thumb:
                    df.at[idx, "thumbnail"] = new_thumb
                    stats["thumbnails_added"] += 1

            # Description
            current_desc = str(row.get("description", ""))
            if overwrite or len(current_desc) < 10:
                new_desc = extract_description(info)
                if new_desc and len(new_desc) > 10:
                    df.at[idx, "description"] = new_desc
                    stats["descriptions_added"] += 1

            # Page count
            current_pages = int(row.get("page_count", 0)) if pd.notna(row.get("page_count")) else 0
            if overwrite or current_pages <= 0:
                new_pages = info.get("pageCount", 0)
                if new_pages and int(new_pages) > 0:
                    df.at[idx, "page_count"] = int(new_pages)
                    stats["pages_added"] += 1

            # Published date
            current_date = str(row.get("published_date", ""))
            if overwrite or len(current_date) < 4:
                new_date = info.get("publishedDate", "")
                if new_date:
                    df.at[idx, "published_date"] = new_date
                    stats["dates_added"] += 1

            logger.info(
                f"  {_GREEN}✓{_RESET} {progress} {title[:45]:45s}"
            )
        else:
            # No result — generate OpenLibrary fallback for thumbnail
            current_thumb = str(row.get("thumbnail", ""))
            if len(current_thumb) < 5 and isbn and len(isbn) > 5:
                df.at[idx, "thumbnail"] = f"https://covers.openlibrary.org/b/isbn/{isbn}-L.jpg"
                stats["thumbnails_added"] += 1

            logger.info(
                f"  {_YELLOW}○{_RESET} {progress} {title[:45]:45s} {_DIM}(no Google result){_RESET}"
            )

        # Rate limiting
        time.sleep(REQUEST_DELAY_S)

    elapsed = time.perf_counter() - t0

    # ── Write back ────────────────────────────────────────────────────────────
    df.to_csv(csv_path, index=False, quoting=csv.QUOTE_ALL, encoding="utf-8")
    logger.info(f"\n  {_GREEN}{_BOLD}✓ Enriched CSV saved → {csv_path}{_RESET}")

    # ── Final report ──────────────────────────────────────────────────────────
    logger.info(f"\n{'─' * 55}")
    logger.info(f"  {_BOLD}Enrichment Results{_RESET}")
    logger.info(f"  Processed     : {stats['processed']}")
    logger.info(f"  API hits      : {stats['api_hits']}")
    logger.info(f"  Thumbnails +  : {_GREEN}{stats['thumbnails_added']}{_RESET}")
    logger.info(f"  Descriptions +: {_GREEN}{stats['descriptions_added']}{_RESET}")
    logger.info(f"  Page counts + : {_GREEN}{stats['pages_added']}{_RESET}")
    logger.info(f"  Pub dates +   : {_GREEN}{stats['dates_added']}{_RESET}")
    logger.info(f"  Errors        : {stats['errors']}")
    logger.info(f"  Time          : {elapsed:.1f}s")
    logger.info(f"{'─' * 55}\n")

    return stats


# ═════════════════════════════════════════════════════════════════════════════
# Main
# ═════════════════════════════════════════════════════════════════════════════

def main() -> int:
    parser = argparse.ArgumentParser(
        description="Enrich books.csv with metadata from Google Books API.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python scripts/enrich_with_google.py                        # enrich missing data
  python scripts/enrich_with_google.py --dry-run              # preview only
  python scripts/enrich_with_google.py --limit 50             # first 50 books
  python scripts/enrich_with_google.py --overwrite            # refresh all metadata
  python scripts/enrich_with_google.py --api-key AIzaSy...    # pass key directly
        """,
    )

    parser.add_argument(
        "--csv",
        default=Config.DATA_PATH,
        help=f"Path to books CSV (default: {Config.DATA_PATH})",
    )
    parser.add_argument(
        "--api-key",
        default="",
        help="Google Books API key (overrides .env)",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=0,
        help="Max books to process (0 = all)",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Overwrite existing thumbnail/description data",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview enrichment without making API calls",
    )

    args = parser.parse_args()

    # ── Resolve API key ───────────────────────────────────────────────────────
    api_key = args.api_key or Config.GOOGLE_BOOKS_API_KEY

    if not api_key and not args.dry_run:
        logger.error(
            f"{_RED}No Google Books API key found!{_RESET}\n\n"
            f"  Option 1: Add to .env (project root):\n"
            f"    GOOGLE_BOOKS_API_KEY=AIzaSy...\n\n"
            f"  Option 2: Pass directly:\n"
            f"    python scripts/enrich_with_google.py --api-key AIzaSy...\n\n"
            f"  Option 3: Preview without key:\n"
            f"    python scripts/enrich_with_google.py --dry-run\n\n"
            f"  Get a key: https://console.cloud.google.com\n"
            f"  Guide: docs/google_api_setup.md"
        )
        return 1

    if not os.path.exists(args.csv):
        logger.error(f"{_RED}CSV not found: {args.csv}{_RESET}")
        return 1

    # ── Banner ────────────────────────────────────────────────────────────────
    logger.info(f"\n{_CYAN}{'═' * 55}{_RESET}")
    logger.info(f"{_CYAN}║  {_BOLD}BookAI — Google Books Enrichment{_RESET}{_CYAN}{'':>18s}║{_RESET}")
    logger.info(f"{_CYAN}{'═' * 55}{_RESET}\n")

    # ── Run ───────────────────────────────────────────────────────────────────
    stats = enrich_csv(
        csv_path=args.csv,
        api_key=api_key or "dry-run",
        overwrite=args.overwrite,
        limit=args.limit,
        dry_run=args.dry_run,
    )

    if not args.dry_run and stats["processed"] > 0:
        logger.info(f"  {_BOLD}Next step:{_RESET}")
        logger.info(f"  python train_model.py --force --validate\n")

    return 0


if __name__ == "__main__":
    sys.exit(main())
