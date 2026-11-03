import logging
import re
from typing import Any, Dict, List, Optional, Set, Tuple

from backend.domain.models import KnowledgeEdge, KnowledgeGraphData, KnowledgeNode
from backend.domain.ports import (
    CatalogPort,
    KnowledgeGraphRepository,
    LearningPathRepository,
    UserInteractionRepository,
    UserNoteRepository,
)
from backend.domain.taxonomy import CANONICAL_CATEGORY_MAP

logger = logging.getLogger(__name__)

VALID_NODE_TYPES = {"book", "concept", "note", "learning_path"}
VALID_SOURCES = {"user_explicit", "reading_note", "book_metadata", "system_inference"}
VALID_CONFIDENCES = {"high", "medium", "suggested"}
VALID_RELATIONSHIP_TYPES = {
    "covers_concept",
    "reinforces_concept",
    "relates_to",
    "builds_upon",
    "curates_book",
    "references_book",
    "derived_from",
    "contrasts_with",
    "prerequisite_for",
}


def slugify_concept(name: str) -> str:
    cleaned = re.sub(r"[^\w\s-]", "", name.lower().strip())
    return re.sub(r"[-\s]+", "_", cleaned)


class GetPersonalKnowledgeGraphUseCase:
    """
    Synthesizes a user's personal, evidence-backed knowledge graph by unifying:
    1. Persisted explicit relationships
    2. Books in the reader's journey (reading, finished, favorites, likes)
    3. Reading notes and key takeaways
    4. Curated learning paths
    5. Domain concept taxonomies
    """

    def __init__(
        self,
        knowledge_repo: KnowledgeGraphRepository,
        interaction_repo: UserInteractionRepository,
        note_repo: Optional[UserNoteRepository] = None,
        learning_path_repo: Optional[LearningPathRepository] = None,
        catalog_port: Optional[CatalogPort] = None,
    ):
        self.knowledge_repo = knowledge_repo
        self.interaction_repo = interaction_repo
        self.note_repo = note_repo
        self.learning_path_repo = learning_path_repo
        self.catalog_port = catalog_port

    def execute(
        self,
        user_id: str,
        focus_id: Optional[str] = None,
        depth: int = 1,
        limit: int = 100,
        node_type_filter: Optional[str] = None,
        relationship_type_filter: Optional[str] = None,
    ) -> KnowledgeGraphData:
        safe_limit = max(1, min(limit, 300))
        safe_depth = max(1, min(depth, 3))

        nodes_map: Dict[str, KnowledgeNode] = {}
        edges_list: List[KnowledgeEdge] = []
        edge_keys: Set[Tuple[str, str, str]] = set()

        def add_node(
            nid: str, label: str, ntype: str, data: Optional[Dict[str, Any]] = None
        ):
            if nid not in nodes_map:
                nodes_map[nid] = KnowledgeNode(
                    id=nid,
                    label=label or nid,
                    type=ntype,
                    data=data or {},
                    degree=0,
                )
            elif data:
                # Merge data if existing had empty
                existing_data = nodes_map[nid].data
                for k, v in data.items():
                    if v and not existing_data.get(k):
                        existing_data[k] = v

        def add_edge(
            source_id: str,
            source_type: str,
            target_id: str,
            target_type: str,
            relationship_type: str,
            source: str = "system_inference",
            evidence_ref: Optional[str] = None,
            confidence: str = "high",
            metadata: Optional[Dict[str, Any]] = None,
            edge_id: Optional[str] = None,
            created_at: Optional[str] = None,
            updated_at: Optional[str] = None,
        ):
            key = (source_id, target_id, relationship_type)
            if key in edge_keys:
                return
            edge_keys.add(key)
            edges_list.append(
                KnowledgeEdge(
                    id=edge_id,
                    user_id=user_id,
                    source_id=source_id,
                    source_type=source_type,
                    target_id=target_id,
                    target_type=target_type,
                    relationship_type=relationship_type,
                    source=source,
                    evidence_ref=evidence_ref,
                    confidence=confidence,
                    metadata=metadata or {},
                    created_at=created_at,
                    updated_at=updated_at,
                )
            )

        # ── 1. User Persisted Explicit Relationships ──────────────────────────
        raw_relationships = self.knowledge_repo.get_user_relationships(
            user_id=user_id, limit=safe_limit
        )
        for rel in raw_relationships:
            s_id = str(rel.get("source_id", ""))
            s_type = str(rel.get("source_type", "concept"))
            t_id = str(rel.get("target_id", ""))
            t_type = str(rel.get("target_type", "concept"))
            r_type = str(rel.get("relationship_type", "relates_to"))

            if not s_id or not t_id:
                continue

            # Ensure placeholder nodes exist
            s_label = s_id.split(":")[-1].replace("_", " ").title()
            t_label = t_id.split(":")[-1].replace("_", " ").title()
            add_node(s_id, s_label, s_type)
            add_node(t_id, t_label, t_type)

            add_edge(
                source_id=s_id,
                source_type=s_type,
                target_id=t_id,
                target_type=t_type,
                relationship_type=r_type,
                source=rel.get("source", "user_explicit"),
                evidence_ref=rel.get("evidence_ref"),
                confidence=rel.get("confidence", "high"),
                metadata=rel.get("metadata") or {},
                edge_id=str(rel.get("id")) if rel.get("id") else None,
                created_at=rel.get("created_at"),
                updated_at=rel.get("updated_at"),
            )

        # ── 2. User Interactions & Books Catalog ──────────────────────────────
        interactions = self.interaction_repo.get_user_interactions(user_id) or []
        user_books: Dict[str, Dict[str, Any]] = {}
        for inter in interactions:
            bid = inter.get("book_id")
            itype = inter.get("interaction_type")
            if not bid:
                continue
            if itype in ("like", "favorite", "finished", "reading", "want_to_read"):
                if bid not in user_books:
                    user_books[bid] = {"interaction_types": set()}
                user_books[bid]["interaction_types"].add(itype)

        # Fetch book details from catalog if available
        for bid, binfo in list(user_books.items())[:50]:
            book_dto = None
            if self.catalog_port:
                try:
                    book_dto = self.catalog_port.get_book_by_isbn(bid)
                except Exception:
                    book_dto = None

            title = (book_dto.get("title") if book_dto else None) or f"Book ({bid})"
            authors = (book_dto.get("authors") if book_dto else None) or ""
            categories = (book_dto.get("categories") if book_dto else None) or ""
            thumbnail = (book_dto.get("thumbnail") if book_dto else None) or ""

            book_node_id = bid
            add_node(
                nid=book_node_id,
                label=title,
                ntype="book",
                data={
                    "isbn13": bid,
                    "title": title,
                    "authors": authors,
                    "categories": categories,
                    "thumbnail": thumbnail,
                    "interactions": list(binfo["interaction_types"]),
                },
            )

            # Extract concepts from category metadata
            if categories:
                raw_cats = [c.strip() for c in categories.replace(";", ",").split(",") if c.strip()]
                for raw_cat in raw_cats:
                    norm_cat = CANONICAL_CATEGORY_MAP.get(raw_cat.lower(), raw_cat.title())
                    cid = f"concept:{slugify_concept(norm_cat)}"
                    add_node(
                        nid=cid,
                        label=norm_cat,
                        ntype="concept",
                        data={"canonical_name": norm_cat, "raw_category": raw_cat},
                    )
                    add_edge(
                        source_id=book_node_id,
                        source_type="book",
                        target_id=cid,
                        target_type="concept",
                        relationship_type="covers_concept",
                        source="book_metadata",
                        evidence_ref=f"category:{raw_cat}",
                        confidence="high",
                    )

        # ── 3. Reading Notes & Takeaways ──────────────────────────────────────
        if self.note_repo:
            try:
                notes = self.note_repo.get_user_notes(user_id=user_id, limit=50) or []
            except Exception:
                notes = []

            for note in notes:
                nid = str(note.get("id"))
                if not nid:
                    continue
                content = str(note.get("content", "")).strip()
                note_type = str(note.get("note_type", "personal_note"))
                bid = str(note.get("book_id", "")).strip()
                snippet = content[:40] + ("..." if len(content) > 40 else "")
                note_node_id = f"note:{nid}"

                add_node(
                    nid=note_node_id,
                    label=snippet or f"Note ({note_type})",
                    ntype="note",
                    data={
                        "note_id": nid,
                        "content": content,
                        "note_type": note_type,
                        "book_id": bid,
                        "created_at": note.get("created_at"),
                    },
                )

                if bid:
                    # Link Note to Book
                    if bid not in nodes_map:
                        add_node(bid, f"Book ({bid})", "book", {"isbn13": bid})
                    add_edge(
                        source_id=note_node_id,
                        source_type="note",
                        target_id=bid,
                        target_type="book",
                        relationship_type="references_book",
                        source="reading_note",
                        evidence_ref=nid,
                        confidence="high",
                    )

        # ── 4. Learning Paths ─────────────────────────────────────────────────
        if self.learning_path_repo:
            try:
                paths = self.learning_path_repo.get_user_paths(user_id=user_id) or []
            except Exception:
                paths = []

            for path in paths:
                pid = str(path.get("id"))
                if not pid:
                    continue
                ptitle = str(path.get("title", "Learning Path")).strip()
                pcat = str(path.get("category", "")).strip()
                path_node_id = f"path:{pid}"

                add_node(
                    nid=path_node_id,
                    label=ptitle,
                    ntype="learning_path",
                    data={
                        "path_id": pid,
                        "title": ptitle,
                        "category": pcat,
                        "status": path.get("status", "active"),
                    },
                )

                # If path has a category, link Path to Concept
                if pcat:
                    norm_cat = CANONICAL_CATEGORY_MAP.get(pcat.lower(), pcat.title())
                    cid = f"concept:{slugify_concept(norm_cat)}"
                    add_node(
                        nid=cid,
                        label=norm_cat,
                        ntype="concept",
                        data={"canonical_name": norm_cat},
                    )
                    add_edge(
                        source_id=path_node_id,
                        source_type="learning_path",
                        target_id=cid,
                        target_type="concept",
                        relationship_type="covers_concept",
                        source="system_inference",
                        confidence="high",
                    )

                # Link Path to curated books
                for item in path.get("books", []):
                    item_bid = str(item.get("book_id", "")).strip()
                    if item_bid:
                        if item_bid not in nodes_map:
                            add_node(item_bid, f"Book ({item_bid})", "book", {"isbn13": item_bid})
                        add_edge(
                            source_id=path_node_id,
                            source_type="learning_path",
                            target_id=item_bid,
                            target_type="book",
                            relationship_type="curates_book",
                            source="system_inference",
                            evidence_ref=pid,
                            confidence="high",
                        )

        # ── 5. Focus & Depth Filtering (BFS) ──────────────────────────────────
        if focus_id:
            # Resolve focus_id directly or with prefix
            matched_focus = None
            for nid in nodes_map:
                if nid == focus_id or nid.endswith(f":{focus_id}"):
                    matched_focus = nid
                    break

            if matched_focus:
                # Build adjacency list
                adj: Dict[str, Set[str]] = {nid: set() for nid in nodes_map}
                for edge in edges_list:
                    if edge.source_id in adj and edge.target_id in adj:
                        adj[edge.source_id].add(edge.target_id)
                        adj[edge.target_id].add(edge.source_id)

                # BFS up to safe_depth
                visited: Set[str] = {matched_focus}
                queue = [(matched_focus, 0)]
                while queue:
                    curr, d = queue.pop(0)
                    if d < safe_depth:
                        for neighbor in adj.get(curr, set()):
                            if neighbor not in visited:
                                visited.add(neighbor)
                                queue.append((neighbor, d + 1))

                # Filter nodes and edges to visited subgraph
                nodes_map = {nid: n for nid, n in nodes_map.items() if nid in visited}
                edges_list = [
                    e for e in edges_list
                    if e.source_id in visited and e.target_id in visited
                ]

        # ── 6. Type & Relationship Filtering ──────────────────────────────────
        if node_type_filter and node_type_filter in VALID_NODE_TYPES:
            # Retain nodes matching type or neighbors with direct edge
            primary_nodes = {nid for nid, n in nodes_map.items() if n.type == node_type_filter}
            allowed_nodes = set(primary_nodes)
            for e in edges_list:
                if e.source_id in primary_nodes:
                    allowed_nodes.add(e.target_id)
                elif e.target_id in primary_nodes:
                    allowed_nodes.add(e.source_id)
            nodes_map = {nid: n for nid, n in nodes_map.items() if nid in allowed_nodes}
            edges_list = [
                e for e in edges_list
                if e.source_id in allowed_nodes and e.target_id in allowed_nodes
            ]

        if relationship_type_filter:
            edges_list = [
                e for e in edges_list if e.relationship_type == relationship_type_filter
            ]
            # Prune orphaned nodes
            connected_nodes = set()
            for e in edges_list:
                connected_nodes.add(e.source_id)
                connected_nodes.add(e.target_id)
            if connected_nodes:
                nodes_map = {nid: n for nid, n in nodes_map.items() if nid in connected_nodes}

        # ── 7. Degree Calculation & Clamping ──────────────────────────────────
        degrees: Dict[str, int] = {nid: 0 for nid in nodes_map}
        for e in edges_list:
            if e.source_id in degrees:
                degrees[e.source_id] += 1
            if e.target_id in degrees:
                degrees[e.target_id] += 1

        for nid, deg in degrees.items():
            if nid in nodes_map:
                nodes_map[nid].degree = deg

        # Limit node count if exceeds safe_limit
        final_nodes = list(nodes_map.values())
        if len(final_nodes) > safe_limit:
            # Sort by degree descending to keep most informative hub nodes
            final_nodes.sort(key=lambda n: n.degree, reverse=True)
            kept_ids = {n.id for n in final_nodes[:safe_limit]}
            final_nodes = final_nodes[:safe_limit]
            edges_list = [
                e for e in edges_list if e.source_id in kept_ids and e.target_id in kept_ids
            ]

        return KnowledgeGraphData(
            nodes=final_nodes,
            edges=edges_list,
            total_nodes=len(final_nodes),
            total_edges=len(edges_list),
            focus_id=focus_id,
            depth=depth,
        )


