
import requests
import json

SUPABASE_URL = "https://vnedgshbefpctjyzpqlm.supabase.co"
SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZuZWRnc2hiZWZwY3RqeXpwcWxtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ3MDU4MDksImV4cCI6MjA5MDI4MTgwOX0.dNbOM-n-HS4VQlI6Hkg6JE1XAhpgFBz5GoCo8o1MIYs"

def debug_query(or_filter):
    headers = {
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}"
    }
    # Emulate the .or() call exactly
    url = f"{SUPABASE_URL}/rest/v1/books?select=*&or=({or_filter})&limit=5"
    print(f"URL: {url}")
    resp = requests.get(url, headers=headers)
    print(f"Status: {resp.status_code}")
    if resp.status_code == 200:
        data = resp.json()
        print(f"Result count: {len(data)}")
        if data:
            print(f"First result categories: {data[0].get('categories')}")
    else:
        print(f"Error: {resp.text}")

if __name__ == "__main__":
    # Test 1: EXACT current app filter for Bilim/Science
    # Science, Technology, Bilim
    filter1 = "categories.ilike.*Science*,categories.ilike.*Technology*,categories.ilike.*Bilim*"
    print("--- Test 1 (App Current) ---")
    debug_query(filter1)

    # Test 2: Simplified filter
    filter2 = "categories.ilike.*Science*"
    print("\n--- Test 2 (Simplified) ---")
    debug_query(filter2)
