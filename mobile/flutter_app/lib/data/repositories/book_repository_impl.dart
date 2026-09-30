import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../../domain/entities/book.dart';
import '../../domain/repositories/book_repository.dart';
import '../../services/api_service.dart';
import '../../services/supabase_service.dart';
import '../models/book_dto.dart';

class BookRepositoryImpl implements BookRepository {
  final ApiService _api;
  final SupabaseService _supabase;
  
  BookRepositoryImpl(this._api, this._supabase);

  @override
  Future<List<Book>> getPopularBooks({int limit = 20}) async {
    try {
      // DTO mapping occurs inside SupabaseService currently, wait, SupabaseService returns Book model!
      // I should map it here if it returned Map. But since SupabaseService already returns Book (now Entity), it's fine.
      final books = await _supabase.getPopularBooks(limit: limit);
      return books;
    } catch (_) {
      // Fallback to Flask API
      final books = await _api.getPopularBooks(limit: limit);
      return books;
    }
  }

  @override
  Future<List<Book>> getMorePopularBooks({required int offset, int limit = 20}) async {
    final response = await _supabase.client
        .from('books')
        .select()
        .order('ratings_count', ascending: false)
        .range(offset, offset + limit - 1)
        .timeout(const Duration(seconds: 10));

    return (response as List).map((j) => BookDto.fromJson(j)).toList();
  }

  @override
  Future<List<Book>> getPersonalizedRecommendations(String userId) async {
    return await _api.getPersonalizedRecommendations(userId: userId);
  }

  @override
  Future<List<Book>> getFallbackRecommendations(String userId) async {
    // 1) Seed from favorites
    final favorites = await _supabase.getFavorites(userId);
    if (favorites.isEmpty) {
      return [];
    }

    final seedIds = <String>[];
    final seedTitles = <String>[];
    for (final favorite in favorites.take(3)) {
      final bid = (favorite['book_id'] ?? '').toString();
      if (bid.isEmpty) continue;
      final book = await _supabase.getBookByIsbn(bid);
      if (book != null && book.title.isNotEmpty) {
        seedIds.add(book.isbn13);
        seedTitles.add(book.title);
      }
    }

    final recMap = <String, Book>{};
    for (final title in seedTitles) {
      final recs = await _api.getRecommendations(title, topN: 12);
      for (final rec in recs) {
        if (seedIds.contains(rec.isbn13)) continue;
        recMap.putIfAbsent(rec.isbn13, () => rec);
      }
    }

    if (recMap.isNotEmpty) {
      return recMap.values.take(20).toList();
    }

    // 2) Category fallback
    final firstFav = favorites.first;
    final bookId = (firstFav['book_id'] ?? '').toString();
    final bookData = await _supabase.getBookByIsbn(bookId);
    
    if (bookData != null && bookData.categories.isNotEmpty) {
      // UI Logic primaryCategory should be extracted
      final category = bookData.categories.split(RegExp(r'[|;,]')).first.trim();
      final response = await _api.getBooksByCategory(
        category: category,
        page: 1,
        perPage: 20,
      );
      final books = response['books'] as List<Book>;
      return books.where((b) => !seedIds.contains(b.isbn13)).take(20).toList();
    } 

    return await _api.getPopularBooks(limit: 20);
  }

  @override
  Future<List<Book>> searchBooks(String query) async {
    return await _supabase.searchBooks(query);
  }

  @override
  Future<List<String>> getCategories() async {
    return await _api.getCategories();
  }

  @override
  Future<bool> submitFeedback({required String userId, required String bookId, required String interaction}) async {
    return await _api.submitFeedback(userId: userId, bookId: bookId, interaction: interaction);
  }

  @override
  Future<bool> submitOnboarding({required String userId, required List<String> bookIds, required List<String> genres}) async {
    return await _api.submitOnboarding(userId: userId, bookIds: bookIds, genres: genres);
  }

  @override
  List<Book> getCachedPopularBooks() {
    try {
      final box = Hive.box('books_cache');
      final popularData = box.get('popular_books');
      if (popularData != null) {
        final List<dynamic> decoded = jsonDecode(popularData);
        return decoded.map((j) => BookDto.fromJson(j)).toList();
      }
    } catch (e) {
      debugPrint('Cache read error: $e');
    }
    return [];
  }

  @override
  void savePopularBooksToCache(List<Book> books) {
    try {
      final box = Hive.box('books_cache');
      final encoded = jsonEncode(books.map((b) => BookDto.toJson(b)).toList());
      box.put('popular_books', encoded);
    } catch (_) {}
  }

  @override
  Future<int> getTotalBookCount() async {
    return await _supabase.getTotalBookCount();
  }
}
