"""
Real-data retrieval audit: production code paths against the REAL stored Gemini embeddings and,
where credentials allow, the live database and Gemini API. Complements run_retrieval_evaluation
(which is offline-only and k=5) with k=10 metrics, latency percentiles, empty-result rates and
recommendation-quality checks (diversity, duplicates, popularity bias, category consistency).

    python -m backend.scripts.run_real_retrieval_audit seeds [--pool]
        Seed -> item ("similar books" / personalised recommendations) on the exported embedding
        snapshot (evaluation/cache/book_embeddings.npz). No network. --pool appends unjudged
        top-10 candidates of every system to evaluation/data/judgments_seeds.csv (blank grade).

    python -m backend.scripts.run_real_retrieval_audit queries [--query-embeddings F.npz ...] [--pool]
        Query -> item. Always: production TF-IDF lexical search and the production RAG pipeline
        end to end (ProcessRagQueryUseCase.execute with the real EmbeddingService, the live
        Postgres vector port and the real LLM adapter, exactly as configured in .env). Semantic
        and hybrid systems need query embeddings exported by export_embedding_snapshot.py; without
        them they are reported as not executed, never estimated.

Results are merged into evaluation/reports/real_retrieval_audit.json (one key per section).
Nothing here writes to the database: the live port only runs SELECTs / vector RPCs.

Label provenance is carried into every result: grades labelled 'llm:*' with an empty reviewed_by
are provisional and NOT human-verified.
"""

from __future__ import annotations

import argparse
import json
import os
import statistics
import sys
import time
from collections import Counter
from typing import Callable, Dict, List, Optional

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from backend.evaluation.metrics import (  # noqa: E402
    graded_ndcg_at_k,
    graded_precision_at_k,
    graded_recall_at_k,
    judged_at_k,
    mean_reciprocal_rank,
)
from backend.evaluation.retrieval import (  # noqa: E402
    DATA_DIR,
    Catalog,
    EmbeddingIndex,
    judgment_provenance,
    load_judgments,
    load_topics,
    topic_split,
    write_pool,
)
from backend.utils.preprocess import _fold, normalize_isbn  # noqa: E402

BACKEND = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODEL_PATH = os.path.join(BACKEND, "saved_model", "tfidf.pkl")
CACHE = os.path.join(BACKEND, "evaluation", "cache")
REPORT = os.path.join(BACKEND, "evaluation", "reports", "real_retrieval_audit.json")
QUERY_JUDGMENTS = os.path.join(DATA_DIR, "judgments_queries.csv")
SEED_JUDGMENTS = os.path.join(DATA_DIR, "judgments_seeds.csv")
RRF_K = 60  # standard reciprocal-rank-fusion constant (Cormack et al. 2009); not tuned here
SEMANTIC_POOL = 100  # what match_*_embeddings is asked for in production


# ── helpers ──────────────────────────────────────────────────────────────────


def percentiles(xs: List[float]) -> Dict[str, Optional[float]]:
    if not xs:
        return {"p50": None, "p95": None, "p99": None, "mean": None, "n": 0}
    a = np.asarray(xs, dtype=float)
    return {"p50": round(float(np.percentile(a, 50)), 2), "p95": round(float(np.percentile(a, 95)), 2),
            "p99": round(float(np.percentile(a, 99)), 2), "mean": round(float(a.mean()), 2), "n": len(xs)}


def _mean(xs) -> Optional[float]:
    xs = [x for x in xs if x is not None]
    return round(statistics.fmean(xs), 4) if xs else None


def dedup_works(catalog: Catalog, isbns: List[str]) -> List[str]:
    seen, out = set(), []
    for i in isbns:
        w = catalog.work_of.get(normalize_isbn(i), f"unknown:{i}")
        if w not in seen:
            seen.add(w)
            out.append(normalize_isbn(i))
    return out


def rrf(rankings: List[List[str]], k: int = RRF_K) -> Dict[str, float]:
    out: Dict[str, float] = {}
    for ranking in rankings:
        for pos, item in enumerate(ranking, start=1):
            out[item] = out.get(item, 0.0) + 1.0 / (k + pos)
    return out


