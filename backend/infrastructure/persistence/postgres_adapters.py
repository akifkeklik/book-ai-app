"""
Real PostgreSQL Persistence Adapters for Libris.
Implements UserInteractionRepository and BookDataPort directly over psycopg2,
enforcing Model A canonical contracts, constraints, and RLS contexts.
"""

import datetime
import logging
import os
from contextlib import contextmanager
from typing import Any, Dict, List, Optional

import psycopg2
import psycopg2.errors
from psycopg2.extras import RealDictCursor

from ...domain.ports import SemanticSearchUnavailable
from .vector_rows import parse_similarity_rows

logger = logging.getLogger(__name__)

# Upper bound for one vector RPC. An exact scan over ~6.5k 3072-d rows takes well under a second;
# anything slower is a stuck or overloaded database, and the request should fall back instead.
VECTOR_QUERY_TIMEOUT_MS = int(os.getenv("VECTOR_QUERY_TIMEOUT_MS", "5000"))

# An HNSW scan returns at most hnsw.ef_search rows (pgvector default 40), whatever LIMIT asks for.
# Measured on the live index (6,446 real vectors, reports/pgvector_live_benchmark.json): a request
# for 100 rows returned exactly 40 at the default; ef_search=200 returned 100 with recall@100 0.994.
# Set per transaction (SET LOCAL) so no server setting changes. ef_search = max(floor, 2 * limit).
VECTOR_EF_SEARCH_MIN = int(os.getenv("VECTOR_EF_SEARCH_MIN", "40"))
VECTOR_EF_SEARCH_MAX = 1000  # pgvector's upper bound for hnsw.ef_search


def hnsw_ef_search_for(limit: int) -> int:
    """hnsw.ef_search that lets an HNSW scan return `limit` rows with high recall."""
    return max(VECTOR_EF_SEARCH_MIN, min(VECTOR_EF_SEARCH_MAX, 2 * max(1, int(limit))))


