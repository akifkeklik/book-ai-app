#!/usr/bin/env python3
"""
fetch_kaggle_data.py — Kaggle dataset downloader & converter for Libris.

Supports two modes:
  1. MANUAL:  Download CSV from Kaggle website, place it anywhere, run this script
  2. API:    Automatically download via Kaggle API (requires kaggle credentials)

Usage:
    # Mode 1 — You already downloaded the CSV manually:
    python scripts/fetch_kaggle_data.py --input path/to/downloaded.csv

    # Mode 2 — Auto-download via Kaggle API:
    python scripts/fetch_kaggle_data.py --kaggle dylanjcastillo/7k-books-with-metadata

    # Preview what the script will do without saving:
    python scripts/fetch_kaggle_data.py --input raw.csv --dry-run

    # Keep only books with descriptions:
    python scripts/fetch_kaggle_data.py --input raw.csv --require-description

Output:
    backend/data/books.csv (the old file is backed up to books_backup_*.csv)
"""

import argparse
import csv
import logging
import os
import shutil
import sys
import time
from datetime import datetime
from pathlib import Path

# ── Ensure backend package is importable ──────────────────────────────────────
_SCRIPT_DIR = Path(__file__).resolve().parent
_BACKEND_DIR = _SCRIPT_DIR.parent
if str(_BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(_BACKEND_DIR))

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger("fetch_data")

# ── ANSI colours ──────────────────────────────────────────────────────────────
_GREEN = "\033[92m"
_YELLOW = "\033[93m"
_RED = "\033[91m"
_CYAN = "\033[96m"
_BOLD = "\033[1m"
_RESET = "\033[0m"

# ── Target schema ─────────────────────────────────────────────────────────────
# Our books.csv must have exactly these columns in this order.
TARGET_COLUMNS = [
    "isbn13",
    "title",
    "authors",
    "categories",
    "description",
    "thumbnail",
    "average_rating",
    "ratings_count",
    "published_date",
    "page_count",
]

# ── Common Kaggle column name mappings ────────────────────────────────────────
# Different Kaggle datasets use different column names. We normalise them all.
COLUMN_ALIASES = {
    # isbn13
    "isbn13":          "isbn13",
    "isbn_13":         "isbn13",
    "isbn":            "isbn13",
    "ISBN13":          "isbn13",

    # title
    "title":           "title",
    "Title":           "title",
    "book_title":      "title",
    "original_title":  "title",

    # authors
    "authors":         "authors",
    "author":          "authors",
    "Author":          "authors",
    "book_authors":    "authors",

    # categories
    "categories":      "categories",
    "category":        "categories",
    "genre":           "categories",
    "genres":          "categories",
    "subject":         "categories",
    "subjects":        "categories",

    # description
    "description":     "description",
    "Description":     "description",
    "summary":         "description",
    "Synopsis":        "description",

    # thumbnail
    "thumbnail":       "thumbnail",
    "image_url":       "thumbnail",
    "imageLinks":      "thumbnail",
    "cover":           "thumbnail",
    "cover_url":       "thumbnail",
    "image":           "thumbnail",
    "smallThumbnail":  "thumbnail",

    # average_rating
    "average_rating":  "average_rating",
    "rating":          "average_rating",
    "avg_rating":      "average_rating",
    "averageRating":   "average_rating",

    # ratings_count
    "ratings_count":   "ratings_count",
    "rating_count":    "ratings_count",
    "ratingsCount":    "ratings_count",
    "num_ratings":     "ratings_count",
    "count":           "ratings_count",
    "text_reviews_count": "ratings_count",

    # published_date
    "published_date":  "published_date",
    "publishedDate":   "published_date",
    "published_year":  "published_date",
    "publication_date":"published_date",
    "year":            "published_date",
    "original_publication_year": "published_date",

    # page_count
    "page_count":      "page_count",
    "pageCount":       "page_count",
    "num_pages":       "page_count",
    "pages":           "page_count",
}


# ═════════════════════════════════════════════════════════════════════════════
# Kaggle API Download
# ═════════════════════════════════════════════════════════════════════════════

