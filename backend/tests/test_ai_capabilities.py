import json

import pytest
from backend.app import create_app
from backend.config import Config
from backend.container import container
from backend.routes.routes import _ai_rate_limits


@pytest.fixture(autouse=True)
def reset_rate_limits():
    _ai_rate_limits.clear()
    yield
    _ai_rate_limits.clear()


@pytest.fixture
def app():
    class TestConfig(Config):
        TESTING = True
        DEBUG = False
        LIBRIS_API_KEY = "test-api-key"
        DATABASE_URL = None

    if container.recommender.df.empty:
        container.recommender.load_data("backend/data/books.csv")

    app = create_app(TestConfig)
    return app


@pytest.fixture
def client(app):
    return app.test_client()


@pytest.fixture
def auth_headers():
    return {
        "X-Api-Key": "test-api-key",
        "Content-Type": "application/json",
    }


def test_clock_intent_turkish(client, auth_headers):
    resp = client.post(
        "/api/ai/chat",
        headers=auth_headers,
        data=json.dumps({"query": "Bugün günlerden ne, saat kaç?"}),
    )
    assert resp.status_code == 200
    data = resp.get_json()
    assert data["status"] == "clock"
    assert "Bugün" in data["answer"]
    assert "saat" in data["answer"]
    assert "(TRT, UTC+3)" in data["answer"]
    assert len(data["referenced_books"]) == 0


def test_clock_intent_english(client, auth_headers):
    resp = client.post(
        "/api/ai/chat",
        headers=auth_headers,
        data=json.dumps({"query": "What day and time is it?"}),
    )
    assert resp.status_code == 200
    data = resp.get_json()
    assert data["status"] == "clock"
    assert "Today is" in data["answer"]
    assert "(TRT, UTC+3)" in data["answer"]


def test_action_intent_theme_dark(client, auth_headers):
    resp = client.post(
        "/api/ai/chat",
        headers=auth_headers,
        data=json.dumps({"query": "Görünümü koyu tema yap"}),
    )
    assert resp.status_code == 200
    data = resp.get_json()
    assert data["status"] == "action_executed"
    assert data["action"] is not None
    assert data["action"]["type"] == "SET_THEME"
    assert data["action"]["payload"]["theme"] == "dark"


def test_action_intent_palette_lavender(client, auth_headers):
    resp = client.post(
        "/api/ai/chat",
        headers=auth_headers,
        data=json.dumps({"query": "Vurgu rengini lavanta yap"}),
    )
    assert resp.status_code == 200
    data = resp.get_json()
    assert data["status"] == "action_executed"
    assert data["action"] is not None
    assert data["action"]["type"] == "SET_PALETTE"
    assert data["action"]["payload"]["palette"] == "lavender"


@pytest.mark.parametrize(
    "query, palette",
    [
        ("Switch the theme to Rose Quartz", "rose_quartz"),
        ("Temayı Nane Esintisi yap", "mint_breeze"),
        ("Set the palette to Lavender Dream", "lavender_dream"),
        ("Farbe Salbeigarten", "sage_garden"),
        ("Use the Arctic Sky theme", "arctic_sky"),
        ("Temayı Kiraz Kırmızısı yap", "cherry_red"),
        ("Switch the theme to Honey Gold", "honey_gold"),
        ("Temayı çivit yap", "indigo_dusk"),
        ("Use the graphite theme", "graphite_slate"),
    ],
)
def test_action_intent_palette_new_themes(client, auth_headers, query, palette):
    """The ten current themes are recognised by name; legacy names keep their legacy ids."""
    resp = client.post("/api/ai/chat", headers=auth_headers, data=json.dumps({"query": query}))
    data = resp.get_json()
    assert data["status"] == "action_executed"
    assert data["action"] == {"type": "SET_PALETTE", "payload": {"palette": palette}}


def test_action_intent_language_turkish(client, auth_headers):
    resp = client.post(
        "/api/ai/chat",
        headers=auth_headers,
        data=json.dumps({"query": "Uygulama dilini Türkçe yap"}),
    )
    assert resp.status_code == 200
    data = resp.get_json()
    assert data["status"] == "action_executed"
    assert data["action"]["type"] == "SET_LANGUAGE"
    assert data["action"]["payload"]["language"] == "tr"


