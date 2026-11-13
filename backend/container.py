import logging

from backend.application.use_cases.ai_rag import ProcessRagQueryUseCase
from backend.application.use_cases.catalog import (
    GetBookDetailsUseCase,
    GetBooksUseCase,
    GetPopularBooksUseCase,
    SearchBooksUseCase,
)
from backend.application.use_cases.export_notes import ExportNotesUseCase
from backend.application.use_cases.interactions import (
    GetUserPreferencesUseCase,
    ResetPreferencesUseCase,
    SubmitFeedbackUseCase,
    SubmitOnboardingUseCase,
    TrackUserActivityUseCase,
    UpdateUserPreferencesUseCase,
)
from backend.application.use_cases.knowledge_graph import (
    CreateRelationshipUseCase,
    DeleteRelationshipUseCase,
    GetNeighborsUseCase,
    GetPersonalKnowledgeGraphUseCase,
    UpdateRelationshipUseCase,
)
from backend.application.use_cases.learning_notes import (
    CreateNoteUseCase,
    DeleteNoteUseCase,
    GetNoteByIdUseCase,
    GetNotesUseCase,
    UpdateNoteUseCase,
)
from backend.application.use_cases.learning_outcomes import (
    CreateReviewItemUseCase,
    DeleteReviewItemUseCase,
    GetConceptOutcomesUseCase,
    GetLearningOverviewUseCase,
    GetReviewHistoryUseCase,
    GetReviewQueueUseCase,
    SubmitReviewAttemptUseCase,
    UpdateReviewItemUseCase,
)
from backend.application.use_cases.learning_paths import (
    AddBookToLearningPathUseCase,
    CreateLearningPathUseCase,
    DeleteLearningPathUseCase,
    GeneratePathSuggestionsUseCase,
    GetLearningPathDetailUseCase,
    GetUserLearningPathsUseCase,
    RemoveBookFromLearningPathUseCase,
    ReorderLearningPathBooksUseCase,
    UpdateLearningPathUseCase,
)
from backend.application.use_cases.recommendations import (
    GetPersonalizedRecommendationsUseCase,
    GetRecommendationsUseCase,
)
from backend.application.use_cases.spaced_repetition import (
    GetDueReviewsUseCase,
    GetReviewStatsUseCase,
    ProcessReviewUseCase,
    UpdateReviewSettingsUseCase,
)
from backend.config import Config
from backend.infrastructure.adapters.enrichment_adapter import GoogleBooksEnrichmentAdapter
from backend.infrastructure.llm.adapters import GenericLlmAdapter
from backend.infrastructure.ml.recommender import BookRecommender
from backend.infrastructure.persistence.in_memory_knowledge_repository import (
    InMemoryKnowledgeRepository,
)
from backend.infrastructure.persistence.in_memory_learning_repository import (
    InMemoryLearningOutcomesRepository,
)
from backend.infrastructure.persistence.in_memory_note_repository import (
    InMemoryLearningPathRepository,
    InMemoryNoteRepository,
    InMemoryNoteReviewRepository,
)
from backend.infrastructure.persistence.supabase_adapters import (
    SupabaseAuthPort,
    SupabaseBookDataPort,
    SupabaseInteractionRepository,
    SupabaseKnowledgeGraphRepository,
    SupabaseLearningOutcomesRepository,
    SupabaseLearningPathRepository,
    SupabaseNoteRepository,
    SupabaseNoteReviewRepository,
)
from backend.services.book_service import BookService
from backend.services.embedding_service import EmbeddingService

logger = logging.getLogger(__name__)


