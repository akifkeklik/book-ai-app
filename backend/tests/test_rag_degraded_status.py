"""
Regression tests for degraded RAG retrieval (audit H1, L4, M2), with a real small recommender.

A degraded answer (embedding provider down, vector store down, or embeddings refused) must:
- carry its degraded mode as `status` and in metrics.retrieval_mode, never "success";
- not be cached, so the very next request retries semantic retrieval;
- switch back to a normal, cached semantic answer as soon as the infrastructure recovers.
"""

from unittest.mock import MagicMock

import pandas as pd
import pytest
from backend.application.use_cases.ai_rag import (
    HEALTHY_RETRIEVAL_MODES,
    ProcessRagQueryUseCase,
    _detect_action_intent,
    _detect_clock_intent,
    _detect_language,
)
from backend.domain.ports import SemanticSearchUnavailable
from backend.infrastructure.ml.recommender import BookRecommender
from backend.utils.preprocess import preprocess_dataframe

BOOKS = [
    ("9780000000201", "Dünya Klasikleri Seçkisi", "Ayşe Yazar", "Classics", "selected world classics anthology"),
    ("9780000000202", "Die Verwandlung", "Franz Kafka", "Fiction", "a travelling salesman wakes up as an insect"),
    ("9780000000203", "Tavsiye Et Bana", "Can Yazar", "Fiction", "a novel of advice and friendship"),
    ("9780000000204", "Ottoman Empire History", "Bea Historian", "History", "history of the ottoman empire sultans"),
    ("9780000000205", "Byzantine Chronicles", "Cy Historian", "History", "history of byzantium constantinople"),
    ("9780000000206", "Garden Cookbook", "Dee Cook", "Cooking", "recipes vegetables garden kitchen"),
]
LLM_JSON = '{"answer": "Here you go", "explanations": {}}'


@pytest.fixture
def recommender():
    rec = BookRecommender()
    rec.engine.df = preprocess_dataframe(pd.DataFrame(
        [dict(isbn13=i, title=t, authors=a, categories=c, description=d, average_rating=4.0, ratings_count=100)
         for i, t, a, c, d in BOOKS]))
    rec.fit()
    return rec


def _use_case(recommender, port, embedding=(0.1, 0.2)):
    emb = MagicMock()
    emb.embed_query.return_value = list(embedding) if embedding else None
    enrich = MagicMock()
    enrich.enrich.side_effect = lambda books: books
    llm = MagicMock()
    llm.generate_response.return_value = LLM_JSON
    repo = MagicMock()
    repo.get_user_interactions.return_value = []
    return ProcessRagQueryUseCase(emb, port, repo, recommender, enrich, llm)


def _assert_degraded(res, mode):
    assert res["status"] == mode
    assert res["status"] != "success"
    assert res["metrics"]["retrieval_mode"] == mode
    assert res["metrics"]["degraded"] is True
    assert res["metrics"].get("source") != "cache_hit"


@pytest.mark.parametrize("query, lang_word", [
    ("Dünya klasikleri", "tr"),   # Turkish, catalog match -> previously answered "success" and cached
    ("Die Verwandlung", "de"),     # German, same path
])
def test_vector_outage_is_labelled_not_cached_and_recovers(recommender, query, lang_word):
    port = MagicMock()
    port.match_query_embeddings.side_effect = SemanticSearchUnavailable("pgvector down")
    uc = _use_case(recommender, port)

    first = uc.execute(query)
    _assert_degraded(first, "semantic_unavailable")
    assert first["metrics"]["degraded_reason"] == "semantic_unavailable"
    assert first["referenced_books"], "catalog matches are still shown"

    second = uc.execute(query)
    _assert_degraded(second, "semantic_unavailable")
    assert port.match_query_embeddings.call_count == 2  # retried, not served from cache

    # Infrastructure recovers: the next request is a normal semantic answer, and that one is cached.
    port.match_query_embeddings.side_effect = None
    port.match_query_embeddings.return_value = {"9780000000204": 0.7}
    recovered = uc.execute(query)
    assert recovered["status"] == "success"
    assert recovered["metrics"]["retrieval_mode"] == "semantic"
    assert recovered["metrics"]["degraded"] is False
    assert uc.execute(query)["metrics"]["source"] == "cache_hit"
    assert _detect_language(query) == lang_word


