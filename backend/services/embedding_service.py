import hashlib
import logging
import os
import time
from typing import List, Optional

try:
    from ..domain.ports import BookDataPort
except ImportError:
    from domain.ports import BookDataPort

import google.generativeai as genai

logger = logging.getLogger(__name__)

class EmbeddingService:
    def __init__(self, book_data_port: Optional[BookDataPort] = None):
        self._book_data_port = book_data_port
        self._model = os.getenv("EMBEDDING_MODEL", "models/gemini-embedding-2")
        self._dimension = int(os.getenv("EMBEDDING_DIMENSION", "3072"))

        # In Libris V1, database vector embeddings are 3072-dimensional vectors produced
        # by Google Gemini (models/gemini-embedding-2). We accept GEMINI_API_KEY or LLM_API_KEY (when provider is gemini).
        provider = os.getenv("LLM_PROVIDER", "gemini").lower()
        self._api_key = os.getenv("GEMINI_API_KEY") or (os.getenv("LLM_API_KEY") if provider == "gemini" else None)

        if not self._api_key and os.getenv("LLM_API_KEY") and provider == "openai":
            logger.warning(
                "LLM_PROVIDER is set to 'openai' for text completions, but 3072-dim embeddings "
                "require Google Gemini. Set GEMINI_API_KEY to enable semantic embeddings."
            )

        if self._api_key:
            genai.configure(api_key=self._api_key)
            self._is_configured = True
        else:
            self._is_configured = False

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

    def generate_embedding(self, text: str, max_retries: int = 3) -> Optional[List[float]]:
        """
        Gemini API'sini çağırarak metnin embedding'ini oluşturur.
        Sabit (bounded) retry mekanizması içerir.
        """
        if not self.is_configured():
            logger.warning("LLM_API_KEY not configured. Cannot generate embedding.")
            return None

        attempt = 0
        while attempt < max_retries:
            try:
                response = genai.embed_content(
                    model=self._model,
                    content=text,
                    task_type="retrieval_document"
                )

                embedding = response['embedding']

                # Boyut (dimension) doğrulaması
                if len(embedding) != self._dimension:
                    logger.error(f"Dimension mismatch. Expected {self._dimension}, got {len(embedding)}.")
                    return None

                return embedding

            except Exception as e:
                attempt += 1
                error_str = str(e)
                sleep_time = 2 ** attempt

                if "429" in error_str or "Quota exceeded" in error_str or "ResourceExhausted" in error_str:
                    import re
                    match = re.search(r'retry in ([\d\.]+)s', error_str, re.IGNORECASE)
                    if match:
                        sleep_time = float(match.group(1)) + 1.0
                    else:
                        match2 = re.search(r'seconds:\s*(\d+)', error_str, re.IGNORECASE)
                        if match2:
                            sleep_time = float(match2.group(1)) + 1.0
                        else:
                            sleep_time = 61.0

                    # We give the quota errors more attempts since it's just a time limit
                    max_retries = max(max_retries, attempt + 2)
                    logger.warning(f"Quota exceeded. Waiting {sleep_time}s before retry (Attempt {attempt}/{max_retries})")
                else:
                    if attempt == max_retries:
                        logger.error(f"Gemini API failed after {max_retries} attempts. Last error: {e}")
                        return None
                    logger.warning(f"Transient error: {e}. Retrying in {sleep_time}s (Attempt {attempt}/{max_retries})")

                time.sleep(sleep_time)

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

        if meta.get("model_version") != self._model:
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
                model_version=self._model,
            )
            return True
        except Exception as e:
            logger.error(f"Error upserting embedding: {e}")
            return False
