from unittest.mock import patch, MagicMock
import pytest
from flask import Flask, jsonify
from backend.routes.routes import rate_limit_ai, _ai_rate_limits

app = Flask(__name__)

@app.route("/test_limit", methods=["GET"])
@rate_limit_ai
def dummy_route():
    return jsonify({"success": True}), 200

@pytest.fixture
def client():
    app.config["TESTING"] = True
    with app.test_client() as client:
        # Reset the dict before each test
        _ai_rate_limits.clear()
        yield client

def test_rate_limiter_allows_under_limit(client):
    for _ in range(5):
        resp = client.get("/test_limit", environ_base={'REMOTE_ADDR': '127.0.0.1'})
        assert resp.status_code == 200

def test_rate_limiter_blocks_over_limit(client):
    for _ in range(5):
        resp = client.get("/test_limit", environ_base={'REMOTE_ADDR': '127.0.0.1'})
        assert resp.status_code == 200
        
    # 6th request should fail
    resp = client.get("/test_limit", environ_base={'REMOTE_ADDR': '127.0.0.1'})
    assert resp.status_code == 429
    assert "Retry-After" in resp.headers

def test_rate_limiter_isolates_users(client):
    for _ in range(5):
        resp = client.get("/test_limit", environ_base={'REMOTE_ADDR': '127.0.0.1'})
        assert resp.status_code == 200
        
    # Another user should succeed
    resp = client.get("/test_limit", environ_base={'REMOTE_ADDR': '127.0.0.2'})
    assert resp.status_code == 200

def test_rate_limiter_proxy_header(client):
    for _ in range(5):
        resp = client.get("/test_limit", headers={"X-Forwarded-For": "10.0.0.1, 192.168.1.1"})
        assert resp.status_code == 200
        
    resp = client.get("/test_limit", headers={"X-Forwarded-For": "10.0.0.1"})
    assert resp.status_code == 429
    
    # 10.0.0.2 should be allowed
    resp = client.get("/test_limit", headers={"X-Forwarded-For": "10.0.0.2"})
    assert resp.status_code == 200
