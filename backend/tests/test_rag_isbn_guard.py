"""
ISBN grounding-guard detection rules (second review, findings G1-G3).

- G1: ISBNs written in any common form are seen: NFKC (full-width digits), dash variants, glued
  "ISBN" prefix, Turkish suffixes, space- or dot-separated groups. A 978/979 13-digit sequence is
  an ISBN claim even with an invalid checksum.
- G2: an unlabelled 10-digit number counts only when its ISBN-10 checksum is valid, so phone and
  order numbers do not reject a good answer. An explicit "ISBN" label always counts.
- G3: the ISBN-10 of a context book (derived from its valid 978 ISBN-13) is grounded.

Helpers are looked up on the module so each test fails on its own if a rule is missing.
"""

import json
from unittest.mock import MagicMock

import pytest
from backend.application.use_cases import ai_rag as rag
from backend.tests import test_rag_grounding as grounding

pytestmark = pytest.mark.unit
_no_network = grounding._no_network   # autouse: any socket connection fails the test


def tokens(text):
    return rag._isbn_like_tokens(text)


# ── G1: forms an ISBN can take ───────────────────────────────────────────────


@pytest.mark.parametrize("text, expected", [
    ("ISBN9781234567897", {"9781234567897"}),                       # glued prefix
    ("isbn9781234567897", {"9781234567897"}),
    ("ISBN-13:978-1-234-56789-7", {"9781234567897"}),
    ("ISBN-13: 978-1-234-56789-7", {"9781234567897"}),
    ("ISBN 13 9781234567897", {"9781234567897"}),
    ("ISBN-10: 0-306-40615-2", {"0306406152"}),
    ("9781234567897yi okuyun", {"9781234567897"}),                  # Turkish suffix, no apostrophe
    ("9781234567897'yi okuyun", {"9781234567897"}),
    ("9781234567897’ü okuyun", {"9781234567897"}),             # typographic apostrophe
    ("ISBN 0306406152'yi", {"0306406152"}),
    ("978 1 234 56789 7", {"9781234567897"}),                       # space-separated groups
    ("ISBN 978 1 234 56789 7", {"9781234567897"}),
    ("978.1.234.56789.7", {"9781234567897"}),                       # dot-separated groups
    ("978–1–234–56789–7", {"9781234567897"}),       # en dash
    ("978—1—234—56789—7", {"9781234567897"}),       # em dash
    ("978‑1‑234‑56789‑7", {"9781234567897"}),       # non-breaking hyphen
    ("978‐1‐234‐56789‐7", {"9781234567897"}),       # hyphen
    ("978‒1‒234‒56789‒7", {"9781234567897"}),       # figure dash
    ("978−1−234−56789−7", {"9781234567897"}),       # minus sign
    ("９７８１２３４５６７８９７", {"9781234567897"}),  # full-width digits (NFKC)
    ("978－1－234－56789－7", {"9781234567897"}),   # full-width hyphen-minus (NFKC)
])
def test_isbn_forms_are_detected(text, expected):
    assert tokens(text) == expected


@pytest.mark.parametrize("text", ["9781234567890", "978-1-234-56789-0", "9790000000001"])
def test_978_979_thirteen_digits_count_even_with_an_invalid_checksum(text):
    assert tokens(text) == {text.replace("-", "")}


def test_a_hyphenated_isbn13_is_not_also_read_as_an_isbn10():
    # "0-306-40615-7" inside it is not a separate ISBN-10 claim.
    assert tokens("978-0-306-40615-7") == {"9780306406157"}


def test_two_isbns_in_one_sentence_are_both_seen():
    assert tokens("Try ISBN 0-306-40615-2 or 978-1-234-56789-7.") == {"0306406152", "9781234567897"}


# ── G2: unlabelled 10-digit numbers need a valid ISBN-10 checksum ───────────


@pytest.mark.parametrize("text, expected", [
    ("0306406152", {"0306406152"}),
    ("0-306-40615-2", {"0306406152"}),
    ("080442957X", {"080442957X"}),          # check character X is kept
    ("0-8044-2957-x", {"080442957X"}),
    ("123456789X", {"123456789X"}),
])
def test_unlabelled_isbn10_with_a_valid_checksum_counts(text, expected):
    assert tokens(text) == expected


