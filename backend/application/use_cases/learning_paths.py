from typing import Any, Dict, List, Optional

from backend.domain.ports import (
    BookDataPort,
    CatalogPort,
    LearningPathRepository,
    NoteReviewRepository,
    UserInteractionRepository,
    UserNoteRepository,
)


class CreateLearningPathUseCase:
    def __init__(self, path_repo: LearningPathRepository, book_data_port: Optional[BookDataPort] = None):
        self._path_repo = path_repo
        self._book_data_port = book_data_port

    def execute(
        self,
        user_id: str,
        title: str,
        description: Optional[str] = None,
        category: Optional[str] = None,
        book_ids: Optional[List[str]] = None,
    ) -> Dict[str, Any]:
        if not user_id or not str(user_id).strip():
            raise ValueError("user_id is required")

        clean_title = str(title or "").strip()
        if not clean_title:
            raise ValueError("title cannot be empty")
        if len(clean_title) > 150:
            raise ValueError("title cannot exceed 150 characters")

        clean_desc = str(description or "").strip()
        if len(clean_desc) > 1000:
            raise ValueError("description cannot exceed 1000 characters")

        clean_cat = str(category or "").strip()
        if len(clean_cat) > 100:
            raise ValueError("category cannot exceed 100 characters")

        sanitized_books = []
        if book_ids:
            seen = set()
            for b in book_ids:
                b_clean = str(b).strip()
                if b_clean and b_clean not in seen:
                    seen.add(b_clean)
                    sanitized_books.append(b_clean)

        return self._path_repo.create_path(
            user_id=str(user_id),
            title=clean_title,
            description=clean_desc,
            category=clean_cat,
            book_ids=sanitized_books,
        )


class GetUserLearningPathsUseCase:
    def __init__(
        self,
        path_repo: LearningPathRepository,
        interaction_repo: Optional[UserInteractionRepository] = None,
        note_repo: Optional[UserNoteRepository] = None,
        review_repo: Optional[NoteReviewRepository] = None,
    ):
        self._path_repo = path_repo
        self._interaction_repo = interaction_repo
        self._note_repo = note_repo
        self._review_repo = review_repo

    def execute(self, user_id: str, status: Optional[str] = None) -> List[Dict[str, Any]]:
        if not user_id:
            return []

        paths = self._path_repo.get_user_paths(user_id=str(user_id), status=status)
        if not paths:
            return []

        # Load user interactions map: book_id -> interaction_type
        interactions_map: Dict[str, str] = {}
        if self._interaction_repo:
            try:
                interactions = self._interaction_repo.get_user_interactions(user_id=str(user_id))
                for inter in interactions:
                    bid = str(inter.get("book_id") or "")
                    itype = str(inter.get("interaction_type") or "")
                    if bid and itype:
                        interactions_map[bid] = itype
            except Exception:
                pass

        enriched = []
        for p in paths:
            books = p.get("books", [])
            total_books = len(books)
            completed_books = 0
            reading_books = 0
            next_book_id = None

            for b in books:
                bid = str(b.get("book_id") or "")
                istatus = interactions_map.get(bid)
                b["reading_status"] = istatus

                if istatus == "finished":
                    completed_books += 1
                elif istatus == "reading":
                    reading_books += 1

                if next_book_id is None and istatus != "finished":
                    next_book_id = bid

            not_started_books = max(0, total_books - completed_books - reading_books)
            progress_percent = (
                int((completed_books / total_books) * 100) if total_books > 0 else 0
            )

            p_copy = dict(p)
            p_copy["total_books"] = total_books
            p_copy["completed_books"] = completed_books
            p_copy["reading_books"] = reading_books
            p_copy["not_started_books"] = not_started_books
            p_copy["progress_percent"] = progress_percent
            p_copy["next_book_id"] = next_book_id
            enriched.append(p_copy)

        return enriched


