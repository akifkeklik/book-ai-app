"""
Unit and regression tests for Phase 9: Personalized Discovery & Recommender Engine.
"""

import pytest
from backend.application.use_cases.recommendations import GetPersonalizedRecommendationsUseCase
from backend.evaluation.metrics import (
    catalog_coverage,
    dislike_suppression_rate,
    ndcg_at_k,
    precision_at_k,
    recall_at_k,
)
from backend.infrastructure.ml.recommender import BookRecommender


class FakeEnrichmentService:
    def enrich(self, books):
        return books


class InMemoryInteractionRepo:
    def __init__(self):
        self.interactions = {}
        self.profiles = {}

    def get_user_interactions(self, user_id: str):
        return self.interactions.get(user_id, [])

    def get_user_profile(self, user_id: str):
        return self.profiles.get(user_id, {})

    def upsert_interactions(self, entries):
        for e in entries:
            uid = e["user_id"]
            self.interactions.setdefault(uid, []).append(e)

    def upsert_profile(self, user_id, genres, updated_at):
        self.profiles[user_id] = {"user_id": user_id, "preferred_genres": genres}

    def track_activity(self, payload):
        pass


@pytest.fixture
def recommender_with_books():
    books = [
        {
            "isbn13": "9780000000001",
            "title": "Dune",
            "authors": "Frank Herbert",
            "categories": "Science Fiction",
            "description": "Epic desert planet sci-fi with spice and worms.",
            "average_rating": 4.5,
            "ratings_count": 1000,
            "popularity_score": 0.9,
            "published_date": "1965",
        },
        {
            "isbn13": "9780000000002",
            "title": "Dune Messiah",
            "authors": "Frank Herbert",
            "categories": "Science Fiction",
            "description": "Continuation of Dune desert planet saga.",
            "average_rating": 4.2,
            "ratings_count": 800,
            "popularity_score": 0.85,
            "published_date": "1969",
        },
        {
            "isbn13": "9780000000003",
            "title": "Neuromancer",
            "authors": "William Gibson",
            "categories": "Science Fiction",
            "description": "Cyberpunk cyberspace matrix hackers.",
            "average_rating": 4.3,
            "ratings_count": 950,
            "popularity_score": 0.88,
            "published_date": "1984",
        },
        {
            "isbn13": "9780000000004",
            "title": "The Hobbit",
            "authors": "J.R.R. Tolkien",
            "categories": "Fantasy",
            "description": "Bilbo Baggins journey to the Lonely Mountain dragon.",
            "average_rating": 4.8,
            "ratings_count": 2000,
            "popularity_score": 0.98,
            "published_date": "1937",
        },
        {
            "isbn13": "9780000000005",
            "title": "The Fellowship of the Ring",
            "authors": "J.R.R. Tolkien",
            "categories": "Fantasy",
            "description": "Frodo Baggins epic quest with the One Ring in Mordor.",
            "average_rating": 4.9,
            "ratings_count": 2500,
            "popularity_score": 0.99,
            "published_date": "1954",
        },
        {
            "isbn13": "9780000000006",
            "title": "Pride and Prejudice",
            "authors": "Jane Austen",
            "categories": "Romance",
            "description": "Elizabeth Bennet and Mr Darcy classic regency romance.",
            "average_rating": 4.6,
            "ratings_count": 1800,
            "popularity_score": 0.92,
            "published_date": "1813",
        },
        {
            "isbn13": "9780000000007",
            "title": "Emma",
            "authors": "Jane Austen",
            "categories": "Romance",
            "description": "Matchmaking high society romance.",
            "average_rating": 4.1,
            "ratings_count": 600,
            "popularity_score": 0.75,
            "published_date": "1815",
        },
    ]
    rec = BookRecommender()
    rec.load_from_dicts(books)
    rec.fit()
    return rec


