import 'models.dart';

enum LeaderboardMetric { mmr, pt }

class LeaderboardEntry {
  const LeaderboardEntry({
    required this.memberId,
    required this.name,
    required this.mmr,
    required this.pt,
    required this.gamesPlayed,
    required this.rank,
  });

  final String memberId;
  final String name;
  final double mmr;
  final double pt;
  final int gamesPlayed;
  final int rank;
}

/// Returns the cumulative PT for one member from the current settlement of
/// each completed rated game. Settlement history is deliberately ignored:
/// corrections replace the current contribution rather than adding another
/// contribution for the same game.
double cumulativePt(ClubSnapshot snapshot, String memberId) {
  return (_ledgerFor(snapshot)[memberId]?.pt ?? 0) / _ptScale;
}

List<LeaderboardEntry> buildLeaderboard(
  ClubSnapshot snapshot, {
  LeaderboardMetric metric = LeaderboardMetric.mmr,
  String? eventId,
}) {
  final ledger = _ledgerFor(snapshot, eventId: eventId);
  // Event standings include only completed rated games linked to that event
  // and always rank by PT. The global board supports either requested metric.
  final rankingMetric = eventId == null ? metric : LeaderboardMetric.pt;

  final entries = snapshot.members
      .where(
        (member) =>
            eventId == null || (ledger[member.id]?.gamesPlayed ?? 0) > 0,
      )
      .map(
        (member) => _UnrankedEntry(
          member: member,
          ptTenths: ledger[member.id]?.pt ?? 0,
          gamesPlayed: ledger[member.id]?.gamesPlayed ?? 0,
        ),
      )
      .toList();

  entries.sort((a, b) {
    // Compare full-precision MMR. Member IDs stabilize equal values' display
    // order; close but unequal ratings do not count as ties.
    final valueComparison = switch (rankingMetric) {
      LeaderboardMetric.mmr => b.member.mmr.compareTo(a.member.mmr),
      LeaderboardMetric.pt => b.ptTenths.compareTo(a.ptTenths),
    };
    return valueComparison == 0
        ? a.member.id.compareTo(b.member.id)
        : valueComparison;
  });

  // Assign dense ranks before paging or searching: ties share a rank and the
  // next group advances by one. Imported ranks may follow a different tie
  // policy and must not override these results.
  final ranked = <LeaderboardEntry>[];
  var rank = 0;
  for (var index = 0; index < entries.length; index++) {
    if (index == 0 ||
        !_sameMetric(entries[index - 1], entries[index], rankingMetric)) {
      rank++;
    }
    ranked.add(
      LeaderboardEntry(
        memberId: entries[index].member.id,
        name: entries[index].member.name,
        mmr: entries[index].member.mmr,
        pt: entries[index].ptTenths / _ptScale,
        gamesPlayed: entries[index].gamesPlayed,
        rank: rank,
      ),
    );
  }
  return ranked;
}

// Accumulate PT as integer tenths and convert back only after summing games.
const int _ptScale = 10;

bool _sameMetric(
  _UnrankedEntry previous,
  _UnrankedEntry current,
  LeaderboardMetric metric,
) => switch (metric) {
  LeaderboardMetric.mmr => previous.member.mmr == current.member.mmr,
  LeaderboardMetric.pt => previous.ptTenths == current.ptTenths,
};

class _UnrankedEntry {
  const _UnrankedEntry({
    required this.member,
    required this.ptTenths,
    required this.gamesPlayed,
  });

  final Member member;
  final int ptTenths;
  final int gamesPlayed;
}

class _MemberLedger {
  int pt = 0;
  int gamesPlayed = 0;
}

Map<String, _MemberLedger> _ledgerFor(
  ClubSnapshot snapshot, {
  String? eventId,
}) {
  final ledger = <String, _MemberLedger>{};
  if (eventId == null) {
    for (final member in snapshot.members) {
      ledger[member.id] = _MemberLedger()
        ..pt = _ptTenths(member.ptBaseline)
        ..gamesPlayed = member.gamesPlayedBaseline;
    }
  }

  for (final game in snapshot.games) {
    if (game.status != GameStatus.completed || game.settlement == null) {
      continue;
    }
    if (eventId != null && game.eventId != eventId) continue;

    // A valid settlement has one row per player. Guarding the member IDs here
    // keeps a malformed settlement from counting one member twice in a game.
    final countedMembers = <String>{};
    for (final player in game.settlement!.players) {
      if (!countedMembers.add(player.memberId)) continue;
      final member = ledger.putIfAbsent(player.memberId, _MemberLedger.new);
      member.pt += _ptTenths(player.pt);
      member.gamesPlayed++;
    }
  }

  return ledger;
}

int _ptTenths(double pt) => (pt * _ptScale).round();
