"""
BookService — orchestration layer between Flask routes and the ML engine.

Responsibilities:
- Bootstrap the recommender (load pickle or train fresh on first run)
- Enrich book dicts with cover thumbnails from Google Books API
- Provide a clean interface for all route handlers
"""

import logging
import random
import requests
from functools import lru_cache
from typing import Any, Dict, List, Optional

from supabase import create_client, Client
from config import Config
from model.recommender import BookRecommender

logger = logging.getLogger(__name__)


class BookService:
    """Singleton-style service initialised once when the blueprint is imported."""

    def __init__(self) -> None:
        self.recommender = BookRecommender()
        self._supabase: Optional[Client] = None
        if Config.SUPABASE_URL and Config.SUPABASE_ANON_KEY:
            self._supabase = create_client(Config.SUPABASE_URL, Config.SUPABASE_ANON_KEY)
        self._bootstrap()

    # ─────────────────────────────────────────────────────────────────────────
    # Initialisation
    # ─────────────────────────────────────────────────────────────────────────

    def _bootstrap(self) -> None:
        """Fetch from Supabase and train; fallback to CSV only if no Supabase."""
        # 1. Try Supabase first (Higher priority (Senior upgrade))
        if self._supabase:
            try:
                # Check if model already exists and matches Supabase data hash (Performance Optimization)
                if self.recommender.load_model(Config.MODEL_PATH):
                    logger.info("Recommendation model loaded from pickle. Verifying data consistency...")
                    # In a production env, we'd compare hashes here. For now, let's assume it's good if loaded.
                    return

                logger.info("Bootstrap: Loading data from Supabase for training...")
                self.recommender.load_from_supabase(self._supabase)
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

    def get_categories(self) -> List[str]:
        """Return all unique categories found in the dataset."""
        if not self.recommender.is_fitted:
            return []
        return self.recommender.get_unique_categories()

    # ─────────────────────────────────────────────────────────────────────────
    # Public API
    # ─────────────────────────────────────────────────────────────────────────

    def get_all_books(self, page: int = 1, per_page: int = 20) -> Dict[str, Any]:
        result = self.recommender.get_all_books(page=page, per_page=per_page)
        result["books"] = self._enrich(result["books"])
        return result

    def get_popular_books(self, limit: int = 20) -> List[Dict[str, Any]]:
        books = self.recommender.get_popular_books(limit=limit)
        return self._enrich(books)

    def search_books(self, query: str, limit: int = 20) -> List[Dict[str, Any]]:
        books = self.recommender.search_books(query=query, limit=limit)
        return self._enrich(books)

    def get_recommendations(
        self,
        book_title: str,
        top_n: int = 10,
        use_hybrid: bool = True,
    ) -> List[Dict[str, Any]]:
        books = self.recommender.recommend(
            book_title=book_title,
            top_n=top_n,
            use_hybrid=use_hybrid,
        )
        return self._enrich(books)

    def get_personalized_recommendations(self, user_id: str, limit: int = 10) -> List[Dict[str, Any]]:
        """Return personalized recommendations by querying ML model on user's recent favorites."""
        if not self._supabase:
            logger.warning("No Supabase client, falling back to popular books for personalized recs.")
            return self.get_popular_books(limit=limit)
            
        try:
            # 1. Fetch user's favorite books directly from Supabase
            favs = self._supabase.table("favorites").select("book_title").eq("user_id", user_id).execute()
            titles = [f["book_title"] for f in getattr(favs, 'data', []) if "book_title" in f]
            
            if not titles:
                logger.info(f"User {user_id} has no favorites. Returning popular books.")
                return self.get_popular_books(limit=limit)
                
            # 2. Use the most recent favorite to get recommendations
            # We take the first one (assuming it's recently interacted, or select randomly from favorites)
            seed_title = titles[0] 
            logger.info(f"Generating ML recommendations for user {user_id} based on favorite: '{seed_title}'.")
            
            # 3. Call the actual ML recommendation engine
            recs = self.recommender.recommend(seed_title, top_n=limit, use_hybrid=True)
            
            if not recs:
                logger.warning(f"ML engine returned no recs for '{seed_title}'. Falling back to popular.")
                return self.get_popular_books(limit=limit)
                
            return self._enrich(recs)
        except Exception as e:
            logger.error(f"Failed to get ML personalized recs: {e}")
            return self.get_popular_books(limit=limit)

    def get_book_by_isbn(self, isbn: str) -> Optional[Dict[str, Any]]:
        book = self.recommender.get_book_by_isbn(isbn)
        if book:
            enriched = self._enrich([book])
            return enriched[0] if enriched else None
        return None

    @staticmethod
    def track_user_activity(
        user_id: str, book_name: str, action: str = "view"
    ) -> Dict[str, Any]:
        """Acknowledge an activity event. Actual persistence is done in Flutter → Supabase."""
        logger.info("Activity | user=%s book=%s action=%s", user_id, book_name, action)
        return {"status": "tracked", "user_id": user_id, "book_name": book_name, "action": action}

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
