import datetime
import logging
from typing import Any, Dict, List, Optional

from supabase import Client

logger = logging.getLogger(__name__)


class SupabaseInteractionRepository:
    def __init__(self, supabase_client: Client):
        self._supabase = supabase_client

    def _get_client(self) -> Client:
        if not self._supabase:
            return None
        try:
            from flask import g, has_request_context

            if has_request_context() and getattr(g, "jwt_token", None):
                from backend.config import Config
                from supabase import create_client

                client = create_client(Config.SUPABASE_URL, Config.SUPABASE_ANON_KEY)
                client.postgrest.auth(g.jwt_token)
                return client
        except ImportError:
            pass
        return self._supabase

    def get_user_interactions(self, user_id: str) -> List[Dict[str, Any]]:
        client = self._get_client()
        if not client:
            return []
        try:
            resp = (
                client.table("user_interactions")
                .select("book_id, interaction_type")
                .eq("user_id", user_id)
                .execute()
            )
            return getattr(resp, "data", [])
        except Exception as e:
            logger.error(f"Failed to fetch user interactions: {e}")
            return []

    def get_user_favorites(self, user_id: str) -> List[Dict[str, Any]]:
        client = self._get_client()
        if not client:
            return []
        try:
            resp = (
                client.table("favorites")
                .select("book_id, book_title, book_author, book_image_url, added_at")
                .eq("user_id", user_id)
                .order("added_at", desc=True)
                .execute()
            )
            return getattr(resp, "data", []) or []
        except Exception as e:
            logger.error(f"Failed to fetch user favorites: {e}")
            return []

    @staticmethod
    def _is_schema_mismatch(error: Exception) -> bool:
        """Determines if a database exception is strictly an expected column-missing schema mismatch."""
        err_str = str(error).lower()
        return any(
            token in err_str
            for token in (
                "42703",  # Postgres undefined_column
                "pgrst204",  # PostgREST column not found in schema cache
                "column does not exist",
                "could not find the 'user_id' column",
                "could not find the 'preferred_authors' column",
                "schema cache",
            )
        )

    def get_user_profile(self, user_id: str) -> Optional[Dict[str, Any]]:
        client = self._get_client()
        if not client:
            return None
        try:
            # Dual-column & schema-tolerant retrieval:
            # Live unmigrated Supabase schema uses primary key 'id' (UUID).
            # Migrated dual-column schema supports 'id' and 'user_id'.
            # Selecting '*' retrieves whatever fields actually exist without hard-crashing
            # on missing optional columns (e.g. preferred_authors).
            data = None
            try:
                resp = client.table("user_profiles").select("*").eq("id", user_id).execute()
                data = getattr(resp, "data", [])
            except Exception as e_id:
                if not self._is_schema_mismatch(e_id):
                    logger.error(f"Query user_profiles by id failed with non-schema error: {e_id}")
                    raise e_id
                logger.debug(f"Query user_profiles by id failed due to schema mismatch: {e_id}")

            if not data:
                try:
                    resp = client.table("user_profiles").select("*").eq("user_id", user_id).execute()
                    data = getattr(resp, "data", [])
                except Exception as e_uid:
                    if not self._is_schema_mismatch(e_uid):
                        logger.error(f"Query user_profiles by user_id failed with non-schema error: {e_uid}")
                        raise e_uid
                    logger.debug(f"Query user_profiles by user_id failed due to schema mismatch: {e_uid}")

            if not data:
                return None

            row = data[0] if isinstance(data, list) and data else {}
            if not row:
                return None

            return {
                "user_id": row.get("user_id") or row.get("id") or user_id,
                "preferred_genres": row.get("preferred_genres") or [],
                "preferred_authors": row.get("preferred_authors") or [],
                "preferred_vibe": row.get("preferred_vibe"),
                "reading_frequency": row.get("reading_frequency"),
                "updated_at": row.get("updated_at"),
            }
        except Exception as e:
            logger.error(f"Failed to fetch user profile: {e}")
            return None

    def upsert_interactions(self, entries: List[Dict[str, Any]]) -> None:
        client = self._get_client()
        if not client:
            raise RuntimeError("Database client is not available")
        if not entries:
            return
        try:
            # Model A canonical contract:
            # "favorite" is stored canonically in `favorites` table, and should NOT
            # overwrite any existing reading status (reading, finished, want_to_read)
            # or signal (like, dislike) in `user_interactions`.
            fav_entries = [e for e in entries if e.get("interaction_type") == "favorite"]
            other_entries = [e for e in entries if e.get("interaction_type") != "favorite"]

            if other_entries:
                client.table("user_interactions").upsert(
                    other_entries, on_conflict="user_id,book_id"
                ).execute()

            if fav_entries:
                for fav in fav_entries:
                    uid = fav.get("user_id")
                    bid = fav.get("book_id")
                    if not uid or not bid:
                        continue
                    # 1. Sync to favorites table
                    try:
                        fav_row = {
                            "user_id": uid,
                            "book_id": bid,
                            "book_title": fav.get("book_name") or fav.get("book_title") or "Book",
                            "book_author": fav.get("book_author") or "Unknown Author",
                            "book_image_url": fav.get("book_image_url") or "",
                            "added_at": fav.get("created_at")
                            or datetime.datetime.now(datetime.timezone.utc).isoformat(),
                        }
                        client.table("favorites").upsert(
                            fav_row, on_conflict="user_id,book_id"
                        ).execute()
                    except Exception as fav_err:
                        logger.warning(f"Could not upsert into favorites table: {fav_err}")

                    # 2. In user_interactions, ONLY insert if no existing interaction
                    try:
                        existing = (
                            client.table("user_interactions")
                            .select("interaction_type")
                            .eq("user_id", uid)
                            .eq("book_id", bid)
                            .execute()
                        )
                        existing_data = getattr(existing, "data", [])
                        if not existing_data:
                            client.table("user_interactions").insert(fav).execute()
                    except Exception as insert_err:
                        logger.warning(f"Could not insert favorite into user_interactions: {insert_err}")
        except Exception as e:
            logger.error(f"Failed to upsert interactions: {e}")
            raise e

    def upsert_profile(
        self, user_id: str, genres: List[str], updated_at: str, authors: Optional[List[str]] = None
    ) -> None:
        client = self._get_client()
        if not client:
            raise RuntimeError("Database client is not available")

        # Dual-schema strategy:
        # 1. Try full dual-column payload ('id' and 'user_id', with 'preferred_authors' if provided)
        full_payload = {
            "id": user_id,
            "user_id": user_id,
            "preferred_genres": genres,
            "updated_at": updated_at,
        }
        if authors is not None:
            full_payload["preferred_authors"] = authors

        try:
            client.table("user_profiles").upsert(full_payload).execute()
            return
        except Exception as full_err:
            if not self._is_schema_mismatch(full_err):
                logger.error(f"Full profile upsert failed with non-schema error: {full_err}")
                raise full_err
            logger.debug(f"Full profile upsert attempt failed due to schema mismatch: {full_err}. Retrying with live schema columns.")

        # 2. Try live schema using 'id' as primary key with authors if provided
        live_payload = {
            "id": user_id,
            "preferred_genres": genres,
            "updated_at": updated_at,
        }
        if authors is not None:
            live_payload["preferred_authors"] = authors

        try:
            client.table("user_profiles").upsert(live_payload).execute()
            return
        except Exception as live_err:
            if not self._is_schema_mismatch(live_err):
                logger.error(f"Profile upsert with authors failed with non-schema error: {live_err}")
                raise live_err
            logger.debug(f"Profile upsert with authors failed due to schema mismatch: {live_err}. Retrying with baseline columns.")

        # 3. Baseline fallback: verified baseline columns ('id', 'preferred_genres', 'updated_at')
        baseline_payload = {
            "id": user_id,
            "preferred_genres": genres,
            "updated_at": updated_at,
        }
        client.table("user_profiles").upsert(baseline_payload).execute()

    def track_activity(self, payload: Dict[str, Any]) -> None:
        client = self._get_client()
        if not client:
            raise RuntimeError("Database client is not available")
        try:
            client.table("user_activities").insert(payload).execute()
        except Exception as e:
            logger.error(f"Failed to track activity: {e}")
            raise e

    def delete_interaction(
        self,
        user_id: str,
        book_id: str,
        interaction_type: Optional[str] = None,
        preserve_favorites: bool = False,
    ) -> None:
        client = self._get_client()
        if not client:
            raise RuntimeError("Database client is not available")
        try:
            query = (
                client.table("user_interactions")
                .delete()
                .eq("user_id", user_id)
                .eq("book_id", book_id)
            )
            if interaction_type:
                query = query.eq("interaction_type", interaction_type)
            elif preserve_favorites:
                query = query.neq("interaction_type", "favorite")
            query.execute()

            # If removing favorite interaction or complete removal without preserve_favorites, also remove from favorites table
            if not preserve_favorites and (interaction_type == "favorite" or interaction_type is None):
                try:
                    client.table("favorites").delete().eq("user_id", user_id).eq(
                        "book_id", book_id
                    ).execute()
                except Exception as fav_err:
                    logger.warning(f"Could not delete from favorites table: {fav_err}")
        except Exception as e:
            logger.error(f"Failed to delete interaction: {e}")
            raise e


