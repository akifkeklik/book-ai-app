import pytest
from backend.app import create_app
from backend.container import Container
from backend.infrastructure.persistence.in_memory_note_repository import InMemoryNoteRepository
from backend.routes.routes import rebind_container


class DummyAuthPort:
    def __init__(self, users_by_token=None):
        self.users_by_token = users_by_token or {}

    def verify_token(self, token: str):
        class DummyUser:
            def __init__(self, uid):
                self.id = uid

        if token in self.users_by_token:
            return DummyUser(self.users_by_token[token])
        return None


class DummyInteractionRepo:
    def __init__(self, interactions=None, profile=None):
        self._interactions = list(interactions or [])
        self._profile = profile or {}

    def get_user_interactions(self, user_id: str):
        return [i for i in self._interactions if i.get("user_id") == user_id]

    def get_user_profile(self, user_id: str):
        return self._profile if self._profile.get("user_id") == user_id else None

    def upsert_interactions(self, entries):
        self._interactions.extend(entries)

    def upsert_profile(self, user_id, genres, updated_at, authors=None):
        self._profile = {"user_id": user_id, "preferred_genres": genres, "preferred_authors": authors or []}

    def track_activity(self, payload):
        pass

    def delete_interaction(self, user_id, book_id, interaction_type=None):
        self._interactions = [
            i for i in self._interactions
            if not (i.get("user_id") == user_id and i.get("book_id") == book_id)
        ]

    def get_user_favorites(self, user_id: str):
        return []


@pytest.fixture
def note_test_env():
    note_repo = InMemoryNoteRepository()
    auth_port = DummyAuthPort({
        "token_user_a": "user-aaa-111",
        "token_user_b": "user-bbb-222",
    })
    interaction_repo = DummyInteractionRepo()

    custom_container = Container(
        interaction_repo=interaction_repo,
        note_repo=note_repo,
        auth_port=auth_port,
    )
    from backend.container import container as default_container
    rebind_container(custom_container)

    app = create_app()
    app.config["TESTING"] = True
    client = app.test_client()

    try:
        yield {
            "client": client,
            "note_repo": note_repo,
            "auth_port": auth_port,
            "container": custom_container,
        }
    finally:
        rebind_container(default_container)


def test_unauthenticated_requests_are_rejected(note_test_env):
    client = note_test_env["client"]

    # GET /api/notes
    resp = client.get("/api/notes")
    assert resp.status_code == 401

    # POST /api/notes
    resp = client.post("/api/notes", json={"book_id": "9780141439518", "content": "Test note"})
    assert resp.status_code == 401

    # GET /api/books/<isbn>/notes
    resp = client.get("/api/books/9780141439518/notes")
    assert resp.status_code == 401


