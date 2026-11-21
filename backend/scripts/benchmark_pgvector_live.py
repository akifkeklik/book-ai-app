"""
READ-ONLY benchmark of the live pgvector retrieval path with the REAL stored Gemini embeddings.

    python -m backend.scripts.benchmark_pgvector_live [--probes 60]

Uses SUPABASE_DB_URL / DATABASE_URL from .env. Every statement runs inside a READ ONLY
transaction; planner/HNSW settings are changed only with SET LOCAL (that transaction only), so
production configuration is never modified. Probe vectors are stored book vectors (a seed-book
lookup, like match_book_embeddings) and the mean of two random books' vectors (a query-like point
that is not itself a row). They are NOT user-query embeddings; Gemini was unavailable.

Measures: index definitions and settings, EXPLAIN (ANALYZE, BUFFERS) plans of the RPC's inner
query, rows returned for LIMIT 100 under several hnsw.ef_search / iterative-scan settings, recall
against exact search, and the latency of the production RPC call (PostgresBookDataPort).
Writes evaluation/reports/pgvector_live_benchmark.json.
"""

import argparse
import json
import os
import sys
import time

import numpy as np
import psycopg2

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

BACKEND = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(BACKEND, "evaluation", "reports", "pgvector_live_benchmark.json")

INNER = ("SELECT be.book_id, 1 - ((be.embedding::halfvec(3072)) <=> (%s::vector::halfvec(3072))) AS similarity "
         "FROM public.book_embeddings be ORDER BY (be.embedding::halfvec(3072)) <=> (%s::vector::halfvec(3072)) "
         "LIMIT %s")


def lit(v) -> str:
    return "[" + ",".join(f"{x:.7f}" for x in v) + "]"


