"""
Comprehensive Catalog Taxonomy and Data Integrity Audit.
Measures all data dimensions specified in Sprint 18 P1:
- Total record count
- Completeness of all fields
- Missing/unknown categories
- Canonical category distribution
- Exact duplicate ISBNs and likely duplicate editions (same title + author)
- ISBN validity (10 vs 13 digit numeric validation)
- Publication date validity
- Rating bounds and missing counts
- Category aliases and unmapped categories
- Conjunction query reproducibility (1984 + Young Adult & Children)
"""

import os
import re
import sys
from typing import Any, Dict, List, Tuple

import pandas as pd

# Ensure workspace root and backend are in path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")))
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

try:
    from backend.domain.taxonomy import CANONICAL_CATEGORIES_ORDERED, CANONICAL_CATEGORY_MAP
except ImportError:
    from domain.taxonomy import CANONICAL_CATEGORIES_ORDERED, CANONICAL_CATEGORY_MAP


def normalize_isbn(val: Any) -> str:
    s = str(val or "").strip()
    if s.endswith(".0"):
        s = s[:-2]
    return re.sub(r"[^0-9X]", "", s.upper())


def is_valid_isbn13(isbn: str) -> bool:
    if len(isbn) != 13 or not isbn.isdigit():
        return False
    # Checksum validation
    total = sum(int(ch) * (1 if i % 2 == 0 else 3) for i, ch in enumerate(isbn[:12]))
    check = (10 - (total % 10)) % 10
    return check == int(isbn[-1])


def is_valid_isbn10(isbn: str) -> bool:
    if len(isbn) != 10:
        return False
    digits = isbn[:9]
    last = isbn[9]
    if not digits.isdigit():
        return False
    check_val = 10 if last == 'X' else (int(last) if last.isdigit() else -1)
    if check_val == -1:
        return False
    total = sum(int(ch) * (10 - i) for i, ch in enumerate(digits)) + check_val
    return total % 11 == 0


