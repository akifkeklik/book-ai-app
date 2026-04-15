
import requests

SUPABASE_URL = "https://vnedgshbefpctjyzpqlm.supabase.co"
SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZuZWRnc2hiZWZwY3RqeXpwcWxtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ3MDU4MDksImV4cCI6MjA5MDI4MTgwOX0.dNbOM-n-HS4VQlI6Hkg6JE1XAhpgFBz5GoCo8o1MIYs"

def list_tables():
    headers = {
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}"
    }
    # OpenResty / PostgREST doesn't directly give table lists via REST usually, 
    # but we can try to query the OpenAPI spec
    url = f"{SUPABASE_URL}/rest/v1/"
    resp = requests.get(url, headers=headers)
    if resp.status_code == 200:
        data = resp.json()
        print(f"Available tables: {list(data.get('definitions', {}).keys())}")
    else:
        print(f"Error listing tables: {resp.text}")

if __name__ == "__main__":
    list_tables()
