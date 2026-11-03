from typing import Dict, List

# Derived from real dataset analysis (6,396 books, 547 raw categories).
# Maps raw category strings (lowercase) to canonical display names.
CANONICAL_CATEGORY_MAP: Dict[str, str] = {
    # Fiction
    "fiction": "Fiction",
    "american fiction": "Fiction",
    "english fiction": "Fiction",
    "australian fiction": "Fiction",
    "classical fiction": "Fiction",
    "domestic fiction": "Fiction",
    "general": "Fiction",
    "short stories": "Fiction",
    "short stories, american": "Fiction",
    "experimental fiction": "Fiction",
    "historical fiction": "Fiction",
    "country life": "Fiction",
    "adventure stories": "Fiction",
    "adventure fiction": "Fiction",
    "literary criticism": "Fiction",
    "american literature": "Fiction",
    "literature": "Fiction",
    "novel": "Fiction",
    "novels": "Fiction",
    "christmas stories": "Fiction",
    "folklore": "Fiction",
    "aubrey, jack (fictitious character)": "Fiction",
    "london (england)": "Fiction",  # Setting tag for London-set novels (Orwell's 1984, Faber, Banks, Mosse, Binchy)
    # Fantasy
    "fantasy": "Fantasy",
    "fantasy fiction": "Fantasy",
    "fantasy fiction, american": "Fantasy",
    "arthurian romances": "Fantasy",
    "baggins, frodo (fictitious character)": "Fantasy",
    "discworld (imaginary place)": "Fantasy",
    "epic fantasy": "Fantasy",  # Google Books enrichment key
    "magic": "Fantasy",
    # Science Fiction
    "science fiction": "Science Fiction",
    "sci-fi": "Science Fiction",
    "science fiction, american": "Science Fiction",
    "life on other planets": "Science Fiction",
    "space opera": "Science Fiction",  # Google Books enrichment key
    "dent, arthur (fictitious character)": "Science Fiction",
    "hyland, morn (fictitious character)": "Science Fiction",
    # Mystery & Thriller
    "mystery & thriller": "Mystery & Thriller",
    "mystery": "Mystery & Thriller",
    "crime": "Mystery & Thriller",
    "detective": "Mystery & Thriller",
    "detective and mystery stories": "Mystery & Thriller",
    "detective and mystery stories, english": "Mystery & Thriller",
    "true crime": "Mystery & Thriller",
    "continental op (fictitious character)": "Mystery & Thriller",
    "crime fiction": "Mystery & Thriller",  # Google Books enrichment key
    "thriller": "Mystery & Thriller",  # Google Books enrichment key
    "bond, james (fictitious character)": "Mystery & Thriller",
    "poirot, hercule (fictitious character)": "Mystery & Thriller",
    "marple, jane (fictitious character)": "Mystery & Thriller",
    "beresford, tommy (fictitious character)": "Mystery & Thriller",
    # Horror
    "horror": "Horror",
    "horror tales": "Horror",
    "horror tales, american": "Horror",
    "horror fiction": "Horror",  # Google Books enrichment key
    "ghost stories": "Horror",  # Google Books enrichment key
    # Romance
    "romance": "Romance",
    "man-woman relationships": "Romance",
    "love stories": "Romance",  # Google Books enrichment key
    "chick lit": "Romance",  # Google Books enrichment key
    # Biography & Memoir
    "biography": "Biography & Memoir",
    "autobiography": "Biography & Memoir",
    "biography & memoir": "Biography & Memoir",
    "memoir": "Biography & Memoir",
    "memoirs": "Biography & Memoir",
    "authors, american": "Biography & Memoir",
    "authors, english": "Biography & Memoir",
    "authors": "Biography & Memoir",
    "biography & autobiography": "Biography & Memoir",
    "african americans": "Biography & Memoir",
    "novelists, english": "Biography & Memoir",
    "novelists, american": "Biography & Memoir",
    # History
    "history": "History",
    "africa, east": "History",
    "united states": "History",
    "great britain": "History",
    "england": "History",
    "boston (mass.)": "History",
    "china": "History",
    "japan": "History",
    "europe": "History",
    "australia": "History",
    "americans": "History",
    "british": "History",
    "belgians": "History",
    "botswana": "History",
    "crusades": "History",
    # Philosophy
    "philosophy": "Philosophy",
    # Religion & Spirituality
    "religion": "Religion & Spirituality",
    "religion & spirituality": "Religion & Spirituality",
    "spirituality": "Religion & Spirituality",
    "christian life": "Religion & Spirituality",
    "bible": "Religion & Spirituality",
    "bibles": "Religion & Spirituality",
    # Psychology
    "psychology": "Psychology",
    "body, mind": "Psychology",
    "body, mind & spirit": "Psychology",
    "spirit": "Psychology",
    "family & relationships": "Psychology",
    "families": "Psychology",
    "friendship": "Psychology",
    "brothers": "Psychology",
    "alienation (social psychology)": "Psychology",
    "adultery": "Psychology",
    # Self-Development
    "self-help": "Self-Development",
    "self-development": "Self-Development",
    "conduct of life": "Self-Development",
    "finance, personal": "Self-Development",
    # Business
    "business": "Business",
    "economics": "Business",
    "business enterprises": "Business",
    "capitalism": "Business",
    "business & economics": "Business",
    # Science
    "science": "Science",
    "mathematics": "Science",
    "cosmology": "Science",
    "nature": "Science",
    "animals": "Science",
    "cats": "Science",
    "pets": "Science",
    "agriculture": "Science",
    "arithmetic": "Science",
    # Technology
    "computers": "Technology",
    "technology": "Technology",
    "engineering": "Technology",
    "technology & engineering": "Technology",
    # Comics & Graphic Novels
    "comics": "Comics & Graphic Novels",
    "graphic novels": "Comics & Graphic Novels",
    "graphic novel": "Comics & Graphic Novels",
    "comic books, strips, etc": "Comics & Graphic Novels",
    "comics & graphic novels": "Comics & Graphic Novels",
    # Drama & Plays
    "drama": "Drama & Plays",
    "drama & plays": "Drama & Plays",
    "plays": "Drama & Plays",
    "english drama": "Drama & Plays",
    "performing arts": "Drama & Plays",
    # Poetry
    "poetry": "Poetry",
    "literary collections": "Poetry",
    "american poetry": "Poetry",
    "american essays": "Poetry",
    # Social Sciences
    "social science": "Social Sciences",
    "social sciences": "Social Sciences",
    "political science": "Social Sciences",
    "law": "Social Sciences",
    "city and town life": "Social Sciences",
    # Young Adult & Children
    "young adult & children": "Young Adult & Children",
    "young adult": "Young Adult & Children",
    "children": "Young Adult & Children",
    "children's": "Young Adult & Children",
    "juvenile fiction": "Young Adult & Children",
    "juvenile nonfiction": "Young Adult & Children",
    "children's stories": "Young Adult & Children",
    "children's stories, english": "Young Adult & Children",
    "young adult fiction": "Young Adult & Children",
    "fairy tales": "Young Adult & Children",
    "boys": "Young Adult & Children",
    "children's poetry": "Young Adult & Children",
    "children's poetry, american": "Young Adult & Children",
    # Art & Design
    "art": "Art & Design",
    "art & design": "Art & Design",
    "architecture": "Art & Design",
    "photography": "Art & Design",
    "design": "Art & Design",
    "music": "Art & Design",
    "antiques & collectibles": "Art & Design",
    # Food & Cooking
    "cooking": "Food & Cooking",
    "food & cooking": "Food & Cooking",
    "food": "Food & Cooking",
    "cookery": "Food & Cooking",
    # Travel
    "travel": "Travel",
    # Health & Wellness
    "health": "Health & Wellness",
    "health & wellness": "Health & Wellness",
    "wellness": "Health & Wellness",
    "fitness": "Health & Wellness",
    "medical": "Health & Wellness",
    "health & fitness": "Health & Wellness",
    "blind": "Health & Wellness",
    # Humor & Satire
    "humor": "Humor & Satire",
    "humor & satire": "Humor & Satire",
    "satire": "Humor & Satire",
    "wit and humor": "Humor & Satire",
    "humorous stories, english": "Humor & Satire",
    "american wit and humor, pictorial": "Humor & Satire",
    # Education & Reference
    "education": "Education & Reference",
    "education & reference": "Education & Reference",
    "language arts & disciplines": "Education & Reference",
    "foreign language study": "Education & Reference",
    "reference": "Education & Reference",
    "study aids": "Education & Reference",
    "english language": "Education & Reference",
    "college teachers": "Education & Reference",
    # Sports & Games
    "sports & games": "Sports & Games",
    "sports": "Sports & Games",
    "games": "Sports & Games",
    "games & activities": "Sports & Games",
    "sports & recreation": "Sports & Games",
    # Crafts & Hobbies
    "crafts & hobbies": "Crafts & Hobbies",
    "crafts": "Crafts & Hobbies",
    "hobbies": "Crafts & Hobbies",
    "gardening": "Crafts & Hobbies",
    "house & home": "Crafts & Hobbies",
}


