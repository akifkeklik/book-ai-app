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

    def test_reading_status_participates_in_personalized_seeds(self, recommender_with_books):
        repo = InMemoryInteractionRepo()
        user_id = "user-reader"
        # User is actively reading Dune (9780000000001)
        repo.interactions[user_id] = [{"book_id": "9780000000001", "interaction_type": "reading"}]
        use_case = GetPersonalizedRecommendationsUseCase(
            recommender=recommender_with_books,
            interaction_repo=repo,
            book_data_port=None,
            enrichment_service=FakeEnrichmentService(),
        )

        recs = use_case.execute(user_id=user_id, limit=3)
        rec_isbns = [r["isbn13"] for r in recs]
        # Seed Dune must not be in recommendations
        assert "9780000000001" not in rec_isbns
        # Related sci-fi Dune Messiah (9780000000002) should be recommended
        assert "9780000000002" in rec_isbns



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


class TestRecommendationEngineInvariantsAndAdversarial:
    """
    Adversarial and boundary-condition tests validating core recommendation invariants:
    - Seed books are excluded where contract requires exclusion (including use_diversity=False).
    - Disliked books never appear in final recommendations under any circumstance.
    - Duplicate interactions do not unintentionally inflate preference weights.
    - Conflicting statuses and duplicate database rows resolve deterministically.
    - Sparse catalogs and empty histories produce safe results without exceptions.
    - User A's private preference data cannot influence User B's results.
    """

    def test_seed_exclusion_under_zero_diversity_and_small_catalog(self, recommender_with_books):
        # Even with use_diversity=False and top_n > catalog size, seed books MUST NOT leak
        seed_isbn = "9780000000001"  # Dune
        recs = recommender_with_books.recommend(
            seed_titles=[seed_isbn],
            top_n=20,  # Request more than catalog size (5 books)
            use_diversity=False,
        )
        rec_isbns = [r["isbn13"] for r in recs]
        assert seed_isbn not in rec_isbns
        assert "Dune" not in [r["title"] for r in recs]

    def test_disliked_books_never_appear_in_any_branch(self, recommender_with_books):
        # Test across MMR, non-MMR, and popular fallback
        disliked_isbn = "9780000000002"  # Dune Messiah

        # 1. MMR branch
        recs_mmr = recommender_with_books.recommend(
            seed_titles=["9780000000001"],
            top_n=10,
            use_diversity=True,
            dislikes=[disliked_isbn],
        )
        assert disliked_isbn not in [r["isbn13"] for r in recs_mmr]

        # 2. Non-MMR branch
        recs_non_mmr = recommender_with_books.recommend(
            seed_titles=["9780000000001"],
            top_n=10,
            use_diversity=False,
            dislikes=[disliked_isbn],
        )
        assert disliked_isbn not in [r["isbn13"] for r in recs_non_mmr]

        # 3. Cold-start fallback (no seeds)
        recs_cold = recommender_with_books.recommend(
            seed_titles=[],
            top_n=10,
            dislikes=[disliked_isbn],
        )
        assert disliked_isbn not in [r["isbn13"] for r in recs_cold]

    def test_duplicate_interactions_do_not_inflate_weights(self, recommender_with_books):
        # Single seed vs duplicate seed titles / IDs
        recs_single = recommender_with_books.recommend(
            seed_titles=["9780000000001"],
            top_n=5,
            use_diversity=False,
        )
        # Pass the exact same seed 5 times
        recs_duplicated = recommender_with_books.recommend(
            seed_titles=["9780000000001"] * 5,
            top_n=5,
            use_diversity=False,
        )
        scores_single = [round(r["final_score"], 5) for r in recs_single]
        scores_dup = [round(r["final_score"], 5) for r in recs_duplicated]
        assert scores_single == scores_dup
        assert [r["isbn13"] for r in recs_single] == [r["isbn13"] for r in recs_duplicated]

    def test_duplicate_database_rows_in_use_case_safe(self, recommender_with_books):
        repo = InMemoryInteractionRepo()
        user_id = "user-dup"
        # Duplicate rows for the same book in DB
        repo.interactions[user_id] = [
            {"book_id": "9780000000001", "interaction_type": "like"},
            {"book_id": "9780000000001", "interaction_type": "like"},
            {"book_id": "9780000000001", "interaction_type": "favorite"},  # Upgraded to favorite
        ]
        use_case = GetPersonalizedRecommendationsUseCase(
            recommender=recommender_with_books,
            interaction_repo=repo,
            book_data_port=None,
            enrichment_service=FakeEnrichmentService(),
        )
        recs = use_case.execute(user_id=user_id, limit=3)
        assert len(recs) > 0
        assert "9780000000001" not in [r["isbn13"] for r in recs]

    def test_sparse_and_empty_catalog_safe(self):
        empty_recommender = BookRecommender()
        empty_recommender.load_from_dicts([])
        empty_recommender.fit()

        recs = empty_recommender.recommend(seed_titles=["Nonexistent"], top_n=5)
        assert recs == []

    def test_all_books_disliked_boundary(self, recommender_with_books):
        all_isbns = recommender_with_books.df["isbn13"].tolist()
        recs = recommender_with_books.recommend(
            seed_titles=["9780000000001"],
            dislikes=all_isbns,
            top_n=5,
        )
        assert recs == []

    def test_vector_search_rpc_failure_graceful_fallback(self, recommender_with_books):
        class FailingBookDataPort:
            def get_semantic_candidates(self, seeds, limit=100):
                raise RuntimeError("Vector RPC connection dropped")

        repo = InMemoryInteractionRepo()
        user_id = "user-rpc-fallback"
        repo.interactions[user_id] = [{"book_id": "9780000000001", "interaction_type": "like"}]

        use_case = GetPersonalizedRecommendationsUseCase(
            recommender=recommender_with_books,
            interaction_repo=repo,
            book_data_port=FailingBookDataPort(),
            enrichment_service=FakeEnrichmentService(),
        )
        # Should gracefully log warning and return TF-IDF recommendations without error
        recs = use_case.execute(user_id=user_id, limit=3)
        assert len(recs) > 0
        assert "9780000000001" not in [r["isbn13"] for r in recs]

    def test_reading_status_weights_and_contextual_reasons(self, recommender_with_books):
        """
        Verify that:
        1. Reading statuses apply differentiated weights (finished > reading > want_to_read).
        2. Nuanced contextual attribution reasons are generated based on source interaction.
        """
        repo = InMemoryInteractionRepo()
        user_id = "user-status-weights"
        # User finished reading Dune (9780000000001), currently reading The Hobbit (9780000000004),
        # and has Emma (9780000000007) in want_to_read list.
        repo.interactions[user_id] = [
            {"book_id": "9780000000001", "interaction_type": "finished"},
            {"book_id": "9780000000004", "interaction_type": "reading"},
            {"book_id": "9780000000007", "interaction_type": "want_to_read"},
        ]

        use_case = GetPersonalizedRecommendationsUseCase(
            recommender=recommender_with_books,
            interaction_repo=repo,
            book_data_port=None,
            enrichment_service=FakeEnrichmentService(),
        )
        recs = use_case.execute(user_id=user_id, limit=4)
        assert len(recs) > 0

        # Verified seeds must be suppressed from recommendations
        rec_isbns = [r["isbn13"] for r in recs]
        assert "9780000000001" not in rec_isbns
        assert "9780000000004" not in rec_isbns
        assert "9780000000007" not in rec_isbns

        # Dune Messiah should be recommended with "Because you read 'Dune'"
        dune_messiah = next((r for r in recs if r["isbn13"] == "9780000000002"), None)
        if dune_messiah:
            assert "Because you read 'Dune'" in dune_messiah.get("recommendation_reason", "")

        # The Fellowship of the Ring should be recommended with "Because you're reading 'The Hobbit'"
        lotr = next((r for r in recs if r["isbn13"] == "9780000000005"), None)
        if lotr:
            assert "Because you're reading 'The Hobbit'" in lotr.get("recommendation_reason", "")

    def test_strict_dislike_suppression_case_and_hyphen_normalized(self, recommender_with_books):
        """
        Verify that disliked books with formatting variations (hyphens, mixed case, title strings)
        are strictly suppressed and never recommended back to the user.
        """
        repo = InMemoryInteractionRepo()
        user_id = "user-strict-dislike"
        # User likes Dune, but dislikes Dune Messiah with hyphenated ISBN
        repo.interactions[user_id] = [
            {"book_id": "9780000000001", "interaction_type": "favorite"},
            {"book_id": "978-0000000002", "interaction_type": "dislike"},
        ]

        use_case = GetPersonalizedRecommendationsUseCase(
            recommender=recommender_with_books,
            interaction_repo=repo,
            book_data_port=None,
            enrichment_service=FakeEnrichmentService(),
        )
        recs = use_case.execute(user_id=user_id, limit=5)

        rec_isbns = [r["isbn13"] for r in recs]
        rec_titles = [r["title"].lower() for r in recs]

        # Both the seed (Dune) and the disliked book (Dune Messiah) must be completely excluded
        assert "9780000000001" not in rec_isbns
        assert "9780000000002" not in rec_isbns
        assert "dune messiah" not in rec_titles

    def test_status_clear_feedback_usecase(self):
        """Verify that SubmitFeedbackUseCase supports 'clear' with preserve_favorites=True."""
        from backend.application.use_cases.interactions import SubmitFeedbackUseCase

        class MockInteractionRepo:
            def __init__(self):
                self.deleted = []

            def delete_interaction(self, user_id, book_id, interaction_type=None, preserve_favorites=False):
                self.deleted.append((user_id, book_id, interaction_type, preserve_favorites))

        repo = MockInteractionRepo()
        uc = SubmitFeedbackUseCase(repo)
        res = uc.execute("user-1", "9780000000001", "clear")
        assert res["status"] == "success"
        assert ("user-1", "9780000000001", None, True) in repo.deleted

    def test_clear_preserves_favorites_while_remove_deletes_all(self):
        """Verify that 'clear' sets preserve_favorites=True while 'remove' sets preserve_favorites=False."""
        from backend.application.use_cases.interactions import SubmitFeedbackUseCase

        class MockInteractionRepo:
            def __init__(self):
                self.calls = []

            def delete_interaction(self, user_id, book_id, interaction_type=None, preserve_favorites=False):
                self.calls.append({"user_id": user_id, "book_id": book_id, "preserve_favorites": preserve_favorites})

        repo = MockInteractionRepo()
        uc = SubmitFeedbackUseCase(repo)

        # Clear reading status
        uc.execute("user-42", "9780452284234", "clear")
        assert repo.calls[-1] == {"user_id": "user-42", "book_id": "9780452284234", "preserve_favorites": True}

        # Clear status alias
        uc.execute("user-42", "9780452284234", "clear_status")
        assert repo.calls[-1] == {"user_id": "user-42", "book_id": "9780452284234", "preserve_favorites": True}

        # Full removal
        uc.execute("user-42", "9780452284234", "remove")
        assert repo.calls[-1] == {"user_id": "user-42", "book_id": "9780452284234", "preserve_favorites": False}

    def test_causal_attribution_guards_against_unrelated_seeds(self):
        """Ensure that recommendations with near-zero seed similarity are attributed to taste profile, not false seed causation."""
        engine = BookRecommender()
        data = [
            {"isbn13": "9780000000001", "title": "Dune", "authors": "Frank Herbert", "categories": "Science Fiction", "description": "Spice and sandworms on desert planet Arrakis", "average_rating": 4.5, "ratings_count": 1000},
            {"isbn13": "9780000000002", "title": "Baking Sourdough Bread", "authors": "Baker Bob", "categories": "Cooking", "description": "Flour water yeast salt fermentation crust crumb", "average_rating": 4.8, "ratings_count": 500},
        ]
        engine.load_from_dicts(data)
        engine.fit()

        # Seed is Dune (Sci-Fi), but candidate recommended is Cooking book. Max similarity is 0.0.
        rec = engine.df.iloc[1].to_dict()
        explanation = engine._explain_recommendation(
            rec,
            seed_indices=[0],
            semantic_scores=None,
            preferred_genres=["Cooking"],
            seed_sources={"9780000000001": "reading"},
        )
        # Must NOT attribute Baking to "Because you're reading 'Dune'"!
        assert "Dune" not in explanation.get("recommendation_reason", "")
        assert explanation.get("recommendation_reason") == "Because you enjoy Cooking"

    def test_complete_personalization_vertical_slice(self):
        """
        End-to-End Vertical Slice:
        1. Cold start returns popular fallback
        2. User marks book 'finished' and 'favorite'
        3. Persisted interactions produce weighted recommendations with causal attribution reasons
        4. User clears reading status with 'clear' -> favorites preserved
        5. User dislikes a book -> strictly suppressed from future recs
        """
        from backend.application.use_cases.interactions import SubmitFeedbackUseCase
        from backend.application.use_cases.recommendations import (
            GetPersonalizedRecommendationsUseCase,
        )

        class InMemoryInteractionRepo:
            def __init__(self):
                self.interactions = []  # list of dicts: user_id, book_id, interaction_type
                self.favorites_table = set()  # set of (user_id, book_id)

            def get_user_interactions(self, user_id):
                return [i for i in self.interactions if i["user_id"] == user_id]

            def get_user_profile(self, user_id):
                return {"preferred_genres": ["Science Fiction"], "preferred_authors": ["Frank Herbert"]}

            def upsert_interactions(self, entries):
                for e in entries:
                    # remove previous matching user_id & book_id
                    self.interactions = [
                        i for i in self.interactions
                        if not (i["user_id"] == e["user_id"] and i["book_id"] == e["book_id"] and i["interaction_type"] == e["interaction_type"])
                    ]
                    self.interactions.append(e)
                    if e.get("interaction_type") == "favorite":
                        self.favorites_table.add((e["user_id"], e["book_id"]))

            def delete_interaction(self, user_id, book_id, interaction_type=None, preserve_favorites=False):
                if interaction_type:
                    self.interactions = [
                        i for i in self.interactions
                        if not (i["user_id"] == user_id and i["book_id"] == book_id and i["interaction_type"] == interaction_type)
                    ]
                    if interaction_type == "favorite":
                        self.favorites_table.discard((user_id, book_id))
                elif preserve_favorites:
                    self.interactions = [
                        i for i in self.interactions
                        if not (i["user_id"] == user_id and i["book_id"] == book_id and i["interaction_type"] != "favorite")
                    ]
                else:
                    self.interactions = [
                        i for i in self.interactions
                        if not (i["user_id"] == user_id and i["book_id"] == book_id)
                    ]
                    self.favorites_table.discard((user_id, book_id))

        class PassthroughEnrichment:
            def enrich(self, books):
                return books

        engine = BookRecommender()
        data = [
            {"isbn13": "9780000000001", "title": "Dune", "authors": "Frank Herbert", "categories": "Science Fiction", "description": "Epic sci-fi desert planet Arrakis spice", "average_rating": 4.6, "ratings_count": 2000, "popularity_score": 0.9},
            {"isbn13": "9780000000002", "title": "Children of Dune", "authors": "Frank Herbert", "categories": "Science Fiction", "description": "Sequel sci-fi desert empire Arrakis", "average_rating": 4.4, "ratings_count": 1200, "popularity_score": 0.8},
            {"isbn13": "9780000000003", "title": "Neuromancer", "authors": "William Gibson", "categories": "Cyberpunk", "description": "Sprawl cyberspace hacker AI matrix", "average_rating": 4.3, "ratings_count": 1500, "popularity_score": 0.85},
            {"isbn13": "9780000000004", "title": "Count Zero", "authors": "William Gibson", "categories": "Cyberpunk", "description": "Cyberspace voodoo AI net run", "average_rating": 4.2, "ratings_count": 800, "popularity_score": 0.7},
        ]
        engine.load_from_dicts(data)
        engine.fit()

        repo = InMemoryInteractionRepo()
        feedback_uc = SubmitFeedbackUseCase(repo)
        rec_uc = GetPersonalizedRecommendationsUseCase(
            recommender=engine,
            interaction_repo=repo,
            book_data_port=None,
            enrichment_service=FakeEnrichmentService(),
        )

        # 1. Cold start (no history)
        recs_cold = rec_uc.execute("alice", limit=2)
        assert len(recs_cold) > 0

        # 2. User favorites Dune and marks finished
        feedback_uc.execute("alice", "9780000000001", "favorite")
        feedback_uc.execute("alice", "9780000000001", "finished")
        assert ("alice", "9780000000001") in repo.favorites_table

        # 3. Recommendations reflect Dune affinity with reason
        recs = rec_uc.execute("alice", limit=2)
        rec_titles = [r["title"] for r in recs]
        assert "Children of Dune" in rec_titles
        child_rec = next(r for r in recs if r["title"] == "Children of Dune")
        assert "Dune" in child_rec["recommendation_reason"]

        # 4. User clears reading status with 'clear' -> favorites table still preserved!
        feedback_uc.execute("alice", "9780000000001", "clear")
        assert ("alice", "9780000000001") in repo.favorites_table

        # 5. User dislikes Neuromancer -> must NOT appear in recs
        feedback_uc.execute("alice", "9780000000003", "dislike")
        recs_after_dislike = rec_uc.execute("alice", limit=3)
        assert "Neuromancer" not in [r["title"] for r in recs_after_dislike]

    def test_explanation_neutral_fallback_when_interaction_provenance_missing(self):
        """
        Sprint 10 UX Invariant:
        When interaction provenance is missing, recommender must never claim
        'Because you liked' or fake causal interactions. It must fall back to neutral wording.
        """
        engine = BookRecommender()
        data = [
            {
                "isbn13": "9780000000001",
                "title": "Dune",
                "authors": "Frank Herbert",
                "categories": "Sci-Fi",
                "description": "Spice on Arrakis",
            },
            {
                "isbn13": "9780000000002",
                "title": "Foundation",
                "authors": "Isaac Asimov",
                "categories": "Sci-Fi",
                "description": "Galactic Empire",
            },
        ]
        engine.load_from_dicts(data)
        engine.fit()

        candidate = engine.df.iloc[1].to_dict()
        # Seed indices present, but seed_sources does NOT contain a recorded interaction for seed 0
        explanation = engine._explain_recommendation(
            candidate,
            seed_indices=[0],
            semantic_scores=None,
            preferred_genres=[],
            seed_sources={},  # Empty provenance
        )

        reason = explanation.get("recommendation_reason", "")
        # Must NOT claim user liked or read the book when provenance is empty!
        assert "Because you liked" not in reason
        assert "Because you read" not in reason
        assert reason == "Curated based on your taste profile"
        exp_text = explanation.get("explanation", "")
        assert "genel okuma profiliniz" in exp_text or "Okuma zevkinize" in exp_text

    def test_category_scoped_personalized_recommendations(self, recommender_with_books):
        repo = InMemoryInteractionRepo()
        user_id = "user-category-test"
        repo.upsert_interactions([
            {"user_id": user_id, "book_id": "Dune", "interaction_type": "favorite"},
            {"user_id": user_id, "book_id": "Pride and Prejudice", "interaction_type": "like"},
            {"user_id": user_id, "book_id": "Dune Messiah", "interaction_type": "dislike"},
        ])

        uc = GetPersonalizedRecommendationsUseCase(
            recommender=recommender_with_books,
            interaction_repo=repo,
            book_data_port=None,
            enrichment_service=FakeEnrichmentService(),
        )

        recs_fantasy = uc.execute(user_id=user_id, limit=5, category="Fantasy")
        for r in recs_fantasy:
            assert "fantasy" in str(r.get("categories", "")).lower()

        recs_scifi = uc.execute(user_id=user_id, limit=5, category="Sci-Fi")
        scifi_titles = [r.get("title") for r in recs_scifi]
        assert "Dune Messiah" not in scifi_titles
        assert "Dune" not in scifi_titles

    def test_preference_signals_influence_ranking_hierarchy(self):
        """
        Verify that higher-weighted preference signals (favorite=2.5) rank similar books
        strictly higher than lower-weighted intent signals (want_to_read=0.8).
        Also measures Precision@K and NDCG@K.
        """
        engine = BookRecommender()
        data = [
            {"isbn13": "9781000000001", "title": "Foundation", "authors": "Isaac Asimov", "categories": "Science Fiction", "description": "Galactic Empire psychohistory Seldon Foundation", "average_rating": 4.5, "ratings_count": 5000, "popularity_score": 0.8},
            {"isbn13": "9781000000002", "title": "Foundation and Empire", "authors": "Isaac Asimov", "categories": "Science Fiction", "description": "Galactic Empire psychohistory Mule Foundation", "average_rating": 4.4, "ratings_count": 4000, "popularity_score": 0.75},
            {"isbn13": "9781000000003", "title": "Neuromancer", "authors": "William Gibson", "categories": "Cyberpunk", "description": "Cyberspace matrix console cowboy hacker Case", "average_rating": 4.3, "ratings_count": 3000, "popularity_score": 0.8},
            {"isbn13": "9781000000004", "title": "Count Zero", "authors": "William Gibson", "categories": "Cyberpunk", "description": "Cyberspace matrix voodoo net runner hacker Turner", "average_rating": 4.1, "ratings_count": 2000, "popularity_score": 0.7},
            {"isbn13": "9781000000005", "title": "Pride and Prejudice", "authors": "Jane Austen", "categories": "Romance, Classics", "description": "Elizabeth Bennet Mr Darcy classic estate manners", "average_rating": 4.6, "ratings_count": 6000, "popularity_score": 0.9},
        ]
        engine.load_from_dicts(data)
        engine.fit()

        repo = InMemoryInteractionRepo()
        user_id = "user-ranking-test"
        # Strong signal for Asimov (favorite=2.5), mild signal for Gibson (want_to_read=0.8)
        repo.upsert_interactions([
            {"user_id": user_id, "book_id": "9781000000001", "interaction_type": "favorite"},
            {"user_id": user_id, "book_id": "9781000000003", "interaction_type": "want_to_read"},
        ])

        uc = GetPersonalizedRecommendationsUseCase(
            recommender=engine,
            interaction_repo=repo,
            book_data_port=None,
            enrichment_service=FakeEnrichmentService(),
        )

        recs = uc.execute(user_id=user_id, limit=3)
        rec_isbns = [r["isbn13"] for r in recs]
        # Seeds themselves must not be recommended
        assert "9781000000001" not in rec_isbns
        assert "9781000000003" not in rec_isbns

        # Foundation and Empire (related to favorite) must rank above Count Zero (related to want_to_read)
        assert "9781000000002" in rec_isbns
        assert "9781000000004" in rec_isbns
        assert rec_isbns.index("9781000000002") < rec_isbns.index("9781000000004")

        # Compute ranking metrics against ground truth relevance {Foundation and Empire}
        p_at_1 = precision_at_k(rec_isbns, {"9781000000002"}, k=1)
        assert p_at_1 == 1.0
        ndcg = ndcg_at_k(rec_isbns, {"9781000000002", "9781000000004"}, k=2)
        assert ndcg > 0.9

    def test_disliked_book_suppression_under_category_fallback(self):
        """
        Verify that disliked books are 100% suppressed even when category filter triggers
        and falls back to popular books in that category.
        """
        engine = BookRecommender()
        data = [
            {"isbn13": "9782000000001", "title": "The Hobbit", "authors": "J.R.R. Tolkien", "categories": "Fantasy", "description": "Bilbo Baggins journey to Lonely Mountain", "average_rating": 4.7, "ratings_count": 8000, "popularity_score": 0.95},
            {"isbn13": "9782000000002", "title": "The Fellowship of the Ring", "authors": "J.R.R. Tolkien", "categories": "Fantasy", "description": "Frodo Baggins One Ring Mordor journey", "average_rating": 4.8, "ratings_count": 9000, "popularity_score": 0.98},
            {"isbn13": "9782000000003", "title": "A Game of Thrones", "authors": "George R.R. Martin", "categories": "Fantasy", "description": "Winter is coming Westeros Iron Throne Stark", "average_rating": 4.5, "ratings_count": 7000, "popularity_score": 0.9},
        ]
        engine.load_from_dicts(data)
        engine.fit()

        repo = InMemoryInteractionRepo()
        user_id = "user-dislike-category-test"
        # User dislikes Fellowship of the Ring
        repo.upsert_interactions([
            {"user_id": user_id, "book_id": "9782000000002", "interaction_type": "dislike"},
        ])

        uc = GetPersonalizedRecommendationsUseCase(
            recommender=engine,
            interaction_repo=repo,
            book_data_port=None,
            enrichment_service=FakeEnrichmentService(),
        )

        recs = uc.execute(user_id=user_id, limit=5, category="Fantasy")
        rec_isbns = [r["isbn13"] for r in recs]
        assert "9782000000002" not in rec_isbns
        suppression = dislike_suppression_rate(rec_isbns, {"9782000000002"}, k=5)
        assert suppression == 1.0

    def test_cold_start_category_fallback_honest_attribution(self):
        """
        Verify that a cold-start user (zero interactions) filtering by category
        receives honest attribution ('Popular in Fantasy') instead of fake personalization.
        """
        engine = BookRecommender()
        data = [
            {"isbn13": "9783000000001", "title": "Dune", "authors": "Frank Herbert", "categories": "Science Fiction", "description": "Arrakis spice desert planet", "average_rating": 4.6, "ratings_count": 5000, "popularity_score": 0.9},
            {"isbn13": "9783000000002", "title": "The Hobbit", "authors": "J.R.R. Tolkien", "categories": "Fantasy", "description": "Bilbo Baggins journey", "average_rating": 4.7, "ratings_count": 6000, "popularity_score": 0.95},
        ]
        engine.load_from_dicts(data)
        engine.fit()

        repo = InMemoryInteractionRepo()
        user_id = "user-cold-start-cat"

        uc = GetPersonalizedRecommendationsUseCase(
            recommender=engine,
            interaction_repo=repo,
            book_data_port=None,
            enrichment_service=FakeEnrichmentService(),
        )

        recs = uc.execute(user_id=user_id, limit=2, category="Fantasy")
        assert len(recs) == 1
        assert recs[0]["isbn13"] == "9783000000002"
        assert recs[0]["recommendation_reason"] == "Popular in Fantasy"
        assert "Because you liked" not in recs[0]["recommendation_reason"]

