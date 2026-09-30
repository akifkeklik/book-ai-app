import logging
from typing import Any, Dict, List, Optional

from supabase import Client

logger = logging.getLogger(__name__)


class SupabaseInteractionRepository:
    def __init__(self, supabase_client: Client):
        self._supabase = supabase_client

    def get_user_interactions(self, user_id: str) -> List[Dict[str, Any]]:
        if not self._supabase:
            return []
        try:
            resp = (
                self._supabase.table("user_interactions")
                .select("book_id, interaction_type")
                .eq("user_id", user_id)
                .execute()
            )
            return getattr(resp, "data", [])
        except Exception as e:
            logger.error(f"Failed to fetch user interactions: {e}")
            return []

    def get_user_profile(self, user_id: str) -> Optional[Dict[str, Any]]:
        if not self._supabase:
            return None
        try:
            resp = (
                self._supabase.table("user_profiles")
                .select("preferred_genres")
                .eq("user_id", user_id)
                .execute()
            )
            data = getattr(resp, "data", [])
            return data[0] if data else None
        except Exception as e:
            logger.error(f"Failed to fetch user profile: {e}")
            return None

    def upsert_interactions(self, entries: List[Dict[str, Any]]) -> None:
        if not self._supabase or not entries:
            return
        try:
            self._supabase.table("user_interactions").upsert(
                entries, on_conflict="user_id,book_id"
            ).execute()
        except Exception as e:
            logger.error(f"Failed to upsert interactions: {e}")
            raise e

    def upsert_profile(self, user_id: str, genres: List[str], updated_at: str) -> None:
        if not self._supabase:
            return
        try:
            self._supabase.table("user_profiles").upsert(
                {
                    "user_id": user_id,
                    "preferred_genres": genres,
                    "updated_at": updated_at,
                }
            ).execute()
        except Exception as e:
            logger.error(f"Failed to upsert profile: {e}")
            raise e

    def track_activity(self, payload: Dict[str, Any]) -> None:
        if not self._supabase:
            return
        try:
            self._supabase.table("user_activities").insert(payload).execute()
        except Exception as e:
            logger.error(f"Failed to track activity: {e}")
            raise e


class SupabaseBookDataPort:
    def __init__(self, supabase_client: Client):
        self._supabase = supabase_client

    def get_semantic_candidates(
        self, likes: List[str], limit: int = 100
    ) -> Dict[str, float]:
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

    def match_query_embeddings(
        self, embedding: List[float], limit: int = 100
    ) -> Dict[str, float]:
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
                self._supabase.table("books")
                .select("*")
                .in_("isbn13", isbns)
                .execute()
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
            self._supabase.table("book_embeddings").upsert(
                payload, on_conflict="book_id"
            ).execute()
        except Exception as e:
            logger.error(f"Error upserting embedding: {e}")
            raise e

class SupabaseAuthPort:
    def __init__(self, supabase_client: Client):
        self._supabase = supabase_client

    def verify_token(self, token: str) -> Any:
        if not self._supabase:
            raise Exception("Supabase client not initialized")
        user_response = self._supabase.auth.get_user(token)
        return user_response.user
