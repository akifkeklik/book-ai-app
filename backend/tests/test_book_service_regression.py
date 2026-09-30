from unittest.mock import MagicMock, patch

from backend.application.use_cases.recommendations import GetPersonalizedRecommendationsUseCase
from backend.application.use_cases.interactions import SubmitFeedbackUseCase

class TestBookServiceRegression:
    def test_personalized_recommendations_filters_dislikes(self):
        # Setup mock Recommender
        mock_recommender_instance = MagicMock()
        mock_recommender_instance.is_fitted = True
        mock_recommender_instance.recommend.return_value = [
            {"isbn13": "111", "title": "Book 1"},
            {"isbn13": "222", "title": "Book 2"}, # This will be disliked
            {"isbn13": "333", "title": "Book 3"}
        ]

        # Setup mock Ports
        mock_interaction_repo = MagicMock()
        mock_interaction_repo.get_user_interactions.return_value = [
            {"book_id": "111", "interaction_type": "like"},
            {"book_id": "222", "interaction_type": "dislike"}
        ]
        
        mock_book_data_port = MagicMock()
        mock_book_data_port.get_semantic_candidates.return_value = {}

        mock_enrichment_service = MagicMock()
        mock_enrichment_service.enrich.side_effect = lambda x: x
        
        # Instantiate service
        service = GetPersonalizedRecommendationsUseCase(
            recommender=mock_recommender_instance,
            interaction_repo=mock_interaction_repo,
            book_data_port=mock_book_data_port,
            enrichment_service=mock_enrichment_service
        )

        # Execute
        recs = service.execute(user_id="user_123", limit=10)

        # Assert
        assert len(recs) == 2
        assert any(r["isbn13"] == "111" for r in recs)
        assert any(r["isbn13"] == "333" for r in recs)
        assert not any(r["isbn13"] == "222" for r in recs) # Disliked book must be filtered

    def test_submit_feedback_upsert_logic(self):
        mock_recommender_instance = MagicMock()
        mock_interaction_repo = MagicMock()
        
        service = SubmitFeedbackUseCase(
            interaction_repo=mock_interaction_repo
        )

        # Submit like
        res = service.execute("user_123", "999", "like")
        assert res["status"] == "success"
        mock_interaction_repo.upsert_interactions.assert_called_with([
            {"user_id": "user_123", "book_id": "999", "interaction_type": "like"}
        ])

        # Submit dislike
        res2 = service.execute("user_123", "999", "dislike")
        assert res2["status"] == "success"
        mock_interaction_repo.upsert_interactions.assert_called_with([
            {"user_id": "user_123", "book_id": "999", "interaction_type": "dislike"}
        ])
