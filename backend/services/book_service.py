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
                    if self.recommender.is_fitted:
                        logger.info("Recommendation model trained on %d database books.", len(df))
                        return
                # An empty or failed catalog read must not leave the app with no catalog: fall
                # through to the bundled CSV instead of fitting on nothing.
                logger.error("Database catalog was empty or unreadable; training from the bundled CSV.")
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
        """
        Adds books stored in the database but missing from the trained model (reader contributions).

        "Known" covers every edition ISBN the model carries (isbn13 and the merged edition_isbns):
        preprocessing collapses editions of one work into a single row, so comparing against
        isbn13 alone re-added every merged edition as a duplicate row on each startup. A missing
        ISBN that is a new edition of a work already in the model is merged into that row instead
        of becoming a second row for the same book.
        """
        if not self.book_data_port or not hasattr(self.book_data_port, "get_all_isbns"):
            return
        try:
            from ..utils.preprocess import normalize_isbn, work_id

            df = self.recommender.df
            known = set(self.recommender.engine._isbn_lookup()) if not df.empty else set()
            missing, seen = [], set()
            for raw in self.book_data_port.get_all_isbns() or []:
                isbn = normalize_isbn(raw)
                if isbn and isbn not in known and isbn not in seen:
                    seen.add(isbn)
                    missing.append(str(raw).strip())
            if not missing:
                return
            rows = self.book_data_port.get_books_by_isbns(missing[:500]) or []
            work_rows = {}
            if not df.empty:
                work_rows = {work_id(t, a): idx for idx, t, a in zip(df.index, df["title"], df["authors"])}
            added = merged = 0
            for row in rows:
                if not row.get("title"):
                    continue
                isbn = normalize_isbn(row.get("isbn13"))
                existing = work_rows.get(work_id(row.get("title"), row.get("authors")))
                if existing is not None:
                    self._merge_edition(existing, isbn)
                    merged += 1
                    continue
                self.recommender.add_book(row)
                new_df = self.recommender.df
                work_rows[work_id(row.get("title"), row.get("authors"))] = new_df.index[-1]
                added += 1
            if added or merged:
                logger.info(
                    "Startup catalog sync: added %d contributed books, merged %d new edition ISBNs "
                    "into existing works.", added, merged,
                )
        except Exception as e:
            logger.warning(f"Could not sync contributed books: {e}")

    def _merge_edition(self, row_idx, isbn: str) -> None:
        """Records `isbn` as another edition of an existing catalog row (no new row)."""
        if not isbn:
            return
        df = self.recommender.engine.df
        if "edition_isbns" not in df.columns:
            df["edition_isbns"] = df["isbn13"].astype(str)
        current = [p for p in str(df.at[row_idx, "edition_isbns"] or "").split("|") if p]
        if isbn not in current:
            df.at[row_idx, "edition_isbns"] = "|".join(current + [isbn])

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
