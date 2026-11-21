# Real-world retrieval & RAG quality audit (2026-11-20)

Branch `ai-subsystem-audit`, uncommitted working tree on top of `23760c6`. Machine-readable results:
[real_retrieval_audit.json](real_retrieval_audit.json) (retrieval/recommendation metrics, per topic) and
[pgvector_live_benchmark.json](pgvector_live_benchmark.json) (live database). Reproduce with
`python -m backend.scripts.run_real_retrieval_audit seeds|queries` and
`python -m backend.scripts.benchmark_pgvector_live`.

## 0. What could and could not be run

| Resource | State | Consequence |
|---|---|---|
| Live PostgreSQL (Supabase pooler) | **Works**, read-only access used. PG 17.11, pgvector 0.8.0 | Real pgvector benchmark, EXPLAIN ANALYZE, production RPC latency |
| Stored embeddings | **6,446 / 6,446**, all `models/gemini-embedding-2`, 3072-d, content hashes match, no orphans | Seed→item evaluation on the real vectors |
| Gemini API (`GEMINI_API_KEY`, `LLM_API_KEY` in `.env`) | **Both rejected**: HTTP 400 `API key not valid` (`models.list` and `embedContent`) | No query embeddings, no LLM answers, the embedding-profile probe could not run |

Nothing was written to the database. No embeddings were regenerated. Judgment CSVs are byte-identical to
before the audit (no new labels were added).

**Label provenance.** All 1,184 graded judgments are provisional LLM labels (`llm:claude-opus-5-5`),
**0 human-reviewed**. Every quality number below rests on them, and the TF-IDF/MMR settings were tuned on
the same labels. Numbers that do **not** depend on LLM labels: known-item recall (hand-defined targets),
empty-result rates, status/degradation behaviour, all latency and pgvector numbers.

## 1. End-to-end flow (as implemented)

```
query ─► deterministic intents (clock, action, auth guard) ─► query cache
      ─► catalog dispatch (title/author/ISBN word-boundary match; existence/rating/author answered without LLM)
      ─► EmbeddingService.embed_query  (profile check, Gemini embedContent)
      ─► match_query_embeddings RPC (top 100, HNSW halfvec cosine)
      ─► BookRecommender.recommend(semantic_scores=…): 0.5·cosine + 0.2·popularity (+0.3·TF-IDF only for
         "similar to X" seeds), TF-IDF MMR λ=0.85 ─► exclusions/dedup ─► top 5
      ─► context (title, authors, ISBN, rating, description ≤1500 chars) ─► Gemini JSON answer
on failure: embedding/vector error ─► lexical TF-IDF fallback (English only) or seed TF-IDF; status = degraded mode
```

There is **no lexical/semantic fusion for free-text queries in production**: lexical is a fallback only.
There is **no reranker**. "Hybrid with reranking" therefore has nothing to evaluate.

### Query embedding profile (`query_format: legacy`, `query_task_type: RETRIEVAL_DOCUMENT`)

This is deliberate, not a mismatch. Proven from code and data:

- The stored rows' `model_version` is the bare `models/gemini-embedding-2` (6,446 rows). They were written by
  commit `23760c6`, whose `GeminiRestClient.embed` **always sent `taskType=RETRIEVAL_DOCUMENT`**
  (`git show 23760c6:backend/infrastructure/llm/gemini_rest.py`), and the old RAG embedded queries through
  the same call. `legacy` reproduces exactly that request for queries.
- Whether gemini-embedding-2 honours `taskType` at all is unverified. If it does, `legacy` is symmetric with
  the documents. If it ignores it, `legacy` equals `raw`. In both cases it is the only setting known to
  match the stored vectors. The asymmetric alternatives (`search_result`, `retrieval_query`) may retrieve
  better but are **unmeasured**.
- Settling it takes one script once a valid key exists: re-embed stored books' canonical text with and
  without `taskType` and compare with the stored vector (cosine ≈ 1.0 identifies the request). The probe
  was written and run. It failed only on the API key.

