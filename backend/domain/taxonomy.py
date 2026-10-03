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
        # Fantasy
        "fantasy": "Fantasy",
        "fantasy fiction": "Fantasy",
        "fantasy fiction, american": "Fantasy",
        "arthurian romances": "Fantasy",
        "baggins, frodo (fictitious character)": "Fantasy",
        "discworld (imaginary place)": "Fantasy",
        # Science Fiction
        "science fiction": "Science Fiction",
        "science fiction, american": "Science Fiction",
        "life on other planets": "Science Fiction",
        # Mystery & Thriller
        "detective and mystery stories": "Mystery & Thriller",
        "detective and mystery stories, english": "Mystery & Thriller",
        "true crime": "Mystery & Thriller",
        # Horror
        "horror tales": "Horror",
        "horror tales, american": "Horror",
        # Romance
        "romance": "Romance",
        "man-woman relationships": "Romance",
        # Biography & Memoir
        "biography": "Biography & Memoir",
        "autobiography": "Biography & Memoir",
        "authors, american": "Biography & Memoir",
        "authors, english": "Biography & Memoir",
        "authors": "Biography & Memoir",
        # History
        "history": "History",
        "africa, east": "History",
        "united states": "History",
        "great britain": "History",
        # Philosophy
        "philosophy": "Philosophy",
        # Religion & Spirituality
        "religion": "Religion & Spirituality",
        "christian life": "Religion & Spirituality",
        "bible": "Religion & Spirituality",
        "bibles": "Religion & Spirituality",
        # Psychology
        "psychology": "Psychology",
        "body, mind": "Psychology",
        "spirit": "Psychology",
        # Self-Development
        "self-help": "Self-Development",
        "conduct of life": "Self-Development",
        "finance, personal": "Self-Development",
        # Business
        "business": "Business",
        "economics": "Business",
        "business enterprises": "Business",
        "capitalism": "Business",
        # Science
        "science": "Science",
        "mathematics": "Science",
        "cosmology": "Science",
        "nature": "Science",
        # Technology
        "computers": "Technology",
        "technology": "Technology",
        "engineering": "Technology",
        # Comics & Graphic Novels
        "comics": "Comics & Graphic Novels",
        "graphic novels": "Comics & Graphic Novels",
        "graphic novel": "Comics & Graphic Novels",
        "comic books, strips, etc": "Comics & Graphic Novels",
        # Drama & Plays
        "drama": "Drama & Plays",
        "english drama": "Drama & Plays",
        "performing arts": "Drama & Plays",
        # Poetry
        "poetry": "Poetry",
        "literary collections": "Poetry",
        "american poetry": "Poetry",
        # Social Sciences
        "social science": "Social Sciences",
        "political science": "Social Sciences",
        # Young Adult & Children
        "juvenile fiction": "Young Adult & Children",
        "juvenile nonfiction": "Young Adult & Children",
        "children's stories": "Young Adult & Children",
        "children's stories, english": "Young Adult & Children",
        "young adult fiction": "Young Adult & Children",
        "fairy tales": "Young Adult & Children",
        "boys": "Young Adult & Children",
        # Art & Design
        "art": "Art & Design",
        "architecture": "Art & Design",
        "photography": "Art & Design",
        "design": "Art & Design",
        # Food & Cooking
        "cooking": "Food & Cooking",
        "cookery": "Food & Cooking",
        # Travel
        "travel": "Travel",
        # Health & Wellness
        "health": "Health & Wellness",
        "fitness": "Health & Wellness",
        "medical": "Health & Wellness",
        # Humor & Satire
        "humor": "Humor & Satire",
        "humorous stories, english": "Humor & Satire",
    }


    # Canonical display order (by book count in real dataset, desc)
CANONICAL_CATEGORIES_ORDERED: List[str] = [
        "Fiction",
        "Young Adult & Children",
        "History",
        "Drama & Plays",
        "Philosophy",
        "Religion & Spirituality",
        "Poetry",
        "Science",
        "Social Sciences",
        "Art & Design",
        "Food & Cooking",
        "Psychology",
        "Self-Development",
        "Technology",
        "Travel",
        "Mystery & Thriller",
        "Humor & Satire",
        "Fantasy",
        "Health & Wellness",
        "Biography & Memoir",
        "Science Fiction",
        "Horror",
        "Comics & Graphic Novels",
        "Romance",
        "Business",
    ]
