import pytest
from backend.app import create_app
from backend.routes.routes import _ai_rate_limits

TEST_LIBRIS_API_KEY = "test-secret-libris-api-key-12345"
TEST_SUPABASE_ANON_KEY = "test-supabase-anon-key-67890"


class DummyUser:
    def __init__(self, user_id="user-uuid-abc"):
        self.id = user_id


class MockAuthPort:
    def verify_token(self, token):
        if token == "valid-user-jwt":
            return DummyUser("user-uuid-abc")
        if token == "valid-user-2-jwt":
            return DummyUser("user-uuid-def")
        raise Exception("Token invalid or expired")


class DummyRecommenderUC:
    def execute(self, user_id, limit=10):
        return [{"isbn13": "9781234567890", "title": "Personalized Book", "authors": "Author"}]


class DummyProcessRagUC:
    def execute(self, query, user_id=None):
        return {"answer": "AI recommendation", "referenced_books": [], "status": "success"}


@pytest.fixture
def auth_app(monkeypatch):
    """Flask application fixture with ENFORCE_AUTH_IN_TESTS enabled."""
    app = create_app()
    app.config["TESTING"] = True
    app.config["ENFORCE_AUTH_IN_TESTS"] = True
    app.config["LIBRIS_API_KEY"] = TEST_LIBRIS_API_KEY
    app.config["SUPABASE_ANON_KEY"] = TEST_SUPABASE_ANON_KEY

    # Mock auth port
    mock_port = MockAuthPort()
    monkeypatch.setattr("backend.routes.routes._auth_port", mock_port)
    monkeypatch.setattr("backend.routes.routes._get_personalized_recs_uc", DummyRecommenderUC())
    monkeypatch.setattr("backend.routes.routes._process_rag_query_uc", DummyProcessRagUC())

    _ai_rate_limits.clear()
    return app


@pytest.fixture
def auth_client(auth_app):
    return auth_app.test_client()


# ─────────────────────────────────────────────────────────────────────────────
# 1. Missing and Invalid API Key
# ─────────────────────────────────────────────────────────────────────────────


def test_missing_credentials_rejected_with_401(auth_client):
    resp = auth_client.get("/api/books")
    assert resp.status_code == 401
    data = resp.get_json()
    assert "Missing API Key or Bearer Token" in data["error"]


def test_server_valid_api_key_allows_catalog(auth_client):
    resp = auth_client.get("/api/categories", headers={"X-Api-Key": TEST_LIBRIS_API_KEY})
    assert resp.status_code == 200


def test_server_invalid_api_key_rejected_with_401(auth_client):
    resp = auth_client.get("/api/categories", headers={"X-Api-Key": "wrong-invalid-key"})
    assert resp.status_code == 401
    data = resp.get_json()
    assert "Invalid API Key" in data["error"]


def test_server_empty_api_key_rejected_with_401(auth_client):
    # Empty string API key
    resp_empty = auth_client.get("/api/categories", headers={"X-Api-Key": ""})
    assert resp_empty.status_code == 401
    assert "Invalid API Key" in resp_empty.get_json()["error"]

    # Whitespace-only API key
    resp_space = auth_client.get("/api/categories", headers={"X-Api-Key": "   "})
    assert resp_space.status_code == 401
    assert "Invalid API Key" in resp_space.get_json()["error"]


# ─────────────────────────────────────────────────────────────────────────────
# 2. Anonymous Access with Supabase Anon Key
# ─────────────────────────────────────────────────────────────────────────────


def test_anonymous_access_with_supabase_anon_key_allows_catalog(auth_client):
    resp = auth_client.get(
        "/api/categories", headers={"Authorization": f"Bearer {TEST_SUPABASE_ANON_KEY}"}
    )
    assert resp.status_code == 200


def test_fake_unverifiable_bearer_token_rejected_with_401(auth_client):
    resp = auth_client.get(
        "/api/categories", headers={"Authorization": "Bearer fake-random-token-123"}
    )
    assert resp.status_code == 401
    data = resp.get_json()
    assert "Invalid or expired Bearer token" in data["error"]


def test_anonymous_access_to_protected_endpoint_rejected_with_401(auth_client):
    resp = auth_client.get(
        "/api/recommend/personalized", headers={"Authorization": f"Bearer {TEST_SUPABASE_ANON_KEY}"}
    )
    assert resp.status_code == 401
    data = resp.get_json()
    assert "Real user authentication required" in data["error"]