The profile was **not changed**.

## 2. Retrieval quality

### 2a. Query → item (72 queries: 30 EN / 24 TR / 18 DE)

| System | nDCG@5 | nDCG@10 | P@5 | MRR@10 | pooled R@5 | pooled R@10 | known-item R@5 / R@10 | empty | latency p50 / p95 / p99 |
|---|---|---|---|---|---|---|---|---|---|
| **Production RAG, live today** (Gemini failing → fallback) | 0.334 | 0.317 | 0.261 | 0.344 | 0.406 | 0.406 | 0.250 / 0.250 | **55.6%** | 115 / 177 / 533 ms |
| Pure lexical (production TF-IDF `lexical_search`) | 0.471 | 0.508 | 0.369 | 0.502 | 0.577 | 0.719 | 0.292 / 0.292 | 11.1% | 11 / 20 / 36 ms |
| Pure semantic | not executed (no query embeddings) | | | | | | | | |
| Hybrid (RRF semantic + lexical) | not executed | | | | | | | | |
| Production with working Gemini | not executed | | | | | | | | |

Per language (nDCG@5 / empty rate):

| | EN | TR | DE |
|---|---|---|---|
| Production RAG, live | 0.734 / 0% | **0.000 / 100%** | 0.111 / 89% |
| Lexical TF-IDF | 0.734 / 0% | 0.239 / 17% | 0.341 / 22% |

- **Every one of the 72 requests was degraded** (40 `embedding_failed`, 32 `lexical_fallback` →
  `llm_fallback`). **None was reported as `success`**, and none was cached. The degraded labelling works
  under a real outage.
- Turkish and German users currently get "search unavailable" for every free-text query. That follows the
  design rule "lexical fallback is English-only". Lexical would return *something* for TR/DE
  (nDCG@5 0.24/0.34), but the lists are weak. Keeping them suppressed is a product decision; it was not changed.
- `pooled_recall` uses the union of judged-relevant works as the relevant set, so it is an upper bound.
  Production returns at most 5 books, so its @10 metrics are computed on ≤5 items.

### 2b. Seed → item on the REAL stored embeddings (50 seeds)

| System | nDCG@5 | judged-only nDCG@5 | nDCG@10 | P@5 | MRR@10 | pooled R@10 | judged@5 | popularity pct@10 | category overlap@10 | same author@10 | latency p50 / p95 / p99 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Production similar-books (TF-IDF+pop+MMR) | 0.570 | 0.570 | 0.635 | 0.576 | 0.735 | 0.739 | 1.00 | 0.770 | 0.702 | 0.382 | 178 / 234 / 287 ms (was 1,272 / 1,512 / 2,008) |
| Pure lexical (TF-IDF cosine) | 0.581 | 0.581 | 0.629 | 0.588 | 0.737 | 0.741 | 1.00 | 0.566 | 0.688 | 0.400 | <1 ms |
| Pure semantic (exact cosine, Gemini vectors) | 0.478 | 0.611 | 0.514 | 0.412 | 0.682 | 0.488 | 0.51 | 0.688 | 0.640 | 0.444 | <1 ms |
| Production personalised *if* `match_book_embeddings` existed (0.3 tfidf + 0.5 sem + 0.2 pop, MMR) | 0.575 | 0.634 | 0.601 | 0.516 | 0.773 | 0.594 | 0.72 | **0.844** | 0.732 | 0.386 | 406 / 548 / 703 ms |
| **Hybrid RRF (lexical + semantic, k=60, no pop/MMR)** | **0.623** | **0.702** | **0.671** | 0.552 | **0.791** | 0.684 | 0.71 | 0.655 | 0.678 | 0.504 | <1 ms |
| Experiment: production fusion, semantic min-max rescaled | 0.549 | 0.635 | 0.578 | 0.480 | 0.747 | 0.562 | 0.61 | 0.766 | 0.686 | 0.460 | 409 ms |

