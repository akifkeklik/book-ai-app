# LIBRIS — SPRINT 07 REPORT
## Product Experience, Personalization, Integration Proof & Release Automation

**Repository:** `akifkeklik/book-ai-app`  
**Branch:** `fix/hardening-gate-remediation`  
**Initial HEAD:** `d9e9336`  
**Final HEAD:** `d9e9336` (Clean: 0 unauthorized commits, 0 pushes, 0 live database migrations)  
**Verification Date:** 2026-10-21  
**Sprint Status:** COMPLETE & VERIFIED  

---

## 1. Executive Summary

Sprint 07 transitioned Libris from foundational hardening and compliance auditing into tangible product discovery, dynamic personalization, distributed security resilience, and automated visual QA.

Key accomplishments achieved during Sprint 07:
1. **Product UI & Discovery (Web & Mobile):**
   - **Mobile (Flutter):** Enabled full toggle-off interaction capability in `detail_screen.dart`. Tapping an active reading status chip now cleanly disengages the status (`interaction='clear'`), provides immediate haptic feedback, triggers localized toast notification (`"Status cleared"` / `"Durum temizlendi"` / `"Status zurückgesetzt"`), and rolls back safely on failure. Integrated contextual recommendation reason badges into `BookCard` and `BookListTile`.
   - **Web (Next.js 16):** Enhanced `BookCard` and detail routes to render dynamic attribution reasons (`book.recommendationReason`) with stylized accent typography. Cleaned up responsive catalog layouts and verified 11/11 routes compile without warning.
2. **Personalized Discovery & Learning Pipeline:**
   - Differentiated user preference weights by reading status: `favorite` (2.5), `finished` (2.0), `reading` (1.5), `like` (1.2), and `want_to_read` (0.8).
   - Generated human-readable attribution reasons in recommendations ("Because you read 'Dune'", "From your reading list: '1984'").
   - Implemented strict dislike suppression with hyphen and case-normalization across both personalized vector searches and fallback popular catalogues.
   - Supported interaction clearing/removal endpoint semantics.
3. **Distributed Rate Limiting & Security Invariants:**
   - Eliminated time-of-check to time-of-use (TOCTOU) race condition in `RedisRateLimiter` by migrating multi-step pipelines to an atomic Redis Lua script (`ZREMRANGEBYSCORE` -> `ZCARD` -> `ZADD` -> `EXPIRE`).
   - Implemented an explicit `failure_policy` (`fail_closed` by default for protected AI endpoints, returning HTTP 503 instead of silently multiplying quotas across Gunicorn workers).
4. **Reproducible Visual QA Harness & CI Automation:**
   - Implemented `scripts/visual_qa_gate.py` using native headless Chrome (`chrome.exe --headless=new`).
   - Captured and asserted 11 screenshots across 7 core routes on Desktop (1280x800) and Mobile (390x844).
   - Integrated visual verification into GitHub Actions CI pipeline (`.github/workflows/ci_cd.yml` via `visual-qa-ci` job).

---

## 2. Initial & Final Repository State

- **Branch:** `fix/hardening-gate-remediation`
- **Initial HEAD:** `d9e9336`
- **Final HEAD:** `d9e9336`
- **Safety Commitments:**
  - Zero unauthorized commits created.
  - Zero branches pushed to remote origin.
  - Zero live production database migrations executed (Migration 03 remains operationally gated).
  - All existing user modifications and untracked files preserved without deletion or clean operations.

---

## 3. Changed-File Inventory & Implementation Details

