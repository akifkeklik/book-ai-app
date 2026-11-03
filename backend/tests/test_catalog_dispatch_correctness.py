from unittest.mock import MagicMock

import pandas as pd
import pytest
from backend.application.use_cases.ai_rag import ProcessRagQueryUseCase
from backend.domain.ports import (
    BookDataPort,
    EmbeddingPort,
    EnrichmentPort,
    LlmPort,
    RecommenderPort,
)


@pytest.fixture
def mock_catalog_recommender():
    rec = MagicMock(spec=RecommenderPort)
    # Synthetic realistic catalog dataframe
    data = [
        {"title": "1984", "authors": "George Orwell", "isbn13": "9780451524935", "isbn10": "0451524934", "average_rating": 4.17, "ratings_count": 2800000},
        {"title": "Animal Farm and 1984", "authors": "George Orwell", "isbn13": "9780151010264", "isbn10": "0151010269", "average_rating": 4.28, "ratings_count": 12000},
        {"title": "The Alchemist", "authors": "Paulo Coelho", "isbn13": "9780062315007", "isbn10": "0062315005", "average_rating": 3.85, "ratings_count": 1900000},
        {"title": "Alice in Wonderland", "authors": "Lewis Carroll", "isbn13": "9780451532008", "isbn10": "0451532007", "average_rating": 4.01, "ratings_count": 450000},
        {"title": "Brave New World", "authors": "Aldous Huxley", "isbn13": "9780060850524", "isbn10": "0060850523", "average_rating": 3.99, "ratings_count": 1300000},
        {"title": "Işık", "authors": "Sevgi Soysal", "isbn13": "9789750500001", "isbn10": "9750500001", "average_rating": 4.20, "ratings_count": 500},
        {"title": "Harry Potter and the Sorcerer's Stone", "authors": "J.K. Rowling", "isbn13": "9780439708180", "isbn10": "0439708184", "average_rating": 4.47, "ratings_count": 6000000},
        {"title": "Harry Potter and the Chamber of Secrets", "authors": "J.K. Rowling", "isbn13": "9780439064873", "isbn10": "0439064872", "average_rating": 4.42, "ratings_count": 2500000},
        {"title": "Unrated Rare Manuscript", "authors": "Anonymous Scribe", "isbn13": "9780000000001", "isbn10": "0000000001", "average_rating": None, "ratings_count": None},
    ]
    rec.df = pd.DataFrame(data)
    rec.recommend.return_value = []
    return rec


@pytest.fixture
def rag_use_case(mock_catalog_recommender):
    mock_emb = MagicMock(spec=EmbeddingPort)
    mock_emb.generate_embedding.return_value = [0.1, 0.2]
    mock_data = MagicMock(spec=BookDataPort)
    mock_data.match_query_embeddings.return_value = {}
    mock_enr = MagicMock(spec=EnrichmentPort)
    mock_enr.enrich.side_effect = lambda b: b
    mock_llm = MagicMock(spec=LlmPort)
    mock_llm.generate_response.return_value = "Mock LLM Response"

    use_case = ProcessRagQueryUseCase(
        embedding_port=mock_emb,
        book_data_port=mock_data,
        interaction_repo=None,
        recommender=mock_catalog_recommender,
        enrichment_service=mock_enr,
        llm_port=mock_llm,
    )
    return use_case, mock_emb, mock_llm, mock_data


@pytest.mark.unit
def test_positive_catalog_existence_bypasses_llm_and_embedding(rag_use_case):
    use_case, mock_emb, mock_llm, mock_data = rag_use_case

    queries = [
        "1984 kitabı var mı?",
        "1984 kitabi var mi?",
        "   1984    kitabı   var   mı?   ",
        "The Alchemist kitabı var mı?",
        "Alice in Wonderland kitabı var mı?",
        "Do you have 1984?",
        "Gibt es 1984?",
    ]

    for q in queries:
        mock_emb.reset_mock()
        mock_llm.reset_mock()
        mock_data.reset_mock()

        res = use_case.execute(q)
        assert res["status"] == "success"
        assert len(res["referenced_books"]) > 0

        # Test spies prove 100% bypass of expensive upstream services
        mock_emb.generate_embedding.assert_not_called()
        mock_llm.generate_response.assert_not_called()
        mock_data.match_query_embeddings.assert_not_called()


