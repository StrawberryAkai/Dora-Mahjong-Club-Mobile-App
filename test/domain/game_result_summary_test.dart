import 'package:flutter_test/flutter_test.dart';

import 'package:dora_mahjong/domain/game_result_summary.dart';
import 'package:dora_mahjong/domain/models.dart';

void main() {
  final baseTime = DateTime.utc(2026, 9, 22);

  Member member(
    String id, {
    double mmr = 1500,
    double mmrBaseline = 1500,
    String? name,
  }) => Member(id: id, name: name ?? id, mmr: mmr, mmrBaseline: mmrBaseline);

  PlayerSettlement result(
    String memberId, {
    double pt = 0,
    double oldMmr = 1500,
    double newMmr = 1500,
  }) => PlayerSettlement(
    memberId: memberId,
    finalPoints: 25000,
    actualUma: 0,
    pt: pt,
    oldMmr: oldMmr,
    mmrDelta: newMmr - oldMmr,
    newMmr: newMmr,
  );

  GameSettlement settlement(
    int order,
    List<PlayerSettlement> players, {
    int revision = 1,
    DateTime? settledAt,
  }) => GameSettlement(
    ruleVersion: 'test',
    order: order,
    revision: revision,
    settledAt: settledAt ?? baseTime,
    players: players,
  );

  ClubGame game(
    String id, {
    required GameStatus status,
    GameSettlement? current,
    List<GameSettlement> history = const [],
  }) => ClubGame(
    id: id,
    roomId: 'room',
    creatorId: 'a',
    players: const [],
    startedAt: baseTime,
    status: status,
    completedAt: status == GameStatus.completed ? baseTime : null,
    settlement: current,
    settlementHistory: history,
  );

  test(
    'reconstructs target standings from settlement order and effective revisions',
    () {
      final earlier = settlement(1, [
        result('a', pt: 1.1, oldMmr: 1500, newMmr: 1700),
        result('b', pt: 1.1, oldMmr: 1500, newMmr: 1400),
        result('c', pt: 0.3, oldMmr: 1500, newMmr: 1490),
        result('d', pt: 0.3, oldMmr: 1500, newMmr: 1490),
        result('e', pt: 0.8, oldMmr: 1500, newMmr: 1450),
      ], settledAt: DateTime.utc(2026, 9, 30));
      final earlierByOrder = settlement(
        2,
        [result('e', pt: -0.8, oldMmr: 1450, newMmr: 1480)],
        // This superseded revision must not leak into the reconstruction.
        revision: 2,
        settledAt: DateTime.utc(2026, 9, 1),
      );
      final target = settlement(3, [
        // These old MMRs deliberately disagree with the earlier game's
        // new MMRs; the target ledger is authoritative for its before view.
        result('a', pt: -0.1, oldMmr: 1600, newMmr: 1500),
        result('b', pt: -0.1, oldMmr: 1600, newMmr: 1500),
        result('c', pt: 1.2, oldMmr: 1500, newMmr: 1600),
        result('d', pt: 1.2, oldMmr: 1500, newMmr: 1600),
        // A saved settlement can contain an identity no longer in the
        // current roster; it must not manufacture a rank for that identity.
        result('ghost', pt: 99, oldMmr: 9999, newMmr: 9999),
      ], settledAt: DateTime.utc(2026, 9, 22));
      final future = settlement(4, [
        result('a', pt: 80, oldMmr: 1500, newMmr: 1900),
      ], settledAt: DateTime.utc(2026, 9, 1));
      final snapshot = ClubSnapshot(
        members: [
          member('a', name: 'Same name'),
          member('b', name: 'Same name'),
          member('c'),
          member('d'),
          // Current MMR must not replace this historical baseline.
          member('e', mmr: 2200, mmrBaseline: 1480),
        ],
        games: [
          game(
            'target',
            status: GameStatus.completed,
            current: target,
            history: [
              // Superseded target revisions do not contribute to PT totals.
              settlement(2, [
                result('a', pt: 100, oldMmr: 1600, newMmr: 1900),
              ], revision: 1),
            ],
          ),
          // Completion timestamps intentionally disagree with settlement order.
          game('earlier', status: GameStatus.completed, current: earlier),
          game(
            'earlier-by-order',
            status: GameStatus.completed,
            current: earlierByOrder,
            history: [
              settlement(2, [
                result('e', pt: 90, oldMmr: 1450, newMmr: 2000),
              ], revision: 1),
            ],
          ),
          game('future', status: GameStatus.completed, current: future),
          game(
            'cancelled',
            status: GameStatus.cancelled,
            current: settlement(1, [result('e', pt: 100, newMmr: 3000)]),
          ),
          game(
            'active-rated',
            status: GameStatus.active,
            current: settlement(3, [result('e', pt: 100, newMmr: 3000)]),
          ),
          game('legacy', status: GameStatus.completed),
        ],
      );

      final summaries = buildGameResultSummaries(
        snapshot,
        snapshot.games.first,
      );

      expect(summaries.keys, containsAll(<String>['a', 'b', 'c', 'd']));
      expect(summaries.keys, isNot(contains('Same name')));
      expect(summaries.keys, isNot(contains('ghost')));
      expect(summaries.length, 4);

      // MMR before: a=b=1600, c=d=1500, e=1480. After: c=d=1600,
      // a=b=1500, e=1480. Dense ranks are 1,1,2,2,3.
      expect(summaries['a']!.mmrRankBefore, 1);
      expect(summaries['a']!.mmrRankAfter, 2);
      expect(summaries['b']!.mmrRankBefore, 1);
      expect(summaries['b']!.mmrRankAfter, 2);
      expect(summaries['c']!.mmrRankBefore, 2);
      expect(summaries['c']!.mmrRankAfter, 1);
      expect(summaries['d']!.mmrRankBefore, 2);
      expect(summaries['d']!.mmrRankAfter, 1);
      expect(summaries['e'], isNull);

      // PT before: a=b=1.1, c=d=0.3, e=0. After: c=d=1.5,
      // a=b=1.0, e=0. Values are accumulated in integer tenths.
      expect(summaries['a']!.ptBefore, 1.1);
      expect(summaries['a']!.ptAfter, 1.0);
      expect(summaries['b']!.ptBefore, 1.1);
      expect(summaries['b']!.ptAfter, 1.0);
      expect(summaries['c']!.ptBefore, 0.3);
      expect(summaries['c']!.ptAfter, 1.5);
      expect(summaries['d']!.ptBefore, 0.3);
      expect(summaries['d']!.ptAfter, 1.5);

      expect(summaries['a']!.mmrRankChange, -1);
      expect(summaries['c']!.mmrRankChange, 1);
      expect(summaries['a']!.ptRankChange, -1);
      expect(summaries['c']!.ptRankChange, 1);
    },
  );

  test('returns no summaries for an unrated or noncompleted target', () {
    final members = [member('a')];
    final unrated = game('unrated', status: GameStatus.completed);
    final active = game(
      'active',
      status: GameStatus.active,
      current: settlement(1, [result('a')]),
    );
    final snapshot = ClubSnapshot(members: members, games: [unrated, active]);

    expect(buildGameResultSummaries(snapshot, unrated), isEmpty);
    expect(buildGameResultSummaries(snapshot, active), isEmpty);
  });
}