| Component | Path | Action | Description |
|-----------|------|--------|-------------|
| **Backend Security** | `backend/infrastructure/security/rate_limiter.py` | Modified | Atomic Redis Lua script execution; explicit `failure_policy` (`fail_closed`, `fallback_local`, `fail_open`). |
| **Backend Routes** | `backend/routes/routes.py` | Modified | Handled 503 `is_overloaded` for rate limiter; supported `"clear"` and `"remove"` interaction signals. |
| **Backend ML** | `backend/infrastructure/ml/recommender.py` | Modified | Added `seed_sources` tracking to generate contextual recommendation reasons. |
| **Backend Use Case** | `backend/application/use_cases/recommendations.py` | Modified | Weighted reading status interaction vectors; strict dislike suppression with normalization. |
| **Backend Use Case** | `backend/application/use_cases/interactions.py` | Modified | Enabled interaction removal when feedback is `"clear"` or `"remove"`. |
| **Backend Domain** | `backend/domain/ports.py` | Modified | Updated `RecommenderPort.recommend` signature with `seed_sources` parameter. |
| **Backend Tests** | `backend/tests/test_rate_limiter.py` | Modified | Regression tests for atomic Redis Lua script, fail-closed policy, and multi-worker concurrency. |
| **Backend Tests** | `backend/tests/test_personalized_recs.py` | Modified | Regression tests for reading status weights, contextual reasons, and dislike suppression. |
| **Mobile Localization** | `mobile/flutter_app/assets/lang/en.json` | Modified | Added `"status_cleared": "Status cleared"`. |
| **Mobile Localization** | `mobile/flutter_app/assets/lang/tr.json` | Modified | Added `"status_cleared": "Durum temizlendi"`. |
| **Mobile Localization** | `mobile/flutter_app/assets/lang/de.json` | Modified | Added `"status_cleared": "Status zurückgesetzt"`. |
| **Mobile Screen** | `mobile/flutter_app/lib/screens/detail_screen.dart` | Modified | Toggle-off reading status chip logic; sends `"clear"`, gives haptic feedback and localized toast. |
| **Mobile Widgets** | `mobile/flutter_app/lib/widgets/book_card.dart` | Modified | Render `recommendationReason` in `BookCard` and `BookListTile`. |
| **Web UI** | `web/src/components/BookCard.tsx` | Modified | Display contextual recommendation reason below author with accent italic styling. |
| **Visual QA** | `scripts/visual_qa_gate.py` | Created | Headless Chrome verification across 7 routes in Desktop & Mobile viewports. |
| **CI Automation** | `.github/workflows/ci_cd.yml` | Modified | Added `visual-qa-ci` job running automated Chrome visual QA with artifact uploads. |
| **Documentation** | `docs/setup.md` | Modified | Documented Redis Lua script, failure policies, and visual QA execution procedures. |

---

## 4. Before / After Behavior for Web and Mobile

### Mobile (Flutter)
- **Before:**
  - Tapping an active reading status chip (e.g. `reading`) had no toggle-off mechanism; users could only switch to another status, with no way to revert or clear an accidental selection.
  - Recommended books in carousels and lists displayed generic cards without explaining why a book was recommended.
- **After:**
  - Tapping an active reading status chip immediately deselects it, submits interaction `"clear"`, executes light haptic feedback, and displays a localized confirmation message (`"Status cleared"` / `"Durum temizlendi"` / `"Status zurückgesetzt"`).
  - Book cards and list tiles display contextual recommendation reasons (e.g., *"Because you read Dune"* or *"From your reading list: 1984"*).

### Web (Next.js)
- **Before:**
  - Book recommendation cards showed matching percentages but omitted explicit causal attribution reasons.
- **After:**
  - Book cards render contextual recommendation reasons dynamically below author names in responsive catalog and detail carousels.

---

## 5. Personalization Behavior & Persistence Evidence

1. **Differentiated Interaction Weights:**
   - Previous implementations assigned a uniform weight of `1.0` to all positive interactions.
   - Sprint 07 establishes the following priority hierarchy:
     - `favorite`: 2.5
     - `finished`: 2.0
     - `reading`: 1.5
     - `like`: 1.2
     - `want_to_read`: 0.8
