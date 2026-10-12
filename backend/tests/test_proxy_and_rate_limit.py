from unittest.mock import patch

import pytest
from backend.app import create_app
from backend.config import Config
from backend.routes.routes import _ai_rate_limits


class ProxyTestConfig(Config):
    TESTING = True
    DEBUG = False
    ENFORCE_AUTH_IN_TESTS = True
    NUM_PROXIES = 1
    LIBRIS_API_KEY = "test-secret-key-123"
    SECRET_KEY = "test-secret-flask-key"

class DirectTestConfig(Config):
    TESTING = True
    DEBUG = False
    ENFORCE_AUTH_IN_TESTS = True
    NUM_PROXIES = 0
    LIBRIS_API_KEY = "test-secret-key-123"
    SECRET_KEY = "test-secret-flask-key"


@pytest.fixture(autouse=True)
def clear_rate_limits_and_mock_rag():
    _ai_rate_limits.clear()
    with patch("backend.routes.routes._process_rag_query_uc.execute", return_value={"answer": "mock answer", "referenced_books": [], "status": "success"}):
        yield
    _ai_rate_limits.clear()

def test_proxyfix_extracts_trusted_client_ip():
    app = create_app(ProxyTestConfig)
    client = app.test_client()

    # For anonymous rate limit testing, provide Supabase anon token in Authorization header
    app.config["SUPABASE_ANON_KEY"] = "anon-key-mock"
    anon_headers_a = {
        "Authorization": "Bearer anon-key-mock",
        "X-Forwarded-For": "203.0.113.10",
        "Content-Type": "application/json"
    }

    # Send 5 requests from client A
    for _ in range(5):
        res = client.post("/api/ai/chat", headers=anon_headers_a, json={"query": "test"})
        assert res.status_code in (200, 400, 500) # Reaches handler, not 429

    # 6th request from client A must be rate-limited (429)
    res_a_blocked = client.post("/api/ai/chat", headers=anon_headers_a, json={"query": "test"})
    assert res_a_blocked.status_code == 429
    assert "Rate limit exceeded" in res_a_blocked.get_json()["error"]

    # Client B from a different IP behind the proxy must NOT be blocked
    anon_headers_b = {
        "Authorization": "Bearer anon-key-mock",
        "X-Forwarded-For": "198.51.100.25",
        "Content-Type": "application/json"
    }
    res_b = client.post("/api/ai/chat", headers=anon_headers_b, json={"query": "test"})
    assert res_b.status_code != 429

def test_proxyfix_prevents_client_spoofed_headers():
    app = create_app(ProxyTestConfig)
    client = app.test_client()
    app.config["SUPABASE_ANON_KEY"] = "anon-key-mock"

    real_ip = "203.0.113.50"
    # When behind 1 proxy, X-Forwarded-For contains "client_spoofed, real_proxy_appended"
    # ProxyFix(x_for=1) must select real_ip and discard client_spoofed
    for i in range(5):
        spoofed_header = f"10.0.0.{i}, {real_ip}"
        res = client.post(
            "/api/ai/chat",
            headers={
                "Authorization": "Bearer anon-key-mock",
                "X-Forwarded-For": spoofed_header,
                "Content-Type": "application/json"
            },
            json={"query": "test"}
        )
        assert res.status_code != 429

    # 6th request with yet another spoofed prefix must STILL be blocked because real_ip is exhausted
    res_blocked = client.post(
        "/api/ai/chat",
        headers={
            "Authorization": "Bearer anon-key-mock",
            "X-Forwarded-For": f"8.8.8.8, {real_ip}",
            "Content-Type": "application/json"
        },
        json={"query": "test"}
    )
    assert res_blocked.status_code == 429

def test_direct_connection_ignores_forwarded_headers():
    # When NUM_PROXIES=0, X-Forwarded-For should not be trusted
    app = create_app(DirectTestConfig)
    client = app.test_client()
    app.config["SUPABASE_ANON_KEY"] = "anon-key-mock"

    # All test_client requests without proxy resolve to default remote_addr (127.0.0.1)
    for _ in range(5):
        res = client.post(
            "/api/ai/chat",
            headers={
                "Authorization": "Bearer anon-key-mock",
                "X-Forwarded-For": "1.2.3.4", # Ignored
                "Content-Type": "application/json"
            },
            json={"query": "test"}
        )
        assert res.status_code != 429

    # Even with a different X-Forwarded-For, it's blocked because remote_addr 127.0.0.1 is exhausted
    res = client.post(
        "/api/ai/chat",
        headers={
            "Authorization": "Bearer anon-key-mock",
            "X-Forwarded-For": "5.6.7.8", # Ignored
            "Content-Type": "application/json"
        },
        json={"query": "test"}
    )
    assert res.status_code == 429
