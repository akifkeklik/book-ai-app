import datetime
import uuid
from typing import Any, Dict, List, Optional


class InMemoryNoteRepository:
    """
    In-memory implementation of UserNoteRepository for isolated testing and development.
    Enforces user isolation, CRUD operations, filtering, and search.
    """

    def __init__(self, initial_notes: Optional[List[Dict[str, Any]]] = None):
        self._notes: List[Dict[str, Any]] = list(initial_notes) if initial_notes else []

    def create_note(
        self, user_id: str, book_id: str, note_type: str, content: str, client_id: Optional[str] = None
    ) -> Dict[str, Any]:
        if client_id:
            for n in self._notes:
                if n.get("user_id") == str(user_id) and n.get("client_id") == str(client_id):
                    return dict(n)
        now = datetime.datetime.now(datetime.timezone.utc).isoformat()
        note = {
            "id": str(uuid.uuid4()),
            "user_id": str(user_id),
            "book_id": str(book_id),
            "note_type": str(note_type),
            "content": str(content),
            "client_id": str(client_id) if client_id else None,
            "created_at": now,
            "updated_at": now,
        }
        self._notes.append(note)
        return dict(note)

    def get_book_notes(self, user_id: str, book_id: str) -> List[Dict[str, Any]]:
        return self.get_user_notes(user_id=user_id, book_id=book_id)

    def get_user_notes(
        self,
        user_id: str,
        note_type: Optional[str] = None,
        book_id: Optional[str] = None,
        query: Optional[str] = None,
        limit: int = 50,
        offset: int = 0,
    ) -> List[Dict[str, Any]]:
        matching = [n for n in self._notes if n.get("user_id") == str(user_id)]

        if book_id:
            matching = [n for n in matching if n.get("book_id") == str(book_id)]

        if note_type:
            matching = [n for n in matching if n.get("note_type") == str(note_type)]

        if query:
            q_lower = query.lower()
            matching = [n for n in matching if q_lower in n.get("content", "").lower()]

        # Sort descending by created_at
        matching.sort(key=lambda x: x.get("created_at", ""), reverse=True)

        sliced = matching[offset : offset + limit]
        return [dict(n) for n in sliced]

    def count_user_notes(
        self,
        user_id: str,
        note_type: Optional[str] = None,
        book_id: Optional[str] = None,
        query: Optional[str] = None,
    ) -> int:
        matching = [n for n in self._notes if n.get("user_id") == str(user_id)]

        if book_id:
            matching = [n for n in matching if n.get("book_id") == str(book_id)]

        if note_type:
            matching = [n for n in matching if n.get("note_type") == str(note_type)]

        if query:
            q_lower = query.lower()
            matching = [n for n in matching if q_lower in n.get("content", "").lower()]

        return len(matching)

    def get_note_by_id(self, note_id: str, user_id: str) -> Optional[Dict[str, Any]]:
        for n in self._notes:
            if n.get("id") == str(note_id) and n.get("user_id") == str(user_id):
                return dict(n)
        return None

    def update_note(
        self, note_id: str, user_id: str, content: str, note_type: Optional[str] = None
    ) -> Optional[Dict[str, Any]]:
        for n in self._notes:
            if n.get("id") == str(note_id) and n.get("user_id") == str(user_id):
                n["content"] = str(content)
                if note_type:
                    n["note_type"] = str(note_type)
                n["updated_at"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
                return dict(n)
        return None

    def delete_note(self, note_id: str, user_id: str) -> bool:
        before_len = len(self._notes)
        self._notes = [
            n for n in self._notes
            if not (n.get("id") == str(note_id) and n.get("user_id") == str(user_id))
        ]
        return len(self._notes) < before_len


class InMemoryNoteReviewRepository:
    """
    In-memory implementation of NoteReviewRepository for spaced repetition review schedules.
    """

    def __init__(self, initial_reviews: Optional[List[Dict[str, Any]]] = None):
        self._reviews: List[Dict[str, Any]] = list(initial_reviews) if initial_reviews else []

    def schedule_initial_review(
        self, note_id: str, user_id: str, initial_interval_days: int = 1
    ) -> Dict[str, Any]:
        for r in self._reviews:
            if r.get("note_id") == str(note_id) and r.get("user_id") == str(user_id):
                return dict(r)

        now = datetime.datetime.now(datetime.timezone.utc)
        next_review = now + datetime.timedelta(days=initial_interval_days)
        review = {
            "id": str(uuid.uuid4()),
            "note_id": str(note_id),
            "user_id": str(user_id),
            "stage": 1,
            "interval_days": initial_interval_days,
            "next_review_at": next_review.isoformat(),
            "last_reviewed_at": None,
            "review_count": 0,
            "status": "active",
            "created_at": now.isoformat(),
            "updated_at": now.isoformat(),
        }
        self._reviews.append(review)
        return dict(review)

    def get_due_reviews(
        self, user_id: str, as_of: Optional[datetime.datetime] = None, limit: int = 50
    ) -> List[Dict[str, Any]]:
        target_time = as_of or datetime.datetime.now(datetime.timezone.utc)
        target_iso = target_time.isoformat()

        matching = [
            r for r in self._reviews
            if r.get("user_id") == str(user_id)
            and r.get("status") == "active"
            and r.get("next_review_at", "") <= target_iso
        ]
        matching.sort(key=lambda x: x.get("next_review_at", ""))
        return [dict(r) for r in matching[:limit]]

    def get_review_by_note_id(self, note_id: str, user_id: str) -> Optional[Dict[str, Any]]:
        for r in self._reviews:
            if r.get("note_id") == str(note_id) and r.get("user_id") == str(user_id):
                return dict(r)
        return None

    def record_review(
        self,
        note_id: str,
        user_id: str,
        outcome: str,
        next_interval_days: int,
        next_review_at: str,
        new_stage: int,
    ) -> Optional[Dict[str, Any]]:
        for r in self._reviews:
            if r.get("note_id") == str(note_id) and r.get("user_id") == str(user_id):
                r["stage"] = new_stage
                r["interval_days"] = next_interval_days
                r["next_review_at"] = next_review_at
                r["last_reviewed_at"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
                r["review_count"] = r.get("review_count", 0) + 1
                r["updated_at"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
                return dict(r)
        return None

    def get_review_stats(
        self, user_id: str, as_of: Optional[datetime.datetime] = None
    ) -> Dict[str, int]:
        target_time = as_of or datetime.datetime.now(datetime.timezone.utc)
        target_iso = target_time.isoformat()

        user_reviews = [r for r in self._reviews if r.get("user_id") == str(user_id)]
        due_count = sum(
            1 for r in user_reviews
            if r.get("status") == "active" and r.get("next_review_at", "") <= target_iso
        )
        upcoming_count = sum(
            1 for r in user_reviews
            if r.get("status") == "active" and r.get("next_review_at", "") > target_iso
        )
        completed_count = sum(
            1 for r in user_reviews
            if r.get("status") == "completed" or r.get("stage", 0) >= 4
        )

        return {
            "total": len(user_reviews),
            "due": due_count,
            "upcoming": upcoming_count,
            "completed": completed_count,
        }

    def update_review_settings(
        self, note_id: str, user_id: str, status: str
    ) -> Optional[Dict[str, Any]]:
        for r in self._reviews:
            if r.get("note_id") == str(note_id) and r.get("user_id") == str(user_id):
                r["status"] = status
                r["updated_at"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
                return dict(r)
        return None

    def delete_review_by_note_id(self, note_id: str, user_id: str) -> bool:
        before_len = len(self._reviews)
        self._reviews = [
            r for r in self._reviews
            if not (r.get("note_id") == str(note_id) and r.get("user_id") == str(user_id))
        ]
        return len(self._reviews) < before_len

