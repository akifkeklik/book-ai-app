import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Localization Parity & Integrity Tests (EN, TR, DE)', () {
    late Map<String, dynamic> enJson;
    late Map<String, dynamic> trJson;
    late Map<String, dynamic> deJson;

    setUpAll(() {
      final enFile = File('assets/lang/en.json');
      final trFile = File('assets/lang/tr.json');
      final deFile = File('assets/lang/de.json');

      expect(enFile.existsSync(), isTrue, reason: 'assets/lang/en.json must exist');
      expect(trFile.existsSync(), isTrue, reason: 'assets/lang/tr.json must exist');
      expect(deFile.existsSync(), isTrue, reason: 'assets/lang/de.json must exist');

      enJson = jsonDecode(enFile.readAsStringSync()) as Map<String, dynamic>;
      trJson = jsonDecode(trFile.readAsStringSync()) as Map<String, dynamic>;
      deJson = jsonDecode(deFile.readAsStringSync()) as Map<String, dynamic>;
    });

    test('100% key parity between English and Turkish', () {
      final enKeys = enJson.keys.toSet();
      final trKeys = trJson.keys.toSet();

      final missingInTr = enKeys.difference(trKeys);
      final extraInTr = trKeys.difference(enKeys);

      expect(missingInTr, isEmpty, reason: 'Keys in EN but missing in TR: $missingInTr');
      expect(extraInTr, isEmpty, reason: 'Keys in TR but missing in EN: $extraInTr');
      expect(enKeys.length, equals(trKeys.length));
    });

    test('100% key parity between English and German', () {
      final enKeys = enJson.keys.toSet();
      final deKeys = deJson.keys.toSet();

      final missingInDe = enKeys.difference(deKeys);
      final extraInDe = deKeys.difference(enKeys);

      expect(missingInDe, isEmpty, reason: 'Keys in EN but missing in DE: $missingInDe');
      expect(extraInDe, isEmpty, reason: 'Keys in DE but missing in EN: $extraInDe');
      expect(enKeys.length, equals(deKeys.length));
    });

    test('Zero empty string values in any language file', () {
      for (final entry in enJson.entries) {
        expect(entry.value.toString().trim(), isNotEmpty,
            reason: 'EN key "${entry.key}" must not be empty');
      }
      for (final entry in trJson.entries) {
        expect(entry.value.toString().trim(), isNotEmpty,
            reason: 'TR key "${entry.key}" must not be empty');
      }
      for (final entry in deJson.entries) {
        expect(entry.value.toString().trim(), isNotEmpty,
            reason: 'DE key "${entry.key}" must not be empty');
      }
    });

    test('Placeholder parameter integrity across languages', () {
      final placeholderRegex = RegExp(r'\{[a-zA-Z0-9_]+\}');

      for (final key in enJson.keys) {
        final enVal = enJson[key].toString();
        final enPlaceholders = placeholderRegex.allMatches(enVal).map((m) => m.group(0)!).toSet();

        if (enPlaceholders.isNotEmpty) {
          final trVal = trJson[key].toString();
          final deVal = deJson[key].toString();

          final trPlaceholders = placeholderRegex.allMatches(trVal).map((m) => m.group(0)!).toSet();
          final dePlaceholders = placeholderRegex.allMatches(deVal).map((m) => m.group(0)!).toSet();

          expect(trPlaceholders, equals(enPlaceholders),
              reason: 'TR placeholder mismatch in key "$key": EN=$enPlaceholders vs TR=$trPlaceholders');
          expect(dePlaceholders, equals(enPlaceholders),
              reason: 'DE placeholder mismatch in key "$key": EN=$enPlaceholders vs DE=$dePlaceholders');
        }
      }
    });

    test('Core personalized reader journey keys present in all languages', () {
      const criticalKeys = [
        'app_name',
        'taste_profile',
        'taste_profile_saved',
        'select_genres_hint',
        'skip',
        'skip_for_now',
        'continue_journey',
        'your_reading_list',
        'because_you_enjoy',
        'popular_books',
        'for_you',
        'reading',
        'want_to_read',
        'finished',
        'favorites_title',
      ];

      for (final k in criticalKeys) {
        expect(enJson.containsKey(k), isTrue, reason: 'Critical key "$k" missing in EN');
        expect(trJson.containsKey(k), isTrue, reason: 'Critical key "$k" missing in TR');
        expect(deJson.containsKey(k), isTrue, reason: 'Critical key "$k" missing in DE');
      }
    });

    test('Zero corrupted question mark characters in translations across all languages', () {
      final dictionaries = {'EN': enJson, 'TR': trJson, 'DE': deJson};
      for (final entry in dictionaries.entries) {
        final lang = entry.key;
        final dict = entry.value;
        for (final item in dict.entries) {
          final str = item.value.toString();
          if (str.contains('?')) {
            // A legitimate question mark can only be at the end of a question sentence (e.g. "Bir hata mı buldun?")
            final trimmed = str.trim();
            expect(
              trimmed.endsWith('?') && !trimmed.substring(0, trimmed.length - 1).contains('?'),
              isTrue,
              reason: '$lang key "${item.key}" has corrupted question mark within text: "$str"',
            );
          }
        }
      }
    });
  });
}

