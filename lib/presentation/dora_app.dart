import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../application/app_preferences.dart';
import '../application/club_controller.dart';
import '../domain/models.dart';
import '../domain/rules.dart';
import 'event_pages.dart';
import 'leaderboard_page.dart';
import 'localization.dart';
import 'rating_widgets.dart';
import 'start_game_sheet.dart';

const _ink = Color(0xFF17231D);
const _forest = Color(0xFF234D3C);
const _forestSoft = Color(0xFFE6EEE8);
const _lime = Color(0xFFDCEA9C);
const _paper = Color(0xFFF6F5F0);
const _paperDeep = Color(0xFFECEBE4);
const _line = Color(0xFFD9DCD4);
const _muted = Color(0xFF68736C);
const _warning = Color(0xFFB86B28);
const _danger = Color(0xFFB4493D);

/// Theme-owned colors used by cards, tables and sheets throughout the app.
/// Keeping these colors in a theme extension means an open modal route and the
/// main route use the same palette while the user switches modes.
@immutable
class DoraPalette extends ThemeExtension<DoraPalette> {
  const DoraPalette({
    required this.ink,
    required this.forest,
    required this.forestSoft,
    required this.lime,
    required this.paper,
    required this.paperDeep,
    required this.line,
    required this.muted,
    required this.warning,
    required this.danger,
    required this.card,
    required this.onForest,
    required this.onLime,
    required this.errorSoft,
    required this.warningSoft,
  });

  final Color ink;
  final Color forest;
  final Color forestSoft;
  final Color lime;
  final Color paper;
  final Color paperDeep;
  final Color line;
  final Color muted;
  final Color warning;
  final Color danger;
  final Color card;
  final Color onForest;
  final Color onLime;
  final Color errorSoft;
  final Color warningSoft;

  @override
  DoraPalette copyWith({
    Color? ink,
    Color? forest,
    Color? forestSoft,
    Color? lime,
    Color? paper,
    Color? paperDeep,
    Color? line,
    Color? muted,
    Color? warning,
    Color? danger,
    Color? card,
    Color? onForest,
    Color? onLime,
    Color? errorSoft,
    Color? warningSoft,
  }) {
    return DoraPalette(
      ink: ink ?? this.ink,
      forest: forest ?? this.forest,
      forestSoft: forestSoft ?? this.forestSoft,
      lime: lime ?? this.lime,
      paper: paper ?? this.paper,
      paperDeep: paperDeep ?? this.paperDeep,
      line: line ?? this.line,
      muted: muted ?? this.muted,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      card: card ?? this.card,
      onForest: onForest ?? this.onForest,
      onLime: onLime ?? this.onLime,
      errorSoft: errorSoft ?? this.errorSoft,
      warningSoft: warningSoft ?? this.warningSoft,
    );
  }

  @override
  DoraPalette lerp(ThemeExtension<DoraPalette>? other, double t) {
    if (other is! DoraPalette) return this;
    return DoraPalette(
      ink: Color.lerp(ink, other.ink, t)!,
      forest: Color.lerp(forest, other.forest, t)!,
      forestSoft: Color.lerp(forestSoft, other.forestSoft, t)!,
      lime: Color.lerp(lime, other.lime, t)!,
      paper: Color.lerp(paper, other.paper, t)!,
      paperDeep: Color.lerp(paperDeep, other.paperDeep, t)!,
      line: Color.lerp(line, other.line, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      card: Color.lerp(card, other.card, t)!,
      onForest: Color.lerp(onForest, other.onForest, t)!,
      onLime: Color.lerp(onLime, other.onLime, t)!,
      errorSoft: Color.lerp(errorSoft, other.errorSoft, t)!,
      warningSoft: Color.lerp(warningSoft, other.warningSoft, t)!,
    );
  }
}

extension DoraThemeContext on BuildContext {
  DoraPalette get doraPalette =>
      Theme.of(this).extension<DoraPalette>() ??
      const DoraPalette(
        ink: _ink,
        forest: _forest,
        forestSoft: _forestSoft,
        lime: _lime,
        paper: _paper,
        paperDeep: _paperDeep,
        line: _line,
        muted: _muted,
        warning: _warning,
        danger: _danger,
        card: Colors.white,
        onForest: Colors.white,
        onLime: _forest,
        errorSoft: Color(0xFFFFE7E2),
        warningSoft: Color(0xFFFFE8CD),
      );
}

class DoraTheme {
  static ThemeData get light {
    return _build(
      Brightness.light,
      const DoraPalette(
        ink: _ink,
        forest: _forest,
        forestSoft: _forestSoft,
        lime: _lime,
        paper: _paper,
        paperDeep: _paperDeep,
        line: _line,
        muted: _muted,
        warning: _warning,
        danger: _danger,
        card: Colors.white,
        onForest: Colors.white,
        onLime: _forest,
        errorSoft: Color(0xFFFFE7E2),
        warningSoft: Color(0xFFFFE8CD),
      ),
    );
  }

  static ThemeData get dark {
    return _build(
      Brightness.dark,
      const DoraPalette(
        ink: Color(0xFFE8F1EA),
        forest: Color(0xFF8FD0A9),
        forestSoft: Color(0xFF203C2E),
        lime: Color(0xFFD8E98E),
        paper: Color(0xFF111814),
        paperDeep: Color(0xFF1A241E),
        line: Color(0xFF35463A),
        muted: Color(0xFFA6B6AA),
        warning: Color(0xFFF3B56B),
        danger: Color(0xFFFFB4AB),
        card: Color(0xFF19231D),
        onForest: Color(0xFF122017),
        onLime: Color(0xFF17231D),
        errorSoft: Color(0xFF482621),
        warningSoft: Color(0xFF49351F),
      ),
    );
  }

  static ThemeData _build(Brightness brightness, DoraPalette palette) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _forest,
      brightness: brightness,
      surface: palette.paper,
      surfaceContainerLowest: palette.paper,
      surfaceContainerLow: palette.paperDeep,
      surfaceContainer: palette.card,
      surfaceContainerHigh: palette.paperDeep,
      primary: palette.forest,
      onPrimary: palette.onForest,
      secondary: palette.lime,
      onSecondary: palette.onLime,
      error: palette.danger,
      onError: palette.onForest,
    );
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    return base.copyWith(
      scaffoldBackgroundColor: palette.paper,
      canvasColor: palette.paper,
      dividerColor: palette.line,
      splashColor: palette.forest.withValues(alpha: .08),
      highlightColor: palette.forest.withValues(alpha: .04),
      extensions: [palette],
      textTheme: base.textTheme.copyWith(
        displayLarge: const TextStyle(
          fontWeight: FontWeight.w700,
          letterSpacing: -2.2,
        ).copyWith(color: palette.ink),
        displayMedium: const TextStyle(
          fontWeight: FontWeight.w700,
          letterSpacing: -1.5,
        ).copyWith(color: palette.ink),
        headlineSmall: const TextStyle(
          fontWeight: FontWeight.w700,
          letterSpacing: -.4,
        ).copyWith(color: palette.ink),
        titleLarge: TextStyle(
          color: palette.ink,
          fontWeight: FontWeight.w700,
          letterSpacing: -.25,
        ),
        titleMedium: TextStyle(color: palette.ink, fontWeight: FontWeight.w700),
        bodyLarge: TextStyle(color: palette.ink, height: 1.4),
        bodyMedium: TextStyle(color: palette.ink, height: 1.35),
        bodySmall: TextStyle(color: palette.muted, height: 1.3),
        labelLarge: const TextStyle(fontWeight: FontWeight.w700),
        labelMedium: const TextStyle(
          fontWeight: FontWeight.w700,
          letterSpacing: .1,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: palette.paper,
        foregroundColor: palette.ink,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: palette.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: palette.line),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.card,
        hintStyle: TextStyle(color: palette.muted),
        labelStyle: TextStyle(color: palette.muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: palette.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: palette.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: palette.forest, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: palette.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: palette.danger, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: palette.card,
        indicatorColor: palette.lime,
        elevation: 0,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? palette.onLime
                : palette.muted,
          ),
        ),
        labelTextStyle: WidgetStatePropertyAll(base.textTheme.labelMedium),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: palette.forestSoft,
        side: BorderSide.none,
        labelStyle: TextStyle(
          color: palette.forest,
          fontWeight: FontWeight.w700,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      ),
    );
  }
}

class DoraHome extends StatefulWidget {
  const DoraHome({super.key, required this.controller});

  final ClubController controller;

  @override
  State<DoraHome> createState() => _DoraHomeState();
}

class _DoraHomeState extends State<DoraHome> {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final snapshot = widget.controller.snapshot;
        final isEmpty = snapshot.rooms.isEmpty && snapshot.members.isEmpty;
        if (widget.controller.loading && isEmpty) return const _LoadingPage();
        if (widget.controller.error != null && isEmpty) {
          return _ErrorPage(controller: widget.controller);
        }
        if (!widget.controller.isAdmin && widget.controller.member == null) {
          return _MemberEntryPage(controller: widget.controller);
        }
        return _DoraShell(controller: widget.controller);
      },
    );
  }
}

class _LoadingPage extends StatelessWidget {
  const _LoadingPage();

