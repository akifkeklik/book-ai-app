import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:book_ai_app/providers/language_provider.dart';

/// Guards every shipped language against missing keys, broken placeholders,
/// empty strings, and keys that the code uses but no language defines.
void main() {
  Map<String, String> load(String code) {
    final raw = jsonDecode(File('assets/lang/$code.json').readAsStringSync()) as Map<String, dynamic>;
    return raw.map((k, v) => MapEntry(k, v.toString()));
  }

  Set<String> placeholders(String value) =>
      RegExp(r'\{(\w+)\}').allMatches(value).map((m) => m.group(1)!).toSet();

  final en = load('en');

  test('every supported language has a translation file', () {
    for (final code in LanguageProvider.supportedLanguages) {
      expect(File('assets/lang/$code.json').existsSync(), isTrue, reason: 'missing assets/lang/$code.json');
    }
  });

  for (final code in LanguageProvider.supportedLanguages.where((c) => c != 'en')) {
    group('$code.json', () {
      final strings = load(code);

      test('has exactly the same keys as en.json', () {
        expect(en.keys.toSet().difference(strings.keys.toSet()), isEmpty, reason: 'missing keys');
        expect(strings.keys.toSet().difference(en.keys.toSet()), isEmpty, reason: 'unknown keys');
      });

      test('keeps every placeholder of en.json', () {
        final broken = <String>[];
        en.forEach((key, value) {
          final translated = strings[key];
          if (translated != null && !setEquals(placeholders(value), placeholders(translated))) {
            broken.add(key);
          }
        });
        expect(broken, isEmpty, reason: 'placeholder mismatch');
      });

      test('has no empty values', () {
        expect(strings.entries.where((e) => e.value.trim().isEmpty).map((e) => e.key), isEmpty);
      });
    });
  }

  test('every translation key used in lib/ is defined in en.json', () {
    final used = <String>{};
    final keyCall = RegExp(r"""(?:\.tr|translate|trPlural)\(\s*'([a-z0-9_]+)'""");
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      used.addAll(keyCall.allMatches(file.readAsStringSync()).map((m) => m.group(1)!));
    }
    final pluralBases = en.keys
        .where((k) => k.endsWith('_one') || k.endsWith('_other'))
        .map((k) => k.replaceAll(RegExp(r'_(one|other)$'), ''))
        .toSet();
    final undefined = used.where((k) => !en.containsKey(k) && !pluralBases.contains(k)).toList()..sort();
    expect(undefined, isEmpty, reason: 'keys used in code but not defined');
  });
}

bool setEquals(Set<String> a, Set<String> b) => a.length == b.length && a.containsAll(b);
