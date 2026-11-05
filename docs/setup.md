# Local Development Setup

This guide follows the current repository layout and CI commands. Configure only the services you intend to run; AI and authenticated/persistent features require valid provider and Supabase configuration.

## Prerequisites

| Tool | Version used by CI / project | Purpose |
|---|---|---|
| Python | 3.12 | Flask API |
| Node.js | 22 | Next.js web app |
| Flutter | 3.24.3 in CI | Mobile app |
| PostgreSQL | 16 for integration CI | Local database and migration testing |
| Git | Current stable | Source control |
| Docker Compose | Compose v2 | Optional full-stack environment |

## 1. Get the source

~~~bash
git clone https://github.com/akifkeklik/book-ai-app.git
cd book-ai-app
~~~

## 2. Configure the backend

Create and activate a virtual environment from the repository root:

~~~bash
python -m venv .venv
~~~

Windows PowerShell:

~~~powershell
.venv\Scripts\Activate.ps1
~~~

macOS / Linux:

~~~bash
source .venv/bin/activate
~~~

Install dependencies and create the backend environment file:

~~~bash
pip install -r backend/requirements-test.txt
~~~

Copy backend/env.example to backend/.env. Set the values required by the features you use:

- SECRET_KEY: long random secret; required for production.
- LIBRIS_API_KEY: server/API authentication key.
- SUPABASE_URL and SUPABASE_ANON_KEY: Supabase project configuration.
- LLM_PROVIDER and LLM_API_KEY: AI provider configuration.
- GEMINI_API_KEY: required for Gemini embeddings where configured.
- GOOGLE_BOOKS_API_KEY: optional metadata enrichment.
- ALLOWED_ORIGINS: comma-separated trusted origins. Use explicit origins in production.

Start the API from the repository root:

~~~bash
python -m backend.app
~~~

Default local URL: http://localhost:5000. Health check: http://localhost:5000/api/health.

## 3. Configure and run the web app

~~~bash
cd web
npm ci
~~~

Copy .env.example to .env.local inside web/. Configure:

- NEXT_PUBLIC_SUPABASE_URL
- NEXT_PUBLIC_SUPABASE_ANON_KEY
- BACKEND_URL (normally http://localhost:5000 for local development)
- LIBRIS_API_KEY (must match the backend's server/API key)

Run the development server:

~~~bash
npm run dev
~~~

Default local URL: http://localhost:3000.

## 4. Configure and run the mobile app

~~~bash
cd mobile/flutter_app
flutter pub get
flutter run
~~~

The app accepts runtime configuration through the --dart-define mechanism. Use the define names referenced by the mobile configuration code. For local networking:

- Android emulator: use http://10.0.2.2:5000 to reach the host machine.
- iOS simulator: http://localhost:5000 is commonly available.
- Physical device: use the development machine's LAN IP and ensure both devices are on a reachable network.

Do not treat values compiled into a mobile application as secret. Never embed a Supabase service-role key in a client application.

## 5. Optional Docker Compose environment

The repository includes docker-compose.yaml for backend, web and a local PostgreSQL service. Compose reads a root .env file; set at least the required SECRET_KEY and the configuration needed by the services before starting:

~~~bash
docker compose config
docker compose up --build
~~~

The PostgreSQL service uses a named local volume. It is a development/test database, not a managed production database. Review the compose file before exposing ports or using persistent data.

## 6. Quality checks

Run from the repository root:

**Backend**

~~~bash
ruff check backend/
PYTHONPATH=. python -m pytest backend/tests/ -v --tb=short
~~~

**Web**

~~~bash
cd web
npm ci
npm run lint
npm test
npm run build
~~~

**Mobile**

~~~bash
cd mobile/flutter_app
flutter pub get
flutter analyze --no-fatal-infos
flutter test
~~~

For the CI-equivalent integration tests, use a disposable PostgreSQL 16 service and set LIBRIS_TEST_DATABASE_URL as shown in .github/workflows/ci_cd.yml. Never point these tests at production.

## 7. Database migrations

Application migrations live in backend/scripts/ and must be reviewed and applied in numeric order:

~~~text
00_init_books.sql
01_schema.sql
02_phase3_migration.sql
03_phase3_embeddings.sql
04_phase3_hybrid.sql
05_phase3_performance.sql
06_phase2_rag.sql
07_phase3_collections.sql
08_user_profiles_and_activities.sql
09_learning_notes.sql
10_learning_notes_idempotency_and_review.sql
11_learning_paths.sql
12_knowledge_graph.sql
13_learning_outcomes.sql
~~~

Do not run backend/ci_stubs.sql against a production database. Do not bulk-execute the contents of backend/scripts/hardening/; some files are explicitly drafts or operator-gated. Follow [supabase_setup.md](supabase_setup.md) and [V1 deployment checklist](V1_DEPLOYMENT_EXECUTION_CHECKLIST.md), validate in staging, and verify a backup before any remote schema change.

## Troubleshooting

| Symptom | Check |
|---|---|
| Backend import errors | Run python -m backend.app from the repository root rather than executing a package module from the wrong working directory. |
| Web cannot reach backend | Confirm the backend is running and BACKEND_URL points to the correct host from the web server's network namespace. |
| Android emulator cannot reach localhost | Use 10.0.2.2 for the host machine. |
| Supabase requests fail | Verify project URL, public anon key, auth configuration, network access and deployed schema. |
| AI features fail | Verify the selected provider and its server-side API key. |
| Integration tests skip | Set LIBRIS_TEST_DATABASE_URL to an isolated PostgreSQL test service. |
