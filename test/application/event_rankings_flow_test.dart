import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:dora_mahjong/application/club_controller.dart';
import 'package:dora_mahjong/data/demo_club_repository.dart';
import 'package:dora_mahjong/domain/leaderboard.dart';
import 'package:dora_mahjong/domain/models.dart';

class _LostCorrectionResponseRepository extends DemoClubRepository {
  var loseNextCorrectionResponse = true;

  @override
  Future<void> correctScores(
    String gameId,
    Map<String, int> scores,
    int expectedVersion,
    String requestId,
  ) async {
    await super.correctScores(gameId, scores, expectedVersion, requestId);
    if (loseNextCorrectionResponse) {
      loseNextCorrectionResponse = false;
      throw StateError('simulated lost correction response');
    }
  }
}

ClubGame _game(ClubSnapshot snapshot, String id) =>
    snapshot.games.singleWhere((game) => game.id == id);

Map<String, double> _ptByMember(List<LeaderboardEntry> entries) => {
  for (final entry in entries) entry.memberId: entry.pt,
};

Map<String, double> _mmrByMember(ClubSnapshot snapshot) => {
  for (final member in snapshot.members) member.id: member.mmr,
};

Future<ClubGame> _completeGame(
  ClubController controller,
  ClubGame initial,
  Map<String, int> scores,
) async {
  var current = initial;
  for (final entry in scores.entries) {
    expect(await controller.saveScore(current, entry.key, entry.value), isTrue);
    current = _game(controller.snapshot, current.id);
  }
  return current;
}

EventDraft _eventEdit(ClubEvent event, {required String name}) => EventDraft(
  id: event.id,
  expectedVersion: event.version,
  name: name,
  description: '  Updated from the application flow.  ',
  startsAt: event.startsAt,
  endsAt: event.endsAt,
  roomIds: List<String>.from(event.roomIds),
);