# Canonical display order (by book count in real dataset, desc)
CANONICAL_CATEGORIES_ORDERED: List[str] = [
    "Fiction",
    "Biography & Memoir",
    "Young Adult & Children",
    "History",
    "Comics & Graphic Novels",
    "Business",
    "Psychology",
    "Education & Reference",
    "Health & Wellness",
    "Drama & Plays",
    "Philosophy",
    "Religion & Spirituality",
    "Poetry",
    "Science",
    "Social Sciences",
    "Art & Design",
    "Food & Cooking",
    "Self-Development",
    "Technology",
    "Travel",
    "Mystery & Thriller",
    "Humor & Satire",
    "Fantasy",
    "Science Fiction",
    "Horror",
    "Romance",
    "Sports & Games",
    "Crafts & Hobbies",
]


# ---------------------------------------------------------------------------
# Broad / umbrella subject strings that are NOT sufficient evidence on their
# own to classify a book into a specific enrichment target category.
#
# When Google Books returns ["Fiction", "General"] for a Romance query the
# book CANNOT be accepted as a Romance candidate — only the query origin is
# known, not the actual sub-genre.  Any subjects list whose *only* taxonomy
# hits come from this set yields NEEDS_HUMAN_REVIEW in the enrichment
# pipeline (fetch_candidates.py).
#
# IMPORTANT: This set does NOT modify CANONICAL_CATEGORY_MAP.  Existing
# dataset taxonomy behaviour (6,396 books) is completely unchanged.
# ---------------------------------------------------------------------------
BROAD_SUBJECTS: frozenset[str] = frozenset({
    "fiction",
    "general",
    "books",
    "nonfiction",
    "non-fiction",
    "literature",
    "american fiction",
    "english fiction",
    "australian fiction",
    "classical fiction",
    "domestic fiction",
    "short stories",
    "short stories, american",
    "experimental fiction",
    "historical fiction",
    "country life",
    "adventure stories",
    "literary criticism",
    "american literature",
    "christmas stories",
})
