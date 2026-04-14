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

print(f"Checking data at: {url}")

try:
    # 1. Total Count
    r = requests.get(f"{url}/rest/v1/books", params={"select": "id", "limit": 1}, headers=headers)
    if r.status_code == 200:
        print("Table 'books' exists and is accessible.")
        
        # 2. Sample categories
        r = requests.get(f"{url}/rest/v1/books", params={"select": "categories", "limit": 20}, headers=headers)
        if r.status_code == 200:
            cats = [b.get('categories') for b in r.json()]
            print("\n--- Sample Categories (First 20) ---")
            for c in cats:
                print(f"  '{c}'")
        
        # 3. Test "Fiction" query specifically
        # The app uses: .or('categories.ilike.%Fiction%,categories.ilike.%Juvenile Fiction%...')
        # Let's test a single ilike
        r = requests.get(f"{url}/rest/v1/books", params={"categories": "ilike.*Fiction*", "select": "id", "limit": 5}, headers=headers)
        print(f"\n--- Fiction ilike Test ---")
        if r.status_code == 200:
            print(f"Found {len(r.json())} books matching 'Fiction' (sample check)")
        else:
            print(f"Fiction query failed: {r.status_code} - {r.text}")

    else:
        print(f"Access failed: {r.status_code} - {r.text}")

except Exception as e:
    print(f"Check failed: {e}")
