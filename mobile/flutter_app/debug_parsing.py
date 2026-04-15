
import requests
import json

SUPABASE_URL = "https://vnedgshbefpctjyzpqlm.supabase.co"
SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZuZWRnc2hiZWZwY3RqeXpwcWxtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ3MDU4MDksImV4cCI6MjA5MDI4MTgwOX0.dNbOM-n-HS4VQlI6Hkg6JE1XAhpgFBz5GoCo8o1MIYs"

def debug_parsing():
    headers = {
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}"
    }
    # Fetch exactly one book that should be in the 'Science' category
    url = f"{SUPABASE_URL}/rest/v1/books?categories=ilike.*Science*&limit=1"
    resp = requests.get(url, headers=headers)
    if resp.status_code == 200:
        data = resp.json()
        if data:
            print("RAW JSON FROM SUPABASE:")
            print(json.dumps(data[0], indent=2))
        else:
            print("No books found for Science in debug script!")
    else:
        print(f"Error: {resp.text}")

if __name__ == "__main__":
    debug_parsing()
