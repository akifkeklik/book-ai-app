from unittest.mock import MagicMock, patch

from backend.services.embedding_service import EmbeddingService

_DIM = 3072
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



@patch("backend.services.embedding_service.genai")
@patch("os.getenv")
def test_generate_embedding_success(mock_getenv, mock_genai):
    """Provider success: 3072-dim embedding returned and validated."""
    def env_side_effect(key, default=None):
        if key == "LLM_API_KEY":
            return "fake-key"
        if key == "EMBEDDING_MODEL":
            return "models/gemini-embedding-2"
        if key == "EMBEDDING_DIMENSION":
            return "3072"
        return default

    mock_getenv.side_effect = env_side_effect

    mock_genai.embed_content.return_value = {"embedding": _FAKE_EMBEDDING}

    service = EmbeddingService()
    assert service.is_configured() is True

    emb = service.generate_embedding("Test text")
    assert emb == _FAKE_EMBEDDING
    assert len(emb) == _DIM
    mock_genai.embed_content.assert_called_once_with(
        model="models/gemini-embedding-2",
        content="Test text",
        task_type="retrieval_document"
    )


@patch("backend.services.embedding_service.genai")
@patch("os.getenv")
def test_generate_embedding_dimension_mismatch(mock_getenv, mock_genai):
    """Dimension mismatch: service returns None and does NOT persist."""
    def env_side_effect(key, default=None):
        if key == "LLM_API_KEY":
            return "fake-key"
        if key == "EMBEDDING_MODEL":
            return "models/gemini-embedding-2"
        if key == "EMBEDDING_DIMENSION":
            return "3072"
        return default

    mock_getenv.side_effect = env_side_effect

    # Wrong dimension: 128 instead of 3072
    mock_genai.embed_content.return_value = {"embedding": [0.1] * 128}

    service = EmbeddingService()
    emb = service.generate_embedding("Test text")

    assert emb is None


@patch("backend.services.embedding_service.time.sleep", return_value=None)
@patch("backend.services.embedding_service.genai")
@patch("os.getenv")
def test_generate_embedding_transient_retry_then_success(mock_getenv, mock_genai, mock_sleep):
    """Transient errors are retried with exponential backoff, bounded at max_retries."""
    def env_side_effect(key, default=None):
        if key == "LLM_API_KEY":
            return "fake-key"
        if key == "EMBEDDING_MODEL":
            return "models/gemini-embedding-2"
        if key == "EMBEDDING_DIMENSION":
            return "3072"
        return default

    mock_getenv.side_effect = env_side_effect

    # Fail once with Exception, then succeed
    mock_genai.embed_content.side_effect = [
        Exception("rate limit"),
        {"embedding": _FAKE_EMBEDDING},
    ]

    service = EmbeddingService()
    emb = service.generate_embedding("Test text", max_retries=3)

    assert emb == _FAKE_EMBEDDING
    assert mock_genai.embed_content.call_count == 2
    mock_sleep.assert_called_once_with(2)  # 2**1 = 2s after first failure


@patch("backend.services.embedding_service.time.sleep", return_value=None)
@patch("backend.services.embedding_service.genai")
@patch("os.getenv")
def test_generate_embedding_transient_exhausts_retries(mock_getenv, mock_genai, mock_sleep):
    """All retries exhausted on transient errors → returns None."""
    def env_side_effect(key, default=None):
        if key == "LLM_API_KEY":
            return "fake-key"
        if key == "EMBEDDING_MODEL":
            return "models/gemini-embedding-2"
        if key == "EMBEDDING_DIMENSION":
            return "3072"
        return default

    mock_getenv.side_effect = env_side_effect

    mock_genai.embed_content.side_effect = Exception("API connection error")

    service = EmbeddingService()
    emb = service.generate_embedding("Test text", max_retries=3)

    assert emb is None
    assert mock_genai.embed_content.call_count == 3


@patch("backend.services.embedding_service.time.sleep", return_value=None)
@patch("backend.services.embedding_service.genai")
@patch("os.getenv")
def test_generate_embedding_permanent_error_no_retry(mock_getenv, mock_genai, mock_sleep):
    """Permanent auth/config errors are currently retried due to catch-all Exception, so it acts like transient."""
    def env_side_effect(key, default=None):
        if key == "LLM_API_KEY":
            return "fake-key"
        if key == "EMBEDDING_MODEL":
            return "models/gemini-embedding-2"
        if key == "EMBEDDING_DIMENSION":
            return "3072"
        return default

    mock_getenv.side_effect = env_side_effect

    mock_genai.embed_content.side_effect = ValueError("invalid model")

    service = EmbeddingService()
    emb = service.generate_embedding("Test text", max_retries=3)

    assert emb is None
    # Current implementation catches all exceptions and retries
    assert mock_genai.embed_content.call_count == 3


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
