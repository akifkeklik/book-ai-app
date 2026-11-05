# Libris

<div align="center">

**AI-assisted reading, discovery, and personal knowledge management**

[![CI](https://github.com/akifkeklik/book-ai-app/actions/workflows/ci_cd.yml/badge.svg)](https://github.com/akifkeklik/book-ai-app/actions/workflows/ci_cd.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Python](https://img.shields.io/badge/Python-3.12-3776AB?logo=python&logoColor=white)](https://www.python.org/)
[![Flask](https://img.shields.io/badge/Flask-3.0-000000?logo=flask)](https://flask.palletsprojects.com/)
[![Next.js](https://img.shields.io/badge/Next.js-16.4-black?logo=next.js)](https://nextjs.org/)
[![React](https://img.shields.io/badge/React-19-61DAFB?logo=react&logoColor=black)](https://react.dev/)
[![Flutter](https://img.shields.io/badge/Flutter-3.24.3-02569B?logo=flutter)](https://flutter.dev/)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-4169E1?logo=postgresql)](https://www.postgresql.org/)

</div>

Libris is a multi-platform reading application that brings together book discovery, personalized recommendations, reading activity, and personal learning tools. It combines a Flutter mobile client, a Next.js web application, and a Python/Flask API backed by PostgreSQL and Supabase.

> **Project status:** Active development. Feature descriptions below reflect the repository implementation; deployment readiness and test status must be checked against the latest CI run and the target environment.

## What it does

- **Discover books:** Search and explore a catalog, with AI-assisted discovery and streamed chat responses.
- **Get recommendations:** Combine catalog signals, reading preferences, and feedback to personalize suggestions.
- **Manage a personal library:** Track reading shelves and favorites as separate states.
- **Keep learning:** Save notes and takeaways, organize learning paths, and review material with spaced repetition.
- **Connect ideas:** Explore a personal knowledge graph linking books, concepts, notes, and learning paths.
- **Continue offline:** The mobile app queues supported local changes and synchronizes them when connectivity returns.
- **Use multiple languages:** English, Turkish, and German localization resources are included.

## Architecture

~~~mermaid
flowchart TB
    subgraph Clients["Client applications"]
        WEB["Next.js 16 · React 19"]
        MOBILE["Flutter · Dart"]
    end

    subgraph Services["Application services"]
        WEB_ACTIONS["Next.js Server Actions / Route Handlers"]
        API["Flask REST API"]
        USECASES["Application Use Cases"]
        DOMAIN["Domain Models & Ports"]
    end

    subgraph Infrastructure["Infrastructure"]
        ADAPTERS["Persistence & External-Service Adapters"]
        AI["LLM / Embedding Providers"]
        DB[("Supabase · PostgreSQL · pgvector")]
        LOCAL["Mobile Local Storage & Sync Outbox"]
    end

    WEB --> WEB_ACTIONS
    WEB_ACTIONS --> API
    MOBILE --> API
    MOBILE <--> LOCAL
    API --> USECASES
    USECASES --> DOMAIN
    DOMAIN --> ADAPTERS
    ADAPTERS --> DB
    USECASES --> AI
~~~

### Main technology choices

| Area | Technologies |
|---|---|
| Web | Next.js 16.4, React 19, TypeScript |
| Mobile | Flutter, Dart, Provider, GoRouter, Hive |
| Backend | Python 3.12, Flask 3 |
| Data | PostgreSQL 16, Supabase, pgvector |
| AI | Retrieval-augmented generation, embeddings, recommendation ranking |
| Quality | Pytest, Ruff, TypeScript/ESLint, Flutter analyzer and tests, GitHub Actions |
| Local orchestration | Docker Compose |

The CI workflow currently pins Flutter 3.24.3 and Node.js 22. Use those versions when reproducing CI locally.

## Repository layout

~~~text
.
├── .github/workflows/       # CI/CD workflow
├── backend/
│   ├── application/         # Use cases
│   ├── domain/              # Domain models and ports
│   ├── infrastructure/      # Persistence, AI, security and integrations
│   ├── routes/              # Flask HTTP endpoints
│   ├── scripts/             # Ordered SQL migrations and maintenance tools
│   └── tests/               # Backend tests
├── docs/                    # Setup, architecture and project documentation
├── mobile/flutter_app/      # Flutter application
├── scripts/                 # Local development and verification scripts
├── web/                     # Next.js application
├── docker-compose.yaml
└── README.md
~~~

## Run locally

### Prerequisites

- Python 3.12
- Node.js 22 and npm
- Flutter 3.24.3 (for mobile development)
- A configured Supabase project for authenticated/persistent features
- Git

### 1. Backend

From the repository root:

~~~bash
python -m venv .venv
~~~

Activate the environment:

~~~powershell
# Windows PowerShell
.venv\Scripts\Activate.ps1
~~~

~~~bash
# macOS / Linux
source .venv/bin/activate
~~~

Install dependencies and configure the backend:

~~~bash
pip install -r backend/requirements-test.txt
# Copy backend/env.example to backend/.env and fill in the values.
python -m backend.app
~~~

The API is expected at http://localhost:5000. The health endpoint is /api/health.

### 2. Web

In a second terminal:

~~~bash
cd web
npm ci
~~~

Copy web/.env.example to web/.env.local and configure the Supabase and backend values. Then run:

~~~bash
npm run dev
~~~

The web app is expected at http://localhost:3000.

### 3. Mobile

~~~bash
cd mobile/flutter_app
flutter pub get
flutter run
~~~

Configure the backend and Supabase values using the app's supported --dart-define settings. For an Android emulator, the host machine is normally reachable at http://10.0.2.2:5000; for a physical device, use the host machine's LAN address.

For the full variable list and platform-specific details, see [docs/setup.md](docs/setup.md).

## Database

The numbered schema migrations are stored in backend/scripts/:

- 00_init_books.sql through 13_learning_outcomes.sql are the ordered application migrations.
- backend/ci_stubs.sql is a CI/test fixture, not a production migration.
- backend/scripts/hardening/ contains separate hardening and rehearsal scripts. Files marked DRAFT are not automatic production instructions.

Read [docs/supabase_setup.md](docs/supabase_setup.md) and the deployment checklist before changing a remote database. Back up the target environment and validate migrations in staging first. Do not apply the hardening scripts to production merely by running the whole directory.

## Quality checks

Run checks from the repository root unless a command says otherwise.

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

GitHub Actions runs database migration validation, backend lint and tests, PostgreSQL integration tests, Docker builds, Flutter analysis/tests, web lint/tests/build, and a targeted visual QA job. A historical report or README badge is not a substitute for checking the latest workflow run.

## Configuration and security

- Keep real credentials in local environment files or deployment secret stores; never commit them.
- SUPABASE_SERVICE_ROLE_KEY is for tightly controlled administrative tasks only. Never expose it to web or mobile clients.
- The web client should only receive public Supabase configuration. Server-to-server credentials belong in server environments.
- Set explicit trusted ALLOWED_ORIGINS values in production; do not use a wildcard.
- Use isolated disposable databases for integration tests. Do not point test commands at a production database.

Environment templates:
- Backend: [backend/env.example](backend/env.example)
- Web: [web/.env.example](web/.env.example)
- Root/Compose: [.env.example](.env.example)

## Documentation

Start with the [documentation index](docs/README.md).

- [Architecture](docs/ARCHITECTURE.md)
- [Local setup](docs/setup.md)
- [Supabase and migrations](docs/supabase_setup.md)
- [Design system](docs/DESIGN_SYSTEM.md)
- [Google Books API setup](docs/google_api_setup.md)
- [V1 deployment checklist](docs/V1_DEPLOYMENT_EXECUTION_CHECKLIST.md)
- [V1 release readiness](docs/V1_RELEASE_READINESS.md)

Sprint and audit reports are historical snapshots. Their test counts, branch names, file paths, and readiness statements describe the date and commit recorded in each report; they should not be treated as current operational guidance.

## Contributing

1. Create a focused branch from the current main (for example, feat/short-description or fix/short-description).
2. Keep each pull request limited to one logical change.
3. Run the relevant quality checks before opening a pull request.
4. Never commit credentials, local databases, generated build output, or personal machine artifacts.
5. Use clear commit messages that describe the change.

## License

Libris is distributed under the [MIT License](LICENSE).
