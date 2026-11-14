"""
Flask Blueprint — all /api/* endpoints.
The BookService is instantiated once at module import time (singleton pattern).
"""

import inspect
import json
import logging
from functools import wraps

from flask import Blueprint, Response, g, jsonify, request

from ..container import container
from ..infrastructure.security.rate_limiter import get_rate_limiter

logger = logging.getLogger(__name__)


class _UnavailableAuthPort:
    """Fail-closed auth adapter used when Supabase auth is not configured."""
    @staticmethod
    def verify_token(token: str):
        return None


catalog_bp = Blueprint("catalog", __name__)
discovery_bp = Blueprint("discovery", __name__)
activity_bp = Blueprint("activity", __name__)
health_bp = Blueprint("health", __name__)

# Re-exporting aliases for convenience and to avoid changing the rest of this file
_book_data_port = container.book_data_port
_auth_port = container.auth_port or _UnavailableAuthPort()
_interaction_repo = container.interaction_repo
_svc = container.book_service
_get_books_uc = container.get_books_uc
_search_books_uc = container.search_books_uc
_get_popular_books_uc = container.get_popular_books_uc
_get_book_details_uc = container.get_book_details_uc
_get_recommendations_uc = container.get_recommendations_uc
_get_personalized_recs_uc = container.get_personalized_recs_uc
_submit_onboarding_uc = container.submit_onboarding_uc
_get_preferences_uc = container.get_preferences_uc
_update_preferences_uc = container.update_preferences_uc
_submit_feedback_uc = container.submit_feedback_uc
_track_activity_uc = container.track_activity_uc
_process_rag_query_uc = container.process_rag_query_uc
_create_note_uc = getattr(container, "create_note_uc", None)
_get_notes_uc = getattr(container, "get_notes_uc", None)
_get_note_by_id_uc = getattr(container, "get_note_by_id_uc", None)
_update_note_uc = getattr(container, "update_note_uc", None)
_delete_note_uc = getattr(container, "delete_note_uc", None)
_get_due_reviews_uc = getattr(container, "get_due_reviews_uc", None)
_get_review_stats_uc = getattr(container, "get_review_stats_uc", None)
_process_review_uc = getattr(container, "process_review_uc", None)
_update_review_settings_uc = getattr(container, "update_review_settings_uc", None)
_export_notes_uc = getattr(container, "export_notes_uc", None)
_reset_preferences_uc = getattr(container, "reset_preferences_uc", None)
_get_review_queue_uc = getattr(container, "get_review_queue_uc", None)
_submit_review_attempt_uc = getattr(container, "submit_review_attempt_uc", None)
_get_learning_overview_uc = getattr(container, "get_learning_overview_uc", None)
_get_review_history_uc = getattr(container, "get_review_history_uc", None)
_create_review_item_uc = getattr(container, "create_review_item_uc", None)
_update_review_item_uc = getattr(container, "update_review_item_uc", None)
_delete_review_item_uc = getattr(container, "delete_review_item_uc", None)
_get_concept_outcomes_uc = getattr(container, "get_concept_outcomes_uc", None)


def rebind_container(new_container):
    """Rebinds blueprint use cases and ports to a custom container (e.g., local PostgreSQL)."""
    global _book_data_port, _auth_port, _interaction_repo, _svc, _get_books_uc, _search_books_uc
    global _get_popular_books_uc, _get_book_details_uc, _get_recommendations_uc
    global _get_personalized_recs_uc, _submit_onboarding_uc, _get_preferences_uc
    global _update_preferences_uc, _submit_feedback_uc, _track_activity_uc, _process_rag_query_uc
    global _create_note_uc, _get_notes_uc, _get_note_by_id_uc, _update_note_uc, _delete_note_uc
    global _get_due_reviews_uc, _get_review_stats_uc, _process_review_uc, _update_review_settings_uc, _export_notes_uc
    global _reset_preferences_uc
    global _get_review_queue_uc, _submit_review_attempt_uc, _get_learning_overview_uc
    global _get_review_history_uc, _create_review_item_uc, _update_review_item_uc
    global _delete_review_item_uc, _get_concept_outcomes_uc
    _book_data_port = new_container.book_data_port
    _auth_port = new_container.auth_port or _UnavailableAuthPort()
    _interaction_repo = new_container.interaction_repo
    _svc = new_container.book_service
    _get_books_uc = new_container.get_books_uc
    _search_books_uc = new_container.search_books_uc
    _get_popular_books_uc = new_container.get_popular_books_uc
    _get_book_details_uc = new_container.get_book_details_uc
    _get_recommendations_uc = new_container.get_recommendations_uc
    _get_personalized_recs_uc = new_container.get_personalized_recs_uc
    _submit_onboarding_uc = new_container.submit_onboarding_uc
    _get_preferences_uc = new_container.get_preferences_uc
    _update_preferences_uc = new_container.update_preferences_uc
    _submit_feedback_uc = new_container.submit_feedback_uc
    _track_activity_uc = new_container.track_activity_uc
    _process_rag_query_uc = new_container.process_rag_query_uc
    _create_note_uc = getattr(new_container, "create_note_uc", None)
    _get_notes_uc = getattr(new_container, "get_notes_uc", None)
    _get_note_by_id_uc = getattr(new_container, "get_note_by_id_uc", None)
    _update_note_uc = getattr(new_container, "update_note_uc", None)
    _delete_note_uc = getattr(new_container, "delete_note_uc", None)
    _get_due_reviews_uc = getattr(new_container, "get_due_reviews_uc", None)
    _get_review_stats_uc = getattr(new_container, "get_review_stats_uc", None)
    _process_review_uc = getattr(new_container, "process_review_uc", None)
    _update_review_settings_uc = getattr(new_container, "update_review_settings_uc", None)
    _export_notes_uc = getattr(new_container, "export_notes_uc", None)
    _reset_preferences_uc = getattr(new_container, "reset_preferences_uc", None)
    _get_review_queue_uc = getattr(new_container, "get_review_queue_uc", None)
    _submit_review_attempt_uc = getattr(new_container, "submit_review_attempt_uc", None)
    _get_learning_overview_uc = getattr(new_container, "get_learning_overview_uc", None)
    _get_review_history_uc = getattr(new_container, "get_review_history_uc", None)
    _create_review_item_uc = getattr(new_container, "create_review_item_uc", None)
    _update_review_item_uc = getattr(new_container, "update_review_item_uc", None)
    _delete_review_item_uc = getattr(new_container, "delete_review_item_uc", None)
    _get_concept_outcomes_uc = getattr(new_container, "get_concept_outcomes_uc", None)


