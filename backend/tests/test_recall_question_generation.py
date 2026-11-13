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
