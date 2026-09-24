import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dora_mahjong/application/app_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('round trips language and theme through device preferences', () async {
    final storage = await SharedPreferences.getInstance();
    final preferences = AppPreferences(storage: storage);
    addTearDown(preferences.dispose);

    await preferences.toggleLanguage();
    await preferences.toggleTheme();

    expect(preferences.isEnglish, isTrue);
    expect(preferences.isDark, isTrue);
    expect(preferences.locale, const Locale('en'));
    expect(preferences.themeMode, ThemeMode.dark);

    final restored = AppPreferences.fromPreferences(storage);
    addTearDown(restored.dispose);
    expect(restored.isEnglish, isTrue);
    expect(restored.isDark, isTrue);
    expect(restored.locale, const Locale('en'));
    expect(restored.themeMode, ThemeMode.dark);
  });

  test(
    'rapid toggles persist the final complete preference snapshot',
    () async {
      final storage = await SharedPreferences.getInstance();
      final preferences = AppPreferences(storage: storage);
      addTearDown(preferences.dispose);

      // Start both writes before awaiting either one. This models quick taps on
      // the two settings while each write is still queued.
      final writes = <Future<void>>[
        preferences.toggleLanguage(),
        preferences.toggleTheme(),
        preferences.toggleLanguage(),
        preferences.toggleTheme(),
        preferences.toggleLanguage(),
      ];
      await Future.wait(writes);

      expect(preferences.isEnglish, isTrue);
      expect(preferences.isDark, isFalse);

      final restored = AppPreferences.fromPreferences(storage);
      addTearDown(restored.dispose);
      expect(restored.isEnglish, isTrue);
      expect(restored.isDark, isFalse);
    },
  );
}
