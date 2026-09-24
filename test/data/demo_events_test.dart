import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:dora_mahjong/data/demo_club_repository.dart';
import 'package:dora_mahjong/domain/models.dart';

ClubGame _game(ClubSnapshot snapshot, String id) =>
    snapshot.games.singleWhere((game) => game.id == id);

Future<void> _selectAndy(DemoClubRepository repository) =>
    repository.selectMember('andy');

Future<ClubGame> _startFresh(
  DemoClubRepository repository, {
  String? eventId,
  String requestId = 'event-start',
}) async {
  final seeded = (await repository.load()).activeGame('room-9162')!;
  await _selectAndy(repository);
  await repository.cancelGame(
    seeded.id,
    'reset seeded game for event test',
    seeded.version,
    '$requestId-cancel',
  );
  await repository.startGame('room-9162', requestId, eventId: eventId);
  return (await repository.load()).activeGame('room-9162')!;
}

Future<ClubGame> _saveAll(
  DemoClubRepository repository,
  ClubGame current,
) async {
  for (final entry in const {
    'andy': 50000,
    'zoey': 30000,
    'jin': 20000,
    'xiong': 0,
  }.entries) {
    await repository.saveScore(
      current.id,
      entry.key,
      entry.value,
      current.version,
      'event-score-${entry.key}-${current.version}',
    );
    current = _game(await repository.load(), current.id);
  }
  return current;
}

EventDraft _draft({
  String? id,
  int? expectedVersion,
  String name = 'Local event',
  DateTime? startsAt,
  DateTime? endsAt,
  List<String> roomIds = const ['room-7699'],
}) {
  final now = DateTime.now().toUtc();
  return EventDraft(
    id: id,
    expectedVersion: expectedVersion,
    name: name,
    description: 'A local event',
    startsAt: startsAt ?? now.add(const Duration(hours: 1)),
    endsAt: endsAt ?? now.add(const Duration(hours: 2)),
    roomIds: roomIds,
  );
}

