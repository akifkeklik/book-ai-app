import os

import psycopg2
from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(os.path.dirname(__file__)), ".env"))
db_url = os.environ.get("SUPABASE_DB_URL")

try:
    conn = psycopg2.connect(db_url)
    cursor = conn.cursor()
    cursor.execute("""
        SELECT prosrc
        FROM pg_proc
        WHERE proname = 'match_query_embeddings';
    """)
    rpc = cursor.fetchone()
    if rpc:
        print("RPC Definition:")
        print(rpc[0])
    else:
        print("RPC 'match_query_embeddings' not found.")
except Exception as e:
    print(f"Error: {e}")
