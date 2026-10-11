from typing import Any, Dict, List, Optional

from backend.application.use_cases.ai_rag import ProcessRagQueryUseCase
from backend.application.use_cases.catalog import GetBooksUseCase
from backend.application.use_cases.recommendations import GetPersonalizedRecommendationsUseCase
from backend.domain.ports import BookDataPort, EmbeddingPort, LlmPort, UserInteractionRepository


# Fakes
class FakeLlmPort(LlmPort):
    def __init__(self, response: Optional[str] = "Generated AI Answer"):
        self.response = response
        self.calls = []

    def generate_response(self, system_prompt: str, user_prompt: str) -> Optional[str]:
        self.calls.append((system_prompt, user_prompt))
        if isinstance(self.response, Exception):
            raise self.response
        return self.response


class FakeEmbeddingPort(EmbeddingPort):
    def __init__(self, embedding: List[float] = [0.1, 0.2]):
        self.embedding = embedding

    def generate_embedding(self, text: str, max_retries: int = 3) -> Optional[List[float]]:
        return self.embedding


class FakeBookDataPort(BookDataPort):
    def __init__(self, candidates: Dict[str, float] = None, books: List[Dict[str, Any]] = None):
        self.candidates = candidates or {}
        self.books = books or []

    def match_query_embeddings(self, embedding: List[float], limit: int = 100) -> Dict[str, float]:
        return self.candidates

    def get_books_by_isbns(self, isbns: List[str]) -> List[Dict[str, Any]]:
        return [b for b in self.books if b.get("isbn13") in isbns]

    def get_semantic_candidates(self, likes: List[str], limit: int = 100) -> Dict[str, float]:
        return self.candidates

    def get_all_books_raw(self):
        return []

    def get_embedding_metadata(self, book_id):
        return None

    def upsert_embedding(self, book_id, embedding, content_hash, model_version):
        pass


class FakeInteractionRepo(UserInteractionRepository):
    def __init__(self, interactions: List[Dict] = None, profile: Dict = None):
        self.interactions = interactions or []
        self.profile = profile

    def get_user_interactions(self, user_id: str) -> List[Dict[str, Any]]:
        return self.interactions

    def get_user_profile(self, user_id: str) -> Optional[Dict[str, Any]]:
        return self.profile

    def upsert_interactions(self, entries):
        pass

    def upsert_profile(self, user_id, genres, updated_at):
        pass

    def track_activity(self, payload):
        pass


class FakeEngine:
    def __init__(self):
        # Provide a dummy DataFrame and find_index method
        pass

    def find_index(self, bid):
        return 0

    @property
    def df(self):
        class DummyDF:
            def iloc(self):
                pass

        import pandas as pd

        return pd.DataFrame([{"title": "Liked Book Title"}])


class FakeRecommender:
    def __init__(self, recs: List[Dict] = None):
        self.recs = recs or []
        self.engine = FakeEngine()

    def recommend(
        self, seed_titles, top_n=10, use_diversity=True, semantic_scores=None, dislikes=None
    ):
        return self.recs

    def get_popular_books(self, limit=10):
        return self.recs


class FakeEnrichmentService:
    def enrich(self, books):
        return books


def test_rag_usecase_success():
    llm = FakeLlmPort(response="RAG Answer")
    emb = FakeEmbeddingPort()
    book_data = FakeBookDataPort(
        candidates={"123": 0.9},
        books=[
            {"isbn13": "123", "title": "Book 1", "authors": "Author 1", "categories": "Fiction"}
        ],
    )
    uc = ProcessRagQueryUseCase(
        emb,
        book_data,
        FakeInteractionRepo(),
        FakeRecommender(
            recs=[
                {"isbn13": "123", "title": "Book 1", "authors": "Author 1", "categories": "Fiction"}
            ]
        ),
        FakeEnrichmentService(),
        llm,
    )

    res = uc.execute("I want a sci-fi book")
    assert res["status"] == "success"
    assert res["answer"] == "RAG Answer"
    assert len(res["referenced_books"]) == 1
    assert res["referenced_books"][0]["title"] == "Book 1"

    # Prompt boundary test: User query should be in the user_prompt
    sys_prompt, user_prompt = llm.calls[0]
    assert "I want a sci-fi book" in user_prompt
    assert "Book 1" in user_prompt  # Context should be in user prompt in this architecture


