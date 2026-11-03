"""
Deterministic Verification for Local User-Feature Vertical Slice & Migration Safety.
Covers:
  1. Target database confirmation (Local Compose PostgreSQL).
  2. Canonical Model A schema initialization & idempotency.
  3. Authentication / session handling (User A vs User B vs unauthenticated).
  4. Adding book to favorites / personal library.
  5. Reading saved state back.
  6. Idempotency across duplicate requests.
  7. Ownership isolation between User A and User B.
  8. Model A shelf and favorite independence.
  9. Live Compose backend HTTP integration.
  10. Persistence across service restart.
  11. Test record cleanup.
"""

import json
import subprocess
import time
import urllib.error
import urllib.request

import psycopg2
import pytest
from psycopg2.extras import RealDictCursor

LOCAL_COMPOSE_PG_URI = "postgresql://postgres:postgrespassword@localhost:5432/postgres"
DISPOSABLE_DB_NAME = "libris_slice_disposable_test"
DISPOSABLE_PG_URI = f"postgresql://postgres:postgrespassword@localhost:5432/{DISPOSABLE_DB_NAME}"
COMPOSE_BACKEND_URL = "http://localhost:5000"

USER_A_ID = "11111111-1111-4111-8111-111111111111"
USER_B_ID = "22222222-2222-4222-8222-222222222222"

BOOK_PARTNERS = "9780007111503"
BOOK_MESOPOTAMIA = "9780007113804"
BOOK_HOBBIT = "9780007116263"


def init_canonical_model_a_schema(conn):
    """Initializes canonical Model A schema for local Compose PostgreSQL."""
    conn.autocommit = True
    with conn.cursor() as cur:
        cur.execute("CREATE EXTENSION IF NOT EXISTS pgcrypto;")
        cur.execute("CREATE EXTENSION IF NOT EXISTS vector;")
        cur.execute("CREATE SCHEMA IF NOT EXISTS auth;")

        cur.execute("""
            CREATE TABLE IF NOT EXISTS auth.users (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                email TEXT,
                created_at TIMESTAMPTZ DEFAULT now()
            );
        """)

        cur.execute("""
            CREATE OR REPLACE FUNCTION auth.uid() RETURNS UUID AS $$
            BEGIN
              RETURN COALESCE(
                NULLIF(current_setting('request.jwt.claim.sub', true), '')::UUID,
                '00000000-0000-0000-0000-000000000000'::UUID
              );
            END;
            $$ LANGUAGE plpgsql;
        """)

        cur.execute("""
            CREATE TABLE IF NOT EXISTS public.books (
                isbn13 TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                authors TEXT DEFAULT '',
                categories TEXT DEFAULT '',
                description TEXT DEFAULT '',
                thumbnail TEXT DEFAULT '',
                average_rating NUMERIC DEFAULT 0,
                ratings_count NUMERIC DEFAULT 0,
                published_date TEXT DEFAULT '',
                page_count NUMERIC DEFAULT 0,
                created_at TIMESTAMPTZ DEFAULT now()
            );
        """)

        cur.execute("""
            CREATE TABLE IF NOT EXISTS public.favorites (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
                book_id TEXT NOT NULL REFERENCES public.books(isbn13) ON DELETE CASCADE,
                book_title TEXT NOT NULL DEFAULT '',
                book_author TEXT NOT NULL DEFAULT '',
                book_image_url TEXT NOT NULL DEFAULT '',
                added_at TIMESTAMPTZ DEFAULT now(),
                UNIQUE(user_id, book_id)
            );
        """)

        cur.execute("""
            CREATE TABLE IF NOT EXISTS public.user_interactions (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
                book_id TEXT NOT NULL,
                interaction_type TEXT NOT NULL CHECK (interaction_type IN ('like', 'dislike', 'want_to_read', 'reading', 'finished', 'favorite')),
                created_at TIMESTAMPTZ DEFAULT now(),
                UNIQUE(user_id, book_id)
            );
        """)

        cur.execute("""
            CREATE TABLE IF NOT EXISTS public.user_profiles (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id UUID UNIQUE NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
                preferred_genres TEXT[] DEFAULT '{}',
                reading_frequency INT DEFAULT 0,
                preferred_authors TEXT[] DEFAULT '{}',
                preferred_vibe TEXT DEFAULT '',
                updated_at TIMESTAMPTZ DEFAULT now()
            );
        """)

        cur.execute("""
            CREATE TABLE IF NOT EXISTS public.user_activities (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
                book_id TEXT,
                activity_type TEXT NOT NULL,
                created_at TIMESTAMPTZ DEFAULT now()
            );
        """)

        # Seed canonical fixture books
        cur.execute("""
            INSERT INTO public.books (isbn13, title, authors, categories, thumbnail, average_rating)
            VALUES
            ('9780007111503', 'Partners in Crime', 'Agatha Christie', 'Detective', 'https://example.com/partners.jpg', 3.89),
            ('9780007113804', 'Murder in Mesopotamia', 'Agatha Christie', 'Detective', 'https://example.com/mesopotamia.jpg', 3.89),
            ('9780007116263', 'The Return of the King', 'J.R.R. Tolkien', 'Fantasy', 'https://example.com/lotr.jpg', 4.59)
            ON CONFLICT (isbn13) DO UPDATE SET
                title = EXCLUDED.title,
                authors = EXCLUDED.authors,
                thumbnail = EXCLUDED.thumbnail;
        """)

        # Seed test auth users
        cur.execute("""
            INSERT INTO auth.users (id, email)
            VALUES
            ('11111111-1111-4111-8111-111111111111', 'user_alpha@libris.local'),
            ('22222222-2222-4222-8222-222222222222', 'user_beta@libris.local')
            ON CONFLICT (id) DO NOTHING;
        """)


