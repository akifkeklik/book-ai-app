import pytest
from backend.app import create_app
from backend.container import Container
from backend.infrastructure.persistence.in_memory_knowledge_repository import (
    InMemoryKnowledgeRepository,
)
from backend.infrastructure.persistence.in_memory_note_repository import (
    InMemoryLearningPathRepository,
    InMemoryNoteRepository,
)
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
    def __init__(self, interactions=None):
        self._interactions = list(interactions or [])

    def get_user_interactions(self, user_id: str):
        return [i for i in self._interactions if i.get("user_id") == str(user_id)]

    def get_user_profile(self, user_id: str):
        return None

    def upsert_interactions(self, entries):
        self._interactions.extend(entries)

    def upsert_profile(self, user_id, genres, updated_at, authors=None):
        pass

    def track_activity(self, payload):
        pass

    def delete_interaction(self, user_id, book_id, interaction_type=None):
        self._interactions = [
            i for i in self._interactions
            if not (i.get("user_id") == user_id and i.get("book_id") == book_id)
        ]

    def get_user_favorites(self, user_id: str):
        return []


class DummyBookDataPort:
    def __init__(self, books=None):
        self._books = books or {}

    def get_book_by_isbn(self, isbn: str):
        return self._books.get(isbn)

    def get_all_books_raw(self):
        return list(self._books.values())

    def get_books_by_isbns(self, isbns):
        return [self._books[b] for b in isbns if b in self._books]

    def check_health(self):
        return True


@pytest.fixture
def kg_test_env():
    knowledge_repo = InMemoryKnowledgeRepository()
    note_repo = InMemoryNoteRepository()
    learning_path_repo = InMemoryLearningPathRepository()
    auth_port = DummyAuthPort({
        "token_alice": "user-alice-111",
        "token_bob": "user-bob-222",
    })
    interaction_repo = DummyInteractionRepo([
        {"user_id": "user-alice-111", "book_id": "9780141036144", "interaction_type": "favorite"},
        {"user_id": "user-alice-111", "book_id": "9780451524935", "interaction_type": "reading"},
        {"user_id": "user-bob-222", "book_id": "9780061120084", "interaction_type": "finished"},
    ])
    book_port = DummyBookDataPort({
        "9780141036144": {
            "isbn13": "9780141036144",
            "title": "1984",
            "authors": "George Orwell",
            "categories": "Fiction, Classics",
            "thumbnail": "https://example.com/1984.jpg",
        },
        "9780451524935": {
            "isbn13": "9780451524935",
            "title": "Animal Farm",
            "authors": "George Orwell",
            "categories": "Fiction",
            "thumbnail": "https://example.com/animal_farm.jpg",
        },
        "9780061120084": {
            "isbn13": "9780061120084",
            "title": "To Kill a Mockingbird",
            "authors": "Harper Lee",
            "categories": "Classics",
            "thumbnail": "https://example.com/mockingbird.jpg",
        },
    })

    test_container = Container(
        interaction_repo=interaction_repo,
        book_data_port=book_port,
        auth_port=auth_port,
        note_repo=note_repo,
        knowledge_repo=knowledge_repo,
    )
    test_container.learning_path_repo = learning_path_repo
    test_container.book_service = book_port

    # Rebind use cases
    from backend.application.use_cases.knowledge_graph import (
        CreateRelationshipUseCase,
        DeleteRelationshipUseCase,
        GetNeighborsUseCase,
        GetPersonalKnowledgeGraphUseCase,
        UpdateRelationshipUseCase,
    )

    test_container.get_knowledge_graph_uc = GetPersonalKnowledgeGraphUseCase(
        knowledge_repo=knowledge_repo,
        interaction_repo=interaction_repo,
        note_repo=note_repo,
        learning_path_repo=learning_path_repo,
        catalog_port=book_port,
    )
    test_container.create_relationship_uc = CreateRelationshipUseCase(
        knowledge_repo=knowledge_repo,
        note_repo=note_repo,
        learning_path_repo=learning_path_repo,
    )
    test_container.update_relationship_uc = UpdateRelationshipUseCase(
        knowledge_repo=knowledge_repo,
    )
    test_container.delete_relationship_uc = DeleteRelationshipUseCase(
        knowledge_repo=knowledge_repo,
    )
    test_container.get_neighbors_uc = GetNeighborsUseCase(
        get_graph_uc=test_container.get_knowledge_graph_uc,
    )

    rebind_container(test_container)

    app = create_app()
    app.config["TESTING"] = True
    app.config["ENFORCE_AUTH_IN_TESTS"] = True
    client = app.test_client()

    return {
        "client": client,
        "knowledge_repo": knowledge_repo,
        "note_repo": note_repo,
        "learning_path_repo": learning_path_repo,
        "interaction_repo": interaction_repo,
    }


