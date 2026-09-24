import 'dart:math' as math;

import 'models.dart';

/// Version of the pure PT/MMR calculation implemented in this file.
const String ratingRuleVersion = 'riichi-pt-mmr-v1';

/// MMR assigned to a member who has no prior rating.
const double initialMmr = 1500;

/// Inputs for one member in one completed four-player game.
class RatingInput {
  const RatingInput({
    required this.memberId,
    required this.finalPoints,
    required this.oldMmr,
  });

  final String memberId;
  final int? finalPoints;
  final double oldMmr;
}

/// The PT and MMR result for one member.
class RatingResult {
  const RatingResult({
    required this.memberId,
    required this.actualUma,
    required this.pt,
    required this.oldMmr,
    required this.mmrDelta,
    required this.newMmr,
    required this.expectedUma,
    required this.rankProbabilities,
  });

  final String memberId;
  final double actualUma;
  final double pt;
  final double oldMmr;
  final double mmrDelta;
  final double newMmr;
  final double expectedUma;
  final List<double> rankProbabilities;
}

/// Parameters for the versioned PT/MMR calculation.
///
/// [k] is the base MMR change multiplier (the rules document writes this as
/// an uppercase K). It is intentionally exposed as a lower camel-case Dart
/// field.
class RatingParameters {
  const RatingParameters({
    this.umaByRank = const <double>[30, 10, -10, -30],
    this.riichiStart = 25000,
    this.riichiDiv = 1000,
    this.wUma = 1,
    this.wOffset = 0.4,
    this.perfPosScale = 0.85,
    this.perfNegScale = 1.15,
    this.centerPerf = true,
    this.mmrScale = 400,
    this.betaMmr = 1,
    this.k = 0.75,
    this.enableAsymK = true,
    this.kGamma = 0.3,
    this.kScaleCap = 0.5,
  });

  final List<double> umaByRank;
  final double riichiStart;
  final double riichiDiv;
  final double wUma;
  final double wOffset;
  final double perfPosScale;
  final double perfNegScale;
  final bool centerPerf;
  final double mmrScale;
  final double betaMmr;
  final double k;
  final bool enableAsymK;
  final double kGamma;
  final double kScaleCap;
}

/// Calculates the PT and MMR changes for exactly one completed game.
List<RatingResult> calculateRatings(
  List<RatingInput> players, {
  RatingParameters parameters = const RatingParameters(),
}) {
  _validateParameters(parameters);
  if (players.length != 4) {
    throw const ClubException('评分必须包含四位成员');
  }

  final memberIds = <String>{};
  for (final player in players) {
    if (player.memberId.trim().isEmpty) {
      throw const ClubException('成员 ID 不能为空');
    }
    if (!memberIds.add(player.memberId)) {
      throw const ClubException('成员 ID 不能重复');
    }
    if (!player.oldMmr.isFinite) {
      throw const ClubException('MMR 必须是有限数值');
    }
  }

  final points = <int>[];
  for (final player in players) {
    final score = player.finalPoints;
    if (score == null) {
      throw const ClubException('请填写全部四位成员的点数');
    }
    if (score < _minimumPersistedScore || score > _maximumPersistedScore) {
      throw const ClubException('点数超出可保存范围');
    }
    if (score % 100 != 0) {
      throw const ClubException('点数必须是 100 的倍数');
    }
    points.add(score);
  }
  if (points.fold<int>(0, (sum, score) => sum + score) != 100000) {
    throw const ClubException('点数合计必须为 100,000');
  }

  final actualUma = _actualUma(points, parameters.umaByRank);
  // Expected ranks, opponent averages, and deltas all use the same old-MMR
  // snapshot. The result loop never feeds a new rating into another player's
  // calculation. Keep double precision without rounding intermediate values.
  final rankProbabilities = _rankProbabilities(
    players.map((player) => player.oldMmr).toList(growable: false),
    parameters,
  );
  final expectedUma = <double>[];
  for (final probabilities in rankProbabilities) {
    var expected = 0.0;
    for (var rank = 0; rank < 4; rank++) {
      expected += probabilities[rank] * parameters.umaByRank[rank];
    }
    expectedUma.add(expected);
  }

  final rawPerformance = <double>[];
  for (var index = 0; index < 4; index++) {
    final offset =
        (points[index] - parameters.riichiStart) / parameters.riichiDiv;
    rawPerformance.add(
      parameters.wUma * (actualUma[index] - expectedUma[index]) +
          parameters.wOffset * offset,
    );
  }

  final adjustedPerformance = rawPerformance
      .map(
        (value) => value >= 0
            ? value * parameters.perfPosScale
            : value * parameters.perfNegScale,
      )
      .toList(growable: false);
  final performanceMean = parameters.centerPerf
      ? adjustedPerformance.fold<double>(0, (sum, value) => sum + value) / 4
      : 0;

  final oldMmr = players.map((player) => player.oldMmr).toList(growable: false);
  final results = <RatingResult>[];
  for (var index = 0; index < 4; index++) {
    final centeredPerformance = adjustedPerformance[index] - performanceMean;
    final opponentMean = _meanExcluding(oldMmr, index);
    final asymmetry = parameters.enableAsymK
        ? _asymmetry(
            opponentMean: opponentMean,
            oldMmr: oldMmr[index],
            performance: centeredPerformance,
            parameters: parameters,
          )
        : 1.0;
    final mmrDelta = parameters.k * asymmetry * centeredPerformance;
    final pt =
        (points[index] - parameters.riichiStart) / parameters.riichiDiv +
        actualUma[index];

    results.add(
      RatingResult(
        memberId: players[index].memberId,
        actualUma: actualUma[index],
        pt: pt,
        oldMmr: oldMmr[index],
        mmrDelta: mmrDelta,
        newMmr: oldMmr[index] + mmrDelta,
        expectedUma: expectedUma[index],
        rankProbabilities: List<double>.unmodifiable(rankProbabilities[index]),
      ),
    );
  }
  return List<RatingResult>.unmodifiable(results);
}

