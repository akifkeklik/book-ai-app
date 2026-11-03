import datetime
import uuid
from typing import Any, Dict, List, Optional


class InMemoryLearningOutcomesRepository:
    """
    In-memory, user-isolated implementation of LearningOutcomesRepository
    for active-recall review items, attempts, and learning outcomes intelligence.
    """

    def __init__(
        self,
        initial_items: Optional[List[Dict[str, Any]]] = None,
        initial_attempts: Optional[List[Dict[str, Any]]] = None,
    ):
        self._items: List[Dict[str, Any]] = list(initial_items) if initial_items else []
        self._attempts: List[Dict[str, Any]] = list(initial_attempts) if initial_attempts else []

    def create_review_item(
        self,
        user_id: str,
        title: str,
        concept: str,
        question: str,
        answer: str,
        explanation: str = "",
        source_type: str = "user_created",
        source_id: Optional[str] = None,
        book_id: Optional[str] = None,
        path_id: Optional[str] = None,
        initial_stage: int = 1,
        initial_interval_days: int = 1,
        next_review_at: Optional[str] = None,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        now = datetime.datetime.now(datetime.timezone.utc)
        if not next_review_at:
            next_review_at = (now + datetime.timedelta(days=initial_interval_days)).isoformat()

        item = {
            "id": str(uuid.uuid4()),
            "user_id": str(user_id),
            "title": str(title).strip(),
            "concept": str(concept).strip(),
            "question": str(question).strip(),
            "answer": str(answer).strip(),
            "explanation": str(explanation or "").strip(),
            "source_type": str(source_type),
            "source_id": str(source_id) if source_id else None,
            "book_id": str(book_id) if book_id else None,
            "path_id": str(path_id) if path_id else None,
            "stage": max(1, min(int(initial_stage), 5)),
            "interval_days": max(1, int(initial_interval_days)),
            "next_review_at": next_review_at,
            "last_reviewed_at": None,
            "total_reviews": 0,
            "successful_reviews": 0,
            "status": "active",
            "metadata": dict(metadata or {}),
            "created_at": now.isoformat(),
            "updated_at": now.isoformat(),
        }
        self._items.append(item)
        return dict(item)

    def get_review_item_by_id(
        self, item_id: str, user_id: str
    ) -> Optional[Dict[str, Any]]:
        clean_item_id = str(item_id).strip()
        clean_user_id = str(user_id).strip()
        for item in self._items:
            if item.get("id") == clean_item_id and item.get("user_id") == clean_user_id:
                return dict(item)
        return None

    def update_review_item(
        self, item_id: str, user_id: str, updates: Dict[str, Any]
    ) -> Optional[Dict[str, Any]]:
        clean_item_id = str(item_id).strip()
        clean_user_id = str(user_id).strip()
        now = datetime.datetime.now(datetime.timezone.utc).isoformat()

        allowed_fields = {
            "title",
            "concept",
            "question",
            "answer",
            "explanation",
            "status",
            "stage",
            "interval_days",
            "next_review_at",
            "last_reviewed_at",
            "total_reviews",
            "successful_reviews",
            "metadata",
            "book_id",
            "path_id",
        }

        for item in self._items:
            if item.get("id") == clean_item_id and item.get("user_id") == clean_user_id:
                for k, v in updates.items():
                    if k in allowed_fields:
                        item[k] = v
                item["updated_at"] = now
                return dict(item)
        return None

    def delete_review_item(self, item_id: str, user_id: str) -> bool:
        clean_item_id = str(item_id).strip()
        clean_user_id = str(user_id).strip()

        before_count = len(self._items)
        self._items = [
            i for i in self._items
            if not (i.get("id") == clean_item_id and i.get("user_id") == clean_user_id)
        ]
        if len(self._items) < before_count:
            # Cascade delete attempts for this item
            self._attempts = [
                a for a in self._attempts
                if not (a.get("item_id") == clean_item_id and a.get("user_id") == clean_user_id)
            ]
            return True
        return False

    def list_review_items(
        self,
        user_id: str,
        concept: Optional[str] = None,
        path_id: Optional[str] = None,
        status: Optional[str] = "active",
        limit: int = 100,
        offset: int = 0,
    ) -> List[Dict[str, Any]]:
        clean_user_id = str(user_id).strip()
        filtered = [i for i in self._items if i.get("user_id") == clean_user_id]

        if status:
            filtered = [i for i in filtered if i.get("status") == status]
        if concept:
            clean_concept = str(concept).strip().lower()
            filtered = [i for i in filtered if i.get("concept", "").strip().lower() == clean_concept]
        if path_id:
            clean_path = str(path_id).strip()
            filtered = [i for i in filtered if i.get("path_id") == clean_path]

        # Order by next_review_at ascending (due earliest first)
        filtered.sort(key=lambda x: (x.get("next_review_at") or "", x.get("created_at") or ""))
        return [dict(i) for i in filtered[offset : offset + limit]]

    def get_due_review_items(
        self,
        user_id: str,
        as_of: Optional[datetime.datetime] = None,
        limit: int = 50,
    ) -> List[Dict[str, Any]]:
        target_time = as_of or datetime.datetime.now(datetime.timezone.utc)
        target_iso = target_time.isoformat()
        clean_user_id = str(user_id).strip()

        due = [
            i for i in self._items
            if i.get("user_id") == clean_user_id
            and i.get("status") == "active"
            and (i.get("next_review_at") or "") <= target_iso
        ]
        # Sort by earliest due date
        due.sort(key=lambda x: x.get("next_review_at") or "")
        return [dict(i) for i in due[:limit]]

    def record_review_attempt(
        self,
        user_id: str,
        item_id: str,
        outcome: str,
        is_correct: bool,
        stage_before: int,
        stage_after: int,
        response_text: str = "",
        reviewed_at: Optional[str] = None,
    ) -> Dict[str, Any]:
        now = datetime.datetime.now(datetime.timezone.utc)
        review_time = reviewed_at or now.isoformat()

        attempt = {
            "id": str(uuid.uuid4()),
            "user_id": str(user_id).strip(),
            "item_id": str(item_id).strip(),
            "outcome": str(outcome).strip().lower(),
            "response_text": str(response_text or "").strip(),
            "is_correct": bool(is_correct),
            "stage_before": int(stage_before),
            "stage_after": int(stage_after),
            "reviewed_at": review_time,
            "created_at": now.isoformat(),
        }
        self._attempts.append(attempt)
        return dict(attempt)

    def get_review_attempts(
        self,
        user_id: str,
        item_id: Optional[str] = None,
        limit: int = 50,
        offset: int = 0,
    ) -> List[Dict[str, Any]]:
        clean_user_id = str(user_id).strip()
        user_attempts = [a for a in self._attempts if a.get("user_id") == clean_user_id]

        if item_id:
            clean_item_id = str(item_id).strip()
            user_attempts = [a for a in user_attempts if a.get("item_id") == clean_item_id]

        # Order by reviewed_at DESC
        user_attempts.sort(key=lambda x: x.get("reviewed_at") or "", reverse=True)
        return [dict(a) for a in user_attempts[offset : offset + limit]]

    def get_concept_stats(self, user_id: str) -> List[Dict[str, Any]]:
        clean_user_id = str(user_id).strip()
        user_items = [i for i in self._items if i.get("user_id") == clean_user_id]
        user_attempts = [a for a in self._attempts if a.get("user_id") == clean_user_id]

        # Map item_id to concept
        item_concept_map = {i.get("id"): i.get("concept", "General") for i in user_items}

        concept_aggregates: Dict[str, Dict[str, Any]] = {}

        for item in user_items:
            concept = item.get("concept", "General")
            if concept not in concept_aggregates:
                concept_aggregates[concept] = {
                    "concept": concept,
                    "total_items": 0,
                    "total_attempts": 0,
                    "successful_recalls": 0,
                    "struggled_recalls": 0,
                    "stages_sum": 0,
                    "due_items": 0,
                }
            agg = concept_aggregates[concept]
            agg["total_items"] += 1
            agg["stages_sum"] += item.get("stage", 1)

        now_iso = datetime.datetime.now(datetime.timezone.utc).isoformat()
        for item in user_items:
            if item.get("status") == "active" and (item.get("next_review_at") or "") <= now_iso:
                concept = item.get("concept", "General")
                if concept in concept_aggregates:
                    concept_aggregates[concept]["due_items"] += 1

        for attempt in user_attempts:
            c = item_concept_map.get(attempt.get("item_id"))
            if c and c in concept_aggregates:
                agg = concept_aggregates[c]
                agg["total_attempts"] += 1
                if attempt.get("outcome") == "remembered":
                    agg["successful_recalls"] += 1
                else:
                    agg["struggled_recalls"] += 1

        results = []
        for c, agg in concept_aggregates.items():
            tot = agg["total_attempts"]
            struggled = agg["struggled_recalls"]
            items_count = agg["total_items"]
            avg_stage = round(agg["stages_sum"] / max(1, items_count), 2)
            retention_rate = round(agg["successful_recalls"] / max(1, tot), 2) if tot > 0 else 0.0

            # Needs review if >= 2 struggles and >= 40% struggle rate
            needs_review = (struggled >= 2 and (struggled / max(1, tot)) >= 0.4)

            results.append({
                "concept": c,
                "total_items": items_count,
                "total_attempts": tot,
                "successful_recalls": agg["successful_recalls"],
                "struggled_recalls": struggled,
                "retention_rate": retention_rate,
                "average_stage": avg_stage,
                "due_items": agg["due_items"],
                "needs_review": needs_review,
            })

        results.sort(key=lambda x: (not x["needs_review"], -x["struggled_recalls"], x["concept"]))
        return results

    def get_user_progress_summary(
        self, user_id: str, as_of: Optional[datetime.datetime] = None
    ) -> Dict[str, Any]:
        target_time = as_of or datetime.datetime.now(datetime.timezone.utc)
        target_iso = target_time.isoformat()
        clean_user_id = str(user_id).strip()

        user_items = [i for i in self._items if i.get("user_id") == clean_user_id]
        active_items = [i for i in user_items if i.get("status") == "active"]
        user_attempts = [a for a in self._attempts if a.get("user_id") == clean_user_id]

        total_items = len(user_items)
        due_count = sum(1 for i in active_items if (i.get("next_review_at") or "") <= target_iso)
        total_attempts = len(user_attempts)
        successful = sum(1 for a in user_attempts if a.get("outcome") == "remembered")
        struggled = sum(1 for a in user_attempts if a.get("outcome") == "struggled")

        return {
            "total_items": total_items,
            "active_items": len(active_items),
            "reviews_due": due_count,
            "reviews_completed": total_attempts,
            "successful_recalls": successful,
            "struggled_recalls": struggled,
        }

