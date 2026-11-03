"""
Cryptographic JWT Authentication Adapter for Libris.
Implements AuthPort protocol to cryptographically verify Bearer tokens.
Supports HMAC-SHA256 (HS256) signature verification, expiration, audience, and subject validation.
"""

import logging
from typing import List, Optional

import jwt

logger = logging.getLogger(__name__)


class AuthUser:
    """Represents an authenticated user identity resolved from a verified token."""

    def __init__(self, id: str, email: Optional[str] = None, role: Optional[str] = None):
        if not id or not isinstance(id, str):
            raise ValueError("AuthUser id must be a non-empty string")
        self.id = id.strip()
        self.email = email
        self.role = role

    def __repr__(self):
        return f"<AuthUser id={self.id}>"


class SupabaseJwtAuthPort:
    """
    Cryptographic JWT verification adapter implementing AuthPort.
    Verifies tokens using HMAC-SHA256 with the configured secret.
    Enforces signature verification, expiration check, audience check, and optional issuer check.
    Extracts the 'sub' claim as the canonical user ID.
    Fails closed on any validation failure.
    """

    def __init__(
        self,
        secret: str,
        algorithms: Optional[List[str]] = None,
        audience: Optional[str] = "authenticated",
        issuer: Optional[str] = None,
    ):
        if not secret or not isinstance(secret, str) or not secret.strip():
            raise ValueError("SupabaseJwtAuthPort requires a non-empty secret")
        self._secret = secret.strip()
        self._algorithms = algorithms or ["HS256"]
        self._audience = audience
        self._issuer = issuer

    def verify_token(self, token: str) -> AuthUser:
        if not token or not isinstance(token, str):
            raise ValueError("Token must be a non-empty string")
        token = token.strip()
        if not token:
            raise ValueError("Token cannot be empty")

        decode_options = {
            "verify_signature": True,
            "verify_exp": True,
            "require": ["exp", "sub"],
        }
        if self._audience:
            decode_options["verify_aud"] = True
        else:
            decode_options["verify_aud"] = False

        if self._issuer:
            decode_options["verify_iss"] = True
        else:
            decode_options["verify_iss"] = False

        try:
            payload = jwt.decode(
                token,
                self._secret,
                algorithms=self._algorithms,
                audience=self._audience,
                issuer=self._issuer,
                options=decode_options,
            )
        except jwt.ExpiredSignatureError as e:
            raise ValueError(f"Token has expired: {e}") from e
        except jwt.InvalidAudienceError as e:
            raise ValueError(f"Token audience mismatch: {e}") from e
        except jwt.InvalidIssuerError as e:
            raise ValueError(f"Token issuer mismatch: {e}") from e
        except jwt.InvalidSignatureError as e:
            raise ValueError(f"Token signature verification failed: {e}") from e
        except jwt.DecodeError as e:
            raise ValueError(f"Malformed or undecodable token: {e}") from e
        except Exception as e:
            raise ValueError(f"Token verification failed: {e}") from e

        sub = payload.get("sub")
        if not sub or not isinstance(sub, str) or not sub.strip():
            raise ValueError("Token missing or invalid 'sub' claim")

        return AuthUser(
            id=sub.strip(),
            email=payload.get("email"),
            role=payload.get("role"),
        )
