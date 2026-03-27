"""
Flask Blueprint — all /api/* endpoints.
The BookService is instantiated once at module import time (singleton pattern).
"""

import logging

from flask import Blueprint, jsonify, request

from services.book_service import BookService

logger = logging.getLogger(__name__)

books_bp = Blueprint("books", __name__)

# Singleton — created when the blueprint is first imported
_svc = BookService()


# ─────────────────────────────────────────────────────────────────────────────
# Health
# ─────────────────────────────────────────────────────────────────────────────

@books_bp.route("/health", methods=["GET"])
def health_check():
    return jsonify({"status": "healthy", "service": "book-ai-api"}), 200


# ─────────────────────────────────────────────────────────────────────────────
# Books
# ─────────────────────────────────────────────────────────────────────────────

@books_bp.route("/books", methods=["GET"])
def get_books():
    try:
        page = max(1, int(request.args.get("page", 1)))
        per_page = min(max(1, int(request.args.get("per_page", 20))), 100)
        return jsonify(_svc.get_all_books(page=page, per_page=per_page)), 200
    except Exception as exc:
        logger.exception("GET /books error")
        return jsonify({"error": str(exc)}), 500


@books_bp.route("/books/popular", methods=["GET"])
def get_popular_books():
    try:
        limit = min(max(1, int(request.args.get("limit", 20))), 50)
        books = _svc.get_popular_books(limit=limit)
        return jsonify({"books": books, "total": len(books)}), 200
    except Exception as exc:
        logger.exception("GET /books/popular error")
        return jsonify({"error": str(exc)}), 500


@books_bp.route("/books/<isbn>", methods=["GET"])
def get_book_by_isbn(isbn: str):
    try:
        book = _svc.get_book_by_isbn(isbn)
        if not book:
            return jsonify({"error": "Book not found"}), 404
        return jsonify({"book": book}), 200
    except Exception as exc:
        logger.exception("GET /books/%s error", isbn)
        return jsonify({"error": str(exc)}), 500


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
        limit = min(max(1, int(request.args.get("limit", 20))), 50)
        books = _svc.search_books(query=query, limit=limit)
        return jsonify({"books": books, "total": len(books), "query": query}), 200
    except Exception as exc:
        logger.exception("GET /search error")
        return jsonify({"error": str(exc)}), 500


# ─────────────────────────────────────────────────────────────────────────────
# Recommendations
# ─────────────────────────────────────────────────────────────────────────────

@books_bp.route("/recommend", methods=["GET"])
def get_recommendations():
    book_title = request.args.get("book", "").strip()
    if not book_title:
        return jsonify({"error": "Query parameter 'book' is required"}), 400
    try:
        top_n = min(max(1, int(request.args.get("top_n", 10))), 20)
        use_hybrid = request.args.get("hybrid", "true").lower() != "false"
        recommendations = _svc.get_recommendations(
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
        logger.exception("GET /recommend error")
        return jsonify({"error": str(exc)}), 500


# ─────────────────────────────────────────────────────────────────────────────
# Activity tracking
# ─────────────────────────────────────────────────────────────────────────────

@books_bp.route("/track", methods=["POST"])
def track_activity():
    data = request.get_json(silent=True)
    if not data:
        return jsonify({"error": "JSON body required"}), 400

    user_id = data.get("user_id", "").strip()
    book_name = data.get("book_name", "").strip()
    action = data.get("action", "view").strip()

    if not user_id or not book_name:
        return jsonify({"error": "'user_id' and 'book_name' are required"}), 400

    try:
        result = _svc.track_user_activity(
            user_id=user_id, book_name=book_name, action=action
        )
        return jsonify(result), 200
    except Exception as exc:
        logger.exception("POST /track error")
        return jsonify({"error": str(exc)}), 500
