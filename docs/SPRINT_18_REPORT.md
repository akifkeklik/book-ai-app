# SPRINT 18 REPORT: AUTH RECOVERY, CATALOG TAXONOMY INTEGRITY & REAL AI PRODUCT COMPLETION

## 1. Executive Summary

Sprint 18 resolved critical product defects and data integrity anomalies across all three tiers of the Libris application (Flutter Mobile Client, Next.js Web Client, and Flask Backend API):

1. **Flutter Sign-Up & Sign-In Full Restoration (P0)**:
   - Diagnosed and fixed the root causes blocking mobile authentication: silent placeholder masquerading, session corruption on email confirmation, unhandled rate-limiting, duplicate in-flight submission race conditions, and missing deep-link URL intent filters on Android and iOS.
   - Enforced client-side guards preventing placeholder credentials (`placeholder.supabase.co`) from masquerading as a live service and throwing opaque network exceptions.
   - Fixed Web client signup flow in Next.js where unconfirmed users were prematurely subjected to `signInWithPassword`, causing `Email not confirmed` fatal toast errors.
   - Added automated unit tests verifying missing configuration, valid login, invalid credentials, rate-limiting, email-confirmation-required states, existing account detection, and double-tap in-flight prevention.

2. **Catalog Taxonomy & Category Normalization Integrity (P1)**:
   - Developed a deterministic audit script (`backend/scripts/audit_catalog_taxonomy.py`) auditing the real 6,446 catalog records.
   - Solved the `1984` category discrepancy: George Orwell's *1984* (`9780452284234`) was mistakenly mapped under `History` due to a raw metadata tag `"london (england)": "History"`. Reassigned `"london (england)"` to `Fiction`.
   - Fixed recommender delimiter splitting on `&` which corrupted compound canonical categories (`Young Adult & Children`, `Mystery & Thriller`, `Social Sciences`, `Self-Development`, `Horror`, `Crafts & Hobbies`).
   - Expanded mobile `CategoryMapper`, `CategoriesScreen`, and localization catalogs (EN, TR, DE) to support all 28 canonical categories with 100% cross-lingual parity.

3. **Grounded AI Discovery Product Feature (P2)**:
   - Audited the full RAG and semantic discovery pipeline.
   - Extended deterministic catalog lookup to author queries ("Who wrote 1984?" / "1984'ün yazarı kim?").
   - Implemented unauthenticated state guards for book-saving and personal-shelf queries, directing signed-out readers to `/login` without fraudulent success messages.
   - Enforced transparent explanations for generic recommendation requests when no user preference history is present.
   - Validated deterministic LLM fallback when the external AI provider is unavailable.

4. **Security, Parity & Quality Gates (P3 & P4)**:
   - Verified that client applications never expose service-role credentials.
   - Confirmed 100% test passes across Flutter (150 passed, 1 skipped, 0 failed), Backend (424 passed, 0 failed), and Web (122 passed, 0 failed; production build verified with 11 static/PPR routes).

---

## 2. Initial Repository State & Verification Baseline

| Attribute | State at Sprint Start | Final State |
| :--- | :--- | :--- |
| **Branch** | `fix/hardening-gate-remediation` | `fix/hardening-gate-remediation` |
| **HEAD Commit** | `d9e9336aab3433f28de72bf3466979be57b56e80` | `d9e9336aab3433f28de72bf3466979be57b56e80` (Uncommitted working tree preserved) |
| **Git Safety Rules** | Strict adherence: NO `git commit`, NO `git push`, NO migrations to live DB | Complied fully |
| **Backend Tests Baseline** | 419 passed in 110.65s | **424 passed, 0 failed in 69.36s** |
| **Web Tests Baseline** | 122 passed in 3.32s | **122 passed, 0 failed in 2.86s** |
| **Flutter Tests Baseline** | 144 passed, 1 skipped in 10s | **150 passed, 1 skipped, 0 failed in 12s** |
| **Flutter Analyzer** | 0 issues found | **0 issues found** |
| **Web Build** | Passed (Next.js 16.4.0 Turbopack) | **Passed (11 routes compiled and optimized)** |

---

## 3. Flutter Auth Root Cause Analysis & Corrections (P0)

### 3.1 Observed Failures & Root Causes

