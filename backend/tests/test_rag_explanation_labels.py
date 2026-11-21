"""
Recommendation labels must say why a book was returned (second review, findings R1/R2).

- A book that received a vector score is labelled as matching the search ("semantic_match").
- A book without a vector score is never called "trending" or a semantic match: it is labelled
  as a popular catalog title, or as taste-profile based when the caller passed a profile.
- RAG localises those explanations to the query language; recommendation_reason stays a
  canonical English string that the web client localises (localizeRecommendationReason).
- Labels are computed after ranking: GOLDEN pins the ranking and scores captured from the code
  before this change, so a label fix that moved results would fail here.

Offline: the recommender is a real BookRecommender on a six-book in-memory catalog, the LLM,
embedding and vector store are mocks, and sockets are refused (fixture from test_rag_grounding).
"""

import json

import pytest
from backend.tests import test_rag_grounding as grounding
from backend.tests.test_rag_grounding import HISTORY_SCORES, INVENTED, QUERY, _llm_json, _use_case

pytestmark = pytest.mark.unit

# Shared fixtures: the six-book recommender and the autouse socket block.
recommender = grounding.recommender
_no_network = grounding._no_network

SEMANTIC_REASON = "Found by semantic search"
POPULAR_REASON = "Popular with Libris readers"
PROFILE_REASON = "Curated based on your taste profile"


def _labels(recs):
    return {str(r["isbn13"]): (r.get("recommendation_reason"), r.get("explanation_type"), r.get("explanation"))
            for r in recs}


# ── Recommender labels ───────────────────────────────────────────────────────


def test_scored_books_are_labelled_semantic_matches_and_unscored_ones_popular(recommender):
    recs = recommender.recommend(top_n=5, use_diversity=True, semantic_scores=dict(HISTORY_SCORES))
    labels = _labels(recs)
    assert set(HISTORY_SCORES) <= set(labels)
    for isbn, (reason, etype, explanation) in labels.items():
        if isbn in HISTORY_SCORES:
            assert (reason, etype) == (SEMANTIC_REASON, "semantic_match")
            assert "anlamsal" in explanation
        else:
            assert (reason, etype) == (POPULAR_REASON, "trending_catalog")
            assert "anlamsal" not in explanation and "popüler" in explanation
        assert "Trending" not in (reason or "")


def test_semantic_label_follows_the_score_not_the_key_type(recommender):
    # The vector store returns string ids; a score reaches the book through its catalog index.
    recs = recommender.recommend(top_n=5, semantic_scores={" 978-0-00-000030-3 ": 0.9})
    labels = _labels(recs)
    assert labels["9780000000303"][:2] == (SEMANTIC_REASON, "semantic_match")


def test_profile_without_semantic_scores_never_claims_a_semantic_match(recommender):
    recs = recommender.recommend(top_n=5, preferred_genres=["History"])
    for isbn, (reason, etype, explanation) in _labels(recs).items():
        assert "anlamsal" not in explanation and etype != "semantic_match"
        assert reason in ("Because you enjoy History", PROFILE_REASON)


def test_explanation_text_is_deterministic_for_multi_category_books(recommender):
    book = recommender.df.iloc[0].to_dict()
    book["categories"] = "Science Fiction, Adventure, Space Opera"
    idx = recommender.engine.find_index(book["isbn13"], validate=False)
    texts = {recommender._explain_recommendation(dict(book), [], {book["isbn13"]: 0.9},
                                                 semantic_indices={idx})["explanation"]
             for _ in range(20)}
    assert texts == {"Bu kitap, aramanız için anlamsal arama sonuçlarında yer aldı ve science fiction kategorisinde."}


# ── Ranking is untouched (captured from the code before the label change) ───

