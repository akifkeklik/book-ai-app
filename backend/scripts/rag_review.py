"""Human-review workflow for the RAG judgment set (no network, no grades are ever invented).

    python -m backend.scripts.rag_review queue    # write evaluation/data/rag_review_queue.csv (blind, deduped, prioritised)
    python -m backend.scripts.rag_review status   # per-intent progress; which intents already count as human-verified
    python -m backend.scripts.rag_review apply    # copy graded queue rows back into rag_eval_judgments.csv

The reviewer fills `human_grade` (0/1/2) and `reviewed_by` in the queue only. `suggested` is the
dataset's own rule/proposal (UNVERIFIED) shown as a hint; it is never copied into `human_grade`.
The queue hides which system retrieved a book (blind review). Open-tier intents are excluded
because they are not scored.
"""
from __future__ import annotations

import argparse
import csv
import os
import sys
from collections import defaultdict

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")))

from backend.evaluation.retrieval import Catalog  # noqa: E402
from backend.scripts.run_rag_quality_eval import (  # noqa: E402
    JUDGMENT_FIELDS,
    JUDGMENTS,
    human_grades,
    load_dataset,
    load_judgment_rows,
)

QUEUE = os.path.join(os.path.dirname(JUDGMENTS), "rag_review_queue.csv")
QUEUE_FIELDS = ["priority", "intent", "query_en", "isbn", "title", "authors", "categories", "description",
                "suggested", "human_grade", "reviewed_by", "notes"]
# The 19 rule-derived queries first, then the 21 proposed ones, then the automatically generated
# candidates of the expansion set (data/rag_eval_expansion.json).
TIER_ORDER = {"rule_derived": 0, "proposed": 1, "automatic_candidate": 2}


def _queries():
    # Original set plus the expansion, so pooled rows of expansion intents can be queued too.
    return {q["intent"]: q for q in load_dataset()["queries"] if q["lang"] == "en"}


def queue(_a) -> None:
    cat, q = Catalog(), _queries()
    seen, out = set(), []
    for r in load_judgment_rows():
        if r["label_tier"] not in TIER_ORDER:
            continue
        work = cat.work_of.get(r["isbn"], r["isbn"])
        if (r["intent"], work) in seen:  # other editions of a work share one grade
            continue
        seen.add((r["intent"], work))
        b = cat.book(r["isbn"])
        out.append({"priority": TIER_ORDER[r["label_tier"]], "intent": r["intent"],
                    "query_en": q[r["intent"]]["text"], "isbn": r["isbn"], "title": r["title"],
                    "authors": r["authors"], "categories": b.get("categories", ""),
                    "description": (b.get("description") or "")[:240],
                    "suggested": "relevant (unverified)" if r["in_proposed_set"] == "1" else "",
                    "human_grade": r["human_grade"], "reviewed_by": r["reviewed_by"], "notes": r["notes"]})
    out.sort(key=lambda x: (x["priority"], x["intent"], x["title"].lower()))
    with open(QUEUE, "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=QUEUE_FIELDS)
        w.writeheader()
        w.writerows(out)
    print(f"{len(out)} rows to grade -> {os.path.relpath(QUEUE)}")


def apply(_a) -> None:
    done = {}
    with open(QUEUE, encoding="utf-8", newline="") as f:
        for r in csv.DictReader(f):
            g, who = r["human_grade"].strip(), r["reviewed_by"].strip()
            if g in ("0", "1", "2") and who:
                done[(r["intent"], r["isbn"])] = (g, who, r["notes"])
            elif g or who:
                print(f"skipped (needs grade 0/1/2 AND reviewer): {r['intent']} {r['isbn']} {r['title']}")
    cat, rows, n = Catalog(), load_judgment_rows(), 0
    by_work = {(r["intent"], cat.work_of.get(r["isbn"], r["isbn"])): v for r in rows
               if (v := done.get((r["intent"], r["isbn"])))}
    for r in rows:
        v = by_work.get((r["intent"], cat.work_of.get(r["isbn"], r["isbn"])))
        if v and not r["human_grade"]:
            r["human_grade"], r["reviewed_by"], r["notes"] = v[0], v[1], v[2] or r["notes"]
            n += 1
    with open(JUDGMENTS, "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=JUDGMENT_FIELDS)
        w.writeheader()
        w.writerows(rows)
    print(f"applied {n} human grades to {os.path.relpath(JUDGMENTS)}")


def status(_a) -> None:
    cat, rows = Catalog(), load_judgment_rows()
    complete = human_grades(rows, cat)
    per = defaultdict(lambda: [0, 0, ""])
    for r in rows:
        p = per[r["intent"]]
        p[0] += 1
        p[1] += r["human_grade"].strip() in ("0", "1", "2") and bool(r["reviewed_by"].strip())
        p[2] = r["label_tier"]
    print(f"{'intent':<18}{'tier':<14}{'graded':>8}  counts in report?")
    for i, (n, g, t) in sorted(per.items(), key=lambda kv: (TIER_ORDER.get(kv[1][2], 9), kv[0])):
        print(f"{i:<18}{t:<14}{g:>3}/{n:<4}  {'YES (human_verified)' if i in complete else 'no - ' + ('open tier, not scored' if t == 'open' else 'incomplete')}")
    print(f"\nhuman-verified intents: {len(complete)} of {sum(1 for v in per.values() if v[2] != 'open')} scorable")


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    for name, fn in (("queue", queue), ("apply", apply), ("status", status)):
        sub.add_parser(name).set_defaults(fn=fn)
    a = p.parse_args()
    a.fn(a)
