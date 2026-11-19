import datetime
from typing import Any, Dict, List, Optional, Protocol


class UserInteractionRepository(Protocol):
    def get_user_interactions(self, user_id: str) -> List[Dict[str, Any]]: ...

    def get_user_profile(self, user_id: str) -> Optional[Dict[str, Any]]: ...

    def upsert_interactions(self, entries: List[Dict[str, Any]]) -> None: ...

    def upsert_profile(
        self, user_id: str, genres: List[str], updated_at: str, authors: Optional[List[str]] = None
    ) -> None: ...

    def track_activity(self, payload: Dict[str, Any]) -> None: ...

    def delete_interaction(
        self, user_id: str, book_id: str, interaction_type: Optional[str] = None
    ) -> None: ...

    def get_user_favorites(self, user_id: str) -> List[Dict[str, Any]]: ...


class UserNoteRepository(Protocol):
    """
    Port for persisting and retrieving user learning notes, takeaways, and questions.
    """
    def create_note(
        self, user_id: str, book_id: str, note_type: str, content: str, client_id: Optional[str] = None
    ) -> Dict[str, Any]: ...

    def get_book_notes(self, user_id: str, book_id: str) -> List[Dict[str, Any]]: ...

    def get_user_notes(
        self,
        user_id: str,
        note_type: Optional[str] = None,
        book_id: Optional[str] = None,
        query: Optional[str] = None,
        limit: int = 50,
        offset: int = 0,
    ) -> List[Dict[str, Any]]: ...

    def count_user_notes(
        self,
        user_id: str,
        note_type: Optional[str] = None,
        book_id: Optional[str] = None,
        query: Optional[str] = None,
    ) -> int: ...

    def get_note_by_id(self, note_id: str, user_id: str) -> Optional[Dict[str, Any]]: ...

    def update_note(
        self, note_id: str, user_id: str, content: str, note_type: Optional[str] = None
    ) -> Optional[Dict[str, Any]]: ...

    def delete_note(self, note_id: str, user_id: str) -> bool: ...


class NoteReviewRepository(Protocol):
    """
    Port for persisting and querying spaced repetition smart review schedules.
    """
    def schedule_initial_review(
        self, note_id: str, user_id: str, initial_interval_days: int = 1
    ) -> Dict[str, Any]: ...

    def get_due_reviews(
        self, user_id: str, as_of: Optional[datetime.datetime] = None, limit: int = 50
    ) -> List[Dict[str, Any]]: ...

    def get_review_by_note_id(self, note_id: str, user_id: str) -> Optional[Dict[str, Any]]: ...

    def record_review(
        self,
        note_id: str,
        user_id: str,
        outcome: str,
        next_interval_days: int,
        next_review_at: str,
        new_stage: int,
    ) -> Optional[Dict[str, Any]]: ...

    def get_review_stats(
        self, user_id: str, as_of: Optional[datetime.datetime] = None
    ) -> Dict[str, int]: ...

    def update_review_settings(
        self, note_id: str, user_id: str, status: str
    ) -> Optional[Dict[str, Any]]: ...

    def delete_review_by_note_id(self, note_id: str, user_id: str) -> bool: ...


class SemanticSearchUnavailable(RuntimeError):
    """
    Vector retrieval cannot run in this configuration (no pgvector table/RPC, or the vector
    store failed). Distinct from an empty result: callers must fall back explicitly instead
    of treating the failure as "no semantically similar books".
    """


class BookDataPort(Protocol):
    def get_semantic_candidates(self, likes: List[str], limit: int = 100) -> Dict[str, float]:
        """Books nearest the centroid of the seeds' embeddings. Raises SemanticSearchUnavailable."""
        ...

    def match_query_embeddings(
        self, embedding: List[float], limit: int = 100
    ) -> Dict[str, float]:
        """{book_id: cosine similarity} for a query embedding. Raises SemanticSearchUnavailable."""
        ...

    def get_books_by_isbns(self, isbns: List[str]) -> List[Dict[str, Any]]: ...

    def get_all_books_raw(self) -> List[Dict[str, Any]]: ...

    def add_book(self, book: Dict[str, Any], user_token: Optional[str] = None) -> bool: ...

    def get_all_isbns(self) -> List[str]: ...

    def get_embedding_metadata(self, book_id: str) -> Optional[Dict[str, Any]]: ...

    def upsert_embedding(
        self, book_id: str, embedding: List[float], content_hash: str, model_version: str
    ) -> None: ...

    def find_other_embedding_profiles(self, accepted: List[str], limit: int = 5) -> List[str]:
        """Up to `limit` stored model_version values not in `accepted` (empty when all match)."""
        ...

    def check_health(self) -> bool: ...


