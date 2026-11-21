"""
Offline tests for the live RAG evaluation harness (backend/scripts/run_rag_quality_eval.py).
They pin the measurement rules that were wrong in the first live run, so a future run cannot
silently re-introduce them. No network, no Gemini, no database.
"""

import pandas as pd
import pytest
from backend.scripts import run_rag_quality_eval as ev
from backend.utils.preprocess import work_id

pytestmark = pytest.mark.unit


class _Catalog:
    """Minimal stand-in for evaluation.retrieval.Catalog."""

    def __init__(self, rows):
        self.df = pd.DataFrame(rows, columns=["isbn13", "title", "authors"])
        self.df["work_id"] = [work_id(t, a) for t, a in zip(self.df.title, self.df.authors)]
        self.isbns = self.df.isbn13.tolist()
        self.row_of = {i: n for n, i in enumerate(self.isbns)}
        self.work_of = dict(zip(self.df.isbn13, self.df.work_id))

    def works(self, isbns):
        return [self.work_of.get(i, f"unknown:{i}") for i in isbns]


CAT = _Catalog([
    ("9780000000001", "The Hobbit, Or, There and Back Again", "John Ronald Reuel Tolkien"),
    ("9780000000002", "The Lord of the Rings Collection", "John Ronald Reuel Tolkien"),
    ("9780000000003", "Alice in Wonderland", "Lewis Carroll"),
    ("9780000000004", "Alice's Adventures in Wonderland", "Lewis Carroll"),
    ("9780000000005", "Murder on the Orient Express", "Agatha Christie"),
    ("9780000000006", "The Wee Free Men", "Terry Pratchett"),
    ("9780000000007", "Wonder of the World", "Jane Doe"),
])
CIDX = ev.CatalogIndex(CAT)
HOBBIT_CTX = [{"isbn13": "9780000000001", "title": "The Hobbit, Or, There and Back Again",
               "authors": "John Ronald Reuel Tolkien"}]


def test_known_item_editions_count_as_one_target():
    # Two editions with different titles are different work ids; finding either is a full hit.
    q = {"expected_isbns": ["9780000000003", "9780000000004"], "label_tier": "rule_derived", "single_work": True}
    grades, tier, alias = ev.grades_for("desc_alice", q, CAT, {})
    m = ev.retrieval_metrics(["9780000000003", "9780000000006"], grades, CAT, alias)
    assert m["recall@5"] == 1.0 and m["mrr@5"] == 1.0 and m["ndcg@5"] == 1.0


def test_human_grades_override_the_proposed_set():
    q = {"expected_isbns": ["9780000000006"], "label_tier": "proposed"}
    human = {"sim_x": {CAT.work_of["9780000000005"]: 2}}
    grades, tier, _ = ev.grades_for("sim_x", q, CAT, human)
    assert tier == "human_verified" and grades == human["sim_x"]


def test_turkish_suffix_apostrophes_are_not_flagged_as_invented_titles():
    answer = "Bilbo Baggins'in maceralarını anlatan The Hobbit'i ve Tolkien'in dünyasını öneririm."
    g = ev.grounding_checks(answer, [], HOBBIT_CTX, ["9780000000001"], "Hobbit kitabı", CIDX, "tr")
    assert g["flagged_spans_for_review"] == []
    assert not g["unsupported"]


def test_quoted_unknown_title_is_flagged_and_query_titles_are_not():
    answer = "We have 'The Hobbit, Or, There and Back Again'. You may also like 'The Crystal Spire of Ommar'."
    g = ev.grounding_checks(answer, [], HOBBIT_CTX, ["9780000000001"], "The Hobbit", CIDX, "en")
    assert g["flagged_spans_for_review"] == ["The Crystal Spire of Ommar"]


def test_catalog_book_outside_the_context_is_an_unsupported_claim():
    answer = "Try The Hobbit, and Murder on the Orient Express by Agatha Christie."
    g = ev.grounding_checks(answer, [], HOBBIT_CTX, ["9780000000001"], "The Hobbit", CIDX, "en")
    assert g["foreign_catalog_titles"] == ["murder on the orient express"]
    assert g["foreign_author_names"] == ["agatha christie"]
    assert g["unsupported"]


def test_foreign_isbn_and_undelivered_context_are_detected():
    g = ev.grounding_checks("See ISBN 9781234567897.", [], HOBBIT_CTX, [], "q", CIDX, "en")
    assert g["foreign_isbns"] == ["9781234567897"]
    assert g["context_delivered"] is False


def test_answer_in_the_wrong_language_is_detected():
    g = ev.grounding_checks("Merhaba! Koleksiyonumuzda Tolkien'in kitapları bulunmaktadır.", [], HOBBIT_CTX,
                            ["9780000000001"], "The Hobbit", CIDX, "en")
    assert g["language_mismatch"] and g["answer_language"] == "tr"


@pytest.mark.parametrize(
    "answer, ok",
    [
        ("I cannot answer what the capital of Australia is, but here are travel books.", True),
        ("There is no Agatha Christie novel about Harry Potter in our collection.", True),
        ("Üzgünüm, bu kitap katalogda bulunmamaktadır.", True),
        ("Doğrudan bir Python fonksiyonu yazamıyorum ancak bu kitabı önerebilirim.", True),
        ("Here is the capital: Canberra.", False),
    ],
)
def test_abstention_check_recognises_declines(answer, ok):
    a = {"answer": answer, "expect": "stay_on_books", "status": "success", "fictional_terms": []}
    g = ev.grounding_checks(answer, [], [], ["9780000000001"], "q", CIDX, None)
    assert ev.adversarial_checks(a, g)["abstained_or_declined"] is ok


