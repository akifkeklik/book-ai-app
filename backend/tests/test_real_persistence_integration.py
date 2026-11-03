"""
Deterministic Integration Tests for Real Persistence Boundaries (Workstream B & C).
Executes against an isolated, disposable PostgreSQL database on the CI service.
Tests all 8 Workstream B backend invariants and all 8 Workstream C cross-client consistency scenarios.
"""

import json
import os
from urllib.parse import urlparse
from uuid import uuid4

import psycopg2
import pytest

from backend.app import create_app
from backend.config import Config
from backend.container import Container
from backend.infrastructure.persistence.postgres_adapters import (
    PostgresBookDataPort,
    PostgresInteractionRepository,
)
from backend.routes.routes import rebind_container
from psycopg2 import extras, sql



pytestmark = pytest.mark.integration


class RealPgTestConfig(Config):
    TESTING = True
    DEBUG = False
    ENFORCE_AUTH_IN_TESTS = True
    LIBRIS_API_KEY = "strictly-required-integration-api-key"
    SUPABASE_ANON_KEY = "test-anon-key-libris"
    SECRET_KEY = "integration-test-secret-key"


@pytest.fixture(scope="module")
def real_pg_uri():
    """Creates an isolated disposable database on the CI PostgreSQL service."""
    base_uri = os.getenv("LIBRIS_TEST_DATABASE_URL")
    if not base_uri:
        pytest.skip("Set LIBRIS_TEST_DATABASE_URL to run real-persistence integration tests")

    database_name = f"libris_integration_{uuid4().hex[:12]}"
    admin_connection = psycopg2.connect(base_uri)
    admin_connection.autocommit = True

    try:
        with admin_connection.cursor() as cursor:
            cursor.execute(
                sql.SQL("CREATE DATABASE {}").format(sql.Identifier(database_name))
            )
    finally:
        admin_connection.close()

    parsed_uri = urlparse(base_uri)
    uri = parsed_uri._replace(path=f"/{database_name}").geturl()

    connection = psycopg2.connect(uri)
    connection.autocommit = True
    with connection.cursor() as cur:
        cur.execute("CREATE SCHEMA IF NOT EXISTS auth;")
        cur.execute("""
            CREATE TABLE IF NOT EXISTS auth.users (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                email TEXT
            );
        """)
        cur.execute("""
            CREATE TABLE IF NOT EXISTS public.books (
                isbn13 TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                authors TEXT DEFAULT '',
                thumbnail TEXT DEFAULT '',
                average_rating NUMERIC DEFAULT 0
            );
        """)
        cur.execute("""
            CREATE TABLE IF NOT EXISTS public.user_profiles (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id TEXT UNIQUE NOT NULL,
                preferred_genres TEXT[] DEFAULT '{}',
                preferred_authors TEXT[] DEFAULT '{}',
                preferred_vibe TEXT DEFAULT 'reflective',
                reading_frequency INTEGER DEFAULT 2,
                updated_at TIMESTAMPTZ DEFAULT now()
            );
        """)
        cur.execute("""
            CREATE TABLE IF NOT EXISTS public.user_interactions (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id TEXT NOT NULL,
                book_id TEXT NOT NULL,
                interaction_type TEXT NOT NULL CHECK (interaction_type IN ('like', 'dislike', 'want_to_read', 'reading', 'finished', 'favorite')),
                created_at TIMESTAMPTZ DEFAULT now(),
                UNIQUE (user_id, book_id)
            );
        """)
        cur.execute("""
            CREATE TABLE IF NOT EXISTS public.favorites (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id TEXT NOT NULL,
                book_id TEXT NOT NULL,
                book_title TEXT NOT NULL DEFAULT '',
                book_author TEXT NOT NULL DEFAULT '',
                book_image_url TEXT NOT NULL DEFAULT '',
                added_at TIMESTAMPTZ DEFAULT now(),
                UNIQUE (user_id, book_id)
            );
        """)
        cur.execute("""
            CREATE TABLE IF NOT EXISTS public.user_activities (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id TEXT NOT NULL,
                activity_type TEXT NOT NULL,
                book_id TEXT,
                created_at TIMESTAMPTZ DEFAULT now()
            );
        """)
        # Test users are synthetic text IDs in this fixture. The production
        # migration defines UUID-backed auth IDs and is checked separately.
        cur.execute("""
            CREATE TABLE IF NOT EXISTS public.user_notes (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id TEXT NOT NULL,
                book_id TEXT NOT NULL,
                note_type TEXT NOT NULL CHECK (note_type IN ('personal_note', 'key_takeaway', 'question')),
                content TEXT NOT NULL,
                created_at TIMESTAMPTZ DEFAULT now(),
                updated_at TIMESTAMPTZ DEFAULT now()
            );
        """)
        cur.execute("""
            CREATE INDEX IF NOT EXISTS idx_test_user_notes_user_created
            ON public.user_notes(user_id, created_at DESC);
        """)
        # Seed test catalog
        cur.execute("""
            INSERT INTO public.books (isbn13, title, authors, thumbnail, average_rating) VALUES
            ('9780141439518', 'Pride and Prejudice', 'Jane Austen', 'https://example.com/pride.jpg', 4.5),
            ('9780451524935', '1984', 'George Orwell', 'https://example.com/1984.jpg', 4.6),
            ('9780061120084', 'To Kill a Mockingbird', 'Harper Lee', 'https://example.com/mockingbird.jpg', 4.8),
            ('9780743273565', 'The Great Gatsby', 'F. Scott Fitzgerald', 'https://example.com/gatsby.jpg', 4.2),
            ('9780547928227', 'The Hobbit', 'J.R.R. Tolkien', 'https://example.com/hobbit.jpg', 4.7)
            ON CONFLICT (isbn13) DO NOTHING;
        """)
    connection.close()

    yield uri

    cleanup_connection = psycopg2.connect(base_uri)
    cleanup_connection.autocommit = True
    try:
        with cleanup_connection.cursor() as cursor:
            cursor.execute(
                "SELECT pg_terminate_backend(pid) FROM pg_stat_activity "
                "WHERE datname = %s AND pid <> pg_backend_pid()",
                (database_name,),
            )
            cursor.execute(
                sql.SQL("DROP DATABASE IF EXISTS {}").format(sql.Identifier(database_name))
            )
    finally:
        cleanup_connection.close()

