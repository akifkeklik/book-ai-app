import os
import sys
from dotenv import load_dotenv

# Ensure we can import from backend
sys.path.append(os.path.join(os.getcwd(), 'backend'))

from services.book_service import BookService

def main():
    load_dotenv('.env')
    print("Initializing BookService...")
    svc = BookService()
    
    print("\n--- Available Categories from ML Model ---")
    cats = svc.get_categories()
    if not cats:
        print("No categories found in the model. Model might not be fitted.")
    else:
        print(f"Found {len(cats)} unique categories.")
        print("Sample (First 50):", cats[:50])
        
        # Test specific genres
        test_genres = ["Fiction", "History", "Science", "Mystery"]
        for g in test_genres:
            matches = [c for c in cats if g.lower() in c.lower()]
            print(f"Matches for '{g}': {matches}")

if __name__ == "__main__":
    main()
