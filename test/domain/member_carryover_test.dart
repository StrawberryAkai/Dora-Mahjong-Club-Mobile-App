import 'package:flutter_test/flutter_test.dart';
import 'package:dora_mahjong/domain/models.dart';
import 'package:dora_mahjong/domain/leaderboard.dart';
import 'package:dora_mahjong/domain/game_result_summary.dart';

void main() {
  test('current server ranks do not replace dense ranks or inherited PT', () {
    final value = Member.fromJson({
      'id': 'a',
      'name': 'Player',
      'legacy_stats': {
        'total_pt': 100.0,
        'games_played': 4,
        'mmr_rank': 1,
        'pt_rank': 1,
      },
      'current_stats': {'total_pt': 150.0, 'mmr_rank': 1, 'pt_rank': 1},
    });
    final higher = Member(
      id: 'higher',
      name: 'Higher',
      mmr: 1600,
      legacyStats: const {'total_pt': 200.0, 'mmr_rank': 2, 'pt_rank': 2},
    );
    final snapshot = ClubSnapshot(members: [value, higher]);
    final mmrRanking = buildLeaderboard(snapshot);
    final ptRanking = buildLeaderboard(snapshot, metric: LeaderboardMetric.pt);

    expect(value.ptBaseline, 100);
    expect(value.gamesPlayedBaseline, 4);
    expect(mmrRanking.map((entry) => entry.rank).toList(), [1, 2]);
    expect(mmrRanking.last.memberId, 'a');
    expect(ptRanking.map((entry) => entry.rank).toList(), [1, 2]);
    expect(ptRanking.last.memberId, 'a');
    expect(Member.fromJson(value.toJson()).currentStats, value.currentStats);
  });
  final member = Member.fromJson({
    'id': 'a',
    'name': 'Existing Player',
    'mmr': 1716.86,
    'mmr_baseline': 1716.86,
    'legacy_stats': {
      'total_pt': 4229.7,
      'games_played': 424,
      'wins': 155,
      'win_rate': 0.3656,
      'mmr_rank': 1,
      'pt_rank': 1,
      'history_highest_pt': 4229.7,
    },
  });
  test('existing statistics survive with an empty new history', () {
    final higher = Member.fromJson({
      'id': 'higher',
      'name': 'Higher Player',
      'mmr': 1800,
      'mmr_baseline': 1800,
      'legacy_stats': {
        'total_pt': 5000.0,
        'games_played': 200,
        'mmr_rank': 2,
        'pt_rank': 2,
      },
    });
    final snapshot = ClubSnapshot(members: [member, higher]);
    final mmrRanking = buildLeaderboard(snapshot);
    final ptRanking = buildLeaderboard(snapshot, metric: LeaderboardMetric.pt);

    expect(snapshot.games, isEmpty);
    expect(cumulativePt(snapshot, 'a'), 4229.7);
    expect(mmrRanking.last.memberId, 'a');
    expect(mmrRanking.last.gamesPlayed, 424);
    expect(mmrRanking.last.rank, 2);
    expect(ptRanking.last.memberId, 'a');
    expect(ptRanking.last.gamesPlayed, 424);
    expect(ptRanking.last.rank, 2);
    expect(Member.fromJson(member.toJson()).legacyStats, member.legacyStats);
  });
  test('new settlements add once, event totals exclude inherited PT', () {
    final settlement = GameSettlement(
      ruleVersion: 'test',
      order: 1,
      revision: 2,
      settledAt: DateTime.utc(2026),
      players: [
        const PlayerSettlement(
          memberId: 'a',
          finalPoints: 40000,
          actualUma: 30,
          pt: 55,
          oldMmr: 1716.86,
          mmrDelta: 5,
          newMmr: 1721.86,
        ),
      ],
    );
    final game = ClubGame(
      id: 'g',
      roomId: 'r',
      creatorId: 'a',
      players: const [],
      startedAt: DateTime.utc(2026),
      status: GameStatus.completed,
      eventId: 'event',
      settlement: settlement,
      settlementHistory: [settlement],
    );
    final snapshot = ClubSnapshot(members: [member], games: [game]);
    expect(cumulativePt(snapshot, 'a'), 4284.7);
    expect(buildLeaderboard(snapshot).single.gamesPlayed, 425);
    expect(buildLeaderboard(snapshot, eventId: 'event').single.pt, 55);
    expect(buildLeaderboard(snapshot, eventId: 'event').single.gamesPlayed, 1);
    expect(buildGameResultSummaries(snapshot, game)['a']!.ptBefore, 4229.7);
    expect(buildGameResultSummaries(snapshot, game)['a']!.ptAfter, 4284.7);
  });
  test('fresh members retain zero PT and the standard baseline', () {
    const fresh = Member(id: 'new', name: 'New');
    expect(fresh.ptBaseline, 0);
    expect(fresh.gamesPlayedBaseline, 0);
    expect(fresh.mmrBaseline, 1500);
  });
}
