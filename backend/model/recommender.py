"""
BookRecommender — TF-IDF + Cosine Similarity engine with hybrid scoring.

Design decisions:
- Full cosine-similarity matrix stored in memory: O(n²) space, O(1) lookup.
  Suitable for datasets up to ~50k books on a standard server.
- Hybrid scoring formula: 0.60×content + 0.25×log_popularity + 0.15×avg_rating
- Model artefacts are pickled so Flask only trains once, then loads from disk.
"""

import logging
import math
import os
import pickle
from typing import Any, Dict, List, Optional

import numpy as np
import pandas as pd
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity

from utils.preprocess import preprocess_dataframe

logger = logging.getLogger(__name__)


class BookRecommender:
    """Content-based book recommender with optional hybrid popularity scoring."""

    def __init__(self) -> None:
        self.df: Optional[pd.DataFrame] = None
        self.tfidf_matrix = None
        self.vectorizer: Optional[TfidfVectorizer] = None
        self.cosine_sim: Optional[np.ndarray] = None
        self.title_index: Optional[pd.Series] = None  # title_lower → row_idx
        self.is_fitted: bool = False

    # ─────────────────────────────────────────────────────────────────────────
    # Data loading
    # ─────────────────────────────────────────────────────────────────────────

    def load_data(self, data_path: str) -> None:
        """Load CSV and run the preprocessing pipeline."""
        logger.info("Loading dataset from %s", data_path)
        raw = pd.read_csv(data_path, encoding="utf-8")
        logger.info("Raw dataset: %d rows", len(raw))
        self.df = preprocess_dataframe(raw)
        logger.info("Preprocessed dataset: %d books (after dedup)", len(self.df))

    # ─────────────────────────────────────────────────────────────────────────
    # Training
    # ─────────────────────────────────────────────────────────────────────────

    def fit(self, save_path: Optional[str] = None) -> None:
        """Fit TF-IDF vectorizer and compute full cosine-similarity matrix."""
        if self.df is None:
            raise ValueError("No data loaded. Call load_data() first.")

        logger.info("Fitting TF-IDF vectorizer on %d books…", len(self.df))

        self.vectorizer = TfidfVectorizer(
            max_features=10_000,
            ngram_range=(1, 2),
            stop_words="english",
            min_df=1,
            max_df=0.90,
            sublinear_tf=True,
            analyzer="word",
        )
        self.tfidf_matrix = self.vectorizer.fit_transform(self.df["combined_features"])
        logger.info("TF-IDF matrix: %s", self.tfidf_matrix.shape)

        logger.info("Computing cosine-similarity matrix…")
        self.cosine_sim = cosine_similarity(self.tfidf_matrix)
        logger.info("Cosine-similarity matrix ready.")

        # Fast title → index lookup (lowercase keys)
        self.title_index = pd.Series(
            self.df.index,
            index=self.df["title"].str.lower().str.strip(),
        )

        self.is_fitted = True

        if save_path:
            self._save(save_path)

    # ─────────────────────────────────────────────────────────────────────────
    # Persistence
    # ─────────────────────────────────────────────────────────────────────────

    def _save(self, path: str) -> None:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        payload = {
            "vectorizer": self.vectorizer,
            "tfidf_matrix": self.tfidf_matrix,
            "cosine_sim": self.cosine_sim,
            "title_index": self.title_index,
            "df": self.df,
        }
        with open(path, "wb") as fh:
            pickle.dump(payload, fh, protocol=pickle.HIGHEST_PROTOCOL)
        logger.info("Model saved → %s", path)

    def load_model(self, path: str) -> bool:
        """Load pre-trained model artefacts from disk. Returns True on success."""
        if not os.path.exists(path):
            return False
        try:
            with open(path, "rb") as fh:
                data = pickle.load(fh)
            self.vectorizer = data["vectorizer"]
            self.tfidf_matrix = data["tfidf_matrix"]
            self.cosine_sim = data["cosine_sim"]
            self.title_index = data["title_index"]
            self.df = data["df"]
            self.is_fitted = True
            logger.info("Model loaded from %s (%d books)", path, len(self.df))
            return True
        except Exception as exc:  # noqa: BLE001
            logger.error("Failed to load model: %s", exc)
            return False

    # ─────────────────────────────────────────────────────────────────────────
    # Lookup helpers
    # ─────────────────────────────────────────────────────────────────────────

    def _find_index(self, title: str) -> Optional[int]:
        """Resolve a title string to a row index (exact, then partial match)."""
        key = title.lower().strip()

        # 1. Exact match
        if key in self.title_index.index:
            idx = self.title_index[key]
            return int(idx.iloc[0]) if isinstance(idx, pd.Series) else int(idx)

        # 2. Partial match — prefer shortest stored title that contains the query
        candidates = [
            (t, i)
            for t, i in self.title_index.items()
            if key in t or t in key
        ]
        if candidates:
            candidates.sort(key=lambda x: len(x[0]))
            idx = candidates[0][1]
            return int(idx.iloc[0]) if isinstance(idx, pd.Series) else int(idx)

        return None

    # ─────────────────────────────────────────────────────────────────────────
    # Recommendation
    # ─────────────────────────────────────────────────────────────────────────

    def recommend(
        self,
        book_title: str,
        top_n: int = 10,
        use_hybrid: bool = True,
    ) -> List[Dict[str, Any]]:
        """
        Return top-N recommendations for *book_title*.

        Raises RuntimeError if model is not fitted.
        Returns [] if title is not found.
        """
        if not self.is_fitted:
            raise RuntimeError("Model not fitted. Call fit() or load_model() first.")

        book_idx = self._find_index(book_title)
        if book_idx is None:
            logger.warning("Book not found in index: '%s'", book_title)
            return []

        matched_title = self.df.iloc[book_idx]["title"]
        logger.info("Recommendations for '%s' (row %d)", matched_title, book_idx)

        # Raw similarity scores (exclude the query book itself)
        sim_scores = [
            (i, float(s))
            for i, s in enumerate(self.cosine_sim[book_idx])
            if i != book_idx
        ]
        sim_scores.sort(key=lambda x: x[1], reverse=True)

        if use_hybrid:
            sim_scores = self._hybrid_score(sim_scores, pool=top_n * 4)

        sim_scores = sim_scores[:top_n]

        results: List[Dict[str, Any]] = []
        for row_idx, score in sim_scores:
            book = self._row_to_dict(self.df.iloc[row_idx])
            book["similarity_score"] = round(score, 4)
            results.append(book)

        return results

    def _hybrid_score(
        self, sim_scores: List[tuple], pool: int
    ) -> List[tuple]:
        """
        Re-rank a candidate pool using:
            0.60 × content_similarity
          + 0.25 × log_normalised_ratings_count
          + 0.15 × normalised_average_rating
        """
        candidates = sim_scores[:pool]

        max_ratings = max(self.df["ratings_count"].max(), 1)
        max_avg = max(self.df["average_rating"].max(), 1)

        ranked = []
        for idx, sim in candidates:
            row = self.df.iloc[idx]
            log_pop = math.log1p(float(row["ratings_count"])) / math.log1p(
                float(max_ratings)
            )
            norm_avg = float(row["average_rating"]) / float(max_avg)
            hybrid = 0.60 * sim + 0.25 * log_pop + 0.15 * norm_avg
            ranked.append((idx, hybrid))

        ranked.sort(key=lambda x: x[1], reverse=True)
        return ranked

    # ─────────────────────────────────────────────────────────────────────────
    # Queries
    # ─────────────────────────────────────────────────────────────────────────

    def search_books(self, query: str, limit: int = 20) -> List[Dict[str, Any]]:
        """Full-text search across title, authors, and categories."""
        if self.df is None:
            return []
        q = query.lower().strip()
        mask = (
            self.df["title"].str.lower().str.contains(q, na=False)
            | self.df["authors"].str.lower().str.contains(q, na=False)
            | self.df["categories"].str.lower().str.contains(q, na=False)
        )
        results = self.df[mask].copy()
        results = results.sort_values("ratings_count", ascending=False).head(limit)
        return [self._row_to_dict(row) for _, row in results.iterrows()]

    def get_popular_books(self, limit: int = 20) -> List[Dict[str, Any]]:
        """Return books ranked by a composite popularity score."""
        if self.df is None:
            return []
        pop = self.df.copy()
        pop["_pop"] = (
            pop["ratings_count"].rank(pct=True) * 0.65
            + pop["average_rating"].rank(pct=True) * 0.35
        )
        pop = pop.sort_values("_pop", ascending=False).head(limit)
        return [self._row_to_dict(row) for _, row in pop.iterrows()]

    def get_all_books(self, page: int = 1, per_page: int = 20) -> Dict[str, Any]:
        """Return a paginated slice of the full dataset."""
        if self.df is None:
            return {"books": [], "total": 0, "page": page, "per_page": per_page, "total_pages": 0}
        total = len(self.df)
        start = (page - 1) * per_page
        end = start + per_page
        slice_df = self.df.iloc[start:end]
        return {
            "books": [self._row_to_dict(row) for _, row in slice_df.iterrows()],
            "total": total,
            "page": page,
            "per_page": per_page,
            "total_pages": math.ceil(total / per_page),
        }

    def get_book_by_isbn(self, isbn: str) -> Optional[Dict[str, Any]]:
        if self.df is None:
            return None
        mask = self.df["isbn13"].astype(str) == str(isbn)
        row = self.df[mask]
        if row.empty:
            return None
        return self._row_to_dict(row.iloc[0])

    # ─────────────────────────────────────────────────────────────────────────
    # Serialisation helper
    # ─────────────────────────────────────────────────────────────────────────

    @staticmethod
    def _row_to_dict(row: pd.Series) -> Dict[str, Any]:
        return {
            "isbn13": str(row.get("isbn13", "")),
            "title": str(row.get("title", "")),
            "authors": str(row.get("authors", "")),
            "categories": str(row.get("categories", "")),
            "description": str(row.get("description", "")),
            "thumbnail": str(row.get("thumbnail", "")),
            "average_rating": float(row.get("average_rating", 0)),
            "ratings_count": int(row.get("ratings_count", 0)),
            "published_date": str(row.get("published_date", "")),
            "page_count": int(row.get("page_count", 0)),
        }