void main() {
  test(
    'controller completion updates global and event PT boards once across correction retry and reload',
    () async {
      final repository = _LostCorrectionResponseRepository();
      final controller = ClubController(repository);
      addTearDown(controller.dispose);
      await controller.initialize();

      const eventId = 'demo-event-active';
      expect(await controller.selectMember('andy'), isTrue);
      final seeded = controller.snapshot.activeGame('room-9162')!;
      expect(
        await controller.cancelGame(seeded, 'reset for event ranking flow'),
        isTrue,
      );
      expect(await controller.startGame('room-9162', eventId: eventId), isTrue);

      final started = controller.snapshot.activeGame('room-9162')!;
      expect(started.eventId, eventId);
      final completed = await _completeGame(controller, started, const {
        'andy': 50000,
        'zoey': 30000,
        'jin': 20000,
        'xiong': 0,
      });
      expect(completed.status, GameStatus.completed);
      expect(completed.eventId, eventId);

      final eventBefore = buildLeaderboard(
        controller.snapshot,
        eventId: eventId,
      );
      final globalPtBefore = buildLeaderboard(
        controller.snapshot,
        metric: LeaderboardMetric.pt,
      );
      expect(eventBefore, hasLength(4));
      expect(eventBefore.every((entry) => entry.gamesPlayed == 1), isTrue);
      expect(_ptByMember(eventBefore), isNotEmpty);
      expect(_ptByMember(globalPtBefore), containsPair('andy', isA<double>()));

      final correctedScores = const {
        'andy': 35000,
        'zoey': 30000,
        'jin': 20000,
        'xiong': 15000,
      };
      final eventGameBeforeCorrection = completed;
      final beforeAuditCount = controller.snapshot.audits.length;
      expect(
        await controller.correctScores(
          eventGameBeforeCorrection,
          correctedScores,
        ),
        isFalse,
      );
      expect(controller.lastActionConflict, isFalse);
      expect(controller.error, isNotNull);

      final eventAfterFirstAttempt = buildLeaderboard(
        controller.snapshot,
        eventId: eventId,
      );
      final globalPtAfterFirstAttempt = buildLeaderboard(
        controller.snapshot,
        metric: LeaderboardMetric.pt,
      );
      expect(
        _ptByMember(eventAfterFirstAttempt),
        isNot(equals(_ptByMember(eventBefore))),
      );
      expect(
        _ptByMember(globalPtAfterFirstAttempt),
        isNot(equals(_ptByMember(globalPtBefore))),
      );
      expect(controller.snapshot.audits, hasLength(beforeAuditCount + 1));
      expect(_game(controller.snapshot, completed.id).eventId, eventId);

      // The first request committed before its response was lost. Retrying
      // the same controller action must replay the request without a second
      // correction or a second leaderboard contribution.
      expect(
        await controller.correctScores(
          eventGameBeforeCorrection,
          correctedScores,
        ),
        isTrue,
      );
      expect(controller.snapshot.audits, hasLength(beforeAuditCount + 1));
      expect(
        _ptByMember(buildLeaderboard(controller.snapshot, eventId: eventId)),
        equals(_ptByMember(eventAfterFirstAttempt)),
      );
      expect(
        _ptByMember(
          buildLeaderboard(controller.snapshot, metric: LeaderboardMetric.pt),
        ),
        equals(_ptByMember(globalPtAfterFirstAttempt)),
      );

      final encoded = jsonEncode(controller.snapshot.toJson());
      final reloaded = await DemoClubRepository(
        saved: jsonDecode(encoded) as Map<String, dynamic>,
      ).load();
      expect(_game(reloaded, completed.id).eventId, eventId);
      expect(
        _ptByMember(buildLeaderboard(reloaded, eventId: eventId)),
        equals(_ptByMember(eventAfterFirstAttempt)),
      );
      expect(
        _ptByMember(buildLeaderboard(reloaded, metric: LeaderboardMetric.pt)),
        equals(_ptByMember(globalPtAfterFirstAttempt)),
      );
    },
  );

  test(
    'legacy snapshot upgrade keeps old games unlinked and ratings unchanged in controller rankings',
    () async {
      final original = await DemoClubRepository().load();
      final originalMmr = _mmrByMember(original);
      final legacy =
          jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>;
      legacy.remove('events');
      legacy.remove('event_schema_version');
      for (final value in legacy['games'] as List) {
        (value as Map).remove('event_id');
      }

      final controller = ClubController(DemoClubRepository(saved: legacy));
      addTearDown(controller.dispose);
      await controller.initialize();

      expect(controller.snapshot.eventSchemaVersion, 1);
      expect(controller.snapshot.events, hasLength(2));
      expect(
        controller.snapshot.games.every((game) => game.eventId == null),
        isTrue,
      );
      expect(_mmrByMember(controller.snapshot), equals(originalMmr));
      expect(
        controller.snapshot.games
            .where((game) => game.status == GameStatus.completed)
            .every((game) => game.settlement != null),
        isTrue,
      );

      final upgradedEvent = controller.snapshot.events.first;
      expect(
        buildLeaderboard(controller.snapshot, eventId: upgradedEvent.id),
        isEmpty,
      );
    },
  );

  test(
    'controller reports an event version conflict while preserving the draft for safe retry',
    () async {
      final repository = DemoClubRepository();
      final editor = ClubController(repository);
      final concurrentEditor = ClubController(repository);
      addTearDown(editor.dispose);
      addTearDown(concurrentEditor.dispose);
      await editor.initialize();
      expect(await editor.signInAdmin('demo', 'demo'), isTrue);

      final original = editor.snapshot.events.singleWhere(
        (event) => event.id == 'demo-event-active',
      );
      final draft = _eventEdit(original, name: '  Pending editor name  ');
      final draftBefore = jsonEncode(draft.toJson());

      await concurrentEditor.initialize();
      expect(
        await concurrentEditor.saveEvent(
          _eventEdit(original, name: 'Concurrent winning edit'),
        ),
        isTrue,
      );
      expect(
        editor.snapshot.events
            .singleWhere((event) => event.id == original.id)
            .version,
        original.version,
      );

      expect(await editor.saveEvent(draft), isFalse);
      expect(editor.lastActionConflict, isTrue);
      expect(editor.error, contains('活动已被更新'));
      expect(jsonEncode(draft.toJson()), draftBefore);
      expect(
        editor.snapshot.events
            .singleWhere((event) => event.id == original.id)
            .name,
        'Concurrent winning edit',
      );

      final refreshed = editor.snapshot.events.singleWhere(
        (event) => event.id == original.id,
      );
      final retryDraft = EventDraft(
        id: draft.id,
        expectedVersion: refreshed.version,
        name: draft.name,
        description: draft.description,
        startsAt: draft.startsAt,
        endsAt: draft.endsAt,
        roomIds: draft.roomIds,
      );
      expect(await editor.saveEvent(retryDraft), isTrue);
      expect(
        editor.snapshot.events
            .singleWhere((event) => event.id == original.id)
            .name,
        'Pending editor name',
      );
    },
  );
}
