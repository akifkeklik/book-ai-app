import 'package:intl/intl.dart';

/// Formats [date] as a short localized date (e.g. "13 Nov 2026", "13 kas 2026").
/// Never throws: if locale data is not initialized, falls back to the default locale.
String formatShortDate(DateTime date, String languageCode) {
  try {
    return DateFormat.yMMMd(languageCode).format(date);
  } catch (_) {
    return DateFormat.yMMMd().format(date);
  }
}