def test_action_intent_navigate_library(client, auth_headers):
    resp = client.post(
        "/api/ai/chat",
        headers=auth_headers,
        data=json.dumps({"query": "Kütüphanemi aç"}),
    )
    assert resp.status_code == 200
    data = resp.get_json()
    assert data["status"] == "action_executed"
    assert data["action"]["type"] == "NAVIGATE"
    assert data["action"]["payload"]["url"] == "/favorites"


def test_exact_book_lookup_1984(client, auth_headers):
    resp = client.post(
        "/api/ai/chat",
        headers=auth_headers,
        data=json.dumps({"query": "1984 kitabı var mı?"}),
    )
    assert resp.status_code == 200
    data = resp.get_json()
    # Verified books exist in response
    books = data.get("referenced_books", [])
    assert len(books) > 0
    # Must contain 1984 or Animal Farm and 1984 by George Orwell
    titles = [b.get("title") for b in books]
    assert any("1984" in t for t in titles)
    orwell_books = [b for b in books if "George Orwell" in (b.get("authors") or "")]
    assert len(orwell_books) > 0


def test_missing_book_lookup_truthful(client, auth_headers):
    resp = client.post(
        "/api/ai/chat",
        headers=auth_headers,
        data=json.dumps({"query": "OlmayanHayaliKitap998877 kitabı var mı?"}),
    )
    assert resp.status_code == 200
    data = resp.get_json()
    assert data["status"] in ("empty_retrieval", "no_match")
    # Must NOT invent any book
    assert len(data.get("referenced_books", [])) == 0
    assert "bulunamadı" in data["answer"] or "couldn't find" in data["answer"].lower()


def test_rating_lookup_real_catalog(client, auth_headers):
    resp = client.post(
        "/api/ai/chat",
        headers=auth_headers,
        data=json.dumps({"query": "1984 kitabı kaç puan almış?"}),
    )
    assert resp.status_code == 200
    data = resp.get_json()
    assert data["status"] == "success"
    # Should report the real average rating
    assert "puan" in data["answer"]
    books = data.get("referenced_books", [])
    assert len(books) > 0
    target = [b for b in books if "1984" in b.get("title", "")][0]
    assert target.get("average_rating") is not None
    assert float(target.get("average_rating")) > 0


def test_author_lookup_real_catalog(client, auth_headers):
    resp = client.post(
        "/api/ai/chat",
        headers=auth_headers,
        data=json.dumps({"query": "1984'ün yazarı kim?"}),
    )
    assert resp.status_code == 200
    data = resp.get_json()
    assert data["status"] == "success"
    assert "George Orwell" in data["answer"]
    books = data.get("referenced_books", [])
    assert len(books) > 0
    assert any("George Orwell" in b.get("authors", "") for b in books)


def test_unauthenticated_save_guard(client, auth_headers):
    resp = client.post(
        "/api/ai/chat",
        headers=auth_headers,
        data=json.dumps({"query": "1984 kitabını favorilerime ekle"}),
    )
    assert resp.status_code == 200
    data = resp.get_json()
    assert data["status"] == "auth_required"
    assert "giriş yapmanız gerekmektedir" in data["answer"]
    assert data["action"] is not None
    assert data["action"]["type"] == "NAVIGATE"
    assert data["action"]["payload"]["url"] == "/login"


def test_unauthenticated_personal_shelf_guard(client, auth_headers):
    resp = client.post(
        "/api/ai/chat",
        headers=auth_headers,
        data=json.dumps({"query": "Kitaplığımda neler var?"}),
    )
    assert resp.status_code == 200
    data = resp.get_json()
    assert data["status"] == "auth_required"
    assert "lütfen giriş yapın" in data["answer"]
    assert data["action"] is not None
    assert data["action"]["type"] == "NAVIGATE"
    assert data["action"]["payload"]["url"] == "/login"


