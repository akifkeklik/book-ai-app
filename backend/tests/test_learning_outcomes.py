import datetime

import pytest
from backend.app import app
from backend.application.use_cases.learning_outcomes import (
    ALGORITHM_VERSION,
    calculate_learning_progress,
    calculate_review_schedule,
)
from backend.container import Container
from backend.infrastructure.persistence.in_memory_learning_repository import (
    InMemoryLearningOutcomesRepository,
)
from backend.infrastructure.persistence.in_memory_note_repository import (
    InMemoryLearningPathRepository,
    InMemoryNoteRepository,
    InMemoryNoteReviewRepository,
)
from backend.routes import routes


class DummyUser:
    def __init__(self, uid: str):
        self.id = uid


class DummyAuthPort:
    def __init__(self, users_by_token=None):
        self.users_by_token = users_by_token or {
            "alice-token": "alice-test-jwt",
            "bob-token": "bob-test-jwt",
        }

    def verify_token(self, token: str):
        if token in self.users_by_token:
            return DummyUser(self.users_by_token[token])
        return None


@pytest.fixture
def test_container():
    learning_repo = InMemoryLearningOutcomesRepository()
    note_repo = InMemoryNoteRepository()
    note_review_repo = InMemoryNoteReviewRepository()
    path_repo = InMemoryLearningPathRepository()
    auth_port = DummyAuthPort()

    c = Container(
        auth_port=auth_port,
        note_repo=note_repo,
        learning_outcomes_repo=learning_repo,
    )
    c.note_review_repo = note_review_repo
    c.learning_path_repo = path_repo
    c.get_review_queue_uc._learning_path_repo = path_repo
    c.get_review_queue_uc._note_repo = note_repo
    routes.rebind_container(c)
    return c


@pytest.fixture
def client(test_container):
    app.config["TESTING"] = True
    with app.test_client() as c:
        yield c


def test_scheduling_calculation_boundaries_and_progression():
    """Verify deterministic stage progression across stages 1 to 5."""
    now = datetime.datetime(2026, 10, 28, 12, 0, 0, tzinfo=datetime.timezone.utc)

    # Stage 1 + remembered -> Stage 2 (3 days)
    new_stage, interval, next_rev = calculate_review_schedule(1, "remembered", as_of=now)
    assert new_stage == 2
    assert interval == 3
    assert next_rev == now + datetime.timedelta(days=3)

    # Stage 2 + remembered -> Stage 3 (7 days)
    new_stage, interval, next_rev = calculate_review_schedule(2, "remembered", as_of=now)
    assert new_stage == 3
    assert interval == 7
    assert next_rev == now + datetime.timedelta(days=7)

    # Stage 3 + remembered -> Stage 4 (14 days)
    new_stage, interval, next_rev = calculate_review_schedule(3, "remembered", as_of=now)
    assert new_stage == 4
    assert interval == 14
    assert next_rev == now + datetime.timedelta(days=14)

    # Stage 4 + remembered -> Stage 5 (30 days)
    new_stage, interval, next_rev = calculate_review_schedule(4, "remembered", as_of=now)
    assert new_stage == 5
    assert interval == 30
    assert next_rev == now + datetime.timedelta(days=30)

    # Stage 5 + remembered -> Stage 5 (capped at stage 5, 30 days)
    new_stage, interval, next_rev = calculate_review_schedule(5, "remembered", as_of=now)
    assert new_stage == 5
    assert interval == 30


