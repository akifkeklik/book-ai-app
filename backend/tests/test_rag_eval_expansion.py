"""
Offline tests for the expanded RAG evaluation set (data/rag_eval_expansion.json) and the dataset
loading, category filter and CSV export of backend/scripts/run_rag_quality_eval.py.
No network, no Gemini, no database.
"""

import csv
import json
from collections import Counter

import pytest
from backend.evaluation.retrieval import Catalog
from backend.scripts import build_rag_eval_expansion as builder
from backend.scripts import rag_review
from backend.scripts import run_rag_quality_eval as ev

pytestmark = pytest.mark.unit


@pytest.fixture(scope="module")
def catalog():
    return Catalog()


@pytest.fixture(scope="module")
def expansion():
    return json.load(open(ev.EXPANSION, encoding="utf-8"))


@pytest.fixture(scope="module")
def base():
    return json.load(open(ev.DATASET, encoding="utf-8"))


# ── The dataset ──────────────────────────────────────────────────────────────

def test_committed_expansion_is_exactly_what_the_builder_produces():
    # Reproducibility: every label comes from the recorded rule over the catalog snapshot.
    assert open(ev.EXPANSION, encoding="utf-8").read() == builder._dump(builder.build())


def test_combined_set_has_at_least_100_queries_across_at_least_10_categories():
    data = ev.load_dataset()
    cats = Counter(q["category"] for q in data["queries"])
    assert len(data["queries"]) >= 100
    assert len(cats) >= 10
    for required in ("no_relevant", "insufficient_info", "multi_constraint", "mood", "exact_title",
                     "author", "genre", "topic", "similar", "semantic_description", "ambiguous"):
        assert cats[required] >= 4, required


def test_every_expansion_intent_is_asked_in_english_and_turkish(expansion):
    langs = {}
    for q in expansion["queries"]:
        langs.setdefault(q["intent"], set()).add(q["lang"])
    assert all(v == {"en", "tr"} for v in langs.values())


def test_query_ids_are_unique_across_both_files():
    ids = [q["id"] for q in ev.load_dataset()["queries"]]
    assert len(ids) == len(set(ids))


def test_no_expansion_label_claims_human_review(expansion):
    assert expansion["human_verified"] is False
    assert {q["label_tier"] for q in expansion["queries"]} == {"automatic_candidate"}
    for q in expansion["queries"]:
        assert "human_grade" not in q and "reviewed_by" not in q
        assert q["label_rule"] and "not reviewed" in q["notes"]


def test_every_expected_isbn_is_a_real_catalog_record(expansion, catalog):
    for q in expansion["queries"]:
        for isbn in q["expected_isbns"]:
            assert isbn in catalog.row_of, (q["id"], isbn)


def test_required_fields_and_vocabularies(expansion):
    for q in expansion["queries"]:
        for field in ("id", "text", "lang", "category", "difficulty", "expected_isbns", "expected_behavior",
                      "label_tier", "label_rule", "notes"):
            assert field in q, (q["id"], field)
        assert q["category"] in builder.CATEGORIES
        assert q["expected_behavior"] in builder.BEHAVIOURS
        assert q["difficulty"] in ("easy", "medium", "hard")


def test_behaviour_only_queries_have_no_relevant_set_and_scored_ones_do(expansion):
    for q in expansion["queries"]:
        if q["category"] in ("no_relevant", "insufficient_info", "ambiguous"):
            assert q["expected_isbns"] == [] and q["expected_behavior"] != "retrieve_relevant"
        else:
            assert q["expected_isbns"] and q["expected_behavior"] == "retrieve_relevant"


def test_no_relevant_queries_name_works_the_catalog_really_lacks(expansion, catalog):
    absent = {s["intent"]: s["absent"] for s in builder.INTENTS if "absent" in s}
    assert absent, "no_relevant intents must record what was verified absent"
    df = builder._load(builder.CATALOG_CSV)
    for intent, spec in absent.items():
        assert builder._absent_matches(df, spec) == [], intent


def test_builder_refuses_a_no_relevant_query_the_catalog_can_answer(monkeypatch):
    # A real author now in the catalog must fail the build, not silently become a wrong label.
    spec = dict(intent="none_x", category="no_relevant", difficulty="medium", behaviour="abstain_not_in_catalog",
                en="Books by Agatha Christie", tr="Agatha Christie kitapları", rule=None,
                absent={"author": ["Agatha Christie"]})
    monkeypatch.setattr(builder, "INTENTS", [spec])
    with pytest.raises(ValueError, match="not a no-relevant query"):
        builder.build()


def test_builder_refuses_a_rule_that_matches_nothing(monkeypatch):
    spec = dict(intent="t_x", category="exact_title", difficulty="easy", en="x", tr="x",
                rule={"title": r"^No Such Book Title 123$"})
    monkeypatch.setattr(builder, "INTENTS", [spec])
    with pytest.raises(ValueError, match="matches no catalog record"):
        builder.build()


def test_rule_constraints_are_all_applied(catalog):
    df = builder._load(builder.CATALOG_CSV)
    short_king = builder.apply_rule(df, {"author": ["Stephen King"], "max_pages": 299})
    all_king = builder.apply_rule(df, {"author": ["Stephen King"]})
    assert short_king and set(short_king) < set(all_king)
    pages = df.set_index("isbn13")["_pages"]
    assert all(pages[i] <= 299 for i in short_king)


# ── Backward compatibility ───────────────────────────────────────────────────

def test_original_queries_are_loaded_unchanged(base):
    loaded = {q["id"]: q for q in ev.load_dataset()["queries"]}
    for q in base["queries"]:
        got = loaded[q["id"]]
        for k, v in q.items():
            assert got[k] == v, (q["id"], k)
        assert got["dataset"] == "base"
        assert got["category"] == ev.TYPE_TO_CATEGORY[q["type"]]


