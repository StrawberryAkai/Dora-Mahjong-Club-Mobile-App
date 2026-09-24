import 'package:flutter_test/flutter_test.dart';

import 'package:dora_mahjong/data/demo_club_repository.dart';
import 'package:dora_mahjong/domain/models.dart';

ClubRoom room(ClubSnapshot snapshot, String id) =>
    snapshot.rooms.singleWhere((value) => value.id == id);

ClubGame game(ClubSnapshot snapshot, String id) =>
    snapshot.games.singleWhere((value) => value.id == id);

ClubGame activeGame(ClubSnapshot snapshot, String roomId) =>
    snapshot.activeGame(roomId)!;

Future<void> select(DemoClubRepository repository, String memberId) =>
    repository.selectMember(memberId);

Future<ClubGame> createFreshGame(DemoClubRepository repository) async {
  final seeded = activeGame(await repository.load(), 'room-9162');
  await select(repository, 'andy');
  await repository.cancelGame(
    seeded.id,
    'reset seeded demo game for local test',
    seeded.version,
    'cancel-seeded-for-local-test',
  );
  await repository.startGame('room-9162', 'start-fresh-game');
  return activeGame(await repository.load(), 'room-9162');
}

Future<void> cancelSeededGame(
  DemoClubRepository repository, {
  bool freeEastSeat = false,
}) async {
  final seeded = activeGame(await repository.load(), 'room-9162');
  await repository.signInAdmin('demo', 'demo');
  await repository.cancelGame(
    seeded.id,
    'reset seeded demo game for local seat test',
    seeded.version,
    'cancel-seeded-for-local-seat-test',
  );
  if (freeEastSeat) {
    await repository.leave('room-9162', memberId: 'andy');
  }
  await repository.signOut();
}

Future<ClubGame> saveAll(
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
      'save-${entry.key}-${entry.value}-${current.version}',
    );
    current = game(await repository.load(), current.id);
  }
  return current;
}

