import 'package:flutter_test/flutter_test.dart';

import 'package:dora_mahjong/domain/leaderboard.dart';
import 'package:dora_mahjong/domain/models.dart';

void main() {
  final settledAt = DateTime.utc(2026, 1, 1);

  Member member(
    String id, {
    double mmr = 1500,
    Map<String, dynamic>? legacyStats,
    Map<String, dynamic>? currentStats,
  }) => Member(
    id: id,
    name: id,
    mmr: mmr,
    legacyStats: legacyStats,
    currentStats: currentStats,
  );

  PlayerSettlement player(String memberId, double pt) => PlayerSettlement(
    memberId: memberId,
    finalPoints: 25000,
    actualUma: 0,
    pt: pt,
    oldMmr: 1500,
    mmrDelta: 0,
    newMmr: 1500,
  );

  GameSettlement settlement(
    List<PlayerSettlement> players, {
    int revision = 1,
  }) => GameSettlement(
    ruleVersion: 'test',
    order: revision,
    revision: revision,
    settledAt: settledAt,
    players: players,
  );

  ClubGame game(
    String id,
    GameStatus status,
    GameSettlement? current, {
    String roomId = 'room-1',
    String? eventId,
    List<GameSettlement> history = const [],
  }) => ClubGame(
    id: id,
    roomId: roomId,
    creatorId: 'creator',
    players: const [],
    startedAt: settledAt,
    status: status,
    settlement: current,
    settlementHistory: history,
    eventId: eventId,
  );

  test('cumulative PT uses one current completed settlement per game', () {
    final current = settlement([player('alice', 1.2)]);
    final old = settlement([player('alice', 9.9)], revision: 0);
    final snapshot = ClubSnapshot(
      members: [member('alice')],
      games: [
        game('current', GameStatus.completed, current, history: [old]),
        game(
          'legacy',
          GameStatus.completed,
          null,
          history: [
            settlement([player('alice', 20)]),
          ],
        ),
        game('active', GameStatus.active, settlement([player('alice', 30)])),
        game(
          'cancelled',
          GameStatus.cancelled,
          settlement([player('alice', 40)]),
        ),
      ],
    );

    expect(cumulativePt(snapshot, 'alice'), 1.2);
    expect(cumulativePt(snapshot, 'missing'), 0);
  });

  test(
    'global PT ranking includes all members, keeps negative PT, and ties',
    () {
      final snapshot = ClubSnapshot(
        members: [member('d'), member('b'), member('a'), member('c')],
        games: [
          game('a-first', GameStatus.completed, settlement([player('a', 0.1)])),
          game(
            'a-second',
            GameStatus.completed,
            settlement([player('a', 0.1)]),
          ),
          game('b', GameStatus.completed, settlement([player('b', 0.2)])),
          game('c', GameStatus.completed, settlement([player('c', -0.3)])),
        ],
      );

      final ranking = buildLeaderboard(snapshot, metric: LeaderboardMetric.pt);

      expect(ranking.map((entry) => entry.memberId).toList(), [
        'a',
        'b',
        'd',
        'c',
      ]);
      expect(ranking.map((entry) => entry.pt).toList(), [0.2, 0.2, 0, -0.3]);
      expect(ranking.map((entry) => entry.rank).toList(), [1, 1, 2, 3]);
      expect(ranking.map((entry) => entry.gamesPlayed).toList(), [2, 1, 0, 1]);
    },
  );

  test('MMR ranking uses full precision and stable member ID tie ordering', () {
    final snapshot = ClubSnapshot(
      members: [
        member('same-z', mmr: 1600),
        member('same-a', mmr: 1600),
        member('precise-low', mmr: 1500.123450),
        member('precise-high', mmr: 1500.123451),
      ],
    );

    final ranking = buildLeaderboard(snapshot);

    expect(ranking.map((entry) => entry.memberId).toList(), [
      'same-a',
      'same-z',
      'precise-high',
      'precise-low',
    ]);
    expect(ranking.map((entry) => entry.rank).toList(), [1, 1, 2, 3]);
    expect(ranking[2].mmr, 1500.123451);
  });

  test(
    'dense ranks continue after a large tied group despite imported ranks',
    () {
      final members = [
        ...List.generate(
          39,
          (index) => member(
            'high-${index.toString().padLeft(2, '0')}',
            mmr: 1600 - index.toDouble(),
          ),
        ),
        for (final id in ['tie-4', 'tie-2', 'tie-0', 'tie-3', 'tie-1'])
          member(
            id,
            mmr: 1500,
            legacyStats: const {'mmr_rank': 1},
            currentStats: const {'mmr_rank': 2},
          ),
        member(
          'below',
          mmr: 1499,
          legacyStats: const {'mmr_rank': 40},
          currentStats: const {'mmr_rank': 1},
        ),
      ];
      final ranking = buildLeaderboard(ClubSnapshot(members: members));

      expect(ranking.skip(39).take(5).map((entry) => entry.memberId).toList(), [
        'tie-0',
        'tie-1',
        'tie-2',
        'tie-3',
        'tie-4',
      ]);
      expect(ranking.skip(39).take(5).map((entry) => entry.rank).toList(), [
        40,
        40,
        40,
        40,
        40,
      ]);
      expect(ranking.last.memberId, 'below');
      expect(ranking.last.rank, 41);
    },
  );

  test(
    'event ranking isolates linked completed games and forces PT metric',
    () {
      final snapshot = ClubSnapshot(
        members: [
          member('alice', mmr: 2000),
          member('bob', mmr: 1000),
          member('cara'),
        ],
        games: [
          game(
            'event-one',
            GameStatus.completed,
            settlement([
              player('alice', 0.5),
              player('bob', 0.5),
              player('cara', 0.1),
            ]),
            eventId: 'event-1',
          ),
          game(
            'event-two',
            GameStatus.completed,
            settlement([player('cara', 3)]),
            eventId: 'event-2',
          ),
          game('casual', GameStatus.completed, settlement([player('bob', 9)])),
        ],
      );

      final ranking = buildLeaderboard(
        snapshot,
        metric: LeaderboardMetric.mmr,
        eventId: 'event-1',
      );

      expect(ranking.map((entry) => entry.memberId).toList(), [
        'alice',
        'bob',
        'cara',
      ]);
      expect(ranking.map((entry) => entry.pt).toList(), [0.5, 0.5, 0.1]);
      expect(ranking.map((entry) => entry.gamesPlayed).toList(), [1, 1, 1]);
      expect(ranking.map((entry) => entry.rank).toList(), [1, 1, 2]);
    },
  );
}
