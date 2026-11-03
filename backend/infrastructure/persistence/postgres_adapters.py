"""
Real PostgreSQL Persistence Adapters for Libris.
Implements UserInteractionRepository and BookDataPort directly over psycopg2,
enforcing Model A canonical contracts, constraints, and RLS contexts.
"""

import datetime
import logging
from typing import Any, Dict, List, Optional

import psycopg2
from psycopg2.extras import RealDictCursor

logger = logging.getLogger(__name__)


class PostgresInteractionRepository:
    """
    Direct PostgreSQL implementation of UserInteractionRepository.
    Executes raw SQL matching Model A Migration 02 and 03 specifications.
    """

    def __init__(self, db_uri_or_conn: Any):
        if isinstance(db_uri_or_conn, str):
            self._db_uri = db_uri_or_conn
            self._conn = None
        else:
            self._db_uri = None
            self._conn = db_uri_or_conn

    def _get_connection(self):
        if self._conn and not self._conn.closed:
            return self._conn
        if self._db_uri:
            self._conn = psycopg2.connect(self._db_uri)
            self._conn.autocommit = True
            return self._conn
        raise RuntimeError("No active database connection or URI provided")

    def get_user_interactions(self, user_id: str) -> List[Dict[str, Any]]:
        conn = self._get_connection()
        try:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute(
                    """
                    SELECT book_id, interaction_type
                    FROM public.user_interactions
                    WHERE user_id = %s;
                    """,
                    (user_id,),
                )
                rows = cur.fetchall()
                return [dict(r) for r in rows]
        except Exception as e:
            logger.error(f"Failed to fetch user interactions from Postgres: {e}")
            return []

    def get_user_favorites(self, user_id: str) -> List[Dict[str, Any]]:
        conn = self._get_connection()
        try:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute(
                    """
                    SELECT book_id, book_title, book_author, book_image_url, added_at
                    FROM public.favorites
                    WHERE user_id = %s
                    ORDER BY added_at DESC;
                    """,
                    (user_id,),
                )
                rows = cur.fetchall()
                res = []
                for r in rows:
                    item = dict(r)
                    if isinstance(item.get("added_at"), (datetime.date, datetime.datetime)):
                        item["added_at"] = item["added_at"].isoformat()
                    res.append(item)
                return res
        except Exception as e:
            logger.error(f"Failed to fetch user favorites from Postgres: {e}")
            return []

    def get_user_profile(self, user_id: str) -> Optional[Dict[str, Any]]:
        conn = self._get_connection()
        try:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                row = None
                try:
                    cur.execute(
                        """
                        SELECT preferred_genres, preferred_authors, preferred_vibe, reading_frequency, updated_at
                        FROM public.user_profiles
                        WHERE user_id = %s
                        LIMIT 1;
                        """,
                        (user_id,),
                    )
                    row = cur.fetchone()
                except Exception:
                    conn.rollback()
                    try:
                        cur.execute(
                            """
                            SELECT preferred_genres, reading_frequency, updated_at
                            FROM public.user_profiles
                            WHERE id = %s
                            LIMIT 1;
                            """,
                            (user_id,),
                        )
                        row = cur.fetchone()
                    except Exception:
                        conn.rollback()

                if row:
                    res = dict(row)
                    if "user_id" not in res:
                        res["user_id"] = user_id
                    if "preferred_authors" not in res:
                        res["preferred_authors"] = []
                    if isinstance(res.get("updated_at"), (datetime.date, datetime.datetime)):
                        res["updated_at"] = res["updated_at"].isoformat()
                    return res
                return None
        except Exception as e:
            logger.error(f"Failed to fetch user profile from Postgres: {e}")
            return None

    def upsert_interactions(self, entries: List[Dict[str, Any]]) -> None:
        if not entries:
            return
        conn = self._get_connection()
        try:
            with conn.cursor() as cur:
                fav_entries = [e for e in entries if e.get("interaction_type") == "favorite"]
                other_entries = [e for e in entries if e.get("interaction_type") != "favorite"]

                # 1. Upsert reading statuses / signals (like, dislike, want_to_read, reading, finished)
                for entry in other_entries:
                    uid = entry.get("user_id")
                    bid = str(entry.get("book_id", "")).strip()
                    itype = entry.get("interaction_type")
                    created_at = entry.get("created_at") or datetime.datetime.now(datetime.timezone.utc).isoformat()
                    if not uid or not bid:
                        continue
                    cur.execute(
                        """
                        INSERT INTO public.user_interactions (user_id, book_id, interaction_type, created_at)
                        VALUES (%s, %s, %s, %s)
                        ON CONFLICT (user_id, book_id)
                        DO UPDATE SET interaction_type = EXCLUDED.interaction_type, created_at = EXCLUDED.created_at;
                        """,
                        (uid, bid, itype, created_at),
                    )

                # 2. Process favorite entries under Model A canonical contract:
                # - favorites table is canonical
                # - user_interactions table preserves any existing reading status
                for fav in fav_entries:
                    uid = fav.get("user_id")
                    bid = str(fav.get("book_id", "")).strip()
                    if not uid or not bid:
                        continue
                    title = fav.get("book_name") or fav.get("book_title") or "Book"
                    author = fav.get("book_author") or "Unknown Author"
                    image_url = fav.get("book_image_url") or ""
                    added_at = fav.get("created_at") or datetime.datetime.now(datetime.timezone.utc).isoformat()

                    # 2a. Canonical upsert to favorites table
                    cur.execute(
                        """
                        INSERT INTO public.favorites (user_id, book_id, book_title, book_author, book_image_url, added_at)
                        VALUES (%s, %s, %s, %s, %s, %s)
                        ON CONFLICT (user_id, book_id) DO UPDATE SET
                            book_title = EXCLUDED.book_title,
                            book_author = EXCLUDED.book_author,
                            book_image_url = EXCLUDED.book_image_url;
                        """,
                        (uid, bid, title, author, image_url, added_at),
                    )

                    # 2b. In user_interactions, ONLY insert if no existing interaction
                    cur.execute(
                        """
                        INSERT INTO public.user_interactions (user_id, book_id, interaction_type, created_at)
                        VALUES (%s, %s, 'favorite', %s)
                        ON CONFLICT (user_id, book_id) DO NOTHING;
                        """,
                        (uid, bid, added_at),
                    )
        except Exception as e:
            logger.error(f"Failed to upsert interactions in Postgres: {e}")
            raise e

    def upsert_profile(
        self, user_id: str, genres: List[str], updated_at: str, authors: Optional[List[str]] = None
    ) -> None:
        conn = self._get_connection()
        try:
            with conn.cursor() as cur:
                authors_list = authors if authors is not None else []
                try:
                    cur.execute(
                        """
                        INSERT INTO public.user_profiles (user_id, preferred_genres, preferred_authors, updated_at)
                        VALUES (%s, %s, %s, %s)
                        ON CONFLICT (user_id)
                        DO UPDATE SET
                            preferred_genres = EXCLUDED.preferred_genres,
                            preferred_authors = COALESCE(EXCLUDED.preferred_authors, user_profiles.preferred_authors),
                            updated_at = EXCLUDED.updated_at;
                        """,
                        (user_id, genres, authors_list, updated_at),
                    )
                except Exception:
                    conn.rollback()
                    cur.execute(
                        """
                        INSERT INTO public.user_profiles (id, preferred_genres, updated_at)
                        VALUES (%s, %s, %s)
                        ON CONFLICT (id)
                        DO UPDATE SET
                            preferred_genres = EXCLUDED.preferred_genres,
                            updated_at = EXCLUDED.updated_at;
                        """,
                        (user_id, genres, updated_at),
                    )
        except Exception as e:
            logger.error(f"Failed to upsert profile in Postgres: {e}")
            raise e

    def track_activity(self, payload: Dict[str, Any]) -> None:
        conn = self._get_connection()
        try:
            with conn.cursor() as cur:
                uid = payload.get("user_id")
                action = payload.get("action") or payload.get("activity_type") or "view"
                book_id = payload.get("book_id")
                created_at = payload.get("created_at") or datetime.datetime.now(datetime.timezone.utc).isoformat()
                cur.execute(
                    """
                    INSERT INTO public.user_activities (user_id, activity_type, book_id, created_at)
                    VALUES (%s, %s, %s, %s);
                    """,
                    (uid, action, book_id, created_at),
                )
        except Exception as e:
            logger.error(f"Failed to track activity in Postgres: {e}")
            raise e

    def delete_interaction(
        self,
        user_id: str,
        book_id: str,
        interaction_type: Optional[str] = None,
        preserve_favorites: bool = False,
    ) -> None:
        conn = self._get_connection()
        try:
            with conn.cursor() as cur:
                if interaction_type:
                    cur.execute(
                        """
                        DELETE FROM public.user_interactions
                        WHERE user_id = %s AND book_id = %s AND interaction_type = %s;
                        """,
                        (user_id, book_id, interaction_type),
                    )
                    if not preserve_favorites and interaction_type == "favorite":
                        cur.execute(
                            """
                            DELETE FROM public.favorites
                            WHERE user_id = %s AND book_id = %s;
                            """,
                            (user_id, book_id),
                        )
                elif preserve_favorites:
                    cur.execute(
                        """
                        DELETE FROM public.user_interactions
                        WHERE user_id = %s AND book_id = %s AND interaction_type != 'favorite';
                        """,
                        (user_id, book_id),
                    )
                else:
                    cur.execute(
                        """
                        DELETE FROM public.user_interactions
                        WHERE user_id = %s AND book_id = %s;
                        """,
                        (user_id, book_id),
                    )
                    cur.execute(
                        """
                        DELETE FROM public.favorites
                        WHERE user_id = %s AND book_id = %s;
                        """,
                        (user_id, book_id),
                    )
        except Exception as e:
            logger.error(f"Failed to delete interaction in Postgres: {e}")
            raise e


