import pytest
from backend.app import create_app
from backend.container import Container
from backend.container import container as default_container
from backend.infrastructure.persistence.in_memory_note_repository import (
    InMemoryLearningPathRepository,
    InMemoryNoteRepository,
    InMemoryNoteReviewRepository,
)
from backend.routes.routes import rebind_container


class DummyUser:
    def __init__(self, uid: str):
        self.id = uid


class DummyAuthPort:
    def __init__(self, valid_tokens=None):
        self._tokens = valid_tokens or {
            "token_user_a": "user-aaa-111",
            "token_user_b": "user-bbb-222",
        }

    def verify_token(self, token: str):
        uid = self._tokens.get(token)
        if uid:
            return DummyUser(uid)
        return None


class DummyInteractionRepo:
    def __init__(self):
        self._interactions = []

    def get_user_interactions(self, user_id: str):
        return [i for i in self._interactions if i.get("user_id") == user_id]

    def upsert_interactions(self, entries):
        self._interactions.extend(entries)

    def set_interaction(self, user_id: str, book_id: str, interaction_type: str):
        self._interactions = [
            i for i in self._interactions
            if not (i.get("user_id") == user_id and i.get("book_id") == book_id)
        ]
        self._interactions.append({
            "user_id": user_id,
            "book_id": book_id,
            "interaction_type": interaction_type,
        })


class DummyBookDataPort:
    def get_books_by_isbns(self, isbns):
        catalog = {
            "9780141439518": {
                "isbn13": "9780141439518",
                "title": "Pride and Prejudice",
                "authors": "Jane Austen",
                "categories": "Classic Literature",
                "thumbnail": "https://example.com/pride.jpg",
            },
            "9780451524935": {
                "isbn13": "9780451524935",
                "title": "1984",
                "authors": "George Orwell",
                "categories": "Dystopian Fiction",
                "thumbnail": "https://example.com/1984.jpg",
            },
            "9780743273565": {
                "isbn13": "9780743273565",
                "title": "The Great Gatsby",
                "authors": "F. Scott Fitzgerald",
                "categories": "Classic Literature",
                "thumbnail": "https://example.com/gatsby.jpg",
            },
        }
        return [catalog[i] for i in isbns if i in catalog]

    def get_all_books_raw(self):
        return [
            {
                "isbn13": "9780141439518",
                "title": "Pride and Prejudice",
                "authors": "Jane Austen",
                "categories": "Classic Literature",
            },
            {
                "isbn13": "9780451524935",
                "title": "1984",
                "authors": "George Orwell",
                "categories": "Dystopian Fiction",
            },
            {
                "isbn13": "9780743273565",
                "title": "The Great Gatsby",
                "authors": "F. Scott Fitzgerald",
                "categories": "Classic Literature",
            },
        ]


