"""
Application configuration loaded from environment variables.
Never commit secrets — use .env locally and platform env vars in production.
"""

import os
from dotenv import load_dotenv

load_dotenv()


class Config:
    # ── General ──────────────────────────────────────────────────────────────
    DEBUG: bool = os.getenv("DEBUG", "False").lower() == "true"
    TESTING: bool = os.getenv("TESTING", "False").lower() == "true"
    SECRET_KEY: str = os.getenv("SECRET_KEY", "dev-secret-change-in-production")

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