1. **Placeholder Masquerading**:
   - *Evidence*: `mobile/flutter_app/lib/config.dart` defaulted `SUPABASE_URL` to `'https://placeholder.supabase.co'` and `SUPABASE_ANON_KEY` to `'placeholder-anon-key'`. When engineers ran `flutter run` without `--dart-define`, `AuthProvider.login()` attempted DNS/TCP connections to `placeholder.supabase.co`.
   - *Consequence*: The failure threw a low-level `SocketException`, which `_friendlyError` converted to `auth_error_network` ("Ağ bağlantı hatası"). This misled developers and users into thinking network connectivity was down rather than missing credentials.
   - *Correction*: Added `AppConfig.isSupabaseConfigured` and `AuthServiceBase.isConfigured`. If false, `AuthProvider` intercepts the request and sets `auth_error_not_configured`, mapped across all 3 language bundles (EN, TR, DE).

2. **Email Confirmation State Invalidation**:
   - *Evidence*: In `AuthProvider.register()`, `_user = res.user;` was called unconditionally. When Supabase email confirmation was enabled, `res.session` was `null` while `res.user` was returned.
   - *Consequence*: Because `isLoggedIn` was defined as `_user != null`, the app marked the unconfirmed user as authenticated. Subsequent requests to protected endpoints failed with 401/403, and restarting the app wiped the session, causing state disorientation.
   - *Correction*: Refactored `register()` to verify `res.session != null`. If `res.session == null` and `res.user != null`, `_requiresEmailConfirmation` is set to `true`, `_user` is reset to `null`, and `RegisterScreen` renders the confirmation screen.

3. **Existing Account Obfuscation**:
   - *Evidence*: Supabase Auth returns a user object with an empty identities list (`res.user.identities == []`) when `signUp` is invoked for an already registered email.
   - *Consequence*: Previously, this was treated as a brand new registration, showing "Confirmation email sent" even though no email was dispatched.
   - *Correction*: Checked `if (res.user!.identities != null && res.user!.identities!.isEmpty)` to flag `'auth_error_already_registered'`.

4. **In-Flight Concurrent Submissions (Double-Taps)**:
   - *Evidence*: Neither `LoginScreen`, `RegisterScreen`, nor `AuthProvider` had re-entrance mutexes. Rapid double-tapping triggered concurrent calls to Supabase Auth.
   - *Correction*: Added `_isAuthenticating` lock in `AuthProvider` and `_isSubmitting` in `LoginScreen` and `RegisterScreen`. Secondary clicks while an operation is in flight are immediately dropped.

5. **Missing Deep-Link URL Schemes for Confirmation Redirects**:
   - *Evidence*: `AndroidManifest.xml` only registered `MAIN` / `LAUNCHER` intent filters. `Info.plist` had no `CFBundleURLTypes`.
   - *Correction*: Added `libris://login-callback` intent filter in `AndroidManifest.xml` and `libris` URL scheme in `Info.plist`.

6. **Web Client Signup Parity**:
   - *Evidence*: `web/src/app/signup/page.tsx` called `supabase.auth.signUp()` and immediately followed with `supabase.auth.signInWithPassword()`.
   - *Consequence*: In projects where Supabase email confirmation is enabled, `signInWithPassword` immediately threw "Email not confirmed", displaying an error toast right after successful registration.
   - *Correction*: Updated `SignUpForm` to inspect `data.session` vs `data.user`. If `data.session` is null, it displays a clear confirmation sent view rather than attempting premature password authentication.

---

## 4. Catalog Taxonomy Audit & Normalization (P1)

### 4.1 Local Catalog Audit Metrics (`backend/scripts/audit_catalog_taxonomy.py`)

A script was developed to audit the 6,446 records in `backend/data/books.csv`:

```
================================================================================
LIBRIS CATALOG TAXONOMY & DATA INTEGRITY AUDIT
================================================================================
Total Records:                     6,446
Unique Titles:                     6,000
Unique ISBN-13s:                   6,446 (0 collisions)
Valid ISBN-13 Checksums:           6,446 / 6,446 (100.0%)
Missing / Null Titles:             0
Missing / Null Authors:            0
Valid Publication Years (1400-2026): 6,446 / 6,446 (100.0%)
Books with Valid Average Ratings:  6,446 / 6,446 (100.0%, min=0.00, max=5.00)
Books with Ratings Count > 0:      6,446 / 6,446 (100.0%)
```

### 4.2 Category Distribution (Top 10 of 28 Canonical Categories)

