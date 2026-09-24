import 'models.dart';

/// Display-only totals and club ranks on either side of one saved settlement.
/// A positive rank change means an improvement (for example, 5 -> 2 is +3).
class GameResultSummary {
  const GameResultSummary({
    required this.memberId,
    required this.ptBefore,
    required this.ptAfter,
    required this.mmrRankBefore,
    required this.mmrRankAfter,
    required this.ptRankBefore,
    required this.ptRankAfter,
  });

  final String memberId;
  final double ptBefore;
  final double ptAfter;
  final int mmrRankBefore;
  final int mmrRankAfter;
  final int ptRankBefore;
  final int ptRankAfter;

  int get mmrRankChange => mmrRankBefore - mmrRankAfter;
  int get ptRankChange => ptRankBefore - ptRankAfter;
}

/// Reconstructs the target game's before/after standings from saved results.
///
/// This never reruns a rating formula or changes a balance. The full club
/// snapshot supplies baseline ratings and the current effective settlements;
/// superseded revisions, unrated games, and later settlements are excluded.
/// Membership has no historical join timestamp in the current model, so both
/// rank comparisons use the same current club roster, including nonplayers.
Map<String, GameResultSummary> buildGameResultSummaries(
  ClubSnapshot snapshot,
  ClubGame game,
) {
  final settlement = game.settlement;
  if (game.status != GameStatus.completed || settlement == null) {
    return const {};
  }

  final mmrBefore = <String, double>{
    for (final member in snapshot.members) member.id: member.mmrBaseline,
  };
  final ptBefore = <String, int>{
    for (final member in snapshot.members)
      member.id: (member.ptBaseline * 10).round(),
  };
  // Replay and accumulate PT as integer tenths, converting back to double only
  // at the end to avoid floating-point drift across games.
  final earlierGames =
      snapshot.games
          .where(
            (candidate) =>
                candidate.id != game.id &&
                candidate.status == GameStatus.completed &&
                candidate.settlement != null &&
                candidate.settlement!.order < settlement.order,
          )
          .toList()
        ..sort((a, b) {
          // Use settlement order, with game ID as a stable tie-break, not completion time.
          final order = a.settlement!.order.compareTo(b.settlement!.order);
          return order != 0 ? order : a.id.compareTo(b.id);
        });

  final seenGames = <String>{};
  for (final previous in earlierGames) {
    if (!seenGames.add(previous.id)) continue;
    final seenMembers = <String>{};
    for (final player in previous.settlement!.players) {
      if (!mmrBefore.containsKey(player.memberId) ||
          !seenMembers.add(player.memberId)) {
        continue;
      }
      mmrBefore[player.memberId] = player.newMmr;
      ptBefore[player.memberId] =
          ptBefore[player.memberId]! + (player.pt * 10).round();
    }
  }

  final targetPlayers = <String, PlayerSettlement>{};
  for (final player in settlement.players) {
    if (!mmrBefore.containsKey(player.memberId)) continue;
    targetPlayers.putIfAbsent(player.memberId, () => player);
  }
  // The target ledger records the authoritative inputs for all four players.
  for (final player in targetPlayers.values) {
    mmrBefore[player.memberId] = player.oldMmr;
  }
  final mmrAfter = Map<String, double>.of(mmrBefore);
  final ptAfter = Map<String, int>.of(ptBefore);
  for (final player in targetPlayers.values) {
    mmrAfter[player.memberId] = player.newMmr;
    ptAfter[player.memberId] =
        ptAfter[player.memberId]! + (player.pt * 10).round();
  }

  final mmrRanksBefore = _ranks(mmrBefore);
  final mmrRanksAfter = _ranks(mmrAfter);
  final ptRanksBefore = _ranks(ptBefore);
  final ptRanksAfter = _ranks(ptAfter);
  return Map.unmodifiable({
    for (final player in targetPlayers.values)
      player.memberId: GameResultSummary(
        memberId: player.memberId,
        ptBefore: ptBefore[player.memberId]! / 10,
        ptAfter: ptAfter[player.memberId]! / 10,
        mmrRankBefore: mmrRanksBefore[player.memberId]!,
        mmrRankAfter: mmrRanksAfter[player.memberId]!,
        ptRankBefore: ptRanksBefore[player.memberId]!,
        ptRankAfter: ptRanksAfter[player.memberId]!,
      ),
  });
}

Map<String, int> _ranks(Map<String, num> values) {
  // Equal values share a rank; the next distinct value advances by one (dense ranking).
  final entries = values.entries.toList()
    ..sort((a, b) {
      final value = b.value.compareTo(a.value);
      return value != 0 ? value : a.key.compareTo(b.key);
    });
  final ranks = <String, int>{};
  var rank = 0;
  for (var index = 0; index < entries.length; index++) {
    if (index == 0 || entries[index].value != entries[index - 1].value) {
      rank++;
    }
    ranks[entries[index].key] = rank;
  }
  return ranks;
}