GOLDEN = {
    ("semantic_2", True): [("9780000000303", 0.61, 0.0), ("9780000000304", 0.57, 0.0), ("9780000000305", 0.2, 0.0), ("9780000000302", 0.2, 0.0), ("9780000000301", 0.2, 0.0)],
    ("semantic_2", False): [("9780000000303", 0.61, 0.0), ("9780000000304", 0.57, 0.0), ("9780000000301", 0.2, 0.0), ("9780000000302", 0.2, 0.0), ("9780000000305", 0.2, 0.0)],
    ("semantic_5", True): [("9780000000303", 0.61, 0.0), ("9780000000304", 0.57, 0.0), ("9780000000305", 0.55, 0.0), ("9780000000302", 0.53, 0.0), ("9780000000301", 0.505, 0.0)],
    ("semantic_5", False): [("9780000000303", 0.61, 0.0), ("9780000000304", 0.57, 0.0), ("9780000000305", 0.55, 0.0), ("9780000000302", 0.53, 0.0), ("9780000000301", 0.505, 0.0)],
    ("semantic_excl", True): [("9780000000303", 0.61, 0.0), ("9780000000304", 0.57, 0.0), ("9780000000302", 0.2, 0.0), ("9780000000306", 0.0, 0.0)],
    ("semantic_excl", False): [("9780000000303", 0.61, 0.0), ("9780000000304", 0.57, 0.0), ("9780000000302", 0.2, 0.0), ("9780000000306", 0.0, 0.0)],
    ("seed", True): [("9780000000302", 0.54588, 0.493133), ("9780000000305", 0.25, 0.0), ("9780000000304", 0.25, 0.0), ("9780000000303", 0.25, 0.0), ("9780000000306", 0.027195, 0.045325)],
    ("seed", False): [("9780000000302", 0.54588, 0.493133), ("9780000000303", 0.25, 0.0), ("9780000000304", 0.25, 0.0), ("9780000000305", 0.25, 0.0), ("9780000000306", 0.027195, 0.045325)],
    ("seed_semantic", True): [("9780000000303", 0.61, 0.0), ("9780000000302", 0.34794, 0.493133), ("9780000000305", 0.2, 0.0), ("9780000000304", 0.2, 0.0), ("9780000000306", 0.013597, 0.045325)],
    ("seed_semantic", False): [("9780000000303", 0.61, 0.0), ("9780000000302", 0.34794, 0.493133), ("9780000000304", 0.2, 0.0), ("9780000000305", 0.2, 0.0), ("9780000000306", 0.013597, 0.045325)],
    ("profile", True): [("9780000000303", 0.519926, 0.412377), ("9780000000304", 0.472132, 0.33272), ("9780000000305", 0.25, 0.0), ("9780000000302", 0.25, 0.0), ("9780000000301", 0.25, 0.0)],
    ("profile", False): [("9780000000303", 0.519926, 0.412377), ("9780000000304", 0.472132, 0.33272), ("9780000000301", 0.25, 0.0), ("9780000000302", 0.25, 0.0), ("9780000000305", 0.25, 0.0)],
}
CONFIGS = {
    "semantic_2": dict(semantic_scores={"9780000000303": 0.82, "9780000000304": 0.74}),
    "semantic_5": dict(semantic_scores={"9780000000301": 0.61, "9780000000302": 0.66, "9780000000303": 0.82,
                                        "9780000000304": 0.74, "9780000000305": 0.70}),
    "semantic_excl": dict(semantic_scores={"9780000000303": 0.82, "9780000000304": 0.74, "9780000000301": 0.9},
                          exclude=["9780000000301"], dislikes=["9780000000305"]),
    "seed": dict(seed_titles=["9780000000301"]),
    "seed_semantic": dict(seed_titles=["9780000000301"], semantic_scores={"9780000000303": 0.82}),
    "profile": dict(preferred_genres=["History"]),
}


@pytest.mark.parametrize("name, diversity", sorted(GOLDEN))
def test_ranking_and_scores_are_unchanged(recommender, name, diversity):
    recs = recommender.recommend(top_n=5, use_diversity=diversity, **CONFIGS[name])
    got = [(str(r["isbn13"]), round(float(r.get("final_score") or 0), 6),
            round(float(r.get("raw_similarity_score") or 0), 6)) for r in recs]
    assert got == GOLDEN[(name, diversity)]


def test_rag_context_order_follows_relevance_without_mmr(recommender):
    # Order was MMR-based (303,304,305,302,301) before unseeded queries stopped using MMR.
    uc, llm, _ = _use_case(recommender, _llm_json("ok"))
    res = uc.execute(QUERY)
    assert [b["isbn13"] for b in res["referenced_books"]] == [
        "9780000000303", "9780000000304", "9780000000301", "9780000000302", "9780000000305"]


# ── RAG localisation ─────────────────────────────────────────────────────────

LOCALISED = {
    "en": (QUERY, "semantic search", "popular"),
    "tr": ("imparatorluk tarihi kitapları", "anlamsal arama", "popüler"),
    "de": ("Bücher über Imperien", "semantischen Suche", "beliebt"),
}


@pytest.mark.parametrize("lang", sorted(LOCALISED))
def test_rag_explanations_follow_the_query_language(recommender, lang):
    query, semantic_word, popular_word = LOCALISED[lang]
    uc, _, _ = _use_case(recommender, _llm_json("ok"))
    res = uc.execute(query)
    assert res["status"] == "success"
    for book in res["referenced_books"]:
        if book["isbn13"] in HISTORY_SCORES:
            assert book["recommendation_reason"] == SEMANTIC_REASON
            assert semantic_word in book["explanation"]
        else:
            assert book["recommendation_reason"] == POPULAR_REASON
            assert popular_word in book["explanation"].lower()
        if lang != "tr":
            assert "Bu kitap" not in book["explanation"]


