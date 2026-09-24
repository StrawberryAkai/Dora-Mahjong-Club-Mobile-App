import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dora_mahjong/application/club_controller.dart';
import 'package:dora_mahjong/data/demo_club_repository.dart';
import 'package:dora_mahjong/domain/models.dart';

class LostStartResponseRepository extends DemoClubRepository {
  var loseNextStartResponse = true;

  @override
  Future<void> startGame(
    String roomId,
    String requestId, {
    String? eventId,
  }) async {
    await super.startGame(roomId, requestId, eventId: eventId);
    if (loseNextStartResponse) {
      loseNextStartResponse = false;
      throw StateError('simulated lost start response');
    }
  }
}

class LostCorrectionResponseRepository extends DemoClubRepository {
  var loseNextCorrectionResponse = true;

  @override
  Future<void> correctScores(
    String gameId,
    Map<String, int> scores,
    int expectedVersion,
    String requestId,
  ) async {
    await super.correctScores(gameId, scores, expectedVersion, requestId);
    if (loseNextCorrectionResponse) {
      loseNextCorrectionResponse = false;
      throw StateError('simulated lost correction response');
    }
  }
}

class LostEventResponseRepository extends DemoClubRepository {
  var loseNextEventResponse = true;

  @override
  Future<void> saveEvent(EventDraft draft, String requestId) async {
    await super.saveEvent(draft, requestId);
    if (loseNextEventResponse) {
      loseNextEventResponse = false;
      throw StateError('simulated lost event response');
    }
  }
}

class PresenceTestRepository extends DemoClubRepository {
  @override
  bool get isDemo => false;

  int heartbeatCount = 0;
  int loadCount = 0;
  bool failRelease = false;
  Completer<void>? mutationGate;
  final List<String> operations = <String>[];

  @override
  Future<ClubSnapshot> load() async {
    loadCount++;
    operations.add('load');
    return super.load();
  }

  @override
  Future<void> heartbeatPresence() async {
    heartbeatCount++;
  }

  @override
  Future<void> releasePresence() async {
    operations.add('release');
    if (failRelease) throw StateError('simulated release failure');
    await super.releasePresence();
  }

  @override
  Future<void> signOut() async {
    await releasePresence();
    operations.add('signout');
    await super.signOut();
  }

  @override
  Future<void> createMember(String name) async {
    await mutationGate?.future;
  }

  @override
  void onAppClosing() {
    operations.add('close');
  }
}

