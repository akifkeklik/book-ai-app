import logging
from typing import Any, Dict, Optional

from ...domain.ports import BookDataPort, NoteReviewRepository, UserNoteRepository

logger = logging.getLogger(__name__)

VALID_NOTE_TYPES = {"personal_note", "key_takeaway", "question"}
MAX_NOTE_LENGTH = 5000


class CreateNoteUseCase:
    def __init__(
        self,
        note_repo: UserNoteRepository,
        book_data_port: Optional[BookDataPort] = None,
        review_repo: Optional[NoteReviewRepository] = None,
    ):
        self._note_repo = note_repo
        self._book_data_port = book_data_port
        self._review_repo = review_repo

    def execute(
        self,
        user_id: str,
        book_id: str,
        note_type: str,
        content: str,
        client_id: Optional[str] = None,
    ) -> Dict[str, Any]:
        if not user_id or not isinstance(user_id, str) or not user_id.strip():
            raise ValueError("user_id is required")

        if not book_id or not isinstance(book_id, str) or not book_id.strip():
            raise ValueError("book_id is required")

        clean_book_id = book_id.strip()

        clean_type = (note_type or "personal_note").strip().lower()
        if clean_type not in VALID_NOTE_TYPES:
            raise ValueError(f"Invalid note_type. Allowed: {sorted(VALID_NOTE_TYPES)}")

        if not content or not isinstance(content, str) or not content.strip():
            raise ValueError("content cannot be empty")

        clean_content = content.strip()
        if len(clean_content) > MAX_NOTE_LENGTH:
            raise ValueError(f"content exceeds maximum length of {MAX_NOTE_LENGTH} characters")

        note_data = self._note_repo.create_note(
            user_id=user_id.strip(),
            book_id=clean_book_id,
            note_type=clean_type,
            content=clean_content,
            client_id=client_id.strip() if client_id and isinstance(client_id, str) and client_id.strip() else None,
        )

        # Automatically schedule spaced repetition review for key takeaways and questions
        if self._review_repo and clean_type in {"key_takeaway", "question"}:
            try:
                note_id = str(note_data.get("id", ""))
                if note_id:
                    self._review_repo.schedule_initial_review(
                        note_id=note_id,
                        user_id=user_id.strip(),
                        initial_interval_days=1,
                    )
            except Exception as e:
                logger.warning(f"Could not auto-schedule review for note {note_data.get('id')}: {e}")

        # Optionally enrich with book summary
        if self._book_data_port and clean_book_id:
            try:
                books = self._book_data_port.get_books_by_isbns([clean_book_id])
                if books:
                    b = books[0]
                    note_data["book"] = {
                        "isbn13": b.get("isbn13") or clean_book_id,
                        "title": b.get("title") or "Unknown Title",
                        "authors": b.get("authors") or "Unknown Author",
                        "thumbnail": b.get("thumbnail") or "",
                    }
            except Exception as e:
                logger.warning(f"Could not enrich note with book data: {e}")

        return note_data