def test_unauthenticated_generic_recommendation(client, auth_headers):
    resp = client.post(
        "/api/ai/chat",
        headers=auth_headers,
        data=json.dumps({"query": "Bana bir kitap öner"}),
    )
    assert resp.status_code == 200
    data = resp.get_json()
    # Without embeddings/vector search (the test environment) this is the popularity fallback;
    # it may only claim "success" when semantic retrieval actually ran.
    assert data["status"] in ("success", "popular_fallback")
    assert (data["status"] == "success") == (data["metrics"]["degraded"] is False)
    # Transparently states that user is anonymous without history
    assert "oturum açmadığınız" in data["answer"] or "popüler" in data["answer"]
    assert len(data.get("referenced_books", [])) > 0


def test_llm_provider_unavailable_deterministic_fallback(client, auth_headers, monkeypatch):
    # Simulate LLM provider failure
    def mock_fail_response(system, user):
        raise RuntimeError("External LLM API unavailable: 503 Service Unavailable")

    monkeypatch.setattr(container.llm_port, "generate_response", mock_fail_response)
    monkeypatch.setattr(
        container.process_rag_query_uc,
        "_lookup_catalog_candidates",
        lambda _query: [{
            "isbn13": "9780451524935",
            "title": "1984",
            "authors": "George Orwell",
            "thumbnail": "",
            "average_rating": 4.6,
        }],
    )
    monkeypatch.setattr(
        container.process_rag_query_uc._enrichment_service,
        "enrich",
        lambda books: books,
    )

    resp = client.post(
        "/api/ai/chat",
        headers=auth_headers,
        data=json.dumps({"query": "1984 kitabı hakkında bilgi verir misin?"}),
    )
    assert resp.status_code == 200
    data = resp.get_json()
    # Falls back gracefully to deterministic catalog result without crashing
    assert data["status"] in ("llm_fallback", "success", "empty_retrieval")
    assert len(data.get("referenced_books", [])) > 0
    assert any("1984" in b.get("title", "") for b in data["referenced_books"])



@pytest.mark.parametrize("query, expected, foreign", [
    ("Temayı Lavanta Rüyası yap", "Lavanta Rüyası", "Lavender Dream"),
    ("Switch the theme to Rose Quartz", "Rose Quartz", "Gül Kuvarsı"),
    # A legacy name is confirmed as the theme the user will actually see after migration.
    ("Vurgu rengini kehribar yap", "Bal Altını", "Amber"),
])
def test_palette_confirmation_names_the_theme_in_the_query_language_only(client, auth_headers, query, expected, foreign):
    data = client.post("/api/ai/chat", headers=auth_headers, data=json.dumps({"query": query})).get_json()
    assert expected in data["answer"]
    assert foreign not in data["answer"] and "(" not in data["answer"]


def test_backend_theme_names_and_migrations_match_the_web_app():
    """The assistant's theme names and legacy map must not drift from web/src/lib (the UI's source of truth)."""
    import os
    import re as _re

    from backend.application.use_cases import ai_rag

    web = os.path.join(os.path.dirname(__file__), "..", "..", "web", "src", "lib")
    themes_ts = open(os.path.join(web, "themes.ts"), encoding="utf-8").read()
    ids = _re.findall(r"^  '([a-z_]+)',$", themes_ts.split("export const THEME_IDS")[1].split("] as const")[0], _re.M)
    assert ids and set(ids) == set(ai_rag._PALETTE_NAMES)
    legacy_block = themes_ts.split("export const LEGACY_THEME_MAP")[1].split("};")[0]
    legacy = dict(_re.findall(r"^  (\w+): '(\w+)',$", legacy_block, _re.M))
    assert legacy == ai_rag._LEGACY_PALETTE_TARGET

    i18n = open(os.path.join(web, "i18n.ts"), encoding="utf-8").read()
    for lang in ("en", "tr", "de"):
        # Each dictionary starts at "  <lang>: {" on its own line; read up to the next one.
        section = _re.split(rf"^  {lang}: \{{$", i18n, flags=_re.M)[1]
        for theme_id in ids:
            m = _re.search(rf"palette_{theme_id}: ['\"](.+?)['\"],", section)
            assert m, (lang, theme_id)
            assert ai_rag._PALETTE_NAMES[theme_id][lang] == m.group(1), (lang, theme_id)