def run_audit(csv_path: str = "backend/data/books.csv") -> Dict[str, Any]:
    df = pd.read_csv(csv_path)
    total_records = len(df)

    # 1. Field completeness
    field_stats = {}
    for col in df.columns:
        null_count = int(df[col].isna().sum())
        empty_str_count = int((df[col].astype(str).str.strip() == "").sum()) if df[col].dtype == object else 0
        field_stats[col] = {
            "total": total_records,
            "present": total_records - null_count,
            "null_count": null_count,
            "empty_str_count": empty_str_count,
            "completeness_pct": round(((total_records - null_count) / total_records) * 100, 2)
        }

    # 2. ISBN Audit
    raw_isbns = df["isbn13"].astype(str)
    norm_isbns = [normalize_isbn(x) for x in raw_isbns]
    unique_isbns = len(set(norm_isbns))
    exact_duplicates = total_records - unique_isbns

    valid_13_count = sum(1 for x in norm_isbns if is_valid_isbn13(x))
    valid_10_count = sum(1 for x in norm_isbns if is_valid_isbn10(x))
    invalid_isbn_count = sum(1 for x in norm_isbns if not (is_valid_isbn13(x) or is_valid_isbn10(x)))

    # Likely duplicate editions (same title and primary author)
    clean_titles = df["title"].astype(str).str.lower().str.strip()
    clean_authors = df["authors"].astype(str).str.lower().str.strip().str.split(";").str[0]
    title_author_pairs = list(zip(clean_titles, clean_authors))
    unique_title_author = len(set(title_author_pairs))
    likely_duplicate_editions = total_records - unique_title_author

    # 3. Publication Year Audit
    year_series = pd.to_numeric(df["published_date"], errors="coerce")
    null_years = int(year_series.isna().sum())
    invalid_year_bounds = int(((year_series < 1000) | (year_series > 2026)).sum())

    # 4. Rating Audit
    rating_series = pd.to_numeric(df["average_rating"], errors="coerce")
    null_ratings = int(rating_series.isna().sum())
    out_of_bounds_ratings = int(((rating_series < 0.0) | (rating_series > 5.0)).sum())

    rc_series = pd.to_numeric(df["ratings_count"], errors="coerce")
    null_rc = int(rc_series.isna().sum())
    negative_rc = int((rc_series < 0).sum())

    # 5. Taxonomy & Category Mapping Audit
    def resolve_canonical(raw_val: Any) -> Tuple[List[str], str]:
        if pd.isna(raw_val):
            return [], "Unknown"
        raw_str = str(raw_val).strip()
        if not raw_str:
            return [], "Unknown"

        parts = [p.strip() for p in re.split(r"[,|;/&]", raw_str) if p.strip()]
        matched_canonicals = set()

        # Check entire string first
        lower_full = raw_str.lower()
        if lower_full in CANONICAL_CATEGORY_MAP:
            matched_canonicals.add(CANONICAL_CATEGORY_MAP[lower_full])

        # Check each part
        for part in parts:
            p_lower = part.lower()
            if p_lower in CANONICAL_CATEGORY_MAP:
                matched_canonicals.add(CANONICAL_CATEGORY_MAP[p_lower])
            elif part in CANONICAL_CATEGORIES_ORDERED:
                matched_canonicals.add(part)
            elif p_lower in [c.lower() for c in CANONICAL_CATEGORIES_ORDERED]:
                for c in CANONICAL_CATEGORIES_ORDERED:
                    if c.lower() == p_lower:
                        matched_canonicals.add(c)
                        break

        canon_list = sorted(list(matched_canonicals))
        primary = canon_list[0] if canon_list else "Unknown"
        return canon_list, primary

    category_resolutions = [resolve_canonical(c) for c in df["categories"]]
    primary_categories = [r[1] for r in category_resolutions]
    multi_category_count = sum(1 for r in category_resolutions if len(r[0]) > 1)
    unknown_category_count = sum(1 for r in category_resolutions if r[1] == "Unknown")

    category_counts = {}
    for cat in primary_categories:
        category_counts[cat] = category_counts.get(cat, 0) + 1

    # Unmapped category strings
    unmapped_raw_strings = {}
    for raw, (canon_list, primary) in zip(df["categories"], category_resolutions):
        if primary == "Unknown":
            raw_k = str(raw).strip()
            unmapped_raw_strings[raw_k] = unmapped_raw_strings.get(raw_k, 0) + 1

    # 6. Specific Book Investigations: 1984
    books_1984 = []
    for idx, row in df.iterrows():
        title = str(row.get("title", ""))
        isbn = str(row.get("isbn13", ""))
        raw_cat = str(row.get("categories", ""))
        desc = str(row.get("description", ""))
        if "1984" in title or "1984" in isbn or "1984" in desc:
            canons, primary = resolve_canonical(raw_cat)
            books_1984.append({
                "isbn13": str(row.get("isbn13")),
                "title": title,
                "authors": str(row.get("authors")),
                "raw_categories": raw_cat,
                "resolved_canonical": canons,
                "primary_canonical": primary,
                "average_rating": row.get("average_rating"),
                "ratings_count": row.get("ratings_count"),
                "published_date": row.get("published_date")
            })

    report = {
        "dataset_path": csv_path,
        "total_records": total_records,
        "field_completeness": field_stats,
        "isbn_metrics": {
            "unique_isbn13": unique_isbns,
            "exact_duplicate_isbns": exact_duplicates,
            "valid_isbn13_checksum": valid_13_count,
            "valid_isbn10_checksum": valid_10_count,
            "invalid_isbn_checksum": invalid_isbn_count,
            "likely_duplicate_editions_by_title_author": likely_duplicate_editions,
        },
        "year_metrics": {
            "null_years": null_years,
            "invalid_year_bounds": invalid_year_bounds,
        },
        "rating_metrics": {
            "null_ratings": null_ratings,
            "out_of_bounds_ratings": out_of_bounds_ratings,
            "null_ratings_count": null_rc,
            "negative_ratings_count": negative_rc,
        },
        "taxonomy_metrics": {
            "canonical_categories_defined": len(CANONICAL_CATEGORIES_ORDERED),
            "raw_taxonomy_rules": len(CANONICAL_CATEGORY_MAP),
            "multi_category_books": multi_category_count,
            "unknown_category_count": unknown_category_count,
            "unknown_category_pct": round((unknown_category_count / total_records) * 100, 2),
            "distribution": sorted(category_counts.items(), key=lambda x: x[1], reverse=True),
            "top_unmapped_raw_categories": sorted(unmapped_raw_strings.items(), key=lambda x: x[1], reverse=True)[:30],
        },
        "investigation_1984": {
            "matches_found": len(books_1984),
            "books": books_1984,
        }
    }
    return report


if __name__ == "__main__":
    rep = run_audit()
    print("=== CATALOG TAXONOMY AUDIT SUMMARY ===")
    print(f"Total Records: {rep['total_records']}")
    print(f"Exact Duplicate ISBNs: {rep['isbn_metrics']['exact_duplicate_isbns']}")
    print(f"Valid ISBN-13 Checksums: {rep['isbn_metrics']['valid_isbn13_checksum']}")
    print(f"Invalid ISBN Checksums: {rep['isbn_metrics']['invalid_isbn_checksum']}")
    print(f"Likely duplicate editions (title+author): {rep['isbn_metrics']['likely_duplicate_editions_by_title_author']}")
    print(f"Unknown Category Books: {rep['taxonomy_metrics']['unknown_category_count']} ({rep['taxonomy_metrics']['unknown_category_pct']}%)")
    print("\nCategory Distribution:")
    for cat, cnt in rep["taxonomy_metrics"]["distribution"][:10]:
        print(f"  - {cat}: {cnt} books")
    print(f"\n1984 Investigation ({rep['investigation_1984']['matches_found']} matches):")
    for b in rep["investigation_1984"]["books"][:5]:
        print(f"  - [{b['isbn13']}] '{b['title']}' by {b['authors']} -> Raw: '{b['raw_categories']}' -> Canonical: {b['resolved_canonical']}")
