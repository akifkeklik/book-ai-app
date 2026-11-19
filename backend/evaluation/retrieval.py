"""
Offline retrieval evaluation for Libris: query-to-item and seed-to-item.

Everything here runs against one frozen catalog snapshot (backend/data/books.csv)
and never calls a network service. Embedding systems are only available when an
exported embedding snapshot is supplied (see scripts/export_embedding_snapshot.py);
they are skipped, and reported as skipped, otherwise.

Book identity: results are compared by *work id* (normalised title + first author
surname), so two editions of one book share a judgment and cannot both earn gain.
"""

from __future__ import annotations

import csv
import hashlib
import json
import os
from collections import Counter
from dataclasses import dataclass, field
from typing import Callable, Dict, Iterable, List, Optional, Sequence

import numpy as np
import pandas as pd
from backend.utils.preprocess import normalize_isbn, work_id
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity

BACKEND_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG_CSV = os.path.join(BACKEND_DIR, "data", "books.csv")
DATA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")

JUDGMENT_FIELDS = [
    "task", "topic_id", "topic_text", "work_id", "isbn13", "title", "authors",
    "categories", "grade", "labeler", "reviewed_by",
]


# ── Catalog snapshot ─────────────────────────────────────────────────────────


class Catalog:
    """The raw catalog snapshot, one row per ISBN, plus edition-aware identities."""

    def __init__(self, csv_path: str = CATALOG_CSV):
        df = pd.read_csv(csv_path, dtype=str).fillna("")
        df["isbn13"] = df["isbn13"].map(normalize_isbn)
        df["work_id"] = [work_id(t, a) for t, a in zip(df["title"], df["authors"])]
        df["ratings_count"] = pd.to_numeric(df["ratings_count"], errors="coerce").fillna(0)
        df["average_rating"] = pd.to_numeric(df["average_rating"], errors="coerce").fillna(0.0)
        self.df = df.reset_index(drop=True)
        self.isbns: List[str] = self.df["isbn13"].tolist()
        self.row_of: Dict[str, int] = {isbn: i for i, isbn in enumerate(self.isbns)}
        self.work_of: Dict[str, str] = dict(zip(self.df["isbn13"], self.df["work_id"]))
        self.n_works = self.df["work_id"].nunique()

    def works(self, isbns: Iterable[str]) -> List[str]:
        return [self.work_of.get(normalize_isbn(i), f"unknown:{i}") for i in isbns]

    def book(self, isbn: str) -> Dict[str, str]:
        return self.df.iloc[self.row_of[isbn]].to_dict()

    def popularity(self) -> np.ndarray:
        """Production popularity formula from utils.preprocess (0.7 rating + 0.3 log count)."""
        r = self.df["average_rating"].to_numpy(float)
        c = self.df["ratings_count"].to_numpy(float)
        rmax = r.max() or 5.0
        cmax = c.max() or 1.0
        return 0.7 * np.clip(r / rmax, 0, 1) + 0.3 * (np.log1p(np.maximum(c, 0)) / np.log1p(cmax))


# ── Representations ──────────────────────────────────────────────────────────


@dataclass
class TfidfIndex:
    name: str
    vectorizer: TfidfVectorizer
    matrix: object  # scipy sparse, rows aligned with `isbns`
    isbns: List[str]
    row_of: Dict[str, int] = field(default_factory=dict)

    def __post_init__(self):
        self.row_of = {isbn: i for i, isbn in enumerate(self.isbns)}

    def query_scores(self, text: str) -> np.ndarray:
        return cosine_similarity(self.vectorizer.transform([text]), self.matrix).ravel()

    def item_scores(self, isbn: str) -> Optional[np.ndarray]:
        row = self.row_of.get(isbn)
        if row is None:
            return None
        return cosine_similarity(self.matrix[row], self.matrix).ravel()


def fit_tfidf(name: str, catalog: Catalog, combine: Callable[[pd.Series], str], **params) -> TfidfIndex:
    docs = [combine(row) for _, row in catalog.df.iterrows()]
    vec = TfidfVectorizer(**params)
    return TfidfIndex(name, vec, vec.fit_transform(docs), list(catalog.isbns))


