"""Validation shared by the Supabase and Postgres vector-retrieval adapters."""

import math
from typing import Any, Dict, Iterable

try:
    from ...domain.ports import SemanticSearchUnavailable
except ImportError:  # imported as a top-level package by scripts/backfill_embeddings.py
    from domain.ports import SemanticSearchUnavailable


def parse_similarity_rows(rows: Any, source: str) -> Dict[str, float]:
    """
    {book_id: similarity} from vector RPC rows, or SemanticSearchUnavailable if the payload is
    malformed. A malformed response means "could not search", which callers must not confuse with
    the empty dict meaning "no similar books". Accepts mappings ({"book_id", "similarity"}) and
    2-item sequences (book_id, similarity), the shapes PostgREST and psycopg2 return.
    """
    if rows is None:
        return {}
    if isinstance(rows, (str, bytes)) or not isinstance(rows, Iterable) or isinstance(rows, dict):
        raise SemanticSearchUnavailable(f"{source} returned {type(rows).__name__}, expected a list of rows")
    out: Dict[str, float] = {}
    for i, row in enumerate(rows):
        try:
            if isinstance(row, dict):
                book_id, sim = row["book_id"], row["similarity"]
            else:
                book_id, sim = row
        except (KeyError, TypeError, ValueError) as e:
            raise SemanticSearchUnavailable(f"{source} row {i} is malformed: {row!r}") from e
        if book_id is None or not str(book_id).strip():
            raise SemanticSearchUnavailable(f"{source} row {i} has no book_id")
        try:
            score = float(sim)
        except (TypeError, ValueError) as e:
            raise SemanticSearchUnavailable(f"{source} row {i} has a non-numeric similarity: {sim!r}") from e
        if not math.isfinite(score):
            raise SemanticSearchUnavailable(f"{source} row {i} has a non-finite similarity: {sim!r}")
        out[str(book_id).strip()] = score
    return out
