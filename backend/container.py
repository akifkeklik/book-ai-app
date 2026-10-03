import logging

from backend.application.use_cases.ai_rag import ProcessRagQueryUseCase
from backend.application.use_cases.catalog import (
    GetBookDetailsUseCase,
    GetBooksUseCase,
    GetPopularBooksUseCase,
    SearchBooksUseCase,
)
from backend.application.use_cases.interactions import (
    SubmitFeedbackUseCase,
    SubmitOnboardingUseCase,
    TrackUserActivityUseCase,
)
from backend.application.use_cases.recommendations import (
    GetPersonalizedRecommendationsUseCase,
    GetRecommendationsUseCase,
)
from backend.config import Config
from backend.infrastructure.adapters.enrichment_adapter import GoogleBooksEnrichmentAdapter
from backend.infrastructure.llm.adapters import GenericLlmAdapter
from backend.infrastructure.ml.recommender import BookRecommender
from backend.infrastructure.persistence.supabase_adapters import (
    SupabaseAuthPort,
    SupabaseBookDataPort,
    SupabaseInteractionRepository,
)
from backend.services.book_service import BookService
from backend.services.embedding_service import EmbeddingService

logger = logging.getLogger(__name__)

class Container:
    """Dependency Injection Container (Composition Root)."""

    def __init__(self):
        self.supabase = None
        if Config.SUPABASE_URL and Config.SUPABASE_ANON_KEY:
            try:
                from supabase import create_client
                self.supabase = create_client(Config.SUPABASE_URL, Config.SUPABASE_ANON_KEY)
            except ImportError:
                logger.warning("Supabase client could not be imported.")

        # 1. Infrastructure Adapters
        self.interaction_repo = SupabaseInteractionRepository(self.supabase) if self.supabase else None
        self.book_data_port = SupabaseBookDataPort(self.supabase) if self.supabase else None
        self.auth_port = SupabaseAuthPort(self.supabase) if self.supabase else None

        self.recommender = BookRecommender()
        self.llm_port = GenericLlmAdapter(provider=Config.LLM_PROVIDER, api_key=Config.LLM_API_KEY)

        # 2. Application Services
        self.enrichment_service = GoogleBooksEnrichmentAdapter()
        self.book_service = BookService(
            recommender=self.recommender,
            interaction_repo=self.interaction_repo,
            book_data_port=self.book_data_port,
        )
        self.embedding_service = EmbeddingService(book_data_port=self.book_data_port)

        # 3. Use Cases
        self.get_books_uc = GetBooksUseCase(self.recommender, self.enrichment_service)
        self.search_books_uc = SearchBooksUseCase(self.recommender, self.enrichment_service)
        self.get_popular_books_uc = GetPopularBooksUseCase(self.recommender, self.enrichment_service)
        self.get_book_details_uc = GetBookDetailsUseCase(self.recommender, self.enrichment_service)
        self.get_recommendations_uc = GetRecommendationsUseCase(self.recommender, self.enrichment_service)
        self.get_personalized_recs_uc = GetPersonalizedRecommendationsUseCase(
            recommender=self.recommender,
            interaction_repo=self.interaction_repo,
            book_data_port=self.book_data_port,
            enrichment_service=self.enrichment_service
        )
        self.submit_onboarding_uc = SubmitOnboardingUseCase(self.interaction_repo)
        self.submit_feedback_uc = SubmitFeedbackUseCase(self.interaction_repo)
        self.track_activity_uc = TrackUserActivityUseCase(self.interaction_repo)

        self.process_rag_query_uc = ProcessRagQueryUseCase(
            embedding_port=self.embedding_service,
            book_data_port=self.book_data_port,
            interaction_repo=self.interaction_repo,
            recommender=self.recommender,
            enrichment_service=self.enrichment_service,
            llm_port=self.llm_port
        )

# Global container instance
container = Container()
