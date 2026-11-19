"""
Contract: embeddings are requested under one explicit, recorded *profile*.

- Defaults reproduce how the stored catalog vectors were produced (commit 23760c6): documents
  AND queries sent with taskType=RETRIEVAL_DOCUMENT, canonical_v1 text, 3072 dimensions.
- The full document profile is stored with each vector, so staleness covers model, dimension,
  document format and task type, not just the model name.
- Legacy rows (bare model name) are read as the profile that code actually used.
- Semantic queries are refused while the store holds vectors of another profile.
- The interactive query path never waits out a quota window.

Whether gemini-embedding-2 actually honours taskType is NOT verified here (no API access);
these tests pin the request contract, not the quality of the resulting vectors.
"""

from unittest.mock import MagicMock, patch

import pytest
from backend.domain.ports import SemanticSearchUnavailable
from backend.infrastructure.llm.gemini_rest import GeminiRestClient
from backend.services.embedding_service import EmbeddingService

DIM = 3072
LEGACY_PROFILE = "models/gemini-embedding-2;dim=3072;text=canonical_v1;task=RETRIEVAL_DOCUMENT"


def _service(monkeypatch, model="models/gemini-embedding-2", query_format=None, doc_task=None,
             dimension=DIM, port=None):
    monkeypatch.setenv("GEMINI_API_KEY", "test-key")
    monkeypatch.setenv("EMBEDDING_MODEL", model)
    monkeypatch.setenv("EMBEDDING_DIMENSION", str(dimension))
    for name, value in (("EMBEDDING_QUERY_FORMAT", query_format), ("EMBEDDING_DOCUMENT_TASK_TYPE", doc_task)):
        if value is None:
            monkeypatch.delenv(name, raising=False)
        else:
            monkeypatch.setenv(name, value)
    svc = EmbeddingService(book_data_port=port)
    svc._client = MagicMock()
    svc._client.embed.return_value = [0.0] * dimension
    return svc


def test_default_profile_matches_how_stored_vectors_were_produced(monkeypatch):
    svc = _service(monkeypatch)
    assert svc.document_profile() == LEGACY_PROFILE
    svc.generate_embedding("Title: Dune")
    assert svc._client.embed.call_args.kwargs["task_type"] == "RETRIEVAL_DOCUMENT"
    # The old RAG embedded queries with generate_embedding, so the default query request is identical.
    svc.embed_query("  desert   planet ")
    assert svc._client.embed.call_args.args[0] == "desert planet"
    assert svc._client.embed.call_args.kwargs["task_type"] == "RETRIEVAL_DOCUMENT"


@pytest.mark.parametrize("fmt, text, task", [
    ("raw", "desert planet", None),
    ("search_result", "task: search result | query: desert planet", None),
    ("retrieval_query", "desert planet", "RETRIEVAL_QUERY"),
])
def test_alternative_query_formats_are_opt_in(monkeypatch, fmt, text, task):
    svc = _service(monkeypatch, query_format=fmt)
    svc.embed_query("desert planet")
    assert svc._client.embed.call_args.args[0] == text
    assert svc._client.embed.call_args.kwargs["task_type"] == task
    # Query format never changes the document side (that would invalidate every stored vector).
    assert svc.document_profile() == LEGACY_PROFILE
    assert svc.describe()["query_format"] == fmt


def test_unknown_settings_fall_back_to_the_legacy_profile(monkeypatch):
    svc = _service(monkeypatch, query_format="nonsense", doc_task="WHATEVER")
    assert svc.describe()["query_format"] == "legacy"
    assert svc.document_profile() == LEGACY_PROFILE


def test_document_task_none_is_a_different_profile(monkeypatch):
    svc = _service(monkeypatch, doc_task="none")
    svc.generate_embedding("Title: Dune")
    assert svc._client.embed.call_args.kwargs["task_type"] is None
    assert svc.document_profile().endswith(";task=none")
    assert svc.document_profile() != LEGACY_PROFILE


def test_legacy_bare_model_names_map_to_the_legacy_profile():
    assert EmbeddingService.normalize_profile("models/gemini-embedding-2") == LEGACY_PROFILE
    assert EmbeddingService.normalize_profile(LEGACY_PROFILE) == LEGACY_PROFILE
    assert EmbeddingService.normalize_profile(None) == ""


