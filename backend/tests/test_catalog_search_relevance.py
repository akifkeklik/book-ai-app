import pytest
from backend.infrastructure.ml.recommender import BookRecommender


def _book(isbn, title, authors, description, popularity):
    return {
        "isbn13": isbn,
        "title": title,
        "authors": authors,
        "categories": "Self-Help",
        "description": description,
        "average_rating": 4.0,
        "ratings_count": 100,
        "popularity_score": popularity,
        "published_date": "2018",
    }


@pytest.fixture
def recommender():
    rec = BookRecommender()
    rec.load_from_dicts(
        [
            # Very popular, but only mentions the query in its description.
            _book("9780000000101", "The Naked Ape", "Desmond Morris", "Human habits and behaviour.", 0.99),
            _book("9780000000102", "Atomic Habits", "James Clear", "Tiny changes, remarkable results.", 0.40),
            _book("9780000000103", "Habits", "Anon Author", "A short essay.", 0.10),
            _book("9780000000104", "Deep Work", "Habits Writer", "Focus.", 0.20),
        ]
    )
    rec.fit()
    return rec


def _titles(result):
    return [b["title"] for b in result["books"]]


def test_default_search_ranks_title_matches_above_description_matches(recommender):
    titles = _titles(recommender.get_all_books(query="habits"))
    assert titles[0] == "Habits"  # exact title
    assert titles[1] == "Atomic Habits"  # title contains
    assert titles[2] == "Deep Work"  # author contains
    assert titles[-1] == "The Naked Ape"  # description only, despite highest popularity


def test_popularity_sort_keeps_relevance_first(recommender):
    titles = _titles(recommender.get_all_books(query="habits", sort="popularity", order="desc"))
    assert titles[0] == "Habits"
    assert titles[-1] == "The Naked Ape"


def test_explicit_sort_is_respected(recommender):
    titles = _titles(recommender.get_all_books(query="habits", sort="title", order="asc"))
    assert titles == sorted(titles)


def test_internal_relevance_column_is_not_exposed(recommender):
    books = recommender.get_all_books(query="habits")["books"]
    assert all("_relevance" not in b for b in books)