def test_unauthenticated_requests_are_rejected(kg_test_env):
    client = kg_test_env["client"]
    res = client.get("/api/knowledge-graph")
    assert res.status_code == 401
    assert "error" in res.get_json()


def test_empty_knowledge_graph_for_fresh_user(kg_test_env):
    client = kg_test_env["client"]
    # User charlie has no books, notes or relationships
    res = client.get(
        "/api/knowledge-graph",
        headers={"Authorization": "Bearer token_charlie"},
    )
    # Token not recognized -> 401
    assert res.status_code == 401


def test_alice_personal_knowledge_graph_synthesis(kg_test_env):
    client = kg_test_env["client"]
    note_repo = kg_test_env["note_repo"]
    path_repo = kg_test_env["learning_path_repo"]

    # Seed note and learning path for Alice
    note_repo.create_note(
        user_id="user-alice-111",
        book_id="9780141036144",
        note_type="key_takeaway",
        content="War is peace, freedom is slavery, ignorance is strength.",
    )
    path_repo.create_path(
        user_id="user-alice-111",
        title="Dystopian Masterpieces",
        category="Fiction",
        book_ids=["9780141036144", "9780451524935"],
    )

    res = client.get(
        "/api/knowledge-graph",
        headers={"Authorization": "Bearer token_alice"},
    )
    assert res.status_code == 200
    data = res.get_json()
    assert data["status"] == "success"
    assert data["total_nodes"] > 0
    assert data["total_edges"] > 0

    node_types = {n["type"] for n in data["nodes"]}
    assert "book" in node_types
    assert "concept" in node_types
    assert "note" in node_types
    assert "learning_path" in node_types

    edge_types = {e["relationship_type"] for e in data["edges"]}
    assert "covers_concept" in edge_types
    assert "references_book" in edge_types
    assert "curates_book" in edge_types


def test_user_can_create_explicit_relationship(kg_test_env):
    client = kg_test_env["client"]
    headers = {"Authorization": "Bearer token_alice"}

    payload = {
        "source_id": "9780141036144",
        "source_type": "book",
        "target_id": "concept:totalitarianism",
        "target_type": "concept",
        "relationship_type": "covers_concept",
        "source": "user_explicit",
        "evidence_ref": "Explicit reader connection",
        "confidence": "high",
        "metadata": {"user_notes": "Key theme"},
    }

    res = client.post("/api/knowledge-graph/relationships", json=payload, headers=headers)
    assert res.status_code == 201
    body = res.get_json()
    assert body["status"] == "success"
    rel = body["relationship"]
    assert rel["source_id"] == "9780141036144"
    assert rel["target_id"] == "concept:totalitarianism"
    assert rel["relationship_type"] == "covers_concept"
    assert rel["user_id"] == "user-alice-111"


def test_duplicate_relationship_prevention(kg_test_env):
    client = kg_test_env["client"]
    headers = {"Authorization": "Bearer token_alice"}

    payload = {
        "source_id": "9780141036144",
        "source_type": "book",
        "target_id": "concept:dystopia",
        "target_type": "concept",
        "relationship_type": "relates_to",
    }

    # First call
    res1 = client.post("/api/knowledge-graph/relationships", json=payload, headers=headers)
    assert res1.status_code == 201
    rel1 = res1.get_json()["relationship"]

    # Second identical call -> Idempotent, returns existing relationship
    res2 = client.post("/api/knowledge-graph/relationships", json=payload, headers=headers)
    assert res2.status_code == 201
    rel2 = res2.get_json()["relationship"]
    assert rel1["id"] == rel2["id"]


def test_cycle_and_invalid_payload_rejection(kg_test_env):
    client = kg_test_env["client"]
    headers = {"Authorization": "Bearer token_alice"}

    # Self-referential loop (source_id == target_id)
    res = client.post("/api/knowledge-graph/relationships", json={
        "source_id": "concept:ai",
        "source_type": "concept",
        "target_id": "concept:ai",
        "target_type": "concept",
        "relationship_type": "relates_to",
    }, headers=headers)
    assert res.status_code == 400
    assert "Self-referential" in res.get_json()["error"]

    # Invalid node type
    res2 = client.post("/api/knowledge-graph/relationships", json={
        "source_id": "concept:ai",
        "source_type": "invalid_type",
        "target_id": "concept:ml",
        "target_type": "concept",
        "relationship_type": "relates_to",
    }, headers=headers)
    assert res2.status_code == 400

    # Invalid relationship type
    res3 = client.post("/api/knowledge-graph/relationships", json={
        "source_id": "concept:ai",
        "source_type": "concept",
        "target_id": "concept:ml",
        "target_type": "concept",
        "relationship_type": "not_a_valid_type",
    }, headers=headers)
    assert res3.status_code == 400