def _parse_int_param(val, default: int, min_val: int = 1, max_val: int = None) -> int:
    try:
        parsed = int(val)
    except (TypeError, ValueError):
        parsed = default
    if min_val is not None:
        parsed = max(min_val, parsed)
    if max_val is not None:
        parsed = min(max_val, parsed)
    return parsed


def require_auth(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        # 1. If caller is explicitly anonymous (e.g. Supabase anon key), reject personal data access
        if getattr(g, "is_anon", False):
            return jsonify(
                {
                    "error": "Unauthorized: Real user authentication required, anonymous access provided"
                }
            ), 401

        # 2. If user already verified by middleware
        if getattr(g, "user_id", None):
            return f(*args, **kwargs)

        auth_header = request.headers.get("Authorization")
        if not auth_header or not auth_header.startswith("Bearer "):
            return jsonify({"error": "Unauthorized: Missing or invalid Authorization header"}), 401

        token = auth_header.split(" ", 1)[1].strip()
        from backend.config import Config

        if Config.SUPABASE_ANON_KEY and token == Config.SUPABASE_ANON_KEY:
            return jsonify(
                {"error": "Unauthorized: Real user authentication required, anonymous key provided"}
            ), 401

        try:
            user = _auth_port.verify_token(token) if _auth_port else None
            if not user or not getattr(user, "id", None):
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
        # If user_id already resolved by middleware, proceed
        if getattr(g, "user_id", None):
            return f(*args, **kwargs)

        auth_header = request.headers.get("Authorization")
        if auth_header and auth_header.startswith("Bearer "):
            token = auth_header.split(" ", 1)[1].strip()
            from backend.config import Config

            if Config.SUPABASE_ANON_KEY and token == Config.SUPABASE_ANON_KEY:
                g.is_anon = True
                return f(*args, **kwargs)

            try:
                user = _auth_port.verify_token(token) if _auth_port else None
                if user and getattr(user, "id", None):
                    g.user_id = user.id
                    g.jwt_token = token
            except Exception:
                pass
        return f(*args, **kwargs)

    return decorated


# ─────────────────────────────────────────────────────────────────────────────
# Health
# ─────────────────────────────────────────────────────────────────────────────


@health_bp.route("/health", methods=["GET"])
def health_check():
    return jsonify({"status": "healthy", "service": "book-ai-api"}), 200


@health_bp.route("/docs", methods=["GET"])
def swagger_ui():
    import os

    from flask import send_from_directory

    # Serve index.html from static/swagger-ui
    static_dir = os.path.join(os.path.dirname(os.path.dirname(__file__)), "static", "swagger-ui")
    return send_from_directory(static_dir, "index.html")


@health_bp.route("/docs/<path:filename>", methods=["GET"])
def swagger_ui_files(filename):
    import os

    from flask import send_from_directory

    static_dir = os.path.join(os.path.dirname(os.path.dirname(__file__)), "static", "swagger-ui")
    return send_from_directory(static_dir, filename)


@health_bp.route("/health/ready", methods=["GET"])
def readiness_check():
    try:
        if not _book_data_port or not _book_data_port.check_health():
            raise Exception("Database health check failed")
        return jsonify({"service": "book-ai-api", "status": "ready"}), 200
    except Exception as exc:
        import logging

        from ..infrastructure.logging.structured_logger import log_event

        log_event(__name__, logging.ERROR, msg="Readiness check failed", error=str(exc))
        return jsonify({"service": "book-ai-api", "status": "not_ready", "error": "Database unavailable"}), 503


@catalog_bp.route("/categories", methods=["GET"])
def get_categories():
    try:
        return jsonify({"categories": _svc.get_categories()}), 200
    except Exception as exc:
        raise exc


# ─────────────────────────────────────────────────────────────────────────────
# Books
# ─────────────────────────────────────────────────────────────────────────────


@catalog_bp.route("/books", methods=["GET"])
def get_books():
    try:
        page = _parse_int_param(request.args.get("page"), default=1, min_val=1)
        per_page = _parse_int_param(request.args.get("per_page"), default=50, min_val=1, max_val=100)

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
            "query": request.args.get("q") or request.args.get("query"),
        }

        return jsonify(_get_books_uc.execute(**kwargs)), 200
    except Exception as exc:
        raise exc


@catalog_bp.route("/books/popular", methods=["GET"])
def get_popular_books():
    try:
        # Senior Update: Increased limit for "All Books" section
        limit = _parse_int_param(request.args.get("limit"), default=50, min_val=1, max_val=5000)
        books = _get_popular_books_uc.execute(limit=limit)
        return jsonify({"books": books, "total": len(books)}), 200
    except Exception as exc:
        raise exc


@catalog_bp.route("/books/<isbn>", methods=["GET"])
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


@catalog_bp.route("/search", methods=["GET"])
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


@discovery_bp.route("/recommend", methods=["GET"])
def get_recommendations():
    book_title = request.args.get("book", "").strip()
    if not book_title:
        return jsonify({"error": "Query parameter 'book' is required"}), 400
    try:
        top_n = _parse_int_param(request.args.get("top_n"), default=10, min_val=1, max_val=50)
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


