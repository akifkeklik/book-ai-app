import threading
from unittest.mock import MagicMock

import pytest
from backend.application.use_cases.ai_rag import (
    ProcessRagQueryUseCase,
    _RagQueryCache,
)
from backend.domain.ports import (
    BookDataPort,
    EmbeddingPort,
    EnrichmentPort,
    LlmPort,
    RecommenderPort,
    UserInteractionRepository,
)


class ControllableClock:
    def __init__(self, start_time: float = 1000.0):
        self.current_time = start_time

    def time(self) -> float:
        return self.current_time

    def advance(self, seconds: float):
        self.current_time += seconds


@pytest.mark.unit
def test_cache_ttl_and_expiry_with_controllable_clock():
    clock = ControllableClock(start_time=100.0)
    cache = _RagQueryCache(capacity=256, ttl_seconds=600.0, time_provider=clock.time)

    cache.set("key1", {"answer": "result1", "status": "success"})

    # Usable before expiry
    assert cache.get("key1") == {"answer": "result1", "status": "success"}

    # At 599 seconds, still usable
    clock.advance(599.0)
    assert cache.get("key1") is not None
    assert cache.get("key1")["answer"] == "result1"

    # At 600.1 seconds, expired and evicted
    clock.advance(1.1)
    assert cache.get("key1") is None


@pytest.mark.unit
def test_cache_lru_capacity_and_eviction():
    cache = _RagQueryCache(capacity=3, ttl_seconds=600.0)

    cache.set("k1", {"val": 1})
    cache.set("k2", {"val": 2})
    cache.set("k3", {"val": 3})

    # Access k1 so k2 becomes least recently used
    assert cache.get("k1")["val"] == 1

    # Insert k4, should evict k2 (LRU)
    cache.set("k4", {"val": 4})

    assert cache.get("k2") is None
    assert cache.get("k1")["val"] == 1
    assert cache.get("k3")["val"] == 3
    assert cache.get("k4")["val"] == 4


@pytest.mark.unit
def test_cache_hit_returns_deepcopy_no_mutation_leak():
    cache = _RagQueryCache(capacity=10, ttl_seconds=600.0)
    original = {
        "answer": "Grounded answer",
        "referenced_books": [{"isbn13": "123", "title": "Original Title"}],
        "metrics": {"total_rag_latency_ms": 10.0},
    }
    cache.set("k1", original)

    hit1 = cache.get("k1")
    assert hit1 is not None

    # Mutate the returned object
    hit1["referenced_books"][0]["title"] = "MUTATED TITLE"
    hit1["metrics"]["total_rag_latency_ms"] = 9999.0
    hit1["new_key"] = "leak"

    # Second hit must be pristine and unaffected
    hit2 = cache.get("k1")
    assert hit2["referenced_books"][0]["title"] == "Original Title"
    assert hit2["metrics"]["total_rag_latency_ms"] == 10.0
    assert "new_key" not in hit2