class GetNotesUseCase:
    def __init__(self, note_repo: UserNoteRepository, book_data_port: Optional[BookDataPort] = None):
        self._note_repo = note_repo
        self._book_data_port = book_data_port

    def execute(
        self,
        user_id: str,
        book_id: Optional[str] = None,
        note_type: Optional[str] = None,
        query: Optional[str] = None,
        limit: int = 50,
        offset: int = 0,
    ) -> Dict[str, Any]:
        if not user_id or not isinstance(user_id, str) or not user_id.strip():
            raise ValueError("user_id is required")

        clean_user_id = user_id.strip()
        clean_book_id = book_id.strip() if book_id and isinstance(book_id, str) else None
        clean_note_type = note_type.strip().lower() if note_type and isinstance(note_type, str) else None
        clean_query = query.strip() if query and isinstance(query, str) else None

        safe_limit = max(1, min(limit, 100))
        safe_offset = max(0, offset)

        notes = self._note_repo.get_user_notes(
            user_id=clean_user_id,
            book_id=clean_book_id,
            note_type=clean_note_type,
            query=clean_query,
            limit=safe_limit,
            offset=safe_offset,
        )

        total = self._note_repo.count_user_notes(
            user_id=clean_user_id,
            book_id=clean_book_id,
            note_type=clean_note_type,
            query=clean_query,
        )

        # Batch enrich book metadata
        if self._book_data_port and notes:
            unique_bids = list({n["book_id"] for n in notes if n.get("book_id")})
            if unique_bids:
                try:
                    books = self._book_data_port.get_books_by_isbns(unique_bids)
                    book_map = {
                        str(b.get("isbn13") or b.get("isbn") or "").strip(): b
                        for b in (books or [])
                    }
                    for n in notes:
                        bid = str(n.get("book_id", "")).strip()
                        if bid in book_map:
                            b = book_map[bid]
                            n["book"] = {
                                "isbn13": b.get("isbn13") or bid,
                                "title": b.get("title") or "Unknown Title",
                                "authors": b.get("authors") or "Unknown Author",
                                "thumbnail": b.get("thumbnail") or "",
                            }
                except Exception as e:
                    logger.warning(f"Could not batch enrich notes with book data: {e}")

        return {
            "notes": notes,
            "total": total,
            "limit": safe_limit,
            "offset": safe_offset,
        }


class GetNoteByIdUseCase:
    def __init__(self, note_repo: UserNoteRepository, book_data_port: Optional[BookDataPort] = None):
        self._note_repo = note_repo
        self._book_data_port = book_data_port

    def execute(self, note_id: str, user_id: str) -> Optional[Dict[str, Any]]:
        if not note_id or not user_id:
            return None
        note = self._note_repo.get_note_by_id(note_id.strip(), user_id.strip())
        if not note:
            return None

        if self._book_data_port and note.get("book_id"):
            try:
                books = self._book_data_port.get_books_by_isbns([note["book_id"]])
                if books:
                    b = books[0]
                    note["book"] = {
                        "isbn13": b.get("isbn13") or note["book_id"],
                        "title": b.get("title") or "Unknown Title",
                        "authors": b.get("authors") or "Unknown Author",
                        "thumbnail": b.get("thumbnail") or "",
                    }
            except Exception as e:
                logger.warning(f"Could not enrich single note with book data: {e}")

        return note


class UpdateNoteUseCase:
    def __init__(self, note_repo: UserNoteRepository):
        self._note_repo = note_repo

    def execute(
        self,
        note_id: str,
        user_id: str,
        content: str,
        note_type: Optional[str] = None,
    ) -> Optional[Dict[str, Any]]:
        if not note_id or not user_id:
            raise ValueError("note_id and user_id are required")

        if not content or not isinstance(content, str) or not content.strip():
            raise ValueError("content cannot be empty")

        clean_content = content.strip()
        if len(clean_content) > MAX_NOTE_LENGTH:
            raise ValueError(f"content exceeds maximum length of {MAX_NOTE_LENGTH} characters")

        clean_type = None
        if note_type is not None:
            clean_type = note_type.strip().lower()
            if clean_type not in VALID_NOTE_TYPES:
                raise ValueError(f"Invalid note_type. Allowed: {sorted(VALID_NOTE_TYPES)}")

        return self._note_repo.update_note(
            note_id=note_id.strip(),
            user_id=user_id.strip(),
            content=clean_content,
            note_type=clean_type,
        )


class DeleteNoteUseCase:
    def __init__(
        self,
        note_repo: UserNoteRepository,
        review_repo: Optional[NoteReviewRepository] = None,
    ):
        self._note_repo = note_repo
        self._review_repo = review_repo

    def execute(self, note_id: str, user_id: str) -> bool:
        if not note_id or not user_id:
            return False
        clean_note_id = note_id.strip()
        clean_user_id = user_id.strip()

        # Clean up any associated review record first so no orphans remain
        if self._review_repo:
            try:
                self._review_repo.delete_review_by_note_id(clean_note_id, clean_user_id)
            except Exception as e:
                logger.warning(f"Could not clean up review for deleted note {clean_note_id}: {e}")

        return self._note_repo.delete_note(note_id=clean_note_id, user_id=clean_user_id)

