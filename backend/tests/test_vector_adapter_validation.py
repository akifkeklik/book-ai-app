"""
Unit regression tests for the persistence adapters (audit L1, L2, L3).

L1  malformed vector RPC payloads raise SemanticSearchUnavailable (never a fake "no matches").
L2  Supabase paging follows the rows actually returned, so a server cap below 1000 cannot
    truncate the catalog.
L3  Postgres adapters commit/roll back injected (non-autocommit) connections, and vector queries
    run in their own transaction under SET LOCAL statement_timeout.
The same Postgres behaviour is exercised against a real server in test_postgres_vector_adapter.py.
"""

import math
from unittest.mock import MagicMock

import psycopg2
import pytest
from backend.domain.ports import SemanticSearchUnavailable
from backend.infrastructure.persistence import postgres_adapters
from backend.infrastructure.persistence.postgres_adapters import (
    PostgresBookDataPort,
    PostgresInteractionRepository,
)
from backend.infrastructure.persistence.supabase_adapters import SupabaseBookDataPort
from backend.infrastructure.persistence.vector_rows import parse_similarity_rows

# ── L1 ────────────────────────────────────────────────────────────────────────

@pytest.mark.parametrize("payload", [
    {"book_id": "1", "similarity": 0.5},            # a dict, not a list of rows
    "oops",
    [{"book_id": "1"}],                              # missing similarity
    [{"similarity": 0.4}],                           # missing book_id
    [{"book_id": "1", "similarity": "high"}],        # non-numeric
    [{"book_id": "1", "similarity": None}],
    [{"book_id": "1", "similarity": math.nan}],
    [{"book_id": "", "similarity": 0.3}],
    [("1", 0.2, "extra")],
    42,
])
def test_malformed_vector_rows_raise(payload):
    with pytest.raises(SemanticSearchUnavailable):
        parse_similarity_rows(payload, "test")


def test_well_formed_vector_rows_parse():
    assert parse_similarity_rows(None, "t") == {}
    assert parse_similarity_rows([], "t") == {}
    assert parse_similarity_rows([{"book_id": 978, "similarity": "0.5"}, ("x", 1)], "t") == {"978": 0.5, "x": 1.0}


@pytest.mark.parametrize("data", [{"unexpected": "shape"}, [{"book_id": "1"}], [{"book_id": "1", "similarity": "n/a"}]])
def test_supabase_rpc_rejects_malformed_payloads(data):
    client = MagicMock()
    client.rpc.return_value.execute.return_value = MagicMock(data=data)
    port = SupabaseBookDataPort(client)
    with pytest.raises(SemanticSearchUnavailable):
        port.match_query_embeddings([0.1], limit=5)
    with pytest.raises(SemanticSearchUnavailable):
        port.get_semantic_candidates(["1"], limit=5)


def test_supabase_rpc_empty_result_is_not_an_error():
    client = MagicMock()
    client.rpc.return_value.execute.return_value = MagicMock(data=None)
    assert SupabaseBookDataPort(client).match_query_embeddings([0.1], limit=5) == {}


# ── L2 ────────────────────────────────────────────────────────────────────────

def _paged_client(pages):
    client = MagicMock()
    query = client.table.return_value.select.return_value.order.return_value
    query.range.return_value.execute.side_effect = [MagicMock(data=p) for p in pages]
    return client, query


def test_supabase_paging_survives_a_server_cap_below_the_page_size():
    """max-rows=500 on the server: the old loop stopped after the first short page (500 books)."""
    pages = [[{"isbn13": f"a{i}"} for i in range(500)], [{"isbn13": f"b{i}"} for i in range(500)],
             [{"isbn13": "c"}], []]
    client, query = _paged_client(pages)
    books = SupabaseBookDataPort(client).get_all_books_raw()
    assert len(books) == 1001
    assert [c.args for c in query.range.call_args_list] == [(0, 999), (500, 1499), (1000, 1999), (1001, 2000)]


