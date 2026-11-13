# Supabase and Database Setup

Libris uses Supabase services with PostgreSQL as its relational database. The authoritative application schema is defined by the numbered SQL migrations in backend/scripts/. Do not create a second, hand-maintained schema by copying SQL examples from older documentation.

## 1. Create a Supabase project

1. Create a project in the Supabase dashboard.
2. Choose a region appropriate for your deployment and users.
3. Store the database password securely.
4. Wait for the project database and API to become available.

## 2. Configure application credentials

Use the environment templates:

- Backend: backend/env.example → backend/.env
- Web: web/.env.example → web/.env.local

The backend uses SUPABASE_URL and SUPABASE_ANON_KEY. The web app uses NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_ANON_KEY.

The Supabase anon/publishable key is intended for client configuration and must be paired with correct authentication and Row Level Security policies. The SUPABASE_SERVICE_ROLE_KEY bypasses RLS and must remain server-side for tightly controlled administrative scripts only. Never put it in a web or mobile client.

## 3. Apply the application migrations

The numbered migrations are located at:

backend/scripts/00_init_books.sql through backend/scripts/13_learning_outcomes.sql.

Apply them in ascending numeric order to a fresh database, using a trusted administrative connection and a reviewed migration procedure. Before applying to an existing database:

1. Identify the exact target project and current schema state.
2. Take and verify a recoverable backup.
3. Rehearse the migration sequence against a disposable PostgreSQL 16 database.
4. Validate the resulting tables, indexes, functions, grants and RLS policies.
5. Apply to staging and run the application integration checks.
6. Schedule production changes only after staging verification and an approved rollback plan.

The CI workflow uses backend/ci_stubs.sql to prepare its disposable PostgreSQL service. That file is a test fixture and must not be treated as an application migration.

## 4. Hardening scripts are a separate operator workflow

The directory backend/scripts/hardening/ contains additional hardening, reconciliation, rollback and verification scripts. Some filenames include DRAFT; others require elevated privileges or explicit operator gates.

- Do not execute the entire directory recursively.
- Read the relevant script, preflight checks and rollback procedure before use.
- Follow [V1_DEPLOYMENT_EXECUTION_CHECKLIST.md](V1_DEPLOYMENT_EXECUTION_CHECKLIST.md).
- Use staging first and confirm the expected Supabase roles and privileges.
- Do not assume that a successful local CI rehearsal proves the remote production schema is ready.

The preflight SQL at backend/scripts/preflight_database_hardening.sql is a diagnostic/preflight artifact, not a substitute for a migration plan or backup.

## 5. Verify the integration

After configuring the project and applying the approved migrations:

- Confirm the backend can reach the configured Supabase project.
- Verify sign-up/sign-in and token validation in the target environment.
- Verify user-scoped reads and writes with two separate test accounts.
- Confirm the expected RLS policies are enabled and enforce ownership.
- Run backend and client tests against non-production test resources.

For local development commands, see [setup.md](setup.md). For the overall system design, see [ARCHITECTURE.md](ARCHITECTURE.md).