def test_scheduling_calculation_step_down_on_struggle():
    """Verify safe resets and step-downs when recall struggles."""
    now = datetime.datetime(2026, 10, 28, 12, 0, 0, tzinfo=datetime.timezone.utc)

    # Stage 1 + struggled -> Stage 1 (1 day)
    new_stage, interval, next_rev = calculate_review_schedule(1, "struggled", as_of=now)
    assert new_stage == 1
    assert interval == 1

    # Stage 2 + struggled -> Stage 1 (1 day)
    new_stage, interval, next_rev = calculate_review_schedule(2, "struggled", as_of=now)
    assert new_stage == 1
    assert interval == 1

    # Stage 3 + struggled -> Stage 2 (3 days)
    new_stage, interval, next_rev = calculate_review_schedule(3, "struggled", as_of=now)
    assert new_stage == 2
    assert interval == 3

    # Stage 4 + struggled -> Stage 3 (7 days)
    new_stage, interval, next_rev = calculate_review_schedule(4, "struggled", as_of=now)
    assert new_stage == 3
    assert interval == 7

    # Stage 5 + struggled -> Stage 3 (7 days)
    new_stage, interval, next_rev = calculate_review_schedule(5, "struggled", as_of=now)
    assert new_stage == 3
    assert interval == 7


def test_scheduling_rejects_invalid_outcomes():
    """Invalid outcome tokens must be rejected with ValueError."""
    with pytest.raises(ValueError, match="Invalid outcome"):
        calculate_review_schedule(1, "forgot_completely")


def test_progress_calculation_for_new_user_and_empty_states():
    """New users or users with zero attempts must report honest insufficient_data."""
    now = datetime.datetime(2026, 10, 28, 12, 0, 0, tzinfo=datetime.timezone.utc)

    # Case 1: completely new user
    progress = calculate_learning_progress(items=[], attempts=[], concept_stats=[], as_of=now)
    assert progress.total_items == 0
    assert progress.reviews_completed == 0
    assert progress.mastery_score == 0
    assert progress.mastery_level == "insufficient_data"
    assert progress.retention_rate == 0.0
    assert progress.active_streak_days == 0
    assert progress.algorithm_version == ALGORITHM_VERSION

    # Case 2: user has items but no review attempts yet
    sample_item = {
        "id": "item-1",
        "stage": 1,
        "status": "active",
        "next_review_at": now.isoformat(),
    }
    progress = calculate_learning_progress(items=[sample_item], attempts=[], concept_stats=[], as_of=now)
    assert progress.total_items == 1
    assert progress.reviews_completed == 0
    assert progress.mastery_score == 0
    assert progress.mastery_level == "insufficient_data"


def test_progress_calculation_for_struggling_and_mastered_users():
    """Test mastery formula accuracy, clamping, and level thresholds."""
    now = datetime.datetime(2026, 10, 28, 12, 0, 0, tzinfo=datetime.timezone.utc)

    items = [{"id": f"i-{k}", "stage": 1, "status": "active"} for k in range(5)]
    struggled_attempts = [
        {"id": f"a-{k}", "outcome": "struggled", "reviewed_at": (now - datetime.timedelta(days=k)).isoformat()}
        for k in range(5)
    ]
    concept_stats = [{"concept": "Algorithms", "struggled_recalls": 5, "retention_rate": 0.0, "needs_review": True}]

    progress = calculate_learning_progress(items=items, attempts=struggled_attempts, concept_stats=concept_stats, as_of=now)
    assert progress.retention_rate == 0.0
    assert progress.successful_recalls == 0
    assert progress.struggled_recalls == 5
    assert progress.mastery_score < 40
    assert progress.mastery_level == "novice"
    assert len(progress.difficult_concepts) == 1

    # Mastered user with 10 successful attempts and stage 5
    mastered_items = [{"id": f"i-{k}", "stage": 5, "status": "active"} for k in range(5)]
    success_attempts = [
        {"id": f"a-{k}", "outcome": "remembered", "reviewed_at": (now - datetime.timedelta(days=k)).isoformat()}
        for k in range(10)
    ]
    progress_mastered = calculate_learning_progress(items=mastered_items, attempts=success_attempts, concept_stats=[], as_of=now)
    assert progress_mastered.retention_rate == 1.0
    assert progress_mastered.mastery_score >= 85
    assert progress_mastered.mastery_level == "mastered"
    assert progress_mastered.active_streak_days >= 1