def ranked_from_scores(catalog: Catalog, scores: Dict[str, float], k: int, exclude_works=()) -> List[str]:
    excluded = set(exclude_works)
    seen, out = set(), []
    for isbn, _ in sorted(scores.items(), key=lambda kv: (-kv[1], kv[0])):
        w = catalog.work_of.get(isbn)
        if w is None or w in excluded or w in seen:
            continue
        seen.add(w)
        out.append(isbn)
        if len(out) >= k:
            break
    return out


def score_list(catalog: Catalog, ranked_isbns: List[str], grades: Dict[str, int], pop_pct: Dict[str, float],
               category_tokens: Callable[[str], set], seed_isbn: Optional[str] = None,
               targets: Optional[List[str]] = None) -> dict:
    """All per-topic metrics for one ranked list (raw, before any de-duplication)."""
    raw_works = catalog.works(ranked_isbns)
    row = {
        "returned": len(ranked_isbns), "empty": len(ranked_isbns) == 0,
        "duplicate_works_in_list": len(raw_works) - len(set(raw_works)),
        "p@5": graded_precision_at_k(raw_works, grades, 5), "p@10": graded_precision_at_k(raw_works, grades, 10),
        "ndcg@5": graded_ndcg_at_k(raw_works, grades, 5), "ndcg@10": graded_ndcg_at_k(raw_works, grades, 10),
        "mrr@10": mean_reciprocal_rank(raw_works, grades, 10),
        "pooled_recall@5": graded_recall_at_k(raw_works, grades, 5) if grades else None,
        "pooled_recall@10": graded_recall_at_k(raw_works, grades, 10) if grades else None,
        "judged@5": judged_at_k(raw_works, grades, 5) if ranked_isbns else None,
        "judged@10": judged_at_k(raw_works, grades, 10) if ranked_isbns else None,
        "popularity_percentile@10": _mean([pop_pct.get(i) for i in ranked_isbns[:10]]),
    }
    # Condensed list (Sakai 2007): drop unjudged items, then score. Robust to the pool bias that
    # penalises systems surfacing books no earlier system retrieved; it cannot reward them either.
    condensed = [w for w in raw_works if w in grades]
    row["condensed_ndcg@5"] = graded_ndcg_at_k(condensed, grades, 5) if grades else None
    row["condensed_p@5"] = graded_precision_at_k(condensed, grades, 5) if len(condensed) >= 5 else None
    authors = [catalog.work_of.get(i, "|").split("|")[-1] for i in ranked_isbns[:10]]
    row["distinct_authors@10"] = len(set(authors)) / float(len(authors)) if authors else None
    if targets:
        tw = {catalog.work_of[t]: 2 for t in targets}
        row["known_item_recall@5"] = graded_recall_at_k(raw_works, tw, 5)
        row["known_item_recall@10"] = graded_recall_at_k(raw_works, tw, 10)
    if seed_isbn:
        seed_work = catalog.work_of[seed_isbn]
        seed_author = seed_work.split("|")[-1]
        seed_cats = category_tokens(seed_isbn)
        top = ranked_isbns[:10]
        row["seed_edition_leak"] = sum(1 for w in raw_works if w == seed_work)
        row["same_author@10"] = _mean([1.0 if a == seed_author else 0.0 for a in authors])
        row["category_overlap@10"] = _mean([1.0 if (category_tokens(i) & seed_cats) else 0.0 for i in top]) \
            if seed_cats else None
    return row


def summarize(rows: List[dict]) -> dict:
    keys = sorted({k for r in rows for k in r if k not in ("topic", "lang", "category", "latency_ms", "status",
                                                           "retrieval_mode", "ranked", "source")})
    out = {}
    for k in keys:
        vals = [r[k] for r in rows if r.get(k) is not None and not isinstance(r.get(k), (list, str))]
        if not vals:
            out[k] = None
        elif isinstance(vals[0], bool):
            out[k + "_rate"] = round(sum(1 for v in vals if v) / float(len(vals)), 4)
        else:
            out[k] = _mean(vals)
    out["n"] = len(rows)
    out["latency_ms"] = percentiles([r["latency_ms"] for r in rows if r.get("latency_ms") is not None])
    return out


