from typing import Any, Dict, List, Optional

from pydantic import BaseModel, Field


class Book(BaseModel):
    """
    Core Catalog Entity for a Book.
    """
    isbn13: str = Field(..., description="Unique 13-digit ISBN")
    title: str = Field(default="Unknown Title")
    authors: str = Field(default="Unknown Author")
    categories: str = Field(default="")
    description: str = Field(default="")
    thumbnail: str = Field(default="")
    average_rating: float = Field(default=0.0)
    ratings_count: int = Field(default=0)
    published_date: str = Field(default="")
    page_count: int = Field(default=0)


class Recommendation(Book):
    """
    Discovery Context Entity for a Recommended Book.
    Inherits Book and adds scoring and reasoning fields.
    """
    similarity_score: Optional[float] = Field(default=None)
    explanation: Optional[str] = Field(default=None)
    explanation_source_book: Optional[str] = Field(default=None)
    recommendation_reason: Optional[str] = Field(default=None)
    explanation_type: Optional[str] = Field(
        default=None,
        description="liked_book, favorite_book, finished_book, reading_journey, takeaway_affinity, category_affinity, author_affinity, learning_path_continuity, trending_catalog",
    )
    confidence: Optional[str] = Field(default="medium", description="high, medium, cold_start")
    is_cold_start: bool = Field(default=False)
    raw_similarity_score: Optional[float] = Field(default=None)
    final_score: Optional[float] = Field(default=None)
    diversity_penalty: Optional[float] = Field(default=None)


class RecommendationDiagnostics(BaseModel):
    """
    Diagnostic telemetry for explainable ranking.
    """
    engine_version: str = "2.6.0"
    candidate_count: int = 0
    filtered_count: int = 0
    is_cold_start: bool = False
    evidence_coverage: str = "cold_start"
    fallback_reason: Optional[str] = None
    latency_ms: Optional[float] = None


class UserPreferenceProfile(BaseModel):
    """
    Derived privacy-conscious preference profile.
    Calculated on-demand from interactions, library, notes, reviews, and learning paths.
    """
    user_id: str
    category_affinities: Dict[str, float] = Field(default_factory=dict)
    author_affinities: Dict[str, float] = Field(default_factory=dict)
    preferred_genres: List[str] = Field(default_factory=list)
    preferred_authors: List[str] = Field(default_factory=list)
    positive_signal_count: int = 0
    negative_signal_count: int = 0
    total_notes_count: int = 0
    takeaway_count: int = 0
    retention_summary: Dict[str, int] = Field(default_factory=dict)
    active_learning_paths_count: int = 0
    disliked_isbns: List[str] = Field(default_factory=list)
    completed_isbns: List[str] = Field(default_factory=list)
    reading_isbns: List[str] = Field(default_factory=list)
    favorite_isbns: List[str] = Field(default_factory=list)
    liked_isbns: List[str] = Field(default_factory=list)
    want_to_read_isbns: List[str] = Field(default_factory=list)
    evidence_coverage: str = Field(default="cold_start", description="cold_start, emerging, established")
    profile_version: str = Field(default="2.6.0")
    computed_at: Optional[str] = None


class UserInteraction(BaseModel):
    """
    Activity Context Entity representing a user's action on a book.
    """
    user_id: str
    book_id: str
    interaction_type: str  # 'like', 'dislike', 'view', etc.
    timestamp: Optional[str] = None


class UserProfile(BaseModel):
    """
    Activity Context Entity for user preferences.
    """
    user_id: str
    preferred_genres: List[str] = Field(default_factory=list)
    updated_at: Optional[str] = None


class UserNote(BaseModel):
    """
    Learning Context Entity representing a user's personal learning note on a book.
    Types: 'personal_note', 'key_takeaway', 'question'.
    """
    id: Optional[str] = None
    user_id: str
    book_id: str
    note_type: str = Field(default="personal_note", description="personal_note, key_takeaway, or question")
    content: str = Field(..., max_length=5000)
    created_at: Optional[str] = None
    updated_at: Optional[str] = None
    book: Optional[dict] = None


class LearningPathItem(BaseModel):
    book_id: str
    order_index: int = 0
    added_at: Optional[str] = None
    book: Optional[dict] = None
    reading_status: Optional[str] = None
    notes_count: int = 0
    has_due_review: bool = False


class LearningPath(BaseModel):
    id: Optional[str] = None
    user_id: str
    title: str = Field(..., min_length=1, max_length=150)
    description: Optional[str] = ""
    category: Optional[str] = ""
    status: str = Field(default="active", description="active, completed, archived")
    books: List[LearningPathItem] = Field(default_factory=list)
    created_at: Optional[str] = None
    updated_at: Optional[str] = None
    # Progress intelligence fields
    total_books: int = 0
    completed_books: int = 0
    reading_books: int = 0
    not_started_books: int = 0
    progress_percent: int = 0
    total_notes_count: int = 0
    total_reviews_due: int = 0
    next_book_id: Optional[str] = None


