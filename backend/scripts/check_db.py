import os
import sys

import psycopg2
from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(os.path.dirname(__file__)), ".env"))
db_url = os.environ.get("SUPABASE_DB_URL")
if not db_url:
    print("SUPABASE_DB_URL not set.")
    sys.exit(1)

try:
    conn = psycopg2.connect(db_url)
    conn.autocommit = True
    cursor = conn.cursor()

    cursor.execute("SELECT COUNT(*) FROM books;")
    books_count = cursor.fetchone()[0]

    cursor.execute("SELECT COUNT(*) FROM book_embeddings;")
    embeddings_count = cursor.fetchone()[0]

    print(f"books = {books_count}")
    print(f"embeddings = {embeddings_count}")
    print(f"missing = {books_count - embeddings_count}")

except Exception as e:
    print(f"DB Error: {e}")
