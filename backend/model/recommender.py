"""
BookRecommender — Production-grade TF-IDF recommendation engine.

Architecture overview:
─────────────────────
    Query: "Dune"
      │
      ▼
    ┌───────────────────────────────┐
    │  Title Resolution             │  Exact → Fuzzy → Semantic fallback
    │  (3-tier matching)            │
    └───────────┬───────────────────┘
                │  book_idx
                ▼
    ┌───────────────────────────────┐
    │  Candidate Retrieval          │  cosine_sim[book_idx] → top 4×N pool
    │  (precomputed O(1) lookup)    │
    └───────────┬───────────────────┘
                │  [(idx, sim), ...]
                ▼
    ┌───────────────────────────────┐
    │  Multi-Signal Scoring         │  content × 0.55
    │  (hybrid re-ranking)          │  + popularity × 0.20
    │                               │  + rating × 0.10
    │                               │  + genre_boost × 0.10
    │                               │  + recency × 0.05
    └───────────┬───────────────────┘
                │  ranked candidates
                ▼
    ┌───────────────────────────────┐
    │  Diversity Filter             │  Max 2 per author
    │  (anti-redundancy)            │  Max 3 per category
    └───────────┬───────────────────┘
                │
                ▼
    Top-N results with explanation metadata

Design decisions:
  • Full cosine-sim matrix in memory: O(n²) space, O(1) lookup.
    Viable up to ~50k books on 2 GB RAM.
  • Multi-signal hybrid scoring replaces the old 3-weight formula
    with 5 signals including genre affinity and recency.
  • Diversity filter prevents "all Harry Potter" or "all Tolkien"
    results by capping per-author and per-category slots.
  • 3-tier title matching: exact → fuzzy (difflib) → TF-IDF vector
    similarity, so typos like "Duen" still find "Dune".
  • Model versioning in pickle prevents stale-model crashes.
  • Thread-safe: no mutable state after fit().

Author: Libris Engine
"""

import hashlib
import logging
import math
import os
import pickle
import threading
import time
from dataclasses import dataclass, field
from difflib import SequenceMatcher
from functools import lru_cache
from typing import Any, Dict, List, Optional, Tuple

import numpy as np
import pandas as pd
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity

from utils.preprocess import preprocess_dataframe

logger = logging.getLogger(__name__)

# ═════════════════════════════════════════════════════════════════════════════
# Configuration
# ═════════════════════════════════════════════════════════════════════════════

MODEL_VERSION = "2.0.0"

@dataclass(frozen=True)
class ScoringWeights:
    """Hybrid scoring coefficients — must sum to 1.0."""
    content:    float = 0.45   # TF-IDF cosine similarity
    popularity: float = 0.15   # log-normalised ratings_count
    rating:     float = 0.10   # normalised average_rating
    genre:      float = 0.15   # category overlap bonus
    page_count: float = 0.10   # affinity to user's preferred book length
    recency:    float = 0.05   # newer books get slight boost

    def __post_init__(self):
        total = self.content + self.popularity + self.rating + self.genre + self.page_count + self.recency
        if abs(total - 1.0) > 1e-6:
            raise ValueError(f"Weights must sum to 1.0, got {total:.4f}")


@dataclass(frozen=True)
class DiversityConfig:
    """Caps to prevent result dominated by one author/category."""
    max_per_author:   int = 2
    max_per_category: int = 3


@dataclass(frozen=True)
class EngineConfig:
    """All tunable engine parameters in one place."""
    # TF-IDF
    max_features:   int   = 10_000
    ngram_range:    tuple = (1, 2)
    max_df:         float = 0.90
    min_df:         int   = 1
    sublinear_tf:   bool  = True

    # Matching
    fuzzy_threshold:    float = 0.55   # min SequenceMatcher ratio
    semantic_threshold: float = 0.10   # min TF-IDF vector similarity

    # Scoring
    weights:   ScoringWeights = field(default_factory=ScoringWeights)
    diversity: DiversityConfig = field(default_factory=DiversityConfig)

    # Candidate pool multiplier (pool = top_n × this)
    pool_multiplier: int = 5


