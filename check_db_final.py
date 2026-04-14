import os
import requests
from dotenv import load_dotenv

load_dotenv('.env')
url = os.getenv('SUPABASE_URL')
key = os.getenv('SUPABASE_ANON_KEY')

headers = {
    "apikey": key,
    "Authorization": f"Bearer {key}"
}

print(f"Checking Supabase at: {url}")

# Check table 'books' structure and some data
print("\n--- First 10 Books 'categories' and 'id' ---")
try:
    # Use params to avoid shell escaping issues with &
    r = requests.get(f"{url}/rest/v1/books", 
                     params={"select": "id,categories,title", "limit": "10"}, 
                     headers=headers,
                     timeout=10)
    if r.status_code == 200:
        data = r.json()
        if not data:
            print("Table 'books' exists but is EMPTY.")
        else:
            for i, book in enumerate(data):
                print(f"[{i+1}] Title: {book.get('title')} | Categories: {book.get('categories')}")
    else:
        print(f"Error: {r.status_code} - {r.text}")
except Exception as e:
    print(f"Connection Failed: {e}")

# Check distinct categories (if possible via search)
print("\n--- Searching for 'Science' in categories ---")
try:
    r = requests.get(f"{url}/rest/v1/books", 
                     params={"categories": "ilike.*Science*", "select": "id,title", "limit": "1"}, 
                     headers=headers,
                     timeout=10)
    if r.status_code == 200:
        res = r.json()
        print(f"Match found: {res}")
    else:
        print(f"Search Error: {r.status_code}")
except Exception as e:
    print(f"Search Failed: {e}")
