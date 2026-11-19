"""
Reproducible offline evaluation of Libris retrieval and recommendation variants.

    python -m backend.scripts.run_retrieval_evaluation pool       # add unjudged candidates to the judgment CSVs
    python -m backend.scripts.run_retrieval_evaluation evaluate   # compute metrics, write evaluation/reports/

Embedding systems need an exported snapshot (no network calls are made here):
    --book-embeddings     evaluation/cache/book_embeddings.npz     (isbns, vectors, model_version)
    --query-embeddings    evaluation/cache/query_embeddings_<fmt>.npz  (topic_ids, vectors, format)
Produce them with backend/scripts/export_embedding_snapshot.py. Without them the
embedding rows are reported as "not executed", never estimated.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import statistics
import sys
from collections import defaultdict
from typing import Callable, Dict, List, Optional

import numpy as np
from sklearn.metrics.pairwise import cosine_similarity

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from backend.evaluation.metrics import (  # noqa: E402
    graded_ndcg_at_k,
    graded_precision_at_k,
    graded_recall_at_k,
    intra_list_distance,
    judged_at_k,
    mean_reciprocal_rank,
)
from backend.evaluation.retrieval import (  # noqa: E402
    DATA_DIR,
    Catalog,
    EmbeddingIndex,
    TfidfIndex,
    fit_tfidf,
    judgment_provenance,
    load_judgments,
    load_topics,
    mmr,
    production_tfidf,
    scores_on_catalog,
    top_k,
    topic_split,
    write_pool,
)
from backend.utils.preprocess import _fold, build_combined_features, clean_text  # noqa: E402

BACKEND = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODEL_PATH = os.path.join(BACKEND, "saved_model", "tfidf.pkl")
REPORT_DIR = os.path.join(BACKEND, "evaluation", "reports")
QUERY_JUDGMENTS = os.path.join(DATA_DIR, "judgments_queries.csv")
SEED_JUDGMENTS = os.path.join(DATA_DIR, "judgments_seeds.csv")
K = 5
# MMR exactly as production applies it (infrastructure/ml/recommender.py: DIVERSITY_LAMBDA on
# max-normalised relevance), so fusion_* rows measure the shipped ranking.
PROD_MMR = dict(lam=0.85, normalize=True)


# ── TF-IDF variants under test ───────────────────────────────────────────────


def _fold_clean(text) -> str:
    """Candidate replacement for clean_text: strips HTML, case- and accent-folds (é→e, ş→s),
    keeps letters/digits of every script instead of deleting all non-ASCII characters."""
    if not isinstance(text, str):
        return ""
    return _fold(re.sub(r"<[^>]+>", " ", text))


def _unicode_clean(text) -> str:
    """Keeps non-ASCII letters but does not fold accents (control for _fold_clean)."""
    if not isinstance(text, str):
        return ""
    return " ".join(re.sub(r"[\W_]+", " ", re.sub(r"<[^>]+>", " ", text.lower())).split())


def _combine_with(clean: Callable[[str], str]):
    def combine(row) -> str:
        t, a, c, d = (clean(str(row.get(f, ""))) for f in ("title", "authors", "categories", "description"))
        return f"{t} {t} {t} {c} {c} {a} {d}".strip()
    return combine


# name -> (query/document cleaner, TfidfVectorizer params). One change at a time from the
# production recipe, then the combination, so each effect can be attributed.
_BASE = dict(stop_words="english", max_df=0.8, ngram_range=(1, 2))
TFIDF_VARIANTS = {
    "tfidf_refit": (clean_text, dict(min_df=5, max_features=10000)),
    "tfidf_fold": (_fold_clean, dict(min_df=5, max_features=10000)),
    "tfidf_mindf2": (_fold_clean, dict(min_df=2, max_features=None)),
    "tfidf_sublinear": (_fold_clean, dict(min_df=5, max_features=10000, sublinear_tf=True)),
    "tfidf_rare": (_fold_clean, dict(min_df=2, max_features=None, sublinear_tf=True)),
    "tfidf_rare_ascii": (clean_text, dict(min_df=2, max_features=None, sublinear_tf=True)),
    "tfidf_rare_nofold": (_unicode_clean, dict(min_df=2, max_features=None, sublinear_tf=True)),
}
QUERY_CLEANERS = {"tfidf_pickle": clean_text, **{k: v[0] for k, v in TFIDF_VARIANTS.items()}}


def build_tfidf_variants(catalog: Catalog) -> Dict[str, TfidfIndex]:
    variants = {"tfidf_pickle": production_tfidf(MODEL_PATH)}
    for name, (clean, params) in TFIDF_VARIANTS.items():
        combine = build_combined_features if clean is clean_text else _combine_with(clean)
        variants[name] = fit_tfidf(name, catalog, combine, **params, **_BASE)
    return variants


# ── Systems ──────────────────────────────────────────────────────────────────


class Systems:
    def __init__(self, catalog: Catalog, book_emb: Optional[EmbeddingIndex],
                 query_embs: Dict[str, Dict[str, np.ndarray]]):
        self.cat = catalog
        self.tfidf = build_tfidf_variants(catalog)
        self.emb = book_emb
        self.query_embs = query_embs
        self.pop = catalog.popularity()
        from backend.infrastructure.ml.recommender import BookRecommender
        self.prod = BookRecommender()
        self.prod.load_model(MODEL_PATH)
        ref = self.tfidf["tfidf_rare"]
        self._ref_rows = [ref.row_of[i] for i in catalog.isbns]
        self._ref = ref

    # similarity helpers on catalog rows
    def tfidf_sim(self, name: str) -> Callable[[int, List[int]], float]:
        idx = self.tfidf[name]
        rows = np.array([idx.row_of.get(i, -1) for i in self.cat.isbns])

        def sim(r: int, selected: List[int]) -> float:
            sel = [rows[s] for s in selected if rows[s] >= 0]
            if rows[r] < 0 or not sel:
                return 0.0
            return float(cosine_similarity(idx.matrix[rows[r]], idx.matrix[sel]).max())
        return sim

    def emb_sim(self) -> Callable[[int, List[int]], float]:
        rows = np.array([self.emb.row_of.get(i, -1) for i in self.cat.isbns])

        def sim(r: int, selected: List[int]) -> float:
            sel = [rows[s] for s in selected if rows[s] >= 0]
            if rows[r] < 0 or not sel:
                return 0.0
            return float((self.emb.vectors[sel] @ self.emb.vectors[rows[r]]).max())
        return sim

    def _tfidf_query(self, name: str, text: str) -> np.ndarray:
        idx = self.tfidf[name]
        return scores_on_catalog(self.cat, idx.isbns, idx.query_scores(QUERY_CLEANERS[name](text)))

    def _tfidf_item(self, name: str, isbn: str) -> np.ndarray:
        idx = self.tfidf[name]
        s = idx.item_scores(isbn)
        return np.zeros(len(self.cat.isbns)) if s is None else scores_on_catalog(self.cat, idx.isbns, s)

    def _semantic_top100(self, vector) -> np.ndarray:
        """What match_*_embeddings returns: top-100 similarities, zero elsewhere."""
        full = scores_on_catalog(self.cat, self.emb.isbns, self.emb.scores(vector))
        out = np.zeros_like(full)
        top = np.argsort(-full)[:100]
        out[top] = full[top]
        return out

    # ---- Task 1 ----
    def query_systems(self, topic: dict) -> Dict[str, List[str]]:
        text = topic["text"]
        out = {name: top_k(self.cat, self._tfidf_query(name, text), K)
               for name in self.tfidf}
        for fmt, vecs in self.query_embs.items():
            if self.emb is None or topic["id"] not in vecs:
                continue
            qv = vecs[topic["id"]]
            out[f"emb_exact[{fmt}]"] = top_k(
                self.cat, scores_on_catalog(self.cat, self.emb.isbns, self.emb.scores(qv)), K)
            out[f"rag_retrieval[{fmt}]"] = self._rag_retrieval(qv)
        return out

    def _rag_retrieval(self, qvec) -> List[str]:
        """ProcessRagQueryUseCase retrieval stage, anonymous user, LLM never called."""
        from unittest.mock import MagicMock

        from backend.application.use_cases.ai_rag import ProcessRagQueryUseCase
        sem = self._semantic_top100(qvec)
        port = MagicMock()
        port.match_query_embeddings.return_value = {
            self.cat.isbns[r]: float(sem[r]) for r in np.nonzero(sem)[0]}
        enrich = MagicMock()
        enrich.enrich.side_effect = lambda books: books
        uc = ProcessRagQueryUseCase(MagicMock(), port, None, self.prod, enrich, MagicMock())
        books = uc._retrieve_books_by_embedding(list(qvec), top_k=K)
        return [str(b["isbn13"]) for b in books]

    # ---- Task 2 ----
    def seed_systems(self, topic: dict) -> Dict[str, List[str]]:
        seed = topic["seed_isbn"]
        seed_work = self.cat.work_of[seed]
        ex = [seed_work]
        out: Dict[str, List[str]] = {}
        # Production "similar books" path, exactly as GetRecommendationsUseCase calls it.
        out["prod_similar"] = [str(r["isbn13"]) for r in self.prod.recommend([seed], top_n=K, use_diversity=True)]
        out["prod_similar_no_mmr"] = [
            str(r["isbn13"]) for r in self.prod.recommend([seed], top_n=K, use_diversity=False)]
        for name in self.tfidf:
            out[f"{name}_raw"] = top_k(self.cat, self._tfidf_item(name, seed), K, ex)
        rare = self._tfidf_item("tfidf_rare", seed)
        rare_sim = self.tfidf_sim("tfidf_rare")
        out["tfidf_rare+pop"] = top_k(self.cat, 0.6 * rare + 0.25 * self.pop, K, ex)
        out["tfidf_rare+pop+mmr0.6"] = mmr(self.cat, 0.6 * rare + 0.25 * self.pop, K, rare_sim, exclude_works=ex)
        out["tfidf_rare+pop+mmr_norm0.85"] = mmr(self.cat, 0.6 * rare + 0.25 * self.pop, K, rare_sim,
                                                 lam=0.85, normalize=True, exclude_works=ex)
        boosted = rare * (1.0 + 0.5 * self.pop)  # popularity can reorder, never promote, irrelevant books
        out["tfidf_rare*pop"] = top_k(self.cat, boosted, K, ex)
        out["tfidf_rare*pop+mmr_norm0.85"] = mmr(self.cat, boosted, K, rare_sim, lam=0.85, normalize=True,
                                                 exclude_works=ex)
        out["tfidf_rare+mmr_norm0.7"] = mmr(self.cat, rare, K, rare_sim, lam=0.7, normalize=True, exclude_works=ex)
        out["tfidf_rare+mmr_norm0.85"] = mmr(self.cat, rare, K, rare_sim, lam=0.85, normalize=True, exclude_works=ex)
        if self.emb is not None and seed in self.emb.row_of:
            centroid = self.emb.centroid([seed])
            full = scores_on_catalog(self.cat, self.emb.isbns, self.emb.scores(centroid))
            sem = self._semantic_top100(centroid)
            tf = self._tfidf_item("tfidf_pickle", seed)
            out["emb_raw"] = top_k(self.cat, full, K, ex)
            prod_fusion = 0.3 * tf + 0.5 * sem + 0.2 * self.pop
            out["fusion_prod"] = mmr(self.cat, prod_fusion, K, self.tfidf_sim("tfidf_pickle"), **PROD_MMR, exclude_works=ex)
            out["fusion_no_mmr"] = top_k(self.cat, prod_fusion, K, ex)
            out["fusion_no_tfidf"] = mmr(self.cat, 0.5 * sem + 0.2 * self.pop, K,
                                         self.tfidf_sim("tfidf_pickle"), **PROD_MMR, exclude_works=ex)
            out["fusion_no_emb"] = mmr(self.cat, 0.6 * tf + 0.25 * self.pop, K,
                                       self.tfidf_sim("tfidf_pickle"), **PROD_MMR, exclude_works=ex)
            out["fusion_mmr_emb"] = mmr(self.cat, prod_fusion, K, self.emb_sim(), **PROD_MMR, exclude_works=ex)
            out["fusion_no_pop"] = mmr(self.cat, 0.3 * tf + 0.5 * sem, K,
                                       self.tfidf_sim("tfidf_pickle"), **PROD_MMR, exclude_works=ex)
        return out

    # ---- diversity references ----
    def category_distance(self, a: str, b: str) -> float:
        ca = set(_fold(self.cat.book(a)["categories"]).split())
        cb = set(_fold(self.cat.book(b)["categories"]).split())
        if not ca and not cb:
            return 0.0
        return 1.0 - len(ca & cb) / float(len(ca | cb))

    def content_distance(self, a: str, b: str) -> float:
        """Fixed reference representation (tfidf_rare) so ILD is comparable across systems."""
        m = self._ref.matrix
        return 1.0 - float(cosine_similarity(m[self._ref.row_of[a]], m[self._ref.row_of[b]])[0, 0])

    def first_author(self, isbn: str) -> str:
        return self.cat.work_of[isbn].split("|")[-1]


# ── Evaluation ───────────────────────────────────────────────────────────────


def _mean(xs: List[float]) -> Optional[float]:
    return round(statistics.fmean(xs), 4) if xs else None


def evaluate_task(task: str, topics: List[dict], runs: Dict[str, Dict[str, List[str]]],
                  judgments: Dict[str, Dict[str, int]], systems: Systems) -> dict:
    cat = systems.cat
    per_system: Dict[str, dict] = {}
    names = sorted({n for r in runs.values() for n in r})
    for name in names:
        rows = []
        all_works = set()
        for t in topics:
            ranked_isbns = runs[t["id"]].get(name)
            if ranked_isbns is None:
                continue
            ranked = cat.works(ranked_isbns)
            all_works.update(ranked)
            grades = dict(judgments.get(t["id"], {}))
            for target in t.get("target_isbns", []):
                grades[cat.work_of[target]] = 2
            row = {
                "topic": t["id"], "lang": t.get("lang", "en"), "category": t.get("category", "seed"),
                "returned": len(ranked_isbns),
                "p@5": graded_precision_at_k(ranked, grades, K),
                "p@5_high": graded_precision_at_k(ranked, grades, K, min_grade=2),
                "ndcg@5": graded_ndcg_at_k(ranked, grades, K),
                "mrr": mean_reciprocal_rank(ranked, grades, K),
                "judged@5": judged_at_k(ranked, grades, K),
                "ild_category@5": intra_list_distance(ranked_isbns, systems.category_distance, K),
                "ild_content@5": intra_list_distance(ranked_isbns, systems.content_distance, K),
                "distinct_authors@5": len({systems.first_author(i) for i in ranked_isbns[:K]}) / float(K),
            }
            if t.get("category") == "known_item":
                target_grades = {cat.work_of[x]: 2 for x in t["target_isbns"]}
                row["recall@5"] = graded_recall_at_k(ranked, target_grades, K)
            if "seed_isbn" in t:
                seed_author = systems.first_author(t["seed_isbn"])
                row["same_author@5"] = sum(
                    1 for i in ranked_isbns[:K] if systems.first_author(i) == seed_author) / float(K)
            rows.append(row)
        metrics = [k for k in rows[0] if k not in ("topic", "lang", "category", "returned")] if rows else []

        def summarize(subset):
            return {m: _mean([r[m] for r in subset if m in r]) for m in metrics} | {"n": len(subset)}

        groups = defaultdict(list)
        for r in rows:
            groups[f"lang={r['lang']}"].append(r)
            groups[f"category={r['category']}"].append(r)
            groups[f"split={topic_split(r['topic'])}"].append(r)
        per_system[name] = {
            "overall": summarize(rows),
            "breakdown": {g: summarize(v) for g, v in sorted(groups.items())},
            "coverage": round(len(all_works) / float(cat.n_works), 4),
            "per_topic": rows,
        }
    return {"task": task, "k": K, "systems": per_system}


def load_query_embeddings(paths: List[str]) -> Dict[str, Dict[str, np.ndarray]]:
    out = {}
    for p in paths:
        data = np.load(p, allow_pickle=False)
        fmt = str(data["format"]) if "format" in data else os.path.basename(p)
        out[fmt] = {tid: vec for tid, vec in zip(data["topic_ids"].tolist(), data["vectors"])}
    return out


def run_all(systems: Systems):
    queries, seeds = load_topics("queries.json"), load_topics("seeds.json")
    q_runs = {t["id"]: systems.query_systems(t) for t in queries}
    s_runs = {t["id"]: systems.seed_systems(t) for t in seeds}
    return queries, seeds, q_runs, s_runs


def catalog_consistency(catalog: Catalog, prod) -> dict:
    """CSV snapshot vs the production TF-IDF artifact: every snapshot ISBN must resolve to a row."""
    unresolved = [i for i in catalog.isbns if not prod.engine.find_all_indices(i)]
    return {
        "csv_isbns": len(catalog.isbns), "csv_works": catalog.n_works, "model_rows": len(prod.df),
        "model_version": prod.config.model_version, "csv_isbns_unresolvable_in_model": len(unresolved),
        "unresolvable_examples": unresolved[:10],
    }


def _markdown(report: dict) -> str:
    c = report["catalog_consistency"]
    lines = ["# Libris offline retrieval evaluation", "", report["provenance"], ""]
    lines += _provenance_markdown(report)
    lines += ["",
             f"Catalog consistency: {c['csv_isbns']} snapshot ISBNs / {c['csv_works']} works; production model "
             f"v{c['model_version']} has {c['model_rows']} rows; {c['csv_isbns_unresolvable_in_model']} snapshot "
             "ISBNs cannot be resolved by the model.", ""]
    for task in ("query_to_item", "seed_to_item"):
        res = report[task]
        lines += [f"## {task} (k={res['k']})", "",
                  "| system | n | P@5 | P@5 (grade 2) | nDCG@5 | MRR | Recall@5 (known-item) | judged@5 | ILD cat | ILD content | distinct authors | coverage |",
                  "|---|---|---|---|---|---|---|---|---|---|---|---|"]
        for name, s in res["systems"].items():
            o = s["overall"]
            ki = s["breakdown"].get("category=known_item", {}).get("recall@5")
            lines.append(
                f"| {name} | {o['n']} | {o['p@5']} | {o['p@5_high']} | {o['ndcg@5']} | {o['mrr']} | "
                f"{ki if ki is not None else '-'} | {o['judged@5']} | {o['ild_category@5']} | "
                f"{o['ild_content@5']} | {o['distinct_authors@5']} | {s['coverage']} |")
        lines += ["", "### Breakdown (nDCG@5)", ""]
        groups = sorted({g for s in res["systems"].values() for g in s["breakdown"]})
        lines += ["| system | " + " | ".join(groups) + " |", "|---|" + "---|" * len(groups)]
        for name, s in res["systems"].items():
            lines.append(f"| {name} | " + " | ".join(
                str(s["breakdown"].get(g, {}).get("ndcg@5", "-")) for g in groups) + " |")
        lines.append("")
    if report.get("not_executed"):
        lines += ["## Not executed", ""] + [f"- {x}" for x in report["not_executed"]]
    return "\n".join(lines) + "\n"


def _provenance_markdown(report: dict) -> List[str]:
    lines = ["## Label provenance", "",
             "| judgments | graded | human-reviewed | unreviewed | labelers |", "|---|---|---|---|---|"]
    for name, p in report["judgments"].items():
        labelers = ", ".join(f"{k}: {v}" for k, v in p["by_labeler"].items())
        lines.append(f"| {name} | {p['graded_rows']} | {p['human_reviewed_rows']} | {p['unreviewed_rows']} | {labelers} |")
    lines += ["", report["validity"], ""]
    return lines


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("mode", choices=["pool", "evaluate"])
    ap.add_argument("--book-embeddings")
    ap.add_argument("--query-embeddings", nargs="*", default=[])
    ap.add_argument("--report-dir", default=REPORT_DIR, help="where evaluate writes its report")
    ap.add_argument("--reviewed-only", action="store_true",
                    help="score with human-reviewed judgments only (rows with reviewed_by set)")
    args = ap.parse_args(argv)
    provenance = {"queries": judgment_provenance(QUERY_JUDGMENTS), "seeds": judgment_provenance(SEED_JUDGMENTS)}
    if args.mode == "evaluate" and args.reviewed_only and not any(
            p["human_reviewed_rows"] for p in provenance.values()):
        print("No human-reviewed judgments yet (reviewed_by is empty on every row); nothing to score.")
        return

    catalog = Catalog()
    book_emb = EmbeddingIndex.load(args.book_embeddings) if args.book_embeddings else None
    systems = Systems(catalog, book_emb, load_query_embeddings(args.query_embeddings))
    queries, seeds, q_runs, s_runs = run_all(systems)

    if args.mode == "pool":
        pooled_q = {tid: sorted({i for r in runs.values() for i in r}) for tid, runs in q_runs.items()}
        pooled_s = {tid: sorted({i for r in runs.values() for i in r}) for tid, runs in s_runs.items()}
        aq = write_pool(QUERY_JUDGMENTS, "query", queries, pooled_q, catalog)
        as_ = write_pool(SEED_JUDGMENTS, "seed", seeds, pooled_s, catalog)
        print(f"pooled: {aq} new query candidates, {as_} new seed candidates (grade column blank = unjudged)")
        return

    not_executed = []
    if book_emb is None:
        not_executed.append("All embedding systems (emb_exact, rag_retrieval, fusion_*): no --book-embeddings snapshot "
                            "was available (no Gemini key / database credentials in this environment).")
    reviewed = args.reviewed_only
    report = {
        "judgments": provenance,
        "labels_used": "human-reviewed only" if reviewed else "all graded rows (provisional labels included)",
        "validity": (
            "Scores computed on human-reviewed judgments only." if reviewed else
            "NOT independently validated: these labels are provisional (unreviewed LLM grades), and "
            "the shipped TF-IDF/MMR settings were chosen by comparing systems on these same labels "
            "and topics. Treat differences as directional evidence, not as measured improvements. "
            "The split=heldout breakdown is reserved for future tuning; it was not held out from "
            "the tuning done so far."),
        "provenance": (
            f"Catalog snapshot: backend/data/books.csv ({len(catalog.isbns)} ISBNs, {catalog.n_works} works). "
            "Judgments: evaluation/data/judgments_*.csv - see the labeler column; rows labelled "
            "'llm:*' with an empty reviewed_by are provisional and NOT human-verified ground truth."),
        "query_to_item": evaluate_task("query_to_item", queries, q_runs,
                                       load_judgments(QUERY_JUDGMENTS, reviewed_only=reviewed), systems),
        "seed_to_item": evaluate_task("seed_to_item", seeds, s_runs,
                                      load_judgments(SEED_JUDGMENTS, reviewed_only=reviewed), systems),
        "embedding_model": book_emb.model_version if book_emb else None,
        "catalog_consistency": catalog_consistency(catalog, systems.prod),
        "not_executed": not_executed,
    }
    os.makedirs(args.report_dir, exist_ok=True)
    stem = "retrieval_evaluation_reviewed" if reviewed else "retrieval_evaluation"
    with open(os.path.join(args.report_dir, f"{stem}.json"), "w", encoding="utf-8") as f:
        json.dump(report, f, indent=1, ensure_ascii=False)
    with open(os.path.join(args.report_dir, f"{stem}.md"), "w", encoding="utf-8") as f:
        f.write(_markdown(report))
    print(_markdown(report))


if __name__ == "__main__":
    main()
