from unittest.mock import MagicMock, patch

from backend.scripts.backfill_embeddings import backfill_embeddings


@patch("backend.scripts.backfill_embeddings.EmbeddingService")
@patch("backend.scripts.backfill_embeddings.create_client")
@patch("backend.scripts.backfill_embeddings.Config")
def test_backfill_loop(mock_config, mock_create_client, mock_embedding_service):
    # Setup Config
    mock_config.SUPABASE_URL = "http://test"
    mock_config.SUPABASE_ANON_KEY = "test_key"

    # Setup Mock Supabase
    mock_supabase = MagicMock()
    mock_create_client.return_value = mock_supabase

    # First batch returns 2 books, second batch returns 0
    mock_resp1 = MagicMock()
    mock_resp1.data = [
        {"isbn13": "book1", "title": "Title 1"},
        {"isbn13": "book2", "title": "Title 2"}
    ]
    mock_resp2 = MagicMock()
    mock_resp2.data = []

    # We have to mock the chained calls: table("books").select("*").order("isbn13").gt("isbn13", last_id).limit(limit).execute()
    mock_table = MagicMock()
    mock_select = MagicMock()
    mock_order = MagicMock()
    mock_limit = MagicMock()

    mock_supabase.table.return_value = mock_table
    mock_table.select.return_value = mock_select
    mock_select.order.return_value = mock_order
    mock_order.gt.return_value = mock_limit
    mock_limit.limit.return_value = MagicMock()
    # The final execute() should return mock_resp1 then mock_resp2
    mock_limit.limit.return_value.execute.side_effect = [mock_resp1, mock_resp2]

    # Setup Mock EmbeddingService
    mock_service_instance = MagicMock()
    mock_embedding_service.return_value = mock_service_instance
    mock_service_instance.is_configured.return_value = True

    mock_service_instance.generate_canonical_text.side_effect = ["text1", "text2"]
    mock_service_instance.generate_content_hash.side_effect = ["hash1", "hash2"]

    # Book 1 is up-to-date, Book 2 needs update
    mock_service_instance._model = "model-v1"
    mock_service_instance.is_stale.side_effect = [
        False, # Skip book1 (not stale)
        True # Process book2 (stale)
    ]

    mock_service_instance.generate_embedding.return_value = [0.1, 0.2]
    mock_service_instance.upsert_embedding.return_value = True

    # Call backfill
    backfill_embeddings(batch_size=2)

    # Verification
    # generate_embedding should be called only for book2
    mock_service_instance.generate_embedding.assert_called_once_with("text2")
    mock_service_instance.upsert_embedding.assert_called_once_with("book2", [0.1, 0.2], "hash2")
