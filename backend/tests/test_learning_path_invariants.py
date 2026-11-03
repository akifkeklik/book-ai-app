import pytest
from backend.application.use_cases.learning_paths import (
    AddBookToLearningPathUseCase,
    CreateLearningPathUseCase,
    GeneratePathSuggestionsUseCase,
    GetLearningPathDetailUseCase,
    GetUserLearningPathsUseCase,
    RemoveBookFromLearningPathUseCase,
    ReorderLearningPathBooksUseCase,
)
from backend.infrastructure.persistence.in_memory_note_repository import (
    InMemoryLearningPathRepository,
    InMemoryNoteRepository,
    InMemoryNoteReviewRepository,
)


class MockCatalogPort:
    def __init__(self, catalog):
        self._catalog = catalog

    def get_books_by_isbns(self, isbns):
        return [self._catalog[i] for i in isbns if i in self._catalog]

    def get_all_books_raw(self):
        return list(self._catalog.values())

    def get_all_books(self, category=None, per_page=10):
        items = [
            b for b in self._catalog.values()
            if not category or category.lower() in str(b.get("categories", "")).lower()
        ]
        return {"books": items[:per_page], "total": len(items)}

    def search_books(self, query, limit=10):
        q = query.lower()
        return [
            b for b in self._catalog.values()
            if q in str(b.get("title", "")).lower() or q in str(b.get("authors", "")).lower()
        ][:limit]


class MockInteractionRepo:
    def __init__(self):
        self._interactions = []

    def get_user_interactions(self, user_id):
        return [i for i in self._interactions if i.get("user_id") == str(user_id)]

    def set_interaction(self, user_id, book_id, itype):
        self._interactions = [
            i for i in self._interactions
            if not (i.get("user_id") == str(user_id) and i.get("book_id") == str(book_id))
        ]
        if itype:
            self._interactions.append({
                "user_id": str(user_id),
                "book_id": str(book_id),
                "interaction_type": str(itype),
            })


@pytest.fixture
def invariant_env():
    catalog_data = {
        "9780000000001": {
            "isbn13": "9780000000001",
            "title": "Clean Code",
            "authors": "Robert Martin",
            "categories": "Software Engineering",
        },
        "9780000000002": {
            "isbn13": "9780000000002",
            "title": "Refactoring",
            "authors": "Martin Fowler",
            "categories": "Software Engineering",
        },
        "9780000000003": {
            "isbn13": "9780000000003",
            "title": "Design Patterns",
            "authors": "Gang of Four",
            "categories": "Software Engineering",
        },
        "9780000000004": {
            "isbn13": "9780000000004",
            "title": "Domain-Driven Design",
            "authors": "Eric Evans",
            "categories": "Software Engineering",
        },
        "9780000000005": {
            "isbn13": "9780000000005",
            "title": "Building Microservices",
            "authors": "Sam Newman",
            "categories": "Software Engineering",
        },
    }

    path_repo = InMemoryLearningPathRepository()
    note_repo = InMemoryNoteRepository()
    review_repo = InMemoryNoteReviewRepository()
    interaction_repo = MockInteractionRepo()
    catalog_port = MockCatalogPort(catalog_data)

    create_uc = CreateLearningPathUseCase(path_repo, catalog_port)
    get_list_uc = GetUserLearningPathsUseCase(path_repo, interaction_repo, note_repo, review_repo)
    get_detail_uc = GetLearningPathDetailUseCase(path_repo, catalog_port, interaction_repo, note_repo, review_repo)
    reorder_uc = ReorderLearningPathBooksUseCase(path_repo)
    add_book_uc = AddBookToLearningPathUseCase(path_repo, catalog_port)
    remove_book_uc = RemoveBookFromLearningPathUseCase(path_repo)
    suggestions_uc = GeneratePathSuggestionsUseCase(catalog_port, interaction_repo, catalog_port)

    return {
        "path_repo": path_repo,
        "note_repo": note_repo,
        "review_repo": review_repo,
        "interaction_repo": interaction_repo,
        "catalog_port": catalog_port,
        "create_uc": create_uc,
        "get_list_uc": get_list_uc,
        "get_detail_uc": get_detail_uc,
        "reorder_uc": reorder_uc,
        "add_book_uc": add_book_uc,
        "remove_book_uc": remove_book_uc,
        "suggestions_uc": suggestions_uc,
    }


