"""
Measurement script for AI SSE streaming latency metrics.
Instruments:
- Time to first HTTP response byte
- Time to first SSE event (metadata)
- Time to first actual model-generated content token (chunk)
- Total generation time
Over 20 independent measurement runs.
"""

import json
import os
import sys
import time
from unittest.mock import patch

# Ensure repository root is in sys.path when executed directly
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))

from backend.app import create_app
from backend.config import Config
from backend.routes.routes import _ai_rate_limits


class MeasureConfig(Config):
    TESTING = True
    DEBUG = False
    SECRET_KEY = "measure-secret"
    LIBRIS_API_KEY = "measure-api-key"

app = create_app(MeasureConfig)

mock_rag_response = {
    "answer": "Here is a personalized recommendation of classic books including 1984 and Brave New World.",
    "referenced_books": [
        {"isbn13": "9780451524935", "title": "1984", "authors": "George Orwell"},
        {"isbn13": "9780060850524", "title": "Brave New World", "authors": "Aldous Huxley"}
    ],
    "status": "success",
    "action": None
}

runs = 20
ttfb_list = []
first_event_list = []
first_token_list = []
total_time_list = []

with app.test_client() as client:
    for run in range(runs):
        _ai_rate_limits.clear()
        with patch("backend.routes.routes._process_rag_query_uc.execute", return_value=mock_rag_response):
            t_start = time.perf_counter()
            response = client.post("/api/ai/chat/stream", json={"query": "recommend dystopian books"})

            t_first_byte = None
            t_first_event = None
            t_first_token = None
            t_total = None

            for chunk in response.response:
                now = time.perf_counter()
                if t_first_byte is None:
                    t_first_byte = (now - t_start) * 1000

                text = chunk.decode("utf-8") if isinstance(chunk, bytes) else str(chunk)
                if "event: metadata" in text and t_first_event is None:
                    t_first_event = (now - t_start) * 1000
                if "event: chunk" in text and t_first_token is None:
                    t_first_token = (now - t_start) * 1000

            t_total = (time.perf_counter() - t_start) * 1000

            ttfb_list.append(t_first_byte)
            first_event_list.append(t_first_event)
            first_token_list.append(t_first_token)
            total_time_list.append(t_total)

def stats(vals):
    s = sorted(vals)
    mean = sum(s) / len(s)
    p50 = s[len(s) // 2]
    p95 = s[int(len(s) * 0.95)]
    return {
        "min_ms": round(s[0], 2),
        "mean_ms": round(mean, 2),
        "p50_ms": round(p50, 2),
        "p95_ms": round(p95, 2),
        "max_ms": round(s[-1], 2),
    }

results = {
    "provider_identity": "Deterministic Test Double (Local RAG Simulator)",
    "provider_type": "deterministic_mock",
    "real_provider_available": False,
    "runs": runs,
    "time_to_first_byte": stats(ttfb_list),
    "time_to_first_sse_event_metadata": stats(first_event_list),
    "time_to_first_content_token": stats(first_token_list),
    "total_generation_time": stats(total_time_list)
}

print(json.dumps(results, indent=2))
