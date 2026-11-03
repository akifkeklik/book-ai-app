import datetime

import pytest
from backend.app import create_app
from backend.application.use_cases.spaced_repetition import calculate_next_schedule
from backend.container import Container
from backend.infrastructure.persistence.in_memory_note_repository import (
    InMemoryNoteRepository,
    InMemoryNoteReviewRepository,
)
from backend.routes.routes import rebind_container


class DummyUser:
    def __init__(self, uid):
        self.id = uid


class DummyAuthPort:
    def __init__(self, users_by_token=None):
        self.users_by_token = users_by_token or {
            "valid-token-user-1": "user-1",
            "valid-token-user-2": "user-2",
        }

    def verify_token(self, token: str):
        if token in self.users_by_token:
            return DummyUser(self.users_by_token[token])
        return None


class DummyBookDataPort:
    def get_books_by_isbns(self, isbns):
        return [
            {
                "isbn13": "9780735211292",
                "title": "Atomik Alışkanlıklar",
                "authors": "James Clear",
                "thumbnail": "https://example.com/atomic.jpg",
            },
            {
                "isbn13": "9780143127741",
                "title": "İnce Memed",
                "authors": "Yaşar Kemal",
                "thumbnail": "https://example.com/memed.jpg",
            },
        ]


@pytest.fixture
def test_setup():
    note_repo = InMemoryNoteRepository()
    review_repo = InMemoryNoteReviewRepository()
    auth_port = DummyAuthPort()
    book_port = DummyBookDataPort()

    test_container = Container(
        note_repo=note_repo,
        auth_port=auth_port,
        book_data_port=book_port,
    )
    # Explicitly attach review_repo
    test_container.note_review_repo = review_repo
    from backend.application.use_cases.export_notes import ExportNotesUseCase
    from backend.application.use_cases.learning_notes import (
        CreateNoteUseCase,
        DeleteNoteUseCase,
        GetNoteByIdUseCase,
        GetNotesUseCase,
        UpdateNoteUseCase,
    )
    from backend.application.use_cases.spaced_repetition import (
        GetDueReviewsUseCase,
        GetReviewStatsUseCase,
        ProcessReviewUseCase,
        UpdateReviewSettingsUseCase,
    )

    test_container.create_note_uc = CreateNoteUseCase(note_repo, book_port, review_repo)
    test_container.delete_note_uc = DeleteNoteUseCase(note_repo, review_repo)
    test_container.get_notes_uc = GetNotesUseCase(note_repo, book_port)
    test_container.get_note_by_id_uc = GetNoteByIdUseCase(note_repo, book_port)
    test_container.update_note_uc = UpdateNoteUseCase(note_repo)
    test_container.get_due_reviews_uc = GetDueReviewsUseCase(review_repo, note_repo, book_port)
    test_container.get_review_stats_uc = GetReviewStatsUseCase(review_repo)
    test_container.process_review_uc = ProcessReviewUseCase(review_repo, note_repo)
    test_container.update_review_settings_uc = UpdateReviewSettingsUseCase(review_repo, note_repo)
    test_container.export_notes_uc = ExportNotesUseCase(note_repo, book_port)

    from backend.container import container as default_container
    rebind_container(test_container)

    app = create_app()
    app.config["TESTING"] = True
    client = app.test_client()

    try:
        yield {
            "app": app,
            "client": client,
            "note_repo": note_repo,
            "review_repo": review_repo,
            "container": test_container,
        }
    finally:
        rebind_container(default_container)


