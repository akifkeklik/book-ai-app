# Human review guide: RAG retrieval judgments

Nothing here is human-verified until a person writes a grade **and** their name. No script
fills `human_grade` or `reviewed_by`.

## Workflow (about 426 rows, one pass)

```bash
python -m backend.scripts.rag_review queue    # builds data/rag_review_queue.csv
# edit the queue: fill human_grade (0/1/2) and reviewed_by on EVERY row of an intent
python -m backend.scripts.rag_review apply    # merges into data/rag_eval_judgments.csv
python -m backend.scripts.rag_review status   # which intents now count
python -m backend.scripts.run_rag_quality_eval report   # existing command, unchanged
```

Why this is the smallest valid set:

- The queue is **blind** (no system names), **deduplicated** by work (editions share one grade;
  3 duplicate rows removed) and **excludes the 2 open intents** (43 rows, not scored).
- Order: the 8 rule-derived intents (19 queries, 166 rows) first, then the 10 proposed
  intents (21 queries, 260 rows).
- Rule-derived rows marked `relevant (unverified)` are identity checks (the author field shows
  it): confirm in seconds. The effort is in the rows without a suggestion and in the 260
  proposed rows.
- **An intent counts only when every one of its rows is graded.** The scorer treats any
  ungraded book as irrelevant once an intent has grades, so partial intents are ignored
  (`status` shows which). Grade a whole intent, then move on.
- Language: both EN and TR queries of an intent share one judgment set, so one reviewer
  covers both; the Turkish phrasing needs no separate pass.
- A second reviewer on about 20% of rows (any intent) gives an agreement figure; do not average,
  adjudicate disagreements.

## Grades

| Grade | Meaning | Example (query: "Books like Dune") |
|---|---|---|
| 2 | Squarely answers the request | *Children of Dune* (same universe), *The Left Hand of Darkness* |
| 1 | Right broad area, weaker fit | A different epic fantasy; a Dune companion or art book |
| 0 | Wrong, lexical coincidence, study guide when novels were asked, or another edition of the seed itself | *Dune Buggy Repair*; a second edition of *Dune* |

Author queries ("George Orwell's books"): 2 = by Orwell; 0 = anything else, however popular
(*All Creatures Great and Small* is 0). Genre/topic: judge the book, not the blurb length.
Known-item descriptions: 2 = any edition of the wanted book, 0 otherwise.

Judge the book as a result for the **English** query text shown. Do not look up what a model
said; use title, author, categories and description in the sheet. Put doubts in `notes`.
