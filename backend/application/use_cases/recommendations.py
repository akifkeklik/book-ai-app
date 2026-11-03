import datetime
import logging
import re
import time
from typing import Any, Dict, List, Optional, Set

from ...domain.models import Recommendation, UserPreferenceProfile
from ...domain.ports import (
    BookDataPort,
    EnrichmentPort,
    LearningPathRepository,
    NoteReviewRepository,
    RecommenderPort,
    UserInteractionRepository,
    UserNoteRepository,
)

logger = logging.getLogger(__name__)

# Named configurable scoring weights for adaptive ranking
WEIGHT_FAVORITE = 2.5
WEIGHT_FINISHED = 2.0
WEIGHT_READING = 1.5
WEIGHT_NOTE = 1.4
WEIGHT_TAKEAWAY = 1.9
WEIGHT_LIKE = 1.2
WEIGHT_WANT_TO_READ = 0.8
WEIGHT_PATH_MEMBER = 1.5
BONUS_SPACED_RETENTION = 0.2
PENALTY_SPACED_STRUGGLE = -0.1
WEIGHT_CATEGORY_AFFINITY = 0.25
WEIGHT_AUTHOR_AFFINITY = 0.20


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
    """
    Unified Explainable Adaptive Ranking Engine.
    Orchestrates:
    1. Candidate retrieval
    2. Eligibility filtering (hard negative suppression, completed exclusion, path membership)
    3. User preference profile derivation
    4. Positive relevance scoring with named weights
    5. Diversity and canonical deduplication
    6. Deterministic tie-breaking
    7. Honest typed explanation generation
    8. Diagnostic telemetry reporting
    """

    def __init__(
        self,
        recommender: RecommenderPort,
        interaction_repo: Optional[UserInteractionRepository],
        book_data_port: Optional[BookDataPort],
        enrichment_service: EnrichmentPort,
        note_repo: Optional[UserNoteRepository] = None,
        review_repo: Optional[NoteReviewRepository] = None,
        learning_path_repo: Optional[LearningPathRepository] = None,
    ):
        self._recommender = recommender
        self._interaction_repo = interaction_repo
        self._book_data_port = book_data_port
        self._enrichment_service = enrichment_service
        self._note_repo = note_repo
        self._review_repo = review_repo
        self._learning_path_repo = learning_path_repo

    def build_user_preference_profile(self, user_id: str) -> UserPreferenceProfile:
        """
        Derives a lightweight, privacy-conscious user preference profile on-demand.
        Never persists or leaks raw note contents; deterministically reconciles signals.
        """
        if not user_id:
            return UserPreferenceProfile(user_id="anonymous", evidence_coverage="cold_start")

        favorites = []
        finished = []
        reading = []
        likes = []
        want_to_read = []
        dislikes = []

        if self._interaction_repo:
            try:
                interactions_data = self._interaction_repo.get_user_interactions(user_id)
                if isinstance(interactions_data, list):
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
                        elif itype == "finished":
                            finished.append(clean_bid)
                        elif itype == "reading":
                            reading.append(clean_bid)
                        elif itype == "like":
                            likes.append(clean_bid)
                        elif itype == "want_to_read":
                            want_to_read.append(clean_bid)
                        elif itype == "dislike":
                            dislikes.append(clean_bid)
            except Exception as e:
                logger.warning(f"Error reading interactions for profile: {e}")

            # Check direct favorites table if available
            try:
                if hasattr(self._interaction_repo, "get_user_favorites"):
                    fav_rows = self._interaction_repo.get_user_favorites(user_id) or []
                    for f in fav_rows:
                        f_bid = str(f.get("book_id", "")).strip()
                        if f_bid and f_bid not in favorites:
                            favorites.append(f_bid)
            except Exception as e:
                logger.debug(f"Could not load direct favorites: {e}")

        dislikes_set = set(dislikes)
        favorites_set = set(favorites) - dislikes_set
        finished_set = (set(finished) - dislikes_set) - favorites_set
        reading_set = ((set(reading) - dislikes_set) - favorites_set) - finished_set
        likes_set = (((set(likes) - dislikes_set) - favorites_set) - finished_set) - reading_set
        want_to_read_set = (
            (((set(want_to_read) - dislikes_set) - favorites_set) - finished_set)
            - reading_set
        ) - likes_set

        # Explicit user preferences (genres, authors)
        preferred_genres = []
        preferred_authors = []
        if self._interaction_repo:
            try:
                profile_data = self._interaction_repo.get_user_profile(user_id)
                if isinstance(profile_data, dict):
                    genres = profile_data.get("preferred_genres", [])
                    if isinstance(genres, list):
                        preferred_genres = [str(g).strip() for g in genres if str(g).strip()]
                    authors = profile_data.get("preferred_authors", [])
                    if isinstance(authors, list):
                        preferred_authors = [str(a).strip() for a in authors if str(a).strip()]
            except Exception as e:
                logger.warning(f"Error reading user profile: {e}")

        # Notes and key takeaways
        total_notes = 0
        takeaway_count = 0
        note_book_ids: Set[str] = set()
        if self._note_repo:
            try:
                notes = self._note_repo.get_user_notes(user_id=user_id, limit=200) or []
                total_notes = len(notes)
                for n in notes:
                    nbid = str(n.get("book_id", "")).strip()
                    if nbid and nbid not in dislikes_set:
                        note_book_ids.add(nbid)
                    if n.get("note_type") == "key_takeaway":
                        takeaway_count += 1
            except Exception as e:
                logger.warning(f"Error reading user notes: {e}")

        # Spaced repetition retention stats
        retention_summary = {}
        if self._review_repo:
            try:
                stats = self._review_repo.get_review_stats(user_id=user_id)
                if isinstance(stats, dict):
                    retention_summary = stats
            except Exception as e:
                logger.debug(f"Could not load review stats: {e}")

        # Active learning paths
        active_paths_count = 0
        path_categories = []
        path_book_ids: Set[str] = set()
        if self._learning_path_repo:
            try:
                user_paths = self._learning_path_repo.get_user_paths(user_id=user_id) or []
                for p in user_paths:
                    if p.get("status") == "active":
                        active_paths_count += 1
                        cat = str(p.get("category", "")).strip()
                        if cat:
                            path_categories.append(cat)
                        for pb in p.get("books", []):
                            pbid = str(pb.get("book_id", "")).strip()
                            if pbid and pbid not in dislikes_set:
                                path_book_ids.add(pbid)
            except Exception as e:
                logger.debug(f"Could not load learning paths: {e}")

        # Compute Category Affinities
        category_counts: Dict[str, float] = {}
        for g in preferred_genres:
            category_counts[g.lower()] = category_counts.get(g.lower(), 0.0) + 3.0
        for pc in path_categories:
            category_counts[pc.lower()] = category_counts.get(pc.lower(), 0.0) + 2.0

        all_pos_isbns = list(favorites_set | finished_set | reading_set | likes_set | note_book_ids | path_book_ids)
        if all_pos_isbns and self._book_data_port:
            try:
                raw_books = self._book_data_port.get_books_by_isbns(all_pos_isbns[:50]) or []
                for rb in raw_books:
                    cats_str = str(rb.get("categories", "")).lower()
                    if cats_str:
                        for part in re.split(r"[,|;/]+", cats_str):
                            c_clean = part.strip()
                            if c_clean:
                                category_counts[c_clean] = category_counts.get(c_clean, 0.0) + 1.0
            except Exception as e:
                logger.debug(f"Could not load book categories for affinity: {e}")

        max_cat_count = max(category_counts.values()) if category_counts else 1.0
        category_affinities = {
            k: round(v / max_cat_count, 3) for k, v in category_counts.items()
        }

        # Evidence coverage classification
        pos_signal_count = len(favorites_set) + len(finished_set) + len(reading_set) + len(likes_set) + len(want_to_read_set)
        neg_signal_count = len(dislikes_set)

        if pos_signal_count == 0 and len(preferred_genres) == 0 and len(note_book_ids) == 0 and active_paths_count == 0:
            evidence_coverage = "cold_start"
        elif pos_signal_count < 3 and len(preferred_genres) < 2 and len(note_book_ids) < 2:
            evidence_coverage = "emerging"
        else:
            evidence_coverage = "established"

        return UserPreferenceProfile(
            user_id=user_id,
            category_affinities=category_affinities,
            author_affinities={},
            preferred_genres=preferred_genres,
            preferred_authors=preferred_authors,
            positive_signal_count=pos_signal_count,
            negative_signal_count=neg_signal_count,
            total_notes_count=total_notes,
            takeaway_count=takeaway_count,
            retention_summary=retention_summary,
            active_learning_paths_count=active_paths_count,
            disliked_isbns=sorted(dislikes_set),
            completed_isbns=sorted(finished_set),
            reading_isbns=sorted(reading_set),
            favorite_isbns=sorted(favorites_set),
            liked_isbns=sorted(likes_set),
            want_to_read_isbns=sorted(want_to_read_set),
            evidence_coverage=evidence_coverage,
            profile_version="2.6.0",
            computed_at=datetime.datetime.now(datetime.timezone.utc).isoformat(),
        )

    def execute(
        self,
        user_id: str,
        limit: int = 10,
        category: Optional[str] = None,
        exclude_completed: bool = False,
        path_id: Optional[str] = None,
        include_diagnostics: bool = False,
    ) -> Any:
        """
        Executes adaptive ranking.
        When include_diagnostics=False (default), returns List[Dict[str, Any]] (100% backward-compatible).
        When include_diagnostics=True, returns Dict[str, Any] containing recommendations and diagnostic telemetry.
        """
        t0 = time.time()
        limit = max(1, min(limit, 50))

        if not self._interaction_repo:
            recs = self._fallback_popular(limit, category=category)
            if include_diagnostics:
                return {
                    "user_id": user_id,
                    "recommendations": recs,
                    "total": len(recs),
                    "is_cold_start": True,
                    "evidence_coverage": "cold_start",
                    "diagnostics": {
                        "engine_version": "2.6.0",
                        "candidate_count": len(recs),
                        "filtered_count": 0,
                        "is_cold_start": True,
                        "evidence_coverage": "cold_start",
                        "fallback_reason": "no_interaction_repo",
                        "latency_ms": round((time.time() - t0) * 1000, 2),
                    },
                }
            return recs

        try:
            profile = self.build_user_preference_profile(user_id)

            # Build clean sets for exclusion filtering
            dislikes_clean = set(d.strip().replace("-", "").lower() for d in profile.disliked_isbns)
            completed_clean = (
                set(c.strip().replace("-", "").lower() for c in profile.completed_isbns)
                if exclude_completed
                else set()
            )

            # If path_id is supplied, resolve path books for exclusion and topic guidance
            path_books_clean: Set[str] = set()
            path_title = ""
            effective_category = category
            if path_id and self._learning_path_repo:
                try:
                    path_obj = self._learning_path_repo.get_path_by_id(path_id=path_id, user_id=user_id)
                    if path_obj:
                        path_title = path_obj.get("title", "")
                        if not effective_category and path_obj.get("category"):
                            effective_category = path_obj.get("category")
                        for pb in path_obj.get("books", []):
                            p_isbn = str(pb.get("book_id", "")).strip().replace("-", "").lower()
                            if p_isbn:
                                path_books_clean.add(p_isbn)
                except Exception as pe:
                    logger.warning(f"Could not load learning path {path_id} for recommendations: {pe}")

            # Cold start fallback with zero positive signals and zero profile preferences
            if profile.evidence_coverage == "cold_start":
                recs = self._fallback_popular(
                    limit=limit,
                    dislikes=profile.disliked_isbns,
                    completed=profile.completed_isbns if exclude_completed else None,
                    path_books=list(path_books_clean),
                    category=effective_category,
                )
                if include_diagnostics:
                    return {
                        "user_id": user_id,
                        "recommendations": recs,
                        "total": len(recs),
                        "is_cold_start": True,
                        "evidence_coverage": "cold_start",
                        "diagnostics": {
                            "engine_version": "2.6.0",
                            "candidate_count": len(recs),
                            "filtered_count": len(profile.disliked_isbns),
                            "is_cold_start": True,
                            "evidence_coverage": "cold_start",
                            "fallback_reason": "sparse_profile_cold_start",
                            "latency_ms": round((time.time() - t0) * 1000, 2),
                        },
                    }
                return recs

            # Assemble positive seeds and source attributions
            seed_sources: Dict[str, str] = {}
            seed_weights: Dict[str, float] = {}

            # 1. Favorites (highest explicit preference)
            for f in profile.favorite_isbns:
                seed_sources[f] = "favorite"
                seed_weights[f] = WEIGHT_FAVORITE

            # 2. Finished books (completed reading journey)
            for fn in profile.completed_isbns:
                if fn not in seed_sources:
                    seed_sources[fn] = "finished"
                    seed_weights[fn] = WEIGHT_FINISHED

            # 3. Currently reading
            for rd in profile.reading_isbns:
                if rd not in seed_sources:
                    seed_sources[rd] = "reading"
                    seed_weights[rd] = WEIGHT_READING

            # 4. Likes
            for lk in profile.liked_isbns:
                if lk not in seed_sources:
                    seed_sources[lk] = "like"
                    seed_weights[lk] = WEIGHT_LIKE

            # 5. Want to read
            for wr in profile.want_to_read_isbns:
                if wr not in seed_sources:
                    seed_sources[wr] = "want_to_read"
                    seed_weights[wr] = WEIGHT_WANT_TO_READ

            # 6. Learning Notes & Key Takeaways engagement signals
            if self._note_repo:
                try:
                    user_notes = self._note_repo.get_user_notes(user_id=user_id, limit=100) or []
                    for n in user_notes:
                        nbid = str(n.get("book_id", "")).strip()
                        if nbid and nbid not in dislikes_clean:
                            is_takeaway = n.get("note_type") == "key_takeaway"
                            if nbid not in seed_sources:
                                seed_sources[nbid] = "takeaway" if is_takeaway else "notes"
                                seed_weights[nbid] = WEIGHT_TAKEAWAY if is_takeaway else WEIGHT_NOTE
                            else:
                                # Boost existing weight with note bonus
                                seed_weights[nbid] += 0.5 if is_takeaway else 0.3
                                if is_takeaway and seed_sources[nbid] not in ("favorite", "like"):
                                    seed_sources[nbid] = "takeaway"
                except Exception as ne:
                    logger.warning(f"Could not load notes for ranking: {ne}")

            # 7. Spaced repetition retention outcome signals
            if self._review_repo and seed_weights:
                try:
                    due_revs = self._review_repo.get_due_reviews(user_id=user_id, limit=100) or []
                    # Positive reinforcement for books with active review schedules
                    for r in due_revs:
                        rbid = str(r.get("book_id", "")).strip()
                        if rbid in seed_weights:
                            seed_weights[rbid] += BONUS_SPACED_RETENTION
                except Exception as re_err:
                    logger.debug(f"Could not load review schedules for weight adjustment: {re_err}")

            seeds = list(seed_sources.keys())

            # Cold start check after seed assembly
            if not seeds and not profile.preferred_genres and not profile.preferred_authors and not effective_category:
                recs = self._fallback_popular(
                    limit=limit,
                    dislikes=profile.disliked_isbns,
                    completed=profile.completed_isbns if exclude_completed else None,
                    path_books=list(path_books_clean),
                    category=effective_category,
                )
                if include_diagnostics:
                    return {
                        "user_id": user_id,
                        "recommendations": recs,
                        "total": len(recs),
                        "is_cold_start": True,
                        "evidence_coverage": "cold_start",
                        "diagnostics": {
                            "engine_version": "2.6.0",
                            "candidate_count": len(recs),
                            "filtered_count": len(profile.disliked_isbns),
                            "is_cold_start": True,
                            "evidence_coverage": "cold_start",
                            "fallback_reason": "no_seeds_available",
                            "latency_ms": round((time.time() - t0) * 1000, 2),
                        },
                    }
                return recs

            # Semantic candidate retrieval
            semantic_scores = None
            if seeds and self._book_data_port:
                try:
                    semantic_scores = self._book_data_port.get_semantic_candidates(seeds, limit=100)
                except Exception as e:
                    logger.warning(f"Semantic candidate generation failed: {e}. Degrading to TF-IDF.")

            recs_limit = max(limit * 3, 30) if effective_category else max(limit * 2, 20)
            effective_genres = list(profile.preferred_genres)
            if effective_category and effective_category.strip():
                cat_name = effective_category.strip()
                if cat_name not in effective_genres:
                    effective_genres.insert(0, cat_name)

            raw_recs = self._recommender.recommend(
                seed_titles=seeds,
                top_n=recs_limit,
                use_diversity=True,
                semantic_scores=semantic_scores,
                dislikes=list(profile.disliked_isbns),
                seed_weights=seed_weights,
                preferred_genres=effective_genres,
                preferred_authors=list(profile.preferred_authors),
                seed_sources=seed_sources,
            )

            # Strict Eligibility Filtering (Dislikes, Completed if requested, Path books if requested)
            filtered_candidates = []
            seen_isbns = set()
            seen_titles = set()
            filtered_count = 0

            for r in raw_recs:
                r_isbn = str(r.get("isbn13", "")).strip().replace("-", "").lower()
                r_title = str(r.get("title", "")).strip().lower()

                # Hard dislike suppression
                if r_isbn in dislikes_clean or r_title in dislikes_clean:
                    filtered_count += 1
                    continue

                # Completed-book exclusion
                if exclude_completed and (r_isbn in completed_clean or r_title in completed_clean):
                    filtered_count += 1
                    continue

                # Target learning path exclusion
                if path_books_clean and (r_isbn in path_books_clean or r_title in path_books_clean):
                    filtered_count += 1
                    continue

                # Deduplication by canonical identity
                if (r_isbn and r_isbn in seen_isbns) or (r_title and r_title in seen_titles):
                    filtered_count += 1
                    continue

                if r_isbn:
                    seen_isbns.add(r_isbn)
                if r_title:
                    seen_titles.add(r_title)

                filtered_candidates.append(r)

            # Strict category scoping if requested
            if effective_category and effective_category.strip():
                cat_clean = effective_category.strip().lower()
                cat_matched = [
                    r for r in filtered_candidates
                    if cat_clean in str(r.get("categories", "")).lower()
                ]

                # Backfill from popular in category if needed
                if len(cat_matched) < limit:
                    fill_recs = self._fallback_popular(
                        limit=limit * 2 + 10,
                        dislikes=profile.disliked_isbns,
                        completed=profile.completed_isbns if exclude_completed else None,
                        path_books=list(path_books_clean),
                        category=effective_category,
                    )
                    for b in fill_recs:
                        b_isbn = str(b.get("isbn13", "")).strip().replace("-", "").lower()
                        b_title = str(b.get("title", "")).strip().lower()
                        if (b_isbn and b_isbn in seen_isbns) or (b_title and b_title in seen_titles):
                            continue
                        if b_isbn in dislikes_clean or (exclude_completed and b_isbn in completed_clean):
                            continue
                        if path_books_clean and b_isbn in path_books_clean:
                            continue
                        if b_isbn:
                            seen_isbns.add(b_isbn)
                        if b_title:
                            seen_titles.add(b_title)
                        cat_matched.append(b)
                        if len(cat_matched) >= limit:
                            break
                filtered_candidates = cat_matched

            final_recs = filtered_candidates[:limit]

            # If recommendation set is still empty (e.g. strict filters exhausted candidates), fallback safely
            if not final_recs:
                final_recs = self._fallback_popular(
                    limit=limit,
                    dislikes=profile.disliked_isbns,
                    completed=profile.completed_isbns if exclude_completed else None,
                    path_books=list(path_books_clean),
                    category=effective_category,
                )

            # Enrich and ensure typed explanation contract on all recommendations
            for r in final_recs:
                # If path_id is supplied, customize explanation for learning path continuity
                if path_id:
                    if not r.get("explanation_type") or r.get("explanation_type") in ("trending_catalog", "category_affinity"):
                        r["explanation_type"] = "learning_path_continuity"
                        r["recommendation_reason"] = (
                            f"For your learning path '{path_title}'"
                            if path_title
                            else "Recommended for your learning path"
                        )
                        r["confidence"] = "high"
                        r["is_cold_start"] = False

                # Ensure non-null explanation fields
                if "explanation_type" not in r or not r.get("explanation_type"):
                    r["explanation_type"] = (
                        "trending_catalog" if profile.evidence_coverage == "cold_start" else "category_affinity"
                    )
                if "confidence" not in r or not r.get("confidence"):
                    r["confidence"] = (
                        "cold_start" if profile.evidence_coverage == "cold_start" else "medium"
                    )
                if "is_cold_start" not in r:
                    r["is_cold_start"] = profile.evidence_coverage == "cold_start"
                if "recommendation_reason" not in r or not r.get("recommendation_reason"):
                    if effective_category:
                        r["recommendation_reason"] = f"Popular in {effective_category.strip().title()}"
                    else:
                        r["recommendation_reason"] = "Curated based on your taste profile"
                if "explanation" not in r or not r.get("explanation"):
                    r["explanation"] = (
                        f"Bu kitap, {r['recommendation_reason']} doğrultusunda önerildi."
                    )

            enriched_books = self._enrichment_service.enrich(final_recs)
            formatted_recs = [Recommendation(**book).model_dump() for book in enriched_books]

            latency = round((time.time() - t0) * 1000, 2)
            is_cold = profile.evidence_coverage == "cold_start"

            if include_diagnostics:
                return {
                    "user_id": user_id,
                    "recommendations": formatted_recs,
                    "total": len(formatted_recs),
                    "is_cold_start": is_cold,
                    "evidence_coverage": profile.evidence_coverage,
                    "diagnostics": {
                        "engine_version": "2.6.0",
                        "candidate_count": len(raw_recs) if 'raw_recs' in locals() else len(formatted_recs),
                        "filtered_count": filtered_count,
                        "is_cold_start": is_cold,
                        "evidence_coverage": profile.evidence_coverage,
                        "fallback_reason": None,
                        "latency_ms": latency,
                    },
                }

            return formatted_recs

        except Exception as exc:
            logger.error(f"Adaptive personalized recommendation failed: {exc}")
            fallback_recs = self._fallback_popular(
                limit=limit,
                dislikes=list(profile.disliked_isbns) if 'profile' in locals() else None,
                completed=list(profile.completed_isbns) if 'profile' in locals() and exclude_completed else None,
                path_books=list(path_books_clean) if 'path_books_clean' in locals() else None,
                category=category,
            )
            if include_diagnostics:
                return {
                    "user_id": user_id,
                    "recommendations": fallback_recs,
                    "total": len(fallback_recs),
                    "is_cold_start": True,
                    "evidence_coverage": "cold_start",
                    "diagnostics": {
                        "engine_version": "2.6.0",
                        "candidate_count": len(fallback_recs),
                        "filtered_count": 0,
                        "is_cold_start": True,
                        "evidence_coverage": "cold_start",
                        "fallback_reason": str(exc),
                        "latency_ms": round((time.time() - t0) * 1000, 2),
                    },
                }
            return fallback_recs

    def _fallback_popular(
        self,
        limit: int,
        dislikes: Optional[List[str]] = None,
        completed: Optional[List[str]] = None,
        path_books: Optional[List[str]] = None,
        category: Optional[str] = None,
    ) -> List[Dict[str, Any]]:
        """
        Deterministic, safe catalog-backed fallback respecting all exclusion rules.
        """
        extra = (len(dislikes or []) + len(completed or []) + len(path_books or [])) * 2 + 30
        books = []
        if self._recommender and hasattr(self._recommender, "get_popular_books"):
            try:
                books = self._recommender.get_popular_books(limit=max(limit + extra, 30))
            except Exception as e:
                logger.warning(f"Recommender get_popular_books failed: {e}")
                books = []

        if not books and self._book_data_port and hasattr(self._book_data_port, "get_popular_books"):
            try:
                raw_books = self._book_data_port.get_popular_books(limit=max(limit + extra, 30))
                books = [
                    b.model_dump() if hasattr(b, "model_dump") else (b if isinstance(b, dict) else vars(b))
                    for b in raw_books
                ]
            except Exception as e:
                logger.warning(f"BookDataPort get_popular_books failed: {e}")
                books = []

        if category and category.strip():
            cat_clean = category.strip().lower()
            books = [
                b for b in books
                if cat_clean in str(b.get("categories", "")).lower()
            ]

        # Assemble exclusion set
        exclusion_set = set()
        if dislikes:
            for d in dislikes:
                d_str = str(d).strip().lower()
                if d_str:
                    exclusion_set.add(d_str)
                    exclusion_set.add(d_str.replace("-", ""))
        if completed:
            for c in completed:
                c_str = str(c).strip().lower()
                if c_str:
                    exclusion_set.add(c_str)
                    exclusion_set.add(c_str.replace("-", ""))
        if path_books:
            for p in path_books:
                p_str = str(p).strip().lower()
                if p_str:
                    exclusion_set.add(p_str)
                    exclusion_set.add(p_str.replace("-", ""))

        if exclusion_set:
            books = [
                b
                for b in books
                if str(b.get("isbn13", "")).strip().lower() not in exclusion_set
                and str(b.get("isbn13", "")).strip().replace("-", "").lower() not in exclusion_set
                and str(b.get("title", "")).strip().lower() not in exclusion_set
                and str(b.get("title", "")).strip().replace("-", "").lower() not in exclusion_set
            ]

        # Strict deduplication by ISBN and title
        seen_isbns = set()
        seen_titles = set()
        deduped = []
        for b in books:
            isbn = str(b.get("isbn13", "")).strip().replace("-", "").lower()
            title = str(b.get("title", "")).strip().lower()
            if isbn and isbn in seen_isbns:
                continue
            if title and title in seen_titles:
                continue
            if isbn:
                seen_isbns.add(isbn)
            if title:
                seen_titles.add(title)
            deduped.append(b)
            if len(deduped) >= limit:
                break

        for b in deduped:
            if category and category.strip():
                b["recommendation_reason"] = f"Popular in {category.strip().title()}"
            elif "recommendation_reason" not in b or not b.get("recommendation_reason"):
                b["recommendation_reason"] = "Trending on Libris right now"
            if "explanation_type" not in b or not b.get("explanation_type"):
                b["explanation_type"] = "trending_catalog"
            if "confidence" not in b or not b.get("confidence"):
                b["confidence"] = "cold_start"
            if "is_cold_start" not in b:
                b["is_cold_start"] = True
            if "explanation" not in b or not b.get("explanation"):
                b["explanation"] = (
                    f"Bu kitap, {b['recommendation_reason']} doğrultusunda seçildi."
                )

        enriched_books = self._enrichment_service.enrich(deduped)
        return [Recommendation(**book).model_dump() for book in enriched_books]
