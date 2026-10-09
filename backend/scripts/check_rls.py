import os

import psycopg2
from dotenv import load_dotenv

load_dotenv('.env')
conn = psycopg2.connect(os.environ['SUPABASE_DB_URL'])
cur = conn.cursor()
cur.execute("SELECT relname, relrowsecurity FROM pg_class WHERE relname IN ('books', 'book_embeddings');")
print(cur.fetchall())
