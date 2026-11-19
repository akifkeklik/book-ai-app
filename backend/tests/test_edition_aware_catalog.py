"""
Regression tests for edition-aware identity (audit H3, L5, L6, L7, M1), on a real recommender.

Preprocessing merges editions of one work into a single row whose `edition_isbns` lists every
edition. A user's library, dislikes and the startup sync may reference any of those ISBNs.
"""

from unittest.mock import MagicMock

import pandas as pd
import pytest
from backend.application.use_cases.ai_rag import ProcessRagQueryUseCase
from backend.domain.ports import SemanticSearchUnavailable
from backend.infrastructure.ml.recommender import BookRecommender
from backend.services.book_service import BookService
from backend.utils.preprocess import preprocess_dataframe

A, B = "9780000000401", "9780000000402"          # two editions of "Galactic Fleet"
C = "9780000000403"                               # "Starship Captain", same author
HURSTON, OCONNOR = "9780000000404", "9780000000405"  # two different books, same title
SAGA = [f"97800000005{i:02d}" for i in range(60)]  # large-library filler


def _rows():
    rows = [
        dict(isbn13=A, title="Galactic Fleet", authors="Ann Author", categories="Science Fiction",
             description="space opera fleet starship admiral war", ratings_count=500),
        dict(isbn13=B, title="GALACTIC FLEET", authors="ann author", categories="Science Fiction",
             description="space opera fleet starship admiral war (paperback)", ratings_count=50),
        dict(isbn13=C, title="Starship Captain", authors="Ann Author", categories="Science Fiction",
             description="space opera starship captain fleet battle", ratings_count=300),
        dict(isbn13=HURSTON, title="The Complete Stories", authors="Zora Neale Hurston",
             categories="Fiction", description="short stories harlem florida folklore", ratings_count=200),
        dict(isbn13=OCONNOR, title="The Complete Stories", authors="Flannery O'Connor",
             categories="Fiction", description="short stories southern gothic georgia", ratings_count=210),
        dict(isbn13="9780000000406", title="Garden Cookbook", authors="Dee Cook", categories="Cooking",
             description="recipes vegetables garden kitchen", ratings_count=20),
    ]
    rows += [dict(isbn13=s, title=f"Space Saga {i}", authors=f"Writer {i}", categories="Science Fiction",
                  description=f"space fleet starship saga volume {i} " + ("nebula" if i % 2 else "comet"),
                  ratings_count=100 + i)
             for i, s in enumerate(SAGA)]
    for r in rows:
        r["average_rating"] = 4.0
    return rows


@pytest.fixture
def recommender():
    rec = BookRecommender()
    rec.engine.df = preprocess_dataframe(pd.DataFrame(_rows()))
    rec.fit()
    return rec


def _use_case(recommender, port, interactions):
    emb = MagicMock()
    emb.embed_query.return_value = [0.1, 0.2]
    repo = MagicMock()
    repo.get_user_interactions.return_value = interactions
    enrich = MagicMock()
    enrich.enrich.side_effect = lambda books: books
    llm = MagicMock()
    llm.generate_response.return_value = '{"answer": "ok", "explanations": {}}'
    return ProcessRagQueryUseCase(emb, port, repo, recommender, enrich, llm)


def test_editions_are_merged_into_one_row(recommender):
    df = recommender.df
    row = df[df["isbn13"] == A].iloc[0]
    assert set(row["edition_isbns"].split("|")) == {A, B}
    assert B not in set(df["isbn13"])
    assert recommender.edition_isbns([B]) == {A, B}


# ── H3: library exclusion covers every edition ───────────────────────────────

def test_semantic_rag_excludes_other_editions_of_library_books(recommender):
    port = MagicMock()
    port.match_query_embeddings.return_value = {A: 0.95, C: 0.80, HURSTON: 0.10}
    uc = _use_case(recommender, port, [{"book_id": B, "interaction_type": "finished"}])
    isbns = [b["isbn13"] for b in uc._retrieve_books_by_embedding([0.1], top_k=3, user_id="u1")]
    assert A not in isbns  # the user owns edition B of this very work
    assert isbns[0] == C


