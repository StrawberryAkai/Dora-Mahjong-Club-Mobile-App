import '../domain/leaderboard.dart';
import '../domain/models.dart';

/// Browses a complete club ranking in local pages without changing its ranks.
///
/// This is presentation paging over the existing snapshot, not server paging.
/// Ranking results are cached per metric until the repository replaces the
/// member/game lists. Scrolling and searching never recalculate PT or MMR.
class LeaderboardBrowser {
  LeaderboardBrowser(ClubSnapshot snapshot) : _snapshot = snapshot {
    _selectRanking();
  }

  static const pageSize = 50;

  ClubSnapshot _snapshot;
  LeaderboardMetric _metric = LeaderboardMetric.mmr;
  String _query = '';
  int _limit = pageSize;
  final _rankings = <LeaderboardMetric, List<LeaderboardEntry>>{};
  List<LeaderboardEntry> _entries = const [];
  List<LeaderboardEntry> _matches = const [];
  List<LeaderboardEntry> _visible = const [];
  LeaderboardEntry? _currentEntry;

  LeaderboardMetric get metric => _metric;
  String get query => _query;
  List<LeaderboardEntry> get visibleEntries => _visible;
  int get matchingCount => _matches.length;
  int get totalCount => _entries.length;
  bool get hasMore => _limit < _matches.length;
  LeaderboardEntry? get currentEntry => _currentEntry;

  /// Repositories replace snapshot lists instead of mutating them in place.
  /// Preserve the query and page depth when fresh results arrive.
  bool updateSnapshot(ClubSnapshot snapshot) {
    if (identical(snapshot, _snapshot)) return false;
    final ratingsChanged =
        !identical(snapshot.members, _snapshot.members) ||
        !identical(snapshot.games, _snapshot.games);
    _snapshot = snapshot;
    if (ratingsChanged) {
      _rankings.clear();
      _selectRanking();
    } else {
      _selectCurrentMember();
    }
    return true;
  }

  bool setMetric(LeaderboardMetric value) {
    if (_metric == value) return false;
    _metric = value;
    // Reset to the first page; each metric retains its own cached full ranking.
    _limit = pageSize;
    _selectRanking();
    return true;
  }

  bool setQuery(String value) {
    final normalized = value.trim().toLowerCase();
    if (_query == normalized) return false;
    _query = normalized;
    // Restart paging for a new query, filtering entries that already have ranks.
    _limit = pageSize;
    _filterRanking();
    return true;
  }

  bool loadMore() {
    if (!hasMore) return false;
    // Extend the visible prefix without duplicating entries or recomputing ranks.
    _limit += pageSize;
    _updateVisible();
    return true;
  }

  /// Include the current member's page and return their actual list index.
  /// Dense ranks can be shared, so they cannot be used as row indices.
  /// Search filters remain intact, including when they hide the current member.
  int? revealCurrentMember() {
    final memberId = _currentEntry?.memberId;
    if (memberId == null) return null;
    final index = _matches.indexWhere((entry) => entry.memberId == memberId);
    if (index < 0) return null;
    // Locate the page by row index, not dense rank, which can differ from position.
    // If search hides the current member, preserve the query and paging state.
    final requiredLimit = ((index ~/ pageSize) + 1) * pageSize;
    if (requiredLimit > _limit) {
      _limit = requiredLimit;
      _updateVisible();
    }
    return index;
  }

  void _selectRanking() {
    _entries = _rankings.putIfAbsent(
      _metric,
      () => List.unmodifiable(buildLeaderboard(_snapshot, metric: _metric)),
    );
    _selectCurrentMember();
    _filterRanking();
  }

  void _selectCurrentMember() {
    final memberId = _snapshot.isAdmin ? null : _snapshot.memberId;
    _currentEntry = memberId == null
        ? null
        : _entries.where((entry) => entry.memberId == memberId).firstOrNull;
  }

  void _filterRanking() {
    // Rank all ordinary members first, then match names case-insensitively by
    // substring while preserving the original order and ranks.
    _matches = _query.isEmpty
        ? _entries
        : _entries
              .where((entry) => entry.name.toLowerCase().contains(_query))
              .toList(growable: false);
    _updateVisible();
  }

  void _updateVisible() {
    // limit tracks expanded page depth; the final page may be smaller than pageSize.
    _visible = List.unmodifiable(_matches.take(_limit));
  }
}