  @override
  Widget build(BuildContext context) {
    final palette = context.doraPalette;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _MahjongMark(size: 84),
              const SizedBox(height: 26),
              Text(
                'Dora Helper',
                style: Theme.of(
                  context,
                ).textTheme.headlineSmall?.copyWith(letterSpacing: 1),
              ),
              const SizedBox(height: 8),
              Text(
                context.t('正在准备牌桌', 'Preparing the tables'),
                style: TextStyle(color: palette.muted),
              ),
              const SizedBox(height: 28),
              const SizedBox(
                width: 90,
                child: LinearProgressIndicator(minHeight: 3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorPage extends StatelessWidget {
  const _ErrorPage({required this.controller});

  final ClubController controller;

  @override
  Widget build(BuildContext context) {
    final palette = context.doraPalette;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded, size: 44, color: palette.forest),
              const SizedBox(height: 18),
              Text(
                context.t('暂时无法打开俱乐部', 'The club is temporarily unavailable'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                controller.error == null
                    ? context.t(
                        '请检查网络后重试',
                        'Check your connection and try again',
                      )
                    : doraMessage(context, controller.error!),
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.muted),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: controller.loading
                    ? null
                    : () => controller.refresh(),
                icon: const Icon(Icons.refresh_rounded),
                label: Text(context.t('重试', 'Retry')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Members select a name; administrators use a separate sign-in flow. A name
/// is not an authentication credential. The logo/language header stays fixed,
/// and an empty search does not expose the full member list.
class _MemberEntryPage extends StatefulWidget {
  const _MemberEntryPage({required this.controller});

  final ClubController controller;

  @override
  State<_MemberEntryPage> createState() => _MemberEntryPageState();
}

class _MemberEntryPageState extends State<_MemberEntryPage> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _createMember() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreateMemberSheet(controller: widget.controller),
    );
    if (created == true && mounted) {
      _searchController.clear();
      setState(() => _query = '');
    }
  }

  Future<void> _adminLogin() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AdminLoginSheet(controller: widget.controller),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.doraPalette;
    final preferences = AppPreferencesScope.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/images/club_logo.png',
                    width: 68,
                    height: 68,
                    fit: BoxFit.contain,
                    semanticLabel: strings.text(
                      'UCSD 麻将社',
                      'Dora Mahjong Club',
                    ),
                  ),
                  const Spacer(),
                  if (widget.controller.isDemo) ...[
                    const _DemoPill(),
                    const SizedBox(width: 12),
                  ],
                  _PreferenceToggleButton(
                    key: const ValueKey('toggle-language'),
                    active: preferences.isEnglish,
                    icon: Icons.translate_rounded,
                    label: preferences.isEnglish
                        ? strings.text('切换为中文', 'Switch to Chinese')
                        : strings.text('切换为 English', 'Switch to English'),
                    onPressed: preferences.toggleLanguage,
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(22, 26, 22, 36),
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            strings.text('选择成员', 'Choose a member'),
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            strings.text(
                              '姓名只用于俱乐部内识别，不需要密码。',
                              'Your name is only used within the club; no password is needed.',
                            ),
                            style: TextStyle(
                              color: palette.muted,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 30),
                      if (widget.controller.isDemo) ...[
                        _DemoBanner(onAdmin: _adminLogin),
                        const SizedBox(height: 18),
                      ],
                      TextField(
                        controller: _searchController,
                        onChanged: (value) => setState(() => _query = value),
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search_rounded),
                          hintText: strings.text(
                            '按姓名首字搜索已有成员',
                            'Search members by first letter',
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      ListenableBuilder(
                        listenable: widget.controller,
                        builder: (context, _) {
                          final normalized = _query.trim().toLowerCase();
                          // Keep the entry page calm until the user asks for a
                          // result. Clearing the field intentionally hides the
                          // list again so a long member directory never becomes a
                          // surprise scrolling surface.
                          if (normalized.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          final matches = widget.controller.snapshot.members
                              .where(
                                (member) => member.name
                                    .toLowerCase()
                                    .startsWith(normalized),
                              )
                              .toList();
                          if (matches.isEmpty) {
                            return _EmptyState(
                              icon: Icons.person_search_rounded,
                              title: strings.text('没有找到成员', 'No members found'),
                              body: normalized.isEmpty
                                  ? strings.text(
                                      '先创建一个俱乐部成员。',
                                      'Create a club member first.',
                                    )
                                  : strings.text(
                                      '试试其他首字，或直接创建新成员。',
                                      'Try another starting letter, or create a new member.',
                                    ),
                            );
                          }
                          return Column(
                            children: matches
                                .map(
                                  (member) => _MemberResultTile(
                                    member: member,
                                    onTap: () => widget.controller.selectMember(
                                      member.id,
                                    ),
                                  ),
                                )
                                .toList(),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: widget.controller.busy
                            ? null
                            : _createMember,
                        icon: const Icon(Icons.add_rounded),
                        label: Text(strings.text('创建新成员', 'Create member')),
                      ),
                      const SizedBox(height: 24),
                      Center(
                        child: TextButton.icon(
                          onPressed: widget.controller.busy
                              ? null
                              : _adminLogin,
                          icon: const Icon(
                            Icons.lock_outline_rounded,
                            size: 18,
                          ),
                          label: Text(strings.text('管理员入口', 'Admin sign in')),
                        ),
                      ),
                      if (widget.controller.error != null) ...[
                        const SizedBox(height: 10),
                        _FeedbackBanner(
                          message: widget.controller.error!,
                          tone: _FeedbackTone.error,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemberResultTile extends StatelessWidget {
  const _MemberResultTile({required this.member, required this.onTap});

  final Member member;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.doraPalette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: palette.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: palette.line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: palette.lime,
                  foregroundColor: palette.onLime,
                  child: Text(
                    member.name.characters.first.toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    member.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(Icons.arrow_forward_rounded, color: palette.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// UI validation provides immediate feedback. The repository must still check
/// duplicates because concurrent clients can submit the same name.
class _CreateMemberSheet extends StatefulWidget {
  const _CreateMemberSheet({required this.controller});

  final ClubController controller;

  @override
  State<_CreateMemberSheet> createState() => _CreateMemberSheetState();
}

class _CreateMemberSheetState extends State<_CreateMemberSheet> {
  final _nameController = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    final validation = validateName(name);
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    widget.controller.clearFeedback();
    final ok = await widget.controller.createMember(name);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _saving = false;
        _error = widget.controller.error ?? '创建失败，请重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return _SheetFrame(
      eyebrow: 'NEW MEMBER',
      title: strings.text('创建俱乐部成员', 'Create club member'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _nameController,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: strings.text('姓名', 'Name'),
              hintText: strings.text('例如：JIN 或者 近', 'For example: JIN or 近'),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            strings.text(
              '1–20 个中文或英文字母；不含数字、空格或符号。',
              'Use 1–20 Chinese or English letters; no numbers, spaces, or symbols.',
            ),
            style: TextStyle(color: context.doraPalette.muted, fontSize: 12),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            _FeedbackBanner(message: _error!, tone: _FeedbackTone.error),
          ],
          const SizedBox(height: 22),
          FilledButton(
            onPressed: _saving ? null : _submit,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(
                _saving
                    ? strings.text('创建中…', 'Creating…')
                    : strings.text('创建并进入', 'Create and enter'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminLoginSheet extends StatefulWidget {
  const _AdminLoginSheet({required this.controller});

  final ClubController controller;

  @override
  State<_AdminLoginSheet> createState() => _AdminLoginSheetState();
}

class _AdminLoginSheetState extends State<_AdminLoginSheet> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit({bool demo = false}) async {
    final username = demo ? 'demo' : _usernameController.text.trim();
    final password = demo ? 'demo' : _passwordController.text;
    if (!demo && (username.isEmpty || password.isEmpty)) {
      setState(() => _error = '请输入管理员用户名和密码');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    widget.controller.clearFeedback();
    final ok = await widget.controller.signInAdmin(username, password);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _saving = false;
        _error = widget.controller.error ?? '登录失败，请检查账号信息';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return _SheetFrame(
      eyebrow: widget.controller.isDemo ? 'ADMIN / DEMO' : 'ADMIN / SIGN IN',
      title: strings.text('管理员登录', 'Admin sign in'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _usernameController,
            enabled: !_saving,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: strings.text('用户名', 'Username'),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordController,
            enabled: !_saving,
            obscureText: true,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: strings.text('密码', 'Password'),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            _FeedbackBanner(message: _error!, tone: _FeedbackTone.error),
          ],
          const SizedBox(height: 22),
          FilledButton(
            onPressed: _saving ? null : _submit,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(
                _saving
                    ? strings.text('登录中…', 'Signing in…')
                    : strings.text('登录', 'Sign in'),
              ),
            ),
          ),
          if (widget.controller.isDemo) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _saving ? null : () => _submit(demo: true),
              icon: const Icon(Icons.auto_awesome_rounded),
              label: Text(strings.text('体验演示管理员', 'Try demo admin')),
            ),
            const SizedBox(height: 8),
            Text(
              strings.text(
                '演示管理员只会修改本设备上的示例数据。',
                'The demo admin only changes sample data on this device.',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(color: context.doraPalette.muted, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

enum _ShellView { rooms, pending, history, ranking, events, audits }

typedef _ShellLocation = ({
  _ShellView view,
  String? roomId,
  String? gameId,
  String? eventId,
});

class _DoraShell extends StatefulWidget {
  const _DoraShell({required this.controller});

  final ClubController controller;

  @override
  State<_DoraShell> createState() => _DoraShellState();
}

class _DoraShellState extends State<_DoraShell> {
  // Shell-owned history lets system Back restore the last tab or detail page.
  // An empty history leaves the explicitly selected Rooms root in place.
  _ShellLocation _location = (
    view: _ShellView.rooms,
    roomId: null,
    gameId: null,
    eventId: null,
  );
  final List<_ShellLocation> _previousLocations = [];

  void _navigateTo(_ShellLocation next) {
    if (next == _location) return;
    setState(() {
      _previousLocations.add(_location);
      _location = next;
    });
  }

  void _replaceLocation(_ShellLocation next) {
    if (next == _location) return;
    setState(() => _location = next);
  }

  void _goBack() {
    if (_previousLocations.isEmpty) return;
    setState(() => _location = _previousLocations.removeLast());
  }

  void _openRoom(String roomId) => _navigateTo((
    view: _location.view,
    roomId: roomId,
    gameId: null,
    eventId: null,
  ));

  void _openGame(String gameId) => _navigateTo((
    view: _location.view,
    roomId: null,
    gameId: gameId,
    eventId: null,
  ));

  void _goTo(_ShellView view) {
    // A repeated tap on the selected tab must leave an open event detail alone.
    if (_location.view == view &&
        _location.roomId == null &&
        _location.gameId == null) {
      return;
    }
    _navigateTo((view: view, roomId: null, gameId: null, eventId: null));
  }

  void _openEvent(String eventId) => _navigateTo((
    view: _location.view,
    roomId: _location.roomId,
    gameId: _location.gameId,
    eventId: eventId,
  ));

  void _changeEvent(String eventId) => _replaceLocation((
    view: _location.view,
    roomId: _location.roomId,
    gameId: _location.gameId,
    eventId: eventId,
  ));

  void _recoverMissingEvent(_ShellLocation expected, String eventId) {
    if (_location != expected || expected.eventId != eventId) return;
    final eventList = (
      view: expected.view,
      roomId: expected.roomId,
      gameId: expected.gameId,
      eventId: null,
    );
    setState(() {
      // Opening an event from its list put that same list directly underneath.
      // Collapse the pair so recovery does not make Back show the list twice.
      if (_previousLocations.isNotEmpty &&
          _previousLocations.last == eventList) {
        _previousLocations.removeLast();
      }
      _location = eventList;
    });
  }

  Future<void> _showProfile() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProfileSheet(
        controller: widget.controller,
        onAudits: () => _goTo(_ShellView.audits),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goBack();
      },
      child: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final location = _location;
          final hasDetail = location.roomId != null || location.gameId != null;
          Widget body;
          if (location.gameId != null) {
            body = _GameDetailPage(
              controller: widget.controller,
              gameId: location.gameId!,
              onBack: _goBack,
              onOpenRoom: _openRoom,
            );
          } else if (location.roomId != null) {
            body = _RoomDetailPage(
              controller: widget.controller,
              roomId: location.roomId!,
              onBack: _goBack,
              onOpenGame: _openGame,
            );
          } else {
            body = switch (location.view) {
              _ShellView.rooms => _HomePage(
                controller: widget.controller,
                onRoom: _openRoom,
                onPending: () => _goTo(_ShellView.pending),
                onProfile: _showProfile,
              ),
              _ShellView.pending => _PendingPage(
                controller: widget.controller,
                onGame: _openGame,
                onProfile: _showProfile,
              ),
              _ShellView.history => _HistoryPage(
                controller: widget.controller,
                onGame: _openGame,
                onProfile: _showProfile,
              ),
              _ShellView.ranking => LeaderboardPage(
                controller: widget.controller,
                onProfile: _showProfile,
              ),
              _ShellView.events => EventsPage(
                controller: widget.controller,
                selectedEventId: location.eventId,
                onProfile: _showProfile,
                onBack: _goBack,
                onOpenEvent: _openEvent,
                onChangeEvent: _changeEvent,
                onMissingEvent: (eventId) =>
                    _recoverMissingEvent(location, eventId),
              ),
              _ShellView.audits => _AuditPage(
                controller: widget.controller,
                onBack: _goBack,
                onProfile: _showProfile,
              ),
            };
          }
          return Scaffold(
            body: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: KeyedSubtree(
                key: ValueKey<_ShellLocation>(location),
                child: body,
              ),
            ),
            bottomNavigationBar: hasDetail || location.view == _ShellView.audits
                ? null
                : _ShellNavigation(
                    current: location.view,
                    controller: widget.controller,
                    onChanged: _goTo,
                  ),
          );
        },
      ),
    );
  }
}

class _ShellNavigation extends StatelessWidget {
  const _ShellNavigation({
    required this.current,
    required this.controller,
    required this.onChanged,
  });

  final _ShellView current;
  final ClubController controller;
  final ValueChanged<_ShellView> onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final pending = controller.member == null
        ? controller.snapshot.games
              .where((game) => game.status == GameStatus.active)
              .length
        : controller.snapshot.games
              .where(
                (game) =>
                    game.status == GameStatus.active &&
                    game.involves(controller.member!.id),
              )
              .length;
    return NavigationBar(
      selectedIndex: switch (current) {
        _ShellView.rooms => 0,
        _ShellView.pending => 1,
        _ShellView.history => 2,
        _ShellView.ranking => 3,
        _ShellView.events => 4,
        _ShellView.audits => 0,
      },
      onDestinationSelected: (index) => onChanged(switch (index) {
        0 => _ShellView.rooms,
        1 => _ShellView.pending,
        2 => _ShellView.history,
        3 => _ShellView.ranking,
        _ => _ShellView.events,
      }),
      destinations: [
        NavigationDestination(
          icon: Icon(Icons.table_restaurant_outlined),
          selectedIcon: Icon(Icons.table_restaurant_rounded),
          label: strings.text('房间', 'Rooms'),
        ),
        NavigationDestination(
          icon: pending == 0
              ? const Icon(Icons.inbox_outlined)
              : Badge(
                  label: Text('$pending'),
                  child: const Icon(Icons.inbox_outlined),
                ),
          selectedIcon: pending == 0
              ? const Icon(Icons.inbox_rounded)
              : Badge(
                  label: Text('$pending'),
                  child: const Icon(Icons.inbox_rounded),
                ),
          label: strings.text('待录入', 'Pending'),
        ),
        NavigationDestination(
          icon: Icon(Icons.menu_book_outlined),
          selectedIcon: Icon(Icons.menu_book_rounded),
          label: strings.text('记录', 'History'),
        ),
        NavigationDestination(
          icon: Icon(Icons.leaderboard_outlined),
          selectedIcon: Icon(Icons.leaderboard_rounded),
          label: strings.text('排名', 'Ranking'),
        ),
        NavigationDestination(
          icon: Icon(Icons.event_outlined),
          selectedIcon: Icon(Icons.event_rounded),
          label: strings.text('活动', 'Events'),
        ),
      ],
    );
  }
}

class _HomePage extends StatelessWidget {
  const _HomePage({
    required this.controller,
    required this.onRoom,
    required this.onPending,
    required this.onProfile,
  });

  final ClubController controller;
  final ValueChanged<String> onRoom;
  final VoidCallback onPending;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    final activeGames = controller.snapshot.games
        .where((game) => game.status == GameStatus.active)
        .toList();
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            children: [
              _TopBar(
                controller: controller,
                onProfile: onProfile,
                title: 'UCSD 麻将社',
                brand: true,
              ),
              const SizedBox(height: 24),
              if (controller.isDemo)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: _DemoBanner(),
                ),
              if (activeGames.isNotEmpty) ...[
                _Eyebrow(
                  text: controller.isAdmin ? 'LIVE TABLES' : 'YOUR TABLES',
                ),
                const SizedBox(height: 10),
                ...activeGames
                    .take(2)
                    .map(
                      (game) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _ActiveGameCallout(
                          game: game,
                          roomName: controller.snapshot.roomName(game.roomId),
                          onTap: () => onRoom(game.roomId),
                        ),
                      ),
                    ),
                const SizedBox(height: 15),
              ],
              const _Eyebrow(text: 'ROOMS / 02'),
              const SizedBox(height: 10),
              if (controller.snapshot.rooms.isEmpty)
                _EmptyState(
                  icon: Icons.table_restaurant_outlined,
                  title: context.t('还没有房间', 'No rooms yet'),
                  body: context.t(
                    '房间初始化后会出现在这里。',
                    'Rooms will appear here after setup.',
                  ),
                )
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth > 640 ? 2 : 1;
                    final width =
                        (constraints.maxWidth - (columns - 1) * 12) / columns;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: controller.snapshot.rooms
                          .map(
                            (room) => SizedBox(
                              width: width,
                              child: _RoomCard(
                                room: room,
                                snapshot: controller.snapshot,
                                onTap: () => onRoom(room.id),
                              ),
                            ),
                          )
                          .toList(),
                    );
                  },
                ),
              const SizedBox(height: 20),
              if (activeGames.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: onPending,
                  icon: const Icon(Icons.inbox_outlined),
                  label: Text(context.t('查看待录入对局', 'View pending games')),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveGameCallout extends StatelessWidget {
  const _ActiveGameCallout({
    required this.game,
    required this.roomName,
    required this.onTap,
  });

  final ClubGame game;
  final String roomName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.doraPalette;
    final waiting = game.allEntered
        ? (game.needsCorrection
              ? strings.text('总分待纠错', 'Total needs correction')
              : strings.text('准备完成', 'Ready'))
        : strings.isEnglish
        ? '${game.enteredCount}/4 entered'
        : '${game.enteredCount}/4 人已录入';
    return Material(
      color: palette.forest,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(17, 15, 15, 15),
          child: Row(
            children: [
              Icon(Icons.play_circle_outline_rounded, color: palette.onForest),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      roomName,
                      style: TextStyle(
                        color: palette.onForest,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      waiting,
                      style: TextStyle(
                        color: palette.onForest.withValues(alpha: .72),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_rounded,
                color: palette.onForest.withValues(alpha: .72),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  const _RoomCard({
    required this.room,
    required this.snapshot,
    required this.onTap,
  });

  final ClubRoom room;
  final ClubSnapshot snapshot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.doraPalette;
    final game = snapshot.activeGame(room.id);
    return Material(
      color: palette.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: palette.line),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      room.name,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  _StatusPill(
                    text: game == null
                        ? strings.text('空闲', 'Available')
                        : strings.text('对局中', 'In progress'),
                    active: game != null,
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                strings.isEnglish
                    ? '${room.seats.length}/4 seated'
                    : '${room.seats.length}/4 人已入座',
                style: TextStyle(color: palette.muted, fontSize: 12),
              ),
              const SizedBox(height: 18),
              Row(
                children: Wind.values.map((wind) {
                  final memberId = room.seats[wind];
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: wind == Wind.north ? 0 : 7,
                      ),
                      child: _TinySeat(
                        wind: wind,
                        name: memberId == null
                            ? null
                            : snapshot.memberName(memberId),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    strings.text('查看房间', 'View room'),
                    style: TextStyle(
                      color: palette.forest,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.arrow_forward_rounded,
                    color: palette.forest,
                    size: 20,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TinySeat extends StatelessWidget {
  const _TinySeat({required this.wind, required this.name});

  final Wind wind;
  final String? name;

  @override
  Widget build(BuildContext context) {
    final palette = context.doraPalette;
    return Container(
      height: 62,
      padding: const EdgeInsets.fromLTRB(8, 7, 8, 6),
      decoration: BoxDecoration(
        color: name == null ? palette.paper : palette.forestSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            doraWindLabel(context, wind, compact: true),
            style: TextStyle(
              color: palette.muted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          Text(
            name ?? context.t('空位', 'Open'),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: name == null ? palette.muted : palette.forest,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomDetailPage extends StatelessWidget {
  const _RoomDetailPage({
    required this.controller,
    required this.roomId,
    required this.onBack,
    required this.onOpenGame,
  });

  final ClubController controller;
  final String roomId;
  final VoidCallback onBack;
  final ValueChanged<String> onOpenGame;

  Future<void> _seat(BuildContext context, ClubRoom room, Wind wind) async {
    // Read the latest snapshot on tap: another device may have started a game
    // or moved a seat since rendering. sit handles empty-seat moves atomically;
    // tapping yourself leaves, while tapping another member opens the menu.
    final currentRoom = controller.snapshot.rooms
        .where((item) => item.id == room.id)
        .firstOrNull;
    if (currentRoom == null || controller.busy) return;
    if (controller.snapshot.activeGame(currentRoom.id) != null) {
      _showSnack(
        context,
        context.t(
          '请先完成或取消当前对局，再调整座位',
          'Finish or cancel the current game before changing seats.',
        ),
      );
      return;
    }
    final occupant = currentRoom.seats[wind];
    final memberId = controller.member?.id;
    if (occupant == null) {
      if (memberId == null) {
        _showSnack(
          context,
          context.t(
            '先选择一个成员身份，再入座。',
            'Choose a member identity before taking a seat.',
          ),
        );
      } else {
        await controller.sit(currentRoom.id, wind);
      }
      return;
    }
    if (occupant == memberId && memberId != null) {
      await controller.leave(currentRoom.id);
    } else if (controller.isAdmin || memberId != null) {
      await _removePlayer(context, currentRoom.id, occupant);
    } else {
      _showSnack(
        context,
        context.t('这个座位已有人入座', 'This seat is already occupied.'),
      );
    }
  }

  Future<void> _removePlayer(
    BuildContext context,
    String roomId,
    String memberId,
  ) async {
    final playerName = controller.snapshot.memberName(memberId);
    final removed = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final locked =
              controller.busy || controller.snapshot.activeGame(roomId) != null;
          final palette = context.doraPalette;
          return Material(
            color: palette.card,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    playerName,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: locked
                        ? null
                        : () => Navigator.pop(sheetContext, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: palette.danger,
                      foregroundColor: palette.onForest,
                    ),
                    icon: const Icon(Icons.person_remove_alt_1_rounded),
                    label: Text(context.t('移除玩家', 'Remove player')),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(sheetContext, false),
                    child: Text(context.t('取消', 'Cancel')),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (removed != true || !context.mounted || controller.busy) return;

    final currentRoom = controller.snapshot.rooms
        .where((item) => item.id == roomId)
        .firstOrNull;
    if (currentRoom == null) return;
    if (controller.snapshot.activeGame(roomId) != null) {
      _showSnack(
        context,
        context.t(
          '请先完成或取消当前对局，再调整座位',
          'Finish or cancel the current game before changing seats.',
        ),
      );
      return;
    }
    if (!currentRoom.seats.containsValue(memberId)) return;
    if (!controller.isAdmin && controller.member == null) {
      _showSnack(
        context,
        context.t('请先选择成员身份', 'Choose a member identity first.'),
      );
      return;
    }

    await controller.leave(currentRoom.id, memberId: memberId);
    if (controller.error != null && context.mounted) {
      _showSnack(context, doraMessage(context, controller.error!));
    }
  }

  Future<void> _showRoomActions(BuildContext context, ClubRoom room) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _SheetFrame(
        eyebrow: 'ROOM / ADMIN',
        title: context.strings.isEnglish
            ? 'Manage ${room.name}'
            : '管理 ${room.name}',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton.icon(
              onPressed: () async {
                Navigator.pop(sheetContext);
                await _renameRoom(context, room);
              },
              icon: const Icon(Icons.edit_outlined),
              label: Text(context.t('修改房间名称', 'Rename room')),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: room.seats.isEmpty
                  ? null
                  : () async {
                      Navigator.pop(sheetContext);
                      await _clearSeats(context, room);
                    },
              icon: const Icon(Icons.cleaning_services_outlined),
              label: Text(context.t('清理全部座位', 'Clear all seats')),
            ),
            const SizedBox(height: 5),
            Text(
              context.t(
                '清理座位不会删除对局记录；进行中的对局仍需先完成或取消。',
                'Clearing seats keeps game history; finish or cancel an active game first.',
              ),
              style: TextStyle(color: context.doraPalette.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _renameRoom(BuildContext context, ClubRoom room) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RenameRoomSheet(controller: controller, room: room),
    );
  }

  Future<void> _clearSeats(BuildContext context, ClubRoom room) async {
    final confirmed = await _confirm(
      context,
      title: context.t('清理全部座位？', 'Clear all seats?'),
      body: context.strings.isEnglish
          ? 'This removes ${room.seats.length} members from ${room.name}; history stays unchanged.'
          : '会将 ${room.seats.length} 位成员移出 ${room.name}，历史记录不会改变。',
      confirm: context.t('清理', 'Clear'),
    );
    if (!confirmed) return;
    for (final memberId in room.seats.values.toList()) {
      await controller.leave(room.id, memberId: memberId);
    }
    if (controller.error != null && context.mounted) {
      _showSnack(context, controller.error!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = controller.snapshot.rooms
        .where((item) => item.id == roomId)
        .firstOrNull;
    if (room == null) {
      return _MissingPage(
        onBack: onBack,
        title: context.t('房间已不存在', 'Room no longer exists'),
      );
    }
    final game = controller.snapshot.activeGame(room.id);
    final canStart =
        game == null &&
        room.seats.length == 4 &&
        room.seats.values.contains(controller.member?.id);
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 30),
            children: [
              _DetailTopBar(
                title: room.name,
                subtitle: context.strings.isEnglish
                    ? '${room.seats.length}/4 seated'
                    : '${room.seats.length}/4 人已入座',
                onBack: onBack,
                trailing: controller.isAdmin
                    ? IconButton(
                        onPressed: controller.busy
                            ? null
                            : () => _showRoomActions(context, room),
                        tooltip: context.t('管理房间', 'Manage room'),
                        icon: const Icon(Icons.more_horiz_rounded),
                      )
                    : null,
              ),
              const SizedBox(height: 15),
              _SeatTable(
                room: room,
                snapshot: controller.snapshot,
                enabled: game == null && !controller.busy,
                onSeat: (wind) => _seat(context, room, wind),
              ),
              const SizedBox(height: 16),
              if (controller.error != null) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _FeedbackBanner(
                    message: doraMessage(context, controller.error!),
                    tone: _FeedbackTone.error,
                  ),
                ),
              ],
              if (game != null)
                _CurrentGameCard(
                  game: game,
                  snapshot: controller.snapshot,
                  onTap: () => onOpenGame(game.id),
                )
              else ...[
                _InfoCard(
                  icon: Icons.hourglass_empty_rounded,
                  title: room.seats.length == 4
                      ? context.t('四位成员已就座', 'Four members are seated')
                      : context.t('等待四位成员入座', 'Waiting for four members'),
                  body: room.seats.length == 4
                      ? context.t(
                          '确认座位后即可开始一场新的对局。',
                          'Confirm the seats to start a new game.',
                        )
                      : context.t(
                          '点击空位即可入座或换座；点击自己的座位可离座。',
                          'Tap an open seat to sit or move; tap your own seat to leave.',
                        ),
                  tone: room.seats.length == 4
                      ? _InfoTone.good
                      : _InfoTone.neutral,
                ),
                if (canStart) ...[
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: controller.busy
                        ? null
                        : () async {
                            final selection = await showGameStartSheet(
                              context: context,
                              controller: controller,
                              room: room,
                            );
                            if (!context.mounted || selection.cancelled) {
                              return;
                            }
                            await controller.startGame(
                              room.id,
                              eventId: selection.eventId,
                            );
                          },
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Padding(
                      padding: EdgeInsets.symmetric(vertical: 3),
                      child: Text(context.t('开始对局', 'Start game')),
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 16),
              const _Eyebrow(text: 'SEAT NOTES'),
              const SizedBox(height: 8),
              Text(
                context.t(
                  '东、南、西、北是本场起始座位。对局开始后座位与参与者会锁定，完成或取消后再调整。',
                  'East, south, west, and north are the starting seats. Seats and players lock once a game starts.',
                ),
                style: TextStyle(color: context.doraPalette.muted, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SeatTable extends StatelessWidget {
  const _SeatTable({
    required this.room,
    required this.snapshot,
    required this.enabled,
    required this.onSeat,
  });

  final ClubRoom room;
  final ClubSnapshot snapshot;
  final bool enabled;
  final ValueChanged<Wind> onSeat;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(constraints.maxWidth, 540.0);
        final tileSize = math.min(84.0, math.max(64.0, width * .22));
        final seatWidth = math.min(
          166.0,
          math.max(78.0, width / 2 - tileSize / 2 - 16),
        );
        const seatHeight = 74.0;
        final height = math.min(width * .92, 410.0);
        final sideTop = (height - seatHeight) / 2;
        return Center(
          child: SizedBox(
            width: width,
            height: height,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _TablePainter(palette: context.doraPalette),
                  ),
                ),
                _seatPosition(
                  context,
                  Wind.east,
                  width: seatWidth,
                  top: 8,
                  left: width / 2 - seatWidth / 2,
                ),
                _seatPosition(
                  context,
                  Wind.south,
                  width: seatWidth,
                  right: 8,
                  top: sideTop,
                ),
                _seatPosition(
                  context,
                  Wind.west,
                  width: seatWidth,
                  bottom: 8,
                  left: width / 2 - seatWidth / 2,
                ),
                _seatPosition(
                  context,
                  Wind.north,
                  width: seatWidth,
                  left: 8,
                  top: sideTop,
                ),
                Positioned(
                  left: width / 2 - tileSize / 2,
                  top: height / 2 - tileSize / 2,
                  child: _MahjongMark(size: tileSize),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _seatPosition(
    BuildContext context,
    Wind wind, {
    required double width,
    double? top,
    double? bottom,
    double? left,
    double? right,
  }) {
    final memberId = room.seats[wind];
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: _SeatNode(
        width: width,
        wind: wind,
        name: memberId == null ? null : snapshot.memberName(memberId),
        onTap: () => onSeat(wind),
        enabled: enabled,
      ),
    );
  }
}

class _SeatNode extends StatelessWidget {
  const _SeatNode({
    required this.width,
    required this.wind,
    required this.name,
    required this.onTap,
    required this.enabled,
  });

  final double width;
  final Wind wind;
  final String? name;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final palette = context.doraPalette;
    final windLabel = doraWindLabel(context, wind);
    return Semantics(
      button: true,
      enabled: enabled,
      label: context.strings.isEnglish
          ? '$windLabel seat, ${name ?? 'open'}'
          : '$windLabel位，${name ?? '空位'}',
      child: Material(
        color: name == null ? palette.card : palette.forest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: name == null ? palette.line : palette.forest),
        ),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
            width: width,
            height: 74,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: name == null
                          ? palette.lime
                          : palette.onForest.withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      doraWindLabel(context, wind, compact: true),
                      style: TextStyle(
                        color: name == null ? palette.onLime : palette.onForest,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      name ?? context.t('点击入座', 'Tap to sit'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: name == null ? palette.ink : palette.onForest,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TablePainter extends CustomPainter {
  const _TablePainter({required this.palette});

  final DoraPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) * .33;
    final ring = Paint()
      ..color = palette.forestSoft
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius + 45, ring);
    final border = Paint()
      ..color = palette.forest.withValues(alpha: .2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawCircle(center, radius + 45, border);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = palette.card
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(center, radius, border);
    for (var i = 0; i < 4; i++) {
      final angle = -math.pi / 2 + i * math.pi / 2;
      final p1 =
          center + Offset(math.cos(angle) * radius, math.sin(angle) * radius);
      final p2 =
          center +
          Offset(
            math.cos(angle) * (radius + 44),
            math.sin(angle) * (radius + 44),
          );
      canvas.drawLine(
        p1,
        p2,
        Paint()
          ..color = palette.forest.withValues(alpha: .14)
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TablePainter oldDelegate) =>
      oldDelegate.palette != palette;
}

class _CurrentGameCard extends StatelessWidget {
  const _CurrentGameCard({
    required this.game,
    required this.snapshot,
    required this.onTap,
  });

  final ClubGame game;
  final ClubSnapshot snapshot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.doraPalette;
    final message = game.allEntered
        ? (game.needsCorrection
              ? strings.text(
                  '总分不等于 100,000，请检查。',
                  'The total is not 100,000. Check the scores.',
                )
              : strings.text('正在确认成绩…', 'Confirming scores…'))
        : strings.isEnglish
        ? '${game.enteredCount}/4 entered · Total ${formatPoints(game.total)}'
        : '${game.enteredCount}/4 人已录入 · 当前合计 ${formatPoints(game.total)}';
    return Material(
      color: palette.forest,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const _Eyebrow(text: 'CURRENT GAME', light: true),
                  const Spacer(),
                  Icon(
                    Icons.arrow_forward_rounded,
                    color: palette.onForest.withValues(alpha: .72),
                  ),
                ],
              ),
              const SizedBox(height: 13),
              Text(
                message,
                style: TextStyle(
                  color: palette.onForest,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 15),
              Row(
                children: game.players
                    .map(
                      (player) => Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                            right: player == game.players.last ? 0 : 7,
                          ),
                          child: _MiniPlayer(
                            player: player,
                            snapshot: snapshot,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniPlayer extends StatelessWidget {
  const _MiniPlayer({required this.player, required this.snapshot});

  final GamePlayer player;
  final ClubSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final palette = context.doraPalette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          doraWindLabel(context, player.wind),
          style: TextStyle(
            color: palette.onForest,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          player.score == null
              ? context.t('待录入', 'Pending')
              : formatPoints(player.score!),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: palette.onForest,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _PendingPage extends StatelessWidget {
  const _PendingPage({
    required this.controller,
    required this.onGame,
    required this.onProfile,
  });

  final ClubController controller;
  final ValueChanged<String> onGame;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    final memberId = controller.member?.id;
    final games =
        controller.snapshot.games
            .where(
              (game) =>
                  game.status == GameStatus.active &&
                  (controller.isAdmin || game.involves(memberId)),
            )
            .toList()
          ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
            children: [
              _TopBar(
                controller: controller,
                onProfile: onProfile,
                title: '待录入',
              ),
              const SizedBox(height: 24),
              Text(
                context.t(
                  '对局会在四位成员都录入且合计 100,000 时自动完成。',
                  'A game completes when all four members enter scores totaling 100,000.',
                ),
                style: TextStyle(color: context.doraPalette.muted),
              ),
              const SizedBox(height: 24),
              if (games.isEmpty)
                _EmptyState(
                  icon: Icons.inbox_rounded,
                  title: context.t('现在没有待处理对局', 'No pending games right now'),
                  body: context.t(
                    '完成的对局会自动进入记录。',
                    'Completed games appear in history automatically.',
                  ),
                )
              else
                ...games.map(
                  (game) => Padding(
                    padding: const EdgeInsets.only(bottom: 11),
                    child: _PendingGameCard(
                      game: game,
                      roomName: controller.snapshot.roomName(game.roomId),
                      memberId: memberId,
                      isAdmin: controller.isAdmin,
                      onTap: () => onGame(game.id),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PendingGameCard extends StatelessWidget {
  const _PendingGameCard({
    required this.game,
    required this.roomName,
    required this.memberId,
    required this.isAdmin,
    required this.onTap,
  });

  final ClubGame game;
  final String roomName;
  final String? memberId;
  final bool isAdmin;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.doraPalette;
    final own = memberId == null
        ? null
        : game.players.where((p) => p.memberId == memberId).firstOrNull;
    final label = game.needsCorrection
        ? strings.text('总分待纠错', 'Total needs correction')
        : own?.score == null
        ? strings.text('待填写你的点数', 'Enter your score')
        : strings.text('等待其他成员', 'Waiting for other members');
    return Material(
      color: palette.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: palette.line),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: game.needsCorrection
                      ? palette.warningSoft
                      : palette.lime,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  game.needsCorrection
                      ? Icons.priority_high_rounded
                      : Icons.edit_note_rounded,
                  color: game.needsCorrection
                      ? palette.warning
                      : palette.onLime,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      roomName,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isAdmin && memberId == null
                          ? strings.isEnglish
                                ? '$label · ${game.enteredCount}/4'
                                : '$label · ${game.enteredCount}/4 人'
                          : label,
                      style: TextStyle(color: palette.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_rounded, color: palette.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryPage extends StatefulWidget {
  const _HistoryPage({
    required this.controller,
    required this.onGame,
    required this.onProfile,
  });

  final ClubController controller;
  final ValueChanged<String> onGame;
  final VoidCallback onProfile;

  @override
  State<_HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<_HistoryPage> {
  int _scope = 0;

  @override
  Widget build(BuildContext context) {
    final memberId = widget.controller.member?.id;
    final all =
        widget.controller.snapshot.games
            .where((game) => game.status != GameStatus.active)
            .toList()
          ..sort(
            (a, b) => (b.completedAt ?? b.cancelledAt ?? b.startedAt).compareTo(
              a.completedAt ?? a.cancelledAt ?? a.startedAt,
            ),
          );
    final games = _scope == 0
        ? all.where((game) => game.involves(memberId)).toList()
        : all;
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
            children: [
              _TopBar(
                controller: widget.controller,
                onProfile: widget.onProfile,
                title: '记录',
              ),
              const SizedBox(height: 24),
              SegmentedButton<int>(
                segments: [
                  ButtonSegment(
                    value: 0,
                    label: Text(context.t('我参与的', 'Mine')),
                  ),
                  ButtonSegment(
                    value: 1,
                    label: Text(context.t('俱乐部', 'Club')),
                  ),
                ],
                selected: {_scope},
                onSelectionChanged: (selection) =>
                    setState(() => _scope = selection.first),
              ),
              const SizedBox(height: 20),
              if (games.isEmpty)
                _EmptyState(
                  icon: Icons.menu_book_outlined,
                  title: _scope == 0
                      ? context.t('还没有我的记录', 'No history for me')
                      : context.t('俱乐部还没有记录', 'The club has no history'),
                  body: _scope == 0
                      ? context.t(
                          '完成一场对局后，它会出现在这里。',
                          'Finish a game and it will appear here.',
                        )
                      : context.t(
                          '第一场完成的对局会从这里开始。',
                          'Completed games will start appearing here.',
                        ),
                )
              else
                ...games.map(
                  (game) => Padding(
                    padding: const EdgeInsets.only(bottom: 11),
                    child: _HistoryGameCard(
                      game: game,
                      roomName: widget.controller.snapshot.roomName(
                        game.roomId,
                      ),
                      onTap: () => widget.onGame(game.id),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryGameCard extends StatelessWidget {
  const _HistoryGameCard({
    required this.game,
    required this.roomName,
    required this.onTap,
  });

  final ClubGame game;
  final String roomName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.doraPalette;
    final first = game.players.where((p) => p.rank == 1).firstOrNull;
    final isCancelled = game.status == GameStatus.cancelled;
    return Material(
      color: palette.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: palette.line),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 45,
                height: 45,
                decoration: BoxDecoration(
                  color: isCancelled ? palette.paperDeep : palette.lime,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Text(
                  isCancelled ? '—' : '1',
                  style: TextStyle(
                    color: isCancelled ? palette.muted : palette.onLime,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      roomName,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isCancelled
                          ? strings.isEnglish
                                ? 'Cancelled · ${game.cancelReason ?? 'No reason'}'
                                : '已取消 · ${game.cancelReason ?? '未填写原因'}'
                          : strings.isEnglish
                          ? '1st ${first?.name ?? '—'} · ${formatPoints(first?.score ?? 0)}'
                          : '第一名 ${first?.name ?? '—'} · ${formatPoints(first?.score ?? 0)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: palette.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_rounded, color: palette.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuditPage extends StatelessWidget {
  const _AuditPage({
    required this.controller,
    required this.onBack,
    required this.onProfile,
  });

  final ClubController controller;
  final VoidCallback onBack;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    final audits = [...controller.snapshot.audits]
      ..sort((a, b) => b.at.compareTo(a.at));
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
            children: [
              _DetailTopBar(
                title: context.t('修改记录', 'Change log'),
                subtitle: context.t('成绩更正与操作者', 'Score changes and operators'),
                onBack: onBack,
                trailing: IconButton(
                  onPressed: controller.loading
                      ? null
                      : () => controller.refresh(quiet: true),
                  tooltip: context.t('刷新', 'Refresh'),
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ),
              const SizedBox(height: 24),
              if (audits.isEmpty)
                _EmptyState(
                  icon: Icons.fact_check_outlined,
                  title: context.t('还没有修改记录', 'No changes yet'),
                  body: context.t(
                    '完成成绩更正后，操作会显示在这里。',
                    'Score corrections will appear here.',
                  ),
                )
              else
                ...audits.map(
                  (audit) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _AuditCard(
                      audit: audit,
                      players:
                          controller.snapshot.games
                              .where((game) => game.id == audit.gameId)
                              .firstOrNull
                              ?.players ??
                          const [],
                      roomName: controller.snapshot.roomName(
                        controller.snapshot.games
                                .where((game) => game.id == audit.gameId)
                                .firstOrNull
                                ?.roomId ??
                            '',
                      ),
                      names: {
                        for (final member in controller.snapshot.members)
                          member.id: member.name,
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuditCard extends StatelessWidget {
  const _AuditCard({
    required this.audit,
    required this.roomName,
    this.names = const {},
    this.players = const [],
  });

  final ScoreAudit audit;
  final String roomName;
  final Map<String, String> names;
  final List<GamePlayer> players;

  Map<String, int> _ranks(Map<String, int> scores) {
    if (players.length != 4 ||
        players.any((player) => !scores.containsKey(player.memberId))) {
      return const {};
    }
    try {
      return {
        for (final player in rankPlayers([
          for (final source in players)
            GamePlayer(
              memberId: source.memberId,
              name: source.name,
              wind: source.wind,
              score: scores[source.memberId],
            ),
        ]))
          player.memberId: player.rank ?? 0,
      };
    } on ClubException {
      return const {};
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.doraPalette;
    final beforeRanks = _ranks(audit.before);
    final afterRanks = _ranks(audit.after);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    roomName,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  _formatDate(audit.at),
                  style: TextStyle(color: palette.muted, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              strings.isEnglish
                  ? '${audit.actor} corrected scores'
                  : '由 ${audit.actor} 更正成绩',
              style: TextStyle(color: palette.muted, fontSize: 12),
            ),
            const SizedBox(height: 14),
            ...audit.after.entries.map((entry) {
              final before = audit.before[entry.key];
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        names[entry.key] ?? entry.key,
                        style: TextStyle(color: palette.muted, fontSize: 12),
                      ),
                    ),
                    Text(
                      strings.isEnglish
                          ? '${formatPoints(before ?? 0)}${beforeRanks[entry.key] == null ? '' : '  #${beforeRanks[entry.key]}'}  →  ${formatPoints(entry.value)}${afterRanks[entry.key] == null ? '' : '  #${afterRanks[entry.key]}'}'
                          : '${formatPoints(before ?? 0)}${beforeRanks[entry.key] == null ? '' : '  第${beforeRanks[entry.key]}'}  →  ${formatPoints(entry.value)}${afterRanks[entry.key] == null ? '' : '  第${afterRanks[entry.key]}'}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _GameDetailPage extends StatelessWidget {
  const _GameDetailPage({
    required this.controller,
    required this.gameId,
    required this.onBack,
    required this.onOpenRoom,
  });

  final ClubController controller;
  final String gameId;
  final VoidCallback onBack;
  final ValueChanged<String> onOpenRoom;

  bool _canEditPlayer(ClubGame game, GamePlayer player) {
    final memberId = controller.member?.id;
    return controller.isAdmin ||
        game.creatorId == memberId ||
        player.memberId == memberId;
  }

  bool _canCorrect(ClubGame game) =>
      controller.isAdmin || game.creatorId == controller.member?.id;

  Future<void> _score(
    BuildContext context,
    ClubGame game,
    GamePlayer player,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _ScoreEditorSheet(controller: controller, game: game, player: player),
    );
  }

  Future<void> _correct(BuildContext context, ClubGame game) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CorrectionSheet(controller: controller, game: game),
    );
  }

  Future<void> _cancel(BuildContext context, ClubGame game) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CancelGameSheet(controller: controller, game: game),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final game = controller.snapshot.games
        .where((item) => item.id == gameId)
        .firstOrNull;
    if (game == null) {
      return _MissingPage(
        onBack: onBack,
        title: strings.text('对局已不存在', 'Game no longer exists'),
      );
    }
    final roomName = controller.snapshot.roomName(game.roomId);
    final eventName = game.eventId == null
        ? null
        : controller.snapshot.events
              .where((event) => event.id == game.eventId)
              .firstOrNull
              ?.name;
    final canCorrect = _canCorrect(game);
    final completed = game.status == GameStatus.completed;
    final cancelled = game.status == GameStatus.cancelled;
    final totalMessage = game.allEntered
        ? (game.total == 100000
              ? strings.text('当前合计 100,000', 'Total 100,000')
              : strings.isEnglish
              ? 'Total ${formatPoints(game.total)}, ${game.total < 100000 ? 'short' : 'over'} ${formatPoints((game.total - 100000).abs())}'
              : '当前合计 ${formatPoints(game.total)}，${game.total < 100000 ? '少' : '多'} ${formatPoints((game.total - 100000).abs())}')
        : strings.isEnglish
        ? '${game.enteredCount}/4 entered · Total ${formatPoints(game.total)}'
        : '${game.enteredCount}/4 人已录入，当前合计 ${formatPoints(game.total)}';
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 30),
            children: [
              _DetailTopBar(
                title: roomName,
                subtitle: cancelled
                    ? strings.text('已取消', 'Cancelled')
                    : completed
                    ? strings.text('已完成', 'Completed')
                    : strings.text('对局中', 'In progress'),
                onBack: onBack,
                trailing: IconButton(
                  onPressed: () => onOpenRoom(game.roomId),
                  tooltip: strings.text('查看房间', 'View room'),
                  icon: const Icon(Icons.table_restaurant_outlined),
                ),
              ),
              const SizedBox(height: 15),
              _GameHero(
                game: game,
                totalMessage: totalMessage,
                isDemo: controller.isDemo,
                eventName: eventName,
              ),
              const SizedBox(height: 16),
              if (controller.error != null) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _FeedbackBanner(
                    message: controller.error!,
                    tone: _FeedbackTone.error,
                  ),
                ),
              ],
              if (cancelled)
                _InfoCard(
                  icon: Icons.block_rounded,
                  title: strings.text('本场已取消', 'This game was cancelled'),
                  body: game.cancelReason?.isNotEmpty == true
                      ? strings.isEnglish
                            ? 'Reason: ${game.cancelReason}'
                            : '原因：${game.cancelReason}'
                      : strings.text(
                          '这场对局不会计入有效成绩。',
                          'This game will not count toward valid scores.',
                        ),
                  tone: _InfoTone.warning,
                )
              else ...[
                _Eyebrow(
                  text: completed
                      ? strings.text('对局结果', 'Game results')
                      : 'PLAYERS / SCORES',
                ),
                const SizedBox(height: 8),
                if (completed && game.settlement != null)
                  RatingSettlementPanel(
                    snapshot: controller.snapshot,
                    game: game,
                  )
                else ...[
                  ...game.players.map(
                    (player) => Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: _GamePlayerRow(
                        player: player,
                        canEdit: !completed && _canEditPlayer(game, player),
                        onEdit: () => _score(context, game, player),
                      ),
                    ),
                  ),
                  if (completed) ...[
                    const SizedBox(height: 4),
                    RatingSettlementPanel(
                      snapshot: controller.snapshot,
                      game: game,
                    ),
                  ],
                ],
                if (completed && canCorrect) ...[
                  const SizedBox(height: 4),
                  OutlinedButton.icon(
                    onPressed: controller.busy
                        ? null
                        : () => _correct(context, game),
                    icon: const Icon(Icons.edit_note_rounded),
                    label: Text(strings.text('更正整场成绩', 'Correct all scores')),
                  ),
                ],
                if (!completed && canCorrect) ...[
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: controller.busy
                        ? null
                        : () => _cancel(context, game),
                    icon: const Icon(Icons.cancel_outlined),
                    label: Text(strings.text('取消这场对局', 'Cancel this game')),
                    style: TextButton.styleFrom(
                      foregroundColor: context.doraPalette.danger,
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 18),
              _GameMeta(
                game: game,
                creatorName: controller.snapshot.memberName(game.creatorId),
              ),
              if (controller.snapshot.audits.any(
                (audit) => audit.gameId == game.id,
              )) ...[
                const SizedBox(height: 23),
                const _Eyebrow(text: 'CHANGE LOG'),
                const SizedBox(height: 9),
                ...controller.snapshot.audits
                    .where((audit) => audit.gameId == game.id)
                    .map(
                      (audit) => Padding(
                        padding: const EdgeInsets.only(bottom: 9),
                        child: _AuditCard(
                          audit: audit,
                          roomName: roomName,
                          players: game.players,
                          names: {
                            for (final member in controller.snapshot.members)
                              member.id: member.name,
                          },
                        ),
                      ),
                    ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _GameHero extends StatelessWidget {
  const _GameHero({
    required this.game,
    required this.totalMessage,
    required this.isDemo,
    this.eventName,
  });

  final ClubGame game;
  final String totalMessage;
  final bool isDemo;
  final String? eventName;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.doraPalette;
    final completed = game.status == GameStatus.completed;
    final cancelled = game.status == GameStatus.cancelled;
    return Container(
      padding: const EdgeInsets.fromLTRB(19, 18, 19, 20),
      decoration: BoxDecoration(
        color: completed
            ? palette.forest
            : cancelled
            ? palette.paperDeep
            : palette.card,
        borderRadius: BorderRadius.circular(21),
        border: Border.all(color: completed ? palette.forest : palette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              _StatusPill(
                text: completed
                    ? strings.text('已完成', 'Completed')
                    : cancelled
                    ? strings.text('已取消', 'Cancelled')
                    : game.needsCorrection
                    ? strings.text('总分待纠错', 'Total needs correction')
                    : strings.text('等待录入', 'Waiting for scores'),
                active: completed,
                inverted: completed,
              ),
              if (completed && game.completedAt != null)
                Text(
                  _formatDate(game.completedAt!),
                  style: TextStyle(
                    color: completed
                        ? palette.onForest.withValues(alpha: .72)
                        : palette.muted,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 17),
          if (eventName != null) ...[
            Row(
              children: [
                Icon(
                  Icons.event_available_outlined,
                  size: 18,
                  color: completed
                      ? palette.onForest.withValues(alpha: .82)
                      : palette.forest,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    eventName!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: completed ? palette.onForest : palette.forest,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          Text(
            totalMessage,
            style: TextStyle(
              color: completed ? palette.onForest : palette.ink,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            completed
                ? isDemo
                      ? strings.text(
                          '演示成绩已保存到此设备。',
                          'Demo scores were saved on this device.',
                        )
                      : strings.text(
                          '四人成绩已保存，本场已完成。',
                          'All four scores are saved; this game is complete.',
                        )
                : cancelled
                ? strings.text('已保存取消信息。', 'Cancellation details are saved.')
                : game.needsCorrection
                ? strings.text(
                    '四人已录入，请检查点数；合计须为 100,000。',
                    'All four scores are entered; check that the total is 100,000.',
                  )
                : strings.text(
                    '每位成员保存自己的原始点数；最后一份正确成绩会自动完成对局。',
                    'Each member saves their raw score; the game completes when the final correct score is entered.',
                  ),
            style: TextStyle(
              color: completed
                  ? palette.onForest.withValues(alpha: .72)
                  : palette.muted,
              height: 1.4,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _GamePlayerRow extends StatelessWidget {
  const _GamePlayerRow({
    required this.player,
    required this.canEdit,
    required this.onEdit,
  });

  final GamePlayer player;
  final bool canEdit;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final palette = context.doraPalette;
    final strings = context.strings;
    final waiting = player.score == null;
    return Material(
      color: palette.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(17),
        side: BorderSide(color: palette.line),
      ),
      child: InkWell(
        onTap: canEdit ? onEdit : null,
        borderRadius: BorderRadius.circular(17),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: player.rank == 1 ? palette.lime : palette.paper,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(
                  player.rank == null
                      ? doraWindLabel(context, player.wind, compact: true)
                      : '${player.rank}',
                  style: TextStyle(
                    color: player.rank == 1 ? palette.onLime : palette.forest,
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      player.name,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      strings.isEnglish
                          ? '${doraWindLabel(context, player.wind)}${player.rank == null ? '' : '  ·  #${player.rank}'}'
                          : '${doraWindLabel(context, player.wind)}位${player.rank == null ? '' : '  ·  第${player.rank}名'}',
                      style: TextStyle(color: palette.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (waiting)
                Text(
                  strings.text('等待录入', 'Waiting'),
                  style: TextStyle(
                    color: palette.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                )
              else
                Text(
                  formatPoints(player.score!),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              if (canEdit) ...[
                const SizedBox(width: 10),
                Icon(Icons.edit_outlined, color: palette.forest, size: 20),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _GameMeta extends StatelessWidget {
  const _GameMeta({required this.game, required this.creatorName});

  final ClubGame game;
  final String creatorName;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Eyebrow(text: 'GAME DETAILS'),
            const SizedBox(height: 12),
            _MetaRow(
              label: context.t('开始时间', 'Started'),
              value: _formatDate(game.startedAt),
            ),
            _MetaRow(label: context.t('创建者', 'Created by'), value: creatorName),
            if (game.completedAt != null)
              _MetaRow(
                label: context.t('完成时间', 'Completed'),
                value: _formatDate(game.completedAt!),
              ),
            if (game.cancelledAt != null)
              _MetaRow(
                label: context.t('取消时间', 'Cancelled'),
                value: _formatDate(game.cancelledAt!),
              ),
          ],
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        SizedBox(
          width: 78,
          child: Text(
            label,
            style: TextStyle(color: context.doraPalette.muted, fontSize: 12),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

class _ScoreEditorSheet extends StatefulWidget {
  const _ScoreEditorSheet({
    required this.controller,
    required this.game,
    required this.player,
  });

  final ClubController controller;
  final ClubGame game;
  final GamePlayer player;

  @override
  State<_ScoreEditorSheet> createState() => _ScoreEditorSheetState();
}

/// Keeps the input draft independent of background snapshot refreshes. After a
/// version conflict, explicitly rebase _game while preserving input and require
/// another save rather than automatically overwriting another client's score.
class _ScoreEditorSheetState extends State<_ScoreEditorSheet> {
  late final TextEditingController _input;
  late ClubGame _game;
  bool _saving = false;
  bool _rebasing = false;
  bool _showRebase = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _game = widget.game;
    _input = TextEditingController(text: widget.player.score?.toString() ?? '');
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _rebasing) return;
    int score;
    try {
      score = parseScore(_input.text);
    } on ClubException catch (error) {
      setState(() {
        _showRebase = false;
        _error = error.message;
      });
      return;
    }
    setState(() {
      _saving = true;
      _showRebase = false;
      _error = null;
    });
    widget.controller.clearFeedback();
    final ok = await widget.controller.saveScore(
      _game,
      widget.player.memberId,
      score,
    );
    if (!mounted) return;
    if (ok) {
      _showSnack(context, context.t('点数已保存', 'Score saved'));
      Navigator.of(context).pop();
    } else {
      setState(() {
        _saving = false;
        _showRebase = widget.controller.lastActionConflict;
        _error = widget.controller.error ?? '保存失败，请重试';
      });
    }
  }

  Future<void> _rebase() async {
    setState(() {
      _rebasing = true;
      _showRebase = false;
      _error = null;
    });
    await widget.controller.refresh(quiet: true);
    if (!mounted) return;
    final latest = widget.controller.snapshot.games
        .where((game) => game.id == _game.id)
        .firstOrNull;
    setState(() {
      _rebasing = false;
      if (latest == null) {
        _error = '本场对局已不存在，请返回刷新。';
      } else {
        _game = latest;
        _error = '已刷新本场版本，输入已保留，请再次保存。';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return _SheetFrame(
      eyebrow: '${doraWindLabel(context, widget.player.wind)} / SCORE',
      title: widget.player.name,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            strings.text('请输入最终原始点数', 'Enter the final raw score'),
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: context.doraPalette.muted),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _input,
            autofocus: true,
            enabled: !_saving,
            keyboardType: const TextInputType.numberWithOptions(
              signed: true,
              decimal: false,
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
            decoration: InputDecoration(
              hintText: '25000',
              suffixText: strings.text('点', 'pts'),
            ),
          ),
          const SizedBox(height: 9),
          Text(
            strings.text(
              '允许 0 和负分，必须是 100 的倍数。保存后三人也能看到进度。',
              'Zero and negative scores are allowed; scores must be multiples of 100. The other players will see the update.',
            ),
            style: TextStyle(
              color: context.doraPalette.muted,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          if (_error != null && _showRebase) ...[
            const SizedBox(height: 14),
            _FeedbackBanner(message: _error!, tone: _FeedbackTone.error),
            const SizedBox(height: 9),
            OutlinedButton.icon(
              onPressed: _saving || _rebasing ? null : _rebase,
              icon: const Icon(Icons.sync_rounded),
              label: Text(
                _rebasing
                    ? strings.text('刷新中…', 'Refreshing…')
                    : strings.text(
                        '刷新本场版本并重试',
                        'Refresh this game and try again',
                      ),
              ),
            ),
          ],
          if (_error != null && !_showRebase)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: _FeedbackBanner(
                message: _error!,
                tone: _FeedbackTone.error,
              ),
            ),
          const SizedBox(height: 22),
          FilledButton(
            onPressed: _saving || _rebasing ? null : _save,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(
                _saving
                    ? strings.text('保存中…', 'Saving…')
                    : strings.text('保存成绩', 'Save score'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CorrectionSheet extends StatefulWidget {
  const _CorrectionSheet({required this.controller, required this.game});

  final ClubController controller;
  final ClubGame game;

  @override
  State<_CorrectionSheet> createState() => _CorrectionSheetState();
}

class _CorrectionSheetState extends State<_CorrectionSheet> {
  late final Map<String, TextEditingController> _inputs;
  late ClubGame _game;
  bool _saving = false;
  bool _rebasing = false;
  bool _showRebase = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _game = widget.game;
    _inputs = {
      for (final player in widget.game.players)
        player.memberId: TextEditingController(
          text: player.score?.toString() ?? '',
        ),
    };
  }

  @override
  void dispose() {
    for (final input in _inputs.values) {
      input.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _rebasing) return;
    final scores = <String, int>{};
    try {
      for (final player in widget.game.players) {
        scores[player.memberId] = parseScore(_inputs[player.memberId]!.text);
      }
    } on ClubException catch (error) {
      setState(() {
        _showRebase = false;
        _error = error.message;
      });
      return;
    }
    if (scores.values.fold<int>(0, (sum, value) => sum + value) != 100000) {
      setState(() {
        _showRebase = false;
        _error =
            '四人合计必须为 100,000，当前为 ${formatPoints(scores.values.fold<int>(0, (sum, value) => sum + value))}';
      });
      return;
    }
    setState(() {
      _saving = true;
      _showRebase = false;
      _error = null;
    });
    widget.controller.clearFeedback();
    final ok = await widget.controller.correctScores(_game, scores);
    if (!mounted) return;
    if (ok) {
      _showSnack(context, context.t('成绩已更正', 'Scores corrected'));
      Navigator.of(context).pop();
    } else {
      setState(() {
        _saving = false;
        _showRebase = widget.controller.lastActionConflict;
        _error = widget.controller.error ?? '保存失败，请重试';
      });
    }
  }

  Future<void> _rebase() async {
    setState(() {
      _rebasing = true;
      _showRebase = false;
      _error = null;
    });
    await widget.controller.refresh(quiet: true);
    if (!mounted) return;
    final latest = widget.controller.snapshot.games
        .where((game) => game.id == _game.id)
        .firstOrNull;
    setState(() {
      _rebasing = false;
      if (latest == null) {
        _error = '本场对局已不存在，请返回刷新。';
      } else {
        _game = latest;
        _error = '已刷新本场版本，保留你当前的更正输入，请再次保存。';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return _SheetFrame(
      eyebrow: 'CORRECT / ALL SCORES',
      title: strings.text('更正整场成绩', 'Correct all scores'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...widget.game.players.map(
            (player) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                controller: _inputs[player.memberId],
                enabled: !_saving,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                  decimal: false,
                ),
                decoration: InputDecoration(
                  labelText: strings.isEnglish
                      ? '${doraWindLabel(context, player.wind)} · ${player.name}'
                      : '${doraWindLabel(context, player.wind)}位 · ${player.name}',
                  suffixText: strings.text('点', 'pts'),
                ),
              ),
            ),
          ),
          const SizedBox(height: 1),
          Text(
            strings.text(
              '一次保存四人的成绩并更新名次，无需填写原因。',
              'Save all four scores together and update the ranks. No reason is required.',
            ),
            style: TextStyle(
              color: context.doraPalette.muted,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            widget.game.settlement == null
                ? strings.text(
                    '这场历史记录未纳入积分结算；更正不会影响 MMR。',
                    'This legacy game was not rated; correcting it will not affect MMR.',
                  )
                : strings.text(
                    '本场PT会重新计算，后续受影响对局的MMR也会按顺序重算',
                    'This game\'s PT will be recalculated, and MMR for later affected games will be replayed in order.',
                  ),
            style: TextStyle(
              color: context.doraPalette.muted,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          if (_error != null && _showRebase) ...[
            const SizedBox(height: 14),
            _FeedbackBanner(message: _error!, tone: _FeedbackTone.error),
            const SizedBox(height: 9),
            OutlinedButton.icon(
              onPressed: _saving || _rebasing ? null : _rebase,
              icon: const Icon(Icons.sync_rounded),
              label: Text(
                _rebasing
                    ? strings.text('刷新中…', 'Refreshing…')
                    : strings.text(
                        '刷新本场版本并重试',
                        'Refresh this game and try again',
                      ),
              ),
            ),
          ],
          if (_error != null && !_showRebase)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: _FeedbackBanner(
                message: _error!,
                tone: _FeedbackTone.error,
              ),
            ),
          const SizedBox(height: 22),
          FilledButton(
            onPressed: _saving || _rebasing ? null : _save,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(
                _saving
                    ? strings.text('保存中…', 'Saving…')
                    : strings.text('保存更正', 'Save correction'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CancelGameSheet extends StatefulWidget {
  const _CancelGameSheet({required this.controller, required this.game});

  final ClubController controller;
  final ClubGame game;

  @override
  State<_CancelGameSheet> createState() => _CancelGameSheetState();
}

class _CancelGameSheetState extends State<_CancelGameSheet> {
  final _reason = TextEditingController();
  late ClubGame _game;
  bool _saving = false;
  bool _rebasing = false;
  bool _showRebase = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _game = widget.game;
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _rebasing) return;
    if (_reason.text.trim().isEmpty) {
      setState(() {
        _showRebase = false;
        _error = '请填写取消原因';
      });
      return;
    }
    setState(() {
      _saving = true;
      _showRebase = false;
      _error = null;
    });
    widget.controller.clearFeedback();
    final ok = await widget.controller.cancelGame(_game, _reason.text.trim());
    if (!mounted) return;
    if (ok) {
      _showSnack(context, context.t('对局已取消', 'Game cancelled'));
      Navigator.of(context).pop();
    } else {
      setState(() {
        _saving = false;
        _showRebase = widget.controller.lastActionConflict;
        _error = widget.controller.error ?? '取消失败，请重试';
      });
    }
  }

  Future<void> _rebase() async {
    setState(() {
      _rebasing = true;
      _showRebase = false;
      _error = null;
    });
    await widget.controller.refresh(quiet: true);
    if (!mounted) return;
    final latest = widget.controller.snapshot.games
        .where((game) => game.id == _game.id)
        .firstOrNull;
    setState(() {
      _rebasing = false;
      if (latest == null) {
        _error = '本场对局已不存在，请返回刷新。';
      } else {
        _game = latest;
        _error = '已刷新本场版本，取消原因已保留，请再次确认。';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return _SheetFrame(
      eyebrow: 'CANCEL / REQUIRED',
      title: strings.text('取消这场对局', 'Cancel this game'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            strings.text(
              '取消后会保留本场和已录入的草稿，并释放房间开始下一场。',
              'Cancelling keeps this game and entered drafts, and frees the room for the next game.',
            ),
            style: TextStyle(color: context.doraPalette.muted, height: 1.4),
          ),
          const SizedBox(height: 15),
          TextField(
            controller: _reason,
            enabled: !_saving,
            autofocus: true,
            maxLines: 3,
            maxLength: 120,
            decoration: InputDecoration(
              labelText: strings.text('取消原因', 'Cancellation reason'),
              hintText: strings.text(
                '例如：成员临时离开',
                'For example: a member had to leave',
              ),
            ),
          ),
          if (_error != null && _showRebase) ...[
            const SizedBox(height: 8),
            _FeedbackBanner(message: _error!, tone: _FeedbackTone.error),
            const SizedBox(height: 9),
            OutlinedButton.icon(
              onPressed: _saving || _rebasing ? null : _rebase,
              icon: const Icon(Icons.sync_rounded),
              label: Text(
                _rebasing
                    ? strings.text('刷新中…', 'Refreshing…')
                    : strings.text(
                        '刷新本场版本并重试',
                        'Refresh this game and try again',
                      ),
              ),
            ),
          ],
          if (_error != null && !_showRebase)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _FeedbackBanner(
                message: _error!,
                tone: _FeedbackTone.error,
              ),
            ),
          const SizedBox(height: 17),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.doraPalette.danger,
              foregroundColor: context.doraPalette.onForest,
            ),
            onPressed: _saving || _rebasing ? null : _save,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(
                _saving
                    ? strings.text('取消中…', 'Cancelling…')
                    : strings.text('确认取消', 'Confirm cancellation'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileSheet extends StatelessWidget {
  const _ProfileSheet({required this.controller, required this.onAudits});

  final ClubController controller;
  final VoidCallback onAudits;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final preferences = AppPreferencesScope.of(context);
    final member = controller.member;
    final display = controller.isAdmin
        ? (controller.snapshot.adminName ?? strings.text('管理员', 'Admin'))
        : (controller.member?.name ?? strings.text('未选择', 'Not selected'));
    return _SheetFrame(
      eyebrow: 'PROFILE / ${controller.isAdmin ? 'ADMIN' : 'MEMBER'}',
      title: display,
      titleTrailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PreferenceToggleButton(
            key: const ValueKey('toggle-language'),
            active: preferences.isEnglish,
            icon: Icons.translate_rounded,
            label: preferences.isEnglish
                ? strings.text('切换为中文', 'Switch to Chinese')
                : strings.text('切换为 English', 'Switch to English'),
            onPressed: preferences.toggleLanguage,
          ),
          const SizedBox(width: 8),
          _PreferenceToggleButton(
            key: const ValueKey('toggle-theme'),
            active: preferences.isDark,
            icon: preferences.isDark
                ? Icons.dark_mode_rounded
                : Icons.light_mode_rounded,
            label: preferences.isDark
                ? strings.text('切换到浅色模式', 'Switch to light mode')
                : strings.text('切换到深色模式', 'Switch to dark mode'),
            onPressed: preferences.toggleTheme,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (controller.isDemo) const _DemoPill(),
          if (!controller.isAdmin && member != null) ...[
            const SizedBox(height: 16),
            ProfileRatingCard(snapshot: controller.snapshot),
          ],
          if (preferences.saveFailed) ...[
            const SizedBox(height: 8),
            Text(
              strings.text(
                '设置已应用，但未能保存到本设备。',
                'Settings applied, but could not be saved on this device.',
              ),
              textAlign: TextAlign.right,
              style: TextStyle(
                color: context.doraPalette.warning,
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              onAudits();
            },
            icon: const Icon(Icons.fact_check_outlined),
            label: Text(strings.text('查看修改记录', 'View change log')),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: controller.busy
                ? null
                : () {
                    Navigator.pop(context);
                    controller.signOut();
                  },
            icon: const Icon(Icons.logout_rounded),
            label: Text(
              controller.isAdmin
                  ? strings.text('管理员退出', 'Sign out admin')
                  : strings.text('切换成员 / 退出', 'Switch member / sign out'),
            ),
            style: TextButton.styleFrom(
              foregroundColor: context.doraPalette.danger,
            ),
          ),
        ],
      ),
    );
  }
}

class _PreferenceToggleButton extends StatelessWidget {
  const _PreferenceToggleButton({
    super.key,
    required this.active,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final bool active;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.doraPalette;
    return Semantics(
      button: true,
      toggled: active,
      label: label,
      child: Tooltip(
        message: label,
        child: IconButton(
          onPressed: onPressed,
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          padding: const EdgeInsets.all(10),
          style: IconButton.styleFrom(
            backgroundColor: active ? palette.forestSoft : palette.paperDeep,
            foregroundColor: palette.forest,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: palette.line),
            ),
          ),
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) {
              final rotation = Tween<double>(
                begin: -.08,
                end: 0,
              ).animate(animation);
              return RotationTransition(
                turns: rotation,
                child: FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(scale: animation, child: child),
                ),
              );
            },
            child: Icon(icon, key: ValueKey<bool>(active), size: 21),
          ),
        ),
      ),
    );
  }
}

class _RenameRoomSheet extends StatefulWidget {
  const _RenameRoomSheet({required this.controller, required this.room});

  final ClubController controller;
  final ClubRoom room;

  @override
  State<_RenameRoomSheet> createState() => _RenameRoomSheetState();
}

class _RenameRoomSheetState extends State<_RenameRoomSheet> {
  late final TextEditingController _input;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _input = TextEditingController(text: widget.room.name);
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _input.text.trim();
    if (name.isEmpty || name.runes.length > 30) {
      setState(() => _error = '房间名称须为 1–30 个字符');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    widget.controller.clearFeedback();
    final ok = await widget.controller.renameRoom(widget.room.id, name);
    if (!mounted) return;
    if (ok) {
      _showSnack(context, '房间名称已更新');
      Navigator.of(context).pop();
    } else {
      setState(() {
        _saving = false;
        _error = widget.controller.error ?? '保存失败，请重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return _SheetFrame(
      eyebrow: 'ROOM NAME',
      title: strings.text('修改房间名称', 'Rename room'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _input,
            autofocus: true,
            enabled: !_saving,
            textCapitalization: TextCapitalization.words,
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(
              labelText: strings.text('显示名称', 'Display name'),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            _FeedbackBanner(message: _error!, tone: _FeedbackTone.error),
          ],
          const SizedBox(height: 22),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(
                _saving
                    ? strings.text('保存中…', 'Saving…')
                    : strings.text('保存', 'Save'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SingleTextSheet extends StatefulWidget {
  const _SingleTextSheet({
    required this.eyebrow,
    required this.title,
    required this.label,
    required this.initial,
    required this.action,
  });

  final String eyebrow;
  final String title;
  final String label;
  final String initial;
  final String action;

  @override
  State<_SingleTextSheet> createState() => _SingleTextSheetState();
}

class _SingleTextSheetState extends State<_SingleTextSheet> {
  late final TextEditingController _input;

  @override
  void initState() {
    super.initState();
    _input = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _SheetFrame(
    eyebrow: widget.eyebrow,
    title: widget.title,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _input,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          onSubmitted: (_) => Navigator.pop(context, _input.text.trim()),
          decoration: InputDecoration(labelText: widget.label),
        ),
        const SizedBox(height: 22),
        FilledButton(
          onPressed: () => Navigator.pop(context, _input.text.trim()),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text(widget.action),
          ),
        ),
      ],
    ),
  );
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({
    required this.eyebrow,
    required this.title,
    required this.child,
    this.titleTrailing,
  });

  final String eyebrow;
  final String title;
  final Widget child;
  final Widget? titleTrailing;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.doraPalette.card,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: context.doraPalette.line,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                _Eyebrow(text: eyebrow),
                const SizedBox(height: 6),
                if (titleTrailing == null)
                  Text(title, style: Theme.of(context).textTheme.headlineSmall)
                else
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                      const SizedBox(width: 12),
                      titleTrailing!,
                    ],
                  ),
                const SizedBox(height: 20),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.controller,
    required this.onProfile,
    required this.title,
    this.brand = false,
  });

  final ClubController controller;
  final VoidCallback onProfile;
  final String title;
  final bool brand;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final palette = context.doraPalette;
    final display = controller.isAdmin
        ? (controller.snapshot.adminName ?? strings.text('管理员', 'Admin'))
        : (controller.member?.name ?? strings.text('成员', 'Member'));
    final avatar = CircleAvatar(
      radius: 21,
      backgroundColor: controller.isAdmin ? palette.forest : palette.lime,
      foregroundColor: controller.isAdmin ? palette.onForest : palette.onLime,
      child: Text(
        display.characters.first.toUpperCase(),
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
    );
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                brand
                    ? strings.text('UCSD 麻将社', 'Dora Mahjong Club')
                    : strings.text(title),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  letterSpacing: brand ? .2 : 1.7,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                brand
                    ? strings.text('Dora Mahjong Club', 'UCSD 麻将社')
                    : strings.text('UCSD 麻将社', 'Dora Mahjong Club'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: palette.muted, fontSize: 11),
              ),
            ],
          ),
        ),
        if (controller.isDemo)
          const Padding(
            padding: EdgeInsets.only(right: 9),
            child: _DemoPill(compact: true),
          ),
        Semantics(
          button: true,
          container: true,
          label:
              '${strings.text('打开', 'Open')} $display ${strings.text('个人设置', 'profile settings')}',
          child: InkWell(
            key: const ValueKey('open-profile'),
            onTap: onProfile,
            borderRadius: BorderRadius.circular(24),
            child: Padding(padding: const EdgeInsets.all(4), child: avatar),
          ),
        ),
      ],
    );
  }
}

class _DetailTopBar extends StatelessWidget {
  const _DetailTopBar({
    required this.title,
    required this.subtitle,
    required this.onBack,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      IconButton(
        onPressed: onBack,
        tooltip: context.t('返回', 'Back'),
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      const SizedBox(width: 3),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(color: context.doraPalette.muted, fontSize: 12),
            ),
          ],
        ),
      ),
      ?trailing,
    ],
  );
}

class _DemoBanner extends StatelessWidget {
  const _DemoBanner({this.onAdmin});

  final VoidCallback? onAdmin;

  @override
  Widget build(BuildContext context) {
    final palette = context.doraPalette;
    final message = Text(
      context.t('演示模式 · 数据仅保存在此设备', 'Demo mode · data stays on this device'),
      style: TextStyle(
        color: palette.onLime,
        fontSize: 12,
        fontWeight: FontWeight.w800,
      ),
    );
    final action = onAdmin == null
        ? null
        : TextButton(
            onPressed: onAdmin,
            style: TextButton.styleFrom(
              foregroundColor: palette.onLime,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              minimumSize: const Size(48, 48),
            ),
            child: Text(context.t('管理员体验', 'Try admin demo')),
          );
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 360;
        return Container(
          padding: const EdgeInsets.fromLTRB(14, 9, 6, 9),
          decoration: BoxDecoration(
            color: palette.lime,
            borderRadius: BorderRadius.circular(16),
          ),
          child: narrow && action != null
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.auto_awesome_rounded,
                          color: palette.onLime,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: message),
                      ],
                    ),
                    Align(alignment: Alignment.centerRight, child: action),
                  ],
                )
              : Row(
                  children: [
                    Icon(
                      Icons.auto_awesome_rounded,
                      color: palette.onLime,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: message),
                    ?action,
                  ],
                ),
        );
      },
    );
  }
}

class _DemoPill extends StatelessWidget {
  const _DemoPill({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.doraPalette;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 5 : 7,
      ),
      decoration: BoxDecoration(
        color: palette.lime,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        compact ? context.t('演示', 'Demo') : context.t('演示模式', 'Demo mode'),
        style: TextStyle(
          color: palette.onLime,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow({required this.text, this.light = false});

  final String text;
  final bool light;

  @override
  Widget build(BuildContext context) {
    final palette = context.doraPalette;
    return Text(
      text,
      style: TextStyle(
        color: light ? palette.onForest.withValues(alpha: .72) : palette.muted,
        fontSize: 10,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.5,
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.text,
    required this.active,
    this.inverted = false,
  });

  final String text;
  final bool active;
  final bool inverted;

  @override
  Widget build(BuildContext context) {
    final palette = context.doraPalette;
    final background = inverted
        ? palette.onForest.withValues(alpha: .15)
        : active
        ? palette.lime
        : palette.paperDeep;
    final foreground = inverted
        ? palette.onForest
        : active
        ? palette.onLime
        : palette.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: foreground,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

enum _InfoTone { neutral, good, warning }

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.tone,
  });

  final IconData icon;
  final String title;
  final String body;
  final _InfoTone tone;

  @override
  Widget build(BuildContext context) {
    final palette = context.doraPalette;
    final color = tone == _InfoTone.good
        ? palette.forestSoft
        : tone == _InfoTone.warning
        ? palette.warningSoft
        : palette.paperDeep;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(17),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: tone == _InfoTone.warning ? palette.warning : palette.forest,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: TextStyle(
                    color: palette.muted,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _FeedbackTone { error }

class _FeedbackBanner extends StatelessWidget {
  const _FeedbackBanner({required this.message, required this.tone});

  final String message;
  final _FeedbackTone tone;

  @override
  Widget build(BuildContext context) {
    final palette = context.doraPalette;
    final error = tone == _FeedbackTone.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: error ? palette.errorSoft : palette.forestSoft,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            error
                ? Icons.error_outline_rounded
                : Icons.check_circle_outline_rounded,
            color: error ? palette.danger : palette.forest,
            size: 19,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              doraMessage(context, message),
              style: TextStyle(
                color: error ? palette.danger : palette.forest,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final palette = context.doraPalette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 30),
      decoration: BoxDecoration(
        color: palette.paperDeep.withValues(alpha: .6),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Icon(icon, color: palette.forest, size: 33),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 5),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.muted, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _MahjongMark extends StatelessWidget {
  const _MahjongMark({this.size = 82});

  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _MahjongMarkPainter(palette: context.doraPalette),
  );
}

class _MahjongMarkPainter extends CustomPainter {
  const _MahjongMarkPainter({required this.palette});

  final DoraPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final tile = Rect.fromLTWH(
      size.width * .16,
      size.height * .07,
      size.width * .68,
      size.height * .84,
    );
    final shadow = RRect.fromRectAndRadius(
      tile.shift(Offset(size.width * .04, size.height * .06)),
      Radius.circular(size.width * .12),
    );
    canvas.drawRRect(
      shadow,
      Paint()..color = palette.forest.withValues(alpha: .13),
    );
    final rrect = RRect.fromRectAndRadius(
      tile,
      Radius.circular(size.width * .12),
    );
    canvas.drawRRect(rrect, Paint()..color = palette.card);
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = palette.forest
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * .035,
    );
    final inner = tile.deflate(size.width * .11);
    canvas.drawRRect(
      RRect.fromRectAndRadius(inner, Radius.circular(size.width * .08)),
      Paint()..color = palette.lime.withValues(alpha: .65),
    );
    final dot = Paint()..color = palette.onLime;
    canvas.drawCircle(
      Offset(size.width * .5, size.height * .34),
      size.width * .065,
      dot,
    );
    canvas.drawCircle(
      Offset(size.width * .4, size.height * .53),
      size.width * .065,
      dot,
    );
    canvas.drawCircle(
      Offset(size.width * .6, size.height * .53),
      size.width * .065,
      dot,
    );
    canvas.drawCircle(
      Offset(size.width * .5, size.height * .72),
      size.width * .065,
      dot,
    );
  }

  @override
  bool shouldRepaint(covariant _MahjongMarkPainter oldDelegate) =>
      oldDelegate.palette != palette;
}

class _MissingPage extends StatelessWidget {
  const _MissingPage({required this.onBack, required this.title});

  final VoidCallback onBack;
  final String title;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.sync_problem_rounded,
              color: context.doraPalette.forest,
              size: 40,
            ),
            const SizedBox(height: 14),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              context.t(
                '请返回并刷新最新状态。',
                'Go back and refresh for the latest state.',
              ),
              style: TextStyle(color: context.doraPalette.muted),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: onBack,
              child: Text(context.t('返回', 'Back')),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String confirm,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(context.t('取消', 'Cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return result == true;
}

void _showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(doraMessage(context, message)),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

String _formatDate(DateTime value) {
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.year}/$month/$day  $hour:$minute';
}
