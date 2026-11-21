# RAG quality evaluation (live) - 2026-11-21T14:47:50+0300

Embedding profile `models/gemini-embedding-2;dim=3072;text=canonical_v1;task=RETRIEVAL_DOCUMENT`, query format `legacy`; vector port `SupabaseBookDataPort`; LLM `gemini-3.5-flash-lite`. Labels: see `label_tiers` in the dataset; human-verified intents: none.

## Retrieval (rule_derived)

| group | system | n | Hit@5 | R@5 | R@10 | P@5 | P@10 | MRR@5 | MRR@10 | nDCG@5 | nDCG@10 | empty |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| all | production_top5 | 19 | 1.0 | 0.947 | – | 0.442 | – | 1.0 | – | 0.958 | – | 0.0 |
| all | semantic_rpc_top10 | 19 | 1.0 | 0.979 | 0.974 | 0.474 | 0.384 | 0.974 | 0.974 | 0.965 | 0.96 | 0.0 |
| all | semantic_exact_top10 | 19 | 1.0 | 0.979 | 0.974 | 0.474 | 0.384 | 0.974 | 0.974 | 0.965 | 0.96 | 0.0 |
| en | production_top5 | 8 | 1.0 | 0.925 | – | 0.425 | – | 1.0 | – | 0.94 | – | 0.0 |
| en | semantic_rpc_top10 | 8 | 1.0 | 0.975 | 0.963 | 0.475 | 0.375 | 1.0 | 1.0 | 0.979 | 0.97 | 0.0 |
| en | semantic_exact_top10 | 8 | 1.0 | 0.975 | 0.963 | 0.475 | 0.375 | 1.0 | 1.0 | 0.979 | 0.97 | 0.0 |
| tr (Turkish letters) | production_top5 | 8 | 1.0 | 0.95 | – | 0.45 | – | 1.0 | – | 0.961 | – | 0.0 |
| tr (Turkish letters) | semantic_rpc_top10 | 8 | 1.0 | 0.975 | 0.975 | 0.475 | 0.388 | 0.938 | 0.938 | 0.937 | 0.935 | 0.0 |
| tr (Turkish letters) | semantic_exact_top10 | 8 | 1.0 | 0.975 | 0.975 | 0.475 | 0.388 | 0.938 | 0.938 | 0.937 | 0.935 | 0.0 |
| tr (ASCII-typed) | production_top5 | 3 | 1.0 | 1.0 | – | 0.467 | – | 1.0 | – | 1.0 | – | 0.0 |
| tr (ASCII-typed) | semantic_rpc_top10 | 3 | 1.0 | 1.0 | 1.0 | 0.467 | 0.4 | 1.0 | 1.0 | 1.0 | 1.0 | 0.0 |
| tr (ASCII-typed) | semantic_exact_top10 | 3 | 1.0 | 1.0 | 1.0 | 0.467 | 0.4 | 1.0 | 1.0 | 1.0 | 1.0 | 0.0 |

## Retrieval (proposed)