def test_note_crud_lifecycle_and_types(note_test_env):
    client = note_test_env["client"]
    headers = {"Authorization": "Bearer token_user_a"}

    # 1. Create personal note
    resp = client.post(
        "/api/notes",
        headers=headers,
        json={
            "book_id": "9780141439518",
            "note_type": "personal_note",
            "content": "A thoughtful reflection on Pride and Prejudice.",
        },
    )
    assert resp.status_code == 201
    data = resp.get_json()
    assert data["status"] == "success"
    note_a1 = data["note"]
    assert note_a1["note_type"] == "personal_note"
    assert note_a1["book_id"] == "9780141439518"
    assert note_a1["user_id"] == "user-aaa-111"

    # 2. Create key takeaway note
    resp = client.post(
        "/api/notes",
        headers=headers,
        json={
            "book_id": "9780141439518",
            "note_type": "key_takeaway",
            "content": "First impressions are frequently misleading.",
        },
    )
    assert resp.status_code == 201
    note_a2 = resp.get_json()["note"]
    assert note_a2["note_type"] == "key_takeaway"

    # 3. Create question note
    resp = client.post(
        "/api/notes",
        headers=headers,
        json={
            "book_id": "9780141439518",
            "note_type": "question",
            "content": "How did Regency entailment laws affect marriage prospects?",
        },
    )
    assert resp.status_code == 201
    note_a3 = resp.get_json()["note"]
    assert note_a3["note_type"] == "question"

    # 4. List notes for the book
    resp = client.get("/api/notes?book_id=9780141439518", headers=headers)
    assert resp.status_code == 200
    list_data = resp.get_json()
    assert list_data["total"] == 3
    assert len(list_data["notes"]) == 3

    # 5. Filter by note type
    resp = client.get("/api/notes?book_id=9780141439518&note_type=key_takeaway", headers=headers)
    assert resp.status_code == 200
    takeaways = resp.get_json()["notes"]
    assert len(takeaways) == 1
    assert takeaways[0]["content"] == "First impressions are frequently misleading."

    # 6. Retrieve single note by ID
    resp = client.get(f"/api/notes/{note_a1['id']}", headers=headers)
    assert resp.status_code == 200
    assert resp.get_json()["note"]["id"] == note_a1["id"]

    # 7. Update note
    resp = client.put(
        f"/api/notes/{note_a1['id']}",
        headers=headers,
        json={"content": "Updated reflection with new perspectives.", "note_type": "personal_note"},
    )
    assert resp.status_code == 200
    assert resp.get_json()["note"]["content"] == "Updated reflection with new perspectives."

    # 8. Delete note
    resp = client.delete(f"/api/notes/{note_a3['id']}", headers=headers)
    assert resp.status_code == 200
    assert resp.get_json()["deleted"] is True

    # 9. Verify deleted
    resp = client.get(f"/api/notes/{note_a3['id']}", headers=headers)
    assert resp.status_code == 404

    # 10. Shortcut /books/<isbn>/notes
    resp = client.get("/api/books/9780141439518/notes", headers=headers)
    assert resp.status_code == 200
    assert resp.get_json()["total"] == 2


def test_user_ownership_and_data_isolation(note_test_env):
    """
    Guarantees User B cannot access, list, edit, or delete User A's notes.
    """
    client = note_test_env["client"]
    headers_a = {"Authorization": "Bearer token_user_a"}
    headers_b = {"Authorization": "Bearer token_user_b"}

    # User A creates a note
    resp = client.post(
        "/api/notes",
        headers=headers_a,
        json={"book_id": "9780451524935", "content": "User A secret reflection."},
    )
    assert resp.status_code == 201
    note_id = resp.get_json()["note"]["id"]

    # User B lists notes: should see 0
    resp_b_list = client.get("/api/notes", headers=headers_b)
    assert resp_b_list.status_code == 200
    assert resp_b_list.get_json()["total"] == 0

    # User B tries to GET User A's note by ID -> 404 (Not Found / Access Denied)
    resp_b_get = client.get(f"/api/notes/{note_id}", headers=headers_b)
    assert resp_b_get.status_code == 404

    # User B tries to UPDATE User A's note -> 404
    resp_b_put = client.put(
        f"/api/notes/{note_id}",
        headers=headers_b,
        json={"content": "Malicious takeover attempt"},
    )
    assert resp_b_put.status_code == 404

    # User B tries to DELETE User A's note -> 404
    resp_b_del = client.delete(f"/api/notes/{note_id}", headers=headers_b)
    assert resp_b_del.status_code == 404

    # User A's note remains intact
    resp_a_verify = client.get(f"/api/notes/{note_id}", headers=headers_a)
    assert resp_a_verify.status_code == 200
    assert resp_a_verify.get_json()["note"]["content"] == "User A secret reflection."


def test_validation_rules_and_error_responses(note_test_env):
    client = note_test_env["client"]
    headers = {"Authorization": "Bearer token_user_a"}

    # Missing book_id
    resp = client.post("/api/notes", headers=headers, json={"content": "No book"})
    assert resp.status_code == 400

    # Empty content
    resp = client.post("/api/notes", headers=headers, json={"book_id": "9780000000001", "content": "   "})
    assert resp.status_code == 400

    # Invalid note type
    resp = client.post(
        "/api/notes",
        headers=headers,
        json={"book_id": "9780000000001", "content": "Good book", "note_type": "invalid_type"},
    )
    assert resp.status_code == 400

    # Content exceeding 5000 characters
    long_content = "A" * 5001
    resp = client.post(
        "/api/notes",
        headers=headers,
        json={"book_id": "9780000000001", "content": long_content},
    )
    assert resp.status_code == 400


