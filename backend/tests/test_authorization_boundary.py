"""
test_authorization_boundary.py — Strict Authorization Trust-Boundary Matrix for Libris.

Proves:
  A. Missing service API key -> reject.
  B. Valid service API key, no Bearer token, user-specific read -> reject.
  C. Valid service API key, no Bearer token, user-specific write -> reject.
  D. Invalid or expired Bearer token -> reject.
  E. Invalid signature, issuer, or audience -> reject.
  F. Valid User A token plus request containing User B's user_id -> safely bind to User A, never gaining User B's authority.
  G. Valid User A token querying User B resource -> no access.
  H. Valid User A token creating, updating, or deleting User B data -> no mutation of User B data.
  I. Valid User B token -> can access only User B's own data.
  J. Legacy API-key-only internal callers -> public catalog endpoints succeed without impersonating end users.
"""

import pytest
from backend.app import create_app
from backend.domain.models import Book

TEST_SERVICE_KEY = "test-secret-service-key-99999"
TEST_ANON_KEY = "test-supabase-anon-key-88888"

USER_A_ID = "11111111-aaaa-4111-8111-aaaaaaaaaaaa"
USER_B_ID = "22222222-bbbb-4222-8222-bbbbbbbbbbbb"

BOOK_ID_1 = "9780007111503"
BOOK_ID_2 = "9780007113804"


class DummyAuthUser:
    def __init__(self, uid):
        self.id = uid


class MockAuthPortMatrix:
    def verify_token(self, token: str):
        if token == "valid-token-user-a":
            return DummyAuthUser(USER_A_ID)
        if token == "valid-token-user-b":
            return DummyAuthUser(USER_B_ID)
        if token == "expired-token":
            raise ValueError("Token is expired")
        if token == "invalid-sig-token":
            raise ValueError("Invalid JWT signature")
        if token == "bad-audience-token":
            raise ValueError("Invalid token audience")
        raise ValueError(f"Unrecognized or malformed token: {token}")


class InMemoryInteractionRepoMatrix:
    def __init__(self):
        self.interactions = {}  # uid -> {book_id: type}
        self.favorites = {}     # uid -> {book_id: dict}
        self.profiles = {}      # uid -> dict
        self.activities = []

    def get_user_interactions(self, user_id):
        items = self.interactions.get(user_id, {})
        return [
            {"user_id": user_id, "book_id": b, "interaction_type": t, "created_at": "2026-10-27T00:00:00Z"}
            for b, t in items.items()
        ]

    def get_user_favorites(self, user_id):
        favs = self.favorites.get(user_id, {})
        return list(favs.values())

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
                    "added_at": "2026-10-27T00:00:00Z",
                }
            elif i_type in ("reading", "want_to_read", "finished", "like", "dislike"):
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

    def get_user_profile(self, user_id):
        return self.profiles.get(user_id, {"preferred_genres": ["Mystery"], "preferred_authors": ["Agatha Christie"]})

    def upsert_user_profile(self, user_id, genres=None, authors=None, **kwargs):
        self.profiles[user_id] = {
            "preferred_genres": genres or [],
            "preferred_authors": authors or [],
            "updated_at": "2026-10-27T00:00:00Z",
        }

    def upsert_profile(self, user_id, genres, updated_at=None, authors=None):
        self.profiles[user_id] = {
            "preferred_genres": genres or [],
            "preferred_authors": authors or [],
            "updated_at": updated_at or "2026-10-27T00:00:00Z",
        }

    def track_activity(self, payload):
        self.activities.append(payload)


class MockBookDataPortMatrix:
    def get_books_by_isbns(self, isbns):
        return [
            {
                "isbn13": isbn,
                "title": f"Book {isbn}",
                "authors": "Author",
                "thumbnail": "",
                "categories": "Fiction",
                "description": "",
                "average_rating": 4.5,
                "ratings_count": 10,
                "published_date": "2020",
                "page_count": 200,
            }
            for isbn in isbns
        ]

    def get_book_by_isbn(self, isbn):
        return Book(
            isbn13=isbn,
            title=f"Book {isbn}",
            authors=["Author"],
            categories=["Fiction"],
            description="A novel",
            thumbnail="",
            average_rating=4.5,
            ratings_count=10,
            published_date="2020",
            page_count=200,
        )

    def check_health(self):
        return True


