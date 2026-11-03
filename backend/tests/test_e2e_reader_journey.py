"""
test_e2e_reader_journey.py — Comprehensive End-to-End Reader Journey & Cross-Account Isolation Tests.

Workstream A, B, and E Quality Gates:
  1. New reader opens app / unauthenticated visitor access to catalog & public recommendations.
  2. Unauthenticated access to private endpoints is rejected with 401.
  3. Reader (Account Alpha) selects preferences with duplicates & whitespace: validates and deduplicates.
  4. Preferences persist through API and remain associated strictly with authenticated account.
  5. Account Beta cannot see or modify Account Alpha's private preferences.
  6. Reopening and editing preferences updates taste profile without corrupting shelf state.
  7. Discovery home and recommendations display authentic provenance explanations.
  8. Disliking a book suppresses it from candidate recommendations.
  9. Favorite, want-to-read, reading, and finished states remain distinct.
  10. Clearing a reading status preserves favorites (Model A invariant).
  11. Cache headers enforce strict isolation:
      - /api/recommend/personalized, /api/preferences, /api/feedback, /api/track:
        'private, no-cache, no-store, max-age=0, must-revalidate', 'Vary: Authorization, Cookie'
      - /api/recommend?book=... & /api/books: 'public, max-age=300, stale-while-revalidate=600'
  12. Input validation for preferences: type checking, length bounds, duplicate deduplication.
"""

import json

import pytest
from backend.app import create_app
from backend.infrastructure.ml.recommender import BookRecommender


class SyntheticUser:
    def __init__(self, user_id: str):
        self.id = user_id


class StatefulInMemoryInteractionRepo:
    """Multi-tenant in-memory repository for deterministic testing."""

    def __init__(self):
        # user_id -> dict of book_id -> interaction dict
        self.interactions = {}
        # user_id -> profile dict
        self.profiles = {}
        # user_id -> set of favorite book_ids
        self.favorites = {}
        # list of recorded activities
        self.activities = []

    def get_user_interactions(self, user_id: str):
        user_map = self.interactions.get(user_id, {})
        return list(user_map.values())

    def get_user_profile(self, user_id: str):
        return self.profiles.get(user_id)

    def upsert_profile(self, user_id: str, genres: list, updated_at: str, authors: list = None):
        profile = self.profiles.get(user_id, {})
        profile["user_id"] = user_id
        profile["preferred_genres"] = genres
        profile["updated_at"] = updated_at
        if authors is not None:
            profile["preferred_authors"] = authors
        self.profiles[user_id] = profile

    def upsert_interactions(self, entries: list):
        for entry in entries:
            uid = entry.get("user_id")
            bid = str(entry.get("book_id"))
            itype = entry.get("interaction_type")

            if itype == "favorite":
                self.favorites.setdefault(uid, set()).add(bid)
                # Model A: favorite does not overwrite existing active reading status
                user_map = self.interactions.setdefault(uid, {})
                if bid not in user_map:
                    user_map[bid] = entry
            else:
                self.interactions.setdefault(uid, {})[bid] = entry

    def track_activity(self, payload: dict):
        self.activities.append(payload)

    def delete_interaction(
        self, user_id: str, book_id: str, interaction_type: str = None, preserve_favorites: bool = False
    ):
        user_map = self.interactions.get(user_id, {})
        bid = str(book_id)

        if interaction_type == "favorite":
            if user_id in self.favorites:
                self.favorites[user_id].discard(bid)
            if bid in user_map and user_map[bid].get("interaction_type") == "favorite":
                del user_map[bid]
        elif preserve_favorites:
            if bid in user_map and user_map[bid].get("interaction_type") != "favorite":
                del user_map[bid]
        else:
            if bid in user_map:
                del user_map[bid]
            if not preserve_favorites and user_id in self.favorites:
                self.favorites[user_id].discard(bid)