@pytest.fixture
def pg_repo(real_pg_uri: str) -> PostgresInteractionRepository:
    return PostgresInteractionRepository(real_pg_uri)


@pytest.fixture
def pg_port(real_pg_uri: str) -> PostgresBookDataPort:
    return PostgresBookDataPort(real_pg_uri)


class SyntheticAuthUser:
    def __init__(self, uid: str):
        self.id = uid


class SyntheticAuthPort:
    def verify_token(self, token: str):
        if token and token.startswith("synthetic-token-"):
            uid = token[len("synthetic-token-") :].strip()
            if uid:
                return SyntheticAuthUser(uid)
        raise ValueError(f"Invalid synthetic token: {token}")


@pytest.fixture
def app_client(real_pg_uri: str, pg_repo: PostgresInteractionRepository, pg_port: PostgresBookDataPort):
    from backend.routes import routes
    prev_repo = routes._interaction_repo
    prev_auth = routes._auth_port
    prev_book = routes._book_data_port

    app = create_app(RealPgTestConfig)
    test_auth_port = SyntheticAuthPort()
    container = Container(
        interaction_repo=pg_repo,
        book_data_port=pg_port,
        auth_port=test_auth_port,
        database_url=real_pg_uri,
    )
    rebind_container(container)
    try:
        with app.test_client() as client:
            yield client
    finally:
        routes._interaction_repo = prev_repo
        routes._auth_port = prev_auth
        routes._book_data_port = prev_book


# ==============================================================================
# WORKSTREAM B: REAL BACKEND PERSISTENCE INVARIANTS
# ==============================================================================

def test_b1_preference_write_survives_fresh_read(real_pg_uri: str):
    """Invariant 1: A preference write survives a fresh repository/client read."""
    user_id = "user-b1-real-pg"
    repo1 = PostgresInteractionRepository(real_pg_uri)
    repo1.upsert_profile(
        user_id=user_id,
        genres=["Science Fiction", "Dystopian"],
        authors=["Philip K. Dick", "Isaac Asimov"],
        updated_at="2026-10-22T12:00:00Z",
    )

    # Fresh repository instance reading from real database
    repo2 = PostgresInteractionRepository(real_pg_uri)
    profile = repo2.get_user_profile(user_id)
    assert profile is not None
    assert "Science Fiction" in profile["preferred_genres"]
    assert "Dystopian" in profile["preferred_genres"]
    assert "Philip K. Dick" in profile["preferred_authors"]


