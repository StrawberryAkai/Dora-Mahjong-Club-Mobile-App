import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dora_mahjong/app.dart';
import 'package:dora_mahjong/application/app_preferences.dart';
import 'package:dora_mahjong/application/club_controller.dart';
import 'package:dora_mahjong/data/demo_club_repository.dart';
import 'package:dora_mahjong/domain/models.dart';
import 'package:dora_mahjong/presentation/dora_app.dart';
import 'package:dora_mahjong/presentation/rating_widgets.dart';

Future<ClubController> localController({bool selectAndy = false}) async {
  final controller = ClubController(DemoClubRepository());
  await controller.initialize();
  if (selectAndy) await controller.selectMember('andy');
  return controller;
}

Future<void> pumpDora(
  WidgetTester tester,
  ClubController controller, {
  required double width,
  double height = 844,
  double textScale = 1,
  AppPreferences? preferences,
}) async {
  tester.view.physicalSize = ui.Size(width * 3, height * 3);
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  await tester.pumpWidget(
    DoraApp(controller: controller, preferences: preferences),
  );
  await tester.pumpAndSettle();
}

void expectNoFrameworkException(WidgetTester tester) {
  expect(tester.takeException(), isNull);
}

Finder profileButton() => find.byKey(const ValueKey('open-profile'));

