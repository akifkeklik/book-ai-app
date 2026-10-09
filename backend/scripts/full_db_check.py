import json
import os

import psycopg2
from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(os.path.dirname(__file__)), ".env"))
db_url = os.environ.get("SUPABASE_DB_URL")

results = {}

try:
    conn = psycopg2.connect(db_url)
    conn.autocommit = True
    cursor = conn.cursor()

    # Check counts
    cursor.execute("SELECT COUNT(*) FROM books;")
    results['books'] = cursor.fetchone()[0]

    cursor.execute("SELECT COUNT(*) FROM book_embeddings;")
    results['embeddings'] = cursor.fetchone()[0]
    results['missing'] = results['books'] - results['embeddings']

    # Check dimensions and model
    cursor.execute("SELECT embedding, model_version FROM book_embeddings LIMIT 1;")
    row = cursor.fetchone()
    if row:
        emb_str, model_ver = row
        # emb_str is a vector (string representation in psycopg2 like '[0.1, 0.2, ...]')
        dim = len(emb_str[1:-1].split(',')) if emb_str else 0
        results['dimension'] = dim
        results['model'] = model_ver

    # Check duplicates
    cursor.execute("SELECT book_id, COUNT(*) FROM book_embeddings GROUP BY book_id HAVING COUNT(*) > 1;")
    dups = cursor.fetchall()
    results['duplicates'] = len(dups)

    # Check index and HNSW
    cursor.execute("""
        SELECT indexname, indexdef
        FROM pg_indexes
        WHERE tablename = 'book_embeddings';
    """)
    indexes = cursor.fetchall()
    results['indexes'] = indexes

    # Run EXPLAIN ANALYZE for match_query_embeddings if it exists, or just a similar query.
    # To do this, we can select a random embedding from the db and query it.
    if row:
        cursor.execute(f"EXPLAIN ANALYZE SELECT book_id FROM book_embeddings ORDER BY embedding <#> '{emb_str}' LIMIT 5;")
        explain = cursor.fetchall()
        results['explain'] = [e[0] for e in explain]

    print(json.dumps(results, indent=2))

except Exception as e:
    print(f"DB Error: {e}")
