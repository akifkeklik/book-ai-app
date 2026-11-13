#!/usr/bin/env python3
"""
fetch_candidates.py - Controlled Enrichment Pipeline for Libris.

Fetches real books from Google Books API (Open Library fallback) into a
SEPARATE candidate file.  The main books.csv is NEVER modified.

Pipeline guarantees:
  - ISBN-13 validated (Luhn-style check digit)
  - Taxonomy classification via backend/domain/taxonomy.py (single source of truth)
  - Duplicate detection against existing books.csv AND within candidate pool
  - Metadata quality gate (hard reject / soft warning)
  - Source provenance recorded per book
  - Deterministic output - idempotent on re-run
  - Zero fabricated fields (missing -> null / warning)

Usage:
    python scripts/fetch_candidates.py --category romance --limit 10
    python scripts/fetch_candidates.py --batch
    python scripts/fetch_candidates.py --batch --dry-run

Requirements:
    GOOGLE_BOOKS_API_KEY in backend/.env  (env var, never CLI)
"""

from __future__ import annotations

import argparse
import csv
import logging
import re
import subprocess
import sys
import time
from collections import Counter
from pathlib import Path

import requests

_SCRIPT_DIR = Path(__file__).resolve().parent
_BACKEND_DIR = _SCRIPT_DIR.parent
if str(_BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(_BACKEND_DIR))

from config import Config  # noqa: E402
from domain.taxonomy import BROAD_SUBJECTS, CANONICAL_CATEGORY_MAP  # noqa: E402

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger("fetch_candidates")

_G = "\033[92m"
_Y = "\033[93m"
_R = "\033[91m"
_C = "\033[96m"
_B = "\033[1m"
_D = "\033[2m"
_X = "\033[0m"

GOOGLE_API_BASE = "https://www.googleapis.com/books/v1/volumes"
OPEN_LIBRARY_API = "https://openlibrary.org/search.json"
OPEN_LIBRARY_COVER = "https://covers.openlibrary.org/b/isbn/{isbn}-L.jpg"

REQUEST_DELAY_S = 1.2
MAX_RETRIES = 2
MIN_DESCRIPTION_LEN = 50

CANDIDATE_COLUMNS = [
    "isbn13", "title", "authors", "raw_categories", "canonical_category",
    "description", "thumbnail", "average_rating", "ratings_count",
    "published_date", "page_count", "source", "taxonomy_confidence",
    "validation_status",
]

CATEGORY_QUERIES: dict[str, list[str]] = {
    "romance": ["subject:romance", "subject:love+stories"],
    "horror": ["subject:horror", "subject:horror+fiction"],
    "science fiction": ["subject:science+fiction", "subject:space+opera"],
    "fantasy": ["subject:fantasy", "subject:epic+fantasy"],
    "mystery & thriller": ["subject:mystery", "subject:thriller", "subject:crime+fiction"],
}

CATEGORY_CANONICAL: dict[str, str] = {
    "romance": "Romance",
    "horror": "Horror",
    "science fiction": "Science Fiction",
    "fantasy": "Fantasy",
    "mystery & thriller": "Mystery & Thriller",
}

_AMBIGUOUS_SUBJECTS = frozenset({
    "magic", "suspense", "literature", "relationships", "adventure",
    "family", "love", "death", "war", "life", "society", "supernatural", "paranormal",
})


