"""
Libris Recommendation Engine - Unified Module

This single file consolidates the logic from the legacy `model` package,
including the core engine, diversity, and explanation components. It is
designed to be a self-contained, robust recommendation system.
"""

import logging
import math
import os
import pickle
import random
import re
from typing import Any, Dict, List, Optional, Tuple

import numpy as np
import pandas as pd
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity
from supabase import Client

from .utils.preprocess import preprocess_dataframe

# ── Constants ─────────────────────────────────────────────────────────────────
MODEL_VERSION = "2.1.0"
# TF-IDF will ignore words that appear in more than this % of documents
TFIDF_MAX_DF = 0.8
# TF-IDF will ignore words that appear in fewer than this many documents
TFIDF_MIN_DF = 5
# Maximum number of features to generate for TF-IDF
TFIDF_MAX_FEATURES = 10000

# For diversity calculations (MMR)
DIVERSITY_LAMBDA = 0.6

# For hybrid scoring
WEIGHT_SIMILARITY = 0.7
WEIGHT_POPULARITY = 0.3

logger = logging.getLogger(__name__)


def _normalize_category_text(value: Any) -> str:
    """Normalize category field into a searchable plain lowercase text."""
    text = str(value or "").lower()
    text = re.sub(r"[\[\]\(\)\{\}'\"]", " ", text)
    text = re.sub(r"[|,;/]", " ", text)
    text = re.sub(r"\s+", " ", text).strip()
    return text


# ── Configuration ─────────────────────────────────────────────────────────────
class EngineConfig:
    """Typed configuration for the recommendation engine."""
    model_version: str = MODEL_VERSION
    tfidf_max_df: float = TFIDF_MAX_DF
    tfidf_min_df: int = TFIDF_MIN_DF
    tfidf_max_features: int = TFIDF_MAX_FEATURES
    diversity_lambda: float = DIVERSITY_LAMBDA
    weight_similarity: float = WEIGHT_SIMILARITY
    weight_popularity: float = WEIGHT_POPULARITY


# ── Core Engine ───────────────────────────────────────────────────────────────
class RecommenderEngine:
    """
    Handles data loading, TF-IDF vectorization, and core similarity calculations.
    """

    def __init__(self, config: EngineConfig = EngineConfig()):
        self.config = config
        self.df: pd.DataFrame = pd.DataFrame()
        self.tfidf_vectorizer: Optional[TfidfVectorizer] = None
        self.tfidf_matrix = None
        self.cosine_sim = None
        self.is_fitted = False

    @property
    def vectorizer(self):
        """Backward-compatible alias used by existing tests/scripts."""
        return self.tfidf_vectorizer

    def save(self, path: str):
        """Persist engine state (legacy helper for older test/script flows)."""
        with open(path, "wb") as f:
            pickle.dump(self, f)

    def fit(self):
        """Fit the TF-IDF vectorizer and compute the cosine similarity matrix."""
        if self.df.empty:
            logger.error("DataFrame is empty. Cannot fit the model.")
            self.is_fitted = False
            return

        logger.info("Fitting TF-IDF vectorizer...")
        min_df = self.config.tfidf_min_df
        self.tfidf_vectorizer = TfidfVectorizer(
            stop_words="english",
            max_df=self.config.tfidf_max_df,
            min_df=min_df,
            max_features=self.config.tfidf_max_features,
            ngram_range=(1, 2),
        )

        try:
            self.tfidf_matrix = self.tfidf_vectorizer.fit_transform(self.df["combined_features"])
        except ValueError:
            # Small/dev datasets can be too sparse for min_df=5; fallback keeps engine usable.
            logger.warning("TF-IDF fit failed with min_df=%s; retrying with min_df=1", min_df)
            self.tfidf_vectorizer = TfidfVectorizer(
                stop_words="english",
                max_df=self.config.tfidf_max_df,
                min_df=1,
                max_features=self.config.tfidf_max_features,
                ngram_range=(1, 2),
            )
            self.tfidf_matrix = self.tfidf_vectorizer.fit_transform(self.df["combined_features"])

        # If any row has no features, similarity on that row collapses; retry with min_df=1.
        if (self.tfidf_matrix.getnnz(axis=1) == 0).any() and min_df != 1:
            logger.warning("Detected empty TF-IDF rows with min_df=%s; refitting with min_df=1", min_df)
            self.tfidf_vectorizer = TfidfVectorizer(
                stop_words="english",
                max_df=self.config.tfidf_max_df,
                min_df=1,
                max_features=self.config.tfidf_max_features,
                ngram_range=(1, 2),
            )
            self.tfidf_matrix = self.tfidf_vectorizer.fit_transform(self.df["combined_features"])

        logger.info(f"TF-IDF matrix created with shape: {self.tfidf_matrix.shape}")

        logger.info("Calculating cosine similarity matrix...")
        self.cosine_sim = cosine_similarity(self.tfidf_matrix)
        logger.info(f"Cosine similarity matrix created with shape: {self.cosine_sim.shape}")
        self.is_fitted = True

    def find_index(self, book_identifier: str) -> Optional[int]:
        """Find the DataFrame index for a book by its title or ISBN."""
        if not isinstance(book_identifier, str):
            return None
            
        # Prioritize ISBN matching
        if len(book_identifier) == 13 and book_identifier.isdigit():
            matches = self.df.index[self.df["isbn13"] == book_identifier].tolist()
            if matches:
                return matches[0]

        # Fallback to title matching
        matches = self.df.index[self.df["title"].str.lower() == book_identifier.lower()].tolist()
        if matches:
            return matches[0]
            
        return None

