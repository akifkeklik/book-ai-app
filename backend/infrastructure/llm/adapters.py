import logging
import re
import threading
import time
from typing import Optional

from ...domain.ports import LlmPort

logger = logging.getLogger(__name__)


def _sanitize_secret(msg: str) -> str:
    """Removes API keys or authorization tokens from error messages and logs."""
    if not msg:
        return ""
    sanitized = re.sub(
        r"(key|api_key|token|password|secret)=[A-Za-z0-9_\-\.]+",
        r"\1=REDACTED",
        str(msg),
        flags=re.IGNORECASE,
    )
    sanitized = re.sub(
        r"Bearer\s+[A-Za-z0-9_\-\.]+",
        "Bearer REDACTED",
        sanitized,
        flags=re.IGNORECASE,
    )
    return sanitized


class GenericLlmAdapter(LlmPort):
    def __init__(self, provider: str, api_key: str, model_name: Optional[str] = None):
        self._provider = provider
        self._api_key = api_key
        self._model_name = model_name or ("models/gemini-2.5-flash" if provider == "gemini" else "gpt-3.5-turbo")
        self._gemini_model = None
        self._openai_client = None
        self._lock = threading.Lock()
        self.last_latency_ms: float = 0.0

        if self._api_key and self._provider == "gemini":
            try:
                import google.generativeai as genai
                genai.configure(api_key=self._api_key)
                self._gemini_model = genai.GenerativeModel(self._model_name)
            except Exception as e:
                logger.warning(f"Failed to pre-initialize Gemini model: {_sanitize_secret(str(e))}")

    def generate_response(self, system_prompt: str, user_prompt: str) -> Optional[str]:
        if not self._api_key:
            logger.error("LLM_API_KEY is missing.")
            return None

        t0 = time.time()
        try:
            if self._provider == "gemini":
                if self._gemini_model is None:
                    with self._lock:
                        if self._gemini_model is None:
                            import google.generativeai as genai
                            genai.configure(api_key=self._api_key)
                            self._gemini_model = genai.GenerativeModel(self._model_name)

                response = self._gemini_model.generate_content(
                    system_prompt + "\n\n" + user_prompt,
                    generation_config={"temperature": 0.3},
                    request_options={"timeout": 15.0},  # Added timeout to prevent hanging
                )
                lat = round((time.time() - t0) * 1000, 2)
                with self._lock:
                    self.last_latency_ms = lat

                try:
                    return response.text
                except (ValueError, AttributeError) as text_err:
                    logger.warning(f"Gemini response has no text part (safety or empty): {_sanitize_secret(str(text_err))}")
                    return None

            elif self._provider == "openai":
                if self._openai_client is None:
                    with self._lock:
                        if self._openai_client is None:
                            from openai import OpenAI
                            self._openai_client = OpenAI(api_key=self._api_key, timeout=15.0)

                response = self._openai_client.chat.completions.create(
                    model=self._model_name,
                    temperature=0.3,
                    messages=[
                        {"role": "system", "content": system_prompt},
                        {"role": "user", "content": user_prompt},
                    ],
                )
                lat = round((time.time() - t0) * 1000, 2)
                with self._lock:
                    self.last_latency_ms = lat
                return response.choices[0].message.content
            else:
                logger.error(f"Unsupported LLM provider: {self._provider}")
                return None

        except Exception as e:
            lat = round((time.time() - t0) * 1000, 2)
            with self._lock:
                self.last_latency_ms = lat
            clean_err = _sanitize_secret(str(e))
            logger.error(
                "LLM provider error",
                extra={
                    "extra_data": {
                        "provider": self._provider,
                        "model": self._model_name,
                        "error": clean_err,
                        "error_type": type(e).__name__,
                        "latency_ms": lat,
                    }
                },
            )
            return None
