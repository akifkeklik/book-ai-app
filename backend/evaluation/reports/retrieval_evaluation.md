# Libris offline retrieval evaluation

Catalog snapshot: backend/data/books.csv (6446 ISBNs, 6427 works). Judgments: evaluation/data/judgments_*.csv - see the labeler column; rows labelled 'llm:*' with an empty reviewed_by are provisional and NOT human-verified ground truth.

## Label provenance

| judgments | graded | human-reviewed | unreviewed | labelers |
|---|---|---|---|---|
| queries | 478 | 0 | 478 | llm:claude-opus-5-5: 478 |
| seeds | 706 | 0 | 706 | llm:claude-opus-5-5: 706 |

NOT independently validated: these labels are provisional (unreviewed LLM grades), and the shipped TF-IDF/MMR settings were chosen by comparing systems on these same labels and topics. Treat differences as directional evidence, not as measured improvements. The split=heldout breakdown is reserved for future tuning; it was not held out from the tuning done so far.


Catalog consistency: 6446 snapshot ISBNs / 6427 works; production model v2.3.0 has 6427 rows; 0 snapshot ISBNs cannot be resolved by the model.

## query_to_item (k=5)

| system | n | P@5 | P@5 (grade 2) | nDCG@5 | MRR | Recall@5 (known-item) | judged@5 | ILD cat | ILD content | distinct authors | coverage |
|---|---|---|---|---|---|---|---|---|---|---|---|
| tfidf_fold | 72 | 0.3167 | 0.1583 | 0.3368 | 0.3861 | 0.125 | 0.7639 | 0.5511 | 0.6513 | 0.6194 | 0.0302 |
| tfidf_mindf2 | 72 | 0.325 | 0.1694 | 0.3981 | 0.485 | 0.2083 | 0.8472 | 0.5988 | 0.7285 | 0.6556 | 0.0319 |
| tfidf_pickle | 72 | 0.3694 | 0.1972 | 0.4462 | 0.4975 | 0.2917 | 0.8889 | 0.586 | 0.7657 | 0.6778 | 0.0349 |
| tfidf_rare | 72 | 0.3639 | 0.1861 | 0.4356 | 0.487 | 0.2917 | 0.8472 | 0.5591 | 0.721 | 0.6333 | 0.0325 |
| tfidf_rare_ascii | 72 | 0.3694 | 0.1972 | 0.4411 | 0.4905 | 0.2917 | 0.8889 | 0.586 | 0.7657 | 0.6778 | 0.0349 |
| tfidf_rare_nofold | 72 | 0.3722 | 0.1944 | 0.4443 | 0.4917 | 0.2917 | 0.8333 | 0.533 | 0.7103 | 0.6139 | 0.0324 |
| tfidf_refit | 72 | 0.3278 | 0.1667 | 0.3524 | 0.3965 | 0.125 | 0.8194 | 0.5702 | 0.706 | 0.6639 | 0.0333 |
| tfidf_sublinear | 72 | 0.3472 | 0.1833 | 0.3694 | 0.3977 | 0.1667 | 0.7639 | 0.4945 | 0.6426 | 0.6 | 0.0302 |

### Breakdown (nDCG@5)

| system | category=author_style | category=known_item | category=mood | category=topic | lang=de | lang=en | lang=tr | split=dev | split=heldout |
|---|---|---|---|---|---|---|---|---|---|
| tfidf_fold | 0.5854 | 0.1578 | 0.3783 | 0.3381 | 0.2165 | 0.5294 | 0.1863 | 0.3366 | 0.3372 |
| tfidf_mindf2 | 0.5773 | 0.2385 | 0.4515 | 0.4206 | 0.319 | 0.5857 | 0.2231 | 0.4046 | 0.3825 |
| tfidf_pickle | 0.6846 | 0.2952 | 0.4882 | 0.4212 | 0.341 | 0.6885 | 0.2223 | 0.4538 | 0.4276 |
| tfidf_rare | 0.6431 | 0.2813 | 0.4936 | 0.4274 | 0.3291 | 0.6659 | 0.2276 | 0.4403 | 0.4243 |
| tfidf_rare_ascii | 0.6846 | 0.2798 | 0.4882 | 0.4212 | 0.341 | 0.6761 | 0.2223 | 0.4466 | 0.4276 |
| tfidf_rare_nofold | 0.6846 | 0.2813 | 0.4936 | 0.4274 | 0.341 | 0.6724 | 0.2366 | 0.4487 | 0.4336 |
| tfidf_refit | 0.6304 | 0.1578 | 0.4114 | 0.3389 | 0.2284 | 0.5381 | 0.2131 | 0.3436 | 0.3735 |
| tfidf_sublinear | 0.627 | 0.1882 | 0.4412 | 0.3467 | 0.2378 | 0.61 | 0.1673 | 0.3649 | 0.3802 |

