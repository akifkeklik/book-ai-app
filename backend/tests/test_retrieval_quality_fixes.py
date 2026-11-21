"""
Regression tests for the retrieval/recommendation defects found in the offline evaluation:
edition-aware identity, lost same-title books, MMR calibration, honest popularity attribution,
graded metrics, and Supabase catalog paging.
"""

from unittest.mock import MagicMock

import numpy as np
import pandas as pd
import pytest
from backend.evaluation.metrics import (
    graded_ndcg_at_k,
    graded_precision_at_k,
    graded_recall_at_k,
    judged_at_k,
    mean_reciprocal_rank,
)
from backend.infrastructure.ml.recommender import BookRecommender
from backend.infrastructure.persistence.supabase_adapters import SupabaseBookDataPort
from backend.utils.preprocess import normalize_isbn, preprocess_dataframe, work_id
from scipy.sparse import csr_matrix

# ── Book identity ────────────────────────────────────────────────────────────

def test_work_id_groups_editions_but_not_same_title_books():
    assert work_id("The Hotel New Hampshire", "JOHN IRVING") == work_id("THE HOTEL NEW HAMPSHIRE", "John Irving")
    assert work_id("Salem's Lot", "Stephen King") == work_id("Salems Lot", "Stephen King") or \
        work_id("Salem's Lot", "Stephen King") == work_id("Salem s Lot", "Stephen King")
    assert work_id("The Birth of Tragedy", "Friedrich Wilhelm Nietzsche") == work_id("The Birth of Tragedy", "Friedrich Nietzsche")
    assert work_id("Harry Potter", "Rowling, J.K.") == work_id("Harry Potter", "J. K. Rowling")
    assert work_id("The Complete Stories", "Zora Neale Hurston") != work_id("The Complete Stories", "Flannery O'Connor")


@pytest.mark.parametrize("raw, expected", [
    ("978-0-441-01359-3", "9780441013593"), (9780441013593.0, "9780441013593"),
    ("9780441013593.0", "9780441013593"), (" 080442957x ", "080442957X"), (None, ""), (float("nan"), ""),
])
def test_normalize_isbn(raw, expected):
    assert normalize_isbn(raw) == expected


def _books():
    return pd.DataFrame([
        {"isbn13": "9780000000001", "title": "The Complete Stories", "authors": "Zora Neale Hurston",
         "categories": "Fiction", "description": "Short stories"},
        {"isbn13": "9780000000002", "title": "The Complete Stories", "authors": "Flannery O'Connor",
         "categories": "Fiction", "description": "Southern gothic stories"},
        {"isbn13": "9780000000003", "title": "The Hotel New Hampshire", "authors": "John Irving",
         "categories": "Fiction", "description": "A family runs hotels"},
        {"isbn13": "9780000000004", "title": "THE HOTEL NEW HAMPSHIRE", "authors": "JOHN IRVING",
         "categories": "Fiction", "description": "A family runs hotels"},
    ])


def test_preprocess_keeps_distinct_same_title_books():
    df = preprocess_dataframe(_books())
    stories = df[df["title"] == "The Complete Stories"]
    assert sorted(stories["authors"]) == ["Flannery O'Connor", "Zora Neale Hurston"]


def test_preprocess_collapses_editions_and_keeps_their_isbns():
    df = preprocess_dataframe(_books())
    hotel = df[df["title"].str.lower() == "the hotel new hampshire"]
    assert len(hotel) == 1
    assert hotel.iloc[0]["edition_isbns"].split("|") == ["9780000000003", "9780000000004"]


def test_any_edition_isbn_resolves_to_the_kept_row():
    """Embeddings/shelves keyed by a merged edition's ISBN must not silently drop."""
    rec = BookRecommender()
    rec.engine.df = preprocess_dataframe(_books())
    kept = rec.engine.find_all_indices("9780000000003")
    assert kept and rec.engine.find_all_indices("9780000000004") == kept
    assert rec.engine.find_all_indices("978-0-000-00000-4") == kept