@pytest.mark.parametrize("stored, stale", [
    ("models/gemini-embedding-2", False),     # legacy row, same effective profile
    (LEGACY_PROFILE, False),
    ("models/gemini-embedding-001", True),    # other model
    ("models/gemini-embedding-2;dim=768;text=canonical_v1;task=RETRIEVAL_DOCUMENT", True),  # other dimension
    ("models/gemini-embedding-2;dim=3072;text=canonical_v1;task=none", True),               # other task type
    ("models/gemini-embedding-2;dim=3072;text=canonical_v0;task=RETRIEVAL_DOCUMENT", True),  # other text format
])
def test_staleness_covers_the_whole_profile(monkeypatch, stored, stale):
    port = MagicMock()
    port.get_embedding_metadata.return_value = {"content_hash": "h", "model_version": stored}
    svc = _service(monkeypatch, port=port)
    assert svc.is_stale("b1", "h") is stale


def test_changing_the_document_task_makes_legacy_rows_stale(monkeypatch):
    port = MagicMock()
    port.get_embedding_metadata.return_value = {"content_hash": "h", "model_version": "models/gemini-embedding-2"}
    assert _service(monkeypatch, port=port, doc_task="none").is_stale("b1", "h") is True


def test_queries_are_refused_while_the_store_holds_another_profile(monkeypatch):
    port = MagicMock()
    port.find_other_embedding_profiles.return_value = ["models/gemini-embedding-001"]
    svc = _service(monkeypatch, port=port)
    with pytest.raises(SemanticSearchUnavailable, match="gemini-embedding-001"):
        svc.embed_query("desert planet")
    svc._client.embed.assert_not_called()  # no Gemini call is wasted on an unusable query
    accepted = port.find_other_embedding_profiles.call_args.args[0]
    assert set(accepted) == {LEGACY_PROFILE, "models/gemini-embedding-2"}


def test_compatible_store_allows_queries_and_check_is_cached(monkeypatch):
    port = MagicMock()
    port.find_other_embedding_profiles.return_value = []
    svc = _service(monkeypatch, port=port)
    assert svc.embed_query("a") is not None
    assert svc.embed_query("b") is not None
    assert port.find_other_embedding_profiles.call_count == 1


def test_store_recovers_after_migration_once_the_cache_expires(monkeypatch):
    port = MagicMock()
    port.find_other_embedding_profiles.side_effect = [["old-model"], []]
    monkeypatch.setenv("EMBEDDING_PROFILE_CHECK_TTL_SECONDS", "0")
    svc = _service(monkeypatch, port=port)
    with pytest.raises(SemanticSearchUnavailable):
        svc.embed_query("q")
    assert svc.embed_query("q") is not None


def test_unreadable_store_does_not_block_queries(monkeypatch):
    """If the profiles cannot be read, the vector query itself reports the real failure."""
    port = MagicMock()
    port.find_other_embedding_profiles.side_effect = RuntimeError("db down")
    assert _service(monkeypatch, port=port).embed_query("q") is not None


def test_query_embedding_dimension_is_validated(monkeypatch):
    svc = _service(monkeypatch)
    svc._client.embed.return_value = [0.0] * 768
    assert svc.embed_query("q") is None


@patch("backend.services.embedding_service.time.sleep")
def test_query_path_does_not_wait_on_quota(mock_sleep, monkeypatch):
    """A 429 inside a web request must fail fast instead of sleeping ~61 s."""
    svc = _service(monkeypatch)
    svc._client.embed.side_effect = Exception("Gemini embedContent failed (429): Quota exceeded")
    assert svc.embed_query("q") is None
    assert svc._client.embed.call_count == 1
    mock_sleep.assert_not_called()


@patch("backend.services.embedding_service.time.sleep")
def test_document_path_still_waits_on_quota(mock_sleep, monkeypatch):
    svc = _service(monkeypatch)
    svc._client.embed.side_effect = [Exception("429 Quota exceeded. retry in 3s"), [0.0] * DIM]
    assert svc.generate_embedding("Title: Dune") is not None
    mock_sleep.assert_called_once_with(4.0)


@pytest.mark.parametrize("task_type, expected", [(None, None), ("RETRIEVAL_QUERY", "RETRIEVAL_QUERY")])
def test_rest_client_only_sends_task_type_when_given(task_type, expected):
    session = MagicMock()
    session.post.return_value.status_code = 200
    session.post.return_value.json.return_value = {"embedding": {"values": [0.1]}}
    GeminiRestClient("k", session=session).embed("hi", "models/gemini-embedding-2", task_type=task_type)
    payload = session.post.call_args.kwargs["json"]
    assert payload.get("taskType") == expected
    assert ("taskType" in payload) == (expected is not None)
