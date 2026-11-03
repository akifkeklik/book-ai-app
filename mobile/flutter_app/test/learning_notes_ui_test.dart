import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:book_ai_app/domain/entities/book.dart';
import 'package:book_ai_app/domain/entities/learning_note.dart';
import 'package:book_ai_app/domain/repositories/book_repository.dart';
import 'package:book_ai_app/screens/detail_screen.dart';
import 'package:book_ai_app/screens/favorites_screen.dart';
import 'package:book_ai_app/providers/auth_provider.dart';
import 'package:book_ai_app/providers/favorites_provider.dart';
import 'package:book_ai_app/providers/language_provider.dart';
import 'package:book_ai_app/providers/notes_provider.dart';
import 'package:book_ai_app/providers/recommendation_provider.dart';
import 'package:book_ai_app/application/use_cases/view_book_details_use_case.dart';
import 'package:book_ai_app/application/use_cases/manage_recommendations_use_case.dart';
import 'package:book_ai_app/services/api_service.dart';
import 'package:book_ai_app/services/supabase_service.dart';

import 'auth_provider_test.dart' show FakeAuthService;

class FakeUiBookRepository implements BookRepository {
  final Book sample;
  FakeUiBookRepository(this.sample);

  @override
  Future<Book?> getBookByIsbn(String isbn) async => sample;

  @override
  Future<List<Book>> getRecommendations(String title) async => [];

  @override
  Future<String?> getUserInteraction(String userId, String bookId) async => null;