@pytest.mark.unit
def test_turkish_dotless_and_dotted_i_matching(rag_use_case):
    use_case, mock_emb, mock_llm, _ = rag_use_case

    # Query with uppercase dotless I vs lowercase dotless ı vs lowercase dotted i
    res1 = use_case.execute("Işık kitabı var mı?")
    assert res1["status"] == "success"
    assert any("Işık" in b["title"] for b in res1["referenced_books"])

    res2 = use_case.execute("ışık kitabı var mı?")
    assert res2["status"] == "success"
    assert any("Işık" in b["title"] for b in res2["referenced_books"])

    mock_emb.generate_embedding.assert_not_called()
    mock_llm.generate_response.assert_not_called()


@pytest.mark.unit
def test_possessive_and_inflection_variants_author_lookup(rag_use_case):
    use_case, mock_emb, mock_llm, _ = rag_use_case

    queries = [
        "1984'ün yazarı kim?",
        "1984ün yazarı kim?",
        "1984un yazari kim?",
        "Who wrote 1984?",
        "Wer hat 1984 geschrieben?",
    ]

    for q in queries:
        mock_emb.reset_mock()
        mock_llm.reset_mock()

        res = use_case.execute(q)
        assert res["status"] == "success"
        assert "George Orwell" in res["answer"]
        mock_emb.generate_embedding.assert_not_called()
        mock_llm.generate_response.assert_not_called()


@pytest.mark.unit
def test_rating_lookup_and_unrated_truthful_handling(rag_use_case):
    use_case, mock_emb, mock_llm, _ = rag_use_case

    # Rated book
    res1 = use_case.execute("1984 kitabı kaç puan almış?")
    assert res1["status"] == "success"
    assert "4.17" in res1["answer"]
    mock_emb.generate_embedding.assert_not_called()
    mock_llm.generate_response.assert_not_called()

    # Unrated book: must NOT fabricate 0 or NaN, must truthfully report unrated
    res2 = use_case.execute("Unrated Rare Manuscript kaç puan almış?")
    assert res2["status"] == "success"
    assert "puan kaydı bulunmamaktadır" in res2["answer"] or "rating unavailable" in res2["answer"].lower()
    assert "NaN" not in res2["answer"]


@pytest.mark.unit
def test_substring_rejection_and_nonexistent_book(rag_use_case):
    use_case, mock_emb, mock_llm, _ = rag_use_case

    # "198" is a substring of "1984", but NOT a book
    res1 = use_case.execute("198 kitabı var mı?")
    assert res1["status"] == "no_match"
    assert len(res1["referenced_books"]) == 0
    assert "1984" not in res1["answer"]

    # Totally nonexistent book
    res2 = use_case.execute("NonExistentSuperFakeBook998877 kitabı var mı?")
    assert res2["status"] == "no_match"
    assert len(res2["referenced_books"]) == 0


@pytest.mark.unit
def test_semantic_query_continues_to_retrieval_does_not_false_refuse(rag_use_case):
    use_case, mock_emb, mock_llm, mock_data = rag_use_case

    # A genre or thematic question that contains "var mı" must NOT be treated as a direct catalog lookup
    semantic_queries = [
        "Bilim kurgu kitapları var mı?",
        "Bana distopik kitaplar öner, var mı kütüphanenizde?",
        "Felsefe hakkında kitaplar var mı?",
    ]

    for q in semantic_queries:
        mock_emb.reset_mock()
        mock_llm.reset_mock()
        mock_data.reset_mock()

        res = use_case.execute(q)
        # Proves it continued to semantic retrieval rather than falsely rejecting as catalog miss
        assert res["status"] != "no_match"
        mock_emb.generate_embedding.assert_called_once()