| group | system | n | Hit@5 | R@5 | R@10 | P@5 | P@10 | MRR@5 | MRR@10 | nDCG@5 | nDCG@10 | empty |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| all | production_top5 | 21 | 0.952 | 0.421 | – | 0.324 | – | 0.802 | – | 0.474 | – | 0.0 |
| all | semantic_rpc_top10 | 21 | 0.905 | 0.538 | 0.67 | 0.41 | 0.338 | 0.655 | 0.671 | 0.53 | 0.6 | 0.0 |
| all | semantic_exact_top10 | 21 | 0.905 | 0.538 | 0.67 | 0.41 | 0.338 | 0.655 | 0.671 | 0.53 | 0.6 | 0.0 |
| en | production_top5 | 10 | 0.9 | 0.433 | – | 0.34 | – | 0.75 | – | 0.47 | – | 0.0 |
| en | semantic_rpc_top10 | 10 | 0.9 | 0.5 | 0.647 | 0.38 | 0.35 | 0.608 | 0.625 | 0.486 | 0.577 | 0.0 |
| en | semantic_exact_top10 | 10 | 0.9 | 0.5 | 0.647 | 0.38 | 0.35 | 0.608 | 0.625 | 0.486 | 0.577 | 0.0 |
| tr (Turkish letters) | production_top5 | 10 | 1.0 | 0.4 | – | 0.32 | – | 0.833 | – | 0.463 | – | 0.0 |
| tr (Turkish letters) | semantic_rpc_top10 | 10 | 0.9 | 0.58 | 0.66 | 0.46 | 0.34 | 0.667 | 0.683 | 0.567 | 0.602 | 0.0 |
| tr (Turkish letters) | semantic_exact_top10 | 10 | 0.9 | 0.58 | 0.66 | 0.46 | 0.34 | 0.667 | 0.683 | 0.567 | 0.602 | 0.0 |
| tr (ASCII-typed) | production_top5 | 1 | 1.0 | 0.5 | – | 0.2 | – | 1.0 | – | 0.613 | – | 0.0 |
| tr (ASCII-typed) | semantic_rpc_top10 | 1 | 1.0 | 0.5 | 1.0 | 0.2 | 0.2 | 1.0 | 1.0 | 0.613 | 0.818 | 0.0 |
| tr (ASCII-typed) | semantic_exact_top10 | 1 | 1.0 | 0.5 | 1.0 | 0.2 | 0.2 | 1.0 | 1.0 | 0.613 | 0.818 | 0.0 |

"–" = not applicable: production answers with at most 5 books, so it has no @10 metrics.

## Dataset composition

120 queries in the dataset, 44 in this run; 20 have no labelled set and are judged by behaviour only.

```json
{
 "by_category": {
  "ambiguous": 8,
  "author": 15,
  "exact_title": 17,
  "genre": 12,
  "insufficient_info": 6,
  "mood": 4,
  "multi_constraint": 6,
  "no_relevant": 6,
  "semantic_description": 17,
  "similar": 14,
  "topic": 15
 },
 "by_language": {
  "en": 58,
  "tr": 62
 },
 "by_tier": {
  "automatic_candidate": 76,
  "open": 4,
  "proposed": 21,
  "rule_derived": 19
 },
 "by_difficulty": {
  "easy": 20,
  "hard": 24,
  "medium": 32,
  "unrated": 44
 },
 "by_expected_behavior": {
  "abstain_not_in_catalog": 6,
  "no_fabrication": 6,
  "open_judgment": 8,
  "retrieve_relevant": 100
 },
 "by_dataset": {
  "base": 44,
  "expansion": 76
 }
}
```

## By category (all tiers mixed; see the per-query CSV for each row's tier)

| category | n | production Hit@5 | production nDCG@5 | semantic nDCG@5 | semantic nDCG@10 |
|---|---|---|---|---|---|
| author | 7 | 1.0 | 0.887 | 0.957 | 0.944 |
| exact_title | 5 | 1.0 | 1.0 | 1.0 | 1.0 |
| genre | 4 | 1.0 | 0.373 | 0.597 | 0.581 |
| semantic_description | 7 | 1.0 | 1.0 | 0.947 | 0.947 |
| similar | 8 | 0.875 | 0.368 | 0.256 | 0.344 |
| topic | 9 | 1.0 | 0.612 | 0.744 | 0.837 |

## Paired EN vs TR (nDCG@5, same intent)

| intent | tier | production EN | production TR | semantic EN | semantic TR |
|---|---|---|---|---|---|
| author_christie | rule_derived | 1.000 | 1.000 | 1.000 | 1.000 |
| author_orwell | rule_derived | 0.869 | 1.000 | 1.000 | 1.000 |
| author_tolkien | rule_derived | 0.655 | 0.684 | 0.830 | 0.869 |
| desc_alice | rule_derived | 1.000 | 1.000 | 1.000 | 1.000 |
| desc_hp | rule_derived | 1.000 | 1.000 | 1.000 | 0.631 |
| desc_kafka | rule_derived | 1.000 | 1.000 | 1.000 | 1.000 |
| genre_detective | proposed | 0.214 | 0.470 | 0.384 | 0.515 |
| genre_horror | proposed | 0.339 | 0.470 | 0.661 | 0.830 |
| sim_1984 | proposed | 0.441 | 0.441 | 0.363 | 0.363 |
| sim_austen | proposed | 0.655 | 0.384 | 0.384 | 0.491 |
| sim_dune | proposed | 0.000 | 0.339 | 0.000 | 0.000 |
| sim_hp | proposed | 0.515 | 0.170 | 0.146 | 0.301 |
| title_crime | rule_derived | 1.000 | 1.000 | 1.000 | 1.000 |
| title_hobbit | rule_derived | 1.000 | 1.000 | 1.000 | 1.000 |
| topic_habits | proposed | 0.469 | 0.469 | 0.967 | 1.000 |
| topic_robots | proposed | 0.509 | 0.509 | 0.339 | 0.553 |
| topic_rome | proposed | 0.613 | 0.613 | 0.613 | 0.613 |
| topic_stoic | proposed | 0.947 | 0.765 | 1.000 | 1.000 |