def grouped(rows: List[dict]) -> dict:
    groups: Dict[str, List[dict]] = {}
    for r in rows:
        for g in (f"lang={r.get('lang', 'en')}", f"category={r.get('category', 'seed')}", f"split={topic_split(r['topic'])}"):
            groups.setdefault(g, []).append(r)
    return {"overall": summarize(rows), "breakdown": {g: summarize(v) for g, v in sorted(groups.items())},
            "per_topic": rows}


def merge_report(section: str, payload: dict) -> None:
    report = {}
    if os.path.exists(REPORT):
        with open(REPORT, encoding="utf-8") as f:
            report = json.load(f)
    report[section] = payload
    report["label_provenance"] = {"queries": judgment_provenance(QUERY_JUDGMENTS),
                                  "seeds": judgment_provenance(SEED_JUDGMENTS)}
    os.makedirs(os.path.dirname(REPORT), exist_ok=True)
    with open(REPORT, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=1, ensure_ascii=False, default=str)


class Shared:
    def __init__(self, with_embeddings: bool = True):
        from backend.infrastructure.ml.recommender import BookRecommender

        self.cat = Catalog()
        self.prod = BookRecommender()
        if not self.prod.load_model(MODEL_PATH):
            raise SystemExit(f"could not load {MODEL_PATH}")
        path = os.path.join(CACHE, "book_embeddings.npz")
        self.emb = EmbeddingIndex.load(path) if with_embeddings and os.path.exists(path) else None
        pop = self.cat.popularity()
        order = pop.argsort().argsort() / float(max(1, len(pop) - 1))
        self.pop_pct = {isbn: float(order[i]) for i, isbn in enumerate(self.cat.isbns)}
        self._cats = {}

    def category_tokens(self, isbn: str) -> set:
        if isbn not in self._cats:
            row = self.cat.row_of.get(isbn)
            text = self.cat.df.at[row, "categories"] if row is not None else ""
            self._cats[isbn] = {t for t in _fold(text).split() if len(t) > 2 and t not in ("and", "the")}
        return self._cats[isbn]

    def semantic_top(self, vector, n: int = SEMANTIC_POOL) -> Dict[str, float]:
        """What match_query_embeddings / match_book_embeddings return: exact top-n {isbn: cosine}."""
        s = self.emb.scores(vector)
        top = np.argsort(-s)[:n]
        return {self.emb.isbns[i]: float(s[i]) for i in top}


# ── seed -> item ─────────────────────────────────────────────────────────────