@contextmanager
def _transaction(conn, explicit: bool = False):
    """
    One unit of work on `conn`, correct for both connection kinds the adapters accept:

    - URI-created connections are autocommit, so each statement already commits on its own.
      With explicit=True a real transaction is opened (BEGIN ... COMMIT/ROLLBACK) so that
      SET LOCAL settings such as statement_timeout apply and are discarded afterwards.
    - Injected connections may be in psycopg2's default transactional mode. Then the work is
      committed on success and rolled back on any error, so a failed statement cannot leave the
      connection "in failed transaction" (every later query would error) and successful writes
      are not silently lost when the caller never commits.
    """
    began = False
    if explicit and conn.autocommit:
        with conn.cursor() as cur:
            cur.execute("BEGIN")
        began = True
    try:
        yield conn
    except BaseException:
        try:
            if began:
                with conn.cursor() as cur:
                    cur.execute("ROLLBACK")
            elif not conn.autocommit:
                conn.rollback()
        except Exception as rollback_error:  # the original error matters more
            logger.warning(f"Rollback failed: {rollback_error}")
        raise
    else:
        if began:
            with conn.cursor() as cur:
                cur.execute("COMMIT")
        elif not conn.autocommit:
            conn.commit()


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
            with _transaction(conn), conn.cursor(cursor_factory=RealDictCursor) as cur:
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
            with _transaction(conn), conn.cursor(cursor_factory=RealDictCursor) as cur:
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
            with _transaction(conn), conn.cursor(cursor_factory=RealDictCursor) as cur:
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
            with _transaction(conn), conn.cursor() as cur:
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
            with _transaction(conn), conn.cursor() as cur:
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
            with _transaction(conn), conn.cursor() as cur:
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
            with _transaction(conn), conn.cursor() as cur:
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
            with _transaction(conn), conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute(
                    """
                    SELECT *
                    FROM public.books
                    WHERE isbn13 = ANY(%s);
                    """,
                    (list(isbns),),
                )
                return [dict(r) for r in cur.fetchall()]
        except Exception as e:
            logger.error(f"Failed to get_books_by_isbns in Postgres: {e}")
            return []

    BOOK_COLUMNS = (
        "isbn13", "title", "authors", "categories", "description", "thumbnail",
        "average_rating", "ratings_count", "published_date", "page_count",
    )

    def add_book(self, book: Dict[str, Any], user_token: Optional[str] = None) -> bool:
        """Inserts a contributed book; never overwrites an existing catalog row."""
        conn = self._get_connection()
        cols = [c for c in self.BOOK_COLUMNS if c in book]
        try:
            with _transaction(conn), conn.cursor() as cur:
                cur.execute(
                    f"INSERT INTO public.books ({', '.join(cols)}) VALUES ({', '.join(['%s'] * len(cols))}) "
                    "ON CONFLICT (isbn13) DO NOTHING;",
                    [book[c] for c in cols],
                )
            return True
        except Exception as e:
            logger.error(f"Failed to add_book in Postgres: {e}")
            return False

    def get_all_isbns(self) -> List[str]:
        conn = self._get_connection()
        try:
            with _transaction(conn), conn.cursor() as cur:
                cur.execute("SELECT isbn13 FROM public.books;")
                return [r[0] for r in cur.fetchall()]
        except Exception as e:
            logger.error(f"Failed to get_all_isbns in Postgres: {e}")
            return []

    def get_all_books_raw(self) -> List[Dict[str, Any]]:
        conn = self._get_connection()
        try:
            with _transaction(conn), conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute("SELECT * FROM public.books;")
                return [dict(r) for r in cur.fetchall()]
        except Exception as e:
            logger.error(f"Failed to get_all_books_raw in Postgres: {e}")
            return []

    def check_health(self) -> bool:
        try:
            conn = self._get_connection()
            with _transaction(conn), conn.cursor() as cur:
                cur.execute("SELECT 1 FROM public.books LIMIT 1;")
                cur.fetchone()
                return True
        except Exception as e:
            logger.error(f"Database health check failed: {e}")
            return False

    # ── Vector retrieval ─────────────────────────────────────────────────────
    # Calls the same SQL functions Supabase exposes as RPCs (migrations 03/05/06), so both
    # adapters rank with one implementation. A missing pgvector table or function raises
    # SemanticSearchUnavailable instead of returning {} (which would read as "no matches").

    def _vector_query(self, sql: str, params: tuple, limit: int = 100) -> Dict[str, float]:
        """Runs one vector RPC under a statement timeout and a matching hnsw.ef_search, in its own
        transaction (SET LOCAL: both settings end with it)."""
        try:
            conn = self._get_connection()
            with _transaction(conn, explicit=True), conn.cursor() as cur:
                cur.execute("SET LOCAL statement_timeout = %s", (f"{int(VECTOR_QUERY_TIMEOUT_MS)}ms",))
                cur.execute("SELECT set_config('hnsw.ef_search', %s, true)", (str(hnsw_ef_search_for(limit)),))
                cur.execute(sql, params)
                rows = cur.fetchall()
        except (psycopg2.errors.UndefinedTable, psycopg2.errors.UndefinedFunction,
                psycopg2.errors.UndefinedObject) as e:
            raise SemanticSearchUnavailable(
                f"pgvector schema missing (apply migrations 03, 05, 06): {str(e).splitlines()[0]}"
            ) from e
        except psycopg2.errors.QueryCanceled as e:
            raise SemanticSearchUnavailable(
                f"vector query exceeded {VECTOR_QUERY_TIMEOUT_MS} ms: {str(e).splitlines()[0]}"
            ) from e
        except psycopg2.Error as e:
            raise SemanticSearchUnavailable(f"vector query failed: {str(e).splitlines()[0]}") from e
        return parse_similarity_rows(rows, "vector query")

    def get_semantic_candidates(self, likes: List[str], limit: int = 100) -> Dict[str, float]:
        if not likes:
            return {}
        return self._vector_query(
            "SELECT book_id, similarity FROM public.match_book_embeddings(%s::text[], 0.0, %s);",
            (list(likes), int(limit)),
            limit=int(limit),
        )

    def match_query_embeddings(self, embedding: List[float], limit: int = 100) -> Dict[str, float]:
        if not embedding:
            return {}
        return self._vector_query(
            "SELECT book_id, similarity FROM public.match_query_embeddings(%s::vector, 0.0, %s);",
            (_vector_literal(embedding), int(limit)),
            limit=int(limit),
        )

    def get_embedding_metadata(self, book_id: str) -> Optional[Dict[str, Any]]:
        conn = self._get_connection()
        try:
            with _transaction(conn), conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute(
                    "SELECT content_hash, model_version FROM public.book_embeddings WHERE book_id = %s;",
                    (book_id,),
                )
                row = cur.fetchone()
                return dict(row) if row else None
        except psycopg2.Error as e:
            logger.error(f"Error fetching embedding metadata in Postgres: {e}")
            return None

    def find_other_embedding_profiles(self, accepted: List[str], limit: int = 5) -> List[str]:
        """Stored model_version values outside `accepted`."""
        conn = self._get_connection()
        with _transaction(conn), conn.cursor() as cur:
            cur.execute(
                "SELECT DISTINCT model_version FROM public.book_embeddings "
                "WHERE NOT (model_version = ANY(%s)) LIMIT %s;",
                (list(accepted), max(1, int(limit))),
            )
            return sorted(str(r[0]) for r in cur.fetchall() if r[0])

    def upsert_embedding(
        self, book_id: str, embedding: List[float], content_hash: str, model_version: str
    ) -> None:
        conn = self._get_connection()
        with _transaction(conn), conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO public.book_embeddings (book_id, embedding, content_hash, model_version)
                VALUES (%s, %s::vector, %s, %s)
                ON CONFLICT (book_id) DO UPDATE SET
                    embedding = EXCLUDED.embedding,
                    content_hash = EXCLUDED.content_hash,
                    model_version = EXCLUDED.model_version,
                    updated_at = now();
                """,
                (book_id, _vector_literal(embedding), content_hash, model_version),
            )


def _vector_literal(embedding: List[float]) -> str:
    """pgvector text input format: '[0.1,0.2,...]'."""
    return "[" + ",".join(repr(float(x)) for x in embedding) + "]"



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
        with _transaction(conn), conn.cursor(cursor_factory=RealDictCursor) as cur:
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

        with _transaction(conn), conn.cursor(cursor_factory=RealDictCursor) as cur:
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
        with _transaction(conn), conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(sql, tuple(params))
            row = cur.fetchone()
            return int(row["total"]) if row else 0

    def get_note_by_id(self, note_id: str, user_id: str) -> Optional[Dict[str, Any]]:
        conn = self._get_connection()
        with _transaction(conn), conn.cursor(cursor_factory=RealDictCursor) as cur:
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
        with _transaction(conn), conn.cursor(cursor_factory=RealDictCursor) as cur:
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
        with _transaction(conn), conn.cursor() as cur:
            cur.execute(
                "DELETE FROM public.user_notes WHERE id = %s AND user_id = %s;",
                (note_id, user_id),
            )
            return cur.rowcount > 0