void main() {
  late ClubController controller;

  setUp(() async {
    controller = ClubController(DemoClubRepository());
    await controller.initialize();
  });

  tearDown(() {
    controller.dispose();
  });

  test(
    'event creation retry after a lost response does not create a duplicate',
    () async {
      final retryController = ClubController(LostEventResponseRepository());
      addTearDown(retryController.dispose);
      await retryController.initialize();
      await retryController.signInAdmin('demo', 'demo');
      final now = DateTime.now();
      final draft = EventDraft(
        name: 'Retry event',
        description: 'Local controller test',
        startsAt: now,
        endsAt: now.add(const Duration(hours: 3)),
        roomIds: const ['room-7699', 'room-9162'],
      );
      final before = retryController.snapshot.events.length;
      expect(await retryController.saveEvent(draft), isFalse);
      expect(retryController.snapshot.events.length, before + 1);
      final created = retryController.snapshot.events.singleWhere(
        (event) => event.name == draft.name,
      );
      expect(await retryController.saveEvent(draft), isTrue);
      expect(retryController.snapshot.events.length, before + 1);
      expect(
        retryController.snapshot.events
            .singleWhere((event) => event.name == draft.name)
            .id,
        created.id,
      );
    },
  );

  test('initializes a local demo without selecting an identity', () {
    expect(controller.isDemo, isTrue);
    expect(controller.loading, isFalse);
    expect(controller.member, isNull);
    expect(controller.isAdmin, isFalse);
    expect(controller.snapshot.rooms, hasLength(2));
  });

  test(
    'returns false and exposes repository errors while preserving state',
    () async {
      final memberCount = controller.snapshot.members.length;

      expect(await controller.createMember('  Casey  '), isTrue);
      expect(controller.member?.name, 'Casey');
      expect(controller.notice, '成员已创建');
      expect(controller.error, isNull);

      expect(await controller.createMember('casey'), isFalse);
      expect(controller.error, contains('已存在'));
      expect(controller.busy, isFalse);
      expect(controller.snapshot.members, hasLength(memberCount + 1));
      expect(controller.member?.name, 'Casey');

      controller.clearFeedback();
      expect(controller.error, isNull);
      expect(controller.notice, isNull);
    },
  );

  test(
    'runs the local seating, start, and automatic completion flow',
    () async {
      expect(await controller.selectMember('andy'), isTrue);
      final seeded = controller.snapshot.activeGame('room-9162')!;
      expect(
        await controller.cancelGame(seeded, 'reset for controller score flow'),
        isTrue,
      );
      expect(await controller.startGame('room-9162'), isTrue);
      var current = controller.snapshot.activeGame('room-9162')!;
      expect(current.status, GameStatus.active);

      for (final entry in <String, int>{
        'andy': 50000,
        'zoey': 30000,
        'jin': 20000,
        'xiong': 0,
      }.entries) {
        expect(
          await controller.saveScore(current, entry.key, entry.value),
          isTrue,
        );
        current = controller.snapshot.games.singleWhere(
          (game) => game.id == current.id,
        );
      }

      expect(current.status, GameStatus.completed);
      expect(current.total, 100000);
      expect(controller.notice, '点数已保存');
      expect(controller.error, isNull);
      expect(controller.busy, isFalse);
    },
  );

  test(
    'exposes demo admin action and protects ordinary cancellation',
    () async {
      final game = controller.snapshot.activeGame('room-9162')!;
      expect(await controller.selectMember('zoey'), isTrue);
      expect(await controller.cancelGame(game, 'ordinary member'), isFalse);
      expect(controller.error, contains('创建者或管理员'));

      expect(await controller.selectMember('andy'), isTrue);
      final refreshed = controller.snapshot.activeGame('room-9162')!;
      expect(await controller.cancelGame(refreshed, 'controller test'), isTrue);
      expect(controller.snapshot.activeGame('room-9162'), isNull);

      expect(await controller.signInAdmin('demo', 'demo'), isTrue);
      expect(controller.isAdmin, isTrue);
      expect(controller.member, isNull);
      expect(
        await controller.renameRoom('room-7699', '  Admin Room  '),
        isTrue,
      );
      expect(controller.snapshot.roomName('room-7699'), 'Admin Room');
      expect(await controller.signOut(), isTrue);
      expect(controller.isAdmin, isFalse);
    },
  );

  test(
    'retries a new start after an accepted start response is lost',
    () async {
      final repository = LostStartResponseRepository();
      final retryController = ClubController(repository);
      addTearDown(retryController.dispose);
      await retryController.initialize();
      expect(await retryController.selectMember('andy'), isTrue);

      final seeded = retryController.snapshot.activeGame('room-9162')!;
      expect(
        await retryController.cancelGame(
          seeded,
          'reset for lost response test',
        ),
        isTrue,
      );

      // The repository commits the game and then reports a lost response.
      expect(await retryController.startGame('room-9162'), isFalse);
      expect(retryController.error, isNotNull);
      final observed = retryController.snapshot.activeGame('room-9162');
      expect(observed, isNotNull);
      expect(observed!.id, isNot(seeded.id));

      expect(
        await retryController.cancelGame(observed, 'finish lost response test'),
        isTrue,
      );
      expect(await retryController.startGame('room-9162'), isTrue);
      final fresh = retryController.snapshot.activeGame('room-9162');
      expect(fresh, isNotNull);
      expect(fresh!.id, isNot(observed.id));
    },
  );

  test(
    'retries an accepted correction with the same request and marks stale conflicts',
    () async {
      final repository = LostCorrectionResponseRepository();
      final retryController = ClubController(repository);
      addTearDown(retryController.dispose);
      await retryController.initialize();
      expect(await retryController.selectMember('andy'), isTrue);

      final original = retryController.snapshot.games.singleWhere(
        (game) => game.id == 'demo-history',
      );
      final corrected = <String, int>{
        'andy': 30000,
        'zoey': 30000,
        'jin': 20000,
        'xiong': 20000,
      };

      // The first call commits the audit and then loses its response.
      expect(await retryController.correctScores(original, corrected), isFalse);
      expect(retryController.lastActionConflict, isFalse);
      expect(retryController.snapshot.audits, hasLength(1));

      // Retry the same immutable request; the repository's idempotency ledger
      // must return the already-accepted result without a second audit.
      expect(await retryController.correctScores(original, corrected), isTrue);
      expect(retryController.snapshot.audits, hasLength(1));
      expect(retryController.lastActionConflict, isFalse);

      // The original version is now stale, so a new request is a definite
      // conflict and must be surfaced as such.
      expect(
        await retryController.correctScores(original, {
          'andy': 31000,
          'zoey': 29000,
          'jin': 20000,
          'xiong': 20000,
        }),
        isFalse,
      );
      expect(retryController.lastActionConflict, isTrue);
      expect(retryController.snapshot.audits, hasLength(1));
    },
  );

  test(
    'foreground presence renews during mutations and pauses in background',
    () {
      fakeAsync((async) {
        final repository = PresenceTestRepository();
        final presenceController = ClubController(repository);
        var initialized = false;
        presenceController.initialize().then((_) => initialized = true);
        async.flushMicrotasks();
        expect(initialized, isTrue);
        expect(repository.heartbeatCount, 1);

        repository.mutationGate = Completer<void>();
        var mutationFinished = false;
        presenceController.createMember('Waiting').then((_) {
          mutationFinished = true;
        });
        expect(presenceController.busy, isTrue);

        async.elapse(const Duration(seconds: 15));
        async.flushMicrotasks();
        expect(repository.heartbeatCount, 2);
        expect(mutationFinished, isFalse);

        presenceController.setForeground(false);
        async.elapse(const Duration(seconds: 30));
        async.flushMicrotasks();
        expect(repository.heartbeatCount, 2);

        presenceController.setForeground(true);
        async.flushMicrotasks();
        expect(repository.heartbeatCount, 3);
        presenceController.dispose();
        repository.mutationGate!.complete();
        async.flushMicrotasks();
      });
    },
  );

  test(
    'sign-out releases before switching identity and reloads current seats',
    () async {
      final repository = PresenceTestRepository();
      final signOutController = ClubController(repository);
      addTearDown(signOutController.dispose);
      await signOutController.initialize();
      expect(await signOutController.selectMember('amy'), isTrue);
      expect(await signOutController.sit('room-7699', Wind.east), isTrue);

      final activeRoomSeats = Map<Wind, String>.of(
        signOutController.snapshot.rooms
            .singleWhere((room) => room.id == 'room-9162')
            .seats,
      );
      final priorLoadCount = repository.loadCount;

      expect(await signOutController.signOut(), isTrue);
      final releaseIndex = repository.operations.lastIndexOf('release');
      expect(repository.operations.skip(releaseIndex).take(3), [
        'release',
        'signout',
        'load',
      ]);
      expect(repository.loadCount, greaterThan(priorLoadCount));
      expect(signOutController.snapshot.memberId, isNull);
      expect(
        signOutController.snapshot.rooms
            .singleWhere((room) => room.id == 'room-7699')
            .seats
            .values,
        isNot(contains('amy')),
      );
      expect(
        signOutController.snapshot.rooms
            .singleWhere((room) => room.id == 'room-9162')
            .seats,
        activeRoomSeats,
      );
    },
  );

  test(
    'failed release restores heartbeat so sign-out can be retried',
    () async {
      final repository = PresenceTestRepository()..failRelease = true;
      final signOutController = ClubController(repository);
      addTearDown(signOutController.dispose);
      await signOutController.initialize();
      final initialHeartbeats = repository.heartbeatCount;

      expect(await signOutController.signOut(), isFalse);
      expect(repository.operations, contains('release'));
      expect(repository.operations, isNot(contains('signout')));
      expect(signOutController.error, isNotNull);
      expect(repository.heartbeatCount, greaterThan(initialHeartbeats));
    },
  );

  test(
    'close while busy calls the close hook once and tolerates late completion',
    () async {
      final repository = PresenceTestRepository();
      final closingController = ClubController(repository);
      await closingController.initialize();
      repository.mutationGate = Completer<void>();
      final mutation = closingController.createMember('Closing');
      expect(closingController.busy, isTrue);

      closingController.onAppClosing();
      closingController.dispose();
      expect(
        repository.operations.where((entry) => entry == 'close'),
        hasLength(1),
      );

      repository.mutationGate!.complete();
      expect(await mutation, isTrue);
    },
  );
}
