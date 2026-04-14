# AI Execution Plan - Stage 4: Backend & Machine Learning

## Context
The ML recommendation engine built in Flask needs to flawlessly integrate with the Flutter app. A key flaw to avoid is the "Cold Start" problem (where a new user has no favorites, hence the ML throws an error or gives zero results). Furthermore, real-time sync across devices is requested.

## Objectives
1. Implement "Cold Start" fallbacks for the ML Engine.
2. Establish Real-time database streams (WebSockets) via Supabase for user data (favorites/reading lists).

## Instructions for AI Agent
1. **Cold Start Strategy**:
   - Check the `Flask` application endpoint responsible for recommendations.
   - If the incoming user ID has an empty `favorites` array, do NOT throw an exception. Instead, fallback the return array to top 10 globally most popular books, ensuring the response format remains identical.
   - On the Flutter side, if the user has 0 favorites, overlay a gentle UI tooltip: "Kalbini bıraktığın kitaplar arttıkça sana özel öneriler belirecek."
2. **Real-time Database Sync**:
   - Open `lib/services/supabase_service.dart`.
   - Modify the user's `Favorites` retrieval. Instead of a single Future `get()`, wrap it in a `Supabase.client.from('favorites').stream(...)`.
   - Pipe this stream directly into the state management provider so that if the DB changes remotely, the app immediately toggles the heart icons without a manual refresh pull.

## Success Criteria
- Creating a brand new account and visiting the "Öneriler" (Recommendations) page displays top-tier default books, no red error screens or infinite spinners.
- Adding a book to favorites on one device instantly (within 1 second) updates the favorites list on another device logged into the same account.
