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
import re
import sys
from typing import Any, Dict, List, Optional

import numpy as np
import pandas as pd
from backend.domain.taxonomy import CANONICAL_CATEGORIES_ORDERED, CANONICAL_CATEGORY_MAP
from backend.utils.preprocess import preprocess_dataframe
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity

# Legacy pickle alias: tfidf.pkl was serialised under the old module path
# "backend.recommender". Setting this alias here (after all imports but before
# any class definitions) ensures sys.modules contains the mapping by the time
# the module is fully initialised, which is always before any pickle.load() call.
sys.modules["backend.recommender"] = sys.modules[__name__]

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

    # Hybrid Weights
    weight_semantic: float = 0.5
    weight_tfidf: float = 0.3
    weight_popularity: float = 0.2


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
            logger.warning(
                "Detected empty TF-IDF rows with min_df=%s; refitting with min_df=1", min_df
            )
            self.tfidf_vectorizer = TfidfVectorizer(
                stop_words="english",
                max_df=self.config.tfidf_max_df,
                min_df=1,
                max_features=self.config.tfidf_max_features,
                ngram_range=(1, 2),
            )
            self.tfidf_matrix = self.tfidf_vectorizer.fit_transform(self.df["combined_features"])

        logger.info(f"TF-IDF matrix created with shape: {self.tfidf_matrix.shape}")

        logger.info("Skipping full cosine similarity matrix calculation to save memory.")
        self.cosine_sim = None
        self.is_fitted = True

    def find_all_indices(self, book_identifier: str) -> List[int]:
        """Find all DataFrame indices for a book by its title or ISBN (handling duplicates)."""
        if not isinstance(book_identifier, str):
            if isinstance(book_identifier, (int, float)):
                book_identifier = str(int(book_identifier))
            else:
                return []

        clean_id = book_identifier.strip()
        if not clean_id or self.df.empty:
            return []

        # Normalize hyphens and float strings (e.g. '9780441013593.0')
        norm_id = clean_id.replace("-", "")
        if norm_id.endswith(".0"):
            norm_id = norm_id[:-2]

        matched = set()
        # Prioritize exact ISBN matching
        if "isbn13" in self.df.columns:
            for idx in self.df.index[self.df["isbn13"] == clean_id].tolist():
                matched.add(idx)
            if norm_id != clean_id:
                for idx in self.df.index[self.df["isbn13"] == norm_id].tolist():
                    matched.add(idx)

        if "isbn10" in self.df.columns:
            for idx in self.df.index[self.df["isbn10"] == norm_id].tolist():
                matched.add(idx)

        # Fallback to title matching
        if "title" in self.df.columns:
            for idx in self.df.index[self.df["title"].astype(str).str.lower() == clean_id.lower()].tolist():
                matched.add(idx)

            unquoted = clean_id.strip("'\"")
            if unquoted != clean_id:
                for idx in self.df.index[self.df["title"].astype(str).str.lower() == unquoted.lower()].tolist():
                    matched.add(idx)

        return sorted(matched)

    def find_index(self, book_identifier: str) -> Optional[int]:
        """Find the primary DataFrame index for a book by its title or ISBN."""
        indices = self.find_all_indices(book_identifier)
        return indices[0] if indices else None


