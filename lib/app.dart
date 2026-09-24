import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'application/club_controller.dart';
import 'application/app_preferences.dart';
import 'presentation/dora_app.dart';

/// The public application entry point used by the platform bootstrap.
class DoraApp extends StatefulWidget {
  const DoraApp({super.key, required this.controller, this.preferences});

  final ClubController controller;
  final AppPreferences? preferences;

  @override
  State<DoraApp> createState() => _DoraAppState();
}

class _DoraAppState extends State<DoraApp> {
  late AppPreferences _preferences;

  @override
  void initState() {
    super.initState();
    _preferences = widget.preferences ?? AppPreferences();
  }

  @override
  void didUpdateWidget(DoraApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.preferences != widget.preferences) {
      if (oldWidget.preferences == null) _preferences.dispose();
      _preferences = widget.preferences ?? AppPreferences();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppPreferencesScope(
      preferences: _preferences,
      child: ListenableBuilder(
        listenable: _preferences,
        builder: (context, _) => MaterialApp(
          title: 'Dora Helper',
          debugShowCheckedModeBanner: false,
          locale: _preferences.locale,
          supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: DoraTheme.light,
          darkTheme: DoraTheme.dark,
          themeMode: _preferences.themeMode,
          themeAnimationDuration: const Duration(milliseconds: 300),
          themeAnimationCurve: Curves.easeInOutCubic,
          home: DoraHome(controller: widget.controller),
        ),
      ),
    );
  }

  @override
  void dispose() {
    if (widget.preferences == null) _preferences.dispose();
    super.dispose();
  }
}
