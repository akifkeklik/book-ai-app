import 'package:flutter/foundation.dart';

class AnalyticsService {
  AnalyticsService._internal();

  static final AnalyticsService instance = AnalyticsService._internal();

  void logEvent(String eventName, [Map<String, dynamic>? parameters]) {
    if (kDebugMode) {
      debugPrint('[Analytics] Event: $eventName | Params: $parameters');
    }
  }

  void logError(dynamic exception, [StackTrace? stackTrace]) {
    if (kDebugMode) {
      debugPrint('[Analytics] Error: $exception\nStackTrace: $stackTrace');
    }
  }
}
