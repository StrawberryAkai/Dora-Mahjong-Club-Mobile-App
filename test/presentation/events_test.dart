import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dora_mahjong/app.dart';
import 'package:dora_mahjong/application/app_preferences.dart';
import 'package:dora_mahjong/application/club_controller.dart';
import 'package:dora_mahjong/data/demo_club_repository.dart';

Future<ClubController> _controller({bool admin = false}) async {
  final controller = ClubController(DemoClubRepository());
  await controller.initialize();
  if (admin) {
    await controller.signInAdmin('demo', 'demo');
  } else {
    await controller.selectMember('andy');
  }
  return controller;
}

Future<void> _pump(
  WidgetTester tester,
  ClubController controller, {
  double width = 390,
  AppPreferences? preferences,
}) async {
  tester.view.physicalSize = ui.Size(width * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  await tester.pumpWidget(
    DoraApp(controller: controller, preferences: preferences),
  );
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.reset();
  });

  testWidgets('events cards open detail and switch event ranking activity', (
    tester,
  ) async {
    final controller = await _controller();
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    await tester.tap(find.text('活动').last);
    await tester.pumpAndSettle();
    expect(find.text('演示历史活动'), findsOneWidget);
    expect(find.text('Demo 进行中活动'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('event-card-demo-event-history')),
      findsOneWidget,
    );

    await tester.tap(find.text('演示历史活动'));
    await tester.pumpAndSettle();
    expect(find.text('活动说明'), findsOneWidget);
    expect(find.text('活动排名'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('event-ranking-selector')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('event-ranking-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Demo 进行中活动').last);
    await tester.pumpAndSettle();
    expect(find.text('Demo 进行中活动'), findsAtLeastNWidgets(1));
    expect(
      find.byKey(const ValueKey('event-leaderboard-demo-event-active')),
      findsOneWidget,
    );
  });

  testWidgets('global ranking toggles between MMR and cumulative PT', (
    tester,
  ) async {
    final controller = await _controller();
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    await tester.tap(find.text('排名').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('global-leaderboard')), findsOneWidget);
    expect(find.text('当前MMR'), findsNothing);
    expect(find.text('累计PT'), findsOneWidget);

    await tester.tap(find.text('累计PT'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('global-leaderboard')), findsOneWidget);
  });

  testWidgets(
    'events and ranking stay readable in English dark mode at 320px',
    (tester) async {
      final controller = await _controller();
      final preferences = AppPreferences(isEnglish: true, isDark: true);
      addTearDown(controller.dispose);
      addTearDown(preferences.dispose);
      await _pump(tester, controller, width: 320, preferences: preferences);
      await tester.tap(find.text('Events').last);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('event-card-demo-event-history')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Ranking').last);
      await tester.pumpAndSettle();
      expect(find.text('Ranking'), findsAtLeastNWidgets(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('profile rating card gives PT and MMR equal columns', (
    tester,
  ) async {
    final controller = await _controller();
    addTearDown(controller.dispose);
    await _pump(tester, controller);
    await tester.tap(find.byKey(const ValueKey('open-profile')));
    await tester.pumpAndSettle();

    final card = find.byKey(const ValueKey('profile-rating-card'));
    expect(card, findsOneWidget);
    expect(find.text('累计PT'), findsOneWidget);
    expect(find.text('当前MMR'), findsOneWidget);
    final columns = find.descendant(of: card, matching: find.byType(Expanded));
    expect(columns, findsNWidgets(2));
    expect(
      tester.getSize(columns.at(0)).width,
      closeTo(tester.getSize(columns.at(1)).width, .01),
    );
  });

  testWidgets('start sheet distinguishes cancellation and event association', (
    tester,
  ) async {
    final controller = await _controller();
    addTearDown(controller.dispose);
    final active = controller.snapshot.activeGame('room-9162');
    expect(active, isNotNull);
    await controller.cancelGame(active!, 'test selection');
    await _pump(tester, controller);

    await tester.tap(find.text('查看房间').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始对局'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('start-casual-game')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cancel-start-game')));
    await tester.pumpAndSettle();
    expect(controller.snapshot.activeGame('room-9162'), isNull);

    await tester.tap(find.text('开始对局'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('start-event-demo-event-active')),
    );
    await tester.pumpAndSettle();
    expect(
      controller.snapshot.activeGame('room-9162')?.eventId,
      'demo-event-active',
    );
  });

  testWidgets(
    'editing an event preserves second precision and accepts an 80 character name',
    (tester) async {
      final seed = DemoClubRepository();
      final snapshot = await seed.load();
      final linkedGame = snapshot.games
          .where((game) => game.eventId == 'demo-event-history')
          .first;
      final saved = snapshot.toJson();
      final eventJson = (saved['events'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((event) => event['id'] == 'demo-event-history');
      final boundaryStart = linkedGame.startedAt.subtract(
        const Duration(hours: 1, seconds: 7),
      );
      final boundaryEnd = linkedGame.startedAt.add(const Duration(seconds: 7));
      eventJson['starts_at'] = boundaryStart.toUtc().toIso8601String();
      eventJson['ends_at'] = boundaryEnd.toUtc().toIso8601String();
      saved['is_admin'] = true;
      saved['admin_name'] = '演示管理员';
      final controller = ClubController(DemoClubRepository(saved: saved));
      addTearDown(controller.dispose);
      await controller.initialize();
      await _pump(tester, controller, width: 320);

      await tester.tap(find.text('活动').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('演示历史活动'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('edit-event')));
      await tester.pumpAndSettle();
      final longName = 'A' * 80;
      await tester.enterText(
        find.byKey(const ValueKey('event-name-field')),
        longName,
      );
      expect(find.text(longName), findsOneWidget);
      final saveButton = find.byKey(const ValueKey('save-event'));
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await tester.ensureVisible(saveButton);
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      final updated = controller.snapshot.events
          .where((event) => event.id == 'demo-event-history')
          .first;
      expect(updated.name, longName);
      expect(updated.version, 1);
      expect(updated.startsAt, boundaryStart.toUtc());
      expect(updated.endsAt, boundaryEnd.toUtc());
      expect(controller.error, isNull);
      final selector = find.byKey(const ValueKey('event-ranking-selector'));
      await tester.ensureVisible(selector);
      await tester.tap(selector);
      await tester.pumpAndSettle();
      expect(find.text(longName), findsAtLeastNWidgets(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('admin event editor is gated and preserves the editable fields', (
    tester,
  ) async {
    final memberController = await _controller();
    addTearDown(memberController.dispose);
    await _pump(tester, memberController);
    await tester.tap(find.text('活动').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('create-event')), findsNothing);

    final adminController = await _controller(admin: true);
    addTearDown(adminController.dispose);
    await _pump(tester, adminController);
    await tester.tap(find.text('活动').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('create-event')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('event-name-field')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('event-name-field')),
      'New event',
    );
    expect(find.text('New event'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cancel-event-editor')));
    await tester.pumpAndSettle();
    expect(find.text('New event'), findsNothing);
  });
}
