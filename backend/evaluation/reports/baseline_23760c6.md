# Libris offline retrieval evaluation — BASELINE (production code + model at commit 23760c6, before this change)

Catalog snapshot: backend/data/books.csv (6446 ISBNs, 6427 works). Judgments: evaluation/data/judgments_*.csv - see the labeler column; rows labelled 'llm:*' with an empty reviewed_by are provisional and NOT human-verified ground truth.

Catalog consistency: 6446 snapshot ISBNs / 6427 works; production model v2.1.0 has 6424 rows; 22 snapshot ISBNs cannot be resolved by the model.

## query_to_item (k=5)

| system | n | P@5 | P@5 (grade 2) | nDCG@5 | MRR | Recall@5 (known-item) | judged@5 | ILD cat | ILD content | distinct authors | coverage |
|---|---|---|---|---|---|---|---|---|---|---|---|
| tfidf_fold | 72 | 0.3167 | 0.1583 | 0.3368 | 0.3861 | 0.125 | 0.7639 | 0.5511 | 0.6513 | 0.6194 | 0.0302 |
| tfidf_mindf2 | 72 | 0.325 | 0.1694 | 0.3981 | 0.485 | 0.2083 | 0.8472 | 0.5988 | 0.7285 | 0.6556 | 0.0319 |
| tfidf_pickle | 72 | 0.3278 | 0.1639 | 0.3511 | 0.3965 | 0.125 | 0.8194 | 0.5668 | 0.7071 | 0.6639 | 0.0331 |
| tfidf_rare | 72 | 0.3639 | 0.1861 | 0.4356 | 0.487 | 0.2917 | 0.8472 | 0.5591 | 0.721 | 0.6333 | 0.0325 |
| tfidf_rare_ascii | 72 | 0.3694 | 0.1972 | 0.4411 | 0.4905 | 0.2917 | 0.8889 | 0.586 | 0.7657 | 0.6778 | 0.0349 |
| tfidf_rare_nofold | 72 | 0.3722 | 0.1944 | 0.4443 | 0.4917 | 0.2917 | 0.8333 | 0.533 | 0.7103 | 0.6139 | 0.0324 |
| tfidf_refit | 72 | 0.3278 | 0.1667 | 0.3524 | 0.3965 | 0.125 | 0.8194 | 0.5702 | 0.706 | 0.6639 | 0.0333 |
| tfidf_sublinear | 72 | 0.3472 | 0.1833 | 0.3694 | 0.3977 | 0.1667 | 0.7639 | 0.4945 | 0.6426 | 0.6 | 0.0302 |

### Breakdown (nDCG@5)

| system | category=author_style | category=known_item | category=mood | category=topic | lang=de | lang=en | lang=tr |
|---|---|---|---|---|---|---|---|
| tfidf_fold | 0.5854 | 0.1578 | 0.3783 | 0.3381 | 0.2165 | 0.5294 | 0.1863 |
| tfidf_mindf2 | 0.5773 | 0.2385 | 0.4515 | 0.4206 | 0.319 | 0.5857 | 0.2231 |
| tfidf_pickle | 0.6304 | 0.1578 | 0.4114 | 0.3345 | 0.2284 | 0.5352 | 0.2131 |
| tfidf_rare | 0.6431 | 0.2813 | 0.4936 | 0.4274 | 0.3291 | 0.6659 | 0.2276 |
| tfidf_rare_ascii | 0.6846 | 0.2798 | 0.4882 | 0.4212 | 0.341 | 0.6761 | 0.2223 |
| tfidf_rare_nofold | 0.6846 | 0.2813 | 0.4936 | 0.4274 | 0.341 | 0.6724 | 0.2366 |
| tfidf_refit | 0.6304 | 0.1578 | 0.4114 | 0.3389 | 0.2284 | 0.5381 | 0.2131 |
| tfidf_sublinear | 0.627 | 0.1882 | 0.4412 | 0.3467 | 0.2378 | 0.61 | 0.1673 |

## seed_to_item (k=5)