def _safe_execute_personalized_recommendations(
    use_case,
    user_id: str,
    limit: int,
    category=None,
    exclude_completed: bool = False,
    include_diagnostics: bool = True,
):
    """
    Safely invokes the recommendation use case or legacy adapter.
    Uses inspect.signature to check supported parameters before invocation,
    ensuring legacy adapters only receive parameters they declare
    WITHOUT catching or concealing genuine internal TypeErrors.
    """
    execute_fn = getattr(use_case, "execute", None)
    if not callable(execute_fn):
        raise TypeError(f"Recommendation use case {use_case!r} has no callable 'execute' method")

    sig = None
    try:
        sig = inspect.signature(execute_fn)
    except (ValueError, TypeError):
        sig = None

    if sig is not None:
        params = sig.parameters
        has_var_keyword = any(p.kind == inspect.Parameter.VAR_KEYWORD for p in params.values())

        if has_var_keyword:
            return execute_fn(
                user_id=user_id,
                limit=limit,
                category=category,
                exclude_completed=exclude_completed,
                include_diagnostics=include_diagnostics,
            )

        call_kwargs = {}
        target_kwargs = {
            "user_id": user_id,
            "limit": limit,
            "category": category,
            "exclude_completed": exclude_completed,
            "include_diagnostics": include_diagnostics,
        }
        for k, v in target_kwargs.items():
            if k in params:
                call_kwargs[k] = v

        return execute_fn(**call_kwargs)

    # Fallback when signature inspection is unavailable (e.g., C extensions)
    try:
        return execute_fn(
            user_id=user_id,
            limit=limit,
            category=category,
            exclude_completed=exclude_completed,
            include_diagnostics=include_diagnostics,
        )
    except TypeError as exc:
        tb = exc.__traceback__
        if tb is not None and tb.tb_next is None and "unexpected keyword argument" in str(exc):
            return execute_fn(user_id=user_id, limit=limit)
        raise exc


@discovery_bp.route("/recommend/personalized", methods=["GET"])
@require_auth
def get_personalized():
    user_id = g.user_id
    if not user_id:
        return jsonify({"error": "user_id is required"}), 400
    try:
        limit = _parse_int_param(request.args.get("limit"), default=10, min_val=1, max_val=50)
        category = request.args.get("category")
        if category:
            category = category.strip()
        exclude_completed = request.args.get("exclude_completed", "false").lower() in ("true", "1", "yes")
        include_diagnostics = request.args.get("diagnostics", "false").lower() in ("true", "1", "yes")

        result = _safe_execute_personalized_recommendations(
            use_case=_get_personalized_recs_uc,
            user_id=user_id,
            limit=limit,
            category=category,
            exclude_completed=exclude_completed,
            include_diagnostics=True,
        )

        if isinstance(result, list):
            recommendations = result
            total = len(result)
            is_cold_start = False
            evidence_coverage = "cold_start"
            diagnostics = None
        elif isinstance(result, dict):
            recommendations = result.get("recommendations")
            if not isinstance(recommendations, list):
                logger.error(f"Malformed recommendation dict: 'recommendations' is not a list ({type(recommendations).__name__})")
                return jsonify({
                    "error": "Malformed recommendation response: 'recommendations' field must be a list",
                    "details": str(type(recommendations).__name__),
                }), 502
            total = result.get("total", len(recommendations))
            is_cold_start = bool(result.get("is_cold_start", False))
            evidence_coverage = str(result.get("evidence_coverage", "cold_start"))
            diagnostics = result.get("diagnostics")
        else:
            logger.error(f"Malformed recommendation response: expected list or dict, got {type(result).__name__}")
            return jsonify({
                "error": "Malformed recommendation response: expected list or dict",
                "details": str(type(result).__name__),
            }), 502

        resp = {
            "user_id": user_id,
            "recommendations": recommendations,
            "total": total,
            "is_cold_start": is_cold_start,
            "evidence_coverage": evidence_coverage,
        }
        if include_diagnostics:
            resp["diagnostics"] = diagnostics

        return jsonify(resp), 200
    except Exception as exc:
        raise exc


@activity_bp.route("/onboarding", methods=["POST"])
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


@activity_bp.route("/preferences", methods=["GET"])
@require_auth
def get_preferences():
    user_id = g.user_id
    if not user_id:
        return jsonify({"error": "user_id is required"}), 400
    try:
        result = _get_preferences_uc.execute(user_id)
        return jsonify(result), 200
    except Exception as exc:
        raise exc


@activity_bp.route("/preferences", methods=["PUT", "POST"])
@require_auth
def update_preferences():
    user_id = g.user_id
    if not user_id:
        return jsonify({"error": "user_id is required"}), 400

    data = request.get_json(silent=True)
    if not data or not isinstance(data, dict):
        return jsonify({"error": "JSON body required"}), 400

    genres = data.get("genres") if data.get("genres") is not None else data.get("preferred_genres", [])
    if not isinstance(genres, list):
        return jsonify({"error": "genres must be a list of strings"}), 400

    for g_item in genres:
        if not isinstance(g_item, str):
            return jsonify({"error": "genres must contain only strings"}), 400
        if len(g_item.strip()) > 100:
            return jsonify({"error": "genre names cannot exceed 100 characters"}), 400

    authors = data.get("authors") if data.get("authors") is not None else data.get("preferred_authors")
    if authors is not None:
        if not isinstance(authors, list):
            return jsonify({"error": "authors must be a list of strings if provided"}), 400
        for a_item in authors:
            if not isinstance(a_item, str):
                return jsonify({"error": "authors must contain only strings"}), 400
            if len(a_item.strip()) > 100:
                return jsonify({"error": "author names cannot exceed 100 characters"}), 400

    try:
        result = _update_preferences_uc.execute(user_id=user_id, genres=genres, authors=authors)
        return jsonify(result), 200 if result.get("status") == "success" else 500
    except Exception as exc:
        raise exc

@activity_bp.route("/taste-profile", methods=["GET"])
@activity_bp.route("/preferences/profile", methods=["GET"])
@require_auth
def get_taste_profile():
    user_id = g.user_id
    if not user_id:
        return jsonify({"error": "Unauthorized"}), 401
    try:
        profile = _get_personalized_recs_uc.build_user_preference_profile(user_id)
        return jsonify(profile.model_dump()), 200
    except Exception as exc:
        logger.error(f"Error fetching taste profile for {user_id}: {exc}")
        return jsonify({"error": "Failed to fetch taste profile"}), 500


@activity_bp.route("/preferences/reset", methods=["POST", "DELETE"])
@require_auth
def reset_preferences():
    user_id = g.user_id
    if not user_id:
        return jsonify({"error": "Unauthorized"}), 401
    try:
        if not _reset_preferences_uc:
            return jsonify({"error": "Reset service unavailable"}), 500
        res = _reset_preferences_uc.execute(user_id)
        return jsonify(res), 200 if res.get("status") == "success" else 500
    except Exception as exc:
        logger.error(f"Error resetting preferences for {user_id}: {exc}")
        return jsonify({"error": "Failed to reset preferences"}), 500



