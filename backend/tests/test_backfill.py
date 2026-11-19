import pathlib
import sys
from unittest.mock import MagicMock, patch

import pytest
from backend.scripts.backfill_embeddings import backfill_embeddings
from backend.services.embedding_service import EmbeddingService


def _real_profiles(svc, model):
    """The mocked service compares profiles with the real EmbeddingService rules."""
    svc._model = model
    svc.document_profile.return_value = EmbeddingService.normalize_profile(model)
    svc.normalize_profile.side_effect = EmbeddingService.normalize_profile
    svc.describe.return_value = {"model": model}


@patch.dict(sys.modules, {"psycopg2": MagicMock()})
@patch("backend.scripts.backfill_embeddings.EmbeddingService")
def test_backfill_loop(mock_embedding_service):
    mock_psycopg2 = sys.modules["psycopg2"]

    import os
    os.environ["SUPABASE_DB_URL"] = "postgres://test"

    # Mock psycopg2 connection
    mock_conn = MagicMock()
    mock_cursor = MagicMock()
    mock_psycopg2.connect.return_value = mock_conn
    mock_conn.cursor.return_value = mock_cursor

    # Setup the mock cursor to return columns and rows
    mock_cursor.description = [("isbn13",), ("title",), ("current_hash",), ("current_model",)]
    mock_cursor.fetchall.return_value = [
        ("book1", "Title 1", "hash1", "model-v1"),
        ("book2", "Title 2", "old_hash2", "model-v1"),
    ]

    # Setup Mock EmbeddingService
    mock_service_instance = MagicMock()
    mock_embedding_service.return_value = mock_service_instance
    mock_service_instance.is_configured.return_value = True

    mock_service_instance.generate_canonical_text.side_effect = ["text1", "text2"]
    mock_service_instance.generate_content_hash.side_effect = ["hash1", "hash2"]

    # Book 1 has current_hash == content_hash (hash1 == hash1), so it's skipped
    # Book 2 has old_hash2 != hash2, so it's processed

    _real_profiles(mock_service_instance, "model-v1")
    mock_service_instance.generate_embedding.return_value = [0.1, 0.2]

    # Call backfill
    backfill_embeddings(max_books=2)

    # Verification
    # generate_embedding should be called only for book2
    mock_service_instance.generate_embedding.assert_called_once_with("text2")
    # cursor.execute: 2 read-only preflight queries, the catalog SELECT, then one upsert for book2
    assert mock_cursor.execute.call_count == 4
    assert "INSERT INTO book_embeddings" in mock_cursor.execute.call_args_list[-1].args[0]
    # Ensure resources are closed cleanly
    mock_cursor.close.assert_called_once()
    mock_conn.close.assert_called_once()


@patch.dict(sys.modules, {"psycopg2": MagicMock()})
@patch("backend.scripts.backfill_embeddings.EmbeddingService")
def test_backfill_closes_resources_on_failure(mock_embedding_service):
    """Verify that cursor and connection are closed even when aborting due to failures."""
    import pytest

    mock_psycopg2 = sys.modules["psycopg2"]

    import os
    os.environ["SUPABASE_DB_URL"] = "postgres://test"

    mock_conn = MagicMock()
    mock_cursor = MagicMock()
    mock_psycopg2.connect.return_value = mock_conn
    mock_conn.cursor.return_value = mock_cursor

    mock_cursor.description = [("isbn13",), ("title",), ("current_hash",)]
    mock_cursor.fetchall.return_value = [
        ("book1", "Title 1", None),
        ("book2", "Title 2", None),
        ("book3", "Title 3", None),
    ]

    mock_service_instance = MagicMock()
    mock_embedding_service.return_value = mock_service_instance
    mock_service_instance.is_configured.return_value = True
    mock_service_instance.generate_canonical_text.return_value = "valid text"
    mock_service_instance.generate_content_hash.return_value = "hash-x"
    # Cause 3 consecutive failures to trigger abort
    mock_service_instance.generate_embedding.return_value = None

    with pytest.raises(SystemExit):
        backfill_embeddings(max_books=3)

    mock_cursor.close.assert_called_once()
    mock_conn.close.assert_called_once()


@patch.dict(sys.modules, {"psycopg2": MagicMock()})
@patch("backend.scripts.backfill_embeddings.EmbeddingService")
def test_backfill_reembeds_when_model_changed(mock_embedding_service):
    """Same text, different embedding model: the stored vector is in another space and is stale."""
    import os
    mock_psycopg2 = sys.modules["psycopg2"]
    os.environ["SUPABASE_DB_URL"] = "postgres://test"
    mock_cursor = MagicMock()
    mock_psycopg2.connect.return_value.cursor.return_value = mock_cursor
    mock_cursor.description = [("isbn13",), ("title",), ("current_hash",), ("current_model",)]
    mock_cursor.fetchall.return_value = [("book1", "Title 1", "hash1", "models/gemini-embedding-001")]
    svc = mock_embedding_service.return_value
    svc.is_configured.return_value = True
    svc.generate_canonical_text.return_value = "text1"
    svc.generate_content_hash.return_value = "hash1"
    _real_profiles(svc, "models/gemini-embedding-2")
    svc.generate_embedding.return_value = [0.1, 0.2]

    # A different stored profile is a full migration and needs the explicit flag.
    with pytest.raises(SystemExit) as exc:
        backfill_embeddings(max_books=1)
    assert exc.value.code == 2
    svc.generate_embedding.assert_not_called()

    backfill_embeddings(max_books=1, allow_profile_migration=True)
    svc.generate_embedding.assert_called_once_with("text1")
    insert_params = mock_cursor.execute.call_args_list[-1].args[1]
    assert insert_params[3] == "models/gemini-embedding-2;dim=3072;text=canonical_v1;task=RETRIEVAL_DOCUMENT"