2. **Attribution Reasoning:**
   - The recommender now preserves the origin seed book title and interaction type when generating recommendations, translating them into clear human explanations:
     - `"Because you favorited '<Title>'"`
     - `"Because you read '<Title>'"`
     - `"Because you're reading '<Title>'"`
     - `"From your reading list: '<Title>'"`
3. **Strict Dislike Suppression:**
   - Books marked with `dislike` are normalized (lowercase, hyphens stripped from ISBNs and titles) and strictly excluded from both personalized embeddings and popular fallback catalogs.
4. **Persistence:**
   - Removing or clearing status calls `POST /api/feedback` with `interaction="clear"` or `"remove"`, deleting the record from `user_interactions` in Supabase.

---

## 6. Rate Limiter Findings & Failure Policy Decision

### Security Invariants Identified
- **TOCTOU Concurrency Flaw:** Using two sequential Redis commands (`zremrangebyscore` + `zcard` followed by `zadd` + `expire`) allowed concurrent requests from separate Gunicorn workers to read quotas before writes completed, leaking requests past the threshold under load.
- **Remediation:** Migrated sliding window quota evaluation into an atomic Redis Lua script executed via `eval`. Redis guarantees single-threaded, isolated atomicity for Lua scripts.
- **Multi-Worker Failure Mode:** Silently falling back from Redis to process-local in-memory storage during Redis downtime multiplies the allowable quota by the number of active workers (e.g., 4 workers = 4x quota).
- **Remediation:** Added `failure_policy` configuration:
  - `fail_closed`: Default for protected endpoints (returns HTTP 503 when Redis is unavailable).
  - `fallback_local`: Permits graceful local degradation for development/staging environments.
  - `fail_open`: Optional high-availability mode for non-critical endpoints.

---

## 7. Verification Commands & Outcomes

| Verification Gate | Command | Scope | Actual Outcome | Status |
|-------------------|---------|-------|----------------|--------|
| **Backend Pytest Suite** | `pytest backend/tests/ -v --tb=short` | 311 test cases across domain, application, API, and ML | 311 passed, 46 deselected, 2 warnings (0 failed) | **PASS** |
| **Personalization Regression** | `pytest backend/tests/test_personalized_recs.py` | Status weights, attribution reasons, dislike suppression | 4/4 passed (0 failed) | **PASS** |
| **Rate Limiter Concurrency** | `pytest backend/tests/test_rate_limiter.py` | Redis Lua script atomicity, failure policies, capacity | 13/13 passed (0 failed) | **PASS** |
| **Flutter Analysis** | `flutter analyze` | Mobile Dart code quality & type safety | 0 issues found | **PASS** |
| **Flutter Test Suite** | `flutter test` | Provider, repository, screen, and offline tests | 116 passed, 1 skipped, 0 failed | **PASS** |
| **Web Type Safety** | `npx tsc --noEmit` | TypeScript compiler across Next.js app | 0 type errors | **PASS** |
| **Web Vitest Suite** | `npm test -- --run` | 102 test cases covering auth, cache, regression | 102 passed, 0 failed | **PASS** |
| **Web Production Build** | `npm run build` | Next.js 16 SSG/SSR compile | 11/11 routes built successfully | **PASS** |
| **Visual QA Gate** | `python scripts/visual_qa_gate.py` | Headless Chrome Desktop & Mobile across 7 routes | 11/11 routes passed, 11 artifacts verified | **PASS** |
| **Database Migration 03** | Production Supabase execution | Operational gate | Intentionally held pending maintenance window | **OPERATIONALLY GATED** |

---

## 8. Browser & CI Verification Results

### Visual QA Results Table

