# AI Execution Plan - Stage 3: Modernization & UX

## Context
The app needs to look and feel premium. This involves adding polished micro-animations, standardizing the color system, and implementing features like deep linking and debounced search to provide a "Sahibinden" or "Netflix" level of smoothness.

## Objectives
1. Introduce sophisticated Micro-Animations and Hero transitions.
2. Implement Deep Linking to allow external URLs to open specific book pages.
3. Add Debounced API calls for the search functionality.

## Instructions for AI Agent
1. **Hero Animations**:
   - Wrap the `CachedNetworkImage` of book covers in a `Hero` widget, both in the Grid/List view and the Detail view. Ensure the `tag` is unique (e.g., `book_cover_${book.id}`).
2. **Smooth Navigations & Feedback**:
   - Replace snappy, instant page jumps with `CupertinoPageRoute` or custom `PageRouteBuilder` with fade/slide transitions in `lib/router.dart` or standard navigation.
   - Add `InkWell` or `GestureDetector` scaling on touch to interactive items (cards, buttons) to provide tactile feedback.
3. **Debounced Search**:
   - In the Search screen/provider, use a `Timer` (Dart `dart:async`) or `rxdart` to debounce the keystrokes. Wait ~500ms after the user stops typing before calling the backend API to save bandwidth and prevent racing conditions.
4. **Deep Linking Preparation**:
   - Ensure `go_router` or the native navigation handles incoming URL paths for `/book/:id`. Update `pubspec.yaml` or AndroidManifest.xml if required, but first ensure the Flutter routing handles the parameter safely.

## Success Criteria
- Transitioning from Home -> Book Detail shows the cover image smoothly expanding (Hero).
- Hitting keys rapidly in the search bar triggers exactly ONE resulting API call.
- The app visually responds (ripple or scale) to all interactions.
