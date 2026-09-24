import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/game_result_summary.dart';
import '../domain/leaderboard.dart';
import '../domain/models.dart';
import '../domain/rules.dart';
import 'localization.dart';

/// Formats a PT value for display only. Rating values are kept at full
/// precision in the domain model; this trims the trailing zero from the one
/// decimal place used by the UI.
String formatRatingPt(double value, {bool signed = false}) {
  final text = _formatRatingNumber(value, decimals: 1, trimTrailingZero: true);
  if (!signed || text == '—' || text == '0') return text;
  return value > 0 ? '+$text' : text;
}

/// Formats an MMR value to the two decimal places shown in the UI.
String formatRatingMmr(double value) =>
    _formatRatingNumber(value, decimals: 2, trimTrailingZero: false);

/// Formats an MMR change with an explicit sign, while avoiding `-0.00`.
String formatRatingMmrDelta(double value) {
  final text = formatRatingMmr(value);
  if (text == '—' || text == '0.00') return text;
  return value > 0 ? '+$text' : text;
}

String _formatRatingNumber(
  double value, {
  required int decimals,
  required bool trimTrailingZero,
}) {
  if (!value.isFinite) return '—';
  final zeroThreshold = math.pow(10, -decimals) / 2;
  final normalized = value.abs() < zeroThreshold ? 0.0 : value;
  var text = normalized.toStringAsFixed(decimals);
  if (trimTrailingZero) {
    text = text.replaceFirst(RegExp(r'\.0$'), '');
  }
  return text == '-0' ? '0' : text;
}

/// The current member's authoritative MMR, shown in the member profile.
class CurrentMmrCard extends StatelessWidget {
  const CurrentMmrCard({super.key, required this.member});