@activity_bp.route("/feedback", methods=["POST"])
@require_auth
def feedback():
    data = request.get_json(silent=True)
    if not data:
        return jsonify({"error": "JSON body required"}), 400

    user_id = g.user_id
    if not user_id:
        return jsonify({"error": "Unauthorized"}), 401

    book_id = data.get("book_id")
    if not book_id or not isinstance(book_id, str) or not book_id.strip():
        return jsonify({"error": "book_id is required"}), 400
    book_id = book_id.strip()

    interaction = data.get("interaction")
    if not interaction or not isinstance(interaction, str):
        return jsonify({"error": "interaction is required"}), 400
    interaction = interaction.strip().lower()

    valid_interactions = [
        "like",
        "dislike",
        "favorite",
        "unfavorite",
        "want_to_read",
        "reading",
        "finished",
        "clear",
        "remove",
    ]
    if interaction not in valid_interactions:
        return jsonify({"error": f"Invalid interaction. Supported: {valid_interactions}"}), 400

    book_title = data.get("book_title")
    book_author = data.get("book_author")
    book_image_url = data.get("book_image_url")
    if interaction == "favorite" and not book_title and _book_data_port:
        try:
            b_details = _book_data_port.get_books_by_isbns([book_id])
            if b_details:
                b_first = b_details[0]
                book_title = b_first.get("title") or ""
                book_author = b_first.get("authors") or ""
                book_image_url = b_first.get("thumbnail") or ""
        except Exception:
            pass

    try:
        result = _submit_feedback_uc.execute(
            user_id,
            book_id,
            interaction,
            book_title=book_title,
            book_author=book_author,
            book_image_url=book_image_url,
        )
        return jsonify(result), 200 if result.get("status") == "success" else 500
    except Exception as exc:
        raise exc


@activity_bp.route("/feedback/<book_id>", methods=["GET"])
@optional_auth
def get_book_feedback(book_id):
    if not book_id or not isinstance(book_id, str):
        return jsonify({"error": "Invalid book_id"}), 400
    clean_id = book_id.strip()

    user_id = getattr(g, "user_id", None)
    if not user_id:
        return jsonify({
            "status": "success",
            "interaction": None,
            "is_favorite": False,
            "is_authenticated": False,
        }), 200

    try:
        interactions = _interaction_repo.get_user_interactions(user_id) if _interaction_repo else []
        book_interactions = [i for i in (interactions or []) if str(i.get("book_id", "")).strip() == clean_id]

        favorites = (
            _interaction_repo.get_user_favorites(user_id)
            if _interaction_repo and hasattr(_interaction_repo, "get_user_favorites")
            else []
        )
        is_fav = any(str(f.get("book_id", "")).strip() == clean_id for f in (favorites or []))

        raw_interaction = None
        if book_interactions:
            raw_interaction = book_interactions[0].get("interaction_type")
            if raw_interaction == "favorite":
                is_fav = True
        elif is_fav:
            raw_interaction = "favorite"

        return jsonify({
            "status": "success",
            "interaction": raw_interaction,
            "is_favorite": is_fav,
            "is_authenticated": True,
        }), 200
    except Exception as exc:
        logger.error(f"Error getting book feedback: {exc}")
        return jsonify({"error": "Failed to retrieve book interaction"}), 500


@activity_bp.route("/library", methods=["GET"])
@require_auth
def get_library():
    user_id = g.user_id
    if not user_id:
        return jsonify({"error": "Unauthorized"}), 401

    try:
        interactions = _interaction_repo.get_user_interactions(user_id) if _interaction_repo else []
        favorites = (
            _interaction_repo.get_user_favorites(user_id)
            if _interaction_repo and hasattr(_interaction_repo, "get_user_favorites")
            else []
        )

        book_map = {}
        for item in (interactions or []):
            bid = str(item.get("book_id", "")).strip()
            itype = item.get("interaction_type", "").strip().lower()
            if not bid or not itype:
                continue
            status = itype
            if itype in ("favorite", "like"):
                status = "favorite"
            book_map[bid] = {
                "status": status,
                "is_favorite": (itype == "favorite"),
                "added_at": item.get("created_at") or "",
                "title": "",
                "author": "",
                "thumbnail": "",
            }

        for fav in (favorites or []):
            bid = str(fav.get("book_id", "")).strip()
            if not bid:
                continue
            existing = book_map.get(bid)
            if not existing:
                book_map[bid] = {
                    "status": "favorite",
                    "is_favorite": True,
                    "added_at": fav.get("added_at") or "",
                    "title": fav.get("book_title") or "",
                    "author": fav.get("book_author") or "",
                    "thumbnail": fav.get("book_image_url") or "",
                }
            else:
                existing["is_favorite"] = True
                if not existing["title"] and fav.get("book_title"):
                    existing["title"] = fav.get("book_title")
                if not existing["author"] and fav.get("book_author"):
                    existing["author"] = fav.get("book_author")
                if not existing["thumbnail"] and fav.get("book_image_url"):
                    existing["thumbnail"] = fav.get("book_image_url")

        unique_bids = list(book_map.keys())
        books_detail_map = {}
        if unique_bids and _book_data_port:
            try:
                raw_books = _book_data_port.get_books_by_isbns(unique_bids)
                for b in (raw_books or []):
                    isbn = b.get("isbn13") or b.get("isbn")
                    if isbn:
                        books_detail_map[str(isbn).strip()] = b
            except Exception as e:
                logger.warning(f"Could not batch fetch book details: {e}")

        items = []
        for bid, entry in book_map.items():
            book_obj = books_detail_map.get(bid)
            if not book_obj:
                book_obj = {
                    "isbn13": bid,
                    "title": entry["title"] or f"Book {bid}",
                    "authors": entry["author"] or "Unknown Author",
                    "thumbnail": entry["thumbnail"] or "",
                    "categories": "",
                    "description": "",
                    "average_rating": 0,
                    "ratings_count": 0,
                    "published_date": "",
                    "page_count": 0,
                }
            items.append({
                "id": bid,
                "book_id": bid,
                "status": entry["status"],
                "is_favorite": entry["is_favorite"],
                "added_at": entry["added_at"],
                "book": book_obj,
            })

        items.sort(key=lambda x: str(x.get("added_at", "")), reverse=True)
        return jsonify({"status": "success", "items": items}), 200
    except Exception as exc:
        logger.error(f"Error fetching library: {exc}")
        return jsonify({"error": "Failed to fetch library"}), 500


