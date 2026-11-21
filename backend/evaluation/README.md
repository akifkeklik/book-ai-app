# Retrieval & recommendation evaluation

Offline, reproducible evaluation of how Libris retrieves books for a free-text query (Ask AI /
RAG) and for a seed book ("similar books", personalised recommendations). Everything runs
against one frozen catalog snapshot and makes **no network calls**.

```bash
# from the repo root
python -m backend.scripts.run_retrieval_evaluation evaluate   # -> evaluation/reports/retrieval_evaluation.{md,json}
python -m backend.scripts.run_retrieval_evaluation pool       # append unjudged candidates of new systems for labelling
```

## What is measured

| Task | Topics | Relevance |
|---|---|---|
| Query → item ([data/queries.json](data/queries.json)) | 72 queries: 30 EN / 24 TR / 18 DE; known-item descriptions (24), topic (20), author style (15), mood (13) | Known-item topics have a defined target (all editions); everything else uses pooled graded judgments |
| Seed → item ([data/seeds.json](data/seeds.json)) | 50 widely read seeds across genres | Pooled graded judgments |

Metrics (k = 5, implemented in [metrics.py](metrics.py)): P@5 (grade ≥ 1), P@5 for grade 2,
graded nDCG@5 (gain 2^g − 1), MRR, **Recall@5 only for known-item queries** (the only topics
whose relevant set is complete), `judged@5` (share of the top 5 that has a judgment; low
values mean a metric is unreliable), intra-list diversity on categories and on a fixed TF-IDF
reference representation, distinct first authors, and catalog coverage. Every metric is also
reported per language and per query category.

**Book identity.** Results are compared by *work id* (folded title + first-author surname,
`utils.preprocess.work_id`), so two editions of a book share one judgment. A repeated work in
a ranked list earns no gain after its first occurrence, so duplicate editions cannot inflate
a score.

## Judgments: provenance and limits

Judgments live in [data/judgments_queries.csv](data/judgments_queries.csv) and
[data/judgments_seeds.csv](data/judgments_seeds.csv) (1,184 rows), one row per (topic, work),
built by pooling the top 5 of every evaluated system.

**All current grades are provisional LLM labels** (`labeler = llm:claude-opus-5-5`, empty
`reviewed_by`: 1,184 of 1,184 graded rows, 0 human-reviewed). They are not human-verified
ground truth. Every report now starts with a *Label provenance* table generated from the CSVs,
and `evaluate --reviewed-only` scores with human-reviewed rows only (today it reports that
there are none and writes nothing).

### Validity of the numbers below

- **Not independently validated.** The shipped TF-IDF settings (`sublinear_tf`, `min_df=2`, no
  feature cap) and the MMR calibration (λ 0.85 on normalised relevance) were *chosen* by
  comparing systems on these same labels and topics. Scoring the chosen configuration on the
  labels used to choose it measures fit to those labels, not generalisation. The "before → after"
  differences are therefore directional evidence that the changes help on this labelling, not
  measured improvements.
- **One labeller, no agreement measure.** A single LLM graded every row, so there is no
  inter-annotator agreement and no estimate of label noise. Systematic LLM biases (for example
  favouring famous books) would move all systems in the same direction and can still change
  their order.
- **Pool bias.** Only books some evaluated system retrieved were judged. A new system that
  surfaces different books (embeddings in particular) has unjudged results; check `judged@5`
  and pool + label before comparing it.
- **What is solid.** Reproducibility (fixed snapshot, no network, deterministic code), the
  known-item Recall@5 targets (defined by hand in `queries.json`), and the catalog-consistency
  checks do not depend on the LLM grades.

Grading rules used:

