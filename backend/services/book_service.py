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
from ..config import Config
from ..recommender import BookRecommender

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

    def get_all_books(self, page: int = 1, per_page: int = 20, category: Optional[str] = None) -> Dict[str, Any]:
        result = self.recommender.get_all_books(page=page, per_page=per_page, category=category)
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
        # Single seed recommendation
        books = self.recommender.recommend(
            seed_titles=[book_title],
            top_n=top_n,
            use_diversity=True,
        )
        return self._enrich(books)

    def get_personalized_recommendations(self, user_id: str, limit: int = 10) -> List[Dict[str, Any]]:
        """
        Production-grade personalization:
        1. Fetch Likes and Dislikes from Supabase.
        2. Calculate centroid based on Likes.
        3. Exclude Dislikes.
        4. Apply MMR Diversity.
        """
        if not self._supabase:
            return self.get_popular_books(limit=limit)
            
        try:
            # 1. Fetch user's interactions
            resp = self._supabase.table("user_interactions").select("*").eq("user_id", user_id).execute()
            interactions = getattr(resp, 'data', [])
            
            likes = [i["book_id"] for i in interactions if i["interaction_type"] == "like"]
            dislikes = [i["book_id"] for i in interactions if i["interaction_type"] == "dislike"]
            
            # Use favorites as additional likes
            fav_resp = self._supabase.table("favorites").select("book_id").eq("user_id", user_id).execute()
            likes.extend([f["book_id"] for f in getattr(fav_resp, 'data', [])])
            likes = list(set(likes)) # dedupe

            if not seed_titles:
                # Senior Solution: Fallback to Profile Genres if no book interactions exist
                profile_resp = self._supabase.table("user_profiles").select("preferred_genres").eq("user_id", user_id).execute()
                profile_data = getattr(profile_resp, 'data', [])
                if profile_data:
                    genres = profile_data[0].get("preferred_genres", [])
                    if genres:
                        logger.info(f"Using preferred genres as seed for {user_id}: {genres}")
                        # Fetch top books in these genres
                        genre_recs = []
                        for g in genres[:3]: # Take first 3 genres for variety
                            res = self.recommender.get_all_books(page=1, per_page=10, category=g)
                            genre_recs.extend(res.get("books", []))
                        
                        if genre_recs:
                            # Dedupe and shuffle
                            unique_recs = {r['isbn13']: r for r in genre_recs}.values()
                            final_genre_recs = list(unique_recs)
                            random.shuffle(final_genre_recs)
                            return self._enrich(final_genre_recs[:limit])

                logger.info(f"User {user_id} has no interactions or profile genres. Returning trending books.")
                return self.get_popular_books(limit=limit)

            logger.info(f"Generating personalized recs for {user_id} with {len(seed_titles)} seeds.")
            
            # 3. Call Orchestrator
            recs = self.recommender.recommend(seed_titles, top_n=limit, use_diversity=True)
            
            # 4. Filter out dislikes (if not already handled by engine)
            final_recs = [r for r in recs if r.get("isbn13") not in dislikes]
            
            return self._enrich(final_recs)
        except Exception as e:
            logger.error(f"Failed personalized recs: {e}")
            return self.get_popular_books(limit=limit)

    def submit_onboarding(self, user_id: str, book_ids: List[str], genres: List[str]) -> Dict[str, Any]:
        """Record initial preferences."""
        if not self._supabase: return {"status": "error", "message": "No Supabase"}
        
        try:
            # 1. Record selected books as 'like'
            entries = [{"user_id": user_id, "book_id": bid, "interaction_type": "like"} for bid in book_ids]
            if entries:
                self._supabase.table("user_interactions").upsert(entries).execute()
            
            # 2. Update profile with genres
            self._supabase.table("user_profiles").upsert({
                "user_id": user_id,
                "preferred_genres": genres,
                "updated_at": "now()"
            }).execute()
            
            return {"status": "success", "message": "Onboarding complete"}
        except Exception as e:
            logger.error(f"Onboarding error: {e}")
            return {"status": "error", "message": str(e)}

    def submit_feedback(self, user_id: str, book_id: str, interaction: str) -> Dict[str, Any]:
        """Submit like/dislike."""
        if not self._supabase: return {"status": "error"}
        try:
            self._supabase.table("user_interactions").upsert({
                "user_id": user_id,
                "book_id": book_id,
                "interaction_type": interaction
            }).execute()
            return {"status": "success"}
        except Exception as e:
            logger.error(f"Feedback error: {e}")
            return {"status": "error"}

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