def pct(xs):
    a = np.asarray(xs, float)
    return {"p50": round(float(np.percentile(a, 50)), 2), "p95": round(float(np.percentile(a, 95)), 2),
            "p99": round(float(np.percentile(a, 99)), 2), "mean": round(float(a.mean()), 2), "n": len(xs)}


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--probes", type=int, default=60)
    args = ap.parse_args(argv)
    from dotenv import load_dotenv
    load_dotenv(os.path.join(os.path.dirname(BACKEND), ".env"), override=False)
    url = os.environ.get("DATABASE_URL") or os.environ.get("SUPABASE_DB_URL")
    if not url:
        sys.exit("DATABASE_URL or SUPABASE_DB_URL is required")
    conn = psycopg2.connect(url, connect_timeout=15)
    conn.set_session(readonly=True, autocommit=False)
    cur = conn.cursor()

    def one(sql, params=()):
        cur.execute(sql, params)
        return cur.fetchall()

    out = {"read_only": True}
    out["server"] = {
        "postgres": one("SHOW server_version")[0][0],
        "pgvector": one("SELECT extversion FROM pg_extension WHERE extname='vector'")[0][0],
        "rows": one("SELECT count(*) FROM public.book_embeddings")[0][0],
        "hnsw.ef_search": one("SHOW hnsw.ef_search")[0][0],
        "hnsw.iterative_scan": one("SELECT current_setting('hnsw.iterative_scan', true)")[0][0],
        "work_mem": one("SHOW work_mem")[0][0],
        "indexes": [r[0] for r in one("SELECT indexdef FROM pg_indexes WHERE tablename='book_embeddings'")],
        "index_size": one("SELECT pg_size_pretty(pg_relation_size('public.book_embeddings_embedding_idx'))")[0][0],
        "functions": sorted(r[0] for r in one(
            "SELECT p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace "
            "WHERE n.nspname='public' AND p.proname LIKE 'match%%'")),
    }
    conn.rollback()

    # Load all stored vectors once (read-only) for exact ground truth.
    rows = one("SELECT book_id, embedding::text FROM public.book_embeddings ORDER BY book_id")
    conn.rollback()
    ids = [r[0] for r in rows]
    vecs = np.array([json.loads(r[1]) for r in rows], dtype=np.float32)
    vecs /= np.maximum(np.linalg.norm(vecs, axis=1, keepdims=True), 1e-12)

    rng = np.random.default_rng(20261120)
    picks = rng.choice(len(ids), size=args.probes, replace=False)
    pairs = rng.choice(len(ids), size=(args.probes, 2), replace=False)
    probes = [("book_vector", vecs[i]) for i in picks] + \
             [("two_book_mean", (vecs[a] + vecs[b]) / np.linalg.norm(vecs[a] + vecs[b])) for a, b in pairs]

    def run(q, limit, settings):
        pass  # session is READ ONLY (set_session); psycopg2 opens the transaction
        for s in settings:
            cur.execute(s)
        t0 = time.perf_counter()
        cur.execute(INNER, (lit(q), lit(q), limit))
        got = [r[0] for r in cur.fetchall()]
        ms = (time.perf_counter() - t0) * 1000
        conn.rollback()
        return got, ms

    # EXPLAIN plans (one probe), default settings and forced exact.
    q0 = probes[0][1]
    plans = {}
    for name, settings in (("default", []), ("exact_no_index", ["SET LOCAL enable_indexscan = off"])):
        pass  # session is READ ONLY (set_session); psycopg2 opens the transaction
        for s in settings:
            cur.execute(s)
        cur.execute("EXPLAIN (ANALYZE, BUFFERS) " + INNER, (lit(q0), lit(q0), 100))
        plans[name] = [r[0] for r in cur.fetchall()]
        conn.rollback()
    out["explain_analyze"] = plans

    configs = {
        "default (ef_search=40)": [],
        "ef_search=100": ["SET LOCAL hnsw.ef_search = 100"],
        "ef_search=200": ["SET LOCAL hnsw.ef_search = 200"],
        "ef_search=40 + iterative_scan=relaxed_order": ["SET LOCAL hnsw.iterative_scan = relaxed_order"],
        "exact (index disabled)": ["SET LOCAL enable_indexscan = off"],
    }
    exact_cache = {}
    results = {}
    for cname, settings in configs.items():
        counts, lat, r5, r10, r100 = [], [], [], [], []
        for kind, q in probes:
            got, ms = run(q, 100, settings)
            key = id(q)
            if key not in exact_cache:
                exact_cache[key] = [ids[j] for j in np.argsort(-(vecs @ q))[:100]]
            exact = exact_cache[key]
            counts.append(len(got))
            lat.append(ms)
            r5.append(len(set(got[:5]) & set(exact[:5])) / 5.0)
            r10.append(len(set(got[:10]) & set(exact[:10])) / 10.0)
            r100.append(len(set(got) & set(exact)) / 100.0)
        results[cname] = {
            "requested": 100, "rows_returned_mean": round(float(np.mean(counts)), 2),
            "rows_returned_min": int(np.min(counts)), "rows_returned_max": int(np.max(counts)),
            "recall@5": round(float(np.mean(r5)), 4), "recall@10": round(float(np.mean(r10)), 4),
            "recall@100_of_requested": round(float(np.mean(r100)), 4), "latency_ms": pct(lat),
        }
        print(cname, json.dumps(results[cname]))
    out["limit_100"] = results

    # Production RPC, as RAG calls it (function + statement timeout), with default settings.
    from backend.infrastructure.persistence.postgres_adapters import PostgresBookDataPort

    port = PostgresBookDataPort(url)
    lat, counts = [], []
    for _, q in probes:
        t0 = time.perf_counter()
        res = port.match_query_embeddings(q.tolist(), limit=100)
        lat.append((time.perf_counter() - t0) * 1000)
        counts.append(len(res))
    out["production_rpc_match_query_embeddings"] = {
        "requested": 100, "rows_returned_mean": round(float(np.mean(counts)), 2),
        "rows_returned_min": int(np.min(counts)), "latency_ms": pct(lat),
        "note": "end-to-end through PostgresBookDataPort (pooled connection, vector literal of 3072 floats).",
    }
    try:
        port.get_semantic_candidates([ids[0]], limit=100)
        out["production_rpc_match_book_embeddings"] = {"available": True}
    except Exception as e:
        out["production_rpc_match_book_embeddings"] = {"available": False, "error": str(e)[:200]}
    print(json.dumps({k: out[k] for k in ("production_rpc_match_query_embeddings",
                                          "production_rpc_match_book_embeddings")}, indent=1))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=1)


if __name__ == "__main__":
    main()
