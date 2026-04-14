# AI Execution Plan - Stage 2: Performance & Scalability

## Context
With a database of 6000+ books, the application must fetch data in chunks rather than loading all items at once. It also needs to cache network imagery and fetched data vigorously to maintain a 60 FPS scrolling experience and provide offline-first capabilities.

## Objectives
1. Implement Pagination / Infinite Scroll in `lib/screens/catalog_screen.dart` (or category timelines).
2. Integrate strict offline-first fetching using `Hive` and `CachedNetworkImage`.
3. Optimize State Management to avoid global rebuilds.

## Instructions for AI Agent
1. **Pagination**:
   - In `lib/services/supabase_service.dart`, modify the methods fetching books (`getBooksByCategory`, etc.) to accept `limit` and `offset` parameters or cursor-based pagination.
   - Attach a `ScrollController` in the list screens. Detect when the user reaches 80% of the list, then trigger the next fetch. Display a small loading indicator at the bottom.
2. **Caching**:
   - Ensure all network images use `CachedNetworkImage` with proper `placeholder` (shimmer) and `errorWidget`.
   - Setup `Hive` in `main.dart` to cache the latest viewed list of books, so if the user opens the app without internet, they see the last catalog view immediately.
3. **Provider Rebuild Optimization**:
   - Review all screens using `Provider.of<T>(context)`. Convert them to `Consumer<T>` or `Selector<T, V>` where only a subset of the screen needs to rebuild (e.g., just the Favorite icon, not the entire book list).

## Success Criteria
- Memory usage does not spike when scrolling past 50 items.
- Network requests drop to 0 for previously viewed book cover images.
- Unnecessary calls to `build()` methods in list items are strictly eliminated.
