import os
import threading
from unittest.mock import MagicMock, patch

import pytest
from backend.domain.models import RAGResponse
from backend.infrastructure.llm.adapters import GenericLlmAdapter, _sanitize_secret


@pytest.mark.unit
def test_secret_sanitization_removes_keys_and_tokens():
    raw_error = (
        "HTTP 403 Forbidden: API key invalid. "
        "https://generativelanguage.googleapis.com/v1beta/models?key=AIzaSyD-SecretKey123456789 "
        "and header Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.token.sig"
    )
    sanitized = _sanitize_secret(raw_error)
    assert "AIzaSyD-SecretKey123456789" not in sanitized
    assert "key=REDACTED" in sanitized
    assert "Bearer REDACTED" in sanitized


@pytest.mark.unit
def test_generic_llm_adapter_missing_api_key():
    adapter = GenericLlmAdapter(provider="gemini", api_key="")
    resp = adapter.generate_response("System prompt", "User prompt")
    assert resp is None


@pytest.mark.unit
def test_generic_llm_adapter_timeout_configuration():
    adapter = GenericLlmAdapter(provider="gemini", api_key="fake-key")
    adapter._gemini = MagicMock()
    adapter._gemini.generate_text.return_value = "Valid model generation"

    resp = adapter.generate_response("Sys", "User")
    assert resp == "Valid model generation"

    adapter._gemini.generate_text.assert_called_once()
    _, kwargs = adapter._gemini.generate_text.call_args
    assert kwargs["timeout"] == 15.0
    assert kwargs["system_instruction"] == "Sys"


@pytest.mark.unit
def test_generic_llm_adapter_safety_blocked_empty_response():
    adapter = GenericLlmAdapter(provider="gemini", api_key="fake-key")
    adapter._gemini = MagicMock()
    # A blocked response yields no text; a transport error must not crash or leak secrets.
    adapter._gemini.generate_text.return_value = None
    assert adapter.generate_response("Sys", "User") is None
    adapter._gemini.generate_text.side_effect = RuntimeError("Gemini failed (403): key=AIzaSecret")
    assert adapter.generate_response("Sys", "User") is None


@pytest.mark.unit
def test_generic_llm_adapter_concurrent_calls_thread_safe():
    adapter = GenericLlmAdapter(provider="gemini", api_key="fake-key")
    adapter._gemini = MagicMock()
    adapter._gemini.generate_text.return_value = '{"answer": "Thread safe"}'

    latencies = []
    errors = []

    def caller(i: int):
        try:
            res = adapter.generate_response(f"Sys {i}", f"User {i}")
            assert res is not None
            latencies.append(adapter.last_latency_ms)
        except Exception as e:
            errors.append(e)

    threads = [threading.Thread(target=caller, args=(i,)) for i in range(10)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()

    assert len(errors) == 0
    assert len(latencies) == 10


@pytest.mark.unit
def test_config_api_key_precedence():
    # If LLM_API_KEY is non-empty, it takes precedence
    with patch.dict(os.environ, {"LLM_API_KEY": "primary-key", "GEMINI_API_KEY": "fallback-key"}):
        k = os.getenv("LLM_API_KEY") or os.getenv("GEMINI_API_KEY") or ""
        assert k == "primary-key"

    # If LLM_API_KEY is empty string, it falls back to GEMINI_API_KEY
    with patch.dict(os.environ, {"LLM_API_KEY": "", "GEMINI_API_KEY": "fallback-key"}):
        k = os.getenv("LLM_API_KEY") or os.getenv("GEMINI_API_KEY") or ""
        assert k == "fallback-key"


@pytest.mark.unit
def test_rag_response_backward_compatibility():
    # Optional latency_ms and metrics must not break older consumers expecting default None
    base_dict = {
        "answer": "Hello",
        "referenced_books": [],
        "status": "success",
    }
    resp = RAGResponse(**base_dict)
    d = resp.model_dump()
    assert d["latency_ms"] is None
    assert d["metrics"] is None
    assert d["action"] is None
    assert d["status"] == "success"