def test_search_and_pagination(note_test_env):
    client = note_test_env["client"]
    headers = {"Authorization": "Bearer token_user_a"}

    # Create 5 notes with distinct keywords
    client.post("/api/notes", headers=headers, json={"book_id": "book1", "content": "Quantum mechanics basics"})
    client.post("/api/notes", headers=headers, json={"book_id": "book1", "content": "Entanglement and superposition"})
    client.post("/api/notes", headers=headers, json={"book_id": "book2", "content": "Quantum computing algorithms"})
    client.post("/api/notes", headers=headers, json={"book_id": "book3", "content": "Classical thermodynamics"})
    client.post("/api/notes", headers=headers, json={"book_id": "book3", "content": "Entropy in closed systems"})

    # Keyword search for 'quantum'
    resp = client.get("/api/notes?q=quantum", headers=headers)
    assert resp.status_code == 200
    results = resp.get_json()
    assert results["total"] == 2
    assert all("quantum" in n["content"].lower() for n in results["notes"])

    # Pagination: limit 2, offset 0
    resp_page1 = client.get("/api/notes?limit=2&offset=0", headers=headers)
    assert resp_page1.status_code == 200
    assert len(resp_page1.get_json()["notes"]) == 2

    # Pagination: limit 2, offset 2
    resp_page2 = client.get("/api/notes?limit=2&offset=2", headers=headers)
    assert resp_page2.status_code == 200
    assert len(resp_page2.get_json()["notes"]) == 2
    # Ensure distinct notes across pages
    ids_page1 = {n["id"] for n in resp_page1.get_json()["notes"]}
    ids_page2 = {n["id"] for n in resp_page2.get_json()["notes"]}
    assert ids_page1.isdisjoint(ids_page2)


def test_recommendation_integration_with_learning_notes(note_test_env):
    """
    Phase 3 verification:
    - User notes on books provide an engagement signal in recommendations.
    - Note content is NEVER leaked in recommendations.
    - Disliked books with notes remain strictly suppressed.
    """
    container = note_test_env["container"]
    note_repo = note_test_env["note_repo"]

    # User A takes key takeaways on a book
    note_repo.create_note(
        user_id="user-aaa-111",
        book_id="9780451524935",
        note_type="key_takeaway",
        content="Super private confidential note that should NEVER appear in recs",
    )

    uc = container.get_personalized_recs_uc
    recs = uc.execute(user_id="user-aaa-111", limit=5)
    assert len(recs) > 0

    # Verify no private note content leaked
    for r in recs:
        assert "confidential" not in str(r.get("explanation", "")).lower()
        assert "confidential" not in str(r.get("recommendation_reason", "")).lower()
        assert "Super private" not in str(r.get("description", ""))

    # Now verify negative signal suppression: user dislikes the book they took notes on
    interaction_repo = container.interaction_repo
    interaction_repo.upsert_interactions([
        {"user_id": "user-aaa-111", "book_id": "9780451524935", "interaction_type": "dislike"}
    ])

    recs_after_dislike = uc.execute(user_id="user-aaa-111", limit=5)
    for r in recs_after_dislike:
        assert r.get("isbn13") != "9780451524935"



def test_saving_a_takeaway_returns_its_recall_question(note_test_env):
    client = note_test_env["client"]
    headers = {"Authorization": "Bearer token_user_a"}
    resp = client.post(
        "/api/notes",
        json={"book_id": "9780141439518", "note_type": "key_takeaway", "content": "Pride blinds judgement."},
        headers=headers,
    )
    assert resp.status_code == 201
    body = resp.get_json()
    assert body["recall_item"]["question"]
    assert body["recall_item"]["next_review_at"]

    personal = client.post(
        "/api/notes",
        json={"book_id": "9780141439518", "note_type": "personal_note", "content": "Nice prose."},
        headers=headers,
    )
    assert "recall_item" not in personal.get_json()
