"""
test_jwt_auth_adapter.py — Cryptographic JWT Verification Tests.

Proves:
  1. Valid HS256 JWT with correct signature, expiration, and audience is accepted.
  2. Wrong signature -> rejected.
  3. Expired token -> rejected.
  4. Wrong audience -> rejected.
  5. Wrong issuer -> rejected.
  6. Missing or empty subject -> rejected.
  7. Unsigned / 'none' algorithm -> rejected.
  8. Malformed or truncated token -> rejected.
  9. Container resolves SupabaseJwtAuthPort when configured.
  10. Flask end-to-end integration: Valid token authorizes user; invalid token rejected;
      spoofed user_id in payload binds strictly to verified subject.
"""

import time

import jwt
import pytest
from backend.app import create_app
from backend.config import Config
from backend.container import Container
from backend.infrastructure.security.jwt_auth_adapter import AuthUser, SupabaseJwtAuthPort
from backend.routes.routes import rebind_container

TEST_JWT_SECRET = "super-secure-local-test-jwt-secret-key-32bytes!!"
TEST_SERVICE_KEY = "libris-test-service-key-888"


class MockInteractionRepo:
    def __init__(self):
        self.favorites = {}  # uid -> {book_id: dict}
        self.interactions = {}  # uid -> {book_id: str}

    def get_user_interactions(self, user_id):
        items = self.interactions.get(user_id, {})
        return [{"user_id": user_id, "book_id": b, "interaction_type": t} for b, t in items.items()]

    def get_user_favorites(self, user_id):
        return list(self.favorites.get(user_id, {}).values())

    def upsert_interactions(self, entries):
        for e in entries:
            uid = e["user_id"]
            bid = e["book_id"]
            itype = e.get("interaction_type")
            if uid not in self.interactions:
                self.interactions[uid] = {}
            if uid not in self.favorites:
                self.favorites[uid] = {}
            if itype == "favorite":
                self.favorites[uid][bid] = {"book_id": bid, "book_title": "Test Book", "added_at": "2026-10-27T00:00:00Z"}
            else:
                self.interactions[uid][bid] = itype

    def delete_interaction(self, user_id, book_id, interaction_type=None, preserve_favorites=False):
        pass


class MockBookPort:
    def get_books_by_isbns(self, isbns):
        return [{"isbn13": b, "title": f"Book {b}", "authors": "Author", "thumbnail": ""} for b in isbns]

    def check_health(self):
        return True


def create_token(
    user_id="user-uuid-1111",
    secret=TEST_JWT_SECRET,
    algorithm="HS256",
    expires_in=3600,
    audience="authenticated",
    issuer="https://test.supabase.co/auth/v1",
    email="user@test.local",
    role="authenticated",
    omit_sub=False,
):
    now = int(time.time())
    payload = {
        "aud": audience,
        "exp": now + expires_in,
        "iat": now,
        "email": email,
        "role": role,
    }
    if issuer:
        payload["iss"] = issuer
    if not omit_sub:
        payload["sub"] = user_id
    if algorithm == "none":
        return jwt.encode(payload, "", algorithm="none")
    return jwt.encode(payload, secret, algorithm=algorithm)


# ─────────────────────────────────────────────────────────────────────────────
# Unit Tests for SupabaseJwtAuthPort
# ─────────────────────────────────────────────────────────────────────────────

def test_valid_token_acceptance():
    port = SupabaseJwtAuthPort(secret=TEST_JWT_SECRET, audience="authenticated")
    token = create_token(user_id="user-12345", email="test@example.com")
    user = port.verify_token(token)
    assert isinstance(user, AuthUser)
    assert user.id == "user-12345"
    assert user.email == "test@example.com"
    assert user.role == "authenticated"


def test_wrong_signature_rejected():
    port = SupabaseJwtAuthPort(secret=TEST_JWT_SECRET, audience="authenticated")
    token = create_token(secret="completely-different-secret-key-999")
    with pytest.raises(ValueError, match="signature verification failed"):
        port.verify_token(token)


def test_expired_token_rejected():
    port = SupabaseJwtAuthPort(secret=TEST_JWT_SECRET, audience="authenticated")
    token = create_token(expires_in=-60)  # Expired 60s ago
    with pytest.raises(ValueError, match="Token has expired"):
        port.verify_token(token)


def test_wrong_audience_rejected():
    port = SupabaseJwtAuthPort(secret=TEST_JWT_SECRET, audience="authenticated")
    token = create_token(audience="wrong-service-aud")
    with pytest.raises(ValueError, match="audience mismatch"):
        port.verify_token(token)


def test_wrong_issuer_rejected():
    port = SupabaseJwtAuthPort(
        secret=TEST_JWT_SECRET,
        audience="authenticated",
        issuer="https://valid.supabase.co/auth/v1",
    )
    token = create_token(issuer="https://rogue.attacker.co/auth/v1")
    with pytest.raises(ValueError, match="issuer mismatch"):
        port.verify_token(token)


def test_matching_issuer_accepted():
    port = SupabaseJwtAuthPort(
        secret=TEST_JWT_SECRET,
        audience="authenticated",
        issuer="https://valid.supabase.co/auth/v1",
    )
    token = create_token(issuer="https://valid.supabase.co/auth/v1")
    user = port.verify_token(token)
    assert user.id == "user-uuid-1111"


def test_missing_sub_rejected():
    port = SupabaseJwtAuthPort(secret=TEST_JWT_SECRET, audience="authenticated")
    token = create_token(omit_sub=True)
    with pytest.raises(ValueError):
        port.verify_token(token)