def seed_systems(sh: Shared, seed: str, k: int = 10) -> Dict[str, tuple]:
    """{system: (ranked isbns, latency_ms)} for one seed book."""
    cat, prod = sh.cat, sh.prod
    seed_work = cat.work_of[seed]
    out: Dict[str, tuple] = {}

    def timed(name, fn):
        t0 = time.perf_counter()
        ranked = [normalize_isbn(x) for x in fn()]
        out[name] = (ranked, (time.perf_counter() - t0) * 1000)

    # 1. Production "similar books" (GetRecommendationsUseCase -> recommender.recommend, TF-IDF + pop + MMR)
    timed("production_similar", lambda: [r["isbn13"] for r in prod.recommend([seed], top_n=k, use_diversity=True)])
    # 2. Pure lexical: production TF-IDF item cosine
    row = prod.engine.find_index(seed)
    tf_scores = {}
    if row is not None:
        from sklearn.metrics.pairwise import cosine_similarity
        sims = cosine_similarity(prod.tfidf_matrix[row], prod.tfidf_matrix).ravel()
        tf_scores = {normalize_isbn(prod.df.iloc[i]["isbn13"]): float(sims[i]) for i in np.argsort(-sims)[:SEMANTIC_POOL + 10]}
    timed("lexical_tfidf", lambda: ranked_from_scores(cat, tf_scores, k, [seed_work]))
    if sh.emb is None or seed not in sh.emb.row_of:
        return out
    seed_vec = sh.emb.vectors[sh.emb.row_of[seed]]
    sem = sh.semantic_top(seed_vec)
    # 3. Pure semantic: exact cosine on the stored Gemini vectors
    timed("semantic_exact", lambda: ranked_from_scores(cat, sem, k, [seed_work]))
    # 4. Production personalised path IF match_book_embeddings existed (it is missing in the live DB):
    #    recommender.recommend with the RPC's top-100 as semantic_scores (0.3 tfidf + 0.5 sem + 0.2 pop, MMR).
    timed("production_personalized_with_rpc",
          lambda: [r["isbn13"] for r in prod.recommend(seed_titles=[seed], top_n=k, use_diversity=True,
                                                         semantic_scores=sem)])
    # 5. Hybrid: reciprocal-rank fusion of lexical and semantic rankings (no popularity, no MMR)
    lex_rank = ranked_from_scores(cat, tf_scores, SEMANTIC_POOL, [seed_work])
    sem_rank = ranked_from_scores(cat, sem, SEMANTIC_POOL, [seed_work])
    timed("hybrid_rrf", lambda: ranked_from_scores(cat, rrf([lex_rank, sem_rank]), k, [seed_work]))
    # 6. Experiment: production fusion with the semantic scores min-max rescaled over the candidate set,
    #    so the semantic term spans [0, 1] like TF-IDF and popularity instead of a ~0.1-wide band.
    lo, hi = min(sem.values()), max(sem.values())
    calibrated = {i: (s - lo) / (hi - lo) if hi > lo else 0.0 for i, s in sem.items()}
    timed("production_personalized_with_rpc_calibrated",
          lambda: [r["isbn13"] for r in prod.recommend(seed_titles=[seed], top_n=k, use_diversity=True,
                                                         semantic_scores=calibrated)])
    return out


def run_seeds(pool: bool) -> None:
    sh = Shared()
    seeds = load_topics("seeds.json")
    runs = {t["id"]: seed_systems(sh, t["seed_isbn"]) for t in seeds}
    if pool:
        pooled = {tid: sorted({i for ranked, _ in r.values() for i in ranked[:10]}) for tid, r in runs.items()}
        added = write_pool(SEED_JUDGMENTS, "seed", seeds, pooled, sh.cat)
        print(f"pooled {added} new seed candidates (blank grade = unjudged)")
        return
    judgments = load_judgments(SEED_JUDGMENTS)
    systems = sorted({n for r in runs.values() for n in r})
    result = {}
    for name in systems:
        rows = []
        for t in seeds:
            if name not in runs[t["id"]]:
                continue
            ranked, lat = runs[t["id"]][name]
            grades = judgments.get(t["id"], {})
            row = score_list(sh.cat, ranked, grades, sh.pop_pct, sh.category_tokens, seed_isbn=t["seed_isbn"])
            row.update(topic=t["id"], lang="en", category="seed", latency_ms=round(lat, 3), ranked=ranked)
            rows.append(row)
        result[name] = grouped(rows)
    catalog_pop = {"catalog_popularity_percentile_mean": 0.5}
    merge_report("seed_to_item", {
        "embedding_snapshot": sh.emb.model_version if sh.emb else None,
        "n_topics": len(seeds), "systems": result, "reference": catalog_pop,
        "notes": [
            "Latency is in-process ranking time on the snapshot (exact NumPy search), not database time; "
            "see the pgvector section for live RPC latency.",
            "pooled_recall@k uses every judged-relevant work for the topic as the relevant set; the pool "
            "is incomplete, so it is an upper bound on true recall.",
        ],
    })
    print_table(result)


# ── query -> item ────────────────────────────────────────────────────────────


class _IdentityEnrichment:
    """Google Books enrichment only adds cover/metadata fields; it does not reorder results."""

    def enrich(self, books):
        return books


