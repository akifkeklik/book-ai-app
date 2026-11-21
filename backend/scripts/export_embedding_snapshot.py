"""
Export what the offline evaluation needs from live infrastructure, once, so benchmark runs are
reproducible and never call Gemini or the database again.

  books    Read-only export of public.book_embeddings -> evaluation/cache/book_embeddings.npz,
           plus a catalog/embedding consistency report (missing, orphaned, stale, mixed models).
           Needs SUPABASE_DB_URL or DATABASE_URL. Never writes to the database.

  queries  Embed the evaluation queries -> evaluation/cache/query_embeddings_<format>.npz using
           the production EmbeddingService.embed_query (so the task-type contract under test is
           the real one). Needs GEMINI_API_KEY; resumable, already-cached topics are skipped.
           --format legacy           production default: raw text with the document taskType
                                     (the way the stored vectors were requested)
           --format raw              raw text, no taskType
           --format search_result    Google's documented gemini-embedding-2 query prefix
           --format retrieval_query  taskType=RETRIEVAL_QUERY (gemini-embedding-001 contract)
           Each file records the full query configuration (EmbeddingService.describe()).

Then:  python -m backend.scripts.run_retrieval_evaluation evaluate \\
           --book-embeddings backend/evaluation/cache/book_embeddings.npz \\
           --query-embeddings backend/evaluation/cache/query_embeddings_legacy.npz \\
                              backend/evaluation/cache/query_embeddings_raw.npz \\
                              backend/evaluation/cache/query_embeddings_search_result.npz
"""

import argparse
import json
import os
import sys
from collections import Counter

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from backend.evaluation.retrieval import Catalog, load_topics  # noqa: E402
from backend.utils.preprocess import normalize_isbn  # noqa: E402

CACHE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "evaluation", "cache")


def export_books(db_url: str) -> None:
    import psycopg2
    from backend.services.embedding_service import EmbeddingService

    conn = psycopg2.connect(db_url)
    conn.set_session(readonly=True)
    cur = conn.cursor()
    cur.execute("SELECT book_id, embedding::text, content_hash, model_version FROM public.book_embeddings ORDER BY book_id")
    rows = cur.fetchall()
    cur.execute("SELECT * FROM public.books")
    cols = [d[0] for d in cur.description]
    books = {normalize_isbn(r[cols.index("isbn13")]): dict(zip(cols, r)) for r in cur.fetchall()}
    conn.close()

    isbns = [normalize_isbn(r[0]) for r in rows]
    vectors = np.array([json.loads(r[1]) for r in rows], dtype=np.float32)
    models = Counter(r[3] for r in rows)
    svc = EmbeddingService()
    stale = [normalize_isbn(r[0]) for r in rows
             if normalize_isbn(r[0]) in books
             and svc.generate_content_hash(svc.generate_canonical_text(books[normalize_isbn(r[0])])) != r[2]]
    catalog = Catalog()
    report = {
        "db_books": len(books), "db_embeddings": len(rows),
        "embedding_dimensions": sorted({len(v) for v in vectors}),
        "model_versions": dict(models),
        "embedding_profiles": dict(Counter(svc.normalize_profile(m) for m in models.elements())),
        "configured_document_profile": svc.document_profile(),
        "books_without_embedding": sorted(set(books) - set(isbns)),
        "embeddings_without_book": sorted(set(isbns) - set(books)),
        "stale_embeddings_content_hash_mismatch": stale,
        "db_books_not_in_csv_snapshot": sorted(set(books) - set(catalog.isbns)),
        "csv_snapshot_books_not_in_db": sorted(set(catalog.isbns) - set(books)),
    }
    os.makedirs(CACHE, exist_ok=True)
    np.savez_compressed(os.path.join(CACHE, "book_embeddings.npz"), isbns=np.array(isbns), vectors=vectors,
                        model_version=np.array(",".join(sorted(models))))
    with open(os.path.join(CACHE, "embedding_consistency.json"), "w", encoding="utf-8") as f:
        json.dump(report, f, indent=1)
    print(json.dumps({k: (len(v) if isinstance(v, list) else v) for k, v in report.items()}, indent=1))


def export_queries(fmt: str) -> None:
    os.environ["EMBEDDING_QUERY_FORMAT"] = fmt
    from backend.services.embedding_service import EmbeddingService

    svc = EmbeddingService()
    if not svc.is_configured():
        sys.exit("GEMINI_API_KEY is required")
    path = os.path.join(CACHE, f"query_embeddings_{fmt}.npz")
    cached = {}
    if os.path.exists(path):
        data = np.load(path, allow_pickle=False)
        cached = dict(zip(data["topic_ids"].tolist(), data["vectors"]))
    for t in load_topics("queries.json"):
        if t["id"] in cached:
            continue
        vec = svc.embed_query(t["text"])
        if vec is None:
            print(f"failed: {t['id']} (re-run to resume)")
            continue
        cached[t["id"]] = np.asarray(vec, dtype=np.float32)
    os.makedirs(CACHE, exist_ok=True)
    ids = sorted(cached)
    np.savez_compressed(path, topic_ids=np.array(ids), vectors=np.stack([cached[i] for i in ids]),
                        format=np.array(fmt), model=np.array(svc._model),
                        profile=np.array(json.dumps(svc.describe(), sort_keys=True)))
    print(f"{len(ids)} query embeddings -> {path}")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("books")
    q = sub.add_parser("queries")
    q.add_argument("--format", choices=["legacy", "raw", "search_result", "retrieval_query"], default="legacy")
    args = ap.parse_args(argv)
    if args.cmd == "books":
        url = os.environ.get("SUPABASE_DB_URL") or os.environ.get("DATABASE_URL")
        if not url:
            sys.exit("SUPABASE_DB_URL or DATABASE_URL is required")
        export_books(url)
    else:
        export_queries(args.format)


if __name__ == "__main__":
    main()
