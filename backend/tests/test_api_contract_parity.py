"""
Contract Parity Tests between the Flask backend and the Next.js web client.
Validates structural schema, required fields, nullability, and status enums
for all prioritized cross-platform capabilities.
"""

from unittest.mock import MagicMock, patch

import pytest
from backend.app import create_app
from backend.config import Config


class ParityTestConfig(Config):
    TESTING = True
    DEBUG = False
    SECRET_KEY = "parity-secret"
    LIBRIS_API_KEY = "test-api-key"


class MockUser:
    def __init__(self, uid="11111111-1111-4111-8111-111111111111", email="parity_user@libris.ai"):
        self.id = uid
        self.email = email


@pytest.fixture
def client(monkeypatch):
    from backend import routes

    # These contract tests exercise authenticated response schemas, not persistence.
    # Supply a mock repository so patch() can replace its methods without requiring
    # production database credentials in the test environment.
    interaction_repo = MagicMock()
    interaction_repo.get_user_interactions.return_value = []
    interaction_repo.get_user_favorites.return_value = []
    book_data_port = MagicMock()
    monkeypatch.setattr(routes.routes, "_interaction_repo", interaction_repo)
    monkeypatch.setattr(routes.routes, "_book_data_port", book_data_port)

    app = create_app(ParityTestConfig)
    with app.test_client() as c:
        yield c


def test_contract_favorites_and_reading_status_feedback(client):
    """Verifies GET /api/feedback/<book_id> contract for authenticated and unauthenticated callers."""
    # 1. Unauthenticated contract
    res_anon = client.get("/api/feedback/9780007111503")
    assert res_anon.status_code == 200
    data_anon = res_anon.get_json()
    assert data_anon["status"] == "success"
    assert data_anon["is_authenticated"] is False
    assert data_anon["interaction"] is None
    assert data_anon["is_favorite"] is False

    # 2. Authenticated contract
    with patch("backend.routes.routes._auth_port.verify_token", return_value=MockUser()):
        with patch("backend.routes.routes._interaction_repo.get_user_interactions", return_value=[
            {"book_id": "9780007111503", "interaction_type": "reading"}
        ]):
            with patch("backend.routes.routes._interaction_repo.get_user_favorites", return_value=[
                {"book_id": "9780007111503", "book_title": "Partners in Crime"}
            ]):
                res_auth = client.get(
                    "/api/feedback/9780007111503",
                    headers={"Authorization": "Bearer valid-token"}
                )
                assert res_auth.status_code == 200
                data_auth = res_auth.get_json()
                assert data_auth["status"] == "success"
                assert data_auth["is_authenticated"] is True
                assert data_auth["interaction"] == "reading"
                assert data_auth["is_favorite"] is True


def test_contract_unified_library_items(client):
    """Verifies GET /api/library schema matches the web LibraryItem type."""
    mock_book_dict = {
        "isbn13": "9780007111503",
        "title": "Partners in Crime",
        "authors": "Agatha Christie",
        "categories": "Mystery",
        "description": "Classic detective fiction.",
        "thumbnail": "https://example.com/cover.jpg",
        "average_rating": 4.2,
        "ratings_count": 150,
        "published_date": "1929",
        "page_count": 280,
    }

    with patch("backend.routes.routes._auth_port.verify_token", return_value=MockUser()):
        with patch("backend.routes.routes._interaction_repo.get_user_interactions", return_value=[
            {"book_id": "9780007111503", "interaction_type": "finished", "created_at": "2026-03-01T10:00:00Z"}
        ]):
            with patch("backend.routes.routes._interaction_repo.get_user_favorites", return_value=[
                {"book_id": "9780007111503", "book_title": "Partners in Crime", "added_at": "2026-03-01T10:00:00Z"}
            ]):
                with patch("backend.routes.routes._book_data_port.get_books_by_isbns", return_value=[mock_book_dict]):
                    res = client.get(
                        "/api/library",
                        headers={"Authorization": "Bearer valid-token"}
                    )
                    assert res.status_code == 200
                    payload = res.get_json()
                    assert payload["status"] == "success"
                    assert isinstance(payload["items"], list)
                    assert len(payload["items"]) >= 1

                    item = payload["items"][0]
                    assert "book_id" in item
                    assert "status" in item
                    assert item["status"] in ("favorite", "want_to_read", "reading", "finished")
                    assert "is_favorite" in item
                    assert isinstance(item["is_favorite"], bool)
                    assert "book" in item
                    book = item["book"]
                    assert book["isbn13"] == "9780007111503"
                    assert book["title"] == "Partners in Crime"
                    assert book["authors"] == "Agatha Christie"