def classify_category(
    raw_categories: list[str],
    expected_canonical: str,
    title: str = "",
    description: str = "",
) -> tuple[str, str]:
    """Classify raw Google Books subjects against the target canonical category.

    Returns (canonical_category, confidence).
    """
    hits: list[tuple[str, str]] = []
    for raw in raw_categories:
        normalised = raw.lower().strip()
        if normalised in _AMBIGUOUS_SUBJECTS:
            continue

        if normalised in CANONICAL_CATEGORY_MAP:
            hits.append((CANONICAL_CATEGORY_MAP[normalised], normalised))
        else:
            # Try splitting by comma for strings like "Fiction, romance, general"
            for part in normalised.split(","):
                p = part.strip()
                if p in _AMBIGUOUS_SUBJECTS:
                    continue
                if p in CANONICAL_CATEGORY_MAP:
                    hits.append((CANONICAL_CATEGORY_MAP[p], p))

    def _check_evidence() -> tuple[str, str]:
        text = f"{title} {description} {' '.join(raw_categories)}".lower()
        if expected_canonical.lower() in text:
            return expected_canonical, "LOW"
        # Check synonyms
        synonyms = CATEGORY_QUERIES.get(expected_canonical.lower(), [])
        for syn in synonyms:
            syn_clean = syn.replace("subject:", "").replace("+", " ")
            if syn_clean in text:
                return expected_canonical, "LOW"
        return "NEEDS_HUMAN_REVIEW", "NEEDS_HUMAN_REVIEW"

    if not hits:
        return _check_evidence()

    # --- Broad-subject guard -------------------------------------------
    all_broad = all(raw_subject in BROAD_SUBJECTS for _, raw_subject in hits)
    if all_broad:
        return _check_evidence()
    # -------------------------------------------------------------------

    specific_hits = [c for c, raw_subject in hits if raw_subject not in BROAD_SUBJECTS]
    counts = Counter(specific_hits)
    winner, winner_count = counts.most_common(1)[0]
    confidence = "HIGH" if winner_count >= 2 or len(specific_hits) == 1 else "LOW"
    if winner != expected_canonical:
        confidence = "LOW"
    return winner, confidence


def validate_isbn13(isbn: str) -> bool:
    if not isbn:
        return False
    isbn = re.sub(r"[^0-9]", "", isbn)
    if len(isbn) != 13:
        return False
    total = sum(int(d) * (1 if i % 2 == 0 else 3) for i, d in enumerate(isbn))
    return total % 10 == 0


def normalise_isbn(raw: str) -> str:
    digits = re.sub(r"[^0-9]", "", str(raw))
    return digits if len(digits) == 13 else ""


def strip_html(text: str) -> str:
    text = re.sub(r"<[^>]+>", " ", text)
    return re.sub(r"\s+", " ", text).strip()


def normalise_title(title: str) -> str:
    return re.sub(r"\s+", " ", title.lower().strip())


def normalise_author(authors: str) -> str:
    return authors.split("|")[0].split(",")[0].strip().lower()


def _google_request(params: dict, api_key: str) -> list[dict]:
    params = {**params, "key": api_key}
    for attempt in range(MAX_RETRIES + 1):
        try:
            resp = requests.get(GOOGLE_API_BASE, params=params, timeout=12)
            if resp.status_code == 429:
                wait = 2 ** attempt * 8
                logger.warning(f"Rate limited - waiting {wait}s")
                time.sleep(wait)
                continue
            resp.raise_for_status()
            data = resp.json()
            return [item.get("volumeInfo", {}) for item in data.get("items", [])]
        except requests.exceptions.Timeout:
            logger.debug(f"Timeout (attempt {attempt + 1})")
            time.sleep(2)
        except requests.exceptions.RequestException as exc:
            logger.debug(f"API error: {exc}")
            break
    return []


def fetch_google_books(query: str, api_key: str, max_results: int = 20) -> list[dict]:
    time.sleep(REQUEST_DELAY_S)
    return _google_request(
        {"q": query, "maxResults": min(max_results, 40), "langRestrict": "en"},
        api_key,
    )


