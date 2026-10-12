from unittest.mock import patch

import pytest
from backend.app import create_app
from backend.config import Config


class HealthTestConfig(Config):
    TESTING = True
    DEBUG = False
    ENFORCE_AUTH_IN_TESTS = True
    LIBRIS_API_KEY = "strictly-required-api-key"
    SECRET_KEY = "test-secret-key"

@pytest.fixture
def client():
    app = create_app(HealthTestConfig)
    with app.test_client() as c:
        yield c

def test_api_health_is_public_and_minimal(client):
    """Liveness probe must be public and return simple status without secrets."""
    res = client.get("/api/health")
    assert res.status_code == 200
    data = res.get_json()
    assert data == {"service": "book-ai-api", "status": "healthy"}
    # Verify no secret headers
    assert "X-Api-Key" not in res.headers
    assert "Authorization" not in res.headers

def test_api_health_ready_is_exempt_from_auth(client):
    """Readiness probe must NOT require X-Api-Key or Authorization header."""
    with patch("backend.routes.routes._book_data_port") as mock_port:
        mock_port.check_health.return_value = True
        res = client.get("/api/health/ready")
        assert res.status_code == 200
        data = res.get_json()
        assert data == {"service": "book-ai-api", "status": "ready"}

def test_api_health_ready_handles_database_failure_cleanly(client):
    """When DB is down, readiness returns 503 without leaking internal stack traces."""
    with patch("backend.routes.routes._book_data_port") as mock_port:
        mock_port.check_health.return_value = False
        res = client.get("/api/health/ready")
        assert res.status_code == 503
        data = res.get_json()
        assert data["status"] == "not_ready"
        assert data["error"] == "Database unavailable"
        assert "traceback" not in data
        assert "password" not in str(data)
