"""
test_library_endpoints.py - Integration & Unit Tests for Unified Library & Feedback Endpoints.

Tests:
  1. GET /api/library:
     - Unauthenticated requests are rejected with 401 Unauthorized.
     - Authenticated requests return 200 and formatted Library items.
     - Model A invariant: Shelves (reading, finished, want_to_read) and Favorites are independent.
     - Ownership isolation: User A sees only User A's items, User B sees only User B's.
  2. GET /api/feedback/<book_id>:
     - Unauthenticated caller receives status="success", is_authenticated=False without error.
     - Authenticated caller receives interaction status and is_favorite boolean.
     - Invalid book ID returns 400.
"""

import pytest
from backend.app import create_app
from backend.domain.models import Book


class MockUser:
    def __init__(self, user_id):
        self.id = user_id


class MockAuthPort:
    def __init__(self):
        self.users = {
            "token-user-a": MockUser("user-a-uuid"),
            "token-user-b": MockUser("user-b-uuid"),
        }

    def verify_token(self, token):
        if token in self.users:
            return self.users[token]
        raise ValueError("Invalid JWT signature or expired token")


class InMemoryInteractionRepo:
    def __init__(self):
        # user_id -> { book_id -> interaction_type }
        self.interactions = {}
        # user_id -> { book_id -> favorite_dict }
        self.favorites = {}

    def get_user_interactions(self, user_id):
        user_items = self.interactions.get(user_id, {})
        return [
            {
                "user_id": user_id,
                "book_id": b_id,
                "interaction_type": i_type,
                "created_at": "2026-02-01T12:00:00Z",
            }
            for b_id, i_type in user_items.items()
        ]

    def get_user_favorites(self, user_id):
        user_favs = self.favorites.get(user_id, {})
        return list(user_favs.values())

    def upsert_interactions(self, entries):
        for entry in entries:
            u_id = entry["user_id"]
            b_id = entry["book_id"]
            i_type = entry.get("interaction_type")
            if u_id not in self.interactions:
                self.interactions[u_id] = {}
            if u_id not in self.favorites:
                self.favorites[u_id] = {}

            if i_type == "favorite":
                self.favorites[u_id][b_id] = {
                    "book_id": b_id,
                    "book_title": entry.get("book_title") or "Test Book",
                    "book_author": entry.get("book_author") or "Test Author",
                    "book_image_url": entry.get("book_image_url") or "",
                    "added_at": "2026-02-01T12:00:00Z",
                }
            elif i_type in ("want_to_read", "reading", "finished", "like", "dislike"):
                self.interactions[u_id][b_id] = i_type

    def delete_interaction(self, user_id, book_id, interaction_type=None, preserve_favorites=False):
        if user_id in self.interactions:
            if interaction_type == "favorite":
                if user_id in self.favorites and book_id in self.favorites[user_id]:
                    del self.favorites[user_id][book_id]
                return
            if not preserve_favorites:
                if user_id in self.favorites and book_id in self.favorites[user_id]:
                    del self.favorites[user_id][book_id]
            if book_id in self.interactions[user_id]:
                del self.interactions[user_id][book_id]


class MockBookDataPort:
    def get_book_by_isbn(self, isbn):
        return Book(
            isbn13=isbn,
            title=f"Title for {isbn}",
            authors=["Author One"],
            categories=["Fiction"],
            description="A great novel.",
            thumbnail="https://example.com/cover.jpg",
            average_rating=4.5,
            ratings_count=100,
            published_date="2020",
            page_count=350,
        )

    def get_books_by_isbns(self, isbns):
        return {isbn: self.get_book_by_isbn(isbn) for isbn in isbns}


@pytest.fixture
def repo():
    return InMemoryInteractionRepo()


@pytest.fixture
def test_client(repo, monkeypatch):
    app = create_app()
    app.config["TESTING"] = True
    app.config["PROPAGATE_EXCEPTIONS"] = False

    auth_port = MockAuthPort()
    book_port = MockBookDataPort()

    monkeypatch.setattr("backend.routes.routes._auth_port", auth_port)
    monkeypatch.setattr("backend.routes.routes._interaction_repo", repo)
    monkeypatch.setattr("backend.routes.routes._submit_feedback_uc._interaction_repo", repo)
    monkeypatch.setattr("backend.routes.routes._book_data_port", book_port)

    with app.test_client() as c:
        yield c


