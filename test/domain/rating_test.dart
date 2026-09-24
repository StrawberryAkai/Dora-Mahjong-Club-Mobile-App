import 'package:flutter_test/flutter_test.dart';

import 'package:dora_mahjong/domain/models.dart';
import 'package:dora_mahjong/domain/rating.dart';

void main() {
  List<RatingInput> inputs(
    List<int?> scores, {
    List<double> mmr = const [1500, 1500, 1500, 1500],
    List<String> ids = const ['a', 'b', 'c', 'd'],
  }) {
    return [
      for (var index = 0; index < 4; index++)
        RatingInput(
          memberId: ids[index],
          finalPoints: scores[index],
          oldMmr: mmr[index],
        ),
    ];
  }

  test('exposes the version and initial MMR used by the rules', () {
    expect(ratingRuleVersion, 'riichi-pt-mmr-v1');
    expect(initialMmr, 1500);
    expect(const RatingParameters().umaByRank, [30, 10, -10, -30]);
  });

  test('calculates the documented four-way result at equal MMR', () {
    final results = calculateRatings(inputs([40000, 30000, 20000, 10000]));

    expect(results.map((result) => result.actualUma), [30, 10, -10, -30]);
    expect(results.map((result) => result.pt), [45, 15, -15, -45]);
    expect(results[0].mmrDelta, closeTo(25.65, 1e-12));
    expect(results[1].mmrDelta, closeTo(10.35, 1e-12));
    expect(results[2].mmrDelta, closeTo(-7.65, 1e-12));
    expect(results[3].mmrDelta, closeTo(-28.35, 1e-12));
    expect(results.map((result) => result.newMmr), [
      1525.65,
      1510.35,
      1492.35,
      1471.65,
    ]);
    for (final result in results) {
      expect(result.expectedUma, closeTo(0, 1e-12));
      for (final probability in result.rankProbabilities) {
        expect(probability, closeTo(0.25, 1e-12));
      }
    }
  });

  test('averages Uma for every tie pattern', () {
    final highestPair = calculateRatings(inputs([35000, 35000, 20000, 10000]));
    expect(highestPair.map((result) => result.actualUma), [20, 20, -10, -30]);

    final middlePair = calculateRatings(inputs([40000, 25000, 25000, 10000]));
    expect(middlePair.map((result) => result.actualUma), [30, 0, 0, -30]);

    final lowestPair = calculateRatings(inputs([40000, 30000, 15000, 15000]));
    expect(lowestPair.map((result) => result.actualUma), [30, 10, -20, -20]);

    final highestTriple = calculateRatings(
      inputs([30000, 30000, 30000, 10000]),
    );
    expect(highestTriple.map((result) => result.actualUma), [10, 10, 10, -30]);

    final lowestTriple = calculateRatings(inputs([40000, 20000, 20000, 20000]));
    expect(lowestTriple.map((result) => result.actualUma), [30, -10, -10, -10]);

    final allTie = calculateRatings(inputs([25000, 25000, 25000, 25000]));
    expect(allTie.map((result) => result.actualUma), [0, 0, 0, 0]);
  });

  test('accepts zero and negative scores while null remains missing', () {
    final zero = calculateRatings(inputs([50000, 30000, 20000, 0]));
    expect(zero.map((result) => result.pt), [55, 15, -15, -55]);

    final negative = calculateRatings(inputs([40000, 35000, 30000, -5000]));
    expect(negative.map((result) => result.pt), [45, 20, -5, -60]);

    expect(
      () => calculateRatings(inputs([40000, 30000, 20000, null])),
      throwsA(isA<ClubException>()),
    );
  });

  test('rejects invalid player identity, score, and MMR input', () {
    final validScores = [40000, 30000, 20000, 10000];
    final invalidInputs = <List<RatingInput>>[
      inputs(validScores, ids: ['a', 'a', 'c', 'd']),
      inputs(validScores, ids: ['a', ' ', 'c', 'd']),
      inputs([40000, 30000, 20000, 9900]),
      inputs([40000, 30000, 20000, 0]),
      inputs([2147483700, -2147383700, 20000, 100000]),
      inputs(validScores, mmr: [1500, double.nan, 1500, 1500]),
    ];
    for (final invalid in invalidInputs) {
      expect(() => calculateRatings(invalid), throwsA(isA<ClubException>()));
    }

    expect(
      () => calculateRatings(inputs(validScores).sublist(0, 3)),
      throwsA(isA<ClubException>()),
    );
    expect(
      () => calculateRatings(
        inputs(validScores),
        parameters: const RatingParameters(mmrScale: 0),
      ),
      throwsA(isA<ClubException>()),
    );
  });

  test('enumerates stable rank probabilities for varied MMR', () {
    final results = calculateRatings(
      inputs([40000, 30000, 20000, 10000], mmr: [1800, 1600, 1400, 1200]),
    );

    for (final result in results) {
      expect(result.rankProbabilities.length, 4);
      expect(result.rankProbabilities.every((value) => value.isFinite), isTrue);
      expect(
        result.rankProbabilities.fold<double>(0, (sum, value) => sum + value),
        closeTo(1, 1e-12),
      );
      expect(result.expectedUma.isFinite, isTrue);
    }
    for (var rank = 0; rank < 4; rank++) {
      final probabilityMass = results.fold<double>(
        0,
        (sum, result) => sum + result.rankProbabilities[rank],
      );
      expect(probabilityMass, closeTo(1, 1e-12));
    }
    expect(
      results.fold<double>(0, (sum, result) => sum + result.expectedUma),
      closeTo(0, 1e-12),
    );
    expect(
      results.fold<double>(0, (sum, result) => sum + result.mmrDelta),
      closeTo(0.34198479, 1e-7),
    );
  });

  test('does not force asymmetric MMR changes back to zero', () {
    final results = calculateRatings(
      inputs([40000, 30000, 20000, 10000], mmr: [1800, 1600, 1400, 1200]),
    );
    final sum = results.fold<double>(
      0,
      (total, result) => total + result.mmrDelta,
    );
    expect(sum.abs(), greaterThan(1e-6));

    final symmetric = calculateRatings(
      inputs([40000, 30000, 20000, 10000], mmr: [1800, 1600, 1400, 1200]),
      parameters: const RatingParameters(enableAsymK: false),
    );
    expect(
      symmetric.fold<double>(0, (total, result) => total + result.mmrDelta),
      closeTo(0, 1e-12),
    );
  });

  test('is invariant to player order and a common MMR translation', () {
    final ordered = calculateRatings(
      inputs([40000, 30000, 20000, 10000], mmr: [1800, 1600, 1400, 1200]),
    );
    final reordered = calculateRatings(
      inputs(
        [10000, 40000, 30000, 20000],
        mmr: [1200, 1800, 1600, 1400],
        ids: ['d', 'a', 'b', 'c'],
      ),
    );
    final byId = {for (final result in reordered) result.memberId: result};
    for (final result in ordered) {
      final counterpart = byId[result.memberId]!;
      expect(counterpart.actualUma, result.actualUma);
      expect(counterpart.pt, result.pt);
      expect(counterpart.expectedUma, closeTo(result.expectedUma, 1e-12));
      expect(counterpart.mmrDelta, closeTo(result.mmrDelta, 1e-12));
    }

    final translated = calculateRatings(
      inputs([40000, 30000, 20000, 10000], mmr: [11800, 11600, 11400, 11200]),
    );
    for (var index = 0; index < 4; index++) {
      expect(
        translated[index].expectedUma,
        closeTo(ordered[index].expectedUma, 1e-12),
      );
      expect(
        translated[index].mmrDelta,
        closeTo(ordered[index].mmrDelta, 1e-12),
      );
    }
  });

  test('stays finite for very large finite MMR gaps', () {
    final results = calculateRatings(
      inputs([40000, 30000, 20000, 10000], mmr: [1e9, -1e9, 5e8, -5e8]),
    );
    for (final result in results) {
      expect(result.expectedUma.isFinite, isTrue);
      expect(result.rankProbabilities.every((value) => value.isFinite), isTrue);
      expect(
        result.rankProbabilities.fold<double>(0, (sum, value) => sum + value),
        closeTo(1, 1e-12),
      );
    }
  });

  test('allows zero and negative unbounded finite MMR values', () {
    final results = calculateRatings(
      inputs([40000, 30000, 20000, 10000], mmr: [0, -1000, 1e7, -1e7]),
    );
    for (final result in results) {
      expect(result.oldMmr.isFinite, isTrue);
      expect(result.newMmr.isFinite, isTrue);
    }
  });
}
