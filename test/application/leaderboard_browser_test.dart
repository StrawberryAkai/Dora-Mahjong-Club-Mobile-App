import 'package:flutter_test/flutter_test.dart';

import 'package:dora_mahjong/application/leaderboard_browser.dart';
import 'package:dora_mahjong/domain/leaderboard.dart';
import 'package:dora_mahjong/domain/models.dart';

void main() {
  test(
    'dense tied ranks survive paging, search, and locating the current row',
    () {
      final snapshot = ClubSnapshot(
        members: [
          for (var index = 0; index < 39; index++)
            Member(
              id: 'higher-$index',
              name: 'Higher $index',
              mmr: 1600 + index.toDouble(),
              legacyStats: {'total_pt': 1600 + index.toDouble()},
            ),
          for (var index = 0; index < 12; index++)
            Member(
              id: 'tied-${index.toString().padLeft(2, '0')}',
              name: 'Tied $index',
              mmr: 1500,
              legacyStats: const {'total_pt': 1500},
            ),
          const Member(
            id: 'next',
            name: 'Next Player',
            mmr: 1499,
            legacyStats: {'total_pt': 1499},
          ),
        ],
        memberId: 'next',
      );
      final browser = LeaderboardBrowser(snapshot);

      for (final metric in LeaderboardMetric.values) {
        browser.setMetric(metric);
        expect(browser.visibleEntries, hasLength(50));
        expect(browser.visibleEntries.last.rank, 40);
        expect(browser.currentEntry?.rank, 41);
        expect(browser.revealCurrentMember(), 51);
        expect(browser.visibleEntries, hasLength(52));
        expect(browser.visibleEntries[50].rank, 40);
        expect(browser.visibleEntries[51].rank, 41);

        browser.setQuery('next');
        expect(browser.visibleEntries.single.rank, 41);
        expect(browser.revealCurrentMember(), 0);
        browser.setQuery('');
      }
    },
  );

  test('pages a full synthetic ranking without duplicates or reranking', () {
    final browser = LeaderboardBrowser(_snapshot(memberCount: 1000));

    expect(browser.totalCount, 1000);
    expect(browser.matchingCount, 1000);
    expect(browser.visibleEntries, hasLength(50));
    expect(browser.visibleEntries.first.memberId, 'member-0000');
    expect(browser.visibleEntries.last.memberId, 'member-0049');
    expect(browser.visibleEntries.first.rank, 1);
    expect(browser.visibleEntries.last.rank, 50);
    expect(browser.hasMore, isTrue);

    final seen = <String>{
      ...browser.visibleEntries.map((entry) => entry.memberId),
    };
    for (final expectedLimit in <int>[100, 150]) {
      expect(browser.loadMore(), isTrue);
      expect(browser.visibleEntries, hasLength(expectedLimit));
      expect(
        browser.visibleEntries.map((entry) => entry.memberId).toSet(),
        hasLength(expectedLimit),
      );
      expect(seen.length, expectedLimit - 50);
      seen.addAll(browser.visibleEntries.map((entry) => entry.memberId));
      expect(seen, hasLength(expectedLimit));
      expect(browser.visibleEntries.last.rank, expectedLimit);
    }

    final partialBrowser = LeaderboardBrowser(_snapshot(memberCount: 163));
    while (partialBrowser.loadMore()) {
      // Keep extending until the partial final page is reached.
    }
    expect(partialBrowser.visibleEntries, hasLength(163));
    expect(
      partialBrowser.visibleEntries.map((entry) => entry.memberId).toSet(),
      hasLength(163),
    );
    expect(partialBrowser.visibleEntries.last.memberId, 'member-0162');
    expect(partialBrowser.visibleEntries.last.rank, 163);
    expect(partialBrowser.hasMore, isFalse);
    expect(partialBrowser.loadMore(), isFalse);
  });

  test('search is trimmed, case insensitive, and keeps original ranks', () {
    final browser = LeaderboardBrowser(
      _snapshot(memberCount: 1000, memberId: 'member-0777'),
    );

    expect(browser.currentEntry?.memberId, 'member-0777');
    expect(browser.currentEntry?.rank, 778);

    expect(browser.setQuery('  TARGET  '), isTrue);
    expect(browser.query, 'target');
    expect(browser.matchingCount, 1);
    expect(browser.visibleEntries, hasLength(1));
    expect(browser.visibleEntries.single.memberId, 'member-0057');
    expect(browser.visibleEntries.single.rank, 58);
    expect(browser.currentEntry?.rank, 778);

    expect(browser.setQuery('目标'), isTrue);
    expect(browser.query, '目标');
    expect(browser.matchingCount, 1);
    expect(browser.visibleEntries.single.memberId, 'member-0777');
    expect(browser.visibleEntries.single.rank, 778);

    expect(browser.setQuery('does-not-exist'), isTrue);
    expect(browser.matchingCount, 0);
    expect(browser.visibleEntries, isEmpty);
    expect(browser.currentEntry?.memberId, 'member-0777');
    expect(browser.currentEntry?.rank, 778);
    expect(browser.setQuery(' DOES-not-exist '), isFalse);
  });

  test(
    'reveals the current member by actual filtered index when ranks are tied',
    () {
      final browser = LeaderboardBrowser(
        _snapshotWithTiedMmr(memberCount: 1000, memberId: 'member-0777'),
      );

      // Every member shares rank 1, while the current row is at index 777.
      // A rank-derived page would incorrectly stop at the first page.
      expect(browser.currentEntry?.rank, 1);
      expect(browser.setQuery('player'), isTrue);
      expect(browser.query, 'player');
      expect(browser.visibleEntries, hasLength(50));

      expect(browser.revealCurrentMember(), 777);
      expect(browser.query, 'player');
      expect(browser.visibleEntries, hasLength(800));
      expect(browser.visibleEntries[777].memberId, 'member-0777');
      expect(browser.visibleEntries[777].rank, 1);

      // Revealing again must preserve an already deeper page.
      expect(browser.loadMore(), isTrue);
      expect(browser.visibleEntries, hasLength(850));
      expect(browser.revealCurrentMember(), 777);
      expect(browser.visibleEntries, hasLength(850));
    },
  );

  test(
    'reveal leaves query and paging unchanged when no current row matches',
    () {
      final admin = LeaderboardBrowser(
        _snapshot(memberCount: 1000, memberId: 'member-0777', isAdmin: true),
      );
      expect(admin.loadMore(), isTrue);
      expect(admin.visibleEntries, hasLength(100));
      expect(admin.revealCurrentMember(), isNull);
      expect(admin.visibleEntries, hasLength(100));

      final missing = LeaderboardBrowser(
        _snapshot(memberCount: 1000, memberId: 'missing-member'),
      );
      expect(missing.loadMore(), isTrue);
      expect(missing.revealCurrentMember(), isNull);
      expect(missing.visibleEntries, hasLength(100));

      final filtered = LeaderboardBrowser(
        _snapshot(memberCount: 1000, memberId: 'member-0777'),
      );
      expect(filtered.setQuery('english'), isTrue);
      expect(filtered.query, 'english');
      expect(filtered.visibleEntries.single.memberId, 'member-0057');
      expect(filtered.revealCurrentMember(), isNull);
      expect(filtered.query, 'english');
      expect(filtered.visibleEntries, hasLength(1));
      expect(filtered.visibleEntries.single.memberId, 'member-0057');
    },
  );

  test(
    'metric changes reset the page and switch back to the cached ranking',
    () {
      final browser = LeaderboardBrowser(_snapshotWithPt(memberCount: 120));
      final mmrFirst = browser.visibleEntries.first;

      expect(mmrFirst.memberId, 'member-0000');
      expect(browser.loadMore(), isTrue);
      expect(browser.visibleEntries, hasLength(100));

      expect(browser.setMetric(LeaderboardMetric.pt), isTrue);
      expect(browser.metric, LeaderboardMetric.pt);
      expect(browser.visibleEntries, hasLength(50));
      expect(browser.visibleEntries.first.memberId, 'member-0119');
      expect(browser.visibleEntries.first.rank, 1);

      expect(browser.setMetric(LeaderboardMetric.mmr), isTrue);
      expect(browser.visibleEntries, hasLength(50));
      expect(browser.visibleEntries.first.memberId, 'member-0000');
      expect(identical(browser.visibleEntries.first, mmrFirst), isTrue);
      expect(browser.setMetric(LeaderboardMetric.mmr), isFalse);
    },
  );

  test('a fresh snapshot preserves query and page depth while reranking', () {
    final original = _snapshot(memberCount: 200, memberId: 'member-0190');
    final browser = LeaderboardBrowser(original);
    expect(browser.setQuery('player'), isTrue);
    expect(browser.loadMore(), isTrue);
    expect(browser.visibleEntries, hasLength(100));

    final refreshedMembers = [
      const Member(id: 'member-0000', name: 'Player 0000', mmr: 5000),
      ..._members(240).skip(1),
    ];
    final refreshed = ClubSnapshot(
      members: refreshedMembers,
      memberId: 'member-0190',
    );
    expect(browser.updateSnapshot(refreshed), isTrue);
    expect(browser.query, 'player');
    expect(browser.metric, LeaderboardMetric.mmr);
    expect(browser.totalCount, 240);
    expect(browser.matchingCount, 239);
    expect(browser.visibleEntries, hasLength(100));
    expect(browser.visibleEntries.first.memberId, 'member-0000');
    expect(browser.visibleEntries.first.rank, 1);
    expect(browser.currentEntry?.memberId, 'member-0190');

    final sameListsDifferentMember = ClubSnapshot(
      members: refreshed.members,
      games: refreshed.games,
      memberId: 'member-0239',
    );
    expect(browser.updateSnapshot(sameListsDifferentMember), isTrue);
    expect(browser.visibleEntries, hasLength(100));
    expect(browser.currentEntry?.memberId, 'member-0239');
    expect(browser.currentEntry?.rank, 240);
  });

  test('administrator snapshots have no current member row', () {
    final browser = LeaderboardBrowser(
      _snapshot(memberCount: 80, memberId: 'member-0007', isAdmin: true),
    );

    expect(browser.currentEntry, isNull);
    expect(browser.setQuery('player 0007'), isTrue);
    expect(browser.visibleEntries, hasLength(1));
    expect(browser.currentEntry, isNull);
  });
}