## Performance

```json
{
 "end_to_end_cold_all": {
  "n": 44,
  "p50": 6749.8,
  "p95": 16294.7,
  "max": 25828.0
 },
 "end_to_end_cold_gemini_answers": {
  "n": 43,
  "p50": 6749.8,
  "p95": 15696.9,
  "max": 25828.0
 },
 "end_to_end_cold_deterministic_catalog": {
  "n": 0,
  "p50": null,
  "p95": null,
  "max": null
 },
 "end_to_end_cold_llm_fallback": {
  "n": 1,
  "p50": 16294.7,
  "p95": 16294.7,
  "max": 16294.7
 },
 "end_to_end_warm_query_cache": {
  "n": 44,
  "p50": 0.5,
  "p95": 0.8,
  "max": 9556.8
 },
 "query_embedding": {
  "n": 44,
  "p50": 428.8,
  "p95": 594.7,
  "max": 1226.6
 },
 "vector_rpc": {
  "n": 44,
  "p50": 501.5,
  "p95": 1387.9,
  "max": 1733.2
 },
 "gemini_generation": {
  "n": 44,
  "p50": 5232.6,
  "p95": 15004.4,
  "max": 23906.8
 },
 "http_calls": {
  "generate": {
   "attempts": 59,
   "non_200": 5,
   "status_counts": {
    "200": 54,
    "503": 4,
    "ReadTimeout": 1
   }
  },
  "embed": {
   "attempts": 55,
   "non_200": 0,
   "status_counts": {
    "200": 55
   }
  }
 },
 "model_versions": [
  "gemini-3.5-flash-lite"
 ],
 "tokens_generate": {
  "promptTokenCount": {
   "sum": 58693,
   "n_calls_with_usage": 54,
   "mean": 1086.9
  },
  "candidatesTokenCount": {
   "sum": 11683,
   "n_calls_with_usage": 54,
   "mean": 216.4
  },
  "thoughtsTokenCount": {
   "sum": 0,
   "n_calls_with_usage": 0,
   "mean": null
  },
  "totalTokenCount": {
   "sum": 70376,
   "n_calls_with_usage": 54,
   "mean": 1303.3
  }
 },
 "tokens_embed": {
  "promptTokenCount": {
   "sum": 550,
   "n_calls_with_usage": 55,
   "mean": 10
  },
  "totalTokenCount": {
   "sum": 0,
   "n_calls_with_usage": 0,
   "mean": null
  }
 },
 "warm_served_from_cache": 43,
 "warm_http_calls": 2
}
```

## Answer reliability

```json
{
 "statuses": {
  "success": 43,
  "llm_fallback": 1
 },
 "sources": {
  "rag_llm": 44
 },
 "gemini_answers": 43,
 "context_delivered_rate": 1.0,
 "answers_with_foreign_isbn": 0,
 "answers_with_foreign_catalog_title": 0,
 "answers_with_foreign_author": 0,
 "unsupported_claim_rate": 0.0,
 "answers_with_spans_for_review": 1,
 "answers_in_wrong_language": [],
 "source_attribution_errors": [
  "sim_hp_tr: fallback answer reported source=rag_llm"
 ],
 "adversarial": {
  "cases": 12,
  "all_checks_passed": 12,
  "failures": {}
 },
 "behaviour_checks": {
  "abstain_not_in_catalog": {
   "n": 0,
   "passed": 0,
   "failures": []
  },
  "no_fabrication": {
   "n": 0,
   "passed": 0,
   "failures": []
  }
 }
}
```
