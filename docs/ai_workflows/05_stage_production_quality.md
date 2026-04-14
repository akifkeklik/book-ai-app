# AI Execution Plan - Stage 5: Production Quality & Maintenance

## Context
As the project prepares for App Store/Play Store launch, the codebase must be rigorously clean (Linter rules) and fully tested to prevent regression bugs. Analytics must be attached to track crashes aggressively.

## Objectives
1. Enforce strict Linter and Clean Code rules across the Dart codebase.
2. Build crucial Widget and Unit tests for `AuthProvider` and `SupabaseService`.
3. Integrate Crashlytics/Analytics foundations.

## Instructions for AI Agent
1. **Linting Sweep**:
   - Open `pubspec.yaml` and ensure `flutter_lints` or `lints` is strictly configured. 
   - Run `flutter analyze` internally to pinpoint unused imports, dead code, or improperly named classes in the `lib` folder.
   - Correct all warnings systematically. Remove console `print()` statements and replace them with a structured `Logger` package (e.g., `logger: ^2.0.2`).
2. **Unit / Widget Testing**:
   - Create the `test/` directory if missing.
   - Write `auth_provider_test.dart` to assert that signing in updates the internal state variables correctly.
   - Write a widget test `catalog_screen_test.dart` to ensure pumping the catalog screen rendering 1 item does not overflow.
3. **Analytics (Prep)**:
   - Since we use Supabase (or optionally Firebase), create an isolated `AnalyticsService` wrapper in `lib/services/analytics_service.dart`. Route app-level crashes or unhandled exceptions from Stage 1 into an `AnalyticsService.logError(...)` framework to intercept real-time crashes in production.

## Success Criteria
- Project complies 100% with the strict Dart linter rules. Zero dead code/unused imports.
- Running `flutter test` outputs all green for the critical business logic layers.
- Production environment crashes are properly dispatched to a logging framework gracefully instead of silent death.
