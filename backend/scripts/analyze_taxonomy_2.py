import os
import sys

import pandas as pd

# Add domain to path to import taxonomy
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
from domain.taxonomy import CANONICAL_CATEGORY_MAP

csv_path = os.path.join(os.path.dirname(__file__), '..', 'data', 'books.csv')
df = pd.read_csv(csv_path)

total_books = len(df)
isbn_unique = df['isbn'].nunique() if 'isbn' in df.columns else 0
duplicate_books = total_books - df['isbn'].nunique() if 'isbn' in df.columns else 0

completeness = {}
for col in df.columns:
    missing = df[col].isna().sum()
    completeness[col] = (total_books - missing) / total_books * 100

def map_category(raw_cat):
    if pd.isna(raw_cat):
        return "Unknown"

    # Simple split and clean (could be improved depending on raw data format)
    raw = str(raw_cat).lower().strip()

    # Try exact match first
    if raw in CANONICAL_CATEGORY_MAP:
        return CANONICAL_CATEGORY_MAP[raw]

    # Try parsing array-like or comma separated
    import ast
    try:
        cats = ast.literal_eval(raw)
        if isinstance(cats, list) and len(cats) > 0:
            raw = cats[0].lower().strip()
            if raw in CANONICAL_CATEGORY_MAP:
                return CANONICAL_CATEGORY_MAP[raw]
    except Exception:
        pass

    # split by comma
    parts = [p.strip() for p in raw.split(',')]
    for p in parts:
        if p in CANONICAL_CATEGORY_MAP:
            return CANONICAL_CATEGORY_MAP[p]

    return "Unknown"

df['canonical_category'] = df['categories'].apply(map_category)

unknown_count_before = len(df[df['canonical_category'] == 'Unknown'])
unknown_pct_before = unknown_count_before / total_books * 100

# Analyze unmapped categories
unmapped_cats = {}
for idx, row in df[df['canonical_category'] == 'Unknown'].iterrows():
    cat = row.get('categories')
    if pd.isna(cat):
        cat = "NULL"
    else:
        cat = str(cat)
    if cat not in unmapped_cats:
        unmapped_cats[cat] = 0
    unmapped_cats[cat] += 1

sorted_unmapped = sorted(unmapped_cats.items(), key=lambda x: x[1], reverse=True)

print(f"Total Books: {total_books}")
print(f"ISBN Uniqueness: {isbn_unique}")
print(f"Duplicate Books: {duplicate_books}")
print("Completeness:")
for k, v in completeness.items():
    print(f"  {k}: {v:.2f}%")
print(f"Unknown Count (Before): {unknown_count_before} ({unknown_pct_before:.2f}%)")
print("\nTop 50 Unmapped Categories:")
for k, v in sorted_unmapped[:50]:
    print(f"  {k}: {v}")
