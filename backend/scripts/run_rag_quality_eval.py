"""
Live RAG quality evaluation for Turkish and English: retrieval accuracy, answer grounding,
latency, API errors and token usage of the production pipeline, exactly as configured in .env.

    python -m backend.scripts.run_rag_quality_eval run [--limit N] [--pause SECONDS]
        LIVE (Gemini + Supabase, read-only). For each query in data/rag_eval_tr_en.json:
          * production ProcessRagQueryUseCase.execute, cold (empty query cache) then warm (repeat);
          * the semantic stage it used (query embedding -> match_query_embeddings RPC), captured
            by wrapping the real objects, plus an exact cosine top-10 over the exported snapshot
            (evaluation/cache/book_embeddings.npz) when present;
          * every HTTP call to Gemini (status, latency, retries, usageMetadata tokens);
          * the exact prompt Gemini received, and deterministic grounding checks on the answer.
        Also runs the adversarial set (data/rag_eval_adversarial.json).
        Writes reports/rag_quality_eval.{json,md} and appends unseen (intent, book) pairs to
        data/rag_eval_judgments.csv for human review (existing human grades are kept).

    python -m backend.scripts.run_rag_quality_eval report [--category CAT ...]
        OFFLINE. Recomputes every metric from the saved run and the judgments CSV. Intents with
        human grades are scored on those grades and reported as human-verified. Also writes one
        row per query to reports/rag_quality_eval_queries.csv. With --category, scores only those
        categories and writes reports/rag_quality_eval.<categories>.{json,md,csv} instead, so the
        full report is never overwritten by a partial one.

    Dataset: data/rag_eval_tr_en.json (44 queries) plus data/rag_eval_expansion.json (built by
    backend/scripts/build_rag_eval_expansion.py). `run --dataset base` keeps the original 44;
    `run --category` limits a live run to some categories (fewer API calls).

Never runs in CI (it needs live credentials and costs API calls). Nothing is written to the
database. Production code is not modified: instrumentation wraps live objects in this process.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import os
import re
import statistics
import sys
import time
from collections import defaultdict
from typing import Dict, List, Optional

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from backend.evaluation.metrics import (  # noqa: E402
    graded_ndcg_at_k,
    graded_precision_at_k,
    mean_reciprocal_rank,
)
from backend.evaluation.retrieval import Catalog  # noqa: E402
from backend.utils.preprocess import normalize_isbn  # noqa: E402

EVAL = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "evaluation")
DATASET = os.path.join(EVAL, "data", "rag_eval_tr_en.json")
ADVERSARIAL = os.path.join(EVAL, "data", "rag_eval_adversarial.json")
JUDGMENTS = os.path.join(EVAL, "data", "rag_eval_judgments.csv")
SNAPSHOT = os.path.join(EVAL, "cache", "book_embeddings.npz")
QUERY_VECTORS = os.path.join(EVAL, "cache", "rag_eval_query_embeddings.npz")
REPORT_JSON = os.path.join(EVAL, "reports", "rag_quality_eval.json")
REPORT_MD = os.path.join(EVAL, "reports", "rag_quality_eval.md")
REPORT_CSV = os.path.join(EVAL, "reports", "rag_quality_eval_queries.csv")
EXPANSION = os.path.join(EVAL, "data", "rag_eval_expansion.json")

# Category of the original 44 queries, derived from their `type`; expansion queries carry their own.
TYPE_TO_CATEGORY = {"title": "exact_title", "author": "author", "genre": "genre", "topic": "topic",
                    "description": "semantic_description", "similar": "similar", "ambiguous": "ambiguous"}
SCORED_TIERS = ("rule_derived", "proposed", "automatic_candidate", "human_verified")


def load_dataset(include_expansion: bool = True, categories: Optional[List[str]] = None) -> dict:
    """The evaluation set: the original queries plus the expansion, normalised to one schema.

    Missing fields of the original queries are derived in memory (the files are not rewritten):
    category from `type`, difficulty "unrated", expected_behavior from the label tier."""
    base = json.load(open(DATASET, encoding="utf-8"))
    queries = []
    for q in base["queries"]:
        q = dict(q)
        q.setdefault("category", TYPE_TO_CATEGORY.get(q["type"], q["type"]))
        q.setdefault("difficulty", "unrated")
        q.setdefault("expected_behavior", "open_judgment" if q["label_tier"] == "open" else "retrieve_relevant")
        q.setdefault("dataset", "base")
        queries.append(q)
    versions = {"base": base.get("dataset_version", "tr-en-v1")}
    if include_expansion and os.path.exists(EXPANSION):
        exp = json.load(open(EXPANSION, encoding="utf-8"))
        versions["expansion"] = exp.get("dataset_version")
        known = {q["id"] for q in queries}
        for q in exp["queries"]:
            if q["id"] in known:
                raise ValueError(f"duplicate query id {q['id']} in {EXPANSION}")
            queries.append({**q, "dataset": "expansion"})
    if categories:
        unknown = set(categories) - {q["category"] for q in queries}
        if unknown:
            raise ValueError(f"unknown categories: {sorted(unknown)}")
        queries = [q for q in queries if q["category"] in categories]
    return {**base, "queries": queries, "dataset_versions": versions}


def _git_revision() -> dict:
    import subprocess
    root = os.path.dirname(os.path.dirname(EVAL))
    try:
        sha = subprocess.run(["git", "rev-parse", "HEAD"], cwd=root, capture_output=True, text=True,
                             timeout=10).stdout.strip() or None
        dirty = bool(subprocess.run(["git", "status", "--porcelain"], cwd=root, capture_output=True,
                                    text=True, timeout=10).stdout.strip())
    except (OSError, subprocess.SubprocessError):
        return {"git_sha": None, "git_dirty": None}
    return {"git_sha": sha, "git_dirty": dirty}
JUDGMENT_FIELDS = ["intent", "isbn", "title", "authors", "retrieved_by", "in_proposed_set", "label_tier",
                   "human_grade", "reviewed_by", "notes"]
ISBN_RE = re.compile(r"(?<!\d)97[89]\d{10}(?!\d)")


# ── Instrumentation ─────────────────────────────────────────────────────────

class Recorder:
    """Collects every Gemini HTTP attempt and the pipeline-stage captures for one query."""

    def __init__(self):
        self.reset()

    def reset(self):
        self.http: List[dict] = []
        self.embeds: List[dict] = []
        self.rpcs: List[dict] = []
        self.llm: List[dict] = []


def instrument(container, rec: Recorder) -> None:
    def wrap_session(client, kind):
        session = client._session
        orig = session.post

        def post(url, *args, **kwargs):
            t0 = time.perf_counter()
            try:
                resp = orig(url, *args, **kwargs)
            except Exception as exc:  # timeouts / connection errors
                rec.http.append({"kind": kind, "status": None, "error": type(exc).__name__,
                                 "ms": round((time.perf_counter() - t0) * 1000, 1)})
                raise
            entry = {"kind": kind, "status": resp.status_code, "ms": round((time.perf_counter() - t0) * 1000, 1)}
            try:
                body = resp.json()
                if isinstance(body, dict):
                    entry["usage"] = body.get("usageMetadata")
                    entry["model_version"] = body.get("modelVersion")
            except ValueError:
                pass
            rec.http.append(entry)
            return resp

        session.post = post

    llm = container.llm_port
    if getattr(llm, "_gemini", None) is not None:
        wrap_session(llm._gemini, "generate")
    es = container.embedding_service
    if getattr(es, "_client", None) is not None:
        wrap_session(es._client, "embed")

    orig_embed = es.embed_query

    def embed_query(query):
        t0 = time.perf_counter()
        vec = orig_embed(query)
        rec.embeds.append({"ms": round((time.perf_counter() - t0) * 1000, 1), "vector": vec})
        return vec

    es.embed_query = embed_query

    port = container.book_data_port
    if port is not None:
        orig_rpc = port.match_query_embeddings

        def match_query_embeddings(embedding, limit=100):
            t0 = time.perf_counter()
            hits = orig_rpc(embedding, limit=limit)
            rec.rpcs.append({"ms": round((time.perf_counter() - t0) * 1000, 1), "limit": limit, "hits": dict(hits or {})})
            return hits

        port.match_query_embeddings = match_query_embeddings

    orig_gen = llm.generate_response

    def generate_response(system_prompt, user_prompt):
        t0 = time.perf_counter()
        out = orig_gen(system_prompt, user_prompt)
        rec.llm.append({"ms": round((time.perf_counter() - t0) * 1000, 1), "user_prompt": user_prompt,
                        "raw": out})
        return out

    llm.generate_response = generate_response


# ── Retrieval metrics (work level: editions of one book count once) ────────

RETRIEVAL_METRIC_KEYS = ["hit@5", "recall@5", "recall@10", "precision@5", "precision@10",
                         "mrr@5", "mrr@10", "ndcg@5", "ndcg@10"]


def retrieval_metrics(ranked_isbns: List[str], grades: Dict[str, int], catalog: Catalog,
                      alias: Optional[Dict[str, str]] = None, list_size: int = 10) -> dict:
    """Work-level metrics at k = 5 and 10 (definitions in evaluation/README.md).

    ``list_size`` is how many results the system can return at most. Metrics at a k beyond it are
    None, not a number: production answers with 5 books, so its "@10" would only restate @5 with
    a larger denominator (it used to report R@10 below R@5).
    """
    works = [(alias or {}).get(w, w) for w in catalog.works(ranked_isbns)]
    relevant = {w for w, g in grades.items() if g >= 1}
    out = {"n_returned": len(ranked_isbns), "n_relevant": len(relevant)}
    for k in (5, 10):
        if k > list_size:
            for name in ("recall", "precision", "mrr", "ndcg"):
                out[f"{name}@{k}"] = None
            continue
        hits = len({w for w in works[:k] if w in relevant})
        # Capped recall: hits / min(k, |relevant|), so a 39-book author set can reach 1.0 at k=10.
        out[f"recall@{k}"] = hits / min(k, len(relevant)) if relevant else None
        out[f"precision@{k}"] = graded_precision_at_k(works, grades, k=k)
        out[f"mrr@{k}"] = mean_reciprocal_rank(works, grades, k=k)
        out[f"ndcg@{k}"] = graded_ndcg_at_k(works, grades, k=k)
    out["hit@5"] = (1.0 if any(w in relevant for w in works[:5]) else 0.0) if relevant else None
    return out


def exact_snapshot_top(vec, snap) -> List[str]:
    if vec is None or snap is None:
        return []
    q = np.asarray(vec, dtype=np.float32)
    q /= np.linalg.norm(q) or 1.0
    scores = snap["matrix"] @ q
    return [snap["isbns"][i] for i in np.argsort(-scores)[:10]]


# ── Answer grounding checks (deterministic) ─────────────────────────────────

_SPAN_RE = re.compile(
    r"[\"“”«»]([^\"“”«»\n]{3,90})[\"“”«»]"
    # Single quotes only when not glued to letters: Hobbit'in / Graves'in are suffix apostrophes.
    r"|(?<![^\W\d_])'([^'\n]{4,90}?)'(?![^\W\d_])"
    r"|‘([^’\n]{3,90})’|\*\*([^*\n]{3,90})\*\*|\*([^*\n]{3,90})\*")


def _norm(s: str) -> str:
    s = s.lower().replace("’", "'")
    s = re.sub(r"[^\w' ]+", " ", s)
    return " ".join(s.split())


def _tokens(s: str) -> set:
    return {t for t in _norm(s).split() if len(t) > 2}


class CatalogIndex:
    def __init__(self, catalog: Catalog):
        df = catalog.df
        self.catalog = catalog
        # (normalized title, isbn, raw title) for multi-word titles. A mention must also match the
        # raw title's capitalisation, so ordinary phrases ("the wonder of the world") are not read
        # as the catalog book "Wonder of the World".
        self.titles = []
        for isbn, title in zip(df["isbn13"], df["title"]):
            raw = " ".join(re.sub(r"\(.*?\)", "", title).split())
            nt = _norm(raw)
            if len(nt.split()) >= 3 and len(nt) >= 12:
                self.titles.append((nt, isbn, raw))
        names = set()
        for raw in df["authors"]:
            for a in re.split(r"[;|]", raw):
                a = a.strip()
                if "," in a:
                    last, first = a.split(",", 1)
                    a = f"{first.strip()} {last.strip()}"
                na = _norm(a)
                if len(na.split()) >= 2 and len(na) >= 9 and "unknown" not in na:
                    names.add(na)
        self.authors = sorted(names)


def answer_language(answer: str, context_books: List[dict]) -> str:
    """Production language detector on the answer with book titles removed (titles are English)."""
    from backend.application.use_cases.ai_rag import _detect_language

    text = _SPAN_RE.sub(" ", answer or "")
    for b in context_books:
        if b.get("title"):
            text = text.replace(b["title"], " ")
    return _detect_language(text)


def grounding_checks(answer: str, explanations: List[str], context_books: List[dict], prompt_isbns: List[str],
                     query: str, cidx: CatalogIndex, query_lang: Optional[str] = None) -> dict:
    text = " ".join([answer or ""] + list(explanations))
    ntext = f" {_norm(text)} "
    nquery = _norm(query)
    ctx_isbns = {normalize_isbn(b.get("isbn13", "")) for b in context_books}
    ctx_works = set(cidx.catalog.works(list(ctx_isbns)))
    ctx_titles = [_norm(b.get("title", "")) for b in context_books]
    ctx_authors = " ".join(_norm(b.get("authors", "")) for b in context_books)
    prompt_isbns = set(prompt_isbns or [])

    foreign_isbns = sorted(set(ISBN_RE.findall(text)) - ctx_isbns)
    # A catalog title (3+ words) of a book that was NOT in the context: a verifiable unsupported mention.
    foreign_titles = sorted({nt for nt, isbn, raw in cidx.titles
                             if f" {nt} " in ntext and raw in text and cidx.catalog.work_of.get(isbn) not in ctx_works
                             and nt not in nquery and not any(nt in ct or ct in nt for ct in ctx_titles)})
    foreign_authors = sorted({na for na in cidx.authors
                              if f" {na} " in ntext and na not in ctx_authors and na not in nquery
                              and not set(na.split()) <= set(ctx_authors.split())})
    # Quoted/emphasised spans that match no context title and do not come from the query: possible
    # invented or translated titles. Needs human review (a translated title is legitimate).
    flagged_spans = []
    for m in _SPAN_RE.finditer(answer or ""):
        span = next(g for g in m.groups() if g)
        ns, ts = _norm(span), _tokens(span)
        if not ts or ns in nquery:
            continue
        if any(ns in ct or ct in ns or (ts and len(ts & _tokens(ct)) / len(ts) >= 0.6) for ct in ctx_titles):
            continue
        flagged_spans.append(span)
    lang = answer_language(answer, context_books) if query_lang else None
    return {
        "context_isbns_in_prompt": sorted(ctx_isbns & prompt_isbns),
        "context_delivered": bool(prompt_isbns) and ctx_isbns <= prompt_isbns,
        "answer_language": lang,
        "language_mismatch": bool(query_lang) and lang != query_lang,
        "foreign_isbns": foreign_isbns,
        "foreign_catalog_titles": foreign_titles,
        "foreign_author_names": foreign_authors,
        "flagged_spans_for_review": flagged_spans,
        "unsupported": bool(foreign_isbns or foreign_titles or foreign_authors),
    }


_NEGATION = re.compile(
    r"\b(don't|do not|does not|doesn't|isn't|not (?:in|available|find|found|have)|couldn't|could not|cannot|can't|"
    r"unable|there (?:is|are) no|no (?:book|novel|match|information|record)|unfortunately|sorry|decline|"
    r"(?:is|are) not (?:among|one of|part of|included)|apologi[sz]e)\b|"
    r"(yok\b|bulunam|bulamad|bulunmu|değil|maalesef|ne yazık ki|mevcut değil|yer almıyor|bulunmamakta|üzgünüm|"
    # -AmIyor: "yazamıyorum", "veremiyorum" (cannot write / cannot give).
    r"yazamam|yapamam|veremem|olamam|[ae]m[ıi]yor)",
    re.IGNORECASE,
)


# ── Run ─────────────────────────────────────────────────────────────────────

def _pct(values: List[float], p: float) -> Optional[float]:
    if not values:
        return None
    vals = sorted(values)
    idx = min(len(vals) - 1, max(0, math.ceil(p / 100 * len(vals)) - 1))
    return round(vals[idx], 1)


def _source(res: dict) -> Optional[str]:
    return (res.get("metrics") or {}).get("source")


def _context(books: List[dict]) -> List[dict]:
    return [{"isbn13": b.get("isbn13"), "title": b.get("title"), "authors": b.get("authors")} for b in books]


def adversarial_checks(a: dict, g: dict) -> Dict[str, bool]:
    """Deterministic checks scoped to what each case expects (see rag_eval_adversarial.json)."""
    answer = a.get("answer") or ""
    negated = bool(_NEGATION.search(answer))
    # A fictional title/author mentioned WITHOUT a negation is a claim that it exists.
    mentions_fiction = any(t.lower() in answer.lower() for t in a.get("fictional_terms", []))
    checks = {
        "no_foreign_isbn": not g["foreign_isbns"],
        "no_foreign_catalog_titles": not g["foreign_catalog_titles"],
        "no_injected_isbn": not any(i in answer for i in a.get("injected_isbns", [])),
        "fictional_not_affirmed": (not mentions_fiction) or negated,
        "answer_in_query_language": not g["language_mismatch"],
    }
    if a["expect"] in ("abstain_not_in_catalog", "stay_on_books"):
        checks["abstained_or_declined"] = negated or a.get("status") in ("no_match", "empty_retrieval")
    return checks


def run(args) -> None:
    from backend.application.use_cases.ai_rag import ProcessRagQueryUseCase
    from backend.container import Container

    data = load_dataset(include_expansion=args.dataset == "all", categories=args.category)
    queries = data["queries"][: args.limit] if args.limit else data["queries"]
    # The adversarial probes are not categorised; a category-limited run skips them.
    adversarial = [] if args.category else json.load(open(ADVERSARIAL, encoding="utf-8"))["cases"]

    container = Container()
    rec = Recorder()
    instrument(container, rec)
    catalog = Catalog()
    snap = None
    if os.path.exists(SNAPSHOT):
        z = np.load(SNAPSHOT, allow_pickle=True)
        m = z["vectors"].astype(np.float32)
        snap = {"isbns": [normalize_isbn(i) for i in z["isbns"].tolist()],
                "matrix": m / np.linalg.norm(m, axis=1, keepdims=True)}

    def fresh_use_case():
        return ProcessRagQueryUseCase(
            embedding_port=container.embedding_service, book_data_port=container.book_data_port,
            interaction_repo=container.interaction_repo, recommender=container.recommender,
            enrichment_service=container.enrichment_service, llm_port=container.llm_port)

    uc = fresh_use_case()
    results, vectors = [], {}

    def execute(text):
        rec.reset()
        t0 = time.perf_counter()
        try:
            res, err = uc.execute(text), None
        except Exception as exc:  # the pipeline should never raise; record it if it does
            res, err = {}, f"{type(exc).__name__}: {exc}"
        wall = round((time.perf_counter() - t0) * 1000, 1)
        return res, err, wall, {"http": list(rec.http), "embeds": list(rec.embeds), "rpcs": list(rec.rpcs),
                                "llm": list(rec.llm)}

    def summarize_calls(cap):
        return [{k: v for k, v in h.items()} for h in cap["http"]]

    print(f"embedding profile: {container.embedding_service.describe()}")
    print(f"book data port: {type(container.book_data_port).__name__}")
    for i, q in enumerate(queries, 1):
        res, err, wall, cap = execute(q["text"])
        if args.pause:
            time.sleep(args.pause)
        res_w, err_w, wall_w, cap_w = execute(q["text"])  # warm: same process, query cache populated
        # Semantic stage as production ran it; if the query was answered without vector search
        # (catalog lookup), run the same embedding + RPC once so the stage is still evaluated.
        extra = None
        if not cap["rpcs"]:
            rec.reset()
            vec = container.embedding_service.embed_query(q["text"])
            if vec:
                container.book_data_port.match_query_embeddings(vec, limit=100)
            extra = {"http": list(rec.http), "embeds": list(rec.embeds), "rpcs": list(rec.rpcs)}
        stage = extra or cap
        vec = stage["embeds"][0]["vector"] if stage["embeds"] else None
        rpc_hits = stage["rpcs"][0]["hits"] if stage["rpcs"] else {}
        semantic_ranked = [normalize_isbn(k) for k, _ in sorted(rpc_hits.items(), key=lambda kv: -kv[1])]
        if vec is not None:
            vectors[q["id"]] = np.asarray(vec, dtype=np.float32)
        books = res.get("referenced_books") or []
        prompt = cap["llm"][0]["user_prompt"] if cap["llm"] else ""
        explanations = [b.get("explanation") for b in books if b.get("explanation")]
        results.append({
            "id": q["id"], "intent": q["intent"], "lang": q["lang"], "variant": q.get("variant"),
            "type": q["type"], "category": q["category"], "label_tier": q["label_tier"], "text": q["text"],
            "cold": {
                "wall_ms": wall, "error": err, "status": res.get("status"), "source": _source(res),
                "retrieval_mode": (res.get("metrics") or {}).get("retrieval_mode"),
                "degraded": (res.get("metrics") or {}).get("degraded"),
                "pipeline_metrics": {k: v for k, v in (res.get("metrics") or {}).items() if k.endswith("_ms")},
                "answer": res.get("answer"), "books": [b.get("isbn13") for b in books],
                "book_titles": [b.get("title") for b in books],
                "llm_called": bool(cap["llm"]), "llm_returned_text": bool(cap["llm"] and cap["llm"][0]["raw"]),
                "llm_ms": cap["llm"][0]["ms"] if cap["llm"] else None,
                "http": summarize_calls(cap),
                "embed_ms": cap["embeds"][0]["ms"] if cap["embeds"] else None,
                "rpc_ms": cap["rpcs"][0]["ms"] if cap["rpcs"] else None,
                "rpc_rows": len(cap["rpcs"][0]["hits"]) if cap["rpcs"] else None,
                # Raw evidence for the grounding checks, which finalize() recomputes offline.
                "context": _context(books), "explanations": explanations,
                "prompt_isbns": sorted(set(ISBN_RE.findall(prompt))),
            },
            "warm": {"wall_ms": wall_w, "error": err_w, "status": res_w.get("status"), "source": _source(res_w),
                     "books": [b.get("isbn13") for b in (res_w.get("referenced_books") or [])],
                     "http": summarize_calls(cap_w)},
            "semantic_stage": {"from_production_call": extra is None, "rpc_rows": len(rpc_hits),
                               "rpc_ms": stage["rpcs"][0]["ms"] if stage["rpcs"] else None,
                               "embed_ms": stage["embeds"][0]["ms"] if stage["embeds"] else None,
                               "top10": semantic_ranked[:10],
                               "top10_scores": [round(rpc_hits[k], 4) for k in semantic_ranked[:10]] if rpc_hits else [],
                               "http": extra["http"] if extra else None},
            "exact_snapshot_top10": exact_snapshot_top(vec, snap),
        })
        c = results[-1]["cold"]
        print(f"[{i}/{len(queries)}] {q['id']:24} {c['status']}/{c['source']} rpc_rows={c['rpc_rows']} "
              f"cold={wall:.0f}ms warm={wall_w:.0f}ms")
        if args.pause:
            time.sleep(args.pause)

    adv_results = []
    for case in adversarial:
        res, err, wall, cap = execute(case["text"])
        books = res.get("referenced_books") or []
        answer = res.get("answer") or ""
        prompt = cap["llm"][0]["user_prompt"] if cap["llm"] else ""
        explanations = [b.get("explanation") for b in books if b.get("explanation")]
        adv_results.append({**case, "status": res.get("status"), "source": _source(res), "error": err,
                            "wall_ms": wall, "answer": answer, "books": [b.get("title") for b in books],
                            "context": _context(books), "explanations": explanations,
                            "prompt_isbns": sorted(set(ISBN_RE.findall(prompt))),
                            "llm_called": bool(cap["llm"]), "llm_returned_text": bool(cap["llm"] and cap["llm"][0]["raw"]),
                            "http": summarize_calls(cap)})
        print(f"[adv] {case['id']:22} {res.get('status')}/{_source(res)} {wall:.0f}ms")
        if args.pause:
            time.sleep(args.pause)

    if vectors:
        os.makedirs(os.path.dirname(QUERY_VECTORS), exist_ok=True)
        np.savez_compressed(QUERY_VECTORS, ids=np.array(list(vectors)), vectors=np.stack(list(vectors.values())),
                            profile=json.dumps(container.embedding_service.describe()))
    run_doc = {
        "run_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "embedding_profile": container.embedding_service.describe(),
        "book_data_port": type(container.book_data_port).__name__,
        "llm_model": getattr(container.llm_port, "_model_name", None),
        "dataset": os.path.relpath(DATASET, EVAL), "dataset_versions": data["dataset_versions"],
        "category_filter": args.category or None, **_git_revision(), "pause_s": args.pause,
        "queries": results, "adversarial": adv_results,
    }
    pool_judgments(run_doc, data, catalog)
    finalize(run_doc, data, catalog)


# ── Judgments ───────────────────────────────────────────────────────────────

def load_judgment_rows() -> List[dict]:
    if not os.path.exists(JUDGMENTS):
        return []
    with open(JUDGMENTS, encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


def pool_judgments(run_doc: dict, data: dict, catalog: Catalog) -> None:
    rows = load_judgment_rows()
    seen = {(r["intent"], r["isbn"]) for r in rows}
    by_intent = defaultdict(lambda: defaultdict(set))
    expected = {q["intent"]: (set(q["expected_isbns"]), q["label_tier"]) for q in data["queries"]}
    for r in run_doc["queries"]:
        for system, isbns in (("production", r["cold"]["books"]), ("semantic_rpc", r["semantic_stage"]["top10"]),
                              ("semantic_exact", r["exact_snapshot_top10"])):
            for i in isbns or []:
                by_intent[r["intent"]][normalize_isbn(i)].add(f"{system}:{r['lang']}{'_ascii' if r['variant'] else ''}")
    for intent, (exp, _) in expected.items():
        for i in exp:
            by_intent[intent][i].add("expected_set")
    added = 0
    for intent, books in sorted(by_intent.items()):
        exp, tier = expected[intent]
        for isbn, systems in sorted(books.items()):
            if (intent, isbn) in seen or isbn not in catalog.row_of:
                continue
            b = catalog.book(isbn)
            rows.append({"intent": intent, "isbn": isbn, "title": b["title"], "authors": b["authors"],
                         "retrieved_by": " ".join(sorted(systems)), "in_proposed_set": int(isbn in exp),
                         "label_tier": tier, "human_grade": "", "reviewed_by": "", "notes": ""})
            added += 1
    with open(JUDGMENTS, "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=JUDGMENT_FIELDS)
        w.writeheader()
        w.writerows(rows)
    print(f"judgments: {added} new rows pooled for review -> {os.path.relpath(JUDGMENTS)}")


def grades_for(intent: str, query: dict, catalog: Catalog, human: Dict[str, Dict[str, int]]):
    """(grades, tier, alias). Human grades win when present for an intent; otherwise the dataset's
    expected set (binary). single_work intents fold every listed edition into one target."""
    if human.get(intent):
        return human[intent], "human_verified", None
    works = catalog.works(query["expected_isbns"])
    if query.get("single_work"):
        target = f"target:{intent}"
        return {target: 1}, query["label_tier"], {w: target for w in works}
    return {w: 1 for w in works}, query["label_tier"], None


# ── Report ──────────────────────────────────────────────────────────────────

def human_grades(rows: List[dict], catalog: Catalog) -> Dict[str, Dict[str, int]]:
    """Per-intent human grades, only for COMPLETE intents. grades_for() treats every book without a grade
    as irrelevant once an intent has human grades, so a half-reviewed intent would silently score
    ungraded relevant books as misses. An intent counts only when every one of its rows has a grade
    in {0,1,2} and a reviewer; partial intents are ignored (and listed by `rag_review.py status`)."""
    by_intent: Dict[str, List[dict]] = defaultdict(list)
    for r in rows:
        by_intent[r["intent"]].append(r)
    out: Dict[str, Dict[str, int]] = {}
    for intent, rs in by_intent.items():
        if not all(r.get("human_grade", "").strip() in ("0", "1", "2") and r.get("reviewed_by", "").strip()
                   for r in rs):
            continue
        grades: Dict[str, int] = {}
        for r in rs:  # editions of one work share a grade; keep the best one
            w = catalog.work_of.get(r["isbn"], r["isbn"])
            grades[w] = max(grades.get(w, 0), int(r["human_grade"]))
        out[intent] = grades
    return out


def finalize(run_doc: dict, data: dict, catalog: Catalog, outputs: Optional[Dict[str, str]] = None) -> None:
    outputs = outputs or {"json": REPORT_JSON, "md": REPORT_MD, "csv": REPORT_CSV}
    human = human_grades(load_judgment_rows(), catalog)
    qmap = {q["id"]: q for q in data["queries"]}

    per_query = []
    for r in run_doc["queries"]:
        q = qmap[r["id"]]
        # No labelled set (open, ambiguous, insufficient-information and no-relevant queries): judged
        # by behaviour below, never scored as a retrieval miss.
        if not q["expected_isbns"] and not human.get(q["intent"]):
            continue
        grades, tier, alias = grades_for(q["intent"], q, catalog, human)
        per_query.append({
            "id": r["id"], "intent": r["intent"], "lang": r["lang"], "variant": r["variant"], "type": r["type"],
            "category": q["category"], "difficulty": q["difficulty"], "tier": tier,
            "production_top5": retrieval_metrics(r["cold"]["books"], grades, catalog, alias, list_size=5),
            "semantic_rpc_top10": retrieval_metrics(r["semantic_stage"]["top10"], grades, catalog, alias),
            "semantic_exact_top10": retrieval_metrics(r["exact_snapshot_top10"], grades, catalog, alias)
            if r["exact_snapshot_top10"] else None,
        })

    def agg(rows, system):
        keys = RETRIEVAL_METRIC_KEYS
        vals = [x[system] for x in rows if x[system]]
        out = {"n": len(vals)}
        for k in keys:
            v = [m[k] for m in vals if m[k] is not None]
            out[k] = round(statistics.mean(v), 3) if v else None
        out["empty_rate"] = round(sum(1 for m in vals if m["n_returned"] == 0) / len(vals), 3) if vals else None
        return out

    groups = {
        "all": lambda x: True,
        "en": lambda x: x["lang"] == "en",
        "tr (Turkish letters)": lambda x: x["lang"] == "tr" and not x["variant"],
        "tr (ASCII-typed)": lambda x: x["variant"] == "ascii_folded",
    }
    summary = {}
    systems = ("production_top5", "semantic_rpc_top10", "semantic_exact_top10")
    for tier in SCORED_TIERS:
        tier_rows = [x for x in per_query if x["tier"] == tier]
        if not tier_rows:
            continue
        summary[tier] = {g: {s: agg([x for x in tier_rows if f(x)], s) for s in systems}
                         for g, f in groups.items()}
    # Per category, across tiers (each row keeps its tier in per_query and in the CSV).
    by_category = {c: {s: agg([x for x in per_query if x["category"] == c], s) for s in systems}
                   for c in sorted({x["category"] for x in per_query})}

    # Paired EN vs TR on identical intents (Turkish-letter variant only).
    paired = defaultdict(dict)
    for x in per_query:
        if not x["variant"]:
            paired[x["intent"]][x["lang"]] = x
    pair_rows = []
    for intent, d in sorted(paired.items()):
        if "en" in d and "tr" in d:
            pair_rows.append({"intent": intent, "tier": d["en"]["tier"],
                              **{f"{s}_{lang}": d[lang][s]["ndcg@5"] for s in ("production_top5", "semantic_rpc_top10")
                                 for lang in ("en", "tr")}})

    # Latency, errors, tokens.
    qs = run_doc["queries"]
    cold_wall = [r["cold"]["wall_ms"] for r in qs]
    warm_wall = [r["warm"]["wall_ms"] for r in qs]
    llm_ms = [r["cold"]["llm_ms"] for r in qs if r["cold"]["llm_ms"] is not None]
    embed_ms = [r["semantic_stage"]["embed_ms"] for r in qs if r["semantic_stage"]["embed_ms"] is not None]
    rpc_ms = [r["semantic_stage"]["rpc_ms"] for r in qs if r["semantic_stage"]["rpc_ms"] is not None]
    # Gemini answers only: a fallback served after a 503/timeout is not a generated answer, even in
    # runs recorded before the fallback path stopped reporting source=rag_llm.
    rag_llm_wall = [r["cold"]["wall_ms"] for r in qs
                    if r["cold"]["source"] == "rag_llm" and r["cold"]["status"] == "success"]
    fallback_wall = [r["cold"]["wall_ms"] for r in qs if r["cold"]["status"] == "llm_fallback"]
    det_wall = [r["cold"]["wall_ms"] for r in qs if (r["cold"]["source"] or "").startswith("deterministic")]
    all_http = [h for r in qs for h in r["cold"]["http"] + r["warm"]["http"] + (r["semantic_stage"]["http"] or [])]
    all_http += [h for a in run_doc["adversarial"] for h in a["http"]]
    gen_http = [h for h in all_http if h["kind"] == "generate"]
    emb_http = [h for h in all_http if h["kind"] == "embed"]

    def tokens(calls, key):
        vals = [(h.get("usage") or {}).get(key) for h in calls if h.get("status") == 200]
        vals = [v for v in vals if isinstance(v, int)]
        return {"sum": sum(vals), "n_calls_with_usage": len(vals),
                "mean": round(statistics.mean(vals), 1) if vals else None}

    def stats(v):
        return {"n": len(v), "p50": _pct(v, 50), "p95": _pct(v, 95), "max": round(max(v), 1) if v else None}

    perf = {
        "end_to_end_cold_all": stats(cold_wall),
        "end_to_end_cold_gemini_answers": stats(rag_llm_wall),
        "end_to_end_cold_deterministic_catalog": stats(det_wall),
        "end_to_end_cold_llm_fallback": stats(fallback_wall),
        "end_to_end_warm_query_cache": stats(warm_wall),
        "query_embedding": stats(embed_ms),
        "vector_rpc": stats(rpc_ms),
        "gemini_generation": stats(llm_ms),
        "http_calls": {
            "generate": {"attempts": len(gen_http),
                         "non_200": sum(1 for h in gen_http if h.get("status") != 200),
                         "status_counts": dict(sorted(_count(h.get("status") or h.get("error") for h in gen_http).items(), key=str))},
            "embed": {"attempts": len(emb_http),
                      "non_200": sum(1 for h in emb_http if h.get("status") != 200),
                      "status_counts": dict(sorted(_count(h.get("status") or h.get("error") for h in emb_http).items(), key=str))},
        },
        "model_versions": sorted({h.get("model_version") for h in gen_http if h.get("model_version")}),
        "tokens_generate": {k: tokens(gen_http, k) for k in
                            ("promptTokenCount", "candidatesTokenCount", "thoughtsTokenCount", "totalTokenCount")},
        "tokens_embed": {k: tokens(emb_http, k) for k in ("promptTokenCount", "totalTokenCount")},
        "warm_served_from_cache": sum(1 for r in qs if r["warm"]["source"] == "cache_hit"),
        "warm_http_calls": sum(len(r["warm"]["http"]) for r in qs),
    }

    # Answer reliability: grounding is recomputed here from the stored evidence (offline).
    cidx = CatalogIndex(catalog)
    for r in qs:
        c = r["cold"]
        c["grounding"] = grounding_checks(c["answer"] or "", c.get("explanations", []), c.get("context", []),
                                          c.get("prompt_isbns", []), r["text"], cidx, r["lang"]) \
            if c["llm_returned_text"] else None
    for a in run_doc["adversarial"]:
        a["grounding"] = grounding_checks(a["answer"] or "", a.get("explanations", []), a.get("context", []),
                                          a.get("prompt_isbns", []), a["text"], cidx, a["lang"])
        a["checks"] = adversarial_checks(a, a["grounding"])
    sources = _count(r["cold"]["source"] for r in qs)
    statuses = _count(r["cold"]["status"] for r in qs)
    gem = [r for r in qs if r["cold"]["llm_returned_text"]]
    llm_rows = [r for r in gem if r["cold"]["grounding"]]
    attribution_errors = []
    for r in qs:
        c = r["cold"]
        if c["source"] == "rag_llm" and c["status"] == "success" and not c["llm_returned_text"]:
            attribution_errors.append(f"{r['id']}: labelled Gemini success but the LLM returned nothing")
        if c["source"] == "rag_llm" and c["status"] == "llm_fallback":
            attribution_errors.append(f"{r['id']}: fallback answer reported source=rag_llm")
        if (c["source"] or "").startswith("deterministic") and c["llm_called"]:
            attribution_errors.append(f"{r['id']}: labelled deterministic but the LLM was called")
        if c["status"] == "llm_fallback" and c["llm_returned_text"] and not (c["grounding"] or {}).get("unsupported") \
                and not (c["grounding"] or {}).get("foreign_isbns"):
            attribution_errors.append(f"{r['id']}: llm_fallback although the LLM answered (rejected by the guard?)")
    reliability = {
        "statuses": statuses, "sources": sources,
        "gemini_answers": len(gem),
        "context_delivered_rate": _rate(llm_rows, lambda r: r["cold"]["grounding"]["context_delivered"]),
        "answers_with_foreign_isbn": sum(1 for r in llm_rows if r["cold"]["grounding"]["foreign_isbns"]),
        "answers_with_foreign_catalog_title": sum(1 for r in llm_rows if r["cold"]["grounding"]["foreign_catalog_titles"]),
        "answers_with_foreign_author": sum(1 for r in llm_rows if r["cold"]["grounding"]["foreign_author_names"]),
        "unsupported_claim_rate": _rate(llm_rows, lambda r: r["cold"]["grounding"]["unsupported"]),
        "answers_with_spans_for_review": sum(1 for r in llm_rows if r["cold"]["grounding"]["flagged_spans_for_review"]),
        "answers_in_wrong_language": sorted(r["id"] for r in llm_rows if r["cold"]["grounding"]["language_mismatch"])
        + sorted(a["id"] for a in run_doc["adversarial"] if a["llm_returned_text"] and a["grounding"]["language_mismatch"]),
        "source_attribution_errors": attribution_errors,
        "adversarial": {
            "cases": len(run_doc["adversarial"]),
            "all_checks_passed": sum(1 for a in run_doc["adversarial"] if all(a["checks"].values())),
            "failures": {a["id"]: [k for k, v in a["checks"].items() if not v]
                         for a in run_doc["adversarial"] if not all(a["checks"].values())},
        },
    }
    reliability["behaviour_checks"] = behaviour_checks(qs, qmap)
    run_doc["evaluation"] = {"per_query": per_query, "summary": summary, "by_category": by_category,
                             "paired_en_tr_ndcg5": pair_rows,
                             "performance": perf, "reliability": reliability,
                             "dataset_composition": dataset_composition(data["queries"], {r["id"] for r in qs}),
                             "human_verified_intents": sorted(k for k, v in human.items() if v)}
    os.makedirs(os.path.dirname(outputs["json"]), exist_ok=True)
    with open(outputs["json"], "w", encoding="utf-8") as f:
        json.dump(run_doc, f, ensure_ascii=False, indent=1, default=str)
    write_markdown(run_doc, outputs["md"])
    write_query_csv(run_doc, data, outputs["csv"])
    print(f"wrote {os.path.relpath(outputs['json'])}, {os.path.relpath(outputs['md'])} and "
          f"{os.path.relpath(outputs['csv'])}")


def behaviour_checks(run_rows: List[dict], qmap: Dict[str, dict]) -> dict:
    """Queries judged by behaviour, not by a relevant set: an answer to a no-relevant query must say
    the work is not in the catalog; an insufficient-information answer must not cite a foreign ISBN
    or make an unsupported claim."""
    out = {"abstain_not_in_catalog": {"n": 0, "passed": 0, "failures": []},
           "no_fabrication": {"n": 0, "passed": 0, "failures": []}}
    for r in run_rows:
        expect = qmap[r["id"]].get("expected_behavior")
        if expect not in out:
            continue
        c = r["cold"]
        g = c.get("grounding") or {}
        if expect == "abstain_not_in_catalog":
            ok = bool(_NEGATION.search(c.get("answer") or "")) or c.get("status") in ("no_match", "empty_retrieval")
        else:
            ok = not g.get("foreign_isbns") and not g.get("unsupported")
        out[expect]["n"] += 1
        out[expect]["passed"] += int(ok)
        if not ok:
            out[expect]["failures"].append(r["id"])
    return out


def dataset_composition(queries: List[dict], run_ids: set) -> dict:
    """What the dataset holds and how much of it the saved run actually covers."""
    def counts(key):
        return dict(sorted(_count(q.get(key) for q in queries).items()))
    return {
        "queries": len(queries), "in_this_run": sum(1 for q in queries if q["id"] in run_ids),
        "by_category": counts("category"), "by_language": counts("lang"), "by_tier": counts("label_tier"),
        "by_difficulty": counts("difficulty"), "by_expected_behavior": counts("expected_behavior"),
        "by_dataset": counts("dataset"),
        "without_labelled_set": sum(1 for q in queries if not q["expected_isbns"]),
    }


QUERY_CSV_FIELDS = ["id", "intent", "lang", "variant", "dataset", "category", "difficulty", "label_tier",
                    "expected_behavior", "n_expected", "scored_tier", "cold_status", "cold_source"]
CSV_SYSTEMS = ("production_top5", "semantic_rpc_top10", "semantic_exact_top10")


def write_query_csv(doc: dict, data: dict, path: str) -> None:
    """One row per query of the run: labels, provenance, outcome, and every metric of every system.
    Metrics that do not apply (no labelled set, or k beyond a system's list size) are empty cells."""
    qmap = {q["id"]: q for q in data["queries"]}
    scored = {x["id"]: x for x in doc["evaluation"]["per_query"]}
    fields = QUERY_CSV_FIELDS + [f"{s}.{k}" for s in CSV_SYSTEMS for k in RETRIEVAL_METRIC_KEYS]
    with open(path, "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        for r in doc["queries"]:
            q = qmap[r["id"]]
            x = scored.get(r["id"])
            row = {"id": r["id"], "intent": r["intent"], "lang": r["lang"], "variant": r.get("variant") or "",
                   "dataset": q.get("dataset", ""), "category": q["category"], "difficulty": q["difficulty"],
                   "label_tier": q["label_tier"], "expected_behavior": q["expected_behavior"],
                   "n_expected": len(q["expected_isbns"]), "scored_tier": x["tier"] if x else "",
                   "cold_status": r["cold"].get("status") or "", "cold_source": r["cold"].get("source") or ""}
            for sname in CSV_SYSTEMS:
                m = (x or {}).get(sname) or {}
                for k in RETRIEVAL_METRIC_KEYS:
                    v = m.get(k)
                    row[f"{sname}.{k}"] = "" if v is None else round(v, 4)
            w.writerow(row)


def _count(items) -> Dict[str, int]:
    out: Dict[str, int] = defaultdict(int)
    for i in items:
        out[str(i)] += 1
    return dict(out)


def _rate(rows, pred) -> Optional[float]:
    return round(sum(1 for r in rows if pred(r)) / len(rows), 3) if rows else None


def write_markdown(doc: dict, path: str = REPORT_MD) -> None:
    ev = doc["evaluation"]
    lines = [f"# RAG quality evaluation (live) - {doc['run_at']}", "",
             f"Embedding profile `{doc['embedding_profile'].get('document_profile')}`, query format "
             f"`{doc['embedding_profile'].get('query_format')}`; vector port `{doc['book_data_port']}`; "
             f"LLM `{doc['llm_model']}`. Labels: see `label_tiers` in the dataset; human-verified intents: "
             f"{ev['human_verified_intents'] or 'none'}.", ""]
    for tier, groups in ev["summary"].items():
        heads = ["Hit@5", "R@5", "R@10", "P@5", "P@10", "MRR@5", "MRR@10", "nDCG@5", "nDCG@10"]
        lines += [f"## Retrieval ({tier})", "",
                  "| group | system | n | " + " | ".join(heads) + " | empty |",
                  "|" + "---|" * (len(heads) + 4)]
        for g, systems in groups.items():
            for s, m in systems.items():
                if m["n"]:
                    cells = ["–" if m.get(k) is None else str(m[k]) for k in RETRIEVAL_METRIC_KEYS]
                    lines.append(f"| {g} | {s} | {m['n']} | " + " | ".join(cells) + f" | {m['empty_rate']} |")
        lines.append("")
    lines += ["\"–\" = not applicable: production answers with at most 5 books, so it has no @10 metrics.", ""]
    comp = ev.get("dataset_composition")
    if comp:
        lines += ["## Dataset composition", "",
                  f"{comp['queries']} queries in the dataset, {comp['in_this_run']} in this run; "
                  f"{comp['without_labelled_set']} have no labelled set and are judged by behaviour only.", "",
                  "```json", json.dumps({k: v for k, v in comp.items() if k.startswith("by_")}, indent=1), "```", ""]
    if ev.get("by_category"):
        lines += ["## By category (all tiers mixed; see the per-query CSV for each row's tier)", "",
                  "| category | n | production Hit@5 | production nDCG@5 | semantic nDCG@5 | semantic nDCG@10 |",
                  "|---|---|---|---|---|---|"]
        for c, m in ev["by_category"].items():
            p, sem = m["production_top5"], m["semantic_rpc_top10"]
            lines.append(f"| {c} | {p['n']} | {p['hit@5']} | {p['ndcg@5']} | {sem['ndcg@5']} | {sem['ndcg@10']} |")
        lines.append("")
    lines += ["## Paired EN vs TR (nDCG@5, same intent)", "",
              "| intent | tier | production EN | production TR | semantic EN | semantic TR |", "|---|---|---|---|---|---|"]
    for p in ev["paired_en_tr_ndcg5"]:
        lines.append(f"| {p['intent']} | {p['tier']} | {p['production_top5_en']:.3f} | {p['production_top5_tr']:.3f} | "
                     f"{p['semantic_rpc_top10_en']:.3f} | {p['semantic_rpc_top10_tr']:.3f} |")
    lines += ["", "## Performance", "", "```json", json.dumps(ev["performance"], indent=1, default=str), "```",
              "", "## Answer reliability", "", "```json", json.dumps(ev["reliability"], indent=1, ensure_ascii=False), "```"]
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def report(args) -> None:
    doc = json.load(open(REPORT_JSON, encoding="utf-8"))
    categories = getattr(args, "category", None)
    data = load_dataset(categories=categories)
    if not categories:
        finalize(doc, data, Catalog())
        return
    ids = {q["id"] for q in data["queries"]}
    doc = {**doc, "queries": [r for r in doc["queries"] if r["id"] in ids], "adversarial": [],
           "category_filter": categories}
    if not doc["queries"]:
        # Categories that exist in the dataset but were never run live (the expansion before its first
        # run): say so instead of writing an empty report that reads like a result.
        print(f"no saved results for categories {categories}; run them live first", file=sys.stderr)
        sys.exit(2)
    stem = os.path.join(EVAL, "reports", "rag_quality_eval." + "+".join(sorted(categories)))
    finalize(doc, data, Catalog(), outputs={"json": stem + ".json", "md": stem + ".md", "csv": stem + ".csv"})


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("run")
    r.add_argument("--limit", type=int, default=0)
    r.add_argument("--pause", type=float, default=1.0, help="seconds between live calls (rate limits)")
    r.add_argument("--dataset", choices=("all", "base"), default="all",
                   help="base = the original 44 queries only; all = plus data/rag_eval_expansion.json")
    r.add_argument("--category", nargs="+", help="run only these query categories")
    r.set_defaults(func=run)
    rp = sub.add_parser("report")
    rp.add_argument("--category", nargs="+", help="score only these categories (separate output files)")
    rp.set_defaults(func=report)
    args = p.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
