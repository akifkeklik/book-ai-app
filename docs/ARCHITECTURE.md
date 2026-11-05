# Libris Architecture

This document describes the repository structure as it exists in the current codebase. It is an implementation overview, not a claim that every component has been independently security-audited or production-certified.

## System overview

Libris has three application surfaces:

- **Web:** Next.js App Router application in web/.
- **Mobile:** Flutter application in mobile/flutter_app/.
- **Backend:** Flask API in backend/.

The clients use the backend for application capabilities and use Supabase for the configured authentication and data services. The web application also contains server actions and route handlers that mediate server-side operations.

~~~mermaid
flowchart TB
    WEB["Next.js Web"]
    MOBILE["Flutter Mobile"]
    WEB_SERVER["Server Actions / Route Handlers"]
    API["Flask API"]
    DOMAIN["Domain Models & Ports"]
    APP["Application Use Cases"]
    INFRA["Infrastructure Adapters"]
    SUPA[("Supabase / PostgreSQL")]
    LLM["LLM & Embedding Providers"]
    OUTBOX["Mobile Local Storage / Sync"]

    WEB --> WEB_SERVER
    WEB_SERVER --> API
    MOBILE --> API
    MOBILE <--> OUTBOX
    API --> APP
    APP --> DOMAIN
    APP --> INFRA
    INFRA --> SUPA
    APP --> LLM
~~~

## Backend boundaries

| Path | Responsibility |
|---|---|
| backend/app.py | Flask application factory and blueprint registration |
| backend/routes/ | HTTP endpoints, request validation and authentication boundary |
| backend/application/use_cases/ | Application workflows such as discovery, recommendations, notes, learning paths and knowledge graph operations |
| backend/domain/ | Domain models, protocols/ports and taxonomy |
| backend/infrastructure/ | Persistence adapters, AI/ML integrations, logging and security |
| backend/container.py | Dependency wiring |
| backend/tests/ | Unit, functional and integration tests |
| backend/scripts/ | SQL migrations and operational/development scripts |

The intended dependency direction is from routes to use cases, and from use cases to domain contracts. Infrastructure adapters implement the contracts used by application workflows.

## Web application

The web application uses Next.js App Router:

- web/src/app/ contains pages, route handlers and server actions.
- web/src/components/ contains reusable UI components.
- web/src/lib/ contains API clients, Supabase helpers, normalizers and localization utilities.
- web/src/types/ contains shared TypeScript contracts.
- web/src/__tests__/ contains Node-based tests.

Server-side credentials must remain in server execution contexts. Only intentionally public configuration should use the NEXT_PUBLIC_ prefix.

## Mobile application

The Flutter source is under mobile/flutter_app/lib/. It separates domain entities, data/repository code, application workflows, providers, screens and services. Local storage and the synchronization outbox support selected offline mutations; this does not imply that every feature is fully available offline.

The CI workflow uses Flutter 3.24.3. See the mobile project and its tests for the exact behavior of individual providers and sync operations.

## Persistence and AI

PostgreSQL is the relational data store, with Supabase providing the configured platform services and pgvector used for vector-related functionality. SQL migrations are versioned in backend/scripts/ and numbered from 00 to 13.

AI-assisted discovery and recommendation workflows are implemented in backend use cases and infrastructure adapters. Provider credentials belong on the server and should never be embedded in client bundles.

## Data and security boundaries

- Protected API routes validate authentication and derive the effective user identity from the verified token.
- User-scoped database access depends on the deployed schema, grants and Row Level Security policies; verify those policies in the target Supabase project.
- Tests should use in-memory adapters, mocks or disposable PostgreSQL databases.
- Never use production credentials or a production database URL in automated tests.
- Hardening scripts are separate from the numbered application migrations. Review their preflight requirements and deployment checklist before running them.

## Change and verification workflow

1. Branch from the latest main.
2. Make a focused change within the appropriate application boundary.
3. Run the backend, web or mobile checks affected by the change.
4. Review the GitHub Actions run for the pull request.
5. Apply database changes only through a reviewed, ordered migration process with staging validation and a verified backup.
