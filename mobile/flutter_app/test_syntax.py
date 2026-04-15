
import requests
import json

SUPABASE_URL = "https://vnedgshbefpctjyzpqlm.supabase.co"
SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZuZWRnc2hiZWZwY3RqeXpwcWxtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ3MDU4MDksImV4cCI6MjA5MDI4MTgwOX0.dNbOM-n-HS4VQlI6Hkg6JE1XAhpgFBz5GoCo8o1MIYs"

def test_parentheses():
    headers = {
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}"
    }
    # Test 1: Single Parentheses (Standard)
    url1 = f"{SUPABASE_URL}/rest/v1/books?or=(categories.ilike.*Science*)&limit=1"
    
    # Test 2: Double Parentheses (My suspected-broken version)
    url2 = f"{SUPABASE_URL}/rest/v1/books?or=((categories.ilike.*Science*))&limit=1"
    
    print("--- Test 1 (Single) ---")
    r1 = requests.get(url1, headers=headers)
    print(f"Status: {r1.status_code}, Results: {len(r1.json()) if r1.status_code==200 else r1.text}")
    
    print("\n--- Test 2 (Double) ---")
    r2 = requests.get(url2, headers=headers)
    print(f"Status: {r2.status_code}, Results: {r2.text}")

if __name__ == "__main__":
    test_parentheses()
