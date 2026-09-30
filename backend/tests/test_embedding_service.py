from unittest.mock import MagicMock, patch

import openai
from backend.services.embedding_service import EmbeddingService

_DIM = 1536
_FAKE_EMBEDDING = [0.01] * _DIM


def test_canonical_text():
    service = EmbeddingService()

    # Tüm alanlar dolu
    book = {
        "title": "The Matrix",
        "authors": "Wachowskis",
        "categories": "Sci-Fi",
        "description": "  A computer hacker learns from mysterious rebels about the true nature of his reality.  \n",
    }

    text = service.generate_canonical_text(book)

    assert "Title: The Matrix" in text
    assert "Authors: Wachowskis" in text
    assert "Categories: Sci-Fi" in text
    assert "Description: A computer hacker learns from mysterious rebels about the true nature of his reality." in text

    # Sadece title var
    book_partial = {"title": "Just a Title", "authors": None, "categories": ""}
    text_partial = service.generate_canonical_text(book_partial)

    assert "Title: Just a Title" in text_partial
    assert "Authors:" not in text_partial
    assert "Categories:" not in text_partial


def test_content_hash():
    service = EmbeddingService()
    text1 = "Title: The Matrix\nAuthors: Wachowskis"
    text2 = "Title: The Matrix\nAuthors: Wachowskis"
    text3 = "Title: The Matrix\nAuthors: Wachowskis\nCategories: Sci-Fi"

    hash1 = service.generate_content_hash(text1)
    hash2 = service.generate_content_hash(text2)
    hash3 = service.generate_content_hash(text3)

    assert hash1 == hash2
    assert hash1 != hash3
    assert len(hash1) == 64  # SHA-256


@patch("backend.services.embedding_service.OpenAI")
@patch("os.getenv")
def test_generate_embedding_success(mock_getenv, mock_openai):
    """Provider success: 1536-dim embedding returned and validated."""
    def env_side_effect(key, default=None):
        if key == "OPENAI_API_KEY":
            return "fake-key"
        if key == "EMBEDDING_MODEL":
            return "text-embedding-3-small"
        if key == "EMBEDDING_DIMENSION":
            return "1536"
        return default

    mock_getenv.side_effect = env_side_effect

    mock_client_instance = MagicMock()
    mock_openai.return_value = mock_client_instance

    mock_response = MagicMock()
    mock_data = MagicMock()
    # Must be exactly 1536 elements to pass dimension validation
    mock_data.embedding = _FAKE_EMBEDDING
    mock_response.data = [mock_data]
    mock_client_instance.embeddings.create.return_value = mock_response

    service = EmbeddingService()
    assert service.is_configured() is True

    emb = service.generate_embedding("Test text")
    assert emb == _FAKE_EMBEDDING
    assert len(emb) == _DIM
    mock_client_instance.embeddings.create.assert_called_once_with(
        input=["Test text"],
        model="text-embedding-3-small",
        dimensions=1536,
    )


@patch("backend.services.embedding_service.OpenAI")
@patch("os.getenv")
def test_generate_embedding_dimension_mismatch(mock_getenv, mock_openai):
    """Dimension mismatch: service returns None and does NOT persist."""
    def env_side_effect(key, default=None):
        if key == "OPENAI_API_KEY":
            return "fake-key"
        if key == "EMBEDDING_MODEL":
            return "text-embedding-3-small"
        if key == "EMBEDDING_DIMENSION":
            return "1536"
        return default

    mock_getenv.side_effect = env_side_effect

    mock_client_instance = MagicMock()
    mock_openai.return_value = mock_client_instance

    mock_response = MagicMock()
    mock_data = MagicMock()
    # Wrong dimension: 128 instead of 1536
    mock_data.embedding = [0.1] * 128
    mock_response.data = [mock_data]
    mock_client_instance.embeddings.create.return_value = mock_response

    service = EmbeddingService()
    emb = service.generate_embedding("Test text")

    assert emb is None


@patch("backend.services.embedding_service.time.sleep", return_value=None)
@patch("backend.services.embedding_service.OpenAI")
@patch("os.getenv")
def test_generate_embedding_transient_retry_then_success(mock_getenv, mock_openai, mock_sleep):
    """Transient errors are retried with exponential backoff, bounded at max_retries."""
    def env_side_effect(key, default=None):
        if key == "OPENAI_API_KEY":
            return "fake-key"
        if key == "EMBEDDING_MODEL":
            return "text-embedding-3-small"
        if key == "EMBEDDING_DIMENSION":
            return "1536"
        return default

    mock_getenv.side_effect = env_side_effect

    mock_client_instance = MagicMock()
    mock_openai.return_value = mock_client_instance

    mock_response = MagicMock()
    mock_data = MagicMock()
    mock_data.embedding = _FAKE_EMBEDDING
    mock_response.data = [mock_data]

    # Fail once with RateLimitError, then succeed
    mock_client_instance.embeddings.create.side_effect = [
        openai.RateLimitError("rate limit", response=MagicMock(), body={}),
        mock_response,
    ]

    service = EmbeddingService()
    emb = service.generate_embedding("Test text", max_retries=3)

    assert emb == _FAKE_EMBEDDING
    assert mock_client_instance.embeddings.create.call_count == 2
    mock_sleep.assert_called_once_with(2)  # 2**1 = 2s after first failure


