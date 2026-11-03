import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../data/repositories/favorites_outbox_repository.dart';
import '../data/repositories/interactions_outbox_repository.dart';
import '../data/repositories/notes_outbox_repository.dart';
import '../domain/entities/favorite_outbox_item.dart';
import '../services/api_service.dart';
import '../services/supabase_service.dart';

enum FailureCategory {
  none,
  auth,
  clientError,
  network,
  server,
}

class SyncDiagnostics {
  final String userId;
  final int queueDepth;
  final int favoritesPending;
  final int interactionsPending;
  final int notesPending;
  final int retryCount;
  final DateTime? lastAttemptAt;
  final DateTime? lastSuccessAt;
  final FailureCategory failureCategory;
  final String? lastErrorSummary;

  const SyncDiagnostics({
    required this.userId,
    required this.queueDepth,
    required this.favoritesPending,
    required this.interactionsPending,
    this.notesPending = 0,
    required this.retryCount,
    required this.lastAttemptAt,
    required this.lastSuccessAt,
    required this.failureCategory,
    this.lastErrorSummary,
  });

  @override
  String toString() =>
      'SyncDiagnostics(user: $userId, depth: $queueDepth [fav: $favoritesPending, int: $interactionsPending, notes: $notesPending], retries: $retryCount, category: $failureCategory)';
}

class SyncCoordinatorResult {
  final SyncResult favResult;
  final SyncResult intResult;
  final SyncResult notesResult;
  final int totalSynced;
  final int totalFailed;
  final int totalSkipped;
  final DateTime timestamp;

  const SyncCoordinatorResult({
    required this.favResult,
    required this.intResult,
    this.notesResult = const SyncResult(synced: 0, failed: 0, skipped: 0),
    required this.totalSynced,
    required this.totalFailed,
    required this.totalSkipped,
    required this.timestamp,
  });

  bool get hasFailures => totalFailed > 0;
  bool get isClean => totalFailed == 0 && totalSkipped == 0;
}

class SyncCoordinator {
  static SyncCoordinator? _instance;
  static SyncCoordinator get instance => _instance ??= SyncCoordinator();

  final FavoritesOutboxRepository _favRepo;
  final InteractionsOutboxRepository _intRepo;
  final NotesOutboxRepository _notesRepo;

  bool _isSyncing = false;
  DateTime? _lastAttemptAt;
  DateTime? _lastSuccessAt;

  SyncCoordinator({
    FavoritesOutboxRepository? favRepo,
    InteractionsOutboxRepository? intRepo,
    NotesOutboxRepository? notesRepo,
  })  : _favRepo = favRepo ?? FavoritesOutboxRepository(),
        _intRepo = intRepo ?? InteractionsOutboxRepository(),
        _notesRepo = notesRepo ?? NotesOutboxRepository();

  bool get isSyncing => _isSyncing;
  DateTime? get lastAttemptAt => _lastAttemptAt;
  DateTime? get lastSuccessAt => _lastSuccessAt;

  /// Resets authentication-caused suspended failures across all outbox repositories for [userId].
  void resetAuthFailures(String userId) {
    _favRepo.resetAuthFailures(userId);
    _intRepo.resetAuthFailures(userId);
    _notesRepo.resetAuthFailures(userId);
  }

  /// Safe bootstrap for background execution in a fresh Dart isolate.
  /// Does not assume the foreground ServiceLocator or Hive boxes are initialized.
  static Future<void> initializeForBackground() async {
    try {
      if (!Hive.isBoxOpen('favorites_outbox') && !Hive.isBoxOpen('books_cache')) {
        await Hive.initFlutter();
      }
      if (!Hive.isBoxOpen('favorites_outbox')) {
        await Hive.openBox('favorites_outbox');
      }
      if (!Hive.isBoxOpen('interactions_outbox')) {
        await Hive.openBox('interactions_outbox');
      }
      if (!Hive.isBoxOpen('notes_outbox')) {
        await Hive.openBox('notes_outbox');
      }
      if (!Hive.isBoxOpen('notes_cache')) {
        await Hive.openBox('notes_cache');
      }

      // Initialize API service in isolate
      ApiService.instance.init();

      // Initialize Supabase if needed
      try {
        // If Supabase is not initialized, accessing client throws an AssertionError or Exception
        Supabase.instance.client;
      } catch (_) {
        await Supabase.initialize(
          url: AppConfig.supabaseUrl,
          publishableKey: AppConfig.supabaseAnonKey,
        );
      }
    } catch (e) {
      debugPrint('[SyncCoordinator] Background isolate bootstrap warning: $e');
    }
  }

