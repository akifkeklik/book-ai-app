"""
test_api.py — Integration tests for the Flask API endpoints.

Tests cover:
  - GET /              (root manifest)
  - GET /api/health    (liveness probe)
  - GET /api/books     (paginated list)
  - GET /api/books/popular
  - GET /api/books/<isbn>
  - GET /api/search
  - GET /api/recommend
  - POST /api/track
  - Error handling (404, 400, invalid input)

Run:
    cd backend
    python -m pytest tests/test_api.py -v
"""

import json

import pytest

from backend.app import create_app


# ═════════════════════════════════════════════════════════════════════════════
# Fixtures
# ═════════════════════════════════════════════════════════════════════════════

@pytest.fixture
def client():
    """Create a Flask test client with the default config."""
    app = create_app()
    app.config["TESTING"] = True
    with app.test_client() as c:
        yield c


# ═════════════════════════════════════════════════════════════════════════════
# 1. ROOT & HEALTH
# ═════════════════════════════════════════════════════════════════════════════

class TestRootAndHealth:
    def test_root_returns_manifest(self, client):
        resp = client.get("/")
        assert resp.status_code == 200
        data = resp.get_json()
        assert data["name"] == "Book AI Recommendation API"
        assert data["version"] == "1.0.0"
        assert data["status"] == "operational"
        assert isinstance(data["endpoints"], list)
        assert len(data["endpoints"]) > 0

    def test_health_check(self, client):
        resp = client.get("/api/health")
        assert resp.status_code == 200
        data = resp.get_json()
        assert data["status"] == "healthy"
        assert data["service"] == "book-ai-api"


# ═════════════════════════════════════════════════════════════════════════════
# 2. BOOKS — LIST
# ═════════════════════════════════════════════════════════════════════════════

class TestBooksList:
    def test_get_books_default(self, client):
        resp = client.get("/api/books")
        assert resp.status_code == 200
        data = resp.get_json()
        assert "books" in data
        assert "total" in data
        assert "page" in data
        assert "per_page" in data
        assert "total_pages" in data
        assert isinstance(data["books"], list)

    def test_get_books_pagination(self, client):
        resp = client.get("/api/books?page=1&per_page=5")
        assert resp.status_code == 200
        data = resp.get_json()
        assert data["page"] == 1
        assert data["per_page"] == 5
        assert len(data["books"]) <= 5

    def test_get_books_page_2(self, client):
        resp1 = client.get("/api/books?page=1&per_page=3")
        resp2 = client.get("/api/books?page=2&per_page=3")
        data1 = resp1.get_json()
        data2 = resp2.get_json()
        titles1 = {b["title"] for b in data1["books"]}
        titles2 = {b["title"] for b in data2["books"]}
        # Pages should have different books
        assert titles1 != titles2 or data1["total"] <= 3

    def test_per_page_capped_at_100(self, client):
        resp = client.get("/api/books?per_page=999")
        assert resp.status_code == 200
        data = resp.get_json()
        assert len(data["books"]) <= 100


# ═════════════════════════════════════════════════════════════════════════════
# 3. BOOKS — POPULAR
# ═════════════════════════════════════════════════════════════════════════════

class TestPopularBooks:
    def test_get_popular(self, client):
        resp = client.get("/api/books/popular")
        assert resp.status_code == 200
        data = resp.get_json()
        assert "books" in data
        assert "total" in data
        assert isinstance(data["books"], list)

    def test_popular_with_limit(self, client):
        resp = client.get("/api/books/popular?limit=5")
        assert resp.status_code == 200
        data = resp.get_json()
        assert len(data["books"]) <= 5

    def test_popular_has_required_fields(self, client):
        resp = client.get("/api/books/popular?limit=1")
        data = resp.get_json()
        if data["books"]:
            book = data["books"][0]
            assert "title" in book
            assert "authors" in book
            assert "average_rating" in book


# ═════════════════════════════════════════════════════════════════════════════
# 4. BOOKS — ISBN LOOKUP
# ═════════════════════════════════════════════════════════════════════════════

