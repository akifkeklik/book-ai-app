"""
The suggested questions on the AI discovery page must each reach the right path.

The preset strings are read from web/src/app/ai-discovery/page.tsx, so every language's chips
are covered and a changed chip cannot drift away from what the backend understands:

- "Do you have the book 1984?"  -> deterministic catalog hit for 1984, no LLM call
  (was: "the book 1984" was searched as a title, answered "no_match" and cached).
- "Books like Dune"             -> the catalog seed is resolved, so retrieval runs as
  semantic_seed_hybrid and Dune itself is never offered back
  (was: the seed was never found; TR "gibi" and DE "wie" were not even read as "similar").
- "A short philosophy book ..." -> semantic retrieval + grounded LLM answer.
- "Switch to dark mode"         -> SET_THEME action in every UI language
  (was: only EN/TR matched; "Dunklen Modus", "modo oscuro", "mode sombre", "modalità scura"
  fell through to book retrieval).

Offline: real BookRecommender on a small in-memory catalog; LLM, embedding and vector store are
mocks; sockets are refused. These tests pin routing and grounding, not LLM answer quality.
"""

import json
import re
import socket
from pathlib import Path
from unittest.mock import MagicMock

import pandas as pd
import pytest
from backend.application.use_cases.ai_rag import ProcessRagQueryUseCase
from backend.infrastructure.ml.recommender import BookRecommender
from backend.utils.preprocess import preprocess_dataframe

pytestmark = pytest.mark.unit

PAGE = Path(__file__).resolve().parents[2] / "web" / "src" / "app" / "ai-discovery" / "page.tsx"

ORWELL_1984 = "9780451524935"
ANIMAL_FARM_1984 = "9780452262935"
DUNE = "9780441172719"
CHAPTERHOUSE = "9780441102679"
FOUNDATION = "9780553293357"
HYPERION = "9780553283686"
SOPHIE = "9780425152256"
COOKBOOK = "9780000000305"

BOOKS = [
    (ORWELL_1984, "1984", "George Orwell", "Fiction", "dystopia totalitarian surveillance big brother", 4.2),
    (ANIMAL_FARM_1984, "Animal Farm and 1984", "George Orwell", "Fiction", "two classic political satires", 4.3),
    (DUNE, "Dune", "Frank Herbert", "Science Fiction", "desert planet spice empire prophecy", 4.3),
    (CHAPTERHOUSE, "Chapterhouse: Dune", "Frank Herbert", "Science Fiction", "the sisterhood on a desert world", 3.9),
    (FOUNDATION, "Foundation", "Isaac Asimov", "Science Fiction", "galactic empire psychohistory decline", 4.2),
    (HYPERION, "Hyperion", "Dan Simmons", "Science Fiction", "pilgrims on a distant planet empire", 4.2),
    (SOPHIE, "Sophie's World", "Jostein Gaarder", "Philosophy",
     "a short novel introducing the history of philosophy to beginners", 3.9),
    (COOKBOOK, "Garden Cookbook", "Dee Cook", "Cooking", "recipes vegetables garden kitchen", 4.0),
]
VECTOR_SCORES = {DUNE: 0.91, FOUNDATION: 0.83, HYPERION: 0.80, SOPHIE: 0.62}


def _presets():
    src = PAGE.read_text(encoding="utf-8")
    block = src[src.index("PROMPT_SUGGESTIONS_BY_LANG"):src.index("const suggestions")]
    out = []
    for lang, body in re.findall(r"^\s+(\w\w): \[(.*?)\]", block, re.M | re.S):
        chips = re.findall(r"'((?:[^'\\]|\\.)*)'", body)
        assert len(chips) == 4, f"{lang}: expected 4 suggestion chips, found {chips}"
        out += [(lang, i, chip.replace("\\'", "'")) for i, chip in enumerate(chips)]
    return out


PRESETS = _presets()
# Chip order on the page: existence check, similar-to-a-book, topic discovery, dark mode.
EXISTENCE, SIMILAR, TOPIC, DARK_MODE = 0, 1, 2, 3


def _ids(kind):
    return [pytest.param(q, id=f"{lang}:{q}") for lang, i, q in PRESETS if i == kind]


@pytest.fixture(autouse=True)
def _no_network(monkeypatch):
    def refuse(*args, **kwargs):
        raise AssertionError("network access attempted in an offline preset test")
    monkeypatch.setattr(socket.socket, "connect", refuse)
    monkeypatch.setattr(socket.socket, "connect_ex", refuse)
    monkeypatch.setattr(socket, "create_connection", refuse)


@pytest.fixture(scope="module")
def recommender():
    rec = BookRecommender()
    rec.engine.df = preprocess_dataframe(pd.DataFrame(
        [dict(isbn13=i, isbn10="", title=t, authors=a, categories=c, description=d,
              average_rating=r, ratings_count=1000) for i, t, a, c, d, r in BOOKS]))
    rec.fit()
    return rec


