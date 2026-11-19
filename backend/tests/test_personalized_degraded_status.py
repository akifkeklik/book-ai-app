"""
Personalised recommendations must report when semantic candidate retrieval failed.

Live audit (November 2026): public.match_book_embeddings did not exist in the production
database, so every personalised request silently fell back to TF-IDF while diagnostics said
fallback_reason=None. The ranking may still degrade gracefully, but diagnostics must say so.
"""

# Pytest fixtures imported from another module are passed back as test arguments.
# ruff: noqa: F811
from backend.application.use_cases.recommendations import GetPersonalizedRecommendationsUseCase
from backend.domain.ports import SemanticSearchUnavailable
from backend.tests.test_personalized_recs import (  # noqa: F401  (fixture re-export)
    FakeEnrichmentService,
    InMemoryInteractionRepo,
    recommender_with_books,
)


class _Port:
    def __init__(self, result=None, error=None):
        self.result, self.error, self.calls = result, error, 0

    def get_semantic_candidates(self, likes, limit=100):
        self.calls += 1
        if self.error:
            raise self.error
        return self.result


def _run(recommender, port):
    repo = InMemoryInteractionRepo()
    repo.interactions["u"] = [{"book_id": "9780000000001", "interaction_type": "like"}]
    uc = GetPersonalizedRecommendationsUseCase(recommender=recommender, interaction_repo=repo,
                                               book_data_port=port, enrichment_service=FakeEnrichmentService())
    return uc.execute(user_id="u", limit=3, include_diagnostics=True)


def test_missing_vector_rpc_is_reported_as_degraded(recommender_with_books):
    port = _Port(error=SemanticSearchUnavailable("function public.match_book_embeddings does not exist"))
    out = _run(recommender_with_books, port)
    assert port.calls == 1
    assert out["recommendations"], "TF-IDF fallback must still return recommendations"
    d = out["diagnostics"]
    assert d["degraded"] is True
    assert d["retrieval_mode"] == "tfidf_fallback"
    assert d["fallback_reason"] == "semantic_unavailable"


def test_healthy_semantic_retrieval_is_not_degraded(recommender_with_books):
    out = _run(recommender_with_books, _Port(result={"9780000000002": 0.9}))
    d = out["diagnostics"]
    assert d["degraded"] is False and d["fallback_reason"] is None
    assert d["retrieval_mode"] == "hybrid_semantic"


def test_empty_semantic_result_is_not_mislabelled_as_failure(recommender_with_books):
    d = _run(recommender_with_books, _Port(result={}))["diagnostics"]
    assert d["degraded"] is False and d["retrieval_mode"] == "tfidf_no_semantic_matches"


def test_no_vector_port_is_plain_tfidf(recommender_with_books):
    d = _run(recommender_with_books, None)["diagnostics"]
    assert d["degraded"] is False and d["retrieval_mode"] == "tfidf"
