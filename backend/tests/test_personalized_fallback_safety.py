"""
Workstream F: Backend Fallback and Type Safety Tests.
Distinguishes:
1. Unsupported keyword arguments (legacy adapters take only user_id and limit).
2. Genuine internal TypeError inside use case logic (never swallowed).
3. Dictionary response (normal modern response).
4. Legacy list response (backward compatible).
5. Malformed response (non-list/non-dict or invalid schema -> 502).
"""

from unittest.mock import patch

import pytest
from backend.app import create_app
from backend.config import Config


class FallbackSafetyConfig(Config):
    TESTING = True
    DEBUG = False
    SECRET_KEY = "test-secret-key"
    LIBRIS_API_KEY = "test-api-key"


@pytest.fixture
def client():
    app = create_app(FallbackSafetyConfig)
    with app.test_client() as c:
        yield c


@pytest.fixture
def auth_headers(monkeypatch):
    class DummyUser:
        id = "user-123"

    class FakeAuthPort:
        def verify_token(self, token):
            if token == "valid-token":
                return DummyUser()
            raise Exception("Invalid token")

    monkeypatch.setattr("backend.routes.routes._auth_port", FakeAuthPort())
    return {
        "Content-Type": "application/json",
        "Authorization": "Bearer valid-token",
    }


def test_scenario_1_unsupported_keyword_arguments_legacy_adapter(client, auth_headers):
    """
    Scenario 1: Legacy adapter that only accepts (self, user_id, limit).
    Calling route with category & diagnostics does NOT fail with TypeError;
    signature inspection cleanly detects parameter limits and invokes with user_id and limit.
    """
    class LegacyAdapter:
        def execute(self, user_id, limit=10):
            return [{"isbn13": "9780000000001", "title": "Legacy Book", "authors": "Legacy Author"}]

    legacy = LegacyAdapter()
    with patch("backend.routes.routes._get_personalized_recs_uc", legacy):
        resp = client.get("/api/recommend/personalized?limit=5&category=Fiction&diagnostics=true", headers=auth_headers)
        assert resp.status_code == 200
        data = resp.get_json()
        assert data["user_id"] == "user-123"
        assert len(data["recommendations"]) == 1
        assert data["recommendations"][0]["title"] == "Legacy Book"


def test_scenario_2_genuine_internal_typeerror_not_masked(client, auth_headers):
    """
    Scenario 2: Genuine internal TypeError raised inside the use case execution.
    MUST NOT be caught or masked as an unsupported argument fallback.
    It should bubble up and return HTTP 500.
    """
    class BuggyUseCase:
        def execute(self, user_id, limit=10, category=None, exclude_completed=False, path_id=None, include_diagnostics=True):
            # Simulate genuine bug inside use case logic:
            result = None
            return result + 1  # Raises TypeError: unsupported operand type(s) for +: 'NoneType' and 'int'

    buggy = BuggyUseCase()
    with patch("backend.routes.routes._get_personalized_recs_uc", buggy):
        resp = client.get("/api/recommend/personalized", headers=auth_headers)
        assert resp.status_code == 500


def test_scenario_3_dictionary_response_modern_contract(client, auth_headers):
    """
    Scenario 3: Standard modern dictionary response with diagnostics, evidence_coverage, and is_cold_start.
    """
    class ModernUseCase:
        def execute(self, user_id, limit=10, category=None, exclude_completed=False, path_id=None, include_diagnostics=True):
            return {
                "user_id": user_id,
                "recommendations": [
                    {"isbn13": "9781111111111", "title": "Modern Book", "recommendation_reason": "Top pick"}
                ],
                "total": 1,
                "is_cold_start": False,
                "evidence_coverage": "established",
                "diagnostics": {"engine_version": "2.6.0", "latency_ms": 12.5},
            }

    modern = ModernUseCase()
    with patch("backend.routes.routes._get_personalized_recs_uc", modern):
        resp = client.get("/api/recommend/personalized?diagnostics=true", headers=auth_headers)
        assert resp.status_code == 200
        data = resp.get_json()
        assert data["user_id"] == "user-123"
        assert data["total"] == 1
        assert data["is_cold_start"] is False
        assert data["evidence_coverage"] == "established"
        assert data["diagnostics"]["engine_version"] == "2.6.0"
        assert data["recommendations"][0]["isbn13"] == "9781111111111"


def test_scenario_4_legacy_list_response(client, auth_headers):
    """
    Scenario 4: Legacy list response directly returned from execute().
    Properly formatted into standard response wrapper with fallback metadata.
    """
    class ListReturningUseCase:
        def execute(self, user_id, limit=10, category=None, exclude_completed=False, path_id=None, include_diagnostics=True):
            return [
                {"isbn13": "9782222222222", "title": "Direct List Book", "authors": "Author Two"},
                {"isbn13": "9783333333333", "title": "Direct List Book 2", "authors": "Author Three"},
            ]

    list_uc = ListReturningUseCase()
    with patch("backend.routes.routes._get_personalized_recs_uc", list_uc):
        resp = client.get("/api/recommend/personalized", headers=auth_headers)
        assert resp.status_code == 200
        data = resp.get_json()
        assert data["total"] == 2
        assert len(data["recommendations"]) == 2
        assert data["is_cold_start"] is False
        assert data["evidence_coverage"] == "cold_start"


def test_scenario_5_malformed_response_handling(client, auth_headers):
    """
    Scenario 5: Malformed responses (non-dict, non-list, or dict with invalid 'recommendations' field).
    Route must return 502 Bad Gateway without crashing the server.
    """
    # 5a: Returns a primitive string
    class StringUseCase:
        def execute(self, user_id, limit=10, **kwargs):
            return "string is not a valid recommendation response"

    with patch("backend.routes.routes._get_personalized_recs_uc", StringUseCase()):
        resp = client.get("/api/recommend/personalized", headers=auth_headers)
        assert resp.status_code == 502
        data = resp.get_json()
        assert "Malformed recommendation response" in data["error"]

    # 5b: Returns a dict with non-list recommendations field
    class BadDictUseCase:
        def execute(self, user_id, limit=10, **kwargs):
            return {"recommendations": "not-a-list", "total": 1}

    with patch("backend.routes.routes._get_personalized_recs_uc", BadDictUseCase()):
        resp = client.get("/api/recommend/personalized", headers=auth_headers)
        assert resp.status_code == 502
        data = resp.get_json()
        assert "Malformed recommendation response" in data["error"]

    # 5c: Returns None
    class NoneUseCase:
        def execute(self, user_id, limit=10, **kwargs):
            return None

    with patch("backend.routes.routes._get_personalized_recs_uc", NoneUseCase()):
        resp = client.get("/api/recommend/personalized", headers=auth_headers)
        assert resp.status_code == 502
        data = resp.get_json()
        assert "Malformed recommendation response" in data["error"]
