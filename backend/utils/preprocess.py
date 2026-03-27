"""
Text preprocessing utilities for the TF-IDF recommendation engine.
All functions are pure and stateless for easy testing.
"""

import math
import re
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
    text = re.sub(r"<[^>]+>", " ", text)          # strip HTML
    text = re.sub(r"[^a-z0-9\s]", " ", text)      # keep alphanumeric
    text = re.sub(r"\s+", " ", text).strip()
    return text


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
    """
    Complete preprocessing pipeline:
    1. Fill missing values with sensible defaults
    2. Cast numeric columns
    3. Extract publication year
    4. Build combined feature string for TF-IDF
    5. Deduplicate on lowercase title
    6. Reset index
    """
    df = df.copy()

    # Fill NaN
    df["title"] = df["title"].fillna("Unknown Title")
    df["authors"] = df["authors"].fillna("Unknown Author")
    df["categories"] = df["categories"].fillna("General")
    df["description"] = df["description"].fillna("")
    df["thumbnail"] = df["thumbnail"].fillna("")
    df["published_date"] = df["published_date"].fillna("").astype(str)

    # Numeric casts
    df["average_rating"] = (
        pd.to_numeric(df["average_rating"], errors="coerce").fillna(0.0).astype(float)
    )
    df["ratings_count"] = (
        pd.to_numeric(df["ratings_count"], errors="coerce").fillna(0).astype(int)
    )
    df["page_count"] = (
        pd.to_numeric(df["page_count"], errors="coerce").fillna(0).astype(int)
    )
    df["isbn13"] = df["isbn13"].fillna("").astype(str)

    # Derived columns
    df["year"] = df["published_date"].apply(extract_year)
    df["combined_features"] = df.apply(build_combined_features, axis=1)

    # Deduplicate
    df["_title_lower"] = df["title"].str.lower().str.strip()
    df = df.drop_duplicates(subset=["_title_lower"], keep="first")
    df = df.drop(columns=["_title_lower"])
    df = df.reset_index(drop=True)

    return df
