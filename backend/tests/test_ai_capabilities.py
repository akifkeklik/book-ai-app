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
    assert data["status"] == "success"
    # Transparently states that user is anonymous without history
    assert "oturum açmadığınız" in data["answer"] or "popüler" in data["answer"]
    assert len(data.get("referenced_books", [])) > 0


def test_llm_provider_unavailable_deterministic_fallback(client, auth_headers, monkeypatch):
    # Simulate LLM provider failure
    def mock_fail_response(system, user):
        raise RuntimeError("External LLM API unavailable: 503 Service Unavailable")

    monkeypatch.setattr(container.llm_port, "generate_response", mock_fail_response)

    resp = client.post(
        "/api/ai/chat",
        headers=auth_headers,
        data=json.dumps({"query": "1984 kitabı hakkında bilgi verir misin?"}),
    )
    assert resp.status_code == 200
    data = resp.get_json()
    # Falls back gracefully to deterministic catalog result without crashing
    assert data["status"] in ("llm_fallback", "success", "empty_retrieval", "embedding_failed")
    assert len(data.get("referenced_books", [])) > 0
    assert any("1984" in b.get("title", "") for b in data["referenced_books"])

