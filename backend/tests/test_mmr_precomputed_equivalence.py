"""
MMR in BookRecommender._get_diverse_recommendations precomputes candidate similarities once
(audit fix: similar-books took ~1.3 s p50 in-process). The selection must be identical to the
original per-step implementation, reproduced here as the reference.
"""

import os

import numpy as np
import pytest
from backend.infrastructure.ml.recommender import BookRecommender, _row_identity
from backend.utils.preprocess import normalize_isbn
from sklearn.metrics.pairwise import cosine_similarity

MODEL = os.path.join(os.path.dirname(os.path.dirname(__file__)), "saved_model", "tfidf.pkl")


def reference_mmr(rec: BookRecommender, scores: np.ndarray, top_n: int):
    """The pre-fix algorithm: one sparse cosine call per candidate per step."""
    valid = [int(i) for i in np.argsort(scores)[::-1] if scores[i] > -0.5]
    cands = valid[: max(100, top_n * 10)]
    if not cands:
        return [], []
    top = float(scores[cands[0]])
    rel = scores / top if top > 1e-9 else scores
    sel, seen_i, seen_w = [], set(), set()

    def dup(i):
        row = rec.df.iloc[i]
        isbn = normalize_isbn(row.get("isbn13", ""))
        return bool(isbn and isbn in seen_i) or _row_identity(row) in seen_w

    def record(i):
        row = rec.df.iloc[i]
        isbn = normalize_isbn(row.get("isbn13", ""))
        if isbn:
            seen_i.add(isbn)
        seen_w.add(_row_identity(row))

    for i in list(cands):
        if not dup(i):
            sel.append(i)
            record(i)
            cands.remove(i)
            break
    lam = rec.config.diversity_lambda
    while len(sel) < top_n and cands:
        best, best_v = -1, -np.inf
        for c in cands:
            if dup(c):
                continue
            s = cosine_similarity(rec.tfidf_matrix[c], rec.tfidf_matrix[sel])[0].max() if sel else 0.0
            v = lam * rel[c] - (1 - lam) * s
            if v > best_v:
                best_v, best = v, c
        if best == -1:
            break
        sel.append(best)
        record(best)
        cands.remove(best)
    pen = [float((1 - lam) * cosine_similarity(rec.tfidf_matrix[i], rec.tfidf_matrix[sel])[0].max()) for i in sel]
    return sel, pen


@pytest.fixture(scope="module")
def rec():
    if not os.path.exists(MODEL):
        pytest.skip("saved model not available")
    r = BookRecommender()
    assert r.load_model(MODEL)
    return r


@pytest.mark.parametrize("seed_row", [0, 17, 250, 1024, 3333, 5000, 6400])
@pytest.mark.parametrize("top_n", [5, 10, 20])
def test_precomputed_mmr_matches_reference(rec, seed_row, top_n):
    scores = cosine_similarity(rec.tfidf_matrix[seed_row], rec.tfidf_matrix).ravel()
    scores = 0.6 * scores + 0.25 * rec.df["popularity_score"].to_numpy(float)
    scores[seed_row] = -1.0
    ref_idx, ref_pen = reference_mmr(rec, scores.copy(), top_n)
    got = rec._get_diverse_recommendations(scores.copy(), top_n)
    got_isbns = [normalize_isbn(r["isbn13"]) for r in got]
    assert got_isbns == [normalize_isbn(rec.df.iloc[i]["isbn13"]) for i in ref_idx]
    assert [r["diversity_penalty"] for r in got] == pytest.approx(ref_pen, abs=1e-9)


def test_all_suppressed_returns_empty(rec):
    assert rec._get_diverse_recommendations(np.full(len(rec.df), -1.0), 10) == []
