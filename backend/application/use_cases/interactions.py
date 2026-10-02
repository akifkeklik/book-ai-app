import datetime
import logging
from typing import Any, Dict, List, Optional

from ...domain.ports import UserInteractionRepository

logger = logging.getLogger(__name__)


class SubmitOnboardingUseCase:
    def __init__(self, interaction_repo: Optional[UserInteractionRepository]):
        self._interaction_repo = interaction_repo

    def execute(self, user_id: str, book_ids: List[str], genres: List[str]) -> Dict[str, Any]:
        if not self._interaction_repo:
            return {"status": "error", "message": "No Interation Repo"}

        try:
            entries = [
                {"user_id": user_id, "book_id": bid, "interaction_type": "like"} for bid in book_ids
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

    def execute(self, user_id: str, book_id: str, interaction: str) -> Dict[str, Any]:
        if not self._interaction_repo:
            return {"status": "error"}
        try:
            self._interaction_repo.upsert_interactions([
                {"user_id": user_id, "book_id": book_id, "interaction_type": interaction}
            ])
            return {"status": "success"}
        except Exception as e:
            logger.error(f"Feedback error: {e}")
            return {"status": "error"}


class TrackUserActivityUseCase:
    def __init__(self, interaction_repo: Optional[UserInteractionRepository]):
        self._interaction_repo = interaction_repo

    def execute(
        self, user_id: str, action: str, book_id: str = "", book_name: str = ""
    ) -> Dict[str, Any]:
        logger.info(
            "Activity | user=%s book_id=%s book_name=%s action=%s",
            user_id,
            book_id,
            book_name,
            action,
        )

        if not self._interaction_repo:
            return {"status": "error", "message": "Interaction repo not initialized"}

        try:
            payload = {
                "user_id": user_id,
                "activity_type": action,
                "created_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            }
            if book_id:
                payload["book_id"] = book_id

            self._interaction_repo.track_activity(payload)

            return {"status": "tracked", "user_id": user_id, "action": action}
        except Exception as e:
            logger.error(f"Tracking error: {e}")
            raise e