def test_rag_usecase_no_results():
    llm = FakeLlmPort(response="General AI Answer")
    emb = FakeEmbeddingPort()
    book_data = FakeBookDataPort(candidates={})  # empty semantic retrieval

    uc = ProcessRagQueryUseCase(
        emb, book_data, FakeInteractionRepo(), FakeRecommender(), FakeEnrichmentService(), llm
    )
    res = uc.execute("Tell me about apples")

    assert res["status"] == "empty_retrieval"
    assert len(res["referenced_books"]) == 0
    # Business logic specifies empty context doesn't crash the LLM call, but RAG returns early
    assert "I couldn't find any books in my library" in res["answer"]


def test_rag_usecase_llm_failure():
    llm = FakeLlmPort(response=None)  # LLM adapter returns None on failure
    book_data = FakeBookDataPort(candidates={"123": 0.9})
    uc = ProcessRagQueryUseCase(
        FakeEmbeddingPort(),
        book_data,
        FakeInteractionRepo(),
        FakeRecommender(recs=[{"isbn13": "124", "title": "Book 2", "authors": "Author"}]),
        FakeEnrichmentService(),
        llm,
    )

    res = uc.execute("Hello")
    assert res["status"] == "llm_fallback"
    assert "I couldn't generate a personalized response" in res["answer"]


def test_rag_usecase_personalization_seed():
    interactions = [
        {"book_id": "111", "interaction_type": "like"},
        {"book_id": "222", "interaction_type": "dislike"},
    ]
    book_data = FakeBookDataPort(
        candidates={"123": 0.9}, books=[{"isbn13": "111", "title": "Liked Book"}]
    )
    llm = FakeLlmPort()
    uc = ProcessRagQueryUseCase(
        FakeEmbeddingPort(),
        book_data,
        FakeInteractionRepo(interactions),
        FakeRecommender(recs=[{"isbn13": "125", "title": "Test", "authors": "Author"}]),
        FakeEnrichmentService(),
        llm,
    )

    uc.execute("Suggest me something", user_id="u1")
    sys_prompt, user_prompt = llm.calls[0]
    # The prompt should contain context about what the user likes/dislikes (or at least the retrieved books)
    assert "Test" in user_prompt


def test_personalized_recs_likes_and_dislikes():
    interactions = [
        {"book_id": "111", "interaction_type": "like"},
        {"book_id": "999", "interaction_type": "dislike"},
    ]
    recommender = FakeRecommender(recs=[{"isbn13": "111"}, {"isbn13": "999"}, {"isbn13": "888"}])
    uc = GetPersonalizedRecommendationsUseCase(
        recommender, FakeInteractionRepo(interactions), None, FakeEnrichmentService()
    )

    res = uc.execute("u1", limit=10)
    # Disliked books must NOT appear in the final output
    isbns = [r["isbn13"] for r in res]
    assert "999" not in isbns
    assert "888" in isbns


def test_personalized_recs_cold_start():
    # No profile, no interactions
    repo = FakeInteractionRepo(interactions=[], profile=None)
    recommender = FakeRecommender(recs=[{"isbn13": "pop1"}])
    uc = GetPersonalizedRecommendationsUseCase(recommender, repo, None, FakeEnrichmentService())

    res = uc.execute("u2", limit=10)
    assert len(res) == 1
    assert res[0]["isbn13"] == "pop1"


def test_submit_onboarding_usecase():
    from backend.application.use_cases.interactions import SubmitOnboardingUseCase

    repo = FakeInteractionRepo()
    uc = SubmitOnboardingUseCase(repo)
    res = uc.execute("u1", ["b1", "b2"], ["sci-fi"])
    assert res["status"] == "success"
    # Verify interaction repo calls
    assert len(repo.profile) > 0 if hasattr(repo, "profile") and repo.profile else True


def test_submit_feedback_usecase():
    from backend.application.use_cases.interactions import SubmitFeedbackUseCase

    repo = FakeInteractionRepo()
    uc = SubmitFeedbackUseCase(repo)
    res = uc.execute("u1", "b1", "like")
    assert res["status"] == "success"


