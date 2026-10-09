import threading
from unittest.mock import MagicMock, patch

import pytest
from backend.infrastructure.persistence.supabase_adapters import SupabaseInteractionRepository
from backend.routes.routes import books_bp
from flask import Flask, g


# Mock the entire _auth_port for the blueprint context
@pytest.fixture
def auth_app():
    app = Flask(__name__)
    app.register_blueprint(books_bp, url_prefix="/api")
    app.config["TESTING"] = True
    return app


def test_jwt_passed_to_supabase_client(auth_app):
    """Verify that a valid JWT in the request is passed to the scoped Supabase client."""
    repo = SupabaseInteractionRepository(supabase_client=MagicMock())

    with auth_app.test_request_context(
        "/api/feedback", headers={"Authorization": "Bearer test-jwt-123"}
    ):
        with patch("supabase.create_client") as mock_create:
            mock_client = MagicMock()
            mock_create.return_value = mock_client

            # Simulate routes.py setting the JWT in `g`
            g.jwt_token = "test-jwt-123"
            g.user_id = "user-1"

            # Call the repository method
            repo.upsert_interactions(
                [{"user_id": "user-1", "book_id": "book-1", "interaction_type": "like"}]
            )

            # Verify the scoped client was created and auth was set
            mock_create.assert_called_once()
            mock_client.postgrest.auth.assert_called_once_with("test-jwt-123")
            mock_client.table.assert_called_once_with("user_interactions")


def test_no_jwt_fallback_to_global_client(auth_app):
    """Verify that without a JWT (e.g. non-auth routes), it falls back to the global anonymous client."""
    global_mock = MagicMock()
    repo = SupabaseInteractionRepository(supabase_client=global_mock)

    with auth_app.test_request_context("/api/health"):
        with patch("supabase.create_client") as mock_create:
            # No jwt_token in `g`
            repo.upsert_interactions(
                [{"user_id": "user-1", "book_id": "book-1", "interaction_type": "like"}]
            )

            # Scoped client should NOT be created
            mock_create.assert_not_called()
            # Global client should be used
            global_mock.table.assert_called_once_with("user_interactions")


def test_concurrent_requests_do_not_mix_jwts(auth_app):
    """Verify that concurrent requests maintain their own JWT context (no race conditions)."""
    repo = SupabaseInteractionRepository(supabase_client=MagicMock())

    results = {}

    def simulate_request(token, user_id):
        with auth_app.test_request_context(
            f"/api/feedback?user={user_id}", headers={"Authorization": f"Bearer {token}"}
        ):
            with patch("supabase.create_client") as mock_create:
                mock_client = MagicMock()
                mock_create.return_value = mock_client

                g.jwt_token = token
                g.user_id = user_id

                repo.upsert_interactions(
                    [{"user_id": user_id, "book_id": "book-1", "interaction_type": "like"}]
                )

                # Store what token this thread actually passed to Supabase
                mock_client.postgrest.auth.assert_called_once()
                args, _ = mock_client.postgrest.auth.call_args
                results[user_id] = args[0]

    t1 = threading.Thread(target=simulate_request, args=("token-A", "user-A"))
    t2 = threading.Thread(target=simulate_request, args=("token-B", "user-B"))

    t1.start()
    t2.start()
    t1.join()
    t2.join()

    # Each thread should have securely passed its own token to the scoped client
    assert results["user-A"] == "token-A"
    assert results["user-B"] == "token-B"