@pytest.fixture
def paths_test_env():
    path_repo = InMemoryLearningPathRepository()
    note_repo = InMemoryNoteRepository()
    review_repo = InMemoryNoteReviewRepository()
    auth_port = DummyAuthPort()
    interaction_repo = DummyInteractionRepo()
    book_port = DummyBookDataPort()

    from backend.application.use_cases.learning_paths import (
        AddBookToLearningPathUseCase,
        CreateLearningPathUseCase,
        DeleteLearningPathUseCase,
        GeneratePathSuggestionsUseCase,
        GetLearningPathDetailUseCase,
        GetUserLearningPathsUseCase,
        RemoveBookFromLearningPathUseCase,
        ReorderLearningPathBooksUseCase,
        UpdateLearningPathUseCase,
    )

    test_container = Container(
        interaction_repo=interaction_repo,
        note_repo=note_repo,
        auth_port=auth_port,
        book_data_port=book_port,
    )
    test_container.note_review_repo = review_repo
    test_container.learning_path_repo = path_repo

    test_container.create_learning_path_uc = CreateLearningPathUseCase(path_repo, book_port)
    test_container.get_user_learning_paths_uc = GetUserLearningPathsUseCase(
        path_repo, interaction_repo, note_repo, review_repo
    )
    test_container.get_learning_path_detail_uc = GetLearningPathDetailUseCase(
        path_repo, book_port, interaction_repo, note_repo, review_repo
    )
    test_container.update_learning_path_uc = UpdateLearningPathUseCase(path_repo)
    test_container.delete_learning_path_uc = DeleteLearningPathUseCase(path_repo)
    test_container.add_book_to_path_uc = AddBookToLearningPathUseCase(path_repo, book_port)
    test_container.remove_book_from_path_uc = RemoveBookFromLearningPathUseCase(path_repo)
    test_container.reorder_path_books_uc = ReorderLearningPathBooksUseCase(path_repo)
    test_container.generate_path_suggestions_uc = GeneratePathSuggestionsUseCase(
        book_port, interaction_repo, None
    )

    rebind_container(test_container)

    app = create_app()
    app.config["TESTING"] = True
    client = app.test_client()

    try:
        yield {
            "app": app,
            "client": client,
            "path_repo": path_repo,
            "interaction_repo": interaction_repo,
            "note_repo": note_repo,
            "review_repo": review_repo,
            "container": test_container,
        }
    finally:
        rebind_container(default_container)


def test_unauthenticated_requests_are_rejected(paths_test_env):
    client = paths_test_env["client"]

    endpoints = [
        ("GET", "/api/learning-paths"),
        ("POST", "/api/learning-paths"),
        ("GET", "/api/learning-paths/some-id"),
        ("PUT", "/api/learning-paths/some-id"),
        ("DELETE", "/api/learning-paths/some-id"),
        ("POST", "/api/learning-paths/some-id/books"),
        ("DELETE", "/api/learning-paths/some-id/books/9780141439518"),
        ("PUT", "/api/learning-paths/some-id/reorder"),
        ("GET", "/api/learning-paths/suggestions"),
    ]

    for method, path in endpoints:
        if method == "GET":
            resp = client.get(path)
        elif method == "POST":
            resp = client.post(path, json={})
        elif method == "PUT":
            resp = client.put(path, json={})
        elif method == "DELETE":
            resp = client.delete(path)
        assert resp.status_code == 401, f"{method} {path} should return 401"


def test_learning_path_crud_and_validation(paths_test_env):
    client = paths_test_env["client"]
    headers = {"Authorization": "Bearer token_user_a"}

    # 1. Validation: empty title rejected
    res_bad = client.post("/api/learning-paths", headers=headers, json={"title": "   "})
    assert res_bad.status_code == 400
    assert "title is required" in res_bad.get_json()["error"]

    # 2. Create valid path with initial books
    res_create = client.post(
        "/api/learning-paths",
        headers=headers,
        json={
            "title": "Classic Literature Mastery",
            "description": "Foundations of literary masterpieces",
            "category": "Classic Literature",
            "book_ids": ["9780141439518", "9780743273565"],
        },
    )
    assert res_create.status_code == 201
    created_data = res_create.get_json()["path"]
    path_id = created_data["id"]
    assert created_data["title"] == "Classic Literature Mastery"
    assert created_data["status"] == "active"
    assert len(created_data["books"]) == 2

    # 3. Read path detail
    res_get = client.get(f"/api/learning-paths/{path_id}", headers=headers)
    assert res_get.status_code == 200
    path_detail = res_get.get_json()["path"]
    assert path_detail["title"] == "Classic Literature Mastery"
    assert path_detail["total_books"] == 2
    assert path_detail["progress_percent"] == 0
    assert path_detail["books"][0]["book"]["title"] == "Pride and Prejudice"

    # 4. Update path
    res_update = client.put(
        f"/api/learning-paths/{path_id}",
        headers=headers,
        json={
            "title": "Updated Literature Rota",
            "status": "completed",
        },
    )
    assert res_update.status_code == 200
    updated_data = res_update.get_json()["path"]
    assert updated_data["title"] == "Updated Literature Rota"
    assert updated_data["status"] == "completed"

    # 5. Delete path
    res_del = client.delete(f"/api/learning-paths/{path_id}", headers=headers)
    assert res_del.status_code == 200
    assert res_del.get_json()["deleted"] is True

    # 6. Verify deleted
    res_not_found = client.get(f"/api/learning-paths/{path_id}", headers=headers)
    assert res_not_found.status_code == 404