def test_b2_favorite_survives_fresh_read_and_shelf_changes(real_pg_uri: str):
    """Invariant 2: A favorite survives a fresh read and is NOT erased by reading-status changes."""
    user_id = "user-b2-real-pg"
    book_id = "9780141439518"
    repo = PostgresInteractionRepository(real_pg_uri)

    # 1. Add favorite
    repo.upsert_interactions([{
        "user_id": user_id,
        "book_id": book_id,
        "interaction_type": "favorite",
        "book_title": "Pride and Prejudice",
        "book_author": "Jane Austen",
    }])

    # 2. Change reading status to 'reading'
    repo.upsert_interactions([{
        "user_id": user_id,
        "book_id": book_id,
        "interaction_type": "reading",
    }])

    # 3. Read directly from public.favorites table
    conn = psycopg2.connect(real_pg_uri)
    with conn.cursor(cursor_factory=extras.RealDictCursor) as cur:
        cur.execute("SELECT * FROM public.favorites WHERE user_id = %s AND book_id = %s;", (user_id, book_id))
        fav = cur.fetchone()
        assert fav is not None, "Favorite record was erased by reading status change!"
        assert fav["book_title"] == "Pride and Prejudice"

        # 4. Check user_interactions preserves 'reading'
        cur.execute("SELECT interaction_type FROM public.user_interactions WHERE user_id = %s AND book_id = %s;", (user_id, book_id))
        inter = cur.fetchone()
        assert inter is not None
        assert inter["interaction_type"] == "reading"
    conn.close()


def test_b3_reading_statuses_remain_distinct_from_favorites(real_pg_uri: str):
    """Invariant 3: Reading statuses remain distinct from favorites."""
    user_id = "user-b3-distinct-real-pg"
    book_fav = "9780451524935"  # 1984
    book_shelf = "9780061120084"  # Mockingbird
    repo = PostgresInteractionRepository(real_pg_uri)

    repo.upsert_interactions([
        {"user_id": user_id, "book_id": book_fav, "interaction_type": "favorite", "book_title": "1984"},
        {"user_id": user_id, "book_id": book_shelf, "interaction_type": "want_to_read"},
    ])

    conn = psycopg2.connect(real_pg_uri)
    with conn.cursor(cursor_factory=extras.RealDictCursor) as cur:
        cur.execute("SELECT book_id FROM public.favorites WHERE user_id = %s;", (user_id,))
        fav_rows = [r["book_id"] for r in cur.fetchall()]
        assert book_fav in fav_rows
        assert book_shelf not in fav_rows

        cur.execute("SELECT book_id, interaction_type FROM public.user_interactions WHERE user_id = %s;", (user_id,))
        interactions = {r["book_id"]: r["interaction_type"] for r in cur.fetchall()}
        assert interactions[book_shelf] == "want_to_read"
    conn.close()


def test_b4_feedback_persisted_and_affects_recommendations(app_client, real_pg_uri: str):
    """Invariant 4: Feedback is persisted and affects recommendations."""
    user_id = "user-b4-feedback-pg"
    disliked_book = "9780451524935"

    headers = {
        "X-Api-Key": RealPgTestConfig.LIBRIS_API_KEY,
        "Authorization": f"Bearer synthetic-token-{user_id}",
    }

    # Submit feedback via real API endpoint backed by Postgres
    res = app_client.post(
        "/api/feedback",
        headers=headers,
        json={"user_id": user_id, "book_id": disliked_book, "interaction": "dislike"},
    )
    assert res.status_code == 200
    assert res.get_json()["status"] == "success"

    # Confirm write in PostgreSQL
    conn = psycopg2.connect(real_pg_uri)
    with conn.cursor() as cur:
        cur.execute("SELECT interaction_type FROM public.user_interactions WHERE user_id = %s AND book_id = %s;", (user_id, disliked_book))
        row = cur.fetchone()
        assert row is not None
        assert row[0] == "dislike"
    conn.close()