def test_contract_personalized_recommendations(client):
    """Verifies GET /api/recommend/personalized contract with diagnostics."""
    mock_result = {
        "recommendations": [
            {
                "isbn13": "9780007113804",
                "title": "Murder in Mesopotamia",
                "authors": "Agatha Christie",
                "categories": "Mystery",
                "similarity_score": 0.88,
                "recommendation_reason": "Because you love Agatha Christie",
                "explanation_type": "author_affinity",
                "confidence": "high",
                "is_cold_start": False,
            }
        ],
        "total": 1,
        "is_cold_start": False,
        "evidence_coverage": "established",
        "diagnostics": {
            "engine_version": "v2.5",
            "candidate_count": 20,
            "filtered_count": 1,
            "latency_ms": 15,
        },
    }

    with patch("backend.routes.routes._auth_port.verify_token", return_value=MockUser()):
        with patch("backend.routes.routes._get_personalized_recs_uc.execute", return_value=mock_result):
            res = client.get(
                "/api/recommend/personalized?diagnostics=true",
                headers={"Authorization": "Bearer valid-token"}
            )
            assert res.status_code == 200
            data = res.get_json()
            assert "recommendations" in data
            assert isinstance(data["recommendations"], list)
            assert len(data["recommendations"]) == 1

            rec_book = data["recommendations"][0]
            assert rec_book["isbn13"] == "9780007113804"
            assert "similarity_score" in rec_book
            assert "recommendation_reason" in rec_book
            assert "diagnostics" in data


def test_contract_ai_discovery_response(client):
    """Verifies POST /api/ai/chat returns canonical referenced_books and structured fallback."""
    mock_rag_response = {
        "answer": "Recommendation based on your query.",
        "referenced_books": [
            {"isbn13": "9780007111503", "title": "Partners in Crime", "authors": "Agatha Christie"}
        ],
        "status": "success",
        "action": None,
    }

    with patch("backend.routes.routes._process_rag_query_uc.execute", return_value=mock_rag_response):
        res = client.post("/api/ai/chat", json={"query": "find mystery books"})
        assert res.status_code == 200
        data = res.get_json()
        assert "answer" in data
        assert "referenced_books" in data
        assert isinstance(data["referenced_books"], list)
        assert data["status"] == "success"


def test_contract_smart_reviews_due(client):
    """Verifies GET /api/notes/reviews/due spaced repetition contract schema."""
    mock_due_reviews = [
        {
            "id": "review-1",
            "user_id": "11111111-1111-4111-8111-111111111111",
            "note_id": "note-1",
            "book_id": "9780007111503",
            "note_type": "key_takeaway",
            "content": "Core clue principle",
            "review_stage": 1,
            "next_review_at": "2026-03-01T09:00:00Z",
            "review_active": True,
        }
    ]

    with patch("backend.routes.routes._auth_port.verify_token", return_value=MockUser()):
        with patch("backend.routes.routes._get_due_reviews_uc.execute", return_value=mock_due_reviews):
            res = client.get(
                "/api/notes/reviews/due",
                headers={"Authorization": "Bearer valid-token"}
            )
            assert res.status_code == 200
            data = res.get_json()
            assert data["status"] == "success"
            assert "reviews" in data
            assert len(data["reviews"]) == 1
            review = data["reviews"][0]
            assert review["id"] == "review-1"
            assert review["note_id"] == "note-1"
            assert "review_stage" in review