def download_from_kaggle(dataset_slug: str, output_dir: str) -> str:
    """
    Download a dataset from Kaggle using the Kaggle API.

    Requires:
      - pip install kaggle
      - Kaggle API token at ~/.kaggle/kaggle.json
        (Get it from: kaggle.com → Account → Create New API Token)

    Returns the path to the largest CSV file in the download.
    """
    try:
        from kaggle.api.kaggle_api_extended import KaggleApi
    except ImportError:
        logger.error(
            f"{_RED}Kaggle API not installed.{_RESET}\n"
            f"  Install: pip install kaggle\n"
            f"  Then place your API token at: ~/.kaggle/kaggle.json\n"
            f"  Get token: https://www.kaggle.com/settings → API → Create New Token"
        )
        sys.exit(1)

    logger.info(f"Authenticating with Kaggle API...")
    api = KaggleApi()
    api.authenticate()

    dl_path = os.path.join(output_dir, "_kaggle_raw")
    os.makedirs(dl_path, exist_ok=True)

    logger.info(f"Downloading dataset: {_CYAN}{dataset_slug}{_RESET}")
    api.dataset_download_files(dataset_slug, path=dl_path, unzip=True)

    # Find the largest CSV
    csv_files = sorted(
        Path(dl_path).rglob("*.csv"),
        key=lambda f: f.stat().st_size,
        reverse=True,
    )
    if not csv_files:
        logger.error(f"{_RED}No CSV files found in downloaded dataset!{_RESET}")
        sys.exit(1)

    chosen = str(csv_files[0])
    logger.info(f"Using: {_GREEN}{chosen}{_RESET} ({csv_files[0].stat().st_size / 1024:.0f} KB)")
    return chosen


# ═════════════════════════════════════════════════════════════════════════════
# CSV Conversion
# ═════════════════════════════════════════════════════════════════════════════

def detect_encoding(file_path: str) -> str:
    """Detect the encoding of a file by trying common ones."""
    for enc in ["utf-8", "utf-8-sig", "latin-1", "cp1252", "iso-8859-1"]:
        try:
            with open(file_path, "r", encoding=enc) as f:
                f.read(4096)
            return enc
        except (UnicodeDecodeError, UnicodeError):
            continue
    return "utf-8"


def map_columns(raw_columns: list) -> dict:
    """
    Map raw CSV columns to our target schema.
    Returns a dict: { raw_column_name: target_column_name }
    """
    mapping = {}
    for raw in raw_columns:
        clean = raw.strip()
        if clean in COLUMN_ALIASES:
            target = COLUMN_ALIASES[clean]
            if target not in mapping.values():  # first match wins
                mapping[clean] = target

    return mapping