| Category Name | Book Count | Share |
| :--- | :--- | :--- |
| **Fiction** | 1,514 | 23.49% |
| **Young Adult & Children** | 678 | 10.52% |
| **Non-Fiction** | 632 | 9.80% |
| **Literature** | 563 | 8.73% |
| **History** | 433 | 6.72% |
| **Classics** | 425 | 6.59% |
| **Mystery & Thriller** | 358 | 5.55% |
| **Science Fiction & Fantasy** | 321 | 4.98% |
| **Biography & Memoir** | 227 | 3.52% |
| **Philosophy** | 163 | 2.53% |
| *Other 18 Categories* | 1,132 | 17.56% |

### 4.3 Root Cause of the `1984` Category Misclassification

- **Record Under Inspection**: ISBN-13 `9780452284234`, Title: *1984*, Author: George Orwell.
- **Source Category Tag**: In Google Books ingestion metadata, this edition was tagged with raw subject: `"London (England)"`.
- **Defect in Taxonomy Mapping**: `backend/domain/taxonomy.py` had mapped `"london (england)": "History"`. Because *1984* is dystopian political fiction, this mapping caused *1984* to appear under History rather than Fiction.
- **Correction**: Reassigned `"london (england)": "Fiction"`.
- **Another Title**: ISBN-13 `9780151010264`, *Animal Farm and 1984*, was already classified under `Fiction`.

### 4.4 Recommender Compound Category Splitting Bug

- **Defect**: In `backend/infrastructure/ml/recommender.py`, `_book_matches_canonical()` split categories by `,`, `|`, `/`, and `&`.
- **Consequence**: Splitting on `&` destroyed compound category names. For example, `Young Adult & Children` was split into `Young Adult` and `Children`. When querying `/api/books?category=Young Adult & Children`, it looked for an exact match on the split parts, failing canonical self-matches.
- **Correction**: Rewrote matching logic to preserve compound names containing `&` (e.g., `Young Adult & Children`, `Mystery & Thriller`, `Sports & Games`, `Crafts & Hobbies`, `Education & Reference`).

---

## 5. Search & Filter Verification

### 5.1 Verification Scenarios

| Scenario / Query | Parameters | Observed API Status & Result | Correctness Proof |
| :--- | :--- | :--- | :--- |
| **1984 Title Search** | `q=1984` | 200 OK — Returns 14 matching titles (including *1984* by George Orwell and *Animal Farm and 1984*) | Verified: Title lexical search accurately retrieves all catalog records matching "1984". |
| **1984 under History** | `q=1984&category=History` | 200 OK — 0 results | Verified: Since `"london (england)"` was reclassified to `Fiction`, *1984* no longer falsely appears in History. |
| **1984 under Fiction** | `q=1984&category=Fiction` | 200 OK — 2 results (*1984* and *Animal Farm and 1984*) | Verified: Canonical Fiction category correctly contains both Orwell editions. |
| **1984 + Young Adult & Children** | `q=1984&category=Young Adult & Children` | 200 OK — 0 results | Verified: Zero results is factually correct because *1984* is NOT in Young Adult & Children (which has 678 other books). The empty state correctly displays active filters and provides reset links. |
| **Exact ISBN-13 Search** | `q=9780452284234` | 200 OK — 1 result (*1984*) | Verified: Fast, exact-match retrieval by ISBN-13. |
| **Category Browsing** | `category=Young Adult & Children` | 200 OK — 678 books returned paginated (20 per page) | Verified: Compound categories with `&` are preserved and populated. |

---

## 6. AI Architecture & Grounded Discovery Evidence (P2)

### 6.1 Verification of All 10 User Journeys