@pytest.fixture
def repo():
    return InMemoryInteractionRepoMatrix()


@pytest.fixture
def auth_client(repo, monkeypatch):
    app = create_app()
    app.config["TESTING"] = True
    app.config["ENFORCE_AUTH_IN_TESTS"] = True
    app.config["LIBRIS_API_KEY"] = TEST_SERVICE_KEY
    app.config["SUPABASE_ANON_KEY"] = TEST_ANON_KEY

    auth_port = MockAuthPortMatrix()
    book_port = MockBookDataPortMatrix()

    monkeypatch.setattr("backend.routes.routes._auth_port", auth_port)
    monkeypatch.setattr("backend.routes.routes._interaction_repo", repo)
    monkeypatch.setattr("backend.routes.routes._submit_feedback_uc._interaction_repo", repo)
    monkeypatch.setattr("backend.routes.routes._update_preferences_uc._interaction_repo", repo)
    monkeypatch.setattr("backend.routes.routes._get_preferences_uc._interaction_repo", repo)
    monkeypatch.setattr("backend.routes.routes._submit_onboarding_uc._interaction_repo", repo)
    monkeypatch.setattr("backend.routes.routes._track_activity_uc._interaction_repo", repo)
    monkeypatch.setattr("backend.routes.routes._book_data_port", book_port)

    with app.test_client() as c:
        yield c


