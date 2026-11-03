"""
Book AI Recommendation API
Flask factory application with CORS, error handlers, and blueprint registration.
"""

import hmac
import logging
import os
import time
import uuid

from flask import Flask, g, jsonify, request
from flask_cors import CORS

from .config import Config
from .infrastructure.logging.structured_logger import log_event, setup_logger
from .routes.routes import activity_bp, catalog_bp, discovery_bp, health_bp

setup_logger()
logger = logging.getLogger(__name__)


def create_app(config_class=Config) -> Flask:
    """Application factory."""
    app = Flask(__name__)
    app.config.from_object(config_class)

    configured_origins = app.config.get("ALLOWED_ORIGINS") or []
    if isinstance(configured_origins, str):
        configured_origins = configured_origins.split(",")
    allowed_origins = [
        origin.strip().rstrip("/")
        for origin in configured_origins
        if isinstance(origin, str) and origin.strip()
    ]

    # ── Production Security Validation ────────────────────────────────────────
    import sys
    is_pytest = "pytest" in sys.modules or bool(os.getenv("PYTEST_CURRENT_TEST"))
    enforce_prod_check = getattr(config_class, "IS_PRODUCTION", False) or (
        (
            os.getenv("FLASK_ENV", "").lower() == "production"
            or os.getenv("ENVIRONMENT", "").lower() == "production"
            or (not app.config.get("DEBUG") and not app.config.get("TESTING"))
        )
        and not is_pytest
    )
    if enforce_prod_check:
        if app.config.get("DEBUG"):
            raise ValueError(
                "Critical Security Misconfiguration: DEBUG mode cannot be enabled when running in production."
            )
        secret_key = str(app.config.get("SECRET_KEY", "")).strip()
        if not secret_key or secret_key in ("replace-with-a-long-random-string", "dev-insecure-secret-key"):
            raise ValueError(
                "Critical Security Misconfiguration: SECRET_KEY environment variable must be set "
                "to a secure random string when running in production mode."
            )
        libris_api_key = str(app.config.get("LIBRIS_API_KEY", "")).strip()
        if not libris_api_key or libris_api_key in ("replace-with-a-secure-random-api-key", "dev-insecure-api-key"):
            raise ValueError(
                "Critical Security Misconfiguration: LIBRIS_API_KEY environment variable must be set "
                "to a secure random string when running in production mode."
            )
        if not allowed_origins or "*" in allowed_origins:
            raise ValueError(
                "Critical Security Misconfiguration: ALLOWED_ORIGINS must contain explicit trusted "
                "origins in production; wildcard origins are not permitted."
            )

    app.config["ALLOWED_ORIGINS"] = allowed_origins

    # ── Reverse Proxy Middleware ──────────────────────────────────────────────
    num_proxies = int(app.config.get("NUM_PROXIES", 0))
    if num_proxies > 0:
        from werkzeug.middleware.proxy_fix import ProxyFix

        app.wsgi_app = ProxyFix(
            app.wsgi_app,
            x_for=num_proxies,
            x_proto=num_proxies,
            x_host=num_proxies,
            x_port=num_proxies,
            x_prefix=num_proxies,
        )

    # ── CORS ──────────────────────────────────────────────────────────────────
    # Allow Flutter Web / browsers to send API key, auth token, and request tracing headers.
    CORS(
        app,
        origins=allowed_origins,
        supports_credentials=True,
        allow_headers=["Content-Type", "X-Api-Key", "Authorization", "X-Request-Id"],
    )

    # ── Blueprints ────────────────────────────────────────────────────────────
    app.register_blueprint(catalog_bp, url_prefix="/api")
    app.register_blueprint(discovery_bp, url_prefix="/api")
    app.register_blueprint(activity_bp, url_prefix="/api")
    app.register_blueprint(health_bp, url_prefix="/api")

    # ── Security Middleware ──────────────────────────────────────────────────
    @app.before_request
    def before_request_hook():
        # Generate Request ID
        g.request_id = request.headers.get("X-Request-Id", str(uuid.uuid4()))
        g.start_time = time.time()
        g.is_server = False
        g.is_anon = False
        g.user_id = None
        g.jwt_token = None

        # Allow tests to bypass unless explicitly enforcing auth in test suite
        if app.config.get("TESTING", False) and not app.config.get("ENFORCE_AUTH_IN_TESTS", False):
            return None

        # Allow CORS preflight OPTIONS requests
        if request.method == "OPTIONS":
            return None

        # Allow root manifest, health checks, and docs without key
        if (
            request.path == "/"
            or request.path == "/api/health"
            or request.path == "/api/health/ready"
            or request.path == "/health/ready"
            or request.path.startswith("/api/docs")
        ):
            return None

        if request.path.startswith("/api/"):
            # 1. Server-to-Server Authentication via X-Api-Key.
            # A missing server key must not disable independent user-JWT authentication.
            api_key = request.headers.get("X-Api-Key")
            if api_key is not None:
                server_key = str(app.config.get("LIBRIS_API_KEY", "")).strip()
                if not server_key:
                    log_event(__name__, logging.ERROR, msg="LIBRIS_API_KEY is not set; rejecting X-Api-Key authentication.")
                    return jsonify({"error": "Server misconfigured"}), 503

                api_key_clean = api_key.strip()
                if not api_key_clean or not server_key:
                    log_event(__name__, logging.WARNING, msg="Unauthorized access attempt: Empty X-Api-Key", ip=request.remote_addr)
                    return jsonify({"error": "Unauthorized: Invalid API Key"}), 401

                if hmac.compare_digest(api_key_clean, server_key):
                    g.is_server = True
                    auth_header = request.headers.get("Authorization")
                    if auth_header:
                        if not auth_header.startswith("Bearer "):
                            log_event(__name__, logging.WARNING, msg="Unauthorized access attempt: Invalid auth scheme with X-Api-Key", ip=request.remote_addr)
                            return jsonify({"error": "Unauthorized: Invalid Authorization scheme"}), 401
                        token = auth_header.split(" ", 1)[1].strip()
                        if not token:
                            return jsonify({"error": "Unauthorized: Empty Bearer token"}), 401
                        anon_key = app.config.get("SUPABASE_ANON_KEY")
                        if anon_key and token == anon_key:
                            g.is_anon = True
                        else:
                            try:
                                from .routes.routes import _auth_port
                                user = _auth_port.verify_token(token) if _auth_port else None
                                if not user or not getattr(user, "id", None):
                                    return jsonify({"error": "Unauthorized: Invalid or expired Bearer token"}), 401
                                g.user_id = user.id
                                g.jwt_token = token
                                g.user = user
                            except Exception as exc:
                                log_event(__name__, logging.WARNING, msg="JWT verification failed with X-Api-Key", error=str(exc), ip=request.remote_addr)
                                return jsonify({"error": "Unauthorized: Invalid or expired Bearer token"}), 401
                    return None
                log_event(__name__, logging.WARNING, msg="Unauthorized access attempt: Invalid X-Api-Key", ip=request.remote_addr)
                return jsonify({"error": "Unauthorized: Invalid API Key"}), 401

            # 2. Bearer Token Authentication (Supabase User JWT or Anon Key)
            auth_header = request.headers.get("Authorization")
            if auth_header:
                if not auth_header.startswith("Bearer "):
                    log_event(__name__, logging.WARNING, msg="Unauthorized access attempt: Invalid auth scheme", ip=request.remote_addr)
                    return jsonify({"error": "Unauthorized: Invalid Authorization scheme"}), 401

                token = auth_header.split(" ", 1)[1].strip()
                if not token:
                    return jsonify({"error": "Unauthorized: Empty Bearer token"}), 401

                # Check if it's the known Supabase Anon Key (Anonymous browsing)
                anon_key = app.config.get("SUPABASE_ANON_KEY")
                if anon_key and token == anon_key:
                    g.is_anon = True
                    return None

                # Otherwise, verify user JWT via Auth port
                try:
                    from .routes.routes import _auth_port
                    user = _auth_port.verify_token(token) if _auth_port else None
                    if user and getattr(user, "id", None):
                        g.user_id = user.id
                        g.jwt_token = token
                        g.user = user
                        return None
                except Exception as exc:
                    log_event(__name__, logging.WARNING, msg="JWT verification failed", error=str(exc), ip=request.remote_addr)

                # Token was provided but is neither valid anon key nor valid user JWT
                return jsonify({"error": "Unauthorized: Invalid or expired Bearer token"}), 401

            log_event(__name__, logging.WARNING, msg="Unauthorized access attempt: Missing credentials", ip=request.remote_addr)
            return jsonify({"error": "Unauthorized: Missing API Key or Bearer Token"}), 401

        return None

    @app.after_request
    def log_response(response):
        from flask import g
        # Propagate request id back to client
        if hasattr(g, "request_id"):
            response.headers["X-Request-Id"] = g.request_id

        # Cache directives for privacy and CDN correctness:
        if "Cache-Control" not in response.headers:
            path = request.path
            if response.status_code >= 400:
                response.headers["Cache-Control"] = "private, no-cache, no-store, max-age=0, must-revalidate"
                response.headers["Pragma"] = "no-cache"
            else:
                is_authenticated = getattr(g, "user_id", None) is not None
                is_personalized = path.startswith("/api/recommend/personalized")
                is_mutation_or_private = (
                    path.startswith("/api/preferences")
                    or path.startswith("/api/feedback")
                    or path.startswith("/api/track")
                    or path.startswith("/api/onboarding")
                )
                if is_authenticated or is_personalized or is_mutation_or_private:
                    response.headers["Cache-Control"] = "private, no-cache, no-store, max-age=0, must-revalidate"
                    response.headers["Pragma"] = "no-cache"
                    response.headers["Vary"] = "Authorization, Cookie"
                elif path.startswith("/api/books") or path == "/api/categories" or path == "/api/recommend":
                    response.headers["Cache-Control"] = "public, max-age=300, stale-while-revalidate=600"

        # Don't log if testing or path is root/health
        if app.config.get("TESTING", False) or request.path in ("/", "/api/health"):
            return response

        duration_ms = 0
        if hasattr(g, "start_time"):
            duration_ms = round((time.time() - g.start_time) * 1000, 2)

        log_event(
            __name__,
            logging.INFO,
            msg="Request completed",
            status=response.status_code,
            duration_ms=duration_ms,
            content_length=response.content_length
        )
        return response

    # ── Global error handlers ─────────────────────────────────────────────────
    @app.errorhandler(404)
    def not_found(error):
        log_event(__name__, logging.WARNING, msg="Resource not found")
        return jsonify({"error": "Resource not found"}), 404

    @app.errorhandler(405)
    def method_not_allowed(error):
        log_event(__name__, logging.WARNING, msg="Method not allowed")
        return jsonify({"error": "Method not allowed"}), 405

    @app.errorhandler(Exception)
    def handle_global_exception(error):
        log_event(__name__, logging.ERROR, msg="Unhandled exception", exc_info=error)
        return jsonify({
            "error": "Internal server error",
            "request_id": getattr(g, "request_id", None)
        }), 500

    # ── Root manifest ─────────────────────────────────────────────────────────
    @app.route("/")
    def index():
        return jsonify(
            {
                "name": "Book AI Recommendation API",
                "version": "1.0.0",
                "status": "operational",
                "endpoints": [
                    "GET  /api/health",
                    "GET  /api/books?page=1&per_page=20",
                    "GET  /api/books/popular?limit=20",
                    "GET  /api/books/<isbn>",
                    "GET  /api/search?q=<query>&limit=20",
                    "GET  /api/recommend?book=<title>&top_n=10&hybrid=true",
                    "POST /api/track",
                ],
            }
        )

    logger.info("Flask application created.")
    return app


app = create_app()

if __name__ == "__main__":
    host = os.getenv("HOST", "127.0.0.1")
    port = int(os.getenv("PORT", "5000"))
    app.run(host=host, port=port, debug=Config.DEBUG)
