import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';

import 'api_service.dart';
import 'supabase_service.dart';
import 'sync_coordinator.dart';

const String kLibrisPeriodicSyncTask = 'libris_periodic_outbox_sync';
const String kLibrisOneOffSyncTask = 'libris_one_off_outbox_sync';

@pragma('vm:entry-point')
void librisBackgroundSyncCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    debugPrint('[BackgroundSync] Dispatcher executing task: $taskName');

    try {
      // 1. Safe isolate initialization
      await SyncCoordinator.initializeForBackground();

      // 2. Identify active authenticated user
      String? activeUserId;
      try {
        activeUserId = Supabase.instance.client.auth.currentUser?.id;
      } catch (_) {}

      if (inputData != null && inputData['userId'] != null) {
        final passedUserId = inputData['userId'].toString();
        // If current authenticated session exists and differs from input data, skip for isolation
        if (activeUserId != null && activeUserId != passedUserId) {
          debugPrint(
            '[BackgroundSync] Account mismatch in background worker. Pausing sync for $passedUserId.',
          );
          return Future.value(true);
        }
        activeUserId ??= passedUserId;
      }

      if (activeUserId == null || activeUserId.isEmpty) {
        debugPrint('[BackgroundSync] No authenticated user found for background sync. Skipping.');
        return Future.value(true);
      }

      // 3. Execute authoritative sync across both outboxes
      final coordinator = SyncCoordinator.instance;
      final result = await coordinator.syncAll(
        userId: activeUserId,
        apiService: ApiService.instance,
        supabaseService: SupabaseService.instance,
      );

      debugPrint(
        '[BackgroundSync] Completed: synced=${result.totalSynced}, failed=${result.totalFailed}, skipped=${result.totalSkipped}',
      );
      return Future.value(true);
    } catch (e, stack) {
      debugPrint('[BackgroundSync] Unhandled error during background sync: $e\n$stack');
      return Future.value(false);
    }
  });
}

class BackgroundSyncManager {
  static bool _isRegistered = false;
  static bool get isRegistered => _isRegistered;

  /// Returns true if the current platform natively supports Workmanager.
  static bool get isSupportedPlatform {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  /// Registers OS-scheduled background synchronization workers on supported platforms.
  static Future<bool> registerBackgroundSync({String? currentUserId}) async {
    if (!isSupportedPlatform) {
      debugPrint(
        '[BackgroundSyncManager] Platform does not support native background workers. Relying on foreground sync triggers.',
      );
      return false;
    }

    try {
      await Workmanager().initialize(
        librisBackgroundSyncCallbackDispatcher,
        isInDebugMode: kDebugMode,
      );

      // Register periodic sync (OS minimum is typically 15 minutes)
      await Workmanager().registerPeriodicTask(
        kLibrisPeriodicSyncTask,
        kLibrisPeriodicSyncTask,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: true,
        ),
        existingWorkPolicy: ExistingWorkPolicy.keep,
        inputData: currentUserId != null ? {'userId': currentUserId} : null,
      );

      _isRegistered = true;
      debugPrint('[BackgroundSyncManager] Background sync registered successfully.');
      return true;
    } catch (e) {
      debugPrint('[BackgroundSyncManager] Failed to register background sync: $e');
      return false;
    }
  }

  /// Schedules a best-effort one-off background sync task when connectivity is restored
  /// or when the app is moving to the background.
  static Future<void> scheduleImmediateSync({required String userId}) async {
    if (!isSupportedPlatform) return;

    try {
      await Workmanager().registerOneOffTask(
        '${kLibrisOneOffSyncTask}_${DateTime.now().millisecondsSinceEpoch}',
        kLibrisOneOffSyncTask,
        constraints: Constraints(networkType: NetworkType.connected),
        inputData: {'userId': userId},
      );
      debugPrint('[BackgroundSyncManager] One-off sync task scheduled for user $userId.');
    } catch (e) {
      debugPrint('[BackgroundSyncManager] Failed to schedule one-off sync: $e');
    }
  }

  /// Cancels scheduled background tasks (e.g., when the user logs out).
  static Future<void> cancelAll() async {
    if (!isSupportedPlatform) return;
    try {
      await Workmanager().cancelAll();
      _isRegistered = false;
      debugPrint('[BackgroundSyncManager] All background sync tasks cancelled.');
    } catch (e) {
      debugPrint('[BackgroundSyncManager] Failed to cancel tasks: $e');
    }
  }
}
