"""
Ranking and diversity metrics for offline recommendation evaluation.
"""

import math
from typing import Any, List, Set

from sklearn.metrics.pairwise import cosine_similarity


def precision_at_k(recommended: List[str], ground_truth: Set[str], k: int = 10) -> float:
    """Calculate Precision@K: proportion of recommended items in top-K that are relevant."""
    if k <= 0 or not recommended:
        return 0.0
    rec_k = recommended[:k]
    hits = sum(1 for item in rec_k if item in ground_truth)
    return hits / float(k)


def recall_at_k(recommended: List[str], ground_truth: Set[str], k: int = 10) -> float:
    """Calculate Recall@K: proportion of relevant items retrieved in top-K."""
    if not ground_truth or not recommended or k <= 0:
        return 0.0
    rec_k = recommended[:k]
    hits = sum(1 for item in rec_k if item in ground_truth)
    return hits / float(len(ground_truth))


def ndcg_at_k(recommended: List[str], ground_truth: Set[str], k: int = 10) -> float:
    """
    Calculate Normalized Discounted Cumulative Gain at K (NDCG@K).
    Uses binary relevance (1 if in ground_truth, 0 otherwise).
    """
    if not ground_truth or not recommended or k <= 0:
        return 0.0

    rec_k = recommended[:k]
    dcg = 0.0
    for i, item in enumerate(rec_k):
        if item in ground_truth:
            dcg += 1.0 / math.log2(i + 2)  # i=0 -> log2(2) = 1.0

    # Ideal DCG (all hits at the top)
    ideal_hits = min(k, len(ground_truth))
    idcg = sum(1.0 / math.log2(i + 2) for i in range(ideal_hits))

    return dcg / idcg if idcg > 0.0 else 0.0


def dislike_suppression_rate(recommended: List[str], dislikes: Set[str], k: int = 10) -> float:
    """
    Calculate Dislike Suppression Rate:
    Returns 1.0 if zero disliked items leaked into top-K, 0.0 if all disliked items leaked.
    """
    if not dislikes:
        return 1.0
    rec_k = recommended[:k]
    leaked = sum(1 for item in rec_k if item in dislikes)
    return 1.0 if leaked == 0 else max(0.0, 1.0 - (leaked / float(len(dislikes))))


def intra_list_diversity(
    recommended_indices: List[int],
    tfidf_matrix: Any,
    k: int = 10,
) -> float:
    """
    Calculate Intra-List Diversity (ILD) at K:
    Average pairwise cosine distance (1 - cos_sim) among unique items in top-K.
    Higher ILD indicates greater topic and content diversity.
    """
    indices = [idx for idx in recommended_indices[:k] if idx is not None]
    n = len(indices)
    if n < 2 or tfidf_matrix is None:
        return 0.0

    sub_matrix = tfidf_matrix[indices]
    sim_matrix = cosine_similarity(sub_matrix)

    # Compute average pairwise distance for upper triangle
    total_dist = 0.0
    pair_count = 0
    for i in range(n):
        for j in range(i + 1, n):
            total_dist += 1.0 - float(sim_matrix[i, j])
            pair_count += 1

    return total_dist / float(pair_count) if pair_count > 0 else 0.0


def catalog_coverage(all_recommended_isbns: Set[str], total_catalog_size: int) -> float:
    """Calculate Catalog Coverage: fraction of unique catalog items recommended across users."""
    if total_catalog_size <= 0:
        return 0.0
    return len(all_recommended_isbns) / float(total_catalog_size)