void main() {
  test(
    'seeds labelled events and links matching games by room and time',
    () async {
      final snapshot = await DemoClubRepository().load();
      final history = _game(snapshot, 'demo-history');
      final active = _game(snapshot, 'demo-active');

      expect(snapshot.eventSchemaVersion, 1);
      expect(snapshot.events, hasLength(3));
      expect(
        snapshot.events.every(
          (event) => event.name.contains('Demo') || event.name.contains('演示'),
        ),
        isTrue,
      );
      expect(history.eventId, 'demo-event-history');
      expect(active.eventId, 'demo-event-active');
      expect(
        snapshot.events
            .singleWhere((event) => event.id == history.eventId)
            .roomIds,
        contains(history.roomId),
      );
      expect(
        snapshot.events
            .singleWhere((event) => event.id == history.eventId)
            .isActiveAt(history.startedAt),
        isTrue,
      );
      expect(
        snapshot.events
            .singleWhere((event) => event.id == active.eventId)
            .isActiveAt(active.startedAt),
        isTrue,
      );
      expect(
        snapshot.events.any((event) => event.startsAt.isAfter(DateTime.now())),
        isTrue,
      );
    },
  );

  test(
    'event writes require admin, are idempotent, and use versions',
    () async {
      final repository = DemoClubRepository();
      final original = await repository.load();
      await _selectAndy(repository);
      await expectLater(
        repository.saveEvent(_draft(), 'member-event'),
        throwsA(isA<ClubException>()),
      );
      expect(
        (await repository.load()).events,
        hasLength(original.events.length),
      );

      await repository.signInAdmin('demo', 'demo');
      final draft = _draft(name: '  New Demo event  ');
      await repository.saveEvent(draft, 'create-event');
      final created = (await repository.load()).events.singleWhere(
        (event) => event.name == 'New Demo event',
      );
      expect(created.version, 0);
      await repository.saveEvent(draft, 'create-event');
      expect(
        (await repository.load()).events.where(
          (event) => event.id == created.id,
        ),
        hasLength(1),
      );

      await repository.saveEvent(
        _draft(id: created.id, expectedVersion: 0, name: 'Edited event'),
        'edit-event',
      );
      final edited = (await repository.load()).events.singleWhere(
        (event) => event.id == created.id,
      );
      expect(edited.version, 1);
      await expectLater(
        repository.saveEvent(
          _draft(id: created.id, expectedVersion: 0, name: 'Stale event'),
          'stale-event',
        ),
        throwsA(
          isA<ClubException>().having(
            (error) => error.isConflict,
            'conflict',
            isTrue,
          ),
        ),
      );
    },
  );

  test('failed event persistence leaves state and request retryable', () async {
    var fail = true;
    final repository = DemoClubRepository(
      persist: (value) async {
        if (fail && (value['events'] as List).length > 3) {
          throw StateError('disk full');
        }
      },
    );
    await repository.signInAdmin('demo', 'demo');
    final draft = _draft(name: 'Retryable event');
    await expectLater(
      repository.saveEvent(draft, 'retry-event'),
      throwsA(isA<StateError>()),
    );
    expect(
      (await repository.load()).events.where(
        (event) => event.name == draft.name,
      ),
      isEmpty,
    );
    fail = false;
    await repository.saveEvent(draft, 'retry-event');
    expect(
      (await repository.load()).events.where(
        (event) => event.name == draft.name,
      ),
      hasLength(1),
    );
  });

  test('editing an event cannot exclude an already linked game', () async {
    final repository = DemoClubRepository();
    final snapshot = await repository.load();
    final event = snapshot.events.singleWhere(
      (entry) => entry.id == 'demo-event-active',
    );
    final linkedGame = _game(snapshot, 'demo-active');
    await repository.signInAdmin('demo', 'demo');

    await expectLater(
      repository.saveEvent(
        _draft(
          id: event.id,
          expectedVersion: event.version,
          startsAt: linkedGame.startedAt.subtract(const Duration(hours: 1)),
          endsAt: linkedGame.startedAt.subtract(const Duration(minutes: 1)),
          roomIds: [linkedGame.roomId],
        ),
        'shrink-event-window',
      ),
      throwsA(isA<ClubException>()),
    );
    await expectLater(
      repository.saveEvent(
        _draft(
          id: event.id,
          expectedVersion: event.version,
          startsAt: event.startsAt,
          endsAt: event.endsAt,
          roomIds: ['room-7699'],
        ),
        'remove-linked-room',
      ),
      throwsA(isA<ClubException>()),
    );
    expect(
      (await repository.load()).events
          .singleWhere((entry) => entry.id == event.id)
          .version,
      event.version,
    );
  });

  test(
    'start validates active in-room events and preserves selection on retry',
    () async {
      final invalidRepository = DemoClubRepository();
      final snapshot = await invalidRepository.load();
      final activeEvent = snapshot.events.singleWhere(
        (event) => event.id == 'demo-event-active',
      );
      final historyEvent = snapshot.events.singleWhere(
        (event) => event.id == 'demo-event-history',
      );
      await expectLater(
        _startFresh(invalidRepository, eventId: historyEvent.id),
        throwsA(isA<ClubException>()),
      );

      final repository = DemoClubRepository();
      final started = await _startFresh(
        repository,
        eventId: activeEvent.id,
        requestId: 'selected-start',
      );
      expect(started.eventId, activeEvent.id);

      await repository.cancelGame(
        started.id,
        'retry selection',
        started.version,
        'retry-selection-cancel',
      );
      await repository.startGame(
        'room-9162',
        'same-selection-request',
        eventId: activeEvent.id,
      );
      await repository.cancelGame(
        (await repository.load()).activeGame('room-9162')!.id,
        'change selection',
        (await repository.load()).activeGame('room-9162')!.version,
        'change-selection-cancel',
      );
      await expectLater(
        repository.startGame('room-9162', 'same-selection-request'),
        throwsA(isA<ClubException>()),
      );
    },
  );

  test(
    'eventId survives score completion, correction, cancellation, and reload',
    () async {
      final repository = DemoClubRepository();
      final active = await _startFresh(
        repository,
        eventId: 'demo-event-active',
      );
      final completed = await _saveAll(repository, active);
      expect(completed.eventId, 'demo-event-active');

      await _selectAndy(repository);
      await repository.correctScores(
        completed.id,
        {'andy': 50000, 'zoey': 30000, 'jin': 15000, 'xiong': 5000},
        completed.version,
        'event-correction',
      );
      expect(
        _game(await repository.load(), completed.id).eventId,
        'demo-event-active',
      );

      await repository.startGame(
        'room-9162',
        'cancel-start',
        eventId: 'demo-event-active',
      );
      final cancelled = (await repository.load()).activeGame('room-9162')!;
      await repository.cancelGame(
        cancelled.id,
        'cancel event game',
        cancelled.version,
        'event-cancel',
      );
      expect(
        _game(await repository.load(), cancelled.id).eventId,
        'demo-event-active',
      );

      final persisted = (await repository.load()).toJson();
      final reloaded = await DemoClubRepository(
        saved: jsonDecode(jsonEncode(persisted)),
      ).load();
      expect(_game(reloaded, completed.id).eventId, 'demo-event-active');
      expect(reloaded.events, hasLength(3));
      expect(reloaded.eventSchemaVersion, 1);
    },
  );

  test(
    'legacy snapshots gain labelled events without auto-linking games',
    () async {
      final legacy = (await DemoClubRepository().load()).toJson();
      legacy.remove('events');
      legacy.remove('event_schema_version');
      for (final value in legacy['games'] as List) {
        (value as Map).remove('event_id');
      }
      final loaded = await DemoClubRepository(saved: legacy).load();

      expect(loaded.events, hasLength(2));
      expect(
        loaded.events.any((event) => event.isActiveAt(DateTime.now())),
        isTrue,
      );
      expect(
        loaded.events.any((event) => event.startsAt.isAfter(DateTime.now())),
        isTrue,
      );
      expect(
        loaded.events.every(
          (event) => event.name.contains('Demo') || event.name.contains('演示'),
        ),
        isTrue,
      );
      expect(loaded.games.every((game) => game.eventId == null), isTrue);
      expect(
        loaded.members.map((member) => member.mmr),
        (await DemoClubRepository().load()).members.map((member) => member.mmr),
      );
    },
  );
}