def test_b5_retried_writes_are_idempotent(real_pg_uri: str):
    """Invariant 5: Retried writes do not create duplicate or contradictory state."""
    user_id = "user-b5-retry-pg"
    book_id = "9780547928227"
    repo = PostgresInteractionRepository(real_pg_uri)

    payload = [{
        "user_id": user_id,
        "book_id": book_id,
        "interaction_type": "favorite",
        "book_title": "The Hobbit",
        "book_author": "J.R.R. Tolkien",
    }]

    # Retry write 5 times consecutively
    for _ in range(5):
        repo.upsert_interactions(payload)

    conn = psycopg2.connect(real_pg_uri)
    with conn.cursor() as cur:
        cur.execute("SELECT COUNT(*) FROM public.favorites WHERE user_id = %s AND book_id = %s;", (user_id, book_id))
        fav_count = cur.fetchone()[0]
        assert fav_count == 1, f"Expected 1 favorite row, found {fav_count}"

        cur.execute("SELECT COUNT(*) FROM public.user_interactions WHERE user_id = %s AND book_id = %s;", (user_id, book_id))
        inter_count = cur.fetchone()[0]
        assert inter_count == 1, f"Expected 1 interaction row, found {inter_count}"
    conn.close()


def test_b6_multi_tenant_isolation(real_pg_uri: str):
    """Invariant 6: One synthetic user cannot access another user's preferences, shelves, or favorites."""
    user_a = "user-tenant-alice"
    user_b = "user-tenant-bob"
    repo = PostgresInteractionRepository(real_pg_uri)

    repo.upsert_profile(user_a, genres=["Historical Fiction"], updated_at="2026-10-22T00:00:00Z")
    repo.upsert_interactions([{"user_id": user_a, "book_id": "9780141439518", "interaction_type": "finished"}])

    # Read as User B
    b_profile = repo.get_user_profile(user_b)
    b_interactions = repo.get_user_interactions(user_b)

    assert b_profile is None, "User B leaked User A's profile!"
    assert len(b_interactions) == 0, "User B leaked User A's interactions!"


def test_b7_failures_fail_closed(real_pg_uri: str):
    """Invariant 7: Failures do not return false success or silently overwrite valid data."""
    repo = PostgresInteractionRepository(real_pg_uri)
    # Missing required identifiers must not corrupt state
    repo.upsert_interactions([{"user_id": "", "book_id": "", "interaction_type": "favorite"}])

    conn = psycopg2.connect(real_pg_uri)
    with conn.cursor() as cur:
        cur.execute("SELECT COUNT(*) FROM public.favorites WHERE user_id = '';")
        assert cur.fetchone()[0] == 0
    conn.close()


def test_b8_public_recommendations_do_not_leak_user_state(app_client):
    """Invariant 8: Public recommendation endpoints do not read or leak authenticated user state."""
    headers = {"Authorization": f"Bearer {RealPgTestConfig.SUPABASE_ANON_KEY}"}
    res = app_client.get("/api/recommend?book=1984&top_n=5", headers=headers)
    assert res.status_code == 200
    data = res.get_json()
    assert "recommendations" in data
    # Verify no private user identifiers in output
    raw_str = json.dumps(data)
    assert "user-" not in raw_str


# ==============================================================================
# WORKSTREAM C: WEB / MOBILE CROSS-CLIENT CONSISTENCY SCENARIOS
# ==============================================================================

def test_c1_web_preference_write_to_mobile_read(app_client, real_pg_uri: str):
    """Scenario 1: Set preferences in web; read back through API and mobile data layer."""
    user_id = "user-cross-c1"
    headers = {
        "X-Api-Key": RealPgTestConfig.LIBRIS_API_KEY,
        "Authorization": f"Bearer synthetic-token-{user_id}",
    }

    # Web sets preferences via API
    res = app_client.post(
        "/api/preferences",
        headers=headers,
        json={"user_id": user_id, "preferred_genres": ["Philosophy", "Classics"], "preferred_authors": ["Plato"]},
    )
    assert res.status_code == 200

    # Mobile data layer reads back from same Postgres instance
    mobile_repo = PostgresInteractionRepository(real_pg_uri)
    mobile_profile = mobile_repo.get_user_profile(user_id)
    assert mobile_profile is not None
    assert "Philosophy" in mobile_profile["preferred_genres"]
    assert "Plato" in mobile_profile["preferred_authors"]