def production_tfidf(model_path: str) -> TfidfIndex:
    """The committed production artifact, loaded exactly as BookService loads it."""
    from backend.infrastructure.ml.recommender import BookRecommender

    rec = BookRecommender()
    if not rec.load_model(model_path):
        raise RuntimeError(f"could not load {model_path}")
    isbns = [normalize_isbn(i) for i in rec.df["isbn13"]]
    return TfidfIndex("tfidf_pickle", rec.engine.tfidf_vectorizer, rec.tfidf_matrix, isbns)


@dataclass
class EmbeddingIndex:
    """Exact (brute-force) cosine search over an exported embedding snapshot."""

    isbns: List[str]
    vectors: np.ndarray  # L2-normalised rows
    model_version: str = ""
    row_of: Dict[str, int] = field(default_factory=dict)

    def __post_init__(self):
        norms = np.linalg.norm(self.vectors, axis=1, keepdims=True)
        self.vectors = self.vectors / np.maximum(norms, 1e-12)
        self.row_of = {isbn: i for i, isbn in enumerate(self.isbns)}

    @classmethod
    def load(cls, path: str) -> "EmbeddingIndex":
        data = np.load(path, allow_pickle=False)
        isbns = [normalize_isbn(i) for i in data["isbns"].tolist()]
        model = str(data["model_version"]) if "model_version" in data else ""
        return cls(isbns, data["vectors"].astype(np.float32), model)

    def scores(self, vector: Sequence[float]) -> np.ndarray:
        q = np.asarray(vector, dtype=np.float32)
        return self.vectors @ (q / max(float(np.linalg.norm(q)), 1e-12))

    def centroid(self, isbns: Sequence[str]) -> Optional[np.ndarray]:
        rows = [self.row_of[i] for i in isbns if i in self.row_of]
        if not rows:
            return None
        return self.vectors[rows].mean(axis=0)


def scores_on_catalog(catalog: Catalog, isbns: List[str], scores: np.ndarray) -> np.ndarray:
    """Re-align a score vector indexed by some index's ISBN order onto catalog rows (missing = 0)."""
    out = np.zeros(len(catalog.isbns))
    for isbn, s in zip(isbns, scores):
        row = catalog.row_of.get(isbn)
        if row is not None:
            out[row] = s
    return out


# ── Ranking ──────────────────────────────────────────────────────────────────


def top_k(catalog: Catalog, scores: np.ndarray, k: int, exclude_works: Iterable[str] = ()) -> List[str]:
    """Top-k ISBNs by score, skipping excluded works and repeated editions of one work."""
    excluded = set(exclude_works)
    seen: set = set()
    out: List[str] = []
    for row in np.argsort(-scores, kind="stable"):
        if scores[row] <= 0:
            break
        w = catalog.df.at[row, "work_id"]
        if w in excluded or w in seen:
            continue
        seen.add(w)
        out.append(catalog.isbns[row])
        if len(out) >= k:
            break
    return out


def mmr(
    catalog: Catalog,
    scores: np.ndarray,
    k: int,
    similarity: Callable[[int, List[int]], float],
    lam: float = 0.6,
    pool: int = 100,
    exclude_works: Iterable[str] = (),
    normalize: bool = False,
) -> List[str]:
    """
    Maximal Marginal Relevance over the top `pool` candidates (same rule as production).
    normalize=True rescales relevance by the pool maximum so it shares the [0, 1] range of
    the similarity penalty; otherwise lambda's meaning depends on the score scale.
    """
    candidates: List[int] = []
    excluded = set(exclude_works)
    seen: set = set()
    for row in np.argsort(-scores, kind="stable"):
        if scores[row] <= 0 or len(candidates) >= pool:
            break
        w = catalog.df.at[row, "work_id"]
        if w in excluded or w in seen:
            continue
        seen.add(w)
        candidates.append(int(row))
    if normalize and candidates:
        top = max(float(scores[candidates[0]]), 1e-12)
        scores = scores / top
    selected: List[int] = []
    while candidates and len(selected) < k:
        best = max(
            candidates,
            key=lambda r: lam * scores[r] - (1 - lam) * (similarity(r, selected) if selected else 0.0),
        )
        selected.append(best)
        candidates.remove(best)
    return [catalog.isbns[r] for r in selected]