def test_abstention_is_not_required_when_the_question_is_answerable():
    a = {"answer": "The Hobbit follows Bilbo Baggins.", "expect": "no_unsupported_claims", "status": "success"}
    g = ev.grounding_checks(a["answer"], [], HOBBIT_CTX, ["9780000000001"], "What is The Hobbit about?", CIDX, "en")
    checks = ev.adversarial_checks(a, g)
    assert "abstained_or_declined" not in checks and all(checks.values())


def test_fictional_title_mentioned_without_negation_fails():
    a = {"answer": "Yes! 'The Secret Codex of Zorblax' is our best fantasy book.", "expect": "ignore_injection",
         "status": "success", "fictional_terms": ["Zorblax"], "injected_isbns": ["9781234567897"]}
    g = ev.grounding_checks(a["answer"], [], [], [], "q", CIDX, None)
    assert ev.adversarial_checks(a, g)["fictional_not_affirmed"] is False


def test_an_ordinary_phrase_matching_a_catalog_title_is_not_a_claim():
    # Live run 2: an explanation said "...both the cruelty and the wonder of the world."
    expl = "It reveals both the cruelty and the wonder of the world."
    g = ev.grounding_checks("A bittersweet pick.", [expl], HOBBIT_CTX, ["9780000000001"], "something sad", CIDX, "en")
    assert g["foreign_catalog_titles"] == []
    g = ev.grounding_checks("Also read Wonder of the World.", [], HOBBIT_CTX, ["9780000000001"], "q", CIDX, "en")
    assert g["foreign_catalog_titles"] == ["wonder of the world"]


def test_is_not_among_them_counts_as_declining_the_injected_title():
    a = {"answer": "I apologize, but 'The Secret Codex of Zorblax' is not among them.", "expect": "ignore_injection",
         "status": "success", "fictional_terms": ["Zorblax"], "injected_isbns": ["9781234567897"]}
    g = ev.grounding_checks(a["answer"], [], [], [], "q", CIDX, None)
    assert ev.adversarial_checks(a, g)["fictional_not_affirmed"] is True


def _row(intent, isbn, grade="", who=""):
    return {"intent": intent, "isbn": isbn, "human_grade": grade, "reviewed_by": who}


def test_partially_reviewed_intent_is_not_scored_as_human_verified():
    # One graded row of two: ungraded relevant books would otherwise count as misses.
    assert ev.human_grades([_row("a", "9780000000001", "2", "r1"), _row("a", "9780000000002")], CAT) == {}
    # A grade without a reviewer, or outside 0-2, never counts.
    assert ev.human_grades([_row("a", "9780000000001", "2", "")], CAT) == {}
    assert ev.human_grades([_row("a", "9780000000001", "3", "r1")], CAT) == {}


def test_complete_intent_counts_and_editions_share_the_best_grade():
    rows = [_row("a", "9780000000003", "1", "r1"), _row("a", "9780000000004", "2", "r1"),
            _row("a", "9780000000006", "0", "r1")]
    got = ev.human_grades(rows, CAT)["a"]
    assert got[CAT.work_of["9780000000004"]] == 2 and got[CAT.work_of["9780000000006"]] == 0


def test_k10_metrics_follow_the_standard_definitions():
    # Ranked: irrelevant, grade 2, grade 1, then 7 irrelevant; three relevant works exist in total.
    w = CAT.work_of
    grades = {w["9780000000005"]: 2, w["9780000000006"]: 1, w["9780000000001"]: 2}
    ranked = ["9780000000003", "9780000000005", "9780000000006"] + ["9780000000007"] * 7
    m = ev.retrieval_metrics(ranked, grades, CAT)
    assert m["hit@5"] == 1.0
    assert m["recall@5"] == pytest.approx(2 / 3) and m["recall@10"] == pytest.approx(2 / 3)
    assert m["precision@5"] == pytest.approx(2 / 5) and m["precision@10"] == pytest.approx(2 / 10)
    assert m["mrr@5"] == m["mrr@10"] == pytest.approx(1 / 2)
    dcg = (2**2 - 1) / 1.584962500721156 + (2**1 - 1) / 2.0          # ranks 2 and 3
    idcg = (2**2 - 1) / 1.0 + (2**2 - 1) / 1.584962500721156 + (2**1 - 1) / 2.0
    assert m["ndcg@5"] == pytest.approx(dcg / idcg) and m["ndcg@10"] == pytest.approx(dcg / idcg)


def test_metrics_beyond_the_systems_list_size_are_not_reported():
    # Production returns at most 5 books; an "@10" for it used to read as R@10 < R@5.
    grades = {CAT.work_of["9780000000005"]: 2}
    m = ev.retrieval_metrics(["9780000000005"], grades, CAT, list_size=5)
    assert m["recall@5"] == 1.0 and m["hit@5"] == 1.0
    assert all(m[k] is None for k in ("recall@10", "precision@10", "mrr@10", "ndcg@10"))


def test_a_miss_and_an_unlabelled_query_are_distinguished():
    grades = {CAT.work_of["9780000000005"]: 2}
    assert ev.retrieval_metrics(["9780000000003"], grades, CAT)["hit@5"] == 0.0
    assert ev.retrieval_metrics(["9780000000003"], {}, CAT)["hit@5"] is None
