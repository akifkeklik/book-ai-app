from typing import Any, Dict, List, Optional

from ...infrastructure.ml.recommender import BookRecommender
from ..services.enrichment_service import BookEnrichmentService


class GetBooksUseCase:
    def __init__(self, recommender: BookRecommender, enrichment_service: BookEnrichmentService):
        self._recommender = recommender
        self._enrichment_service = enrichment_service

    def execute(self, page: int = 1, per_page: int = 20, category: Optional[str] = None) -> Dict[str, Any]:
        result = self._recommender.get_all_books(page=page, per_page=per_page, category=category)
        result["books"] = self._enrichment_service.enrich(result["books"])
        return result


class SearchBooksUseCase:
    def __init__(self, recommender: BookRecommender, enrichment_service: BookEnrichmentService):
        self._recommender = recommender
        self._enrichment_service = enrichment_service

    def execute(self, query: str, limit: int = 20) -> List[Dict[str, Any]]:
        books = self._recommender.search_books(query=query, limit=limit)
        return self._enrichment_service.enrich(books)


class GetPopularBooksUseCase:
    def __init__(self, recommender: BookRecommender, enrichment_service: BookEnrichmentService):
        self._recommender = recommender
        self._enrichment_service = enrichment_service

    def execute(self, limit: int = 20) -> List[Dict[str, Any]]:
        books = self._recommender.get_popular_books(limit=limit)
        return self._enrichment_service.enrich(books)


class GetBookDetailsUseCase:
    def __init__(self, recommender: BookRecommender, enrichment_service: BookEnrichmentService):
        self._recommender = recommender
        self._enrichment_service = enrichment_service

    def execute(self, isbn: str) -> Optional[Dict[str, Any]]:
        book = self._recommender.get_book_by_isbn(isbn)
        if book:
            enriched = self._enrichment_service.enrich([book])
            return enriched[0] if enriched else None
        return None