- **2** highly relevant: answers the query squarely (a known-item target, a book by the
  requested author, on-topic non-fiction); for seeds, a reader of the seed would very plausibly
  want it next (same series, the author's comparable work, a close sub-genre or theme).
- **1** partially relevant: right broad genre or audience but weaker fit (for example, serious
  SF for "funny satirical SF"); fan companions for a seed.
- **0** irrelevant, a lexical coincidence ("The Road to Serfdom" for *The Road*), a study
  guide or reference work when novels were asked for, or **another edition of the seed itself**.

## Results (provisional LLM labels, tuned on the same labels; see *Validity* above)

Baseline = production code and model at commit `23760c6`
([reports/baseline_23760c6.md](reports/baseline_23760c6.md)); current =
[reports/retrieval_evaluation.md](reports/retrieval_evaluation.md).

### Seed → item ("similar books", `GetRecommendationsUseCase`)

| System | nDCG@5 | P@5 | distinct authors@5 | content ILD@5 |
|---|---|---|---|---|
| Production before (TF-IDF min_df 5, 10k features, raw tf; +0.25·pop; MMR λ 0.6 on raw scores) | **0.290** | 0.296 | 0.99 | 0.989 |
| Same model, MMR off | 0.406 | 0.452 | 0.74 | 0.869 |
| Old TF-IDF alone (cosine) | 0.378 | 0.440 | 0.78 | 0.862 |
| New TF-IDF alone (sublinear tf, min_df 2, no feature cap) | 0.581 | 0.588 | 0.65 | 0.850 |
| New TF-IDF + popularity, no MMR | 0.602 | 0.624 | 0.64 | 0.852 |
| **Production after** (new TF-IDF + popularity + MMR λ 0.85 on normalised relevance) | **0.570** | 0.576 | 0.69 | 0.878 |

Paired bootstrap over the 50 seeds (95% CI of the per-seed nDCG@5 difference, on these labels;
the interval covers topic sampling only, not label error or the selection effect of tuning):

- before → after: +0.21 [+0.14, +0.28]
- popularity on vs off: +0.02 [−0.02, +0.06], not distinguishable from zero
- calibrated MMR on vs off: −0.035 [−0.065, −0.006] on these labels, traded for +6 pp author diversity

Attribution on these labels, one change at a time from the old recipe: refit on the full snapshot 0.376;
accent folding 0.376; `min_df=2` without the cap 0.397; **`sublinear_tf` 0.567**. Titles are
repeated 3× and categories 2× in the document text, so raw term frequency rewarded incidental
title-word matches; log-scaled tf removes most of that. The old MMR compared TF-IDF scores of
about 0.1–0.3 against a similarity penalty on a 0–1 scale, so the penalty dominated and lists
filled with unrelated bestsellers. A content ILD of 0.99 meant "unrelated", not "diverse".

### Query → item (TF-IDF as a lexical retriever)

| System | nDCG@5 EN | nDCG@5 TR | nDCG@5 DE | known-item Recall@5 |
|---|---|---|---|---|
| Old TF-IDF | 0.535 | 0.213 | 0.228 | 0.125 |
| New TF-IDF (shipped model) | 0.689 | 0.222 | 0.341 | 0.292 |

ASCII-only, Unicode-preserving and accent-folded text cleaning all land within ±0.005, so
`clean_text` was left unchanged. Turkish and German stay weak whatever the cleaning, because
the catalog text is English and lexical matching cannot cross languages. That (large, and
consistent across every variant) gap is why RAG uses the lexical fallback for English queries
only; it does not depend on the exact label values.

### Audit remediation (November 2026): before / after

Same harness, same snapshot, same labels, run before and after the remediation
(`reports/retrieval_evaluation.md` is the after run). All 25 systems produced identical
metrics; for example `prod_similar` nDCG@5 0.5695 → 0.5695, `prod_similar_no_mmr`
0.6046 → 0.6046, `tfidf_pickle` (query→item) 0.4462 → 0.4462. Expected: the regenerated model
artifact has the same rows, vocabulary and TF-IDF matrix (it now also stores its config), and
the identity/exclusion fixes change results only for same-title books or user libraries,
which these topics do not exercise. The fixes are covered by regression tests instead.

### Embedding systems: **not executed**

`emb_exact`, `rag_retrieval` (end-to-end RAG retrieval, LLM never called) and the `fusion_*`
ablations (production fusion, without TF-IDF, without embeddings, without popularity, MMR on
embedding similarity) are implemented, and their code paths were smoke-tested on synthetic
vectors. No real numbers exist yet, because this environment had no Gemini key and no
database credentials. Whether the stored vectors and the configured query format are
compatible (see `EmbeddingService` *embedding profile*) is therefore **unverified**. To produce
the numbers and compare the query formats against the stored vectors:

```bash
SUPABASE_DB_URL=... python -m backend.scripts.export_embedding_snapshot books     # read-only export + consistency report (incl. embedding_profiles)
GEMINI_API_KEY=...  python -m backend.scripts.export_embedding_snapshot queries --format legacy           # production default
GEMINI_API_KEY=...  python -m backend.scripts.export_embedding_snapshot queries --format raw
GEMINI_API_KEY=...  python -m backend.scripts.export_embedding_snapshot queries --format search_result
GEMINI_API_KEY=...  python -m backend.scripts.export_embedding_snapshot queries --format retrieval_query
python -m backend.scripts.run_retrieval_evaluation pool     --book-embeddings backend/evaluation/cache/book_embeddings.npz --query-embeddings backend/evaluation/cache/query_embeddings_*.npz
#   ...label the new rows (embedding systems surface candidates TF-IDF never retrieved)...
python -m backend.scripts.run_retrieval_evaluation evaluate --book-embeddings backend/evaluation/cache/book_embeddings.npz --query-embeddings backend/evaluation/cache/query_embeddings_*.npz
```

`evaluation/cache/` is git-ignored because it holds production data.

### Vector RPCs (exact vs HNSW)

`python -m backend.scripts.benchmark_vector_rpcs` applies migrations 03/05/06 verbatim to an
empty scratch database and compares each RPC with brute-force cosine
([reports/vector_rpc_benchmark.json](reports/vector_rpc_benchmark.json), pgvector 0.8.6,
**synthetic vectors**). At 6,446 rows the planner chooses an exact sequential scan:
recall@100 = 1.0, and `halfvec` precision costs 0.4% recall@5. When the HNSW index is
used, the RPCs return at most `hnsw.ef_search` (default 40) rows even though 100 are
requested. See *Remaining limitations* in the change report.

## Live RAG quality evaluation (Turkish / English)

`python -m backend.scripts.run_rag_quality_eval run` runs the **production pipeline, live**
(Gemini + Supabase, read-only, roughly 120 API calls, about 15 minutes) on
[data/rag_eval_tr_en.json](data/rag_eval_tr_en.json): 20 intents asked in both English and
Turkish, plus 4 Turkish queries typed without Turkish letters (44 queries). It also runs the
answer-reliability probes in [data/rag_eval_adversarial.json](data/rag_eval_adversarial.json).
It is never part of CI.

- **What it records per query:**
  - cold (empty query cache) and warm (repeat) end-to-end latency;
  - the semantic stage production actually used (query embedding, then the vector RPC; the
    real objects are wrapped, not reimplemented);
  - an exact cosine top-10 over the exported snapshot;
  - every Gemini HTTP attempt (status, retries, latency, `usageMetadata` tokens);
  - the ISBNs in the prompt Gemini received.
- **Retrieval metrics** (work level, so editions of one book count once; `rel` = works graded ≥ 1):
  - Hit@5 = 1 if any of the top 5 is relevant, else 0;
  - R@k = |top-k ∩ rel| / min(k, |rel|), capped so a 39-book author set can reach 1.0;
  - P@k = |top-k ∩ rel| / k;
  - MRR@k = 1 / rank of the first relevant result within the top k (0 if none);
  - nDCG@k = DCG@k / IDCG@k with gain 2^grade − 1 and discount log2(rank + 1).

  Production answers with at most 5 books, so its @10 metrics are reported as "–", not as a
  number. A query with no labelled set is excluded from a metric rather than scored 0.
- **Grounding checks.** Deterministic, recomputed offline by
  `python -m backend.scripts.run_rag_quality_eval report`:
  - ISBNs outside the context;
  - catalog titles and author names outside the context;
  - the answer language versus the query language;
  - quoted titles that match nothing, flagged for human review;
  - the adversarial expectations (abstain, stay on books, ignore injection).
- **Labels.** `label_tier` is `rule_derived` (identity rules: the book's own title or author, or
  a known item), `proposed` (genre, topic and similar-book sets, pending review) or `open` (no
  fixed set). Known-item intents set `single_work`, so any edition of the wanted book is a hit.
  **No label is human-verified yet.** Reviewers fill `human_grade` (0/1/2) and `reviewed_by` in
  [data/rag_eval_judgments.csv](data/rag_eval_judgments.csv). `report` then scores those intents
  on the human grades and lists them as `human_verified`.
- **Outputs:** [reports/rag_quality_eval.json](reports/rag_quality_eval.json) (everything, per
  query), [reports/rag_quality_eval.md](reports/rag_quality_eval.md) (summary), and
  `cache/rag_eval_query_embeddings.npz` (query vectors, for offline re-runs).
- **Offline protection.** `backend/tests/test_rag_quality_eval_harness.py` pins the measurement
  rules. `test_rag_grounding.py` and `test_ai_streaming.py` pin the defects found live.

## What a human-reviewed evaluation set needs

1. **Reviewers and protocol.** At least two people who read in the topic's language (EN, TR,
   DE), grading independently with the rules above, blind to which system retrieved a book.
   Record each reviewer in `reviewed_by`; keep the LLM grade in a separate column if it is kept
   at all, never as the reviewed grade.