def test_user_ownership_and_data_isolation(paths_test_env):
    client = paths_test_env["client"]
    headers_a = {"Authorization": "Bearer token_user_a"}
    headers_b = {"Authorization": "Bearer token_user_b"}

    # User A creates path
    res = client.post(
        "/api/learning-paths",
        headers=headers_a,
        json={"title": "User A Private Path", "book_ids": ["9780141439518"]},
    )
    assert res.status_code == 201
    path_id = res.get_json()["path"]["id"]

    # User B cannot access User A's path
    assert client.get(f"/api/learning-paths/{path_id}", headers=headers_b).status_code == 404
    assert client.put(f"/api/learning-paths/{path_id}", headers=headers_b, json={"title": "Hacked"}).status_code == 404
    assert client.delete(f"/api/learning-paths/{path_id}", headers=headers_b).status_code == 404
    assert client.post(f"/api/learning-paths/{path_id}/books", headers=headers_b, json={"book_id": "9780451524935"}).status_code == 404
    assert client.delete(f"/api/learning-paths/{path_id}/books/9780141439518", headers=headers_b).status_code == 404
    assert client.put(f"/api/learning-paths/{path_id}/reorder", headers=headers_b, json={"book_ids": []}).status_code == 404

    # User B's path list does not contain User A's path
    list_b = client.get("/api/learning-paths", headers=headers_b).get_json()["paths"]
    assert len(list_b) == 0


def test_path_books_management_and_reorder(paths_test_env):
    client = paths_test_env["client"]
    headers = {"Authorization": "Bearer token_user_a"}

    # Create path with 1 book
    res = client.post(
        "/api/learning-paths",
        headers=headers,
        json={"title": "Path 1", "book_ids": ["9780141439518"]},
    )
    path_id = res.get_json()["path"]["id"]

    # 1. Add second book
    res_add = client.post(
        f"/api/learning-paths/{path_id}/books",
        headers=headers,
        json={"book_id": "9780451524935"},
    )
    assert res_add.status_code == 200
    assert len(res_add.get_json()["path"]["books"]) == 2

    # 2. Add duplicate book (should not duplicate)
    res_dup = client.post(
        f"/api/learning-paths/{path_id}/books",
        headers=headers,
        json={"book_id": "9780141439518"},
    )
    assert res_dup.status_code == 200
    assert len(res_dup.get_json()["path"]["books"]) == 2

    # 3. Add third book
    client.post(
        f"/api/learning-paths/{path_id}/books",
        headers=headers,
        json={"book_id": "9780743273565"},
    )

    # 4. Reorder books (reverse order)
    res_reorder = client.put(
        f"/api/learning-paths/{path_id}/reorder",
        headers=headers,
        json={"book_ids": ["9780743273565", "9780451524935", "9780141439518"]},
    )
    assert res_reorder.status_code == 200
    reordered_books = res_reorder.get_json()["path"]["books"]
    assert reordered_books[0]["book_id"] == "9780743273565"
    assert reordered_books[1]["book_id"] == "9780451524935"
    assert reordered_books[2]["book_id"] == "9780141439518"

    # 5. Remove book
    res_rem = client.delete(
        f"/api/learning-paths/{path_id}/books/9780451524935",
        headers=headers,
    )
    assert res_rem.status_code == 200
    remaining_books = res_rem.get_json()["path"]["books"]
    assert len(remaining_books) == 2
    assert remaining_books[0]["book_id"] == "9780743273565"
    assert remaining_books[1]["book_id"] == "9780141439518"