class Container:
    """Dependency Injection Container (Composition Root)."""

    def __init__(
        self,
        interaction_repo=None,
        book_data_port=None,
        auth_port=None,
        recommender=None,
        note_repo=None,
        knowledge_repo=None,
        learning_outcomes_repo=None,
        database_url=None,
    ):
        self.supabase = None
        effective_db_url = database_url or getattr(Config, "DATABASE_URL", None)

        if Config.SUPABASE_URL and Config.SUPABASE_ANON_KEY:
            try:
                from supabase import create_client

                self.supabase = create_client(Config.SUPABASE_URL, Config.SUPABASE_ANON_KEY)
            except ImportError:
                logger.warning("Supabase client could not be imported.")
            except Exception as e:
                logger.warning(f"Could not initialize Supabase client: {e}")

        # 1. Infrastructure Adapters
        if interaction_repo is not None:
            self.interaction_repo = interaction_repo
        elif effective_db_url:
            from backend.infrastructure.persistence.postgres_adapters import (
                PostgresInteractionRepository,
            )

            self.interaction_repo = PostgresInteractionRepository(effective_db_url)
        elif self.supabase:
            self.interaction_repo = SupabaseInteractionRepository(self.supabase)
        else:
            self.interaction_repo = None

        if note_repo is not None:
            self.note_repo = note_repo
        elif effective_db_url:
            from backend.infrastructure.persistence.postgres_adapters import PostgresNoteRepository

            self.note_repo = PostgresNoteRepository(effective_db_url)
        elif self.supabase:
            self.note_repo = SupabaseNoteRepository(self.supabase)
        else:
            self.note_repo = InMemoryNoteRepository()

        if hasattr(self, "note_review_repo") and self.note_review_repo is not None:
            pass
        elif self.supabase:
            self.note_review_repo = SupabaseNoteReviewRepository(self.supabase)
        else:
            self.note_review_repo = InMemoryNoteReviewRepository()

        if knowledge_repo is not None:
            self.knowledge_repo = knowledge_repo
        elif hasattr(self, "knowledge_repo") and self.knowledge_repo is not None:
            pass
        elif self.supabase:
            self.knowledge_repo = SupabaseKnowledgeGraphRepository(self.supabase)
        else:
            self.knowledge_repo = InMemoryKnowledgeRepository()

        if learning_outcomes_repo is not None:
            self.learning_outcomes_repo = learning_outcomes_repo
        elif hasattr(self, "learning_outcomes_repo") and self.learning_outcomes_repo is not None:
            pass
        elif self.supabase:
            self.learning_outcomes_repo = SupabaseLearningOutcomesRepository(self.supabase)
        else:
            self.learning_outcomes_repo = InMemoryLearningOutcomesRepository()

        if hasattr(self, "learning_path_repo") and self.learning_path_repo is not None:
            pass
        elif self.supabase:
            self.learning_path_repo = SupabaseLearningPathRepository(self.supabase)
        else:
            self.learning_path_repo = InMemoryLearningPathRepository()

        if book_data_port is not None:
            self.book_data_port = book_data_port
        elif effective_db_url:
            from backend.infrastructure.persistence.postgres_adapters import PostgresBookDataPort

            self.book_data_port = PostgresBookDataPort(effective_db_url)
        elif self.supabase:
            self.book_data_port = SupabaseBookDataPort(self.supabase)
        else:
            self.book_data_port = None

        if auth_port is not None:
            self.auth_port = auth_port
        elif getattr(Config, "SUPABASE_JWT_SECRET", ""):
            from backend.infrastructure.security.jwt_auth_adapter import SupabaseJwtAuthPort

            self.auth_port = SupabaseJwtAuthPort(
                secret=Config.SUPABASE_JWT_SECRET,
                audience=getattr(Config, "SUPABASE_JWT_AUDIENCE", "authenticated") or None,
                issuer=getattr(Config, "SUPABASE_JWT_ISSUER", "") or None,
            )
        elif self.supabase:
            self.auth_port = SupabaseAuthPort(self.supabase)
        else:
            self.auth_port = None

        self.recommender = recommender if recommender is not None else BookRecommender()
        self.llm_port = GenericLlmAdapter(
            provider=Config.LLM_PROVIDER,
            api_key=Config.LLM_API_KEY,
            model_name=getattr(Config, "GEMINI_MODEL", "models/gemini-2.5-flash"),
        )

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
        self.get_popular_books_uc = GetPopularBooksUseCase(
            self.recommender, self.enrichment_service
        )
        self.get_book_details_uc = GetBookDetailsUseCase(self.recommender, self.enrichment_service)
        self.get_recommendations_uc = GetRecommendationsUseCase(
            self.recommender, self.enrichment_service
        )
        self.get_personalized_recs_uc = GetPersonalizedRecommendationsUseCase(
            recommender=self.recommender,
            interaction_repo=self.interaction_repo,
            book_data_port=self.book_data_port,
            enrichment_service=self.enrichment_service,
            note_repo=self.note_repo,
            review_repo=getattr(self, "note_review_repo", None),
            learning_path_repo=getattr(self, "learning_path_repo", None),
        )
        self.submit_onboarding_uc = SubmitOnboardingUseCase(self.interaction_repo)
        self.get_preferences_uc = GetUserPreferencesUseCase(self.interaction_repo)
        self.update_preferences_uc = UpdateUserPreferencesUseCase(self.interaction_repo)
        self.submit_feedback_uc = SubmitFeedbackUseCase(self.interaction_repo)
        self.track_activity_uc = TrackUserActivityUseCase(self.interaction_repo)
        self.reset_preferences_uc = ResetPreferencesUseCase(self.interaction_repo)

        # Learning Notes Use Cases
        self.create_note_uc = CreateNoteUseCase(self.note_repo, self.book_data_port, getattr(self, "note_review_repo", None))
        self.get_notes_uc = GetNotesUseCase(self.note_repo, self.book_data_port)
        self.get_note_by_id_uc = GetNoteByIdUseCase(self.note_repo, self.book_data_port)
        self.update_note_uc = UpdateNoteUseCase(self.note_repo)
        self.delete_note_uc = DeleteNoteUseCase(self.note_repo, getattr(self, "note_review_repo", None))

        # Smart Review & Knowledge Retention Use Cases
        self.get_due_reviews_uc = GetDueReviewsUseCase(self.note_review_repo, self.note_repo, self.book_data_port)
        self.get_review_stats_uc = GetReviewStatsUseCase(self.note_review_repo)
        self.process_review_uc = ProcessReviewUseCase(self.note_review_repo, self.note_repo)
        self.update_review_settings_uc = UpdateReviewSettingsUseCase(self.note_review_repo, self.note_repo)

        # Learning Outcomes Intelligence Use Cases
        self.get_review_queue_uc = GetReviewQueueUseCase(
            learning_repo=self.learning_outcomes_repo,
            note_repo=self.note_repo,
            learning_path_repo=self.learning_path_repo,
            book_data_port=self.book_data_port,
        )
        self.submit_review_attempt_uc = SubmitReviewAttemptUseCase(
            learning_repo=self.learning_outcomes_repo,
            note_review_repo=getattr(self, "note_review_repo", None),
        )
        self.get_learning_overview_uc = GetLearningOverviewUseCase(
            learning_repo=self.learning_outcomes_repo
        )
        self.get_review_history_uc = GetReviewHistoryUseCase(
            learning_repo=self.learning_outcomes_repo
        )
        self.create_review_item_uc = CreateReviewItemUseCase(
            learning_repo=self.learning_outcomes_repo
        )
        self.update_review_item_uc = UpdateReviewItemUseCase(
            learning_repo=self.learning_outcomes_repo
        )
        self.delete_review_item_uc = DeleteReviewItemUseCase(
            learning_repo=self.learning_outcomes_repo
        )
        self.get_concept_outcomes_uc = GetConceptOutcomesUseCase(
            learning_repo=self.learning_outcomes_repo
        )

        # Notes Export Use Case
        self.export_notes_uc = ExportNotesUseCase(self.note_repo, self.book_data_port)

        # Learning Paths & Progress Intelligence Use Cases
        self.create_learning_path_uc = CreateLearningPathUseCase(self.learning_path_repo, self.book_data_port)
        self.get_user_learning_paths_uc = GetUserLearningPathsUseCase(
            self.learning_path_repo, self.interaction_repo, self.note_repo, self.note_review_repo
        )
        self.get_learning_path_detail_uc = GetLearningPathDetailUseCase(
            self.learning_path_repo, self.book_data_port, self.interaction_repo, self.note_repo, self.note_review_repo
        )
        self.update_learning_path_uc = UpdateLearningPathUseCase(self.learning_path_repo)
        self.delete_learning_path_uc = DeleteLearningPathUseCase(self.learning_path_repo)
        self.add_book_to_path_uc = AddBookToLearningPathUseCase(self.learning_path_repo, self.book_data_port)
        self.remove_book_from_path_uc = RemoveBookFromLearningPathUseCase(self.learning_path_repo)
        self.reorder_path_books_uc = ReorderLearningPathBooksUseCase(self.learning_path_repo)
        self.generate_path_suggestions_uc = GeneratePathSuggestionsUseCase(
            book_data_port=self.book_data_port,
            interaction_repo=self.interaction_repo,
            catalog_port=getattr(self, "get_books_uc", None),
            personalized_recs_uc=self.get_personalized_recs_uc,
            path_repo=self.learning_path_repo,
        )

        # Personal Knowledge Graph Use Cases
        self.get_knowledge_graph_uc = GetPersonalKnowledgeGraphUseCase(
            knowledge_repo=self.knowledge_repo,
            interaction_repo=self.interaction_repo,
            note_repo=self.note_repo,
            learning_path_repo=self.learning_path_repo,
            catalog_port=self.book_service,
        )
        self.create_relationship_uc = CreateRelationshipUseCase(
            knowledge_repo=self.knowledge_repo,
            note_repo=self.note_repo,
            learning_path_repo=self.learning_path_repo,
        )
        self.update_relationship_uc = UpdateRelationshipUseCase(
            knowledge_repo=self.knowledge_repo,
        )
        self.delete_relationship_uc = DeleteRelationshipUseCase(
            knowledge_repo=self.knowledge_repo,
        )
        self.get_neighbors_uc = GetNeighborsUseCase(
            get_graph_uc=self.get_knowledge_graph_uc,
        )

        self.process_rag_query_uc = ProcessRagQueryUseCase(
            embedding_port=self.embedding_service,
            book_data_port=self.book_data_port,
            interaction_repo=self.interaction_repo,
            recommender=self.recommender,
            enrichment_service=self.enrichment_service,
            llm_port=self.llm_port,
        )

        volatile = self.in_memory_repositories()
        if volatile:
            logger.warning(
                "Non-persistent in-memory repositories are active (data is lost on restart): %s",
                ", ".join(volatile),
            )

    _REPOSITORY_ATTRS = (
        "note_repo",
        "note_review_repo",
        "knowledge_repo",
        "learning_outcomes_repo",
        "learning_path_repo",
    )

    def in_memory_repositories(self) -> list[str]:
        """Names of user-data repositories backed by volatile in-memory adapters."""
        return [
            name
            for name in self._REPOSITORY_ATTRS
            if type(getattr(self, name, None)).__name__.startswith("InMemory")
        ]


# Global container instance
container = Container()
