# AI Execution Plan - Stage 8: App Store Prep & Permissions

## Context
Before submitting to Apple App Store and Google Play, native project configurations must be strictly defined, and internet/storage permissions declared.

## Objectives
1. Set up standard App Icons / Splash Screen config logic.
2. Inject required OS permissions in Android and iOS.
3. Final Linter / App Size Checks.

## Instructions for AI Agent
1. **Permissions**:
   - Open `android/app/src/main/AndroidManifest.xml`. Ensure `<uses-permission android:name="android.permission.INTERNET"/>` is present.
   - For iOS: Check `ios/Runner/Info.plist`. Add standard keys for network connectivity or tracking transparency if requested.
2. **Native Branding Setup**:
   - Add `flutter_launcher_icons` to `pubspec.yaml` under `dev_dependencies` to automate icon generation.
   - Provide a template `flutter_icons` block in pubspec.
3. **Release Profile Setup**:
   - Ensure ProGuard rules for Android are stable so the Flutter build engine doesn't strip out Supabase/Firebase classes aggressively during release compilation.

## Success Criteria
- Running `flutter format .` and `flutter analyze` returns absolutely zero issues.
- Project is fully ready for `flutter build apk --release` and `flutter build ipa`.
