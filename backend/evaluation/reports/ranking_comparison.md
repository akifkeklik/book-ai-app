# RAG ranking comparison (offline, identical candidates)

`python -m backend.scripts.run_ranking_comparison --pool 100`. Candidates: exact cosine top-100 from the
snapshot with the stored query vectors (no Gemini/DB). Labels: `rule_derived` (identity rules, 16 queries
excluding ASCII variants); `proposed` labels are orientation only and were NOT used to choose.
Raw numbers: [ranking_comparison.json](ranking_comparison.json).

| Strategy (rule_derived) | nDCG@5 | P@5 | R@5 | MRR@5 | foreign-author share@5 (author queries) |
|---|---|---|---|---|---|
| Production (pop + MMR) | 0.941 | 0.425 | 0.925 | 1.00 | 20% |
| Production without MMR | **0.979** | 0.475 | 0.975 | 1.00 | **6.7%** |
| Popularity off, with MMR | 0.938 | 0.45 | 0.95 | 0.969 | 13% |
| Popularity off, no MMR | 0.958 | 0.475 | 0.975 | 0.969 | 6.7% |
| Semantic only | 0.958 | 0.475 | 0.975 | 0.969 | 6.7% |

Cause of "Orwell -> All Creatures Great and Small": MMR diversity (cosine 0.62 book chosen because it is
unlike the Orwell books already picked), not popularity. Fix: no MMR for unseeded semantic queries.
Paired over 19 rule-derived queries: 4 better, 0 worse, mean +0.031, bootstrap 95% CI [+0.007, +0.061].
Popularity weight (0 / 0.05 / default) without MMR: 0.958 / 0.982 / 0.979, indistinguishable; unchanged.
Candidate pool 20 / 40 / 100: production_nomm nDCG@5 0.979 at all sizes (pool size does not change top-5).