void main() {
  group('seed and member flows', () {
    test('starts with demo-only data and no selected identity', () async {
      final repository = DemoClubRepository();
      final snapshot = await repository.load();

      expect(repository.isDemo, isTrue);
      expect(snapshot.memberId, isNull);
      expect(snapshot.isAdmin, isFalse);
      expect(room(snapshot, 'room-7699').seats, isEmpty);
      expect(room(snapshot, 'room-9162').seats.length, 4);
      expect(snapshot.activeGame('room-9162'), isNotNull);
      expect(
        snapshot.games.where((value) => value.status == GameStatus.completed),
        hasLength(1),
      );
    });

    test('trims a new name and rejects case-insensitive duplicates', () async {
      final repository = DemoClubRepository();

      await repository.createMember('  NewPlayer  ');
      var snapshot = await repository.load();
      expect(snapshot.currentMember?.name, 'NewPlayer');

      await expectLater(
        repository.createMember('newplayer'),
        throwsA(isA<ClubException>()),
      );
      snapshot = await repository.load();
      expect(
        snapshot.members.where((member) => member.name == 'NewPlayer'),
        hasLength(1),
      );
    });
  });

  group('seating and start constraints', () {
    test('moves within a room and preserves occupied-seat rejection', () async {
      final repository = DemoClubRepository();
      await select(repository, 'amy');
      await repository.sit('room-7699', Wind.east);

      // Repeating the exact occupied seat for the same member is idempotent.
      await repository.sit('room-7699', Wind.east);
      await repository.sit('room-7699', Wind.south);

      var snapshot = await repository.load();
      expect(room(snapshot, 'room-7699').seats, {Wind.south: 'amy'});

      await select(repository, 'xiaoming');
      await repository.sit('room-7699', Wind.east);
      await select(repository, 'amy');
      await expectLater(
        repository.sit('room-7699', Wind.east),
        throwsA(
          isA<ClubException>().having(
            (error) => error.message,
            'message',
            '这个座位已有人入座',
          ),
        ),
      );

      snapshot = await repository.load();
      expect(room(snapshot, 'room-7699').seats, {
        Wind.south: 'amy',
        Wind.east: 'xiaoming',
      });
    });

    test(
      'moves across rooms atomically and leaves one seat for the member',
      () async {
        final repository = DemoClubRepository();
        await select(repository, 'amy');
        await repository.sit('room-7699', Wind.east);
        await cancelSeededGame(repository, freeEastSeat: true);

        await select(repository, 'amy');
        await repository.sit('room-9162', Wind.east);

        final snapshot = await repository.load();
        expect(room(snapshot, 'room-7699').seats, isEmpty);
        expect(room(snapshot, 'room-9162').seats[Wind.east], 'amy');
        expect(
          snapshot.rooms
              .expand((value) => value.seats.values)
              .where((memberId) => memberId == 'amy'),
          hasLength(1),
        );
      },
    );

    test('rejects an occupied destination and keeps the source seat', () async {
      final repository = DemoClubRepository();
      await select(repository, 'amy');
      await repository.sit('room-7699', Wind.east);
      await cancelSeededGame(repository);
      await select(repository, 'amy');

      await expectLater(
        repository.sit('room-9162', Wind.east),
        throwsA(
          isA<ClubException>().having(
            (error) => error.message,
            'message',
            '这个座位已有人入座',
          ),
        ),
      );
      final snapshot = await repository.load();
      expect(room(snapshot, 'room-7699').seats[Wind.east], 'amy');
      expect(room(snapshot, 'room-9162').seats[Wind.east], 'andy');
    });

    test(
      'an identified member can remove another member from an idle room',
      () async {
        final repository = DemoClubRepository();
        await select(repository, 'amy');
        await repository.sit('room-7699', Wind.east);
        await select(repository, 'zoey');
        final before = await repository.load();

        await repository.leave('room-7699', memberId: 'amy');

        final after = await repository.load();
        expect(room(after, 'room-7699').seats, isEmpty);
        expect(
          Map<String, dynamic>.of(after.toJson())..remove('rooms'),
          Map<String, dynamic>.of(before.toJson())..remove('rooms'),
        );
      },
    );

    test(
      'rejects named seat removal during a game and without identity',
      () async {
        final active = DemoClubRepository();
        await select(active, 'amy');
        final activeBefore = await active.load();
        await expectLater(
          active.leave('room-9162', memberId: 'andy'),
          throwsA(
            isA<ClubException>().having(
              (error) => error.message,
              'message',
              '请先完成或取消当前对局，再调整座位',
            ),
          ),
        );
        final activeAfter = await active.load();
        expect(
          room(activeAfter, 'room-9162').seats,
          room(activeBefore, 'room-9162').seats,
        );

        final seated = DemoClubRepository();
        await select(seated, 'amy');
        await seated.sit('room-7699', Wind.east);
        final saved = Map<String, dynamic>.of((await seated.load()).toJson())
          ..['member_id'] = null
          ..['is_admin'] = false
          ..['admin_name'] = null;
        final visitor = DemoClubRepository(saved: saved);
        await expectLater(
          visitor.leave('room-7699', memberId: 'amy'),
          throwsA(
            isA<ClubException>().having(
              (error) => error.message,
              'message',
              '请先选择成员身份',
            ),
          ),
        );
        expect(room(await visitor.load(), 'room-7699').seats[Wind.east], 'amy');
      },
    );

    test(
      'blocks moves when either the destination or source room is active',
      () async {
        final destinationLocked = DemoClubRepository();
        await select(destinationLocked, 'amy');
        await destinationLocked.sit('room-7699', Wind.east);
        await expectLater(
          destinationLocked.sit('room-9162', Wind.east),
          throwsA(
            isA<ClubException>().having(
              (error) => error.message,
              'message',
              '请先完成或取消当前对局，再调整座位',
            ),
          ),
        );
        expect(
          room(await destinationLocked.load(), 'room-7699').seats[Wind.east],
          'amy',
        );

        final sourceLocked = DemoClubRepository();
        await cancelSeededGame(sourceLocked, freeEastSeat: true);
        for (final (memberId, wind) in [
          ('amy', Wind.east),
          ('zoey', Wind.south),
          ('jin', Wind.west),
          ('xiong', Wind.north),
        ]) {
          await select(sourceLocked, memberId);
          await sourceLocked.sit('room-7699', wind);
        }
        await select(sourceLocked, 'amy');
        await sourceLocked.startGame('room-7699', 'start-source-locked-game');

        await expectLater(
          sourceLocked.sit('room-9162', Wind.east),
          throwsA(
            isA<ClubException>().having(
              (error) => error.message,
              'message',
              '请先完成或取消当前对局，再调整座位',
            ),
          ),
        );
        final snapshot = await sourceLocked.load();
        expect(room(snapshot, 'room-7699').seats[Wind.east], 'amy');
        expect(
          room(snapshot, 'room-9162').seats.containsKey(Wind.east),
          isFalse,
        );
      },
    );

    test(
      'serializes concurrent moves and preserves the one-seat invariant',
      () async {
        final repository = DemoClubRepository();
        await select(repository, 'amy');

        await Future.wait([
          repository.sit('room-7699', Wind.east),
          repository.sit('room-7699', Wind.south),
        ]);

        final seats = room(await repository.load(), 'room-7699').seats;
        expect(seats, {Wind.south: 'amy'});
        expect(
          seats.values.where((memberId) => memberId == 'amy'),
          hasLength(1),
        );
      },
    );

    test('leaves both rooms unchanged when persisting a move fails', () async {
      var failPersistence = false;
      final repository = DemoClubRepository(
        persist: (_) async {
          if (failPersistence) throw StateError('local persistence failed');
        },
      );
      await select(repository, 'amy');
      await repository.sit('room-7699', Wind.east);
      final before = await repository.load();
      failPersistence = true;

      await expectLater(
        repository.sit('room-7699', Wind.south),
        throwsA(isA<StateError>()),
      );

      final after = await repository.load();
      expect(after.toJson(), before.toJson());
    });

    test(
      'locks seating while a game is active and permits four distinct starters',
      () async {
        final repository = DemoClubRepository();
        await select(repository, 'andy');
        await expectLater(
          repository.leave('room-9162'),
          throwsA(isA<ClubException>()),
        );

        final fresh = await createFreshGame(repository);
        expect(fresh.creatorId, 'andy');
        expect(fresh.players.map((player) => player.wind), Wind.values);
        expect(
          fresh.players.map((player) => player.memberId).toSet(),
          hasLength(4),
        );

        await expectLater(
          repository.startGame('room-9162', 'start-again'),
          throwsA(isA<ClubException>()),
        );
      },
    );
  });

  group('score lifecycle', () {
    test(
      'allows zero and negative scores and completes automatically at 100,000',
      () async {
        final repository = DemoClubRepository();
        final started = await createFreshGame(repository);
        final completed = await saveAll(repository, started, {
          'andy': 50000,
          'zoey': 30000,
          'jin': 20000,
          'xiong': 0,
        });

        expect(completed.status, GameStatus.completed);
        expect(completed.total, 100000);
        expect(completed.enteredCount, 4);
        expect(completed.completedAt, isNotNull);
        expect(
          {
            for (final player in completed.players)
              player.memberId: player.rank,
          },
          {'andy': 1, 'zoey': 2, 'jin': 3, 'xiong': 4},
        );
      },
    );

    test(
      'keeps a four-score wrong total active until the correction reaches 100,000',
      () async {
        final repository = DemoClubRepository();
        final started = await createFreshGame(repository);
        var current = await saveAll(repository, started, {
          'andy': 40000,
          'zoey': 35000,
          'jin': 30000,
          'xiong': -5100,
        });

        expect(current.status, GameStatus.active);
        expect(current.total, 99900);
        expect(current.needsCorrection, isTrue);

        await repository.saveScore(
          current.id,
          'xiong',
          -5000,
          current.version,
          'fix-total',
        );
        current = game(await repository.load(), current.id);
        expect(current.status, GameStatus.completed);
        expect(current.total, 100000);
        expect(current.needsCorrection, isFalse);
      },
    );

    test(
      'rejects an ordinary member from saving another player score',
      () async {
        final repository = DemoClubRepository();
        final before = game(await repository.load(), 'demo-active');
        await select(repository, 'zoey');

        await expectLater(
          repository.saveScore(
            before.id,
            'andy',
            32500,
            before.version,
            'not-allowed',
          ),
          throwsA(isA<ClubException>()),
        );
        final after = game(await repository.load(), before.id);
        expect(after.version, before.version);
        expect(
          after.players.map((player) => player.score),
          before.players.map((player) => player.score),
        );
      },
    );
  });

  group('correction and cancellation permissions', () {
    test(
      'applies a valid correction atomically and records one audit',
      () async {
        final repository = DemoClubRepository();
        final before = game(await repository.load(), 'demo-history');
        await select(repository, 'andy');

        await expectLater(
          repository.correctScores(
            before.id,
            {'andy': 30000, 'zoey': 30000, 'jin': 20000, 'xiong': 19900},
            before.version,
            'invalid-total',
          ),
          throwsA(isA<ClubException>()),
        );
        var after = game(await repository.load(), before.id);
        expect(after.version, before.version);
        expect((await repository.load()).audits, isEmpty);

        await repository.correctScores(
          before.id,
          {'andy': 30000, 'zoey': 30000, 'jin': 20000, 'xiong': 20000},
          before.version,
          'valid-correction',
        );
        final snapshot = await repository.load();
        after = game(snapshot, before.id);
        expect(after.status, GameStatus.completed);
        expect(after.total, 100000);
        expect(after.completedAt, before.completedAt);
        expect(snapshot.audits, hasLength(1));
        expect(snapshot.audits.single.actor, 'Andy');
        expect(snapshot.audits.single.before, {
          'andy': 38200,
          'zoey': 27100,
          'jin': 20900,
          'xiong': 13800,
        });
        expect(snapshot.audits.single.after, {
          'andy': 30000,
          'zoey': 30000,
          'jin': 20000,
          'xiong': 20000,
        });
      },
    );

    test(
      'allows only a creator or demo admin to cancel and requires a reason',
      () async {
        final repository = DemoClubRepository();
        final before = game(await repository.load(), 'demo-active');

        await select(repository, 'zoey');
        await expectLater(
          repository.cancelGame(
            before.id,
            'member cannot cancel',
            before.version,
            'ordinary',
          ),
          throwsA(isA<ClubException>()),
        );

        await select(repository, 'andy');
        await expectLater(
          repository.cancelGame(
            before.id,
            '   ',
            before.version,
            'blank-reason',
          ),
          throwsA(isA<ClubException>()),
        );
        var unchanged = game(await repository.load(), before.id);
        expect(unchanged.status, GameStatus.active);
        expect(unchanged.version, before.version);

        await repository.cancelGame(
          before.id,
          '  table reset  ',
          before.version,
          'creator-cancel',
        );
        var snapshot = await repository.load();
        var cancelled = game(snapshot, before.id);
        expect(cancelled.status, GameStatus.cancelled);
        expect(cancelled.cancelReason, 'table reset');
        expect(cancelled.cancelledBy, 'Andy');
        expect(snapshot.activeGame('room-9162'), isNull);

        final adminRepository = DemoClubRepository();
        final adminGame = game(await adminRepository.load(), 'demo-active');
        await adminRepository.signInAdmin('demo', 'demo');
        await adminRepository.cancelGame(
          adminGame.id,
          'admin cleanup',
          adminGame.version,
          'admin-cancel',
        );
        snapshot = await adminRepository.load();
        cancelled = game(snapshot, adminGame.id);
        expect(cancelled.cancelledBy, '管理员（演示）');
      },
    );
  });

  test('replaying a start request is idempotent', () async {
    final repository = DemoClubRepository();
    final seeded = activeGame(await repository.load(), 'room-9162');
    await select(repository, 'andy');
    await repository.cancelGame(
      seeded.id,
      'reset seeded demo game for idempotency test',
      seeded.version,
      'cancel-seeded-for-idempotency-test',
    );

    await repository.startGame('room-9162', 'same-request');
    await repository.startGame('room-9162', 'same-request');
    final snapshot = await repository.load();
    expect(
      snapshot.games.where(
        (value) =>
            value.roomId == 'room-9162' && value.status == GameStatus.active,
      ),
      hasLength(1),
    );
  });
}
