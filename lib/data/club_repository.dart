import 'dart:async';

import '../domain/models.dart';

/// Unified entry point for the data layer: the cloud implementation obtains a
/// complete snapshot and submits writes through RPCs, while the local implementation
/// uses the same models to simulate these constraints. Writes with `requestId` must
/// support safe retries; updates with `expectedVersion` use optimistic concurrency
/// checks, so callers should refresh the snapshot after a conflict.
abstract class ClubRepository {
  bool get isDemo;
  Future<ClubSnapshot> load();
  Future<void> createMember(String name);
  Future<void> selectMember(String memberId);
  Future<void> signInAdmin(String username, String password);
  Future<void> signOut();
  Future<void> sit(String roomId, Wind wind);
  Future<void> leave(String roomId, {String? memberId});
  Future<void> startGame(String roomId, String requestId, {String? eventId});
  Future<void> saveEvent(EventDraft draft, String requestId);
  Future<void> saveScore(
    String gameId,
    String memberId,
    int score,
    int expectedVersion,
    String requestId,
  );
  Future<void> correctScores(
    String gameId,
    Map<String, int> scores,
    int expectedVersion,
    String requestId,
  );
  Future<void> cancelGame(
    String gameId,
    String reason,
    int expectedVersion,
    String requestId,
  );
  Future<void> renameRoom(String roomId, String name);

  /// Renews the current client's seats and cleans up expired seats that are not
  /// locked by an in-progress game. The cloud implementation relies on short
  /// leases and RPC cleanup; the local demo only refreshes deferred departures.
  Future<void> heartbeatPresence() async {}

  /// Releases seats immediately; if a room has an in-progress game, the departure
  /// is deferred until the game ends.
  Future<void> releasePresence() async {}

  /// Attempts to release seats on a best-effort basis: forced process termination,
  /// browser closure, or a network interruption may skip the callback. The cloud
  /// implementation ultimately relies on lease expiry cleanup; in-progress games
  /// continue to lock seats until they finish.
  void onAppClosing() {
    unawaited(releasePresence().catchError((Object _) {}));
  }

  void dispose() {}
}
