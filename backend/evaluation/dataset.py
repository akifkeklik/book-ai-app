"""
Deterministic Evaluation Dataset & Persona Cohorts.

Constructs realistic reader cohorts from the catalog (backend/data/books.csv)
with explicit Train (Seeds) / Test (Holdout Ground-Truth) separation
to ensure zero evaluation data leakage.
"""

from dataclasses import dataclass, field
from typing import Dict, List, Set

import pandas as pd


@dataclass
class EvaluationUser:
    """Represents an evaluation persona with train inputs and test ground truth."""

    user_id: str
    persona_name: str
    # Train inputs: passed into the recommendation engine / use case
    seed_likes: List[str] = field(default_factory=list)
    seed_favorites: List[str] = field(default_factory=list)
    reading_history: List[Dict[str, str]] = field(default_factory=list)
    dislikes: List[str] = field(default_factory=list)
    preferred_genres: List[str] = field(default_factory=list)
    preferred_authors: List[str] = field(default_factory=list)

    # Test / Holdout ground truth: NEVER passed to recommender as seeds
    # Used strictly to evaluate recall, precision, and NDCG
    holdout_ground_truth: Set[str] = field(default_factory=set)

    # Expected category/genre affinity for relevance checks
    target_categories: List[str] = field(default_factory=list)
    simulate_missing_vector: bool = False


def build_evaluation_cohort(df: pd.DataFrame) -> List[EvaluationUser]:
    """
    Build a deterministic evaluation cohort covering the 8 required offline evaluation scenarios.
    Uses reproducible catalog queries and fixed seed sets to prevent data leakage.
    """
    if df.empty:
        return []

    def find_isbns_by_category(query: str, limit: int = 12) -> List[str]:
        mask = df["categories"].astype(str).str.contains(query, case=False, na=False)
        subset = df[mask].sort_values(by="popularity_score", ascending=False)
        isbns = [str(x).strip() for x in subset["isbn13"].dropna().tolist() if str(x).strip()]
        return isbns[:limit]

    cohort: List[EvaluationUser] = []

    scifi_isbns = find_isbns_by_category("Science Fiction", limit=12)
    fantasy_isbns = find_isbns_by_category("Fantasy", limit=12)
    mystery_isbns = find_isbns_by_category("Mystery", limit=12)
    romance_isbns = find_isbns_by_category("Romance", limit=6)

    # Scenario 1: New user with no interactions (pure cold start blank slate)
    cohort.append(
        EvaluationUser(
            user_id="eval-user-blank-1",
            persona_name="1. New user with no interactions (Blank Slate)",
            seed_likes=[],
            seed_favorites=[],
            reading_history=[],
            dislikes=[],
            preferred_genres=[],
            preferred_authors=[],
            holdout_ground_truth=set(),
            target_categories=[],
        )
    )

    # Scenario 2: User with favorites only
    if len(fantasy_isbns) >= 6:
        cohort.append(
            EvaluationUser(
                user_id="eval-user-favorites-2",
                persona_name="2. User with favorites only",
                seed_likes=[],
                seed_favorites=fantasy_isbns[:3],
                reading_history=[],
                dislikes=[],
                preferred_genres=["Fantasy"],
                preferred_authors=[],
                holdout_ground_truth=set(fantasy_isbns[3:]),
                target_categories=["Fantasy"],
            )
        )

    # Scenario 3: User with reading history (want_to_read, reading, finished)
    if len(scifi_isbns) >= 6:
        cohort.append(
            EvaluationUser(
                user_id="eval-user-reading-3",
                persona_name="3. User with reading history",
                seed_likes=[],
                seed_favorites=[],
                reading_history=[
                    {"book_id": scifi_isbns[0], "status": "finished"},
                    {"book_id": scifi_isbns[1], "status": "reading"},
                    {"book_id": scifi_isbns[2], "status": "want_to_read"},
                ],
                dislikes=[],
                preferred_genres=["Science Fiction"],
                preferred_authors=[],
                holdout_ground_truth=set(scifi_isbns[3:]),
                target_categories=["Science Fiction"],
            )
        )

    # Scenario 4: User with explicit likes and dislikes
    if len(scifi_isbns) >= 6 and len(romance_isbns) >= 2:
        cohort.append(
            EvaluationUser(
                user_id="eval-user-likes-dislikes-4",
                persona_name="4. User with explicit likes and dislikes",
                seed_likes=scifi_isbns[:3],
                seed_favorites=[],
                reading_history=[],
                dislikes=romance_isbns[:2],
                preferred_genres=["Science Fiction"],
                preferred_authors=[],
                holdout_ground_truth=set(scifi_isbns[3:8]),
                target_categories=["Science Fiction"],
            )
        )

    # Scenario 5: User with a mixture of reading states and taste feedback
    if len(mystery_isbns) >= 6 and len(romance_isbns) >= 2:
        cohort.append(
            EvaluationUser(
                user_id="eval-user-mixed-5",
                persona_name="5. User with mixture of reading states and taste feedback",
                seed_likes=[mystery_isbns[0]],
                seed_favorites=[mystery_isbns[1]],
                reading_history=[
                    {"book_id": mystery_isbns[2], "status": "finished"},
                    {"book_id": mystery_isbns[3], "status": "reading"},
                ],
                dislikes=[romance_isbns[0]],
                preferred_genres=["Mystery & Thriller"],
                preferred_authors=[],
                holdout_ground_truth=set(mystery_isbns[4:]),
                target_categories=["Mystery & Thriller"],
            )
        )

    # Scenario 6: User whose preferred titles are absent from the candidate catalog
    cohort.append(
        EvaluationUser(
            user_id="eval-user-absent-6",
            persona_name="6. User with preferred titles absent from catalog",
            seed_likes=["9789999999001", "9789999999002"],
            seed_favorites=["9789999999003"],
            reading_history=[],
            dislikes=[],
            preferred_genres=["Fantasy"],
            preferred_authors=[],
            holdout_ground_truth=set(fantasy_isbns[:5]) if fantasy_isbns else set(),
            target_categories=["Fantasy"],
        )
    )

    # Scenario 7: Sparse or malformed metadata
    cohort.append(
        EvaluationUser(
            user_id="eval-user-sparse-7",
            persona_name="7. User with sparse or malformed metadata",
            seed_likes=[scifi_isbns[0]] if scifi_isbns else [],
            seed_favorites=[],
            reading_history=[],
            dislikes=["   ", ""],  # Malformed empty dislikes
            preferred_genres=["  ", "Science Fiction", ""],  # Whitespace / malformed genres
            preferred_authors=["Unknown Author"],
            holdout_ground_truth=set(scifi_isbns[1:5]) if len(scifi_isbns) > 1 else set(),
            target_categories=["Science Fiction"],
        )
    )

    # Scenario 8: Missing embeddings or unavailable vector retrieval
    if len(fantasy_isbns) >= 6:
        cohort.append(
            EvaluationUser(
                user_id="eval-user-vector-unavailable-8",
                persona_name="8. Missing embeddings / unavailable vector retrieval",
                seed_likes=fantasy_isbns[:2],
                seed_favorites=[fantasy_isbns[2]],
                reading_history=[],
                dislikes=[],
                preferred_genres=["Fantasy"],
                preferred_authors=[],
                holdout_ground_truth=set(fantasy_isbns[3:]),
                target_categories=["Fantasy"],
                simulate_missing_vector=True,
            )
        )

    return cohort