def test_calculate_next_schedule_intervals_and_transitions():
    base_time = datetime.datetime(2026, 10, 27, 12, 0, 0, tzinfo=datetime.timezone.utc)

    # 1. Stage 1 -> Remembered -> Stage 2 (3 days)
    stage, interval, next_at = calculate_next_schedule(1, "remembered", base_time)
    assert stage == 2
    assert interval == 3
    assert next_at == base_time + datetime.timedelta(days=3)

    # 2. Stage 2 -> Remembered -> Stage 3 (7 days)
    stage, interval, next_at = calculate_next_schedule(2, "remembered", base_time)
    assert stage == 3
    assert interval == 7
    assert next_at == base_time + datetime.timedelta(days=7)

    # 3. Stage 3 -> Remembered -> Stage 4 (30 days)
    stage, interval, next_at = calculate_next_schedule(3, "remembered", base_time)
    assert stage == 4
    assert interval == 30
    assert next_at == base_time + datetime.timedelta(days=30)

    # 4. Stage 4 -> Remembered -> Stays Stage 4 (30 days)
    stage, interval, next_at = calculate_next_schedule(4, "remembered", base_time)
    assert stage == 4
    assert interval == 30
    assert next_at == base_time + datetime.timedelta(days=30)

    # 5. Stage 4 -> Struggled -> Falls back to Stage 3 (7 days)
    stage, interval, next_at = calculate_next_schedule(4, "struggled", base_time)
    assert stage == 3
    assert interval == 7
    assert next_at == base_time + datetime.timedelta(days=7)

    # 6. Stage 3 -> Struggled -> Falls back to Stage 2 (3 days)
    stage, interval, next_at = calculate_next_schedule(3, "struggled", base_time)
    assert stage == 2
    assert interval == 3
    assert next_at == base_time + datetime.timedelta(days=3)

    # 7. Stage 2 -> Struggled -> Falls back to Stage 1 (1 day)
    stage, interval, next_at = calculate_next_schedule(2, "struggled", base_time)
    assert stage == 1
    assert interval == 1
    assert next_at == base_time + datetime.timedelta(days=1)

    # 8. Stage 1 -> Struggled -> Stays Stage 1 (1 day)
    stage, interval, next_at = calculate_next_schedule(1, "struggled", base_time)
    assert stage == 1
    assert interval == 1
    assert next_at == base_time + datetime.timedelta(days=1)


def test_note_creation_idempotency(test_setup):
    client = test_setup["client"]
    headers = {"Authorization": "Bearer valid-token-user-1"}

    payload = {
        "book_id": "9780735211292",
        "note_type": "key_takeaway",
        "content": "Her gün %1 daha iyi olmak, yıl sonunda 37 kat gelişim sağlar.",
        "client_id": "client-uuid-12345",
    }

    # First request
    res1 = client.post("/api/notes", json=payload, headers=headers)
    assert res1.status_code == 201
    data1 = res1.get_json()
    note_id1 = data1["note"]["id"]

    # Retry with same client_id (network retry scenario)
    res2 = client.post("/api/notes", json=payload, headers=headers)
    assert res2.status_code in (200, 201)
    data2 = res2.get_json()
    note_id2 = data2["note"]["id"]

    # Must return same note without creating duplicate
    assert note_id1 == note_id2

    # Check total notes for user is exactly 1
    notes_res = client.get("/api/notes", headers=headers)
    assert notes_res.get_json()["total"] == 1


def test_smart_review_auto_scheduling_and_review_flow(test_setup):
    client = test_setup["client"]
    review_repo = test_setup["review_repo"]
    headers = {"Authorization": "Bearer valid-token-user-1"}

    # 1. Create a key takeaway note
    create_res = client.post(
        "/api/notes",
        json={
            "book_id": "9780735211292",
            "note_type": "key_takeaway",
            "content": "Sistemler hedeflerden daha önemlidir.",
        },
        headers=headers,
    )
    assert create_res.status_code == 201
    note_id = create_res.get_json()["note"]["id"]

    # Verify review was auto-scheduled
    review = review_repo.get_review_by_note_id(note_id, "user-1")
    assert review is not None
    assert review["stage"] == 1
    assert review["interval_days"] == 1

    # Check review stats
    stats_res = client.get("/api/notes/reviews/stats", headers=headers)
    assert stats_res.status_code == 200
    stats = stats_res.get_json()["stats"]
    assert stats["total"] == 1

    # Simulate review submission: Remembered
    review_res = client.post(
        f"/api/notes/{note_id}/review",
        json={"outcome": "remembered"},
        headers=headers,
    )
    assert review_res.status_code == 200
    updated_review = review_res.get_json()["review"]
    assert updated_review["stage"] == 2
    assert updated_review["interval_days"] == 3
    assert updated_review["review_count"] == 1

    # Simulate second review: Remembered
    review_res2 = client.post(
        f"/api/notes/{note_id}/review",
        json={"outcome": "remembered"},
        headers=headers,
    )
    assert review_res2.status_code == 200
    assert review_res2.get_json()["review"]["stage"] == 3
    assert review_res2.get_json()["review"]["interval_days"] == 7

    # Simulate third review: Struggled (falls back to stage 2)
    review_res3 = client.post(
        f"/api/notes/{note_id}/review",
        json={"outcome": "struggled"},
        headers=headers,
    )
    assert review_res3.status_code == 200
    assert review_res3.get_json()["review"]["stage"] == 2
    assert review_res3.get_json()["review"]["interval_days"] == 3