def test_supabase_isbn_paging_is_ordered_and_complete():
    pages = [[{"isbn13": str(i)} for i in range(300)], [{"isbn13": "x"}, {"isbn13": None}], []]
    client, query = _paged_client(pages)
    isbns = SupabaseBookDataPort(client).get_all_isbns()
    assert len(isbns) == 301
    client.table.return_value.select.return_value.order.assert_called_with("isbn13")


def test_supabase_paging_errors_never_return_a_partial_catalog():
    client = MagicMock()
    query = client.table.return_value.select.return_value.order.return_value
    query.range.return_value.execute.side_effect = [MagicMock(data=[{"isbn13": "1"}] * 400), Exception("timeout")]
    assert SupabaseBookDataPort(client).get_all_books_raw() == []


def test_supabase_paging_rejects_a_non_list_page():
    client, _ = _paged_client([{"error": "boom"}])
    assert SupabaseBookDataPort(client).get_all_books_raw() == []


def test_supabase_profile_lookup_filters_out_accepted_values():
    client = MagicMock()
    q = client.table.return_value.select.return_value
    q.neq.return_value.neq.return_value.limit.return_value.execute.return_value = MagicMock(
        data=[{"model_version": "old"}, {"model_version": "old"}, {"model_version": None}])
    assert SupabaseBookDataPort(client).find_other_embedding_profiles(["p1", "p2"], limit=3) == ["old"]
    q.neq.assert_called_once_with("model_version", "p1")


# ── L3 ────────────────────────────────────────────────────────────────────────

class FakeCursor:
    def __init__(self, conn):
        self.conn = conn

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False

    def execute(self, sql, params=None):
        self.conn.statements.append(sql.strip().split()[0].upper() if sql.strip() else sql)
        self.conn.executed.append((sql, params))
        if self.conn.fail_on and self.conn.fail_on in sql:
            raise self.conn.error

    def fetchall(self):
        return self.conn.rows

    def fetchone(self):
        return self.conn.rows[0] if self.conn.rows else None

    def close(self):
        pass


class FakeConn:
    def __init__(self, autocommit=False, rows=None, fail_on=None, error=None):
        self.autocommit = autocommit
        self.closed = False
        self.rows = rows or []
        self.fail_on, self.error = fail_on, error or psycopg2.Error("boom")
        self.commits = self.rollbacks = 0
        self.statements, self.executed = [], []

    def cursor(self, cursor_factory=None):
        return FakeCursor(self)

    def commit(self):
        self.commits += 1

    def rollback(self):
        self.rollbacks += 1


def test_injected_connection_commits_successful_writes():
    conn = FakeConn(autocommit=False)
    PostgresBookDataPort(conn).upsert_embedding("b1", [0.1], "h", "p")
    assert conn.commits == 1 and conn.rollbacks == 0


def test_injected_connection_rolls_back_after_errors():
    conn = FakeConn(autocommit=False, fail_on="INSERT INTO public.books", error=psycopg2.IntegrityError("dup"))
    port = PostgresBookDataPort(conn)
    assert port.add_book({"isbn13": "1", "title": "t"}) is False
    assert conn.rollbacks == 1 and conn.commits == 0
    conn.fail_on = None
    conn.rows = [("9780000000001",)]
    assert port.get_all_isbns() == ["9780000000001"]  # the connection is usable again
    assert conn.commits == 1


def test_injected_connection_rollback_covers_interaction_repository():
    conn = FakeConn(autocommit=False, fail_on="INSERT INTO public.user_activities")
    repo = PostgresInteractionRepository(conn)
    with pytest.raises(psycopg2.Error):
        repo.track_activity({"user_id": "u", "action": "view"})
    assert conn.rollbacks == 1


def test_autocommit_connection_is_not_committed_or_rolled_back():
    conn = FakeConn(autocommit=True, rows=[("1",)])
    assert PostgresBookDataPort(conn).get_all_isbns() == ["1"]
    assert conn.commits == 0 and conn.rollbacks == 0