Empty-result rate 0%, duplicate works 0, and seed-edition leaks 0 for every system.

How to read this:

- Unjudged results count as irrelevant in plain nDCG, which *penalises* systems that surface new books.
  Judged-only (condensed) nDCG drops them, which *favours* them. The truth lies between. Hybrid RRF leads on
  both, and on nDCG@10 and MRR, despite the bias against it. It is the strongest signal in this audit,
  but it is still on unreviewed LLM labels from a single run. **It was not shipped.**
- Pure semantic alone is worse than TF-IDF on the lower bound (0.48 vs 0.58), and only 51% of its top 5 is
  judged. Higher cosine is not better recommendations here.
- **Popularity bias.** Within the semantic top 100, the weighted semantic term spans ≈0.048 and the
  popularity term ≈0.047 (cosine top-1 ≈0.85, rank-100 ≈0.75, unrelated pairs average 0.68). Popularity
  therefore carries as much weight as relevance. The personalised-with-RPC path recommends books at the
  **84th popularity percentile** on average, against 57 for lexical and 66 for RRF. Rescaling the semantic
  scores did not help (0.549), so it was not shipped.

## 3. Live pgvector performance (real vectors, read-only)

Index: `hnsw ((embedding::halfvec(3072)) halfvec_cosine_ops)`, 50 MB, default parameters (m=16,
ef_construction=64). Server defaults: `hnsw.ef_search=40`, `hnsw.iterative_scan=off`. The planner **does
use the HNSW index** for the RPC's query (EXPLAIN ANALYZE in the JSON). 120 probes: 60 stored book vectors
and 60 two-book means. These are not real user-query embeddings.

| Setting (SET LOCAL, one transaction) | rows for LIMIT 100 | recall@5 | recall@10 | recall@100 | latency p50 / p95 / p99 |
|---|---|---|---|---|---|
| **Default, ef_search=40 (production)** | **40** (min 40) | 0.983 | 0.984 | **0.40** | 250 / 629 / 816 ms* |
| ef_search=100 | 100 | 0.997 | 0.996 | 0.975 | 113 / 214 / 342 ms |
| ef_search=200 | 100 | 1.000 | 0.998 | 0.994 | 106 / 141 / 175 ms |
| ef_search=40 + iterative_scan=relaxed_order | 100 | 0.983 | 0.984 | 0.982 | 93 / 137 / 165 ms |
| Exact (index disabled) | 100 | 1.000 | 0.999 | 1.000 | 297 / 325 / 353 ms |

\* first configuration measured, so it includes cache warm-up; the configurations are not interleaved.

- **Confirmed: asking for 100 rows returns exactly 40.** RAG and personalised fusion silently worked on
  40 candidates.
- The production RPC call through `PostgresBookDataPort` (pooler round trip plus a 3072-float literal)
  takes 349 / 416 / 525 ms p50/p95/p99. In an interleaved A/B, ef_search=40 measured 410 / 484 / 526 ms
  and ef_search=200 measured 448 / 533 / 787 ms. The fix costs about 40 ms p50 for 2.5× the candidates.
  Most of the RPC time is transport, not search.
- **`public.match_book_embeddings` does not exist in the live database** (migration 05 never applied).
  Personalised recommendations can never use embeddings in production today. The learning-notes tables
  (migrations 09/10: `user_notes`, `note_reviews`, `review_items`, `review_attempts`) are missing too.

## 4. RAG

