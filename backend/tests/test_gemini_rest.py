from unittest.mock import MagicMock

import pytest
from backend.infrastructure.llm.gemini_rest import DEFAULT_TEXT_MODEL, GeminiError, GeminiRestClient


def _resp(status, payload):
    r = MagicMock()
    r.status_code = status
    r.json.return_value = payload
    r.text = str(payload)
    return r


def _client(*responses):
    session = MagicMock()
    session.post.side_effect = list(responses)
    return GeminiRestClient("secret-key", session=session, retry_wait_seconds=0), session


def test_generates_text_with_flash_lite_and_header_auth():
    client, session = _client(_resp(200, {"candidates": [{"content": {"parts": [{"text": " Why do habits compound? "}]}}]}))
    assert client.generate_text("note", system_instruction="Write a question") == "Why do habits compound?"
    url = session.post.call_args.args[0]
    kwargs = session.post.call_args.kwargs
    assert url.endswith(f"models/{DEFAULT_TEXT_MODEL}:generateContent")
    assert DEFAULT_TEXT_MODEL == "gemini-3.5-flash-lite"
    assert "secret-key" not in url, "the API key must never be placed in the URL"
    assert kwargs["headers"]["x-goog-api-key"] == "secret-key"
    assert kwargs["json"]["systemInstruction"]["parts"][0]["text"] == "Write a question"


def test_retries_once_on_free_tier_quota_then_succeeds():
    client, session = _client(
        _resp(429, {"error": {"message": "quota"}}),
        _resp(200, {"candidates": [{"content": {"parts": [{"text": "Q?"}]}}]}),
    )
    assert client.generate_text("note") == "Q?"
    assert session.post.call_count == 2


def test_persistent_errors_raise_without_leaking_the_key():
    client, _ = _client(_resp(429, {"error": {"message": "quota"}}), _resp(429, {"error": {"message": "quota"}}))
    with pytest.raises(GeminiError) as err:
        client.generate_text("note")
    assert err.value.status == 429 and "secret-key" not in str(err.value)


def test_blocked_responses_return_none():
    client, _ = _client(_resp(200, {"candidates": []}))
    assert client.generate_text("note") is None


def test_embeddings_use_models_prefix_and_return_values():
    client, session = _client(_resp(200, {"embedding": {"values": [0.1, 0.2]}}))
    assert client.embed("text", "models/gemini-embedding-2") == [0.1, 0.2]
    assert session.post.call_args.args[0].endswith("models/gemini-embedding-2:embedContent")