  final Member member;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 15),
        child: Row(
          children: [
            Icon(Icons.insights_rounded, color: scheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                context.t('当前MMR', 'Current MMR'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              formatRatingMmr(member.mmr),
              style: TextStyle(
                color: scheme.primary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows the two authoritative profile metrics with equal visual weight.
///
/// PT is derived from the current completed settlements rather than stored on
/// the member record. Keeping the derivation here in the presentation layer
/// means the profile uses the same pure ranking rule as the leaderboard.
class ProfileRatingCard extends StatelessWidget {
  const ProfileRatingCard({super.key, required this.snapshot});

  final ClubSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final member = snapshot.currentMember;
    if (member == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final pt = cumulativePt(snapshot, member.id);
    return Card(
      key: const ValueKey('profile-rating-card'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Row(
          children: [
            Expanded(
              child: _ProfileMetric(
                label: context.t('累计PT', 'Cumulative PT'),
                value: formatRatingPt(pt),
                icon: Icons.stars_rounded,
                color: scheme.primary,
              ),
            ),
            Container(width: 1, height: 54, color: scheme.outlineVariant),
            Expanded(
              child: _ProfileMetric(
                label: context.t('当前MMR', 'Current MMR'),
                value: formatRatingMmr(member.mmr),
                icon: Icons.insights_rounded,
                color: scheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileMetric extends StatelessWidget {
  const _ProfileMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 6),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    ),
  );
}

/// Displays the authoritative settlement attached to a completed game.
///
/// The game players provide names and seat display order. Settlement values
/// are always looked up by [GamePlayer.memberId], so a changed display name
/// cannot make a rating row point at another member.
class RatingSettlementPanel extends StatelessWidget {
  const RatingSettlementPanel({
    super.key,
    required this.snapshot,
    required this.game,
  });

  final ClubSnapshot snapshot;
  final ClubGame game;

  @override
  Widget build(BuildContext context) {
    final settlement = game.settlement;
    if (game.status != GameStatus.completed) return const SizedBox.shrink();
    if (settlement == null) return const _LegacyUnratedCard();

    return _SettlementCard(
      settlement: settlement,
      players: game.players,
      history: game.settlementHistory,
      summaries: buildGameResultSummaries(snapshot, game),
    );
  }
}

class _LegacyUnratedCard extends StatelessWidget {
  const _LegacyUnratedCard();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, color: scheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.t('未纳入积分结算', 'Not rated'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    context.t(
                      '这场历史对局没有积分结算记录，当前不会自动补算。',
                      'This completed legacy game has no settlement record and is not backfilled automatically.',
                    ),
                    style: TextStyle(
                      color: scheme.onSurface.withValues(alpha: .68),
                      height: 1.35,
                      fontSize: 13,
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

class _SettlementCard extends StatelessWidget {
  const _SettlementCard({
    required this.settlement,
    required this.players,
    required this.history,
    required this.summaries,
  });

  final GameSettlement settlement;
  final List<GamePlayer> players;
  final List<GameSettlement> history;
  final Map<String, GameResultSummary> summaries;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ..._settlementRows(
              context,
              players: players,
              settlement: settlement,
              summaries: summaries,
              showGlobalRanks: true,
            ),
            if (history.isNotEmpty)
              ExpansionTile(
                key: const ValueKey('rating-settlement-history'),
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: Text(
                  context.t('历史记录', 'Previous results'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  context.t(
                    '${history.length} 条旧结算记录',
                    '${history.length} earlier result${history.length == 1 ? '' : 's'}',
                  ),
                  style: TextStyle(
                    color: scheme.onSurface.withValues(alpha: .62),
                    fontSize: 12,
                  ),
                ),
                children: [
                  for (final previous in history)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _PreviousSettlement(
                        settlement: previous,
                        players: players,
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _PreviousSettlement extends StatelessWidget {
  const _PreviousSettlement({required this.settlement, required this.players});

  final GameSettlement settlement;
  final List<GamePlayer> players;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${context.t('结算时间', 'Settled')} ${_formatSettlementTimestamp(context, settlement.settledAt)}',
            style: TextStyle(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: .62),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 7),
          ..._settlementRows(
            context,
            players: players,
            settlement: settlement,
            showGlobalRanks: false,
          ),
        ],
      ),
    );
  }
}

class _PlayerSettlementRow extends StatelessWidget {
  const _PlayerSettlementRow({
    required this.player,
    required this.settlement,
    required this.placement,
    required this.summary,
    required this.showGlobalRanks,
  });

  final GamePlayer player;
  final PlayerSettlement? settlement;
  final int placement;
  final GameResultSummary? summary;
  final bool showGlobalRanks;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final entry = settlement;
    if (entry == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            _RankBadge(rank: placement),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                player.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              context.t('待结算', 'Pending'),
              style: TextStyle(
                color: scheme.onSurface.withValues(alpha: .62),
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }

    final ptValue = showGlobalRanks
        ? summary == null
              ? '—'
              : formatRatingPt(summary!.ptAfter)
        : formatRatingPt(entry.pt);
    final ptLabel = showGlobalRanks
        ? 'PT'
        : context.t('单场PT', 'Single-game PT');

    return Padding(
      key: showGlobalRanks ? ValueKey('game-result-${player.memberId}') : null,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _RankBadge(rank: placement),
              const SizedBox(width: 9),
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 5,
                  runSpacing: 2,
                  children: [
                    Text(
                      player.name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      '(${formatPoints(entry.finalPoints)})',
                      style: TextStyle(
                        color: scheme.onSurface.withValues(alpha: .68),
                        fontSize: 12,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      doraWindLabel(context, player.wind, compact: true),
                      style: TextStyle(
                        color: scheme.onSurface.withValues(alpha: .62),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SettlementMetricLine(
                key: showGlobalRanks
                    ? ValueKey('game-result-mmr-${player.memberId}')
                    : null,
                label: 'MMR',
                value: formatRatingMmr(entry.newMmr),
                delta: formatRatingMmrDelta(entry.mmrDelta),
                deltaAmount: entry.mmrDelta,
                rankLabel: context.t('排名', 'Rank'),
                rank: showGlobalRanks ? summary?.mmrRankAfter : null,
                rankChange: showGlobalRanks ? summary?.mmrRankChange : null,
                showRank: showGlobalRanks,
              ),
              const SizedBox(height: 2),
              _SettlementMetricLine(
                key: showGlobalRanks
                    ? ValueKey('game-result-pt-${player.memberId}')
                    : null,
                label: ptLabel,
                value: ptValue,
                delta: showGlobalRanks
                    ? formatRatingPt(entry.pt, signed: true)
                    : null,
                deltaAmount: showGlobalRanks ? entry.pt : null,
                rankLabel: context.t('排名', 'Rank'),
                rank: showGlobalRanks ? summary?.ptRankAfter : null,
                rankChange: showGlobalRanks ? summary?.ptRankChange : null,
                showRank: showGlobalRanks,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (rank) {
      1 => scheme.secondary,
      2 => scheme.surfaceContainerHighest,
      3 => scheme.tertiaryContainer,
      _ => scheme.surfaceContainerLow,
    };
    final foreground = switch (rank) {
      1 => scheme.onSecondary,
      2 => scheme.onSurface,
      3 => scheme.onTertiaryContainer,
      _ => scheme.onSurfaceVariant,
    };
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(9),
      ),
      alignment: Alignment.center,
      child: Text(
        '$rank',
        style: TextStyle(
          color: foreground,
          fontSize: 12,
          fontWeight: FontWeight.w900,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _SettlementMetricLine extends StatelessWidget {
  const _SettlementMetricLine({
    super.key,
    required this.label,
    required this.value,
    required this.delta,
    required this.deltaAmount,
    required this.rankLabel,
    required this.rank,
    required this.rankChange,
    required this.showRank,
  });

  final String label;
  final String value;
  final String? delta;
  final double? deltaAmount;
  final String rankLabel;
  final int? rank;
  final int? rankChange;
  final bool showRank;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      runSpacing: 2,
      children: [
        Text(
          '$label:',
          style: TextStyle(
            color: scheme.onSurface.withValues(alpha: .62),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        if (delta != null)
          _SignedRatingValue(value: delta!, amount: deltaAmount),
        if (showRank) ...[
          Text(
            '|',
            style: TextStyle(
              color: scheme.onSurface.withValues(alpha: .42),
              fontSize: 11,
            ),
          ),
          Text(
            rank == null ? '$rankLabel —' : '$rankLabel #$rank',
            style: TextStyle(
              color: scheme.onSurface.withValues(alpha: .68),
              fontSize: 11,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          _RankMovement(change: rankChange),
        ],
      ],
    );
  }
}

class _SignedRatingValue extends StatelessWidget {
  const _SignedRatingValue({required this.value, required this.amount});

  final String value;
  final double? amount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final direction = amount == null
        ? 0
        : amount! > 0
        ? 1
        : amount! < 0
        ? -1
        : 0;
    if (direction == 0) {
      return Text(
        '($value)',
        style: TextStyle(
          color: scheme.onSurface.withValues(alpha: .68),
          fontSize: 11,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
    }
    final color = direction > 0 ? scheme.primary : scheme.error;
    return Text(
      '($value)',
      style: TextStyle(
        color: color,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

class _RankMovement extends StatelessWidget {
  const _RankMovement({required this.change});

  final int? change;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (change == null) {
      return Semantics(
        label: context.t('排名变化未知', 'Rank change unavailable'),
        excludeSemantics: true,
        child: Text(
          '—',
          style: TextStyle(
            color: scheme.onSurface.withValues(alpha: .55),
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }
    if (change == 0) {
      return Semantics(
        label: context.t('排名不变', 'Unchanged'),
        excludeSemantics: true,
        child: Text(
          '—',
          style: TextStyle(
            color: scheme.onSurface.withValues(alpha: .55),
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }
    final improved = change! > 0;
    final color = improved ? scheme.primary : scheme.error;
    return Semantics(
      label: context.t(
        '${improved ? '上升' : '下降'} ${change!.abs()} 名',
        '${improved ? 'Up' : 'Down'} ${change!.abs()} places',
      ),
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            improved
                ? Icons.arrow_upward_rounded
                : Icons.arrow_downward_rounded,
            size: 13,
            color: color,
          ),
          Text(
            '${change!.abs()}',
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

List<Widget> _settlementRows(
  BuildContext context, {
  required List<GamePlayer> players,
  required GameSettlement settlement,
  Map<String, GameResultSummary> summaries = const {},
  required bool showGlobalRanks,
}) {
  final sortedPlayers = [...players]
    ..sort((a, b) {
      final aPoints = settlement.player(a.memberId)?.finalPoints ?? a.score;
      final bPoints = settlement.player(b.memberId)?.finalPoints ?? b.score;
      if (aPoints == null && bPoints != null) return 1;
      if (aPoints != null && bPoints == null) return -1;
      if (aPoints != null && bPoints != null) {
        final points = bPoints.compareTo(aPoints);
        if (points != 0) return points;
      }
      return a.wind.index.compareTo(b.wind.index);
    });

  return [
    for (var index = 0; index < sortedPlayers.length; index++) ...[
      if (index > 0)
        Divider(
          height: 9,
          thickness: 1,
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      _PlayerSettlementRow(
        player: sortedPlayers[index],
        settlement: settlement.player(sortedPlayers[index].memberId),
        placement: index + 1,
        summary: summaries[sortedPlayers[index].memberId],
        showGlobalRanks: showGlobalRanks,
      ),
    ],
  ];
}

String _formatSettlementTimestamp(BuildContext context, DateTime timestamp) {
  final local = timestamp.toLocal();
  final material = MaterialLocalizations.of(context);
  return '${material.formatMediumDate(local)} · ${material.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
}