def extract_google_book(info: dict) -> dict:
    isbns = info.get("industryIdentifiers", [])
    isbn13 = ""
    for id_entry in isbns:
        if id_entry.get("type") == "ISBN_13":
            isbn13 = normalise_isbn(id_entry.get("identifier", ""))
            break
    if not isbn13:
        for id_entry in isbns:
            if id_entry.get("type") == "ISBN_10":
                raw10 = re.sub(r"[^0-9X]", "", id_entry.get("identifier", ""))
                if len(raw10) == 10:
                    body = "978" + raw10[:9]
                    total = sum(int(d) * (1 if i % 2 == 0 else 3) for i, d in enumerate(body))
                    check = (10 - total % 10) % 10
                    isbn13 = normalise_isbn(body + str(check))

    authors_list = info.get("authors", [])
    authors = "|".join(authors_list) if authors_list else ""
    raw_cats = info.get("categories", [])

    thumbnail = ""
    links = info.get("imageLinks", {})
    for key in ("thumbnail", "smallThumbnail", "large", "medium", "small"):
        url = links.get(key, "")
        if url:
            thumbnail = url.replace("http://", "https://")
            break

    description = strip_html(info.get("description", ""))
    rating = info.get("averageRating")
    ratings_count = info.get("ratingsCount")
    page_count = info.get("pageCount")

    if rating is not None:
        try:
            rating = float(rating)
            if not (0.0 <= rating <= 5.0):
                rating = None
        except (ValueError, TypeError):
            rating = None

    return {
        "isbn13": isbn13,
        "title": info.get("title", "").strip(),
        "authors": authors,
        "raw_categories": raw_cats,
        "description": description,
        "thumbnail": thumbnail,
        "average_rating": rating,
        "ratings_count": int(ratings_count) if ratings_count is not None else None,
        "published_date": info.get("publishedDate", ""),
        "page_count": int(page_count) if page_count is not None else None,
        "source": "google_books",
    }


def fetch_open_library(query: str, limit: int = 10) -> list[dict]:
    try:
        time.sleep(REQUEST_DELAY_S)
        resp = requests.get(
            OPEN_LIBRARY_API,
            params={
                "q": query, "limit": limit,
                "fields": "isbn,title,author_name,subject,first_publish_year,number_of_pages_median",
            },
            timeout=12,
        )
        resp.raise_for_status()
        docs = resp.json().get("docs", [])
    except Exception as exc:
        logger.debug(f"Open Library error: {exc}")
        return []

    results = []
    for doc in docs:
        isbn13 = ""
        for raw in doc.get("isbn", []):
            candidate = normalise_isbn(raw)
            if candidate and validate_isbn13(candidate):
                isbn13 = candidate
                break
        authors_list = doc.get("author_name", [])
        authors = "|".join(authors_list) if authors_list else ""
        subjects = doc.get("subject", [])
        thumbnail = OPEN_LIBRARY_COVER.format(isbn=isbn13) if isbn13 else ""
        pub_year = doc.get("first_publish_year")
        page_count = doc.get("number_of_pages_median")
        results.append({
            "isbn13": isbn13,
            "title": doc.get("title", "").strip(),
            "authors": authors,
            "raw_categories": subjects[:5] if subjects else [],
            "description": "",
            "thumbnail": thumbnail,
            "average_rating": None,
            "ratings_count": None,
            "published_date": str(pub_year) if pub_year else "",
            "page_count": int(page_count) if page_count else None,
            "source": "open_library",
        })
    return results


