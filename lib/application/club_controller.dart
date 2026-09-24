import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../data/club_repository.dart';
import '../domain/models.dart';

/// Coordinates UI submissions, snapshot refreshes, retry IDs, and heartbeats.
/// busy only guards this client; repositories/server rules must still enforce
/// permissions and handle conflicts between devices.
class ClubController extends ChangeNotifier {
  ClubController(this.repository);
  final ClubRepository repository;
  ClubSnapshot snapshot = const ClubSnapshot();
  bool loading = true;
  bool busy = false;
  String? error;
  String? notice;
  bool lastActionConflict = false;
  bool _disposed = false;
  bool _refreshing = false;
  bool _foreground = false;
  bool _presenceEnabled = true;
  bool _heartbeatInFlight = false;
  bool _appClosing = false;
  int _revision = 0;
  // Snapshot polling and seat lease renewal serve separate purposes.
  Timer? _poll;
  Timer? _heartbeat;
  // Keys include operation content and relevant versions. Identical retries
  // reuse a UUID; changed content starts a new operation. This in-memory map
  // lasts only as long as the controller, not across app restarts.
  final Map<String, String> _requests = {};
  static const _uuid = Uuid();
  bool get isDemo => repository.isDemo;
  Member? get member => snapshot.currentMember;
  bool get isAdmin => snapshot.isAdmin;

  Future<void> initialize() async {
    await refresh();
    setForeground(true);
  }

  void setForeground(bool active) {
    if (_disposed) return;
    _foreground = active;
    if (active) _appClosing = false;
    _poll?.cancel();
    _poll = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    if (active && !isDemo && !_disposed) {
      _poll = Timer.periodic(const Duration(seconds: 5), (_) {
        if (!busy) unawaited(refresh(quiet: true));
      });
      _startHeartbeat();
    }
  }

  void _startHeartbeat() {
    if (_disposed || !_foreground || !_presenceEnabled || isDemo) return;
    _heartbeat?.cancel();
    unawaited(_sendHeartbeat());
    _heartbeat = Timer.periodic(const Duration(seconds: 15), (_) {
      unawaited(_sendHeartbeat());
    });
  }

