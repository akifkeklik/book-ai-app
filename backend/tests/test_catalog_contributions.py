import pytest
from backend.application.use_cases.catalog_contributions import (
    AddCatalogBookUseCase,
    CatalogContributionError,
    LookupBooksUseCase,
)
from backend.infrastructure.adapters.book_lookup_adapter import BookLookupAdapter
from backend.infrastructure.ml.recommender import BookRecommender

USER = "user-1"


def _catalog():
    rec = BookRecommender()
    rec.load_from_dicts(
        [
            {"isbn13": "9780000000101", "title": "Atomic Habits", "authors": "James Clear", "categories": "Self-Help",
             "description": "Habits.", "average_rating": 4.5, "ratings_count": 100, "published_date": "2018", "page_count": 320},
            {"isbn13": "9780000000102", "title": "Deep Work", "authors": "Cal Newport", "categories": "Business",
             "description": "Focus.", "average_rating": 4.2, "ratings_count": 80, "published_date": "2016", "page_count": 296},
        ]
    )
    rec.fit()
    return rec


class FakePort:
    def __init__(self, ok=True, fail=False):
        self.ok, self.fail, self.calls = ok, fail, []

    def add_book(self, book, user_token=None):
        self.calls.append((book, user_token))
        if self.fail:
            raise RuntimeError("db down")
        return self.ok


def test_adds_a_missing_book_and_makes_it_findable():
    rec = _catalog()
    port = FakePort()
    book, created, persisted = AddCatalogBookUseCase(rec, port).execute(
        USER,
        {"title": "  The   Psychology of Money ", "authors": "Morgan Housel", "isbn13": "978-0-85719-768-9",
         "categories": "Business", "page_count": "256", "published_date": "2020",
         "thumbnail": "https://books.google.com/books/content?id=x"},
        user_token="jwt-abc",
    )
    assert created and persisted
    assert book["isbn13"] == "9780857197689"
    assert book["title"] == "The Psychology of Money"
    assert rec.get_book_by_isbn("9780857197689")["authors"] == "Morgan Housel"
    titles = [b["title"] for b in rec.get_all_books(query="psychology of money")["books"]]
    assert "The Psychology of Money" in titles
    assert port.calls[0][1] == "jwt-abc"


def test_contributions_do_not_jump_ahead_of_established_books():
    rec = _catalog()
    AddCatalogBookUseCase(rec, None).execute(USER, {"title": "Brand New", "authors": "Someone"})
    popular = [b["title"] for b in rec.get_popular_books(limit=3)]
    assert popular[-1] == "Brand New"


def test_existing_books_are_returned_not_duplicated():
    rec = _catalog()
    uc = AddCatalogBookUseCase(rec, FakePort())
    same_isbn, created, _ = uc.execute(USER, {"title": "Other", "authors": "X", "isbn13": "9780000000101"})
    assert not created and same_isbn["title"] == "Atomic Habits"
    same_title, created, _ = uc.execute(USER, {"title": "atomic habits", "authors": "James Clear"})
    assert not created and same_title["isbn13"] == "9780000000101"
    assert len(rec.df) == 2


def test_books_without_isbn_get_a_url_safe_id():
    rec = _catalog()
    book, created, _ = AddCatalogBookUseCase(rec, None).execute(USER, {"title": "Zine", "authors": "Me"})
    assert created and book["isbn13"].startswith("lb") and len(book["isbn13"]) == 18
    assert book["isbn13"][2:].isalnum()


@pytest.mark.parametrize(
    "data, message",
    [
        ({"authors": "A"}, "title is required"),
        ({"title": "T"}, "authors is required"),
        ({"title": "T", "authors": "A", "isbn13": "12345"}, "isbn13"),
        ({"title": "T", "authors": "A", "page_count": "lots"}, "page_count"),
        ({"title": "T", "authors": "A", "page_count": 99999}, "page_count"),
        ({"title": "x" * 301, "authors": "A"}, "title exceeds"),
    ],
)
def test_invalid_input_is_rejected(data, message):
    with pytest.raises(CatalogContributionError, match=message):
        AddCatalogBookUseCase(_catalog(), None).execute(USER, data)


def test_untrusted_cover_urls_are_dropped():
    book, _, _ = AddCatalogBookUseCase(_catalog(), None).execute(
        USER, {"title": "T", "authors": "A", "thumbnail": "javascript:alert(1)"}
    )
    assert book["thumbnail"] == ""


def test_database_failure_still_adds_book_for_this_session():
    rec = _catalog()
    book, created, persisted = AddCatalogBookUseCase(rec, FakePort(fail=True)).execute(
        USER, {"title": "Offline Book", "authors": "A"}
    )
    assert created and not persisted
    assert rec.get_book_by_isbn(book["isbn13"])


# ── lookup ───────────────────────────────────────────────────────────────────


class FakeResponse:
    def __init__(self, payload, status=200):
        self._payload, self.status_code = payload, status

    def json(self):
        return self._payload


class FakeSession:
    def __init__(self, responses):
        self.responses, self.urls = responses, []

    def get(self, url, params=None, timeout=None):
        self.urls.append(url)
        return self.responses.pop(0)


