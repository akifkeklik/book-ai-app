"""
Book AI Recommendation API
Flask factory application with CORS, error handlers, and blueprint registration.
"""

import logging
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

    # ── CORS ──────────────────────────────────────────────────────────────────
    # Allow Flutter Web / browsers to send our API key header.
    CORS(
        app,
        origins=config_class.ALLOWED_ORIGINS,
        supports_credentials=True,
        allow_headers=["Content-Type", "X-Api-Key"],
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

        # Allow root manifest, health checks, and docs without key
        if request.path == "/" or request.path == "/api/health" or request.path.startswith("/api/docs") or request.path == "/health/ready":
            return None

        if request.path.startswith("/api/"):
            # Misconfiguration guard: never run "open" by accident
            if not app.config.get("LIBRIS_API_KEY"):
                log_event(__name__, logging.ERROR, msg="LIBRIS_API_KEY is not set. Refusing to serve protected endpoints.")
                return jsonify({"error": "Server misconfigured"}), 503

            # 1. Server-to-Server Authentication via X-Api-Key
            api_key = request.headers.get("X-Api-Key")
            if api_key:
                if api_key == app.config["LIBRIS_API_KEY"]:
                    g.is_server = True
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
        # Propagate request id back to client
        if hasattr(g, "request_id"):
            response.headers["X-Request-Id"] = g.request_id
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
    app.run(host="0.0.0.0", port=5000, debug=Config.DEBUG)
