
import requests
import json

# Testing the user's backend connectivity
SUPABASE_URL = "https://vnedgshbefpctjyzpqlm.supabase.co"
SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZuZWRnc2hiZWZwY3RqeXpwcWxtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ3MDU4MDksImV4cCI6MjA5MDI4MTgwOX0.dNbOM-n-HS4VQlI6Hkg6JE1XAhpgFBz5GoCo8o1MIYs"

def test_supabase():
    print(f"Testing Supabase URL: {SUPABASE_URL}")
    try:
        # Try to count books
        headers = {
            "apikey": SUPABASE_KEY,
            "Authorization": f"Bearer {SUPABASE_KEY}"
        }
        url = f"{SUPABASE_URL}/rest/v1/books?select=id"
        # Use a HEAD request or a small select
        resp = requests.get(url, headers=headers, params={"limit": 1})
        print(f"Status Code: {resp.status_code}")
        if resp.status_code == 200:
            print("Successfully connected to Supabase!")
            print(f"Sample data: {resp.json()}")
        else:
            print(f"Error: {resp.text}")
    except Exception as e:
        print(f"Exception: {e}")

def test_backend():
    BACKEND_URL = "https://book-ai-app-libris-api.onrender.com"
    print(f"Testing Backend URL: {BACKEND_URL}")
    try:
        resp = requests.get(f"{BACKEND_URL}/api/books/popular?limit=1")
        print(f"Status Code: {resp.status_code}")
        if resp.status_code == 200:
            print("Successfully connected to Backend!")
        else:
            print(f"Error: {resp.text}")
    except Exception as e:
        print(f"Exception: {e}")

if __name__ == "__main__":
    test_supabase()
    test_backend()