class TestAuthorizationNegativeMatrix:
    """A. Missing service API key -> reject."""
    def test_matrix_a_missing_credentials_rejected(self, auth_client):
        # 1. Public catalog endpoint without any credentials -> 401
        res_cat = auth_client.get("/api/books")
        assert res_cat.status_code == 401
        assert "Missing API Key or Bearer Token" in res_cat.get_json()["error"]

        # 2. User personal library endpoint without any credentials -> 401
        res_lib = auth_client.get("/api/library")
        assert res_lib.status_code == 401

        # 3. User feedback mutation without any credentials -> 401
        res_feed = auth_client.post("/api/feedback", json={"book_id": BOOK_ID_1, "interaction": "favorite"})
        assert res_feed.status_code == 401

    """B. Valid service API key, no Bearer token, user-specific read -> reject."""
    def test_matrix_b_service_key_only_cannot_read_user_endpoints(self, auth_client):
        srv_header = {"X-Api-Key": TEST_SERVICE_KEY}

        # 1. GET /api/library with X-Api-Key only -> 401
        res_lib1 = auth_client.get("/api/library", headers=srv_header)
        assert res_lib1.status_code == 401
        assert "Missing or invalid Authorization header" in res_lib1.get_json()["error"]

        # 2. GET /api/library with X-Api-Key + query user_id -> MUST STILL BE 401!
        res_lib2 = auth_client.get(f"/api/library?user_id={USER_A_ID}", headers=srv_header)
        assert res_lib2.status_code == 401
        assert "Missing or invalid Authorization header" in res_lib2.get_json()["error"]

        # 3. GET /api/recommend/personalized with X-Api-Key only -> 401
        res_rec = auth_client.get("/api/recommend/personalized", headers=srv_header)
        assert res_rec.status_code == 401

        # 4. GET /api/preferences with X-Api-Key only -> 401
        res_pref = auth_client.get("/api/preferences", headers=srv_header)
        assert res_pref.status_code == 401

    """C. Valid service API key, no Bearer token, user-specific write -> reject."""
    def test_matrix_c_service_key_only_cannot_write_user_endpoints(self, auth_client, repo):
        srv_header = {"X-Api-Key": TEST_SERVICE_KEY, "Content-Type": "application/json"}

        # 1. POST /api/feedback without user_id -> 401
        res_fb1 = auth_client.post(
            "/api/feedback",
            headers=srv_header,
            json={"book_id": BOOK_ID_1, "interaction": "favorite"},
        )
        assert res_fb1.status_code == 401

        # 2. POST /api/feedback WITH spoofed user_id in body -> MUST STILL BE 401! (No bypass!)
        res_fb2 = auth_client.post(
            "/api/feedback",
            headers=srv_header,
            json={"user_id": USER_A_ID, "book_id": BOOK_ID_1, "interaction": "favorite"},
        )
        assert res_fb2.status_code == 401
        assert len(repo.favorites) == 0  # Zero database mutation!

        # 3. POST /api/onboarding WITH user_id -> 401
        res_onb = auth_client.post(
            "/api/onboarding",
            headers=srv_header,
            json={"user_id": USER_A_ID, "book_ids": [BOOK_ID_1], "genres": ["Fiction"]},
        )
        assert res_onb.status_code == 401

        # 4. PUT /api/preferences WITH user_id -> 401
        res_pref = auth_client.put(
            "/api/preferences",
            headers=srv_header,
            json={"user_id": USER_A_ID, "genres": ["Sci-Fi"]},
        )
        assert res_pref.status_code == 401

        # 5. POST /api/track WITH user_id -> 401
        res_trk = auth_client.post(
            "/api/track",
            headers=srv_header,
            json={"user_id": USER_A_ID, "book_id": BOOK_ID_1, "action": "view"},
        )
        assert res_trk.status_code == 401

    """D. Invalid or expired Bearer token -> reject."""
    def test_matrix_d_invalid_or_expired_bearer_token_rejected(self, auth_client):
        # 1. Expired token on protected route
        res1 = auth_client.get(
            "/api/library",
            headers={"X-Api-Key": TEST_SERVICE_KEY, "Authorization": "Bearer expired-token"},
        )
        assert res1.status_code == 401
        assert "Invalid or expired" in res1.get_json()["error"]

        # 2. Expired token on mutation
        res2 = auth_client.post(
            "/api/feedback",
            headers={"X-Api-Key": TEST_SERVICE_KEY, "Authorization": "Bearer expired-token"},
            json={"book_id": BOOK_ID_1, "interaction": "reading"},
        )
        assert res2.status_code == 401

    """E. Invalid signature, issuer, or audience -> reject."""
    def test_matrix_e_invalid_signature_or_audience_rejected(self, auth_client):
        # Invalid signature
        res_sig = auth_client.get(
            "/api/library",
            headers={"Authorization": "Bearer invalid-sig-token"},
        )
        assert res_sig.status_code == 401
        assert "Invalid" in res_sig.get_json()["error"]

        # Bad audience claim
        res_aud = auth_client.get(
            "/api/library",
            headers={"Authorization": "Bearer bad-audience-token"},
        )
        assert res_aud.status_code == 401
        assert "Invalid" in res_aud.get_json()["error"]

    """F. Valid User A token plus a request containing User B's user_id -> safely bind to User A."""
    def test_matrix_f_client_supplied_user_b_id_cannot_compromise_user_b(self, auth_client, repo):
        # User A sends request containing User B's user_id in payload
        headers_a = {
            "X-Api-Key": TEST_SERVICE_KEY,
            "Authorization": "Bearer valid-token-user-a",
        }
        res = auth_client.post(
            "/api/feedback",
            headers=headers_a,
            json={
                "user_id": USER_B_ID,  # Attacker tries to mutate User B
                "book_id": BOOK_ID_1,
                "interaction": "favorite",
            },
        )
        assert res.status_code == 200

        # Verified in repository: Favorite was assigned strictly to User A, NOT User B!
        assert USER_A_ID in repo.favorites
        assert BOOK_ID_1 in repo.favorites[USER_A_ID]
        assert USER_B_ID not in repo.favorites  # User B is completely untouched!

    """G. Valid User A token querying User B resource -> no access."""
    def test_matrix_g_user_a_cannot_query_user_b_library(self, auth_client, repo):
        # Setup: Seed User B with a favorite book
        repo.upsert_interactions([{
            "user_id": USER_B_ID,
            "book_id": BOOK_ID_2,
            "interaction_type": "favorite",
        }])

        # User A queries library with User A token and ?user_id=User_B
        headers_a = {
            "X-Api-Key": TEST_SERVICE_KEY,
            "Authorization": "Bearer valid-token-user-a",
        }
        res = auth_client.get(f"/api/library?user_id={USER_B_ID}", headers=headers_a)
        assert res.status_code == 200
        items = res.get_json()["items"]
        # User A must receive 0 items (User B's items are never leaked!)
        assert len(items) == 0

    """H. Valid User A token creating, updating, or deleting User B data -> no mutation."""
    def test_matrix_h_user_a_cannot_delete_or_mutate_user_b_data(self, auth_client, repo):
        # Seed User B's favorite
        repo.upsert_interactions([{
            "user_id": USER_B_ID,
            "book_id": BOOK_ID_2,
            "interaction_type": "favorite",
        }])

        # User A tries to unfavorite User B's book
        headers_a = {
            "X-Api-Key": TEST_SERVICE_KEY,
            "Authorization": "Bearer valid-token-user-a",
        }
        res = auth_client.post(
            "/api/feedback",
            headers=headers_a,
            json={"user_id": USER_B_ID, "book_id": BOOK_ID_2, "interaction": "unfavorite"},
        )
        assert res.status_code == 200

        # User B's favorite must STILL exist intact!
        assert BOOK_ID_2 in repo.favorites[USER_B_ID]

    """I. Valid User B token -> can access only User B's own data."""
    def test_matrix_i_user_b_accesses_own_data(self, auth_client, repo):
        # Seed User A and User B
        repo.upsert_interactions([
            {"user_id": USER_A_ID, "book_id": BOOK_ID_1, "interaction_type": "favorite"},
            {"user_id": USER_B_ID, "book_id": BOOK_ID_2, "interaction_type": "favorite"},
        ])

        headers_b = {
            "X-Api-Key": TEST_SERVICE_KEY,
            "Authorization": "Bearer valid-token-user-b",
        }
        res = auth_client.get("/api/library", headers=headers_b)
        assert res.status_code == 200
        items = res.get_json()["items"]
        assert len(items) == 1
        assert items[0]["book_id"] == BOOK_ID_2  # Sees only User B's own book

    """J. Legacy API-key-only internal callers -> public catalog endpoints succeed without user token."""
    def test_matrix_j_public_catalog_endpoints_succeed_with_service_key(self, auth_client):
        srv_header = {"X-Api-Key": TEST_SERVICE_KEY}

        res_cat = auth_client.get("/api/categories", headers=srv_header)
        assert res_cat.status_code == 200

        res_books = auth_client.get("/api/books", headers=srv_header)
        assert res_books.status_code == 200

        res_detail = auth_client.get(f"/api/books/{BOOK_ID_1}", headers=srv_header)
        assert res_detail.status_code == 200

        res_search = auth_client.get("/api/search?q=fiction", headers=srv_header)
        assert res_search.status_code == 200

    """K. Cross-user preferences & onboarding isolation -> spoofed user_id in body binds to token user."""
    def test_matrix_k_cross_user_preferences_and_onboarding_isolation(self, auth_client, repo):
        # User A updates preferences but puts User B's ID in body
        headers_a = {
            "X-Api-Key": TEST_SERVICE_KEY,
            "Authorization": "Bearer valid-token-user-a",
            "Content-Type": "application/json",
        }
        res_pref = auth_client.put(
            "/api/preferences",
            headers=headers_a,
            json={"user_id": USER_B_ID, "genres": ["Sci-Fi", "Cyberpunk"], "authors": ["William Gibson"]},
        )
        assert res_pref.status_code == 200

        # Verified in repository: User A profile was updated, User B profile was untouched
        assert USER_A_ID in repo.profiles
        assert repo.profiles[USER_A_ID]["preferred_genres"] == ["Sci-Fi", "Cyberpunk"]
        assert USER_B_ID not in repo.profiles

        # User A submits onboarding with User B's ID in body
        res_onb = auth_client.post(
            "/api/onboarding",
            headers=headers_a,
            json={"user_id": USER_B_ID, "book_ids": [BOOK_ID_1], "genres": ["Sci-Fi"]},
        )
        assert res_onb.status_code == 200
        # Verified: User A recorded the interaction, User B did not
        assert USER_A_ID in repo.interactions
        assert BOOK_ID_1 in repo.interactions[USER_A_ID]
        assert USER_B_ID not in repo.interactions

        # User A tracks activity with User B's ID in body
        res_trk = auth_client.post(
            "/api/track",
            headers=headers_a,
            json={"user_id": USER_B_ID, "book_id": BOOK_ID_1, "action": "view"},
        )
        assert res_trk.status_code == 200
        assert len(repo.activities) == 1
        assert repo.activities[0]["user_id"] == USER_A_ID  # Strictly User A!

    """L. Server key with invalid Bearer token -> rejected with 401."""
    def test_matrix_l_server_key_with_invalid_or_expired_bearer_rejected(self, auth_client):
        # 1. Server key with expired token on protected route -> 401
        res1 = auth_client.get(
            "/api/library",
            headers={"X-Api-Key": TEST_SERVICE_KEY, "Authorization": "Bearer expired-token"},
        )
        assert res1.status_code == 401
        assert "Invalid or expired" in res1.get_json()["error"]

        # 2. Server key with invalid signature token -> 401
        res2 = auth_client.post(
            "/api/feedback",
            headers={"X-Api-Key": TEST_SERVICE_KEY, "Authorization": "Bearer invalid-sig-token"},
            json={"book_id": BOOK_ID_1, "interaction": "reading"},
        )
        assert res2.status_code == 401

        # 3. Server key with malformed auth scheme -> 401
        res3 = auth_client.get(
            "/api/library",
            headers={"X-Api-Key": TEST_SERVICE_KEY, "Authorization": "Basic some-credentials"},
        )
        assert res3.status_code == 401
        assert "Invalid Authorization scheme" in res3.get_json()["error"]

    """M. Health and ready checks succeed without any credentials."""
    def test_matrix_m_health_endpoints_accessible_without_credentials(self, auth_client):
        res_health = auth_client.get("/api/health")
        assert res_health.status_code == 200
        assert res_health.get_json()["status"] == "healthy"

        res_ready = auth_client.get("/api/health/ready")
        assert res_ready.status_code == 200
        assert res_ready.get_json()["status"] == "ready"

    """N. Query param spoofing in personalized recommendations binds strictly to token subject."""
    def test_matrix_n_personalized_recs_spoofed_user_id_strictly_uses_token_subject(self, auth_client, monkeypatch):
        class SpiedRecommenderUC:
            def __init__(self):
                self.called_user_id = None
            def execute(self, user_id, limit=10):
                self.called_user_id = user_id
                return []

        spied_uc = SpiedRecommenderUC()
        monkeypatch.setattr("backend.routes.routes._get_personalized_recs_uc", spied_uc)

        headers_a = {
            "X-Api-Key": TEST_SERVICE_KEY,
            "Authorization": "Bearer valid-token-user-a",
        }
        res = auth_client.get(f"/api/recommend/personalized?user_id={USER_B_ID}", headers=headers_a)
        assert res.status_code == 200
        # Recommender UC was invoked strictly with User A's ID
        assert spied_uc.called_user_id == USER_A_ID
        assert res.get_json()["user_id"] == USER_A_ID