@patch.dict(sys.modules, {"psycopg2": MagicMock()})
@patch("backend.scripts.backfill_embeddings.EmbeddingService")
def test_backfill_upsert_refreshes_updated_at(mock_embedding_service):
    """Regression: the conflict clause must bump updated_at when an embedding is replaced."""
    import os
    import re
    mock_psycopg2 = sys.modules["psycopg2"]
    os.environ["SUPABASE_DB_URL"] = "postgres://test"
    mock_cursor = MagicMock()
    mock_psycopg2.connect.return_value.cursor.return_value = mock_cursor
    mock_cursor.description = [("isbn13",), ("title",), ("current_hash",), ("current_model",)]
    mock_cursor.fetchall.return_value = [("book1", "Title 1", "old_hash", "model-v1")]
    svc = mock_embedding_service.return_value
    svc.is_configured.return_value = True
    svc.generate_canonical_text.return_value = "text1"
    svc.generate_content_hash.return_value = "new_hash"
    _real_profiles(svc, "model-v1")
    svc.generate_embedding.return_value = [0.1, 0.2]

    backfill_embeddings(max_books=1)

    upsert_sql = mock_cursor.execute.call_args_list[-1].args[0]
    assert "ON CONFLICT (book_id) DO UPDATE" in upsert_sql
    assert re.search(r"updated_at\s*=\s*now\(\)", upsert_sql)


def _cursor_with_preflight(privileges=(True, True, True, True), rls_applies=False):
    """A cursor whose two preflight fetchone() calls return the given privilege/RLS answers."""
    cursor = MagicMock()
    cursor.fetchone.side_effect = [("postgres", *privileges), (rls_applies,)]
    return cursor


def test_backfill_does_not_use_supabase_rest_client():
    """The job reads and writes over PostgreSQL only, so SUPABASE_ANON_KEY's format cannot break it."""
    import backend.scripts.backfill_embeddings as mod
    source = pathlib.Path(mod.__file__).read_text(encoding="utf-8")
    assert "create_client" not in source
    assert "SUPABASE_ANON_KEY" not in source


@patch.dict(sys.modules, {"psycopg2": MagicMock()})
@patch("backend.scripts.backfill_embeddings.EmbeddingService")
def test_check_mode_is_read_only(mock_embedding_service, monkeypatch):
    monkeypatch.setenv("SUPABASE_DB_URL", "postgres://test")
    cursor = _cursor_with_preflight()
    sys.modules["psycopg2"].connect.return_value.cursor.return_value = cursor
    cursor.description = [("isbn13",), ("title",), ("current_hash",), ("current_model",)]
    cursor.fetchall.return_value = [("b1", "T1", "h1", "m"), ("b2", "T2", "old", "m"), ("b3", "T3", None, None)]
    svc = mock_embedding_service.return_value
    svc.is_configured.return_value = False  # no Gemini key needed for a check
    svc.generate_canonical_text.side_effect = ["t1", "t2", "t3"]
    svc.generate_content_hash.side_effect = ["h1", "h2", "h3"]
    _real_profiles(svc, "m")

    result = backfill_embeddings(check_only=True)

    assert result["would_embed"] == 2 and result["up_to_date"] == 1
    svc.generate_embedding.assert_not_called()
    statements = [c.args[0] for c in cursor.execute.call_args_list]
    assert all("INSERT INTO" not in s.upper() for s in statements)


@patch.dict(sys.modules, {"psycopg2": MagicMock()})
@patch("backend.scripts.backfill_embeddings.EmbeddingService")
def test_missing_write_privilege_aborts_before_embedding(mock_embedding_service, monkeypatch, caplog):
    monkeypatch.setenv("SUPABASE_DB_URL", "postgres://test")
    cursor = _cursor_with_preflight(privileges=(True, True, False, False))
    conn = sys.modules["psycopg2"].connect.return_value
    conn.cursor.return_value = cursor
    svc = mock_embedding_service.return_value
    svc.is_configured.return_value = True

    with pytest.raises(SystemExit) as exc:
        backfill_embeddings()
    assert exc.value.code == 3
    svc.generate_embedding.assert_not_called()
    assert "GRANT INSERT ON public.book_embeddings" in caplog.text
    assert "GRANT UPDATE ON public.book_embeddings" in caplog.text
    cursor.close.assert_called_once()
    conn.close.assert_called_once()


@patch.dict(sys.modules, {"psycopg2": MagicMock()})
@patch("backend.scripts.backfill_embeddings.EmbeddingService")
def test_connection_failure_is_classified_and_redacted(mock_embedding_service, monkeypatch, caplog):
    secret_url = "postgresql://postgres.ref:S3cretPassw0rd@db.example.com:6543/postgres"
    monkeypatch.setenv("SUPABASE_DB_URL", secret_url)
    sys.modules["psycopg2"].connect.side_effect = Exception(
        f'connection to {secret_url} failed: FATAL: password authentication failed for user "postgres.ref" '
        "S3cretPassw0rd")
    mock_embedding_service.return_value.is_configured.return_value = True

    with pytest.raises(SystemExit):
        backfill_embeddings()
    assert "[auth]" in caplog.text
    assert "S3cretPassw0rd" not in caplog.text
    assert secret_url not in caplog.text
