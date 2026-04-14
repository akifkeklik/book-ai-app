import urllib.request
import urllib.error
import json
import sys

SUPABASE_URL = "https://vnedgshbefpctjyzpqlm.supabase.co"
ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZuZWRnc2hiZWZwY3RqeXpwcWxtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ3MDU4MDksImV4cCI6MjA5MDI4MTgwOX0.dNbOM-n-HS4VQlI6Hkg6JE1XAhpgFBz5GoCo8o1MIYs"

def test_supabase():
    # Test 1: Auth health endpoint
    url = f"{SUPABASE_URL}/auth/v1/health"
    req = urllib.request.Request(url, headers={
        "apikey": ANON_KEY,
        "Authorization": f"Bearer {ANON_KEY}",
    })
    try:
        with urllib.request.urlopen(req, timeout=10) as res:
            body = res.read().decode()
            print(f"[AUTH HEALTH] ✅ {res.status} - {body[:100]}")
    except urllib.error.HTTPError as e:
        print(f"[AUTH HEALTH] ⚠️  HTTP {e.code}: {e.read().decode()[:200]}")
    except Exception as e:
        print(f"[AUTH HEALTH] ❌ BAĞLANTI HATASI: {e}")

    # Test 2: Books table
    url2 = f"{SUPABASE_URL}/rest/v1/books?select=id,title&limit=3"
    req2 = urllib.request.Request(url2, headers={
        "apikey": ANON_KEY,
        "Authorization": f"Bearer {ANON_KEY}",
    })
    try:
        with urllib.request.urlopen(req2, timeout=10) as res:
            body = json.loads(res.read().decode())
            print(f"[BOOKS TABLE] ✅ {res.status} - {len(body)} kitap geldi. İlk kitap: {body[0]['title'] if body else 'BOŞ'}")
    except urllib.error.HTTPError as e:
        print(f"[BOOKS TABLE] ⚠️  HTTP {e.code}: {e.read().decode()[:200]}")
    except Exception as e:
        print(f"[BOOKS TABLE] ❌ BAĞLANTI HATASI: {e}")

test_supabase()
