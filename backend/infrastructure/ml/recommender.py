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
from dataclasses import asdict, dataclass, fields
from typing import Any, Dict, Iterable, List, Optional, Set

import numpy as np
import pandas as pd
from backend.domain.taxonomy import CANONICAL_CATEGORIES_ORDERED, CANONICAL_CATEGORY_MAP
from backend.utils.preprocess import clean_text, normalize_isbn, preprocess_dataframe, work_id
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity

# Legacy pickle alias: tfidf.pkl was serialised under the old module path
# "backend.recommender". Setting this alias here (after all imports but before
# any class definitions) ensures sys.modules contains the mapping by the time
# the module is fully initialised, which is always before any pickle.load() call.
sys.modules["backend.recommender"] = sys.modules[__name__]

# ── Constants ─────────────────────────────────────────────────────────────────
# Bump whenever the persisted artifact's meaning changes (TF-IDF recipe, preprocessing, row
# layout). 2.3.0: EngineConfig is stored on the instance (earlier pickles stored no config at all,
# so their version could not be checked) and rows carry merged `edition_isbns`.
MODEL_VERSION = "2.3.0"
# TF-IDF recipe picked with the offline harness in backend/evaluation (see its README). Those
# comparisons use provisional LLM-generated labels that were also used for the tuning itself, so
# they indicate a direction, not an independently validated improvement. sublinear_tf is the
# change that moved the provisional seed-to-item scores most: it keeps the 3x-repeated title
# from dominating similarity on incidental title words.
TFIDF_MAX_DF = 0.8
TFIDF_MIN_DF = 2
TFIDF_MAX_FEATURES = None
TFIDF_SUBLINEAR_TF = True

# MMR trade-off on max-normalised relevance (see _get_diverse_recommendations). With lambda 0.6
# on raw scores the similarity penalty (0-1 scale) outweighed TF-IDF relevance (~0.1-0.3), which
# filled lists with unrelated popular books.
DIVERSITY_LAMBDA = 0.85

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
def _optional_column_contains(df, column: str, query: str):
    """Case-insensitive substring match on an optional ISBN column."""
    if column not in df.columns:
        return pd.Series(False, index=df.index)
    return df[column].astype(str).str.contains(query, case=False, na=False, regex=False)


@dataclass
class EngineConfig:
    """
    Typed configuration for the recommendation engine.

    A dataclass, so every value lives in the instance __dict__ and is pickled with the model.
    (As a plain class with class attributes, a pickled config carried no values: reading
    `model_version` from an unpickled artifact returned the *current* code's constant, so the
    version check could never fail.)
    """

    model_version: str = MODEL_VERSION
    tfidf_max_df: float = TFIDF_MAX_DF
    tfidf_min_df: int = TFIDF_MIN_DF
    tfidf_max_features: Optional[int] = TFIDF_MAX_FEATURES
    tfidf_sublinear_tf: bool = TFIDF_SUBLINEAR_TF
    diversity_lambda: float = DIVERSITY_LAMBDA

    # Hybrid Weights
    weight_semantic: float = 0.5
    weight_tfidf: float = 0.3
    weight_popularity: float = 0.2


def artifact_incompatibility(saved_config: Any, expected: EngineConfig) -> Optional[str]:
    """
    Why a persisted config cannot be used with the running code, or None when it matches.

    Reads the values actually stored on the instance (vars()), never class-level fallbacks, so an
    artifact that predates stored configs is reported as such instead of silently passing.
    """
    if saved_config is None:
        return "artifact has no config"
    stored = vars(saved_config) if hasattr(saved_config, "__dict__") else {}
    if "model_version" not in stored:
        return "artifact predates stored model configs (no model_version saved with it)"
    if stored["model_version"] != expected.model_version:
        return f"model_version {stored['model_version']!r} != expected {expected.model_version!r}"
    wanted = asdict(expected)
    diff = sorted(f.name for f in fields(EngineConfig) if stored.get(f.name, "<missing>") != wanted[f.name])
    if diff:
        return "config differs from the running code in: " + ", ".join(diff)
    return None


