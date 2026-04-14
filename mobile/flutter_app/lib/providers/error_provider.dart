import 'package:flutter/material.dart';
import '../services/analytics_service.dart';

class ErrorProvider extends ChangeNotifier {
  String? _currentError;

  String? get currentError => _currentError;

  void showError(String message) {
    _currentError = message;
    AnalyticsService.instance.logError(message);
    notifyListeners();
  }

  void clearError() {
    _currentError = null;
    notifyListeners();
  }
}
