import hashlib
import logging
import os
import re
import time
from typing import List, Optional

try:
    from ..domain.ports import BookDataPort, SemanticSearchUnavailable
    from ..infrastructure.llm.gemini_rest import GeminiRestClient
except ImportError:
    from domain.ports import BookDataPort, SemanticSearchUnavailable
    from infrastructure.llm.gemini_rest import GeminiRestClient


logger = logging.getLogger(__name__)

class EmbeddingService:
    def __init__(self, book_data_port: Optional[BookDataPort] = None):
        self._book_data_port = book_data_port
        self._model = os.getenv("EMBEDDING_MODEL", "models/gemini-embedding-2")
        self._dimension = int(os.getenv("EMBEDDING_DIMENSION", "3072"))
        self._doc_task = self._parse_document_task(os.getenv("EMBEDDING_DOCUMENT_TASK_TYPE"))
        self._query_format = (os.getenv("EMBEDDING_QUERY_FORMAT") or "legacy").strip().lower()
        if self._query_format not in self.QUERY_FORMATS:
            logger.warning("Unknown EMBEDDING_QUERY_FORMAT=%r; using 'legacy'", self._query_format)
            self._query_format = "legacy"
        self._profile_check_ttl = float(os.getenv("EMBEDDING_PROFILE_CHECK_TTL_SECONDS", "600"))
        self._profile_check: Optional[tuple] = None  # (monotonic time, problem or None)

        # In Libris V1, database vector embeddings are 3072-dimensional vectors produced
        # by Google Gemini (models/gemini-embedding-2). We accept GEMINI_API_KEY or LLM_API_KEY (when provider is gemini).
        provider = os.getenv("LLM_PROVIDER", "gemini").lower()
        self._api_key = os.getenv("GEMINI_API_KEY") or (os.getenv("LLM_API_KEY") if provider == "gemini" else None)

        if not self._api_key and os.getenv("LLM_API_KEY") and provider == "openai":
            logger.warning(
                "LLM_PROVIDER is set to 'openai' for text completions, but 3072-dim embeddings "
                "require Google Gemini. Set GEMINI_API_KEY to enable semantic embeddings."
            )

        self._client = GeminiRestClient(self._api_key) if self._api_key else None
        self._is_configured = self._client is not None

    def is_configured(self) -> bool:
        return self._is_configured

    def generate_canonical_text(self, book: dict) -> str:
        """
        Deterministik olarak kitabın embedding'i için metin üretir.
        Null alanları atlar.
        """
        parts = []

        title = str(book.get("title") or "").strip()
        if title:
            parts.append(f"Title: {title}")

        authors = str(book.get("authors") or "").strip()
        if authors:
            parts.append(f"Authors: {authors}")

        categories = str(book.get("categories") or "").strip()
        if categories:
            parts.append(f"Categories: {categories}")

        description = str(book.get("description") or "").strip()
        if description:
            # Whitespace normalizasyonu
            desc_clean = " ".join(description.split())
            parts.append(f"Description: {desc_clean}")

        return "\n".join(parts)

    def generate_content_hash(self, canonical_text: str) -> str:
        """
        Metinden SHA-256 hash üretir.
        """
        return hashlib.sha256(canonical_text.encode("utf-8")).hexdigest()

    # ── Embedding profile ─────────────────────────────────────────────────────
    #
    # A stored vector is only comparable with a query vector produced under a compatible
    # configuration. The *document profile* records everything that determines a stored vector:
    #   model;dim=<n>;text=<document text format>;task=<taskType sent with documents | none>
    # and is written to book_embeddings.model_version (TEXT, so no schema change is needed).
    #
    # Rows written before profiles existed hold only the model name. That code (commit 23760c6)
    # always sent taskType=RETRIEVAL_DOCUMENT, always produced generate_canonical_text() documents
    # and validated 3072 dimensions, so a bare model name M is read as
    #   M;dim=3072;text=canonical_v1;task=RETRIEVAL_DOCUMENT.
    #
    # Defaults reproduce that production configuration exactly, for documents AND queries (the
    # old RAG embedded queries through generate_embedding, i.e. with RETRIEVAL_DOCUMENT too), so
    # existing vectors stay valid. Alternatives are opt-in and must be measured first
    # (scripts/export_embedding_snapshot.py + scripts/run_retrieval_evaluation.py):
    #   EMBEDDING_DOCUMENT_TASK_TYPE  RETRIEVAL_DOCUMENT (default) | none
    #       Changing it changes the document profile -> every stored vector becomes stale.
    #   EMBEDDING_QUERY_FORMAT        legacy (default: raw text, same taskType as documents)
    #                                 raw             (raw text, no taskType)
    #                                 search_result   ("task: search result | query: ..." prefix,
    #                                                  the format Google documents for
    #                                                  gemini-embedding-2; no taskType)
    #                                 retrieval_query (raw text, taskType=RETRIEVAL_QUERY, the
    #                                                  asymmetric gemini-embedding-001 contract)
    # Whether gemini-embedding-2 actually uses the taskType field has NOT been verified against
    # the live API from this codebase; until it is, "legacy" is the only configuration known to
    # match the stored vectors.

    DOCUMENT_TEXT_FORMAT = "canonical_v1"  # bump when generate_canonical_text() changes
    LEGACY_DOCUMENT_TASK = "RETRIEVAL_DOCUMENT"
    LEGACY_DIMENSION = 3072
    QUERY_FORMATS = ("legacy", "raw", "search_result", "retrieval_query")
    DOCUMENT_TASKS = ("RETRIEVAL_DOCUMENT",)

    @classmethod
    def _parse_document_task(cls, raw: Optional[str]) -> Optional[str]:
        if raw is None or not raw.strip():
            return cls.LEGACY_DOCUMENT_TASK
        value = raw.strip()
        if value.lower() in ("none", "omit", "off"):
            return None
        if value.upper() in cls.DOCUMENT_TASKS:
            return value.upper()
        logger.warning("Unknown EMBEDDING_DOCUMENT_TASK_TYPE=%r; using %s", raw, cls.LEGACY_DOCUMENT_TASK)
        return cls.LEGACY_DOCUMENT_TASK

    def document_profile(self) -> str:
        """Profile of the document vectors this service writes (stored in model_version)."""
        task = self._doc_task or "none"
        return f"{self._model};dim={self._dimension};text={self.DOCUMENT_TEXT_FORMAT};task={task}"

    @classmethod
    def normalize_profile(cls, stored: Optional[str]) -> str:
        """Full profile for a stored model_version value; legacy bare model names are expanded."""
        value = str(stored or "").strip()
        if not value or ";" in value:
            return value
        return f"{value};dim={cls.LEGACY_DIMENSION};text=canonical_v1;task={cls.LEGACY_DOCUMENT_TASK}"

    def accepted_stored_values(self) -> List[str]:
        """Literal model_version values whose vectors match this service's document profile."""
        values = [self.document_profile()]
        if self.normalize_profile(self._model) == self.document_profile():
            values.append(self._model)  # legacy rows written before profiles existed
        return values

    def _query_request(self, query: str) -> tuple:
        """(text, taskType) sent for a user query under the configured EMBEDDING_QUERY_FORMAT."""
        text = " ".join(str(query or "").split())
        if self._query_format == "search_result":
            return f"task: search result | query: {text}", None
        if self._query_format == "retrieval_query":
            return text, "RETRIEVAL_QUERY"
        if self._query_format == "raw":
            return text, None
        return text, self._doc_task  # legacy: symmetric with the stored documents

    def format_query(self, query: str) -> str:
        return self._query_request(query)[0]

    def describe(self) -> dict:
        """The active embedding configuration, for logs, health output and evaluation exports."""
        return {
            "model": self._model,
            "dimension": self._dimension,
            "document_text_format": self.DOCUMENT_TEXT_FORMAT,
            "document_task_type": self._doc_task,
            "document_profile": self.document_profile(),
            "query_format": self._query_format,
            "query_task_type": self._query_request("")[1],
        }

    def check_store_compatibility(self, force: bool = False) -> Optional[str]:
        """
        None when the stored vectors match this service's document profile (or the store cannot
        be inspected); otherwise a description of the mismatch. Cached for
        EMBEDDING_PROFILE_CHECK_TTL_SECONDS (default 600) so it costs one small query per window.

        Any foreign profile blocks semantic queries, including a store that is part-way through a
        re-embedding: comparing a query against vectors from two incompatible spaces gives
        rankings that look plausible and are wrong, which is worse than an explicit fallback.
        """
        finder = getattr(self._book_data_port, "find_other_embedding_profiles", None)
        if self._book_data_port is None or not callable(finder):
            return None
        now = time.monotonic()
        if not force and self._profile_check and now - self._profile_check[0] < self._profile_check_ttl:
            return self._profile_check[1]
        problem = None
        try:
            others = finder(self.accepted_stored_values(), limit=5)
            if isinstance(others, (list, tuple, set)):
                foreign = sorted({str(o) for o in others if self.normalize_profile(o) != self.document_profile()})
                if foreign:
                    problem = (
                        f"stored vectors include embedding profile(s) {foreign}, but queries are embedded "
                        f"for {self.document_profile()!r}; re-embed the catalog (scripts/backfill_embeddings.py "
                        "--allow-profile-migration) or restore the matching EMBEDDING_* settings"
                    )
        except Exception as e:
            logger.warning(f"Could not inspect stored embedding profiles: {e}")
        if problem:
            logger.error(problem)
        self._profile_check = (now, problem)
        return problem

    def generate_embedding(self, text: str, max_retries: int = 3) -> Optional[List[float]]:
        """Embeds a catalog DOCUMENT (canonical book text). Used by the backfill job."""
        return self._embed(text, self._doc_task, max_retries=max_retries, wait_on_quota=True)

    def embed_query(self, query: str) -> Optional[List[float]]:
        """
        Embeds a user's search QUERY. Runs inside a web request, so it never waits out a quota
        window: one attempt (the REST client already retries a 429/503 once after ~2s), then None.
        Raises SemanticSearchUnavailable when the stored vectors use an incompatible profile.
        """
        problem = self.check_store_compatibility()
        if problem:
            raise SemanticSearchUnavailable(problem)
        text, task = self._query_request(query)
        return self._embed(text, task, max_retries=1, wait_on_quota=False)

    def _embed(self, text: str, task_type: Optional[str], max_retries: int, wait_on_quota: bool) -> Optional[List[float]]:
        """Calls the Gemini API with bounded retries and validates the vector dimension."""
        if not self.is_configured():
            logger.warning("GEMINI_API_KEY not configured. Cannot generate embedding.")
            return None

        attempt = 0
        while attempt < max_retries:
            try:
                embedding = self._client.embed(text, self._model, task_type=task_type)

                if len(embedding) != self._dimension:
                    logger.error(f"Dimension mismatch. Expected {self._dimension}, got {len(embedding)}.")
                    return None

                return embedding

            except Exception as e:
                attempt += 1
                error_str = str(e)
                sleep_time = 2 ** attempt
                is_quota = "429" in error_str or "Quota exceeded" in error_str or "ResourceExhausted" in error_str

                if is_quota and wait_on_quota:
                    match = re.search(r"retry in ([\d\.]+)s", error_str, re.IGNORECASE)
                    if match:
                        sleep_time = float(match.group(1)) + 1.0
                    else:
                        match2 = re.search(r"seconds:\s*(\d+)", error_str, re.IGNORECASE)
                        sleep_time = float(match2.group(1)) + 1.0 if match2 else 61.0

                    # Batch jobs get extra attempts on quota errors since they are only a time limit
                    max_retries = max(max_retries, attempt + 2)
                    logger.warning(f"Quota exceeded. Waiting {sleep_time}s before retry (Attempt {attempt}/{max_retries})")
                else:
                    if attempt >= max_retries:
                        logger.error(f"Gemini API failed after {attempt} attempt(s). Last error: {e}")
                        return None
                    logger.warning(f"Transient error: {e}. Retrying in {sleep_time}s (Attempt {attempt}/{max_retries})")

                time.sleep(sleep_time)
        return None

    def get_existing_metadata(self, book_id: str) -> Optional[dict]:
        """
        Veritabanında bu kitap için embedding olup olmadığını kontrol eder.
        """
        if not self._book_data_port:
            return None

        try:
            return self._book_data_port.get_embedding_metadata(book_id)
        except Exception as e:
            logger.error(f"Error fetching embedding metadata: {e}")
            return None

    def is_stale(self, book_id: str, current_content_hash: str) -> bool:
        """
        Mevcut embedding'in güncel olup olmadığını kontrol eder.
        Hash değişmişse VEYA model versiyonu değişmişse STALE kabul edilir (True döner).
        """
        meta = self.get_existing_metadata(book_id)
        if not meta:
            return True # Yoksa stale sayılır (yeniden üretilmelidir)

        if meta.get("content_hash") != current_content_hash:
            return True

        # Stale when the stored vector came from another embedding profile (model, dimension,
        # document text format or document task type), not only another model name.
        if self.normalize_profile(meta.get("model_version")) != self.document_profile():
            return True

        return False

    def upsert_embedding(self, book_id: str, embedding: List[float], content_hash: str) -> bool:
        """
        Oluşturulan embedding'i veritabanına kaydeder.
        """
        if not self._book_data_port:
            return False

        try:
            self._book_data_port.upsert_embedding(
                book_id=book_id,
                embedding=embedding,
                content_hash=content_hash,
                model_version=self.document_profile(),
            )
            return True
        except Exception as e:
            logger.error(f"Error upserting embedding: {e}")
            return False
