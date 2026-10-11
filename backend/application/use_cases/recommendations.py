import logging
import random
import time
from typing import Any, Dict, List, Optional

from ...domain.models import Recommendation
from ...domain.ports import BookDataPort, EnrichmentPort, RecommenderPort, UserInteractionRepository

logger = logging.getLogger(__name__)


class GetRecommendationsUseCase:
    def __init__(self, recommender: RecommenderPort, enrichment_service: EnrichmentPort):
        self._recommender = recommender
        self._enrichment_service = enrichment_service

    def execute(
        self, book_title: str, top_n: int = 10, use_hybrid: bool = True
    ) -> List[Dict[str, Any]]:
        t0 = time.time()
        books = self._recommender.recommend(
            seed_titles=[book_title],
            top_n=top_n,
            use_diversity=True,
        )
        latency = round((time.time() - t0) * 1000, 2)
        logger.info(
            "Recommendation generated",
            extra={
                "extra_data": {
                    "recommendation_latency_ms": latency,
                    "seed": book_title,
                    "count": len(books),
                }
            },
        )
        enriched_books = self._enrichment_service.enrich(books)
        return [Recommendation(**book).model_dump() for book in enriched_books]


class GetPersonalizedRecommendationsUseCase:
    def __init__(
        self,
        recommender: RecommenderPort,
        interaction_repo: Optional[UserInteractionRepository],
        book_data_port: Optional[BookDataPort],
        enrichment_service: EnrichmentPort,
    ):
        self._recommender = recommender
        self._interaction_repo = interaction_repo
        self._book_data_port = book_data_port
        self._enrichment_service = enrichment_service

    def execute(self, user_id: str, limit: int = 10) -> List[Dict[str, Any]]:
        """
        Production-grade personalization.
        Note: Caching can be handled by a decorator at the service level,
        but the business logic goes here.
        """
        if not self._interaction_repo:
            return self._fallback_popular(limit)

        try:
            # 1. Get user interactions (Likes, Favorites, and Dislikes)
            interactions_data = self._interaction_repo.get_user_interactions(user_id)
            if not isinstance(interactions_data, list):
                interactions_data = []

            likes = []
            dislikes = []
            for item in interactions_data:
                if not isinstance(item, dict):
                    continue
                bid = item.get("book_id")
                itype = item.get("interaction_type")
                if not bid:
                    continue
                clean_bid = str(bid).strip()
                if not clean_bid:
                    continue
                if itype in ("like", "favorite"):
                    likes.append(clean_bid)
                elif itype == "dislike":
                    dislikes.append(clean_bid)

            dislikes_set = set(dislikes)
            # Active dislikes take strict precedence over older likes
            likes_set = set(likes) - dislikes_set

            likes_tuple = tuple(sorted(likes_set))
            dislikes_tuple = tuple(sorted(dislikes_set))

            genres_tuple = ()
            if not likes_tuple:
                profile_data = self._interaction_repo.get_user_profile(user_id)
                if isinstance(profile_data, dict):
                    genres = profile_data.get("preferred_genres", [])
                    if isinstance(genres, list) and genres:
                        genres_tuple = tuple(
                            sorted(set(str(g).strip() for g in genres if str(g).strip()))
                        )

            return self._compute_recs(user_id, likes_tuple, dislikes_tuple, genres_tuple, limit)
        except Exception as e:
            logger.error(f"Failed fetching interactions for personalized recs: {e}")
            return self._fallback_popular(limit)

    def _compute_recs(
        self, user_id: str, likes: tuple, dislikes: tuple, genres: tuple, limit: int
    ) -> List[Dict[str, Any]]:
        try:
            seed_titles = list(likes)

            if not seed_titles and genres:
                logger.info(f"Using preferred genres as seed for {user_id}: {genres}")
                genre_recs = []
                for g in genres[:3]:
                    res = self._recommender.get_all_books(page=1, per_page=10, category=g)
                    for book in res.get("books", []):
                        book["recommendation_reason"] = f"Because you like {g}"
                    genre_recs.extend(res.get("books", []))

                if genre_recs:
                    unique_recs = {r["isbn13"]: r for r in genre_recs}.values()
                    final_genre_recs = list(unique_recs)
                    random.shuffle(final_genre_recs)
                    enriched_books = self._enrichment_service.enrich(final_genre_recs[:limit])
                    return [Recommendation(**book).model_dump() for book in enriched_books]

            if not seed_titles and not genres:
                logger.info(f"User {user_id} has no profile info. Returning trending books.")
                return self._fallback_popular(limit)

            logger.info(
                f"Generating personalized recs for {user_id} with {len(seed_titles)} seeds."
            )

            semantic_scores = None
            if likes and self._book_data_port:
                try:
                    semantic_scores = self._book_data_port.get_semantic_candidates(
                        list(likes), limit=100
                    )
                    if semantic_scores:
                        logger.info(f"Retrieved {len(semantic_scores)} semantic candidates.")
                except Exception as e:
                    logger.warning(
                        f"Semantic candidate generation failed: {e}. Degrading to TF-IDF only."
                    )

            t0 = time.time()
            recs = self._recommender.recommend(
                seed_titles,
                top_n=limit,
                use_diversity=True,
                semantic_scores=semantic_scores,
                dislikes=list(dislikes),
            )

            dislikes_set = set(str(d).strip() for d in dislikes)
            final_recs = [r for r in recs if str(r.get("isbn13", "")).strip() not in dislikes_set]

            # Attach a reason to the final recommendations
            for r in final_recs:
                if "recommendation_reason" not in r:
                    r["recommendation_reason"] = "Based on your recent reading history"

            latency = round((time.time() - t0) * 1000, 2)
            logger.info(
                "Personalized recommendation generated",
                extra={
                    "extra_data": {
                        "personalized_latency_ms": latency,
                        "seed_count": len(seed_titles),
                        "semantic_candidates": len(semantic_scores) if semantic_scores else 0,
                        "count": len(final_recs),
                    }
                },
            )
            enriched_books = self._enrichment_service.enrich(final_recs)
            return [Recommendation(**book).model_dump() for book in enriched_books]
        except Exception as e:
            logger.error(f"Failed cached personalized recs computation: {e}")
            return self._fallback_popular(limit)

    def _fallback_popular(self, limit: int) -> List[Dict[str, Any]]:
        books = self._recommender.get_popular_books(limit=limit)
        for b in books:
            b["recommendation_reason"] = "Trending on Libris right now"
        enriched_books = self._enrichment_service.enrich(books)
        return [Recommendation(**book).model_dump() for book in enriched_books]
