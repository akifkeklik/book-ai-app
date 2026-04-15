
import requests
import json

SUPABASE_URL = "https://vnedgshbefpctjyzpqlm.supabase.co"
SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZuZWRnc2hiZWZwY3RqeXpwcWxtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ3MDU4MDksImV4cCI6MjA5MDI4MTgwOX0.dNbOM-n-HS4VQlI6Hkg6JE1XAhpgFBz5GoCo8o1MIYs"

def inspect_categories():
    headers = {
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}"
    }
    # Get 10 random books to see what the categories column actually looks like
    url = f"{SUPABASE_URL}/rest/v1/books?select=title,categories&limit=10"
    resp = requests.get(url, headers=headers)
    if resp.status_code == 200:
        data = resp.json()
        print("Category Data Samples:")
        for item in data:
            print(f"Title: {item['title']} | Categories: {type(item['categories'])} | Value: {item['categories']}")
    else:
        print(f"Error: {resp.text}")

if __name__ == "__main__":
    inspect_categories()