ClubSnapshot _snapshot({
  required int memberCount,
  String? memberId,
  bool isAdmin = false,
}) {
  return ClubSnapshot(
    members: _members(memberCount),
    memberId: memberId,
    isAdmin: isAdmin,
  );
}

List<Member> _members(int count) => [
  for (var index = 0; index < count; index++)
    Member(
      id: 'member-${index.toString().padLeft(4, '0')}',
      name: switch (index) {
        57 => 'English Target',
        777 => '中文目标',
        _ => 'Player ${index.toString().padLeft(4, '0')}',
      },
      mmr: (3000 - index).toDouble(),
    ),
];

ClubSnapshot _snapshotWithPt({required int memberCount}) {
  final members = _members(memberCount);
  final settlement = GameSettlement(
    ruleVersion: 'synthetic',
    order: 1,
    revision: 1,
    settledAt: DateTime(2026, 1, 1),
    players: [
      for (var index = 0; index < members.length; index++)
        PlayerSettlement(
          memberId: members[index].id,
          finalPoints: 0,
          actualUma: 0,
          pt: index + 1,
          oldMmr: members[index].mmr,
          mmrDelta: 0,
          newMmr: members[index].mmr,
        ),
    ],
  );
  return ClubSnapshot(
    members: members,
    games: [
      ClubGame(
        id: 'synthetic-game',
        roomId: 'synthetic-room',
        creatorId: members.first.id,
        players: const [],
        startedAt: DateTime(2026, 1, 1),
        status: GameStatus.completed,
        completedAt: DateTime(2026, 1, 1),
        settlement: settlement,
      ),
    ],
  );
}

ClubSnapshot _snapshotWithTiedMmr({
  required int memberCount,
  String? memberId,
}) {
  return ClubSnapshot(
    members: [
      for (final member in _members(memberCount))
        Member(id: member.id, name: 'Player ${member.id}', mmr: 3000),
    ],
    memberId: memberId,
  );
}
