# 🐳 Libris AI Engine: Docker Infrastructure
# Multi-stage build for a slim, production-ready image.

# ── 1. Build Stage ──────────────────────────────────────────────────────────
FROM python:3.10-slim-buster AS builder

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /app

# System dependencies for ML libraries (numpy/pandas)
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Dependency installation
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir --prefix=/install -r requirements.txt

# ── 2. Runtime Stage ────────────────────────────────────────────────────────
FROM python:3.10-slim-buster

WORKDIR /app

# Copy only the installed dependencies from the builder
COPY --from=builder /install /usr/local
COPY . .

# Environment Defaults
ENV FLASK_ENV=production
ENV PORT=5000

# Metadata
EXPOSE 5000

# High-performance server: Gunicorn with multiple workers
CMD sh -c "gunicorn --bind 0.0.0.0:${PORT:-5000} --workers 4 --timeout 120 app:app"