  @override
  Future<bool> trackActivity({
    required String userId,
    required String activityType,
    required String bookId,
    String? bookName,
  }) async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeUiSupabaseService implements SupabaseService {
  @override
  Stream<List<Map<String, dynamic>>> streamFavorites(String userId) {
    return Stream.value(const []);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class FakeUiApiService implements ApiService {
  final List<LearningNote> db = [];

  @override
  Future<List<LearningNote>> getNotes({
    String? bookId,
    String? noteType,
    String? query,
    int limit = 50,
    int offset = 0,
  }) async {
    var list = List<LearningNote>.from(db);
    if (bookId != null && bookId.isNotEmpty) {
      list = list.where((n) => n.bookId == bookId).toList();
    }
    if (noteType != null && noteType.isNotEmpty) {
      list = list.where((n) => n.noteType == noteType).toList();
    }
    if (query != null && query.isNotEmpty) {
      final q = query.toLowerCase();
      list = list.where((n) => n.content.toLowerCase().contains(q) || n.bookId.toLowerCase().contains(q)).toList();
    }
    return list;
  }

  @override
  Future<LearningNote?> createNote({
    required String bookId,
    required String noteType,
    required String content,
    String? clientId,
  }) async {
    final note = LearningNote(
      id: 'ui-note-${db.length + 1}',
      userId: 'test_user_1',
      bookId: bookId,
      noteType: noteType,
      content: content,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      clientId: clientId,
    );
    db.insert(0, note);
    return note;
  }

  @override
  Future<LearningNote?> updateNote({
    required String noteId,
    required String content,
    String? noteType,
  }) async {
    final index = db.indexWhere((n) => n.id == noteId);
    if (index == -1) return null;
    final updated = db[index].copyWith(
      content: content,
      noteType: noteType ?? db[index].noteType,
      updatedAt: DateTime.now(),
    );
    db[index] = updated;
    return updated;
  }

  @override
  Future<bool> deleteNote({required String noteId}) async {
    final index = db.indexWhere((n) => n.id == noteId);
    if (index == -1) return false;
    db.removeAt(index);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const sampleBook = Book(
    isbn13: '978-0451524935',
    title: '1984',
    authors: 'George Orwell',
    categories: 'Fiction',
    thumbnail: '',
    description: 'A dystopian social science fiction novel.',
    publishedDate: '1949',
    averageRating: 4.8,
    ratingsCount: 5000,
    pageCount: 328,
  );

  group('Learning Notes UI & Widget Tests', () {
    testWidgets('DetailScreen shows sign-in card when unauthenticated', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeRepo = FakeUiBookRepository(sampleBook);
      final fakeAuth = FakeAuthService();
      final authProvider = AuthProvider(fakeAuth);
      final fakeSupabase = FakeUiSupabaseService();
      final fakeApi = FakeUiApiService();
      final notesProvider = NotesProvider(apiService: fakeApi);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
            ChangeNotifierProvider(create: (_) => FavoritesProvider(fakeSupabase)),
            ChangeNotifierProvider(create: (_) => LanguageProvider()),
            ChangeNotifierProvider<NotesProvider>.value(value: notesProvider),
            ChangeNotifierProvider(create: (_) => RecommendationProvider(manageRecommendations: ManageRecommendationsUseCase(fakeRepo))),
            Provider<ViewBookDetailsUseCase>(create: (_) => ViewBookDetailsUseCase(fakeRepo)),
            Provider<ManageRecommendationsUseCase>(create: (_) => ManageRecommendationsUseCase(fakeRepo)),
          ],
          child: MaterialApp(
            home: DetailScreen(
              isbn: sampleBook.isbn13,
              initialBook: sampleBook,
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify sign in card is shown for notes
      expect(find.byIcon(Icons.edit_note_rounded), findsWidgets);
      expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      authProvider.dispose();
      notesProvider.dispose();
    });

    testWidgets('DetailScreen shows notes and allows adding a new note', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeRepo = FakeUiBookRepository(sampleBook);
      final fakeAuth = FakeAuthService();
      final authProvider = AuthProvider(fakeAuth);
      await authProvider.login(email: 'ok@test.com', password: 'password123');

      final fakeSupabase = FakeUiSupabaseService();
      final fakeApi = FakeUiApiService();
      final notesProvider = NotesProvider(apiService: fakeApi);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
            ChangeNotifierProvider(create: (_) => FavoritesProvider(fakeSupabase)),
            ChangeNotifierProvider(create: (_) => LanguageProvider()),
            ChangeNotifierProvider<NotesProvider>.value(value: notesProvider),
            ChangeNotifierProvider(create: (_) => RecommendationProvider(manageRecommendations: ManageRecommendationsUseCase(fakeRepo))),
            Provider<ViewBookDetailsUseCase>(create: (_) => ViewBookDetailsUseCase(fakeRepo)),
            Provider<ManageRecommendationsUseCase>(create: (_) => ManageRecommendationsUseCase(fakeRepo)),
          ],
          child: MaterialApp(
            home: DetailScreen(
              isbn: sampleBook.isbn13,
              initialBook: sampleBook,
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Check empty notes state has add button
      expect(find.byKey(const Key('add_first_note_button')), findsOneWidget);

      // Tap add note button
      await tester.tap(find.byKey(const Key('add_first_note_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Bottom sheet modal should appear with TextField
      expect(find.byKey(const Key('note_content_textfield')), findsOneWidget);

      // Enter content
      await tester.enterText(
        find.byKey(const Key('note_content_textfield')),
        'War is peace, freedom is slavery, ignorance is strength.',
      );
      await tester.pump();

      // Save note
      await tester.tap(find.byKey(const Key('save_note_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Note card should now be rendered in the list
      expect(find.text('War is peace, freedom is slavery, ignorance is strength.'), findsOneWidget);
      expect(find.byIcon(Icons.sticky_note_2_outlined), findsWidgets);

      await tester.pump(const Duration(seconds: 5));
      authProvider.dispose();
      notesProvider.dispose();
    });

    testWidgets('FavoritesScreen displays Library Notes tab and filters', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeAuth = FakeAuthService();
      final authProvider = AuthProvider(fakeAuth);
      await authProvider.login(email: 'ok@test.com', password: 'password123');

      final fakeSupabase = FakeUiSupabaseService();
      final fakeApi = FakeUiApiService();
      fakeApi.db.add(LearningNote(
        id: 'note-hub-1',
        userId: 'uid-1',
        bookId: '978-0451524935',
        noteType: 'key_takeaway',
        content: 'Historical revisionism as a tool of total control',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      final notesProvider = NotesProvider(apiService: fakeApi);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
            ChangeNotifierProvider(create: (_) => FavoritesProvider(fakeSupabase)),
            ChangeNotifierProvider(create: (_) => LanguageProvider()),
            ChangeNotifierProvider<NotesProvider>.value(value: notesProvider),
          ],
          child: const MaterialApp(
            home: FavoritesScreen(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify the Notes tab exists
      expect(find.byKey(const Key('library_notes_tab')), findsOneWidget);

      // Switch to Notes tab
      await tester.tap(find.byKey(const Key('library_notes_tab')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Verify note item is visible
      expect(find.text('Historical revisionism as a tool of total control'), findsOneWidget);
      expect(find.text('ISBN: 978-0451524935'), findsOneWidget);
      expect(find.byKey(const Key('notes_hub_search_input')), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      authProvider.dispose();
      notesProvider.dispose();
    });
  });
}