def test_lexical_fallback_excludes_other_editions_of_library_books(recommender):
    port = MagicMock()
    port.match_query_embeddings.side_effect = SemanticSearchUnavailable("down")
    uc = _use_case(recommender, port, [{"book_id": B, "interaction_type": "reading"}])
    res = uc.execute("space opera admiral", user_id="u1")  # matches A (owned as B) and C
    assert res["status"] == "lexical_fallback"
    assert A not in [b["isbn13"] for b in res["referenced_books"]]
    assert res["referenced_books"], "other relevant books are still returned"


@pytest.mark.parametrize("expose_edition_lookup", [True, False])
def test_rag_post_filter_is_edition_aware_even_if_the_ranker_ignores_exclusions(recommender, expose_edition_lookup):
    """Defence in depth: the RAG filter alone must drop other editions of owned books, using the
    ranker's edition lookup when it has one and the candidate's own edition_isbns otherwise."""
    rows = {i: recommender.df[recommender.df["isbn13"] == i].iloc[0].to_dict() for i in (A, C)}
    ranker = MagicMock(spec=["recommend", "df", "edition_isbns"] if expose_edition_lookup else ["recommend", "df"])
    ranker.recommend.return_value = [rows[A], rows[C]]  # ignores `exclude`
    ranker.df = recommender.df
    if expose_edition_lookup:
        ranker.edition_isbns = recommender.edition_isbns
    port = MagicMock()
    port.match_query_embeddings.return_value = {A: 0.9, C: 0.8}
    uc = _use_case(ranker, port, [{"book_id": B, "interaction_type": "favorite"}])
    isbns = [b["isbn13"] for b in uc._retrieve_books_by_embedding([0.1], top_k=3, user_id="u1")]
    assert isbns == [C]


def test_dislike_of_any_edition_is_still_excluded(recommender):
    port = MagicMock()
    port.match_query_embeddings.return_value = {A: 0.95, C: 0.80}
    uc = _use_case(recommender, port, [{"book_id": B, "interaction_type": "dislike"}])
    isbns = [b["isbn13"] for b in uc._retrieve_books_by_embedding([0.1], top_k=3, user_id="u1")]
    assert A not in isbns and C in isbns


def test_large_library_still_gets_the_requested_number_of_results(recommender):
    """40 owned books outrank everything else; RAG must still return top_k eligible books."""
    owned = SAGA[:40]
    scores = {s: 0.99 - i * 0.001 for i, s in enumerate(SAGA)}
    scores.update({A: 0.5, C: 0.49})
    port = MagicMock()
    port.match_query_embeddings.return_value = scores
    uc = _use_case(recommender, port, [{"book_id": s, "interaction_type": "finished"} for s in owned])
    isbns = [b["isbn13"] for b in uc._retrieve_books_by_embedding([0.1], top_k=5, user_id="u1")]
    assert len(isbns) == 5
    assert not set(isbns) & set(owned)
    # The ranking request stays bounded instead of growing with the library size.
    assert len(isbns) == len(set(isbns))


def test_recommender_exclude_applies_to_all_editions_before_ranking(recommender):
    recs = recommender.recommend(seed_titles=[C], top_n=5, use_diversity=False, exclude=[B])
    isbns = [r["isbn13"] for r in recs]
    assert A not in isbns and C not in isbns
    assert len(isbns) == 5
    popular = recommender.recommend(top_n=5, exclude=[B])  # popularity branch honours it too
    assert A not in [r["isbn13"] for r in popular] and len(popular) == 5


# ── L7: bounded lexical fallback ─────────────────────────────────────────────

def test_lexical_search_limit_is_capped_and_exclusions_do_not_consume_slots(recommender):
    hits = recommender.lexical_search("nebula comet", limit=10_000)
    assert len(hits) == BookRecommender.LEXICAL_SEARCH_MAX_LIMIT
    excluded = [h["isbn13"] for h in hits[:3]]
    again = recommender.lexical_search("nebula comet", limit=5, exclude=excluded)
    assert len(again) == 5 and not set(excluded) & {h["isbn13"] for h in again}