@pytest.mark.parametrize("query", ["Dünya klasikleri", "Die Verwandlung"])
def test_embedding_failure_is_labelled_not_cached_and_recovers(recommender, query):
    port = MagicMock()
    port.match_query_embeddings.return_value = {"9780000000204": 0.7}
    uc = _use_case(recommender, port, embedding=None)

    _assert_degraded(uc.execute(query), "embedding_failed")
    _assert_degraded(uc.execute(query), "embedding_failed")
    assert uc._embedding_port.embed_query.call_count == 2

    uc._embedding_port.embed_query.return_value = [0.1, 0.2]
    assert uc.execute(query)["status"] == "success"


def test_refused_embedding_profile_is_semantic_unavailable(recommender):
    port = MagicMock()
    uc = _use_case(recommender, port)
    uc._embedding_port.embed_query.side_effect = SemanticSearchUnavailable("stored vectors use another profile")
    res = uc.execute("Die Verwandlung")
    _assert_degraded(res, "semantic_unavailable")
    port.match_query_embeddings.assert_not_called()


def test_anonymous_generic_popular_fallback_is_labelled_and_retried(recommender):
    port = MagicMock()
    port.match_query_embeddings.side_effect = SemanticSearchUnavailable("down")
    uc = _use_case(recommender, port)

    res = uc.execute("Bana bir kitap öner")
    _assert_degraded(res, "popular_fallback")
    assert res["metrics"]["degraded_reason"] == "semantic_unavailable"
    assert res["referenced_books"]
    assert "oturum açmadığınız" in res["answer"]
    uc.execute("Bana bir kitap öner")
    assert port.match_query_embeddings.call_count == 2


def test_anonymous_generic_curated_branch_with_catalog_match_is_not_cached_when_degraded(recommender):
    """The second curated branch (generic request that also hit a catalog title)."""
    port = MagicMock()
    port.match_query_embeddings.side_effect = SemanticSearchUnavailable("down")
    uc = _use_case(recommender, port)

    res = uc.execute("kitap tavsiye et")
    _assert_degraded(res, "semantic_unavailable")
    assert res["metrics"]["source"] == "curated_anonymous_rec"
    uc.execute("kitap tavsiye et")
    assert port.match_query_embeddings.call_count == 2

    port.match_query_embeddings.side_effect = None
    port.match_query_embeddings.return_value = {"9780000000206": 0.9}
    healthy = uc.execute("kitap tavsiye et")
    assert healthy["status"] == "success"
    assert uc.execute("kitap tavsiye et")["metrics"]["source"] == "cache_hit"


def test_lexical_fallback_label_is_kept_for_english(recommender):
    port = MagicMock()
    port.match_query_embeddings.side_effect = SemanticSearchUnavailable("down")
    res = _use_case(recommender, port).execute("history of the ottoman empire")
    _assert_degraded(res, "lexical_fallback")
    assert res["referenced_books"][0]["isbn13"] == "9780000000204"


# ── L4: retrieval_mode labels for seed-based ranking ──────────────────────────

def _similar_use_case(recommender, port):
    uc = _use_case(recommender, port)
    seed = recommender.df[recommender.df["isbn13"] == "9780000000204"].iloc[0].to_dict()
    uc._lookup_catalog_candidates = lambda _q: [seed]
    return uc


