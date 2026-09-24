import 'dart:convert';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'application/app_preferences.dart';
import 'application/club_controller.dart';
import 'data/club_repository.dart';
import 'data/demo_club_repository.dart';
import 'data/supabase_club_repository.dart';
import 'domain/models.dart';
import 'platform/app_exit.dart';

/// Wires configuration, device preferences, and the repository. Both app modes
/// expose the same controller to the UI.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(isOptional: true);
    final mode = dotenv.maybeGet('APP_MODE')?.trim() ?? 'local';
    final preferences = await SharedPreferences.getInstance();
    final appPreferences = AppPreferences.fromPreferences(preferences);
    final ClubRepository repository;
    if (mode == 'local') {
      // Local snapshots are never uploaded. Keep the legacy storage key so
      // renaming the mode does not discard existing demo data.
      final encoded = preferences.getString('dora.demo.v1');
      Map<String, dynamic>? saved;
      if (encoded != null) {
        try {
          saved = Map<String, dynamic>.from(jsonDecode(encoded) as Map);
        } catch (_) {
          throw const FormatException('本地演示数据无法读取。请清除应用演示数据后重试。');
        }
      }
      repository = DemoClubRepository(
        saved: saved,
        persist: (data) async {
          final success = await preferences.setString(
            'dora.demo.v1',
            jsonEncode(data),
          );
          if (!success) throw StateError('Unable to persist demo data');
        },
      );
    } else if (mode == 'development') {
      // .env is bundled and readable by clients; only public keys belong here.
      final url = dotenv.maybeGet('SUPABASE_URL')?.trim() ?? '';
      final key = dotenv.maybeGet('SUPABASE_PUBLISHABLE_KEY')?.trim() ?? '';
      final uri = Uri.tryParse(url);
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host.isEmpty ||
          key.isEmpty) {
        throw const FormatException(
          '请在 .env 中填写 Supabase 项目地址和公开连接密钥，或将 APP_MODE 设为 local。',
        );
      }
      if (!key.startsWith('sb_publishable_')) {
        throw const FormatException(
          '请使用以 sb_publishable_ 开头的公开连接密钥；管理员或服务端密钥不能放入移动端。',
        );
      }
      await Supabase.initialize(url: url, publishableKey: key);
      repository = SupabaseClubRepository(
        Supabase.instance.client,
        supabaseUrl: url,
        publishableKey: key,
      );
    } else {
      throw const FormatException('APP_MODE 仅支持 local 或 development。');
    }
    final controller = ClubController(repository);
    runApp(_AppLifecycle(controller: controller, preferences: appPreferences));
    await controller.initialize();
  } catch (error) {
    runApp(
      _StartupFailure(
        message: error is FormatException
            ? error.message
            : error is ClubException
            ? '${error.message}。原始数据已保留，请先核对数据版本和配置。'
            : '应用暂时无法启动。请检查配置后重试。',
      ),
    );
  }
}

class _AppLifecycle extends StatefulWidget {
  const _AppLifecycle({required this.controller, required this.preferences});
  final ClubController controller;
  final AppPreferences preferences;
  @override
  State<_AppLifecycle> createState() => _AppLifecycleState();
}

class _AppLifecycleState extends State<_AppLifecycle>
    with WidgetsBindingObserver {
  late final void Function() _unregisterAppExit;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _unregisterAppExit = registerAppExit(widget.controller.onAppClosing);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Backgrounding stops polling and lease renewal. The repository/server
    // decides whether a seat can be released based on the game's state.
    // Exit callbacks are not guaranteed, so lease expiry remains necessary.
    switch (state) {
      case AppLifecycleState.resumed:
        widget.controller.setForeground(true);
        widget.controller.refresh(quiet: true);
        break;
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        widget.controller.setForeground(false);
        break;
      case AppLifecycleState.detached:
        widget.controller.onAppClosing();
        break;
      case AppLifecycleState.inactive:
        // Inactive is a transient interruption (for example, a system dialog)
        // and should not pause presence renewal or release the seat.
        break;
    }
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    widget.controller.onAppClosing();
    return AppExitResponse.exit;
  }

  @override
  Widget build(BuildContext context) =>
      DoraApp(controller: widget.controller, preferences: widget.preferences);
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _unregisterAppExit();
    widget.controller.dispose();
    widget.preferences.dispose();
    super.dispose();
  }
}

class _StartupFailure extends StatelessWidget {
  const _StartupFailure({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff234d3c)),
    ),
    home: Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.settings_outlined, size: 48),
                  const SizedBox(height: 24),
                  Text(
                    '启动需要一点准备',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),
                  Text(message, textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  FilledButton(onPressed: main, child: const Text('重试')),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