def test_empty_and_one_item_paths(invariant_env):
    user_id = "user_alpha"
    create_uc = invariant_env["create_uc"]
    get_detail_uc = invariant_env["get_detail_uc"]
    add_book_uc = invariant_env["add_book_uc"]
    interaction_repo = invariant_env["interaction_repo"]

    # 1. Empty path invariants
    empty_path = create_uc.execute(user_id=user_id, title="Empty Path", book_ids=[])
    detail_empty = get_detail_uc.execute(empty_path["id"], user_id)
    assert detail_empty["total_books"] == 0
    assert detail_empty["completed_books"] == 0
    assert detail_empty["reading_books"] == 0
    assert detail_empty["not_started_books"] == 0
    assert detail_empty["progress_percent"] == 0
    assert detail_empty["next_book_id"] is None
    assert detail_empty["books"] == []

    # 2. Single item - Not Started
    add_book_uc.execute(empty_path["id"], user_id, "9780000000001")
    detail_single = get_detail_uc.execute(empty_path["id"], user_id)
    assert detail_single["total_books"] == 1
    assert detail_single["completed_books"] == 0
    assert detail_single["reading_books"] == 0
    assert detail_single["not_started_books"] == 1
    assert detail_single["progress_percent"] == 0
    assert detail_single["next_book_id"] == "9780000000001"

    # 3. Single item - Reading
    interaction_repo.set_interaction(user_id, "9780000000001", "reading")
    detail_reading = get_detail_uc.execute(empty_path["id"], user_id)
    assert detail_reading["completed_books"] == 0
    assert detail_reading["reading_books"] == 1
    assert detail_reading["not_started_books"] == 0
    assert detail_reading["progress_percent"] == 0
    assert detail_reading["next_book_id"] == "9780000000001"

    # 4. Single item - Finished
    interaction_repo.set_interaction(user_id, "9780000000001", "finished")
    detail_finished = get_detail_uc.execute(empty_path["id"], user_id)
    assert detail_finished["completed_books"] == 1
    assert detail_finished["reading_books"] == 0
    assert detail_finished["not_started_books"] == 0
    assert detail_finished["progress_percent"] == 100
    assert detail_finished["next_book_id"] is None


def test_all_finished_and_mixed_status_paths(invariant_env):
    user_id = "user_beta"
    create_uc = invariant_env["create_uc"]
    get_detail_uc = invariant_env["get_detail_uc"]
    interaction_repo = invariant_env["interaction_repo"]

    books = [
        "9780000000001",
        "9780000000002",
        "9780000000003",
        "9780000000004",
        "9780000000005",
    ]
    path = create_uc.execute(user_id=user_id, title="Architecture Track", book_ids=books)

    # All finished
    for b in books:
        interaction_repo.set_interaction(user_id, b, "finished")

    detail_all = get_detail_uc.execute(path["id"], user_id)
    assert detail_all["total_books"] == 5
    assert detail_all["completed_books"] == 5
    assert detail_all["reading_books"] == 0
    assert detail_all["not_started_books"] == 0
    assert detail_all["progress_percent"] == 100
    assert detail_all["next_book_id"] is None

    # Mixed status:
    # 0 -> finished
    # 1 -> finished
    # 2 -> reading
    # 3 -> want_to_read
    # 4 -> None (not started)
    interaction_repo.set_interaction(user_id, "9780000000003", "reading")
    interaction_repo.set_interaction(user_id, "9780000000004", "want_to_read")
    interaction_repo.set_interaction(user_id, "9780000000005", None)

    detail_mixed = get_detail_uc.execute(path["id"], user_id)
    assert detail_mixed["total_books"] == 5
    assert detail_mixed["completed_books"] == 2
    assert detail_mixed["reading_books"] == 1
    assert detail_mixed["not_started_books"] == 2
    assert detail_mixed["progress_percent"] == 40  # 2/5 * 100 = 40%
    assert detail_mixed["next_book_id"] == "9780000000003"  # Reading book is next uncompleted