@pytest.mark.parametrize("autocommit", [True, False])
def test_vector_query_runs_in_a_transaction_with_a_statement_timeout(autocommit, monkeypatch):
    monkeypatch.setattr(postgres_adapters, "VECTOR_QUERY_TIMEOUT_MS", 1234)
    conn = FakeConn(autocommit=autocommit, rows=[("9780000000001", 0.9)])
    assert PostgresBookDataPort(conn).match_query_embeddings([0.1, 0.2], limit=3) == {"9780000000001": 0.9}
    set_local = [p for sql, p in conn.executed if "statement_timeout" in sql]
    assert set_local == [("1234ms",)]
    if autocommit:
        assert conn.statements[0] == "BEGIN" and conn.statements[-1] == "COMMIT"
    else:
        assert conn.commits == 1


@pytest.mark.parametrize("autocommit", [True, False])
def test_vector_query_timeout_is_semantic_unavailable_and_rolled_back(autocommit):
    conn = FakeConn(autocommit=autocommit, fail_on="match_query_embeddings",
                    error=psycopg2.errors.QueryCanceled("canceling statement due to statement timeout"))
    with pytest.raises(SemanticSearchUnavailable, match="exceeded"):
        PostgresBookDataPort(conn).match_query_embeddings([0.1], limit=3)
    if autocommit:
        assert conn.statements[-1] == "ROLLBACK"
    else:
        assert conn.rollbacks == 1 and conn.commits == 0


def test_vector_query_malformed_rows_are_semantic_unavailable():
    conn = FakeConn(autocommit=True, rows=[("9780000000001", None)])
    with pytest.raises(SemanticSearchUnavailable):
        PostgresBookDataPort(conn).match_query_embeddings([0.1], limit=3)


def test_postgres_profile_lookup():
    conn = FakeConn(autocommit=True, rows=[("old-model",), (None,)])
    assert PostgresBookDataPort(conn).find_other_embedding_profiles(["p"], limit=2) == ["old-model"]
    sql, params = conn.executed[-1]
    assert "NOT (model_version = ANY(%s))" in sql and params == (["p"], 2)


# ── hnsw.ef_search caps HNSW results (live audit: LIMIT 100 returned 40 rows at ef_search=40) ──


@pytest.mark.parametrize("limit,expected", [(100, "200"), (3, "40"), (5000, "1000")])
def test_vector_query_sets_transaction_local_ef_search_for_the_limit(limit, expected):
    conn = FakeConn(autocommit=True, rows=[("9780000000001", 0.9)])
    PostgresBookDataPort(conn).match_query_embeddings([0.1, 0.2], limit=limit)
    ef = [(sql, p) for sql, p in conn.executed if "hnsw.ef_search" in sql]
    assert len(ef) == 1
    sql, params = ef[0]
    # set_config(..., is_local => true) is SET LOCAL: it ends with the transaction, so no
    # server or session setting is changed.
    assert "set_config('hnsw.ef_search', %s, true)" in sql and params == (expected,)
    assert conn.statements[0] == "BEGIN" and conn.statements[-1] == "COMMIT"


def test_seed_candidate_query_also_sets_ef_search():
    conn = FakeConn(autocommit=True, rows=[("9780000000002", 0.8)])
    PostgresBookDataPort(conn).get_semantic_candidates(["9780000000001"], limit=100)
    assert [p for sql, p in conn.executed if "hnsw.ef_search" in sql] == [("200",)]


def test_ef_search_is_set_before_the_vector_query():
    conn = FakeConn(autocommit=True, rows=[])
    PostgresBookDataPort(conn).match_query_embeddings([0.1], limit=100)
    order = [sql for sql, _ in conn.executed]
    ef_at = next(i for i, s in enumerate(order) if "hnsw.ef_search" in s)
    rpc_at = next(i for i, s in enumerate(order) if "match_query_embeddings" in s)
    assert ef_at < rpc_at
