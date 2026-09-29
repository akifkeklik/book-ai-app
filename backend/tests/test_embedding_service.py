from unittest.mock import MagicMock, patch

from backend.services.embedding_service import EmbeddingService


def test_canonical_text():
    service = EmbeddingService()

    # Tüm alanlar dolu
    book = {
        "title": "The Matrix",
        "authors": "Wachowskis",
        "categories": "Sci-Fi",
        "description": "  A computer hacker learns from mysterious rebels about the true nature of his reality.  \n"
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
    assert len(hash1) == 64 # SHA-256

@patch("backend.services.embedding_service.OpenAI")
@patch("os.getenv")
def test_generate_embedding_success(mock_getenv, mock_openai):
    # Setup mock env vars
    def env_side_effect(key, default=None):
        if key == "OPENAI_API_KEY":
            return "fake-key"
        if key == "EMBEDDING_MODEL":
            return "text-embedding-3-small"
        if key == "EMBEDDING_DIMENSION":
            return "1536"
        return default
    mock_getenv.side_effect = env_side_effect

    # Setup mock OpenAI client
    mock_client_instance = MagicMock()
    mock_openai.return_value = mock_client_instance

    mock_response = MagicMock()
    mock_data = MagicMock()
    mock_data.embedding = [0.1, 0.2, 0.3]
    mock_response.data = [mock_data]
    mock_client_instance.embeddings.create.return_value = mock_response

    service = EmbeddingService()
    assert service.is_configured() is True

    emb = service.generate_embedding("Test text")
    assert emb == [0.1, 0.2, 0.3]
    mock_client_instance.embeddings.create.assert_called_once_with(
        input=["Test text"],
        model="text-embedding-3-small",
        dimensions=1536
    )

def test_get_existing_metadata():
    mock_supabase = MagicMock()
    mock_resp = MagicMock()
    mock_resp.data = [{"content_hash": "hash123", "model_version": "v1"}]
    mock_supabase.table().select().eq().execute.return_value = mock_resp

    service = EmbeddingService(supabase_client=mock_supabase)
    meta = service.get_existing_metadata("book1")

    assert meta == {"content_hash": "hash123", "model_version": "v1"}
    mock_supabase.table().select().eq.assert_called_with("book_id", "book1")

def test_get_existing_metadata_empty():
    mock_supabase = MagicMock()
    mock_resp = MagicMock()
    mock_resp.data = []
    mock_supabase.table().select().eq().execute.return_value = mock_resp

    service = EmbeddingService(supabase_client=mock_supabase)
    meta = service.get_existing_metadata("book1")

    assert meta is None

def test_upsert_embedding():
    mock_supabase = MagicMock()
    service = EmbeddingService(supabase_client=mock_supabase)
    service._model = "test-model"

    res = service.upsert_embedding("book1", [0.1, 0.2], "hash123")

    assert res is True
    mock_supabase.table().upsert.assert_called_once_with(
        {
            "book_id": "book1",
            "embedding": [0.1, 0.2],
            "content_hash": "hash123",
            "model_version": "test-model"
        },
        on_conflict="book_id"
    )

def test_is_stale():
    service = EmbeddingService(supabase_client=MagicMock())
    service._model = "model-v2"

    # No metadata in DB -> Stale
    service.get_existing_metadata = MagicMock(return_value=None)
    assert service.is_stale("book1", "hash123") is True

    # Same hash, same model -> Not Stale
    service.get_existing_metadata = MagicMock(return_value={"content_hash": "hash123", "model_version": "model-v2"})
    assert service.is_stale("book1", "hash123") is False

    # Different hash, same model -> Stale
    service.get_existing_metadata = MagicMock(return_value={"content_hash": "hash-old", "model_version": "model-v2"})
    assert service.is_stale("book1", "hash123") is True

    # Same hash, different model -> Stale
    service.get_existing_metadata = MagicMock(return_value={"content_hash": "hash123", "model_version": "model-v1"})
    assert service.is_stale("book1", "hash123") is True
