"""
Flask Blueprint — all /api/* endpoints.
The BookService is instantiated once at module import time (singleton pattern).
"""

import logging
from functools import wraps

from flask import Blueprint, g, jsonify, request

from ..config import Config
from ..infrastructure.ml.recommender import BookRecommender
from ..services.book_service import BookService
from ..services.embedding_service import EmbeddingService

logger = logging.getLogger(__name__)

books_bp = Blueprint("books", __name__)

# Composition Root - Singleton Creation
_supabase = None
if Config.SUPABASE_URL and Config.SUPABASE_ANON_KEY:
    from supabase import create_client
    _supabase = create_client(Config.SUPABASE_URL, Config.SUPABASE_ANON_KEY)

from ..infrastructure.persistence.supabase_adapters import (  # noqa: E402
    SupabaseAuthPort,
    SupabaseBookDataPort,
    SupabaseInteractionRepository,
)

_interaction_repo = SupabaseInteractionRepository(_supabase) if _supabase else None
_book_data_port = SupabaseBookDataPort(_supabase) if _supabase else None
_auth_port = SupabaseAuthPort(_supabase) if _supabase else None
_recommender = BookRecommender()

from ..application.services.enrichment_service import BookEnrichmentService  # noqa: E402
from ..application.use_cases.ai_rag import ProcessRagQueryUseCase  # noqa: E402
from ..application.use_cases.catalog import (  # noqa: E402
    GetBookDetailsUseCase,
    GetBooksUseCase,
    GetPopularBooksUseCase,
    SearchBooksUseCase,
)
from ..application.use_cases.interactions import (  # noqa: E402
    SubmitFeedbackUseCase,
    SubmitOnboardingUseCase,
    TrackUserActivityUseCase,
)
from ..application.use_cases.recommendations import (  # noqa: E402
    GetPersonalizedRecommendationsUseCase,
    GetRecommendationsUseCase,
)
from ..infrastructure.llm.adapters import GenericLlmAdapter  # noqa: E402

_enrichment_service = BookEnrichmentService()
_llm_port = GenericLlmAdapter(provider=Config.LLM_PROVIDER, api_key=Config.LLM_API_KEY)

_get_books_uc = GetBooksUseCase(_recommender, _enrichment_service)
_search_books_uc = SearchBooksUseCase(_recommender, _enrichment_service)
_get_popular_books_uc = GetPopularBooksUseCase(_recommender, _enrichment_service)
_get_book_details_uc = GetBookDetailsUseCase(_recommender, _enrichment_service)
_get_recommendations_uc = GetRecommendationsUseCase(_recommender, _enrichment_service)
_get_personalized_recs_uc = GetPersonalizedRecommendationsUseCase(
    recommender=_recommender,
    interaction_repo=_interaction_repo,
    book_data_port=_book_data_port,
    enrichment_service=_enrichment_service
)
_submit_onboarding_uc = SubmitOnboardingUseCase(_interaction_repo)
_submit_feedback_uc = SubmitFeedbackUseCase(_interaction_repo)
_track_activity_uc = TrackUserActivityUseCase(_interaction_repo)

_svc = BookService(
    recommender=_recommender,
    interaction_repo=_interaction_repo,
    book_data_port=_book_data_port,
    auth_port=_auth_port,
)
_emb_svc = EmbeddingService(book_data_port=_book_data_port)
_process_rag_query_uc = ProcessRagQueryUseCase(
    embedding_port=_emb_svc,
    book_data_port=_book_data_port,
    interaction_repo=_interaction_repo,
    recommender=_recommender,
    enrichment_service=_enrichment_service,
    llm_port=_llm_port
)


def require_auth(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        auth_header = request.headers.get("Authorization")
        if not auth_header or not auth_header.startswith("Bearer "):
            return jsonify({"error": "Unauthorized: Missing or invalid Authorization header"}), 401

        token = auth_header.split(" ")[1]
        try:
            user = _svc.verify_token(token)
            if not user or not user.id:
                return jsonify({"error": "Unauthorized: Invalid token"}), 401
            g.user_id = user.id
        except Exception as exc:
            logger.warning(f"JWT verification failed: {exc}")
            return jsonify({"error": "Unauthorized: Invalid or expired token"}), 401

        return f(*args, **kwargs)

    return decorated


# ─────────────────────────────────────────────────────────────────────────────
# Health
# ─────────────────────────────────────────────────────────────────────────────


@books_bp.route("/health", methods=["GET"])
def health_check():
    return jsonify({"status": "healthy", "service": "book-ai-api"}), 200

@books_bp.route("/health/ready", methods=["GET"])
def readiness_check():
    try:
        # Check DB dependency
        if _supabase:
            _supabase.table("books").select("isbn13").limit(1).execute()
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
        category = request.args.get("category", None)
        return jsonify(_get_books_uc.execute(page=page, per_page=per_page, category=category)), 200
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


@books_bp.route("/ai/chat", methods=["POST"])
# @require_auth  # Optionally require auth, uncomment if Flutter sends token for this
def ai_chat():
    data = request.get_json(silent=True)
    if not data or "query" not in data:
        return jsonify({"error": "JSON body with 'query' is required"}), 400

    query = data["query"].strip()
    if not query:
        return jsonify({"error": "Query cannot be empty"}), 400

    user_id = getattr(g, "user_id", None) # Optional if auth is not strictly enforced here
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
