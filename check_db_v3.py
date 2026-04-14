import os
import json
import urllib.request
from dotenv import load_dotenv

# Path to .env
env_path = os.path.join('backend', '.env')
load_dotenv(env_path)

url = os.getenv('SUPABASE_URL')
key = os.getenv('SUPABASE_ANON_KEY')

if not url or not key:
    print(f"Error: Credentials not found at {env_path}")
    # Try current dir .env
    load_dotenv('.env')
    url = os.getenv('SUPABASE_URL')
    key = os.getenv('SUPABASE_ANON_KEY')

headers = {
    "apikey": key,
    "Authorization": f"Bearer {key}",
    "Content-Type": "application/json"
}

def get_data(endpoint_params):
    full_url = f"{url}/rest/v1/books?{endpoint_params}"
    req = urllib.request.Request(full_url, headers=headers)
    with urllib.request.urlopen(req) as response:
        return json.load(response)

# 1. Total count
print("\n--- Summary ---")
try:
    # Get total count (permissive way)
    count_req = urllib.request.Request(f"{url}/rest/v1/books?select=id", headers={**headers, "Prefer": "count=exact"})
    with urllib.request.urlopen(count_req) as response:
        count = response.headers.get('Content-Range', '').split('/')[-1]
        print(f"Total books in 'books' table: {count}")
except Exception as e:
    print(f"Count failed: {e}")

# 2. Sample data
print("\n--- Sample Categories (First 5) ---")
try:
    data = get_data("select=title,categories&limit=5")
    for i, b in enumerate(data):
        print(f"[{i}] {b.get('title')}: {b.get('categories')}")
except Exception as e:
    print(f"Sample failed: {e}")

# 3. Science Search
print("\n--- 'Science' Search Test ---")
try:
    # ilike.*Science*
    data = get_data("categories=ilike.*Science*&select=id&limit=3")
    print(f"Direct Science query match count: {len(data)}")
except Exception as e:
    print(f"Science search failed: {e}")
