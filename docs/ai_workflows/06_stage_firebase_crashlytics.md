# AI Execution Plan - Stage 6: Firebase Analytics & Crashlytics

## Context
While Supabase handles our relational database and Auth perfectly, Firebase Crashlytics is the industry standard for catching fatal/non-fatal app crashes in production. We use Firebase *only* for observability.

## Objectives
1. Add Firebase Core, Analytics, and Crashlytics dependencies to `pubspec.yaml`.
2. Initialize Firebase in `main.dart` safely before Supabase.
3. Wire `AnalyticsService` to actually trigger Firebase methods.

## Instructions for AI Agent
1. **Dependencies**:
   - Add `firebase_core`, `firebase_analytics`, `firebase_crashlytics` to `pubspec.yaml`.
2. **Initialization**:
   - In `main.dart`, add `await Firebase.initializeApp(...)`.
   - *Wait for User:* The user must run `flutterfire configure` to generate `firebase_options.dart`. If it doesn't exist, wrap the initialization in a try/catch or skip it gracefully.
3. **Analytics Integration**:
   - Open `lib/services/analytics_service.dart`.
   - Update `logEvent` to call `FirebaseAnalytics.instance.logEvent`.
   - Update `logError` to call `FirebaseCrashlytics.instance.recordError`.
   - Catch Flutter errors globally in `main.dart` using `FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;`.

## Success Criteria
- App compiles without errors.
- Unhandled exceptions are piped to Crashlytics.