# ── Datasets and judgments ───────────────────────────────────────────────────


def load_topics(name: str) -> List[dict]:
    with open(os.path.join(DATA_DIR, name), encoding="utf-8") as f:
        return json.load(f)["topics"]


def is_human_reviewed(row: Dict[str, str]) -> bool:
    """A judgment counts as human-reviewed only when a reviewer signed it off (reviewed_by)."""
    return bool((row.get("reviewed_by") or "").strip())


def load_judgments(path: str, reviewed_only: bool = False) -> Dict[str, Dict[str, int]]:
    """
    {topic_id: {work_id: grade}} from a judgments CSV; blank grades are skipped. With
    reviewed_only, provisional (unreviewed, e.g. LLM-generated) grades are skipped as well.
    """
    out: Dict[str, Dict[str, int]] = {}
    if not os.path.exists(path):
        return out
    with open(path, encoding="utf-8", newline="") as f:
        for row in csv.DictReader(f):
            if row.get("grade", "").strip() == "":
                continue
            if reviewed_only and not is_human_reviewed(row):
                continue
            out.setdefault(row["topic_id"], {})[row["work_id"]] = int(row["grade"])
    return out


def judgment_provenance(path: str) -> Dict[str, object]:
    """Who produced the grades in a judgments CSV, so reports cannot hide label quality."""
    labelers: Counter = Counter()
    graded = reviewed = ungraded = 0
    reviewed_topics = set()
    if os.path.exists(path):
        with open(path, encoding="utf-8", newline="") as f:
            for row in csv.DictReader(f):
                if row.get("grade", "").strip() == "":
                    ungraded += 1
                    continue
                graded += 1
                labelers[(row.get("labeler") or "unknown").strip() or "unknown"] += 1
                if is_human_reviewed(row):
                    reviewed += 1
                    reviewed_topics.add(row["topic_id"])
    return {
        "graded_rows": graded, "human_reviewed_rows": reviewed, "unreviewed_rows": graded - reviewed,
        "ungraded_rows": ungraded, "by_labeler": dict(sorted(labelers.items())),
        "topics_with_reviewed_judgments": len(reviewed_topics),
    }


def topic_split(topic_id: str) -> str:
    """
    Deterministic split: about one topic in three is "heldout". Future tuning should look only
    at "dev" and report "heldout" once. Every configuration chosen so far was selected on all
    topics, so today's heldout numbers are not independent of that tuning either.
    """
    return "heldout" if int(hashlib.sha1(topic_id.encode("utf-8")).hexdigest(), 16) % 3 == 0 else "dev"


def write_pool(path: str, task: str, topics: List[dict], pooled: Dict[str, List[str]], catalog: Catalog) -> int:
    """Append unjudged pooled candidates to the judgments CSV for review. Returns rows added."""
    existing = set()
    rows: List[dict] = []
    if os.path.exists(path):
        with open(path, encoding="utf-8", newline="") as f:
            rows = list(csv.DictReader(f))
        existing = {(r["topic_id"], r["work_id"]) for r in rows}
    text_of = {t["id"]: t.get("text") or t.get("seed_title", "") for t in topics}
    added = 0
    for topic_id, isbns in pooled.items():
        for isbn in isbns:
            w = catalog.work_of[isbn]
            if (topic_id, w) in existing:
                continue
            existing.add((topic_id, w))
            b = catalog.book(isbn)
            rows.append({
                "task": task, "topic_id": topic_id, "topic_text": text_of.get(topic_id, ""),
                "work_id": w, "isbn13": isbn, "title": b["title"], "authors": b["authors"],
                "categories": b["categories"], "grade": "", "labeler": "", "reviewed_by": "",
            })
            added += 1
    rows.sort(key=lambda r: (r["topic_id"], r["work_id"]))
    with open(path, "w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=JUDGMENT_FIELDS)
        writer.writeheader()
        writer.writerows(rows)
    return added