@pytest.fixture
def test_env(monkeypatch):
    app = create_app()
    app.config["TESTING"] = True
    app.config["PROPAGATE_EXCEPTIONS"] = False

    repo = StatefulInMemoryInteractionRepo()

    class MultiUserAuthPort:
        def verify_token(self, token: str):
            if token == "token-alpha":
                return SyntheticUser("user-alpha-101")
            elif token == "token-beta":
                return SyntheticUser("user-beta-202")
            raise Exception("Invalid token")

    sample_books = [
        {
            "isbn13": "9780000000001",
            "title": "Dune",
            "authors": "Frank Herbert",
            "categories": "Science Fiction",
            "description": "Epic desert planet sci-fi with spice and giant worms.",
            "average_rating": 4.5,
            "ratings_count": 1000,
            "popularity_score": 0.95,
        },
        {
            "isbn13": "9780000000002",
            "title": "Dune Messiah",
            "authors": "Frank Herbert",
            "categories": "Science Fiction",
            "description": "Continuation of the Dune saga and planetary empire.",
            "average_rating": 4.3,
            "ratings_count": 800,
            "popularity_score": 0.88,
        },
        {
            "isbn13": "9780000000003",
            "title": "Neuromancer",
            "authors": "William Gibson",
            "categories": "Science Fiction",
            "description": "Seminal cyberpunk novel featuring cyberspace and AI.",
            "average_rating": 4.2,
            "ratings_count": 900,
            "popularity_score": 0.85,
        },
        {
            "isbn13": "9780000000004",
            "title": "Pride and Prejudice",
            "authors": "Jane Austen",
            "categories": "Romance",
            "description": "Classic romantic literature exploring society and love.",
            "average_rating": 4.6,
            "ratings_count": 1500,
            "popularity_score": 0.98,
        },
        {
            "isbn13": "9780000000005",
            "title": "The Hobbit",
            "authors": "J.R.R. Tolkien",
            "categories": "Fantasy",
            "description": "Fantasy quest with hobbits, dragons, and treasure.",
            "average_rating": 4.7,
            "ratings_count": 2000,
            "popularity_score": 0.99,
        },
    ]
    recommender = BookRecommender()
    recommender.load_from_dicts(sample_books)
    recommender.fit()

    # Wire into backend routes
    monkeypatch.setattr("backend.routes.routes._auth_port", MultiUserAuthPort())
    monkeypatch.setattr("backend.routes.routes._get_preferences_uc._interaction_repo", repo)
    monkeypatch.setattr("backend.routes.routes._update_preferences_uc._interaction_repo", repo)
    monkeypatch.setattr("backend.routes.routes._submit_onboarding_uc._interaction_repo", repo)
    monkeypatch.setattr("backend.routes.routes._submit_feedback_uc._interaction_repo", repo)
    monkeypatch.setattr("backend.routes.routes._track_activity_uc._interaction_repo", repo)
    monkeypatch.setattr("backend.routes.routes._get_personalized_recs_uc._interaction_repo", repo)
    monkeypatch.setattr("backend.routes.routes._get_personalized_recs_uc._recommender", recommender)
    monkeypatch.setattr("backend.routes.routes._get_recommendations_uc._recommender", recommender)
    monkeypatch.setattr("backend.routes.routes._svc.recommender", recommender)

    with app.test_client() as client:
        yield {
            "client": client,
            "repo": repo,
            "headers_alpha": {"Authorization": "Bearer token-alpha"},
            "headers_beta": {"Authorization": "Bearer token-beta"},
        }


