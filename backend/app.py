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
from .routes.routes import books_bp

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
    app.register_blueprint(books_bp, url_prefix="/api")

    # ── Security Middleware ──────────────────────────────────────────────────
    @app.before_request
    def before_request_hook():
        # Generate Request ID
        g.request_id = request.headers.get("X-Request-Id", str(uuid.uuid4()))
        g.start_time = time.time()

        # Don't enforce API keys in unit/integration tests
        if app.config.get("TESTING", False):
            return None

        # Allow root manifest and health checks without key potentially
        if request.path == "/" or request.path == "/api/health":
            return None

        if request.path.startswith("/api/"):
            # Misconfiguration guard: never run "open" by accident
            if not app.config.get("LIBRIS_API_KEY"):
                log_event(__name__, logging.ERROR, msg="LIBRIS_API_KEY is not set. Refusing to serve protected endpoints.")
                return jsonify({"error": "Server misconfigured"}), 503

            api_key = request.headers.get("X-Api-Key")
            if not api_key or api_key != app.config["LIBRIS_API_KEY"]:
                log_event(__name__, logging.WARNING, msg="Unauthorized access attempt", ip=request.remote_addr)
                return jsonify({"error": "Unauthorized: Invalid or missing API Key"}), 401

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
