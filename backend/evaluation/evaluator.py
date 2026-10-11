"""
Evaluation Engine for Libris Recommendation Pipelines.

Evaluates recommender engines and personalized recommendation use cases
against the deterministic evaluation cohort across Precision@K, Recall@K,
NDCG@K, Diversity (ILD), Catalog Coverage, Category Alignment, and Dislike Suppression.
"""

from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Set

import numpy as np

from .dataset import EvaluationUser
from .metrics import (
    catalog_coverage,
    dislike_suppression_rate,
    intra_list_diversity,
    ndcg_at_k,
    precision_at_k,
    recall_at_k,
)


@dataclass
class EvaluationReport:
    """Consolidated offline evaluation metrics."""

    model_name: str
    num_users_evaluated: int
    precision_at_5: float
    precision_at_10: float
    recall_at_5: float
    recall_at_10: float
    ndcg_at_5: float
    ndcg_at_10: float
    diversity_ild_at_5: float
    diversity_ild_at_10: float
    catalog_coverage: float
    dislike_suppression_rate: float
    category_alignment_at_5: float
    category_alignment_at_10: float
    per_user_results: List[Dict[str, Any]] = field(default_factory=list)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "model_name": self.model_name,
            "num_users_evaluated": self.num_users_evaluated,
            "precision@5": round(self.precision_at_5, 4),
            "precision@10": round(self.precision_at_10, 4),
            "recall@5": round(self.recall_at_5, 4),
            "recall@10": round(self.recall_at_10, 4),
            "ndcg@5": round(self.ndcg_at_5, 4),
            "ndcg@10": round(self.ndcg_at_10, 4),
            "diversity_ild@5": round(self.diversity_ild_at_5, 4),
            "diversity_ild@10": round(self.diversity_ild_at_10, 4),
            "catalog_coverage": round(self.catalog_coverage, 4),
            "dislike_suppression_rate": round(self.dislike_suppression_rate, 4),
            "category_alignment@5": round(self.category_alignment_at_5, 4),
            "category_alignment@10": round(self.category_alignment_at_10, 4),
        }