## seed_to_item (k=5)

| system | n | P@5 | P@5 (grade 2) | nDCG@5 | MRR | Recall@5 (known-item) | judged@5 | ILD cat | ILD content | distinct authors | coverage |
|---|---|---|---|---|---|---|---|---|---|---|---|
| prod_similar | 50 | 0.576 | 0.356 | 0.5695 | 0.728 | - | 1.0 | 0.532 | 0.8776 | 0.692 | 0.0363 |
| prod_similar_no_mmr | 50 | 0.628 | 0.376 | 0.6046 | 0.7307 | - | 1.0 | 0.501 | 0.853 | 0.632 | 0.0363 |
| tfidf_fold_raw | 50 | 0.44 | 0.216 | 0.376 | 0.5297 | - | 1.0 | 0.6 | 0.8608 | 0.776 | 0.0375 |
| tfidf_mindf2_raw | 50 | 0.448 | 0.244 | 0.397 | 0.562 | - | 1.0 | 0.6117 | 0.861 | 0.752 | 0.0381 |
| tfidf_pickle_raw | 50 | 0.588 | 0.36 | 0.5806 | 0.734 | - | 1.0 | 0.519 | 0.8499 | 0.652 | 0.0378 |
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

| system | category=seed | lang=en | split=dev | split=heldout |
|---|---|---|---|---|
| prod_similar | 0.5695 | 0.5695 | 0.541 | 0.6089 |
| prod_similar_no_mmr | 0.6046 | 0.6046 | 0.5572 | 0.6701 |
| tfidf_fold_raw | 0.376 | 0.376 | 0.3601 | 0.398 |
| tfidf_mindf2_raw | 0.397 | 0.397 | 0.3775 | 0.424 |
| tfidf_pickle_raw | 0.5806 | 0.5806 | 0.5185 | 0.6664 |
| tfidf_rare*pop | 0.5802 | 0.5802 | 0.5263 | 0.6546 |
| tfidf_rare*pop+mmr_norm0.85 | 0.5743 | 0.5743 | 0.5234 | 0.6445 |
| tfidf_rare+mmr_norm0.7 | 0.5562 | 0.5562 | 0.5068 | 0.6245 |
| tfidf_rare+mmr_norm0.85 | 0.5665 | 0.5665 | 0.5162 | 0.636 |
| tfidf_rare+pop | 0.6024 | 0.6024 | 0.5568 | 0.6652 |
| tfidf_rare+pop+mmr0.6 | 0.358 | 0.358 | 0.3483 | 0.3713 |
| tfidf_rare+pop+mmr_norm0.85 | 0.5735 | 0.5735 | 0.539 | 0.6212 |
| tfidf_rare_ascii_raw | 0.578 | 0.578 | 0.514 | 0.6664 |
| tfidf_rare_nofold_raw | 0.578 | 0.578 | 0.514 | 0.6664 |
| tfidf_rare_raw | 0.5824 | 0.5824 | 0.5193 | 0.6694 |
| tfidf_refit_raw | 0.3759 | 0.3759 | 0.359 | 0.3993 |
| tfidf_sublinear_raw | 0.567 | 0.567 | 0.509 | 0.6472 |

## Not executed

- All embedding systems (emb_exact, rag_retrieval, fusion_*): no --book-embeddings snapshot was available (no Gemini key / database credentials in this environment).