class PostgresBookDataPort:
    """
    Direct PostgreSQL implementation of BookDataPort.
    """

    def __init__(self, db_uri_or_conn: Any):
        if isinstance(db_uri_or_conn, str):
            self._db_uri = db_uri_or_conn
            self._conn = None
        else:
            self._db_uri = None
            self._conn = db_uri_or_conn

    def _get_connection(self):
        if self._conn and not self._conn.closed:
            return self._conn
        if self._db_uri:
            self._conn = psycopg2.connect(self._db_uri)
            self._conn.autocommit = True
            return self._conn
        raise RuntimeError("No active database connection or URI provided")

    def get_books_by_isbns(self, isbns: List[str]) -> List[Dict[str, Any]]:
        if not isbns:
            return []
        conn = self._get_connection()
        try:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute(
                    """
                    SELECT isbn13, title, authors, thumbnail, average_rating
                    FROM public.books
                    WHERE isbn13 = ANY(%s);
                    """,
                    (list(isbns),),
                )
                return [dict(r) for r in cur.fetchall()]
        except Exception as e:
            logger.error(f"Failed to get_books_by_isbns in Postgres: {e}")
            return []

    def get_all_books_raw(self) -> List[Dict[str, Any]]:
        conn = self._get_connection()
        try:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute("SELECT * FROM public.books;")
                return [dict(r) for r in cur.fetchall()]
        except Exception as e:
            logger.error(f"Failed to get_all_books_raw in Postgres: {e}")
            return []

    def check_health(self) -> bool:
        try:
            conn = self._get_connection()
            with conn.cursor() as cur:
                cur.execute("SELECT 1 FROM public.books LIMIT 1;")
                cur.fetchone()
                return True
        except Exception as e:
            logger.error(f"Database health check failed: {e}")
            return False

    def get_semantic_candidates(self, likes: List[str], limit: int = 100) -> Dict[str, float]:
        # Semantic RPC is Supabase pgvector specific. In local Postgres fallback gracefully.
        return {}



