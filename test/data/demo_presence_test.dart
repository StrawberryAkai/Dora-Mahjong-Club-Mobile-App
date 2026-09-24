import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:dora_mahjong/data/demo_club_repository.dart';
import 'package:dora_mahjong/domain/models.dart';

ClubRoom room(ClubSnapshot snapshot, String id) =>
    snapshot.rooms.singleWhere((value) => value.id == id);

ClubGame game(ClubSnapshot snapshot, String id) =>
    snapshot.games.singleWhere((value) => value.id == id);

Future<ClubGame> saveScores(
  DemoClubRepository repository,
  ClubGame current,
  Map<String, int> scores,
) async {
  for (final entry in scores.entries) {
    await repository.saveScore(
      current.id,
      entry.key,
      entry.value,
      current.version,
      'presence-${entry.key}-${current.version}',
    );
    current = game(await repository.load(), current.id);
  }
  return current;
}

void main() {
  test('signing out immediately clears only the selected idle seat', () async {
    Map<String, dynamic>? persisted;
    final repository = DemoClubRepository(
      persist: (payload) async => persisted = Map<String, dynamic>.from(
        jsonDecode(jsonEncode(payload)) as Map,
      ),
    );

    await repository.selectMember('amy');
    await repository.sit('room-7699', Wind.east);
    await repository.signOut();

    final snapshot = await repository.load();
    expect(snapshot.memberId, isNull);
    expect(room(snapshot, 'room-7699').seats, isEmpty);
    expect(room(snapshot, 'room-9162').seats, {
      Wind.east: 'andy',
      Wind.south: 'zoey',
      Wind.west: 'jin',
      Wind.north: 'xiong',
    });
    expect(persisted?['member_id'], isNull);
    expect(persisted?['pending_seat_departures'], isEmpty);
  });

  test(
    'closing the app clears an idle seat without clearing identity',
    () async {
      final repository = DemoClubRepository();
      await repository.selectMember('amy');
      await repository.sit('room-7699', Wind.east);

      await repository.releasePresence();

      final snapshot = await repository.load();
      expect(snapshot.memberId, 'amy');
      expect(room(snapshot, 'room-7699').seats, isEmpty);
    },
  );

  test(
    'release during a game retains the seat and clears it on completion',
    () async {
      final repository = DemoClubRepository();
      await repository.selectMember('andy');
      await repository.releasePresence();

      var snapshot = await repository.load();
      expect(room(snapshot, 'room-9162').seats[Wind.east], 'andy');
      final original = game(snapshot, 'demo-active');
      final completed = await saveScores(repository, original, {
        'andy': 40000,
        'zoey': 30000,
        'jin': 20000,
        'xiong': 10000,
      });

      snapshot = await repository.load();
      expect(completed.status, GameStatus.completed);
      expect(completed.players.map((player) => player.memberId), [
        'andy',
        'zoey',
        'jin',
        'xiong',
      ]);
      expect(room(snapshot, 'room-9162').seats, {
        Wind.south: 'zoey',
        Wind.west: 'jin',
        Wind.north: 'xiong',
      });
    },
  );

  test(
    'release during a game clears the seat when the game is cancelled',
    () async {
      final repository = DemoClubRepository();
      await repository.selectMember('andy');
      await repository.releasePresence();
      final active = game(await repository.load(), 'demo-active');

      await repository.cancelGame(
        active.id,
        'cancel after departure',
        active.version,
        'presence-cancel-active',
      );

      final snapshot = await repository.load();
      expect(game(snapshot, active.id).status, GameStatus.cancelled);
      expect(room(snapshot, 'room-9162').seats, {
        Wind.south: 'zoey',
        Wind.west: 'jin',
        Wind.north: 'xiong',
      });
    },
  );

  test(
    'sign-out persists an active departure across reload until game end',
    () async {
      Map<String, dynamic>? persisted;
      final repository = DemoClubRepository(
        persist: (payload) async => persisted = Map<String, dynamic>.from(
          jsonDecode(jsonEncode(payload)) as Map,
        ),
      );
      await repository.selectMember('andy');
      await repository.signOut();

      expect(persisted?['member_id'], isNull);
      expect(persisted?['pending_seat_departures'], ['andy']);
      expect(
        room(ClubSnapshot.fromJson(persisted!), 'room-9162').seats[Wind.east],
        'andy',
      );
      final reloaded = DemoClubRepository(saved: persisted);
      var snapshot = await reloaded.load();
      expect(snapshot.memberId, isNull);
      expect(room(snapshot, 'room-9162').seats[Wind.east], 'andy');

      await reloaded.signInAdmin('demo', 'demo');
      final active = game(await reloaded.load(), 'demo-active');
      await reloaded.cancelGame(
        active.id,
        'finish pending departure',
        active.version,
        'presence-reload-cancel',
      );
      snapshot = await reloaded.load();
      expect(room(snapshot, 'room-9162').seats.containsValue('andy'), isFalse);
      expect(room(snapshot, 'room-9162').seats.values, [
        'zoey',
        'jin',
        'xiong',
      ]);
    },
  );

  test('startup clears only the previously selected unlocked seat', () async {
    final initial = DemoClubRepository();
    await initial.selectMember('amy');
    await initial.sit('room-7699', Wind.east);
    final saved = (await initial.load()).toJson();
    Map<String, dynamic>? persisted;

    final restarted = DemoClubRepository(
      saved: saved,
      persist: (payload) async => persisted = Map<String, dynamic>.from(
        jsonDecode(jsonEncode(payload)) as Map,
      ),
    );
    final snapshot = await restarted.load();

    expect(snapshot.memberId, 'amy');
    expect(room(snapshot, 'room-7699').seats, isEmpty);
    expect(room(snapshot, 'room-9162').seats.values, [
      'andy',
      'zoey',
      'jin',
      'xiong',
    ]);
    expect(persisted?['pending_seat_departures'], isEmpty);
  });

  test(
    'a failed game-ending write keeps its pending departure for retry',
    () async {
      var failPersistence = false;
      Map<String, dynamic>? persisted;
      final repository = DemoClubRepository(
        persist: (payload) async {
          if (failPersistence) throw StateError('local persistence failed');
          persisted = Map<String, dynamic>.from(
            jsonDecode(jsonEncode(payload)) as Map,
          );
        },
      );
      await repository.selectMember('andy');
      await repository.releasePresence();
      final active = game(await repository.load(), 'demo-active');
      expect(persisted?['pending_seat_departures'], ['andy']);

      failPersistence = true;
      await expectLater(
        repository.cancelGame(
          active.id,
          'retry pending departure',
          active.version,
          'presence-failing-cancel',
        ),
        throwsA(isA<StateError>()),
      );
      var snapshot = await repository.load();
      expect(game(snapshot, active.id).status, GameStatus.active);
      expect(room(snapshot, 'room-9162').seats[Wind.east], 'andy');
      expect(persisted?['pending_seat_departures'], ['andy']);

      failPersistence = false;
      await repository.cancelGame(
        active.id,
        'retry pending departure',
        active.version,
        'presence-successful-retry',
      );
      snapshot = await repository.load();
      expect(room(snapshot, 'room-9162').seats.containsValue('andy'), isFalse);
      expect(persisted?['pending_seat_departures'], isEmpty);
    },
  );

  test('a valid new sit clears its restored pending departure', () async {
    final initial = DemoClubRepository();
    await initial.selectMember('xiaoming');
    await initial.sit('room-7699', Wind.east);
    await initial.selectMember('amy');
    final saved = (await initial.load()).toJson()
      ..['pending_seat_departures'] = ['amy'];
    Map<String, dynamic>? persisted;
    final repository = DemoClubRepository(
      saved: saved,
      persist: (payload) async => persisted = Map<String, dynamic>.from(
        jsonDecode(jsonEncode(payload)) as Map,
      ),
    );

    await expectLater(
      repository.sit('room-7699', Wind.east),
      throwsA(isA<ClubException>()),
    );
    expect(persisted, isNull);
    await repository.sit('room-7699', Wind.south);

    final snapshot = await repository.load();
    expect(room(snapshot, 'room-7699').seats, {
      Wind.east: 'xiaoming',
      Wind.south: 'amy',
    });
    expect(persisted?['pending_seat_departures'], isEmpty);
  });

  test(
    'heartbeat clears persisted departures after a game is unlocked',
    () async {
      final initial = DemoClubRepository();
      await initial.signInAdmin('demo', 'demo');
      final active = game(await initial.load(), 'demo-active');
      await initial.cancelGame(
        active.id,
        'prepare a finished saved game',
        active.version,
        'heartbeat-prepare-game',
      );
      final saved = (await initial.load()).toJson()
        ..['pending_seat_departures'] = ['andy'];
      var persistCount = 0;
      Map<String, dynamic>? persisted;
      final restarted = DemoClubRepository(
        saved: saved,
        persist: (payload) async {
          persistCount++;
          persisted = Map<String, dynamic>.from(
            jsonDecode(jsonEncode(payload)) as Map,
          );
        },
      );

      await restarted.heartbeatPresence();

      final snapshot = await restarted.load();
      expect(room(snapshot, 'room-9162').seats.containsValue('andy'), isFalse);
      expect(persisted?['pending_seat_departures'], isEmpty);
      expect(persistCount, 1);

      await restarted.heartbeatPresence();
      expect(persistCount, 1);
    },
  );

  test('admin sign-out leaves member seats untouched', () async {
    final repository = DemoClubRepository();
    final before = await repository.load();
    await repository.signInAdmin('demo', 'demo');
    await repository.signOut();

    final after = await repository.load();
    expect(after.memberId, isNull);
    expect(room(after, 'room-9162').seats, room(before, 'room-9162').seats);
  });
}