# ── Orchestrator Class ────────────────────────────────────────────────────────
class BookRecommender:
    """
    Orchestrates the recommendation process, integrating the core engine,
    diversity, and explanation logic.
    """

    CANONICAL_CATEGORIES_ORDERED = CANONICAL_CATEGORIES_ORDERED
    CANONICAL_CATEGORY_MAP = CANONICAL_CATEGORY_MAP

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
        return None

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

    def load_from_dicts(self, books: List[Dict[str, Any]]):
        """Load and preprocess data from a list of dictionaries."""
        logger.info("Loading data from list of dictionaries...")
        if not books:
            logger.warning("No data provided to load.")
            self.engine.df = pd.DataFrame()
            return

        try:
            df = pd.DataFrame(books)
            self.engine.df = preprocess_dataframe(df)
            logger.info(f"Data loaded and preprocessed. Shape: {self.engine.df.shape}")
        except Exception as e:
            logger.error(f"Failed to process book data: {e}")
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

            if (
                not hasattr(loaded_model, "config")
                or loaded_model.config.model_version != self.config.model_version
            ):
                logger.warning(
                    f"Model version mismatch. Found {getattr(loaded_model, 'config', 'N/A')}, "
                    f"expected {self.config.model_version}. Refusing to load."
                )
                return False

            self.__dict__.update(loaded_model.__dict__)
            self.is_fitted = getattr(self, "is_fitted", False)
            logger.info(f"Model loaded successfully from {path}.")
            return self.is_fitted
        except Exception as e:
            logger.error(f"Error loading model: {e}")
            return False

    def recommend(
        self,
        seed_titles: Optional[List[str] | str] = None,
        top_n: int = 10,
        use_diversity: bool = True,
        semantic_scores: Optional[Dict[str, float]] = None,
        dislikes: Optional[List[str]] = None,
        seed_weights: Optional[Dict[str, float]] = None,
        preferred_genres: Optional[List[str]] = None,
        preferred_authors: Optional[List[str]] = None,
        seed_sources: Optional[Dict[str, str]] = None,
    ) -> List[Dict[str, Any]]:
        """
        Generate personalized book recommendations with Rocchio relevance feedback,
        profile affinity fusion, and strict dislike suppression.
        """
        if not self.is_fitted:
            logger.info("Model not fitted. Fitting now...")
            self.fit()
            if not self.is_fitted:
                logger.warning("Model could not be fitted. Returning popular books as fallback.")
                return self.get_popular_books(limit=top_n)

        if isinstance(seed_titles, str):
            seed_titles = [seed_titles]
        elif seed_titles is None:
            seed_titles = []

        # Find all valid indices for seeds (handling duplicates and editions)
        seed_indices = []
        all_seed_indices = set()
        weights_by_idx: Dict[int, float] = {}
        for title in seed_titles:
            indices = self.engine.find_all_indices(title)
            if not indices:
                continue
            primary_idx = indices[0]
            w = 1.0
            if seed_weights and title in seed_weights:
                w = float(seed_weights[title])
            if primary_idx not in weights_by_idx:
                seed_indices.append(primary_idx)
                weights_by_idx[primary_idx] = w
            else:
                # Deduplicate and preserve the highest confidence weight
                weights_by_idx[primary_idx] = max(weights_by_idx[primary_idx], w)
            all_seed_indices.update(indices)

        # Dislikes indices (all occurrences) and authors
        disliked_indices = []
        all_disliked_indices = set()
        disliked_authors = set()
        if dislikes:
            for d in dislikes:
                indices = self.engine.find_all_indices(d)
                for d_idx in indices:
                    all_disliked_indices.add(d_idx)
                    if d_idx not in disliked_indices:
                        disliked_indices.append(d_idx)
                    d_auth = str(self.df.iloc[d_idx].get("authors", "")).strip().lower()
                    if d_auth and d_auth not in ("unknown author", "nan", "none"):
                        disliked_authors.add(d_auth)

        # Calculate user taste profile vector
        if seed_indices:
            # Weighted Rocchio centroid
            weighted_vecs = [
                weights_by_idx[i] * np.asarray(self.tfidf_matrix[i].todense()).flatten()
                for i in seed_indices
            ]
            sum_w = sum(weights_by_idx[i] for i in seed_indices)
            pos_centroid = np.sum(weighted_vecs, axis=0) / max(1e-6, sum_w)

            # Negative feedback shift from dislikes
            if all_disliked_indices:
                neg_indices = sorted(all_disliked_indices)
                neg_vecs = [
                    np.asarray(self.tfidf_matrix[i].todense()).flatten() for i in neg_indices
                ]
                neg_centroid = np.mean(neg_vecs, axis=0)
                user_vec = pos_centroid - 0.5 * neg_centroid
            else:
                user_vec = pos_centroid

            norm = np.linalg.norm(user_vec)
            if norm > 1e-6:
                user_vec = user_vec / norm
                raw_scores = cosine_similarity(user_vec.reshape(1, -1), self.tfidf_matrix).flatten()
            else:
                raw_scores = np.zeros(len(self.df))

        elif preferred_genres or preferred_authors:
            # Cold-start profile query vector
            query_parts = []
            if preferred_genres:
                query_parts.extend([g for g in preferred_genres for _ in range(3)])
            if preferred_authors:
                query_parts.extend([a for a in preferred_authors for _ in range(2)])
            profile_text = " ".join(query_parts).strip()
            if profile_text and self.engine.tfidf_vectorizer:
                prof_vec = self.engine.tfidf_vectorizer.transform([profile_text])
                raw_scores = cosine_similarity(prof_vec, self.tfidf_matrix).flatten()
            else:
                raw_scores = np.zeros(len(self.df))

        elif semantic_scores:
            raw_scores = np.zeros(len(self.df))
        else:
            # Zero positive signals: fallback to popular books filtering dislikes
            logger.info("No positive seeds or profile signals provided. Returning popular books.")
            extra = len(all_disliked_indices) + 10 if all_disliked_indices else 0
            pop_books = self.get_popular_books(limit=top_n + extra)
            if all_disliked_indices or dislikes:
                dislike_clean_set = set(
                    str(d).strip().replace("-", "").lower() for d in (dislikes or [])
                )
                for d_idx in all_disliked_indices:
                    dislike_clean_set.add(
                        str(self.df.iloc[d_idx].get("isbn13", "")).strip().replace("-", "").lower()
                    )
                    dislike_clean_set.add(str(self.df.iloc[d_idx].get("title", "")).strip().lower())
                pop_books = [
                    b
                    for b in pop_books
                    if str(b.get("isbn13", "")).strip().replace("-", "").lower()
                    not in dislike_clean_set
                    and str(b.get("title", "")).strip().lower() not in dislike_clean_set
                ]
            for b in pop_books:
                if "recommendation_reason" not in b:
                    b["recommendation_reason"] = "Trending on Libris right now"
            return pop_books[:top_n]

        # Process semantic scores if provided
        semantic_vec = np.zeros(len(self.df))
        if semantic_scores:
            for isbn, score in semantic_scores.items():
                indices = self.engine.find_all_indices(isbn)
                for idx in indices:
                    semantic_vec[idx] = score

        # Compute Profile Affinity Bonuses
        affinity_scores = np.zeros(len(self.df))
        if preferred_genres:
            for g in preferred_genres:
                g_clean = g.strip().lower()
                if g_clean:
                    mask = (
                        self.df["categories"]
                        .astype(str)
                        .str.contains(g_clean, case=False, na=False, regex=False)
                    )
                    affinity_scores[mask.to_numpy()] += 0.15

        if preferred_authors:
            for a in preferred_authors:
                a_clean = a.strip().lower()
                if a_clean:
                    mask = (
                        self.df["authors"]
                        .astype(str)
                        .str.contains(a_clean, case=False, na=False, regex=False)
                    )
                    affinity_scores[mask.to_numpy()] += 0.20

        # Disliked authors penalty
        if disliked_authors:
            for d_auth in disliked_authors:
                mask = self.df["authors"].astype(str).str.lower().str.contains(d_auth, regex=False)
                affinity_scores[mask.to_numpy()] -= 0.35

        # Nan/inf guards for all input vectors
        raw_scores = np.nan_to_num(raw_scores, nan=0.0, posinf=0.0, neginf=0.0)
        popularity_scores = np.nan_to_num(
            self.df["popularity_score"].to_numpy(dtype=float), nan=0.0, posinf=0.0, neginf=0.0
        )
        semantic_vec = np.nan_to_num(semantic_vec, nan=0.0, posinf=0.0, neginf=0.0)
        affinity_scores = np.nan_to_num(affinity_scores, nan=0.0, posinf=0.0, neginf=0.0)

        # Hybrid Scoring
        if semantic_scores:
            final_scores = (
                self.config.weight_tfidf * raw_scores
                + self.config.weight_semantic * semantic_vec
                + self.config.weight_popularity * popularity_scores
                + affinity_scores
            )
        else:
            final_scores = 0.60 * raw_scores + 0.25 * popularity_scores + 0.15 * affinity_scores

        final_scores = np.nan_to_num(final_scores, nan=-1.0, posinf=0.0, neginf=-1.0)

        # Set scores of ALL seed books to a very low value to exclude them
        if all_seed_indices:
            final_scores[list(all_seed_indices)] = -1.0

        # Strict hard filter for ALL dislikes
        if all_disliked_indices:
            final_scores[list(all_disliked_indices)] = -1.0

        if use_diversity:
            # Maximal Marginal Relevance (MMR) for diversity
            recs = self._get_diverse_recommendations(final_scores, top_n)
        else:
            # Deterministic top-N recommendations excluding suppressed candidates
            suppressed = all_seed_indices.union(all_disliked_indices)
            valid_indices = [
                i
                for i in range(len(final_scores))
                if i not in suppressed and final_scores[i] > -0.5
            ]
            sorted_indices = sorted(
                valid_indices,
                key=lambda i: (
                    float(final_scores[i]),
                    float(popularity_scores[i]),
                    float(self.df.iloc[i].get("average_rating") or 0.0),
                    -i,  # Stable deterministic tie-breaker
                ),
                reverse=True,
            )
            top_indices = []
            seen_isbns = set()
            seen_titles = set()
            for idx in sorted_indices:
                row = self.df.iloc[idx]
                isbn = str(row.get("isbn13", "")).strip().replace("-", "").lower()
                title = str(row.get("title", "")).strip().lower()
                if isbn and isbn in seen_isbns:
                    continue
                if title and title in seen_titles:
                    continue
                if isbn:
                    seen_isbns.add(isbn)
                if title:
                    seen_titles.add(title)
                top_indices.append(idx)
                if len(top_indices) >= top_n:
                    break

            recs = self.df.iloc[top_indices].to_dict(orient="records")
            for i, rec in enumerate(recs):
                rec["final_score"] = float(final_scores[top_indices[i]])

        # Strict post-filter safeguard against dislikes and seeds
        dislike_clean_set = set()
        if dislikes or all_disliked_indices:
            for d in (dislikes or []):
                dislike_clean_set.add(str(d).strip().replace("-", "").lower())
            for d_idx in all_disliked_indices:
                dislike_clean_set.add(
                    str(self.df.iloc[d_idx].get("isbn13", "")).strip().replace("-", "").lower()
                )
                dislike_clean_set.add(str(self.df.iloc[d_idx].get("title", "")).strip().lower())

        seed_clean_set = set()
        if seed_titles or all_seed_indices:
            for s in seed_titles:
                seed_clean_set.add(str(s).strip().replace("-", "").lower())
            for s_idx in all_seed_indices:
                seed_clean_set.add(
                    str(self.df.iloc[s_idx].get("isbn13", "")).strip().replace("-", "").lower()
                )
                seed_clean_set.add(str(self.df.iloc[s_idx].get("title", "")).strip().lower())

        if dislike_clean_set or seed_clean_set:
            recs = [
                r
                for r in recs
                if str(r.get("isbn13", "")).strip().replace("-", "").lower() not in dislike_clean_set
                and str(r.get("title", "")).strip().lower() not in dislike_clean_set
                and str(r.get("isbn13", "")).strip().replace("-", "").lower() not in seed_clean_set
                and str(r.get("title", "")).strip().lower() not in seed_clean_set
            ]

        # Add explanations
        for rec in recs:
            rec_idx = self.engine.find_index(rec.get("isbn13", ""))
            rec["raw_similarity_score"] = float(raw_scores[rec_idx]) if rec_idx is not None else 0.0
            rec.update(
                self._explain_recommendation(
                    rec,
                    seed_indices,
                    semantic_scores,
                    preferred_genres=preferred_genres,
                    preferred_authors=preferred_authors,
                    seed_sources=seed_sources,
                )
            )

        return recs[:top_n]

    def _get_diverse_recommendations(self, scores: np.ndarray, top_n: int) -> List[Dict[str, Any]]:
        """Select diverse recommendations using Maximal Marginal Relevance (MMR) with candidate deduplication."""
        # Exclude suppressed/negative items from candidate pool
        valid_indices = [int(i) for i in np.argsort(scores)[::-1] if scores[i] > -0.5]
        candidate_indices = valid_indices[: max(100, top_n * 10)]

        # Start with the highest-scoring item
        if not candidate_indices:
            return []

        selected_indices = []
        seen_isbns = set()
        seen_titles = set()

        def _is_duplicate_book(idx: int) -> bool:
            row = self.df.iloc[idx]
            isbn = str(row.get("isbn13", "")).strip().replace("-", "").lower()
            title = str(row.get("title", "")).strip().lower()
            if isbn and isbn in seen_isbns:
                return True
            if title and title in seen_titles:
                return True
            return False

        def _record_book(idx: int) -> None:
            row = self.df.iloc[idx]
            isbn = str(row.get("isbn13", "")).strip().replace("-", "").lower()
            title = str(row.get("title", "")).strip().lower()
            if isbn:
                seen_isbns.add(isbn)
            if title:
                seen_titles.add(title)

        for idx in list(candidate_indices):
            if not _is_duplicate_book(idx):
                selected_indices.append(idx)
                _record_book(idx)
                candidate_indices.remove(idx)
                break

        while len(selected_indices) < top_n and candidate_indices:
            max_mmr = -np.inf
            best_candidate_idx = -1

            for cand_idx in candidate_indices:
                if _is_duplicate_book(cand_idx):
                    continue

                if selected_indices:
                    sim_scores = cosine_similarity(
                        self.tfidf_matrix[cand_idx], self.tfidf_matrix[selected_indices]
                    )[0]
                    sim_to_selected = sim_scores.max()
                else:
                    sim_to_selected = 0.0
                mmr = (self.config.diversity_lambda * scores[cand_idx]) - (
                    (1 - self.config.diversity_lambda) * sim_to_selected
                )

                if mmr > max_mmr:
                    max_mmr = mmr
                    best_candidate_idx = cand_idx

            if best_candidate_idx != -1:
                selected_indices.append(best_candidate_idx)
                _record_book(best_candidate_idx)
                candidate_indices.remove(best_candidate_idx)
            else:
                break  # No more candidates to add

        recs = self.df.iloc[selected_indices].to_dict(orient="records")
        # Add scores and diversity penalty for transparency
        for rec in recs:
            idx = self.engine.find_index(rec["isbn13"])
            if idx is not None:
                if selected_indices:
                    sim_scores = cosine_similarity(
                        self.tfidf_matrix[idx], self.tfidf_matrix[selected_indices]
                    )[0]
                    sim_to_selected = sim_scores.max()
                else:
                    sim_to_selected = 0.0
                rec["final_score"] = float(scores[idx])
                rec["diversity_penalty"] = float(
                    (1 - self.config.diversity_lambda) * sim_to_selected
                )
        return recs[:top_n]

    def _explain_recommendation(
        self,
        recommended_book: Dict[str, Any],
        seed_indices: List[int],
        semantic_scores: Optional[Dict[str, float]] = None,
        preferred_genres: Optional[List[str]] = None,
        preferred_authors: Optional[List[str]] = None,
        seed_sources: Optional[Dict[str, str]] = None,
    ) -> Dict[str, str]:
        """Generate an explainability payload and natural reasoning for a recommendation."""
        rec_idx = self.engine.find_index(recommended_book["isbn13"])
        if rec_idx is None:
            return {}

        isbn = recommended_book.get("isbn13", "")
        has_semantic_match = semantic_scores and isbn in semantic_scores

        rec_cats = set(re.split(r"\s*[,|]\s*", str(recommended_book.get("categories", "")).lower()))
        cat_list = [c for c in rec_cats if c]

        if not seed_indices:
            # Check profile matches first
            if preferred_genres:
                for g in preferred_genres:
                    if g.strip().lower() in str(recommended_book.get("categories", "")).lower():
                        return {
                            "explanation": f"Bu kitap, ilgi duyduğunuz {g} kategorisiyle eşleştiği için önerildi.",
                            "explanation_source_book": "",
                            "recommendation_reason": f"Because you enjoy {g}",
                            "explanation_type": "category_affinity",
                            "confidence": "medium",
                            "is_cold_start": False,
                        }
            if preferred_authors:
                for a in preferred_authors:
                    if a.strip().lower() in str(recommended_book.get("authors", "")).lower():
                        return {
                            "explanation": f"Bu kitap, tercih ettiğiniz yazar {a} tarafından yazıldığı için önerildi.",
                            "explanation_source_book": "",
                            "recommendation_reason": f"By your preferred author {a}",
                            "explanation_type": "author_affinity",
                            "confidence": "medium",
                            "is_cold_start": False,
                        }
            # Pure semantic search case
            if cat_list:
                explanation = f"Bu kitap, aramanızla anlamsal olarak eşleşti ve {cat_list[0]} kategorisinde yer alıyor."
            else:
                explanation = "Bu kitap, arama niyetinizle en yüksek anlamsal benzerliğe sahip olduğu için önerildi."
            return {
                "explanation": explanation,
                "explanation_source_book": "",
                "recommendation_reason": "Trending on Libris right now",
                "explanation_type": "trending_catalog",
                "confidence": "cold_start",
                "is_cold_start": True,
            }

        # Hybrid case: we have both likes/status seeds (seed_indices) and possibly semantic matches
        sim_scores = cosine_similarity(self.tfidf_matrix[rec_idx], self.tfidf_matrix[seed_indices])[
            0
        ]
        if sim_scores.size == 0:
            return {}

        max_sim = float(np.max(sim_scores))
        if max_sim < 0.05:
            # Low similarity to specific seeds - attribute to profile or general taste rather than false seed causation
            if preferred_genres:
                for g in preferred_genres:
                    if g.strip().lower() in str(recommended_book.get("categories", "")).lower():
                        return {
                            "explanation": f"Bu kitap, ilgi duyduğunuz {g} kategorisiyle eşleştiği için önerildi.",
                            "explanation_source_book": "",
                            "recommendation_reason": f"Because you enjoy {g}",
                            "explanation_type": "category_affinity",
                            "confidence": "medium",
                            "is_cold_start": False,
                        }
            if preferred_authors:
                for a in preferred_authors:
                    if a.strip().lower() in str(recommended_book.get("authors", "")).lower():
                        return {
                            "explanation": f"Bu kitap, tercih ettiğiniz yazar {a} tarafından yazıldığı için önerildi.",
                            "explanation_source_book": "",
                            "recommendation_reason": f"By your preferred author {a}",
                            "explanation_type": "author_affinity",
                            "confidence": "medium",
                            "is_cold_start": False,
                        }
            return {
                "explanation": "Bu kitap, genel okuma profiliniz ve beğenileriniz doğrultusunda önerildi.",
                "explanation_source_book": "",
                "recommendation_reason": "Curated based on your taste profile",
                "explanation_type": "category_affinity",
                "confidence": "medium",
                "is_cold_start": False,
            }

        most_similar_seed_idx = seed_indices[np.argmax(sim_scores)]
        source_book = self.df.iloc[most_similar_seed_idx]
        source_cats = set(re.split(r"\s*[,|]\s*", str(source_book.get("categories", "")).lower()))
        common_genres = rec_cats.intersection(source_cats)

        # Determine source interaction type for personalized attribution
        src_clean_isbn = str(source_book.get("isbn13", "")).strip().replace("-", "").lower()
        src_raw_isbn = str(source_book.get("isbn13", "")).strip()
        src_title = str(source_book.get("title", "")).strip().lower()
        src_type = None
        if seed_sources:
            src_type = (
                seed_sources.get(src_clean_isbn)
                or seed_sources.get(src_raw_isbn)
                or seed_sources.get(src_title)
                or seed_sources.get(str(source_book.get("title", "")).strip())
            )

        explanation_type = "liked_book"
        confidence = "high"

        if src_type == "favorite":
            rec_reason = f"Because you favorited '{source_book['title']}'"
            verb_tr = "favorilerinize eklediğiniz"
            explanation_type = "favorite_book"
            confidence = "high"
        elif src_type == "finished":
            rec_reason = f"Because you read '{source_book['title']}'"
            verb_tr = "okuduğunuz"
            explanation_type = "finished_book"
            confidence = "high"
        elif src_type == "reading":
            rec_reason = f"Because you're reading '{source_book['title']}'"
            verb_tr = "şu an okumakta olduğunuz"
            explanation_type = "reading_journey"
            confidence = "medium"
        elif src_type == "want_to_read":
            rec_reason = f"From your reading list: '{source_book['title']}'"
            verb_tr = "okuma listenize eklediğiniz"
            explanation_type = "reading_journey"
            confidence = "medium"
        elif src_type == "like":
            rec_reason = f"Because you liked '{source_book['title']}'"
            verb_tr = "beğendiğiniz"
            explanation_type = "liked_book"
            confidence = "high"
        elif src_type == "notes":
            rec_reason = f"Based on your notes for '{source_book['title']}'"
            verb_tr = "öğrenme notları aldığınız"
            explanation_type = "reading_journey"
            confidence = "medium"
        elif src_type == "takeaway":
            rec_reason = f"Deepens takeaways from '{source_book['title']}'"
            verb_tr = "çıkarımlar kaydettiğiniz"
            explanation_type = "takeaway_affinity"
            confidence = "high"
        elif src_type == "learning_path":
            rec_reason = "Suggested for your learning path"
            verb_tr = "öğrenme yolunuzdaki"
            explanation_type = "learning_path_continuity"
            confidence = "high"
        else:
            # Evidence-based attribution: distinguish user profile from content-similarity
            has_profile = bool(preferred_genres or preferred_authors)
            if has_profile:
                rec_reason = "Curated based on your taste profile"
                verb_tr = "ilgilendiğiniz"
                explanation_type = "category_affinity"
                confidence = "medium"
            else:
                rec_reason = f"Similar to '{source_book['title']}'"
                verb_tr = "incelediğiniz"
                explanation_type = "liked_book"
                confidence = "medium"

        if src_type:
            if has_semantic_match:
                # Acknowledge both user preference and semantic query
                if common_genres:
                    explanation = f"Aramanızla eşleşmesinin yanı sıra, {verb_tr} '{source_book['title']}' kitabıyla ortak ({list(common_genres)[0]}) türünde olduğu için önerildi."
                else:
                    explanation = f"Aramanızla güçlü bir eşleşme sağladı ve okuma geçmişinizdeki '{source_book['title']}' kitabına benzer bir atmosfere sahip."
            else:
                # Standard personalized recommendation
                if common_genres:
                    explanation = f"'{source_book['title']}' kitabını {verb_tr} için, ortak {', '.join(list(common_genres)[:2])} türündeki bu kitabı önerdik."
                else:
                    explanation = (
                        f"'{source_book['title']}' kitabına benzer bir atmosferi olduğu için önerdik."
                    )
        else:
            has_profile = bool(preferred_genres or preferred_authors)
            if has_profile:
                if common_genres:
                    explanation = f"İlgi duyduğunuz {', '.join(list(common_genres)[:2])} türündeki okuma zevkinize özel seçildi."
                else:
                    explanation = "Okuma zevkinize ve kütüphanenize özel olarak seçildi."
            else:
                if common_genres:
                    explanation = f"'{source_book['title']}' kitabıyla ortak ({', '.join(list(common_genres)[:2])}) türünde olduğu için önerildi."
                else:
                    explanation = f"'{source_book['title']}' kitabına benzer tematik ve anlamsal özellikleri nedeniyle önerildi."

        return {
            "explanation": explanation,
            "explanation_source_book": source_book["title"],
            "recommendation_reason": rec_reason,
            "explanation_type": explanation_type,
            "confidence": confidence,
            "is_cold_start": False,
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
        """Get the most popular books based on the pre-calculated popularity score with deduplication."""
        if self.df.empty:
            return []
        sorted_df = self.df.sort_values(by="popularity_score", ascending=False)
        if "isbn13" in sorted_df.columns:
            sorted_df = sorted_df.drop_duplicates(subset=["isbn13"])
        if "title" in sorted_df.columns:
            sorted_df = sorted_df.drop_duplicates(subset=["title"])
        books = sorted_df.head(limit).to_dict(orient="records")
        for b in books:
            if "recommendation_reason" not in b or not b.get("recommendation_reason"):
                b["recommendation_reason"] = "Trending on Libris right now"
            if "explanation" not in b or not b.get("explanation"):
                b["explanation"] = "Bu kitap, Libris genelindeki popüler ve yüksek puanlı eserler arasından seçildi."
            if "explanation_type" not in b or not b.get("explanation_type"):
                b["explanation_type"] = "trending_catalog"
            if "confidence" not in b or not b.get("confidence"):
                b["confidence"] = "cold_start"
            if "is_cold_start" not in b:
                b["is_cold_start"] = True
        return books

    def get_all_books(
        self,
        page: int = 1,
        per_page: int = 20,
        category: Optional[str] = None,
        author: Optional[str] = None,
        publisher: Optional[str] = None,
        min_pages: Optional[int] = None,
        max_pages: Optional[int] = None,
        min_rating: Optional[float] = None,
        published_from: Optional[int] = None,
        published_to: Optional[int] = None,
        sort: Optional[str] = None,
        order: Optional[str] = "asc",
        query: Optional[str] = None,
    ) -> Dict[str, Any]:
        """Get a paginated list of all books, optionally filtered and sorted."""
        if self.df.empty:
            return {"books": [], "total": 0, "page": page, "per_page": per_page, "total_pages": 0}

        df = self.df.copy()

        if query:
            q_clean = query.strip()
            if q_clean:
                title_mask = df["title"].astype(str).str.contains(q_clean, case=False, na=False, regex=False)
                author_mask = df["authors"].astype(str).str.contains(q_clean, case=False, na=False, regex=False)
                desc_mask = (
                    df["description"].astype(str).str.contains(q_clean, case=False, na=False, regex=False)
                    if "description" in df.columns
                    else False
                )
                isbn13_mask = (
                    df["isbn13"].astype(str).str.contains(q_clean, case=False, na=False, regex=False)
                    if "isbn13" in df.columns
                    else False
                )
                isbn10_mask = (
                    df["isbn10"].astype(str).str.contains(q_clean, case=False, na=False, regex=False)
                    if "isbn10" in df.columns
                    else False
                )
                df = df[title_mask | author_mask | desc_mask | isbn13_mask | isbn10_mask]

        if category:
            cat = category.strip()
            if cat and cat.lower() != "all":
                if cat in self.CANONICAL_CATEGORIES_ORDERED:
                    mask = (
                        df["categories"]
                        .astype(str)
                        .apply(lambda raw: self._book_matches_canonical(raw, cat))
                    )
                else:
                    mask = (
                        df["categories"]
                        .astype(str)
                        .str.contains(cat, case=False, na=False, regex=False)
                    )
                df = df[mask]

        if author:
            df = df[
                df["authors"]
                .astype(str)
                .str.contains(author.strip(), case=False, na=False, regex=False)
            ]

        if publisher:
            # Check if dataset has publisher, if not ignore or handle gracefully
            if "publisher" in df.columns:
                df = df[
                    df["publisher"]
                    .astype(str)
                    .str.contains(publisher.strip(), case=False, na=False, regex=False)
                ]

        if min_pages is not None:
            if "page_count" in df.columns:
                df = df[df["page_count"] >= min_pages]

        if max_pages is not None:
            if "page_count" in df.columns:
                df = df[df["page_count"] <= max_pages]

        if min_rating is not None:
            if "average_rating" in df.columns:
                df = df[df["average_rating"] >= min_rating]

        if published_from is not None or published_to is not None:
            if "published_date" in df.columns:
                years = df["published_date"].astype(str).str.extract(r"(\d{4})")[0].astype(float)
                if published_from is not None:
                    df = df[years >= published_from]
                if published_to is not None:
                    df = df[years <= published_to]

        if sort:
            ascending = order.lower() == "asc"
            if sort == "rating" and "average_rating" in df.columns:
                df = df.sort_values(by="average_rating", ascending=ascending, na_position="last")
            elif sort == "popularity" and "popularity_score" in df.columns:
                df = df.sort_values(by="popularity_score", ascending=ascending, na_position="last")
            elif sort == "newest" or sort == "oldest":
                if "published_date" in df.columns:
                    sort_years = df["published_date"].astype(str).str.extract(r"(\d{4})")[0].astype(float)
                    df = (
                        df.assign(_sort_year=sort_years)
                        .sort_values(by="_sort_year", ascending=(sort == "oldest"), na_position="last")
                        .drop(columns=["_sort_year"])
                    )
            elif sort == "title" and "title" in df.columns:
                df = df.sort_values(by="title", ascending=ascending, na_position="last")

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

    # ── Canonical Category Taxonomy ───────────────────────────────────────────

    @classmethod
    def _get_canonical_for_raw(cls, raw_category: str) -> Optional[str]:
        """Return canonical category name for a raw category string, or None."""
        key = raw_category.strip().lower()
        if not key:
            return None
        if key in CANONICAL_CATEGORY_MAP:
            return CANONICAL_CATEGORY_MAP[key]
        for canonical in CANONICAL_CATEGORIES_ORDERED:
            if canonical.lower() == key:
                return canonical
        return None

    @classmethod
    def _book_matches_canonical(cls, raw_categories_str: str, canonical: str) -> bool:
        """Check if a book's raw categories string contains the given canonical category."""
        clean_raw = str(raw_categories_str or "").strip()
        if not clean_raw:
            return False

        # 1. Direct check on the whole un-split string (preserves compound categories with '&')
        direct_match = cls._get_canonical_for_raw(clean_raw)
        if direct_match and direct_match.lower() == canonical.lower():
            return True

        # 2. Check parts split on delimiters (commas, semicolons, pipes)
        parts = re.split(r"[,|;/]", clean_raw)
        for part in parts:
            p_strip = part.strip()
            mapped = cls._get_canonical_for_raw(p_strip)
            if mapped and mapped.lower() == canonical.lower():
                return True
            # Also sub-split on '&' if not already matching a compound category
            if "&" in p_strip:
                subparts = [sp.strip() for sp in p_strip.split("&")]
                for sp in subparts:
                    sp_mapped = cls._get_canonical_for_raw(sp)
                    if sp_mapped and sp_mapped.lower() == canonical.lower():
                        return True
        return False

    def get_unique_categories(self) -> List[Dict[str, Any]]:
        """Return canonical categories that have at least one book in the dataset, with their counts."""
        if self.df.empty:
            return []

        counts = {}
        for raw in self.df["categories"].dropna().astype(str):
            clean_raw = raw.strip()
            if not clean_raw:
                continue
            matched_for_book = set()
            whole_mapped = self._get_canonical_for_raw(clean_raw)
            if whole_mapped:
                matched_for_book.add(whole_mapped)
            for part in re.split(r"[,|;/]", clean_raw):
                p_mapped = self._get_canonical_for_raw(part.strip())
                if p_mapped:
                    matched_for_book.add(p_mapped)
            for c in matched_for_book:
                counts[c] = counts.get(c, 0) + 1

        return [
            {"name": c, "count": counts[c]} for c in CANONICAL_CATEGORIES_ORDERED if c in counts
        ]

    def get_book_by_isbn(self, isbn: str) -> Optional[Dict[str, Any]]:
        """Retrieve a single book by its ISBN13."""
        if self.df.empty:
            return None
        book_df = self.df[self.df["isbn13"] == isbn]
        if not book_df.empty:
            return book_df.iloc[0].to_dict()
        return None