def build_live_rag():
    """ProcessRagQueryUseCase wired like the container: real embedding service, live Postgres
    vector port, real LLM adapter. Enrichment is the identity (no Google Books calls)."""
    from backend.application.use_cases.ai_rag import ProcessRagQueryUseCase
    from backend.config import Config
    from backend.infrastructure.llm.adapters import GenericLlmAdapter
    from backend.infrastructure.ml.recommender import BookRecommender
    from backend.infrastructure.persistence.postgres_adapters import PostgresBookDataPort
    from backend.services.embedding_service import EmbeddingService

    db_url = os.environ.get("DATABASE_URL") or os.environ.get("SUPABASE_DB_URL")
    port = PostgresBookDataPort(db_url) if db_url else None
    rec = BookRecommender()
    rec.load_model(MODEL_PATH)
    emb = EmbeddingService(book_data_port=port)
    llm = GenericLlmAdapter(provider=Config.LLM_PROVIDER, api_key=Config.LLM_API_KEY,
                            model_name=Config.GEMINI_MODEL if Config.LLM_PROVIDER == "gemini" else None)
    uc = ProcessRagQueryUseCase(emb, port, None, rec, _IdentityEnrichment(), llm)
    return uc, emb, port


def gemini_health(emb) -> dict:
    """One embedding call to classify the provider state (never logs the key)."""
    if not emb.is_configured():
        return {"configured": False, "ok": False, "error": "no GEMINI_API_KEY / LLM_API_KEY"}
    try:
        v = emb._client.embed("health check", emb._model, task_type=None)
        return {"configured": True, "ok": len(v) == emb._dimension, "dimension": len(v)}
    except Exception as e:  # GeminiError carries the HTTP status and Google's message, not the key
        return {"configured": True, "ok": False, "error": str(e)[:200]}