def test_empty_sub_rejected():
    port = SupabaseJwtAuthPort(secret=TEST_JWT_SECRET, audience="authenticated")
    token = create_token(user_id="   ")
    with pytest.raises(ValueError, match="missing or invalid 'sub' claim"):
        port.verify_token(token)


def test_unsigned_none_algorithm_rejected():
    port = SupabaseJwtAuthPort(secret=TEST_JWT_SECRET, audience="authenticated")
    token = create_token(algorithm="none")
    with pytest.raises(ValueError):
        port.verify_token(token)


def test_malformed_token_rejected():
    port = SupabaseJwtAuthPort(secret=TEST_JWT_SECRET, audience="authenticated")
    with pytest.raises(ValueError):
        port.verify_token("not.a.valid.jwt.string")


# ─────────────────────────────────────────────────────────────────────────────
# Container Integration Tests
# ─────────────────────────────────────────────────────────────────────────────

def test_container_resolves_jwt_auth_port_when_secret_set(monkeypatch):
    monkeypatch.setattr(Config, "SUPABASE_JWT_SECRET", TEST_JWT_SECRET)
    monkeypatch.setattr(Config, "SUPABASE_JWT_AUDIENCE", "authenticated")
    c = Container(database_url="sqlite:///:memory:")
    assert isinstance(c.auth_port, SupabaseJwtAuthPort)


def test_container_fails_closed_when_no_auth_configured(monkeypatch):
    monkeypatch.setattr(Config, "SUPABASE_JWT_SECRET", "")
    monkeypatch.setattr(Config, "SUPABASE_URL", "")
    monkeypatch.setattr(Config, "SUPABASE_ANON_KEY", "")
    c = Container(database_url="sqlite:///:memory:")
    assert c.auth_port is None


# ─────────────────────────────────────────────────────────────────────────────
# Flask Route End-to-End Tests with SupabaseJwtAuthPort
# ─────────────────────────────────────────────────────────────────────────────

@pytest.fixture
def jwt_auth_client(monkeypatch):
    from backend.routes import routes
    prev_repo = routes._interaction_repo
    prev_auth = routes._auth_port
    prev_book = routes._book_data_port

    repo = MockInteractionRepo()
    book_port = MockBookPort()
    auth_port = SupabaseJwtAuthPort(secret=TEST_JWT_SECRET, audience="authenticated")

    container = Container(
        interaction_repo=repo,
        book_data_port=book_port,
        auth_port=auth_port,
    )
    rebind_container(container)

    app = create_app()
    app.config["TESTING"] = True
    app.config["ENFORCE_AUTH_IN_TESTS"] = True
    app.config["LIBRIS_API_KEY"] = TEST_SERVICE_KEY
    app.config["SUPABASE_ANON_KEY"] = "mock-anon-key"

    try:
        with app.test_client() as client:
            yield client, repo
    finally:
        routes._interaction_repo = prev_repo
        routes._auth_port = prev_auth
        routes._book_data_port = prev_book


def test_valid_token_authorizes_library_and_feedback(jwt_auth_client):
    client, repo = jwt_auth_client
    user_a_id = "user-alice-uuid-99"
    token = create_token(user_id=user_a_id)

    # 1. User A adds favorite book
    res_fav = client.post(
        "/api/feedback",
        headers={"X-Api-Key": TEST_SERVICE_KEY, "Authorization": f"Bearer {token}"},
        json={"book_id": "9780007111503", "interaction": "favorite"},
    )
    assert res_fav.status_code == 200
    assert res_fav.get_json()["status"] == "success"

    # 2. User A retrieves library
    res_lib = client.get(
        "/api/library",
        headers={"X-Api-Key": TEST_SERVICE_KEY, "Authorization": f"Bearer {token}"},
    )
    assert res_lib.status_code == 200
    items = res_lib.get_json()["items"]
    assert len(items) == 1
    assert items[0]["book_id"] == "9780007111503"


def test_expired_token_rejected_with_401(jwt_auth_client):
    client, repo = jwt_auth_client
    token = create_token(expires_in=-10)

    res = client.get(
        "/api/library",
        headers={"X-Api-Key": TEST_SERVICE_KEY, "Authorization": f"Bearer {token}"},
    )
    assert res.status_code == 401
    assert "Invalid or expired" in res.get_json()["error"]


def test_wrong_secret_token_rejected_with_401(jwt_auth_client):
    client, repo = jwt_auth_client
    token = create_token(secret="wrong-secret-key-12345678901234567890")

    res = client.get(
        "/api/library",
        headers={"X-Api-Key": TEST_SERVICE_KEY, "Authorization": f"Bearer {token}"},
    )
    assert res.status_code == 401


def test_spoofed_user_id_in_payload_bound_to_token_user(jwt_auth_client):
    client, repo = jwt_auth_client
    user_alice = "user-alice-uuid"
    user_bob = "user-bob-uuid"
    token_alice = create_token(user_id=user_alice)

    # Alice sends Bob's user_id in the JSON body
    res = client.post(
        "/api/feedback",
        headers={"X-Api-Key": TEST_SERVICE_KEY, "Authorization": f"Bearer {token_alice}"},
        json={"user_id": user_bob, "book_id": "9780007111503", "interaction": "favorite"},
    )
    assert res.status_code == 200

    # Verify Bob was NOT modified, Alice received the favorite
    assert user_bob not in repo.favorites
    assert user_alice in repo.favorites
    assert "9780007111503" in repo.favorites[user_alice]