def test_duplicate_and_invalid_candidates_in_creation_and_reorder(invariant_env):
    user_id = "user_gamma"
    create_uc = invariant_env["create_uc"]
    reorder_uc = invariant_env["reorder_uc"]
    add_book_uc = invariant_env["add_book_uc"]

    # Duplicates in initial creation are sanitized
    raw_candidates = ["9780000000001", "9780000000001", "  9780000000002  ", ""]
    path = create_uc.execute(user_id=user_id, title="Deduplication Path", book_ids=raw_candidates)
    assert len(path["books"]) == 2
    assert [b["book_id"] for b in path["books"]] == ["9780000000001", "9780000000002"]

    # Adding already-existing book is a safe no-op
    updated = add_book_uc.execute(path["id"], user_id, "9780000000001")
    assert len(updated["books"]) == 2

    # Reorder preserves deterministic unique indexes
    reordered = reorder_uc.execute(path["id"], user_id, ["9780000000002", "9780000000001"])
    assert reordered["books"][0]["book_id"] == "9780000000002"
    assert reordered["books"][0]["order_index"] == 0
    assert reordered["books"][1]["book_id"] == "9780000000001"
    assert reordered["books"][1]["order_index"] == 1


def test_disliked_and_completed_books_suppression(invariant_env):
    user_id = "user_delta"
    interaction_repo = invariant_env["interaction_repo"]
    suggestions_uc = invariant_env["suggestions_uc"]

    # Mark 001 as dislike, 002 as finished
    interaction_repo.set_interaction(user_id, "9780000000001", "dislike")
    interaction_repo.set_interaction(user_id, "9780000000002", "finished")
    interaction_repo.set_interaction(user_id, "9780000000003", "want_to_read")

    suggestions = suggestions_uc.execute(user_id=user_id, category="Software Engineering", limit=5)
    suggested_isbns = [s["isbn13"] for s in suggestions]

    assert "9780000000001" not in suggested_isbns, "Disliked book must never be suggested"
    assert "9780000000002" not in suggested_isbns, "Finished book must never be suggested in new suggestions"
    assert "9780000000003" in suggested_isbns, "Want-to-read book can be suggested"
    # Verify reading_status is attached
    for s in suggestions:
        if s["isbn13"] == "9780000000003":
            assert s["reading_status"] == "want_to_read"


def test_missing_history_and_notes_metadata_resilience(invariant_env):
    user_id = "user_newbie"
    create_uc = invariant_env["create_uc"]
    get_detail_uc = invariant_env["get_detail_uc"]
    suggestions_uc = invariant_env["suggestions_uc"]

    # Cold start user creates path
    path = create_uc.execute(user_id=user_id, title="Cold Start Path", book_ids=["9780000000004"])
    detail = get_detail_uc.execute(path["id"], user_id)

    assert detail["total_books"] == 1
    assert detail["progress_percent"] == 0
    assert detail["total_notes_count"] == 0
    assert detail["total_reviews_due"] == 0
    assert detail["books"][0]["notes_count"] == 0
    assert detail["books"][0]["has_due_review"] is False

    # Suggestions provide honest fallback
    suggs = suggestions_uc.execute(user_id=user_id, category="Software Engineering")
    assert len(suggs) > 0
    for s in suggs:
        assert s["recommendation_reason"] is not None
        assert "Software Engineering" in s["recommendation_reason"]


def test_multi_user_account_isolation_with_overlapping_ids(invariant_env):
    user_a = "user_aaa_test"
    user_b = "user_bbb_test"
    create_uc = invariant_env["create_uc"]
    get_detail_uc = invariant_env["get_detail_uc"]
    reorder_uc = invariant_env["reorder_uc"]
    add_book_uc = invariant_env["add_book_uc"]
    remove_book_uc = invariant_env["remove_book_uc"]

    # Both users create paths with same title and books
    path_a = create_uc.execute(user_a, "Mastery Track", book_ids=["9780000000001", "9780000000002"])
    path_b = create_uc.execute(user_b, "Mastery Track", book_ids=["9780000000001", "9780000000002"])

    # User A cannot read User B's path
    assert get_detail_uc.execute(path_b["id"], user_a) is None
    assert get_detail_uc.execute(path_a["id"], user_b) is None

    # User A cannot reorder or modify User B's path
    assert reorder_uc.execute(path_b["id"], user_a, ["9780000000002", "9780000000001"]) is None
    assert add_book_uc.execute(path_b["id"], user_a, "9780000000003") is None
    assert remove_book_uc.execute(path_b["id"], user_a, "9780000000001") is None

    # Path B remains intact
    detail_b = get_detail_uc.execute(path_b["id"], user_b)
    assert len(detail_b["books"]) == 2
    assert detail_b["books"][0]["book_id"] == "9780000000001"

