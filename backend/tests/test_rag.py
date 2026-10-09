from unittest.mock import MagicMock
import pytest

from backend.application.use_cases.ai_rag import ProcessRagQueryUseCase
from backend.domain.ports import BookDataPort, EmbeddingPort, LlmPort, RecommenderPort, EnrichmentPort


@pytest.mark.unit
def test_process_rag_query_success():
    mock_embedding = MagicMock(spec=EmbeddingPort)
    mock_data_port = MagicMock(spec=BookDataPort)
    mock_recommender = MagicMock(spec=RecommenderPort)
    mock_enrichment = MagicMock(spec=EnrichmentPort)
    mock_llm = MagicMock(spec=LlmPort)

    mock_embedding.generate_embedding.return_value = [0.1, 0.2, 0.3]

    # Mock retrieval
    mock_data_port.match_query_embeddings.return_value = {"123": 0.9}
    mock_recommender.recommend.return_value = [
        {"isbn13": "123", "title": "Fantasy Book", "authors": "Author 1"}
    ]
    mock_enrichment.enrich.side_effect = lambda books: books

    mock_llm.generate_response.return_value = "This is a great fantasy book."

    use_case = ProcessRagQueryUseCase(
        embedding_port=mock_embedding,
        book_data_port=mock_data_port,
        interaction_repo=None,
        recommender=mock_recommender,
        enrichment_service=mock_enrichment,
        llm_port=mock_llm
    )

    response = use_case.execute("I want a fantasy book")

    assert response["answer"] == "This is a great fantasy book."
    assert len(response["referenced_books"]) == 1

    mock_embedding.generate_embedding.assert_called_once()
    mock_data_port.match_query_embeddings.assert_called_once()
    mock_llm.generate_response.assert_called_once()

@pytest.mark.unit
def test_process_rag_query_empty_retrieval():
    mock_embedding = MagicMock(spec=EmbeddingPort)
    mock_data_port = MagicMock(spec=BookDataPort)
    mock_recommender = MagicMock(spec=RecommenderPort)
    mock_enrichment = MagicMock(spec=EnrichmentPort)
    mock_llm = MagicMock(spec=LlmPort)

    mock_embedding.generate_embedding.return_value = [0.1, 0.2, 0.3]
    mock_data_port.match_query_embeddings.return_value = {}
    mock_recommender.recommend.return_value = []
    mock_enrichment.enrich.side_effect = lambda books: books

    mock_llm.generate_response.return_value = "I couldn't find any books."

    use_case = ProcessRagQueryUseCase(
        embedding_port=mock_embedding,
        book_data_port=mock_data_port,
        interaction_repo=None,
        recommender=mock_recommender,
        enrichment_service=mock_enrichment,
        llm_port=mock_llm
    )
    response = use_case.execute("I want a weird book")

    assert response["answer"] == "I couldn't find any books in my library matching your description."
    assert len(response["referenced_books"]) == 0

@pytest.mark.unit
def test_process_rag_query_embedding_failure():
    mock_embedding = MagicMock(spec=EmbeddingPort)
    mock_embedding.generate_embedding.return_value = None

    use_case = ProcessRagQueryUseCase(
        embedding_port=mock_embedding,
        book_data_port=MagicMock(),
        interaction_repo=None,
        recommender=MagicMock(),
        enrichment_service=MagicMock(),
        llm_port=MagicMock()
    )
    response = use_case.execute("Fail me")

    assert response["status"] == "embedding_failed"
    assert response["answer"] == "I'm having trouble understanding your query right now. Please try again later."
    assert len(response.get("referenced_books", [])) == 0
