import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dora_mahjong/application/app_preferences.dart';
import 'package:dora_mahjong/application/club_controller.dart';
import 'package:dora_mahjong/data/demo_club_repository.dart';
import 'package:dora_mahjong/domain/models.dart';
import 'package:dora_mahjong/presentation/dora_app.dart';
import 'package:dora_mahjong/presentation/leaderboard_page.dart';

void main() {
  tearDown(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.clearTextScaleFactorTestValue();
    binding.reset();
  });

  testWidgets('ranking list lazily appends pages while keeping rows unique', (
    tester,
  ) async {
    final controller = _controllerFor(_snapshot(memberCount: 163));
    addTearDown(controller.dispose);
    await _pumpRanking(tester, controller, width: 390);

    expect(find.byKey(const ValueKey('global-leaderboard')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('global-leaderboard-metric')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('ranking-list')), findsOneWidget);
    expect(_mountedRankingRows(tester), lessThan(40));
    expect(find.byKey(_rowKey('member-0000')), findsOneWidget);
    expect(find.byKey(_rowKey('member-0162')), findsNothing);

    await _dragToBottom(tester);
    await _scrollToRow(tester, 'member-0050');
    expect(find.byKey(_rowKey('member-0050')), findsOneWidget);
    expect(find.byKey(_rowKey('member-0162')), findsNothing);

    await _dragToBottom(tester);
    await _scrollToRow(tester, 'member-0100');
    expect(find.byKey(_rowKey('member-0100')), findsOneWidget);
    expect(_mountedRankingRows(tester), lessThan(40));

    await _dragToBottom(tester);
    await _scrollToRow(tester, 'member-0162');
    expect(find.byKey(_rowKey('member-0162')), findsOneWidget);
    expect(find.byKey(_rowKey('member-0163')), findsNothing);
    expect(find.byKey(const ValueKey('ranking-load-more')), findsNothing);
  });

  testWidgets(
    'deep current row is revealed while searches stay on their first page',
    (tester) async {
      final controller = _controllerFor(
        _snapshot(memberCount: 1000, memberId: 'member-0777'),
      );
      addTearDown(controller.dispose);
      await _pumpRanking(tester, controller, width: 390);

      expect(find.byKey(const ValueKey('my-ranking')), findsNothing);
      final currentRow = find.byKey(_rowKey('member-0777'));
      expect(currentRow, findsOneWidget);
      expect(
        find.descendant(of: currentRow, matching: find.text('778')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: currentRow,
          matching: find.byKey(const ValueKey('ranking-self-badge')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: currentRow, matching: find.text('我')),
        findsOneWidget,
      );
      expect(_mountedRankingRows(tester), lessThan(40));
      _expectRowInListViewport(tester, 'member-0777');

      // An empty-query metric change still locates the current row. PT has a
      // tie for every member in this fixture, so the row keeps actual rank 1
      // even though it is the 778th list item.
      await tester.tap(find.text('累计PT'));
      await tester.pumpAndSettle();
      final ptCurrentRow = find.byKey(_rowKey('member-0777'));
      expect(ptCurrentRow, findsOneWidget);
      expect(
        find.descendant(of: ptCurrentRow, matching: find.text('1')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: ptCurrentRow,
          matching: find.byKey(const ValueKey('ranking-self-badge')),
        ),
        findsOneWidget,
      );
      expect(_mountedRankingRows(tester), lessThan(40));
      _expectRowInListViewport(tester, 'member-0777');

      await tester.tap(find.text('MMR').first);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(_rowKey('member-0777')),
          matching: find.text('778'),
        ),
        findsOneWidget,
      );

      final search = find.byKey(const ValueKey('ranking-search'));
      await tester.enterText(search, '  TARGET  ');
      await tester.pumpAndSettle();
      expect(find.byKey(_rowKey('member-0057')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(_rowKey('member-0057')),
          matching: find.text('58'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('my-ranking')), findsNothing);
      expect(find.byKey(_rowKey('member-0777')), findsNothing);

      await tester.enterText(search, '目标');
      await tester.pumpAndSettle();
      expect(find.byKey(_rowKey('member-0777')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(_rowKey('member-0777')),
          matching: find.text('778'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(_rowKey('member-0777')),
          matching: find.byKey(const ValueKey('ranking-self-badge')),
        ),
        findsOneWidget,
      );

      await tester.enterText(search, 'definitely-not-a-member');
      await tester.pumpAndSettle();
      expect(find.text('没有找到匹配的成员'), findsOneWidget);
      expect(find.byKey(_rowKey('member-0777')), findsNothing);
      expect(find.byKey(const ValueKey('my-ranking')), findsNothing);
      expect(find.byKey(const ValueKey('ranking-self-badge')), findsNothing);
      expect(
        find.byKey(const ValueKey('ranking-clear-search')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('ranking-clear-search')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(search).controller?.text, isEmpty);
      expect(find.byKey(_rowKey('member-0000')), findsOneWidget);
      expect(find.byKey(_rowKey('member-0777')), findsNothing);
      expect(find.byKey(const ValueKey('ranking-self-badge')), findsNothing);
    },
  );

  testWidgets('reentering the leaderboard repositions the current row', (
    tester,
  ) async {
    final controller = _controllerFor(
      _snapshot(memberCount: 1000, memberId: 'member-0777'),
    );
    addTearDown(controller.dispose);
    await _pumpRanking(tester, controller, width: 390);
    expect(find.byKey(_rowKey('member-0777')), findsOneWidget);
    _expectRowInListViewport(tester, 'member-0777');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(find.byKey(_rowKey('member-0777')), findsNothing);

    await _pumpRanking(tester, controller, width: 390);
    final currentRow = find.byKey(_rowKey('member-0777'));
    expect(currentRow, findsOneWidget);
    expect(
      find.descendant(of: currentRow, matching: find.text('778')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: currentRow,
        matching: find.byKey(const ValueKey('ranking-self-badge')),
      ),
      findsOneWidget,
    );
    expect(_mountedRankingRows(tester), lessThan(40));
    _expectRowInListViewport(tester, 'member-0777');
  });

  testWidgets(
    'metric selection changes the order and resets to the first page',
    (tester) async {
      final controller = _controllerFor(_snapshotWithPt(memberCount: 120));
      addTearDown(controller.dispose);
      await _pumpRanking(tester, controller, width: 390);

      expect(find.byKey(_rowKey('member-0000')), findsOneWidget);
      await _dragToBottom(tester);
      await _scrollToRow(tester, 'member-0100');
      expect(find.byKey(_rowKey('member-0100')), findsOneWidget);

      await tester.tap(find.text('累计PT'));
      await tester.pumpAndSettle();
      expect(find.byKey(_rowKey('member-0119')), findsOneWidget);
      expect(find.byKey(_rowKey('member-0100')), findsNothing);
    },
  );

  testWidgets(
    'pending metric reveal follows a refreshed ranking before its frame',
    (tester) async {
      final initial = _snapshotWithPt(
        memberCount: 120,
        memberId: 'member-0119',
      );
      final repository = _SnapshotRepository(initial);
      final controller = _controllerFor(initial, repository: repository);
      addTearDown(controller.dispose);
      await _pumpRanking(tester, controller, width: 390);

      // The PT ordering places the selected member first, so this establishes
      // a first-page position before the MMR reveal is scheduled.
      await tester.tap(find.text('累计PT'));
      await tester.pumpAndSettle();
      expect(find.byKey(_rowKey('member-0119')), findsOneWidget);

      // Tap MMR but hold the frame. The pending reveal initially targets the
      // old MMR index. Refresh the same identity into a new ranking where the
      // member is at index 70 (rank 71), beyond the first page.
      await tester.tap(find.text('MMR').first);
      final refreshedMembers = [
        for (final member in _members(120, decorateTargets: false))
          member.id == 'member-0119'
              ? Member(id: member.id, name: member.name, mmr: 2930.5)
              : member,
      ];
      repository.snapshot = ClubSnapshot(
        members: refreshedMembers,
        memberId: 'member-0119',
      );
      await controller.refresh();
      await tester.pumpAndSettle();

      final currentRow = find.byKey(_rowKey('member-0119'));
      expect(currentRow, findsOneWidget);
      expect(
        find.descendant(of: currentRow, matching: find.text('71')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: currentRow,
          matching: find.byKey(const ValueKey('ranking-self-badge')),
        ),
        findsOneWidget,
      );
      _expectRowInListViewport(tester, 'member-0119');
      expect(_mountedRankingRows(tester), lessThan(40));
    },
  );

  testWidgets('controller refresh preserves search and the loaded page depth', (
    tester,
  ) async {
    final initial = _snapshot(memberCount: 180, decorateTargets: false);
    final repository = _SnapshotRepository(initial);
    final controller = _controllerFor(initial, repository: repository);
    addTearDown(controller.dispose);
    await _pumpRanking(tester, controller, width: 390);

    final search = find.byKey(const ValueKey('ranking-search'));
    await tester.enterText(search, 'player');
    await tester.pumpAndSettle();
    await _dragToBottom(tester);
    await _scrollToRow(tester, 'member-0099');
    expect(find.byKey(_rowKey('member-0099')), findsOneWidget);

    final refreshedMembers = [
      const Member(id: 'member-0000', name: 'Player 0000', mmr: 5000),
      ..._members(240, decorateTargets: false).skip(1),
    ];
    repository.snapshot = ClubSnapshot(members: refreshedMembers);
    await controller.refresh();
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(search).controller?.text, 'player');
    expect(find.byKey(_rowKey('member-0000')), findsNothing);
    expect(find.byKey(_rowKey('member-0099')), findsOneWidget);
    expect(find.byKey(_rowKey('member-0239')), findsNothing);
  });

  testWidgets(
    'English dark ranking remains usable at 320px with large text and keyboard',
    (tester) async {
      final preferences = AppPreferences(isEnglish: true, isDark: true);
      addTearDown(preferences.dispose);
      final controller = _controllerFor(
        _snapshot(
          memberCount: 80,
          memberId: 'member-0070',
          decorateTargets: false,
        ),
      );
      addTearDown(controller.dispose);
      await _pumpRanking(
        tester,
        controller,
        preferences: preferences,
        width: 320,
        height: 640,
        textScale: 1.5,
        navigationHeight: 80,
      );

      expect(find.text('Ranking'), findsOneWidget);
      expect(find.byKey(const ValueKey('my-ranking')), findsNothing);
      expect(find.byKey(const ValueKey('ranking-search')), findsOneWidget);
      final currentRow = find.byKey(_rowKey('member-0070'));
      expect(currentRow, findsOneWidget);
      expect(
        find.descendant(of: currentRow, matching: find.text('Me')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: currentRow,
          matching: find.byKey(const ValueKey('ranking-self-badge')),
        ),
        findsOneWidget,
      );
      final search = find.byKey(const ValueKey('ranking-search'));
      await tester.ensureVisible(search);
      await tester.pumpAndSettle();
      await tester.tap(search);
      await tester.showKeyboard(search);
      await tester.enterText(search, 'Player');
      await tester.pumpAndSettle();
      await _pumpRanking(
        tester,
        controller,
        preferences: preferences,
        width: 320,
        height: 640,
        textScale: 1.5,
        keyboardInset: 300,
        navigationHeight: 80,
      );
      expect(tester.widget<TextField>(search).controller!.text, 'Player');
      final editable = find.descendant(
        of: search,
        matching: find.byType(EditableText),
      );
      expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isTrue);
      await _dragToBottom(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('administrator view does not render a personal rank card', (
    tester,
  ) async {
    final controller = _controllerFor(
      _snapshot(memberCount: 80, memberId: 'member-0007', isAdmin: true),
    );
    addTearDown(controller.dispose);
    await _pumpRanking(tester, controller, width: 390);

    expect(find.byKey(const ValueKey('my-ranking')), findsNothing);
    expect(find.byKey(_rowKey('member-0007')), findsOneWidget);
    expect(find.byKey(const ValueKey('ranking-self-badge')), findsNothing);
  });
}

Future<void> _pumpRanking(
  WidgetTester tester,
  ClubController controller, {
  AppPreferences? preferences,
  required double width,
  double height = 844,
  double textScale = 1,
  double keyboardInset = 0,
  double navigationHeight = 0,
}) async {
  tester.view.physicalSize = ui.Size(width * 3, height * 3);
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;

  final app = MaterialApp(
    locale: preferences?.locale,
    theme: DoraTheme.light,
    darkTheme: DoraTheme.dark,
    themeMode: preferences?.themeMode ?? ThemeMode.light,
    home: MediaQuery(
      data: MediaQueryData(
        size: ui.Size(width, height),
        devicePixelRatio: 3,
        textScaler: TextScaler.linear(textScale),
        viewInsets: EdgeInsets.only(bottom: keyboardInset),
      ),
      child: Scaffold(
        bottomNavigationBar: SizedBox(height: navigationHeight),
        body: ListenableBuilder(
          listenable: controller,
          builder: (context, child) =>
              LeaderboardPage(controller: controller, onProfile: () {}),
        ),
      ),
    ),
  );
  await tester.pumpWidget(
    preferences == null
        ? app
        : AppPreferencesScope(preferences: preferences, child: app),
  );
  await tester.pumpAndSettle();
}

Future<void> _dragToBottom(WidgetTester tester) async {
  final list = find.byKey(const ValueKey('ranking-list'));
  await tester.drag(list, const Offset(0, -10000));
  await tester.pumpAndSettle();
}

Future<void> _scrollToRow(WidgetTester tester, String memberId) async {
  final row = find.byKey(_rowKey(memberId));
  await tester.scrollUntilVisible(
    row,
    500,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.pumpAndSettle();
}

void _expectRowInListViewport(WidgetTester tester, String memberId) {
  final listRect = tester.getRect(find.byKey(const ValueKey('ranking-list')));
  final rowRect = tester.getRect(find.byKey(_rowKey(memberId)));
  expect(rowRect.overlaps(listRect), isTrue);
}

int _mountedRankingRows(WidgetTester tester) {
  return find
      .byWidgetPredicate((widget) {
        final key = widget.key;
        return key is ValueKey &&
            key.value is String &&
            (key.value as String).startsWith('leaderboard-');
      })
      .evaluate()
      .length;
}

ValueKey<String> _rowKey(String memberId) =>
    ValueKey<String>('leaderboard-$memberId');

ClubController _controllerFor(
  ClubSnapshot snapshot, {
  _SnapshotRepository? repository,
}) {
  final controller = ClubController(
    repository ?? _SnapshotRepository(snapshot),
  );
  controller.snapshot = snapshot;
  controller.loading = false;
  return controller;
}

class _SnapshotRepository extends DemoClubRepository {
  _SnapshotRepository(this.snapshot);

  ClubSnapshot snapshot;

  @override
  Future<ClubSnapshot> load() async => snapshot;
}

ClubSnapshot _snapshot({
  required int memberCount,
  String? memberId,
  bool isAdmin = false,
  bool decorateTargets = true,
}) {
  return ClubSnapshot(
    members: _members(memberCount, decorateTargets: decorateTargets),
    memberId: memberId,
    isAdmin: isAdmin,
  );
}

ClubSnapshot _snapshotWithPt({required int memberCount, String? memberId}) {
  final members = _members(memberCount, decorateTargets: false);
  final settlement = GameSettlement(
    ruleVersion: 'synthetic',
    order: 1,
    revision: 1,
    settledAt: DateTime(2026, 1, 1),
    players: [
      for (var index = 0; index < members.length; index++)
        PlayerSettlement(
          memberId: members[index].id,
          finalPoints: 0,
          actualUma: 0,
          pt: index + 1,
          oldMmr: members[index].mmr,
          mmrDelta: 0,
          newMmr: members[index].mmr,
        ),
    ],
  );
  return ClubSnapshot(
    members: members,
    memberId: memberId,
    games: [
      ClubGame(
        id: 'synthetic-game',
        roomId: 'synthetic-room',
        creatorId: members.first.id,
        players: const [],
        startedAt: DateTime(2026, 1, 1),
        status: GameStatus.completed,
        completedAt: DateTime(2026, 1, 1),
        settlement: settlement,
      ),
    ],
  );
}

List<Member> _members(int count, {bool decorateTargets = true}) => [
  for (var index = 0; index < count; index++)
    Member(
      id: 'member-${index.toString().padLeft(4, '0')}',
      name: !decorateTargets
          ? 'Player ${index.toString().padLeft(4, '0')}'
          : switch (index) {
              57 => 'English Target',
              777 => '中文目标',
              _ => 'Player ${index.toString().padLeft(4, '0')}',
            },
      mmr: (3000 - index).toDouble(),
    ),
];
