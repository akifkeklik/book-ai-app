import datetime
import uuid
from typing import Any, Dict, List, Optional


class InMemoryKnowledgeRepository:
    """
    In-memory implementation of KnowledgeGraphRepository for isolated testing and local development.
    Enforces user isolation, unique relationship constraints, CRUD, and pagination.
    """

    def __init__(self, initial_relationships: Optional[List[Dict[str, Any]]] = None):
        self._relationships: List[Dict[str, Any]] = list(initial_relationships) if initial_relationships else []

    def create_relationship(
        self,
        user_id: str,
        source_id: str,
        source_type: str,
        target_id: str,
        target_type: str,
        relationship_type: str,
        source: str = "user_explicit",
        evidence_ref: Optional[str] = None,
        confidence: str = "high",
        metadata: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        existing = self.find_existing_relationship(
            user_id=str(user_id),
            source_id=str(source_id),
            target_id=str(target_id),
            relationship_type=str(relationship_type),
        )
        if existing:
            return dict(existing)

        now = datetime.datetime.now(datetime.timezone.utc).isoformat()
        item = {
            "id": str(uuid.uuid4()),
            "user_id": str(user_id),
            "source_id": str(source_id),
            "source_type": str(source_type),
            "target_id": str(target_id),
            "target_type": str(target_type),
            "relationship_type": str(relationship_type),
            "source": str(source),
            "evidence_ref": str(evidence_ref) if evidence_ref else None,
            "confidence": str(confidence),
            "metadata": dict(metadata or {}),
            "created_at": now,
            "updated_at": now,
        }
        self._relationships.append(item)
        return dict(item)

    def get_user_relationships(
        self,
        user_id: str,
        entity_id: Optional[str] = None,
        relationship_type: Optional[str] = None,
        limit: int = 100,
        offset: int = 0,
    ) -> List[Dict[str, Any]]:
        matching = [r for r in self._relationships if r.get("user_id") == str(user_id)]

        if entity_id:
            eid = str(entity_id)
            matching = [
                r for r in matching
                if r.get("source_id") == eid or r.get("target_id") == eid
            ]

        if relationship_type:
            rtype = str(relationship_type)
            matching = [r for r in matching if r.get("relationship_type") == rtype]

        # Sort descending by created_at
        matching.sort(key=lambda x: x.get("created_at", ""), reverse=True)

        sliced = matching[offset : offset + limit]
        return [dict(r) for r in sliced]

    def get_relationship_by_id(
        self, relationship_id: str, user_id: str
    ) -> Optional[Dict[str, Any]]:
        for r in self._relationships:
            if r.get("id") == str(relationship_id) and r.get("user_id") == str(user_id):
                return dict(r)
        return None

    def update_relationship(
        self,
        relationship_id: str,
        user_id: str,
        relationship_type: Optional[str] = None,
        confidence: Optional[str] = None,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> Optional[Dict[str, Any]]:
        for r in self._relationships:
            if r.get("id") == str(relationship_id) and r.get("user_id") == str(user_id):
                if relationship_type is not None:
                    r["relationship_type"] = str(relationship_type)
                if confidence is not None:
                    r["confidence"] = str(confidence)
                if metadata is not None:
                    r["metadata"] = dict(metadata)
                r["updated_at"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
                return dict(r)
        return None

    def delete_relationship(self, relationship_id: str, user_id: str) -> bool:
        for idx, r in enumerate(self._relationships):
            if r.get("id") == str(relationship_id) and r.get("user_id") == str(user_id):
                self._relationships.pop(idx)
                return True
        return False

    def find_existing_relationship(
        self,
        user_id: str,
        source_id: str,
        target_id: str,
        relationship_type: str,
    ) -> Optional[Dict[str, Any]]:
        for r in self._relationships:
            if (
                r.get("user_id") == str(user_id)
                and r.get("source_id") == str(source_id)
                and r.get("target_id") == str(target_id)
                and r.get("relationship_type") == str(relationship_type)
            ):
                return dict(r)
        return None

