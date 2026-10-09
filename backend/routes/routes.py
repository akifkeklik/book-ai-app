"""
Flask Blueprint — all /api/* endpoints.
The BookService is instantiated once at module import time (singleton pattern).
"""

import logging
import threading
import time
from functools import wraps

from flask import Blueprint, g, jsonify, request

from ..container import container

logger = logging.getLogger(__name__)

books_bp = Blueprint("books", __name__)

# Re-exporting aliases for convenience and to avoid changing the rest of this file
_book_data_port = container.book_data_port
_auth_port = container.auth_port
_svc = container.book_service
_get_books_uc = container.get_books_uc
_search_books_uc = container.search_books_uc
_get_popular_books_uc = container.get_popular_books_uc
_get_book_details_uc = container.get_book_details_uc
_get_recommendations_uc = container.get_recommendations_uc
_get_personalized_recs_uc = container.get_personalized_recs_uc
_submit_onboarding_uc = container.submit_onboarding_uc
_submit_feedback_uc = container.submit_feedback_uc
_track_activity_uc = container.track_activity_uc
_process_rag_query_uc = container.process_rag_query_uc


def require_auth(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        auth_header = request.headers.get("Authorization")
        if not auth_header or not auth_header.startswith("Bearer "):
            return jsonify({"error": "Unauthorized: Missing or invalid Authorization header"}), 401

        token = auth_header.split(" ")[1]
        try:
            user = _auth_port.verify_token(token) if _auth_port else None
            if not user or not user.id:
                return jsonify({"error": "Unauthorized: Invalid token"}), 401
            g.user_id = user.id
            g.jwt_token = token
        except Exception as exc:
            logger.warning(f"JWT verification failed: {exc}")
            return jsonify({"error": "Unauthorized: Invalid or expired token"}), 401

        return f(*args, **kwargs)

    return decorated


def optional_auth(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        auth_header = request.headers.get("Authorization")
        if auth_header and auth_header.startswith("Bearer "):
            token = auth_header.split(" ")[1]
            try:
                user = _auth_port.verify_token(token) if _auth_port else None
                if user and user.id:
                    g.user_id = user.id
                    g.jwt_token = token
            except Exception:
                pass
        return f(*args, **kwargs)

    return decorated


# ─────────────────────────────────────────────────────────────────────────────
# Health
# ─────────────────────────────────────────────────────────────────────────────


@books_bp.route("/health", methods=["GET"])
def health_check():
    return jsonify({"status": "healthy", "service": "book-ai-api"}), 200


@books_bp.route("/docs", methods=["GET"])
def swagger_ui():
    import os

    from flask import send_from_directory

    # Serve index.html from static/swagger-ui
    static_dir = os.path.join(os.path.dirname(os.path.dirname(__file__)), "static", "swagger-ui")
    return send_from_directory(static_dir, "index.html")


@books_bp.route("/docs/<path:filename>", methods=["GET"])
def swagger_ui_files(filename):
    import os

    from flask import send_from_directory

    static_dir = os.path.join(os.path.dirname(os.path.dirname(__file__)), "static", "swagger-ui")
    return send_from_directory(static_dir, filename)


@books_bp.route("/health/ready", methods=["GET"])
def readiness_check():
    try:
        if _book_data_port and not _book_data_port.check_health():
            raise Exception("Database health check failed")
        return jsonify({"status": "ready", "service": "book-ai-api"}), 200
    except Exception as exc:
        import logging

        from .infrastructure.logging.structured_logger import log_event

        log_event(__name__, logging.ERROR, msg="Readiness check failed", error=str(exc))
        return jsonify({"status": "not_ready", "error": "Database unavailable"}), 503


@books_bp.route("/categories", methods=["GET"])
def get_categories():
    try:
        return jsonify({"categories": _svc.get_categories()}), 200
    except Exception as exc:
        raise exc


# ─────────────────────────────────────────────────────────────────────────────
# Books
# ─────────────────────────────────────────────────────────────────────────────


@books_bp.route("/books", methods=["GET"])
def get_books():
    try:
        page = max(1, int(request.args.get("page", 1)))
        per_page = min(max(1, int(request.args.get("per_page", 50))), 100)

        def safe_int(val):
            if val is not None and val.isdigit():
                return int(val)
            return None

        def safe_float(val):
            if val is not None:
                try:
                    return float(val)
                except ValueError:
                    return None
            return None

        kwargs = {
            "page": page,
            "per_page": per_page,
            "category": request.args.get("category"),
            "author": request.args.get("author"),
            "publisher": request.args.get("publisher"),
            "min_pages": safe_int(request.args.get("min_pages")),
            "max_pages": safe_int(request.args.get("max_pages")),
            "min_rating": safe_float(request.args.get("min_rating")),
            "published_from": safe_int(request.args.get("published_from")),
            "published_to": safe_int(request.args.get("published_to")),
            "sort": request.args.get("sort"),
            "order": request.args.get("order", "asc"),
        }

        return jsonify(_get_books_uc.execute(**kwargs)), 200
    except Exception as exc:
        raise exc


@books_bp.route("/books/popular", methods=["GET"])
def get_popular_books():
    try:
        # Senior Update: Increased limit for "All Books" section
        limit = min(max(1, int(request.args.get("limit", 50))), 5000)
        books = _get_popular_books_uc.execute(limit=limit)
        return jsonify({"books": books, "total": len(books)}), 200
    except Exception as exc:
        raise exc


@books_bp.route("/books/<isbn>", methods=["GET"])
def get_book_by_isbn(isbn: str):
    try:
        book = _get_book_details_uc.execute(isbn)
        if not book:
            return jsonify({"error": "Book not found"}), 404
        return jsonify({"book": book}), 200
    except Exception as exc:
        raise exc


# ─────────────────────────────────────────────────────────────────────────────
# Search
# ─────────────────────────────────────────────────────────────────────────────


@books_bp.route("/search", methods=["GET"])
def search_books():
    query = request.args.get("q", "").strip()
    if not query:
        return jsonify({"error": "Query parameter 'q' is required"}), 400
    if len(query) < 2:
        return jsonify({"error": "Query must be at least 2 characters"}), 400
    try:
        limit = min(max(1, int(request.args.get("limit", 20))), 100)
        books = _search_books_uc.execute(query=query, limit=limit)
        return jsonify({"books": books, "total": len(books), "query": query}), 200
    except Exception as exc:
        raise exc


# ─────────────────────────────────────────────────────────────────────────────
# Recommendations
# ─────────────────────────────────────────────────────────────────────────────


@books_bp.route("/recommend", methods=["GET"])
def get_recommendations():
    book_title = request.args.get("book", "").strip()
    if not book_title:
        return jsonify({"error": "Query parameter 'book' is required"}), 400
    try:
        top_n = min(max(1, int(request.args.get("top_n", 10))), 50)
        use_hybrid = request.args.get("hybrid", "true").lower() != "false"
        recommendations = _get_recommendations_uc.execute(
            book_title=book_title,
            top_n=top_n,
            use_hybrid=use_hybrid,
        )
        if not recommendations:
            return jsonify(
                {
                    "error": f"Book '{book_title}' not found in dataset",
                    "hint": "Check spelling or use a partial title",
                }
            ), 404
        return jsonify(
            {
                "book": book_title,
                "recommendations": recommendations,
                "total": len(recommendations),
            }
        ), 200
    except Exception as exc:
        raise exc


@books_bp.route("/recommend/personalized", methods=["GET"])
@require_auth
def get_personalized():
    user_id = g.user_id
    if not user_id:
        return jsonify({"error": "user_id is required"}), 400
    try:
        limit = min(max(1, int(request.args.get("limit", 10))), 50)
        recommendations = _get_personalized_recs_uc.execute(user_id=user_id, limit=limit)
        return jsonify(
            {"user_id": user_id, "recommendations": recommendations, "total": len(recommendations)}
        ), 200
    except Exception as exc:
        raise exc


@books_bp.route("/onboarding", methods=["POST"])
@require_auth
def onboarding():
    data = request.get_json(silent=True)
    if not data:
        return jsonify({"error": "JSON body required"}), 400

    user_id = g.user_id
    book_ids = data.get("book_ids", [])
    genres = data.get("genres", [])

    if not user_id:
        return jsonify({"error": "user_id is required"}), 400

    try:
        result = _submit_onboarding_uc.execute(user_id, book_ids, genres)
        return jsonify(result), 200 if result["status"] == "success" else 500
    except Exception as exc:
        raise exc


@books_bp.route("/feedback", methods=["POST"])
@require_auth
def feedback():
    data = request.get_json(silent=True)
    if not data:
        return jsonify({"error": "JSON body required"}), 400

    user_id = g.user_id
    book_id = data.get("book_id")
    interaction = data.get("interaction")  # 'like' or 'dislike'

    if not all([user_id, book_id, interaction]):
        return jsonify({"error": "user_id, book_id, and interaction are required"}), 400

    try:
        result = _submit_feedback_uc.execute(user_id, book_id, interaction)
        return jsonify(result), 200 if result["status"] == "success" else 500
    except Exception as exc:
        raise exc


# ─────────────────────────────────────────────────────────────────────────────
# AI / Semantic Discovery
# ─────────────────────────────────────────────────────────────────────────────


_ai_rate_limits = {}
_ai_rate_lock = threading.Lock()


def rate_limit_ai(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        # Prevent memory leak by periodically cleaning up old records
        now = time.time()
        limit = 5
        window = 60

        # Use X-Forwarded-For if available to prevent proxy spoofing (simplistic approach for now)
        client_ip = (
            request.headers.get("X-Forwarded-For", request.remote_addr or "").split(",")[0].strip()
        )
        user_id = getattr(g, "user_id", client_ip)

        with _ai_rate_lock:
            # Simple cleanup
            if len(_ai_rate_limits) > 1000:
                for k in list(_ai_rate_limits.keys()):
                    _ai_rate_limits[k] = [t for t in _ai_rate_limits[k] if now - t < window]
                    if not _ai_rate_limits[k]:
                        del _ai_rate_limits[k]

            if user_id in _ai_rate_limits:
                reqs = _ai_rate_limits[user_id]
                reqs = [t for t in reqs if now - t < window]
                if len(reqs) >= limit:
                    retry_after = int(window - (now - reqs[0]))
                    response = jsonify({"error": "Rate limit exceeded. Please try again later."})
                    response.headers["Retry-After"] = str(retry_after)
                    return response, 429
                reqs.append(now)
                _ai_rate_limits[user_id] = reqs
            else:
                _ai_rate_limits[user_id] = [now]

        return f(*args, **kwargs)

    return decorated


@books_bp.route("/ai/chat", methods=["POST"])
@optional_auth
@rate_limit_ai
def ai_chat():
    data = request.get_json(silent=True)
    if not data or "query" not in data:
        return jsonify({"error": "JSON body with 'query' is required"}), 400

    query = data["query"].strip()
    if not query:
        return jsonify({"error": "Query cannot be empty"}), 400

    user_id = getattr(g, "user_id", None)  # Optional if auth is not strictly enforced here
    try:
        result = _process_rag_query_uc.execute(query, user_id=user_id)
        # result contains: answer, referenced_books, status
        return jsonify(result), 200
    except Exception as exc:
        raise exc


# ─────────────────────────────────────────────────────────────────────────────
# Activity tracking
# ─────────────────────────────────────────────────────────────────────────────


@books_bp.route("/track", methods=["POST"])
@require_auth
def track_activity():
    data = request.get_json(silent=True)
    if not data:
        return jsonify({"error": "JSON body required"}), 400

    user_id = g.user_id
    book_name = data.get("book_name", "").strip()
    book_id = data.get("book_id", "").strip()
    action = data.get("action", "view").strip()

    if not book_id:
        return jsonify({"error": "book_id is required"}), 400

    valid_actions = [
        "view",
        "book_view",
        "book_like",
        "book_dislike",
        "book_favorite",
        "recommendation_click",
        "search",
    ]
    if action not in valid_actions:
        return jsonify({"error": f"Invalid action. Supported: {valid_actions}"}), 400

    try:
        result = _track_activity_uc.execute(
            user_id=user_id, action=action, book_id=book_id, book_name=book_name
        )
        return jsonify(result), 200
    except Exception as exc:
        raise exc