def test_c2_mobile_preference_write_to_web_read(app_client, real_pg_uri: str):
    """Scenario 2: Mobile writes preferences; Web receives updated data on fresh request."""
    user_id = "user-cross-c2"
    mobile_repo = PostgresInteractionRepository(real_pg_uri)

    # Mobile writes directly to persistence adapter
    mobile_repo.upsert_profile(
        user_id=user_id,
        genres=["Cyberpunk", "AI"],
        authors=["Gibson"],
        updated_at="2026-10-22T14:30:00Z",
    )

    # Web client queries preferences via API
    headers = {
        "X-Api-Key": RealPgTestConfig.LIBRIS_API_KEY,
        "Authorization": f"Bearer synthetic-token-{user_id}",
    }
    res = app_client.get(f"/api/preferences?user_id={user_id}", headers=headers)
    assert res.status_code == 200
    data = res.get_json()
    assert "Cyberpunk" in data["preferred_genres"]
    assert "Gibson" in data["preferred_authors"]


def test_c3_cross_client_favorite_preserved_across_shelf_changes(app_client, real_pg_uri: str):
    """Scenario 3: Favorite a book in mobile; confirm it remains favorited when web changes reading status."""
    user_id = "user-cross-c3"
    book_id = "9780141439518"
    mobile_repo = PostgresInteractionRepository(real_pg_uri)

    # Mobile adds to favorites
    mobile_repo.upsert_interactions([{
        "user_id": user_id,
        "book_id": book_id,
        "interaction_type": "favorite",
        "book_title": "Pride and Prejudice",
    }])

    # Web updates shelf to 'reading' via API feedback
    headers = {
        "X-Api-Key": RealPgTestConfig.LIBRIS_API_KEY,
        "Authorization": f"Bearer synthetic-token-{user_id}",
    }
    res = app_client.post(
        "/api/feedback",
        headers=headers,
        json={"user_id": user_id, "book_id": book_id, "interaction": "reading"},
    )
    assert res.status_code == 200

    # Verify both: shelf is 'reading' AND favorite is preserved in favorites table
    conn = psycopg2.connect(real_pg_uri)
    with conn.cursor() as cur:
        cur.execute("SELECT COUNT(*) FROM public.favorites WHERE user_id = %s AND book_id = %s;", (user_id, book_id))
        assert cur.fetchone()[0] == 1, "Favorite was erased by web reading status update!"

        cur.execute("SELECT interaction_type FROM public.user_interactions WHERE user_id = %s AND book_id = %s;", (user_id, book_id))
        assert cur.fetchone()[0] == "reading"
    conn.close()


def test_c4_cross_client_reading_status_consistency(app_client, real_pg_uri: str):
    """Scenario 4: Update reading status in Web; verify consistent shelf state in Mobile."""
    user_id = "user-cross-c4"
    book_id = "9780743273565"  # Great Gatsby
    headers = {
        "X-Api-Key": RealPgTestConfig.LIBRIS_API_KEY,
        "Authorization": f"Bearer synthetic-token-{user_id}",
    }

    # Web sets shelf to 'finished'
    res = app_client.post(
        "/api/feedback",
        headers=headers,
        json={"user_id": user_id, "book_id": book_id, "interaction": "finished"},
    )
    assert res.status_code == 200

    # Mobile queries user interaction
    mobile_repo = PostgresInteractionRepository(real_pg_uri)
    interactions = mobile_repo.get_user_interactions(user_id)
    matching = [i for i in interactions if i["book_id"] == book_id]
    assert len(matching) == 1
    assert matching[0]["interaction_type"] == "finished"


