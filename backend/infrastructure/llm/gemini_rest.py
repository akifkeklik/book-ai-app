"""Minimal client for the official Gemini REST API (generativelanguage.googleapis.com).

Why REST instead of an SDK: the legacy `google-generativeai` package is no longer
maintained, and every version of its replacement `google-genai` requires
`websockets>=13`, which conflicts with the Supabase client used here
(`realtime` requires `websockets<13`). The REST API is what both SDKs call.
The API key is sent in a header, never in the URL, so it cannot leak into logs.
"""

import logging
import time
from typing import List, Optional

import requests

logger = logging.getLogger(__name__)

API_BASE = "https://generativelanguage.googleapis.com/v1beta"
DEFAULT_TEXT_MODEL = "gemini-3.5-flash-lite"


class GeminiError(RuntimeError):
    def __init__(self, message: str, status: int = 0):
        super().__init__(message)
        self.status = status


def _model_path(model: str) -> str:
    return model if model.startswith("models/") else f"models/{model}"


class GeminiRestClient:
    def __init__(self, api_key: str, session: Optional[requests.Session] = None, retry_wait_seconds: float = 2.0):
        self._api_key = api_key
        self._session = session or requests.Session()
        self._retry_wait = retry_wait_seconds

    def _post(self, model: str, method: str, payload: dict, timeout: float) -> dict:
        url = f"{API_BASE}/{_model_path(model)}:{method}"
        headers = {"x-goog-api-key": self._api_key, "Content-Type": "application/json"}
        for attempt in (1, 2):
            resp = self._session.post(url, json=payload, headers=headers, timeout=timeout)
            # Free-tier per-minute quota: one short retry recovers most bursts.
            if resp.status_code in (429, 503) and attempt == 1:
                time.sleep(self._retry_wait)
                continue
            if resp.status_code != 200:
                try:
                    detail = resp.json().get("error", {}).get("message", "")
                except ValueError:
                    detail = resp.text[:200]
                raise GeminiError(f"Gemini {method} failed ({resp.status_code}): {detail[:200]}", resp.status_code)
            return resp.json()
        raise GeminiError("unreachable")

    def generate_text(self, prompt: str, model: str = DEFAULT_TEXT_MODEL, temperature: float = 0.3,
                      timeout: float = 15.0, system_instruction: Optional[str] = None) -> Optional[str]:
        payload: dict = {
            "contents": [{"role": "user", "parts": [{"text": prompt}]}],
            "generationConfig": {"temperature": temperature},
        }
        if system_instruction:
            payload["systemInstruction"] = {"parts": [{"text": system_instruction}]}
        data = self._post(model, "generateContent", payload, timeout)
        candidates = data.get("candidates") or []
        if not candidates:
            return None  # blocked by safety filters or empty
        parts = (candidates[0].get("content") or {}).get("parts") or []
        text = "".join(p.get("text", "") for p in parts).strip()
        return text or None

    def embed(self, text: str, model: str, task_type: str = "RETRIEVAL_DOCUMENT", timeout: float = 20.0) -> List[float]:
        payload = {"model": _model_path(model), "content": {"parts": [{"text": text}]}, "taskType": task_type}
        data = self._post(model, "embedContent", payload, timeout)
        return list((data.get("embedding") or {}).get("values") or [])
