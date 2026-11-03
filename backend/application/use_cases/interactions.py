import datetime
import logging
from typing import Any, Dict, List, Optional

from ...domain.models import UserInteraction
from ...domain.ports import UserInteractionRepository

logger = logging.getLogger(__name__)


class SubmitOnboardingUseCase:
    def __init__(self, interaction_repo: Optional[UserInteractionRepository]):
        self._interaction_repo = interaction_repo

    def execute(self, user_id: str, book_ids: List[str], genres: List[str]) -> Dict[str, Any]:
        if not self._interaction_repo:
            return {"status": "error", "message": "No Interaction Repo"}

        try:
            entries = [
                UserInteraction(user_id=user_id, book_id=bid, interaction_type="like").model_dump(
                    exclude_unset=True
                )
                for bid in book_ids
            ]
            if entries:
                self._interaction_repo.upsert_interactions(entries)

            self._interaction_repo.upsert_profile(
                user_id=user_id,
                genres=genres,
                updated_at=datetime.datetime.now(datetime.timezone.utc).isoformat(),
            )

            return {"status": "success", "message": "Onboarding complete"}
        except Exception as e:
            logger.error(f"Onboarding error: {e}")
            return {"status": "error", "message": str(e)}


class SubmitFeedbackUseCase:
    def __init__(self, interaction_repo: Optional[UserInteractionRepository]):
        self._interaction_repo = interaction_repo

    def execute(
        self,
        user_id: str,
        book_id: str,
        interaction: str,
        book_title: Optional[str] = None,
        book_author: Optional[str] = None,
        book_image_url: Optional[str] = None,
    ) -> Dict[str, Any]:
        if not self._interaction_repo:
            return {"status": "error"}
        try:
            if interaction == "unfavorite":
                if hasattr(self._interaction_repo, "delete_interaction"):
                    self._interaction_repo.delete_interaction(
                        user_id=user_id, book_id=book_id, interaction_type="favorite"
                    )
                return {"status": "success"}

            if interaction in ("clear", "clear_status"):
                if hasattr(self._interaction_repo, "delete_interaction"):
                    try:
                        self._interaction_repo.delete_interaction(
                            user_id=user_id, book_id=book_id, preserve_favorites=True
                        )
                    except TypeError:
                        self._interaction_repo.delete_interaction(
                            user_id=user_id, book_id=book_id
                        )
                return {"status": "success"}

            if interaction == "remove":
                if hasattr(self._interaction_repo, "delete_interaction"):
                    try:
                        self._interaction_repo.delete_interaction(
                            user_id=user_id, book_id=book_id, preserve_favorites=False
                        )
                    except TypeError:
                        self._interaction_repo.delete_interaction(
                            user_id=user_id, book_id=book_id
                        )
                return {"status": "success"}

            entry = {
                "user_id": user_id,
                "book_id": book_id,
                "interaction_type": interaction,
            }
            if book_title:
                entry["book_title"] = book_title
            if book_author:
                entry["book_author"] = book_author
            if book_image_url:
                entry["book_image_url"] = book_image_url

            self._interaction_repo.upsert_interactions([entry])
            return {
                "status": "success",
                "interaction": interaction,
                "book_id": book_id,
                "idempotent": True,
            }
        except Exception as e:
            logger.error(f"Feedback error: {e}")
            return {"status": "error"}


