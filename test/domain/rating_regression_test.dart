import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:dora_mahjong/domain/models.dart';
import 'package:dora_mahjong/domain/rating.dart';

class _GoldenCase {
  const _GoldenCase({
    required this.name,
    required this.points,
    required this.oldMmr,
    required this.actualUma,
    required this.pt,
    required this.expectedUma,
    required this.mmrDelta,
    required this.newMmr,
  });

  final String name;
  final List<int> points;
  final List<double> oldMmr;
  final List<double> actualUma;
  final List<double> pt;
  final List<double> expectedUma;
  final List<double> mmrDelta;
  final List<double> newMmr;
}

const _goldens = <_GoldenCase>[
  _GoldenCase(
    name: 'A standard',
    points: [40000, 30000, 20000, 10000],
    oldMmr: [1500, 1500, 1500, 1500],
    actualUma: [30, 10, -10, -30],
    pt: [45, 15, -15, -45],
    expectedUma: [0, 0, 0, 0],
    mmrDelta: [25.65, 10.35, -7.65, -28.35],
    newMmr: [1525.65, 1510.35, 1492.35, 1471.65],
  ),
  _GoldenCase(
    name: 'B top tie',
    points: [35000, 35000, 20000, 10000],
    oldMmr: [1500, 1500, 1500, 1500],
    actualUma: [20, 20, -10, -30],
    pt: [30, 30, -15, -45],
    expectedUma: [0, 0, 0, 0],
    mmrDelta: [18, 18, -7.65, -28.35],
    newMmr: [1518, 1518, 1492.35, 1471.65],
  ),
  _GoldenCase(
    name: 'C all tie',
    points: [25000, 25000, 25000, 25000],
    oldMmr: [1500, 1500, 1500, 1500],
    actualUma: [0, 0, 0, 0],
    pt: [0, 0, 0, 0],
    expectedUma: [0, 0, 0, 0],
    mmrDelta: [0, 0, 0, 0],
    newMmr: [1500, 1500, 1500, 1500],
  ),
  _GoldenCase(
    name: 'D zero score',
    points: [50000, 30000, 20000, 0],
    oldMmr: [1500, 1500, 1500, 1500],
    actualUma: [30, 10, -10, -30],
    pt: [55, 15, -15, -55],
    expectedUma: [0, 0, 0, 0],
    mmrDelta: [28.425, 10.575, -7.425, -31.575],
    newMmr: [1528.425, 1510.575, 1492.575, 1468.425],
  ),
  _GoldenCase(
    name: 'E negative score',
    points: [40000, 35000, 30000, -5000],
    oldMmr: [1500, 1500, 1500, 1500],
    actualUma: [30, 10, -10, -30],
    pt: [45, 20, -5, -60],
    expectedUma: [0, 0, 0, 0],
    mmrDelta: [25.7625, 11.7375, -4.0875, -33.4125],
    newMmr: [1525.7625, 1511.7375, 1495.9125, 1466.5875],
  ),
  _GoldenCase(
    name: 'F mixed MMR',
    points: [40000, 30000, 20000, 10000],
    oldMmr: [1800, 1600, 1400, 1200],
    actualUma: [30, 10, -10, -30],
    pt: [45, 15, -15, -45],
    expectedUma: [
      13.42184772051006,
      4.621171572600097,
      -4.621171572600099,
      -13.421847720510058,
    ],
    mmrDelta: [
      11.25505657005617,
      5.750174958506992,
      -4.211243418482875,
      -12.452003323408261,
    ],
    newMmr: [
      1811.2550565700562,
      1605.750174958507,
      1395.7887565815172,
      1187.5479966765918,
    ],
  ),
  _GoldenCase(
    name: 'G mixed MMR all tie',
    points: [25000, 25000, 25000, 25000],
    oldMmr: [1800, 1600, 1400, 1200],
    actualUma: [0, 0, 0, 0],
    pt: [0, 0, 0, 0],
    expectedUma: [
      13.42184772051006,
      4.621171572600097,
      -4.621171572600099,
      -13.421847720510058,
    ],
    mmrDelta: [
      -13.729850970813226,
      -3.2679247107431513,
      4.35700838404701,
      12.442752084181391,
    ],
    newMmr: [
      1786.2701490291868,
      1596.732075289257,
      1404.357008384047,
      1212.4427520841814,
    ],
  ),
];

List<RatingInput> _inputs(
  List<int?> points, {
  List<double> oldMmr = const [1500, 1500, 1500, 1500],
}) {
  return [
    for (var index = 0; index < 4; index++)
      RatingInput(
        memberId: 'player-$index',
        finalPoints: points[index],
        oldMmr: oldMmr[index],
      ),
  ];
}

void _expectCloseVector(
  List<double> actual,
  List<double> expected,
  String field,
) {
  expect(actual, hasLength(expected.length));
  for (var index = 0; index < expected.length; index++) {
    expect(
      actual[index],
      closeTo(expected[index], 1e-7),
      reason: '$field[$index]',
    );
  }
}