def evaluate_cohort(
    recommender: Any,
    cohort: List[EvaluationUser],
    model_name: str = "Recommender",
    use_case: Optional[Any] = None,
    mock_repo: Optional[Any] = None,
) -> EvaluationReport:
    """
    Run evaluation on a cohort.
    If use_case and mock_repo are provided, routes execution through the use case.
    Otherwise runs directly against recommender.recommend.
    """
    p5_list, p10_list = [], []
    r5_list, r10_list = [], []
    ndcg5_list, ndcg10_list = [], []
    ild5_list, ild10_list = [], []
    suppression_list = []
    cat_align5_list, cat_align10_list = [], []

    all_recommended_isbns: Set[str] = set()
    total_catalog_size = len(recommender.df) if hasattr(recommender, "df") else 1
    per_user_results = []

    for user in cohort:
        # Prepare inputs
        if use_case and mock_repo:
            # Seed mock_repo with this user's interactions and profile
            interactions = []
            for b in user.seed_likes:
                interactions.append({"book_id": b, "interaction_type": "like"})
            for b in user.seed_favorites:
                interactions.append({"book_id": b, "interaction_type": "favorite"})
            for b in user.dislikes:
                interactions.append({"book_id": b, "interaction_type": "dislike"})

            profile = {
                "user_id": user.user_id,
                "preferred_genres": user.preferred_genres,
                "preferred_authors": user.preferred_authors,
            }

            mock_repo.set_user_data(user.user_id, interactions, profile)
            recs_data = use_case.execute(user.user_id, limit=10)
        else:
            # Direct recommender call
            seeds = list(user.seed_likes) + list(user.seed_favorites)
            recs_data = recommender.recommend(
                seed_titles=seeds,
                top_n=10,
                use_diversity=True,
                dislikes=user.dislikes,
            )

        recommended_isbns = [
            str(r.get("isbn13", "")).strip() for r in recs_data if str(r.get("isbn13", "")).strip()
        ]
        all_recommended_isbns.update(recommended_isbns)

        # Match indices for ILD calculation
        rec_indices = []
        for isbn in recommended_isbns:
            if hasattr(recommender, "engine"):
                rec_indices.append(recommender.engine.find_index(isbn))
            else:
                rec_indices.append(None)

        # Metrics for users with holdout ground truth
        if user.holdout_ground_truth:
            p5 = precision_at_k(recommended_isbns, user.holdout_ground_truth, k=5)
            p10 = precision_at_k(recommended_isbns, user.holdout_ground_truth, k=10)
            r5 = recall_at_k(recommended_isbns, user.holdout_ground_truth, k=5)
            r10 = recall_at_k(recommended_isbns, user.holdout_ground_truth, k=10)
            ndcg5 = ndcg_at_k(recommended_isbns, user.holdout_ground_truth, k=5)
            ndcg10 = ndcg_at_k(recommended_isbns, user.holdout_ground_truth, k=10)

            p5_list.append(p5)
            p10_list.append(p10)
            r5_list.append(r5)
            r10_list.append(r10)
            ndcg5_list.append(ndcg5)
            ndcg10_list.append(ndcg10)

        # Dislike suppression rate
        suppression = dislike_suppression_rate(recommended_isbns, set(user.dislikes), k=10)
        suppression_list.append(suppression)

        # Intra-list diversity
        tfidf_mat = getattr(recommender, "tfidf_matrix", None)
        ild5 = intra_list_diversity(rec_indices, tfidf_mat, k=5)
        ild10 = intra_list_diversity(rec_indices, tfidf_mat, k=10)
        ild5_list.append(ild5)
        ild10_list.append(ild10)

        # Category alignment
        if user.target_categories:
            target_cats_lower = [c.lower() for c in user.target_categories]
            cats_in_rec = [str(r.get("categories", "")).lower() for r in recs_data]

            def match_cat(rec_cat_str: str) -> bool:
                return any(tc in rec_cat_str for tc in target_cats_lower)

            cat_align5 = sum(1 for c in cats_in_rec[:5] if match_cat(c)) / 5.0
            cat_align10 = sum(1 for c in cats_in_rec[:10] if match_cat(c)) / 10.0
            cat_align5_list.append(cat_align5)
            cat_align10_list.append(cat_align10)

        per_user_results.append(
            {
                "user_id": user.user_id,
                "persona": user.persona_name,
                "recommended_count": len(recommended_isbns),
                "dislike_suppression": suppression,
                "ild@10": round(ild10, 4),
            }
        )

    coverage = catalog_coverage(all_recommended_isbns, total_catalog_size)

    return EvaluationReport(
        model_name=model_name,
        num_users_evaluated=len(cohort),
        precision_at_5=float(np.mean(p5_list)) if p5_list else 0.0,
        precision_at_10=float(np.mean(p10_list)) if p10_list else 0.0,
        recall_at_5=float(np.mean(r5_list)) if r5_list else 0.0,
        recall_at_10=float(np.mean(r10_list)) if r10_list else 0.0,
        ndcg_at_5=float(np.mean(ndcg5_list)) if ndcg5_list else 0.0,
        ndcg_at_10=float(np.mean(ndcg10_list)) if ndcg10_list else 0.0,
        diversity_ild_at_5=float(np.mean(ild5_list)) if ild5_list else 0.0,
        diversity_ild_at_10=float(np.mean(ild10_list)) if ild10_list else 0.0,
        catalog_coverage=coverage,
        dislike_suppression_rate=float(np.mean(suppression_list)) if suppression_list else 1.0,
        category_alignment_at_5=float(np.mean(cat_align5_list)) if cat_align5_list else 0.0,
        category_alignment_at_10=float(np.mean(cat_align10_list)) if cat_align10_list else 0.0,
        per_user_results=per_user_results,
    )
