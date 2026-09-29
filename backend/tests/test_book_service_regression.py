from unittest.mock import MagicMock, patch

from backend.services.book_service import BookService


class TestBookServiceRegression:
    @patch("backend.services.book_service.create_client")
    @patch("backend.services.book_service.Config")
    @patch("backend.services.book_service.BookRecommender")
    def test_personalized_recommendations_filters_dislikes(self, mock_recommender, mock_config, mock_create_client):
        # Setup mock Config
        mock_config.SUPABASE_URL = "test_url"
        mock_config.SUPABASE_ANON_KEY = "test_key"

        # Setup mock Supabase client
        mock_supabase = MagicMock()
        mock_create_client.return_value = mock_supabase

        # Setup mock Recommender
        mock_recommender_instance = MagicMock()
        mock_recommender_instance.is_fitted = True
        mock_recommender_instance.recommend.return_value = [
            {"isbn13": "111", "title": "Book 1"},
            {"isbn13": "222", "title": "Book 2"}, # This will be disliked
            {"isbn13": "333", "title": "Book 3"}
        ]
        mock_recommender.return_value = mock_recommender_instance

        # Instantiate service
        service = BookService()
        service._enrich = lambda x: x # Disable enrichment for test

        # Mock Supabase response for interactions
        mock_interactions_resp = MagicMock()
        mock_interactions_resp.data = [
            {"book_id": "111", "interaction_type": "like"},
            {"book_id": "222", "interaction_type": "dislike"}
        ]
        mock_supabase.table().select().eq().execute.return_value = mock_interactions_resp

        # Execute
        recs = service.get_personalized_recommendations(user_id="user_123", limit=10)

        # Assert
        assert len(recs) == 2
        assert any(r["isbn13"] == "111" for r in recs)
        assert any(r["isbn13"] == "333" for r in recs)
        assert not any(r["isbn13"] == "222" for r in recs) # Disliked book must be filtered

    @patch("backend.services.book_service.create_client")
    @patch("backend.services.book_service.Config")
    @patch("backend.services.book_service.BookRecommender")
    def test_submit_feedback_upsert_logic(self, mock_recommender, mock_config, mock_create_client):
        mock_config.SUPABASE_URL = "test_url"
        mock_config.SUPABASE_ANON_KEY = "test_key"

        mock_supabase = MagicMock()
        mock_create_client.return_value = mock_supabase

        service = BookService()

        # Submit like
        res = service.submit_feedback("user_123", "999", "like")
        assert res["status"] == "success"
        mock_supabase.table().upsert.assert_called_with(
            {"user_id": "user_123", "book_id": "999", "interaction_type": "like"},
            on_conflict="user_id,book_id"
        )

        # Submit dislike
        res2 = service.submit_feedback("user_123", "999", "dislike")
        assert res2["status"] == "success"
        mock_supabase.table().upsert.assert_called_with(
            {"user_id": "user_123", "book_id": "999", "interaction_type": "dislike"},
            on_conflict="user_id,book_id"
        )