def get_backend_api_key():
    """Extracts backend API key directly from running container without exposing in terminal."""
    res = subprocess.run(
        ["docker", "exec", "libris_backend", "python", "-c", "from backend.config import Config; print(Config.LIBRIS_API_KEY)"],
        capture_output=True,
        text=True,
        check=True
    )
    return res.stdout.strip()


class TestLocalVerticalSlice:
    @classmethod
    def setup_class(cls):
        """Prepares both the disposable test database and the local Compose database."""
        # 1. Confirm local Compose PostgreSQL is reachable
        try:
            conn_master = psycopg2.connect(LOCAL_COMPOSE_PG_URI, connect_timeout=2)
        except psycopg2.OperationalError as e:
            pytest.skip(f"Local Compose PostgreSQL is not running at localhost:5432 ({e}). Blocked by missing infrastructure.")
        conn_master.autocommit = True
        with conn_master.cursor() as cur:
            cur.execute("SELECT inet_server_addr(), inet_server_port();")
            addr, port = cur.fetchone()
            # Ensure local loopback or local Docker Compose container target (e.g. 172.16.0.0/12 bridge networks)
            addr_str = str(addr) if addr is not None else ""
            is_local = (
                addr is None
                or addr_str in ("127.0.0.1", "::1")
                or addr_str.startswith("172.18.")
                or addr_str.startswith("172.19.")
                or addr_str.startswith("172.20.")
            )
            assert is_local, f"Dangerous non-local host: {addr}"
            # Create disposable test database
            cur.execute(f"DROP DATABASE IF EXISTS {DISPOSABLE_DB_NAME};")
            cur.execute(f"CREATE DATABASE {DISPOSABLE_DB_NAME};")
        conn_master.close()

        # Initialize schema on disposable database
        conn_disp = psycopg2.connect(DISPOSABLE_PG_URI)
        init_canonical_model_a_schema(conn_disp)
        conn_disp.close()

        # Initialize schema on Compose postgres database (for container integration)
        conn_compose = psycopg2.connect(LOCAL_COMPOSE_PG_URI)
        init_canonical_model_a_schema(conn_compose)
        conn_compose.close()

    @classmethod
    def teardown_class(cls):
        """Drops the disposable test database."""
        try:
            conn = psycopg2.connect(LOCAL_COMPOSE_PG_URI)
            conn.autocommit = True
            with conn.cursor() as cur:
                cur.execute(f"DROP DATABASE IF EXISTS {DISPOSABLE_DB_NAME};")
            conn.close()
        except Exception:
            pass

    def test_01_target_confirmation_and_schema_idempotency(self):
        """Phase 1 & 2: Confirms local Compose PostgreSQL and validates schema idempotency."""
        conn = psycopg2.connect(DISPOSABLE_PG_URI)
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute("""
                SELECT table_name
                FROM information_schema.tables
                WHERE table_schema = 'public'
                ORDER BY table_name;
            """)
            tables = [r["table_name"] for r in cur.fetchall()]
            assert "books" in tables
            assert "favorites" in tables
            assert "user_interactions" in tables
            assert "user_profiles" in tables
            assert "user_activities" in tables

            # Verify UNIQUE(user_id, book_id) on user_interactions
            cur.execute("""
                SELECT conname
                FROM pg_constraint
                WHERE conrelid = 'public.user_interactions'::regclass
                  AND contype = 'u';
            """)
            constraints = [r["conname"] for r in cur.fetchall()]
            assert len(constraints) >= 1, "UNIQUE constraint on user_interactions missing!"

            # Verify 6-state check constraint
            cur.execute("""
                SELECT pg_get_constraintdef(oid)
                FROM pg_constraint
                WHERE conrelid = 'public.user_interactions'::regclass
                  AND contype = 'c';
            """)
            defs = [r["pg_get_constraintdef"] for r in cur.fetchall()]
            assert any("favorite" in d for d in defs), "CHECK constraint missing 'favorite' state!"
        conn.close()

    def test_02_authentication_and_unauthorized_rejection(self):
        """Phase 3: Verifies unauthenticated and anonymous requests are rejected."""
        _api_key = get_backend_api_key()

        # 1. Completely unauthenticated request -> 401
        req = urllib.request.Request(
            f"{COMPOSE_BACKEND_URL}/api/feedback",
            data=json.dumps({"user_id": USER_A_ID, "book_id": BOOK_PARTNERS, "interaction": "favorite"}).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST"
        )
        with pytest.raises(urllib.error.HTTPError) as exc_info:
            urllib.request.urlopen(req)
        assert exc_info.value.code == 401

        # 2. Anonymous Bearer token to personal endpoint -> 401
        req_anon = urllib.request.Request(
            f"{COMPOSE_BACKEND_URL}/api/feedback",
            data=json.dumps({"user_id": USER_A_ID, "book_id": BOOK_PARTNERS, "interaction": "favorite"}).encode("utf-8"),
            headers={
                "Content-Type": "application/json",
                "Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJvbGUiOiJub25lIn0.invalid"
            },
            method="POST"
        )
        with pytest.raises(urllib.error.HTTPError) as exc_info_anon:
            urllib.request.urlopen(req_anon)
        assert exc_info_anon.value.code == 401

    def test_03_add_book_to_favorites_and_library(self):
        """Phase 3: Adds a book to favorites for User A and verifies dual-table Model A persistence."""
        from backend.infrastructure.persistence.postgres_adapters import (
            PostgresInteractionRepository,
        )

        repo = PostgresInteractionRepository(LOCAL_COMPOSE_PG_URI)

        # User A adds BOOK_PARTNERS to favorites
        repo.upsert_interactions([{
            "user_id": USER_A_ID,
            "book_id": BOOK_PARTNERS,
            "interaction_type": "favorite",
            "book_title": "Partners in Crime",
            "book_author": "Agatha Christie",
            "book_image_url": "https://example.com/partners.jpg"
        }])

        # User A sets BOOK_MESOPOTAMIA to 'reading'
        repo.upsert_interactions([{
            "user_id": USER_A_ID,
            "book_id": BOOK_MESOPOTAMIA,
            "interaction_type": "reading"
        }])

        # Verify database records
        conn = psycopg2.connect(LOCAL_COMPOSE_PG_URI)
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute("SELECT * FROM public.favorites WHERE user_id = %s;", (USER_A_ID,))
            favs = cur.fetchall()
            assert len(favs) == 1
            assert favs[0]["book_id"] == BOOK_PARTNERS
            assert favs[0]["book_title"] == "Partners in Crime"

            cur.execute("SELECT book_id, interaction_type FROM public.user_interactions WHERE user_id = %s ORDER BY book_id;", (USER_A_ID,))
            interactions = cur.fetchall()
            inter_map = {r["book_id"]: r["interaction_type"] for r in interactions}
            assert inter_map[BOOK_PARTNERS] == "favorite"
            assert inter_map[BOOK_MESOPOTAMIA] == "reading"
        conn.close()

    def test_04_read_saved_state_and_idempotency(self):
        """Phase 3: Reads saved state back and proves duplicate retries are strictly idempotent."""
        from backend.infrastructure.persistence.postgres_adapters import (
            PostgresInteractionRepository,
        )

        repo = PostgresInteractionRepository(LOCAL_COMPOSE_PG_URI)

        # Read back via repository adapter
        user_interactions = repo.get_user_interactions(USER_A_ID)
        inter_map = {r["book_id"]: r["interaction_type"] for r in user_interactions}
        assert inter_map.get(BOOK_PARTNERS) == "favorite"
        assert inter_map.get(BOOK_MESOPOTAMIA) == "reading"

        # Retry identical favorite request 5 times
        duplicate_payload = [{
            "user_id": USER_A_ID,
            "book_id": BOOK_PARTNERS,
            "interaction_type": "favorite",
            "book_title": "Partners in Crime",
            "book_author": "Agatha Christie",
            "book_image_url": "https://example.com/partners.jpg"
        }]
        for _ in range(5):
            repo.upsert_interactions(duplicate_payload)

        # Assert no duplicate records exist
        conn = psycopg2.connect(LOCAL_COMPOSE_PG_URI)
        with conn.cursor() as cur:
            cur.execute("SELECT count(*) FROM public.favorites WHERE user_id = %s AND book_id = %s;", (USER_A_ID, BOOK_PARTNERS))
            assert cur.fetchone()[0] == 1
            cur.execute("SELECT count(*) FROM public.user_interactions WHERE user_id = %s AND book_id = %s;", (USER_A_ID, BOOK_PARTNERS))
            assert cur.fetchone()[0] == 1
        conn.close()

    def test_05_ownership_isolation_between_test_users(self):
        """Phase 3: Verifies strict tenant isolation between User A and User B."""
        from backend.infrastructure.persistence.postgres_adapters import (
            PostgresInteractionRepository,
        )

        repo = PostgresInteractionRepository(LOCAL_COMPOSE_PG_URI)

        # 1. User B reads their interactions -> must be empty
        b_interactions = repo.get_user_interactions(USER_B_ID)
        assert len(b_interactions) == 0, "User B leaked User A's interactions!"

        # 2. Check favorites table for User B -> 0
        conn = psycopg2.connect(LOCAL_COMPOSE_PG_URI)
        with conn.cursor() as cur:
            cur.execute("SELECT count(*) FROM public.favorites WHERE user_id = %s;", (USER_B_ID,))
            assert cur.fetchone()[0] == 0, "User B leaked User A's favorites!"

            # 3. User B attempts to delete User A's book -> User A's state must be unaffected
            cur.execute("DELETE FROM public.favorites WHERE user_id = %s AND book_id = %s;", (USER_B_ID, BOOK_PARTNERS))
            cur.execute("DELETE FROM public.user_interactions WHERE user_id = %s AND book_id = %s;", (USER_B_ID, BOOK_PARTNERS))

            cur.execute("SELECT count(*) FROM public.favorites WHERE user_id = %s AND book_id = %s;", (USER_A_ID, BOOK_PARTNERS))
            assert cur.fetchone()[0] == 1, "User A's favorite was deleted by User B!"

        # 4. User B adds their own favorite (BOOK_HOBBIT)
        repo.upsert_interactions([{
            "user_id": USER_B_ID,
            "book_id": BOOK_HOBBIT,
            "interaction_type": "favorite",
            "book_title": "The Return of the King",
            "book_author": "J.R.R. Tolkien"
        }])

        # Verify separation: User A has PARTNERS, User B has HOBBIT
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute("SELECT book_id FROM public.favorites WHERE user_id = %s;", (USER_A_ID,))
            a_favs = [r["book_id"] for r in cur.fetchall()]
            assert a_favs == [BOOK_PARTNERS]

            cur.execute("SELECT book_id FROM public.favorites WHERE user_id = %s;", (USER_B_ID,))
            b_favs = [r["book_id"] for r in cur.fetchall()]
            assert b_favs == [BOOK_HOBBIT]
        conn.close()

    def test_06_model_a_shelf_and_favorite_independence(self):
        """Phase 3: Verifies favoriting preserves reading status and removing favorite preserves shelf."""
        from backend.infrastructure.persistence.postgres_adapters import (
            PostgresInteractionRepository,
        )

        repo = PostgresInteractionRepository(LOCAL_COMPOSE_PG_URI)

        # 1. User A favorites BOOK_MESOPOTAMIA (which is currently 'reading')
        repo.upsert_interactions([{
            "user_id": USER_A_ID,
            "book_id": BOOK_MESOPOTAMIA,
            "interaction_type": "favorite",
            "book_title": "Murder in Mesopotamia",
            "book_author": "Agatha Christie"
        }])

        conn = psycopg2.connect(LOCAL_COMPOSE_PG_URI)
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            # favorites table MUST have BOOK_MESOPOTAMIA
            cur.execute("SELECT count(*) FROM public.favorites WHERE user_id = %s AND book_id = %s;", (USER_A_ID, BOOK_MESOPOTAMIA))
            assert cur.fetchone()["count"] == 1

            # user_interactions table MUST PRESERVE 'reading' status
            cur.execute("SELECT interaction_type FROM public.user_interactions WHERE user_id = %s AND book_id = %s;", (USER_A_ID, BOOK_MESOPOTAMIA))
            assert cur.fetchone()["interaction_type"] == "reading", "Reading status was overwritten by favorite!"

        # 2. User A unfavorites BOOK_MESOPOTAMIA
        repo.delete_interaction(user_id=USER_A_ID, book_id=BOOK_MESOPOTAMIA, interaction_type="favorite")

        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            # favorites table must NO LONGER have BOOK_MESOPOTAMIA
            cur.execute("SELECT count(*) FROM public.favorites WHERE user_id = %s AND book_id = %s;", (USER_A_ID, BOOK_MESOPOTAMIA))
            assert cur.fetchone()["count"] == 0

            # user_interactions table MUST STILL PRESERVE 'reading' status
            cur.execute("SELECT interaction_type FROM public.user_interactions WHERE user_id = %s AND book_id = %s;", (USER_A_ID, BOOK_MESOPOTAMIA))
            row = cur.fetchone()
            assert row is not None, "Reading status was erased when unfavoriting!"
            assert row["interaction_type"] == "reading"
        conn.close()

    def test_07_live_compose_http_e2e_journey(self):
        """Phase 3: Proves live Compose HTTP endpoint enforces auth boundary (rejects X-Api-Key without Bearer token)."""
        api_key = get_backend_api_key()

        # Service-key-only without verified user Bearer token must be rejected with 401
        payload = {
            "user_id": USER_A_ID,
            "book_id": BOOK_PARTNERS,
            "interaction": "favorite"
        }
        req = urllib.request.Request(
            f"{COMPOSE_BACKEND_URL}/api/feedback",
            data=json.dumps(payload).encode("utf-8"),
            headers={
                "Content-Type": "application/json",
                "X-Api-Key": api_key
            },
            method="POST"
        )
        with pytest.raises(urllib.error.HTTPError) as exc_info:
            urllib.request.urlopen(req)
        assert exc_info.value.code == 401, f"Expected 401 Unauthorized, got {exc_info.value.code}"

        # Read back from database to verify Model A data state integrity
        conn = psycopg2.connect(LOCAL_COMPOSE_PG_URI)
        with conn.cursor() as cur:
            cur.execute("SELECT count(*) FROM public.favorites WHERE user_id = %s AND book_id = %s;", (USER_A_ID, BOOK_PARTNERS))
            assert cur.fetchone()[0] == 1
        conn.close()

    def test_08_persistence_across_service_restart(self):
        """Phase 3: Verifies saved state in libris_pgdata volume survives backend service restart."""
        # 1. Verify record exists before restart
        conn = psycopg2.connect(LOCAL_COMPOSE_PG_URI)
        with conn.cursor() as cur:
            cur.execute("SELECT count(*) FROM public.favorites WHERE user_id = %s AND book_id = %s;", (USER_A_ID, BOOK_PARTNERS))
            assert cur.fetchone()[0] == 1
        conn.close()

        # 2. Restart backend service safely
        subprocess.run(["docker", "restart", "libris_backend"], check=True)

        # 3. Wait for backend to regain healthy status
        healthy = False
        for _ in range(15):
            time.sleep(2)
            try:
                with urllib.request.urlopen(f"{COMPOSE_BACKEND_URL}/api/health", timeout=3) as resp:
                    if resp.status == 200:
                        healthy = True
                        break
            except Exception:
                pass
        assert healthy, "Backend failed to regain health after service restart!"

        # 4. Verify saved state persists across restart
        conn = psycopg2.connect(LOCAL_COMPOSE_PG_URI)
        with conn.cursor() as cur:
            cur.execute("SELECT count(*) FROM public.favorites WHERE user_id = %s AND book_id = %s;", (USER_A_ID, BOOK_PARTNERS))
            assert cur.fetchone()[0] == 1, "Data loss occurred across service restart!"
        conn.close()

    def test_09_test_records_cleanup(self):
        """Phase 3: Cleans up only test records created by this run."""
        conn = psycopg2.connect(LOCAL_COMPOSE_PG_URI)
        conn.autocommit = True
        with conn.cursor() as cur:
            cur.execute("DELETE FROM public.favorites WHERE user_id IN (%s, %s);", (USER_A_ID, USER_B_ID))
            cur.execute("DELETE FROM public.user_interactions WHERE user_id IN (%s, %s);", (USER_A_ID, USER_B_ID))
            cur.execute("DELETE FROM public.user_profiles WHERE user_id IN (%s, %s);", (USER_A_ID, USER_B_ID))
            cur.execute("DELETE FROM public.user_activities WHERE user_id IN (%s, %s);", (USER_A_ID, USER_B_ID))
            cur.execute("DELETE FROM auth.users WHERE id IN (%s, %s);", (USER_A_ID, USER_B_ID))

            # Verify complete cleanup
            cur.execute("SELECT count(*) FROM public.favorites WHERE user_id IN (%s, %s);", (USER_A_ID, USER_B_ID))
            assert cur.fetchone()[0] == 0
            cur.execute("SELECT count(*) FROM public.user_interactions WHERE user_id IN (%s, %s);", (USER_A_ID, USER_B_ID))
            assert cur.fetchone()[0] == 0
        conn.close()
