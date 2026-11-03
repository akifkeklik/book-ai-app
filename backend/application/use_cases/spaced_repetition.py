import datetime
import logging
from typing import Any, Dict, List, Optional, Tuple

from ...domain.ports import BookDataPort, NoteReviewRepository, UserNoteRepository

logger = logging.getLogger(__name__)

# Default spaced repetition intervals in days (Stage 1 to 4)
INTERVAL_DAYS_MAP: Dict[int, int] = {
    1: 1,   # 1st review: 1 day
    2: 3,   # 2nd review: 3 days
    3: 7,   # 3rd review: 7 days
    4: 30,  # 4th review: 30 days
}

VALID_OUTCOMES = {"remembered", "struggled"}
VALID_STATUSES = {"active", "paused", "completed"}


def calculate_next_schedule(
    current_stage: int,
    outcome: str,
    as_of: Optional[datetime.datetime] = None,
) -> Tuple[int, int, datetime.datetime]:
    """
    Deterministic spaced repetition calculation.
    Returns: (new_stage, next_interval_days, next_review_at)
    """
    base_time = as_of or datetime.datetime.now(datetime.timezone.utc)
    clean_outcome = outcome.strip().lower()

    if clean_outcome not in VALID_OUTCOMES:
        raise ValueError(f"Invalid outcome: '{outcome}'. Allowed: {sorted(VALID_OUTCOMES)}")

    stage = max(1, min(current_stage, 4))

    if clean_outcome == "remembered":
        # Progress to next stage up to stage 4
        new_stage = min(4, stage + 1)
        next_interval = INTERVAL_DAYS_MAP[new_stage]
    else:  # struggled
        # Fall back or step down interval
        if stage <= 1:
            new_stage = 1
            next_interval = 1
        elif stage == 2:
            new_stage = 1
            next_interval = 1
        elif stage == 3:
            new_stage = 2
            next_interval = 3
        else:  # stage 4
            new_stage = 3
            next_interval = 7

    next_review_at = base_time + datetime.timedelta(days=next_interval)
    return new_stage, next_interval, next_review_at


class GetDueReviewsUseCase:
    def __init__(
        self,
        review_repo: NoteReviewRepository,
        note_repo: UserNoteRepository,
        book_data_port: Optional[BookDataPort] = None,
    ):
        self._review_repo = review_repo
        self._note_repo = note_repo
        self._book_data_port = book_data_port

    def execute(
        self,
        user_id: str,
        as_of: Optional[datetime.datetime] = None,
        limit: int = 50,
    ) -> List[Dict[str, Any]]:
        if not user_id or not user_id.strip():
            raise ValueError("user_id is required")

        clean_user_id = user_id.strip()
        due_reviews = self._review_repo.get_due_reviews(clean_user_id, as_of=as_of, limit=limit)

        enriched = []
        book_ids_to_fetch = set()

        for review in due_reviews:
            item = dict(review)
            note_id = str(item.get("note_id", "")).strip()
            # Fetch note details if not already present
            if "note" not in item or not item["note"]:
                note = self._note_repo.get_note_by_id(note_id, clean_user_id)
                if not note:
                    # Note was deleted or does not exist for this user; skip orphan
                    continue
                item["note"] = note
            else:
                note = item["note"]

            b_id = str(note.get("book_id", "")).strip()
            if b_id:
                book_ids_to_fetch.add(b_id)
            enriched.append(item)

        # Batch enrich book metadata
        if self._book_data_port and book_ids_to_fetch:
            try:
                books = self._book_data_port.get_books_by_isbns(list(book_ids_to_fetch))
                book_map = {
                    str(b.get("isbn13") or b.get("isbn") or "").strip(): b
                    for b in (books or [])
                }
                for item in enriched:
                    note = item.get("note") or {}
                    bid = str(note.get("book_id", "")).strip()
                    if bid in book_map:
                        b = book_map[bid]
                        note["book"] = {
                            "isbn13": b.get("isbn13") or bid,
                            "title": b.get("title") or "Unknown Title",
                            "authors": b.get("authors") or "Unknown Author",
                            "thumbnail": b.get("thumbnail") or "",
                        }
            except Exception as e:
                logger.warning(f"Could not batch enrich reviews with book metadata: {e}")

        return enriched


class GetReviewStatsUseCase:
    def __init__(self, review_repo: NoteReviewRepository):
        self._review_repo = review_repo

    def execute(
        self, user_id: str, as_of: Optional[datetime.datetime] = None
    ) -> Dict[str, int]:
        if not user_id or not user_id.strip():
            raise ValueError("user_id is required")
        return self._review_repo.get_review_stats(user_id.strip(), as_of=as_of)


class ProcessReviewUseCase:
    def __init__(
        self,
        review_repo: NoteReviewRepository,
        note_repo: UserNoteRepository,
    ):
        self._review_repo = review_repo
        self._note_repo = note_repo

    def execute(
        self,
        note_id: str,
        user_id: str,
        outcome: str,
        as_of: Optional[datetime.datetime] = None,
    ) -> Optional[Dict[str, Any]]:
        if not note_id or not user_id:
            raise ValueError("note_id and user_id are required")

        clean_user_id = user_id.strip()
        clean_note_id = note_id.strip()

        # 1. Verify note exists and belongs to user
        note = self._note_repo.get_note_by_id(clean_note_id, clean_user_id)
        if not note:
            return None

        # 2. Get existing review schedule or initialize it
        review = self._review_repo.get_review_by_note_id(clean_note_id, clean_user_id)
        if not review:
            review = self._review_repo.schedule_initial_review(clean_note_id, clean_user_id, 1)

        current_stage = int(review.get("stage", 1))

        # 3. Calculate next stage & interval deterministically
        new_stage, next_interval, next_review_at = calculate_next_schedule(
            current_stage=current_stage,
            outcome=outcome,
            as_of=as_of,
        )

        # 4. Record update
        updated = self._review_repo.record_review(
            note_id=clean_note_id,
            user_id=clean_user_id,
            outcome=outcome,
            next_interval_days=next_interval,
            next_review_at=next_review_at.isoformat(),
            new_stage=new_stage,
        )

        return updated


class UpdateReviewSettingsUseCase:
    def __init__(self, review_repo: NoteReviewRepository, note_repo: UserNoteRepository):
        self._review_repo = review_repo
        self._note_repo = note_repo

    def execute(self, note_id: str, user_id: str, status: str) -> Optional[Dict[str, Any]]:
        if not note_id or not user_id:
            raise ValueError("note_id and user_id are required")

        clean_status = status.strip().lower()
        if clean_status not in VALID_STATUSES:
            raise ValueError(f"Invalid status: '{status}'. Allowed: {sorted(VALID_STATUSES)}")

        clean_user_id = user_id.strip()
        clean_note_id = note_id.strip()

        # Verify note ownership
        note = self._note_repo.get_note_by_id(clean_note_id, clean_user_id)
        if not note:
            return None

        return self._review_repo.update_review_settings(clean_note_id, clean_user_id, clean_status)

