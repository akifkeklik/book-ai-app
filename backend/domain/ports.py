from typing import Any, Dict, List, Optional, Protocol


class UserInteractionRepository(Protocol):
    def get_user_interactions(self, user_id: str) -> List[Dict[str, Any]]:
        ...

    def get_user_profile(self, user_id: str) -> Optional[Dict[str, Any]]:
        ...

    def upsert_interactions(self, entries: List[Dict[str, Any]]) -> None:
        ...

    def upsert_profile(self, user_id: str, genres: List[str], updated_at: str) -> None:
        ...

    def track_activity(self, payload: Dict[str, Any]) -> None:
        ...


class BookDataPort(Protocol):
    def get_semantic_candidates(
        self, likes: List[str], limit: int = 100
    ) -> Dict[str, float]:
        ...

    def match_query_embeddings(
        self, embedding: List[float], limit: int = 100
    ) -> Dict[str, float]:
        ...

    def get_books_by_isbns(self, isbns: List[str]) -> List[Dict[str, Any]]:
        ...

    def get_all_books_raw(self) -> List[Dict[str, Any]]:
        ...

    def get_embedding_metadata(self, book_id: str) -> Optional[Dict[str, Any]]:
        ...

    def upsert_embedding(
        self, book_id: str, embedding: List[float], content_hash: str, model_version: str
    ) -> None:
        ...

    def check_health(self) -> bool:
        ...


class AuthPort(Protocol):
    def verify_token(self, token: str) -> Any:
        ...


class LlmPort(Protocol):
    def generate_response(self, system_prompt: str, user_prompt: str) -> Optional[str]:
        """
        Generate a text response given a system and user prompt.
        Should handle its own timeouts and fallbacks.
        """
        ...


class EmbeddingPort(Protocol):
    def generate_embedding(self, text: str, max_retries: int = 3) -> Optional[List[float]]:
        ...


class RecommenderPort(Protocol):
    def recommend(
        self,
        seed_titles: Optional[List[str]] = None,
        top_n: int = 10,
        use_diversity: bool = False,
        semantic_scores: Optional[Dict[str, float]] = None,
        dislikes: Optional[List[str]] = None,
    ) -> List[Dict[str, Any]]:
        ...

    def search_books(self, query: str, limit: int = 10) -> List[Dict[str, Any]]:
        ...

    def get_popular_books(self, limit: int = 10) -> List[Dict[str, Any]]:
        ...

    def get_all_books(
        self, page: int = 1, per_page: int = 50, category: Optional[str] = None
    ) -> Dict[str, Any]:
        ...

    def get_unique_categories(self) -> List[str]:
        ...

    def get_book_by_isbn(self, isbn: str) -> Optional[Dict[str, Any]]:
        ...


class EnrichmentPort(Protocol):
    def enrich(self, books: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        ...