class TestPersonalizedRecommendationEngine:
    def test_weighted_seeds_favorites_have_higher_weight(self, recommender_with_books):
        # When seed_weights gives 2.0 to Dune and 1.0 to The Hobbit, Dune Messiah should rank higher than Fellowship
        recs = recommender_with_books.recommend(
            seed_titles=["9780000000001", "9780000000004"],
            seed_weights={"9780000000001": 2.5, "9780000000004": 0.5},
            top_n=3,
            use_diversity=False,
        )
        assert len(recs) > 0
        # Dune Messiah (sci-fi continuation) should be ranked first
        assert recs[0]["isbn13"] == "9780000000002"

    def test_dislike_suppression_in_recommender(self, recommender_with_books):
        # Disliking Dune Messiah must exclude it from recommendations completely
        recs = recommender_with_books.recommend(
            seed_titles=["9780000000001"],
            dislikes=["9780000000002"],
            top_n=5,
            use_diversity=True,
        )
        rec_isbns = [r["isbn13"] for r in recs]
        assert "9780000000002" not in rec_isbns
        assert "9780000000001" not in rec_isbns  # Seed is also excluded

    def test_dislike_author_penalty(self, recommender_with_books):
        # Disliking Jane Austen book suppresses other Jane Austen books
        recs = recommender_with_books.recommend(
            seed_titles=["9780000000004"],  # Fantasy seed
            dislikes=["9780000000006"],  # Disliked Pride and Prejudice
            top_n=5,
            use_diversity=False,
        )
        rec_isbns = [r["isbn13"] for r in recs]
        assert "9780000000006" not in rec_isbns
        # Emma should have suffered author penalty and not be ranked above Fellowship
        assert recs[0]["isbn13"] == "9780000000005"

    def test_find_index_robustness(self, recommender_with_books):
        engine = recommender_with_books.engine
        # Exact ISBN-13
        assert engine.find_index("9780000000001") is not None
        # Hyphenated ISBN
        assert engine.find_index("978-0-000-00000-1") is not None
        # Float-like string
        assert engine.find_index("9780000000001.0") is not None
        # Integer
        assert engine.find_index(9780000000001) is not None
        # Case-insensitive title
        assert engine.find_index("dune") is not None
        assert engine.find_index("DUNE") is not None
        # Quoted title
        assert engine.find_index('"Dune"') is not None
        # Unknown ISBN returns None gracefully
        assert engine.find_index("9999999999999") is None
        assert engine.find_index("") is None
        assert engine.find_index(None) is None

    def test_cold_start_profile_preferences(self, recommender_with_books):
        # A user with no seeds but preferred_genres=['Fantasy'] should receive fantasy books
        recs = recommender_with_books.recommend(
            seed_titles=[],
            preferred_genres=["Fantasy"],
            top_n=2,
            use_diversity=False,
        )
        assert len(recs) == 2
        rec_cats = [r["categories"] for r in recs]
        assert all("Fantasy" in c for c in rec_cats)
        assert (
            recs[0]["recommendation_reason"].startswith("Because you enjoy")
            or "Fantasy" in recs[0]["recommendation_reason"]
        )


