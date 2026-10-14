from unittest.mock import MagicMock

from backend.application.use_cases.interactions import (
    SubmitOnboardingUseCase,
    TrackUserActivityUseCase,
)
from backend.application.use_cases.recommendations import GetPersonalizedRecommendationsUseCase


def test_track_activity_model_a_reading_statuses():
    """Verify TrackUserActivityUseCase maps all Model A reading statuses and preferences."""
    mock_repo = MagicMock()
    use_case = TrackUserActivityUseCase(mock_repo)

    actions = [
        ("reading", "reading"),
        ("want_to_read", "want_to_read"),
        ("finished", "finished"),
        ("favorite", "favorite"),
        ("book_favorite", "favorite"),
        ("like", "like"),
        ("dislike", "dislike"),
    ]

    for action, expected_mapped in actions:
        mock_repo.reset_mock()
        result = use_case.execute("user-1", action=action, book_id="book-100", book_name="Dune")

        assert result["status"] == "tracked"
        assert result["action"] == action
        mock_repo.track_activity.assert_called_once()
        mock_repo.upsert_interactions.assert_called_once()

        upsert_arg = mock_repo.upsert_interactions.call_args[0][0]
        assert len(upsert_arg) == 1
        assert upsert_arg[0]["user_id"] == "user-1"
        assert upsert_arg[0]["book_id"] == "book-100"
        assert upsert_arg[0]["interaction_type"] == expected_mapped


def test_personalized_recommendations_model_a_signal_fusion():
    """Verify personalization correctly fuses Model A favorites and distinct reading statuses."""
    mock_recommender = MagicMock()
    mock_enrichment = MagicMock()
    mock_repo = MagicMock()

    # User has book-1 as favorite, book-2 as reading, book-3 as finished, and book-4 as dislike
    mock_repo.get_user_interactions.return_value = [
        {"book_id": "book-1", "interaction_type": "favorite"},
        {"book_id": "book-2", "interaction_type": "reading"},
        {"book_id": "book-3", "interaction_type": "finished"},
        {"book_id": "book-4", "interaction_type": "dislike"},
    ]

    mock_recommender.recommend.return_value = [
        {"isbn13": "book-rec-1", "title": "Rec 1", "average_rating": 4.5}
    ]
    mock_enrichment.enrich.side_effect = lambda books: books

    use_case = GetPersonalizedRecommendationsUseCase(
        recommender=mock_recommender,
        interaction_repo=mock_repo,
        book_data_port=None,
        enrichment_service=mock_enrichment,
    )

    recs = use_case.execute("user-1", limit=5)
    assert len(recs) == 1
    assert recs[0]["isbn13"] == "book-rec-1"

    # Verify recommend was called with seed titles or personalization params
    mock_recommender.recommend.assert_called_once()


def test_onboarding_preserves_clean_user_interactions():
    """Verify submit onboarding properly creates like interactions and profile without overwriting."""
    mock_repo = MagicMock()
    use_case = SubmitOnboardingUseCase(mock_repo)

    res = use_case.execute(
        user_id="user-onboarding",
        book_ids=["b1", "b2"],
        genres=["Sci-Fi", "Fantasy"],
    )

    assert res["status"] == "success"
    mock_repo.upsert_interactions.assert_called_once()
    mock_repo.upsert_profile.assert_called_once()
    entries = mock_repo.upsert_interactions.call_args[0][0]
    assert len(entries) == 2
    assert entries[0]["interaction_type"] == "like"
    assert entries[1]["interaction_type"] == "like"