class SupabaseBookDataPort:
    def __init__(self, supabase_client: Client):
        self._supabase = supabase_client

    def get_semantic_candidates(self, likes: List[str], limit: int = 100) -> Dict[str, float]:
        if not self._supabase or not likes:
            return {}
        try:
            rpc_resp = self._supabase.rpc(
                "match_book_embeddings",
                {
                    "seed_book_ids": list(likes),
                    "match_threshold": 0.0,
                    "match_count": limit,
                },
            ).execute()
            rpc_data = getattr(rpc_resp, "data", [])
            if rpc_data:
                return {row["book_id"]: row["similarity"] for row in rpc_data}
        except Exception as e:
            logger.warning(f"Semantic candidate generation failed: {e}")
        return {}

    def match_query_embeddings(self, embedding: List[float], limit: int = 100) -> Dict[str, float]:
        if not self._supabase:
            return {}
        try:
            response = self._supabase.rpc(
                "match_query_embeddings",
                {
                    "query_embedding": embedding,
                    "match_threshold": 0.0,
                    "match_count": limit,
                },
            ).execute()
            matches = getattr(response, "data", [])
            if matches:
                return {m["book_id"]: m["similarity"] for m in matches}
        except Exception as e:
            logger.error(f"Error in match_query_embeddings: {e}")
        return {}

    def get_books_by_isbns(self, isbns: List[str]) -> List[Dict[str, Any]]:
        if not self._supabase or not isbns:
            return []
        try:
            books_response = (
                self._supabase.table("books").select("*").in_("isbn13", isbns).execute()
            )
            return getattr(books_response, "data", [])
        except Exception as e:
            logger.error(f"Failed to get_books_by_isbns: {e}")
            return []

    def get_all_books_raw(self) -> List[Dict[str, Any]]:
        if not self._supabase:
            return []
        try:
            response = self._supabase.table("books").select("*").execute()
            return getattr(response, "data", [])
        except Exception as e:
            logger.error(f"Failed to get_all_books_raw: {e}")
            return []

    def get_embedding_metadata(self, book_id: str) -> Optional[Dict[str, Any]]:
        if not self._supabase:
            return None
        try:
            resp = (
                self._supabase.table("book_embeddings")
                .select("content_hash, model_version")
                .eq("book_id", book_id)
                .execute()
            )
            data = getattr(resp, "data", [])
            return data[0] if data else None
        except Exception as e:
            logger.error(f"Error fetching embedding metadata: {e}")
            return None

    def upsert_embedding(
        self, book_id: str, embedding: List[float], content_hash: str, model_version: str
    ) -> None:
        if not self._supabase:
            return
        try:
            payload = {
                "book_id": book_id,
                "embedding": embedding,
                "content_hash": content_hash,
                "model_version": model_version,
            }
            self._supabase.table("book_embeddings").upsert(payload, on_conflict="book_id").execute()
        except Exception as e:
            logger.error(f"Error upserting embedding: {e}")
            raise e

    def check_health(self) -> bool:
        if not self._supabase:
            return False
        try:
            self._supabase.table("books").select("isbn13").limit(1).execute()
            return True
        except Exception as e:
            logger.error(f"Health check failed: {e}")
            return False