def test_base_only_loading_matches_the_original_file(base):
    data = ev.load_dataset(include_expansion=False)
    assert [q["id"] for q in data["queries"]] == [q["id"] for q in base["queries"]]
    assert set(data["dataset_versions"]) == {"base"}


def test_original_tiers_are_still_scored_and_automatic_candidates_are_too():
    assert {"rule_derived", "proposed", "automatic_candidate", "human_verified"} <= set(ev.SCORED_TIERS)


def test_review_queue_accepts_expansion_rows():
    assert rag_review.TIER_ORDER["automatic_candidate"] > max(rag_review.TIER_ORDER["rule_derived"],
                                                              rag_review.TIER_ORDER["proposed"])
    queries = rag_review._queries()
    assert "author_king" in queries and "author_christie" in queries   # expansion and original intents


def test_human_grades_still_override_an_automatic_candidate(catalog):
    q = {"expected_isbns": [catalog.isbns[0]], "label_tier": "automatic_candidate"}
    human = {"intent_x": {"w": 2}}
    _, tier, _ = ev.grades_for("intent_x", q, catalog, human)
    assert tier == "human_verified"


# ── Category filter ──────────────────────────────────────────────────────────

def test_category_filter_keeps_only_those_categories():
    data = ev.load_dataset(categories=["no_relevant", "mood"])
    assert data["queries"] and {q["category"] for q in data["queries"]} == {"no_relevant", "mood"}


def test_unknown_category_is_an_error_not_an_empty_selection():
    with pytest.raises(ValueError, match="unknown categories"):
        ev.load_dataset(categories=["moood"])


def test_filtered_report_without_saved_results_exits_instead_of_writing(monkeypatch, tmp_path):
    saved = {"queries": [], "adversarial": []}
    path = tmp_path / "run.json"
    path.write_text(json.dumps(saved), encoding="utf-8")
    monkeypatch.setattr(ev, "REPORT_JSON", str(path))
    with pytest.raises(SystemExit) as exc:
        ev.report(type("A", (), {"category": ["no_relevant"]})())
    assert exc.value.code == 2


# ── Behaviour checks and CSV export ──────────────────────────────────────────

def _row(qid, answer="", status="success", grounding=None):
    return {"id": qid, "intent": qid.rsplit("_", 1)[0], "lang": qid.rsplit("_", 1)[1], "variant": None,
            "cold": {"answer": answer, "status": status, "source": "rag_llm", "grounding": grounding}}


def test_behaviour_checks_score_abstention_and_fabrication():
    qmap = {"none_shafak_en": {"expected_behavior": "abstain_not_in_catalog"},
            "none_sapiens_en": {"expected_behavior": "abstain_not_in_catalog"},
            "insuff_one_word_en": {"expected_behavior": "no_fabrication"},
            "insuff_blue_cover_en": {"expected_behavior": "no_fabrication"},
            "author_king_en": {"expected_behavior": "retrieve_relevant"}}
    rows = [_row("none_shafak_en", "Elif Shafak is not in our catalog, but you might like ..."),
            _row("none_sapiens_en", "Sapiens is a great read: 9780000000001"),
            _row("insuff_one_word_en", "Here are a few popular picks.", grounding={"foreign_isbns": [], "unsupported": False}),
            _row("insuff_blue_cover_en", "That is 9781111111111", grounding={"foreign_isbns": ["9781111111111"]}),
            _row("author_king_en", "anything")]
    out = ev.behaviour_checks(rows, qmap)
    assert out["abstain_not_in_catalog"] == {"n": 2, "passed": 1, "failures": ["none_sapiens_en"]}
    assert out["no_fabrication"] == {"n": 2, "passed": 1, "failures": ["insuff_blue_cover_en"]}


def test_query_csv_has_one_row_per_query_and_blank_cells_for_metrics_that_do_not_apply(tmp_path):
    data = ev.load_dataset(categories=["author", "no_relevant"])
    run_rows = [_row("author_king_en"), _row("none_shafak_en")]
    scored = {"id": "author_king_en", "tier": "automatic_candidate",
              "production_top5": {"hit@5": 1.0, "recall@5": 0.2, "recall@10": None},
              "semantic_rpc_top10": {"hit@5": 1.0, "recall@10": 0.3}, "semantic_exact_top10": None}
    doc = {"queries": run_rows, "evaluation": {"per_query": [scored]}}
    out = tmp_path / "q.csv"
    ev.write_query_csv(doc, data, str(out))
    rows = list(csv.DictReader(open(out, encoding="utf-8", newline="")))
    assert [r["id"] for r in rows] == ["author_king_en", "none_shafak_en"]
    king, shafak = rows
    assert king["category"] == "author" and king["label_tier"] == "automatic_candidate"
    assert king["production_top5.hit@5"] == "1.0" and king["production_top5.recall@10"] == ""
    assert king["semantic_rpc_top10.recall@10"] == "0.3"
    assert shafak["scored_tier"] == "" and shafak["expected_behavior"] == "abstain_not_in_catalog"
    assert all(shafak[f"production_top5.{k}"] == "" for k in ev.RETRIEVAL_METRIC_KEYS)


def test_dataset_composition_reports_coverage_of_the_run():
    data = ev.load_dataset()
    comp = ev.dataset_composition(data["queries"], {"author_king_en"})
    assert comp["queries"] == len(data["queries"]) and comp["in_this_run"] == 1
    assert comp["by_tier"]["automatic_candidate"] == 76
    assert comp["without_labelled_set"] == sum(1 for q in data["queries"] if not q["expected_isbns"])