@patch("backend.services.embedding_service.time.sleep", return_value=None)
@patch("backend.services.embedding_service.OpenAI")
@patch("os.getenv")
def test_generate_embedding_transient_exhausts_retries(mock_getenv, mock_openai, mock_sleep):
    """All retries exhausted on transient errors → returns None."""
    def env_side_effect(key, default=None):
        if key == "OPENAI_API_KEY":
            return "fake-key"
        if key == "EMBEDDING_MODEL":
            return "text-embedding-3-small"
        if key == "EMBEDDING_DIMENSION":
            return "1536"
        return default

    mock_getenv.side_effect = env_side_effect

    mock_client_instance = MagicMock()
    mock_openai.return_value = mock_client_instance

    mock_client_instance.embeddings.create.side_effect = openai.APIConnectionError(
        request=MagicMock()
    )

    service = EmbeddingService()
    emb = service.generate_embedding("Test text", max_retries=3)

    assert emb is None
    assert mock_client_instance.embeddings.create.call_count == 3


@patch("backend.services.embedding_service.OpenAI")
@patch("os.getenv")
def test_generate_embedding_permanent_error_no_retry(mock_getenv, mock_openai):
    """Permanent auth/config errors are NOT retried."""
    def env_side_effect(key, default=None):
        if key == "OPENAI_API_KEY":
            return "fake-key"
        if key == "EMBEDDING_MODEL":
            return "text-embedding-3-small"
        if key == "EMBEDDING_DIMENSION":
            return "1536"
        return default

    mock_getenv.side_effect = env_side_effect

    mock_client_instance = MagicMock()
    mock_openai.return_value = mock_client_instance

    # openai.APIError is the base permanent error (not transient sub-classes)
    mock_client_instance.embeddings.create.side_effect = openai.BadRequestError(
        "invalid model", response=MagicMock(), body={}
    )

    service = EmbeddingService()
    emb = service.generate_embedding("Test text", max_retries=3)

    assert emb is None
    # Permanent error → called exactly once (no retry)
    assert mock_client_instance.embeddings.create.call_count == 1


def test_get_existing_metadata():
    mock_port = MagicMock()
    mock_port.get_embedding_metadata.return_value = {"content_hash": "hash123", "model_version": "v1"}

    service = EmbeddingService(book_data_port=mock_port)
    meta = service.get_existing_metadata("book1")

    assert meta == {"content_hash": "hash123", "model_version": "v1"}
    mock_port.get_embedding_metadata.assert_called_with("book1")


def test_get_existing_metadata_empty():
    mock_port = MagicMock()
    mock_port.get_embedding_metadata.return_value = None

    service = EmbeddingService(book_data_port=mock_port)
    meta = service.get_existing_metadata("book1")

    assert meta is None


def test_upsert_embedding():
    mock_port = MagicMock()
    service = EmbeddingService(book_data_port=mock_port)
    service._model = "test-model"

    res = service.upsert_embedding("book1", [0.1, 0.2], "hash123")

    assert res is True
    mock_port.upsert_embedding.assert_called_once_with(
        book_id="book1",
        embedding=[0.1, 0.2],
        content_hash="hash123",
        model_version="test-model",
    )


def test_is_stale():
    service = EmbeddingService(book_data_port=MagicMock())
    service._model = "model-v2"

    # No metadata in DB -> Stale
    service.get_existing_metadata = MagicMock(return_value=None)
    assert service.is_stale("book1", "hash123") is True

    # Same hash, same model -> Not Stale
    service.get_existing_metadata = MagicMock(
        return_value={"content_hash": "hash123", "model_version": "model-v2"}
    )
    assert service.is_stale("book1", "hash123") is False

    # Different hash, same model -> Stale
    service.get_existing_metadata = MagicMock(
        return_value={"content_hash": "hash-old", "model_version": "model-v2"}
    )
    assert service.is_stale("book1", "hash123") is True

    # Same hash, different model -> Stale
    service.get_existing_metadata = MagicMock(
        return_value={"content_hash": "hash123", "model_version": "model-v1"}
    )
    assert service.is_stale("book1", "hash123") is True
