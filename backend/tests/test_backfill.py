import sys
from unittest.mock import MagicMock, patch

from backend.scripts.backfill_embeddings import backfill_embeddings

# Inject psycopg2 into sys.modules so the local import in the script gets the mock
mock_psycopg2 = MagicMock()
sys.modules["psycopg2"] = mock_psycopg2


@patch("backend.scripts.backfill_embeddings.create_client")
@patch("backend.scripts.backfill_embeddings.Config")
@patch("backend.scripts.backfill_embeddings.EmbeddingService")
def test_backfill_loop(mock_embedding_service, mock_config, mock_create_client):
    mock_config.SUPABASE_URL = "https://test.supabase.co"
    mock_config.SUPABASE_ANON_KEY = "dummy.header.payload"

    import os
    os.environ["SUPABASE_DB_URL"] = "postgres://test"

    # Mock psycopg2 connection
    mock_conn = MagicMock()
    mock_cursor = MagicMock()
    mock_psycopg2.connect.return_value = mock_conn
    mock_conn.cursor.return_value = mock_cursor

    # Setup the mock cursor to return columns and rows
    mock_cursor.description = [("isbn13",), ("title",), ("current_hash",)]
    mock_cursor.fetchall.return_value = [
        ("book1", "Title 1", "hash1"),
        ("book2", "Title 2", "old_hash2")
    ]

    # Setup Mock EmbeddingService
    mock_service_instance = MagicMock()
    mock_embedding_service.return_value = mock_service_instance
    mock_service_instance.is_configured.return_value = True

    mock_service_instance.generate_canonical_text.side_effect = ["text1", "text2"]
    mock_service_instance.generate_content_hash.side_effect = ["hash1", "hash2"]

    # Book 1 has current_hash == content_hash (hash1 == hash1), so it's skipped
    # Book 2 has old_hash2 != hash2, so it's processed

    mock_service_instance._model = "model-v1"
    mock_service_instance.generate_embedding.return_value = [0.1, 0.2]

    # Call backfill
    backfill_embeddings(max_books=2)

    # Verification
    # generate_embedding should be called only for book2
    mock_service_instance.generate_embedding.assert_called_once_with("text2")
    # cursor.execute should be called for SELECT and then INSERT/UPDATE for book2
    assert mock_cursor.execute.call_count == 2