# ─────────────────────────────────────────────────────────────────────────────
# AI / Semantic Discovery
# ─────────────────────────────────────────────────────────────────────────────

_rate_limiter = get_rate_limiter()
_ai_rate_limits = getattr(_rate_limiter, "buckets", {})


def rate_limit_ai(f):
    """
    Tiered AI Rate Limiter.
    - Anonymous (IP-based): 5 requests / 60 seconds
    - Authenticated User (user_id-based): 10 requests / 60 seconds
    - Server (X-Api-Key): 30 requests / 60 seconds

    ARCHITECTURAL NOTE:
    Backed by pluggable RateLimiter infrastructure:
    - Single worker / local dev: InMemoryRateLimiter with thread safety and bounded capacity.
    - Multi-worker / scaled production: RedisRateLimiter when REDIS_URL is configured,
      preventing multi-worker bypasses across WSGI/Gunicorn processes.
    IP resolution uses request.remote_addr to prevent unverified X-Forwarded-For spoofing.
    """

    @wraps(f)
    def decorated(*args, **kwargs):
        window = 60

        # Do not blindly trust X-Forwarded-For without proper proxy configuration
        client_ip = request.remote_addr or "unknown"
        user_id = getattr(g, "user_id", None)
        is_server = getattr(g, "is_server", False)

        if user_id:
            bucket_key = f"user:{user_id}"
            limit = 10
        elif is_server:
            bucket_key = f"server:{client_ip}"
            limit = 30
        else:
            # Anonymous access (with valid SUPABASE_ANON_KEY or test fixture)
            bucket_key = f"anon:{client_ip}"
            limit = 5

        allowed, retry_after, is_overloaded = _rate_limiter.check(
            bucket_key=bucket_key, limit=limit, window=window
        )

        if is_overloaded:
            return jsonify({"error": "Service overloaded. Rate limiter capacity reached."}), 503

        if not allowed:
            response = jsonify({"error": "Rate limit exceeded. Please try again later."})
            response.headers["Retry-After"] = str(retry_after)
            return response, 429

        return f(*args, **kwargs)

    return decorated



@discovery_bp.route("/ai/chat", methods=["POST"])
@optional_auth
@rate_limit_ai
def ai_chat():
    data = request.get_json(silent=True)
    if not data or "query" not in data:
        return jsonify({"error": "JSON body with 'query' is required"}), 400

    raw_query = data.get("query")
    if not isinstance(raw_query, str):
        return jsonify({"error": "Query must be a string"}), 400

    query = raw_query.strip()
    if not query:
        return jsonify({"error": "Query cannot be empty"}), 400

    MAX_QUERY_LENGTH = 1000
    if len(query) > MAX_QUERY_LENGTH:
        return (
            jsonify(
                {
                    "error": f"Query exceeds maximum allowed length of {MAX_QUERY_LENGTH} characters",
                    "max_length": MAX_QUERY_LENGTH,
                    "actual_length": len(query),
                }
            ),
            400,
        )

    user_id = getattr(g, "user_id", None)  # Optional if auth is not strictly enforced here
    try:
        result = _process_rag_query_uc.execute(query, user_id=user_id)
        # result contains: answer, referenced_books, status
        return jsonify(result), 200
    except Exception as exc:
        raise exc


@discovery_bp.route("/ai/chat/stream", methods=["POST"])
@optional_auth
@rate_limit_ai
def ai_chat_stream():
    """
    Authenticated, validated SSE streaming endpoint for AI discovery.
    Yields 'metadata' (referenced books), 'chunk' (incremental tokens), and 'done' events.
    """
    data = request.get_json(silent=True)
    if not data or "query" not in data:
        return jsonify({"error": "JSON body with 'query' is required"}), 400

    raw_query = data.get("query")
    if not isinstance(raw_query, str):
        return jsonify({"error": "Query must be a string"}), 400

    query = raw_query.strip()
    if not query:
        return jsonify({"error": "Query cannot be empty"}), 400

    MAX_QUERY_LENGTH = 1000
    if len(query) > MAX_QUERY_LENGTH:
        return (
            jsonify(
                {
                    "error": f"Query exceeds maximum allowed length of {MAX_QUERY_LENGTH} characters",
                    "max_length": MAX_QUERY_LENGTH,
                    "actual_length": len(query),
                }
            ),
            400,
        )

    user_id = getattr(g, "user_id", None)

    def generate_events():
        try:
            result = _process_rag_query_uc.execute(query, user_id=user_id)
            referenced_books = result.get("referenced_books", [])
            full_answer = result.get("answer", "")
            action = result.get("action")
            status = result.get("status", "success")

            # 1. Metadata event with referenced books
            yield f"event: metadata\ndata: {json.dumps({'referenced_books': referenced_books, 'status': 'streaming'}, ensure_ascii=False)}\n\n"

            # 2. Token chunks
            if full_answer:
                words = full_answer.split(" ")
                chunk_size = 4
                for i in range(0, len(words), chunk_size):
                    chunk = " ".join(words[i : i + chunk_size])
                    if i + chunk_size < len(words):
                        chunk += " "
                    yield f"event: chunk\ndata: {json.dumps({'delta': chunk}, ensure_ascii=False)}\n\n"

            # 3. Done event
            yield f"event: done\ndata: {json.dumps({'answer': full_answer, 'referenced_books': referenced_books, 'status': status, 'action': action}, ensure_ascii=False)}\n\n"
        except Exception:
            yield f"event: error\ndata: {json.dumps({'error': 'An error occurred during AI processing.'})}\n\n"

    return Response(
        generate_events(),
        mimetype="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Content-Type": "text/event-stream; charset=utf-8",
            "X-Accel-Buffering": "no",
            "Connection": "keep-alive",
        },
    )


# ─────────────────────────────────────────────────────────────────────────────
# Activity tracking
# ─────────────────────────────────────────────────────────────────────────────


