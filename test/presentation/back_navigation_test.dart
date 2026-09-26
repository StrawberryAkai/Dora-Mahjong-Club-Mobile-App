import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dora_mahjong/app.dart';
import 'package:dora_mahjong/application/club_controller.dart';
import 'package:dora_mahjong/data/demo_club_repository.dart';
import 'package:dora_mahjong/domain/models.dart';

class _RemovableHistoryEventRepository extends DemoClubRepository {
  bool removeHistoryEvent = false;

  @override
  Future<ClubSnapshot> load() async {
    final snapshot = await super.load();
    if (!removeHistoryEvent) return snapshot;
    return ClubSnapshot(
      members: snapshot.members,
      rooms: snapshot.rooms,
      games: snapshot.games,
      audits: snapshot.audits,
      memberId: snapshot.memberId,
      isAdmin: snapshot.isAdmin,
      adminName: snapshot.adminName,
      ratingSchemaVersion: snapshot.ratingSchemaVersion,
      events: snapshot.events
          .where((event) => event.id != 'demo-event-history')
          .toList(),
      eventSchemaVersion: snapshot.eventSchemaVersion,
    );
  }
}

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

Future<void> _pump(WidgetTester tester, ClubController controller) async {
  tester.view.physicalSize = const ui.Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  await tester.pumpWidget(DoraApp(controller: controller));
  await tester.pumpAndSettle();
}

Future<void> _back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

