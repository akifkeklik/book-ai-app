"""
Supabase configuration diagnostics.

Classifies Supabase API keys and connection failures so errors say *what* is wrong (missing URL,
missing key, wrong key format, SDK incompatibility, authentication, network, permission/RLS)
without ever including a secret value. Only key *kinds* (e.g. "publishable") are reported.

Why this exists: supabase-py < 2.18 validates the API key client-side with a JWT-shaped regex
and raises a bare "Invalid API key" for the newer opaque keys (``sb_publishable_...``), before any
request is made. That message is indistinguishable from a real authentication failure.
"""

from __future__ import annotations

import base64
import binascii
import json
import re
from functools import lru_cache
from typing import Optional
from urllib.parse import urlsplit

# Key kinds returned by classify_supabase_key()
MISSING = "missing"
PUBLISHABLE = "publishable"            # sb_publishable_...  (new low-privilege key)
SECRET = "secret"                      # sb_secret_...       (new elevated key; never for clients)
LEGACY_ANON = "legacy_anon"            # JWT with role=anon
LEGACY_SERVICE_ROLE = "legacy_service_role"  # JWT with role=service_role (bypasses RLS)
LEGACY_JWT = "legacy_jwt"              # JWT-shaped, role unknown
MALFORMED = "malformed"

ELEVATED_KINDS = (SECRET, LEGACY_SERVICE_ROLE)

# First supabase-py release verified (from the published wheels) to have dropped the JWT regex.
OPAQUE_KEY_MIN_SDK = "2.18"

_JWT_RE = re.compile(r"^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*$")


class SupabaseConfigError(RuntimeError):
    """A Supabase configuration problem. ``reason`` is a stable machine-readable code and the
    message is safe to log (it never contains key values or credentials)."""

    def __init__(self, reason: str, message: str):
        super().__init__(message)
        self.reason = reason


def _jwt_role(key: str) -> Optional[str]:
    try:
        payload = key.split(".")[1]
        payload += "=" * (-len(payload) % 4)
        claims = json.loads(base64.urlsafe_b64decode(payload.encode("ascii")))
        role = claims.get("role") if isinstance(claims, dict) else None
        return str(role) if role else None
    except (IndexError, ValueError, binascii.Error, UnicodeError):
        return None


def classify_supabase_key(key: Optional[str]) -> str:
    """Kind of a Supabase API key, judged from its shape only (no network, no verification)."""
    value = (key or "").strip()
    if not value:
        return MISSING
    if value.startswith("sb_publishable_"):
        return PUBLISHABLE
    if value.startswith("sb_secret_"):
        return SECRET
    if _JWT_RE.match(value):
        role = _jwt_role(value)
        if role == "anon":
            return LEGACY_ANON
        if role == "service_role":
            return LEGACY_SERVICE_ROLE
        return LEGACY_JWT
    return MALFORMED


def installed_sdk_version() -> str:
    try:
        from importlib.metadata import version

        return version("supabase")
    except Exception:
        return "unknown"


@lru_cache(maxsize=1)
def sdk_accepts_opaque_keys() -> bool:
    """Whether the installed supabase-py accepts ``sb_publishable_`` keys. Probed behaviourally:
    constructing a client performs no network I/O, it only runs the SDK's local validation."""
    try:
        from supabase import create_client

        create_client("https://example.supabase.co", "sb_publishable_compatibilityprobe")
        return True
    except Exception:
        return False