class TestPersonalizedUseCaseFlow:
    def test_user_interaction_fusion_and_precedence(self, recommender_with_books):
        repo = InMemoryInteractionRepo()
        user_id = "user-alice"
        # Alice liked Dune, favorited Neuromancer, but disliked Dune Messiah
        repo.interactions[user_id] = [
            {"book_id": "9780000000001", "interaction_type": "like"},
            {"book_id": "9780000000003", "interaction_type": "favorite"},
            {"book_id": "9780000000002", "interaction_type": "dislike"},
        ]
        repo.profiles[user_id] = {
            "user_id": user_id,
            "preferred_genres": ["Science Fiction"],
        }

        use_case = GetPersonalizedRecommendationsUseCase(
            recommender=recommender_with_books,
            interaction_repo=repo,
            book_data_port=None,
            enrichment_service=FakeEnrichmentService(),
        )

        recs = use_case.execute(user_id=user_id, limit=5)
        rec_isbns = [r["isbn13"] for r in recs]

        # Disliked book must never be present
        assert "9780000000002" not in rec_isbns
        # Seed books must not be in recommendations
        assert "9780000000001" not in rec_isbns
        assert "9780000000003" not in rec_isbns

    def test_dislike_cancels_like_for_same_book(self, recommender_with_books):
        repo = InMemoryInteractionRepo()
        user_id = "user-bob"
        # User liked and later disliked the exact same book
        repo.interactions[user_id] = [
            {"book_id": "9780000000001", "interaction_type": "like"},
            {"book_id": "9780000000001", "interaction_type": "dislike"},
        ]

        use_case = GetPersonalizedRecommendationsUseCase(
            recommender=recommender_with_books,
            interaction_repo=repo,
            book_data_port=None,
            enrichment_service=FakeEnrichmentService(),
        )

        recs = use_case.execute(user_id=user_id, limit=5)
        rec_isbns = [r["isbn13"] for r in recs]
        # Must be completely suppressed
        assert "9780000000001" not in rec_isbns

    def test_cross_user_isolation(self, recommender_with_books):
        repo = InMemoryInteractionRepo()
        # Alice loves Sci-Fi
        repo.interactions["alice"] = [{"book_id": "9780000000001", "interaction_type": "like"}]
        # Charlie loves Romance
        repo.interactions["charlie"] = [{"book_id": "9780000000006", "interaction_type": "like"}]

        use_case = GetPersonalizedRecommendationsUseCase(
            recommender=recommender_with_books,
            interaction_repo=repo,
            book_data_port=None,
            enrichment_service=FakeEnrichmentService(),
        )

        alice_recs = use_case.execute(user_id="alice", limit=2)
        charlie_recs = use_case.execute(user_id="charlie", limit=2)

        alice_isbns = {r["isbn13"] for r in alice_recs}
        charlie_isbns = {r["isbn13"] for r in charlie_recs}

        # Charlie should get Emma, not Dune continuation
        assert "9780000000007" in charlie_isbns
        # Alice should get sci-fi, not romance
        assert "9780000000002" in alice_isbns

    def test_deterministic_recommendations(self, recommender_with_books):
        repo = InMemoryInteractionRepo()
        user_id = "user-determ"
        repo.interactions[user_id] = [{"book_id": "9780000000004", "interaction_type": "like"}]
        use_case = GetPersonalizedRecommendationsUseCase(
            recommender=recommender_with_books,
            interaction_repo=repo,
            book_data_port=None,
            enrichment_service=FakeEnrichmentService(),
        )

        recs_run1 = use_case.execute(user_id=user_id, limit=4)
        recs_run2 = use_case.execute(user_id=user_id, limit=4)

        isbns_1 = [r["isbn13"] for r in recs_run1]
        isbns_2 = [r["isbn13"] for r in recs_run2]
        assert isbns_1 == isbns_2


class TestEvaluationMetricsDirectly:
    def test_precision_recall_ndcg(self):
        ground_truth = {"B1", "B2", "B3"}
        recommended = ["B1", "X1", "B2", "X2", "X3"]

        p5 = precision_at_k(recommended, ground_truth, k=5)
        assert p5 == 2.0 / 5.0  # 0.4

        r5 = recall_at_k(recommended, ground_truth, k=5)
        assert r5 == 2.0 / 3.0  # 0.6667

        ndcg5 = ndcg_at_k(recommended, ground_truth, k=5)
        # DCG = 1/log2(2) + 1/log2(4) = 1.0 + 0.5 = 1.5
        # IDCG = 1/log2(2) + 1/log2(3) + 1/log2(4) = 1.0 + 0.6309 + 0.5 = 2.1309
        # NDCG = 1.5 / 2.1309 = ~0.7039
        assert 0.70 < ndcg5 < 0.71

    def test_dislike_suppression_metric(self):
        dislikes = {"D1", "D2"}
        clean_recs = ["B1", "B2", "B3"]
        assert dislike_suppression_rate(clean_recs, dislikes, k=3) == 1.0

        leaked_recs = ["B1", "D1", "B3"]
        assert dislike_suppression_rate(leaked_recs, dislikes, k=3) == 0.5

    def test_catalog_coverage_metric(self):
        all_recs = {"B1", "B2", "B3", "B4"}
        total_catalog = 100
        assert catalog_coverage(all_recs, total_catalog) == 0.04