| # | User Journey / Query | Implementation Type | Observed Outcome |
| :--- | :--- | :--- | :--- |
| 1 | **“Do you have 1984?”** | Deterministic Catalog Lookup | Status `success`. Returns George Orwell's *1984* with valid catalog link and ISBN-13. |
| 2 | **“Who wrote this book?” / “1984'ün yazarı kim?”** | Deterministic Author Extraction | Status `success`. Extracts author "George Orwell" directly from verified record. |
| 3 | **“What rating does it have?” / “1984 kaç puan?”** | Deterministic Metadata Tool | Status `success`. Answers with stored catalog rating (4.19 / 5.00) and review counts. |
| 4 | **“Find similar books”** | Vector Embedding + Seed Exclusion | Status `success`. Recommends dystopian/classic fiction, excluding *1984* itself from recommendations. |
| 5 | **“Recommend something for me” (Anonymous)** | Authenticated Boundary Guard | Status `success`. Clarifies that user is unauthenticated, providing top-rated catalog selections. |
| 6 | **“Change language to English” / “Uygulama dilini İngilizce yap”** | Action Intent Dispatcher | Status `action_executed`. Returns typed action `{"type": "SET_LANGUAGE", "payload": {"language": "en"}}`. |
| 7 | **“What day and time is it?” / “Bugün günlerden ne, saat kaç?”** | System Clock Intent (Europe/Istanbul) | Status `clock`. Returns current date, weekday, and TRT (UTC+3) timestamp. |
| 8 | **External Provider Unavailable** | Resilient Deterministic Fallback | Status `llm_fallback`. Seamlessly returns catalog records without crashing or hallucinating. |
| 9 | **“1984 kitabını favorilerime ekle” (Signed Out)** | Authorization Boundary Guard | Status `auth_required`. Refuses unauthorized mutation and directs to `/login`. |
| 10 | **“Kitaplığımda neler var?” (Signed Out)** | Authorization Boundary Guard | Status `auth_required`. Refuses access to private data and directs to `/login`. |

---

## 7. Cross-Client Parity Matrix

| Feature / Domain | Backend API | Web Client (Next.js) | Flutter Client (Mobile/Web) | Automated Tests |
| :--- | :---: | :---: | :---: | :---: |
| **Supabase Authentication** | N/A (Client/Auth Server) | Full (SSR + Client) | Full (Reactive Provider) | Passed (Unit & Flow) |
| **Email Confirmation Notice** | Supabase Auth API | Yes (`setConfirmationSent`) | Yes (`requiresEmailConfirmation`) | Passed |
| **Deep-Link Intent Handlers** | N/A | Next.js dynamic routing | Android Intent + iOS URL scheme | Verified in Plist & Manifest |
| **In-Flight Click Protection** | Rate-limiter (HTTP 429) | Form disabled state | `_isSubmitting` & `_isAuthenticating` | Passed |
| **28 Canonical Categories** | Full (`taxonomy.py`) | Full (`categories`) | Full (`CategoryMapper` + Icons) | Passed |
| **Catalog Search & Filtering** | Full (`/api/books`) | Full (`/catalog`) | Full (`CatalogProvider`) | Passed |
| **Empty State Recovery Links** | Standardized JSON | UI Filter Chips & Reset | UI Filter Reset & Retry | Passed |
| **Grounded AI Discovery** | Full (`/api/ai/chat`) | Full (`/ai-discovery`) | Full (`AiDiscoveryScreen`) | Passed |
| **Theme / Palette / Language** | Action JSON API | Full (`PreferencesProvider`) | Full (`ThemeProvider`, `LanguageProvider`) | Passed (100% i18n parity) |
| **User Library / Shelves** | Full (RLS Scoped) | Full (`/favorites`) | Full (`FavoritesProvider`) | Passed |

---

## 8. Security Review

1. **Client Credential Boundary**:
   - `mobile/flutter_app/lib/config.dart` and `web/src/lib/supabase/client.ts` only receive the public Supabase anon key (`SUPABASE_ANON_KEY`).
   - The Supabase Service Role key is strictly isolated to backend environments and never exposed to clients or checked into git.
2. **Missing Configuration Diagnostics**:
   - Both Web and Flutter verify configuration presence without leaking key values in logs or exception messages.
3. **Data Boundary & RLS Enforcement**:
   - Endpoints modifying shelves or reading personal preferences require authenticated bearer tokens (`Authorization: Bearer <jwt>`) verified against Supabase Auth.
   - Unauthenticated AI chat queries cannot access or modify personal reading shelves (`status="auth_required"`).
4. **Input Sanitization & Prompt Injection Protection**:
   - All AI prompt inputs are sanitized via `_sanitize_prompt_text` in `backend/application/use_cases/ai_rag.py`, stripping dangerous XML-like breakout delimiters (`<context>`, `<system>`, `<instruction>`).

---

## 9. Exact Commands and Observed Outcomes

