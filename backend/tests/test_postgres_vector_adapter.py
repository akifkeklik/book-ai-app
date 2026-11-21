"""
Integration: PostgresBookDataPort vector retrieval on a real pgvector server, using the
production migrations (03 table + halfvec HNSW index, 05/06 RPC functions) verbatim.

    LIBRIS_PGVECTOR_TEST_URL=postgresql://postgres:pw@localhost:55432/postgres \
        python -m pytest backend/tests/test_postgres_vector_adapter.py -m integration

The URL must allow CREATE DATABASE; each run creates and drops its own scratch databases.
pgvector >= 0.7 is required (halfvec), e.g. the pgvector/pgvector:pg16 image used by CI.
"""

import os
import uuid
from pathlib import Path

import numpy as np
import pytest

psycopg2 = pytest.importorskip("psycopg2")

from backend.domain.ports import SemanticSearchUnavailable  # noqa: E402
from backend.infrastructure.persistence.postgres_adapters import PostgresBookDataPort  # noqa: E402

pytestmark = pytest.mark.integration

ADMIN_URL = os.environ.get("LIBRIS_PGVECTOR_TEST_URL")
SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"
DIM = 3072


def _db_url(name: str) -> str:
    base, _, _ = ADMIN_URL.rpartition("/")
    return f"{base}/{name}"