void main() {
  test('matches every section 6 corrected golden vector', () {
    for (final golden in _goldens) {
      final results = calculateRatings(
        _inputs(golden.points, oldMmr: golden.oldMmr),
      );

      expect(results, hasLength(4), reason: golden.name);
      _expectCloseVector(
        results.map((result) => result.actualUma).toList(),
        golden.actualUma,
        '${golden.name} actualUma',
      );
      _expectCloseVector(
        results.map((result) => result.pt).toList(),
        golden.pt,
        '${golden.name} pt',
      );
      _expectCloseVector(
        results.map((result) => result.expectedUma).toList(),
        golden.expectedUma,
        '${golden.name} expectedUma',
      );
      _expectCloseVector(
        results.map((result) => result.oldMmr).toList(),
        golden.oldMmr,
        '${golden.name} oldMmr',
      );
      _expectCloseVector(
        results.map((result) => result.mmrDelta).toList(),
        golden.mmrDelta,
        '${golden.name} mmrDelta',
      );
      _expectCloseVector(
        results.map((result) => result.newMmr).toList(),
        golden.newMmr,
        '${golden.name} newMmr',
      );
    }
  });

  test('centerPerf false uses the uncentered literal performance values', () {
    // With equal MMR, E is zero and the documented H vector is
    // [36, 12, -12, -36] adjusted to [30.6, 10.2, -13.8, -41.4].
    // centerPerf:false therefore applies K=.75 directly to that vector.
    final results = calculateRatings(
      _inputs([40000, 30000, 20000, 10000]),
      parameters: const RatingParameters(centerPerf: false),
    );

    _expectCloseVector(results.map((result) => result.mmrDelta).toList(), [
      22.95,
      7.65,
      -10.35,
      -31.05,
    ], 'centerPerf:false mmrDelta');
    expect(
      results.fold<double>(0, (sum, result) => sum + result.mmrDelta),
      closeTo(-10.8, 1e-7),
    );
  });

  test('enableAsymK false uses the literal symmetric K multiplier', () {
    // This vector is independently derived from the documented expected Uma,
    // positive/negative performance scales, and centered performance. Setting
    // C_i=1 gives K=.75 * V_i for every player.
    final results = calculateRatings(
      _inputs([40000, 30000, 20000, 10000], oldMmr: [1800, 1600, 1400, 1200]),
      parameters: const RatingParameters(enableAsymK: false),
    );

    _expectCloseVector(results.map((result) => result.mmrDelta).toList(), [
      16.078652242937387,
      6.389083287229991,
      -4.679159353869861,
      -17.78857617629752,
    ], 'enableAsymK:false mmrDelta');
    expect(
      results.fold<double>(0, (sum, result) => sum + result.mmrDelta),
      closeTo(0, 1e-7),
    );
  });

  test('rejects a nonmultiple score with a valid total and infinite MMR', () {
    expect(
      () => calculateRatings(_inputs([40150, 29850, 20000, 10000])),
      throwsA(isA<ClubException>()),
    );
    expect(
      () => calculateRatings(
        _inputs(
          [40000, 30000, 20000, 10000],
          oldMmr: [double.infinity, 1500, 1500, 1500],
        ),
      ),
      throwsA(isA<ClubException>()),
    );
    expect(
      () => calculateRatings(
        _inputs(
          [40000, 30000, 20000, 10000],
          oldMmr: [1500, 1500, 1500, double.negativeInfinity],
        ),
      ),
      throwsA(isA<ClubException>()),
    );
  });

  test('rating model JSON rejects explicit null and NaN values', () {
    expect(
      () => Member.fromJson({'id': 'p', 'name': 'P', 'mmr': null}),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => Member.fromJson({
        'id': 'p',
        'name': 'P',
        'mmr': double.nan,
        'mmr_baseline': 1500,
      }),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => PlayerSettlement.fromJson({
        'member_id': 'p',
        'final_points': 25000,
        'actual_uma': 0,
        'pt': null,
        'old_mmr': 1500,
        'mmr_delta': 0,
        'new_mmr': 1500,
      }),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => PlayerSettlement.fromJson({
        'member_id': 'p',
        'final_points': 25000,
        'actual_uma': 0,
        'pt': 0,
        'old_mmr': double.nan,
        'mmr_delta': 0,
        'new_mmr': 1500,
      }),
      throwsA(isA<FormatException>()),
    );
  });

  test('rating model JSON preserves a large finite MMR', () {
    const member = Member(
      id: 'large',
      name: 'Large',
      mmr: 1234567890123.125,
      mmrBaseline: -987654321098.625,
    );
    final encoded = jsonEncode(member.toJson());
    final decoded = Member.fromJson(
      Map<String, dynamic>.from(jsonDecode(encoded) as Map),
    );

    expect(decoded.mmr, member.mmr);
    expect(decoded.mmrBaseline, member.mmrBaseline);
  });
}
