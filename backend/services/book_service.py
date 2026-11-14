"""
BookService — orchestration layer between Flask routes and the ML engine.
Responsibilities:
- Bootstrap the recommender (load pickle or train fresh on first run)
- Enrich book dicts with cover thumbnails from Google Books API
- Provide a clean interface for all route handlers
"""
import logging
from functools import lru_cache
from typing import Any, Dict, List, Optional

from ..config import Config
from ..domain.ports import BookDataPort, UserInteractionRepository
from ..infrastructure.ml.recommender import BookRecommender

logger = logging.getLogger(__name__)
class BookService:
    """Singleton-style service initialised once when the blueprint is imported."""
    def __init__(
        self,
        recommender: "BookRecommender",
        interaction_repo: Optional["UserInteractionRepository"] = None,
        book_data_port: Optional["BookDataPort"] = None,
    ) -> None:
        self.recommender = recommender
        self.interaction_repo = interaction_repo
        self.book_data_port = book_data_port
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
                    self._sync_contributed_books()
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
    def _sync_contributed_books(self) -> None:
        """Adds books stored in the database but missing from the trained model (reader contributions)."""
        if not self.book_data_port or not hasattr(self.book_data_port, "get_all_isbns"):
            return
        try:
            known = set(self.recommender.df["isbn13"].astype(str)) if not self.recommender.df.empty else set()
            missing = [i for i in self.book_data_port.get_all_isbns() if i and i not in known]
            if not missing:
                return
            rows = self.book_data_port.get_books_by_isbns(missing[:500]) or []
            for row in rows:
                if row.get("title"):
                    self.recommender.add_book(row)
            logger.info("Added %d contributed books missing from the trained model.", len(rows))
        except Exception as e:
            logger.warning(f"Could not sync contributed books: {e}")

    @lru_cache(maxsize=1)
    def get_categories(self) -> List[Dict[str, Any]]:
        """Return all unique categories found in the dataset with counts."""
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