class CreateRelationshipUseCase:
    """
    Creates an evidence-backed relationship between knowledge entities.
    Enforces user ownership, duplicate prevention, and cycle protection.
    """

    def __init__(
        self,
        knowledge_repo: KnowledgeGraphRepository,
        note_repo: Optional[UserNoteRepository] = None,
        learning_path_repo: Optional[LearningPathRepository] = None,
    ):
        self.knowledge_repo = knowledge_repo
        self.note_repo = note_repo
        self.learning_path_repo = learning_path_repo

    def execute(
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
        s_id = str(source_id).strip()
        t_id = str(target_id).strip()
        s_type = str(source_type).strip().lower()
        t_type = str(target_type).strip().lower()
        r_type = str(relationship_type).strip().lower()
        src = str(source).strip().lower() if source else "user_explicit"
        conf = str(confidence).strip().lower() if confidence else "high"

        if not s_id or not t_id:
            raise ValueError("source_id and target_id are required and cannot be empty.")

        if s_id == t_id:
            raise ValueError("Self-referential relationships (cycles) are not permitted.")

        if s_type not in VALID_NODE_TYPES:
            raise ValueError(f"Invalid source_type '{s_type}'. Must be one of {sorted(VALID_NODE_TYPES)}.")

        if t_type not in VALID_NODE_TYPES:
            raise ValueError(f"Invalid target_type '{t_type}'. Must be one of {sorted(VALID_NODE_TYPES)}.")

        if r_type not in VALID_RELATIONSHIP_TYPES:
            raise ValueError(f"Invalid relationship_type '{r_type}'. Must be one of {sorted(VALID_RELATIONSHIP_TYPES)}.")

        if src not in VALID_SOURCES:
            raise ValueError(f"Invalid source '{src}'. Must be one of {sorted(VALID_SOURCES)}.")

        if conf not in VALID_CONFIDENCES:
            raise ValueError(f"Invalid confidence '{conf}'. Must be one of {sorted(VALID_CONFIDENCES)}.")

        # Ownership validation for notes
        if s_type == "note" and self.note_repo:
            clean_note_id = s_id.replace("note:", "")
            note = self.note_repo.get_note_by_id(clean_note_id, user_id)
            if not note:
                raise PermissionError(f"Note '{clean_note_id}' does not exist or does not belong to user.")

        if t_type == "note" and self.note_repo:
            clean_note_id = t_id.replace("note:", "")
            note = self.note_repo.get_note_by_id(clean_note_id, user_id)
            if not note:
                raise PermissionError(f"Note '{clean_note_id}' does not exist or does not belong to user.")

        # Ownership validation for learning paths
        if s_type == "learning_path" and self.learning_path_repo:
            clean_path_id = s_id.replace("path:", "")
            path = self.learning_path_repo.get_path_by_id(clean_path_id, user_id)
            if not path:
                raise PermissionError(f"Learning path '{clean_path_id}' does not exist or does not belong to user.")

        if t_type == "learning_path" and self.learning_path_repo:
            clean_path_id = t_id.replace("path:", "")
            path = self.learning_path_repo.get_path_by_id(clean_path_id, user_id)
            if not path:
                raise PermissionError(f"Learning path '{clean_path_id}' does not exist or does not belong to user.")

        return self.knowledge_repo.create_relationship(
            user_id=user_id,
            source_id=s_id,
            source_type=s_type,
            target_id=t_id,
            target_type=t_type,
            relationship_type=r_type,
            source=src,
            evidence_ref=evidence_ref,
            confidence=conf,
            metadata=metadata or {},
        )


class UpdateRelationshipUseCase:
    """
    Updates an existing relationship's metadata, relationship_type, or confidence.
    Enforces user ownership.
    """

    def __init__(self, knowledge_repo: KnowledgeGraphRepository):
        self.knowledge_repo = knowledge_repo

    def execute(
        self,
        relationship_id: str,
        user_id: str,
        relationship_type: Optional[str] = None,
        confidence: Optional[str] = None,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        existing = self.knowledge_repo.get_relationship_by_id(relationship_id, user_id)
        if not existing:
            raise KeyError(f"Relationship '{relationship_id}' not found or unauthorized.")

        if relationship_type and relationship_type not in VALID_RELATIONSHIP_TYPES:
            raise ValueError(f"Invalid relationship_type '{relationship_type}'.")

        if confidence and confidence not in VALID_CONFIDENCES:
            raise ValueError(f"Invalid confidence '{confidence}'.")

        updated = self.knowledge_repo.update_relationship(
            relationship_id=relationship_id,
            user_id=user_id,
            relationship_type=relationship_type,
            confidence=confidence,
            metadata=metadata,
        )
        if not updated:
            raise KeyError(f"Failed to update relationship '{relationship_id}'.")
        return updated


class DeleteRelationshipUseCase:
    """
    Deletes an existing relationship belonging to user.
    """

    def __init__(self, knowledge_repo: KnowledgeGraphRepository):
        self.knowledge_repo = knowledge_repo

    def execute(self, relationship_id: str, user_id: str) -> bool:
        existing = self.knowledge_repo.get_relationship_by_id(relationship_id, user_id)
        if not existing:
            raise KeyError(f"Relationship '{relationship_id}' not found or unauthorized.")
        return self.knowledge_repo.delete_relationship(relationship_id, user_id)


class GetNeighborsUseCase:
    """
    Queries the 1-hop or 2-hop neighborhood of a specific node in the user's graph.
    """

    def __init__(self, get_graph_uc: GetPersonalKnowledgeGraphUseCase):
        self.get_graph_uc = get_graph_uc

    def execute(
        self, user_id: str, node_id: str, depth: int = 1, limit: int = 50
    ) -> KnowledgeGraphData:
        return self.get_graph_uc.execute(
            user_id=user_id, focus_id=node_id, depth=depth, limit=limit
        )

