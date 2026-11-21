"""
Text preprocessing utilities for the TF-IDF recommendation engine.
All functions are pure and stateless for easy testing.
"""

import math
import re
import unicodedata
from typing import Optional

import pandas as pd

# ─────────────────────────────────────────────────────────────────────────────
# Text helpers
# ─────────────────────────────────────────────────────────────────────────────


def clean_text(text: str) -> str:
    """Lowercase, strip HTML tags, collapse special chars and whitespace."""
    if not text or not isinstance(text, str):
        return ""
    text = text.lower()
    text = re.sub(r"<[^>]+>", " ", text)  # strip HTML
    text = re.sub(r"[^a-z0-9\s]", " ", text)  # keep alphanumeric
    text = re.sub(r"\s+", " ", text).strip()
    return text


def normalize_isbn(value) -> str:
    """Canonical ISBN string: no hyphens/spaces, no float suffix ('9780…0.0'), upper-case X."""
    if value is None or (isinstance(value, float) and math.isnan(value)):
        return ""
    if isinstance(value, float) and value.is_integer():
        value = int(value)
    text = str(value).strip().replace("-", "").replace(" ", "").upper()
    return text[:-2] if text.endswith(".0") else text


def _fold(text: str) -> str:
    """Case- and accent-insensitive form, keeping letters and digits of any script."""
    text = str(text or "").replace("İ", "i").casefold()
    text = "".join(c for c in unicodedata.normalize("NFKD", text) if not unicodedata.combining(c))
    return " ".join(re.sub(r"[\W_]+", " ", text).split())


def work_id(title, authors) -> str:
    """
    Edition-aware book identity: folded title + first author's surname.

    Two catalog rows with the same work_id are editions of one book (e.g. 'JOHN IRVING'
    vs 'John Irving'); rows that only share a title ('The Complete Stories' by Hurston
    and by O'Connor) stay distinct. Authors are ';' or '|' separated, either
    'First Last' or 'Last, First'.
    """
    first = re.split(r"[;|]", str(authors or ""))[0].strip()
    if "," in first:
        surname = first.split(",")[0]
    else:
        tokens = _fold(first).split()
        surname = tokens[-1] if tokens else ""
    surname = _fold(surname)
    if surname in ("", "unknown author", "author", "nan", "none"):
        surname = ""
    return f"{_fold(title)}|{surname}"


def extract_year(date_str: Optional[str]) -> int:
    """Extract the first 4-digit year in range 1800–2030 from a date string."""
    if not date_str or not isinstance(date_str, str):
        return 0
    match = re.search(r"\b(\d{4})\b", date_str)
    if match:
        year = int(match.group(1))
        if 1800 <= year <= 2030:
            return year
    return 0


# ─────────────────────────────────────────────────────────────────────────────
# Feature engineering
# ─────────────────────────────────────────────────────────────────────────────


def build_combined_features(row: pd.Series) -> str:
    """
    Concatenate weighted text features for a single book row.

    Weighting strategy (via repetition):
    - title      ×3  – most discriminative feature
    - categories ×2  – strongly signals genre
    - authors    ×1
    - description×1  – adds semantic depth
    """
    title = clean_text(str(row.get("title", "")))
    authors = clean_text(str(row.get("authors", "")))
    categories = clean_text(str(row.get("categories", "")))
    description = clean_text(str(row.get("description", "")))

    return f"{title} {title} {title} {categories} {categories} {authors} {description}".strip()


# ─────────────────────────────────────────────────────────────────────────────
# Normalization helpers
# ─────────────────────────────────────────────────────────────────────────────


def normalize_rating(rating: float, max_rating: float = 5.0) -> float:
    """Clamp and scale rating to [0, 1]."""
    if max_rating == 0:
        return 0.0
    return min(1.0, max(0.0, float(rating) / max_rating))


def normalize_count(count: float, max_count: float) -> float:
    """Log-normalize a count to [0, 1] to reduce skew from bestsellers."""
    if max_count <= 0 or count <= 0:
        return 0.0
    return math.log1p(float(count)) / math.log1p(float(max_count))


# ─────────────────────────────────────────────────────────────────────────────
# Full preprocessing pipeline
# ─────────────────────────────────────────────────────────────────────────────


def preprocess_dataframe(df: pd.DataFrame) -> pd.DataFrame:
    """Complete preprocessing pipeline for the recommender dataset."""
    df = df.copy()

    expected_defaults = {
        "title": "Unknown Title",
        "authors": "Unknown Author",
        "categories": "General",
        "description": "",
        "thumbnail": "",
        "published_date": "",
        "average_rating": 0.0,
        "ratings_count": 0,
        "page_count": 0,
        "isbn13": "",
    }
    for col, default_val in expected_defaults.items():
        if col not in df.columns:
            df[col] = default_val

    # Fill missing values with sensible defaults.
    df["title"] = df["title"].fillna("Unknown Title")
    df["authors"] = df["authors"].fillna("Unknown Author")
    df["categories"] = df["categories"].fillna("General").astype(str)
    df["description"] = df["description"].fillna("")
    df["thumbnail"] = df["thumbnail"].fillna("")
    df["published_date"] = df["published_date"].fillna("").astype(str)

    # Normalize numeric columns.
    df["average_rating"] = (
        pd.to_numeric(df["average_rating"], errors="coerce").fillna(0.0).astype(float)
    )
    df["ratings_count"] = pd.to_numeric(df["ratings_count"], errors="coerce").fillna(0).astype(int)
    df["page_count"] = pd.to_numeric(df["page_count"], errors="coerce").fillna(0).astype(int)
    df["isbn13"] = df["isbn13"].fillna("").astype(str)

    # Derived columns.
    df["year"] = df["published_date"].apply(extract_year)
    df["combined_features"] = df.apply(build_combined_features, axis=1)

    # Popularity score based on normalized rating and ratings_count.
    max_rating = df["average_rating"].max() if not df["average_rating"].empty else 5.0
    max_count = df["ratings_count"].max() if not df["ratings_count"].empty else 1
    df["_norm_rating"] = df["average_rating"].apply(
        lambda value: normalize_rating(value, max_rating)
    )
    df["_norm_count"] = df["ratings_count"].apply(lambda value: normalize_count(value, max_count))
    df["popularity_score"] = 0.7 * df["_norm_rating"] + 0.3 * df["_norm_count"]
    df = df.drop(columns=["_norm_rating", "_norm_count"])

    # Collapse editions of one work (same folded title + first-author surname) into one row.
    # Deduplicating on title alone used to drop distinct books that share a title (e.g. Hurston's
    # and O'Connor's "The Complete Stories"). The surviving row keeps every edition's ISBN in
    # `edition_isbns` so an ISBN from another source (embeddings, user shelves) still resolves.
    df["_work"] = [work_id(t, a) for t, a in zip(df["title"], df["authors"])]
    isbns = df["isbn13"].map(normalize_isbn)
    editions = isbns.groupby(df["_work"]).agg(lambda s: "|".join(dict.fromkeys(i for i in s if i)))
    df = df.drop_duplicates(subset=["_work"], keep="first")
    df["edition_isbns"] = df["_work"].map(editions).fillna("")
    df = df.drop(columns=["_work"])

    return df.reset_index(drop=True)