// Keep these bounds identical to parseScore in domain/rules.dart. They are
// persisted int32-compatible values, rather than the full Dart int range.
const int _minimumPersistedScore = -2147483600;
const int _maximumPersistedScore = 2147483600;

void _validateParameters(RatingParameters parameters) {
  if (parameters.umaByRank.length != 4 ||
      parameters.umaByRank.any((value) => !value.isFinite)) {
    throw const ClubException('马点参数必须包含四个有限数值');
  }
  if (!parameters.riichiStart.isFinite ||
      !parameters.riichiDiv.isFinite ||
      parameters.riichiDiv <= 0 ||
      !parameters.wUma.isFinite ||
      parameters.wUma < 0 ||
      !parameters.wOffset.isFinite ||
      parameters.wOffset < 0 ||
      !parameters.perfPosScale.isFinite ||
      parameters.perfPosScale < 0 ||
      !parameters.perfNegScale.isFinite ||
      parameters.perfNegScale < 0 ||
      !parameters.mmrScale.isFinite ||
      parameters.mmrScale <= 0 ||
      !parameters.betaMmr.isFinite ||
      parameters.betaMmr < 0 ||
      !parameters.k.isFinite ||
      parameters.k < 0 ||
      !parameters.kGamma.isFinite ||
      parameters.kGamma < 0 ||
      !parameters.kScaleCap.isFinite ||
      parameters.kScaleCap < 0) {
    throw const ClubException('评分参数无效');
  }
}

List<double> _actualUma(List<int> points, List<double> umaByRank) {
  // Sorting only identifies the Uma slots occupied by each tied group, which
  // shares those bonuses equally. Write back by original index so results
  // preserve input order rather than adopting score order.
  final order = List<int>.generate(4, (index) => index)
    ..sort((left, right) => points[right].compareTo(points[left]));
  final actualUma = List<double>.filled(4, 0);
  var groupStart = 0;
  while (groupStart < 4) {
    var groupEnd = groupStart + 1;
    while (groupEnd < 4 &&
        points[order[groupEnd]] == points[order[groupStart]]) {
      groupEnd++;
    }
    var occupiedUma = 0.0;
    for (var position = groupStart; position < groupEnd; position++) {
      occupiedUma += umaByRank[position];
    }
    final averageUma = occupiedUma / (groupEnd - groupStart);
    for (var position = groupStart; position < groupEnd; position++) {
      actualUma[order[position]] = averageUma;
    }
    groupStart = groupEnd;
  }
  return actualUma;
}