def test_rag_lexical_request_size_does_not_grow_with_library(recommender):
    recommender_spy = MagicMock(wraps=recommender)
    recommender_spy.df = recommender.df
    port = MagicMock()
    port.match_query_embeddings.side_effect = SemanticSearchUnavailable("down")
    uc = _use_case(recommender_spy, port, [{"book_id": s, "interaction_type": "finished"} for s in SAGA])
    res = uc.execute("nebula comet stories", user_id="u1")
    assert recommender_spy.lexical_search.call_args.kwargs["limit"] <= 10
    assert not {b["isbn13"] for b in res["referenced_books"]} & set(SAGA)


# ── L5: identity is the work, not the title ──────────────────────────────────

def test_distinct_books_with_the_same_title_both_survive_deduplication(recommender):
    popular = [b["isbn13"] for b in recommender.get_popular_books(limit=70)]
    assert HURSTON in popular and OCONNOR in popular
    recs = recommender.recommend(seed_titles=["9780000000406"], top_n=70, use_diversity=False)
    assert {HURSTON, OCONNOR} <= {r["isbn13"] for r in recs}

    port = MagicMock()
    port.match_query_embeddings.return_value = {HURSTON: 0.9, OCONNOR: 0.88}
    uc = _use_case(recommender, port, [])
    isbns = [b["isbn13"] for b in uc._retrieve_books_by_embedding([0.1], top_k=5)]
    assert HURSTON in isbns and OCONNOR in isbns


def test_disliking_one_same_title_book_does_not_hide_the_other(recommender):
    recs = recommender.recommend(seed_titles=["9780000000406"], top_n=70, use_diversity=True, dislikes=[HURSTON])
    isbns = {r["isbn13"] for r in recs}
    assert HURSTON not in isbns and OCONNOR in isbns


# ── L6: ISBN index invalidation ──────────────────────────────────────────────

def test_isbn_index_sees_in_place_dataframe_changes(recommender):
    engine = recommender.engine
    row = engine.find_index(A)
    assert engine.find_all_indices("9780000009999") == []
    engine.df.at[row, "edition_isbns"] = engine.df.at[row, "edition_isbns"] + "|9780000009999"
    assert engine.find_all_indices("9780000009999") == [row]
    engine.df.at[row, "isbn13"] = "9780000008888"
    assert engine.find_index("9780000008888") == row


def test_isbn_index_sees_reassignment(recommender):
    engine = recommender.engine
    assert engine.find_index("9780000007777") is None
    recommender.add_book(dict(isbn13="9780000007777", title="New Contribution", authors="Neo Writer"))
    assert engine.find_index("9780000007777") == len(engine.df) - 1


# ── M1: startup sync knows every edition ISBN ────────────────────────────────

def _service(recommender, db_rows):
    port = MagicMock()
    port.get_all_isbns.return_value = [r["isbn13"] for r in db_rows]
    by_isbn = {r["isbn13"]: r for r in db_rows}
    port.get_books_by_isbns.side_effect = lambda isbns: [by_isbn[i] for i in isbns if i in by_isbn]
    service = BookService.__new__(BookService)  # skip _bootstrap: the model is already "loaded"
    service.recommender, service.book_data_port, service.interaction_repo = recommender, port, None
    return service, port


def test_startup_sync_does_not_re_add_merged_editions(recommender):
    rows_before = len(recommender.df)
    db_rows = [dict(isbn13=r["isbn13"], title=r["title"], authors=r["authors"]) for r in _rows()]
    service, port = _service(recommender, db_rows)
    service._sync_contributed_books()
    assert len(recommender.df) == rows_before  # B is known through edition_isbns
    port.get_books_by_isbns.assert_not_called()


def test_startup_sync_adds_new_books_and_merges_new_editions(recommender):
    rows_before = len(recommender.df)
    new_edition = dict(isbn13="9780000000499", title="Galactic Fleet", authors="Ann Author")
    new_book = dict(isbn13="9780000000498", title="Reader Contribution", authors="Some Reader")
    db_rows = [dict(isbn13=A, title="Galactic Fleet", authors="Ann Author"), new_edition, new_book]
    service, _ = _service(recommender, db_rows)

    service._sync_contributed_books()
    assert len(recommender.df) == rows_before + 1  # only the genuinely new book is a new row
    assert recommender.engine.find_index("9780000000499") == recommender.engine.find_index(A)
    assert recommender.engine.find_index("9780000000498") is not None

    service._sync_contributed_books()  # idempotent on the next startup
    assert len(recommender.df) == rows_before + 1