# ── Orchestrator Class ────────────────────────────────────────────────────────
class BookRecommender:
    """
    Orchestrates the recommendation process, integrating the core engine,
    diversity, and explanation logic.
    """

    def __init__(self, config: EngineConfig = EngineConfig()):
        self.config = config
        self.engine = RecommenderEngine(config)
        self.is_fitted = False

    @property
    def df(self) -> pd.DataFrame:
        return self.engine.df

    @property
    def tfidf_matrix(self):
        return self.engine.tfidf_matrix

    @property
    def cosine_sim(self):
        return self.engine.cosine_sim

    def load_data(self, csv_path: str):
        """Load and preprocess data from a CSV file."""
        logger.info(f"Loading data from {csv_path}...")
        try:
            df = pd.read_csv(csv_path)
            self.engine.df = preprocess_dataframe(df)
            logger.info(f"Data loaded and preprocessed. Shape: {self.engine.df.shape}")
        except FileNotFoundError:
            logger.error(f"Data file not found at {csv_path}")
            self.engine.df = pd.DataFrame()

    def load_from_supabase(self, supabase_client: Client):
        """Load and preprocess data from Supabase."""
        logger.info("Fetching data from Supabase...")
        try:
            response = supabase_client.table("books").select("*").execute()
            if not response.data:
                logger.warning("No data returned from Supabase.")
                self.engine.df = pd.DataFrame()
                return
            df = pd.DataFrame(response.data)
            self.engine.df = preprocess_dataframe(df)
            logger.info(f"Data loaded from Supabase and preprocessed. Shape: {self.engine.df.shape}")
        except Exception as e:
            logger.error(f"Failed to load data from Supabase: {e}")
            self.engine.df = pd.DataFrame()

    def fit(self, save_path: Optional[str] = None):
        """Train the model and optionally save it."""
        if self.df.empty:
            logger.error("Cannot fit model: data has not been loaded.")
            self.is_fitted = False
            return
        self.engine.fit()
        self.is_fitted = self.engine.is_fitted
        if save_path and self.is_fitted:
            self.save_model(save_path)

    def save_model(self, path: str):
        """Save the fitted model to a pickle file."""
        if not self.is_fitted:
            logger.warning("Model is not fitted. Cannot save.")
            return
        logger.info(f"Saving model version {self.config.model_version} to {path}...")
        try:
            with open(path, "wb") as f:
                pickle.dump(self, f)
            logger.info("Model saved successfully.")
        except Exception as e:
            logger.error(f"Error saving model: {e}")

    def load_model(self, path: str) -> bool:
        """Load a model from a pickle file."""
        if not os.path.exists(path):
            logger.info(f"Model file not found at {path}.")
            return False
        try:
            with open(path, "rb") as f:
                loaded_model = pickle.load(f)

            # Legacy compatibility: old flows persist only RecommenderEngine.
            if isinstance(loaded_model, RecommenderEngine):
                self.engine = loaded_model
                self.config = loaded_model.config
                self.is_fitted = loaded_model.is_fitted
                logger.info("Legacy RecommenderEngine loaded successfully from %s.", path)
                return self.is_fitted

            if not hasattr(loaded_model, 'config') or loaded_model.config.model_version != self.config.model_version:
                logger.warning(
                    f"Model version mismatch. Found {getattr(loaded_model, 'config', 'N/A')}, "
                    f"expected {self.config.model_version}. Refusing to load."
                )
                return False

            self.__dict__.update(loaded_model.__dict__)
            self.is_fitted = getattr(self, 'is_fitted', False)
            logger.info(f"Model loaded successfully from {path}.")
            return self.is_fitted
        except Exception as e:
            logger.error(f"Error loading model: {e}")
            return False

    def recommend(
        self,
        seed_titles: List[str] | str,
        top_n: int = 10,
        use_diversity: bool = True,
    ) -> List[Dict[str, Any]]:
        """
        Generate book recommendations based on seed titles.
        """
        if not self.is_fitted:
            logger.info("Model not fitted. Fitting now...")
            self.fit()
            if not self.is_fitted:
                logger.warning("Model could not be fitted. Returning popular books as fallback.")
                return self.get_popular_books(limit=top_n)

        if isinstance(seed_titles, str):
            seed_titles = [seed_titles]

        if not seed_titles:
            logger.info("No seed titles provided. Returning popular books.")
            return self.get_popular_books(limit=top_n)

        seed_indices = [self.engine.find_index(title) for title in seed_titles]
        seed_indices = [idx for idx in seed_indices if idx is not None]

        if not seed_indices:
            logger.warning("None of the seed titles found in the dataset. Returning popular books.")
            return self.get_popular_books(limit=top_n)

        # Create a centroid vector from the seed books
        centroid_vec = np.asarray(self.tfidf_matrix[seed_indices].mean(axis=0)).reshape(1, -1)

        # Calculate raw similarity scores
        raw_scores = cosine_similarity(centroid_vec, self.tfidf_matrix).flatten()

        # Hybrid Scoring
        popularity_scores = self.df["popularity_score"].to_numpy()
        final_scores = (
            self.config.weight_similarity * raw_scores
            + self.config.weight_popularity * popularity_scores
        )

        # Set scores of seed books to a very low value to exclude them
        final_scores[seed_indices] = -1.0

        if use_diversity:
            # Maximal Marginal Relevance (MMR) for diversity
            recs = self._get_diverse_recommendations(final_scores, top_n)
        else:
            # Simple top-N recommendations
            top_indices = final_scores.argsort()[::-1][:top_n]
            recs = self.df.iloc[top_indices].to_dict(orient="records")
            for i, rec in enumerate(recs):
                rec["final_score"] = final_scores[top_indices[i]]

        # Add explanations
        for rec in recs:
            rec_idx = self.engine.find_index(rec.get("isbn13", ""))
            rec["raw_similarity_score"] = float(raw_scores[rec_idx]) if rec_idx is not None else 0.0
            rec.update(self._explain_recommendation(rec, seed_indices))

        return recs

    def _get_diverse_recommendations(self, scores: np.ndarray, top_n: int) -> List[Dict[str, Any]]:
        """Select diverse recommendations using Maximal Marginal Relevance (MMR)."""
        selected_indices = []
        candidate_indices = np.argsort(scores)[::-1].tolist()

        # Start with the highest-scoring item
        if not candidate_indices:
            return []

        best_idx = candidate_indices.pop(0)
        selected_indices.append(best_idx)

        while len(selected_indices) < top_n and candidate_indices:
            max_mmr = -np.inf
            best_candidate_idx = -1

            for cand_idx in candidate_indices:
                sim_to_selected = self.cosine_sim[cand_idx, selected_indices].max() if selected_indices else 0.0
                mmr = (self.config.diversity_lambda * scores[cand_idx]) - ((1 - self.config.diversity_lambda) * sim_to_selected)

                if mmr > max_mmr:
                    max_mmr = mmr
                    best_candidate_idx = cand_idx

            if best_candidate_idx != -1:
                selected_indices.append(best_candidate_idx)
                candidate_indices.remove(best_candidate_idx)
            else:
                break # No more candidates to add

        recs = self.df.iloc[selected_indices].to_dict(orient="records")
        # Add scores and diversity penalty for transparency
        for rec in recs:
            idx = self.engine.find_index(rec["isbn13"])
            if idx is not None:
                sim_to_selected = self.cosine_sim[idx, selected_indices].max() if selected_indices else 0.0
                rec["final_score"] = scores[idx]
                rec["diversity_penalty"] = (1 - self.config.diversity_lambda) * sim_to_selected
        return recs

    def _explain_recommendation(self, recommended_book: Dict[str, Any], seed_indices: List[int]) -> Dict[str, str]:
        """Generate a simple explanation for a recommendation."""
        rec_idx = self.engine.find_index(recommended_book["isbn13"])
        if rec_idx is None or not seed_indices:
            return {"explanation": "Could not generate explanation.", "explanation_source_book": ""}

        sim_scores = self.cosine_sim[rec_idx, seed_indices]
        if sim_scores.size == 0:
            return {"explanation": "Could not generate explanation.", "explanation_source_book": ""}
        most_similar_seed_idx = seed_indices[np.argmax(sim_scores)]
        source_book = self.df.iloc[most_similar_seed_idx]

        rec_cats = set(re.split(r'\s*[,|]\s*', recommended_book.get("categories", "").lower()))
        source_cats = set(re.split(r'\s*[,|]\s*', source_book.get("categories", "").lower()))
        common_genres = rec_cats.intersection(source_cats)

        if common_genres:
            explanation = f"'{source_book['title']}' kitabını sevdiğiniz için, ortak {', '.join(list(common_genres)[:2])} türündeki bu kitabı önerdik."
        else:
            explanation = f"'{source_book['title']}' kitabına benzer bir atmosferi olduğu için önerdik."
        return {
            "explanation": explanation,
            "explanation_source_book": source_book['title']
        }

    def search_books(self, query: str, limit: int = 10) -> List[Dict[str, Any]]:
        """Search for books by title, author, or description."""
        if not self.is_fitted:
            return []
        
        # A simple search implementation: check for query in combined features
        # A more robust search would use a dedicated search index or more advanced matching.
        mask = self.df["combined_features"].str.contains(query, case=False, na=False, regex=False)
        results = self.df[mask].head(limit)
        return results.to_dict(orient="records")

    def get_popular_books(self, limit: int = 10) -> List[Dict[str, Any]]:
        """Get the most popular books based on the pre-calculated popularity score."""
        if self.df.empty:
            return []
        sorted_df = self.df.sort_values(by="popularity_score", ascending=False)
        return sorted_df.head(limit).to_dict(orient="records")

    def get_all_books(self, page: int = 1, per_page: int = 20, category: Optional[str] = None) -> Dict[str, Any]:
        """Get a paginated list of all books, optionally filtered by category."""
        if self.df.empty:
            return {"books": [], "total": 0, "page": page, "per_page": per_page, "total_pages": 0}

        df = self.df
        if category:
            cat = category.strip()
            if cat and cat.lower() != 'all':
                # Senior Solution: Explicitly cast to string to handle list-like objects from Supabase/CSV
                # and use a case-insensitive search.
                mask = df["categories"].astype(str).str.contains(cat, case=False, na=False, regex=False)
                df = df[mask]

        start = (page - 1) * per_page
        end = start + per_page
        total = len(df)
        total_pages = math.ceil(total / per_page) if per_page else 1

        paginated_df = df.iloc[start:end]
        return {
            "books": paginated_df.to_dict(orient="records"),
            "total": total,
            "page": page,
            "per_page": per_page,
            "total_pages": total_pages,
        }

    def get_unique_categories(self) -> List[str]:
        """Get a list of all unique categories."""
        if self.df.empty:
            return []
        raw = self.df["categories"].dropna().astype(str)
        exploded = raw.str.split(r"\s*[,|;/]\s*").explode().str.strip()
        cleaned = exploded[
            exploded.ne("")
            & ~exploded.str.lower().isin({"nan", "none", "null", "unknown"})
        ]
        return sorted(cleaned.str.title().unique().tolist())

    def get_book_by_isbn(self, isbn: str) -> Optional[Dict[str, Any]]:
        """Retrieve a single book by its ISBN13."""
        if self.df.empty:
            return None
        book_df = self.df[self.df["isbn13"] == isbn]
        if not book_df.empty:
            return book_df.iloc[0].to_dict()
        return None