def test_semantic_score_for_merged_edition_reaches_the_kept_row():
    rec = BookRecommender()
    rec.engine.df = preprocess_dataframe(_books())
    rec.fit()
    recs = rec.recommend(seed_titles=[], semantic_scores={"9780000000004": 0.9}, top_n=1, use_diversity=False)
    assert recs and recs[0]["title"].lower() == "the hotel new hampshire"


# ── MMR calibration ──────────────────────────────────────────────────────────

def _mmr_engine(sims, scores):
    rec = BookRecommender()
    n = len(scores)
    rec.engine.df = preprocess_dataframe(pd.DataFrame([
        {"isbn13": f"97800000001{i:02d}", "title": f"Book {i}", "authors": f"Author {i}", "categories": "Fiction"}
        for i in range(n)
    ]))
    rec.engine.tfidf_matrix = csr_matrix(sims)
    rec.is_fitted = rec.engine.is_fitted = True
    return rec, np.asarray(scores, dtype=float)


def test_mmr_does_not_trade_relevant_books_for_irrelevant_ones():
    """
    TF-IDF scores are small (~0.1-0.3). On raw scores, lambda=0.6 let the similarity penalty
    outweigh relevance, so an almost-irrelevant book beat relevant near-duplicates.
    """
    # Items 0-2: relevant and mutually similar (cos 0.5); item 3: barely relevant, dissimilar.
    vectors = np.array([[1.0, 0.0, 0.0], [0.5, 0.866, 0.0], [0.5, 0.0, 0.866], [0.0, 0.0, 0.0]])
    vectors[3] = [0.0, -0.5, -0.5]
    rec, scores = _mmr_engine(vectors, [0.20, 0.19, 0.18, 0.05])
    picked = [r["title"] for r in rec._get_diverse_recommendations(scores, top_n=2)]
    assert picked == ["Book 0", "Book 1"]


def test_mmr_still_breaks_ties_toward_diversity():
    vectors = np.array([[1.0, 0.0], [1.0, 0.0], [0.0, 1.0]])  # 0 and 1 are identical in content
    rec, scores = _mmr_engine(vectors, [0.31, 0.30, 0.29])
    picked = [r["title"] for r in rec._get_diverse_recommendations(scores, top_n=2)]
    assert picked == ["Book 0", "Book 2"]


# ── Graded metrics ───────────────────────────────────────────────────────────

def test_graded_metrics_count_duplicates_once():
    grades = {"a": 2, "b": 1, "c": 0}
    assert graded_precision_at_k(["a", "a", "b"], grades, k=3) == pytest.approx(2 / 3)
    assert graded_precision_at_k(["a", "b"], grades, k=2, min_grade=2) == 0.5
    assert graded_ndcg_at_k(["a", "b"], grades, k=2) == pytest.approx(1.0)
    assert graded_ndcg_at_k(["a", "a"], grades, k=2) < 1.0
    assert graded_ndcg_at_k(["b", "a"], grades, k=2) < 1.0
    assert mean_reciprocal_rank(["c", "x", "b"], grades, k=5) == pytest.approx(1 / 3)
    assert graded_recall_at_k(["b"], grades, k=5) == 0.5
    assert judged_at_k(["a", "x"], grades, k=2) == 0.5
    assert graded_ndcg_at_k(["x"], {}, k=5) == 0.0


# ── Catalog paging ───────────────────────────────────────────────────────────

def test_supabase_get_all_books_raw_pages_past_postgrest_cap():
    client = MagicMock()
    pages = [[{"isbn13": str(i)} for i in range(1000)], [{"isbn13": "x"}], []]
    query = client.table.return_value.select.return_value.order.return_value
    query.range.return_value.execute.side_effect = [MagicMock(data=p) for p in pages]
    books = SupabaseBookDataPort(client).get_all_books_raw()
    assert len(books) == 1001
    assert query.range.call_args_list[1].args == (1000, 1999)


def test_supabase_get_all_books_raw_never_returns_a_partial_catalog():
    client = MagicMock()
    query = client.table.return_value.select.return_value.order.return_value
    query.range.return_value.execute.side_effect = [MagicMock(data=[{"isbn13": "1"}] * 1000), Exception("timeout")]
    assert SupabaseBookDataPort(client).get_all_books_raw() == []