def _use_case(recommender):
    emb = MagicMock()
    emb.embed_query.return_value = [0.1, 0.2]
    port = MagicMock()
    port.match_query_embeddings.return_value = dict(VECTOR_SCORES)
    enrich = MagicMock()
    enrich.enrich.side_effect = lambda books: books
    llm = MagicMock()
    llm.generate_response.side_effect = lambda system, user: json.dumps({
        "answer": "Here are books from the Libris catalog.",
        "explanations": {},
    })
    return ProcessRagQueryUseCase(emb, port, None, recommender, enrich, llm), llm, emb


def _isbns(res):
    return [b["isbn13"] for b in res["referenced_books"]]


def test_every_language_has_the_four_chip_kinds():
    langs = {lang for lang, _, _ in PRESETS}
    assert langs == {"en", "tr", "de", "es", "fr", "it"}
    assert len(PRESETS) == 24


@pytest.mark.parametrize("query", _ids(EXISTENCE))
def test_existence_chip_finds_the_catalog_book_without_the_llm(recommender, query):
    uc, llm, emb = _use_case(recommender)
    res = uc.execute(query)
    assert res["status"] == "success", res["answer"]
    assert _isbns(res)[0] == ORWELL_1984
    assert "1984" in res["answer"]
    assert res["metrics"]["source"] == "deterministic_catalog_hit"
    llm.generate_response.assert_not_called()
    emb.embed_query.assert_not_called()


@pytest.mark.parametrize("query", _ids(SIMILAR))
def test_similar_chip_resolves_the_seed_and_never_returns_it(recommender, query):
    uc, llm, _ = _use_case(recommender)
    res = uc.execute(query)
    assert res["status"] == "success", res["answer"]
    assert res["metrics"]["retrieval_mode"] == "semantic_seed_hybrid"
    isbns = _isbns(res)
    assert isbns and DUNE not in isbns
    assert FOUNDATION in isbns and HYPERION in isbns
    llm.generate_response.assert_called_once()
    assert res["answer"] == "Here are books from the Libris catalog."


@pytest.mark.parametrize("query", _ids(TOPIC))
def test_topic_chip_uses_semantic_retrieval_and_the_llm(recommender, query):
    uc, llm, emb = _use_case(recommender)
    res = uc.execute(query)
    assert res["status"] == "success", res["answer"]
    assert res["metrics"]["retrieval_mode"] == "semantic"
    assert SOPHIE in _isbns(res)
    emb.embed_query.assert_called_once()
    llm.generate_response.assert_called_once()
    assert res["answer"] == "Here are books from the Libris catalog."


@pytest.mark.parametrize("query", _ids(DARK_MODE))
def test_dark_mode_chip_switches_the_theme_in_every_language(recommender, query):
    uc, llm, emb = _use_case(recommender)
    res = uc.execute(query)
    assert res["status"] == "action_executed"
    assert res["action"] == {"type": "SET_THEME", "payload": {"theme": "dark"}}
    llm.generate_response.assert_not_called()
    emb.embed_query.assert_not_called()


# ── The fixes must not widen what is matched ─────────────────────────────────


@pytest.mark.parametrize("query", [
    "Do you have the book Nonexistent Title?",
    "Gibt es das Buch Nonexistent Title?",
])
def test_existence_check_for_a_missing_book_still_answers_no_match(recommender, query):
    uc, llm, _ = _use_case(recommender)
    res = uc.execute(query)
    assert res["status"] == "no_match"
    assert res["referenced_books"] == []
    llm.generate_response.assert_not_called()


@pytest.mark.parametrize("query", [
    "a dark fantasy novel",
    "Un romanzo scuro e moderno",
    "un roman sombre",
    "una novela oscura",
    "ein dunkler Krimi",
])
def test_book_queries_with_dark_words_are_not_theme_commands(recommender, query):
    uc, _, _ = _use_case(recommender)
    assert uc.execute(query)["status"] != "action_executed"


@pytest.mark.parametrize("query", ["1984", "Dune", "Chapterhouse: Dune"])
def test_plain_title_lookup_is_unchanged(recommender, query):
    uc, _, _ = _use_case(recommender)
    titles = [b["title"] for b in uc._lookup_catalog_candidates(query)]
    assert titles and titles[0] == query


def test_stream_route_serves_a_preset_end_to_end(recommender, monkeypatch):
    """The Flask SSE route runs the real use case (offline) and the client sees books + answer."""
    from backend.app import create_app
    from backend.config import Config
    from backend.routes import routes

    class _Cfg(Config):
        TESTING = True
        DEBUG = False
        SECRET_KEY = "test-secret-key"
        LIBRIS_API_KEY = "test-api-key"

    uc, _, _ = _use_case(recommender)
    app = create_app(_Cfg)
    monkeypatch.setattr(routes, "_process_rag_query_uc", uc)
    routes._ai_rate_limits.clear()
    query = next(q for lang, i, q in PRESETS if lang == "en" and i == SIMILAR)
    with app.test_client() as client:
        res = client.post("/api/ai/chat/stream", json={"query": query})
        body = res.get_data(as_text=True)
    assert res.status_code == 200
    events = dict(re.findall(r"event: (\w+)\ndata: (.*)\n\n", body))
    assert "error" not in events
    done = json.loads(events["done"])
    assert done["status"] == "success"
    assert done["answer"] == "Here are books from the Libris catalog."
    assert DUNE not in [b["isbn13"] for b in done["referenced_books"]]