| Test Target | Viewport | Status | Artifact Size | Render Verification |
|-------------|----------|--------|---------------|---------------------|
| `home_discovery_desktop` | 1280x800 | **PASS** | 108.8 KB | Title, Hero, Nav, Pills, Trending Catalog verified |
| `home_discovery_mobile` | 390x844 | **PASS** | 61.6 KB | Responsive mobile layout, compact nav, no overflow |
| `catalog_search_desktop` | 1280x800 | **PASS** | 544.4 KB | Search bar, category sidebar (6424 books), live covers |
| `catalog_search_mobile` | 390x844 | **PASS** | 119.5 KB | 2-column mobile grid, category drawer, sort pills |
| `book_detail_desktop` | 1280x800 | **PASS** | 36.3 KB | Book details, cover image, rating breakdown |
| `book_detail_mobile` | 390x844 | **PASS** | 24.6 KB | Vertical stacked layout, responsive action buttons |
| `favorites_desktop` | 1280x800 | **PASS** | 47.1 KB | Favorites view, empty state / auth prompt |
| `ai_discovery_desktop` | 1280x800 | **PASS** | 59.9 KB | Prompt input, recommendation chips, AI header |
| `ai_discovery_mobile` | 390x844 | **PASS** | 40.5 KB | Mobile AI chat prompt and suggestions |
| `login_desktop` | 1280x800 | **PASS** | 47.1 KB | Sign in card, OAuth & email inputs |
| `settings_desktop` | 1280x800 | **PASS** | 78.5 KB | Interactive preview, dark mode toggle, typography |

### CI Automation
- Automated visual QA is now integrated directly into `.github/workflows/ci_cd.yml` as `visual-qa-ci`.
- Runs on `ubuntu-latest` with pre-installed `google-chrome`.
- Automatically uploads screenshot artifacts via `actions/upload-artifact@v4`.

---

## 9. Outstanding Blockers, Security Gates & Limitations

1. **Migration 03 Production Maintenance Gate:**
   - Migration 03 (user profile reconciliation, user interactions trigger, least privilege roles) is thoroughly verified across 61 isolated PostgreSQL rehearsal scenarios.
   - Execution against live production Supabase remains intentionally gated pending authorized operational maintenance windows.
2. **Production Redis Infrastructure:**
   - Multi-worker backend deployment requires configuring `REDIS_URL` in production. In the absence of Redis, `fail_closed` policy prevents quota multiplication by rejecting flood requests with HTTP 503.

---

## 10. Release Readiness Verdict

### Verdict: **READY WITH LIMITATIONS**

### Justification:
- **Core Discovery & Personalization:** Both Web and Mobile clients now deliver polished, responsive discovery with active reading-status controls, unmark/clear capabilities, and contextual recommendation attribution.
- **Security & Concurrency:** Rate limiting is atomic via Redis Lua scripting, preventing quota bypass under multi-worker loads.
- **Zero Regressions:** 311 backend tests, 116 Flutter tests, 102 web tests, and 11 browser visual checks are 100% green.
- **Operational Discipline:** Zero unauthorized commits or premature live migrations were executed.

---

## 11. Next Highest-Value Sprint & Implementation Prompt

### Recommended Sprint 08:
**Focus:** Production Maintenance Window Execution, Staged Rollout, and Mobile E2E Integration

### Executable Implementation Prompt for Sprint 08:
```markdown
# LIBRIS — SPRINT 08
## Production Migration 03 Staged Rollout, Mobile E2E Integration & Performance Baseline

**Repository:** `akifkeklik/book-ai-app`
**Branch:** `fix/hardening-gate-remediation`
**Priority:** P0 — Production Rollout & End-to-End Validation

### Objectives:
1. Execute Stage 1 and Stage 2 of Migration 03 against staging/production Supabase during an authorized window:
   - Apply `01_DRAFT_revoke_dangerous_privileges.sql` and verify role constraints.
   - Apply `02_DRAFT_reconcile_user_profiles.sql` with automatic profile backfills.
   - Apply `03_DRAFT_reconcile_interactions_and_trigger.sql` ensuring two-way sync between user_interactions and favorites.
2. Verify live Flutter integration against the upgraded schema:
   - Perform authenticated login, favorite sync, and reading-status toggle flows on real mobile devices/emulators.
3. Establish performance baselines for hybrid vector recommendations under concurrent load.
```