class DuplicateChecker:
    def __init__(self, existing_csv: Path) -> None:
        self._isbns: set[str] = set()
        self._title_author: dict[str, str] = {}
        if existing_csv.exists():
            self._load_existing(existing_csv)

    def _load_existing(self, csv_path: Path) -> None:
        import pandas as pd
        df = pd.read_csv(csv_path, dtype=str)
        for _, row in df.iterrows():
            isbn = normalise_isbn(str(row.get("isbn13", "")))
            if isbn:
                self._isbns.add(isbn)
            key = self._make_key(str(row.get("title", "")), str(row.get("authors", "")))
            if key:
                self._title_author[key] = isbn
        logger.info(f"  Loaded {len(self._isbns)} existing ISBNs from {csv_path.name}")

    @staticmethod
    def _make_key(title: str, authors: str) -> str:
        t = normalise_title(title)
        a = normalise_author(authors)
        return f"{t}||{a}" if t and a else ""

    def check(self, book: dict) -> str:
        isbn = book.get("isbn13", "")
        if isbn and isbn in self._isbns:
            return "DUPLICATE_ISBN"
        key = self._make_key(book.get("title", ""), book.get("authors", ""))
        if key and key in self._title_author:
            if self._title_author[key] != isbn:
                return "EDITION_REVIEW"
        return "OK"

    def register(self, book: dict) -> None:
        isbn = book.get("isbn13", "")
        if isbn:
            self._isbns.add(isbn)
        key = self._make_key(book.get("title", ""), book.get("authors", ""))
        if key:
            self._title_author[key] = isbn


class QualityReport:
    def __init__(self) -> None:
        self.hard_errors: list[str] = []
        self.soft_warnings: list[str] = []

    @property
    def is_rejected(self) -> bool:
        return bool(self.hard_errors)

    def check_book(self, book: dict, canonical: str, isbn_valid: bool) -> None:
        if not isbn_valid:
            self.hard_errors.append("invalid_isbn")
        if not book.get("title", "").strip():
            self.hard_errors.append("missing_title")
        if not book.get("authors", "").strip():
            self.hard_errors.append("missing_author")
        rating = book.get("average_rating")
        if rating is not None:
            try:
                r = float(rating)
                if not (0.0 <= r <= 5.0):
                    self.hard_errors.append("invalid_rating")
            except (ValueError, TypeError):
                self.hard_errors.append("invalid_rating")
        if canonical in ("", "NEEDS_HUMAN_REVIEW"):
            self.hard_errors.append("no_canonical_category")

        desc = book.get("description", "")
        if not desc or len(desc) < MIN_DESCRIPTION_LEN:
            self.soft_warnings.append("missing_or_short_description")
        if not book.get("page_count"):
            self.soft_warnings.append("missing_page_count")
        if not book.get("published_date", "").strip():
            self.soft_warnings.append("missing_published_date")
        if not book.get("ratings_count"):
            self.soft_warnings.append("ratings_count_zero_or_missing")
        # SOFT WARNING: the web client has a cover fallback
        # thumbnail -> openLibraryCoverUrl (isbn based) -> BookCoverFallback widget
        if not book.get("thumbnail", "").strip():
            self.soft_warnings.append("missing_thumbnail")


