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


class InMemoryLearningPathRepository:
    """
    In-memory implementation of LearningPathRepository for testing and development.
    Enforces user isolation, path creation, ordered items, duplicate prevention, and reordering.
    """

    def __init__(self, initial_paths: Optional[List[Dict[str, Any]]] = None):
        self._paths: List[Dict[str, Any]] = list(initial_paths) if initial_paths else []

    def create_path(
        self,
        user_id: str,
        title: str,
        description: Optional[str] = None,
        category: Optional[str] = None,
        book_ids: Optional[List[str]] = None,
    ) -> Dict[str, Any]:
        now_iso = datetime.datetime.now(datetime.timezone.utc).isoformat()
        path_id = str(uuid.uuid4())

        books = []
        if book_ids:
            seen = set()
            for b_id in book_ids:
                b_str = str(b_id).strip()
                if b_str and b_str not in seen:
                    seen.add(b_str)
                    books.append({
                        "book_id": b_str,
                        "order_index": len(books),
                        "added_at": now_iso,
                    })

        record = {
            "id": path_id,
            "user_id": str(user_id),
            "title": str(title).strip(),
            "description": str(description or "").strip(),
            "category": str(category or "").strip(),
            "status": "active",
            "books": books,
            "created_at": now_iso,
            "updated_at": now_iso,
        }
        self._paths.append(record)
        return dict(record)

    def get_user_paths(
        self, user_id: str, status: Optional[str] = None
    ) -> List[Dict[str, Any]]:
        results = [p for p in self._paths if p.get("user_id") == str(user_id)]
        if status:
            results = [p for p in results if p.get("status") == status]
        return [dict(p) for p in results]

    def get_path_by_id(self, path_id: str, user_id: str) -> Optional[Dict[str, Any]]:
        for p in self._paths:
            if p.get("id") == str(path_id) and p.get("user_id") == str(user_id):
                return dict(p)
        return None

    def update_path(
        self,
        path_id: str,
        user_id: str,
        title: Optional[str] = None,
        description: Optional[str] = None,
        category: Optional[str] = None,
        status: Optional[str] = None,
    ) -> Optional[Dict[str, Any]]:
        for p in self._paths:
            if p.get("id") == str(path_id) and p.get("user_id") == str(user_id):
                if title is not None:
                    p["title"] = str(title).strip()
                if description is not None:
                    p["description"] = str(description).strip()
                if category is not None:
                    p["category"] = str(category).strip()
                if status is not None:
                    p["status"] = status
                p["updated_at"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
                return dict(p)
        return None

    def delete_path(self, path_id: str, user_id: str) -> bool:
        before = len(self._paths)
        self._paths = [
            p for p in self._paths
            if not (p.get("id") == str(path_id) and p.get("user_id") == str(user_id))
        ]
        return len(self._paths) < before

    def add_book_to_path(
        self, path_id: str, user_id: str, book_id: str, order_index: Optional[int] = None
    ) -> Optional[Dict[str, Any]]:
        for p in self._paths:
            if p.get("id") == str(path_id) and p.get("user_id") == str(user_id):
                books = p.get("books", [])
                clean_id = str(book_id).strip()
                if any(b.get("book_id") == clean_id for b in books):
                    return dict(p)
                now_iso = datetime.datetime.now(datetime.timezone.utc).isoformat()
                new_item = {
                    "book_id": clean_id,
                    "order_index": order_index if order_index is not None else len(books),
                    "added_at": now_iso,
                }
                if order_index is not None and 0 <= order_index < len(books):
                    books.insert(order_index, new_item)
                    for i, b in enumerate(books):
                        b["order_index"] = i
                else:
                    new_item["order_index"] = len(books)
                    books.append(new_item)
                p["updated_at"] = now_iso
                return dict(p)
        return None

    def remove_book_from_path(
        self, path_id: str, user_id: str, book_id: str
    ) -> Optional[Dict[str, Any]]:
        for p in self._paths:
            if p.get("id") == str(path_id) and p.get("user_id") == str(user_id):
                clean_id = str(book_id).strip()
                books = [b for b in p.get("books", []) if b.get("book_id") != clean_id]
                for i, b in enumerate(books):
                    b["order_index"] = i
                p["books"] = books
                p["updated_at"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
                return dict(p)
        return None

    def reorder_path_books(
        self, path_id: str, user_id: str, book_ids: List[str]
    ) -> Optional[Dict[str, Any]]:
        for p in self._paths:
            if p.get("id") == str(path_id) and p.get("user_id") == str(user_id):
                existing_books = {b.get("book_id"): b for b in p.get("books", [])}
                new_books = []
                now_iso = datetime.datetime.now(datetime.timezone.utc).isoformat()
                for i, bid in enumerate(book_ids):
                    clean_id = str(bid).strip()
                    if clean_id in existing_books:
                        item = existing_books.pop(clean_id)
                        item["order_index"] = i
                        new_books.append(item)
                for item in existing_books.values():
                    item["order_index"] = len(new_books)
                    new_books.append(item)
                p["books"] = new_books
                p["updated_at"] = now_iso
                return dict(p)
        return None