2. **Agreement.** Double-grade a sample (for example 20% of rows), report Cohen's κ per language,
   and adjudicate disagreements before scoring.
3. **A held-out split that tuning never sees.** Use `split=dev` for any parameter search and
   report `split=heldout` once per decision. Because everything so far was tuned on all topics,
   a clean held-out set needs *new* topics (or a fresh review of the heldout ones that nobody
   tuning the system has seen).
4. **Coverage.** Enough topics per language and category for stable estimates (the current
   18 German queries are thin), pooled from every system to be compared, including embedding
   systems once a snapshot exists (`pool`, then review the new rows).
5. **Score it.** `python -m backend.scripts.run_retrieval_evaluation evaluate --reviewed-only`
   writes `reports/retrieval_evaluation_reviewed.{md,json}`; only those numbers should be
   quoted as validated.

## Files

- [retrieval.py](retrieval.py): catalog snapshot, work ids, TF-IDF and embedding indexes, `top_k`, `mmr`, judgment I/O
- [metrics.py](metrics.py): graded metrics (shared with the older cohort benchmark)
- [../scripts/run_retrieval_evaluation.py](../scripts/run_retrieval_evaluation.py): systems under test, pooling, report
- [../scripts/export_embedding_snapshot.py](../scripts/export_embedding_snapshot.py): one-off export from live infrastructure
- [../scripts/benchmark_vector_rpcs.py](../scripts/benchmark_vector_rpcs.py): exact-vs-approximate check of the SQL RPCs
- [../scripts/run_real_retrieval_audit.py](../scripts/run_real_retrieval_audit.py): k=10 metrics, latency percentiles, empty rates and recommendation-quality checks on the real stored embeddings and the live RAG pipeline
- [../scripts/benchmark_pgvector_live.py](../scripts/benchmark_pgvector_live.py): read-only benchmark of the live pgvector index (ef_search / LIMIT interaction, EXPLAIN ANALYZE, RPC latency)
- [reports/real_retrieval_audit.md](reports/real_retrieval_audit.md): November 2026 real-data audit (results, fixes, remaining issues)
