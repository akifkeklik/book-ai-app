import os
import psycopg2
from dotenv import load_dotenv

load_dotenv()
db_url = os.getenv("SUPABASE_DB_URL")
if not db_url:
    print("No SUPABASE_DB_URL found.")
    exit(1)

conn = psycopg2.connect(db_url)
with conn.cursor() as cur:
    cur.execute("""
        SELECT column_name, data_type, is_nullable
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'user_profiles'
        ORDER BY ordinal_position;
    """)
    cols = cur.fetchall()
    print("user_profiles columns:")
    for c in cols:
        print(" ", c)

    cur.execute("""
        SELECT column_name, data_type, is_nullable
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'user_interactions'
        ORDER BY ordinal_position;
    """)
    print("\nuser_interactions columns:")
    for c in cur.fetchall():
        print(" ", c)

    cur.execute("""
        SELECT column_name, data_type, is_nullable
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'favorites'
        ORDER BY ordinal_position;
    """)
    print("\nfavorites columns:")
    for c in cur.fetchall():
        print(" ", c)
conn.close()
