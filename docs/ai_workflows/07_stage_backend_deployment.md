# AI Execution Plan - Stage 7: ML Backend Dockerization & Deployment

## Context
The Python Flask backend containing the Machine Learning engine needs to be isolated for deployment on AWS, Google Cloud, or Render. 

## Objectives
1. Create a `Dockerfile` for the `backend/` Python environment.
2. Optimize `requirements.txt` (use Gunicorn instead of standard Flask dev server).
3. Connect the Flutter app to the production URL instead of localhost.

## Instructions for AI Agent
1. **Docker Setup**:
   - Create `backend/Dockerfile`. Build from `python:3.10-slim`.
   - Ensure it exposes port 8080 and runs with Gunicorn for production scale.
2. **Backend Optimization**:
   - Check `backend/requirements.txt`. Ensure `gunicorn` is listed.
   - Separate the heavy ML model loading to occur ONCE at startup, not per request, to prevent memory leaks and massive latency.
3. **App Integration**:
   - In Mobile: open `lib/config.dart`.
   - Setup a toggle: if `kReleaseMode` is true, point the ML API base URL to `https://libris-api.yourdomain.com`, else `http://localhost:5000`.

## Success Criteria
- Running `docker build -t libris-api .` in the backend folder succeeds without missing C++ build tools for ML libraries.
- The Flutter codebase automatically targets the live cloud server when compiled for production.