def test_review_queue_prioritization_and_reasons(test_container):
    """Overdue items must receive highest priority and correct explainable reason."""
    now = datetime.datetime(2026, 10, 28, 12, 0, 0, tzinfo=datetime.timezone.utc)
    user_id = "user-alice"

    # Create overdue item (due 3 days ago)
    overdue_time = (now - datetime.timedelta(days=3)).isoformat()
    test_container.learning_outcomes_repo.create_review_item(
        user_id=user_id,
        title="Distributed Consensus",
        concept="Distributed Systems",
        question="What is Raft leader election?",
        answer="A leader is elected via majority votes.",
        next_review_at=overdue_time,
    )

    # Create item due in 20 days (concept practice)
    future_time = (now + datetime.timedelta(days=20)).isoformat()
    test_container.learning_outcomes_repo.create_review_item(
        user_id=user_id,
        title="CAP Theorem",
        concept="Distributed Systems",
        question="What does CAP stand for?",
        answer="Consistency, Availability, Partition tolerance.",
        next_review_at=future_time,
    )

    queue = test_container.get_review_queue_uc.execute(user_id=user_id, as_of=now)
    assert len(queue) == 2
    # First item must be the overdue item
    assert queue[0]["title"] == "Distributed Consensus"
    assert queue[0]["priority"] >= 100
    assert queue[0]["recommendation_reason_key"] == "review_overdue"

    # Second item is voluntary practice
    assert queue[1]["title"] == "CAP Theorem"
    assert queue[1]["priority"] < queue[0]["priority"]
    assert queue[1]["recommendation_reason_key"] == "concept_practice"


def test_review_queue_path_filtering_and_continuity_reason(test_container):
    """Items filtered by path_id must return only matching items, and items connected to active path get continuity reason."""
    now = datetime.datetime(2026, 10, 28, 12, 0, 0, tzinfo=datetime.timezone.utc)
    user_id = "user-alice"
    path_a = "path-systems-101"
    path_b = "path-algorithms-201"

    # Create active path in repo
    test_container.learning_path_repo.create_path(
        user_id=user_id,
        title="Distributed Systems Path",
        book_ids=["9780134494166"],
    )

    # Item attached to path_a
    test_container.learning_outcomes_repo.create_review_item(
        user_id=user_id,
        title="Paxos Basics",
        concept="Distributed Systems",
        question="What is consensus?",
        answer="Agreement among distributed nodes.",
        path_id=path_a,
        book_id="9780134494166",
        next_review_at=(now + datetime.timedelta(days=10)).isoformat(),
    )

    # Item attached to path_b
    test_container.learning_outcomes_repo.create_review_item(
        user_id=user_id,
        title="Binary Search",
        concept="Algorithms",
        question="What is binary search complexity?",
        answer="O(log n).",
        path_id=path_b,
        next_review_at=(now + datetime.timedelta(days=10)).isoformat(),
    )

    # Filter queue by path_a
    queue_a = test_container.get_review_queue_uc.execute(user_id=user_id, path_id=path_a, as_of=now)
    assert len(queue_a) == 1
    assert queue_a[0]["title"] == "Paxos Basics"
    assert queue_a[0]["recommendation_reason_key"] == "learning_path_continuity"

    # Filter queue by path_b
    queue_b = test_container.get_review_queue_uc.execute(user_id=user_id, path_id=path_b, as_of=now)
    assert len(queue_b) == 1
    assert queue_b[0]["title"] == "Binary Search"


