import json
import logging
from unittest.mock import MagicMock, patch
import pytest

from backend.app import create_app
from backend.infrastructure.logging.structured_logger import JSONFormatter
from backend.application.use_cases.ai_rag import ProcessRagQueryUseCase
from backend.application.use_cases.recommendations import GetRecommendationsUseCase

@pytest.fixture
def app():
    app = create_app()
    app.config["TESTING"] = True
    app.config["PROPAGATE_EXCEPTIONS"] = False

    # Route for testing global error handler
    @app.route("/api/test-error")
    def test_error():
        raise Exception("SuperSecretPassword=12345 Failed to connect to DB")

    return app

@pytest.fixture
def client(app):
    return app.test_client()

def test_request_correlation_id(client):
    # Test without provided X-Request-Id
    resp = client.get("/api/health/ready")
    assert resp.status_code in (200, 503)
    assert "X-Request-Id" in resp.headers
    req_id = resp.headers["X-Request-Id"]
    assert len(req_id) > 10

    # Test with provided X-Request-Id
    custom_id = "test-custom-request-id-999"
    resp2 = client.get("/api/health/ready", headers={"X-Request-Id": custom_id})
    assert resp2.headers["X-Request-Id"] == custom_id

def test_global_error_handler_and_redaction(client, caplog):
    caplog.set_level(logging.ERROR)
    
    resp = client.get("/api/test-error")
    assert resp.status_code == 500
    data = resp.get_json()
    assert data["error"] == "Internal server error"
    assert "request_id" in data
    assert "12345" not in str(data)

    # Check logs for redaction
    log_records = [r for r in caplog.records if r.levelname == "ERROR" and r.name != "werkzeug"]
    assert len(log_records) > 0
    
    formatter = JSONFormatter()
    for record in log_records:
        formatted = formatter.format(record)
        # The exception string should be redacted
        assert "12345" not in formatted
        assert "***REDACTED***" in formatted

def test_health_readiness(client):
    # Liveness
    resp = client.get("/api/health")
    assert resp.status_code == 200
    assert resp.get_json()["status"] == "healthy"
    
    # Readiness
    resp = client.get("/api/health/ready")
    # Might be 200 or 503 depending on DB connection in test
    assert resp.status_code in (200, 503)
    data = resp.get_json()
    assert "status" in data
    assert "secret" not in str(data).lower()
    assert "password" not in str(data).lower()

def test_ai_rag_observability_metrics(caplog):
    caplog.set_level(logging.INFO)
    
    embedding_port = MagicMock()
    embedding_port.generate_embedding.return_value = [0.1, 0.2]
    
    book_data_port = MagicMock()
    book_data_port.match_query_embeddings.return_value = {"123": 0.9}
    
    recommender = MagicMock()
    recommender.recommend.return_value = [{"title": "Test Book", "isbn13": "123"}]
    
    enrichment_service = MagicMock()
    enrichment_service.enrich.return_value = [{"title": "Test Book", "isbn13": "123"}]
    
    llm_port = MagicMock()
    llm_port.generate_response.return_value = "This is a generated answer."
    
    uc = ProcessRagQueryUseCase(
        embedding_port=embedding_port,
        book_data_port=book_data_port,
        interaction_repo=None,
        recommender=recommender,
        enrichment_service=enrichment_service,
        llm_port=llm_port
    )
    
    result = uc.execute("I want a sci-fi book")
    assert result["status"] == "success"
    
    # Find the log event
    rag_logs = [r for r in caplog.records if "RAG request successful" in r.getMessage()]
    assert len(rag_logs) == 1
    record = rag_logs[0]
    extra = record.extra_data
    
    assert "embedding_latency_ms" in extra
    assert "retrieval_latency_ms" in extra
    assert "llm_latency_ms" in extra
    assert "total_rag_latency_ms" in extra
    assert "candidate_count" in extra
    assert extra["candidate_count"] == 1
    
    # Check that prompts are not logged
    assert "prompt" not in str(extra).lower()
    assert "I want a sci-fi book" not in str(extra).lower()

def test_recommendation_observability_metrics(caplog):
    caplog.set_level(logging.INFO)
    
    recommender = MagicMock()
    recommender.recommend.return_value = [{"title": "Dune", "isbn13": "123"}]
    
    enrichment = MagicMock()
    enrichment.enrich.return_value = [{"title": "Dune", "isbn13": "123"}]
    
    uc = GetRecommendationsUseCase(recommender, enrichment)
    result = uc.execute("Dune")
    
    rec_logs = [r for r in caplog.records if "Recommendation generated" in r.getMessage()]
    assert len(rec_logs) == 1
    extra = rec_logs[0].extra_data
    
    assert "recommendation_latency_ms" in extra
    assert extra["seed"] == "Dune"
    assert extra["count"] == 1