def _engine_integrity_problem(engine: "RecommenderEngine") -> Optional[str]:
    """A fitted artifact must have a vectorizer and one TF-IDF row per catalog row."""
    if not getattr(engine, "is_fitted", False):
        return "artifact is not fitted"
    matrix = getattr(engine, "tfidf_matrix", None)
    df = getattr(engine, "df", None)
    if matrix is None or getattr(engine, "tfidf_vectorizer", None) is None or df is None:
        return "artifact is missing its TF-IDF state"
    if matrix.shape[0] != len(df):
        return f"TF-IDF rows ({matrix.shape[0]}) != catalog rows ({len(df)})"
    return None


def _row_identity(row) -> str:
    """Edition-aware book identity of a catalog row (folded title + first-author surname)."""
    return work_id(row.get("title", ""), row.get("authors", ""))


# ── Core Engine ───────────────────────────────────────────────────────────────
class RecommenderEngine:
    """
    Handles data loading, TF-IDF vectorization, and core similarity calculations.
    """

    _ISBN_COLUMNS = ("isbn13", "isbn10", "edition_isbns")

    def __init__(self, config: Optional[EngineConfig] = None):
        self.config = config if config is not None else EngineConfig()
        self.df: pd.DataFrame = pd.DataFrame()
        self.tfidf_vectorizer: Optional[TfidfVectorizer] = None
        self.tfidf_matrix = None
        self.cosine_sim = None
        self.is_fitted = False
        self._isbn_index: Dict[str, List[int]] = {}
        self._isbn_index_key: Optional[tuple] = None

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
        docs = self.df["combined_features"]
        try:
            self.tfidf_vectorizer = self._make_vectorizer(min_df)
            self.tfidf_matrix = self.tfidf_vectorizer.fit_transform(docs)
        except ValueError:
            # Small/dev datasets can be too sparse for min_df>1; fallback keeps engine usable.
            logger.warning("TF-IDF fit failed with min_df=%s; retrying with min_df=1", min_df)
            min_df = 1
            self.tfidf_vectorizer = self._make_vectorizer(1)
            self.tfidf_matrix = self.tfidf_vectorizer.fit_transform(docs)

        # If any row has no features, similarity on that row collapses; retry with min_df=1.
        if (self.tfidf_matrix.getnnz(axis=1) == 0).any() and min_df != 1:
            logger.warning(
                "Detected empty TF-IDF rows with min_df=%s; refitting with min_df=1", min_df
            )
            self.tfidf_vectorizer = self._make_vectorizer(1)
            self.tfidf_matrix = self.tfidf_vectorizer.fit_transform(docs)

        logger.info(f"TF-IDF matrix created with shape: {self.tfidf_matrix.shape}")

        logger.info("Skipping full cosine similarity matrix calculation to save memory.")
        self.cosine_sim = None
        self.is_fitted = True

    def _make_vectorizer(self, min_df: int) -> TfidfVectorizer:
        return TfidfVectorizer(
            stop_words="english",
            max_df=self.config.tfidf_max_df,
            min_df=min_df,
            max_features=self.config.tfidf_max_features,
            ngram_range=(1, 2),
            sublinear_tf=self.config.tfidf_sublinear_tf,
        )

    def _isbn_fingerprint(self) -> tuple:
        """
        Identity of the ISBN data the index was built from. Covers reassignment (id/len) and
        in-place edits of the ISBN columns (content hash), e.g. a startup sync that merges a new
        edition ISBN into an existing row's edition_isbns. About 0.2 ms on the 6.4k-row catalog.
        """
        cols = tuple(c for c in self._ISBN_COLUMNS if c in self.df.columns)
        content = hash(tuple(hash(tuple(self.df[c].astype(str).tolist())) for c in cols))
        return (id(self.df), len(self.df), tuple(self.df.index[:1]), tuple(self.df.index[-1:]), cols, content)

    def _isbn_lookup(self, validate: bool = True) -> Dict[str, List[int]]:
        """
        ISBN -> row indices, covering every edition ISBN merged into a row (edition_isbns).

        validate=False skips the content fingerprint and only checks the cheap (id, len) part;
        callers use it for repeated lookups inside one operation after validating once.
        """
        key = self._isbn_index_key
        cheap = (id(self.df), len(self.df))
        if key is not None and not validate and key[:2] == cheap:
            return self._isbn_index
        fingerprint = self._isbn_fingerprint()
        if key != fingerprint:
            index: Dict[str, List[int]] = {}
            for col in fingerprint[4]:
                for idx, raw in zip(self.df.index, self.df[col].astype(str)):
                    for part in raw.split("|"):
                        isbn = normalize_isbn(part)
                        if isbn and isbn not in ("NAN", "NONE") and idx not in index.setdefault(isbn, []):
                            index[isbn].append(idx)
            self._isbn_index, self._isbn_index_key = index, fingerprint
        return self._isbn_index

    def indices_for_isbns(self, isbns: Iterable[str], validate: bool = True) -> Set[int]:
        """Row indices of every catalog row that carries any of the ISBNs, on any edition."""
        lookup = self._isbn_lookup(validate=validate)
        out: Set[int] = set()
        for raw in isbns or []:
            out.update(lookup.get(normalize_isbn(raw), []))
        return out

    def find_all_indices(self, book_identifier: str, validate: bool = True) -> List[int]:
        """Find all DataFrame indices for a book by its title or ISBN (handling duplicates)."""
        if not isinstance(book_identifier, str):
            if isinstance(book_identifier, (int, float)):
                book_identifier = str(int(book_identifier))
            else:
                return []

        clean_id = book_identifier.strip()
        if not clean_id or self.df.empty:
            return []

        # Exact ISBN match on any edition (hyphens and float suffixes like '….0' normalised)
        matched = set(self._isbn_lookup(validate=validate).get(normalize_isbn(clean_id), []))

        # Fallback to title matching
        if "title" in self.df.columns:
            for idx in self.df.index[self.df["title"].astype(str).str.lower() == clean_id.lower()].tolist():
                matched.add(idx)

            unquoted = clean_id.strip("'\"")
            if unquoted != clean_id:
                for idx in self.df.index[self.df["title"].astype(str).str.lower() == unquoted.lower()].tolist():
                    matched.add(idx)

        return sorted(matched)

    def find_index(self, book_identifier: str, validate: bool = True) -> Optional[int]:
        """Find the primary DataFrame index for a book by its title or ISBN."""
        indices = self.find_all_indices(book_identifier, validate=validate)
        return indices[0] if indices else None