Future<void> _tapTab(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void _expectTab(WidgetTester tester, int index) {
  expect(find.byType(NavigationBar), findsOneWidget);
  expect(
    tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
    index,
  );
}

Future<void> _openRoom9162(WidgetTester tester) async {
  final roomLink = find.text('查看房间').last;
  await tester.ensureVisible(roomLink);
  await tester.tap(roomLink);
  await tester.pumpAndSettle();
}

Future<void> _openGameRoom(WidgetTester tester) async {
  await tester.tap(find.byTooltip('查看房间'));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() {
    TestWidgetsFlutterBinding.ensureInitialized().reset();
  });

  testWidgets('rooms -> room 9162 -> game -> room 9162 -> rooms', (
    tester,
  ) async {
    final controller = await _controller();
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    await _openRoom9162(tester);
    expect(find.text('CURRENT GAME'), findsOneWidget);
    await tester.tap(find.text('CURRENT GAME'));
    await tester.pumpAndSettle();
    expect(find.text('PLAYERS / SCORES'), findsOneWidget);

    await _back(tester);
    expect(find.text('CURRENT GAME'), findsOneWidget);
    expect(find.text('PLAYERS / SCORES'), findsNothing);

    // The visible arrow must consume the same prior-page entry as system back.
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    _expectTab(tester, 0);
    expect(find.text('查看房间'), findsNWidgets(2));
  });

  testWidgets(
    'game -> room returns to its originating pending or history tab',
    (tester) async {
      final controller = await _controller();
      addTearDown(controller.dispose);
      await _pump(tester, controller);

      await _tapTab(tester, '待录入');
      await tester.tap(find.text('9162'));
      await tester.pumpAndSettle();
      expect(find.text('PLAYERS / SCORES'), findsOneWidget);
      await _openGameRoom(tester);
      await _back(tester);
      expect(find.text('PLAYERS / SCORES'), findsOneWidget);
      await _back(tester);
      _expectTab(tester, 1);
      expect(find.text('等待其他成员'), findsOneWidget);

      await _tapTab(tester, '记录');
      await tester.tap(find.text('7699'));
      await tester.pumpAndSettle();
      expect(find.text('对局结果'), findsOneWidget);
      await _openGameRoom(tester);
      await _back(tester);
      expect(find.text('对局结果'), findsOneWidget);
      await _back(tester);
      _expectTab(tester, 2);
      expect(find.text('我参与的'), findsOneWidget);
    },
  );

  testWidgets(
    'tab back uses the actual prior tab and ignores a duplicate tap',
    (tester) async {
      final controller = await _controller();
      addTearDown(controller.dispose);
      await _pump(tester, controller);

      await _tapTab(tester, '待录入');
      await _tapTab(tester, '记录');
      await _tapTab(tester, '记录');

      await _back(tester);
      _expectTab(tester, 1);
      expect(find.text('等待其他成员'), findsOneWidget);

      await _back(tester);
      _expectTab(tester, 0);
      expect(find.text('查看房间'), findsNWidgets(2));
    },
  );

  testWidgets('two system backs during tab animations pop two locations', (
    tester,
  ) async {
    final controller = await _controller();
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    await tester.tap(find.text('待录入').last);
    await tester.pump(const Duration(milliseconds: 30));
    await tester.tap(find.text('记录').last);
    await tester.pump(const Duration(milliseconds: 30));

    // The AnimatedSwitcher is still transitioning when both back requests land.
    await tester.binding.handlePopRoute();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    _expectTab(tester, 0);
    expect(find.text('查看房间'), findsNWidgets(2));
  });

  testWidgets('event detail restores across tabs and selection adds no page', (
    tester,
  ) async {
    final controller = await _controller();
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    await _tapTab(tester, '活动');
    await tester.tap(find.text('演示历史活动'));
    await tester.pumpAndSettle();
    expect(find.text('活动说明'), findsOneWidget);

    await _tapTab(tester, '记录');
    await _back(tester);
    expect(find.text('活动说明'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('event-detail-demo-event-history')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('event-detail-back')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('event-card-demo-event-history')),
      findsOneWidget,
    );
    await _back(tester);
    _expectTab(tester, 0);

    await _tapTab(tester, '活动');
    await tester.tap(find.text('演示历史活动'));
    await tester.pumpAndSettle();
    final selector = find.byKey(const ValueKey('event-ranking-selector'));
    await tester.ensureVisible(selector);
    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Demo 进行中活动').last);
    await tester.pumpAndSettle();
    expect(find.text('Demo 进行中活动'), findsAtLeastNWidgets(1));

    await _back(tester);
    expect(
      find.byKey(const ValueKey('event-card-demo-event-history')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('event-detail-demo-event-active')),
      findsNothing,
    );
    await _back(tester);
    _expectTab(tester, 0);
  });

  testWidgets('removed outgoing event detail recovers without stale history', (
    tester,
  ) async {
    final repository = _RemovableHistoryEventRepository();
    final controller = ClubController(repository);
    await controller.initialize();
    await controller.selectMember('andy');
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    await _tapTab(tester, '活动');
    await tester.tap(find.text('演示历史活动'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('event-detail-demo-event-history')),
      findsOneWidget,
    );

    repository.removeHistoryEvent = true;
    await controller.refresh(quiet: true);
    await tester.pump(); // Schedule event recovery while detail is current.

    // Switch tabs before settling the recovery transition. The old detail stays
    // mounted briefly as an AnimatedSwitcher child while the shell changes.
    await tester.tap(find.text('记录').last);
    await tester.pump(const Duration(milliseconds: 30));
    await tester.pumpAndSettle();
    _expectTab(tester, 2);
    expect(find.text('我参与的'), findsOneWidget);

    await _back(tester);
    expect(
      find.byKey(const ValueKey('event-card-demo-event-active')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('event-detail-demo-event-history')),
      findsNothing,
    );
    await _back(tester);
    _expectTab(tester, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('system back closes profile and score-entry sheets first', (
    tester,
  ) async {
    final controller = await _controller();
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    await _tapTab(tester, '待录入');
    await tester.tap(find.byKey(const ValueKey('open-profile')));
    await tester.pumpAndSettle();
    expect(find.text('当前MMR'), findsOneWidget);
    await _back(tester);
    expect(find.text('当前MMR'), findsNothing);
    expect(find.text('等待其他成员'), findsOneWidget);
    _expectTab(tester, 1);

    await tester.tap(find.text('9162'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xiong'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);

    await _back(tester);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('PLAYERS / SCORES'), findsOneWidget);
    await _back(tester);
    expect(find.text('等待其他成员'), findsOneWidget);
    _expectTab(tester, 1);
  });

  testWidgets('change log back returns to the tab that opened profile', (
    tester,
  ) async {
    final controller = await _controller();
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    await _tapTab(tester, '记录');
    await tester.tap(find.byKey(const ValueKey('open-profile')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看修改记录'));
    await tester.pumpAndSettle();
    expect(find.text('修改记录'), findsOneWidget);

    await _back(tester);
    expect(find.text('修改记录'), findsNothing);
    expect(find.text('我参与的'), findsOneWidget);
    _expectTab(tester, 2);
  });

  testWidgets(
    'room sheets and dialogs close before navigation; root back stays',
    (tester) async {
      final controller = await _controller(admin: true);
      addTearDown(controller.dispose);
      await _pump(tester, controller);
      await _openRoom9162(tester);

      await tester.tap(find.byTooltip('管理房间'));
      await tester.pumpAndSettle();
      expect(find.text('清理全部座位'), findsOneWidget);
      await _back(tester);
      expect(find.text('清理全部座位'), findsNothing);
      expect(find.text('9162'), findsOneWidget);

      await tester.tap(find.byTooltip('管理房间'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('清理全部座位'));
      await tester.pumpAndSettle();
      expect(find.text('清理全部座位？'), findsOneWidget);
      await _back(tester);
      expect(find.text('清理全部座位？'), findsNothing);
      expect(find.text('9162'), findsOneWidget);

      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      _expectTab(tester, 0);

      final platformMethods = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        platformMethods.add(call.method);
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );

      await _back(tester);
      _expectTab(tester, 0);
      expect(find.text('查看房间'), findsNWidgets(2));
      expect(platformMethods, isNot(contains('SystemNavigator.pop')));
    },
  );

  testWidgets('logout clears prior navigation before a member signs in again', (
    tester,
  ) async {
    final controller = await _controller();
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    await _tapTab(tester, '待录入');
    await _tapTab(tester, '记录');
    await tester.tap(find.byKey(const ValueKey('open-profile')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('切换成员 / 退出'));
    await tester.pumpAndSettle();
    expect(find.text('选择成员'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'A');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Andy'));
    await tester.pumpAndSettle();
    _expectTab(tester, 0);

    await _back(tester);
    _expectTab(tester, 0);
    expect(find.text('查看房间'), findsNWidgets(2));
  });
}
