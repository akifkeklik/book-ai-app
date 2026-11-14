from backend.application.use_cases.learning_outcomes import (
    MAX_RECALL_QUESTIONS_PER_REQUEST,
    GetReviewQueueUseCase,
)
from backend.infrastructure.persistence.in_memory_learning_repository import (
    InMemoryLearningOutcomesRepository,
)
from backend.infrastructure.persistence.in_memory_note_repository import InMemoryNoteRepository

USER = "user-1"
FALLBACK_PREFIX = "What is the key takeaway from"


class StubLlm:
    def __init__(self, reply=None, error=None):
        self.reply = reply
        self.error = error
        self.calls = []

    def generate_response(self, system_prompt, user_prompt):
        self.calls.append(user_prompt)
        if self.error:
            raise self.error
        return self.reply


def _queue(llm, takeaways=1, note_type="key_takeaway"):
    note_repo = InMemoryNoteRepository()
    for i in range(takeaways):
        note_repo.create_note(USER, "9780000000001", note_type, f"Habits compound over time #{i}")
    uc = GetReviewQueueUseCase(
        learning_repo=InMemoryLearningOutcomesRepository(), note_repo=note_repo, llm_port=llm
    )
    return uc.execute(USER, limit=50)


def test_takeaway_gets_ai_generated_recall_question_and_keeps_note_as_answer():
    llm = StubLlm(reply='"Why do small habits matter in the long run?"\nextra line')
    items = _queue(llm)
    assert items[0]["question"] == "Why do small habits matter in the long run?"
    assert items[0]["answer"].startswith("Habits compound")


def test_falls_back_without_llm():
    assert _queue(None)[0]["question"].startswith(FALLBACK_PREFIX)


def test_falls_back_when_llm_returns_nothing_or_non_question():
    assert _queue(StubLlm(reply=None))[0]["question"].startswith(FALLBACK_PREFIX)
    assert _queue(StubLlm(reply="Sure! Here is a summary."))[0]["question"].startswith(FALLBACK_PREFIX)


def test_falls_back_when_llm_raises():
    assert _queue(StubLlm(error=RuntimeError("provider down")))[0]["question"].startswith(FALLBACK_PREFIX)


def test_llm_calls_are_bounded_per_request():
    llm = StubLlm(reply="What compounds over time according to the note?")
    items = _queue(llm, takeaways=MAX_RECALL_QUESTIONS_PER_REQUEST + 3)
    assert len(llm.calls) == MAX_RECALL_QUESTIONS_PER_REQUEST
    assert len(items) == MAX_RECALL_QUESTIONS_PER_REQUEST + 3


def test_user_written_questions_are_not_sent_to_llm():
    llm = StubLlm(reply="Irrelevant?")
    items = _queue(llm, note_type="question")
    assert llm.calls == []
    assert items[0]["question"].startswith("Habits compound")


# ── Instant recall item on note save ─────────────────────────────────────────


def _uc(llm):
    return GetReviewQueueUseCase(
        learning_repo=InMemoryLearningOutcomesRepository(),
        note_repo=InMemoryNoteRepository(),
        llm_port=llm,
    )


def test_create_item_for_note_returns_ai_question_immediately():
    uc = _uc(StubLlm(reply="Why do small habits compound over time?"))
    note = {"id": "n1", "book_id": "9780000000001", "note_type": "key_takeaway", "content": "Habits compound."}
    item = uc.create_item_for_note(USER, note)
    assert item["question"] == "Why do small habits compound over time?"
    assert item["answer"] == "Habits compound."
    assert item["next_review_at"]


def test_create_item_for_note_is_idempotent():
    llm = StubLlm(reply="Why do small habits compound over time?")
    uc = _uc(llm)
    note = {"id": "n1", "book_id": "9780000000001", "note_type": "key_takeaway", "content": "Habits compound."}
    first = uc.create_item_for_note(USER, note)
    second = uc.create_item_for_note(USER, note)
    assert first["id"] == second["id"]
    assert len(llm.calls) == 1


def test_personal_notes_do_not_become_recall_items():
    uc = _uc(StubLlm(reply="Irrelevant?"))
    note = {"id": "n2", "book_id": "9780000000001", "note_type": "personal_note", "content": "Liked chapter 3."}
    assert uc.create_item_for_note(USER, note) is None


def test_review_queue_does_not_duplicate_an_item_created_on_save():
    llm = StubLlm(reply="Why do small habits compound over time?")
    note_repo = InMemoryNoteRepository()
    note = note_repo.create_note(USER, "9780000000001", "key_takeaway", "Habits compound.")
    uc = GetReviewQueueUseCase(
        learning_repo=InMemoryLearningOutcomesRepository(), note_repo=note_repo, llm_port=llm
    )
    uc.create_item_for_note(USER, note)
    queue = uc.execute(USER, limit=50)
    assert len([i for i in queue if i.get("source_id") == note["id"]]) == 1
