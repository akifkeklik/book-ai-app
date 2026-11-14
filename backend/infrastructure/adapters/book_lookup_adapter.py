"""Looks up book metadata for books that are not in the catalog yet.

Google Books is used when an API key is configured; Open Library (no key needed) is the
fallback. Results are normalized to the catalog's field names so the web form can be
pre-filled. Network failures never raise: they return an empty list.
"""

import logging
import re
from typing import Any, Dict, List, Optional

import requests

from ...config import Config

logger = logging.getLogger(__name__)

TIMEOUT_SECONDS = 6
MAX_RESULTS = 6
ALLOWED_COVER_HOSTS = ("books.google.com", "covers.openlibrary.org")


def _clean_isbn(value: Any) -> str:
    return re.sub(r"[^0-9Xx]", "", str(value or "")).upper()


def _https_cover(url: Optional[str]) -> str:
    if not url:
        return ""
    url = str(url).replace("http://", "https://", 1)
    return url if any(host in url for host in ALLOWED_COVER_HOSTS) else ""


def _year(value: Any) -> str:
    match = re.search(r"\d{4}", str(value or ""))
    return match.group(0) if match else ""


class BookLookupAdapter:
    def __init__(self, session: Optional[requests.Session] = None):
        self._session = session or requests.Session()

    def search(self, query: str) -> List[Dict[str, Any]]:
        query = (query or "").strip()
        if len(query) < 2:
            return []
        results: List[Dict[str, Any]] = []
        if Config.GOOGLE_BOOKS_API_KEY:
            results = self._google(query)
        if not results:
            results = self._open_library(query)
        return results[:MAX_RESULTS]

    def _google(self, query: str) -> List[Dict[str, Any]]:
        try:
            resp = self._session.get(
                Config.GOOGLE_BOOKS_API_URL,
                params={"q": query, "maxResults": MAX_RESULTS, "printType": "books", "key": Config.GOOGLE_BOOKS_API_KEY},
                timeout=TIMEOUT_SECONDS,
            )
            if resp.status_code != 200:
                return []
            items = resp.json().get("items") or []
        except Exception as e:
            logger.warning(f"Google Books lookup failed: {e}")
            return []
        out = []
        for item in items:
            info = item.get("volumeInfo") or {}
            isbns = {i.get("type"): _clean_isbn(i.get("identifier")) for i in info.get("industryIdentifiers") or []}
            title = (info.get("title") or "").strip()
            if info.get("subtitle"):
                title = f"{title}: {info['subtitle'].strip()}"
            if not title:
                continue
            out.append({
                "isbn13": isbns.get("ISBN_13", ""),
                "title": title,
                "authors": ", ".join(info.get("authors") or []),
                "categories": ", ".join(info.get("categories") or []),
                "description": (info.get("description") or "")[:5000],
                "thumbnail": _https_cover((info.get("imageLinks") or {}).get("thumbnail")),
                "page_count": int(info.get("pageCount") or 0),
                "published_date": _year(info.get("publishedDate")),
            })
        return out

    def _open_library(self, query: str) -> List[Dict[str, Any]]:
        try:
            resp = self._session.get(
                "https://openlibrary.org/search.json",
                params={
                    "q": query,
                    "limit": MAX_RESULTS,
                    "fields": "title,author_name,isbn,first_publish_year,number_of_pages_median,subject,cover_i",
                },
                timeout=TIMEOUT_SECONDS,
            )
            if resp.status_code != 200:
                return []
            docs = resp.json().get("docs") or []
        except Exception as e:
            logger.warning(f"Open Library lookup failed: {e}")
            return []
        out = []
        for doc in docs:
            title = (doc.get("title") or "").strip()
            if not title:
                continue
            isbn13 = next((_clean_isbn(i) for i in doc.get("isbn") or [] if len(_clean_isbn(i)) == 13), "")
            cover_id = doc.get("cover_i")
            out.append({
                "isbn13": isbn13,
                "title": title,
                "authors": ", ".join((doc.get("author_name") or [])[:3]),
                "categories": ", ".join((doc.get("subject") or [])[:2]),
                "description": "",
                "thumbnail": f"https://covers.openlibrary.org/b/id/{cover_id}-M.jpg" if cover_id else "",
                "page_count": int(doc.get("number_of_pages_median") or 0),
                "published_date": _year(doc.get("first_publish_year")),
            })
        return out