def test_cross_user_isolation(kg_test_env):
    client = kg_test_env["client"]
    headers_alice = {"Authorization": "Bearer token_alice"}
    headers_bob = {"Authorization": "Bearer token_bob"}

    # Alice creates a relationship
    res_a = client.post("/api/knowledge-graph/relationships", json={
        "source_id": "concept:alice_secret",
        "source_type": "concept",
        "target_id": "concept:alice_project",
        "target_type": "concept",
        "relationship_type": "relates_to",
    }, headers=headers_alice)
    assert res_a.status_code == 201
    rel_id = res_a.get_json()["relationship"]["id"]

    # Bob tries to fetch Alice's relationship -> 404
    res_b_get = client.get(f"/api/knowledge-graph/relationships/{rel_id}", headers=headers_bob)
    assert res_b_get.status_code == 404

    # Bob tries to delete Alice's relationship -> 404
    res_b_del = client.delete(f"/api/knowledge-graph/relationships/{rel_id}", headers=headers_bob)
    assert res_b_del.status_code == 404

    # Bob's knowledge graph does not contain Alice's secret node or edge
    res_b_graph = client.get("/api/knowledge-graph", headers=headers_bob)
    assert res_b_graph.status_code == 200
    bob_node_ids = {n["id"] for n in res_b_graph.get_json()["nodes"]}
    assert "concept:alice_secret" not in bob_node_ids


def test_cross_user_private_note_reference_rejection(kg_test_env):
    client = kg_test_env["client"]
    note_repo = kg_test_env["note_repo"]

    # Bob has a private note
    bob_note = note_repo.create_note(
        user_id="user-bob-222",
        book_id="9780061120084",
        note_type="personal_note",
        content="Bob's private thought",
    )
    bob_note_id = bob_note["id"]

    # Alice tries to link Bob's private note into her graph -> 403 Forbidden
    res = client.post("/api/knowledge-graph/relationships", json={
        "source_id": f"note:{bob_note_id}",
        "source_type": "note",
        "target_id": "concept:ethics",
        "target_type": "concept",
        "relationship_type": "reinforces_concept",
    }, headers={"Authorization": "Bearer token_alice"})

    assert res.status_code == 403
    assert "does not belong to user" in res.get_json()["error"]


def test_update_and_delete_relationship(kg_test_env):
    client = kg_test_env["client"]
    headers = {"Authorization": "Bearer token_alice"}

    res = client.post("/api/knowledge-graph/relationships", json={
        "source_id": "9780141036144",
        "source_type": "book",
        "target_id": "concept:surveillance",
        "target_type": "concept",
        "relationship_type": "covers_concept",
        "confidence": "medium",
    }, headers=headers)
    rel_id = res.get_json()["relationship"]["id"]

    # Update
    up_res = client.put(f"/api/knowledge-graph/relationships/{rel_id}", json={
        "relationship_type": "builds_upon",
        "confidence": "high",
        "metadata": {"updated_key": "val"},
    }, headers=headers)
    assert up_res.status_code == 200
    updated_rel = up_res.get_json()["relationship"]
    assert updated_rel["relationship_type"] == "builds_upon"
    assert updated_rel["confidence"] == "high"

    # Delete
    del_res = client.delete(f"/api/knowledge-graph/relationships/{rel_id}", headers=headers)
    assert del_res.status_code == 200
    assert del_res.get_json()["status"] == "success"

    # Verify gone
    get_res = client.get(f"/api/knowledge-graph/relationships/{rel_id}", headers=headers)
    assert get_res.status_code == 404


def test_neighborhood_and_depth_query(kg_test_env):
    client = kg_test_env["client"]
    headers = {"Authorization": "Bearer token_alice"}

    # Seed relationships: A -> B -> C
    client.post("/api/knowledge-graph/relationships", json={
        "source_id": "concept:node_a",
        "source_type": "concept",
        "target_id": "concept:node_b",
        "target_type": "concept",
        "relationship_type": "relates_to",
    }, headers=headers)

    client.post("/api/knowledge-graph/relationships", json={
        "source_id": "concept:node_b",
        "source_type": "concept",
        "target_id": "concept:node_c",
        "target_type": "concept",
        "relationship_type": "relates_to",
    }, headers=headers)

    # 1-hop neighborhood of node_a should have node_a and node_b, but NOT node_c
    res = client.get("/api/knowledge-graph/nodes/concept:node_a/neighbors?depth=1", headers=headers)
    assert res.status_code == 200
    data = res.get_json()
    node_ids = {n["id"] for n in data["nodes"]}
    assert "concept:node_a" in node_ids
    assert "concept:node_b" in node_ids
    assert "concept:node_c" not in node_ids

    # 2-hop neighborhood should reach node_c
    res_depth2 = client.get("/api/knowledge-graph/nodes/concept:node_a/neighbors?depth=2", headers=headers)
    assert res_depth2.status_code == 200
    data2 = res_depth2.get_json()
    node_ids2 = {n["id"] for n in data2["nodes"]}
    assert "concept:node_c" in node_ids2

