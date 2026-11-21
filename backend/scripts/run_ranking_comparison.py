"""Offline, controlled comparison of RAG ranking strategies on IDENTICAL candidate sets.

Candidates = exact cosine top-N over the exported snapshot using the stored query vectors from the
last live run (no Gemini, no database). Every strategy sees the same candidates, then is scored
with the harness's own metrics. Labels used: `rule_derived` (identity rules) and, once graded,
human-verified intents. `proposed` labels are shown for orientation only and must not be used to
choose between strategies.

    python -m backend.scripts.run_ranking_comparison [--pool 100] [--json out.json]
"""
from __future__ import annotations

import argparse
import json
import os
import statistics
import sys
from collections import defaultdict

import numpy as np

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")))

from backend.evaluation.retrieval import Catalog  # noqa: E402
from backend.infrastructure.ml.recommender import BookRecommender, WEIGHT_POPULARITY  # noqa: E402
from backend.scripts.run_rag_quality_eval import (  # noqa: E402
    DATASET, QUERY_VECTORS, SNAPSHOT, grades_for, human_grades, load_judgment_rows, retrieval_metrics)
from backend.config import Config  # noqa: E402
from backend.utils.preprocess import normalize_isbn  # noqa: E402



def candidates(vec, isbns, matrix, pool):
    q = np.asarray(vec, dtype=np.float32)
    q /= np.linalg.norm(q) or 1.0
    s = matrix @ q
    top = np.argsort(-s)[:pool]
    return {isbns[i]: float(s[i]) for i in top}


def dedupe_top(ranked, cat, k=5):
    seen, out = set(), []
    for i in ranked:
        w = cat.work_of.get(i, i)
        if w not in seen:
            seen.add(w)
            out.append(i)
        if len(out) == k:
            break
    return out


def run_strategy(name, rec, cat, cands, k=5):
    if name == "semantic_only":
        return dedupe_top(sorted(cands, key=lambda i: -cands[i]), cat, k)
    diversity = not name.endswith("_nomm")
    name = name.removesuffix("_nomm")
    cfg = rec.engine.config if hasattr(rec, "engine") else rec.config
    saved = cfg.weight_popularity
    try:
        if name == "pop_off":
            cfg.weight_popularity = 0.0
        elif name.startswith("pop_"):
            cfg.weight_popularity = float(name[4:])
        recs = rec.recommend(top_n=k + 5, use_diversity=diversity, semantic_scores=cands)
    finally:
        cfg.weight_popularity = saved
    return dedupe_top([normalize_isbn(r["isbn13"]) for r in recs], cat, k)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pool", type=int, default=100)
    ap.add_argument("--strategies", default="production,semantic_only,pop_off,pop_0.05")
    ap.add_argument("--json", default="")
    a = ap.parse_args()

    cat = Catalog()
    snap = np.load(SNAPSHOT, allow_pickle=True)
    isbns, matrix = [str(x) for x in snap["isbns"]], snap["vectors"].astype(np.float32)
    matrix /= np.maximum(np.linalg.norm(matrix, axis=1, keepdims=True), 1e-12)
    qv = np.load(QUERY_VECTORS, allow_pickle=True)
    vecs = dict(zip([str(x) for x in qv["ids"]], qv["vectors"]))
    data = json.load(open(DATASET, encoding="utf-8"))
    human = human_grades(load_judgment_rows(), cat)
    rec = BookRecommender()
    if not rec.load_model(Config.MODEL_PATH):
        raise SystemExit(f"cannot load {Config.MODEL_PATH}")
    strategies = a.strategies.split(",")

    rows = defaultdict(lambda: defaultdict(list))
    foreign = defaultdict(list)
    for q in data["queries"]:
        if q["id"] not in vecs or q["label_tier"] == "open" or q.get("variant"):
            continue
        cands = candidates(vecs[q["id"]], isbns, matrix, a.pool)
        grades, tier, alias = grades_for(q["intent"], q, cat, human)
        for s in strategies:
            ranked = run_strategy(s, rec, cat, cands)
            m = retrieval_metrics(ranked, grades, cat, alias)
            for key in ("ndcg@5", "precision@5", "recall@5", "mrr@5"):
                rows[(tier, s)][key].append(m[key] if m[key] is not None else 0.0)
            if q["intent"].startswith("author_"):
                rel = {w for w in grades}
                foreign[s].append(sum(1 for i in ranked if cat.work_of.get(i, i) not in rel) / max(1, len(ranked)))
    out = {"pool": a.pool, "default_popularity_weight": WEIGHT_POPULARITY, "metrics": {}, "author_foreign_share@5": {}}
    for (tier, s), v in sorted(rows.items()):
        out["metrics"][f"{tier}/{s}"] = {k: round(statistics.mean(x), 3) for k, x in v.items()} | {"n": len(v["ndcg@5"])}
    out["author_foreign_share@5"] = {s: round(statistics.mean(v), 3) for s, v in foreign.items()}
    print(json.dumps(out, indent=1))
    if a.json:
        json.dump(out, open(a.json, "w"), indent=1)


if __name__ == "__main__":
    main()