def convert_csv(
    input_path: str,
    output_path: str,
    require_description: bool = False,
    min_title_length: int = 2,
    dry_run: bool = False,
) -> int:
    """
    Read a Kaggle CSV, normalise columns, clean data, and write
    to our target format.

    Returns the number of books written.
    """
    # ── Detect encoding ───────────────────────────────────────────────────────
    encoding = detect_encoding(input_path)
    logger.info(f"Detected encoding: {encoding}")

    # ── Read raw CSV ──────────────────────────────────────────────────────────
    import pandas as pd

    df = pd.read_csv(input_path, encoding=encoding, on_bad_lines="skip", low_memory=False)
    logger.info(f"Raw CSV loaded: {_BOLD}{len(df)} rows{_RESET}, {len(df.columns)} columns")
    logger.info(f"  Columns: {list(df.columns)}")

    # ── Map columns ───────────────────────────────────────────────────────────
    col_map = map_columns(list(df.columns))
    if not col_map:
        logger.error(f"{_RED}Could not map any columns!{_RESET}")
        logger.error(f"  Raw columns: {list(df.columns)}")
        logger.error(f"  Expected some of: {list(set(COLUMN_ALIASES.keys()))}")
        return 0

    logger.info(f"  Column mapping:")
    for raw, target in sorted(col_map.items(), key=lambda x: x[1]):
        logger.info(f"    {raw:30s} → {_GREEN}{target}{_RESET}")

    df = df.rename(columns=col_map)

    # ── Ensure all target columns exist ───────────────────────────────────────
    for col in TARGET_COLUMNS:
        if col not in df.columns:
            logger.warning(f"  {_YELLOW}Missing column '{col}' — filling with defaults{_RESET}")
            if col in ("average_rating", "ratings_count", "page_count"):
                df[col] = 0
            else:
                df[col] = ""

    # ── Data cleaning ─────────────────────────────────────────────────────────
    logger.info(f"\n{_BOLD}Cleaning data...{_RESET}")

    # Fill NaN
    df["title"] = df["title"].fillna("").astype(str).str.strip()
    df["authors"] = df["authors"].fillna("Unknown Author").astype(str).str.strip()
    df["categories"] = df["categories"].fillna("General").astype(str).str.strip()
    df["description"] = df["description"].fillna("").astype(str).str.strip()
    df["thumbnail"] = df["thumbnail"].fillna("").astype(str).str.strip()
    df["published_date"] = df["published_date"].fillna("").astype(str).str.strip()
    df["isbn13"] = df["isbn13"].fillna("").astype(str).str.strip()

    # Numeric
    df["average_rating"] = pd.to_numeric(df["average_rating"], errors="coerce").fillna(0.0)
    df["ratings_count"] = pd.to_numeric(df["ratings_count"], errors="coerce").fillna(0).astype(int)
    df["page_count"] = pd.to_numeric(df["page_count"], errors="coerce").fillna(0).astype(int)

    # ── Filters ───────────────────────────────────────────────────────────────
    before = len(df)

    # Remove books with no/tiny title
    df = df[df["title"].str.len() >= min_title_length]
    logger.info(f"  Removed {before - len(df)} books with title < {min_title_length} chars")

    # Remove exact duplicate titles
    before = len(df)
    df = df.drop_duplicates(subset=["title"], keep="first")
    logger.info(f"  Removed {before - len(df)} duplicate titles")

    # Optionally require description
    if require_description:
        before = len(df)
        df = df[df["description"].str.len() > 10]
        logger.info(f"  Removed {before - len(df)} books without descriptions")

    # Clamp ratings
    df["average_rating"] = df["average_rating"].clip(0.0, 5.0)

    # ── Generate thumbnails for missing ones ──────────────────────────────────
    mask_no_thumb = df["thumbnail"].str.len() < 5
    isbn_available = df["isbn13"].str.len() > 5
    df.loc[mask_no_thumb & isbn_available, "thumbnail"] = (
        "https://covers.openlibrary.org/b/isbn/"
        + df.loc[mask_no_thumb & isbn_available, "isbn13"]
        + "-L.jpg"
    )
    n_filled = (mask_no_thumb & isbn_available).sum()
    if n_filled > 0:
        logger.info(f"  Generated {n_filled} OpenLibrary cover URLs")

    # ── Select only target columns ────────────────────────────────────────────
    df = df[TARGET_COLUMNS].reset_index(drop=True)

    # ── Quality report ────────────────────────────────────────────────────────
    n = len(df)
    n_desc = (df["description"].str.len() > 10).sum()
    n_thumb = (df["thumbnail"].str.len() > 5).sum()
    n_rating = (df["average_rating"] > 0).sum()
    n_isbn = (df["isbn13"].str.len() > 5).sum()

    logger.info(f"\n{'─' * 55}")
    logger.info(f"  {_BOLD}Quality Report{_RESET}")
    logger.info(f"  Total books     : {_BOLD}{n}{_RESET}")
    logger.info(f"  With ISBN       : {n_isbn} ({n_isbn/n*100:.0f}%)")
    logger.info(f"  With description: {n_desc} ({n_desc/n*100:.0f}%)")
    logger.info(f"  With thumbnail  : {n_thumb} ({n_thumb/n*100:.0f}%)")
    logger.info(f"  With rating > 0 : {n_rating} ({n_rating/n*100:.0f}%)")
    logger.info(f"{'─' * 55}")

    if n < 50:
        logger.warning(f"  {_YELLOW}⚠ Only {n} books — ML quality may be low{_RESET}")

    # ── Write output ──────────────────────────────────────────────────────────
    if dry_run:
        logger.info(f"\n{_YELLOW}DRY RUN — nothing written.{_RESET}")
        logger.info(f"  Would write {n} books to {output_path}")
        # Print sample
        logger.info(f"\n{_BOLD}Sample (first 5 rows):{_RESET}")
        for _, row in df.head().iterrows():
            logger.info(f"  {row['title'][:50]:50s} | {row['authors'][:25]:25s} | {row['categories'][:20]}")
        return n

    # Backup existing
    if os.path.exists(output_path):
        ts = datetime.now().strftime("%Y%m%d_%H%M%S")
        backup = output_path.replace(".csv", f"_backup_{ts}.csv")
        shutil.copy2(output_path, backup)
        logger.info(f"  Backed up existing → {_CYAN}{backup}{_RESET}")

    os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)
    df.to_csv(output_path, index=False, quoting=csv.QUOTE_ALL, encoding="utf-8")

    size_kb = os.path.getsize(output_path) / 1024
    logger.info(f"\n  {_GREEN}{_BOLD}✓ Wrote {n} books → {output_path} ({size_kb:.0f} KB){_RESET}")

    # ── Remind about pickle ───────────────────────────────────────────────────
    pkl_path = os.path.join(_BACKEND_DIR, "saved_model", "tfidf.pkl")
    if os.path.exists(pkl_path):
        logger.info(f"\n  {_YELLOW}⚠ Old model pickle exists: {pkl_path}{_RESET}")
        logger.info(f"  {_YELLOW}  Delete it or run: python train_model.py --force --validate{_RESET}")

    return n