class PostgresNoteRepository:
    """
    Direct PostgreSQL implementation of UserNoteRepository.
    Executes raw SQL matching Migration 09 specifications.
    """

    def __init__(self, db_uri_or_conn: Any):
        if isinstance(db_uri_or_conn, str):
            self._db_uri = db_uri_or_conn
            self._conn = None
        else:
            self._db_uri = None
            self._conn = db_uri_or_conn

    def _get_connection(self):
        if self._conn and not self._conn.closed:
            return self._conn
        if self._db_uri:
            self._conn = psycopg2.connect(self._db_uri)
            self._conn.autocommit = True
            return self._conn
        raise RuntimeError("No active database connection or URI provided")

    def create_note(
        self, user_id: str, book_id: str, note_type: str, content: str
    ) -> Dict[str, Any]:
        conn = self._get_connection()
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                """
                INSERT INTO public.user_notes (user_id, book_id, note_type, content)
                VALUES (%s, %s, %s, %s)
                RETURNING id, user_id, book_id, note_type, content, created_at, updated_at;
                """,
                (user_id, book_id, note_type, content),
            )
            row = cur.fetchone()
            res = dict(row)
            for k in ("created_at", "updated_at"):
                if isinstance(res.get(k), (datetime.date, datetime.datetime)):
                    res[k] = res[k].isoformat()
            if "id" in res:
                res["id"] = str(res["id"])
            return res

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
        conn = self._get_connection()
        sql = "SELECT id, user_id, book_id, note_type, content, created_at, updated_at FROM public.user_notes WHERE user_id = %s"
        params = [user_id]
        if note_type:
            sql += " AND note_type = %s"
            params.append(note_type)
        if book_id:
            sql += " AND book_id = %s"
            params.append(book_id)
        if query:
            sql += " AND content ILIKE %s"
            params.append(f"%{query}%")
        sql += " ORDER BY created_at DESC LIMIT %s OFFSET %s;"
        params.extend([limit, offset])

        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(sql, tuple(params))
            rows = cur.fetchall()
            result = []
            for r in rows:
                item = dict(r)
                item["id"] = str(item["id"])
                for k in ("created_at", "updated_at"):
                    if isinstance(item.get(k), (datetime.date, datetime.datetime)):
                        item[k] = item[k].isoformat()
                result.append(item)
            return result

    def count_user_notes(
        self,
        user_id: str,
        note_type: Optional[str] = None,
        book_id: Optional[str] = None,
        query: Optional[str] = None,
    ) -> int:
        conn = self._get_connection()
        sql = "SELECT COUNT(*) AS total FROM public.user_notes WHERE user_id = %s"
        params = [user_id]
        if note_type:
            sql += " AND note_type = %s"
            params.append(note_type)
        if book_id:
            sql += " AND book_id = %s"
            params.append(book_id)
        if query:
            sql += " AND content ILIKE %s"
            params.append(f"%{query}%")
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(sql, tuple(params))
            row = cur.fetchone()
            return int(row["total"]) if row else 0

    def get_note_by_id(self, note_id: str, user_id: str) -> Optional[Dict[str, Any]]:
        conn = self._get_connection()
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                """
                SELECT id, user_id, book_id, note_type, content, created_at, updated_at
                FROM public.user_notes
                WHERE id = %s AND user_id = %s
                LIMIT 1;
                """,
                (note_id, user_id),
            )
            row = cur.fetchone()
            if not row:
                return None
            res = dict(row)
            res["id"] = str(res["id"])
            for k in ("created_at", "updated_at"):
                if isinstance(res.get(k), (datetime.date, datetime.datetime)):
                    res[k] = res[k].isoformat()
            return res

    def update_note(
        self, note_id: str, user_id: str, content: str, note_type: Optional[str] = None
    ) -> Optional[Dict[str, Any]]:
        conn = self._get_connection()
        now = datetime.datetime.now(datetime.timezone.utc)
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            if note_type:
                cur.execute(
                    """
                    UPDATE public.user_notes
                    SET content = %s, note_type = %s, updated_at = %s
                    WHERE id = %s AND user_id = %s
                    RETURNING id, user_id, book_id, note_type, content, created_at, updated_at;
                    """,
                    (content, note_type, now, note_id, user_id),
                )
            else:
                cur.execute(
                    """
                    UPDATE public.user_notes
                    SET content = %s, updated_at = %s
                    WHERE id = %s AND user_id = %s
                    RETURNING id, user_id, book_id, note_type, content, created_at, updated_at;
                    """,
                    (content, now, note_id, user_id),
                )
            row = cur.fetchone()
            if not row:
                return None
            res = dict(row)
            res["id"] = str(res["id"])
            for k in ("created_at", "updated_at"):
                if isinstance(res.get(k), (datetime.date, datetime.datetime)):
                    res[k] = res[k].isoformat()
            return res

    def delete_note(self, note_id: str, user_id: str) -> bool:
        conn = self._get_connection()
        with conn.cursor() as cur:
            cur.execute(
                "DELETE FROM public.user_notes WHERE id = %s AND user_id = %s;",
                (note_id, user_id),
            )
            return cur.rowcount > 0