def fetch_category(
    category_key: str,
    limit: int,
    api_key: str,
    duplicate_checker: DuplicateChecker,
) -> tuple[list[dict], list[dict]]:
    expected_canonical = CATEGORY_CANONICAL[category_key]
    queries = CATEGORY_QUERIES[category_key]

    accepted: list[dict] = []
    rejected: list[dict] = []
    seen_isbns_this_run: set[str] = set()

    # 1. Fetch Google Books
    google_raw = []
    for query in queries:
        logger.info(f"  {_D}Google Books: {query}{_X}")
        results = fetch_google_books(query, api_key, max_results=40)
        google_raw.extend(results)
        logger.info(f"    -> {len(results)} results from API")

    # 2. Fetch Open Library unconditionally as fallback/merging source
    ol_query = category_key.replace(" & ", " ").replace(" ", "+")
    logger.info(f"  {_D}Open Library: {ol_query}{_X}")
    ol_raw = fetch_open_library(ol_query, limit=20)
    logger.info(f"    -> {len(ol_raw)} results from API")

    # 3. Merge metadata based on ISBN13
    combined_books: dict[str, dict] = {}

    for info in google_raw:
        book = info if "raw_categories" in info else extract_google_book(info)
        isbn = book.get("isbn13", "")
        if isbn:
            combined_books[isbn] = book

    for ol_book in ol_raw:
        isbn = ol_book.get("isbn13", "")
        if not isbn:
            continue
        if isbn in combined_books:
            # Merge missing fields from OL to Google
            gb = combined_books[isbn]
            for k, v in ol_book.items():
                if not gb.get(k) and v:
                    gb[k] = v
            # Merge raw categories safely
            gb_cats = gb.get("raw_categories", [])
            ol_cats = ol_book.get("raw_categories", [])
            gb["raw_categories"] = list(dict.fromkeys(gb_cats + ol_cats))
            if gb.get("source") == "google_books":
                gb["source"] = "google+open_library"
        else:
            combined_books[isbn] = ol_book

    all_books = list(combined_books.values())

    # 4. Evaluate candidates up to limit
    for book in all_books:
        if len(accepted) >= limit:
            break
        isbn = book.get("isbn13", "")

        if isbn and isbn in seen_isbns_this_run:
            continue
        if isbn:
            seen_isbns_this_run.add(isbn)

        isbn_valid = bool(isbn) and validate_isbn13(isbn)
        raw_cats = book.get("raw_categories", [])
        canonical, confidence = classify_category(
            raw_cats,
            expected_canonical,
            title=book.get("title", ""),
            description=book.get("description", "")
        )
        dup_status = duplicate_checker.check(book)

        qr = QualityReport()
        qr.check_book(book, canonical, isbn_valid)

        candidate = {
            "isbn13": isbn,
            "title": book.get("title", ""),
            "authors": book.get("authors", ""),
            "raw_categories": "; ".join(raw_cats),
            "canonical_category": canonical,
            "description": book.get("description", ""),
            "thumbnail": book.get("thumbnail", ""),
            "average_rating": book.get("average_rating"),
            "ratings_count": book.get("ratings_count"),
            "published_date": book.get("published_date", ""),
            "page_count": book.get("page_count"),
            "source": book.get("source", "unknown"),
            "taxonomy_confidence": confidence,
            "validation_status": "",
            "_requested_category": category_key,
            "_hard_errors": qr.hard_errors,
            "_soft_warnings": qr.soft_warnings,
            "_dup_status": dup_status,
        }

        if qr.is_rejected:
            candidate["validation_status"] = f"REJECTED:{','.join(qr.hard_errors)}"
            rejected.append(candidate)
            logger.info(
                f"  {_R}X{_X} [{category_key}] {book.get('title', '')[:40]:40s}"
                f"  -> {candidate['validation_status']}"
            )
        elif dup_status == "DUPLICATE_ISBN":
            candidate["validation_status"] = "DUPLICATE_ISBN"
            rejected.append(candidate)
            logger.info(
                f"  {_Y}={_X} [{category_key}] {book.get('title', '')[:40]:40s}"
                f"  -> DUPLICATE_ISBN"
            )
        elif dup_status == "EDITION_REVIEW":
            candidate["validation_status"] = "EDITION_REVIEW"
            if qr.soft_warnings:
                candidate["validation_status"] += f"+WARN:{','.join(qr.soft_warnings)}"
            accepted.append(candidate)
            duplicate_checker.register(candidate)
            logger.info(
                f"  {_C}~{_X} [{category_key}] {book.get('title', '')[:40]:40s}"
                f"  -> EDITION_REVIEW"
            )
        else:
            warnings_str = (
                f"WARN:{','.join(qr.soft_warnings)}" if qr.soft_warnings else "VALID"
            )
            candidate["validation_status"] = warnings_str
            accepted.append(candidate)
            duplicate_checker.register(candidate)
            status_color = _G if not qr.soft_warnings else _Y
            logger.info(
                f"  {status_color}v{_X} [{category_key}] "
                f"{book.get('title', '')[:40]:40s}"
                f"  [{confidence}] -> {warnings_str}"
            )

    return accepted, rejected


