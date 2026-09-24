import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../application/club_controller.dart';
import '../application/leaderboard_browser.dart';
import '../domain/leaderboard.dart';
import '../domain/models.dart';
import 'localization.dart';
import 'rating_widgets.dart';

/// Global member leaderboard. Event leaderboards are rendered by
/// [EventsPage] so the Events tab remains one destination with selectable
/// activity rankings.
class LeaderboardPage extends StatefulWidget {
  const LeaderboardPage({
    super.key,
    required this.controller,
    required this.onProfile,
  });

  final ClubController controller;
  final VoidCallback onProfile;

  @override
  State<LeaderboardPage> createState() => _LeaderboardPageState();
}

class _LeaderboardPageState extends State<LeaderboardPage> {
  late LeaderboardBrowser _browser;
  late final ScrollController _scrollController;
  late final TextEditingController _searchController;
  bool _suppressScrollLoad = false;
  bool _loadScheduled = false;
  bool _revealPending = false;
  int _revealGeneration = 0;
  late String _lastIdentityKey;

  @override
  void initState() {
    super.initState();
    _browser = LeaderboardBrowser(widget.controller.snapshot);
    _scrollController = ScrollController()..addListener(_onScroll);
    _searchController = TextEditingController();
    _lastIdentityKey = _identityKey(widget.controller.snapshot);
    _scheduleCurrentMemberReveal();
  }

