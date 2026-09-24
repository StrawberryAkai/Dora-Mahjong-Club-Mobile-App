import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:dora_mahjong/data/demo_club_repository.dart';
import 'package:dora_mahjong/domain/models.dart';
import 'package:dora_mahjong/domain/rating.dart';

ClubGame _game(ClubSnapshot snapshot, String id) =>
    snapshot.games.singleWhere((entry) => entry.id == id);

Future<ClubGame> _freshGame(DemoClubRepository repository) async {
  var snapshot = await repository.load();
  final active = snapshot.activeGame('room-9162')!;
  await repository.selectMember('andy');
  await repository.cancelGame(
    active.id,
    'reset seeded game for rating test',
    active.version,
    'rating-cancel-${active.version}',
  );
  await repository.startGame('room-9162', 'rating-start');
  snapshot = await repository.load();
  return snapshot.activeGame('room-9162')!;
}

Future<ClubGame> _saveAll(
  DemoClubRepository repository,
  ClubGame initial,
  Map<String, int> scores,
) async {
  var current = initial;
  for (final entry in scores.entries) {
    await repository.saveScore(
      current.id,
      entry.key,
      entry.value,
      current.version,
      'rating-score-${current.id}-${entry.key}-${current.version}',
    );
    current = _game(await repository.load(), current.id);
  }
  return current;
}

Map<String, double> _mmr(ClubSnapshot snapshot) => {
  for (final member in snapshot.members) member.id: member.mmr,
};

Map<String, double> _independentMmr(ClubSnapshot snapshot) {
  final values = {
    for (final member in snapshot.members) member.id: member.mmrBaseline,
  };
  final rated = snapshot.games.where((game) => game.settlement != null).toList()
    ..sort(
      (left, right) =>
          left.settlement!.order.compareTo(right.settlement!.order),
    );
  for (final game in rated) {
    final results = calculateRatings(
      game.players
          .map(
            (player) => RatingInput(
              memberId: player.memberId,
              finalPoints: player.score,
              oldMmr: values[player.memberId]!,
            ),
          )
          .toList(),
    );
    for (final result in results) {
      values[result.memberId] = result.newMmr;
    }
  }
  return values;
}