def run_queries(query_embedding_files: List[str], pool: bool) -> None:
    sh = Shared()
    topics = load_topics("queries.json")
    judgments = load_judgments(QUERY_JUDGMENTS)
    qembs = {}
    for p in query_embedding_files:
        data = np.load(p, allow_pickle=False)
        fmt = str(data["format"]) if "format" in data else os.path.basename(p)
        qembs[fmt] = dict(zip(data["topic_ids"].tolist(), data["vectors"]))

    uc, emb_svc, port = build_live_rag()
    health = gemini_health(emb_svc)
    runs: Dict[str, Dict[str, dict]] = {}
    for t in topics:
        r: Dict[str, dict] = {}
        t0 = time.perf_counter()
        lex = [normalize_isbn(b["isbn13"]) for b in sh.prod.lexical_search(t["text"], limit=10)]
        r["lexical_tfidf"] = {"ranked": lex, "latency_ms": (time.perf_counter() - t0) * 1000}
        # Production end to end (anonymous user). Cache cleared so every topic exercises retrieval.
        uc._cache.clear()
        t0 = time.perf_counter()
        res = uc.execute(t["text"])
        lat = (time.perf_counter() - t0) * 1000
        m = res.get("metrics") or {}
        r["production_rag"] = {
            "ranked": [normalize_isbn(b["isbn13"]) for b in res.get("referenced_books") or []],
            "latency_ms": lat, "status": res.get("status"), "retrieval_mode": m.get("retrieval_mode"),
            "source": m.get("source"), "degraded": m.get("degraded"),
            "embedding_latency_ms": m.get("embedding_latency_ms"), "llm_latency_ms": m.get("llm_latency_ms"),
        }
        for fmt, vecs in qembs.items():
            if t["id"] not in vecs or sh.emb is None:
                continue
            qv = vecs[t["id"]]
            t0 = time.perf_counter()
            sem = sh.semantic_top(qv)
            r[f"semantic_exact[{fmt}]"] = {"ranked": ranked_from_scores(sh.cat, sem, 10),
                                           "latency_ms": (time.perf_counter() - t0) * 1000}
            t0 = time.perf_counter()
            hyb = ranked_from_scores(sh.cat, rrf([ranked_from_scores(sh.cat, sem, SEMANTIC_POOL),
                                                  dedup_works(sh.cat, [normalize_isbn(b["isbn13"]) for b in
                                                                       sh.prod.lexical_search(t["text"], limit=SEMANTIC_POOL)])]), 10)
            r[f"hybrid_rrf[{fmt}]"] = {"ranked": hyb, "latency_ms": (time.perf_counter() - t0) * 1000}
            t0 = time.perf_counter()
            recs = sh.prod.recommend(top_n=10, use_diversity=True, semantic_scores=sem)
            r[f"production_semantic_ranking[{fmt}]"] = {"ranked": [normalize_isbn(b["isbn13"]) for b in recs],
                                                        "latency_ms": (time.perf_counter() - t0) * 1000}
        runs[t["id"]] = r

    if pool:
        pooled = {tid: sorted({i for v in r.values() for i in v["ranked"][:10]}) for tid, r in runs.items()}
        print(f"pooled {write_pool(QUERY_JUDGMENTS, 'query', topics, pooled, sh.cat)} new query candidates")
        return

    result = {}
    for name in sorted({n for r in runs.values() for n in r}):
        rows = []
        for t in topics:
            v = runs[t["id"]].get(name)
            if v is None:
                continue
            row = score_list(sh.cat, v["ranked"], judgments.get(t["id"], {}), sh.pop_pct, sh.category_tokens,
                             targets=t.get("target_isbns") if t.get("category") == "known_item" else None)
            row.update(topic=t["id"], lang=t.get("lang", "en"), category=t.get("category"),
                       latency_ms=round(v["latency_ms"], 2), ranked=v["ranked"])
            for extra in ("status", "retrieval_mode", "source", "degraded", "embedding_latency_ms", "llm_latency_ms"):
                if extra in v:
                    row[extra] = v[extra]
            rows.append(row)
        g = grouped(rows)
        if name == "production_rag":
            g["status_counts"] = dict(Counter(r["status"] for r in rows))
            g["retrieval_mode_counts"] = dict(Counter(str(r.get("retrieval_mode")) for r in rows))
            g["status_by_lang"] = {lang: dict(Counter(r["status"] for r in rows if r["lang"] == lang))
                                   for lang in sorted({r["lang"] for r in rows})}
            g["embedding_latency_ms"] = percentiles([r["embedding_latency_ms"] for r in rows
                                                     if r.get("embedding_latency_ms") is not None])
        result[name] = g
    not_executed = []
    if not qembs:
        not_executed.append(
            "semantic_exact / hybrid_rrf / production_semantic_ranking: no query embeddings "
            f"(Gemini embedding API state: {health})")
    merge_report("query_to_item", {"gemini": health, "n_topics": len(topics), "systems": result,
                                   "not_executed": not_executed,
                                   "notes": ["production_rag returns at most 5 books (top_k=5), so its @10 "
                                             "metrics are computed on <=5 items."]})
    print(json.dumps(health))
    print_table(result)


def print_table(result: dict) -> None:
    cols = ["n", "empty_rate", "p@5", "ndcg@5", "condensed_ndcg@5", "ndcg@10", "mrr@10", "pooled_recall@10", "judged@5", "judged@10",
            "known_item_recall@5", "known_item_recall@10", "popularity_percentile@10", "category_overlap@10",
            "same_author@10", "distinct_authors@10", "duplicate_works_in_list", "seed_edition_leak"]
    print("| system | " + " | ".join(cols) + " | latency p50/p95/p99 |")
    for name, g in result.items():
        o = g["overall"]
        lat = o["latency_ms"]
        print(f"| {name} | " + " | ".join(str(o.get(c, "-")) for c in cols) + f" | {lat['p50']}/{lat['p95']}/{lat['p99']} |")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("seeds")
    s.add_argument("--pool", action="store_true")
    q = sub.add_parser("queries")
    q.add_argument("--query-embeddings", nargs="*", default=[])
    q.add_argument("--pool", action="store_true")
    args = ap.parse_args(argv)
    from dotenv import load_dotenv
    load_dotenv(os.path.join(os.path.dirname(BACKEND), ".env"), override=False)
    if args.cmd == "seeds":
        run_seeds(args.pool)
    else:
        run_queries(args.query_embeddings, args.pool)


if __name__ == "__main__":
    main()
