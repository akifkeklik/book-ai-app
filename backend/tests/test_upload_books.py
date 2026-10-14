import os
from unittest.mock import MagicMock, patch

import pytest
from backend.scripts.upload_books_to_supabase import upload_to_supabase


def test_upload_fails_closed_when_service_role_key_missing(tmp_path, monkeypatch):
    """Verify upload fails immediately without writing when SUPABASE_SERVICE_ROLE_KEY is missing."""
    csv_file = tmp_path / "books.csv"
    csv_file.write_text("isbn13,title\n9780001,Test Book\n", encoding="utf-8")

    monkeypatch.setenv("SUPABASE_URL", "https://test.supabase.co")
    monkeypatch.delenv("SUPABASE_SERVICE_ROLE_KEY", raising=False)
    monkeypatch.setenv("SUPABASE_ANON_KEY", "anon-key-that-must-not-be-used")

    with patch("backend.scripts.upload_books_to_supabase.create_client") as mock_client:
        with pytest.raises(ValueError, match="SUPABASE_SERVICE_ROLE_KEY is required"):
            upload_to_supabase(csv_path=str(csv_file))

        mock_client.assert_not_called()


def test_upload_fails_closed_when_url_missing(tmp_path, monkeypatch):
    """Verify upload fails immediately when SUPABASE_URL is missing."""
    csv_file = tmp_path / "books.csv"
    csv_file.write_text("isbn13,title\n9780001,Test Book\n", encoding="utf-8")

    monkeypatch.delenv("SUPABASE_URL", raising=False)
    monkeypatch.setenv("SUPABASE_SERVICE_ROLE_KEY", "dummy-service-key")

    with patch("backend.scripts.upload_books_to_supabase.Config") as mock_config:
        mock_config.SUPABASE_URL = ""
        with patch("backend.scripts.upload_books_to_supabase.create_client") as mock_client:
            with pytest.raises(ValueError, match="SUPABASE_URL environment variable is required"):
                upload_to_supabase(csv_path=str(csv_file))

            mock_client.assert_not_called()


def test_upload_never_falls_back_to_anon_key(tmp_path, monkeypatch):
    """Verify that having SUPABASE_ANON_KEY set never allows fallback if service key is missing."""
    csv_file = tmp_path / "books.csv"
    csv_file.write_text("isbn13,title\n9780001,Test Book\n", encoding="utf-8")

    monkeypatch.setenv("SUPABASE_URL", "https://test.supabase.co")
    monkeypatch.setenv("SUPABASE_ANON_KEY", "active-anon-key")
    monkeypatch.delenv("SUPABASE_SERVICE_ROLE_KEY", raising=False)

    with patch("backend.scripts.upload_books_to_supabase.create_client") as mock_client:
        with pytest.raises(ValueError, match="SUPABASE_SERVICE_ROLE_KEY"):
            upload_to_supabase(csv_path=str(csv_file))

        mock_client.assert_not_called()


def test_upload_succeeds_with_service_role_key(tmp_path, monkeypatch):
    """Verify upload initializes client with service role key and executes upsert."""
    csv_file = tmp_path / "books.csv"
    csv_file.write_text("isbn13,title,average_rating\n9780001,Test Book,4.5\n", encoding="utf-8")

    fake_service_key = "test-service-role-key-xyz"
    monkeypatch.setenv("SUPABASE_URL", "https://test.supabase.co")
    monkeypatch.setenv("SUPABASE_SERVICE_ROLE_KEY", fake_service_key)

    mock_supabase = MagicMock()
    mock_table = MagicMock()
    mock_upsert = MagicMock()
    mock_execute = MagicMock()

    mock_supabase.table.return_value = mock_table
    mock_table.upsert.return_value = mock_upsert
    mock_upsert.execute.return_value = mock_execute

    with patch("backend.scripts.upload_books_to_supabase.create_client", return_value=mock_supabase) as mock_create:
        total = upload_to_supabase(csv_path=str(csv_file))

        mock_create.assert_called_once_with("https://test.supabase.co", fake_service_key)
        mock_supabase.table.assert_called_once_with("books")
        mock_table.upsert.assert_called_once()
        assert total == 1


def test_upload_redacts_secret_in_error_logs(tmp_path, monkeypatch):
    """Verify that if an error occurs, the service role key is redacted from logs."""
    csv_file = tmp_path / "books.csv"
    csv_file.write_text("isbn13,title\n9780001,Test Book\n", encoding="utf-8")

    fake_service_key = "super-secret-service-role-key-999"
    monkeypatch.setenv("SUPABASE_URL", "https://test.supabase.co")
    monkeypatch.setenv("SUPABASE_SERVICE_ROLE_KEY", fake_service_key)

    mock_supabase = MagicMock()
    mock_table = MagicMock()
    mock_upsert = MagicMock()

    mock_supabase.table.return_value = mock_table
    mock_table.upsert.return_value = mock_upsert
    # Simulate an error that echoes the secret authorization header
    mock_upsert.execute.side_effect = Exception(f"HTTP 401 Unauthorized for Bearer {fake_service_key}")

    log_file = "upload_log.txt"
    if os.path.exists(log_file):
        try:
            os.remove(log_file)
        except OSError:
            pass

    with patch("backend.scripts.upload_books_to_supabase.create_client", return_value=mock_supabase):
        with pytest.raises(Exception):
            upload_to_supabase(csv_path=str(csv_file))

    try:
        assert os.path.exists(log_file)
        with open(log_file, "r", encoding="utf-8") as f:
            log_content = f.read()

        assert fake_service_key not in log_content
        assert "[REDACTED]" in log_content
    finally:
        if os.path.exists(log_file):
            try:
                os.remove(log_file)
            except OSError:
                pass