class GetLearningPathDetailUseCase:
    def __init__(
        self,
        path_repo: LearningPathRepository,
        book_data_port: Optional[BookDataPort] = None,
        interaction_repo: Optional[UserInteractionRepository] = None,
        note_repo: Optional[UserNoteRepository] = None,
        review_repo: Optional[NoteReviewRepository] = None,
    ):
        self._path_repo = path_repo
        self._book_data_port = book_data_port
        self._interaction_repo = interaction_repo
        self._note_repo = note_repo
        self._review_repo = review_repo

    def execute(self, path_id: str, user_id: str) -> Optional[Dict[str, Any]]:
        if not path_id or not user_id:
            return None

        path = self._path_repo.get_path_by_id(path_id=str(path_id), user_id=str(user_id))
        if not path:
            return None

        books = path.get("books", [])
        book_ids = [str(b.get("book_id")) for b in books if b.get("book_id")]

        # 1. Fetch catalog metadata
        catalog_map: Dict[str, Dict[str, Any]] = {}
        if self._book_data_port and book_ids:
            try:
                books_data = self._book_data_port.get_books_by_isbns(book_ids)
                for b_raw in books_data:
                    isbn = str(b_raw.get("isbn13") or b_raw.get("id") or "")
                    if isbn:
                        catalog_map[isbn] = b_raw
            except Exception:
                pass

        # 2. Fetch user interactions
        interactions_map: Dict[str, str] = {}
        if self._interaction_repo:
            try:
                interactions = self._interaction_repo.get_user_interactions(user_id=str(user_id))
                for inter in interactions:
                    bid = str(inter.get("book_id") or "")
                    itype = str(inter.get("interaction_type") or "")
                    if bid and itype:
                        interactions_map[bid] = itype
            except Exception:
                pass

        # 3. Fetch due smart reviews
        due_review_notes: set = set()
        if self._review_repo:
            try:
                due_reviews = self._review_repo.get_due_reviews(user_id=str(user_id))
                for r in due_reviews:
                    nid = r.get("note_id")
                    if nid:
                        due_review_notes.add(str(nid))
            except Exception:
                pass

        # 4. Enrich books
        total_books = len(books)
        completed_books = 0
        reading_books = 0
        total_notes_count = 0
        total_reviews_due = 0
        next_book_id = None

        enriched_books = []
        for b in sorted(books, key=lambda x: x.get("order_index", 0)):
            bid = str(b.get("book_id") or "")
            b_copy = dict(b)

            # Metadata
            meta = catalog_map.get(bid) or {
                "isbn13": bid,
                "title": f"Book {bid}",
                "authors": "Unknown Author",
                "categories": path.get("category", ""),
                "thumbnail": "",
            }
            b_copy["book"] = meta

            # Reading status
            istatus = interactions_map.get(bid)
            b_copy["reading_status"] = istatus

            # Notes count
            notes_count = 0
            if self._note_repo:
                try:
                    notes_count = self._note_repo.count_user_notes(user_id=str(user_id), book_id=bid)
                except Exception:
                    pass
            b_copy["notes_count"] = notes_count
            total_notes_count += notes_count

            # Due review check
            has_due_review = False
            if self._note_repo and due_review_notes:
                try:
                    book_notes = self._note_repo.get_book_notes(user_id=str(user_id), book_id=bid)
                    if any(str(n.get("id")) in due_review_notes for n in book_notes):
                        has_due_review = True
                        total_reviews_due += 1
                except Exception:
                    pass
            b_copy["has_due_review"] = has_due_review

            if istatus == "finished":
                completed_books += 1
            elif istatus == "reading":
                reading_books += 1

            if next_book_id is None and istatus != "finished":
                next_book_id = bid

            enriched_books.append(b_copy)

        not_started_books = max(0, total_books - completed_books - reading_books)
        progress_percent = int((completed_books / total_books) * 100) if total_books > 0 else 0

        res = dict(path)
        res["books"] = enriched_books
        res["total_books"] = total_books
        res["completed_books"] = completed_books
        res["reading_books"] = reading_books
        res["not_started_books"] = not_started_books
        res["progress_percent"] = progress_percent
        res["total_notes_count"] = total_notes_count
        res["total_reviews_due"] = total_reviews_due
        res["next_book_id"] = next_book_id
        return res