class TrackUserActivityUseCase:
    def __init__(self, interaction_repo: Optional[UserInteractionRepository]):
        self._interaction_repo = interaction_repo

    def execute(
        self, user_id: str, action: str, book_id: str = "", book_name: str = ""
    ) -> Dict[str, Any]:
        if not user_id:
            raise ValueError("user_id is required")

        logger.info(
            "Activity | user=%s book_id=%s book_name=%s action=%s",
            user_id,
            book_id,
            book_name,
            action,
        )

        if not self._interaction_repo:
            raise RuntimeError("Interaction repo not initialized")

        try:
            payload = {
                "user_id": user_id,
                "activity_type": action,
                "created_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            }
            if book_id:
                payload["book_id"] = book_id

            self._interaction_repo.track_activity(payload)

            if action in ("unfavorite", "remove_favorite") and book_id:
                if hasattr(self._interaction_repo, "delete_interaction"):
                    self._interaction_repo.delete_interaction(
                        user_id=user_id, book_id=book_id, interaction_type="favorite"
                    )
            elif action in ("clear", "clear_status") and book_id:
                if hasattr(self._interaction_repo, "delete_interaction"):
                    try:
                        self._interaction_repo.delete_interaction(
                            user_id=user_id, book_id=book_id, preserve_favorites=True
                        )
                    except TypeError:
                        self._interaction_repo.delete_interaction(
                            user_id=user_id, book_id=book_id
                        )

            # Synchronize explicit rating/preference actions to user_interactions table
            interaction_mapping = {
                "like": "like",
                "book_like": "like",
                "dislike": "dislike",
                "book_dislike": "dislike",
                "favorite": "favorite",
                "book_favorite": "favorite",
                "want_to_read": "want_to_read",
                "book_want_to_read": "want_to_read",
                "reading": "reading",
                "book_reading": "reading",
                "finished": "finished",
                "book_finished": "finished",
            }
            if (
                action in interaction_mapping
                and book_id
                and hasattr(self._interaction_repo, "upsert_interactions")
            ):
                mapped_interaction = interaction_mapping[action]
                model = UserInteraction(
                    user_id=user_id, book_id=book_id, interaction_type=mapped_interaction
                )
                self._interaction_repo.upsert_interactions([model.model_dump(exclude_unset=True)])

            return {"status": "tracked", "user_id": user_id, "action": action}
        except Exception as e:
            logger.error(f"Tracking error: {e}")
            raise e


class GetUserPreferencesUseCase:
    def __init__(self, interaction_repo: Optional[UserInteractionRepository]):
        self._interaction_repo = interaction_repo

    def execute(self, user_id: str) -> Dict[str, Any]:
        if not user_id:
            raise ValueError("user_id is required")
        if not self._interaction_repo:
            return {
                "user_id": user_id,
                "preferred_genres": [],
                "preferred_authors": [],
                "reading_frequency": None,
                "updated_at": None,
            }
        try:
            profile = self._interaction_repo.get_user_profile(user_id) or {}
            return {
                "user_id": user_id,
                "preferred_genres": profile.get("preferred_genres", []) or [],
                "preferred_authors": profile.get("preferred_authors", []) or [],
                "reading_frequency": profile.get("reading_frequency"),
                "updated_at": profile.get("updated_at"),
            }
        except Exception as e:
            logger.error(f"Error fetching user preferences: {e}")
            return {
                "user_id": user_id,
                "preferred_genres": [],
                "preferred_authors": [],
                "reading_frequency": None,
                "updated_at": None,
            }


class UpdateUserPreferencesUseCase:
    def __init__(self, interaction_repo: Optional[UserInteractionRepository]):
        self._interaction_repo = interaction_repo

    def execute(
        self,
        user_id: str,
        genres: List[str],
        authors: Optional[List[str]] = None,
    ) -> Dict[str, Any]:
        if not user_id:
            raise ValueError("user_id is required")
        if not self._interaction_repo:
            return {"status": "error", "message": "Interaction repository not available"}

        try:
            seen_genres = set()
            cleaned_genres = []
            if isinstance(genres, list):
                for g in genres:
                    if isinstance(g, str):
                        cg = g.strip()
                        if cg and len(cg) <= 100 and cg.lower() not in seen_genres:
                            seen_genres.add(cg.lower())
                            cleaned_genres.append(cg)
                            if len(cleaned_genres) >= 50:
                                break

            cleaned_authors = None
            if authors is not None and isinstance(authors, list):
                seen_authors = set()
                cleaned_authors = []
                for a in authors:
                    if isinstance(a, str):
                        ca = a.strip()
                        if ca and len(ca) <= 100 and ca.lower() not in seen_authors:
                            seen_authors.add(ca.lower())
                            cleaned_authors.append(ca)
                            if len(cleaned_authors) >= 50:
                                break

            now_iso = datetime.datetime.now(datetime.timezone.utc).isoformat()

            kwargs = {}
            if cleaned_authors is not None:
                kwargs["authors"] = cleaned_authors

            try:
                self._interaction_repo.upsert_profile(
                    user_id=user_id,
                    genres=cleaned_genres,
                    updated_at=now_iso,
                    **kwargs,
                )
            except TypeError:
                # Backward compatibility with older 3-argument stubs
                self._interaction_repo.upsert_profile(
                    user_id=user_id,
                    genres=cleaned_genres,
                    updated_at=now_iso,
                )

            result = {
                "status": "success",
                "user_id": user_id,
                "preferred_genres": cleaned_genres,
                "updated_at": now_iso,
            }
            if cleaned_authors is not None:
                result["preferred_authors"] = cleaned_authors
            return result
        except Exception as e:
            logger.error(f"Error updating user preferences: {e}")
            return {"status": "error", "message": str(e)}


class ResetPreferencesUseCase:
    """
    Enables user-directed personalization reset / privacy cleanup.
    Clears interactions and resets preferred genres/authors for the authenticated user.
    """
    def __init__(self, interaction_repo: Optional[UserInteractionRepository]):
        self._interaction_repo = interaction_repo

    def execute(self, user_id: str) -> Dict[str, Any]:
        if not user_id:
            raise ValueError("user_id is required")
        if not self._interaction_repo:
            return {"status": "error", "message": "No interaction repo"}
        try:
            now_iso = datetime.datetime.now(datetime.timezone.utc).isoformat()
            if hasattr(self._interaction_repo, "upsert_profile"):
                try:
                    self._interaction_repo.upsert_profile(
                        user_id=user_id,
                        genres=[],
                        updated_at=now_iso,
                        authors=[],
                    )
                except TypeError:
                    self._interaction_repo.upsert_profile(
                        user_id=user_id,
                        genres=[],
                        updated_at=now_iso,
                    )
            if hasattr(self._interaction_repo, "delete_all_user_interactions"):
                self._interaction_repo.delete_all_user_interactions(user_id)
            elif hasattr(self._interaction_repo, "get_user_interactions") and hasattr(self._interaction_repo, "delete_interaction"):
                items = self._interaction_repo.get_user_interactions(user_id) or []
                for item in items:
                    bid = item.get("book_id")
                    if bid:
                        try:
                            self._interaction_repo.delete_interaction(user_id=user_id, book_id=bid)
                        except Exception:
                            pass
            return {"status": "success", "message": "Personalization preferences reset successfully"}
        except Exception as e:
            logger.error(f"Failed to reset preferences for user {user_id}: {e}")
            return {"status": "error", "message": str(e)}
