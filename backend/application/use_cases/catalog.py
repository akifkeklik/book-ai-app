from typing import Any, Dict, List, Optional

from ...domain.ports import EnrichmentPort, RecommenderPort


class GetBooksUseCase:
    def __init__(self, recommender: RecommenderPort, enrichment_service: EnrichmentPort):
        self._recommender = recommender
        self._enrichment_service = enrichment_service

    def execute(
        self,
        page: int = 1,
        per_page: int = 20,
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
    ) -> Dict[str, Any]:
        result = self._recommender.get_all_books(
            page=page, per_page=per_page, category=category,
            author=author, publisher=publisher, min_pages=min_pages,
            max_pages=max_pages, min_rating=min_rating,
            published_from=published_from, published_to=published_to,
            sort=sort, order=order
        )
        result["books"] = self._enrichment_service.enrich(result["books"])
        return result


class SearchBooksUseCase:
    def __init__(self, recommender: RecommenderPort, enrichment_service: EnrichmentPort):
        self._recommender = recommender
        self._enrichment_service = enrichment_service

    def execute(self, query: str, limit: int = 20) -> List[Dict[str, Any]]:
        books = self._recommender.search_books(query=query, limit=limit)
        return self._enrichment_service.enrich(books)


class GetPopularBooksUseCase:
    def __init__(self, recommender: RecommenderPort, enrichment_service: EnrichmentPort):
        self._recommender = recommender
        self._enrichment_service = enrichment_service

    def execute(self, limit: int = 20) -> List[Dict[str, Any]]:
        books = self._recommender.get_popular_books(limit=limit)
        return self._enrichment_service.enrich(books)


class GetBookDetailsUseCase:
    def __init__(self, recommender: RecommenderPort, enrichment_service: EnrichmentPort):
        self._recommender = recommender
        self._enrichment_service = enrichment_service

    def execute(self, isbn: str) -> Optional[Dict[str, Any]]:
        book = self._recommender.get_book_by_isbn(isbn)
        if book:
            enriched = self._enrichment_service.enrich([book])
            return enriched[0] if enriched else None
        return None