# ═════════════════════════════════════════════════════════════════════════════
# Main
# ═════════════════════════════════════════════════════════════════════════════

def main() -> int:
    parser = argparse.ArgumentParser(
        description="Download & convert Kaggle book datasets for BookAI.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Manual: you already downloaded a CSV from Kaggle
  python scripts/fetch_kaggle_data.py --input ~/Downloads/books.csv

  # Auto-download from Kaggle API
  python scripts/fetch_kaggle_data.py --kaggle dylanjcastillo/7k-books-with-metadata

  # Preview without saving
  python scripts/fetch_kaggle_data.py --input raw.csv --dry-run

  # Only keep books with descriptions
  python scripts/fetch_kaggle_data.py --input raw.csv --require-description

Recommended Kaggle datasets:
  - dylanjcastillo/7k-books-with-metadata  (7,000 books, excellent metadata)
  - jealousleopard/goodreadsbooks          (10,000 books, Goodreads data)
  - mdhamani/goodreads-books-100k          (100,000 books, large scale)
        """,
    )

    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument(
        "--input", "-i",
        help="Path to a manually downloaded CSV file",
    )
    source.add_argument(
        "--kaggle", "-k",
        help="Kaggle dataset slug (e.g. 'dylanjcastillo/7k-books-with-metadata')",
    )

    parser.add_argument(
        "--output", "-o",
        default=os.path.join(_BACKEND_DIR, "data", "books.csv"),
        help="Output CSV path (default: backend/data/books.csv)",
    )
    parser.add_argument(
        "--require-description",
        action="store_true",
        help="Remove books without descriptions (improves ML quality)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview results without writing any files",
    )

    args = parser.parse_args()

    logger.info(f"\n{_CYAN}{'═' * 55}{_RESET}")
    logger.info(f"{_CYAN}║  {_BOLD}Libris — Kaggle Data Pipeline{_RESET}{_CYAN}{'':>21s}║{_RESET}")
    logger.info(f"{_CYAN}{'═' * 55}{_RESET}\n")

    # ── Resolve input path ────────────────────────────────────────────────────
    if args.kaggle:
        input_path = download_from_kaggle(args.kaggle, str(_BACKEND_DIR))
    else:
        input_path = args.input

    if not os.path.exists(input_path):
        logger.error(f"{_RED}File not found: {input_path}{_RESET}")
        return 1

    # ── Convert ───────────────────────────────────────────────────────────────
    t0 = time.perf_counter()
    n = convert_csv(
        input_path=input_path,
        output_path=args.output,
        require_description=args.require_description,
        dry_run=args.dry_run,
    )
    elapsed = time.perf_counter() - t0

    if n == 0:
        logger.error(f"{_RED}No books were processed. Check your CSV format.{_RESET}")
        return 1

    logger.info(f"\n  Total time: {elapsed:.2f}s")

    if not args.dry_run:
        logger.info(f"\n  {_BOLD}Next steps:{_RESET}")
        logger.info(f"  1. python scripts/enrich_with_google.py  (add covers)")
        logger.info(f"  2. python train_model.py --force --validate  (retrain model)")
        logger.info(f"  3. python app.py  (start the API)\n")

    return 0


if __name__ == "__main__":
    sys.exit(main())