def test_user_isolation_and_cross_user_privacy(test_container):
    """User B must never access or modify User A's review items or attempts."""
    alice_id = "alice-uuid"
    bob_id = "bob-uuid"

    alice_item = test_container.learning_outcomes_repo.create_review_item(
        user_id=alice_id,
        title="Alice Secret Concept",
        concept="Cryptography",
        question="What is Alice's private key?",
        answer="Super secret",
    )

    # Bob lists items -> Alice's item is not returned
    bob_items = test_container.learning_outcomes_repo.list_review_items(user_id=bob_id)
    assert len(bob_items) == 0

    # Bob attempts to fetch Alice's item directly -> None
    item = test_container.learning_outcomes_repo.get_review_item_by_id(alice_item["id"], bob_id)
    assert item is None

    # Bob attempts to submit review for Alice's item -> rejected / None
    res = test_container.submit_review_attempt_uc.execute(
        user_id=bob_id,
        item_id=alice_item["id"],
        outcome="remembered",
    )
    assert res is None

    # Bob attempts to delete Alice's item -> False
    deleted = test_container.delete_review_item_uc.execute(user_id=bob_id, item_id=alice_item["id"])
    assert deleted is False

    # Alice can still access her item
    assert test_container.learning_outcomes_repo.get_review_item_by_id(alice_item["id"], alice_id) is not None


def test_full_active_recall_workflow_api(client, test_container):
    """Verify end-to-end HTTP API flow: Create item -> Get queue -> Submit attempt -> Overview."""
    auth_headers = {"Authorization": "Bearer alice-token"}

    # 1. Create a review item
    create_resp = client.post(
        "/api/learning/items",
        headers=auth_headers,
        json={
            "title": "Quantum Entanglement",
            "concept": "Quantum Physics",
            "question": "What did Einstein call entanglement?",
            "answer": "Spooky action at a distance",
            "explanation": "Einstein, Podolsky, Rosen paper in 1935.",
        },
    )
    assert create_resp.status_code == 201
    item_data = create_resp.get_json()["item"]
    item_id = item_data["id"]
    assert item_data["stage"] == 1

    # 2. Fetch Review Queue
    queue_resp = client.get("/api/learning/queue", headers=auth_headers)
    assert queue_resp.status_code == 200
    queue = queue_resp.get_json()["queue"]
    assert any(q["id"] == item_id for q in queue)

    # 3. Submit Active Recall Attempt (Outcome: remembered)
    attempt_resp = client.post(
        f"/api/learning/items/{item_id}/attempt",
        headers=auth_headers,
        json={
            "outcome": "remembered",
            "response_text": "Spooky action at a distance",
        },
    )
    assert attempt_resp.status_code == 200
    res_data = attempt_resp.get_json()
    assert res_data["new_stage"] == 2
    assert res_data["interval_days"] == 3
    assert res_data["item"]["successful_reviews"] == 1

    # 4. Fetch Learning Overview
    overview_resp = client.get("/api/learning/overview", headers=auth_headers)
    assert overview_resp.status_code == 200
    overview = overview_resp.get_json()["progress"]
    assert overview["total_items"] == 1
    assert overview["reviews_completed"] == 1
    assert overview["successful_recalls"] == 1
    assert overview["retention_rate"] == 1.0

    # 5. Fetch History
    history_resp = client.get("/api/learning/history", headers=auth_headers)
    assert history_resp.status_code == 200
    history = history_resp.get_json()["attempts"]
    assert len(history) == 1
    assert history[0]["outcome"] == "remembered"

    # 6. Fetch Concepts
    concepts_resp = client.get("/api/learning/concepts", headers=auth_headers)
    assert concepts_resp.status_code == 200
    concepts = concepts_resp.get_json()["concepts"]
    assert len(concepts) == 1
    assert concepts[0]["concept"] == "Quantum Physics"

    # 7. Delete Item
    delete_resp = client.delete(f"/api/learning/items/{item_id}", headers=auth_headers)
    assert delete_resp.status_code == 200

    # Ensure deleted
    get_del = client.get(f"/api/learning/items/{item_id}", headers=auth_headers)
    assert get_del.status_code == 404