class SupabaseAuthPort:
    def __init__(self, supabase_client: Client):
        self._supabase = supabase_client

    def verify_token(self, token: str) -> Any:
        if not self._supabase:
            raise Exception("Supabase client not initialized")
        user_response = self._supabase.auth.get_user(token)
        return user_response.user



class SupabaseNoteRepository:
    def __init__(self, supabase_client: Client):
        self._supabase = supabase_client

    def _get_client(self) -> Client:
        if not self._supabase:
            return None
        try:
            from flask import g, has_request_context

            if has_request_context() and getattr(g, "jwt_token", None):
                from backend.config import Config
                from supabase import create_client

                client = create_client(Config.SUPABASE_URL, Config.SUPABASE_ANON_KEY)
                client.postgrest.auth(g.jwt_token)
                return client
        except ImportError:
            pass
        return self._supabase

    def create_note(
        self, user_id: str, book_id: str, note_type: str, content: str, client_id: Optional[str] = None
    ) -> Dict[str, Any]:
        client = self._get_client()
        now = datetime.datetime.now(datetime.timezone.utc).isoformat()
        payload = {
            "user_id": user_id,
            "book_id": book_id,
            "note_type": note_type,
            "content": content,
            "created_at": now,
            "updated_at": now,
        }
        if client_id:
            payload["client_id"] = client_id
        if not client:
            return payload
        if client_id:
            try:
                existing = (
                    client.table("user_notes")
                    .select("*")
                    .eq("user_id", user_id)
                    .eq("client_id", client_id)
                    .limit(1)
                    .execute()
                )
                data = getattr(existing, "data", [])
                if data:
                    return data[0]
            except Exception:
                pass
        resp = client.table("user_notes").insert(payload).execute()
        data = getattr(resp, "data", [])
        return data[0] if data else payload

    def get_book_notes(self, user_id: str, book_id: str) -> List[Dict[str, Any]]:
        return self.get_user_notes(user_id=user_id, book_id=book_id)

    def get_user_notes(
        self,
        user_id: str,
        note_type: Optional[str] = None,
        book_id: Optional[str] = None,
        query: Optional[str] = None,
        limit: int = 50,
        offset: int = 0,
    ) -> List[Dict[str, Any]]:
        client = self._get_client()
        if not client:
            return []
        q = client.table("user_notes").select("*").eq("user_id", user_id)
        if note_type:
            q = q.eq("note_type", note_type)
        if book_id:
            q = q.eq("book_id", book_id)
        if query:
            q = q.ilike("content", f"%{query}%")
        resp = q.order("created_at", desc=True).range(offset, offset + limit - 1).execute()
        return getattr(resp, "data", []) or []

    def count_user_notes(
        self,
        user_id: str,
        note_type: Optional[str] = None,
        book_id: Optional[str] = None,
        query: Optional[str] = None,
    ) -> int:
        client = self._get_client()
        if not client:
            return 0
        q = client.table("user_notes").select("id", count="exact").eq("user_id", user_id)
        if note_type:
            q = q.eq("note_type", note_type)
        if book_id:
            q = q.eq("book_id", book_id)
        if query:
            q = q.ilike("content", f"%{query}%")
        resp = q.execute()
        return getattr(resp, "count", 0) or len(getattr(resp, "data", []) or [])

    def get_note_by_id(self, note_id: str, user_id: str) -> Optional[Dict[str, Any]]:
        client = self._get_client()
        if not client:
            return None
        resp = (
            client.table("user_notes")
            .select("*")
            .eq("id", note_id)
            .eq("user_id", user_id)
            .limit(1)
            .execute()
        )
        data = getattr(resp, "data", [])
        return data[0] if data else None

    def update_note(
        self, note_id: str, user_id: str, content: str, note_type: Optional[str] = None
    ) -> Optional[Dict[str, Any]]:
        client = self._get_client()
        if not client:
            return None
        payload = {
            "content": content,
            "updated_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        }
        if note_type:
            payload["note_type"] = note_type
        resp = (
            client.table("user_notes")
            .update(payload)
            .eq("id", note_id)
            .eq("user_id", user_id)
            .execute()
        )
        data = getattr(resp, "data", [])
        return data[0] if data else None

    def delete_note(self, note_id: str, user_id: str) -> bool:
        client = self._get_client()
        if not client:
            return False
        resp = (
            client.table("user_notes")
            .delete()
            .eq("id", note_id)
            .eq("user_id", user_id)
            .execute()
        )
        data = getattr(resp, "data", [])
        return bool(data)



class SupabaseNoteReviewRepository:
    def __init__(self, supabase_client: Client):
        self._supabase = supabase_client

    def _get_client(self) -> Client:
        if not self._supabase:
            return None
        try:
            from flask import g, has_request_context

            if has_request_context() and getattr(g, "jwt_token", None):
                from backend.config import Config
                from supabase import create_client

                client = create_client(Config.SUPABASE_URL, Config.SUPABASE_ANON_KEY)
                client.postgrest.auth(g.jwt_token)
                return client
        except ImportError:
            pass
        return self._supabase

    def schedule_initial_review(
        self, note_id: str, user_id: str, initial_interval_days: int = 1
    ) -> Dict[str, Any]:
        client = self._get_client()
        now = datetime.datetime.now(datetime.timezone.utc)
        next_review = now + datetime.timedelta(days=initial_interval_days)
        payload = {
            "note_id": note_id,
            "user_id": user_id,
            "stage": 1,
            "interval_days": initial_interval_days,
            "next_review_at": next_review.isoformat(),
            "last_reviewed_at": None,
            "review_count": 0,
            "status": "active",
            "created_at": now.isoformat(),
            "updated_at": now.isoformat(),
        }
        if not client:
            return payload
        try:
            # Check if exists
            existing = (
                client.table("note_reviews")
                .select("*")
                .eq("user_id", user_id)
                .eq("note_id", note_id)
                .limit(1)
                .execute()
            )
            data = getattr(existing, "data", [])
            if data:
                return data[0]

            resp = client.table("note_reviews").insert(payload).execute()
            data = getattr(resp, "data", [])
            return data[0] if data else payload
        except Exception:
            return payload

    def get_due_reviews(
        self, user_id: str, as_of: Optional[datetime.datetime] = None, limit: int = 50
    ) -> List[Dict[str, Any]]:
        client = self._get_client()
        if not client:
            return []
        target_time = as_of or datetime.datetime.now(datetime.timezone.utc)
        target_iso = target_time.isoformat()
        try:
            resp = (
                client.table("note_reviews")
                .select("*, user_notes(*)")
                .eq("user_id", user_id)
                .eq("status", "active")
                .lte("next_review_at", target_iso)
                .order("next_review_at", desc=False)
                .limit(limit)
                .execute()
            )
            data = getattr(resp, "data", []) or []
            # Flatten or format note data if joined
            formatted = []
            for item in data:
                entry = dict(item)
                if "user_notes" in entry and isinstance(entry["user_notes"], dict):
                    note_info = entry.pop("user_notes")
                    entry["note"] = note_info
                formatted.append(entry)
            return formatted
        except Exception:
            return []

    def get_review_by_note_id(self, note_id: str, user_id: str) -> Optional[Dict[str, Any]]:
        client = self._get_client()
        if not client:
            return None
        try:
            resp = (
                client.table("note_reviews")
                .select("*")
                .eq("user_id", user_id)
                .eq("note_id", note_id)
                .limit(1)
                .execute()
            )
            data = getattr(resp, "data", [])
            return data[0] if data else None
        except Exception:
            return None

    def record_review(
        self,
        note_id: str,
        user_id: str,
        outcome: str,
        next_interval_days: int,
        next_review_at: str,
        new_stage: int,
    ) -> Optional[Dict[str, Any]]:
        client = self._get_client()
        if not client:
            return None
        now_iso = datetime.datetime.now(datetime.timezone.utc).isoformat()
        try:
            current = self.get_review_by_note_id(note_id, user_id)
            review_count = (current.get("review_count", 0) + 1) if current else 1
            payload = {
                "stage": new_stage,
                "interval_days": next_interval_days,
                "next_review_at": next_review_at,
                "last_reviewed_at": now_iso,
                "review_count": review_count,
                "updated_at": now_iso,
            }
            resp = (
                client.table("note_reviews")
                .update(payload)
                .eq("user_id", user_id)
                .eq("note_id", note_id)
                .execute()
            )
            data = getattr(resp, "data", [])
            return data[0] if data else None
        except Exception:
            return None

    def get_review_stats(
        self, user_id: str, as_of: Optional[datetime.datetime] = None
    ) -> Dict[str, int]:
        client = self._get_client()
        if not client:
            return {"total": 0, "due": 0, "upcoming": 0, "completed": 0}
        target_time = as_of or datetime.datetime.now(datetime.timezone.utc)
        target_iso = target_time.isoformat()
        try:
            resp = client.table("note_reviews").select("id, status, next_review_at, stage").eq("user_id", user_id).execute()
            records = getattr(resp, "data", []) or []
            due_count = sum(1 for r in records if r.get("status") == "active" and (r.get("next_review_at") or "") <= target_iso)
            upcoming_count = sum(1 for r in records if r.get("status") == "active" and (r.get("next_review_at") or "") > target_iso)
            completed_count = sum(1 for r in records if r.get("status") == "completed" or r.get("stage", 0) >= 4)
            return {
                "total": len(records),
                "due": due_count,
                "upcoming": upcoming_count,
                "completed": completed_count,
            }
        except Exception:
            return {"total": 0, "due": 0, "upcoming": 0, "completed": 0}

    def update_review_settings(
        self, note_id: str, user_id: str, status: str
    ) -> Optional[Dict[str, Any]]:
        client = self._get_client()
        if not client:
            return None
        now_iso = datetime.datetime.now(datetime.timezone.utc).isoformat()
        try:
            resp = (
                client.table("note_reviews")
                .update({"status": status, "updated_at": now_iso})
                .eq("user_id", user_id)
                .eq("note_id", note_id)
                .execute()
            )
            data = getattr(resp, "data", [])
            return data[0] if data else None
        except Exception:
            return None

    def delete_review_by_note_id(self, note_id: str, user_id: str) -> bool:
        client = self._get_client()
        if not client:
            return False
        try:
            (
                client.table("note_reviews")
                .delete()
                .eq("user_id", user_id)
                .eq("note_id", note_id)
                .execute()
            )
            return True
        except Exception:
            return False



class SupabaseLearningOutcomesRepository:
    """
    Supabase implementation of LearningOutcomesRepository with RLS and user isolation.
    """

    def __init__(self, supabase_client=None):
        self._client = supabase_client

    def _get_client(self):
        if self._client:
            return self._client
        from backend.config import Config
        if Config.SUPABASE_URL and Config.SUPABASE_ANON_KEY:
            try:
                from supabase import create_client
                return create_client(Config.SUPABASE_URL, Config.SUPABASE_ANON_KEY)
            except Exception:
                return None
        return None

    def create_review_item(
        self,
        user_id: str,
        title: str,
        concept: str,
        question: str,
        answer: str,
        explanation: str = "",
        source_type: str = "user_created",
        source_id: Optional[str] = None,
        book_id: Optional[str] = None,
        path_id: Optional[str] = None,
        initial_stage: int = 1,
        initial_interval_days: int = 1,
        next_review_at: Optional[str] = None,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        client = self._get_client()
        now = datetime.datetime.now(datetime.timezone.utc)
        if not next_review_at:
            next_review_at = (now + datetime.timedelta(days=initial_interval_days)).isoformat()

        row = {
            "user_id": str(user_id),
            "title": str(title).strip(),
            "concept": str(concept).strip(),
            "question": str(question).strip(),
            "answer": str(answer).strip(),
            "explanation": str(explanation or "").strip(),
            "source_type": str(source_type),
            "source_id": str(source_id) if source_id else None,
            "book_id": str(book_id) if book_id else None,
            "path_id": str(path_id) if path_id else None,
            "stage": max(1, min(int(initial_stage), 5)),
            "interval_days": max(1, int(initial_interval_days)),
            "next_review_at": next_review_at,
            "total_reviews": 0,
            "successful_reviews": 0,
            "status": "active",
            "metadata": dict(metadata or {}),
            "created_at": now.isoformat(),
            "updated_at": now.isoformat(),
        }
        if not client:
            return row
        try:
            resp = client.table("review_items").insert(row).execute()
            records = getattr(resp, "data", []) or []
            return records[0] if records else row
        except Exception:
            return row

    def get_review_item_by_id(
        self, item_id: str, user_id: str
    ) -> Optional[Dict[str, Any]]:
        client = self._get_client()
        if not client:
            return None
        try:
            resp = (
                client.table("review_items")
                .select("*")
                .eq("id", str(item_id))
                .eq("user_id", str(user_id))
                .execute()
            )
            records = getattr(resp, "data", []) or []
            return records[0] if records else None
        except Exception:
            return None

    def update_review_item(
        self, item_id: str, user_id: str, updates: Dict[str, Any]
    ) -> Optional[Dict[str, Any]]:
        client = self._get_client()
        if not client:
            return None
        payload = dict(updates)
        payload["updated_at"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        try:
            resp = (
                client.table("review_items")
                .update(payload)
                .eq("id", str(item_id))
                .eq("user_id", str(user_id))
                .execute()
            )
            records = getattr(resp, "data", []) or []
            return records[0] if records else None
        except Exception:
            return None

    def delete_review_item(self, item_id: str, user_id: str) -> bool:
        client = self._get_client()
        if not client:
            return False
        try:
            client.table("review_items").delete().eq("id", str(item_id)).eq("user_id", str(user_id)).execute()
            return True
        except Exception:
            return False

    def list_review_items(
        self,
        user_id: str,
        concept: Optional[str] = None,
        path_id: Optional[str] = None,
        status: Optional[str] = "active",
        limit: int = 100,
        offset: int = 0,
    ) -> List[Dict[str, Any]]:
        client = self._get_client()
        if not client:
            return []
        try:
            q = client.table("review_items").select("*").eq("user_id", str(user_id))
            if status:
                q = q.eq("status", status)
            if concept:
                q = q.eq("concept", str(concept).strip())
            if path_id:
                q = q.eq("path_id", str(path_id).strip())
            q = q.order("next_review_at", desc=False).range(offset, offset + limit - 1)
            resp = q.execute()
            return getattr(resp, "data", []) or []
        except Exception:
            return []

    def get_due_review_items(
        self,
        user_id: str,
        as_of: Optional[datetime.datetime] = None,
        limit: int = 50,
    ) -> List[Dict[str, Any]]:
        client = self._get_client()
        if not client:
            return []
        target = as_of or datetime.datetime.now(datetime.timezone.utc)
        try:
            resp = (
                client.table("review_items")
                .select("*")
                .eq("user_id", str(user_id))
                .eq("status", "active")
                .lte("next_review_at", target.isoformat())
                .order("next_review_at", desc=False)
                .limit(limit)
                .execute()
            )
            return getattr(resp, "data", []) or []
        except Exception:
            return []

    def record_review_attempt(
        self,
        user_id: str,
        item_id: str,
        outcome: str,
        is_correct: bool,
        stage_before: int,
        stage_after: int,
        response_text: str = "",
        reviewed_at: Optional[str] = None,
    ) -> Dict[str, Any]:
        client = self._get_client()
        now = datetime.datetime.now(datetime.timezone.utc)
        attempt = {
            "user_id": str(user_id),
            "item_id": str(item_id),
            "outcome": str(outcome),
            "response_text": str(response_text or ""),
            "is_correct": bool(is_correct),
            "stage_before": int(stage_before),
            "stage_after": int(stage_after),
            "reviewed_at": reviewed_at or now.isoformat(),
            "created_at": now.isoformat(),
        }
        if not client:
            return attempt
        try:
            resp = client.table("review_attempts").insert(attempt).execute()
            records = getattr(resp, "data", []) or []
            return records[0] if records else attempt
        except Exception:
            return attempt

    def get_review_attempts(
        self,
        user_id: str,
        item_id: Optional[str] = None,
        limit: int = 50,
        offset: int = 0,
    ) -> List[Dict[str, Any]]:
        client = self._get_client()
        if not client:
            return []
        try:
            q = client.table("review_attempts").select("*").eq("user_id", str(user_id))
            if item_id:
                q = q.eq("item_id", str(item_id))
            q = q.order("reviewed_at", desc=True).range(offset, offset + limit - 1)
            resp = q.execute()
            return getattr(resp, "data", []) or []
        except Exception:
            return []

    def get_concept_stats(self, user_id: str) -> List[Dict[str, Any]]:
        items = self.list_review_items(user_id=user_id, status=None, limit=500)
        attempts = self.get_review_attempts(user_id=user_id, limit=1000)
        item_concept = {i.get("id"): i.get("concept", "General") for i in items}

        aggregates: Dict[str, Dict[str, Any]] = {}
        for i in items:
            c = i.get("concept", "General")
            if c not in aggregates:
                aggregates[c] = {
                    "concept": c,
                    "total_items": 0,
                    "total_attempts": 0,
                    "successful_recalls": 0,
                    "struggled_recalls": 0,
                    "stages_sum": 0,
                    "due_items": 0,
                }
            aggregates[c]["total_items"] += 1
            aggregates[c]["stages_sum"] += i.get("stage", 1)

        now_iso = datetime.datetime.now(datetime.timezone.utc).isoformat()
        for i in items:
            if i.get("status") == "active" and (i.get("next_review_at") or "") <= now_iso:
                c = i.get("concept", "General")
                if c in aggregates:
                    aggregates[c]["due_items"] += 1

        for a in attempts:
            c = item_concept.get(a.get("item_id"))
            if c and c in aggregates:
                agg = aggregates[c]
                agg["total_attempts"] += 1
                if a.get("outcome") == "remembered":
                    agg["successful_recalls"] += 1
                else:
                    agg["struggled_recalls"] += 1

        res = []
        for c, agg in aggregates.items():
            tot = agg["total_attempts"]
            struggled = agg["struggled_recalls"]
            items_count = agg["total_items"]
            avg_stage = round(agg["stages_sum"] / max(1, items_count), 2)
            ret_rate = round(agg["successful_recalls"] / max(1, tot), 2) if tot > 0 else 0.0
            needs_rev = (struggled >= 2 and (struggled / max(1, tot)) >= 0.4) or (agg["due_items"] > 0)
            res.append({
                "concept": c,
                "total_items": items_count,
                "total_attempts": tot,
                "successful_recalls": agg["successful_recalls"],
                "struggled_recalls": struggled,
                "retention_rate": ret_rate,
                "average_stage": avg_stage,
                "due_items": agg["due_items"],
                "needs_review": needs_rev,
            })
        res.sort(key=lambda x: (not x["needs_review"], -x["struggled_recalls"], x["concept"]))
        return res

    def get_user_progress_summary(
        self, user_id: str, as_of: Optional[datetime.datetime] = None
    ) -> Dict[str, Any]:
        items = self.list_review_items(user_id=user_id, status=None, limit=500)
        attempts = self.get_review_attempts(user_id=user_id, limit=1000)
        target_iso = (as_of or datetime.datetime.now(datetime.timezone.utc)).isoformat()

        active = [i for i in items if i.get("status") == "active"]
        due_count = sum(1 for i in active if (i.get("next_review_at") or "") <= target_iso)
        total_attempts = len(attempts)
        successful = sum(1 for a in attempts if a.get("outcome") == "remembered")
        struggled = sum(1 for a in attempts if a.get("outcome") == "struggled")

        return {
            "total_items": len(items),
            "active_items": len(active),
            "reviews_due": due_count,
            "reviews_completed": total_attempts,
            "successful_recalls": successful,
            "struggled_recalls": struggled,
        }
