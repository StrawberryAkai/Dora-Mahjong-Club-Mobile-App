import 'package:flutter_test/flutter_test.dart';

import 'package:dora_mahjong/domain/models.dart';
import 'package:dora_mahjong/domain/rules.dart';

void main() {
  group('name rules', () {
    test(
      'trims display input and accepts one to twenty CJK or English runes',
      () {
        expect(validateName(' A '), isNull);
        expect(validateName(' 小明Andy '), isNull);
        expect(validateName(List.filled(20, '明').join()), isNull);
        expect(validateName(List.filled(21, '明').join()), contains('1–20'));
        expect(validateName('   '), contains('1–20'));
      },
    );

    test('rejects digits, internal whitespace, punctuation, and emoji', () {
      for (final input in <String>['A1', 'A B', 'A-B', '小明🙂']) {
        expect(validateName(input), isNotNull, reason: input);
      }
    });

    test(
      'normalizes case and surrounding whitespace only for identity matching',
      () {
        expect(normalizeName('  Andy '), 'andy');
        expect(normalizeName(' 小明Andy '), '小明andy');
        expect(normalizeName('Andy'), normalizeName('andy'));
      },
    );
  });

  group('score rules', () {
    test('accepts zero, negative values, and hundreds after trimming', () {
      expect(parseScore(' 0 '), 0);
      expect(parseScore('-5,000'.replaceAll(',', '')), -5000);
      expect(parseScore('100'), 100);
      expect(parseScore('-100'), -100);
    });

    test('rejects blank, non-integer, and non-hundred point values', () {
      for (final input in <String>['', '25.0', '25,000', '25050', '+100']) {
        expect(
          () => parseScore(input),
          throwsA(isA<ClubException>()),
          reason: input,
        );
      }
    });
  });

  group('ranking rules', () {
    GamePlayer player(String id, Wind wind, int score) =>
        GamePlayer(memberId: id, name: id, wind: wind, score: score);

    test('orders an all-way tie by east, south, west, north', () {
      final ranked = rankPlayers([
        player('north', Wind.north, 25000),
        player('west', Wind.west, 25000),
        player('east', Wind.east, 25000),
        player('south', Wind.south, 25000),
      ]);

      expect(
        {for (final p in ranked) p.memberId: p.rank},
        {'east': 1, 'south': 2, 'west': 3, 'north': 4},
      );
    });

    test('uses starting wind for a tie among the highest scores', () {
      final ranked = rankPlayers([
        player('north', Wind.north, 40000),
        player('west', Wind.west, 40000),
        player('east', Wind.east, 10000),
        player('south', Wind.south, 10000),
      ]);

      expect(
        {for (final p in ranked) p.memberId: p.rank},
        {'west': 1, 'north': 2, 'east': 3, 'south': 4},
      );
    });

    test('requires exactly four players with entered scores', () {
      expect(
        () => rankPlayers([
          player('east', Wind.east, 25000),
          player('south', Wind.south, 25000),
          player('west', Wind.west, 25000),
        ]),
        throwsA(isA<ClubException>()),
      );
      expect(
        () => rankPlayers([
          player('east', Wind.east, 25000),
          player('south', Wind.south, 25000),
          player('west', Wind.west, 25000),
          GamePlayer(memberId: 'north', name: 'north', wind: Wind.north),
        ]),
        throwsA(isA<ClubException>()),
      );
    });
  });

  test('formats negative points with separators', () {
    expect(formatPoints(100000), '100,000');
    expect(formatPoints(-5000), '-5,000');
    expect(formatPoints(0), '0');
  });
}