  /// Synchronizes both favorites and interactions queues with strict account isolation
  /// and concurrency guards.
  Future<SyncCoordinatorResult> syncAll({
    required String userId,
    required ApiService apiService,
    required SupabaseService supabaseService,
    bool forceRetry = false,
  }) async {
    // Account Isolation Guard:
    // A task queued for User A must NEVER be sent under User B's credentials or unauthenticated!
    final currentSessionUser = supabaseService.currentUser?.id;
    if (currentSessionUser != userId) {
      debugPrint(
        '[SyncCoordinator] Account Isolation Block: Outbox owner ($userId) != current session ($currentSessionUser). Pausing queue.',
      );
      return SyncCoordinatorResult(
        favResult: const SyncResult(synced: 0, failed: 0, skipped: 0),
        intResult: const SyncResult(synced: 0, failed: 0, skipped: 0),
        notesResult: const SyncResult(synced: 0, failed: 0, skipped: 0),
        totalSynced: 0,
        totalFailed: 0,
        totalSkipped: _favRepo.getPendingItems(userId).length +
            _intRepo.getPendingItems(userId).length +
            _notesRepo.getPendingItems(userId).length,
        timestamp: DateTime.now(),
      );
    }

    // Overlapping execution guard:
    if (_isSyncing) {
      debugPrint('[SyncCoordinator] Sync already in progress. Skipping duplicate request.');
      return SyncCoordinatorResult(
        favResult: const SyncResult(synced: 0, failed: 0, skipped: 0),
        intResult: const SyncResult(synced: 0, failed: 0, skipped: 0),
        notesResult: const SyncResult(synced: 0, failed: 0, skipped: 0),
        totalSynced: 0,
        totalFailed: 0,
        totalSkipped: _favRepo.getPendingItems(userId).length +
            _intRepo.getPendingItems(userId).length +
            _notesRepo.getPendingItems(userId).length,
        timestamp: DateTime.now(),
      );
    }

    _isSyncing = true;
    _lastAttemptAt = DateTime.now();

    try {
      // 1. Synchronize favorites outbox
      final favResult = await _favRepo.syncUserOutbox(
        userId: userId,
        supabaseService: supabaseService,
        forceRetry: forceRetry,
      );

      // 2. Synchronize interactions outbox
      final intResult = await _intRepo.syncUserOutbox(
        userId: userId,
        apiService: apiService,
        forceRetry: forceRetry,
      );

      // 3. Synchronize notes outbox
      final notesResult = await _notesRepo.syncUserOutbox(
        userId: userId,
        apiService: apiService,
        forceRetry: forceRetry,
      );

      final totalSynced = favResult.synced + intResult.synced + notesResult.synced;
      final totalFailed = favResult.failed + intResult.failed + notesResult.failed;
      final totalSkipped = favResult.skipped + intResult.skipped + notesResult.skipped;

      if (totalFailed == 0 && totalSynced > 0) {
        _lastSuccessAt = DateTime.now();
      }

      return SyncCoordinatorResult(
        favResult: favResult,
        intResult: intResult,
        notesResult: notesResult,
        totalSynced: totalSynced,
        totalFailed: totalFailed,
        totalSkipped: totalSkipped,
        timestamp: DateTime.now(),
      );
    } finally {
      _isSyncing = false;
    }
  }