class RAGResponse(BaseModel):
    """
    Discovery Context Entity for AI Chat response.
    """
    answer: str
    referenced_books: List[Recommendation] = Field(default_factory=list)
    status: str = "success"
    action: Optional[dict] = Field(default=None)
    latency_ms: Optional[float] = Field(default=None)
    metrics: Optional[dict] = Field(default=None)


class KnowledgeNode(BaseModel):
    """
    Graph vertex representing a Book, Concept/Topic, Reading Note, or Learning Path.
    """
    id: str
    label: str
    type: str = Field(..., description="book, concept, note, learning_path")
    data: Dict[str, Any] = Field(default_factory=dict)
    degree: int = 0


class KnowledgeEdge(BaseModel):
    """
    Evidence-backed directed edge connecting two entities in the personal knowledge graph.
    """
    id: Optional[str] = None
    user_id: str
    source_id: str
    source_type: str = Field(..., description="book, concept, note, learning_path")
    target_id: str
    target_type: str = Field(..., description="book, concept, note, learning_path")
    relationship_type: str = Field(
        ...,
        description="covers_concept, reinforces_concept, relates_to, builds_upon, curates_book, references_book, derived_from",
    )
    source: str = Field(
        default="user_explicit",
        description="user_explicit, reading_note, book_metadata, system_inference",
    )
    evidence_ref: Optional[str] = None
    confidence: str = Field(default="high", description="high, medium, suggested")
    metadata: Dict[str, Any] = Field(default_factory=dict)
    created_at: Optional[str] = None
    updated_at: Optional[str] = None


class KnowledgeGraphData(BaseModel):
    """
    Composite Personal Knowledge Graph response.
    """
    nodes: List[KnowledgeNode] = Field(default_factory=list)
    edges: List[KnowledgeEdge] = Field(default_factory=list)
    total_nodes: int = 0
    total_edges: int = 0
    focus_id: Optional[str] = None
    depth: int = 1


class ReviewItem(BaseModel):
    """
    Review item representing an active-recall study unit linked to concepts, notes, or books.
    """
    id: Optional[str] = None
    user_id: str
    title: str = Field(..., min_length=1, max_length=200)
    concept: str = Field(..., min_length=1, max_length=150)
    question: str = Field(..., min_length=1, max_length=2000)
    answer: str = Field(..., min_length=1, max_length=5000)
    explanation: Optional[str] = Field(default="", max_length=3000)
    source_type: str = Field(
        default="user_created",
        description="user_note, key_takeaway, concept, learning_path, user_created, book",
    )
    source_id: Optional[str] = None
    book_id: Optional[str] = None
    path_id: Optional[str] = None
    stage: int = Field(default=1, ge=1, le=5)
    interval_days: int = Field(default=1, ge=1)
    next_review_at: Optional[str] = None
    last_reviewed_at: Optional[str] = None
    total_reviews: int = Field(default=0, ge=0)
    successful_reviews: int = Field(default=0, ge=0)
    status: str = Field(default="active", description="active, paused, archived")
    metadata: Dict[str, Any] = Field(default_factory=dict)
    created_at: Optional[str] = None
    updated_at: Optional[str] = None
    book: Optional[Dict[str, Any]] = None


class ReviewAttempt(BaseModel):
    """
    An immutable record of an active recall review attempt.
    """
    id: Optional[str] = None
    user_id: str
    item_id: str
    outcome: str = Field(..., description="remembered or struggled")
    response_text: Optional[str] = ""
    is_correct: bool = False
    stage_before: int = Field(default=1, ge=1, le=5)
    stage_after: int = Field(default=1, ge=1, le=5)
    reviewed_at: Optional[str] = None
    created_at: Optional[str] = None


class LearningProgress(BaseModel):
    """
    Evidence-derived metrics representing user's learning intelligence and retention.
    """
    mastery_score: int = Field(default=0, ge=0, le=100)
    mastery_level: str = Field(
        default="insufficient_data",
        description="insufficient_data, novice, practicing, proficient, mastered",
    )
    total_items: int = 0
    reviews_due: int = 0
    reviews_completed: int = 0
    successful_recalls: int = 0
    struggled_recalls: int = 0
    retention_rate: float = 0.0
    concepts_count: int = 0
    difficult_concepts: List[Dict[str, Any]] = Field(default_factory=list)
    recent_activity: List[Dict[str, Any]] = Field(default_factory=list)
    active_streak_days: int = 0
    algorithm_version: str = "v1"


class ReviewQueueItem(ReviewItem):
    """
    Review item enriched with adaptive priority and explainable recommendation reasons.
    """
    priority: int = 0
    recommendation_reason: str = ""
    recommendation_reason_key: str = "concept_practice"


