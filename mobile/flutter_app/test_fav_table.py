
import requests
import json

SUPABASE_URL = "https://vnedgshbefpctjyzpqlm.supabase.co"
SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZuZWRnc2hiZWZwY3RqeXpwcWxtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ3MDU4MDksImV4cCI6MjA5MDI4MTgwOX0.dNbOM-n-HS4VQlI6Hkg6JE1XAhpgFBz5GoCo8o1MIYs"

def test_fav_insertion():
    headers = {
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}",
        "Content-Type": "application/json",
        "Prefer": "return=minimal"
    }
    # User ID: 00000000-0000-0000-0000-000000000000 (Dummy)
    payload = {
        "user_id": "00000000-0000-0000-0000-000000000000",
        "book_id": "9780000000000",
        "book_title": "Diagnostic Test",
        "book_author": "Antigravity",
        "book_image_url": "",
        "added_at": "2026-04-14T12:00:00Z"
    }
    url = f"{SUPABASE_URL}/rest/v1/favorites"
    resp = requests.post(url, headers=headers, data=json.dumps(payload))
    print(f"Status Code: {resp.status_code}")
    print(f"Response: {resp.text}")

if __name__ == "__main__":
    test_fav_insertion()