# ─────────────────────────────────────────────────────────────────────────────
# 3. User JWT Authentication
# ─────────────────────────────────────────────────────────────────────────────


def test_valid_user_jwt_allows_protected_endpoint(auth_client):
    resp = auth_client.get(
        "/api/recommend/personalized", headers={"Authorization": "Bearer valid-user-jwt"}
    )
    assert resp.status_code == 200
    data = resp.get_json()
    assert data["user_id"] == "user-uuid-abc"


def test_invalid_user_jwt_rejected_on_protected_endpoint(auth_client):
    resp = auth_client.get(
        "/api/recommend/personalized", headers={"Authorization": "Bearer expired-or-tampered-token"}
    )
    assert resp.status_code == 401
    data = resp.get_json()
    assert "Invalid or expired" in data["error"]


# ─────────────────────────────────────────────────────────────────────────────
# 4. AI Endpoint Rate Limiting & Cost Control
# ─────────────────────────────────────────────────────────────────────────────


def test_ai_chat_rate_limiting_for_anonymous_user(auth_client):
    _ai_rate_limits.clear()
    headers = {"Authorization": f"Bearer {TEST_SUPABASE_ANON_KEY}"}
    payload = {"query": "Tell me about science fiction books"}

    # 5 requests succeed under limit
    for _ in range(5):
        resp = auth_client.post(
            "/api/ai/chat",
            headers=headers,
            json=payload,
            environ_base={"REMOTE_ADDR": "192.168.1.10"},
        )
        assert resp.status_code == 200

    # 6th request fails with 429
    resp = auth_client.post(
        "/api/ai/chat", headers=headers, json=payload, environ_base={"REMOTE_ADDR": "192.168.1.10"}
    )
    assert resp.status_code == 429
    assert "Retry-After" in resp.headers


def test_ai_chat_rate_limiting_isolated_per_user(auth_client):
    _ai_rate_limits.clear()
    headers_u1 = {"Authorization": "Bearer valid-user-jwt"}
    headers_u2 = {"Authorization": "Bearer valid-user-2-jwt"}
    payload = {"query": "Tell me about history"}

    # User 1 makes 10 requests under user limit
    for _ in range(10):
        resp = auth_client.post(
            "/api/ai/chat",
            headers=headers_u1,
            json=payload,
            environ_base={"REMOTE_ADDR": "192.168.1.10"},
        )
        assert resp.status_code == 200

    # User 1 11th request hits limit
    resp = auth_client.post(
        "/api/ai/chat",
        headers=headers_u1,
        json=payload,
        environ_base={"REMOTE_ADDR": "192.168.1.10"},
    )
    assert resp.status_code == 429

    # User 2 on the same IP is still allowed because User 2 has separate authenticated quota
    resp_u2 = auth_client.post(
        "/api/ai/chat",
        headers=headers_u2,
        json=payload,
        environ_base={"REMOTE_ADDR": "192.168.1.10"},
    )
    assert resp_u2.status_code == 200


def test_ai_chat_query_length_boundary_accepted(auth_client):
    _ai_rate_limits.clear()
    headers = {"Authorization": f"Bearer {TEST_SUPABASE_ANON_KEY}"}
    # Exactly 1000 characters
    valid_query = "A" * 1000
    resp = auth_client.post("/api/ai/chat", headers=headers, json={"query": valid_query})
    assert resp.status_code == 200


def test_ai_chat_query_length_exceeded_rejected_with_400(auth_client):
    _ai_rate_limits.clear()
    headers = {"Authorization": f"Bearer {TEST_SUPABASE_ANON_KEY}"}
    # 1001 characters
    long_query = "A" * 1001
    resp = auth_client.post("/api/ai/chat", headers=headers, json={"query": long_query})
    assert resp.status_code == 400
    data = resp.get_json()
    assert "Query exceeds maximum allowed length of 1000 characters" in data["error"]
    assert data["max_length"] == 1000
    assert data["actual_length"] == 1001


def test_misconfiguration_guard_when_libris_key_missing(auth_app):
    auth_app.config["LIBRIS_API_KEY"] = ""
    client = auth_app.test_client()
    resp = client.get("/api/categories")
    assert resp.status_code == 503
    data = resp.get_json()
    assert data["error"] == "Server misconfigured"
