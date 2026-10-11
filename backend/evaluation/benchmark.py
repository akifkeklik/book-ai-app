"""
CLI Benchmark Runner for Libris Recommendation Engine.

Executes offline evaluation pipeline against backend/data/books.csv
and outputs comparative ranking, diversity, and suppression metrics.
"""

import json
import logging
import os
import sys

# Ensure repository root is on sys.path
repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
if repo_root not in sys.path:
    sys.path.insert(0, repo_root)

from backend.application.use_cases.recommendations import (  # noqa: E402
    GetPersonalizedRecommendationsUseCase,
)
from backend.evaluation.dataset import build_evaluation_cohort  # noqa: E402
from backend.evaluation.evaluator import evaluate_cohort  # noqa: E402
from backend.infrastructure.ml.recommender import BookRecommender  # noqa: E402

logging.basicConfig(level=logging.WARNING)


class MockInteractionRepository:
    """In-memory repository for evaluation."""

    def __init__(self):
        self._user_interactions = {}
        self._user_profiles = {}

    def set_user_data(self, user_id: str, interactions: list, profile: dict):
        self._user_interactions[user_id] = interactions
        self._user_profiles[user_id] = profile

    def get_user_interactions(self, user_id: str):
        return self._user_interactions.get(user_id, [])

    def get_user_profile(self, user_id: str):
        return self._user_profiles.get(user_id, None)

    def upsert_interactions(self, entries):
        pass

    def upsert_profile(self, user_id, genres, updated_at):
        pass

    def track_activity(self, payload):
        pass


class PassthroughEnrichment:
    def enrich(self, books):
        return books


def run_benchmark():
    data_path = os.path.join(repo_root, "backend", "data", "books.csv")
    if not os.path.exists(data_path):
        print(f"Error: Data file not found at {data_path}")
        sys.exit(1)

    print("=" * 70)
    print(" LIBRIS OFFLINE RECOMMENDATION BENCHMARK EVALUATION")
    print("=" * 70)
    print(f"Loading catalog dataset from: {data_path}")

    recommender = BookRecommender()
    recommender.load_data(data_path)
    recommender.fit()

    cohort = build_evaluation_cohort(recommender.df)
    print(f"Built deterministic evaluation cohort of {len(cohort)} personas.")
    print("Train/Test split: 60% train positive seeds / 40% holdout ground-truth.")
    print("-" * 70)

    mock_repo = MockInteractionRepository()
    use_case = GetPersonalizedRecommendationsUseCase(
        recommender=recommender,
        interaction_repo=mock_repo,
        book_data_port=None,
        enrichment_service=PassthroughEnrichment(),
    )

    report = evaluate_cohort(
        recommender=recommender,
        cohort=cohort,
        model_name="Libris Production Recommender",
        use_case=use_case,
        mock_repo=mock_repo,
    )

    print("\nRESULTS SUMMARY:")
    metrics = report.to_dict()
    for k, v in metrics.items():
        print(f"  {k:<28}: {v}")
    print("=" * 70)

    output_dir = os.path.join(repo_root, "backend", "evaluation", "reports")
    os.makedirs(output_dir, exist_ok=True)
    report_path = os.path.join(output_dir, "benchmark_report.json")
    with open(report_path, "w") as f:
        json.dump(metrics, f, indent=2)
    print(f"Report saved to: {report_path}\n")
    return report


if __name__ == "__main__":
    run_benchmark()