def validate_supabase_config(url: Optional[str], key: Optional[str], key_name: str = "SUPABASE_ANON_KEY") -> str:
    """Raises SupabaseConfigError for configuration that cannot work; returns the key kind."""
    url = (url or "").strip()
    if not url:
        raise SupabaseConfigError("missing_url", "SUPABASE_URL is not set.")
    parts = urlsplit(url)
    if parts.scheme not in ("http", "https") or not parts.netloc:
        raise SupabaseConfigError("invalid_url", "SUPABASE_URL must be an http(s) URL such as https://<project-ref>.supabase.co.")

    kind = classify_supabase_key(key)
    if kind == MISSING:
        raise SupabaseConfigError("missing_key", f"{key_name} is not set.")
    if kind in ELEVATED_KINDS:
        raise SupabaseConfigError(
            "elevated_key_not_allowed",
            f"{key_name} holds an elevated key ({kind}); it bypasses Row Level Security and must not be "
            f"used here. Use the project's publishable key or legacy 'anon' key instead.",
        )
    if kind == PUBLISHABLE and not sdk_accepts_opaque_keys():
        raise SupabaseConfigError(
            "sdk_incompatible_key",
            f"{key_name} is a publishable key (sb_publishable_...), but the installed supabase-py "
            f"{installed_sdk_version()} only accepts legacy JWT API keys (opaque keys need supabase-py "
            f">= {OPAQUE_KEY_MIN_SDK}). Either set {key_name} to the project's legacy 'anon' key "
            f"(Supabase Dashboard > Project Settings > API Keys > Legacy API keys), or upgrade supabase-py.",
        )
    return kind


def create_supabase_client(url: Optional[str], key: Optional[str], key_name: str = "SUPABASE_ANON_KEY"):
    """create_client() with configuration checks and secret-free, categorised errors."""
    kind = validate_supabase_config(url, key, key_name)
    from supabase import create_client

    try:
        return create_client(url.strip(), key.strip())
    except Exception as e:
        if "Invalid API key" in str(e):
            raise SupabaseConfigError(
                "invalid_key_format",
                f"supabase-py {installed_sdk_version()} rejected {key_name} (key kind: {kind}) before "
                f"sending any request; check that the value was copied completely.",
            ) from None
        raise SupabaseConfigError(
            "client_init_failed", f"Supabase client could not be created: {type(e).__name__}"
        ) from None


# ── Connection failure classification ───────────────────────────────────────────────────────────

_AUTH_MARKERS = ("password authentication failed", "authentication failed", "tenant or user not found",
                 "no pg_hba.conf entry", "invalid password", "role \"", "sasl")
_NETWORK_MARKERS = ("could not translate host name", "timeout expired", "timed out", "connection refused",
                    "could not connect", "network is unreachable", "server closed the connection",
                    "no route to host", "name or service not known", "connection reset")


def redact(text: str, *secrets: Optional[str]) -> str:
    """Removes the given secrets (and the password inside any URL among them) from text."""
    out = str(text)
    for secret in secrets:
        if not secret:
            continue
        try:
            password = urlsplit(secret).password
        except ValueError:
            password = None
        for value in (secret, password):
            if value and len(value) >= 4:
                out = out.replace(value, "<redacted>")
    return out


def classify_db_error(exc: BaseException) -> str:
    """'permission' | 'auth' | 'network' | 'database' for a psycopg2 (or similar) exception."""
    if getattr(exc, "pgcode", None) == "42501" or type(exc).__name__ == "InsufficientPrivilege":
        return "permission"
    message = str(exc).lower()
    if "permission denied" in message or "row-level security" in message:
        return "permission"
    if any(m in message for m in _AUTH_MARKERS):
        return "auth"
    if any(m in message for m in _NETWORK_MARKERS):
        return "network"
    return "database"


def classify_rest_status(status: int, body: str = "") -> str:
    """'ok' | 'auth' | 'permission' | 'not_found' | 'error' for a PostgREST response."""
    if 200 <= status < 300:
        return "ok"
    if status == 401:
        # PostgREST answers 401 with code 42501 when the role lacks a grant.
        return "permission" if "42501" in body else "auth"
    if status == 403:
        return "permission"
    if status == 404:
        return "not_found"
    return "error"


def check_rest_read(url: str, key: str, table: str = "books", timeout: float = 15.0) -> tuple:
    """Minimal read-only PostgREST check (GET one row). Returns (category, safe detail)."""
    import requests

    endpoint = f"{url.strip().rstrip('/')}/rest/v1/{table}"
    try:
        r = requests.get(endpoint, params={"select": "*", "limit": "1"},
                         headers={"apikey": key.strip()}, timeout=timeout)
    except requests.RequestException as e:
        return "network", f"{type(e).__name__} while reaching the Supabase REST API"
    category = classify_rest_status(r.status_code, r.text)
    detail = f"HTTP {r.status_code}"
    if category != "ok":
        detail += f": {redact(r.text[:200], key)}"
    return category, detail
