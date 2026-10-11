import logging
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
        Production-grade personalization with Rocchio relevance feedback,
        explicit preference fusion (favorites, likes, dislikes), and deterministic cold-start.
        """
        if not self._interaction_repo:
            return self._fallback_popular(limit)

        try:
            # 1. Fetch user interactions
            interactions_data = self._interaction_repo.get_user_interactions(user_id)
            if not isinstance(interactions_data, list):
                interactions_data = []

            favorites = []
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
                if itype == "favorite":
                    favorites.append(clean_bid)
                elif itype in ("like", "want_to_read", "finished"):
                    likes.append(clean_bid)
                elif itype == "dislike":
                    dislikes.append(clean_bid)

            dislikes_set = set(dislikes)
            # Active dislikes take strict precedence over older likes and favorites
            favorites_set = set(favorites) - dislikes_set
            likes_set = (set(likes) - dislikes_set) - favorites_set

            # 2. Fetch user profile (genres, authors)
            genres_tuple = ()
            authors_tuple = ()
            profile_data = self._interaction_repo.get_user_profile(user_id)
            if isinstance(profile_data, dict):
                genres = profile_data.get("preferred_genres", [])
                if isinstance(genres, list) and genres:
                    genres_tuple = tuple(
                        sorted(set(str(g).strip() for g in genres if str(g).strip()))
                    )
                authors = profile_data.get("preferred_authors", [])
                if isinstance(authors, list) and authors:
                    authors_tuple = tuple(
                        sorted(set(str(a).strip() for a in authors if str(a).strip()))
                    )

            favorites_tuple = tuple(sorted(favorites_set))
            likes_tuple = tuple(sorted(likes_set))
            dislikes_tuple = tuple(sorted(dislikes_set))

            return self._compute_recs(
                user_id=user_id,
                favorites=favorites_tuple,
                likes=likes_tuple,
                dislikes=dislikes_tuple,
                genres=genres_tuple,
                authors=authors_tuple,
                limit=limit,
            )
        except Exception as e:
            logger.error(f"Failed fetching interactions for personalized recs: {e}")
            return self._fallback_popular(limit)

    def _compute_recs(
        self,
        user_id: str,
        favorites: tuple,
        likes: tuple,
        dislikes: tuple,
        genres: tuple,
        authors: tuple,
        limit: int,
    ) -> List[Dict[str, Any]]:
        try:
            seeds = list(favorites) + list(likes)
            seed_weights = {}
            for f in favorites:
                seed_weights[f] = 2.0  # High positive confidence for favorited books
            for liked_id in likes:
                seed_weights[liked_id] = 1.0  # Standard positive signal for liked books

            # Cold start with zero history and zero profile
            if not seeds and not genres and not authors:
                logger.info(
                    f"User {user_id} has no interaction or profile data. Returning popular books."
                )
                return self._fallback_popular(limit, dislikes=list(dislikes))

            logger.info(
                f"Generating personalized recs for {user_id} with {len(seeds)} seeds, "
                f"{len(genres)} genres, {len(authors)} authors."
            )

            semantic_scores = None
            if seeds and self._book_data_port:
                try:
                    semantic_scores = self._book_data_port.get_semantic_candidates(seeds, limit=100)
                    if semantic_scores:
                        logger.info(f"Retrieved {len(semantic_scores)} semantic candidates.")
                except Exception as e:
                    logger.warning(
                        f"Semantic candidate generation failed: {e}. Degrading to TF-IDF only."
                    )

            t0 = time.time()
            recs = self._recommender.recommend(
                seed_titles=seeds,
                top_n=limit,
                use_diversity=True,
                semantic_scores=semantic_scores,
                dislikes=list(dislikes),
                seed_weights=seed_weights,
                preferred_genres=list(genres),
                preferred_authors=list(authors),
            )

            dislikes_set = set(str(d).strip().replace("-", "") for d in dislikes)
            final_recs = [
                r
                for r in recs
                if str(r.get("isbn13", "")).strip().replace("-", "") not in dislikes_set
            ]

            # Attach fallback reason if missing
            for r in final_recs:
                if "recommendation_reason" not in r:
                    r["recommendation_reason"] = "Based on your personalized taste"

            latency = round((time.time() - t0) * 1000, 2)
            logger.info(
                "Personalized recommendation generated",
                extra={
                    "extra_data": {
                        "personalized_latency_ms": latency,
                        "seed_count": len(seeds),
                        "semantic_candidates": len(semantic_scores) if semantic_scores else 0,
                        "count": len(final_recs),
                    }
                },
            )
            enriched_books = self._enrichment_service.enrich(final_recs)
            return [Recommendation(**book).model_dump() for book in enriched_books]
        except Exception as e:
            logger.error(f"Failed cached personalized recs computation: {e}")
            return self._fallback_popular(limit, dislikes=list(dislikes))

    def _fallback_popular(
        self, limit: int, dislikes: Optional[List[str]] = None
    ) -> List[Dict[str, Any]]:
        extra = len(dislikes) + 10 if dislikes else 0
        books = self._recommender.get_popular_books(limit=limit + extra)
        if dislikes:
            dislikes_clean = set(str(d).strip().replace("-", "").lower() for d in dislikes)
            books = [
                b
                for b in books
                if str(b.get("isbn13", "")).strip().replace("-", "").lower() not in dislikes_clean
                and str(b.get("title", "")).strip().lower() not in dislikes_clean
            ]
        books = books[:limit]
        for b in books:
            if "recommendation_reason" not in b:
                b["recommendation_reason"] = "Trending on Libris right now"
        enriched_books = self._enrichment_service.enrich(books)
        return [Recommendation(**book).model_dump() for book in enriched_books]
