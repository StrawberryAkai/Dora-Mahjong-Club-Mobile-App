import 'package:flutter_test/flutter_test.dart';

import 'package:dora_mahjong/domain/event_rules.dart';
import 'package:dora_mahjong/domain/models.dart';

void main() {
  final start = DateTime.utc(2026, 1, 1, 10);
  final end = DateTime.utc(2026, 1, 1, 12);
  final rooms = [
    const ClubRoom(id: 'room-a', name: 'A'),
    const ClubRoom(id: 'room-b', name: 'B'),
  ];

  EventDraft draft({
    String? id,
    int? expectedVersion,
    String name = '  Spring Cup  ',
    String description = '  Friendly games  ',
    DateTime? startsAt,
    DateTime? endsAt,
    List<String> roomIds = const ['room-a'],
  }) => EventDraft(
    id: id,
    expectedVersion: expectedVersion,
    name: name,
    description: description,
    startsAt: startsAt ?? start,
    endsAt: endsAt ?? end,
    roomIds: roomIds,
  );

  ClubGame linkedGame({
    String id = 'game-1',
    String roomId = 'room-a',
    DateTime? startedAt,
    String? eventId = 'event-1',
    GameStatus status = GameStatus.completed,
  }) => ClubGame(
    id: id,
    roomId: roomId,
    creatorId: 'creator',
    players: const [],
    startedAt: startedAt ?? start,
    status: status,
    eventId: eventId,
  );

  test('accepts trimmed text, a valid room list, and a creation draft', () {
    expect(() => validateEventDraft(draft(), rooms), returnsNormally);
  });

  test('rejects invalid text, dates, rooms, and id/version combinations', () {
    final invalidDrafts = <EventDraft>[
      draft(name: '   '),
      draft(name: List.filled(81, '名').join()),
      draft(description: List.filled(2001, '字').join()),
      draft(startsAt: end, endsAt: end),
      draft(roomIds: const []),
      draft(roomIds: const ['room-a', 'room-a']),
      draft(roomIds: const ['missing']),
      draft(id: 'event-1'),
      draft(expectedVersion: 0),
      draft(id: 'event-1', expectedVersion: -1),
    ];

    for (final invalid in invalidDrafts) {
      expect(
        () => validateEventDraft(invalid, rooms),
        throwsA(isA<ClubException>()),
        reason: invalid.toJson().toString(),
      );
    }
  });

  test(
    'event edits keep every linked game inside the same time and room scope',
    () {
      final edit = draft(id: 'event-1', expectedVersion: 2);
      expect(
        () => validateEventEdit(edit, [
          linkedGame(status: GameStatus.cancelled),
          linkedGame(id: 'unrelated', eventId: 'other-event'),
        ]),
        returnsNormally,
      );

      final invalidGames = <ClubGame>[
        linkedGame(
          id: 'before',
          startedAt: start.subtract(const Duration(minutes: 1)),
        ),
        linkedGame(id: 'at-end', startedAt: end),
        linkedGame(id: 'wrong-room', roomId: 'room-b'),
      ];
      for (final game in invalidGames) {
        expect(
          () => validateEventEdit(edit, [game]),
          throwsA(isA<ClubException>()),
          reason: game.id,
        );
      }
    },
  );

  test(
    'eligible events use start inclusive/end exclusive window and sort ties',
    () {
      final now = start;
      final snapshot = ClubSnapshot(
        events: [
          ClubEvent(
            id: 'z',
            name: 'Same',
            description: '',
            startsAt: start,
            endsAt: end,
            roomIds: const ['room-a'],
            createdAt: start,
          ),
          ClubEvent(
            id: 'a',
            name: 'Same',
            description: '',
            startsAt: start,
            endsAt: end,
            roomIds: const ['room-a'],
            createdAt: start,
          ),
          ClubEvent(
            id: 'later',
            name: 'Later',
            description: '',
            startsAt: start,
            endsAt: end,
            roomIds: const ['room-a'],
            createdAt: start,
          ),
          ClubEvent(
            id: 'other-room',
            name: 'Other',
            description: '',
            startsAt: start,
            endsAt: end,
            roomIds: const ['room-b'],
            createdAt: start,
          ),
          ClubEvent(
            id: 'ended',
            name: 'Ended',
            description: '',
            startsAt: start.subtract(const Duration(hours: 2)),
            endsAt: start,
            roomIds: const ['room-a'],
            createdAt: start,
          ),
        ],
      );

      expect(
        eligibleEvents(
          snapshot,
          'room-a',
          now,
        ).map((event) => event.id).toList(),
        ['later', 'a', 'z'],
      );
      expect(eligibleEvents(snapshot, 'room-a', end), isEmpty);
    },
  );
}
