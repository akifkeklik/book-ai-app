import os
import sys

# Set up paths and environment
sys.path.append(os.path.abspath(os.path.dirname(os.path.dirname(__file__))))
from dotenv import load_dotenv

load_dotenv('.env')

from container import container


def test_rag():
    print("Executing RAG E2E test...")
    result = container.process_rag_query_uc.execute("I love fantasy books with magic and dragons.")

    print("\nResult:")
    print("Status:", result.get("status"))
    print("Answer length:", len(result.get("answer", "")))
    print("Referenced books count:", len(result.get("referenced_books", [])))
    print("\nAnswer Snippet:")
    print(result.get("answer", "")[:500])

if __name__ == "__main__":
    test_rag()
