from __future__ import annotations

import sys
from pathlib import Path

_BACKEND_DIR = Path(__file__).resolve().parent.parent
if str(_BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(_BACKEND_DIR))

from domain.taxonomy import (  # noqa: E402
    BROAD_SUBJECTS,
    CANONICAL_CATEGORIES_ORDERED,
    CANONICAL_CATEGORY_MAP,
)
from scripts.fetch_candidates import classify_category  # noqa: E402


def _classify(subjects, expected):
    return classify_category(subjects, expected)


class TestBroadSubjectsOnlyReturnNeedsHumanReview:
    def test_case1_fiction_general_for_romance(self):
        canonical, confidence = _classify(["Fiction", "General"], "Romance")
        assert canonical == "NEEDS_HUMAN_REVIEW"

    def test_case1_fiction_general_for_horror(self):
        canonical, _ = _classify(["Fiction", "General"], "Horror")
        assert canonical == "NEEDS_HUMAN_REVIEW"

    def test_case1_fiction_general_for_science_fiction(self):
        canonical, _ = _classify(["Fiction", "General"], "Science Fiction")
        assert canonical == "NEEDS_HUMAN_REVIEW"

    def test_case1_fiction_general_for_fantasy(self):
        canonical, _ = _classify(["Fiction", "General"], "Fantasy")
        assert canonical == "NEEDS_HUMAN_REVIEW"

    def test_case1_fiction_general_for_mystery(self):
        canonical, _ = _classify(["Fiction", "General"], "Mystery & Thriller")
        assert canonical == "NEEDS_HUMAN_REVIEW"


def test_case2_romance_fiction_classifies_as_romance():
    canonical, _ = _classify(["Romance", "Fiction"], "Romance")
    assert canonical == "Romance"


def test_case3_horror_fiction_classifies_as_horror():
    canonical, _ = _classify(["Horror Fiction", "Fiction"], "Horror")
    assert canonical == "Horror"


def test_case4_science_fiction_classifies_correctly():
    canonical, _ = _classify(["Science Fiction", "Fiction"], "Science Fiction")
    assert canonical == "Science Fiction"


def test_case5_fantasy_fiction_classifies_as_fantasy():
    canonical, _ = _classify(["Fantasy", "Fiction"], "Fantasy")
    assert canonical == "Fantasy"


def test_case6_thriller_fiction_classifies_as_mystery_thriller():
    canonical, _ = _classify(["Thriller", "Fiction"], "Mystery & Thriller")
    assert canonical == "Mystery & Thriller"


def test_case7_books_general_needs_human_review():
    canonical, _ = _classify(["Books", "General"], "Romance")
    assert canonical == "NEEDS_HUMAN_REVIEW"


class TestEdgeCases:
    def test_empty_subjects(self):
        canonical, confidence = _classify([], "Romance")
        assert canonical == "NEEDS_HUMAN_REVIEW"
        assert confidence == "NEEDS_HUMAN_REVIEW"

    def test_unknown_subjects_only(self):
        canonical, _ = _classify(["Underwater Basket Weaving"], "Fantasy")
        assert canonical == "NEEDS_HUMAN_REVIEW"

    def test_fiction_alone_is_broad(self):
        canonical, _ = _classify(["Fiction"], "Romance")
        assert canonical == "NEEDS_HUMAN_REVIEW"

    def test_general_alone_is_broad(self):
        canonical, _ = _classify(["General"], "Horror")
        assert canonical == "NEEDS_HUMAN_REVIEW"

    def test_romance_with_ambiguous_subjects_still_classifies(self):
        canonical, _ = _classify(["Romance", "Love"], "Romance")
        assert canonical == "Romance"

    def test_horror_fiction_subject_key(self):
        canonical, _ = _classify(["horror fiction"], "Horror")
        assert canonical == "Horror"

    def test_love_stories_subject_key(self):
        canonical, _ = _classify(["love stories"], "Romance")
        assert canonical == "Romance"


