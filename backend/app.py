"""
Book AI Recommendation API
Flask factory application with CORS, error handlers, and blueprint registration.
"""

import logging

from flask import Flask, jsonify, request
from flask_cors import CORS

from config import Config
from routes.routes import books_bp

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(name)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
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
    def validate_api_key():
        # Don't enforce API keys in unit/integration tests
        if app.config.get("TESTING", False):
            return None

        # Allow root manifest and health checks without key potentially
        if request.path == "/" or request.path == "/api/health":
            return None
        
        if request.path.startswith("/api/"):
            # Misconfiguration guard: never run "open" by accident
            if not app.config.get("LIBRIS_API_KEY"):
                logger.error("LIBRIS_API_KEY is not set. Refusing to serve protected endpoints.")
                return jsonify({"error": "Server misconfigured"}), 503

            api_key = request.headers.get("X-Api-Key")
            if not api_key or api_key != app.config["LIBRIS_API_KEY"]:
                logger.warning(f"Unauthorized access attempt from {request.remote_addr}")
                return jsonify({"error": "Unauthorized: Invalid or missing API Key"}), 401
        return None

    # ── Global error handlers ─────────────────────────────────────────────────
    @app.errorhandler(404)
    def not_found(error):
        return jsonify({"error": "Resource not found"}), 404

    @app.errorhandler(405)
    def method_not_allowed(error):
        return jsonify({"error": "Method not allowed"}), 405

    @app.errorhandler(500)
    def internal_error(error):
        logger.error("Internal server error: %s", error)
        return jsonify({"error": "Internal server error"}), 500

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