# ═════════════════════════════════════════════════════════════════════════════
# Engine
# ═════════════════════════════════════════════════════════════════════════════

class BookRecommender:
    """
    Content-based book recommender with multi-signal hybrid scoring
    and diversity-aware re-ranking.

    Thread-safe after fit() — all mutable state is set during training
    and only read afterwards.
    """

    def __init__(self, config: Optional[EngineConfig] = None) -> None:
        self.config = config or EngineConfig()

        # ── Data ──────────────────────────────────────────────────────────────
        self.df: Optional[pd.DataFrame] = None

        # ── TF-IDF artefacts ──────────────────────────────────────────────────
        self.vectorizer:  Optional[TfidfVectorizer] = None
        self.tfidf_matrix = None                         # sparse CSR matrix
        self.cosine_sim:  Optional[np.ndarray] = None    # dense n×n

        # ── Fast lookup indices ───────────────────────────────────────────────
        self._title_to_idx:  Dict[str, int] = {}         # lower(title) → row
        self._isbn_to_idx:   Dict[str, int] = {}         # isbn13 → row
        self._category_sets: Optional[pd.Series] = None  # row → set of cats

        # ── Precomputed normalisation constants ───────────────────────────────
        self._max_log_ratings: float = 1.0
        self._max_rating:     float = 5.0
        self._max_year:       int = 2026
        self._min_year:       int = 1800

        # ── State ─────────────────────────────────────────────────────────────
        self.is_fitted: bool = False
        self._lock = threading.RLock()
        self._model_metadata: Dict[str, Any] = {}

    # ─────────────────────────────────────────────────────────────────────────
    # 1. DATA LOADING
    # ─────────────────────────────────────────────────────────────────────────

    def load_data(self, data_path: str) -> None:
        """Load CSV and run the full preprocessing pipeline."""
        logger.info("Loading dataset from %s", data_path)
        raw = pd.read_csv(data_path, encoding="utf-8")
        logger.info("Raw dataset: %d rows", len(raw))
        self.df = preprocess_dataframe(raw)
        
        # Senior Upgrade: Filter out books with missing critical data (page_count) as requested
        before_count = len(self.df)
        self.df = self.df[self.df["page_count"] > 0].reset_index(drop=True)
        dropped = before_count - len(self.df)
        logger.info("Filtered out %d books with missing page_count. Remaining: %d", dropped, len(self.df))

    def load_from_supabase(self, client: Any) -> None:
        """Fetch all books from Supabase 'books' table."""
        logger.info("Fetching all books from Supabase...")
        
        all_data = []
        page_size = 1000
        offset = 0
        
        while True:
            resp = client.table("books").select("*").range(offset, offset + page_size - 1).execute()
            if not resp.data:
                break
            all_data.extend(resp.data)
            if len(resp.data) < page_size:
                break
            offset += page_size
            
        if not all_data:
            raise ValueError("Supabase 'books' table is empty. Migration failed?")
            
        logger.info("Fetched %d books from Supabase", len(all_data))
        raw = pd.DataFrame(all_data)
        self.df = preprocess_dataframe(raw)

        # Senior Upgrade: Filter out books with missing critical data (page_count)
        before_count = len(self.df)
        self.df = self.df[self.df["page_count"] > 0].reset_index(drop=True)
        dropped = before_count - len(self.df)
        logger.info("Filtered out %d books with missing page_count. Remaining: %d", dropped, len(self.df))

    # ─────────────────────────────────────────────────────────────────────────
    # 2. TRAINING
    # ─────────────────────────────────────────────────────────────────────────

    def fit(self, save_path: Optional[str] = None) -> None:
        """
        Full training pipeline:
        1. Fit TF-IDF vectorizer
        2. Compute full cosine-similarity matrix
        3. Build lookup indices
        4. Precompute normalisation constants
        5. Optionally save to disk
        """
        if self.df is None:
            raise ValueError("No data loaded. Call load_data() first.")

        t0 = time.perf_counter()
        n = len(self.df)
        cfg = self.config

        # ── Step 1: TF-IDF ────────────────────────────────────────────────────
        logger.info("Fitting TF-IDF on %d books (max_features=%d, ngrams=%s)…",
                     n, cfg.max_features, cfg.ngram_range)

        self.vectorizer = TfidfVectorizer(
            max_features=cfg.max_features,
            ngram_range=cfg.ngram_range,
            stop_words="english",
            min_df=cfg.min_df,
            max_df=cfg.max_df,
            sublinear_tf=cfg.sublinear_tf,
            analyzer="word",
        )
        self.tfidf_matrix = self.vectorizer.fit_transform(self.df["combined_features"])
        logger.info("TF-IDF matrix: %s  (vocab=%d)",
                     self.tfidf_matrix.shape, len(self.vectorizer.vocabulary_))

        # ── Step 2: Cosine similarity ─────────────────────────────────────────
        logger.info("Computing %d×%d cosine-similarity matrix…", n, n)
        self.cosine_sim = cosine_similarity(self.tfidf_matrix)

        # ── Step 3: Lookup indices ────────────────────────────────────────────
        self._build_indices()

        # ── Step 4: Normalisation constants ───────────────────────────────────
        self._precompute_norms()

        # ── Done ──────────────────────────────────────────────────────────────
        self.is_fitted = True
        elapsed = time.perf_counter() - t0

        self._model_metadata = {
            "version": MODEL_VERSION,
            "n_books": n,
            "n_features": self.tfidf_matrix.shape[1],
            "trained_at": time.strftime("%Y-%m-%d %H:%M:%S"),
            "training_time_s": round(elapsed, 2),
            "data_hash": self._data_fingerprint(),
            "config": {
                "max_features": cfg.max_features,
                "ngram_range": cfg.ngram_range,
                "weights": {
                    "content": cfg.weights.content,
                    "popularity": cfg.weights.popularity,
                    "rating": cfg.weights.rating,
                    "genre": cfg.weights.genre,
                    "recency": cfg.weights.recency,
                },
            },
        }

        logger.info("Training complete in %.2fs — %d books, %d features",
                     elapsed, n, self.tfidf_matrix.shape[1])

        if save_path:
            self._save(save_path)

    def _build_indices(self) -> None:
        """Build fast O(1) lookup dicts from the dataframe."""
        # Title → index (lowercase, stripped)
        self._title_to_idx = {}
        for idx, title in enumerate(self.df["title"]):
            key = str(title).lower().strip()
            if key not in self._title_to_idx:   # keep first occurrence
                self._title_to_idx[key] = idx

        # ISBN → index
        self._isbn_to_idx = {}
        for idx, isbn in enumerate(self.df["isbn13"]):
            key = str(isbn).strip()
            if key and key != "nan":
                self._isbn_to_idx[key] = idx

        # Category sets for genre-boost scoring
        self._category_sets = self.df["categories"].apply(
            lambda c: frozenset(
                cat.strip().lower()
                for cat in str(c).split("|") if cat.strip()
            ) if pd.notna(c) else frozenset()
        )

        logger.info("Indices built: %d titles, %d ISBNs",
                     len(self._title_to_idx), len(self._isbn_to_idx))

    def _precompute_norms(self) -> None:
        """Cache normalisation constants once so scoring is O(1) per book."""
        max_rc = self.df["ratings_count"].max()
        self._max_log_ratings = math.log1p(float(max_rc)) if max_rc > 0 else 1.0
        self._max_rating = max(float(self.df["average_rating"].max()), 1.0)

        years = self.df["year"] if "year" in self.df.columns else pd.Series([0])
        valid_years = years[years > 0]
        self._min_year = int(valid_years.min()) if len(valid_years) else 1800
        self._max_year = int(valid_years.max()) if len(valid_years) else 2026

    def _data_fingerprint(self) -> str:
        """Quick hash of the dataset for cache invalidation."""
        sample = self.df["title"].str.cat(sep="|")
        return hashlib.md5(sample.encode("utf-8", errors="replace")).hexdigest()[:12]

    # ─────────────────────────────────────────────────────────────────────────
    # 3. PERSISTENCE
    # ─────────────────────────────────────────────────────────────────────────

    def _save(self, path: str) -> None:
        """Serialize all artefacts to a versioned pickle."""
        os.makedirs(os.path.dirname(path) or ".", exist_ok=True)

        payload = {
            "__version__":    MODEL_VERSION,
            "metadata":       self._model_metadata,
            "vectorizer":     self.vectorizer,
            "tfidf_matrix":   self.tfidf_matrix,
            "cosine_sim":     self.cosine_sim,
            "df":             self.df,
            "config":         self.config,
        }

        with open(path, "wb") as fh:
            pickle.dump(payload, fh, protocol=pickle.HIGHEST_PROTOCOL)

        size_kb = os.path.getsize(path) / 1024
        logger.info("Model saved → %s (%.0f KB)", path, size_kb)

    def load_model(self, path: str) -> bool:
        """
        Load pre-trained artefacts from disk.

        Returns True on success, False if file missing or incompatible.
        Handles both old (v1) and new (v2) pickle formats gracefully.
        """
        if not os.path.exists(path):
            return False

        try:
            with open(path, "rb") as fh:
                data = pickle.load(fh)

            # ── Version check ─────────────────────────────────────────────────
            saved_version = data.get("__version__", "1.0.0")
            major_saved = int(saved_version.split(".")[0])
            major_current = int(MODEL_VERSION.split(".")[0])

            if major_saved < major_current:
                logger.warning(
                    "Pickle is v%s but engine is v%s — retraining recommended.",
                    saved_version, MODEL_VERSION,
                )

            # ── Load artefacts ────────────────────────────────────────────────
            self.vectorizer   = data["vectorizer"]
            self.tfidf_matrix = data["tfidf_matrix"]
            self.cosine_sim   = data["cosine_sim"]
            self.df           = data["df"]

            # v2 pickles include config; v1 don't
            if "config" in data:
                self.config = data["config"]

            # v2 pickles include metadata
            self._model_metadata = data.get("metadata", {})

            # Rebuild indices (not stored in pickle to save space)
            self._build_indices()
            self._precompute_norms()

            self.is_fitted = True
            logger.info(
                "Model loaded from %s (v%s, %d books, trained %s)",
                path, saved_version, len(self.df),
                self._model_metadata.get("trained_at", "unknown"),
            )
            return True

        except Exception as exc:
            logger.error("Failed to load model from %s: %s", path, exc)
            return False

    @property
    def metadata(self) -> Dict[str, Any]:
        """Public access to model metadata for API responses."""
        return {
            **self._model_metadata,
            "is_fitted": self.is_fitted,
            "n_books": len(self.df) if self.df is not None else 0,
        }

    # ─────────────────────────────────────────────────────────────────────────
    # 4. TITLE RESOLUTION (3-Tier Matching)
    # ─────────────────────────────────────────────────────────────────────────

    def _find_index(self, title: str) -> Optional[int]:
        """
        Resolve a title string to a row index with 3-tier fallback:

        Tier 1 — Exact match (O(1) dict lookup)
        Tier 2 — Fuzzy match via SequenceMatcher (handles typos)
        Tier 3 — Semantic match via TF-IDF vector similarity
        """
        key = title.lower().strip()

        # ── Tier 1: Exact match ───────────────────────────────────────────────
        if key in self._title_to_idx:
            return self._title_to_idx[key]

        # Also try substring match (e.g. "Dune" matches "Dune (Dune Chronicles)")
        for stored_title, idx in self._title_to_idx.items():
            if key in stored_title or stored_title in key:
                return idx

        # ── Tier 2: Fuzzy match ───────────────────────────────────────────────
        best_ratio = 0.0
        best_idx = None
        for stored_title, idx in self._title_to_idx.items():
            ratio = SequenceMatcher(None, key, stored_title).ratio()
            if ratio > best_ratio:
                best_ratio = ratio
                best_idx = idx

        if best_ratio >= self.config.fuzzy_threshold:
            matched = self.df.iloc[best_idx]["title"]
            logger.info("Fuzzy matched '%s' → '%s' (%.0f%% match)",
                        title, matched, best_ratio * 100)
            return best_idx

        # ── Tier 3: Semantic match via TF-IDF ─────────────────────────────────
        if self.vectorizer is not None:
            try:
                query_vec = self.vectorizer.transform([key])
                sims = cosine_similarity(query_vec, self.tfidf_matrix).flatten()
                best_semantic_idx = int(np.argmax(sims))
                best_semantic_sim = float(sims[best_semantic_idx])

                if best_semantic_sim >= self.config.semantic_threshold:
                    matched = self.df.iloc[best_semantic_idx]["title"]
                    logger.info("Semantic matched '%s' → '%s' (sim=%.3f)",
                                title, matched, best_semantic_sim)
                    return best_semantic_idx
            except Exception as exc:
                logger.debug("Semantic matching failed: %s", exc)

        logger.warning("Book not found in any tier: '%s'", title)
        return None

    # ─────────────────────────────────────────────────────────────────────────
    # 5. RECOMMENDATION ENGINE
    # ─────────────────────────────────────────────────────────────────────────

    def recommend(
        self,
        book_title: str,
        top_n: int = 10,
        use_hybrid: bool = True,
        use_diversity: bool = True,
    ) -> List[Dict[str, Any]]:
        """
        Return top-N recommendations for a book title.

        Pipeline:
        1. Resolve title → index (3-tier)
        2. Retrieve candidate pool from cosine-sim matrix
        3. Score with multi-signal hybrid formula
        4. Apply diversity filter
        5. Return enriched results with explanation metadata
        """
        self._ensure_fitted()

        book_idx = self._find_index(book_title)
        if book_idx is None:
            return []

        source_book = self.df.iloc[book_idx]
        source_title = str(source_book["title"])
        source_cats = self._category_sets.iloc[book_idx] if self._category_sets is not None else frozenset()

        logger.info("Generating recommendations for '%s' (idx=%d)", source_title, book_idx)

        # ── Candidate retrieval ───────────────────────────────────────────────
        pool_size = top_n * self.config.pool_multiplier
        raw_scores = self.cosine_sim[book_idx]

        # Get top candidates (excluding self)
        candidate_indices = np.argsort(raw_scores)[::-1]
        candidates = [
            (int(i), float(raw_scores[i]))
            for i in candidate_indices
            if i != book_idx
        ][:pool_size]

        # ── Scoring ───────────────────────────────────────────────────────────
        if use_hybrid:
            scored = self._multi_signal_score(candidates, source_cats)
        else:
            scored = candidates

        # ── Diversity filter ──────────────────────────────────────────────────
        if use_diversity:
            scored = self._apply_diversity(scored, top_n)
        else:
            scored = scored[:top_n]

        # ── Build results ─────────────────────────────────────────────────────
        results: List[Dict[str, Any]] = []
        for rank, (row_idx, score) in enumerate(scored, 1):
            book_dict = self._row_to_dict(self.df.iloc[row_idx])
            book_dict["similarity_score"] = round(score, 4)
            book_dict["rank"] = rank

            # Explanation: why was this recommended?
            content_sim = float(raw_scores[row_idx])
            book_dict["_explanation"] = {
                "content_similarity": round(content_sim, 4),
                "matched_source": source_title,
                "match_type": "hybrid" if use_hybrid else "content_only",
            }

            results.append(book_dict)

        logger.info("Returned %d recommendations for '%s'", len(results), source_title)
        return results

    def recommend_multi(
        self,
        book_titles: List[str],
        top_n: int = 10,
        pref_page_count: Optional[int] = None,
        use_diversity: bool = True,
    ) -> List[Dict[str, Any]]:
        """
        Senior Upgrade: Recommend based on MULTIPLE seed books (e.g. user's favorites).
        Calculates the centroid of the seed vectors and finds similar items.
        """
        self._ensure_fitted()
        
        valid_indices = []
        source_titles = []
        all_source_cats = set()
        
        for title in book_titles:
            idx = self._find_index(title)
            if idx is not None:
                valid_indices.append(idx)
                source_titles.append(str(self.df.iloc[idx]["title"]))
                if self._category_sets is not None:
                    all_source_cats.update(self._category_sets.iloc[idx])
        
        if not valid_indices:
            logger.warning("No valid seed books found for multi-recommendation: %s", book_titles)
            return []
            
        logger.info("Generating multi-seed recommendations for: %s", source_titles)
        
        # 1. Calculate centroid vector
        seed_vectors = self.tfidf_matrix[valid_indices]
        centroid_vec = seed_vectors.mean(axis=0)
        
        # 2. Compute similarity of all books to this centroid
        # Convert centroid back to sparse if it's dense from mean()
        from scipy.sparse import issparse, csr_matrix
        if not issparse(centroid_vec):
            centroid_vec = csr_matrix(centroid_vec)
            
        raw_scores = cosine_similarity(centroid_vec, self.tfidf_matrix).flatten()
        
        # 3. Retrieve candidates (excluding seeds)
        candidate_indices = np.argsort(raw_scores)[::-1]
        pool_size = top_n * self.config.pool_multiplier
        
        candidates = []
        for i in candidate_indices:
            idx = int(i)
            if idx not in valid_indices:
                candidates.append((idx, float(raw_scores[idx])))
            if len(candidates) >= pool_size:
                break
                
        # 4. Multi-signal scoring
        scored = self._multi_signal_score(
            candidates, 
            frozenset(all_source_cats),
            pref_page_count=pref_page_count
        )
        
        # 5. Diversity
        if use_diversity:
            scored = self._apply_diversity(scored, top_n)
        else:
            scored = scored[:top_n]
            
        # 6. Build results
        results = []
        for rank, (row_idx, score) in enumerate(scored, 1):
            book_dict = self._row_to_dict(self.df.iloc[row_idx])
            book_dict["similarity_score"] = round(score, 4)
            book_dict["rank"] = rank
            book_dict["_explanation"] = {
                "content_similarity": round(float(raw_scores[row_idx]), 4),
                "matched_sources": source_titles,
                "match_type": "multi_seed_hybrid",
            }
            results.append(book_dict)
            
        return results

    def _multi_signal_score(
        self,
        candidates: List[Tuple[int, float]],
        source_categories: frozenset,
        pref_page_count: Optional[int] = None,
    ) -> List[Tuple[int, float]]:
        """
        6-signal hybrid re-ranking:
        
        score = w_content   × cosine_similarity
              + w_popularity × log_norm(ratings_count)
              + w_rating     × norm(average_rating)
              + w_genre      × category_overlap_ratio
              + w_page_count × length_affinity_score
              + w_recency    × year_norm
        """
        w = self.config.weights
        scored = []

        for idx, content_sim in candidates:
            row = self.df.iloc[idx]

            # Signal 1: Content similarity
            s_content = content_sim

            # Signal 2: Popularity
            rc = float(row["ratings_count"])
            s_popularity = math.log1p(rc) / self._max_log_ratings if rc > 0 else 0.0

            # Signal 3: Rating quality
            s_rating = float(row["average_rating"]) / self._max_rating

            # Signal 4: Genre affinity
            if self._category_sets is not None and source_categories:
                cand_cats = self._category_sets.iloc[idx]
                s_genre = 0.0
                if cand_cats:
                    intersection = len(source_categories & cand_cats)
                    union = len(source_categories | cand_cats)
                    s_genre = intersection / union if union > 0 else 0.0
            else:
                s_genre = 0.0

            # Signal 5: Page Count Affinity (Custom logic for preference)
            s_page_count = 1.0 # default neutral
            if pref_page_count and pref_page_count > 0:
                book_pages = int(row.get("page_count", 0))
                # Gaussian-like decay based on distance from preferred length
                diff = abs(book_pages - pref_page_count)
                # Sigma is 200 pages (half-width of preference)
                s_page_count = math.exp(-(diff**2) / (2 * (250**2)))

            # Signal 6: Recency
            year = int(row.get("year", 0)) if "year" in row.index else 0
            if year > 0 and self._max_year > self._min_year:
                s_recency = (year - self._min_year) / (self._max_year - self._min_year)
            else:
                s_recency = 0.5  # neutral if no year data

            # Combined
            final = (
                w.content      * s_content
                + w.popularity * s_popularity
                + w.rating     * s_rating
                + w.genre      * s_genre
                + w.page_count * s_page_count
                + w.recency    * s_recency
            )
            scored.append((idx, final))

        scored.sort(key=lambda x: x[1], reverse=True)
        return scored

    def _apply_diversity(
        self,
        scored: List[Tuple[int, float]],
        top_n: int,
    ) -> List[Tuple[int, float]]:
        """
        Greedily select top_n results while enforcing diversity caps.

        Prevents output like [HP1, HP2, HP3, HP4, HP5] by limiting
        how many books from the same author or category can appear.
        """
        cfg = self.config.diversity
        selected = []
        author_count: Dict[str, int] = {}
        category_count: Dict[str, int] = {}

        for idx, score in scored:
            if len(selected) >= top_n:
                break

            row = self.df.iloc[idx]
            author = str(row.get("authors", "")).lower().strip()
            primary_cat = str(row.get("categories", "")).split("|")[0].strip().lower()

            # Check author cap
            if author and author_count.get(author, 0) >= cfg.max_per_author:
                continue

            # Check category cap
            if primary_cat and category_count.get(primary_cat, 0) >= cfg.max_per_category:
                continue

            selected.append((idx, score))
            if author:
                author_count[author] = author_count.get(author, 0) + 1
            if primary_cat:
                category_count[primary_cat] = category_count.get(primary_cat, 0) + 1

        return selected

    # ─────────────────────────────────────────────────────────────────────────
    # 6. QUERY METHODS
    # ─────────────────────────────────────────────────────────────────────────

    def search_books(self, query: str, limit: int = 20) -> List[Dict[str, Any]]:
        """
        Full-text search across title, authors, and categories.

        Uses TF-IDF vector scoring for relevance ranking when exact
        substring matching returns too few results.
        """
        if self.df is None:
            return []

        q = query.lower().strip()

        # ── Primary: substring matching (fast, exact) ─────────────────────────
        mask = (
            self.df["title"].str.lower().str.contains(q, na=False, regex=False)
            | self.df["authors"].str.lower().str.contains(q, na=False, regex=False)
            | self.df["categories"].str.lower().str.contains(q, na=False, regex=False)
        )
        results = self.df[mask].copy()

        # Sort by relevance: title match first, then by popularity
        if not results.empty:
            results["_title_match"] = results["title"].str.lower().str.contains(
                q, na=False, regex=False
            ).astype(int)
            results = results.sort_values(
                ["_title_match", "ratings_count"],
                ascending=[False, False],
            ).head(limit)
            results = results.drop(columns=["_title_match"])
            return [self._row_to_dict(row) for _, row in results.iterrows()]

        # ── Fallback: TF-IDF semantic search ──────────────────────────────────
        if self.vectorizer is not None:
            try:
                query_vec = self.vectorizer.transform([q])
                sims = cosine_similarity(query_vec, self.tfidf_matrix).flatten()
                top_indices = np.argsort(sims)[::-1][:limit]
                return [
                    self._row_to_dict(self.df.iloc[i])
                    for i in top_indices
                    if sims[i] > 0.01  # minimum relevance threshold
                ]
            except Exception:
                pass

        return []

    def get_popular_books(self, limit: int = 20) -> List[Dict[str, Any]]:
        """
        Return books ranked by a composite popularity score.

        Formula: 0.65 × percentile_rank(ratings_count)
               + 0.35 × percentile_rank(average_rating)
        """
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
            return {
                "books": [], "total": 0, "page": page,
                "per_page": per_page, "total_pages": 0,
            }
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
        """O(1) lookup by ISBN using pre-built index."""
        if self.df is None:
            return None

        isbn_key = str(isbn).strip()
        idx = self._isbn_to_idx.get(isbn_key)

        if idx is not None:
            return self._row_to_dict(self.df.iloc[idx])

        # Fallback: brute-force scan (handles edge cases)
        mask = self.df["isbn13"].astype(str) == isbn_key
        row = self.df[mask]
        if row.empty:
            return None
        return self._row_to_dict(row.iloc[0])

    def get_similar_by_isbn(self, isbn: str, top_n: int = 5) -> List[Dict[str, Any]]:
        """Convenience: get recommendations starting from an ISBN."""
        book = self.get_book_by_isbn(isbn)
        if not book:
            return []
        return self.recommend(book["title"], top_n=top_n)

    # ─────────────────────────────────────────────────────────────────────────
    # 7. STATISTICS & INTROSPECTION
    # ─────────────────────────────────────────────────────────────────────────

    def get_stats(self) -> Dict[str, Any]:
        """Return engine statistics for monitoring / API health endpoints."""
        if not self.is_fitted or self.df is None:
            return {"status": "not_fitted"}

        return {
            "status": "ready",
            "model_version": MODEL_VERSION,
            "n_books": len(self.df),
            "n_features": self.tfidf_matrix.shape[1] if self.tfidf_matrix is not None else 0,
            "avg_rating": round(float(self.df["average_rating"].mean()), 2),
            "total_ratings": int(self.df["ratings_count"].sum()),
            "categories": sorted(
                set(
                    cat.strip()
                    for cats in self.df["categories"].dropna()
                    for cat in str(cats).split("|")
                    if cat.strip()
                )
            ),
            "top_authors": (
                self.df["authors"]
                .value_counts()
                .head(10)
                .to_dict()
            ),
            "trained_at": self._model_metadata.get("trained_at", "unknown"),
            "data_hash": self._model_metadata.get("data_hash", "unknown"),
        }

    def get_category_distribution(self) -> Dict[str, int]:
        """Count books per category — useful for frontend filters."""
        if self.df is None:
            return {}
        cats: Dict[str, int] = {}
        for raw in self.df["categories"].dropna():
            for cat in str(raw).split("|"):
                cat = cat.strip()
                if cat:
                    cats[cat] = cats.get(cat, 0) + 1
        return dict(sorted(cats.items(), key=lambda x: x[1], reverse=True))

    def get_unique_categories(self) -> List[str]:
        """Return alphabetical list of unique categories."""
        dist = self.get_category_distribution()
        return sorted(list(dist.keys()))

    # ─────────────────────────────────────────────────────────────────────────
    # 8. SERIALISATION
    # ─────────────────────────────────────────────────────────────────────────

    @staticmethod
    def _row_to_dict(row: pd.Series) -> Dict[str, Any]:
        """Convert a DataFrame row to a clean API-ready dict."""
        return {
            "isbn13":         str(row.get("isbn13", "")),
            "title":          str(row.get("title", "")),
            "authors":        str(row.get("authors", "")),
            "categories":     str(row.get("categories", "")),
            "description":    str(row.get("description", "")),
            "thumbnail":      str(row.get("thumbnail", "")),
            "average_rating": round(float(row.get("average_rating", 0)), 2),
            "ratings_count":  int(row.get("ratings_count", 0)),
            "published_date": str(row.get("published_date", "")),
            "page_count":     int(row.get("page_count", 0)),
        }

    # ─────────────────────────────────────────────────────────────────────────
    # 9. INTERNAL HELPERS
    # ─────────────────────────────────────────────────────────────────────────

    def _ensure_fitted(self) -> None:
        """Guard: raise if model hasn't been trained/loaded."""
        if not self.is_fitted:
            raise RuntimeError(
                "Model not fitted. Call fit() or load_model() first."
            )