def test_llm_explanation_still_overrides_the_label_text(recommender):
    uc, _, _ = _use_case(recommender, _llm_json("ok", {"9780000000303": "Ottoman sultans, told well."}))
    res = uc.execute(QUERY)
    by_isbn = {b["isbn13"]: b for b in res["referenced_books"]}
    assert by_isbn["9780000000303"]["explanation"] == "Ottoman sultans, told well."
    assert by_isbn["9780000000303"]["recommendation_reason"] == SEMANTIC_REASON


def test_guard_fallback_shows_honest_localised_labels(recommender):
    uc, _, _ = _use_case(recommender, json.dumps({"answer": f"Read {INVENTED}.", "explanations": {}}))
    res = uc.execute(QUERY)
    assert res["status"] == "llm_fallback"
    reasons = {b["isbn13"]: b["recommendation_reason"] for b in res["referenced_books"]}
    assert all(reasons[i] == SEMANTIC_REASON for i in HISTORY_SCORES)
    assert all(r == POPULAR_REASON for i, r in reasons.items() if i not in HISTORY_SCORES)


# ── Seed explanations: language and determinism ─────────────────────────────

SEED_QUERY = {"en": "books similar to Starship Liked", "de": "Bücher wie Starship Liked",
              "tr": "Starship Liked gibi kitaplar"}


@pytest.mark.parametrize("lang", sorted(SEED_QUERY))
def test_rag_seed_explanations_follow_the_query_language(recommender, lang):
    uc, _, _ = _use_case(recommender, _llm_json("ok"))
    res = uc.execute(SEED_QUERY[lang])
    assert res["metrics"]["retrieval_mode"] == "semantic_seed_hybrid"
    by_isbn = {b["isbn13"]: b for b in res["referenced_books"]}
    assert "9780000000301" not in by_isbn  # the seed is never offered back
    similar = by_isbn["9780000000302"]
    assert similar["explanation_type"] == "liked_book"
    assert "Starship Liked" in similar["explanation"]
    if lang == "tr":
        assert "kitab" in similar["explanation"]
    else:
        assert "kitab" not in similar["explanation"] and "önerildi" not in similar["explanation"]


def test_shared_genre_in_seed_explanation_is_independent_of_hash_seed():
    """The genre named in a seed explanation used to come from set order (PYTHONHASHSEED)."""
    import os
    import subprocess
    import sys

    script = (
        "import pandas as pd\n"
        "from backend.infrastructure.ml.recommender import BookRecommender\n"
        "from backend.utils.preprocess import preprocess_dataframe\n"
        "rows=[dict(isbn13='9780000000401',title='Seed',authors='A',categories='Science Fiction, Space Opera, Adventure',"
        "description='fleet starship war captain',average_rating=4,ratings_count=10),"
        "dict(isbn13='9780000000402',title='Other',authors='B',categories='Adventure, Space Opera, Science Fiction',"
        "description='fleet starship war admiral',average_rating=4,ratings_count=10),"
        "dict(isbn13='9780000000403',title='Cook',authors='C',categories='Cooking',"
        "description='recipes garden kitchen vegetables',average_rating=4,ratings_count=10)]\n"
        "r=BookRecommender(); r.engine.df=preprocess_dataframe(pd.DataFrame(rows)); r.fit()\n"
        "book=r.df.iloc[1].to_dict()\n"
        "print(r._explain_recommendation(book,[0],seed_sources={'9780000000401':'like'})['explanation'])\n"
    )
    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    outputs = set()
    for seed in ("0", "1", "2", "3", "4", "5"):
        env = {**os.environ, "PYTHONHASHSEED": seed, "PYTHONPATH": root}
        out = subprocess.run([sys.executable, "-c", script], env=env, cwd=root,
                             capture_output=True, text=True, timeout=120)
        assert out.returncode == 0, out.stderr[-500:]
        outputs.add(out.stdout.strip().splitlines()[-1])
    assert len(outputs) == 1, outputs
    # Genres are named in the recommended book's own catalog order.
    assert "adventure, space opera" in outputs.pop()


def test_semantic_labels_never_claim_a_match_or_a_strong_match(recommender):
    """The vector RPC runs with threshold 0.0: a vector score means "retrieved", not "matched"."""
    configs = [dict(semantic_scores={"9780000000303": 0.05}),
               dict(seed_titles=["9780000000301"], semantic_scores={"9780000000302": 0.05},
                    seed_sources={"9780000000301": "like"})]
    for cfg in configs:
        for rec in recommender.recommend(top_n=5, **cfg):
            text = rec.get("explanation") or ""
            assert "eşleş" not in text and "güçlü" not in text, text
            assert rec.get("recommendation_reason") != "Matches your search"