@pytest.mark.parametrize("text", [
    "call 555-123-4567",
    "call 5551234567",
    "+1 (555) 123-4567",
    "+90 532 123 45 67",
    "0532 123 45 67",
    "0532-123-45-67",
    "05321234567",
    "order 1234567890",
    "order no. 1122334455",
    "tracking 3125550199",
    "pages 12-34-56-78-90",
    "2024-11-20", "20.11.2024", "1984-1999",
    "1,234,567,890 readers",
    "12345678901234567890",
    "١٢٣٤٥٦٧٨٩٠",   # Arabic-Indic digits are not ISBN digits
    "lb0123456789abcdef",                          # catalog id of a book without ISBN
    "1234567890123",                               # 13 digits without a 978/979 prefix
])
def test_numbers_that_are_not_isbns_are_ignored(text):
    assert tokens(text) == set()


@pytest.mark.parametrize("text, expected", [
    ("ISBN 1234567890", {"1234567890"}),           # invalid checksum, but explicitly an ISBN
    ("ISBN: 0000000306", {"0000000306"}),
    ("ISBN-10 555-123-4567", {"5551234567"}),
    ("ISBN 1234567890123", {"1234567890123"}),      # labelled 13 digits, no 978/979 prefix
])
def test_an_explicit_isbn_label_counts_regardless_of_checksum(text, expected):
    assert tokens(text) == expected


def test_known_limit_a_checksum_valid_ten_digit_number_is_treated_as_an_isbn():
    # About 1 in 11 random 10-digit numbers has a valid ISBN-10 checksum; those still count.
    assert tokens("order 9876543210") == {"9876543210"}


# ── G3: context ISBN-10 derived from the context ISBN-13 ─────────────────────


@pytest.mark.parametrize("isbn13, isbn10", [
    ("9780306406157", "0306406152"),
    ("9780804429573", "080442957X"),               # derived ISBN-10 ending in X
    ("978-0-306-40615-7", "0306406152"),
])
def test_isbn10_is_derived_from_a_valid_978_isbn13(isbn13, isbn10):
    assert rag._isbn13_to_isbn10(isbn13) == isbn10
    assert isbn10 in rag._context_isbns([{"isbn13": isbn13}])


@pytest.mark.parametrize("isbn13", [
    "9791234567896",    # 979 has no ISBN-10
    "9780306406150",    # invalid ISBN-13 checksum
    "978030640615",     # too short
    "lb0123456789abcd",
    "",
])
def test_no_isbn10_is_invented_for_ineligible_isbn13(isbn13):
    assert rag._isbn13_to_isbn10(isbn13) is None
    assert {i for i in rag._context_isbns([{"isbn13": isbn13}]) if len(i) == 10} == set()


def test_derived_isbn10_makes_a_context_citation_grounded():
    books = [{"isbn13": "9780306406157"}]
    assert rag._ungrounded_isbns("See ISBN 0-306-40615-2.", books) == set()
    assert rag._ungrounded_isbns("See 0306406152.", books) == set()
    assert rag._ungrounded_isbns("See ISBN 080442957X.", books) == {"080442957X"}


# ── End to end through ProcessRagQueryUseCase (mocks only, no network) ──────


def _use_case(answer, books):
    emb = MagicMock()
    emb.embed_query.return_value = [0.1, 0.2]
    port = MagicMock()
    port.match_query_embeddings.return_value = {b["isbn13"]: 0.9 for b in books}
    recommender = MagicMock()
    recommender.recommend.return_value = [dict(b) for b in books]
    recommender.df = MagicMock(empty=True)
    enrich = MagicMock()
    enrich.enrich.side_effect = lambda b: b
    llm = MagicMock()
    llm.generate_response.return_value = json.dumps({"answer": answer, "explanations": {}})
    return rag.ProcessRagQueryUseCase(emb, port, None, recommender, enrich, llm)


BOOK = {"isbn13": "9780306406157", "title": "Context Book", "authors": "A. Writer"}


@pytest.mark.parametrize("answer", [
    "Call our shop on 555-123-4567 to order Context Book.",
    "Your order 1234567890 includes Context Book.",
    "Context Book (ISBN 0-306-40615-2) fits.",       # ISBN-10 of the context book
])
def test_grounded_answers_with_phone_order_or_context_isbn10_are_kept(answer):
    res = _use_case(answer, [BOOK]).execute("history of empires")
    assert res["status"] == "success"
    assert res["answer"] == answer


@pytest.mark.parametrize("answer", [
    "Read ISBN9781234567897 next.",
    "Read 978 1 234 56789 7 next.",
    "Read 978–1–234–56789–7 next.",
    "9781234567897yi okuyun.",
    "Read ISBN 1234567890 next.",
])
def test_out_of_context_isbns_in_new_forms_are_rejected(answer):
    res = _use_case(answer, [BOOK]).execute("history of empires")
    assert res["status"] == "llm_fallback"
    assert res["metrics"]["generation_rejected"] == "ungrounded_isbn"