@pytest.fixture
def scratch_db():
    if not ADMIN_URL:
        pytest.skip("LIBRIS_PGVECTOR_TEST_URL not set")
    name = f"libris_vec_{uuid.uuid4().hex[:8]}"
    admin = psycopg2.connect(ADMIN_URL)
    admin.autocommit = True
    admin.cursor().execute(f"CREATE DATABASE {name}")
    conns = []
    try:
        yield _db_url(name), conns
    finally:
        for c in conns:
            c.close()
        admin.cursor().execute(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")
        admin.close()


def _apply_vector_schema(url, conns):
    conn = psycopg2.connect(url)
    conn.autocommit = True
    conns.append(conn)
    cur = conn.cursor()
    cur.execute("CREATE EXTENSION IF NOT EXISTS vector")
    cur.execute("CREATE TABLE public.books (isbn13 TEXT PRIMARY KEY)")
    for name in ("03_phase3_embeddings.sql", "05_phase3_performance.sql", "06_phase2_rag.sql"):
        cur.execute((SCRIPTS / name).read_text(encoding="utf-8"))
    return conn


def _vectors(n, seed=3):
    """Unit vectors sharing a common direction, like real text embeddings (pairwise cosine > 0;
    the RPCs drop similarity <= 0, so independent random vectors would lose ~half the rows)."""
    rng = np.random.default_rng(seed)
    v = rng.standard_normal((n, DIM)).astype(np.float32) + 0.25
    return v / np.linalg.norm(v, axis=1, keepdims=True)


def test_query_retrieval_matches_exact_cosine(scratch_db):
    url, conns = scratch_db
    conn = _apply_vector_schema(url, conns)
    vecs = _vectors(40)
    ids = [f"97800000{i:05d}" for i in range(len(vecs))]
    conn.cursor().executemany("INSERT INTO public.books VALUES (%s)", [(i,) for i in ids])
    port = PostgresBookDataPort(url)
    for i, v in zip(ids, vecs):
        port.upsert_embedding(i, v.tolist(), content_hash=f"h{i}", model_version="models/gemini-embedding-2")

    query = vecs[7] + 0.3 * vecs[21]
    got = port.match_query_embeddings(query.tolist(), limit=10)

    exact = np.argsort(-(vecs @ (query / np.linalg.norm(query))))[:10]
    assert list(got) == [ids[j] for j in exact]            # same order as brute force
    assert got[ids[7]] == pytest.approx(float(vecs[7] @ query / np.linalg.norm(query)), abs=2e-3)  # halfvec precision


def test_seed_retrieval_excludes_seeds_and_metadata_round_trips(scratch_db):
    url, conns = scratch_db
    conn = _apply_vector_schema(url, conns)
    vecs = _vectors(12)
    ids = [f"97800000{i:05d}" for i in range(len(vecs))]
    conn.cursor().executemany("INSERT INTO public.books VALUES (%s)", [(i,) for i in ids])
    port = PostgresBookDataPort(url)
    for i, v in zip(ids, vecs):
        port.upsert_embedding(i, v.tolist(), content_hash="old", model_version="m1")
    port.upsert_embedding(ids[0], vecs[0].tolist(), content_hash="new", model_version="m2")

    assert port.get_embedding_metadata(ids[0]) == {"content_hash": "new", "model_version": "m2"}
    assert port.get_embedding_metadata("9789999999999") is None

    similar = port.get_semantic_candidates([ids[0], ids[1]], limit=5)
    assert len(similar) == 5 and ids[0] not in similar and ids[1] not in similar
    assert port.get_semantic_candidates([], limit=5) == {}


def test_missing_vector_schema_is_explicit(scratch_db):
    """Without migrations 03/06 the adapter must raise, not report 'no similar books'."""
    url, _ = scratch_db
    port = PostgresBookDataPort(url)
    with pytest.raises(SemanticSearchUnavailable, match="migrations"):
        port.match_query_embeddings([0.1] * DIM, limit=5)
    with pytest.raises(SemanticSearchUnavailable):
        port.get_semantic_candidates(["9780000000001"], limit=5)


# ── Transaction handling and statement timeout (audit L3) ─────────────────────

def test_injected_transactional_connection_commits_and_recovers_after_errors(scratch_db):
    """A caller-supplied connection in psycopg2's default (non-autocommit) mode."""
    url, conns = scratch_db
    admin = _apply_vector_schema(url, conns)
    ids = ["9780000000901", "9780000000902"]
    admin.cursor().executemany("INSERT INTO public.books VALUES (%s)", [(i,) for i in ids])
    injected = psycopg2.connect(url)
    conns.append(injected)
    assert injected.autocommit is False
    port = PostgresBookDataPort(injected)

    port.upsert_embedding(ids[0], _vectors(1)[0].tolist(), content_hash="h", model_version="p1")
    other = admin.cursor()
    other.execute("SELECT count(*) FROM public.book_embeddings")
    assert other.fetchone()[0] == 1  # committed, visible to another session

    with pytest.raises(psycopg2.Error):  # wrong dimension -> the statement fails
        port.upsert_embedding(ids[1], [0.1, 0.2], content_hash="h", model_version="p1")
    # Without a rollback every later statement would fail with "current transaction is aborted".
    assert port.get_embedding_metadata(ids[0]) == {"content_hash": "h", "model_version": "p1"}
    assert port.match_query_embeddings(_vectors(1)[0].tolist(), limit=5)
    assert injected.get_transaction_status() == psycopg2.extensions.TRANSACTION_STATUS_IDLE


def test_vector_query_timeout_is_enforced_and_not_leaked(scratch_db, monkeypatch):
    from backend.infrastructure.persistence import postgres_adapters

    url, conns = scratch_db
    _apply_vector_schema(url, conns)
    monkeypatch.setattr(postgres_adapters, "VECTOR_QUERY_TIMEOUT_MS", 100)
    for conn_factory in (lambda: url, lambda: psycopg2.connect(url)):  # autocommit URI and injected
        target = conn_factory()
        if not isinstance(target, str):
            conns.append(target)
        port = PostgresBookDataPort(target)
        with pytest.raises(SemanticSearchUnavailable, match="exceeded"):
            port._vector_query("SELECT '1'::text, 1.0::float8 FROM pg_sleep(1)", ())
        conn = port._get_connection()
        if isinstance(target, str):
            conns.append(conn)
        cur = conn.cursor()
        cur.execute("SHOW statement_timeout")
        assert cur.fetchone()[0] == "0"  # SET LOCAL did not outlive the vector query
        if not conn.autocommit:
            conn.rollback()  # end the read-only transaction SHOW opened
        assert port._vector_query("SELECT '1'::text, 0.5::float8", ()) == {"1": 0.5}


def test_embedding_profile_lookup_on_real_rows(scratch_db):
    url, conns = scratch_db
    conn = _apply_vector_schema(url, conns)
    ids = ["9780000000911", "9780000000912", "9780000000913"]
    conn.cursor().executemany("INSERT INTO public.books VALUES (%s)", [(i,) for i in ids])
    port = PostgresBookDataPort(url)
    vec = _vectors(1)[0].tolist()
    port.upsert_embedding(ids[0], vec, content_hash="h", model_version="models/gemini-embedding-2")
    port.upsert_embedding(ids[1], vec, content_hash="h", model_version="new;dim=3072;text=canonical_v1;task=none")
    port.upsert_embedding(ids[2], vec, content_hash="h", model_version="models/gemini-embedding-001")
    others = port.find_other_embedding_profiles(
        ["models/gemini-embedding-2;dim=3072;text=canonical_v1;task=RETRIEVAL_DOCUMENT", "models/gemini-embedding-2"])
    assert others == ["models/gemini-embedding-001", "new;dim=3072;text=canonical_v1;task=none"]
