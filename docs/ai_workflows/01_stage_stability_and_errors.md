# AI Execution Plan - Stage 1: Stability & Error Handling

## Context
The application needs global error handling and robust edge-case management to avoid silent crashes, white screens, or infinite loading states. 

## Objectives
1. Implement a Global Error Handler for Dio/HTTP requests to show meaningful feedback.
2. Fix edge-cases in `SupabaseService` and `AuthProvider` (e.g., token expiration, sudden offline status).
3. Prevent UI Overflows on small devices using `Flexible`, `Expanded`, and `SingleChildScrollView`.

## Instructions for AI Agent
1. **Global Provider Update**: 
   - Check `lib/providers/`. If an `error_provider.dart` doesn't exist, create it. It should expose a global method to show SnackBars/Dialogs on failure.
   - Modify `lib/main.dart` to inject this provider.
2. **Network/Supabase Resilience**:
   - Open `lib/services/supabase_service.dart`.
   - Wrap all API calls (favorites fetching, book retrieval) in robust `try/catch` blocks.
   - Timeout exceptions should throw a specific error intercepted by the UI, which triggers a "Retry" button rather than hanging.
3. **Auth Edge Cases**:
   - Open `lib/providers/auth_provider.dart`.
   - Ensure the `signOut` method clears all cached user data (favorites, profile info) locally.

## Success Criteria
- Disabling the device's internet mid-app usage should trigger a UI alert instead of hanging.
- No `Bottom overflowed` exceptions in Flutter's debug console.
- Logging out correctly clears memory.

**Agent Execution Note:** Proceed exactly with these changes without side-effects. Use `multi_replace_file_content` or `replace_file_content` carefully.
