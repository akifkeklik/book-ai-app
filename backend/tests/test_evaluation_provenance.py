"""The offline evaluation separates provisional (LLM) labels from human-reviewed ones (audit §5)."""

import csv

from backend.evaluation.retrieval import (
    JUDGMENT_FIELDS,
    judgment_provenance,
    load_judgments,
    topic_split,
)


def _write(path, rows):
    with open(path, "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=JUDGMENT_FIELDS)
        w.writeheader()
        for r in rows:
            w.writerow({k: r.get(k, "") for k in JUDGMENT_FIELDS})


ROWS = [
    dict(task="query", topic_id="q1", work_id="a|x", grade="2", labeler="llm:model", reviewed_by=""),
    dict(task="query", topic_id="q1", work_id="b|y", grade="1", labeler="llm:model", reviewed_by="alice"),
    dict(task="query", topic_id="q2", work_id="c|z", grade="0", labeler="human:bob", reviewed_by="bob"),
    dict(task="query", topic_id="q2", work_id="d|w", grade="", labeler="", reviewed_by=""),
]


def test_reviewed_only_drops_provisional_labels(tmp_path):
    path = tmp_path / "j.csv"
    _write(path, ROWS)
    assert load_judgments(str(path)) == {"q1": {"a|x": 2, "b|y": 1}, "q2": {"c|z": 0}}
    assert load_judgments(str(path), reviewed_only=True) == {"q1": {"b|y": 1}, "q2": {"c|z": 0}}


def test_provenance_counts_labelers_and_reviews(tmp_path):
    path = tmp_path / "j.csv"
    _write(path, ROWS)
    assert judgment_provenance(str(path)) == {
        "graded_rows": 3, "human_reviewed_rows": 2, "unreviewed_rows": 1, "ungraded_rows": 1,
        "by_labeler": {"human:bob": 1, "llm:model": 2}, "topics_with_reviewed_judgments": 2,
    }


def test_topic_split_is_deterministic_and_keeps_a_heldout_share():
    ids = [f"en{i:02d}" for i in range(60)]
    assert [topic_split(i) for i in ids] == [topic_split(i) for i in ids]
    heldout = sum(topic_split(i) == "heldout" for i in ids)
    assert 10 <= heldout <= 30


def test_reviewed_only_run_refuses_to_score_without_reviews(tmp_path, capsys, monkeypatch):
    from backend.scripts import run_retrieval_evaluation as run

    q, s = tmp_path / "q.csv", tmp_path / "s.csv"
    _write(q, [ROWS[0]])
    _write(s, [ROWS[0]])
    monkeypatch.setattr(run, "QUERY_JUDGMENTS", str(q))
    monkeypatch.setattr(run, "SEED_JUDGMENTS", str(s))
    run.main(["evaluate", "--reviewed-only", "--report-dir", str(tmp_path / "out")])
    assert "No human-reviewed judgments" in capsys.readouterr().out
    assert not (tmp_path / "out").exists()
