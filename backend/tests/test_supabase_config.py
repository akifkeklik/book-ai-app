"""Supabase configuration diagnostics: key classification, client creation, safe errors."""

import base64
import json
import logging
from unittest.mock import MagicMock, patch

import pytest
from backend.infrastructure.persistence import supabase_config as sc


def _jwt(claims: dict) -> str:
    def seg(obj):
        return base64.urlsafe_b64encode(json.dumps(obj).encode()).rstrip(b"=").decode()
    return f"{seg({'alg': 'HS256', 'typ': 'JWT'})}.{seg(claims)}.signature_part"


PUBLISHABLE = "sb_publishable_" + "A1b2C3d4" * 4
SECRET = "sb_secret_" + "Z9y8X7w6" * 4
ANON_JWT = _jwt({"role": "anon", "ref": "abc"})
SERVICE_JWT = _jwt({"role": "service_role", "ref": "abc"})
URL = "https://abc.supabase.co"


@pytest.mark.parametrize("key,kind", [
    (None, sc.MISSING),
    ("   ", sc.MISSING),
    (PUBLISHABLE, sc.PUBLISHABLE),
    (f"  {PUBLISHABLE}\n", sc.PUBLISHABLE),
    (SECRET, sc.SECRET),
    (ANON_JWT, sc.LEGACY_ANON),
    (SERVICE_JWT, sc.LEGACY_SERVICE_ROLE),
    ("aaa.bbb.ccc", sc.LEGACY_JWT),
    ("not-a-key", sc.MALFORMED),
])
def test_classify_supabase_key(key, kind):
    assert sc.classify_supabase_key(key) == kind


def test_installed_sdk_2_3_rejects_publishable_keys_locally():
    """Documents the root cause: supabase-py 2.3.x validates keys with a JWT-only regex."""
    from supabase import create_client

    if sc.sdk_accepts_opaque_keys():
        pytest.skip("installed supabase-py accepts opaque keys")
    with pytest.raises(Exception, match="Invalid API key"):
        create_client(URL, PUBLISHABLE)


@pytest.mark.parametrize("url,key,reason", [
    ("", ANON_JWT, "missing_url"),
    ("abc.supabase.co", ANON_JWT, "invalid_url"),
    (URL, "", "missing_key"),
    (URL, SECRET, "elevated_key_not_allowed"),
    (URL, SERVICE_JWT, "elevated_key_not_allowed"),
])
def test_validate_rejects_unusable_config(url, key, reason):
    with pytest.raises(sc.SupabaseConfigError) as exc:
        sc.validate_supabase_config(url, key)
    assert exc.value.reason == reason
    if key:
        assert key not in str(exc.value)


def test_publishable_key_with_old_sdk_gives_actionable_error():
    with patch.object(sc, "sdk_accepts_opaque_keys", return_value=False):
        with pytest.raises(sc.SupabaseConfigError) as exc:
            sc.create_supabase_client(URL, PUBLISHABLE)
    assert exc.value.reason == "sdk_incompatible_key"
    message = str(exc.value)
    assert PUBLISHABLE not in message
    assert "Legacy API keys" in message and sc.OPAQUE_KEY_MIN_SDK in message


def test_publishable_key_accepted_when_sdk_supports_it():
    client = MagicMock()
    with patch.object(sc, "sdk_accepts_opaque_keys", return_value=True), \
            patch("supabase.create_client", return_value=client) as create:
        assert sc.create_supabase_client(URL, f" {PUBLISHABLE} ") is client
    create.assert_called_once_with(URL, PUBLISHABLE)


def test_legacy_anon_key_creates_real_client():
    assert sc.create_supabase_client(URL, ANON_JWT) is not None


def test_sdk_rejection_is_translated_without_leaking_key():
    with patch("supabase.create_client", side_effect=Exception("Invalid API key")):
        with pytest.raises(sc.SupabaseConfigError) as exc:
            sc.create_supabase_client(URL, "aaa.bbb.ccc")
    assert exc.value.reason == "invalid_key_format"
    assert "aaa.bbb.ccc" not in str(exc.value)


def test_container_logs_reason_without_secret(monkeypatch, caplog):
    from backend.config import Config
    from backend.container import Container

    monkeypatch.setattr(Config, "SUPABASE_URL", URL)
    monkeypatch.setattr(Config, "SUPABASE_ANON_KEY", PUBLISHABLE)
    with patch.object(sc, "sdk_accepts_opaque_keys", return_value=False), caplog.at_level(logging.WARNING):
        container = Container(database_url="postgresql://unused")
    assert container.supabase is None
    assert "[sdk_incompatible_key]" in caplog.text
    assert PUBLISHABLE not in caplog.text


@pytest.mark.parametrize("message,category", [
    ('FATAL: password authentication failed for user "postgres.x"', "auth"),
    ("FATAL: Tenant or user not found", "auth"),
    ('could not translate host name "db.x" to address', "network"),
    ("connection to server failed: Connection refused", "network"),
    ("timeout expired", "network"),
    ("permission denied for table book_embeddings", "permission"),
    ('new row violates row-level security policy for table "book_embeddings"', "permission"),
    ("syntax error at or near", "database"),
])
def test_classify_db_error(message, category):
    assert sc.classify_db_error(Exception(message)) == category


def test_classify_db_error_uses_pgcode():
    exc = Exception("denied")
    exc.pgcode = "42501"
    assert sc.classify_db_error(exc) == "permission"


def test_redact_removes_url_and_password():
    url = "postgresql://user:hunter2pass@host:5432/db"
    out = sc.redact(f"failed for {url} with hunter2pass", url)
    assert "hunter2pass" not in out and url not in out


@pytest.mark.parametrize("status,body,category", [
    (200, "[]", "ok"),
    (401, '{"message":"Invalid API key"}', "auth"),
    (401, '{"code":"42501","message":"permission denied for table books"}', "permission"),
    (403, "", "permission"),
    (404, "", "not_found"),
    (500, "", "error"),
])
def test_classify_rest_status(status, body, category):
    assert sc.classify_rest_status(status, body) == category


def test_check_rest_read_network_failure_is_safe():
    import requests

    with patch("requests.get", side_effect=requests.ConnectionError(f"boom {PUBLISHABLE}")):
        category, detail = sc.check_rest_read(URL, PUBLISHABLE)
    assert category == "network"
    assert PUBLISHABLE not in detail


def test_check_rest_read_sends_key_only_as_apikey_header():
    response = MagicMock(status_code=200, text="[]")
    with patch("requests.get", return_value=response) as get:
        assert sc.check_rest_read(URL, PUBLISHABLE) == ("ok", "HTTP 200")
    _, kwargs = get.call_args
    assert kwargs["headers"] == {"apikey": PUBLISHABLE}
    assert kwargs["params"]["limit"] == "1"
