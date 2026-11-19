"""
Exact-vs-approximate check of the pgvector RPCs used by RAG and personalised recommendations.

Applies migrations 03 (book_embeddings + halfvec HNSW index), 05 (match_book_embeddings) and
06 (match_query_embeddings) verbatim to an EMPTY scratch database, loads vectors, then compares
each RPC's answer with brute-force cosine in NumPy: number of rows returned and recall@k.

    DATABASE_URL=postgresql://... python -m backend.scripts.benchmark_vector_rpcs [--snapshot book_embeddings.npz]

Without --snapshot the vectors are SYNTHETIC (TF-IDF -> 256-d SVD -> random rotation to 3072-d):
they have realistic neighbourhood structure but are not Gemini embeddings, so recall numbers
describe the index configuration, not production retrieval quality.

Safety: refuses to run if public.books already exists. Never point it at a real database.
"""

import argparse
import json
import os
import sys

import numpy as np
import psycopg2

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from backend.evaluation.retrieval import Catalog, EmbeddingIndex  # noqa: E402

SCRIPTS = os.path.dirname(os.path.abspath(__file__))
MIGRATIONS = ["03_phase3_embeddings.sql", "05_phase3_performance.sql", "06_phase2_rag.sql"]
DIM = 3072


def synthetic_vectors(catalog: Catalog, seed: int = 7) -> np.ndarray:
    from sklearn.decomposition import TruncatedSVD
    from sklearn.feature_extraction.text import TfidfVectorizer

    docs = (catalog.df["title"] + " " + catalog.df["categories"] + " " + catalog.df["description"]).tolist()
    m = TfidfVectorizer(stop_words="english", min_df=2, sublinear_tf=True).fit_transform(docs)
    low = TruncatedSVD(256, random_state=seed).fit_transform(m)
    rot, _ = np.linalg.qr(np.random.default_rng(seed).standard_normal((DIM, 256)))
    vecs = low @ rot.T
    return (vecs / np.maximum(np.linalg.norm(vecs, axis=1, keepdims=True), 1e-12)).astype(np.float32)


def vec_literal(v) -> str:
    return "[" + ",".join(f"{x:.7f}" for x in v) + "]"


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--snapshot", help="book_embeddings.npz exported from production")
    ap.add_argument("--queries", type=int, default=100, help="number of probe vectors")
    ap.add_argument("--out", default=os.path.join(SCRIPTS, "..", "evaluation", "reports", "vector_rpc_benchmark.json"))
    args = ap.parse_args(argv)

    url = os.environ.get("DATABASE_URL")
    if not url:
        sys.exit("DATABASE_URL must point to an empty scratch database")
    conn = psycopg2.connect(url)
    conn.autocommit = True
    cur = conn.cursor()
    cur.execute("SELECT to_regclass('public.books') IS NOT NULL")
    if cur.fetchone()[0]:
        sys.exit("refusing to run: public.books already exists (this script needs an empty scratch database)")

    catalog = Catalog()
    if args.snapshot:
        snap = EmbeddingIndex.load(args.snapshot)
        isbns, vecs, source = snap.isbns, snap.vectors, f"snapshot:{os.path.basename(args.snapshot)}"
    else:
        isbns, vecs, source = catalog.isbns, synthetic_vectors(catalog), "synthetic (TF-IDF SVD, not Gemini)"

    cur.execute("CREATE EXTENSION IF NOT EXISTS vector")
    cur.execute("SELECT extversion FROM pg_extension WHERE extname = 'vector'")
    pgvector_version = cur.fetchone()[0]
    cur.execute("CREATE TABLE public.books (isbn13 TEXT PRIMARY KEY)")
    cur.executemany("INSERT INTO public.books VALUES (%s)", [(i,) for i in isbns])
    for name in MIGRATIONS:
        cur.execute(open(os.path.join(SCRIPTS, name), encoding="utf-8").read())
    for i in range(0, len(isbns), 500):
        cur.executemany(
            "INSERT INTO public.book_embeddings (book_id, embedding, content_hash, model_version) "
            "VALUES (%s, %s::vector, 'bench', 'bench')",
            [(isbns[j], vec_literal(vecs[j])) for j in range(i, min(i + 500, len(isbns)))])
    cur.execute("ANALYZE public.book_embeddings")

    rng = np.random.default_rng(11)
    probes = rng.choice(len(isbns), size=min(args.queries, len(isbns)), replace=False)
    results = {"vector_source": source, "pgvector": pgvector_version, "rows": len(isbns), "probes": len(probes)}

    def recall(got, exact, k):
        return len(set(got[:k]) & set(exact[:k])) / float(k)

    for rpc in ("match_query_embeddings", "match_book_embeddings"):
        counts, r5, r10, r100 = [], [], [], []
        for p in probes:
            if rpc == "match_query_embeddings":
                q = vecs[p] + 0.05 * rng.standard_normal(DIM).astype(np.float32)  # a query near, not equal to, a book
                cur.execute(f"SELECT book_id FROM {rpc}(%s::vector, 0.0, 100)", (vec_literal(q),))
                exclude = set()
            else:
                q = vecs[p]
                cur.execute(f"SELECT book_id FROM {rpc}(%s, 0.0, 100)", ([isbns[p]],))
                exclude = {isbns[p]}
            got = [r[0] for r in cur.fetchall()]
            sims = vecs @ (q / np.linalg.norm(q))
            exact = [isbns[j] for j in np.argsort(-sims) if isbns[j] not in exclude][:100]
            counts.append(len(got))
            r5.append(recall(got, exact, 5))
            r10.append(recall(got, exact, 10))
            r100.append(len(set(got) & set(exact)) / 100.0)
        cur.execute("SHOW hnsw.ef_search")
        results[rpc] = {
            "requested": 100, "hnsw.ef_search": cur.fetchone()[0],
            "rows_returned_mean": float(np.mean(counts)), "rows_returned_min": int(np.min(counts)),
            "recall@5": round(float(np.mean(r5)), 4), "recall@10": round(float(np.mean(r10)), 4),
            "recall@100_of_requested": round(float(np.mean(r100)), 4),
        }
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(results, f, indent=1)
    print(json.dumps(results, indent=1))


if __name__ == "__main__":
    main()
