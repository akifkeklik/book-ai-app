
import requests

SUPABASE_URL = "https://vnedgshbefpctjyzpqlm.supabase.co"
SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZuZWRnc2hiZWZwY3RqeXpwcWxtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ3MDU4MDksImV4cCI6MjA5MDI4MTgwOX0.dNbOM-n-HS4VQlI6Hkg6JE1XAhpgFBz5GoCo8o1MIYs"

def check_schema():
    headers = {
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}"
    }
    # Get 1 row to see all columns
    url = f"{SUPABASE_URL}/rest/v1/books?limit=1"
    resp = requests.get(url, headers=headers)
    if resp.status_code == 200:
        data = resp.json()
        if data:
            print(f"Columns in 'books' table: {list(data[0].keys())}")
        else:
            print("Table is empty!")
    else:
        print(f"Error checking schema: {resp.text}")

if __name__ == "__main__":
    check_schema()
