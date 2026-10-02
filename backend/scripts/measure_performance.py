import time
import statistics
from backend.app import create_app

app = create_app()
client = app.test_client()

from unittest.mock import patch
patch("backend.routes.routes._svc.verify_token", return_value=type("User", (), {"id": "test_user"})).start()
token = "mock_token"
headers = {"Authorization": f"Bearer {token}"}

def measure_endpoint(name, method, url, iterations=5, **kwargs):
    latencies = []
    status = None
    for _ in range(iterations):
        t0 = time.time()
        if method == "GET":
            res = client.get(url, **kwargs)
        else:
            res = client.post(url, **kwargs)
        t1 = time.time()
        latencies.append((t1 - t0) * 1000)
        status = res.status_code

    print(f"--- {name} ---")
    print(f"Status: {status}")
    print(f"Mean Latency: {statistics.mean(latencies):.2f} ms")
    print(f"Min Latency: {min(latencies):.2f} ms")
    print(f"Max Latency: {max(latencies):.2f} ms")
    print("")

with app.app_context():
    # Warmup
    client.get("/api/books/popular")

    measure_endpoint("Popular Books", "GET", "/api/books/popular")
    measure_endpoint("Search Books", "GET", "/api/books/search?q=Harry+Potter")
    # measure_endpoint("Book Details", "GET", "/api/books/9780439708180")
    measure_endpoint("Personalized Recs", "GET", "/api/books/recommendations/personalized", headers=headers)
    measure_endpoint("AI/RAG Query", "POST", "/api/books/chat", json={"query": "sci-fi books about space"}, headers=headers)