class AuthPort(Protocol):
    def verify_token(self, token: str) -> Any: ...


class LlmPort(Protocol):
    def generate_response(self, system_prompt: str, user_prompt: str) -> Optional[str]:
        """
        Generate a text response given a system and user prompt.
        Should handle its own timeouts and fallbacks.
        """
        ...


class EmbeddingPort(Protocol):
    def generate_embedding(self, text: str, max_retries: int = 3) -> Optional[List[float]]:
        """Embedding of a catalog document (canonical book text)."""
        ...

    def embed_query(self, query: str) -> Optional[List[float]]:
        """Embedding of a user search query, in the space of the stored document embeddings."""
        ...


class RecommenderPort(Protocol):
    def recommend(
        self,
        seed_titles: Optional[List[str]] = None,
        top_n: int = 10,
        use_diversity: bool = False,
        semantic_scores: Optional[Dict[str, float]] = None,
        dislikes: Optional[List[str]] = None,
        seed_weights: Optional[Dict[str, float]] = None,
        preferred_genres: Optional[List[str]] = None,
        preferred_authors: Optional[List[str]] = None,
        seed_sources: Optional[Dict[str, str]] = None,
        exclude: Optional[List[str]] = None,
    ) -> List[Dict[str, Any]]:
        """`exclude`: ISBNs (any edition) never to return, applied before ranking."""
        ...


class CatalogPort(Protocol):
    def search_books(self, query: str, limit: int = 10) -> List[Dict[str, Any]]: ...

    def get_popular_books(self, limit: int = 10) -> List[Dict[str, Any]]: ...

    def get_all_books(
        self,
        page: int = 1,
        per_page: int = 50,
        category: Optional[str] = None,
        author: Optional[str] = None,
        publisher: Optional[str] = None,
        min_pages: Optional[int] = None,
        max_pages: Optional[int] = None,
        min_rating: Optional[float] = None,
        published_from: Optional[int] = None,
        published_to: Optional[int] = None,
        sort: Optional[str] = None,
        order: Optional[str] = "asc",
        query: Optional[str] = None,
    ) -> Dict[str, Any]: ...

    def get_unique_categories(self) -> List[Dict[str, Any]]: ...

    def get_book_by_isbn(self, isbn: str) -> Optional[Dict[str, Any]]: ...


class EnrichmentPort(Protocol):
    def enrich(self, books: List[Dict[str, Any]]) -> List[Dict[str, Any]]: ...


class LearningOutcomesRepository(Protocol):
    """
    Port for persisting and querying active-recall review items, attempts, and learning outcomes.
    """
    def create_review_item(
        self,
        user_id: str,
        title: str,
        concept: str,
        question: str,
        answer: str,
        explanation: str = "",
        source_type: str = "user_created",
        source_id: Optional[str] = None,
        book_id: Optional[str] = None,
        path_id: Optional[str] = None,
        initial_stage: int = 1,
        initial_interval_days: int = 1,
        next_review_at: Optional[str] = None,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]: ...

    def get_review_item_by_id(
        self, item_id: str, user_id: str
    ) -> Optional[Dict[str, Any]]: ...

    def update_review_item(
        self, item_id: str, user_id: str, updates: Dict[str, Any]
    ) -> Optional[Dict[str, Any]]: ...

    def delete_review_item(self, item_id: str, user_id: str) -> bool: ...

    def list_review_items(
        self,
        user_id: str,
        concept: Optional[str] = None,
        path_id: Optional[str] = None,
        status: Optional[str] = "active",
        limit: int = 100,
        offset: int = 0,
    ) -> List[Dict[str, Any]]: ...

    def get_due_review_items(
        self,
        user_id: str,
        as_of: Optional[datetime.datetime] = None,
        limit: int = 50,
    ) -> List[Dict[str, Any]]: ...

    def record_review_attempt(
        self,
        user_id: str,
        item_id: str,
        outcome: str,
        is_correct: bool,
        stage_before: int,
        stage_after: int,
        response_text: str = "",
        reviewed_at: Optional[str] = None,
    ) -> Dict[str, Any]: ...

    def get_review_attempts(
        self,
        user_id: str,
        item_id: Optional[str] = None,
        limit: int = 50,
        offset: int = 0,
    ) -> List[Dict[str, Any]]: ...

    def get_concept_stats(self, user_id: str) -> List[Dict[str, Any]]: ...

    def get_user_progress_summary(
        self, user_id: str, as_of: Optional[datetime.datetime] = None
    ) -> Dict[str, Any]: ...