def test_note_deletion_cleans_up_review_record(test_setup):
    client = test_setup["client"]
    review_repo = test_setup["review_repo"]
    headers = {"Authorization": "Bearer valid-token-user-1"}

    # Create note
    create_res = client.post(
        "/api/notes",
        json={
            "book_id": "9780143127741",
            "note_type": "question",
            "content": "Toroslar'da adalet kavramı nasıl işleniyor?",
        },
        headers=headers,
    )
    note_id = create_res.get_json()["note"]["id"]
    assert review_repo.get_review_by_note_id(note_id, "user-1") is not None

    # Delete note
    del_res = client.delete(f"/api/notes/{note_id}", headers=headers)
    assert del_res.status_code == 200

    # Review record must be cleaned up (no orphan)
    assert review_repo.get_review_by_note_id(note_id, "user-1") is None


def test_user_isolation_for_reviews_and_settings(test_setup):
    client = test_setup["client"]
    user1_headers = {"Authorization": "Bearer valid-token-user-1"}
    user2_headers = {"Authorization": "Bearer valid-token-user-2"}

    # User 1 creates note
    create_res = client.post(
        "/api/notes",
        json={
            "book_id": "9780735211292",
            "note_type": "key_takeaway",
            "content": "Gizli not içeriği",
        },
        headers=user1_headers,
    )
    note_id = create_res.get_json()["note"]["id"]

    # User 2 tries to review User 1's note -> 404
    u2_review = client.post(
        f"/api/notes/{note_id}/review",
        json={"outcome": "remembered"},
        headers=user2_headers,
    )
    assert u2_review.status_code == 404

    # User 2 tries to update settings on User 1's note -> 404
    u2_settings = client.put(
        f"/api/notes/{note_id}/review/settings",
        json={"status": "paused"},
        headers=user2_headers,
    )
    assert u2_settings.status_code == 404

    # User 1 pauses review successfully
    u1_settings = client.put(
        f"/api/notes/{note_id}/review/settings",
        json={"status": "paused"},
        headers=user1_headers,
    )
    assert u1_settings.status_code == 200
    assert u1_settings.get_json()["review"]["status"] == "paused"


def test_notes_export_markdown_and_turkish_characters(test_setup):
    client = test_setup["client"]
    user1_headers = {"Authorization": "Bearer valid-token-user-1"}
    user2_headers = {"Authorization": "Bearer valid-token-user-2"}

    # Create notes with Turkish characters: ç, ğ, ı, ö, ş, ü, İ
    client.post(
        "/api/notes",
        json={
            "book_id": "9780143127741",
            "note_type": "key_takeaway",
            "content": "Çukurova'nın sıcağında özgürlük ve kardeşlik mücadelesi.",
        },
        headers=user1_headers,
    )
    client.post(
        "/api/notes",
        json={
            "book_id": "9780735211292",
            "note_type": "personal_note",
            "content": "Alışkanlıkları değiştirmek için ipuçlarını düzenle.",
        },
        headers=user1_headers,
    )

    # 1. User 1 exports all notes
    export_res = client.get("/api/notes/export", headers=user1_headers)
    assert export_res.status_code == 200
    assert "attachment;" in export_res.headers.get("Content-Disposition", "")
    assert "text/markdown" in export_res.headers.get("Content-Type", "")

    md_text = export_res.get_data(as_text=True)
    assert "Atomik Alışkanlıklar" in md_text
    assert "İnce Memed" in md_text
    assert "Çukurova'nın sıcağında özgürlük ve kardeşlik mücadelesi." in md_text
    assert "Alışkanlıkları değiştirmek için ipuçlarını düzenle." in md_text
    assert "Total Notes:** 2" in md_text

    # 2. Filter export by single book
    single_res = client.get("/api/notes/export?book_id=9780143127741", headers=user1_headers)
    assert single_res.status_code == 200
    single_md = single_res.get_data(as_text=True)
    assert "İnce Memed" in single_md
    assert "Atomik Alışkanlıklar" not in single_md

    # 3. User 2 exports -> sees 0 notes (no leakage)
    u2_export = client.get("/api/notes/export", headers=user2_headers)
    assert u2_export.status_code == 200
    u2_md = u2_export.get_data(as_text=True)
    assert "Total Notes:** 0" in u2_md
    assert "Çukurova" not in u2_md