def print_quality_report(
    accepted_by_cat: dict[str, list[dict]],
    rejected_by_cat: dict[str, list[dict]],
    requested: dict[str, int],
) -> None:
    all_accepted = [r for rows in accepted_by_cat.values() for r in rows]
    all_rejected = [r for rows in rejected_by_cat.values() for r in rows]

    logger.info(f"\n{_C}{'=' * 62}{_X}")
    logger.info(f"{_B}  CANDIDATE QUALITY REPORT{_X}")
    logger.info(f"{_C}{'=' * 62}{_X}")
    logger.info(f"\n  {'Category':<25} {'Req':>5} {'Valid':>7} {'Rejected':>9} {'Review':>8} {'Dup':>6}")
    logger.info(f"  {'-'*25} {'-'*5} {'-'*7} {'-'*9} {'-'*8} {'-'*6}")

    for cat_key in CATEGORY_CANONICAL:
        acc = accepted_by_cat.get(cat_key, [])
        rej = rejected_by_cat.get(cat_key, [])
        valid = sum(
            1 for r in acc
            if "REJECTED" not in r["validation_status"]
            and "DUPLICATE" not in r["validation_status"]
        )
        edition = sum(1 for r in acc if "EDITION_REVIEW" in r["validation_status"])
        dup = sum(1 for r in rej if "DUPLICATE_ISBN" in r["validation_status"])
        hard_rej = sum(1 for r in rej if "REJECTED" in r["validation_status"])
        label = CATEGORY_CANONICAL[cat_key]
        logger.info(
            f"  {label:<25} {requested.get(cat_key, 0):>5} {valid:>7} "
            f"{hard_rej:>9} {edition:>8} {dup:>6}"
        )

    logger.info(f"  {'-'*25} {'-'*5} {'-'*7} {'-'*9} {'-'*8} {'-'*6}")

    total_valid = sum(
        1 for r in all_accepted
        if "REJECTED" not in r["validation_status"] and "DUPLICATE" not in r["validation_status"]
    )
    total_rej = sum(1 for r in all_rejected if "REJECTED" in r["validation_status"])
    total_edition = sum(1 for r in all_accepted if "EDITION_REVIEW" in r["validation_status"])
    total_dup = sum(1 for r in all_rejected if "DUPLICATE_ISBN" in r["validation_status"])
    logger.info(
        f"  {'TOTAL':<25} {sum(requested.values()):>5} {total_valid:>7} "
        f"{total_rej:>9} {total_edition:>8} {total_dup:>6}"
    )

    logger.info(f"\n  {_B}Metadata Quality{_X}")
    invalid_isbn = sum(1 for r in all_rejected if "invalid_isbn" in " ".join(r.get("_hard_errors", [])))
    missing_desc = sum(1 for r in all_accepted if "missing_or_short_description" in " ".join(r.get("_soft_warnings", [])))
    missing_thumb = sum(1 for r in all_accepted if "missing_thumbnail" in " ".join(r.get("_soft_warnings", [])))
    missing_rating = sum(1 for r in all_accepted if r.get("average_rating") is None)
    missing_pages = sum(1 for r in all_accepted if not r.get("page_count"))
    missing_date = sum(1 for r in all_accepted if not str(r.get("published_date", "")).strip())

    logger.info(f"  Invalid ISBN          : {invalid_isbn}")
    logger.info(f"  Missing description   : {missing_desc}  {_D}(soft warning){_X}")
    logger.info(f"  Missing thumbnail     : {missing_thumb}  {_D}(soft warning - client cover fallback){_X}")
    logger.info(f"  Missing rating        : {missing_rating}  {_D}(soft warning){_X}")
    logger.info(f"  Missing page count    : {missing_pages}  {_D}(soft warning){_X}")
    logger.info(f"  Missing published date: {missing_date}  {_D}(soft warning){_X}")
    logger.info(f"\n{_C}{'=' * 62}{_X}\n")