| Aspect | Finding | Evidence |
|---|---|---|
| Retrieval vs generation failures | Kept separate: `metrics.retrieval_mode` / `degraded` / `degraded_reason` describe retrieval, `status=llm_fallback` describes generation | Live run: 32 answers `status=llm_fallback` with `retrieval_mode=lexical_fallback`, `degraded=true` |
| Degraded reported as success | **No** for RAG (0/72 under a real outage). **Yes** for personalised recommendations: **fixed** | §5 fix 2 |
| Fallback when vector search fails | Grounded deterministic answer listing retrieved catalog books; never cached | Live run + `test_rag_degraded_status.py` |
| Context construction | Top 5 books, sanitised, descriptions truncated to 1,500 chars, ISBN-keyed explanations accepted only for books in the context | code review of `_build_context` / explanation filter |
| Answer relevance, faithfulness, hallucinations | **Not measured**: the LLM could not be called | Gemini 400 |
| Context precision (proxy) | For live production answers, P@5 of the context books = 0.261 overall and 0.734 nDCG@5 for EN; TR/DE contexts empty | §2a |

## 5. Fixes (each from a measurement or code inspection) and tests

| # | Fix | Evidence before → after | Tests |
|---|---|---|---|
| 1 | `PostgresBookDataPort._vector_query` sets `hnsw.ef_search = max(40, min(1000, 2·limit))` with `set_config(..., true)` (transaction-local; no server setting changes) | Live: 40 → **100** rows for LIMIT 100, recall@100 0.40 → **0.991**; server `ef_search` still 40 afterwards | `test_vector_adapter_validation.py` (+5) |
| 2 | Personalised recommendations report `retrieval_mode` (`hybrid_semantic` / `tfidf_fallback` / `tfidf_no_semantic_matches` / `tfidf`), `degraded`, and `fallback_reason="semantic_unavailable"` when the vector RPC fails | Before: missing RPC → `fallback_reason: None` on every request | `test_personalized_degraded_status.py` (4) |
| 3 | MMR precomputes the candidate×candidate TF-IDF similarity once instead of ~1,000 sparse cosine calls | Similar-books p50 **1,272 → 152–178 ms** (≈7–8×); personalised-with-semantic 1,469 → 406 ms; all seed metrics identical | `test_mmr_precomputed_equivalence.py` (22: identical ISBNs and penalties vs the original algorithm on the real model) |

Full backend suite: **848 passed**, 0 failed (817 before).

Not fixed, deliberately:
- Fusion weights and the RRF result: the evidence is directional on unreviewed labels.
- The query embedding format: unmeasurable without a key.
- TR/DE lexical fallback: a product decision.
- The Supabase REST path: PostgREST RPCs cannot `SET LOCAL`. If production uses `SupabaseBookDataPort`
  instead of a DB URL, the 40-row cap remains until the function gets
  `ALTER FUNCTION public.match_query_embeddings(vector, float8, int) SET hnsw.ef_search = 200`.
  That is a manual migration, not applied.

## 6. Prioritised remaining issues

1. **Gemini credentials invalid** (P0). If the deployed key matches `.env`, production RAG is 100%
   degraded and TR/DE get no results. Replace the key, then run `export_embedding_snapshot queries` for
   all 4 formats and `run_real_retrieval_audit queries --query-embeddings …` to fill the not-executed rows.
2. **Apply migration 05** (`match_book_embeddings`) and, on the Supabase-RPC path, the `ef_search`
   function setting (P1). Personalised semantic retrieval is dead in production today.
3. **Human-review the judgments, then decide on hybrid RRF and popularity weighting** (P1). RRF is the best
   seed system on every rank metric here. Popularity weighting (84th percentile) needs a calibrated design.
4. Embedding-profile probe once a key exists (P2). Determines whether `taskType` matters for
   gemini-embedding-2 and whether `search_result` queries beat `legacy`.
5. RAG generation evaluation (faithfulness, unsupported claims, answer relevance) on ~30 representative
   questions once the LLM is reachable (P2).
6. Missing learning-notes tables in the live DB (migrations 09/10) (P2, outside retrieval but observed).
7. Personalised recommendations dedupe and exclude by lower-cased title (`seen_titles`), which drops
   distinct books that share a title (22 shared titles in the catalog) (P3).
