"""
Libris Sprint 21 - Reproducible Performance & Latency Benchmark Runner.
Measures deterministic local routing, RAG query cache, authorization context isolation,
and simulated provider failure modes using monotonic timing (time.perf_counter).
"""

import json
import os
import statistics
import sys
import time
from pathlib import Path
from typing import Any, Callable, Dict, List
from unittest.mock import MagicMock

import pandas as pd

# Ensure repository root is in sys.path when executed directly
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from backend.application.use_cases.ai_rag import ProcessRagQueryUseCase
from backend.domain.ports import (
    BookDataPort,
    EmbeddingPort,
    EnrichmentPort,
    LlmPort,
    RecommenderPort,
)


class ControllableBenchmarkClock:
    def __init__(self, start_time: float = 100000.0):
        self._time = start_time

    def time(self) -> float:
        return self._time

    def advance(self, delta: float):
        self._time += delta


def measure_execution(
    fn: Callable[[], Any],
    iterations: int = 15,
    warmup: int = 3,
) -> Dict[str, Any]:
    # Warmup runs (not included in statistics)
    for _ in range(warmup):
        fn()

    latencies_ms: List[float] = []
    last_res = None
    for _ in range(iterations):
        t0 = time.perf_counter()
        last_res = fn()
        t1 = time.perf_counter()
        latencies_ms.append((t1 - t0) * 1000.0)

    sorted_lats = sorted(latencies_ms)
    p95_idx = int(0.95 * len(sorted_lats))
    p95 = sorted_lats[min(p95_idx, len(sorted_lats) - 1)]

    return {
        "samples": iterations,
        "median_ms": round(statistics.median(latencies_ms), 3),
        "mean_ms": round(statistics.mean(latencies_ms), 3),
        "p95_ms": round(p95, 3),
        "min_ms": round(min(latencies_ms), 3),
        "max_ms": round(max(latencies_ms), 3),
        "last_result": last_res,
    }