class UpdateLearningPathUseCase:
    def __init__(self, path_repo: LearningPathRepository):
        self._path_repo = path_repo

    def execute(
        self,
        path_id: str,
        user_id: str,
        title: Optional[str] = None,
        description: Optional[str] = None,
        category: Optional[str] = None,
        status: Optional[str] = None,
    ) -> Optional[Dict[str, Any]]:
        if not path_id or not user_id:
            return None

        if title is not None:
            clean_title = str(title).strip()
            if not clean_title:
                raise ValueError("title cannot be empty")
            if len(clean_title) > 150:
                raise ValueError("title cannot exceed 150 characters")
            title = clean_title

        if description is not None:
            clean_desc = str(description).strip()
            if len(clean_desc) > 1000:
                raise ValueError("description cannot exceed 1000 characters")
            description = clean_desc

        if category is not None:
            clean_cat = str(category).strip()
            if len(clean_cat) > 100:
                raise ValueError("category cannot exceed 100 characters")
            category = clean_cat

        if status is not None:
            clean_status = str(status).strip().lower()
            if clean_status not in ("active", "completed", "archived"):
                raise ValueError("status must be active, completed, or archived")
            status = clean_status

        return self._path_repo.update_path(
            path_id=str(path_id),
            user_id=str(user_id),
            title=title,
            description=description,
            category=category,
            status=status,
        )


class DeleteLearningPathUseCase:
    def __init__(self, path_repo: LearningPathRepository):
        self._path_repo = path_repo

    def execute(self, path_id: str, user_id: str) -> bool:
        if not path_id or not user_id:
            return False
        return self._path_repo.delete_path(path_id=str(path_id), user_id=str(user_id))


class AddBookToLearningPathUseCase:
    def __init__(self, path_repo: LearningPathRepository, book_data_port: Optional[BookDataPort] = None):
        self._path_repo = path_repo
        self._book_data_port = book_data_port

    def execute(
        self, path_id: str, user_id: str, book_id: str, order_index: Optional[int] = None
    ) -> Optional[Dict[str, Any]]:
        if not path_id or not user_id or not book_id:
            raise ValueError("path_id, user_id, and book_id are required")

        clean_bid = str(book_id).strip()
        if not clean_bid:
            raise ValueError("book_id cannot be empty")

        return self._path_repo.add_book_to_path(
            path_id=str(path_id),
            user_id=str(user_id),
            book_id=clean_bid,
            order_index=order_index,
        )


class RemoveBookFromLearningPathUseCase:
    def __init__(self, path_repo: LearningPathRepository):
        self._path_repo = path_repo

    def execute(self, path_id: str, user_id: str, book_id: str) -> Optional[Dict[str, Any]]:
        if not path_id or not user_id or not book_id:
            return None
        return self._path_repo.remove_book_from_path(
            path_id=str(path_id), user_id=str(user_id), book_id=str(book_id).strip()
        )


class ReorderLearningPathBooksUseCase:
    def __init__(self, path_repo: LearningPathRepository):
        self._path_repo = path_repo

    def execute(self, path_id: str, user_id: str, book_ids: List[str]) -> Optional[Dict[str, Any]]:
        if not path_id or not user_id:
            return None
        if not isinstance(book_ids, list):
            raise ValueError("book_ids must be a list of book ids")
        return self._path_repo.reorder_path_books(
            path_id=str(path_id), user_id=str(user_id), book_ids=[str(b).strip() for b in book_ids]
        )


