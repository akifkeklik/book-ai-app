"""Readers can add a book that is missing from the shared catalog.

The book becomes visible to everyone immediately (in-memory catalog) and is persisted
through the BookDataPort when a database is configured. Notes and feedback on it stay
private to each reader, like for every other book.
"""

import logging
import re
import uuid
from typing import Any, Dict, List, Optional, Tuple

logger = logging.getLogger(__name__)

ALLOWED_COVER_PREFIXES = ("https://books.google.com/", "https://covers.openlibrary.org/")
LIMITS = {"title": 300, "authors": 300, "categories": 120, "description": 5000, "published_date": 20}


class CatalogContributionError(ValueError):
    """Invalid input for a catalog contribution (maps to HTTP 400)."""


def _text(data: Dict[str, Any], key: str, required: bool = False) -> str:
    value = re.sub(r"\s+", " ", str(data.get(key) or "")).strip()
    if required and not value:
        raise CatalogContributionError(f"{key} is required")
    if len(value) > LIMITS[key]:
        raise CatalogContributionError(f"{key} exceeds {LIMITS[key]} characters")
    return value


def _isbn13(value: Any) -> str:
    digits = re.sub(r"[^0-9]", "", str(value or ""))
    if not digits:
        return ""
    if len(digits) != 13 or not digits.startswith(("978", "979")):
        raise CatalogContributionError("isbn13 must be a 13-digit ISBN starting with 978 or 979")
    return digits


def _page_count(value: Any) -> int:
    if value in (None, ""):
        return 0
    try:
        pages = int(value)
    except (TypeError, ValueError):
        raise CatalogContributionError("page_count must be a whole number")
    if not 0 <= pages <= 20000:
        raise CatalogContributionError("page_count must be between 0 and 20000")
    return pages


def _cover(value: Any) -> str:
    url = str(value or "").strip()
    return url if url.startswith(ALLOWED_COVER_PREFIXES) and len(url) <= 500 else ""


class AddCatalogBookUseCase:
    def __init__(self, recommender, book_data_port=None):
        self._recommender = recommender
        self._book_data_port = book_data_port

    def _find_existing(self, isbn13: str, title: str, authors: str) -> Optional[Dict[str, Any]]:
        if isbn13:
            found = self._recommender.get_book_by_isbn(isbn13)
            if found:
                return found
        return self._recommender.find_book_by_title_author(title, authors)

    def execute(
        self, user_id: str, data: Dict[str, Any], user_token: Optional[str] = None
    ) -> Tuple[Dict[str, Any], bool, bool]:
        """Returns (book, created, persisted)."""
        if not (user_id or "").strip():
            raise CatalogContributionError("user_id is required")
        if not isinstance(data, dict):
            raise CatalogContributionError("JSON object required")

        title = _text(data, "title", required=True)
        authors = _text(data, "authors", required=True)
        isbn13 = _isbn13(data.get("isbn13"))

        existing = self._find_existing(isbn13, title, authors)
        if existing:
            return existing, False, False

        book = {
            # Books without an ISBN get a stable, URL-safe catalog id.
            "isbn13": isbn13 or f"lb{uuid.uuid4().hex[:16]}",
            "title": title,
            "authors": authors,
            "categories": _text(data, "categories") or "General",
            "description": _text(data, "description"),
            "thumbnail": _cover(data.get("thumbnail")),
            "page_count": _page_count(data.get("page_count")),
            "published_date": _text(data, "published_date"),
            "average_rating": 0.0,
            "ratings_count": 0,
        }

        persisted = False
        if self._book_data_port and hasattr(self._book_data_port, "add_book"):
            try:
                persisted = bool(self._book_data_port.add_book(book, user_token=user_token))
            except Exception as e:
                logger.warning(f"Could not persist contributed book {book['isbn13']}: {e}")

        added = self._recommender.add_book(book)
        logger.info(f"Catalog contribution by {user_id}: {book['isbn13']} persisted={persisted}")
        return added, True, persisted


class LookupBooksUseCase:
    def __init__(self, lookup_adapter, recommender):
        self._lookup = lookup_adapter
        self._recommender = recommender

    def execute(self, query: str) -> List[Dict[str, Any]]:
        query = (query or "").strip()
        if len(query) < 2:
            return []
        if len(query) > 200:
            raise CatalogContributionError("query is too long")
        results = self._lookup.search(query)
        for r in results:
            existing = self._recommender.get_book_by_isbn(r["isbn13"]) if r.get("isbn13") else None
            existing = existing or self._recommender.find_book_by_title_author(r.get("title", ""), r.get("authors", ""))
            r["in_catalog_isbn"] = existing.get("isbn13") if existing else None
        return results