  Future<void> _sendHeartbeat() async {
    if (_disposed ||
        !_foreground ||
        !_presenceEnabled ||
        isDemo ||
        _heartbeatInFlight) {
      return;
    }
    _heartbeatInFlight = true;
    try {
      await repository.heartbeatPresence();
    } on Object {
      // The next foreground heartbeat retries transient network failures.
    } finally {
      _heartbeatInFlight = false;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void clearFeedback() {
    error = null;
    notice = null;
    _notify();
  }

  Future<void> refresh({bool quiet = false}) async {
    if (_refreshing || busy || _disposed) return;
    _refreshing = true;
    final revision = _revision;
    // A response started before a write must not overwrite the newer state.
    if (!quiet) {
      loading = true;
      _notify();
    }
    try {
      final next = await repository.load();
      if (revision == _revision && !_disposed) {
        snapshot = next;
        if (!quiet) error = null;
      }
    } catch (e) {
      if (revision == _revision && !_disposed) error = _message(e);
    } finally {
      _refreshing = false;
      if (!_disposed) loading = false;
      _notify();
    }
  }

  String _message(Object e) =>
      e is ClubException ? e.message : '暂时无法保存或获取数据，请检查网络后重试';

  /// Reloads authoritative state after writing. Distinguishes a failed write
  /// from a successful write followed by a failed refresh to guide retries.
  Future<bool> _run(Future<void> Function() action, String success) async {
    if (busy || _disposed) return false;
    busy = true;
    lastActionConflict = false;
    error = null;
    notice = null;
    _revision++;
    _notify();
    var saved = false;
    try {
      await action();
      saved = true;
      if (_disposed) return true;
      final next = await repository.load();
      if (_disposed) return true;
      snapshot = next;
      notice = success;
      return true;
    } catch (e) {
      if (_disposed) return false;
      lastActionConflict = !saved && e is ClubException && e.isConflict;
      error = saved ? '操作已保存，但页面刷新失败。请刷新查看最新状态' : _message(e);
      // Reload conflicts without discarding input held by the editor.
      try {
        final latest = await repository.load();
        if (!_disposed) snapshot = latest;
      } catch (_) {
        /* Original failure stays visible. */
      }
      return false;
    } finally {
      busy = false;
      _notify();
    }
  }

  /// Retains the request ID on failure so a lost response can be retried safely.
  /// Normal completion clears it after both the write and refresh succeed.
  Future<bool> _idempotent(
    String key,
    Future<void> Function(String) action,
    String message,
  ) async {
    final id = _requests.putIfAbsent(key, () => _uuid.v4());
    final result = await _run(() => action(id), message);
    if (result) _requests.remove(key);
    return result;
  }

  Future<bool> createMember(String name) =>
      _run(() => repository.createMember(name), '成员已创建');
  Future<bool> selectMember(String id) async {
    final success = await _run(() => repository.selectMember(id), '身份已切换');
    if (success) _enablePresence();
    return success;
  }

  Future<bool> signInAdmin(String username, String password) async {
    final success = await _run(
      () => repository.signInAdmin(username, password),
      '已进入管理',
    );
    if (success) _enablePresence();
    return success;
  }

  Future<bool> signOut() async {
    if (busy || _disposed) return false;
    _presenceEnabled = false;
    _heartbeat?.cancel();
    _heartbeat = null;
    try {
      // Supabase releases while the old access token is still present. The
      // following reload may then create an anonymous browsing session, which
      // keeps the shared room view current after sign-out.
      return await _run(repository.signOut, '已退出当前身份');
    } finally {
      if (!_disposed) {
        // A failed release leaves its retry token intact; a successful
        // sign-out reload may have opened a fresh anonymous session.
        _presenceEnabled = true;
        _startHeartbeat();
      }
    }
  }

  void _enablePresence() {
    _presenceEnabled = true;
    _startHeartbeat();
  }

  void onAppClosing() {
    if (_appClosing) return;
    _appClosing = true;
    _foreground = false;
    _poll?.cancel();
    _poll = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    try {
      repository.onAppClosing();
    } on Object {
      // Closing is best effort; expiry and the next sweep remain the fallback.
    }
  }

  Future<bool> sit(String roomId, Wind wind) =>
      _run(() => repository.sit(roomId, wind), '已入座');
  Future<bool> leave(String roomId, {String? memberId}) => _run(
    () => repository.leave(roomId, memberId: memberId),
    memberId != null && memberId != snapshot.memberId ? '玩家已移除' : '已离座',
  );
  Future<bool> startGame(String roomId, {String? eventId}) {
    // A lost response may leave a successful request ID in the retry map.
    // Scope it to the history observed before starting, so a later new game
    // cannot reuse a previous game's accepted request.
    final roomGameIds =
        snapshot.games
            .where((game) => game.roomId == roomId)
            .map((game) => game.id)
            .toList()
          ..sort();
    return _idempotent(
      'start:$roomId:${eventId ?? 'casual'}:${roomGameIds.join(',')}',
      (id) => repository.startGame(roomId, id, eventId: eventId),
      '对局已开始',
    );
  }

  Future<bool> saveEvent(EventDraft draft) => _idempotent(
    'event:${jsonEncode(draft.toJson())}',
    (requestId) => repository.saveEvent(draft, requestId),
    draft.id == null ? '活动已创建' : '活动已更新',
  );

  Future<bool> saveScore(ClubGame game, String memberId, int score) =>
      _idempotent(
        'score:${game.id}:$memberId:$score:${game.version}',
        (id) =>
            repository.saveScore(game.id, memberId, score, game.version, id),
        '点数已保存',
      );
  Future<bool> correctScores(ClubGame game, Map<String, int> scores) {
    // Map insertion order is not a new correction; sort by memberId for a stable key.
    final entries = scores.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return _idempotent(
      'correct:${game.id}:${entries.map((e) => '${e.key}=${e.value}').join(',')}:${game.version}',
      (id) => repository.correctScores(game.id, scores, game.version, id),
      '成绩已更正，修改记录已保留',
    );
  }

  Future<bool> cancelGame(ClubGame game, String reason) => _idempotent(
    'cancel:${game.id}:$reason:${game.version}',
    (id) => repository.cancelGame(game.id, reason, game.version, id),
    '对局已取消',
  );
  Future<bool> renameRoom(String roomId, String name) =>
      _run(() => repository.renameRoom(roomId, name), '房间名称已更新');
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _poll?.cancel();
    _poll = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    onAppClosing();
    repository.dispose();
    super.dispose();
  }
}