def _clean_for_csv(row: dict) -> dict:
    return {k: (v if v is not None else "") for k, v in row.items() if not k.startswith("_")}


def write_csv(rows: list[dict], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=CANDIDATE_COLUMNS, quoting=csv.QUOTE_ALL, extrasaction="ignore")
        writer.writeheader()
        for row in rows:
            writer.writerow(_clean_for_csv(row))
    logger.info(f"  {_G}v{_X} Written {len(rows)} rows -> {path}")


def load_existing_candidate_isbns(candidate_path: Path) -> set[str]:
    if not candidate_path.exists():
        return set()
    existing: set[str] = set()
    with open(candidate_path, encoding="utf-8") as f:
        for row in csv.DictReader(f):
            isbn = normalise_isbn(row.get("isbn13", ""))
            if isbn:
                existing.add(isbn)
    return existing


def verify_books_csv_unchanged(books_csv: Path) -> bool:
    git_root = books_csv.parent
    for _ in range(5):
        if (git_root / ".git").exists():
            break
        git_root = git_root.parent
    result = subprocess.run(
        ["git", "diff", "--name-only", "--", str(books_csv)],
        capture_output=True, text=True, cwd=str(git_root),
    )
    modified = books_csv.name in result.stdout
    if modified:
        logger.error(f"{_R}SAFETY VIOLATION: {books_csv} was modified!{_X}")
    return not modified


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Fetch book candidates from Google Books / Open Library.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python scripts/fetch_candidates.py --category romance --limit 10
  python scripts/fetch_candidates.py --batch
  python scripts/fetch_candidates.py --batch --dry-run
  python scripts/fetch_candidates.py --category horror --limit 5 --output custom.csv
        """,
    )

    mode_group = parser.add_mutually_exclusive_group(required=True)
    mode_group.add_argument("--category", choices=list(CATEGORY_QUERIES.keys()), help="Single category to fetch")
    mode_group.add_argument("--batch", action="store_true", help="Fetch all 5 categories (10 each)")

    parser.add_argument("--limit", type=int, default=10, help="Max accepted candidates per category (default: 10)")

    _default_output = str(_BACKEND_DIR / "data" / "enrichment" / "candidate_books.csv")
    _default_rejected = str(_BACKEND_DIR / "data" / "enrichment" / "rejected_books.csv")

    parser.add_argument("--output", default=_default_output, help="Candidate output path")
    parser.add_argument("--rejected-output", default=_default_rejected, help="Rejected output path")
    parser.add_argument("--books-csv", default=Config.DATA_PATH, help="Existing dataset for duplicate check")
    parser.add_argument(
        "--api-key",
        default="",
        dest="api_key",
        # DEPRECATED: Passing secrets via CLI arguments exposes them in the
        # process list (ps aux, /proc/<pid>/cmdline) and shell history.
        # Set GOOGLE_BOOKS_API_KEY in backend/.env instead.
        # This argument is accepted for backward-compatibility only and will
        # trigger a hard error if a non-empty value is supplied.
        help=argparse.SUPPRESS,
    )
    parser.add_argument("--dry-run", action="store_true", help="Preview queries - no API calls, no files written")
    parser.add_argument("--append", action="store_true", help="Append to existing candidate file instead of overwriting")

    args = parser.parse_args()

    if args.api_key:
        logger.error(
            f"{_R}SECURITY: --api-key is deprecated and rejected.{_X}\n"
            "  Passing secrets via CLI arguments exposes them in the process\n"
            "  list (ps aux) and shell history.\n"
            "  Set GOOGLE_BOOKS_API_KEY in backend/.env instead."
        )
        return 1

    api_key = Config.GOOGLE_BOOKS_API_KEY
    if not api_key and not args.dry_run:
        logger.error(
            f"{_R}No Google Books API key.{_X}"
            " Add GOOGLE_BOOKS_API_KEY to backend/.env"
        )
        return 1

    if args.batch:
        categories = list(CATEGORY_QUERIES.keys())
        limit_per_cat = 10
    else:
        categories = [args.category]
        limit_per_cat = args.limit

    requested = {cat: limit_per_cat for cat in categories}
    output_path = Path(args.output)
    rejected_path = Path(args.rejected_output)
    books_csv = Path(args.books_csv)

    logger.info(f"\n{_C}{'=' * 60}{_X}")
    logger.info(f"{_C}  {_B}Libris - Controlled Enrichment Pipeline{_X}")
    logger.info(f"{_C}{'=' * 60}{_X}")
    logger.info(f"  Categories : {', '.join(CATEGORY_CANONICAL[c] for c in categories)}")
    logger.info(f"  Limit/cat  : {limit_per_cat}")
    logger.info(f"  Output     : {output_path}")
    logger.info(f"  books.csv  : {books_csv}")
    if args.dry_run:
        logger.info(f"  {_Y}DRY RUN - no API calls, no files written{_X}")
    logger.info("")

    if args.dry_run:
        logger.info("Queries that would be made:")
        for cat in categories:
            for q in CATEGORY_QUERIES[cat]:
                logger.info(f"  [{CATEGORY_CANONICAL[cat]}] {q}")
        return 0

    existing_candidate_isbns: set[str] = set()
    if args.append and output_path.exists():
        existing_candidate_isbns = load_existing_candidate_isbns(output_path)
        logger.info(f"  Existing candidates: {len(existing_candidate_isbns)} ISBNs")

    dup_checker = DuplicateChecker(books_csv)
    for isbn in existing_candidate_isbns:
        dup_checker._isbns.add(isbn)

    accepted_by_cat: dict[str, list[dict]] = {}
    rejected_by_cat: dict[str, list[dict]] = {}

    for cat_key in categories:
        logger.info(f"\n{_B}[{CATEGORY_CANONICAL[cat_key]}]{_X}")
        acc, rej = fetch_category(cat_key, limit_per_cat, api_key, dup_checker)
        accepted_by_cat[cat_key] = acc
        rejected_by_cat[cat_key] = rej
        logger.info(f"  -> {_G}{len(acc)}{_X} accepted, {_R}{len(rej)}{_X} rejected")

    all_accepted = [r for rows in accepted_by_cat.values() for r in rows]
    all_rejected = [r for rows in rejected_by_cat.values() for r in rows]

    if args.append and output_path.exists():
        existing_rows: list[dict] = []
        with open(output_path, encoding="utf-8") as f:
            existing_rows = list(csv.DictReader(f))
        write_csv(existing_rows + [_clean_for_csv(r) for r in all_accepted], output_path)  # type: ignore[arg-type]
    else:
        write_csv(all_accepted, output_path)

    if all_rejected:
        if args.append and rejected_path.exists():
            existing_rej: list[dict] = []
            with open(rejected_path, encoding="utf-8") as f:
                existing_rej = list(csv.DictReader(f))
            write_csv(existing_rej + [_clean_for_csv(r) for r in all_rejected], rejected_path)  # type: ignore[arg-type]
        else:
            write_csv(all_rejected, rejected_path)

    print_quality_report(accepted_by_cat, rejected_by_cat, requested)

    logger.info(f"{_B}Dataset Safety Check{_X}")
    if verify_books_csv_unchanged(books_csv):
        logger.info(f"  {_G}v books.csv unchanged{_X}")
    else:
        logger.error(f"  {_R}X books.csv was modified - INVESTIGATE IMMEDIATELY{_X}")
        return 2

    logger.info(f"\n{_G}{_B}PIPELINE COMPLETE - {len(all_accepted)} candidates written.{_X}")
    logger.info(f"  Next: Review {output_path}")
    logger.info("  Then: Human approval before merge into books.csv\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
