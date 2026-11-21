from unittest.mock import MagicMock

import pytest
from backend.domain.ports import SemanticSearchUnavailable
from backend.infrastructure.persistence.supabase_adapters import SupabaseBookDataPort


def test_get_semantic_candidates_normal_contract():
    """Verify get_semantic_candidates passes expected parameters and maps return table."""
    mock_supabase = MagicMock()
    mock_rpc = MagicMock()
    mock_execute = MagicMock()

    mock_supabase.rpc.return_value = mock_rpc
    mock_rpc.execute.return_value = mock_execute
    mock_execute.data = [
        {"book_id": "9780001", "similarity": 0.88},
        {"book_id": "9780002", "similarity": 0.75},
    ]

    port = SupabaseBookDataPort(mock_supabase)
    result = port.get_semantic_candidates(["9780001"], limit=50)

    mock_supabase.rpc.assert_called_once_with(
        "match_book_embeddings",
        {
            "seed_book_ids": ["9780001"],
            "match_threshold": 0.0,
            "match_count": 50,
        },
    )
    assert result == {"9780001": 0.88, "9780002": 0.75}


def test_get_semantic_candidates_empty_seeds_noop():
    """Verify empty seeds returns empty dict without invoking database RPC."""
    mock_supabase = MagicMock()
    port = SupabaseBookDataPort(mock_supabase)

    assert port.get_semantic_candidates([]) == {}
    assert port.get_semantic_candidates(None) == {}
    mock_supabase.rpc.assert_not_called()


def test_get_semantic_candidates_rpc_failure_is_explicit():
    """A missing/failing match_book_embeddings RPC raises instead of posing as 'no similar books'."""
    mock_supabase = MagicMock()
    mock_supabase.rpc.side_effect = Exception("PGRST202: Could not find function match_book_embeddings")

    port = SupabaseBookDataPort(mock_supabase)
    with pytest.raises(SemanticSearchUnavailable, match="match_book_embeddings"):
        port.get_semantic_candidates(["9780001"])


def test_match_query_embeddings_normal_contract():
    """Verify match_query_embeddings invokes correct RPC and formats result."""
    mock_supabase = MagicMock()
    mock_rpc = MagicMock()
    mock_execute = MagicMock()

    mock_supabase.rpc.return_value = mock_rpc
    mock_rpc.execute.return_value = mock_execute
    mock_execute.data = [{"book_id": "9780003", "similarity": 0.92}]

    port = SupabaseBookDataPort(mock_supabase)
    query_vector = [0.1] * 3072
    result = port.match_query_embeddings(query_vector, limit=25)

    mock_supabase.rpc.assert_called_once_with(
        "match_query_embeddings",
        {
            "query_embedding": query_vector,
            "match_threshold": 0.0,
            "match_count": 25,
        },
    )
    assert result == {"9780003": 0.92}


def test_match_query_embeddings_rpc_failure_is_explicit():
    """An RPC error raises SemanticSearchUnavailable so RAG can fall back explicitly."""
    mock_supabase = MagicMock()
    mock_supabase.rpc.side_effect = Exception("Internal DB error")

    port = SupabaseBookDataPort(mock_supabase)
    with pytest.raises(SemanticSearchUnavailable, match="Internal DB error"):
        port.match_query_embeddings([0.0] * 10)


def test_match_query_embeddings_empty_result_is_not_an_error():
    """Zero matches is a valid answer and must stay distinguishable from a failure."""
    mock_supabase = MagicMock()
    mock_supabase.rpc.return_value.execute.return_value.data = []
    assert SupabaseBookDataPort(mock_supabase).match_query_embeddings([0.1] * 10) == {}


def test_missing_client_is_explicit():
    with pytest.raises(SemanticSearchUnavailable):
        SupabaseBookDataPort(None).match_query_embeddings([0.1] * 10)