def test_progress_intelligence_calculations(paths_test_env):
    client = paths_test_env["client"]
    interaction_repo = paths_test_env["interaction_repo"]
    note_repo = paths_test_env["note_repo"]
    review_repo = paths_test_env["review_repo"]
    headers = {"Authorization": "Bearer token_user_a"}
    user_id = "user-aaa-111"

    # Seed interactions:
    # 9780141439518 -> finished
    # 9780451524935 -> reading
    # 9780743273565 -> not started
    interaction_repo.set_interaction(user_id, "9780141439518", "finished")
    interaction_repo.set_interaction(user_id, "9780451524935", "reading")

    # Seed note on reading book with due review (initial_interval_days=0)
    note = note_repo.create_note(user_id, "9780451524935", "key_takeaway", "War is peace.")
    review_repo.schedule_initial_review(note["id"], user_id, initial_interval_days=0)

    # Create path with 3 books
    res = client.post(
        "/api/learning-paths",
        headers=headers,
        json={
            "title": "Mastery Path",
            "book_ids": ["9780141439518", "9780451524935", "9780743273565"],
        },
    )
    path_id = res.get_json()["path"]["id"]

    # Fetch detail
    res_detail = client.get(f"/api/learning-paths/{path_id}", headers=headers)
    assert res_detail.status_code == 200
    data = res_detail.get_json()["path"]

    assert data["total_books"] == 3
    assert data["completed_books"] == 1
    assert data["reading_books"] == 1
    assert data["not_started_books"] == 1
    assert data["progress_percent"] == 33  # 1/3 * 100 = 33%
    assert data["total_notes_count"] == 1
    assert data["total_reviews_due"] == 1
    assert data["next_book_id"] == "9780451524935"  # Reading book is next uncompleted

    # Now mark reading book as finished in interaction repo
    interaction_repo.set_interaction(user_id, "9780451524935", "finished")

    res_detail2 = client.get(f"/api/learning-paths/{path_id}", headers=headers)
    data2 = res_detail2.get_json()["path"]
    assert data2["completed_books"] == 2
    assert data2["reading_books"] == 0
    assert data2["not_started_books"] == 1
    assert data2["progress_percent"] == 66  # 2/3 * 100 = 66%
    assert data2["next_book_id"] == "9780743273565"  # Next uncompleted book

    # Verify deleting path does NOT delete library interactions or learning notes
    client.delete(f"/api/learning-paths/{path_id}", headers=headers)
    assert len(interaction_repo.get_user_interactions(user_id)) == 2
    assert len(note_repo.get_user_notes(user_id)) == 1


def test_path_suggestions_suppresses_dislikes_and_finished(paths_test_env):
    client = paths_test_env["client"]
    interaction_repo = paths_test_env["interaction_repo"]
    headers = {"Authorization": "Bearer token_user_a"}
    user_id = "user-aaa-111"

    # User dislikes 1984 (9780451524935) and finished Gatsby (9780743273565)
    interaction_repo.set_interaction(user_id, "9780451524935", "dislike")
    interaction_repo.set_interaction(user_id, "9780743273565", "finished")

    # Request suggestions for Classic Literature
    res = client.get("/api/learning-paths/suggestions?category=Classic", headers=headers)
    assert res.status_code == 200
    suggestions = res.get_json()["suggestions"]

    suggested_isbns = [s["isbn13"] for s in suggestions]
    # Disliked and finished books must be suppressed
    assert "9780451524935" not in suggested_isbns
    assert "9780743273565" not in suggested_isbns
    # Allowed candidate
    assert "9780141439518" in suggested_isbns
    assert suggestions[0]["recommendation_reason"] is not None
