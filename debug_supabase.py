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
    "Authorization": f"Bearer {key}"
}

print(f"Connecting to: {url}")

# 1. Test connection and get all tables (PostgREST root)
print("\n--- API Root ---")
try:
    r = requests.get(f"{url}/rest/v1/", headers=headers)
    if r.status_code == 200:
        print("Connected successfully.")
        # print(r.json()) # Too much info
    else:
        print(f"Connection failed: {r.status_code}")
except Exception as e:
    print(f"Error: {e}")

# 2. Get first 5 rows from 'books' table
print("\n--- Raw Data (First 5 Books) ---")
try:
    # Use params for limit to avoid & in URL
    r = requests.get(f"{url}/rest/v1/books", params={"select": "*", "limit": 5}, headers=headers)
    if r.status_code == 200:
        data = r.json()
        if not data:
            print("Table 'books' is EMPTY!")
        else:
            for i, book in enumerate(data):
                print(f"\n[Book {i+1}]")
                for k, v in book.items():
                    print(f"  {k}: {v}")
    else:
        print(f"Error fetching books: {r.status_code} - {r.text}")
except Exception as e:
    print(f"Book fetch failed: {e}")

# 3. Check specific count for Science
print("\n--- Search Test (Science) ---")
try:
    # Test ilike directly
    r = requests.get(f"{url}/rest/v1/books", params={"categories": "ilike.*Science*", "select": "id", "limit": 1}, headers=headers)
    if r.status_code == 200:
        print(f"Science match result length: {len(r.json())}")
    else:
        print(f"Science search failed: {r.status_code}")
except Exception as e:
    print(f"Search failed: {e}")