def test_seed_ranking_during_vector_outage_is_labelled_seed_tfidf_fallback(recommender):
    port = MagicMock()
    port.match_query_embeddings.side_effect = SemanticSearchUnavailable("down")
    res = _similar_use_case(recommender, port).execute("books similar to Ottoman Empire History")
    _assert_degraded(res, "seed_tfidf_fallback")
    isbns = [b["isbn13"] for b in res["referenced_books"]]
    assert "9780000000204" not in isbns  # the seed itself is never recommended back
    assert isbns[0] == "9780000000205"   # the other history book is the closest by TF-IDF


@pytest.mark.parametrize("scores, mode", [
    ({}, "seed_tfidf"),                                   # vector search ran but found nothing
    ({"9780000000205": 0.8}, "semantic_seed_hybrid"),
])
def test_seed_ranking_with_working_vector_search_is_labelled(recommender, scores, mode):
    port = MagicMock()
    port.match_query_embeddings.return_value = scores
    res = _similar_use_case(recommender, port).execute("books similar to Ottoman Empire History")
    assert res["status"] == "success"
    assert res["metrics"]["retrieval_mode"] == mode
    assert mode in HEALTHY_RETRIEVAL_MODES


def test_malformed_vector_result_is_treated_as_unavailable(recommender):
    port = MagicMock()
    port.match_query_embeddings.return_value = ["not", "a", "dict"]
    _assert_degraded(_use_case(recommender, port).execute("Die Verwandlung"), "semantic_unavailable")


# ── M2: language detection and localized deterministic replies ───────────────

@pytest.mark.parametrize("query, lang", [
    ("Dünya klasikleri", "tr"),
    ("öykü", "tr"),
    ("Bir öykü kitabı", "tr"),
    ("Türk edebiyatı klasikleri", "tr"),
    ("Hikayeler", "tr"),
    ("Müzik hakkında kitaplar", "tr"),
    ("Die Verwandlung", "de"),
    ("Mein Lieblingsbuch", "de"),
    ("Kafka Die Verwandlung", "de"),
    ("Krieg und Frieden", "de"),
    ("Schöne Liebesromane", "de"),
    ("Zauberer Bücher für Kinder", "de"),
    ("books where the heroes die", "en"),
    ("Pride and Prejudice", "en"),
    ("Harry Potter and the Goblet of Fire", "en"),
    ("a murder mystery set in Istanbul", "en"),
    ("1984", "en"),
])
def test_language_detection_cases(query, lang):
    assert _detect_language(query) == lang


@pytest.mark.parametrize("query, prefix", [
    ("Welcher Tag ist heute?", "Heute ist"),
    ("Wie spät ist es?", "Heute ist"),
    ("Bugün hangi gün?", "Bugün"),
    ("Saat kaç?", "Bugün"),
    ("What day is it today?", "Today is"),
])
def test_clock_reply_follows_query_language(query, prefix):
    assert _detect_clock_intent(query)["answer"].startswith(prefix)


@pytest.mark.parametrize("query, expected", [
    ("switch theme to dark mode", "Appearance set to Dark Mode."),
    ("Koyu temaya geç", "Görünüm modu Koyu Tema (Dark Mode) olarak ayarlandı."),
    ("Dunkel Modus bitte", "Der dunkle Modus (Dark Mode) ist jetzt aktiv."),
    ("open catalog", "Taking you to the book catalog."),
])
def test_action_confirmation_follows_query_language(query, expected):
    assert _detect_action_intent(query, _detect_language(query))["answer"] == expected


@pytest.mark.parametrize("query, expected", [
    ("Dünya klasikleri", "Anlamsal arama"),
    ("Die Verwandlung des Gregor Samsa über Insekten", "Die semantische Suche"),
])
def test_unavailable_message_is_localized(recommender, query, expected):
    port = MagicMock()
    port.match_query_embeddings.side_effect = SemanticSearchUnavailable("down")
    uc = _use_case(recommender, port)
    uc._lookup_catalog_candidates = lambda _q: []
    res = uc.execute(query)
    assert res["status"] == "semantic_unavailable"
    assert expected in res["answer"]
