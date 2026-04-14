import os
import requests
from dotenv import load_dotenv
from collections import Counter

load_dotenv('.env')

url = os.getenv('SUPABASE_URL')
key = os.getenv('SUPABASE_ANON_KEY')

headers = {
    "apikey": key,
    "Authorization": f"Bearer {key}"
}

print(f"Auditing categories at: {url}")

try:
    # Fetch 1000 records to get a good sample of categories
    r = requests.get(f"{url}/rest/v1/books", params={"select": "categories", "limit": 1000}, headers=headers)
    if r.status_code == 200:
        data = r.json()
        categories = [d.get('categories') for d in data if d.get('categories')]
        
        counter = Counter(categories)
        print("\n--- Most Frequent Categories in DB ---")
        for cat, count in counter.most_common(20):
            print(f"  {cat}: {count}")
            
        # Check specifically for "Fiction" containing strings
        print("\n--- Fiction-related Categories ---")
        fiction_cats = [cat for cat in counter if 'fiction' in cat.lower()]
        for cat in fiction_cats[:10]:
            print(f"  {cat}")
            
    else:
        print(f"Error: {r.status_code} - {r.text}")
except Exception as e:
    print(f"Audit failed: {e}")