  @override
  void didUpdateWidget(covariant LeaderboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _cancelPendingReveal();
      _browser = LeaderboardBrowser(widget.controller.snapshot);
      _searchController.clear();
      _lastIdentityKey = _identityKey(widget.controller.snapshot);
      _scheduleCurrentMemberReveal();
      return;
    }
    // Build synchronizes snapshots so it can also refresh a pending reveal's
    // target before laying out a newly ordered list.
  }

  @override
  void dispose() {
    _cancelPendingReveal();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!mounted ||
        _suppressScrollLoad ||
        _loadScheduled ||
        !_scrollController.hasClients ||
        !_browser.hasMore) {
      return;
    }
    final position = _scrollController.position;
    if (position.maxScrollExtent - position.pixels > 220) return;
    _loadMore();
  }

  void _resetScrollPosition() {
    _suppressScrollLoad = true;
    if (_scrollController.hasClients && _scrollController.offset != 0) {
      _scrollController.jumpTo(0);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_revealPending) _suppressScrollLoad = false;
    });
  }

  String _identityKey(ClubSnapshot snapshot) =>
      snapshot.isAdmin ? 'admin' : 'member:${snapshot.memberId ?? '<none>'}';

  void _cancelPendingReveal() {
    _revealGeneration++;
    _revealPending = false;
    _suppressScrollLoad = false;
  }

  void _scheduleCurrentMemberReveal() {
    _cancelPendingReveal();
    if (_browser.query.isNotEmpty) return;
    final index = _browser.revealCurrentMember();
    if (index == null) {
      _resetScrollPosition();
      return;
    }

    _resetScrollPosition();
    final generation = _revealGeneration;
    _revealPending = true;
    _suppressScrollLoad = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _revealGeneration) return;
      if (!_scrollController.hasClients) {
        _revealPending = false;
        _suppressScrollLoad = false;
        return;
      }

      _suppressScrollLoad = true;
      final position = _scrollController.position;
      final rowExtent = _leaderboardRowExtent(context);
      final targetCenter = index * rowExtent + rowExtent / 2;
      final desiredOffset = targetCenter - position.viewportDimension / 2;
      // A lazy sliver can still estimate the previous shorter page here.
      // Fixed row sizes give a reliable minimum extent for the new prefix.
      final knownRowsExtent =
          _browser.visibleEntries.length * rowExtent -
          position.viewportDimension;
      final offset = desiredOffset.clamp(
        0.0,
        math.max(position.maxScrollExtent, knownRowsExtent),
      );
      _scrollController.jumpTo(offset.toDouble());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && generation == _revealGeneration) {
          _revealPending = false;
          _suppressScrollLoad = false;
        }
      });
    });
  }

  void _setMetric(LeaderboardMetric metric) {
    if (!_browser.setMetric(metric)) return;
    if (_browser.query.isEmpty) {
      _scheduleCurrentMemberReveal();
    } else {
      _cancelPendingReveal();
      _resetScrollPosition();
    }
    if (mounted) setState(() {});
  }

  void _setQuery(String query) {
    _cancelPendingReveal();
    if (_browser.setQuery(query)) _resetScrollPosition();
    // Rebuild even when the normalized query is unchanged so the clear
    // affordance follows the text currently visible in the field.
    if (mounted) setState(() {});
  }

  void _loadMore() {
    if (!mounted || _loadScheduled || !_browser.loadMore()) return;
    _loadScheduled = true;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadScheduled = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.controller.snapshot;
    final snapshotChanged = _browser.updateSnapshot(snapshot);
    final identityKey = _identityKey(snapshot);
    if (identityKey != _lastIdentityKey ||
        (snapshotChanged && _revealPending)) {
      _lastIdentityKey = identityKey;
      _scheduleCurrentMemberReveal();
    }
    final strings = context.strings;
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              MediaQuery.viewInsetsOf(context).bottom > 0 ? 8 : 18,
              20,
              MediaQuery.viewInsetsOf(context).bottom > 0 ? 8 : 28,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Keep one stable control subtree so opening the keyboard
                  // preserves the search field's focus and composition.
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight:
                          constraints.maxHeight *
                          (constraints.maxHeight < 360 ? .35 : .45),
                    ),
                    child: SingleChildScrollView(
                      key: const ValueKey('ranking-controls'),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _LeaderboardHeader(
                            title: strings.text('排行榜', 'Ranking'),
                            subtitle: strings.text('全体成员', 'All members'),
                            onProfile: widget.onProfile,
                          ),
                          const SizedBox(height: 16),
                          SegmentedButton<LeaderboardMetric>(
                            key: const ValueKey('global-leaderboard-metric'),
                            segments: [
                              ButtonSegment(
                                value: LeaderboardMetric.mmr,
                                label: const Text('MMR'),
                              ),
                              ButtonSegment(
                                value: LeaderboardMetric.pt,
                                label: Text(
                                  strings.text('累计PT', 'Cumulative PT'),
                                ),
                              ),
                            ],
                            selected: {_browser.metric},
                            onSelectionChanged: (selection) {
                              if (selection.isNotEmpty) {
                                _setMetric(selection.first);
                              }
                            },
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            key: const ValueKey('ranking-search'),
                            controller: _searchController,
                            textInputAction: TextInputAction.search,
                            onChanged: _setQuery,
                            onSubmitted: (_) =>
                                FocusManager.instance.primaryFocus?.unfocus(),
                            decoration: InputDecoration(
                              labelText: strings.text('搜索成员', 'Search members'),
                              hintText: strings.text('按姓名搜索', 'Search by name'),
                              prefixIcon: const Icon(Icons.search_rounded),
                              suffixIcon: _searchController.text.isEmpty
                                  ? null
                                  : IconButton(
                                      key: const ValueKey(
                                        'ranking-clear-search',
                                      ),
                                      tooltip: strings.text(
                                        '清除搜索',
                                        'Clear search',
                                      ),
                                      onPressed: () {
                                        _searchController.clear();
                                        _setQuery('');
                                      },
                                      icon: const Icon(Icons.clear_rounded),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(child: _buildRanking()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRanking() {
    final strings = context.strings;
    if (_browser.totalCount == 0) {
      return SingleChildScrollView(
        child: _LeaderboardEmpty(
          title: strings.text('还没有成员', 'No members yet'),
          body: strings.text(
            '成员加入后会出现在这里。',
            'Members appear here after they join.',
          ),
        ),
      );
    }

    final entries = _browser.visibleEntries;
    final hasRows = entries.isNotEmpty;
    return Card(
      key: const ValueKey('global-leaderboard'),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
          children: [
            if (constraints.maxHeight >= 64)
              _LeaderboardColumnHeader(metric: _browser.metric),
            Expanded(
              child: CustomScrollView(
                key: const ValueKey('ranking-list'),
                controller: _scrollController,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  if (hasRows)
                    SliverFixedExtentList(
                      itemExtent: _leaderboardRowExtent(context),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => _LeaderboardFixedRow(
                          entry: entries[index],
                          metric: _browser.metric,
                          isCurrent:
                              _browser.currentEntry?.memberId ==
                              entries[index].memberId,
                          extent: _leaderboardRowExtent(context),
                        ),
                        childCount: entries.length,
                        addAutomaticKeepAlives: false,
                      ),
                    )
                  else
                    SliverToBoxAdapter(
                      child: _LeaderboardNoResults(
                        query: _browser.query,
                        onClear: () {
                          _searchController.clear();
                          _setQuery('');
                        },
                      ),
                    ),
                  if (!hasRows)
                    SliverToBoxAdapter(
                      child: Divider(
                        height: 1,
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                  SliverToBoxAdapter(
                    child: _LeaderboardFooter(
                      shown: entries.length,
                      matching: _browser.matchingCount,
                      hasMore: _browser.hasMore,
                      onLoadMore: _loadMore,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LeaderboardHeader extends StatelessWidget {
  const _LeaderboardHeader({
    required this.title,
    required this.subtitle,
    required this.onProfile,
  });

  final String title;
  final String subtitle;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
      Semantics(
        button: true,
        label: context.t('打开个人设置', 'Open profile settings'),
        child: IconButton(
          key: const ValueKey('open-profile'),
          onPressed: onProfile,
          tooltip: context.t('个人设置', 'Profile settings'),
          icon: const Icon(Icons.account_circle_outlined),
        ),
      ),
    ],
  );
}

class _LeaderboardNoResults extends StatelessWidget {
  const _LeaderboardNoResults({required this.query, required this.onClear});

  final String query;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.person_search_outlined,
            color: Theme.of(context).colorScheme.primary,
            size: 32,
          ),
          const SizedBox(height: 8),
          Text(
            strings.text('没有找到匹配的成员', 'No members match your search'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          if (query.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '“$query”',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 8),
          TextButton(
            onPressed: onClear,
            child: Text(strings.text('清除搜索', 'Clear search')),
          ),
        ],
      ),
    );
  }
}

class _LeaderboardFooter extends StatelessWidget {
  const _LeaderboardFooter({
    required this.shown,
    required this.matching,
    required this.hasMore,
    required this.onLoadMore,
  });

  final int shown;
  final int matching;
  final bool hasMore;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            strings.text(
              '显示 $shown / $matching 名成员',
              'Showing $shown of $matching members',
            ),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          if (hasMore) ...[
            const SizedBox(height: 6),
            OutlinedButton(
              key: const ValueKey('ranking-load-more'),
              onPressed: onLoadMore,
              child: Text(strings.text('加载更多', 'Load more')),
            ),
          ],
        ],
      ),
    );
  }
}

class _LeaderboardColumnHeader extends StatelessWidget {
  const _LeaderboardColumnHeader({required this.metric});

  final LeaderboardMetric metric;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 9),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(
              context.t('名次', 'Rank'),
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11),
            ),
          ),
          Expanded(
            child: Text(
              context.t('成员', 'Member'),
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11),
            ),
          ),
          Text(
            metric == LeaderboardMetric.mmr ? 'MMR' : context.t('累计PT', 'PT'),
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

double _leaderboardRowExtent(BuildContext context) {
  final textScaler = MediaQuery.textScalerOf(context);
  final contentExtent =
      textScaler.scale(14) * 1.25 + 2 + textScaler.scale(11) * 1.25 + 26;
  return math.max(61, contentExtent + 2);
}

class _LeaderboardFixedRow extends StatelessWidget {
  const _LeaderboardFixedRow({
    required this.entry,
    required this.metric,
    required this.isCurrent,
    required this.extent,
  });

  final LeaderboardEntry entry;
  final LeaderboardMetric metric;
  final bool isCurrent;
  final double extent;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: extent,
    child: Column(
      children: [
        Expanded(
          child: _LeaderboardRow(
            entry: entry,
            metric: metric,
            isCurrent: isCurrent,
          ),
        ),
        Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
      ],
    ),
  );
}

class _LeaderboardRow extends StatelessWidget {
  const _LeaderboardRow({
    required this.entry,
    required this.metric,
    this.isCurrent = false,
  });

  final LeaderboardEntry entry;
  final LeaderboardMetric metric;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final score = metric == LeaderboardMetric.mmr
        ? formatRatingMmr(entry.mmr)
        : formatRatingPt(entry.pt, signed: true);
    final games = context.strings.isEnglish
        ? '${entry.gamesPlayed} ${entry.gamesPlayed == 1 ? 'game' : 'games'}'
        : '${entry.gamesPlayed} 场';
    final textScaler = MediaQuery.textScalerOf(context);
    final rankWidth = math.max(
      36.0,
      textScaler.scale(entry.rank.toString().length * 8.5 + 2),
    );
    return Padding(
      key: ValueKey('leaderboard-${entry.memberId}'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          SizedBox(
            width: rankWidth,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                '${entry.rank}',
                style: TextStyle(
                  color: scheme.primary,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        entry.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                    ),
                    if (isCurrent) ...[
                      const SizedBox(width: 6),
                      const _CurrentMemberBadge(
                        key: ValueKey('ranking-self-badge'),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  games,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 11,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  score,
                  maxLines: 1,
                  style: TextStyle(
                    color: scheme.primary,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CurrentMemberBadge extends StatelessWidget {
  const _CurrentMemberBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        strings.text('我', 'Me'),
        maxLines: 1,
        style: TextStyle(
          color: scheme.onPrimaryContainer,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _LeaderboardEmpty extends StatelessWidget {
  const _LeaderboardEmpty({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 30),
      child: Column(
        children: [
          Icon(
            Icons.leaderboard_outlined,
            color: Theme.of(context).colorScheme.primary,
            size: 34,
          ),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 5),
          Text(body, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

/// Reusable event-ranking section for the Events detail view.
class EventLeaderboard extends StatelessWidget {
  const EventLeaderboard({
    super.key,
    required this.snapshot,
    required this.event,
  });

  final ClubSnapshot snapshot;
  final ClubEvent event;

  @override
  Widget build(BuildContext context) {
    final entries = buildLeaderboard(snapshot, eventId: event.id);
    if (entries.isEmpty) {
      return KeyedSubtree(
        key: ValueKey('event-leaderboard-${event.id}'),
        child: _LeaderboardEmpty(
          title: context.t('暂无活动战绩', 'No event results yet'),
          body: context.t(
            '完成一场与此活动关联的有效对局后，成员会出现在这里。',
            'Members appear after a valid rated game linked to this event.',
          ),
        ),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    return Card(
      key: ValueKey('event-leaderboard-${event.id}'),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _LeaderboardColumnHeader(metric: LeaderboardMetric.pt),
          for (var index = 0; index < entries.length; index++) ...[
            if (index > 0) Divider(height: 1, color: scheme.outlineVariant),
            _LeaderboardRow(
              entry: entries[index],
              metric: LeaderboardMetric.pt,
            ),
          ],
        ],
      ),
    );
  }
}