class TestDatasetSafety:
    def test_general_still_maps_to_fiction(self):
        assert CANONICAL_CATEGORY_MAP.get("general") == "Fiction"

    def test_fiction_still_maps_to_fiction(self):
        assert CANONICAL_CATEGORY_MAP.get("fiction") == "Fiction"

    def test_romance_maps_to_romance(self):
        assert CANONICAL_CATEGORY_MAP.get("romance") == "Romance"

    def test_horror_fiction_maps_to_horror(self):
        assert CANONICAL_CATEGORY_MAP.get("horror fiction") == "Horror"

    def test_thriller_maps_to_mystery_thriller(self):
        assert CANONICAL_CATEGORY_MAP.get("thriller") == "Mystery & Thriller"

    def test_science_fiction_maps_correctly(self):
        assert CANONICAL_CATEGORY_MAP.get("science fiction") == "Science Fiction"

    def test_fantasy_maps_to_fantasy(self):
        assert CANONICAL_CATEGORY_MAP.get("fantasy") == "Fantasy"

    def test_all_canonical_categories_present(self):
        expected = {
            "Fiction", "Fantasy", "Science Fiction", "Mystery & Thriller",
            "Horror", "Romance", "Biography & Memoir", "History",
            "Philosophy", "Religion & Spirituality", "Psychology",
            "Self-Development", "Business", "Science", "Technology",
            "Comics & Graphic Novels", "Drama & Plays", "Poetry",
            "Social Sciences", "Young Adult & Children", "Art & Design",
            "Food & Cooking", "Travel", "Health & Wellness",
            "Humor & Satire", "Education & Reference",
            "Sports & Games", "Crafts & Hobbies",
        }
        actual = set(CANONICAL_CATEGORIES_ORDERED)
        missing = expected - actual
        assert not missing, f"Missing from CANONICAL_CATEGORIES_ORDERED: {missing}"


class TestBroadSubjectsSet:
    def test_broad_subjects_is_frozenset(self):
        assert isinstance(BROAD_SUBJECTS, frozenset)

    def test_required_broad_subjects_present(self):
        required = {"fiction", "general", "books", "nonfiction", "literature"}
        missing = required - BROAD_SUBJECTS
        assert not missing, f"Missing from BROAD_SUBJECTS: {missing}"

    def test_romance_not_in_broad_subjects(self):
        assert "romance" not in BROAD_SUBJECTS

    def test_horror_not_in_broad_subjects(self):
        assert "horror" not in BROAD_SUBJECTS

    def test_fantasy_not_in_broad_subjects(self):
        assert "fantasy" not in BROAD_SUBJECTS

    def test_science_fiction_not_in_broad_subjects(self):
        assert "science fiction" not in BROAD_SUBJECTS

    def test_thriller_not_in_broad_subjects(self):
        assert "thriller" not in BROAD_SUBJECTS


class TestTaxonomyRegression:
    def test_case1_fiction_romance_contemporary(self):
        canonical, _ = _classify(["Fiction", "Romance", "Contemporary"], "Romance")
        assert canonical == "Romance"

    def test_case2_fiction_horror(self):
        canonical, _ = _classify(["Fiction", "Horror"], "Horror")
        assert canonical == "Horror"

    def test_case3_fiction_fantasy(self):
        canonical, _ = _classify(["Fiction", "Fantasy"], "Fantasy")
        assert canonical == "Fantasy"

    def test_case4_fiction_science_fiction(self):
        canonical, _ = _classify(["Fiction", "Science Fiction"], "Science Fiction")
        assert canonical == "Science Fiction"

    def test_case5_fiction_thriller(self):
        canonical, _ = _classify(["Fiction", "Thriller"], "Mystery & Thriller")
        assert canonical == "Mystery & Thriller"

    def test_case6_fiction_general(self):
        canonical, _ = _classify(["Fiction", "General"], "Romance")
        assert canonical == "NEEDS_HUMAN_REVIEW"

    def test_case7_fiction(self):
        canonical, _ = _classify(["Fiction"], "Romance")
        assert canonical == "NEEDS_HUMAN_REVIEW"

    def test_case8_romance_fiction(self):
        canonical, _ = _classify(["Romance", "Fiction"], "Romance")
        assert canonical == "Romance"

    def test_case9_horror_stories_fiction(self):
        canonical, _ = _classify(["Horror Stories", "Fiction"], "Horror")
        assert canonical == "Horror"

    def test_case10_contemporary_fiction_romance(self):
        canonical, _ = _classify(["Contemporary Fiction", "Romance"], "Romance")
        assert canonical == "Romance"