void main() {
  test(
    'settles valid scores with one old MMR vector and keeps full precision',
    () async {
      final repository = DemoClubRepository();
      final started = await _freshGame(repository);
      final before = await repository.load();
      final oldMmr = _mmr(before);
      final completed = await _saveAll(repository, started, {
        'andy': 50000,
        'zoey': 30000,
        'jin': 20000,
        'xiong': 0,
      });

      expect(completed.status, GameStatus.completed);
      expect(completed.settlement?.revision, 1);
      expect(completed.settlement?.order, greaterThan(1));
      expect(completed.settlement?.players, hasLength(4));
      for (final player in completed.players) {
        final settlement = completed.settlement!.player(player.memberId)!;
        expect(settlement.finalPoints, player.score);
        expect(settlement.oldMmr, oldMmr[player.memberId]);
      }
      final expected = calculateRatings(
        completed.players
            .map(
              (player) => RatingInput(
                memberId: player.memberId,
                finalPoints: player.score,
                oldMmr: oldMmr[player.memberId]!,
              ),
            )
            .toList(),
      );
      final after = await repository.load();
      for (final result in expected) {
        expect(
          completed.settlement!.player(result.memberId)!.newMmr,
          result.newMmr,
        );
        expect(
          after.members.singleWhere((m) => m.id == result.memberId).mmr,
          result.newMmr,
        );
      }
    },
  );

  test(
    'incomplete, zero-total-invalid, and cancelled games do not settle or change MMR',
    () async {
      final repository = DemoClubRepository();
      final started = await _freshGame(repository);
      final before = await repository.load();
      final oldMmr = _mmr(before);

      await repository.saveScore(
        started.id,
        'andy',
        50000,
        started.version,
        'incomplete-score',
      );
      var current = _game(await repository.load(), started.id);
      expect(current.settlement, isNull);

      current = await _saveAll(repository, current, {
        'zoey': 30000,
        'jin': 30000,
        'xiong': -100,
      });
      expect(current.status, GameStatus.active);
      expect(current.settlement, isNull);
      expect(_mmr(await repository.load()), oldMmr);

      await repository.cancelGame(
        current.id,
        'invalid total is cancelled',
        current.version,
        'cancel-invalid-total',
      );
      final cancelled = _game(await repository.load(), current.id);
      expect(cancelled.status, GameStatus.cancelled);
      expect(cancelled.settlement, isNull);
      expect(_mmr(await repository.load()), oldMmr);
    },
  );

  test(
    'same request is idempotent when queued concurrently and retries cannot change content',
    () async {
      final repository = DemoClubRepository();
      final started = await _freshGame(repository);
      await Future.wait([
        repository.saveScore(
          started.id,
          'andy',
          40000,
          started.version,
          'same-score',
        ),
        repository.saveScore(
          started.id,
          'andy',
          40000,
          started.version,
          'same-score',
        ),
      ]);
      final after = _game(await repository.load(), started.id);
      expect(after.version, started.version + 1);
      expect(
        after.players.singleWhere((p) => p.memberId == 'andy').score,
        40000,
      );
      await expectLater(
        repository.saveScore(
          started.id,
          'andy',
          41000,
          started.version,
          'same-score',
        ),
        throwsA(isA<ClubException>()),
      );
    },
  );

  test(
    'a failed persistence callback rolls back the whole completion and can be retried',
    () async {
      var failCompletion = true;
      Map<String, dynamic>? saved;
      final repository = DemoClubRepository(
        persist: (value) async {
          final hasNewSettlement = (value['games'] as List).any(
            (entry) =>
                entry is Map &&
                entry['id'] != 'demo-history' &&
                entry['settlement'] != null,
          );
          if (failCompletion && hasNewSettlement) throw StateError('disk full');
          saved = jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
        },
      );
      final started = await _freshGame(repository);
      var current = await _saveAll(repository, started, {
        'andy': 40000,
        'zoey': 30000,
        'jin': 20000,
      });
      final beforeFailure = await repository.load();
      await expectLater(
        repository.saveScore(
          current.id,
          'xiong',
          10000,
          current.version,
          'retryable-completion',
        ),
        throwsA(isA<StateError>()),
      );
      var afterFailure = await repository.load();
      expect(_game(afterFailure, current.id).status, GameStatus.active);
      expect(_mmr(afterFailure), _mmr(beforeFailure));

      failCompletion = false;
      await repository.saveScore(
        current.id,
        'xiong',
        10000,
        current.version,
        'retryable-completion',
      );
      afterFailure = await repository.load();
      expect(_game(afterFailure, current.id).settlement, isNotNull);
      expect(saved, isNotNull);
      final reloaded = await DemoClubRepository(saved: saved!).load();
      expect(_game(reloaded, current.id).settlement, isNotNull);
      expect(_mmr(reloaded), _mmr(afterFailure));
    },
  );

  test('tied scores share Uma while display ranks stay seat ordered', () async {
    final repository = DemoClubRepository();
    final completed = await _saveAll(repository, await _freshGame(repository), {
      'andy': 30000,
      'zoey': 30000,
      'jin': 25000,
      'xiong': 15000,
    });
    expect(completed.players.map((p) => p.rank), [1, 2, 3, 4]);
    expect(completed.settlement!.player('andy')!.actualUma, 20);
    expect(completed.settlement!.player('zoey')!.actualUma, 20);
  });

  test(
    'correction replays later games with new opponents and preserves order/history',
    () async {
      final repository = DemoClubRepository();
      final firstStarted = await _freshGame(repository);
      final first = await _saveAll(repository, firstStarted, {
        'andy': 40000,
        'zoey': 30000,
        'jin': 20000,
        'xiong': 10000,
      });

      await repository.signInAdmin('demo', 'demo');
      for (final memberId in ['andy', 'zoey', 'jin', 'xiong']) {
        await repository.leave('room-9162', memberId: memberId);
      }
      await repository.signOut();
      for (final entry in {
        'andy': Wind.east,
        'zoey': Wind.south,
        'amy': Wind.west,
        'xiaoming': Wind.north,
      }.entries) {
        await repository.selectMember(entry.key);
        await repository.sit('room-7699', entry.value);
      }
      await repository.selectMember('andy');
      await repository.startGame('room-7699', 'second-start');
      var second = (await repository.load()).activeGame('room-7699')!;
      second = await _saveAll(repository, second, {
        'andy': 38000,
        'zoey': 27000,
        'amy': 25000,
        'xiaoming': 10000,
      });
      await repository.createMember('Rin');
      final rinId = (await repository.load()).currentMember!.id;
      await repository.createMember('Mika');
      final mikaId = (await repository.load()).currentMember!.id;
      await repository.signInAdmin('demo', 'demo');
      for (final memberId in ['andy', 'zoey', 'amy', 'xiaoming']) {
        await repository.leave('room-7699', memberId: memberId);
      }
      await repository.signOut();
      for (final entry in {
        'amy': Wind.east,
        'xiaoming': Wind.south,
        rinId: Wind.west,
        mikaId: Wind.north,
      }.entries) {
        await repository.selectMember(entry.key);
        await repository.sit('room-7699', entry.value);
      }
      await repository.selectMember('amy');
      await repository.startGame('room-7699', 'third-start');
      var third = (await repository.load()).activeGame('room-7699')!;
      third = await _saveAll(repository, third, {
        'amy': 40000,
        'xiaoming': 30000,
        rinId: 20000,
        mikaId: 10000,
      });
      final before = await repository.load();
      final oldSecond = _game(before, second.id);
      final oldThird = _game(before, third.id);
      final oldAmyMmr = oldSecond.settlement!.player('amy')!.newMmr;
      final oldRinMmr = oldThird.settlement!.player(rinId)!.newMmr;

      await repository.selectMember('andy');
      await repository.correctScores(
        first.id,
        {'andy': 35000, 'zoey': 30000, 'jin': 20000, 'xiong': 15000},
        first.version,
        'correct-first-rated-game',
      );
      final after = await repository.load();
      final corrected = _game(after, first.id);
      final replayed = _game(after, second.id);
      final replayedThird = _game(after, third.id);
      final unchangedSeed = _game(after, 'demo-history');
      expect(corrected.version, first.version + 1);
      expect(corrected.settlement!.revision, 2);
      expect(corrected.settlementHistory, hasLength(1));
      expect(corrected.settlementHistory.single.revision, 1);
      expect(corrected.settlement!.order, first.settlement!.order);
      expect(replayed.settlement!.revision, 2);
      expect(replayed.settlementHistory, hasLength(1));
      expect(replayed.settlement!.order, oldSecond.settlement!.order);
      expect(replayed.version, oldSecond.version + 1);
      expect(replayed.settlement!.sourceGameId, first.id);
      expect(replayed.settlement!.player('amy')!.newMmr, isNot(oldAmyMmr));
      expect(replayedThird.settlement!.revision, 2);
      expect(replayedThird.settlementHistory, hasLength(1));
      expect(replayedThird.settlement!.order, oldThird.settlement!.order);
      expect(replayedThird.version, oldThird.version + 1);
      expect(replayedThird.settlement!.sourceGameId, first.id);
      expect(replayedThird.settlement!.player(rinId)!.newMmr, isNot(oldRinMmr));
      expect(unchangedSeed.settlement!.revision, 1);
      expect(unchangedSeed.settlementHistory, isEmpty);
      expect(_mmr(after), _independentMmr(after));
    },
  );

  test(
    'legacy completed games stay unrated after load and correction',
    () async {
      final original = await DemoClubRepository().load();
      final legacy = original.toJson();
      legacy.remove('rating_schema_version');
      for (final member in (legacy['members'] as List)) {
        (member as Map).remove('mmr');
        member.remove('mmr_baseline');
      }
      for (final game in (legacy['games'] as List)) {
        (game as Map).remove('settlement');
        game.remove('settlement_history');
      }
      final repository = DemoClubRepository(saved: legacy);
      final loaded = await repository.load();
      expect(loaded.ratingSchemaVersion, 1);
      expect(
        loaded.members.every((member) => member.mmr == initialMmr),
        isTrue,
      );
      expect(_game(loaded, 'demo-history').settlement, isNull);
      await repository.selectMember('andy');
      await repository.correctScores(
        'demo-history',
        {'andy': 38200, 'zoey': 27100, 'jin': 20900, 'xiong': 13800},
        _game(loaded, 'demo-history').version,
        'legacy-correction',
      );
      final corrected = await repository.load();
      expect(_game(corrected, 'demo-history').settlement, isNull);
      expect(
        corrected.members.every((member) => member.mmr == initialMmr),
        isTrue,
      );
    },
  );

  test(
    'failed rated correction persistence rolls back settlement and audit',
    () async {
      var failCorrection = false;
      final repository = DemoClubRepository(
        persist: (value) async {
          if (failCorrection && (value['audits'] as List).isNotEmpty) {
            throw StateError('disk full');
          }
        },
      );
      await repository.selectMember('andy');
      final before = await repository.load();
      final target = _game(before, 'demo-history');
      failCorrection = true;
      await expectLater(
        repository.correctScores(
          target.id,
          {'andy': 35000, 'zoey': 30000, 'jin': 20000, 'xiong': 15000},
          target.version,
          'failed-rated-correction',
        ),
        throwsA(isA<StateError>()),
      );
      final after = await repository.load();
      expect(_mmr(after), _mmr(before));
      expect(_game(after, target.id).toJson(), target.toJson());
      expect(after.audits, isEmpty);
    },
  );

  test('partial or unknown saved rating metadata is rejected', () async {
    final original = (await DemoClubRepository().load()).toJson();
    final partial = jsonDecode(jsonEncode(original)) as Map<String, dynamic>;
    (partial['members'] as List).first.remove('mmr_baseline');
    expect(
      () => DemoClubRepository(saved: partial),
      throwsA(isA<ClubException>()),
    );

    final unknown = jsonDecode(jsonEncode(original)) as Map<String, dynamic>;
    final history =
        (unknown['games'] as List).firstWhere(
              (entry) => (entry as Map)['settlement'] != null,
            )
            as Map;
    (history['settlement'] as Map)['rule_version'] = 'unknown-rule';
    expect(
      () => DemoClubRepository(saved: unknown),
      throwsA(isA<ClubException>()),
    );
  });
}
