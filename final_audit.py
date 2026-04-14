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

print(f"Final Audit at: {url}")

try:
    # Get 100 books to see categories
    r = requests.get(f"{url}/rest/v1/books", params={"select": "categories", "limit": 100}, headers=headers)
    if r.status_code == 200:
        data = r.json()
        cats = [d.get('categories') for d in data if d.get('categories')]
        
        from collections import Counter
        counter = Counter(cats)
        print("\n--- Found Categories ---")
        for cat, count in counter.most_common(50):
            print(f"  '{cat}': {count}")
    else:
        print(f"Error: {r.status_code} - {r.text}")
except Exception as e:
    print(f"Audit failed: {e}")