| system | n | P@5 | P@5 (grade 2) | nDCG@5 | MRR | Recall@5 (known-item) | judged@5 | ILD cat | ILD content | distinct authors | coverage |
|---|---|---|---|---|---|---|---|---|---|---|---|
| prod_similar | 50 | 0.296 | 0.124 | 0.2903 | 0.5667 | - | 1.0 | 0.7583 | 0.9887 | 0.988 | 0.0339 |
| prod_similar_no_mmr | 50 | 0.452 | 0.236 | 0.4056 | 0.5383 | - | 1.0 | 0.6107 | 0.8685 | 0.744 | 0.0369 |
| tfidf_fold_raw | 50 | 0.44 | 0.216 | 0.376 | 0.5297 | - | 1.0 | 0.6 | 0.8608 | 0.776 | 0.0375 |
| tfidf_mindf2_raw | 50 | 0.448 | 0.244 | 0.397 | 0.562 | - | 1.0 | 0.6117 | 0.861 | 0.752 | 0.0381 |
| tfidf_pickle_raw | 50 | 0.44 | 0.22 | 0.3775 | 0.523 | - | 1.0 | 0.5957 | 0.8622 | 0.776 | 0.0377 |
| tfidf_rare*pop | 50 | 0.592 | 0.36 | 0.5802 | 0.724 | - | 1.0 | 0.524 | 0.8511 | 0.656 | 0.0378 |
| tfidf_rare*pop+mmr_norm0.85 | 50 | 0.6 | 0.352 | 0.5743 | 0.724 | - | 1.0 | 0.528 | 0.8581 | 0.66 | 0.038 |
| tfidf_rare+mmr_norm0.7 | 50 | 0.576 | 0.332 | 0.5562 | 0.7397 | - | 1.0 | 0.543 | 0.8693 | 0.688 | 0.038 |
| tfidf_rare+mmr_norm0.85 | 50 | 0.58 | 0.328 | 0.5665 | 0.744 | - | 1.0 | 0.508 | 0.8584 | 0.672 | 0.038 |
| tfidf_rare+pop | 50 | 0.624 | 0.372 | 0.6024 | 0.7307 | - | 1.0 | 0.507 | 0.8519 | 0.636 | 0.0364 |
| tfidf_rare+pop+mmr0.6 | 50 | 0.34 | 0.14 | 0.358 | 0.6783 | - | 1.0 | 0.746 | 0.9832 | 0.952 | 0.0311 |
| tfidf_rare+pop+mmr_norm0.85 | 50 | 0.576 | 0.356 | 0.5735 | 0.728 | - | 1.0 | 0.532 | 0.8784 | 0.696 | 0.0363 |
| tfidf_rare_ascii_raw | 50 | 0.588 | 0.356 | 0.578 | 0.7307 | - | 1.0 | 0.519 | 0.8492 | 0.652 | 0.0378 |
| tfidf_rare_nofold_raw | 50 | 0.588 | 0.356 | 0.578 | 0.7307 | - | 1.0 | 0.519 | 0.8492 | 0.652 | 0.0378 |
| tfidf_rare_raw | 50 | 0.588 | 0.352 | 0.5824 | 0.7407 | - | 1.0 | 0.518 | 0.8483 | 0.656 | 0.0378 |
| tfidf_refit_raw | 50 | 0.444 | 0.216 | 0.3759 | 0.528 | - | 1.0 | 0.6 | 0.8628 | 0.776 | 0.0375 |
| tfidf_sublinear_raw | 50 | 0.588 | 0.336 | 0.567 | 0.7263 | - | 1.0 | 0.497 | 0.8416 | 0.632 | 0.0369 |

### Breakdown (nDCG@5)

| system | category=seed | lang=en |
|---|---|---|
| prod_similar | 0.2903 | 0.2903 |
| prod_similar_no_mmr | 0.4056 | 0.4056 |
| tfidf_fold_raw | 0.376 | 0.376 |
| tfidf_mindf2_raw | 0.397 | 0.397 |
| tfidf_pickle_raw | 0.3775 | 0.3775 |
| tfidf_rare*pop | 0.5802 | 0.5802 |
| tfidf_rare*pop+mmr_norm0.85 | 0.5743 | 0.5743 |
| tfidf_rare+mmr_norm0.7 | 0.5562 | 0.5562 |
| tfidf_rare+mmr_norm0.85 | 0.5665 | 0.5665 |
| tfidf_rare+pop | 0.6024 | 0.6024 |
| tfidf_rare+pop+mmr0.6 | 0.358 | 0.358 |
| tfidf_rare+pop+mmr_norm0.85 | 0.5735 | 0.5735 |
| tfidf_rare_ascii_raw | 0.578 | 0.578 |
| tfidf_rare_nofold_raw | 0.578 | 0.578 |
| tfidf_rare_raw | 0.5824 | 0.5824 |
| tfidf_refit_raw | 0.3759 | 0.3759 |
| tfidf_sublinear_raw | 0.567 | 0.567 |

## Not executed

- All embedding systems (emb_exact, rag_retrieval, fusion_*): no --book-embeddings snapshot was available (no Gemini key / database credentials in this environment).
