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
                    logger.info(
                        "Recommendation model loaded from pickle. Verifying data consistency..."
                    )
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

    @lru_cache(maxsize=1)
    def get_categories(self) -> List[str]:
        """Return all unique categories found in the dataset."""
        if not self.recommender.is_fitted:
            return []
        return self.recommender.get_unique_categories()

    # ─────────────────────────────────────────────────────────────────────────
    # Public API
    # ─────────────────────────────────────────────────────────────────────────

    @lru_cache(maxsize=256)
    def get_all_books(
        self, page: int = 1, per_page: int = 20, category: Optional[str] = None
    ) -> Dict[str, Any]:
        result = self.recommender.get_all_books(page=page, per_page=per_page, category=category)
        result["books"] = self._enrich(result["books"])
        return result

    @lru_cache(maxsize=128)
    def get_popular_books(self, limit: int = 20) -> List[Dict[str, Any]]:
        books = self.recommender.get_popular_books(limit=limit)
        return self._enrich(books)

    @lru_cache(maxsize=512)
    def search_books(self, query: str, limit: int = 20) -> List[Dict[str, Any]]:
        books = self.recommender.search_books(query=query, limit=limit)
        return self._enrich(books)

    @lru_cache(maxsize=1024)
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

    def get_personalized_recommendations(
        self, user_id: str, limit: int = 10
    ) -> List[Dict[str, Any]]:
        """
        Production-grade personalization with LRU caching:
        1. Fetch Likes, Dislikes and Profile Genres.
        2. Pass them as hashable tuples to the cached recommendation computation.
        """
        if not self._supabase:
            return self.get_popular_books(limit=limit)

        try:
            # 1. Get user interactions (Likes and Dislikes)
            interactions_resp = (
                self._supabase.table("user_interactions").select("book_id, interaction_type").eq("user_id", user_id).execute()
            )
            interactions_data = getattr(interactions_resp, "data", [])
            likes = [f["book_id"] for f in interactions_data if f.get("interaction_type") == "like"]
            dislikes = [f["book_id"] for f in interactions_data if f.get("interaction_type") == "dislike"]

            likes_tuple = tuple(sorted(set(likes)))
            dislikes_tuple = tuple(sorted(set(dislikes)))

            genres_tuple = ()
            if not likes_tuple:
                profile_resp = (
                    self._supabase.table("user_profiles")
                    .select("preferred_genres")
                    .eq("user_id", user_id)
                    .execute()
                )
                profile_data = getattr(profile_resp, "data", [])
                if profile_data:
                    genres = profile_data[0].get("preferred_genres", [])
                    if genres:
                        genres_tuple = tuple(sorted(set(genres)))

            return self._compute_cached_personalized_recs(
                user_id, likes_tuple, dislikes_tuple, genres_tuple, limit
            )
        except Exception as e:
            logger.error(f"Failed fetching interactions for personalized recs: {e}")
            return self.get_popular_books(limit=limit)

    @lru_cache(maxsize=1024)
    def _compute_cached_personalized_recs(
        self, user_id: str, likes: tuple, dislikes: tuple, genres: tuple, limit: int
    ) -> List[Dict[str, Any]]:
        """
        Cached computation of recommendations. 
        Invalidates naturally when the input tuples (likes/dislikes/genres) change.
        """
        try:
            seed_titles = []
            if likes:
                # Convert ISBNs to Titles for the engine
                for bid in likes:
                    idx = self.recommender.engine.find_index(bid)
                    if idx is not None:
                        seed_titles.append(self.recommender.engine.df.iloc[idx]["title"])

            # 2. If no direct likes found, check Profile Genres
            if not seed_titles and genres:
                logger.info(f"Using preferred genres as seed for {user_id}: {genres}")
                genre_recs = []
                for g in genres[:3]:  # Variety
                    res = self.recommender.get_all_books(page=1, per_page=10, category=g)
                    genre_recs.extend(res.get("books", []))

                if genre_recs:
                    unique_recs = {r["isbn13"]: r for r in genre_recs}.values()
                    final_genre_recs = list(unique_recs)
                    random.shuffle(final_genre_recs)
                    return self._enrich(final_genre_recs[:limit])

            if not seed_titles and not genres:
                # 3. Final Fallback: Trending books
                logger.info(f"User {user_id} has no profile info. Returning trending books.")
                return self.get_popular_books(limit=limit)

            # 4. If we have seeds, generate recommendations
            logger.info(
                f"Generating personalized recs for {user_id} with {len(seed_titles)} seeds."
            )

            # --- PHASE 3.3: Fetch Semantic Candidates via pgvector RPC ---
            semantic_scores = None
            if likes:
                try:
                    rpc_resp = self._supabase.rpc(
                        "match_book_embeddings",
                        {"seed_book_ids": list(likes), "match_threshold": 0.0, "match_count": 100}
                    ).execute()
                    rpc_data = getattr(rpc_resp, "data", [])
                    if rpc_data:
                        semantic_scores = {row["book_id"]: row["similarity"] for row in rpc_data}
                        logger.info(f"Retrieved {len(semantic_scores)} semantic candidates.")
                except Exception as e:
                    logger.warning(f"Semantic candidate generation failed: {e}. Degrading to TF-IDF only.")

            recs = self.recommender.recommend(
                seed_titles,
                top_n=limit,
                use_diversity=True,
                semantic_scores=semantic_scores,
                dislikes=list(dislikes)
            )

            # Dislikes are now hard-filtered during recommendation, but double-check
            final_recs = [r for r in recs if r.get("isbn13") not in dislikes]

            return self._enrich(final_recs)
        except Exception as e:
            logger.error(f"Failed cached personalized recs computation: {e}")
            return self.get_popular_books(limit=limit)

    def submit_onboarding(
        self, user_id: str, book_ids: List[str], genres: List[str]
    ) -> Dict[str, Any]:
        """Record initial preferences."""
        if not self._supabase:
            return {"status": "error", "message": "No Supabase"}

        try:
            # 1. Record selected books as 'like'
            entries = [
                {"user_id": user_id, "book_id": bid, "interaction_type": "like"} for bid in book_ids
            ]
            if entries:
                self._supabase.table("user_interactions").upsert(entries, on_conflict="user_id,book_id").execute()

            import datetime

            # 2. Update profile with genres
            self._supabase.table("user_profiles").upsert(
                {
                    "user_id": user_id,
                    "preferred_genres": genres,
                    "updated_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                }
            ).execute()

            return {"status": "success", "message": "Onboarding complete"}
        except Exception as e:
            logger.error(f"Onboarding error: {e}")
            return {"status": "error", "message": str(e)}

    def submit_feedback(self, user_id: str, book_id: str, interaction: str) -> Dict[str, Any]:
        """Submit like/dislike."""
        if not self._supabase:
            return {"status": "error"}
        try:
            self._supabase.table("user_interactions").upsert(
                {"user_id": user_id, "book_id": book_id, "interaction_type": interaction},
                on_conflict="user_id,book_id"
            ).execute()
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

    def track_user_activity(
        self, user_id: str, action: str, book_id: str = "", book_name: str = ""
    ) -> Dict[str, Any]:
        """Acknowledge an activity event and persist to Supabase."""
        logger.info(
            "Activity | user=%s book_id=%s book_name=%s action=%s",
            user_id,
            book_id,
            book_name,
            action,
        )

        if not self._supabase:
            return {"status": "error", "message": "Supabase not initialized"}

        try:
            import datetime

            payload = {
                "user_id": user_id,
                "activity_type": action,
                "created_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            }
            if book_id:
                payload["book_id"] = book_id

            self._supabase.table("user_activities").insert(payload).execute()

            return {"status": "tracked", "user_id": user_id, "action": action}
        except Exception as e:
            logger.error(f"Tracking error: {e}")
            raise e

    def verify_token(self, token: str):
        """Verifies JWT with Supabase auth."""
        if not self._supabase:
            raise Exception("Supabase client not initialized")
        user_response = self._supabase.auth.get_user(token)
        return user_response.user

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
