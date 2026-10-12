"""
Application configuration loaded from environment variables.
Never commit secrets — use .env locally and platform env vars in production.
"""

import os
from pathlib import Path

from dotenv import load_dotenv

# Always load .env from the backend directory, regardless of CWD
_ENV_FILE = Path(__file__).parent / ".env"
load_dotenv(dotenv_path=_ENV_FILE, override=True)


class Config:
    # ── General ──────────────────────────────────────────────────────────────
    DEBUG: bool = os.getenv("DEBUG", "False").lower() == "true"
    TESTING: bool = os.getenv("TESTING", "False").lower() == "true"
    # ── Security ─────────────────────────────────────────────────────────────
    # In production these must be set via environment variables.
    SECRET_KEY: str = os.getenv(
        "SECRET_KEY",
        "dev-insecure-secret-key"
        if (os.getenv("DEBUG", "False").lower() == "true" or os.getenv("TESTING", "False").lower() == "true")
        else "",
    )
    LIBRIS_API_KEY: str = os.getenv("LIBRIS_API_KEY", "")
    LLM_PROVIDER: str = os.getenv("LLM_PROVIDER", "gemini").lower() # gemini or openai
    LLM_API_KEY: str = os.getenv("LLM_API_KEY", "")
    GEMINI_API_KEY: str = os.getenv("GEMINI_API_KEY", os.getenv("LLM_API_KEY", ""))

    # ── Reverse Proxy ─────────────────────────────────────────────────────────
    # Count of trusted reverse proxy headers (e.g. 1 for Render / Railway / Nginx).
    # Default: 1 in production, 0 in dev/testing unless explicitly overridden.
    NUM_PROXIES: int = int(
        os.getenv(
            "NUM_PROXIES",
            "0"
            if (os.getenv("DEBUG", "False").lower() == "true" or os.getenv("TESTING", "False").lower() == "true")
            else "1",
        )
    )

    # ── Paths ─────────────────────────────────────────────────────────────────
    BASE_DIR: str = os.path.dirname(os.path.abspath(__file__))
    DATA_PATH: str = os.path.join(BASE_DIR, "data", "books.csv")
    MODEL_DIR: str = os.path.join(BASE_DIR, "saved_model")
    MODEL_PATH: str = os.path.join(MODEL_DIR, "tfidf.pkl")

    # ── Google Books API ──────────────────────────────────────────────────────
    GOOGLE_BOOKS_API_KEY: str = os.getenv("GOOGLE_BOOKS_API_KEY", "")
    GOOGLE_BOOKS_API_URL: str = "https://www.googleapis.com/books/v1/volumes"

    # ── Supabase (reference only — main Supabase usage is in Flutter) ─────────
    SUPABASE_URL: str = os.getenv("SUPABASE_URL", "")
    SUPABASE_ANON_KEY: str = os.getenv("SUPABASE_ANON_KEY", "")

    # ── ML Settings ───────────────────────────────────────────────────────────
    TOP_N_RECOMMENDATIONS: int = int(os.getenv("TOP_N_RECOMMENDATIONS", "10"))

    # ── CORS ──────────────────────────────────────────────────────────────────
    ALLOWED_ORIGINS: list = os.getenv("ALLOWED_ORIGINS", "*").split(",")