def main():
    print("=" * 70)
    print("LIBRIS SPRINT 21: REPRODUCIBLE BENCHMARK RUNNER")
    print("=" * 70)
    print("Monotonic timer: time.perf_counter()")
    print(f"Timer resolution: {time.get_clock_info('perf_counter').resolution * 1e9:.2f} ns")
    print("-" * 70)

    # 1. Load real catalog data for deterministic accuracy
    data_path = Path(__file__).parent.parent / "data" / "books.csv"
    if not data_path.exists():
        raise FileNotFoundError(f"Catalog data missing at {data_path}")

    df = pd.read_csv(data_path)
    print(f"Loaded {len(df):,} catalog titles for realistic execution.")

    # 2. Setup mock ports for reproducible, cost-free benchmark
    mock_recommender = MagicMock(spec=RecommenderPort)
    mock_recommender.df = df
    mock_recommender.recommend.return_value = [
        {"isbn13": "9780451524935", "title": "1984", "authors": "George Orwell", "average_rating": 4.17}
    ]

    mock_emb = MagicMock(spec=EmbeddingPort)
    mock_emb.generate_embedding.return_value = [0.05] * 768

    mock_data_port = MagicMock(spec=BookDataPort)
    mock_data_port.match_query_embeddings.return_value = {"9780451524935": 0.95}

    mock_enrichment = MagicMock(spec=EnrichmentPort)
    mock_enrichment.enrich.side_effect = lambda b: b

    mock_llm = MagicMock(spec=LlmPort)
    mock_llm.generate_response.return_value = json.dumps({
        "answer": "Distopik edebiyatın başyapıtı olan 1984, totaliter rejimin gözetim toplumunu anlatır.",
        "explanations": {"9780451524935": "Distopya türünün temel taşıdır."},
    })

    clock = ControllableBenchmarkClock(start_time=1000.0)

    use_case = ProcessRagQueryUseCase(
        embedding_port=mock_emb,
        book_data_port=mock_data_port,
        interaction_repo=None,
        recommender=mock_recommender,
        enrichment_service=mock_enrichment,
        llm_port=mock_llm,
        time_provider=clock.time,
    )

    benchmark_cases = []

    # Case 1: Deterministic Clock Query
    c1 = measure_execution(lambda: use_case.execute("Bugün günlerden ne, saat kaç?"), iterations=30)
    benchmark_cases.append({
        "id": "CASE-01",
        "name": "Deterministic Clock Query",
        "query": "Bugün günlerden ne, saat kaç?",
        "environment": "Local Deterministic",
        "cache_state": "N/A (Bypassed)",
        "external_calls": False,
        "status": c1["last_result"]["status"],
        "metrics": {k: c1[k] for k in ["samples", "median_ms", "p95_ms", "min_ms", "max_ms"]},
    })

    # Case 2: Exact Catalog Existence Lookup
    use_case._cache.clear()
    c2 = measure_execution(lambda: use_case.execute("1984 kitabı var mı?"), iterations=30)
    benchmark_cases.append({
        "id": "CASE-02",
        "name": "Exact Catalog Existence Lookup",
        "query": "1984 kitabı var mı?",
        "environment": "Local Catalog Word-Boundary Match",
        "cache_state": "Cold -> Warm Cached",
        "external_calls": False,
        "status": c2["last_result"]["status"],
        "metrics": {k: c2[k] for k in ["samples", "median_ms", "p95_ms", "min_ms", "max_ms"]},
    })

    # Case 3: Author Lookup
    use_case._cache.clear()
    c3 = measure_execution(lambda: use_case.execute("1984'ün yazarı kim?"), iterations=30)
    benchmark_cases.append({
        "id": "CASE-03",
        "name": "Author Inquiry Lookup",
        "query": "1984'ün yazarı kim?",
        "environment": "Local Catalog Deterministic",
        "cache_state": "Cold -> Warm Cached",
        "external_calls": False,
        "status": c3["last_result"]["status"],
        "metrics": {k: c3[k] for k in ["samples", "median_ms", "p95_ms", "min_ms", "max_ms"]},
    })

    # Case 4: Rating Lookup
    use_case._cache.clear()
    c4 = measure_execution(lambda: use_case.execute("1984 kitabı kaç puan almış?"), iterations=30)
    benchmark_cases.append({
        "id": "CASE-04",
        "name": "Rating Inquiry Lookup",
        "query": "1984 kitabı kaç puan almış?",
        "environment": "Local Catalog Deterministic",
        "cache_state": "Cold -> Warm Cached",
        "external_calls": False,
        "status": c4["last_result"]["status"],
        "metrics": {k: c4[k] for k in ["samples", "median_ms", "p95_ms", "min_ms", "max_ms"]},
    })

    # Case 5: Semantic Recommendation Cold Cache
    use_case._cache.clear()
    mock_emb.reset_mock()
    mock_llm.reset_mock()
    # Single cold execution measurement
    t0 = time.perf_counter()
    res_cold = use_case.execute("bana distopik bir kitap öner", user_id="user_bench")
    t1 = time.perf_counter()
    cold_ms = (t1 - t0) * 1000.0
    benchmark_cases.append({
        "id": "CASE-05",
        "name": "Semantic Recommendation (Cold Cache)",
        "query": "bana distopik bir kitap öner",
        "environment": "Local Recommender + Simulated Provider",
        "cache_state": "Cold (Miss)",
        "external_calls": True,
        "status": res_cold["status"],
        "metrics": {"samples": 1, "median_ms": round(cold_ms, 3), "p95_ms": round(cold_ms, 3), "min_ms": round(cold_ms, 3), "max_ms": round(cold_ms, 3)},
    })

    # Case 6: Identical Semantic Recommendation Warm Cache
    c6 = measure_execution(lambda: use_case.execute("bana distopik bir kitap öner", user_id="user_bench"), iterations=50)
    benchmark_cases.append({
        "id": "CASE-06",
        "name": "Identical Semantic (Warm Cache Hit)",
        "query": "bana distopik bir kitap öner",
        "environment": "In-Memory LRU Cache",
        "cache_state": "Warm (Hit)",
        "external_calls": False,
        "status": c6["last_result"]["status"],
        "metrics": {k: c6[k] for k in ["samples", "median_ms", "p95_ms", "min_ms", "max_ms"]},
    })

    # Case 7: Semantically Equivalent But Nonidentical Query
    t0 = time.perf_counter()
    res_equiv = use_case.execute("distopik edebiyat önerisi istiyorum", user_id="user_bench")
    t1 = time.perf_counter()
    equiv_ms = (t1 - t0) * 1000.0
    benchmark_cases.append({
        "id": "CASE-07",
        "name": "Semantically Equivalent Query (Nonidentical)",
        "query": "distopik edebiyat önerisi istiyorum",
        "environment": "Local Recommender + Simulated Provider",
        "cache_state": "Cold (Distinct Key)",
        "external_calls": True,
        "status": res_equiv["status"],
        "metrics": {"samples": 1, "median_ms": round(equiv_ms, 3), "p95_ms": round(equiv_ms, 3), "min_ms": round(equiv_ms, 3), "max_ms": round(equiv_ms, 3)},
    })

    # Case 8: Different User Context (User Isolation)
    t0 = time.perf_counter()
    res_user_b = use_case.execute("bana distopik bir kitap öner", user_id="user_distinct_B")
    t1 = time.perf_counter()
    user_b_ms = (t1 - t0) * 1000.0
    benchmark_cases.append({
        "id": "CASE-08",
        "name": "Different User Context (User Isolation)",
        "query": "bana distopik bir kitap öner [User B]",
        "environment": "Local Recommender + Simulated Provider",
        "cache_state": "Cold (User Key Isolation)",
        "external_calls": True,
        "status": res_user_b["status"],
        "metrics": {"samples": 1, "median_ms": round(user_b_ms, 3), "p95_ms": round(user_b_ms, 3), "min_ms": round(user_b_ms, 3), "max_ms": round(user_b_ms, 3)},
    })

    # Case 9: Cache Expiry (600s TTL verification)
    clock.advance(601.0)
    t0 = time.perf_counter()
    res_expired = use_case.execute("bana distopik bir kitap öner", user_id="user_bench")
    t1 = time.perf_counter()
    expired_ms = (t1 - t0) * 1000.0
    benchmark_cases.append({
        "id": "CASE-09",
        "name": "Cache Expiry (Clock Advanced 601s)",
        "query": "bana distopik bir kitap öner [Post-TTL]",
        "environment": "In-Memory LRU Cache + Execution",
        "cache_state": "Expired -> Recomputed",
        "external_calls": True,
        "status": res_expired["status"],
        "metrics": {"samples": 1, "median_ms": round(expired_ms, 3), "p95_ms": round(expired_ms, 3), "min_ms": round(expired_ms, 3), "max_ms": round(expired_ms, 3)},
    })

    # Case 10: Provider Timeout / Failure Mode
    mock_llm.generate_response.side_effect = TimeoutError("Simulated Upstream Provider 504")
    use_case._cache.clear()
    t0 = time.perf_counter()
    res_timeout = use_case.execute("karanlık bilim kurgu kitapları", user_id="user_bench")
    t1 = time.perf_counter()
    timeout_ms = (t1 - t0) * 1000.0
    benchmark_cases.append({
        "id": "CASE-10",
        "name": "Provider Timeout / Quota Failure",
        "query": "karanlık bilim kurgu kitapları [Timeout]",
        "environment": "Deterministic Fallback Mode",
        "cache_state": "Uncached (Transient Failure)",
        "external_calls": True,
        "status": res_timeout["status"],
        "metrics": {"samples": 1, "median_ms": round(timeout_ms, 3), "p95_ms": round(timeout_ms, 3), "min_ms": round(timeout_ms, 3), "max_ms": round(timeout_ms, 3)},
    })

    # Print Table
    print(f"\n{'ID':<9} | {'Case Name':<38} | {'Median (ms)':<11} | {'p95 (ms)':<9} | {'Min (ms)':<9} | {'Max (ms)':<9} | {'Status':<12} | {'Cache'}")
    print("-" * 125)
    for c in benchmark_cases:
        m = c["metrics"]
        print(f"{c['id']:<9} | {c['name']:<38} | {m['median_ms']:<11.3f} | {m['p95_ms']:<9.3f} | {m['min_ms']:<9.3f} | {m['max_ms']:<9.3f} | {c['status']:<12} | {c['cache_state']}")

    # Save to report artifact
    report_data = {
        "benchmark_date": time.strftime("%Y-%m-%d %H:%M:%S"),
        "timing_mechanism": "time.perf_counter (Monotonic)",
        "timer_resolution_ns": round(time.get_clock_info("perf_counter").resolution * 1e9, 2),
        "catalog_size": len(df),
        "results": benchmark_cases,
    }

    report_dir = Path(__file__).parent.parent / "evaluation" / "reports"
    report_dir.mkdir(parents=True, exist_ok=True)
    report_path = report_dir / "benchmark_sprint21_report.json"
    with open(report_path, "w", encoding="utf-8") as f:
        json.dump(report_data, f, indent=2, ensure_ascii=False)

    print(f"\nStructured benchmark evidence persisted to: {report_path}")


if __name__ == "__main__":
    main()
