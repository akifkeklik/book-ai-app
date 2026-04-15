"""
Flask Blueprint — all /api/* endpoints.
The BookService is instantiated once at module import time (singleton pattern).
"""

import logging

from flask import Blueprint, jsonify, request

from ..services.book_service import BookService

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


@books_bp.route("/categories", methods=["GET"])
def get_categories():
    try:
        return jsonify({"categories": _svc.get_categories()}), 200
    except Exception as exc:
        logger.exception("GET /categories error")
        return jsonify({"error": str(exc)}), 500


# ─────────────────────────────────────────────────────────────────────────────
# Books
# ─────────────────────────────────────────────────────────────────────────────

@books_bp.route("/books", methods=["GET"])
def get_books():
    try:
        page = max(1, int(request.args.get("page", 1)))
        per_page = min(max(1, int(request.args.get("per_page", 50))), 100)
        category = request.args.get("category", None)
        return jsonify(_svc.get_all_books(page=page, per_page=per_page, category=category)), 200
    except Exception as exc:
        logger.exception("GET /books error")
        return jsonify({"error": str(exc)}), 500


@books_bp.route("/books/popular", methods=["GET"])
def get_popular_books():
    try:
        # Senior Update: Increased limit for "All Books" section
        limit = min(max(1, int(request.args.get("limit", 50))), 5000)
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
        limit = min(max(1, int(request.args.get("limit", 20))), 100)
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
        top_n = min(max(1, int(request.args.get("top_n", 10))), 50)
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


@books_bp.route("/recommend/personalized", methods=["GET"])
def get_personalized():
    user_id = request.args.get("user_id", "").strip()
    if not user_id:
        return jsonify({"error": "user_id is required"}), 400
    try:
        limit = min(max(1, int(request.args.get("limit", 10))), 50)
        recommendations = _svc.get_personalized_recommendations(user_id=user_id, limit=limit)
        return jsonify({
            "user_id": user_id,
            "recommendations": recommendations,
            "total": len(recommendations)
        }), 200
    except Exception as exc:
        logger.exception("GET /recommend/personalized error")
        return jsonify({"error": str(exc)}), 500


@books_bp.route("/onboarding", methods=["POST"])
def onboarding():
    data = request.get_json(silent=True)
    if not data:
        return jsonify({"error": "JSON body required"}), 400
    
    user_id = data.get("user_id")
    book_ids = data.get("book_ids", [])
    genres = data.get("genres", [])
    
    if not user_id:
        return jsonify({"error": "user_id is required"}), 400
        
    try:
        result = _svc.submit_onboarding(user_id, book_ids, genres)
        return jsonify(result), 200 if result["status"] == "success" else 500
    except Exception as exc:
        logger.exception("POST /onboarding error")
        return jsonify({"error": str(exc)}), 500


@books_bp.route("/feedback", methods=["POST"])
def feedback():
    data = request.get_json(silent=True)
    if not data:
        return jsonify({"error": "JSON body required"}), 400
        
    user_id = data.get("user_id")
    book_id = data.get("book_id")
    interaction = data.get("interaction") # 'like' or 'dislike'
    
    if not all([user_id, book_id, interaction]):
        return jsonify({"error": "user_id, book_id, and interaction are required"}), 400
        
    try:
        result = _svc.submit_feedback(user_id, book_id, interaction)
        return jsonify(result), 200 if result["status"] == "success" else 500
    except Exception as exc:
        logger.exception("POST /feedback error")
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
