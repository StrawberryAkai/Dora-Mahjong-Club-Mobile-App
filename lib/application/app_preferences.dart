import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device preferences are independent of the currently selected club member.
class AppPreferences extends ChangeNotifier {
  AppPreferences({
    bool isEnglish = false,
    bool isDark = false,
    SharedPreferences? storage,
  }) : _isEnglish = isEnglish,
       _isDark = isDark,
       _storage = storage;

  factory AppPreferences.fromPreferences(SharedPreferences storage) {
    try {
      final saved = storage.getString(storageKey);
      if (saved != null) {
        final values = jsonDecode(saved) as Map<String, dynamic>;
        return AppPreferences(
          isEnglish: values['language'] == 'en',
          isDark: values['dark'] == true,
          storage: storage,
        );
      }
    } on FormatException {
      // An invalid preference must not prevent access to the club.
    } on TypeError {
      // Ignore values left by an incompatible or damaged preference file.
    }
    return AppPreferences(storage: storage);
  }

  static const storageKey = 'dora.preferences.v1';
  final SharedPreferences? _storage;
  bool _isEnglish;
  bool _isDark;
  bool _disposed = false;
  bool _saveFailed = false;
  Future<void> _pendingSave = Future<void>.value();

  bool get isEnglish => _isEnglish;
  bool get isDark => _isDark;
  bool get saveFailed => _saveFailed;
  Locale get locale =>
      isEnglish ? const Locale('en') : const Locale('zh', 'CN');
  ThemeMode get themeMode => isDark ? ThemeMode.dark : ThemeMode.light;

  Future<void> toggleLanguage() {
    _isEnglish = !_isEnglish;
    return _changed();
  }

  Future<void> toggleTheme() {
    _isDark = !_isDark;
    return _changed();
  }

  Future<void> _changed() {
    _saveFailed = false;
    notifyListeners();
    final storage = _storage;
    if (storage == null) return Future<void>.value();
    final encoded = jsonEncode({
      'language': isEnglish ? 'en' : 'zh',
      'dark': isDark,
    });
    // Serialize complete snapshots so rapid taps cannot restore an older choice.
    _pendingSave = _pendingSave.then((_) async {
      var failed = false;
      try {
        failed = !await storage.setString(storageKey, encoded);
      } catch (_) {
        failed = true;
      }
      if (!_disposed && _saveFailed != failed) {
        _saveFailed = failed;
        notifyListeners();
      }
    });
    return _pendingSave;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Above MaterialApp so preferences also rebuild open modal routes.
class AppPreferencesScope extends InheritedNotifier<AppPreferences> {
  const AppPreferencesScope({
    super.key,
    required AppPreferences preferences,
    required super.child,
  }) : super(notifier: preferences);

  static AppPreferences of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<AppPreferencesScope>();
    assert(scope != null, 'AppPreferencesScope must wrap the application.');
    return scope!.notifier!;
  }
}