### 9.1 Backend Tests
- **Command**: `python -m pytest backend/tests -m "not integration and not external and not e2e"`
- **Result**: `424 passed in 69.36s` (Exit Code: 0).
- **Targeted AI Test Command**: `python -m pytest backend/tests/test_ai_capabilities.py`
- **Result**: `14 passed in 20.28s` (Exit Code: 0).

### 9.2 Mobile Tests & Analyzer
- **Analyzer Command**: `flutter analyze` in `mobile/flutter_app`
- **Result**: `No issues found! (ran in 6.8s)` (Exit Code: 0).
- **Unit Test Command**: `flutter test test/auth_provider_test.dart` in `mobile/flutter_app`
- **Result**: `11 passed in 4s` (Exit Code: 0).
- **Full Test Suite Command**: `flutter test` in `mobile/flutter_app`
- **Result**: `150 passed, 1 skipped, 0 failed in 12s` (Exit Code: 0).

### 9.3 Web Client Tests & Build
- **Test Command**: `npm test` in `web`
- **Result**: `122 passed, 0 failed in 2.86s` (Exit Code: 0).
- **Build Command**: `npm run build` in `web`
- **Result**: `Compiled successfully in 449ms, 11 static/PPR routes generated` (Exit Code: 0).

---

## 10. Known Limitations & Next Steps

1. **Live Device Push Notifications**:
   - Android and iOS push notifications require platform-specific Apple Developer / Firebase credentials not available in local test environments.
2. **External LLM Provider Live API Key**:
   - When no external OpenAI / Claude API key is configured in the environment, the backend automatically runs in deterministic fallback mode.
3. **Next.js Security Upgrade Recommendation**:
   - Next.js 16.4.0 reported a security vulnerability advisory during initial build. A managed upgrade (`next upgrade --agent=security`) should be performed in a separate worktree.

---

## 11. Final Working-Tree Summary

| File | Change Description |
| :--- | :--- |
| `backend/domain/taxonomy.py` | Added self-mappings for all 28 canonical categories; remapped `"london (england)"` to `Fiction`. |
| `backend/infrastructure/ml/recommender.py` | Fixed `_book_matches_canonical()` to prevent delimiter splitting on `&` from breaking compound categories. |
| `backend/scripts/audit_catalog_taxonomy.py` | Created comprehensive catalog taxonomy and metadata checksum audit script. |
| `backend/application/use_cases/ai_rag.py` | Added deterministic author lookup, unauthenticated save/shelf guards, and anonymous recommendation transparency. |
| `backend/tests/test_ai_capabilities.py` | Added test cases covering all 10 grounded AI discovery user journeys. |
| `mobile/flutter_app/lib/config.dart` | Added `AppConfig.isSupabaseConfigured` validation getter. |
| `mobile/flutter_app/lib/services/auth_service_base.dart` | Added `isConfigured` property to `AuthServiceBase` contract. |
| `mobile/flutter_app/lib/services/supabase_service.dart` | Implemented `isConfigured` checking `AppConfig.isSupabaseConfigured`. |
| `mobile/flutter_app/lib/providers/auth_provider.dart` | Added configuration guard, email confirmation handling, rate limit mapping, and in-flight click protection. |
| `mobile/flutter_app/lib/screens/login_screen.dart` | Added `_isSubmitting` in-flight lock to prevent duplicate authentication requests. |
| `mobile/flutter_app/lib/screens/register_screen.dart` | Added `_isSubmitting` in-flight lock and handled `requiresEmailConfirmation` state. |
| `mobile/flutter_app/lib/utils/category_mapper.dart` | Added mappings for all 28 canonical categories and Turkish aliases. |
| `mobile/flutter_app/lib/screens/categories_screen.dart` | Added dedicated icons and gradients for all canonical categories. |
| `mobile/flutter_app/assets/lang/*.json` | Added missing genre translation keys and authentication diagnostics in EN, TR, and DE (100% key parity). |
| `mobile/flutter_app/android/app/src/main/AndroidManifest.xml` | Added intent filter for `libris://login-callback`. |
| `mobile/flutter_app/ios/Runner/Info.plist` | Added `CFBundleURLTypes` with `libris` URL scheme. |
| `mobile/flutter_app/test/auth_provider_test.dart` | Added tests for unconfigured state, rate limits, email confirmation, existing accounts, and concurrency. |
| `web/src/app/signup/page.tsx` | Handled `data.session === null` and `data.user?.identities?.length === 0` to display confirmation notices without premature login attempts. |