# ── Orchestrator Class ────────────────────────────────────────────────────────
class BookRecommender:
    """
    Orchestrates the recommendation process, integrating the core engine,
    diversity, and explanation logic.
    """

    CANONICAL_CATEGORIES_ORDERED = CANONICAL_CATEGORIES_ORDERED
    CANONICAL_CATEGORY_MAP = CANONICAL_CATEGORY_MAP

    def __init__(self, config: Optional[EngineConfig] = None):
        self.config = config if config is not None else EngineConfig()
        self.engine = RecommenderEngine(self.config)
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
        """
        Load a model from a pickle file. Returns False (leaving this instance untouched) when the
        artifact is missing, unreadable, or incompatible with the running code; callers then
        retrain (BookService._bootstrap), so an old artifact never silently serves stale state.
        """
        if not os.path.exists(path):
            logger.info(f"Model file not found at {path}.")
            return False
        try:
            with open(path, "rb") as f:
                loaded_model = pickle.load(f)
        except Exception as e:
            logger.error(f"Error loading model from {path}: {e}")
            return False

        # Older flows persisted only a RecommenderEngine; it gets the same checks.
        if isinstance(loaded_model, RecommenderEngine):
            engine, saved_config = loaded_model, getattr(loaded_model, "config", None)
        elif isinstance(loaded_model, BookRecommender):
            engine, saved_config = getattr(loaded_model, "engine", None), getattr(loaded_model, "config", None)
        else:
            logger.warning("Refusing to load %s: unexpected artifact type %s.", path, type(loaded_model).__name__)
            return False

        problem = artifact_incompatibility(saved_config, self.config)
        if problem is None and engine is not None:
            problem = artifact_incompatibility(getattr(engine, "config", None), self.config)
        if problem is None:
            problem = _engine_integrity_problem(engine) if engine is not None else "artifact has no engine"
        if problem:
            logger.warning("Refusing to load model %s: %s. It must be retrained.", path, problem)
            return False

        if isinstance(loaded_model, RecommenderEngine):
            self.engine = loaded_model
            self.config = loaded_model.config
            self.is_fitted = True
            logger.info("Legacy RecommenderEngine artifact loaded from %s.", path)
            return True

        self.__dict__.update(loaded_model.__dict__)
        self.is_fitted = True
        logger.info(f"Model {self.config.model_version} loaded from {path}.")
        return True

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
        exclude: Optional[List[str]] = None,
    ) -> List[Dict[str, Any]]:
        """
        Generate personalized book recommendations with Rocchio relevance feedback,
        profile affinity fusion, and strict dislike suppression.

        `exclude` lists ISBNs (of any edition) that must not be returned, e.g. books already in
        the user's library. Unlike `dislikes` it carries no negative taste signal, and unlike a
        post-filter it is applied before ranking, so excluded books never use up result slots.
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

        # Validate the ISBN index once; the many lookups below reuse it.
        self.engine._isbn_lookup(validate=True)
        excluded_indices = self.engine.indices_for_isbns(exclude or [], validate=False)

        # Find all valid indices for seeds (handling duplicates and editions)
        seed_indices = []
        all_seed_indices = set()
        weights_by_idx: Dict[int, float] = {}
        for title in seed_titles:
            indices = self.engine.find_all_indices(title, validate=False)
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
                indices = self.engine.find_all_indices(d, validate=False)
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
            pop_books = self.get_popular_books(
                limit=top_n, exclude_indices=all_disliked_indices | excluded_indices,
                exclude_isbns=list(dislikes or []) + list(exclude or []),
            )
            for b in pop_books:
                if "recommendation_reason" not in b:
                    b["recommendation_reason"] = "Trending on Libris right now"
            return pop_books[:top_n]

        # Process semantic scores if provided
        semantic_vec = np.zeros(len(self.df))
        # Catalog rows that received a vector score (any edition); used only to label results.
        semantic_indices: set = set()
        if semantic_scores:
            for isbn, score in semantic_scores.items():
                indices = self.engine.find_all_indices(isbn, validate=False)
                for idx in indices:
                    semantic_vec[idx] = score
                    semantic_indices.add(idx)

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

        # Strict hard filter for ALL dislikes and caller exclusions (every edition)
        if all_disliked_indices:
            final_scores[list(all_disliked_indices)] = -1.0
        if excluded_indices:
            final_scores[list(excluded_indices)] = -1.0

        if use_diversity:
            # Maximal Marginal Relevance (MMR) for diversity
            recs = self._get_diverse_recommendations(final_scores, top_n)
        else:
            # Deterministic top-N recommendations excluding suppressed candidates
            suppressed = all_seed_indices | all_disliked_indices | excluded_indices
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
            seen_works = set()
            for idx in sorted_indices:
                row = self.df.iloc[idx]
                isbn = normalize_isbn(row.get("isbn13", ""))
                work = _row_identity(row)
                if (isbn and isbn in seen_isbns) or work in seen_works:
                    continue
                if isbn:
                    seen_isbns.add(isbn)
                seen_works.add(work)
                top_indices.append(idx)
                if len(top_indices) >= top_n:
                    break

            recs = self.df.iloc[top_indices].to_dict(orient="records")
            for i, rec in enumerate(recs):
                rec["final_score"] = float(final_scores[top_indices[i]])

        # Strict post-filter safeguard against dislikes, seeds and exclusions. Rows are matched by
        # ISBN (any edition) and by work identity, never by title alone: two different books can
        # share a title ("The Complete Stories" by Hurston and by O'Connor).
        blocked_rows = all_disliked_indices | all_seed_indices | excluded_indices
        blocked_isbns = {normalize_isbn(x) for x in list(dislikes or []) + list(seed_titles) + list(exclude or [])}
        blocked_works = set()
        for b_idx in blocked_rows:
            row = self.df.iloc[b_idx]
            blocked_works.add(_row_identity(row))
            for part in str(row.get("edition_isbns", "") or "").split("|") + [str(row.get("isbn13", ""))]:
                if normalize_isbn(part):
                    blocked_isbns.add(normalize_isbn(part))
        blocked_isbns.discard("")
        if blocked_isbns or blocked_works:
            recs = [
                r
                for r in recs
                if normalize_isbn(r.get("isbn13", "")) not in blocked_isbns
                and _row_identity(r) not in blocked_works
            ]

        # Add explanations
        for rec in recs:
            rec_idx = self.engine.find_index(rec.get("isbn13", ""), validate=False)
            rec["raw_similarity_score"] = float(raw_scores[rec_idx]) if rec_idx is not None else 0.0
            rec.update(
                self._explain_recommendation(
                    rec,
                    seed_indices,
                    semantic_scores,
                    preferred_genres=preferred_genres,
                    preferred_authors=preferred_authors,
                    seed_sources=seed_sources,
                    semantic_indices=semantic_indices,
                )
            )

        return recs[:top_n]

    def _get_diverse_recommendations(self, scores: np.ndarray, top_n: int) -> List[Dict[str, Any]]:
        """Select diverse recommendations using Maximal Marginal Relevance (MMR) with candidate deduplication."""
        # Exclude suppressed/negative items from candidate pool
        valid_indices = [int(i) for i in np.argsort(scores)[::-1] if scores[i] > -0.5]
        candidate_indices = valid_indices[: max(100, top_n * 10)]

        if not candidate_indices:
            return []
        # Relevance is rescaled by the best candidate's score so it shares the [0, 1] range of
        # the cosine-similarity penalty; otherwise lambda's effect depends on the score scale.
        top_score = float(scores[candidate_indices[0]])
        relevance = scores / top_score if top_score > 1e-9 else scores

        selected_indices = []
        seen_isbns = set()
        seen_works = set()

        def _is_duplicate_book(idx: int) -> bool:
            row = self.df.iloc[idx]
            isbn = normalize_isbn(row.get("isbn13", ""))
            return bool(isbn and isbn in seen_isbns) or _row_identity(row) in seen_works

        def _record_book(idx: int) -> None:
            row = self.df.iloc[idx]
            isbn = normalize_isbn(row.get("isbn13", ""))
            if isbn:
                seen_isbns.add(isbn)
            seen_works.add(_row_identity(row))

        # Candidate-candidate similarities are computed once (<= ~100x100) instead of one sparse
        # cosine call per candidate per step (~1,000 calls for top_n=10): same values, same
        # selection rule and tie-breaking. Live audit: similar-books p50 was ~1.3 s in-process.
        pos = {idx: i for i, idx in enumerate(candidate_indices)}
        pair_sim = cosine_similarity(self.tfidf_matrix[candidate_indices])
        max_sim_to_selected = np.zeros(len(candidate_indices))

        def _select(idx: int) -> None:
            nonlocal max_sim_to_selected
            selected_indices.append(idx)
            _record_book(idx)
            candidate_indices.remove(idx)
            max_sim_to_selected = np.maximum(max_sim_to_selected, pair_sim[pos[idx]])

        for idx in list(candidate_indices):
            if not _is_duplicate_book(idx):
                _select(idx)
                break

        lam = self.config.diversity_lambda
        while len(selected_indices) < top_n and candidate_indices:
            max_mmr = -np.inf
            best_candidate_idx = -1

            for cand_idx in candidate_indices:
                if _is_duplicate_book(cand_idx):
                    continue
                sim_to_selected = max_sim_to_selected[pos[cand_idx]] if selected_indices else 0.0
                mmr = (lam * relevance[cand_idx]) - ((1 - lam) * sim_to_selected)
                if mmr > max_mmr:
                    max_mmr = mmr
                    best_candidate_idx = cand_idx

            if best_candidate_idx != -1:
                _select(best_candidate_idx)
            else:
                break  # No more candidates to add

        recs = self.df.iloc[selected_indices].to_dict(orient="records")
        # Add scores and diversity penalty for transparency
        sel_pos = [pos[i] for i in selected_indices]
        for idx, rec in zip(selected_indices, recs):
            sim_to_selected = float(pair_sim[pos[idx], sel_pos].max()) if sel_pos else 0.0
            rec["final_score"] = float(scores[idx])
            rec["diversity_penalty"] = float((1 - lam) * sim_to_selected)
        return recs[:top_n]

    def _explain_recommendation(
        self,
        recommended_book: Dict[str, Any],
        seed_indices: List[int],
        semantic_scores: Optional[Dict[str, float]] = None,
        preferred_genres: Optional[List[str]] = None,
        preferred_authors: Optional[List[str]] = None,
        seed_sources: Optional[Dict[str, str]] = None,
        semantic_indices: Optional[set] = None,
    ) -> Dict[str, str]:
        """
        Generate an explainability payload and natural reasoning for a recommendation.

        `semantic_indices` holds the catalog rows that received a vector score in this request
        (recommend() passes it). A book is called a semantic match only if its row is in it, so a
        book that ranked on popularity alone is never described as matching the search.
        """
        rec_idx = self.engine.find_index(recommended_book["isbn13"], validate=False)
        if rec_idx is None:
            return {}

        if semantic_indices is not None:
            has_semantic_match = rec_idx in semantic_indices
        else:
            isbn = normalize_isbn(recommended_book.get("isbn13", ""))
            has_semantic_match = bool(semantic_scores) and isbn in {normalize_isbn(k) for k in semantic_scores}

        # Catalog order, not set order, so the explanation text is the same on every run.
        cat_list = list(dict.fromkeys(
            c for c in re.split(r"\s*[,|]\s*", str(recommended_book.get("categories", "")).lower()) if c
        ))

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
            # No seeds: the book either received a vector score (a semantic match), or it ranked
            # on the profile / popularity terms. Only the first is described as matching the search.
            # confidence / is_cold_start keep their previous values: they describe the user's
            # evidence (none without seeds), not the match.
            if has_semantic_match:
                if cat_list:
                    explanation = f"Bu kitap, aramanız için anlamsal arama sonuçlarında yer aldı ve {cat_list[0]} kategorisinde."
                else:
                    explanation = "Bu kitap, aramanız için anlamsal arama sonuçlarında yer aldı."
                # A vector score only means the book is among the nearest neighbours (the RPC threshold is
                # 0.0), so the label says "found by semantic search", never "matches".
                reason, explanation_type = "Found by semantic search", "semantic_match"
            elif preferred_genres or preferred_authors:
                explanation = "Bu kitap, belirttiğiniz okuma tercihleri doğrultusunda seçildi."
                reason, explanation_type = "Curated based on your taste profile", "category_affinity"
            else:
                explanation = "Bu kitap, Libris genelindeki popüler ve yüksek puanlı eserler arasından seçildi."
                reason, explanation_type = "Popular with Libris readers", "trending_catalog"
            return {
                "explanation": explanation,
                "explanation_source_book": "",
                "recommendation_reason": reason,
                "explanation_type": explanation_type,
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
            # A signed-in user's library seeds (seed_sources) or explicit preferences are a real profile.
            if preferred_genres or preferred_authors or seed_sources:
                return {
                    "explanation": "Bu kitap, genel okuma profiliniz ve beğenileriniz doğrultusunda önerildi.",
                    "explanation_source_book": "",
                    "recommendation_reason": "Curated based on your taste profile",
                    "explanation_type": "category_affinity",
                    "confidence": "medium",
                    "is_cold_start": False,
                }
            # Not similar to the seed and no profile to point to: it ranked on popularity, so say so
            # rather than claiming a taste profile the user never provided.
            return {
                "explanation": "Bu kitap, Libris genelindeki popüler ve yüksek puanlı eserler arasından seçildi.",
                "explanation_source_book": "",
                "recommendation_reason": "Popular with Libris readers",
                "explanation_type": "trending_catalog",
                "confidence": "medium",
                "is_cold_start": False,
            }

        most_similar_seed_idx = seed_indices[np.argmax(sim_scores)]
        source_book = self.df.iloc[most_similar_seed_idx]
        source_cats = set(re.split(r"\s*[,|]\s*", str(source_book.get("categories", "")).lower()))
        # In the recommended book's catalog order: a set intersection made the named genre depend
        # on PYTHONHASHSEED, so the same request could explain itself differently per process.
        common_genres = [c for c in cat_list if c in source_cats]

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
                    explanation = f"Anlamsal arama sonuçlarında yer aldı; ayrıca {verb_tr} '{source_book['title']}' kitabıyla ortak ({common_genres[0]}) türünde olduğu için önerildi."
                else:
                    explanation = f"Anlamsal arama sonuçlarında yer aldı ve okuma geçmişinizdeki '{source_book['title']}' kitabına benzer bir atmosfere sahip."
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

    LEXICAL_SEARCH_MAX_LIMIT = 50

    def lexical_search(
        self, query: str, limit: int = 10, exclude: Optional[List[str]] = None
    ) -> List[Dict[str, Any]]:
        """
        Ranks the catalog by TF-IDF cosine to a free-text query. This is RAG's fallback when
        vector search is unavailable. The catalog text is English, so lexical matching cannot
        bridge Turkish or German queries; on the provisional offline labels the English scores
        were clearly higher than the Turkish/German ones, and callers should not rely on it for
        non-English queries.

        `limit` is capped at LEXICAL_SEARCH_MAX_LIMIT. `exclude` (ISBNs of any edition) is
        applied while ranking, so excluded books do not consume result slots and callers do not
        need to over-fetch by the size of a user's library.
        """
        if not self.is_fitted or self.engine.tfidf_vectorizer is None:
            return []
        text = clean_text(query)
        if not text:
            return []
        limit = max(1, min(int(limit), self.LEXICAL_SEARCH_MAX_LIMIT))
        excluded = self.engine.indices_for_isbns(exclude or [])
        scores = cosine_similarity(
            self.engine.tfidf_vectorizer.transform([text]), self.tfidf_matrix
        ).ravel()
        books: List[Dict[str, Any]] = []
        for idx in np.argsort(-scores):
            if scores[idx] <= 0 or len(books) >= limit:
                break
            if int(idx) in excluded:
                continue
            book = self.df.iloc[int(idx)].to_dict()
            book["similarity_score"] = float(scores[idx])
            books.append(book)
        return books

    def edition_isbns(self, isbns: Iterable[str]) -> Set[str]:
        """
        Every normalised ISBN of every catalog work that carries one of `isbns` on any edition,
        plus the given ISBNs themselves (so books missing from the catalog still match exactly).
        """
        out = {normalize_isbn(i) for i in isbns or []}
        for idx in self.engine.indices_for_isbns(isbns or []):
            row = self.df.iloc[idx]
            for part in str(row.get("edition_isbns", "") or "").split("|") + [str(row.get("isbn13", ""))]:
                out.add(normalize_isbn(part))
        out.discard("")
        return out

    def search_books(self, query: str, limit: int = 10) -> List[Dict[str, Any]]:
        """Search for books by title, author, or description."""
        if not self.is_fitted:
            return []

        # A simple search implementation: check for query in combined features
        # A more robust search would use a dedicated search index or more advanced matching.
        mask = self.df["combined_features"].str.contains(query, case=False, na=False, regex=False)
        results = self.df[mask].head(limit)
        return results.to_dict(orient="records")

    def get_popular_books(
        self,
        limit: int = 10,
        exclude_indices: Optional[Set[int]] = None,
        exclude_isbns: Optional[List[str]] = None,
    ) -> List[Dict[str, Any]]:
        """
        Most popular books by the pre-calculated popularity score, one per work. Deduplication is
        by ISBN and work identity (title + first-author surname), not by title alone, so distinct
        books that share a title are both eligible.
        """
        if self.df.empty:
            return []
        excluded = set(exclude_indices or ())
        if exclude_isbns:
            excluded |= self.engine.indices_for_isbns(exclude_isbns)
        blocked_isbns = {normalize_isbn(i) for i in exclude_isbns or []} - {""}
        sorted_df = self.df.sort_values(by="popularity_score", ascending=False, kind="stable")
        picked: List[int] = []
        seen_isbns, seen_works = set(), set()
        col = lambda name: sorted_df[name].tolist() if name in sorted_df.columns else [""] * len(sorted_df)  # noqa: E731
        for idx, raw_isbn, title, authors in zip(sorted_df.index, col("isbn13"), col("title"), col("authors")):
            if idx in excluded:
                continue
            isbn = normalize_isbn(raw_isbn)
            work = work_id(title, authors)
            if (isbn and (isbn in seen_isbns or isbn in blocked_isbns)) or work in seen_works:
                continue
            seen_isbns.add(isbn)
            seen_works.add(work)
            picked.append(idx)
            if len(picked) >= limit:
                break
        books = self.df.loc[picked].to_dict(orient="records")
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
                df = df[title_mask | author_mask | desc_mask | isbn13_mask | isbn10_mask].copy()
                # Relevance tiers: exact title > title > author/ISBN > description-only.
                title_lower = df["title"].astype(str).str.strip().str.lower()
                q_lower = q_clean.lower()
                relevance = pd.Series(1, index=df.index)
                relevance = relevance.mask(_optional_column_contains(df, "isbn13", q_clean), 3)
                relevance = relevance.mask(_optional_column_contains(df, "isbn10", q_clean), 3)
                relevance = relevance.mask(
                    df["authors"].astype(str).str.contains(q_clean, case=False, na=False, regex=False), 3
                )
                relevance = relevance.mask(title_lower.str.contains(q_lower, na=False, regex=False), 4)
                relevance = relevance.mask(title_lower == q_lower, 5)
                df["_relevance"] = relevance

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

        if "_relevance" in df.columns and (not sort or sort == "popularity"):
            # With a search query, the default ordering is relevance first, then popularity.
            by = ["_relevance"] + (["popularity_score"] if "popularity_score" in df.columns else [])
            df = df.sort_values(by=by, ascending=False, na_position="last", kind="stable")
        elif sort:
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

        paginated_df = df.iloc[start:end].drop(columns=["_relevance"], errors="ignore")
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

    def find_book_by_title_author(self, title: str, authors: str) -> Optional[Dict[str, Any]]:
        """Case-insensitive exact title match whose authors contain the given first author."""
        if self.df.empty or not (title or "").strip():
            return None
        t = title.strip().lower()
        first_author = (authors or "").split(",")[0].strip().lower()
        same_title = self.df[self.df["title"].astype(str).str.strip().str.lower() == t]
        if first_author:
            same_title = same_title[
                same_title["authors"].astype(str).str.lower().str.contains(first_author, regex=False, na=False)
            ]
        return same_title.iloc[0].to_dict() if not same_title.empty else None

    def add_book(self, book: Dict[str, Any]) -> Dict[str, Any]:
        """
        Appends a contributed book to the in-memory catalog so it can be browsed and searched
        right away, keeping the TF-IDF matrix aligned with the catalog rows.
        """
        row = preprocess_dataframe(pd.DataFrame([book]))
        row["popularity_score"] = 0.0  # contributions never jump ahead of established books
        base = self.engine.df if self.engine.df is not None else pd.DataFrame()
        engine = self.engine
        matrix = getattr(engine, "tfidf_matrix", None)
        vectorizer = getattr(engine, "tfidf_vectorizer", None)
        # Scoring assumes catalog rows and TF-IDF rows are aligned 1:1, so the new row gets
        # its vector from the already-fitted vectorizer (no retraining needed).
        if matrix is not None and vectorizer is not None and matrix.shape[0] == len(base):
            from scipy.sparse import vstack

            engine.tfidf_matrix = vstack([matrix, vectorizer.transform(row["combined_features"])]).tocsr()
        engine.df = pd.concat([base, row], ignore_index=True)
        return row.iloc[0].to_dict()

    def get_book_by_isbn(self, isbn: str) -> Optional[Dict[str, Any]]:
        """Retrieve a single book by its ISBN13."""
        if self.df.empty:
            return None
        book_df = self.df[self.df["isbn13"] == isbn]
        if not book_df.empty:
            return book_df.iloc[0].to_dict()
        return None
