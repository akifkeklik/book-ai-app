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


def duplicate_result_rate(recommended: List[str], k: int = 10) -> float:
    """
    Calculate Duplicate Result Rate:
    Proportion of recommended items in top-K that are duplicate entries.
    Target: 0.0 (no duplicate items).
    """
    if not recommended or k <= 0:
        return 0.0
    rec_k = recommended[:k]
    if not rec_k:
        return 0.0
    duplicates = len(rec_k) - len(set(rec_k))
    return float(duplicates) / float(len(rec_k))


def seed_leakage_rate(recommended: List[str], seed_items: Set[str], k: int = 10) -> float:
    """
    Calculate Seed-Item Leakage Rate:
    Proportion of recommended items in top-K that were input training seeds.
    Target: 0.0 (user is not recommended books they already provided as seeds).
    """
    if not recommended or not seed_items or k <= 0:
        return 0.0
    rec_k = recommended[:k]
    if not rec_k:
        return 0.0
    clean_seeds = set(str(s).strip().replace("-", "").lower() for s in seed_items if str(s).strip())
    leaked = sum(1 for item in rec_k if str(item).strip().replace("-", "").lower() in clean_seeds)
    return float(leaked) / float(len(rec_k))


def disliked_violation_rate(recommended: List[str], dislikes: Set[str], k: int = 10) -> float:
    """
    Calculate Disliked-Item Violation Rate:
    Proportion of recommended items in top-K that violate explicit user dislikes.
    Target: 0.0 (zero disliked items recommended).
    """
    if not recommended or not dislikes or k <= 0:
        return 0.0
    rec_k = recommended[:k]
    if not rec_k:
        return 0.0
    clean_dislikes = set(str(d).strip().replace("-", "").lower() for d in dislikes if str(d).strip())
    violations = sum(1 for item in rec_k if str(item).strip().replace("-", "").lower() in clean_dislikes)
    return float(violations) / float(len(rec_k))



# ── Graded relevance metrics (query-to-item and seed-to-item retrieval) ──────
#
# These operate on ranked lists of *work ids* (edition-aware identities, see
# evaluation/retrieval/catalog.py) and graded judgments {work_id: 0|1|2}.
# Repeated work ids in a ranked list earn no gain after their first occurrence,
# so duplicate editions cannot inflate a score. Unjudged items count as 0 and
# are surfaced separately through judged_at_k().


def _dedup_gains(ranked: List[str], grades: dict, k: int) -> List[int]:
    seen: Set[str] = set()
    gains: List[int] = []
    for item in ranked[:k]:
        if item in seen:
            gains.append(0)
            continue
        seen.add(item)
        gains.append(int(grades.get(item, 0)))
    return gains


def graded_precision_at_k(ranked: List[str], grades: dict, k: int = 5, min_grade: int = 1) -> float:
    """Fraction of the k slots holding a distinct item with grade >= min_grade."""
    if k <= 0:
        return 0.0
    return sum(1 for g in _dedup_gains(ranked, grades, k) if g >= min_grade) / float(k)


def graded_recall_at_k(ranked: List[str], grades: dict, k: int = 5, min_grade: int = 1) -> float:
    """Recall over the judged relevant set; only meaningful when that set is complete."""
    relevant = {i for i, g in grades.items() if g >= min_grade}
    if not relevant:
        return 0.0
    hits = {i for i in ranked[:k] if i in relevant}
    return len(hits) / float(len(relevant))


def mean_reciprocal_rank(ranked: List[str], grades: dict, k: int = 10, min_grade: int = 1) -> float:
    """1/rank of the first item with grade >= min_grade within the top k (0 if none)."""
    for pos, g in enumerate(_dedup_gains(ranked, grades, k), start=1):
        if g >= min_grade:
            return 1.0 / pos
    return 0.0


def graded_ndcg_at_k(ranked: List[str], grades: dict, k: int = 5) -> float:
    """nDCG@k with exponential gain (2^grade - 1); ideal ranking built from all judgments."""
    gains = _dedup_gains(ranked, grades, k)
    dcg = sum((2**g - 1) / math.log2(i + 2) for i, g in enumerate(gains))
    ideal = sorted((int(g) for g in grades.values() if int(g) > 0), reverse=True)[:k]
    idcg = sum((2**g - 1) / math.log2(i + 2) for i, g in enumerate(ideal))
    return dcg / idcg if idcg > 0 else 0.0


def judged_at_k(ranked: List[str], grades: dict, k: int = 5) -> float:
    """Fraction of the top-k that has a judgment; low values mean the metric is unreliable."""
    top = ranked[:k]
    if not top:
        return 0.0
    return sum(1 for i in top if i in grades) / float(len(top))


def intra_list_distance(items: List[Any], distance, k: int = 5) -> float:
    """Mean pairwise distance(a, b) over the top-k items, for any distance function."""
    top = items[:k]
    pairs = [(a, b) for i, a in enumerate(top) for b in top[i + 1:]]
    if not pairs:
        return 0.0
    return sum(distance(a, b) for a, b in pairs) / float(len(pairs))
