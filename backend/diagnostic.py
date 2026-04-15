
import os
import sys
import pandas as pd
from supabase import create_client

# Add parent dir to sys.path to import backend modules
sys.path.append(os.getcwd())

from backend.config import Config
from backend.services.book_service import BookService

def diagnostic():
    print("--- Diagnostic Start ---")
    svc = BookService()
    recommender = svc.recommender
    
    if recommender.df.empty:
        print("ERROR: DataFrame is empty!")
        return

    print(f"DataFrame loaded. Row count: {len(recommender.df)}")
    print("Columns:", recommender.df.columns.tolist())
    
    print("\nSample Categories Content:")
    print(recommender.df["categories"].value_counts().head(10))
    
    print("\nSample ISBN13 Content:")
    print(recommender.df["isbn13"].head(5))
    
    # Check category filtering
    test_cat = "Fiction"
    mask = recommender.df["categories"].str.contains(test_cat, case=False, na=False, regex=False)
    filtered = recommender.df[mask]
    print(f"\nFiltering test for '{test_cat}': Found {len(filtered)} books.")
    
    if len(filtered) == 0:
        print("DEBUG: Try exact match or astype(str)?")
        mask_typed = recommender.df["categories"].astype(str).str.contains(test_cat, case=False, na=False, regex=False)
        print(f"Filtering test with astype(str) for '{test_cat}': Found {len(recommender.df[mask_typed])} books.")

    # Check unique categories
    unique_cats = svc.get_categories()
    print(f"\nUnique Categories count: {len(unique_cats)}")
    print("Sample Unique Categories:", unique_cats[:10])

    print("--- Diagnostic End ---")

if __name__ == "__main__":
    diagnostic()
