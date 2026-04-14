import 'package:flutter/foundation.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

class AnalyticsService {
  AnalyticsService._internal();

  static final AnalyticsService instance = AnalyticsService._internal();

  void logEvent(String eventName, [Map<String, dynamic>? parameters]) {
    if (kDebugMode) {
      debugPrint('[Analytics] Event: $eventName | Params: $parameters');
    }
    try {
      if (!kIsWeb) {
         FirebaseAnalytics.instance.logEvent(name: eventName, parameters: parameters?.cast<String, Object>());
      }
    } catch (_) {}
  }

  void logError(dynamic exception, [StackTrace? stackTrace]) {
    if (kDebugMode) {
      debugPrint('[Analytics] Error: $exception\nStackTrace: $stackTrace');
    }
    try {
      if (!kIsWeb) {
         FirebaseCrashlytics.instance.recordError(exception, stackTrace);
      }
    } catch (_) {}
  }
}
