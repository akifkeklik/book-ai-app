"""
Deterministic Evaluation Dataset & Persona Cohorts.

Constructs realistic reader cohorts from the catalog (backend/data/books.csv)
with explicit Train (Seeds) / Test (Holdout Ground-Truth) separation
to ensure zero evaluation data leakage.
"""

from dataclasses import dataclass, field
from typing import List, Set

import pandas as pd


@dataclass
class EvaluationUser:
    """Represents an evaluation persona with train inputs and test ground truth."""

    user_id: str
    persona_name: str
    # Train inputs: passed into the recommendation engine / use case
    seed_likes: List[str] = field(default_factory=list)
    seed_favorites: List[str] = field(default_factory=list)
    dislikes: List[str] = field(default_factory=list)
    preferred_genres: List[str] = field(default_factory=list)
    preferred_authors: List[str] = field(default_factory=list)

    # Test / Holdout ground truth: NEVER passed to recommender as seeds
    # Used strictly to evaluate recall, precision, and NDCG
    holdout_ground_truth: Set[str] = field(default_factory=set)

    # Expected category/genre affinity for relevance checks
    target_categories: List[str] = field(default_factory=list)


def build_evaluation_cohort(df: pd.DataFrame) -> List[EvaluationUser]:
    """
    Build a deterministic evaluation cohort using actual catalog books.
    Uses reproducible category matching to find relevant ISBNs.
    """
    if df.empty:
        return []

    def find_isbns_by_category(query: str, limit: int = 12) -> List[str]:
        mask = df["categories"].astype(str).str.contains(query, case=False, na=False)
        subset = df[mask].sort_values(by="popularity_score", ascending=False)
        isbns = [str(x).strip() for x in subset["isbn13"].dropna().tolist() if str(x).strip()]
        return isbns[:limit]

    def find_isbns_by_author(author_query: str, limit: int = 6) -> List[str]:
        mask = df["authors"].astype(str).str.contains(author_query, case=False, na=False)
        subset = df[mask].sort_values(by="popularity_score", ascending=False)
        return [str(x).strip() for x in subset["isbn13"].dropna().tolist() if str(x).strip()][
            :limit
        ]

    cohort: List[EvaluationUser] = []

    # Persona 1: Sci-Fi Enthusiast
    scifi_isbns = find_isbns_by_category("Science Fiction", limit=12)
    if len(scifi_isbns) >= 6:
        cohort.append(
            EvaluationUser(
                user_id="eval-user-scifi-1",
                persona_name="Sci-Fi Enthusiast",
                seed_likes=scifi_isbns[:3],
                seed_favorites=[scifi_isbns[3]],
                dislikes=[],
                preferred_genres=["Science Fiction"],
                preferred_authors=[],
                holdout_ground_truth=set(scifi_isbns[4:]),
                target_categories=["Science Fiction"],
            )
        )

    # Persona 2: Fantasy & Adventure Lover
    fantasy_isbns = find_isbns_by_category("Fantasy", limit=12)
    if len(fantasy_isbns) >= 6:
        cohort.append(
            EvaluationUser(
                user_id="eval-user-fantasy-2",
                persona_name="Epic Fantasy Lover",
                seed_likes=fantasy_isbns[:3],
                seed_favorites=[fantasy_isbns[3]],
                dislikes=[],
                preferred_genres=["Fantasy"],
                preferred_authors=[],
                holdout_ground_truth=set(fantasy_isbns[4:]),
                target_categories=["Fantasy"],
            )
        )

    # Persona 3: Mystery & Detective Fiction
    mystery_isbns = find_isbns_by_category("Mystery", limit=12)
    if len(mystery_isbns) >= 6:
        cohort.append(
            EvaluationUser(
                user_id="eval-user-mystery-3",
                persona_name="Mystery & Detective Reader",
                seed_likes=mystery_isbns[:3],
                seed_favorites=[mystery_isbns[3]],
                dislikes=[],
                preferred_genres=["Mystery & Thriller"],
                preferred_authors=[],
                holdout_ground_truth=set(mystery_isbns[4:]),
                target_categories=["Mystery & Thriller"],
            )
        )

    # Persona 4: Science & Nonfiction
    science_isbns = find_isbns_by_category("Science", limit=12)
    if len(science_isbns) >= 6:
        cohort.append(
            EvaluationUser(
                user_id="eval-user-science-4",
                persona_name="Popular Science Reader",
                seed_likes=science_isbns[:3],
                seed_favorites=[science_isbns[3]],
                dislikes=[],
                preferred_genres=["Science"],
                preferred_authors=[],
                holdout_ground_truth=set(science_isbns[4:]),
                target_categories=["Science"],
            )
        )

    # Persona 5: Philosophy & Deep Thought
    philo_isbns = find_isbns_by_category("Philosophy", limit=12)
    if len(philo_isbns) >= 6:
        cohort.append(
            EvaluationUser(
                user_id="eval-user-philo-5",
                persona_name="Philosophy & Essays Reader",
                seed_likes=philo_isbns[:3],
                seed_favorites=[philo_isbns[3]],
                dislikes=[],
                preferred_genres=["Philosophy"],
                preferred_authors=[],
                holdout_ground_truth=set(philo_isbns[4:]),
                target_categories=["Philosophy"],
            )
        )

    # Persona 6: Divergent Interests with Explicit Dislikes
    # Loves Sci-Fi, but explicitly disliked Romance and specific Thriller books
    romance_isbns = find_isbns_by_category("Romance", limit=4)
    if len(scifi_isbns) >= 6 and len(romance_isbns) >= 2:
        cohort.append(
            EvaluationUser(
                user_id="eval-user-divergent-6",
                persona_name="Sci-Fi Reader with Romance Dislikes",
                seed_likes=scifi_isbns[:3],
                seed_favorites=[scifi_isbns[3]],
                dislikes=romance_isbns[:2],
                preferred_genres=["Science Fiction"],
                preferred_authors=[],
                holdout_ground_truth=set(scifi_isbns[4:8]),
                target_categories=["Science Fiction"],
            )
        )

    # Persona 7: Cold-Start User with Profile Preferences (Zero Seeds)
    # Specified preferred genres and author during onboarding, but 0 interaction events
    cohort.append(
        EvaluationUser(
            user_id="eval-user-coldstart-profile-7",
            persona_name="Cold-Start Onboarding Profile",
            seed_likes=[],
            seed_favorites=[],
            dislikes=[],
            preferred_genres=["Fantasy", "Fiction"],
            preferred_authors=["J.K. Rowling", "Tolkien"],
            holdout_ground_truth=set(fantasy_isbns),
            target_categories=["Fantasy", "Fiction"],
        )
    )

    # Persona 8: Pure Cold-Start Blank Slate (Zero interactions, zero profile)
    cohort.append(
        EvaluationUser(
            user_id="eval-user-blank-8",
            persona_name="Blank Slate Cold Start",
            seed_likes=[],
            seed_favorites=[],
            dislikes=[],
            preferred_genres=[],
            preferred_authors=[],
            holdout_ground_truth=set(),
            target_categories=[],
        )
    )

    return cohort
