import os
import requests
from dotenv import load_dotenv

# Load from project root `.env` (recommended)
load_dotenv('.env')

url = os.getenv('SUPABASE_URL')
key = os.getenv('SUPABASE_ANON_KEY')

if not url or not key:
    print("Error: SUPABASE_URL or SUPABASE_ANON_KEY not found in .env")
    exit(1)

headers = {
    "apikey": key,
    "Authorization": f"Bearer {key}",
    "Range": "0-19" # First 20 records
}

# 1. Get a sample of 20 books to see the raw 'categories' column
print("--- Sample 20 Books ---")
try:
    r = requests.get(f"{url}/rest/v1/books?select=title,categories&limit=20", headers=headers)
    if r.status_code == 200:
        for book in r.json():
            print(f"Title: {book.get('title', 'N/A')} | Categories: {book.get('categories', 'N/A')}")
    else:
        print(f"Error fetching sample: {r.status_code} - {r.text}")
except Exception as e:
    print(f"Request failed: {e}")

# 2. Check for some common genres to see if they return anything
genres_to_test = ["History", "Fiction", "Science", "Mystery"]
print("\n--- Testing Specific Genres ---")
for genre in genres_to_test:
    try:
        # Proper PostgREST ilike: .ilike.history*
        r = requests.get(f"{url}/rest/v1/books?categories=ilike.*{genre}*&select=id&limit=1", headers=headers)
        if r.status_code == 200:
            count = len(r.json())
            print(f"Genre '{genre}' match? {'YES' if count > 0 else 'NO'}")
        else:
            print(f"Error testing '{genre}': {r.status_code}")
    except Exception as e:
        print(f"Test failed for '{genre}': {e}")

# 3. List some unique categories (brute force on first 500)
print("\n--- Unique Categories (Brute force sample) ---")
try:
    # Use explicit URL parameters for limit instead of headers sometimes
    r = requests.get(f"{url}/rest/v1/books?select=categories&limit=500", headers=headers)
    if r.status_code == 200:
        all_cats = set()
        for item in r.json():
            cat_str = item.get('categories')
            if cat_str and cat_str != 'nan':
                # Split by | or ; if present
                for c in str(cat_str).replace(';', '|').split('|'):
                    all_cats.add(c.strip())
        print(f"Found {len(all_cats)} unique categories in sample.")
        print("Sample Categories:", sorted(list(all_cats))[:50])
    else:
        print("Error fetching categories sample.")
except Exception as e:
    print(f"Category audit failed: {e}")