@pytest.mark.api
class TestEndToEndReaderJourney:
    """Full 12-step reader journey across synthetic accounts."""

    def test_complete_reader_journey_and_isolation(self, test_env):
        client = test_env["client"]
        headers_alpha = test_env["headers_alpha"]
        headers_beta = test_env["headers_beta"]

        # ── Step 1: Unauthenticated visitor can browse catalog & public recommendations ──
        res = client.get("/api/books")
        assert res.status_code == 200
        assert "public" in res.headers.get("Cache-Control", "")

        res_rec = client.get("/api/recommend?book=Dune")
        assert res_rec.status_code == 200
        assert "public" in res_rec.headers.get("Cache-Control", "")

        # ── Step 2: Unauthenticated access to personal endpoints is rejected ─────────────
        res_priv = client.get("/api/preferences")
        assert res_priv.status_code == 401
        assert "private" in res_priv.headers.get("Cache-Control", "")

        res_priv_rec = client.get("/api/recommend/personalized")
        assert res_priv_rec.status_code == 401

        # ── Step 3: Account Alpha sets up taste profile with duplicates & whitespace ───────
        payload_alpha = {
            "genres": ["Science Fiction", "Science Fiction", " Fantasy ", "  "],
            "authors": ["Frank Herbert", "Frank Herbert"],
        }
        res_post_alpha = client.post(
            "/api/preferences",
            headers=headers_alpha,
            data=json.dumps(payload_alpha),
            content_type="application/json",
        )
        assert res_post_alpha.status_code == 200
        data_alpha = res_post_alpha.get_json()
        assert data_alpha["status"] == "success"
        # Verify deduplication & whitespace trimming
        assert data_alpha["preferred_genres"] == ["Science Fiction", "Fantasy"]
        assert data_alpha["preferred_authors"] == ["Frank Herbert"]
        # Verify Cache-Control header is strictly private
        assert "private" in res_post_alpha.headers.get("Cache-Control", "")
        assert "no-store" in res_post_alpha.headers.get("Cache-Control", "")

        # ── Step 4: Account Alpha retrieves preferences via GET /api/preferences ─────────
        res_get_alpha = client.get("/api/preferences", headers=headers_alpha)
        assert res_get_alpha.status_code == 200
        get_data_alpha = res_get_alpha.get_json()
        assert get_data_alpha["user_id"] == "user-alpha-101"
        assert get_data_alpha["preferred_genres"] == ["Science Fiction", "Fantasy"]
        assert get_data_alpha["preferred_authors"] == ["Frank Herbert"]

        # ── Step 5: Account Beta cannot see Account Alpha's private preferences ───────────
        res_get_beta = client.get("/api/preferences", headers=headers_beta)
        assert res_get_beta.status_code == 200
        get_data_beta = res_get_beta.get_json()
        assert get_data_beta["user_id"] == "user-beta-202"
        # Beta has not calibrated yet: must be empty, NOT Alpha's data
        assert get_data_beta["preferred_genres"] == []
        assert get_data_beta["preferred_authors"] == []

        # ── Step 6: Account Alpha edits preferences (reopening settings) ──────────────────
        payload_update = {"genres": ["Science Fiction", "Mystery"]}
        res_put_alpha = client.put(
            "/api/preferences",
            headers=headers_alpha,
            data=json.dumps(payload_update),
            content_type="application/json",
        )
        assert res_put_alpha.status_code == 200
        assert res_put_alpha.get_json()["preferred_genres"] == ["Science Fiction", "Mystery"]

        # ── Step 7: Account Alpha marks 'Dune' as favorite and 'The Hobbit' as reading ────
        res_fav = client.post(
            "/api/feedback",
            headers=headers_alpha,
            data=json.dumps({"book_id": "9780000000001", "interaction": "favorite"}),
            content_type="application/json",
        )
        assert res_fav.status_code == 200

        res_reading = client.post(
            "/api/feedback",
            headers=headers_alpha,
            data=json.dumps({"book_id": "9780000000005", "interaction": "reading"}),
            content_type="application/json",
        )
        assert res_reading.status_code == 200

        # Verify favorite is in favorites set
        assert "9780000000001" in test_env["repo"].favorites.get("user-alpha-101", set())

        # ── Step 8: Clear reading status on 'The Hobbit' (Model A Deletion Safety) ────────
        res_clear = client.post(
            "/api/feedback",
            headers=headers_alpha,
            data=json.dumps({"book_id": "9780000000005", "interaction": "clear"}),
            content_type="application/json",
        )
        assert res_clear.status_code == 200
        # Favorite 'Dune' must remain 100% intact
        assert "9780000000001" in test_env["repo"].favorites.get("user-alpha-101", set())

        # ── Step 9: Disliking 'Pride and Prejudice' suppresses it from candidate feed ─────
        res_dislike = client.post(
            "/api/feedback",
            headers=headers_alpha,
            data=json.dumps({"book_id": "9780000000004", "interaction": "dislike"}),
            content_type="application/json",
        )
        assert res_dislike.status_code == 200

        # ── Step 10: Personalized recommendations for Account Alpha ───────────────────────
        res_recs_alpha = client.get("/api/recommend/personalized", headers=headers_alpha)
        assert res_recs_alpha.status_code == 200
        alpha_recs = res_recs_alpha.get_json()["recommendations"]
        alpha_titles = [r["title"] for r in alpha_recs]

        # 1. Negative feedback invariant: disliked book MUST NOT appear
        assert "Pride and Prejudice" not in alpha_titles
        # 2. Positive signal reinforcement: 'Dune Messiah' is recommended
        assert "Dune Messiah" in alpha_titles
        # 3. Provenance reason is genuine and grounded
        messiah_rec = next(r for r in alpha_recs if r["title"] == "Dune Messiah")
        assert "Dune" in messiah_rec.get("recommendation_reason", "")
        # 4. Cache header is private and uncacheable
        assert "private" in res_recs_alpha.headers.get("Cache-Control", "")
        assert "no-store" in res_recs_alpha.headers.get("Cache-Control", "")

        # ── Step 11: Cross-account recommendation isolation for Account Beta ──────────────
        res_recs_beta = client.get("/api/recommend/personalized", headers=headers_beta)
        assert res_recs_beta.status_code == 200
        beta_recs = res_recs_beta.get_json()["recommendations"]
        # Account Beta is cold-start: receives trending/popular, no 'Because you favorited Dune'
        for br in beta_recs:
            assert "Because you favorited 'Dune'" not in br.get("recommendation_reason", "")

    def test_preference_validation_rejects_malformed_input(self, test_env):
        client = test_env["client"]
        headers = test_env["headers_alpha"]

        # 1. Non-list genres
        res = client.post(
            "/api/preferences",
            headers=headers,
            data=json.dumps({"genres": "Science Fiction"}),
            content_type="application/json",
        )
        assert res.status_code == 400

        # 2. Non-string items inside genres
        res = client.post(
            "/api/preferences",
            headers=headers,
            data=json.dumps({"genres": [123, True]}),
            content_type="application/json",
        )
        assert res.status_code == 400

        # 3. Oversized genre string (>100 chars)
        res = client.post(
            "/api/preferences",
            headers=headers,
            data=json.dumps({"genres": ["A" * 105]}),
            content_type="application/json",
        )
        assert res.status_code == 400

        # 4. Non-string items inside authors
        res = client.post(
            "/api/preferences",
            headers=headers,
            data=json.dumps({"genres": ["Fiction"], "authors": [456]}),
            content_type="application/json",
        )
        assert res.status_code == 400

        # 5. Non-dict root JSON
        res = client.post(
            "/api/preferences",
            headers=headers,
            data=json.dumps(["Fiction"]),
            content_type="application/json",
        )
        assert res.status_code == 400

    def test_cache_headers_matrix(self, test_env):
        client = test_env["client"]
        headers = test_env["headers_alpha"]

        # Public endpoints
        public_routes = [
            "/api/books",
            "/api/categories",
            "/api/recommend?book=Dune",
        ]
        for route in public_routes:
            resp = client.get(route)
            assert resp.status_code == 200
            cc = resp.headers.get("Cache-Control", "")
            assert "public" in cc, f"Route {route} expected public cache control, got {cc}"

        # Private authenticated / mutation endpoints
        private_routes = [
            ("/api/preferences", "GET", None),
            ("/api/preferences", "POST", {"genres": ["Sci-Fi"]}),
            ("/api/feedback", "POST", {"book_id": "9780000000001", "interaction": "like"}),
            ("/api/track", "POST", {"book_id": "9780000000001", "action": "view"}),
            ("/api/recommend/personalized", "GET", None),
        ]
        for path, method, payload in private_routes:
            if method == "GET":
                resp = client.get(path, headers=headers)
            else:
                resp = client.post(path, headers=headers, data=json.dumps(payload), content_type="application/json")
            assert resp.status_code == 200, f"Route {path} failed with {resp.status_code}: {resp.data}"
            cc = resp.headers.get("Cache-Control", "")
            assert "private" in cc, f"Route {path} expected private cache control, got {cc}"
            assert "no-store" in cc, f"Route {path} expected no-store, got {cc}"
            assert "Vary" in resp.headers, f"Route {path} expected Vary header"