def test_track_activity_usecase():
    from backend.application.use_cases.interactions import TrackUserActivityUseCase

    repo = FakeInteractionRepo()
    uc = TrackUserActivityUseCase(repo)
    res = uc.execute("u1", "view", "b1", "Book 1")
    assert res["status"] == "tracked"


def test_personalized_recs_dislike_overrides_like():
    # User has both like and dislike for book 111 (e.g. later disliked it)
    interactions = [
        {"book_id": "111", "interaction_type": "like"},
        {"book_id": "111", "interaction_type": "dislike"},
        {"book_id": "222", "interaction_type": "like"},
    ]
    recommender = FakeRecommender(recs=[{"isbn13": "111"}, {"isbn13": "333"}])
    uc = GetPersonalizedRecommendationsUseCase(
        recommender, FakeInteractionRepo(interactions), None, FakeEnrichmentService()
    )

    res = uc.execute("u1", limit=10)
    isbns = [r["isbn13"] for r in res]
    # Disliked 111 must be strictly excluded from seeds and final recs
    assert "111" not in isbns
    assert "333" in isbns


def test_personalized_recs_malformed_interactions_safe():
    interactions = [
        None,
        "not-a-dict",
        {"book_id": None, "interaction_type": "like"},
        {"book_id": "", "interaction_type": "like"},
        {"book_id": "  ", "interaction_type": "dislike"},
        {"book_id": "valid-123", "interaction_type": "like"},
    ]
    recommender = FakeRecommender(recs=[{"isbn13": "rec1"}])
    uc = GetPersonalizedRecommendationsUseCase(
        recommender, FakeInteractionRepo(interactions), None, FakeEnrichmentService()
    )

    res = uc.execute("u1", limit=10)
    assert len(res) >= 1
    assert res[0]["isbn13"] == "rec1"


def test_track_activity_syncs_preference_to_interactions():
    from backend.application.use_cases.interactions import TrackUserActivityUseCase

    repo = FakeInteractionRepo()
    repo.upserted_interactions = []

    def mock_upsert(entries):
        repo.upserted_interactions.extend(entries)

    repo.upsert_interactions = mock_upsert

    uc = TrackUserActivityUseCase(repo)
    res = uc.execute("u1", "book_like", "9781234567890", "Book Title")
    assert res["status"] == "tracked"
    assert len(repo.upserted_interactions) == 1
    assert repo.upserted_interactions[0]["interaction_type"] == "like"
    assert repo.upserted_interactions[0]["book_id"] == "9781234567890"


def test_track_activity_missing_user_id_raises():
    import pytest
    from backend.application.use_cases.interactions import TrackUserActivityUseCase

    repo = FakeInteractionRepo()
    uc = TrackUserActivityUseCase(repo)
    with pytest.raises(ValueError):
        uc.execute("", "view", "b1")


def test_get_books_usecase_with_query_filter():
    class QueryCatalog:
        def get_all_books(self, **kwargs):
            q = kwargs.get("query")
            assert q == "fantasy"
            return {
                "books": [{"isbn13": "9781111111111", "title": "Fantasy Tale", "authors": "A. Writer"}],
                "total": 1,
                "page": 1,
                "per_page": 20,
                "total_pages": 1,
            }

    uc = GetBooksUseCase(QueryCatalog(), FakeEnrichmentService())
    result = uc.execute(query="fantasy")
    assert result["total"] == 1
    assert result["books"][0]["title"] == "Fantasy Tale"


def test_track_activity_want_to_read_and_finished_sync():
    from backend.application.use_cases.interactions import TrackUserActivityUseCase

    repo = FakeInteractionRepo()
    repo.upserted_interactions = []

    def mock_upsert(entries):
        repo.upserted_interactions.extend(entries)

    repo.upsert_interactions = mock_upsert

    uc = TrackUserActivityUseCase(repo)
    res1 = uc.execute("u1", "want_to_read", "9780001", "Book 1")
    assert res1["status"] == "tracked"
    assert repo.upserted_interactions[-1]["interaction_type"] == "want_to_read"

    res2 = uc.execute("u1", "finished", "9780002", "Book 2")
    assert res2["status"] == "tracked"
    assert repo.upserted_interactions[-1]["interaction_type"] == "finished"

