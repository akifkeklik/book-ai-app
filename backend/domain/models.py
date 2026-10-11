from typing import List, Optional

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
    raw_similarity_score: Optional[float] = Field(default=None)
    final_score: Optional[float] = Field(default=None)
    diversity_penalty: Optional[float] = Field(default=None)


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


class RAGResponse(BaseModel):
    """
    Discovery Context Entity for AI Chat response.
    """
    answer: str
    referenced_books: List[Recommendation] = Field(default_factory=list)
    status: str = "success"