List<List<double>> _rankProbabilities(
  List<double> oldMmr,
  RatingParameters parameters,
) {
  final probabilities = List.generate(4, (_) => List<double>.filled(4, 0));
  var totalProbability = 0.0;

  void visit(List<int> remaining, int rank, double probability) {
    if (remaining.isEmpty) {
      totalProbability += probability;
      return;
    }
    final choices = _stableChoiceProbabilities(remaining, oldMmr, parameters);
    for (var choice = 0; choice < remaining.length; choice++) {
      final playerIndex = remaining[choice];
      final nextRemaining = List<int>.from(remaining)..removeAt(choice);
      final nextProbability = probability * choices[choice];
      probabilities[playerIndex][rank] += nextProbability;
      visit(nextRemaining, rank + 1, nextProbability);
    }
  }

  visit([0, 1, 2, 3], 0, 1);
  if (!totalProbability.isFinite || totalProbability <= 0) {
    throw const ClubException('无法计算有效的顺位概率');
  }
  for (final playerProbabilities in probabilities) {
    for (var rank = 0; rank < 4; rank++) {
      playerProbabilities[rank] /= totalProbability;
    }
  }
  return probabilities;
}

List<double> _stableChoiceProbabilities(
  List<int> remaining,
  List<double> oldMmr,
  RatingParameters parameters,
) {
  final bestMmr = remaining
      .map((index) => oldMmr[index])
      .reduce((left, right) => left > right ? left : right);
  final weights = <double>[];
  var weightSum = 0.0;
  for (final index in remaining) {
    final relativeLogit = _relativeLogit(oldMmr[index], bestMmr, parameters);
    final weight = math.exp(relativeLogit);
    weights.add(weight);
    weightSum += weight;
  }
  if (!weightSum.isFinite || weightSum <= 0) {
    throw const ClubException('无法计算有效的顺位概率');
  }
  return weights.map((weight) => weight / weightSum).toList(growable: false);
}

double _relativeLogit(double mmr, double bestMmr, RatingParameters parameters) {
  if (parameters.betaMmr == 0 || mmr == bestMmr) return 0;
  final difference = mmr - bestMmr;
  final scale = parameters.betaMmr / parameters.mmrScale;
  final scaledDifference = difference * scale;
  if (!scaledDifference.isFinite) return -745;
  if (scaledDifference >= 0) return 0;
  return math.max(scaledDifference, -745);
}

double _meanExcluding(List<double> values, int excludedIndex) {
  // Averaging after subtracting a common baseline avoids overflowing the sum
  // for large but finite MMR values while preserving the exact ordinary case.
  final baseline = values[excludedIndex];
  var relativeSum = 0.0;
  for (var index = 0; index < values.length; index++) {
    if (index != excludedIndex) {
      relativeSum += values[index] - baseline;
    }
  }
  final relativeMean = relativeSum / 3;
  final mean = baseline + relativeMean;
  if (mean.isFinite) return mean;

  // If the baseline-relative representation itself overflows, fall back to a
  // scaled sum. This path is only relevant for values close to double limits.
  var largestMagnitude = 0.0;
  for (var index = 0; index < values.length; index++) {
    if (index != excludedIndex) {
      largestMagnitude = math.max(largestMagnitude, values[index].abs());
    }
  }
  if (largestMagnitude == 0) return 0;
  var scaledSum = 0.0;
  for (var index = 0; index < values.length; index++) {
    if (index != excludedIndex) {
      scaledSum += values[index] / largestMagnitude;
    }
  }
  return (scaledSum / 3) * largestMagnitude;
}

double _asymmetry({
  required double opponentMean,
  required double oldMmr,
  required double performance,
  required RatingParameters parameters,
}) {
  final performanceSign = _sign(performance);
  if (performanceSign == 0) return 1;
  final ratingGap = (opponentMean - oldMmr) / parameters.mmrScale;
  return _clamp(
    1 + parameters.kGamma * ratingGap * performanceSign,
    1 - parameters.kScaleCap,
    1 + parameters.kScaleCap,
  );
}

double _clamp(double value, double minimum, double maximum) => value < minimum
    ? minimum
    : value > maximum
    ? maximum
    : value;

double _sign(double value) => value > 0
    ? 1
    : value < 0
    ? -1
    : 0;
