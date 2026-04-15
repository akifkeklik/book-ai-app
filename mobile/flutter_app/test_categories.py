
import requests

SUPABASE_URL = "https://vnedgshbefpctjyzpqlm.supabase.co"
SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZuZWRnc2hiZWZwY3RqeXpwcWxtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ3MDU4MDksImV4cCI6MjA5MDI4MTgwOX0.dNbOM-n-HS4VQlI6Hkg6JE1XAhpgFBz5GoCo8o1MIYs"

def test_category_query(category_keyword):
    headers = {
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}"
    }
    # Test ilike query
    url = f"{SUPABASE_URL}/rest/v1/books?categories=ilike.*{category_keyword}*&limit=5"
    resp = requests.get(url, headers=headers)
    print(f"Testing keyword: {category_keyword}")
    print(f"Status Code: {resp.status_code}")
    if resp.status_code == 200:
        data = resp.json()
        print(f"Found {len(data)} books.")
        if data:
            print(f"First book: {data[0]['title']} - Categories: {data[0]['categories']}")
    else:
        print(f"Error: {resp.text}")

if __name__ == "__main__":
    test_category_query("Science")
    test_category_query("Fiction")