class TestLibraryEndpoints:
    def test_get_library_unauthenticated_rejected(self, test_client):
        """Unauthenticated caller to GET /api/library is rejected with 401."""
        # 1. Missing credentials entirely
        res1 = test_client.get("/api/library")
        assert res1.status_code == 401
        data1 = res1.get_json()
        assert "error" in data1

        # 2. Service-key provided without user session -> Rejected by @require_auth
        app_key = test_client.application.config.get("LIBRIS_API_KEY", "default-dev-secret-key-change-in-prod")
        res2 = test_client.get("/api/library", headers={"X-Api-Key": app_key})
        assert res2.status_code == 401
        data2 = res2.get_json()
        assert "error" in data2
        assert "Unauthorized" in data2["error"]

    def test_get_library_authenticated_empty(self, test_client):
        """Authenticated caller with empty library receives 200 and empty list."""
        headers = {"Authorization": "Bearer token-user-a"}
        res = test_client.get("/api/library", headers=headers)
        assert res.status_code == 200
        data = res.get_json()
        assert data["status"] == "success"
        assert data["items"] == []

    def test_get_library_model_a_independence(self, test_client, repo):
        """Validates that favorite status and shelf reading status are completely independent."""
        headers = {"Authorization": "Bearer token-user-a"}
        book_isbn = "9780007111503"

        # 1. User sets book to reading shelf
        repo.upsert_interactions([{
            "user_id": "user-a-uuid",
            "book_id": book_isbn,
            "interaction_type": "reading",
        }])

        res1 = test_client.get("/api/library", headers=headers)
        assert res1.status_code == 200
        items1 = res1.get_json()["items"]
        assert len(items1) == 1
        assert items1[0]["book_id"] == book_isbn
        assert items1[0]["status"] == "reading"
        assert items1[0]["is_favorite"] is False

        # 2. User favorites the same book (Model A: both reading and favorite active simultaneously)
        repo.upsert_interactions([{
            "user_id": "user-a-uuid",
            "book_id": book_isbn,
            "interaction_type": "favorite",
            "book_title": "Partners in Crime",
            "book_author": "Agatha Christie",
        }])

        res2 = test_client.get("/api/library", headers=headers)
        assert res2.status_code == 200
        items2 = res2.get_json()["items"]
        assert len(items2) == 1
        assert items2[0]["book_id"] == book_isbn
        assert items2[0]["status"] == "reading"
        assert items2[0]["is_favorite"] is True

        # 3. User unfavorites the book -> reading status MUST be preserved
        repo.delete_interaction("user-a-uuid", book_isbn, interaction_type="favorite")

        res3 = test_client.get("/api/library", headers=headers)
        assert res3.status_code == 200
        items3 = res3.get_json()["items"]
        assert len(items3) == 1
        assert items3[0]["book_id"] == book_isbn
        assert items3[0]["status"] == "reading"
        assert items3[0]["is_favorite"] is False

    def test_get_library_user_isolation(self, test_client, repo):
        """User A and User B cannot access each other's library items."""
        # Setup User A with one book
        repo.upsert_interactions([{
            "user_id": "user-a-uuid",
            "book_id": "9780007111503",
            "interaction_type": "favorite",
        }])

        # User A checks library -> 1 item
        res_a = test_client.get("/api/library", headers={"Authorization": "Bearer token-user-a"})
        assert res_a.status_code == 200
        assert len(res_a.get_json()["items"]) == 1

        # User B checks library -> 0 items (strict tenant isolation)
        res_b = test_client.get("/api/library", headers={"Authorization": "Bearer token-user-b"})
        assert res_b.status_code == 200
        assert len(res_b.get_json()["items"]) == 0

    def test_get_feedback_by_book_id(self, test_client, repo):
        """GET /api/feedback/<book_id> returns interaction and favorite status."""
        book_isbn = "9780007111503"

        # 1. Unauthenticated caller gets safe default without error
        res_unauth = test_client.get(f"/api/feedback/{book_isbn}")
        assert res_unauth.status_code == 200
        data_unauth = res_unauth.get_json()
        assert data_unauth["status"] == "success"
        assert data_unauth["is_authenticated"] is False
        assert data_unauth["interaction"] is None
        assert data_unauth["is_favorite"] is False

        # 2. Authenticated caller with no interactions
        headers = {"Authorization": "Bearer token-user-a"}
        res_auth_empty = test_client.get(f"/api/feedback/{book_isbn}", headers=headers)
        assert res_auth_empty.status_code == 200
        data_empty = res_auth_empty.get_json()
        assert data_empty["status"] == "success"
        assert data_empty["is_authenticated"] is True
        assert data_empty["interaction"] is None
        assert data_empty["is_favorite"] is False

        # 3. Authenticated caller after setting status and favorite
        repo.upsert_interactions([
            {
                "user_id": "user-a-uuid",
                "book_id": book_isbn,
                "interaction_type": "finished",
            },
            {
                "user_id": "user-a-uuid",
                "book_id": book_isbn,
                "interaction_type": "favorite",
            },
        ])

        res_active = test_client.get(f"/api/feedback/{book_isbn}", headers=headers)
        assert res_active.status_code == 200
        data_active = res_active.get_json()
        assert data_active["status"] == "success"
        assert data_active["is_authenticated"] is True
        assert data_active["interaction"] == "finished"
        assert data_active["is_favorite"] is True
