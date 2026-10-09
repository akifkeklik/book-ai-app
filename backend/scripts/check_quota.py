import os
import sys

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from services.embedding_service import EmbeddingService


def check_quota():
    embedding_service = EmbeddingService(book_data_port=None)
    if not embedding_service.is_configured():
        print("EmbeddingService is not configured.")
        sys.exit(1)

    print("Sending diagnostic embedding request...")
    embedding = embedding_service.generate_embedding("Test diagnostic string for quota check.")
    if embedding:
        print("SUCCESS: Quota is available. Embedding length:", len(embedding))
    else:
        print("FAILED: Embedding generation returned None or failed. Quota might be blocked.")
        sys.exit(1)

if __name__ == "__main__":
    check_quota()
