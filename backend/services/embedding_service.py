import hashlib
import logging
import os
from typing import List, Optional

import openai
from openai import OpenAI

logger = logging.getLogger(__name__)

class EmbeddingService:
    def __init__(self, supabase_client=None):
        self._supabase = supabase_client
        self._model = os.getenv("EMBEDDING_MODEL", "text-embedding-3-small")
        self._dimension = int(os.getenv("EMBEDDING_DIMENSION", "1536"))
        self._client = None

        # Sadece OPENAI_API_KEY varsa client'ı başlat.
        api_key = os.getenv("OPENAI_API_KEY")
        if api_key:
            self._client = OpenAI(api_key=api_key)

    def is_configured(self) -> bool:
        return self._client is not None

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

    def generate_embedding(self, text: str) -> Optional[List[float]]:
        """
        OpenAI API'sini çağırarak metnin embedding'ini oluşturur.
        """
        if not self.is_configured():
            logger.warning("OpenAI API key not configured. Cannot generate embedding.")
            return None

        try:
            response = self._client.embeddings.create(
                input=[text],
                model=self._model,
                dimensions=self._dimension
            )
            return response.data[0].embedding
        except openai.APIError as e:
            logger.error(f"OpenAI API Error: {e}")
            return None
        except Exception as e:
            logger.error(f"Unexpected error during embedding generation: {e}")
            return None

    def get_existing_metadata(self, book_id: str) -> Optional[dict]:
        """
        Veritabanında bu kitap için embedding olup olmadığını kontrol eder.
        """
        if not self._supabase:
            return None

        try:
            resp = self._supabase.table("book_embeddings").select("content_hash, model_version").eq("book_id", book_id).execute()
            data = getattr(resp, "data", [])
            if data:
                return data[0]
            return None
        except Exception as e:
            logger.error(f"Error fetching embedding metadata: {e}")
            return None

    def upsert_embedding(self, book_id: str, embedding: List[float], content_hash: str) -> bool:
        """
        Oluşturulan embedding'i veritabanına kaydeder.
        """
        if not self._supabase:
            return False

        try:
            payload = {
                "book_id": book_id,
                "embedding": embedding,
                "content_hash": content_hash,
                "model_version": self._model
            }
            # book_embeddings tablosunda book_id primary key, bu nedenle on_conflict ile doğrudan update edilebilir.
            self._supabase.table("book_embeddings").upsert(
                payload,
                on_conflict="book_id"
            ).execute()
            return True
        except Exception as e:
            logger.error(f"Error upserting embedding: {e}")
            return False
