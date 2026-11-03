# Setup Guide — Book AI App

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| Python | 3.11+ | https://python.org |
| Flutter | 3.16+ | https://flutter.dev |
| Git | any | https://git-scm.com |

---

## 1. Clone / Download

```bash
git clone https://github.com/your-username/book-ai-app.git
cd book-ai-app
```

---

## 2. Backend Setup (Flask)

### 2.1 Create virtual environment

```bash
cd backend
python -m venv venv

# Windows
venv\Scripts\activate

# macOS / Linux
source venv/bin/activate
```

### 2.2 Install dependencies

```bash
pip install -r requirements.txt
```

### 2.3 Configure environment variables

```bash
cp env.example .env
```

Open `.env` and fill in:

```env
DEBUG=True
SECRET_KEY=any-random-string-here

# Leave empty to use OpenLibrary covers (no key needed)
GOOGLE_BOOKS_API_KEY=

# Your Supabase project credentials (see supabase_setup.md)
SUPABASE_URL=https://xxxx.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOi...
```

### 2.4 Start the server

```bash
python app.py
```

On first run the server will:
1. Load `data/books.csv`
2. Train the TF-IDF model (~2 seconds)
3. Save it to `saved_model/tfidf.pkl`
4. On subsequent starts, load from pickle (instant)

### 2.5 Verify it works

```
GET http://localhost:5000/api/health
→ {"status":"healthy","service":"book-ai-api"}

GET http://localhost:5000/api/books/popular?limit=5
→ {"books":[...], "total":5}

GET http://localhost:5000/api/recommend?book=Dune
→ {"book":"Dune","recommendations":[...],"total":10}

GET http://localhost:5000/api/search?q=tolkien
→ {"books":[...],"total":2,"query":"tolkien"}
```

### 2.6 Distributed Multi-Worker Scaling (Redis)

By default, the backend uses a thread-safe in-memory sliding window rate limiter. In production with multiple Gunicorn/Uvicorn workers or multi-pod clusters, configure Redis:

```env
REDIS_URL=redis://localhost:6379/0
RATE_LIMIT_FAILURE_POLICY=fail_closed
```

- **Atomic Lua Scripting:** When `REDIS_URL` is set, Redis executes an atomic Lua script (`ZREMRANGEBYSCORE` -> `ZCARD` -> `ZADD` -> `EXPIRE`) to ensure zero race conditions or quota leaks under concurrent multi-worker requests.
- **Explicit Failure Policy:** If the Redis cluster becomes unavailable:
  - `fail_closed` (default for protected AI endpoints): Returns HTTP 503 (`Service Unavailable`), preventing multi-worker quota multiplication or abuse during Redis outages.
  - `fallback_local`: Temporarily falls back to local in-memory sliding window rate limiting.
  - `fail_open`: Allows requests through if rate limiting infrastructure is degraded.

---

## 3. Flutter App Setup

### 3.1 Install dependencies

```bash
cd ../mobile/flutter_app
flutter pub get
```

### 3.2 Configure endpoints
This app reads config from `--dart-define` (recommended) so secrets are not hard-coded.

Examples:

```bash
# Android emulator
flutter run \
  --dart-define=BACKEND_URL=http://10.0.2.2:5000 \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY \
  --dart-define=LIBRIS_API_KEY=YOUR_BACKEND_API_KEY
```

> **Android physical device**: use your machine's local IP, e.g. `http://192.168.1.x:5000`

### 3.3 Run on device / emulator

```bash
# List available devices
flutter devices

# Run
flutter run

# Run on specific device
flutter run -d <device-id>

# Build release APK
flutter build apk --release
```

---

## 4. Web App Setup (Next.js 16 App Router)

### 4.1 Install dependencies

```bash
cd web
npm install
```

### 4.2 Configure environment variables

Copy `web/.env.example` to `web/.env.local`:

```bash
cp .env.example .env.local
```

Fill in:
- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY`
- `BACKEND_URL=http://localhost:5000`
- `LIBRIS_API_KEY=your-backend-api-key`

### 4.3 Run the Web App

```bash
# Development mode
npm run dev

# Production build and start
npm run build
npm start
```
Open `http://localhost:3000` in your browser.

---

## 5. Running the Full Stack Locally

Terminal 1 (Backend):
```bash
python -m backend.app
```

Terminal 2 (Web):
```bash
cd web && npm run dev
```

Terminal 3 (Mobile - Optional):
```bash
cd mobile/flutter_app && flutter run
```

---

## 6. Visual QA Gate & Screenshot Verification

Libris includes an automated headless Chrome verification harness covering 7 core routes across Desktop (`1280x800`) and Mobile (`390x844`) viewports:

```bash
python scripts/visual_qa_gate.py --output-dir artifacts/visual_qa
```

The script:
1. Probes or starts the backend on port 5000 and web app on port 3000.
2. Captures full-fidelity screenshots for desktop and mobile viewports.
3. Dumps and verifies rendered DOM for core content, navigation, and absence of catastrophic client exceptions.
4. Generates an execution summary table and returns exit code `0` on success.

---

## 7. Common Issues

| Problem | Solution |
|---------|----------|
| `ModuleNotFoundError` | Activate venv: `venv\Scripts\activate` |
| `Connection refused` on emulator | Use `10.0.2.2` not `localhost` |
| Model training slow | Normal on first run — model is cached after |
| Flutter pub get fails | Run `flutter doctor` and fix SDK issues |
| `CORS error` in browser testing | Set `ALLOWED_ORIGINS=*` in `.env` |
| `429 Rate Limit` on AI | Configured at 10 requests / 60 seconds per IP/token |
| `503 Service Unavailable` on AI | Rate limiter `fail_closed` policy active while Redis is unreachable |