class GeneratePathSuggestionsUseCase:
    """
    Adaptive Candidate Suggestion Engine for Learning Paths.
    - Utilizes user profile & interaction history.
    - Suppresses disliked books.
    - Avoids finished books unless specifically requested (exclude_completed=True by default).
    - Excludes books already present in target learning path (when path_id provided).
    - Labels current interaction status (want_to_read, reading).
    - Returns books with genuine attribution (learning_path_continuity).
    """
    def __init__(
        self,
        book_data_port: Optional[BookDataPort] = None,
        interaction_repo: Optional[UserInteractionRepository] = None,
        catalog_port: Optional[CatalogPort] = None,
        personalized_recs_uc: Optional[Any] = None,
        path_repo: Optional[LearningPathRepository] = None,
    ):
        self._book_data_port = book_data_port
        self._interaction_repo = interaction_repo
        self._catalog_port = catalog_port
        self._personalized_recs_uc = personalized_recs_uc
        self._path_repo = path_repo

    def execute(
        self,
        user_id: str,
        category: Optional[str] = None,
        query: Optional[str] = None,
        limit: int = 10,
        path_id: Optional[str] = None,
        exclude_completed: bool = True,
    ) -> List[Dict[str, Any]]:
        # If personalized recommendation engine is available and no free-text query override,
        # use the unified explainable ranking engine.
        if self._personalized_recs_uc and not (query and query.strip()):
            try:
                effective_cat = category
                if path_id and self._path_repo and not effective_cat:
                    p_obj = self._path_repo.get_path_by_id(path_id, user_id)
                    if p_obj:
                        effective_cat = p_obj.get("category")
                recs = self._personalized_recs_uc.execute(
                    user_id=user_id,
                    limit=limit,
                    category=effective_cat,
                    exclude_completed=exclude_completed,
                    path_id=path_id,
                    include_diagnostics=False,
                )
                if recs:
                    return recs
            except Exception:
                pass
        disliked_isbns = set()
        finished_isbns = set()
        interactions_map = {}

        if self._interaction_repo and user_id:
            try:
                interactions = self._interaction_repo.get_user_interactions(user_id)
                for inter in interactions:
                    bid = str(inter.get("book_id") or "")
                    itype = str(inter.get("interaction_type") or "")
                    interactions_map[bid] = itype
                    if itype in ("dislike", "dismiss"):
                        disliked_isbns.add(bid)
                    elif itype == "finished":
                        finished_isbns.add(bid)
            except Exception:
                pass

        # 1. Search books or get by category
        candidates = []
        if self._catalog_port:
            try:
                if query and query.strip():
                    results = self._catalog_port.search_books(query.strip(), limit=limit * 2)
                    candidates.extend(results)
                elif category and category.strip():
                    cat_res = self._catalog_port.get_all_books(category=category.strip(), per_page=limit * 2)
                    items = cat_res.get("books", []) if isinstance(cat_res, dict) else []
                    candidates.extend(items)
            except Exception:
                pass

        # Fallback to book_data_port raw candidates if empty
        if not candidates and self._book_data_port:
            try:
                all_raw = self._book_data_port.get_all_books_raw()
                clean_cat = (category or "").lower().strip()
                clean_q = (query or "").lower().strip()
                for b in all_raw:
                    title = str(b.get("title") or "").lower()
                    cats = str(b.get("categories") or "").lower()
                    if clean_q and clean_q in title:
                        candidates.append(b)
                    elif clean_cat and clean_cat in cats:
                        candidates.append(b)
            except Exception:
                pass

        curated = []
        seen = set()
        for b in candidates:
            bid = str(b.get("isbn13") or b.get("id") or "")
            if not bid or bid in seen:
                continue
            if bid in disliked_isbns or bid in finished_isbns:
                continue
            seen.add(bid)

            b_copy = dict(b)
            b_copy["reading_status"] = interactions_map.get(bid)
            if not b_copy.get("recommendation_reason"):
                if category:
                    b_copy["recommendation_reason"] = f"Top book in {category}"
                else:
                    b_copy["recommendation_reason"] = "Recommended for your learning path"

            curated.append(b_copy)
            if len(curated) >= limit:
                break

        return curated