@activity_bp.route("/track", methods=["POST"])
@require_auth
def track_activity():
    data = request.get_json(silent=True)
    if not data:
        return jsonify({"error": "JSON body required"}), 400

    user_id = g.user_id
    if not user_id:
        return jsonify({"error": "Unauthorized"}), 401

    book_name = data.get("book_name", "").strip() if isinstance(data.get("book_name"), str) else ""
    book_id = data.get("book_id", "").strip() if isinstance(data.get("book_id"), str) else ""
    if not book_id and book_name:
        book_id = book_name

    if not book_id:
        return jsonify({"error": "book_id is required"}), 400

    action = data.get("action", "view")
    if not isinstance(action, str):
        return jsonify({"error": "action must be a string"}), 400
    action = action.strip().lower()

    valid_actions = [
        "view",
        "book_view",
        "like",
        "book_like",
        "dislike",
        "book_dislike",
        "favorite",
        "book_favorite",
        "want_to_read",
        "book_want_to_read",
        "reading",
        "book_reading",
        "finished",
        "book_finished",
        "unfavorite",
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
        logger.error(f"Tracking error: {exc}")
        return jsonify({"error": "Failed to track activity"}), 500



# ─────────────────────────────────────────────────────────────────────────────
# Learning Notes & Knowledge Retention
# ─────────────────────────────────────────────────────────────────────────────


@activity_bp.route("/notes", methods=["GET"])
@require_auth
def get_notes():
    user_id = g.user_id
    if not user_id:
        return jsonify({"error": "Unauthorized"}), 401

    book_id = request.args.get("book_id")
    note_type = request.args.get("note_type")
    query = request.args.get("q") or request.args.get("query")
    limit = _parse_int_param(request.args.get("limit"), default=50, min_val=1, max_val=100)
    offset = _parse_int_param(request.args.get("offset"), default=0, min_val=0)

    try:
        result = _get_notes_uc.execute(
            user_id=user_id,
            book_id=book_id,
            note_type=note_type,
            query=query,
            limit=limit,
            offset=offset,
        )
        return jsonify({"status": "success", **result}), 200
    except ValueError as val_err:
        return jsonify({"error": str(val_err)}), 400
    except Exception as exc:
        logger.error(f"Error fetching notes: {exc}")
        return jsonify({"error": "Failed to fetch learning notes"}), 500


@activity_bp.route("/notes", methods=["POST"])
@require_auth
def create_note():
    user_id = g.user_id
    if not user_id:
        return jsonify({"error": "Unauthorized"}), 401

    data = request.get_json(silent=True)
    if not data or not isinstance(data, dict):
        return jsonify({"error": "JSON body required"}), 400

    book_id = data.get("book_id")
    note_type = data.get("note_type", "personal_note")
    content = data.get("content")
    client_id = data.get("client_id")

    if not book_id or not str(book_id).strip():
        return jsonify({"error": "book_id is required"}), 400
    clean_book_id = str(book_id).strip()
    if len(clean_book_id) > 64:
        return jsonify({"error": "book_id exceeds maximum length of 64"}), 400
    if not content or not str(content).strip():
        return jsonify({"error": "content cannot be empty"}), 400
    clean_content = str(content)
    if len(clean_content) > 20000:
        return jsonify({"error": "content cannot exceed 20000 characters"}), 400
    if client_id and len(str(client_id)) > 128:
        return jsonify({"error": "client_id exceeds maximum length of 128"}), 400

    try:
        result = _create_note_uc.execute(
            user_id=user_id,
            book_id=str(book_id),
            note_type=str(note_type),
            content=str(content),
            client_id=str(client_id) if client_id else None,
        )
        payload = {"status": "success", "note": result}
        # Turn a takeaway into its AI recall question immediately so the user sees the value
        # of saving it. Never fail the note save because of this optional step.
        if _get_review_queue_uc and str(note_type) in ("key_takeaway", "question") and isinstance(result, dict):
            try:
                item = _get_review_queue_uc.create_item_for_note(user_id, result)
                if item:
                    payload["recall_item"] = {
                        "id": item.get("id"),
                        "question": item.get("question"),
                        "next_review_at": item.get("next_review_at"),
                    }
            except Exception as rec_err:
                logger.warning(f"Could not create recall item for note: {rec_err}")
        return jsonify(payload), 201
    except ValueError as val_err:
        return jsonify({"error": str(val_err)}), 400
    except Exception as exc:
        logger.error(f"Error creating note: {exc}")
        return jsonify({"error": "Failed to create learning note"}), 500


@activity_bp.route("/notes/<note_id>", methods=["GET"])
@require_auth
def get_note(note_id: str):
    user_id = g.user_id
    if not user_id:
        return jsonify({"error": "Unauthorized"}), 401

    try:
        note = _get_note_by_id_uc.execute(note_id=note_id, user_id=user_id)
        if not note:
            return jsonify({"error": "Note not found or access denied"}), 404
        return jsonify({"status": "success", "note": note}), 200
    except Exception as exc:
        logger.error(f"Error retrieving note {note_id}: {exc}")
        return jsonify({"error": "Failed to retrieve note"}), 500


@activity_bp.route("/notes/<note_id>", methods=["PUT", "PATCH"])
@require_auth
def update_note(note_id: str):
    user_id = g.user_id
    if not user_id:
        return jsonify({"error": "Unauthorized"}), 401

    data = request.get_json(silent=True)
    if not data or not isinstance(data, dict):
        return jsonify({"error": "JSON body required"}), 400

    content = data.get("content")
    note_type = data.get("note_type")

    if content is None or not str(content).strip():
        return jsonify({"error": "content cannot be empty"}), 400

    try:
        updated = _update_note_uc.execute(
            note_id=note_id,
            user_id=user_id,
            content=str(content),
            note_type=str(note_type) if note_type else None,
        )
        if not updated:
            return jsonify({"error": "Note not found or access denied"}), 404
        return jsonify({"status": "success", "note": updated}), 200
    except ValueError as val_err:
        return jsonify({"error": str(val_err)}), 400
    except Exception as exc:
        logger.error(f"Error updating note {note_id}: {exc}")
        return jsonify({"error": "Failed to update note"}), 500


@activity_bp.route("/notes/<note_id>", methods=["DELETE"])
@require_auth
def delete_note(note_id: str):
    user_id = g.user_id
    if not user_id:
        return jsonify({"error": "Unauthorized"}), 401

    try:
        deleted = _delete_note_uc.execute(note_id=note_id, user_id=user_id)
        if not deleted:
            return jsonify({"error": "Note not found or access denied"}), 404
        return jsonify({"status": "success", "deleted": True}), 200
    except Exception as exc:
        logger.error(f"Error deleting note {note_id}: {exc}")
        return jsonify({"error": "Failed to delete note"}), 500


@catalog_bp.route("/books/<isbn>/notes", methods=["GET"])
@require_auth
def get_book_notes(isbn: str):
    user_id = g.user_id
    if not user_id:
        return jsonify({"error": "Unauthorized"}), 401

    try:
        result = _get_notes_uc.execute(user_id=user_id, book_id=isbn, limit=100)
        return jsonify({"status": "success", "notes": result.get("notes", []), "total": result.get("total", 0)}), 200
    except Exception as exc:
        logger.error(f"Error getting book notes for {isbn}: {exc}")
        return jsonify({"error": "Failed to fetch book notes"}), 500



# ─────────────────────────────────────────────────────────────────────────────
# Smart Review & Spaced Repetition Endpoints
# ─────────────────────────────────────────────────────────────────────────────


@activity_bp.route("/notes/reviews/due", methods=["GET"])
@require_auth
def get_due_reviews():
    user_id = g.user_id
    if not user_id:
        return jsonify({"error": "Unauthorized"}), 401

    limit = _parse_int_param(request.args.get("limit"), default=50, min_val=1, max_val=100)
    try:
        reviews = _get_due_reviews_uc.execute(user_id=user_id, limit=limit)
        return jsonify({"status": "success", "reviews": reviews, "total": len(reviews)}), 200
    except Exception as exc:
        logger.error(f"Error fetching due reviews: {exc}")
        return jsonify({"error": "Failed to fetch due reviews"}), 500


@activity_bp.route("/notes/reviews/stats", methods=["GET"])
@require_auth
def get_review_stats():
    user_id = g.user_id
    if not user_id:
        return jsonify({"error": "Unauthorized"}), 401

    try:
        stats = _get_review_stats_uc.execute(user_id=user_id)
        return jsonify({"status": "success", "stats": stats}), 200
    except Exception as exc:
        logger.error(f"Error fetching review stats: {exc}")
        return jsonify({"error": "Failed to fetch review stats"}), 500


@activity_bp.route("/notes/<note_id>/review", methods=["POST"])
@require_auth
def submit_note_review(note_id: str):
    user_id = g.user_id
    if not user_id:
        return jsonify({"error": "Unauthorized"}), 401

    data = request.get_json(silent=True)
    if not data or not isinstance(data, dict):
        return jsonify({"error": "JSON body required"}), 400

    outcome = data.get("outcome")
    if not outcome or str(outcome).lower() not in {"remembered", "struggled"}:
        return jsonify({"error": "outcome must be 'remembered' or 'struggled'"}), 400

    try:
        updated = _process_review_uc.execute(
            note_id=note_id,
            user_id=user_id,
            outcome=str(outcome).lower(),
        )
        if not updated:
            return jsonify({"error": "Note not found or access denied"}), 404
        return jsonify({"status": "success", "review": updated}), 200
    except ValueError as val_err:
        return jsonify({"error": str(val_err)}), 400
    except Exception as exc:
        logger.error(f"Error submitting review for note {note_id}: {exc}")
        return jsonify({"error": "Failed to submit review"}), 500


@activity_bp.route("/notes/<note_id>/review/settings", methods=["PUT", "PATCH"])
@require_auth
def update_review_settings(note_id: str):
    user_id = g.user_id
    if not user_id:
        return jsonify({"error": "Unauthorized"}), 401

    data = request.get_json(silent=True)
    if not data or not isinstance(data, dict):
        return jsonify({"error": "JSON body required"}), 400

    status = data.get("status")
    if not status or str(status).lower() not in {"active", "paused", "completed"}:
        return jsonify({"error": "status must be 'active', 'paused', or 'completed'"}), 400

    try:
        updated = _update_review_settings_uc.execute(
            note_id=note_id,
            user_id=user_id,
            status=str(status).lower(),
        )
        if not updated:
            return jsonify({"error": "Note not found or access denied"}), 404
        return jsonify({"status": "success", "review": updated}), 200
    except ValueError as val_err:
        return jsonify({"error": str(val_err)}), 400
    except Exception as exc:
        logger.error(f"Error updating review settings for note {note_id}: {exc}")
        return jsonify({"error": "Failed to update review settings"}), 500


# ─────────────────────────────────────────────────────────────────────────────
# Notes Export Endpoint
# ─────────────────────────────────────────────────────────────────────────────


@activity_bp.route("/notes/export", methods=["GET"])
@require_auth
def export_notes():
    user_id = g.user_id
    if not user_id:
        return jsonify({"error": "Unauthorized"}), 401

    book_id = request.args.get("book_id")
    export_format = request.args.get("format", "markdown")
    as_json = request.args.get("json", "false").lower() == "true"

    try:
        result = _export_notes_uc.execute(
            user_id=user_id,
            book_id=book_id,
            export_format=export_format,
        )
        if as_json:
            return jsonify({"status": "success", **result}), 200

        response = Response(result["content"], mimetype=result["mime_type"])
        response.headers["Content-Disposition"] = f'attachment; filename="{result["filename"]}"'
        response.headers["Cache-Control"] = "no-store, private"
        return response
    except ValueError as val_err:
        return jsonify({"error": str(val_err)}), 400
    except Exception as exc:
        logger.error(f"Error exporting notes: {exc}")
        return jsonify({"error": "Failed to export notes"}), 500



# =============================================================================
# Learning Outcomes Intelligence Endpoints
# =============================================================================


@activity_bp.route("/learning/overview", methods=["GET"])
@require_auth
def get_learning_overview():
    user_id = g.user_id
    if not user_id:
        return jsonify({"error": "Unauthorized"}), 401

    try:
        overview = _get_learning_overview_uc.execute(user_id=user_id)
        return jsonify({"status": "success", "progress": overview}), 200
    except Exception as exc:
        logger.error(f"Error fetching learning overview for user {user_id}: {exc}")
        return jsonify({"error": "Failed to fetch learning overview"}), 500


@activity_bp.route("/learning/queue", methods=["GET"])
@require_auth
def get_learning_queue():
    user_id = g.user_id
    if not user_id:
        return jsonify({"error": "Unauthorized"}), 401

    concept = request.args.get("concept")
    limit = _parse_int_param(request.args.get("limit"), default=20, min_val=1, max_val=100)

    try:
        queue = _get_review_queue_uc.execute(
            user_id=user_id,
            concept=concept,
            limit=limit,
        )
        return jsonify({"status": "success", "queue": queue, "total": len(queue)}), 200
    except Exception as exc:
        logger.error(f"Error fetching review queue for user {user_id}: {exc}")
        return jsonify({"error": "Failed to fetch review queue"}), 500


@activity_bp.route("/learning/items/<item_id>", methods=["GET"])
@require_auth
def get_learning_item(item_id: str):
    user_id = g.user_id
    if not user_id:
        return jsonify({"error": "Unauthorized"}), 401

    item = container.learning_outcomes_repo.get_review_item_by_id(item_id, user_id)
    if not item:
        return jsonify({"error": "Review item not found"}), 404

    return jsonify({"status": "success", "item": item}), 200


@activity_bp.route("/learning/items", methods=["POST"])
@require_auth
def create_learning_item():
    user_id = g.user_id
    if not user_id:
        return jsonify({"error": "Unauthorized"}), 401

    data = request.get_json(silent=True)
    if not data or not isinstance(data, dict):
        return jsonify({"error": "JSON body required"}), 400

    title = data.get("title")
    concept = data.get("concept")
    question = data.get("question")
    answer = data.get("answer")

    if not title or not concept or not question or not answer:
        return jsonify({"error": "title, concept, question, and answer are required"}), 400

    try:
        item = _create_review_item_uc.execute(
            user_id=user_id,
            title=str(title).strip(),
            concept=str(concept).strip(),
            question=str(question).strip(),
            answer=str(answer).strip(),
            explanation=str(data.get("explanation", "")).strip(),
            source_type=str(data.get("source_type", "user_created")),
            source_id=data.get("source_id"),
            book_id=data.get("book_id"),
            metadata=data.get("metadata"),
        )
        return jsonify({"status": "success", "item": item}), 201
    except ValueError as val_err:
        return jsonify({"error": str(val_err)}), 400
    except Exception as exc:
        logger.error(f"Error creating review item: {exc}")
        return jsonify({"error": "Failed to create review item"}), 500


@activity_bp.route("/learning/items/<item_id>", methods=["PUT", "PATCH"])
@require_auth
def update_learning_item(item_id: str):
    user_id = g.user_id
    if not user_id:
        return jsonify({"error": "Unauthorized"}), 401

    data = request.get_json(silent=True)
    if not data or not isinstance(data, dict):
        return jsonify({"error": "JSON body required"}), 400

    try:
        updated = _update_review_item_uc.execute(
            user_id=user_id,
            item_id=item_id,
            updates=data,
        )
        if not updated:
            return jsonify({"error": "Review item not found or access denied"}), 404
        return jsonify({"status": "success", "item": updated}), 200
    except ValueError as val_err:
        return jsonify({"error": str(val_err)}), 400
    except Exception as exc:
        logger.error(f"Error updating review item {item_id}: {exc}")
        return jsonify({"error": "Failed to update review item"}), 500


@activity_bp.route("/learning/items/<item_id>", methods=["DELETE"])
@require_auth
def delete_learning_item(item_id: str):
    user_id = g.user_id
    if not user_id:
        return jsonify({"error": "Unauthorized"}), 401

    try:
        deleted = _delete_review_item_uc.execute(user_id=user_id, item_id=item_id)
        if not deleted:
            return jsonify({"error": "Review item not found or access denied"}), 404
        return jsonify({"status": "success", "message": "Review item deleted"}), 200
    except Exception as exc:
        logger.error(f"Error deleting review item {item_id}: {exc}")
        return jsonify({"error": "Failed to delete review item"}), 500


@activity_bp.route("/learning/items/<item_id>/attempt", methods=["POST"])
@require_auth
def submit_learning_attempt(item_id: str):
    user_id = g.user_id
    if not user_id:
        return jsonify({"error": "Unauthorized"}), 401

    data = request.get_json(silent=True)
    if not data or not isinstance(data, dict):
        return jsonify({"error": "JSON body required"}), 400

    outcome = data.get("outcome")
    if not outcome or str(outcome).lower() not in {"remembered", "struggled"}:
        return jsonify({"error": "outcome must be 'remembered' or 'struggled'"}), 400

    response_text = str(data.get("response_text", "")).strip()

    try:
        result = _submit_review_attempt_uc.execute(
            user_id=user_id,
            item_id=item_id,
            outcome=str(outcome).lower(),
            response_text=response_text,
        )
        if not result:
            return jsonify({"error": "Review item not found or access denied"}), 404
        return jsonify({"status": "success", **result}), 200
    except ValueError as val_err:
        return jsonify({"error": str(val_err)}), 400
    except Exception as exc:
        logger.error(f"Error recording review attempt for {item_id}: {exc}")
        return jsonify({"error": "Failed to record review attempt"}), 500


@activity_bp.route("/learning/history", methods=["GET"])
@require_auth
def get_learning_history():
    user_id = g.user_id
    if not user_id:
        return jsonify({"error": "Unauthorized"}), 401

    item_id = request.args.get("item_id")
    limit = _parse_int_param(request.args.get("limit"), default=50, min_val=1, max_val=100)
    offset = _parse_int_param(request.args.get("offset"), default=0, min_val=0, max_val=10000)

    try:
        history = _get_review_history_uc.execute(
            user_id=user_id,
            item_id=item_id,
            limit=limit,
            offset=offset,
        )
        return jsonify({"status": "success", **history}), 200
    except Exception as exc:
        logger.error(f"Error fetching learning history: {exc}")
        return jsonify({"error": "Failed to fetch learning history"}), 500


@activity_bp.route("/learning/concepts", methods=["GET"])
@require_auth
def get_learning_concepts():
    user_id = g.user_id
    if not user_id:
        return jsonify({"error": "Unauthorized"}), 401

    try:
        concepts = _get_concept_outcomes_uc.execute(user_id=user_id)
        return jsonify({"status": "success", "concepts": concepts, "total": len(concepts)}), 200
    except Exception as exc:
        logger.error(f"Error fetching concept outcomes: {exc}")
        return jsonify({"error": "Failed to fetch concept outcomes"}), 500