  /// Produces privacy-safe diagnostics for monitoring queue depth and health.
  SyncDiagnostics getDiagnostics(String userId) {
    final favItems = _favRepo.getPendingItems(userId);
    final intItems = _intRepo.getPendingItems(userId);
    final noteItems = _notesRepo.getPendingItems(userId);

    final queueDepth = favItems.length + intItems.length + noteItems.length;
    int maxRetries = 0;
    DateTime? latestAttempt = _lastAttemptAt;
    FailureCategory category = FailureCategory.none;
    String? errorSummary;

    for (final item in favItems) {
      if (item.retryCount > maxRetries) maxRetries = item.retryCount;
      if (item.lastAttemptAt != null &&
          (latestAttempt == null || item.lastAttemptAt!.isAfter(latestAttempt))) {
        latestAttempt = item.lastAttemptAt;
      }
      if (item.status == OutboxStatus.failed ||
          item.status == OutboxStatus.permanentFailure) {
        final err = (item.lastError ?? '').toLowerCase();
        if (err.contains('401') || err.contains('unauthorized') || err.contains('jwt')) {
          category = FailureCategory.auth;
          errorSummary = 'Authentication token expired or invalid';
        } else if (err.contains('400') || err.contains('422')) {
          category = FailureCategory.clientError;
          errorSummary = 'Client validation error';
        } else if (err.contains('socket') || err.contains('network') || err.contains('timeout')) {
          if (category == FailureCategory.none) {
            category = FailureCategory.network;
            errorSummary = 'Network connectivity unavailable';
          }
        } else if (category == FailureCategory.none) {
          category = FailureCategory.server;
          errorSummary = 'Server error during sync';
        }
      }
    }

    for (final item in intItems) {
      if (item.retryCount > maxRetries) maxRetries = item.retryCount;
      if (item.lastAttemptAt != null &&
          (latestAttempt == null || item.lastAttemptAt!.isAfter(latestAttempt))) {
        latestAttempt = item.lastAttemptAt;
      }
      if (item.status == OutboxStatus.failed ||
          item.status == OutboxStatus.permanentFailure) {
        final err = (item.lastError ?? '').toLowerCase();
        if (err.contains('401') || err.contains('unauthorized') || err.contains('jwt')) {
          category = FailureCategory.auth;
          errorSummary = 'Authentication token expired or invalid';
        } else if (err.contains('400') || err.contains('422')) {
          category = FailureCategory.clientError;
          errorSummary = 'Client validation error';
        } else if (err.contains('socket') || err.contains('network') || err.contains('timeout')) {
          if (category == FailureCategory.none) {
            category = FailureCategory.network;
            errorSummary = 'Network connectivity unavailable';
          }
        } else if (category == FailureCategory.none) {
          category = FailureCategory.server;
          errorSummary = 'Server error during sync';
        }
      }
    }

    for (final item in noteItems) {
      if (item.retryCount > maxRetries) maxRetries = item.retryCount;
      if (item.lastAttemptAt != null &&
          (latestAttempt == null || item.lastAttemptAt!.isAfter(latestAttempt))) {
        latestAttempt = item.lastAttemptAt;
      }
      if (item.status == OutboxStatus.failed ||
          item.status == OutboxStatus.permanentFailure) {
        final err = (item.lastError ?? '').toLowerCase();
        if (err.contains('401') || err.contains('unauthorized') || err.contains('jwt')) {
          category = FailureCategory.auth;
          errorSummary = 'Authentication token expired or invalid';
        } else if (err.contains('400') || err.contains('422')) {
          category = FailureCategory.clientError;
          errorSummary = 'Client validation error';
        } else if (err.contains('socket') || err.contains('network') || err.contains('timeout')) {
          if (category == FailureCategory.none) {
            category = FailureCategory.network;
            errorSummary = 'Network connectivity unavailable';
          }
        } else if (category == FailureCategory.none) {
          category = FailureCategory.server;
          errorSummary = 'Server error during sync';
        }
      }
    }

    return SyncDiagnostics(
      userId: userId,
      queueDepth: queueDepth,
      favoritesPending: favItems.length,
      interactionsPending: intItems.length,
      notesPending: noteItems.length,
      retryCount: maxRetries,
      lastAttemptAt: latestAttempt,
      lastSuccessAt: _lastSuccessAt,
      failureCategory: category,
      lastErrorSummary: errorSummary,
    );
  }
}