@pytest.mark.unit
def test_cache_multithreaded_concurrency():
    cache = _RagQueryCache(capacity=50, ttl_seconds=600.0)
    errors = []

    def worker(worker_id: int):
        try:
            for i in range(100):
                key = f"key_{i % 30}"
                cache.set(key, {"worker": worker_id, "i": i})
                val = cache.get(key)
                if val is not None:
                    assert "worker" in val
        except Exception as e:
            errors.append(e)

    threads = [threading.Thread(target=worker, args=(t,)) for t in range(8)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()

    assert len(errors) == 0


@pytest.mark.unit
def test_cache_key_user_isolation_and_anon_safety():
    mock_emb = MagicMock(spec=EmbeddingPort)
    mock_emb.generate_embedding.return_value = [0.1]
    mock_data = MagicMock(spec=BookDataPort)
    mock_data.match_query_embeddings.return_value = {"123": 0.9}
    mock_rec = MagicMock(spec=RecommenderPort)
    mock_rec.recommend.return_value = [{"isbn13": "123", "title": "B1"}]
    mock_enr = MagicMock(spec=EnrichmentPort)
    mock_enr.enrich.side_effect = lambda b: b
    mock_llm = MagicMock(spec=LlmPort)
    mock_llm.generate_response.return_value = "Response A"

    mock_repo = MagicMock(spec=UserInteractionRepository)
    mock_repo.get_user_interactions.side_effect = lambda uid: [
        {"book_id": "pref_book", "interaction_type": "like"}
    ] if uid == "user_A" else []

    use_case = ProcessRagQueryUseCase(
        embedding_port=mock_emb,
        book_data_port=mock_data,
        interaction_repo=mock_repo,
        recommender=mock_rec,
        enrichment_service=mock_enr,
        llm_port=mock_llm,
    )

    # 1. User A executes query
    res_a = use_case.execute("tell me about fantasy themes", user_id="user_A")
    assert res_a["status"] == "success"

    # 2. User B executes identical query — must NOT get User A's cached entry
    mock_llm.generate_response.return_value = "Response B"
    res_b = use_case.execute("tell me about fantasy themes", user_id="user_B")
    assert res_b["status"] == "success"
    # Proves LLM was called again for User B due to cache key separation
    assert mock_llm.generate_response.call_count == 2

    # 3. User with user_id="anon" vs unauthenticated user_id=None must NOT collide
    mock_llm.generate_response.return_value = "Response Anon User"
    res_user_anon = use_case.execute("tell me about fantasy themes", user_id="anon")
    assert res_user_anon["status"] == "success"

    mock_llm.generate_response.return_value = "Response Unauth Anon"
    res_unauth = use_case.execute("tell me about fantasy themes", user_id=None)
    assert res_unauth["status"] == "success"

    assert mock_llm.generate_response.call_count == 4


@pytest.mark.unit
def test_transient_recoverable_failures_are_not_cached():
    mock_emb = MagicMock(spec=EmbeddingPort)
    mock_emb.generate_embedding.return_value = [0.1]
    mock_data = MagicMock(spec=BookDataPort)
    mock_data.match_query_embeddings.return_value = {"123": 0.9}
    mock_rec = MagicMock(spec=RecommenderPort)
    mock_rec.recommend.return_value = [{"isbn13": "123", "title": "B1"}]
    mock_enr = MagicMock(spec=EnrichmentPort)
    mock_enr.enrich.side_effect = lambda b: b
    mock_llm = MagicMock(spec=LlmPort)

    # First attempt: LLM throws timeout error -> returns llm_fallback
    mock_llm.generate_response.side_effect = TimeoutError("Provider 504")

    use_case = ProcessRagQueryUseCase(
        embedding_port=mock_emb,
        book_data_port=mock_data,
        interaction_repo=None,
        recommender=mock_rec,
        enrichment_service=mock_enr,
        llm_port=mock_llm,
    )

    res1 = use_case.execute("science fiction books")
    assert res1["status"] == "llm_fallback"

    # Second attempt: LLM has recovered -> MUST NOT serve cached fallback!
    mock_llm.generate_response.side_effect = None
    mock_llm.generate_response.return_value = "Recovered personalized answer"

    res2 = use_case.execute("science fiction books")
    assert res2["status"] == "success"
    assert res2["answer"] == "Recovered personalized answer"
    assert mock_llm.generate_response.call_count == 2


@pytest.mark.unit
def test_cache_hit_telemetry_and_fresh_latency():
    mock_emb = MagicMock(spec=EmbeddingPort)
    mock_emb.generate_embedding.return_value = [0.1]
    mock_data = MagicMock(spec=BookDataPort)
    mock_data.match_query_embeddings.return_value = {"123": 0.9}
    mock_rec = MagicMock(spec=RecommenderPort)
    mock_rec.recommend.return_value = [{"isbn13": "123", "title": "B1"}]
    mock_enr = MagicMock(spec=EnrichmentPort)
    mock_enr.enrich.side_effect = lambda b: b
    mock_llm = MagicMock(spec=LlmPort)
    mock_llm.generate_response.return_value = "Original Answer"

    use_case = ProcessRagQueryUseCase(
        embedding_port=mock_emb,
        book_data_port=mock_data,
        interaction_repo=None,
        recommender=mock_rec,
        enrichment_service=mock_enr,
        llm_port=mock_llm,
    )

    # Cold run
    res_cold = use_case.execute("historical fiction")
    assert res_cold["metrics"]["source"] == "rag_llm"
    assert "llm_latency_ms" in res_cold["metrics"]

    # Warm run
    res_warm = use_case.execute("historical fiction")
    assert res_warm["metrics"]["source"] == "cache_hit"
    # Telemetry does NOT falsely claim an LLM call occurred
    assert "llm_latency_ms" not in res_warm["metrics"]
    assert res_warm["metrics"]["total_rag_latency_ms"] >= 0.0
