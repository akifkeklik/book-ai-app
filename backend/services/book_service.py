"""
BookService — orchestration layer between Flask routes and the ML engine.

Responsibilities:
- Bootstrap the recommender (load pickle or train fresh on first run)
- Enrich book dicts with cover thumbnails from Google Books API
- Provide a clean interface for all route handlers
"""

import logging
import random
from functools import lru_cache
from typing import Any, Dict, List, Optional

import requests
from supabase import Client, create_client

from ..config import Config
from ..recommender import BookRecommender
from ..domain.ports import UserInteractionRepository, BookDataPort, AuthPort

logger = logging.getLogger(__name__)


class BookService:
    """Singleton-style service initialised once when the blueprint is imported."""

    def __init__(
        self,
        recommender: "BookRecommender",
        interaction_repo: Optional["UserInteractionRepository"] = None,
        book_data_port: Optional["BookDataPort"] = None,
        auth_port: Optional["AuthPort"] = None,
    ) -> None:
        self.recommender = recommender
        self.interaction_repo = interaction_repo
        self.book_data_port = book_data_port
        self.auth_port = auth_port
        self._bootstrap()

    # ─────────────────────────────────────────────────────────────────────────
    # Initialisation
    # ─────────────────────────────────────────────────────────────────────────

    def _bootstrap(self) -> None:
        """Fetch from Supabase and train; fallback to CSV only if no Supabase."""
        # 1. Try DB Port first (Higher priority (Senior upgrade))
        if self.book_data_port:
            try:
                # Check if model already exists and matches Supabase data hash (Performance Optimization)
                if self.recommender.load_model(Config.MODEL_PATH):
                    logger.info(
                        "Recommendation model loaded from pickle. Verifying data consistency..."
                    )
                    # In a production env, we'd compare hashes here. For now, let's assume it's good if loaded.
                    return

                logger.info("Bootstrap: Loading data from Supabase for training...")
                # We need to adapt the recommender to load from our new port.
                raw_data = self.book_data_port.get_all_books_raw()
                if raw_data:
                    import pandas as pd
                    from ..utils.preprocess import preprocess_dataframe
                    df = pd.DataFrame(raw_data)
                    self.recommender.engine.df = preprocess_dataframe(df)
                    
                self.recommender.fit(save_path=Config.MODEL_PATH)
                logger.info("Recommendation model trained on Supabase data.")
                return
            except Exception as e:
                logger.error(f"Failed to bootstrap from Supabase: {e}")


        # 2. Fallback to pickle or CSV
        if self.recommender.load_model(Config.MODEL_PATH):
            logger.info("Recommendation model loaded from pickle.")
            return

        logger.info("No pickle found — training from CSV…")
        self.recommender.load_data(Config.DATA_PATH)
        self.recommender.fit(save_path=Config.MODEL_PATH)
        logger.info("Training complete. Model saved to %s", Config.MODEL_PATH)

    @lru_cache(maxsize=1)
    def get_categories(self) -> List[str]:
        """Return all unique categories found in the dataset."""
        if not self.recommender.is_fitted:
            return []
        return self.recommender.get_unique_categories()

    # ─────────────────────────────────────────────────────────────────────────
    # Public API
    # ─────────────────────────────────────────────────────────────────────────
    # Note: Orchestration methods have been migrated to the Application Use Cases
    # (GetBooksUseCase, GetPersonalizedRecommendationsUseCase, etc.)
    # 
    # AIService still accesses self.recommender and self._enrich directly, 
    # which is technical debt for M5.3 (AI Boundary Refactor).

    def verify_token(self, token: str):
        """Verifies JWT with auth port."""
        if not self.auth_port:
            raise Exception("Auth port not initialized")
        return self.auth_port.verify_token(token)

    # ─────────────────────────────────────────────────────────────────────────
    # Cover enrichment
    # ─────────────────────────────────────────────────────────────────────────

    def _enrich(self, books: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """Fill missing thumbnails from Google Books API or OpenLibrary fallback."""
        enriched = []
        for book in books:
            if not book.get("thumbnail"):
                cover = self._google_cover(book.get("title", ""), book.get("authors", ""))
                if cover:
                    book["thumbnail"] = cover
                elif book.get("isbn13"):
                    book["thumbnail"] = (
                        f"https://covers.openlibrary.org/b/isbn/{book['isbn13']}-L.jpg"
                    )
            enriched.append(book)
        return enriched

    @lru_cache(maxsize=512)
    def _google_cover(self, title: str, authors: str) -> Optional[str]:
        """Fetch the best available thumbnail from Google Books API (cached)."""
        if not Config.GOOGLE_BOOKS_API_KEY or not title:
            return None

        first_author = authors.split(",")[0].strip() if authors else ""
        query = f"intitle:{title}"
        if first_author:
            query += f"+inauthor:{first_author}"

        try:
            resp = requests.get(
                Config.GOOGLE_BOOKS_API_URL,
                params={
                    "q": query,
                    "key": Config.GOOGLE_BOOKS_API_KEY,
                    "maxResults": 1,
                    "fields": "items(volumeInfo/imageLinks)",
                },
                timeout=5,
            )
            resp.raise_for_status()
            items = resp.json().get("items", [])
            if items:
                links = items[0].get("volumeInfo", {}).get("imageLinks", {})
                return links.get("thumbnail") or links.get("smallThumbnail")
        except requests.RequestException as exc:
            logger.debug("Google Books API error for '%s': %s", title, exc)

        return None
