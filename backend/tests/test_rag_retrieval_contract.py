"""
RAG retrieval contract, exercised with a real (small) BookRecommender rather than mocks:
- the query's semantic scores decide relevance; the user's library is only excluded,
- vector-store failure is explicit and never cached as a normal answer,
- the lexical fallback is used only where it was measured to work (English),
- deterministic replies follow the query language.
"""

from unittest.mock import MagicMock

import pandas as pd
import pytest
from backend.application.use_cases.ai_rag import ProcessRagQueryUseCase
from backend.domain.ports import SemanticSearchUnavailable
from backend.infrastructure.ml.recommender import BookRecommender
from backend.utils.preprocess import preprocess_dataframe

BOOKS = [
    ("9780000000101", "Starship Liked", "Ann Author", "Science Fiction", "space opera fleet starship captain war"),
    ("9780000000102", "Galactic Fleet", "Ann Author", "Science Fiction", "space opera fleet starship admiral war"),
    ("9780000000103", "Ottoman Empire History", "Bea Historian", "History", "history of the ottoman empire sultans istanbul"),
    ("9780000000104", "Byzantine Chronicles", "Cy Historian", "History", "history of byzantium constantinople emperors"),
    ("9780000000105", "Garden Cookbook", "Dee Cook", "Cooking", "recipes vegetables garden kitchen"),
]


@pytest.fixture
def recommender():
    rec = BookRecommender()
    rec.engine.df = preprocess_dataframe(pd.DataFrame(
        [dict(isbn13=i, title=t, authors=a, categories=c, description=d, average_rating=4.0, ratings_count=100)
         for i, t, a, c, d in BOOKS]))
    rec.fit()
    return rec


def _use_case(recommender, data_port, interactions=None, llm_answer=None):
    emb = MagicMock()
    emb.embed_query.return_value = [0.1, 0.2]
    repo = MagicMock()
    repo.get_user_interactions.return_value = interactions or []
    enrich = MagicMock()
    enrich.enrich.side_effect = lambda books: books
    llm = MagicMock()
    llm.generate_response.return_value = llm_answer
    return ProcessRagQueryUseCase(emb, data_port, repo, recommender, enrich, llm), llm


def test_query_relevance_is_not_overridden_by_the_users_library(recommender):
    """A sci-fi reader asking about Ottoman history gets history, not more sci-fi."""
    port = MagicMock()
    port.match_query_embeddings.return_value = {
        "9780000000103": 0.82, "9780000000104": 0.74, "9780000000102": 0.40, "9780000000101": 0.38,
    }
    uc, _ = _use_case(recommender, port,
                      interactions=[{"book_id": "9780000000101", "interaction_type": "favorite"}])
    books = uc._retrieve_books_by_embedding([0.1], top_k=2, user_id="u1")
    assert [b["isbn13"] for b in books] == ["9780000000103", "9780000000104"]


def test_library_and_dislikes_are_excluded(recommender):
    port = MagicMock()
    port.match_query_embeddings.return_value = {
        "9780000000101": 0.9, "9780000000102": 0.8, "9780000000103": 0.3,
    }
    uc, _ = _use_case(recommender, port, interactions=[
        {"book_id": "9780000000101", "interaction_type": "reading"},
        {"book_id": "9780000000102", "interaction_type": "dislike"},
    ])
    isbns = [b["isbn13"] for b in uc._retrieve_books_by_embedding([0.1], top_k=5, user_id="u1")]
    assert "9780000000101" not in isbns and "9780000000102" not in isbns
    assert isbns[0] == "9780000000103"


def test_vector_failure_raises_instead_of_looking_like_no_results(recommender):
    port = MagicMock()
    port.match_query_embeddings.side_effect = RuntimeError("connection reset")
    uc, _ = _use_case(recommender, port)
    with pytest.raises(SemanticSearchUnavailable):
        uc._retrieve_books_by_embedding([0.1], top_k=5)


def test_missing_book_data_port_is_explicit(recommender):
    uc, _ = _use_case(recommender, None)
    with pytest.raises(SemanticSearchUnavailable):
        uc._retrieve_books_by_embedding([0.1], top_k=5)


def test_english_query_uses_labelled_lexical_fallback_and_is_not_cached(recommender):
    port = MagicMock()
    port.match_query_embeddings.side_effect = SemanticSearchUnavailable("pgvector schema missing")
    uc, llm = _use_case(recommender, port, llm_answer='{"answer": "History picks", "explanations": {}}')

    first = uc.execute("history of the ottoman empire")
    assert first["status"] == "lexical_fallback"
    assert first["metrics"]["retrieval_mode"] == "lexical_fallback"
    assert first["referenced_books"][0]["isbn13"] == "9780000000103"

    second = uc.execute("history of the ottoman empire")
    assert second["metrics"].get("source") != "cache_hit"
    assert port.match_query_embeddings.call_count == 2  # vector search retried, not served from cache


def test_non_english_query_without_vector_search_fails_honestly(recommender):
    """English-only catalog text: lexical TF-IDF cannot match Turkish queries, so no junk answer is shown."""
    port = MagicMock()
    port.match_query_embeddings.side_effect = SemanticSearchUnavailable("down")
    uc, llm = _use_case(recommender, port, llm_answer="should not be called")
    res = uc.execute("osmanlı tarihi hakkında kitaplar öner")
    assert res["status"] == "semantic_unavailable"
    assert res["referenced_books"] == []
    assert "Anlamsal arama" in res["answer"]
    llm.generate_response.assert_not_called()


def test_embedding_failure_keeps_its_own_status(recommender):
    uc, _ = _use_case(recommender, MagicMock())
    uc._embedding_port.embed_query.return_value = None
    res = uc.execute("Welche Bücher über Byzanz gibt es zu empfehlen bitte")
    assert res["status"] == "embedding_failed"
    assert "semantische Suche" in res["answer"]


def test_semantic_success_is_cached(recommender):
    port = MagicMock()
    port.match_query_embeddings.return_value = {"9780000000103": 0.8}
    uc, _ = _use_case(recommender, port, llm_answer='{"answer": "ok", "explanations": {}}')
    assert uc.execute("ottoman empire")["status"] == "success"
    assert uc.execute("ottoman empire")["metrics"]["source"] == "cache_hit"


@pytest.mark.parametrize("query, expected", [
    ("Do you have the book Zzyzx Quantum Llama?", "We couldn't find a verified book"),
    ("Gibt es das Buch Zzyzx Quantum Llama?", "In unserem Katalog wurde kein passendes Buch gefunden"),
    ("Zzyzx Quantum Llama kitabı var mı?", "Kataloğumuzda bu aramayla"),
])
def test_catalog_miss_reply_follows_query_language(recommender, query, expected):
    uc, _ = _use_case(recommender, MagicMock())
    res = uc.execute(query)
    assert res["status"] == "no_match"
    assert res["answer"].startswith(expected)


@pytest.mark.parametrize("query, lang", [
    ("Bücher über den Zweiten Weltkrieg", "de"),        # ü/ö are shared with Turkish
    ("eine herzerwärmende Geschichte über Freundschaft", "de"),
    ("Was ist ein gutes Buch?", "de"),
    ("Gibt es Märchen für Kinder?", "de"),
    ("Hangi kitapları önerirsin?", "tr"),
    ("John Grisham gibi hukuk gerilimleri", "tr"),
    ("Ödev için kısa öykü", "tr"),
    ("books where the heroes die", "en"),
    ("do you have 1984", "en"),
])
def test_language_detection(query, lang):
    from backend.application.use_cases.ai_rag import _detect_language
    assert _detect_language(query) == lang