void main() {
  tearDown(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.clearTextScaleFactorTestValue();
    binding.reset();
  });

  testWidgets('member entry remains usable at 390px and 320px', (tester) async {
    final controller = await localController();
    addTearDown(controller.dispose);

    for (final width in <double>[390, 320]) {
      await pumpDora(tester, controller, width: width, textScale: 1.25);
      expect(find.text('选择成员'), findsOneWidget);
      expect(find.text('演示模式 · 数据仅保存在此设备'), findsOneWidget);
      expect(find.text('按姓名首字搜索已有成员'), findsOneWidget);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(find.text('创建新成员'), findsOneWidget);
      expectNoFrameworkException(tester);
    }
  });

  testWidgets(
    'member search hides names until a non-whitespace prefix is entered',
    (tester) async {
      final controller = await localController();
      addTearDown(controller.dispose);

      await pumpDora(tester, controller, width: 390);
      final search = find.byType(TextField).first;

      expect(find.text('Andy'), findsNothing);
      expect(find.text('Amy'), findsNothing);
      expect(find.text('小明'), findsNothing);

      await tester.enterText(search, ' ');
      await tester.pump();
      expect(find.text('Andy'), findsNothing);
      expect(find.text('Amy'), findsNothing);

      await tester.enterText(search, 'A');
      await tester.pump();
      expect(find.text('Andy'), findsOneWidget);
      expect(find.text('Amy'), findsOneWidget);
      expect(find.text('Zoey'), findsNothing);

      await tester.enterText(search, 'a');
      await tester.pump();
      expect(find.text('Andy'), findsOneWidget);
      expect(find.text('Amy'), findsOneWidget);

      await tester.enterText(search, '小');
      await tester.pump();
      expect(find.text('小明'), findsOneWidget);
      expect(find.text('Andy'), findsNothing);

      await tester.enterText(search, '');
      await tester.pump();
      expect(find.text('Andy'), findsNothing);
      expect(find.text('Amy'), findsNothing);
      expect(find.text('小明'), findsNothing);
      expectNoFrameworkException(tester);
    },
  );

  testWidgets(
    'local demo shell routes render and remain navigable on mobile widths',
    (tester) async {
      final controller = await localController(selectAndy: true);
      addTearDown(controller.dispose);

      await pumpDora(tester, controller, width: 390);
      expect(find.text('你好，Andy'), findsNothing);
      expect(find.text('7699'), findsAtLeastNWidgets(1));
      expect(find.text('9162'), findsAtLeastNWidgets(1));
      expect(find.text('房间'), findsOneWidget);
      expect(find.text('待录入'), findsOneWidget);
      expect(find.text('记录'), findsOneWidget);
      expectNoFrameworkException(tester);

      await tester.tap(find.text('待录入'));
      await tester.pumpAndSettle();
      expect(find.text('让每一份成绩\n落到桌面上。'), findsNothing);
      expect(find.text('等待其他成员'), findsOneWidget);
      expectNoFrameworkException(tester);

      await tester.tap(find.text('记录').last);
      await tester.pumpAndSettle();
      expect(find.text('每一场都留在桌边。'), findsNothing);
      expect(find.text('我参与的'), findsOneWidget);
      expect(find.text('俱乐部'), findsOneWidget);
      expect(find.text('7699'), findsOneWidget);
      await tester.tap(find.text('俱乐部'));
      await tester.pumpAndSettle();
      expect(find.text('7699'), findsOneWidget);
      expectNoFrameworkException(tester);

      await tester.tap(find.text('房间').last);
      await tester.pumpAndSettle();
      expect(find.text('查看房间'), findsNWidgets(2));
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -360));
      await tester.pump(const Duration(milliseconds: 300));
      final secondRoomLink = find.text('查看房间').last;
      await tester.ensureVisible(secondRoomLink);
      await tester.tap(secondRoomLink);
      await tester.pumpAndSettle();
      expect(find.text('CURRENT GAME'), findsOneWidget);
      expect(find.text('东'), findsAtLeastNWidgets(1));
      expect(find.text('南'), findsAtLeastNWidgets(1));
      expect(find.text('西'), findsAtLeastNWidgets(1));
      expect(find.text('北'), findsAtLeastNWidgets(1));
      expectNoFrameworkException(tester);

      await tester.tap(find.text('CURRENT GAME'));
      await tester.pumpAndSettle();
      expect(find.text('PLAYERS / SCORES'), findsOneWidget);
      expect(find.text('对局中'), findsOneWidget);
      expect(find.text('Andy'), findsAtLeastNWidgets(1));
      expect(find.text('Zoey'), findsAtLeastNWidgets(1));
      expect(find.text('Jin'), findsAtLeastNWidgets(1));
      expect(find.text('Xiong'), findsAtLeastNWidgets(1));
      expectNoFrameworkException(tester);
    },
  );

  testWidgets(
    'a seated member can move, leave, or remove another idle seat from a sheet',
    (tester) async {
      final controller = await localController();
      addTearDown(controller.dispose);
      await controller.selectMember('xiaoming');
      await controller.sit('room-7699', Wind.west);
      await controller.selectMember('amy');
      await controller.sit('room-7699', Wind.east);

      await pumpDora(tester, controller, width: 390);
      await tester.tap(find.text('查看房间').first);
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel(RegExp('南位，空位')));
      await tester.pumpAndSettle();

      ClubRoom currentRoom() => controller.snapshot.rooms.singleWhere(
        (room) => room.id == 'room-7699',
      );
      expect(currentRoom().seats, {Wind.south: 'amy', Wind.west: 'xiaoming'});
      expect(find.bySemanticsLabel(RegExp('东位，空位')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('南位，Amy')), findsOneWidget);

      await tester.tap(find.bySemanticsLabel(RegExp('西位，小明')));
      await tester.pumpAndSettle();
      expect(find.text('小明'), findsAtLeastNWidgets(1));
      final removePlayer = find.text('移除玩家');
      expect(removePlayer, findsOneWidget);
      final removeButton = find.ancestor(
        of: removePlayer,
        matching: find.byWidgetPredicate(
          (widget) => widget is ButtonStyleButton,
        ),
      );
      expect(
        tester
            .widget<ButtonStyleButton>(removeButton)
            .style
            ?.backgroundColor
            ?.resolve({}),
        Theme.of(tester.element(removeButton)).extension<DoraPalette>()!.danger,
      );
      expect(currentRoom().seats, {Wind.south: 'amy', Wind.west: 'xiaoming'});

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(currentRoom().seats, {Wind.south: 'amy', Wind.west: 'xiaoming'});

      await tester.tap(find.bySemanticsLabel(RegExp('西位，小明')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('移除玩家'));
      await tester.pumpAndSettle();
      expect(currentRoom().seats, {Wind.south: 'amy'});

      await tester.tap(find.bySemanticsLabel(RegExp('南位，Amy')));
      await tester.pumpAndSettle();
      expect(currentRoom().seats, isEmpty);
      expectNoFrameworkException(tester);
    },
  );

  testWidgets('English occupied-seat sheet offers Remove player', (
    tester,
  ) async {
    final controller = await localController();
    final preferences = AppPreferences(isEnglish: true);
    addTearDown(controller.dispose);
    addTearDown(preferences.dispose);
    await controller.selectMember('xiaoming');
    await controller.sit('room-7699', Wind.east);
    await controller.selectMember('amy');

    await pumpDora(tester, controller, width: 390, preferences: preferences);
    await tester.tap(find.text('View room').first);
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel(RegExp('East seat, 小明')));
    await tester.pumpAndSettle();

    expect(find.text('Remove player'), findsOneWidget);
    await tester.tap(find.text('Remove player'));
    await tester.pumpAndSettle();
    expect(
      controller.snapshot.rooms
          .singleWhere((room) => room.id == 'room-7699')
          .seats,
      isEmpty,
    );
    expectNoFrameworkException(tester);
  });

  testWidgets(
    'shell also settles without exceptions at 320px with larger text',
    (tester) async {
      final controller = await localController(selectAndy: true);
      addTearDown(controller.dispose);

      await pumpDora(tester, controller, width: 320, textScale: 1.2);
      expect(find.text('你好，Andy'), findsNothing);
      expectNoFrameworkException(tester);

      await tester.tap(find.text('待录入'));
      await tester.pumpAndSettle();
      expect(find.text('等待其他成员'), findsOneWidget);
      expectNoFrameworkException(tester);

      await tester.tap(find.text('记录').last);
      await tester.pumpAndSettle();
      expect(find.text('我参与的'), findsOneWidget);
      expectNoFrameworkException(tester);
    },
  );

  testWidgets(
    'profile preferences update locale and rendered theme while preserving the route',
    (tester) async {
      final controller = await localController(selectAndy: true);
      final preferences = AppPreferences();
      addTearDown(controller.dispose);
      addTearDown(preferences.dispose);

      await pumpDora(tester, controller, width: 390, preferences: preferences);
      expect(find.text('你好，Andy'), findsNothing);
      expect(find.text('UCSD 麻将社'), findsAtLeastNWidgets(1));

      await tester.tap(find.text('待录入'));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        1,
      );

      final profile = profileButton();
      expect(profile, findsOneWidget);
      await tester.ensureVisible(profile);
      await tester.tap(profile);
      await tester.pumpAndSettle();
      expect(find.text('已选择俱乐部成员身份'), findsNothing);
      expect(find.text('刷新俱乐部状态'), findsNothing);
      expect(find.text('当前MMR'), findsOneWidget);

      final languageToggle = find.byKey(
        const ValueKey<String>('toggle-language'),
      );
      final themeToggle = find.byKey(const ValueKey<String>('toggle-theme'));
      expect(languageToggle, findsOneWidget);
      expect(themeToggle, findsOneWidget);
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).locale,
        const Locale('zh', 'CN'),
      );
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.light,
      );
      expect(
        Theme.of(tester.element(languageToggle)).brightness,
        Brightness.light,
      );

      await tester.tap(languageToggle);
      await tester.pumpAndSettle();
      expect(preferences.isEnglish, isTrue);
      expect(find.text('View change log'), findsOneWidget);
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).locale,
        const Locale('en'),
      );
      expect(
        find.byKey(const ValueKey<String>('toggle-language')),
        findsOneWidget,
      );
      expect(find.text('Dora Mahjong Club'), findsAtLeastNWidgets(1));

      await tester.tap(themeToggle);
      await tester.pumpAndSettle();
      expect(preferences.isDark, isTrue);
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );
      expect(
        Theme.of(tester.element(languageToggle)).brightness,
        Brightness.dark,
      );

      await tester.tap(themeToggle);
      await tester.pumpAndSettle();
      expect(preferences.isDark, isFalse);
      expect(
        Theme.of(tester.element(languageToggle)).brightness,
        Brightness.light,
      );

      Navigator.of(tester.element(languageToggle)).pop();
      await tester.pumpAndSettle();
      expect(controller.member?.id, 'andy');
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        1,
      );
      expectNoFrameworkException(tester);
    },
  );

  testWidgets(
    'English shell and profile remain usable at 320px without overflow',
    (tester) async {
      final controller = await localController(selectAndy: true);
      final preferences = AppPreferences(isEnglish: true);
      addTearDown(controller.dispose);
      addTearDown(preferences.dispose);

      await pumpDora(
        tester,
        controller,
        width: 320,
        textScale: 1.2,
        preferences: preferences,
      );
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).locale,
        const Locale('en'),
      );
      expect(find.text('Dora Mahjong Club'), findsAtLeastNWidgets(1));
      expectNoFrameworkException(tester);

      final profile = profileButton();
      expect(profile, findsOneWidget);
      await tester.ensureVisible(profile);
      await tester.tap(profile);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('toggle-language')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('toggle-theme')),
        findsOneWidget,
      );
      expect(find.text('Current MMR'), findsOneWidget);
      expectNoFrameworkException(tester);
    },
  );

  testWidgets(
    'English score correction reports an invalid total without saving',
    (tester) async {
      final controller = await localController(selectAndy: true);
      final preferences = AppPreferences(isEnglish: true, isDark: true);
      addTearDown(controller.dispose);
      addTearDown(preferences.dispose);

      await pumpDora(tester, controller, width: 390, preferences: preferences);
      await tester.tap(find.text('History').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('7699'));
      await tester.pumpAndSettle();
      final correct = find.text('Correct all scores');
      await tester.scrollUntilVisible(correct, 300);
      await Scrollable.ensureVisible(tester.element(correct), alignment: 0.5);
      await tester.pumpAndSettle();
      await tester.tap(correct);
      await tester.pumpAndSettle();

      final before = controller.snapshot.games
          .firstWhere((game) => game.id == 'demo-history')
          .version;
      final inputs = find.byType(TextField);
      expect(inputs, findsNWidgets(4));
      for (var i = 0; i < 4; i++) {
        await tester.enterText(inputs.at(i), i == 0 ? '25100' : '25000');
      }
      final save = find.text('Save correction');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(
        find.text(
          'The four scores must total 100,000. Current total: 100,100.',
        ),
        findsOneWidget,
      );
      expect(
        controller.snapshot.games
            .firstWhere((game) => game.id == 'demo-history')
            .version,
        before,
      );
      expectNoFrameworkException(tester);
    },
  );

  testWidgets(
    'completed result rows stay compact at 320px in English light and dark themes',
    (tester) async {
      for (final isDark in [false, true]) {
        final controller = await localController(selectAndy: true);
        final preferences = AppPreferences(isEnglish: true, isDark: isDark);
        addTearDown(controller.dispose);
        addTearDown(preferences.dispose);

        await pumpDora(
          tester,
          controller,
          width: 320,
          textScale: 1.5,
          preferences: preferences,
        );
        await tester.tap(find.text('History').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('7699'));
        await tester.pumpAndSettle();

        expect(find.byType(RatingSettlementPanel), findsOneWidget);
        for (final memberId in ['andy', 'zoey', 'jin', 'xiong']) {
          expect(find.byKey(ValueKey('game-result-$memberId')), findsOneWidget);
          expect(
            find.byKey(ValueKey('game-result-mmr-$memberId')),
            findsOneWidget,
          );
          expect(
            find.byKey(ValueKey('game-result-pt-$memberId')),
            findsOneWidget,
          );
        }
        expect(find.text('MMR:'), findsNWidgets(4));
        expect(find.text('PT:'), findsNWidgets(4));
        expect(find.text('Single-game PT:'), findsNothing);
        expect(find.text('(38,200)'), findsOneWidget);
        expect(find.text('(27,100)'), findsOneWidget);
        expect(find.textContaining('Rule'), findsNothing);
        expect(find.textContaining('Order'), findsNothing);
        expect(find.textContaining('Revision'), findsNothing);
        expect(
          Theme.of(
            tester.element(find.byType(RatingSettlementPanel)),
          ).brightness,
          isDark ? Brightness.dark : Brightness.light,
        );
        expectNoFrameworkException(tester);
        if (!isDark) {
          await tester.tap(find.byTooltip('Back'));
          await tester.pumpAndSettle();
        }
      }
    },
  );

  testWidgets(
    'external preference changes keep a typed score draft in its open modal',
    (tester) async {
      final controller = await localController(selectAndy: true);
      final preferences = AppPreferences();
      addTearDown(controller.dispose);
      addTearDown(preferences.dispose);

      await pumpDora(tester, controller, width: 390, preferences: preferences);
      await tester.tap(find.text('待录入'));
      await tester.pumpAndSettle();
      final pendingGame = find.text('9162');
      await tester.ensureVisible(pendingGame);
      await tester.tap(pendingGame);
      await tester.pumpAndSettle();
      final xiong = find.text('Xiong');
      await tester.ensureVisible(xiong);
      await tester.tap(xiong);
      await tester.pumpAndSettle();

      final input = find.byType(TextField).last;
      expect(input, findsOneWidget);
      await tester.enterText(input, '25000');
      await tester.pump();
      expect(tester.widget<TextField>(input).controller?.text, '25000');

      await preferences.toggleLanguage();
      await tester.pumpAndSettle();
      await preferences.toggleTheme();
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).last).controller?.text,
        '25000',
      );
      expect(controller.member?.id, 'andy');
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).locale,
        const Locale('en'),
      );
      expect(
        Theme.of(tester.element(find.byType(TextField).last)).brightness,
        Brightness.dark,
      );

      Navigator.of(tester.element(input)).pop();
      await tester.pumpAndSettle();
      expect(find.text('PLAYERS / SCORES'), findsOneWidget);
      expect(controller.member?.id, 'andy');
      expectNoFrameworkException(tester);
    },
  );

  test('rating display formatting preserves required precision', () {
    expect(formatRatingPt(12), '12');
    expect(formatRatingPt(-0.04, signed: true), '0');
    expect(formatRatingMmr(1500), '1500.00');
    expect(formatRatingMmrDelta(2.345), '+2.35');
    expect(formatRatingMmrDelta(-0.004), '0.00');
  });

  testWidgets('rated detail renders compact result rows and revisions', (
    tester,
  ) async {
    final players = [
      const GamePlayer(
        memberId: 'a',
        name: 'Seat name',
        wind: Wind.east,
        score: 30000,
        rank: 1,
      ),
      const GamePlayer(
        memberId: 'b',
        name: 'Second',
        wind: Wind.south,
        score: 30000,
        rank: 2,
      ),
    ];
    GameSettlement settlement(
      int revision,
      double oldMmr,
      double newMmr, {
      double bNewMmr = 1500,
      double aPt = 3.25,
      double bPt = 2,
    }) => GameSettlement(
      ruleVersion: 'riichi-pt-mmr-v1',
      order: 12,
      revision: revision,
      settledAt: DateTime(2026, 9, 22),
      players: [
        PlayerSettlement(
          memberId: 'a',
          finalPoints: 30000,
          actualUma: 15,
          pt: aPt,
          oldMmr: oldMmr,
          mmrDelta: newMmr - oldMmr,
          newMmr: newMmr,
        ),
        PlayerSettlement(
          memberId: 'b',
          finalPoints: 30000,
          actualUma: 15,
          pt: bPt,
          oldMmr: 1500,
          mmrDelta: bNewMmr - 1500,
          newMmr: bNewMmr,
        ),
      ],
    );
    final game = ClubGame(
      id: 'rated',
      roomId: 'room',
      creatorId: 'a',
      players: players,
      startedAt: DateTime(2026, 9, 22),
      status: GameStatus.completed,
      completedAt: DateTime(2026, 9, 22),
      settlement: settlement(2, 1510, 1490, bNewMmr: 1510),
      settlementHistory: [settlement(1, 1500, 1508)],
    );
    final priorGame = ClubGame(
      id: 'prior',
      roomId: 'room',
      creatorId: 'a',
      players: players,
      startedAt: DateTime(2026, 9, 21),
      status: GameStatus.completed,
      completedAt: DateTime(2026, 9, 30),
      settlement: GameSettlement(
        ruleVersion: 'riichi-pt-mmr-v1',
        order: 11,
        revision: 1,
        settledAt: DateTime(2026, 9, 30),
        players: [
          PlayerSettlement(
            memberId: 'a',
            finalPoints: 25000,
            actualUma: 0,
            pt: 1.25,
            oldMmr: 1500,
            mmrDelta: 0,
            newMmr: 1500,
          ),
          PlayerSettlement(
            memberId: 'b',
            finalPoints: 25000,
            actualUma: 0,
            pt: 0.4,
            oldMmr: 1500,
            mmrDelta: 0,
            newMmr: 1500,
          ),
        ],
      ),
    );
    final snapshot = ClubSnapshot(
      members: const [
        Member(id: 'a', name: 'Seat name'),
        Member(id: 'b', name: 'Second'),
      ],
      games: [priorGame, game],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: DoraTheme.light,
        home: Scaffold(
          body: ListView(
            children: [RatingSettlementPanel(game: game, snapshot: snapshot)],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('积分结算'), findsNothing);
    expect(find.text('规则 riichi-pt-mmr-v1'), findsNothing);
    expect(find.text('顺序 12'), findsNothing);
    expect(find.text('修订 2'), findsNothing);
    expect(find.text('Seat name'), findsOneWidget);
    expect(find.text('Second'), findsOneWidget);
    expect(find.text('(30,000)'), findsNWidgets(2));
    expect(find.text('PT:'), findsNWidgets(2));
    expect(find.text('单场PT:'), findsNothing);
    expect(find.text('1490.00'), findsOneWidget);
    expect(find.text('1510.00'), findsOneWidget);
    expect(find.text('(-20.00)'), findsOneWidget);
    expect(find.text('(+10.00)'), findsOneWidget);
    expect(find.text('4.6'), findsOneWidget);
    expect(find.text('2.4'), findsOneWidget);
    expect(find.text('同分玩家共享相同 Uma；座位顺序显示的名次可能不同。'), findsNothing);
    expect(find.text('历史记录'), findsOneWidget);

    final aMmr = find.byKey(const ValueKey('game-result-mmr-a'));
    final aPt = find.byKey(const ValueKey('game-result-pt-a'));
    final bMmr = find.byKey(const ValueKey('game-result-mmr-b'));
    expect(aMmr, findsOneWidget);
    expect(aPt, findsOneWidget);
    expect(bMmr, findsOneWidget);
    expect(
      find.descendant(
        of: aMmr,
        matching: find.byIcon(Icons.arrow_downward_rounded),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: aPt,
        matching: find.byIcon(Icons.arrow_upward_rounded),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: bMmr,
        matching: find.byIcon(Icons.arrow_upward_rounded),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('历史记录'));
    await tester.pumpAndSettle();
    expect(find.text('1508.00'), findsOneWidget);
    expect(find.text('(+3.3)'), findsOneWidget);
    expect(find.text('单场PT:'), findsNWidgets(2));
    expect(find.textContaining('排名 #'), findsNWidgets(4));
    expectNoFrameworkException(tester);
  });

  testWidgets('legacy completed games are explicitly unrated', (tester) async {
    final game = ClubGame(
      id: 'legacy',
      roomId: 'room',
      creatorId: 'a',
      players: const [
        GamePlayer(memberId: 'a', name: 'A', wind: Wind.east, score: 100000),
      ],
      startedAt: DateTime(2026, 9, 22),
      status: GameStatus.completed,
      completedAt: DateTime(2026, 9, 22),
    );
    final snapshot = ClubSnapshot(
      members: const [Member(id: 'a', name: 'A')],
      games: [game],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: DoraTheme.light,
        home: Scaffold(
          body: RatingSettlementPanel(game: game, snapshot: snapshot),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('未纳入积分结算'), findsOneWidget);
    expect(find.text('这场历史对局没有积分结算记录，当前不会自动补算。'), findsOneWidget);
    expectNoFrameworkException(tester);
  });
}
