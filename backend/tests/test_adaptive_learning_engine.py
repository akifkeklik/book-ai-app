import unittest
from typing import Any, Dict, List, Optional

from backend.application.use_cases.interactions import ResetPreferencesUseCase
from backend.application.use_cases.recommendations import (
    GetPersonalizedRecommendationsUseCase,
)
from backend.infrastructure.ml.recommender import BookRecommender


class FakeEnrichmentService:
    def enrich(self, books: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        return books


class MockInteractionRepo:
    def __init__(self):
        self.interactions: Dict[str, List[Dict[str, Any]]] = {}
        self.profiles: Dict[str, Dict[str, Any]] = {}
        self.favorites: Dict[str, List[Dict[str, Any]]] = {}

    def get_user_interactions(self, user_id: str) -> List[Dict[str, Any]]:
        return list(self.interactions.get(user_id, []))

    def get_user_favorites(self, user_id: str) -> List[Dict[str, Any]]:
        return list(self.favorites.get(user_id, []))

    def get_user_profile(self, user_id: str) -> Optional[Dict[str, Any]]:
        return self.profiles.get(user_id)

    def upsert_interactions(self, entries: List[Dict[str, Any]]) -> None:
        for entry in entries:
            uid = entry["user_id"]
            bid = entry["book_id"]
            itype = entry.get("interaction_type")
            if uid not in self.interactions:
                self.interactions[uid] = []
            # Remove prior interaction for same book if not multiple
            self.interactions[uid] = [i for i in self.interactions[uid] if i["book_id"] != bid]
            self.interactions[uid].append(entry)
            if itype == "favorite":
                if uid not in self.favorites:
                    self.favorites[uid] = []
                self.favorites[uid] = [f for f in self.favorites[uid] if f["book_id"] != bid]
                self.favorites[uid].append(entry)

    def upsert_profile(self, user_id: str, genres: List[str], updated_at: str, authors: Optional[List[str]] = None) -> None:
        self.profiles[user_id] = {
            "preferred_genres": genres,
            "preferred_authors": authors or [],
            "updated_at": updated_at,
        }

    def delete_interaction(self, user_id: str, book_id: str, interaction_type: Optional[str] = None) -> None:
        if user_id in self.interactions:
            self.interactions[user_id] = [i for i in self.interactions[user_id] if i["book_id"] != book_id]
        if user_id in self.favorites:
            self.favorites[user_id] = [f for f in self.favorites[user_id] if f["book_id"] != book_id]

    def delete_all_user_interactions(self, user_id: str) -> None:
        self.interactions[user_id] = []
        self.favorites[user_id] = []


class MockNoteRepo:
    def __init__(self):
        self.notes: Dict[str, List[Dict[str, Any]]] = {}

    def get_user_notes(self, user_id: str, limit: int = 50, **kwargs) -> List[Dict[str, Any]]:
        return self.notes.get(user_id, [])[:limit]

    def add_note(self, user_id: str, book_id: str, note_type: str, content: str):
        if user_id not in self.notes:
            self.notes[user_id] = []
        self.notes[user_id].append({
            "id": f"note-{len(self.notes[user_id])}",
            "user_id": user_id,
            "book_id": book_id,
            "note_type": note_type,
            "content": content,
        })


class TestAdaptiveLearningEngine(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.catalog = [
            {"isbn13": "9781000000001", "title": "Machine Learning Fundamentals", "authors": "Alice Smith", "categories": "Computer Science", "description": "Intro to neural networks and ML basics", "average_rating": 4.8, "ratings_count": 1000, "popularity_score": 0.95},
            {"isbn13": "9781000000002", "title": "Deep Learning Principles", "authors": "Alice Smith", "categories": "Computer Science", "description": "Advanced deep learning architectures and backpropagation", "average_rating": 4.9, "ratings_count": 800, "popularity_score": 0.92},
            {"isbn13": "9781000000003", "title": "Data Structures in Python", "authors": "Bob Jones", "categories": "Computer Science", "description": "Algorithms and data structures practical guide", "average_rating": 4.5, "ratings_count": 600, "popularity_score": 0.85},
            {"isbn13": "9781000000004", "title": "Fantasy World Epic", "authors": "Carol White", "categories": "Fantasy", "description": "Dragons magic kingdom adventure quest", "average_rating": 4.7, "ratings_count": 1200, "popularity_score": 0.90},
            {"isbn13": "9781000000005", "title": "The Mage Guild", "authors": "Carol White", "categories": "Fantasy", "description": "Spells wizards magical battles", "average_rating": 4.6, "ratings_count": 700, "popularity_score": 0.88},
            {"isbn13": "9781000000006", "title": "Historical Ottoman Empire", "authors": "David Black", "categories": "History", "description": "Ottoman centuries chronicles and sultan eras", "average_rating": 4.4, "ratings_count": 400, "popularity_score": 0.80},
        ]
        cls.engine = BookRecommender()
        cls.engine.load_from_dicts(cls.catalog)
        cls.engine.fit()

    def setUp(self):
        self.interaction_repo = MockInteractionRepo()
        self.note_repo = MockNoteRepo()
        self.enrichment = FakeEnrichmentService()
        self.uc = GetPersonalizedRecommendationsUseCase(
            recommender=self.engine,
            interaction_repo=self.interaction_repo,
            book_data_port=None,
            enrichment_service=self.enrichment,
            note_repo=self.note_repo,
        )

    def test_cold_start_fallback_and_diagnostics(self):
        """Phase 1 & 10: New user receives valid cold-start catalog fallback with correct diagnostics."""
        result = self.uc.execute(
            user_id="user-newbie",
            limit=3,
            include_diagnostics=True,
        )
        self.assertIsInstance(result, dict)
        self.assertTrue(result["is_cold_start"])
        self.assertEqual(result["evidence_coverage"], "cold_start")
        self.assertIn("diagnostics", result)
        self.assertEqual(result["diagnostics"]["engine_version"], "2.6.0")
        self.assertEqual(len(result["recommendations"]), 3)
        for r in result["recommendations"]:
            self.assertTrue(r["is_cold_start"])
            self.assertEqual(r["confidence"], "cold_start")
            self.assertEqual(r["explanation_type"], "trending_catalog")

    def test_strict_dislike_suppression(self):
        """Phase 1: Negative signal strictly suppresses disliked book and prevents leakage."""
        user_id = "user-negative-tester"
        # Seed user with machine learning interest
        self.interaction_repo.upsert_interactions([
            {"user_id": user_id, "book_id": "9781000000001", "interaction_type": "like"},
            {"user_id": user_id, "book_id": "9781000000002", "interaction_type": "dislike"},
        ])

        recs = self.uc.execute(user_id=user_id, limit=5)
        isbns = [r["isbn13"] for r in recs]

        # 9781000000002 was disliked, must NEVER leak
        self.assertNotIn("9781000000002", isbns)
        # Seed 9781000000001 is already consumed so not recommended
        self.assertNotIn("9781000000001", isbns)
        # Relevant sibling book 9781000000003 should be surfaced
        self.assertIn("9781000000003", isbns)

    def test_completed_book_exclusion_when_requested(self):
        """Phase 1: When exclude_completed=True, finished books are strictly suppressed."""
        user_id = "user-completed-filter"
        self.interaction_repo.upsert_interactions([
            {"user_id": user_id, "book_id": "9781000000001", "interaction_type": "finished"},
            {"user_id": user_id, "book_id": "9781000000003", "interaction_type": "finished"},
        ])

        profile = self.uc.build_user_preference_profile(user_id)
        self.assertIn("9781000000001", profile.completed_isbns)
        self.assertIn("9781000000003", profile.completed_isbns)

        recs = self.uc.execute(user_id=user_id, limit=5, exclude_completed=True)
        isbns = [r["isbn13"] for r in recs]
        self.assertNotIn("9781000000001", isbns)
        self.assertNotIn("9781000000003", isbns)

    def test_ranking_determinism(self):
        """Phase 1: Equivalent input profiles produce 100% deterministic ranking."""
        user_id = "user-determinism"
        self.interaction_repo.upsert_interactions([
            {"user_id": user_id, "book_id": "9781000000004", "interaction_type": "favorite"},
        ])

        run_1 = self.uc.execute(user_id=user_id, limit=3)
        run_2 = self.uc.execute(user_id=user_id, limit=3)

        self.assertEqual([r["isbn13"] for r in run_1], [r["isbn13"] for r in run_2])
        self.assertEqual([r.get("final_score") for r in run_1], [r.get("final_score") for r in run_2])

    def test_cross_user_isolation(self):
        """Phase 2 & 6: User A's feedback and profile never pollute User B's recommendations."""
        user_a = "user-alpha"
        user_b = "user-beta"

        # User A loves Fantasy and dislikes Computer Science
        self.interaction_repo.upsert_interactions([
            {"user_id": user_a, "book_id": "9781000000004", "interaction_type": "favorite"},
            {"user_id": user_a, "book_id": "9781000000001", "interaction_type": "dislike"},
        ])

        # User B loves Computer Science and dislikes Fantasy
        self.interaction_repo.upsert_interactions([
            {"user_id": user_b, "book_id": "9781000000001", "interaction_type": "favorite"},
            {"user_id": user_b, "book_id": "9781000000004", "interaction_type": "dislike"},
        ])

        recs_a = self.uc.execute(user_id=user_a, limit=3)
        recs_b = self.uc.execute(user_id=user_b, limit=3)

        isbns_a = [r["isbn13"] for r in recs_a]
        isbns_b = [r["isbn13"] for r in recs_b]

        # User A should NOT receive disliked book 9781000000001
        self.assertNotIn("9781000000001", isbns_a)
        # User B should receive 9781000000002 or 9781000000003
        self.assertNotIn("9781000000004", isbns_b)

    def test_user_preference_profile_derivation_and_reset(self):
        """Phase 2 & 3: Profile derives correct stats and reset clears user data."""
        user_id = "user-privacy-reset"
        self.interaction_repo.upsert_interactions([
            {"user_id": user_id, "book_id": "9781000000001", "interaction_type": "like"},
            {"user_id": user_id, "book_id": "9781000000004", "interaction_type": "dislike"},
        ])
        self.note_repo.add_note(user_id, "9781000000001", "key_takeaway", "Important concept")

        profile = self.uc.build_user_preference_profile(user_id)
        self.assertEqual(profile.positive_signal_count, 1)
        self.assertEqual(profile.negative_signal_count, 1)
        self.assertEqual(profile.takeaway_count, 1)
        self.assertEqual(profile.evidence_coverage, "emerging")

        reset_uc = ResetPreferencesUseCase(self.interaction_repo)
        res = reset_uc.execute(user_id=user_id)
        self.assertEqual(res["status"], "success")

        # After reset, interactions are cleared; clear notes for cold start verification
        self.note_repo.notes[user_id] = []
        reset_profile = self.uc.build_user_preference_profile(user_id)
        self.assertEqual(reset_profile.positive_signal_count, 0)
        self.assertEqual(reset_profile.negative_signal_count, 0)
        self.assertEqual(reset_profile.evidence_coverage, "cold_start")

    def test_honest_explanation_contract(self):
        """Phase 4: Explanation fields are typed, non-empty, and backed by actual signals."""
        user_id = "user-explanation-tester"
        self.interaction_repo.upsert_interactions([
            {"user_id": user_id, "book_id": "9781000000001", "interaction_type": "favorite"},
        ])

        recs = self.uc.execute(user_id=user_id, limit=2)
        self.assertTrue(len(recs) > 0)
        top = recs[0]
        self.assertIn("explanation_type", top)
        self.assertIn(top["explanation_type"], [
            "favorite_book", "liked_book", "category_affinity", "author_affinity", "trending_catalog"
        ])
        self.assertIn("confidence", top)
        self.assertIn(top["confidence"], ["high", "medium", "cold_start"])
        self.assertIn("recommendation_reason", top)
        self.assertTrue(len(top["recommendation_reason"]) > 0)


    def test_comprehensive_evaluation_metrics(self):
        """Phase 9 & 13: Comprehensive fixture-based quantitative evaluation suite."""
        valid_catalog_isbns = set(b["isbn13"] for b in self.catalog)

        # 1. Leakage test across multiple synthetic personas
        personas = [
            {"uid": "eval-p1", "dislikes": ["9781000000001", "9781000000004"], "finished": ["9781000000002"], "favs": ["9781000000003"]},
            {"uid": "eval-p2", "dislikes": ["9781000000005"], "finished": ["9781000000006"], "favs": ["9781000000004"]},
            {"uid": "eval-p3", "dislikes": ["9781000000002", "9781000000003"], "finished": ["9781000000001"], "favs": []},
        ]

        disliked_leak_count = 0
        completed_leak_count = 0
        duplicate_count = 0
        invalid_catalog_count = 0
        valid_explanation_count = 0
        total_eval_recs = 0

        for p in personas:
            uid = p["uid"]
            entries = []
            for d in p["dislikes"]:
                entries.append({"user_id": uid, "book_id": d, "interaction_type": "dislike"})
            for f in p["finished"]:
                entries.append({"user_id": uid, "book_id": f, "interaction_type": "finished"})
            for fv in p["favs"]:
                entries.append({"user_id": uid, "book_id": fv, "interaction_type": "favorite"})
            if entries:
                self.interaction_repo.upsert_interactions(entries)

            recs = self.uc.execute(user_id=uid, limit=4, exclude_completed=True)
            total_eval_recs += len(recs)

            seen = set()
            for r in recs:
                isbn = r["isbn13"]
                # Disliked leakage
                if isbn in p["dislikes"]:
                    disliked_leak_count += 1
                # Completed leakage
                if isbn in p["finished"]:
                    completed_leak_count += 1
                # Duplicate rate
                if isbn in seen:
                    duplicate_count += 1
                seen.add(isbn)
                # Invalid catalog rate
                if isbn not in valid_catalog_isbns:
                    invalid_catalog_count += 1
                # Explanation validity
                exp_type = r.get("explanation_type")
                if exp_type in (
                    "liked_book", "favorite_book", "finished_book", "reading_journey",
                    "takeaway_affinity", "category_affinity", "author_affinity",
                    "trending_catalog"
                ):
                    valid_explanation_count += 1

        disliked_leakage_rate = (disliked_leak_count / max(1, total_eval_recs)) * 100.0
        completed_leakage_rate = (completed_leak_count / max(1, total_eval_recs)) * 100.0
        duplicate_rate = (duplicate_count / max(1, total_eval_recs)) * 100.0
        invalid_catalog_rate = (invalid_catalog_count / max(1, total_eval_recs)) * 100.0
        explanation_validity_rate = (valid_explanation_count / max(1, total_eval_recs)) * 100.0

        # Assert zero leakage and 100% contract compliance
        self.assertEqual(disliked_leakage_rate, 0.0, f"Disliked leakage detected: {disliked_leakage_rate}%")
        self.assertEqual(completed_leakage_rate, 0.0, f"Completed leakage detected: {completed_leakage_rate}%")
        self.assertEqual(duplicate_rate, 0.0, f"Duplicates detected: {duplicate_rate}%")
        self.assertEqual(invalid_catalog_rate, 0.0, f"Invalid catalog candidates detected: {invalid_catalog_rate}%")
        self.assertEqual(explanation_validity_rate, 100.0, f"Invalid explanations: {explanation_validity_rate}%")


if __name__ == "__main__":
    unittest.main()
