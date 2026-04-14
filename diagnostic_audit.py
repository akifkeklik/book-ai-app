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

print(f"Auditing database at: {url}")

try:
    # 1. Total records
    r = requests.get(f"{url}/rest/v1/books", params={"select": "id", "limit": 1}, headers=headers)
    if r.status_code != 200:
        print(f"Connection failed: {r.status_code}")
        exit(1)
    
    # 2. Sample data
    r = requests.get(f"{url}/rest/v1/books", params={"select": "title,authors,categories", "limit": 10}, headers=headers)
    if r.status_code == 200:
        print("\n--- Data Sample ---")
        for b in r.json():
            print(f"Title: {b.get('title')}, Authors: {b.get('authors')}, Categories: {b.get('categories')}")
    
    # 3. Fiction Test
    print("\n--- Fiction Query Test ('ilike.*Fiction*') ---")
    r = requests.get(f"{url}/rest/v1/books", params={"categories": "ilike.*Fiction*", "select": "title", "limit": 5}, headers=headers)
    if r.status_code == 200:
        print(f"Found {len(r.json())} books.")
        for b in r.json():
            print(f"  - {b.get('title')}")
    else:
        print(f"Query error: {r.status_code} - {r.text}")

except Exception as e:
    print(f"Error: {e}")