class TestISBNLookup:
    def test_get_book_by_isbn(self, client):
        # Use a known ISBN from our dataset
        resp = client.get("/api/books/9780441013593")
        if resp.status_code == 200:
            data = resp.get_json()
            assert "book" in data
            assert data["book"]["title"] == "Dune"

    def test_isbn_not_found(self, client):
        resp = client.get("/api/books/0000000000000")
        assert resp.status_code == 404
        data = resp.get_json()
        assert "error" in data


# ═════════════════════════════════════════════════════════════════════════════
# 5. SEARCH
# ═════════════════════════════════════════════════════════════════════════════

class TestSearch:
    def test_search_by_title(self, client):
        resp = client.get("/api/search?q=Dune")
        assert resp.status_code == 200
        data = resp.get_json()
        assert "books" in data
        assert "total" in data
        assert "query" in data
        assert data["query"] == "Dune"

    def test_search_by_author(self, client):
        resp = client.get("/api/search?q=Tolkien")
        assert resp.status_code == 200
        data = resp.get_json()
        assert isinstance(data["books"], list)

    def test_search_no_query(self, client):
        resp = client.get("/api/search")
        assert resp.status_code == 400
        data = resp.get_json()
        assert "error" in data

    def test_search_too_short(self, client):
        resp = client.get("/api/search?q=a")
        assert resp.status_code == 400

    def test_search_with_limit(self, client):
        resp = client.get("/api/search?q=fiction&limit=3")
        assert resp.status_code == 200
        data = resp.get_json()
        assert len(data["books"]) <= 3


# ═════════════════════════════════════════════════════════════════════════════
# 6. RECOMMENDATIONS
# ═════════════════════════════════════════════════════════════════════════════

class TestRecommendations:
    def test_recommend(self, client):
        resp = client.get("/api/recommend?book=Dune")
        assert resp.status_code == 200
        data = resp.get_json()
        assert "recommendations" in data
        assert "total" in data
        assert data["book"] == "Dune"

    def test_recommend_with_top_n(self, client):
        resp = client.get("/api/recommend?book=Dune&top_n=3")
        assert resp.status_code == 200
        data = resp.get_json()
        assert len(data["recommendations"]) <= 3

    def test_recommend_no_book(self, client):
        resp = client.get("/api/recommend")
        assert resp.status_code == 400
        data = resp.get_json()
        assert "error" in data

    def test_recommend_not_found(self, client):
        resp = client.get("/api/recommend?book=XYZZY_NONEXISTENT_BOOK_99999")
        # Should return 404 or results from semantic match
        assert resp.status_code in (200, 404)

    def test_recommend_excludes_self(self, client):
        resp = client.get("/api/recommend?book=Dune")
        if resp.status_code == 200:
            data = resp.get_json()
            titles = [r["title"] for r in data["recommendations"]]
            assert "Dune" not in titles

    def test_recommend_hybrid_off(self, client):
        resp = client.get("/api/recommend?book=Dune&hybrid=false")
        assert resp.status_code == 200


# ═════════════════════════════════════════════════════════════════════════════
# 7. ACTIVITY TRACKING
# ═════════════════════════════════════════════════════════════════════════════

class TestActivityTracking:
    def test_track_activity(self, client):
        resp = client.post(
            "/api/track",
            data=json.dumps({
                "user_id": "test-user-123",
                "book_name": "Dune",
                "action": "view",
            }),
            content_type="application/json",
        )
        assert resp.status_code == 200
        data = resp.get_json()
        assert data["status"] == "tracked"
        assert data["user_id"] == "test-user-123"
        assert data["book_name"] == "Dune"

    def test_track_missing_fields(self, client):
        resp = client.post(
            "/api/track",
            data=json.dumps({"user_id": "test-user"}),
            content_type="application/json",
        )
        assert resp.status_code == 400

    def test_track_no_json(self, client):
        resp = client.post("/api/track")
        assert resp.status_code == 400


# ═════════════════════════════════════════════════════════════════════════════
# 8. ERROR HANDLING
# ═════════════════════════════════════════════════════════════════════════════

class TestErrorHandling:
    def test_404(self, client):
        resp = client.get("/nonexistent-path")
        assert resp.status_code == 404
        data = resp.get_json()
        assert "error" in data

    def test_405(self, client):
        resp = client.post("/api/health")
        assert resp.status_code == 405
        data = resp.get_json()
        assert "error" in data