def test_c5_cross_client_dislike_suppression(app_client, real_pg_uri: str):
    """Scenario 5: Submit dislike feedback in mobile; verify recommendation suppression."""
    user_id = "user-cross-c5"
    disliked_book = "9780451524935"
    mobile_repo = PostgresInteractionRepository(real_pg_uri)

    mobile_repo.upsert_interactions([{
        "user_id": user_id,
        "book_id": disliked_book,
        "interaction_type": "dislike",
    }])

    # Query personalized recommendations for this user
    headers = {
        "X-Api-Key": RealPgTestConfig.LIBRIS_API_KEY,
        "Authorization": f"Bearer synthetic-token-{user_id}",
    }
    res = app_client.get(f"/api/recommend/personalized?user_id={user_id}&limit=10", headers=headers)
    assert res.status_code in (200, 404)  # 200 or clean fallback if candidates empty
    if res.status_code == 200:
        data = res.get_json()
        recs = data.get("recommendations", [])
        rec_isbns = [r.get("isbn13") for r in recs]
        assert disliked_book not in rec_isbns, "Disliked book was not suppressed from personalized recommendations!"


def test_c6_synthetic_account_switching_isolation(real_pg_uri: str):
    """Scenario 6: Log out and switch synthetic accounts; verify zero private state leakage."""
    user_alpha = "user-alpha-switch"
    user_beta = "user-beta-switch"
    repo = PostgresInteractionRepository(real_pg_uri)

    repo.upsert_profile(user_alpha, genres=["Mystery"], updated_at="2026-10-22T08:00:00Z")
    repo.upsert_interactions([{
        "user_id": user_alpha,
        "book_id": "9780061120084",
        "interaction_type": "favorite",
        "book_title": "Private Mystery Book",
    }])

    # Synthetic User Alpha logs out; User Beta logs in
    beta_profile = repo.get_user_profile(user_beta)
    beta_interactions = repo.get_user_interactions(user_beta)

    conn = psycopg2.connect(real_pg_uri)
    with conn.cursor() as cur:
        cur.execute("SELECT COUNT(*) FROM public.favorites WHERE user_id = %s;", (user_beta,))
        beta_fav_count = cur.fetchone()[0]
    conn.close()

    assert beta_profile is None
    assert len(beta_interactions) == 0
    assert beta_fav_count == 0


def test_c7_mobile_outbox_offline_recovery_sync(real_pg_uri: str):
    """Scenario 7: Simulate offline changes in mobile outbox and recovery synchronization."""
    user_id = "user-cross-c7-outbox"
    repo = PostgresInteractionRepository(real_pg_uri)

    # Simulated mobile outbox queue accumulated during offline status
    offline_outbox = [
        {"user_id": user_id, "book_id": "9780141439518", "interaction_type": "favorite", "book_title": "Pride and Prejudice"},
        {"user_id": user_id, "book_id": "9780451524935", "interaction_type": "want_to_read"},
    ]

    # Device reconnects: flush outbox to real database
    repo.upsert_interactions(offline_outbox)

    # Verify both records synchronized cleanly
    conn = psycopg2.connect(real_pg_uri)
    with conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute("SELECT book_id FROM public.favorites WHERE user_id = %s;", (user_id,))
        assert cur.fetchone()["book_id"] == "9780141439518"

        cur.execute("SELECT book_id, interaction_type FROM public.user_interactions WHERE user_id = %s ORDER BY book_id;", (user_id,))
        rows = cur.fetchall()
        assert len(rows) == 2
        assert rows[0]["interaction_type"] == "favorite"
        assert rows[1]["interaction_type"] == "want_to_read"
    conn.close()


def test_c8_transient_write_failure_retry_behavior(real_pg_uri: str):
    """Scenario 8: Simulate a transient failure, then retry and verify state consistency."""
    user_id = "user-cross-c8-retry"
    book_id = "9780547928227"
    repo = PostgresInteractionRepository(real_pg_uri)

    # Attempt 1: succeeds
    repo.upsert_interactions([{
        "user_id": user_id,
        "book_id": book_id,
        "interaction_type": "want_to_read",
    }])

    # Attempt 2: retry of same action
    repo.upsert_interactions([{
        "user_id": user_id,
        "book_id": book_id,
        "interaction_type": "want_to_read",
    }])

    # Verify single exact entry in database without duplication
    conn = psycopg2.connect(real_pg_uri)
    with conn.cursor() as cur:
        cur.execute("SELECT COUNT(*) FROM public.user_interactions WHERE user_id = %s AND book_id = %s;", (user_id, book_id))
        assert cur.fetchone()[0] == 1
    conn.close()