def test_google_books_results_are_normalized(monkeypatch):
    from backend.config import Config

    monkeypatch.setattr(Config, "GOOGLE_BOOKS_API_KEY", "key")
    session = FakeSession([FakeResponse({"items": [{"volumeInfo": {
        "title": "Thinking", "subtitle": "Fast and Slow", "authors": ["Daniel Kahneman"],
        "categories": ["Psychology"], "pageCount": 499, "publishedDate": "2011-10-25",
        "industryIdentifiers": [{"type": "ISBN_13", "identifier": "9780374275631"}],
        "imageLinks": {"thumbnail": "http://books.google.com/books/content?id=1"},
    }}]})])
    [r] = BookLookupAdapter(session).search("thinking fast")
    assert r == {
        "isbn13": "9780374275631", "title": "Thinking: Fast and Slow", "authors": "Daniel Kahneman",
        "categories": "Psychology", "description": "", "page_count": 499, "published_date": "2011",
        "thumbnail": "https://books.google.com/books/content?id=1",
    }


def test_falls_back_to_open_library_when_google_fails(monkeypatch):
    from backend.config import Config

    monkeypatch.setattr(Config, "GOOGLE_BOOKS_API_KEY", "key")
    session = FakeSession([
        FakeResponse({}, status=429),
        FakeResponse({"docs": [{"title": "Sapiens", "author_name": ["Yuval Noah Harari"],
                                "isbn": ["0062316095", "9780062316097"], "first_publish_year": 2011,
                                "number_of_pages_median": 443, "cover_i": 12345}]}),
    ])
    [r] = BookLookupAdapter(session).search("sapiens")
    assert r["isbn13"] == "9780062316097"
    assert r["thumbnail"] == "https://covers.openlibrary.org/b/id/12345-M.jpg"
    assert "openlibrary.org" in session.urls[1]


def test_lookup_marks_books_already_in_catalog():
    class Lookup:
        def search(self, q):
            return [{"isbn13": "9780000000101", "title": "Atomic Habits", "authors": "James Clear"},
                    {"isbn13": "", "title": "Unknown Book", "authors": "Nobody"}]

    results = LookupBooksUseCase(Lookup(), _catalog()).execute("habits")
    assert results[0]["in_catalog_isbn"] == "9780000000101"
    assert results[1]["in_catalog_isbn"] is None


def test_short_queries_do_not_call_the_network():
    class Lookup:
        def search(self, q):
            raise AssertionError("should not be called")

    assert LookupBooksUseCase(Lookup(), _catalog()).execute(" a ") == []


# ── startup sync of contributions stored in the database ───────────────────


def test_bootstrap_adds_database_books_missing_from_the_trained_model(monkeypatch):
    from backend.services.book_service import BookService

    rec = _catalog()

    class Port:
        def get_all_isbns(self):
            return ["9780000000101", "9781111111111"]

        def get_books_by_isbns(self, isbns):
            assert isbns == ["9781111111111"]
            return [{"isbn13": "9781111111111", "title": "Contributed", "authors": "Reader"}]

    svc = BookService.__new__(BookService)
    svc.recommender, svc.book_data_port = rec, Port()
    svc._sync_contributed_books()
    assert rec.get_book_by_isbn("9781111111111")["title"] == "Contributed"


# ── HTTP API ─────────────────────────────────────────────────────────────────


@pytest.fixture
def api():
    from backend.app import create_app
    from backend.container import Container
    from backend.container import container as default_container
    from backend.routes.routes import rebind_container
    from backend.tests.test_learning_notes import DummyAuthPort, DummyInteractionRepo

    c = Container(
        interaction_repo=DummyInteractionRepo(),
        auth_port=DummyAuthPort({"token_a": "user-aaa"}),
        recommender=_catalog(),
    )
    rebind_container(c)
    app = create_app()
    app.config["TESTING"] = True
    try:
        yield app.test_client()
    finally:
        rebind_container(default_container)


def test_api_requires_a_signed_in_reader(api):
    assert api.post("/api/books", json={"title": "T", "authors": "A"}).status_code == 401
    assert api.get("/api/books/lookup?q=sapiens").status_code == 401


def test_api_adds_book_once_and_it_shows_up_in_the_catalog(api):
    headers = {"Authorization": "Bearer token_a"}
    first = api.post("/api/books", json={"title": "Range", "authors": "David Epstein"}, headers=headers)
    assert first.status_code == 201
    body = first.get_json()
    assert body["created"] is True and body["book"]["title"] == "Range"

    again = api.post("/api/books", json={"title": "range", "authors": "David Epstein"}, headers=headers)
    assert again.status_code == 200 and again.get_json()["created"] is False
    assert again.get_json()["book"]["isbn13"] == body["book"]["isbn13"]

    detail = api.get(f"/api/books/{body['book']['isbn13']}")
    assert detail.status_code == 200 and detail.get_json()["book"]["authors"] == "David Epstein"


def test_api_rejects_invalid_books(api):
    resp = api.post("/api/books", json={"title": "", "authors": "A"}, headers={"Authorization": "Bearer token_a"})
    assert resp.status_code == 400 and "title" in resp.get_json()["error"]


def test_added_books_keep_recommendations_working_and_are_recommendable():
    """Regression: catalog rows and TF-IDF rows must stay aligned after contributions."""
    rec = _catalog()
    uc = AddCatalogBookUseCase(rec, None)
    book, _, _ = uc.execute(USER, {"title": "Tiny Habits", "authors": "BJ Fogg", "categories": "Self-Help",
                                   "description": "Habits behaviour change small steps."})
    assert rec.engine.tfidf_matrix.shape[0] == len(rec.df)
    recs = rec.recommend(seed_titles=["9780000000101"], top_n=5)
    assert "Tiny Habits" in [r["title"] for r in recs]
    assert rec.recommend(seed_titles=[book["isbn13"]], top_n=5)
