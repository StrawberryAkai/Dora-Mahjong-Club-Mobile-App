import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../domain/models.dart';
import '../platform/app_exit.dart';
import 'club_repository.dart';

/// Supabase implementation: `load` first cleans up expired seats, then retrieves
/// a complete snapshot through `club_snapshot`. Writes only call the RPCs provided
/// by the migrations; they do not write to public tables directly or let the client
/// forge the actor, member permissions, or administrator flag.
class SupabaseClubRepository extends ClubRepository {
  SupabaseClubRepository(
    this.client, {
    this.isDemo = false,
    this.supabaseUrl,
    this.publishableKey,
  });

  final SupabaseClient client;
  final String? supabaseUrl;
  final String? publishableKey;

  static const _uuid = Uuid();
  String _presenceClientId = _uuid.v4();
  bool _presenceMayBeOwned = false;
  bool _appClosing = false;
  int _presenceGeneration = 0;
  final Set<String> _pendingReleases = <String>{};
  final Map<String, Future<void>> _releaseRequests = <String, Future<void>>{};

  @override
  final bool isDemo;

  static final RegExp _adminUsername = RegExp(r'^[a-z0-9_-]{3,32}$');
  static const String _adminEmailSuffix = '@admin.dora.invalid';

  @override
  Future<ClubSnapshot> load() async {
    try {
      // Every refresh retrieves a complete snapshot from the server; sweep first
      // reclaims expired seats that are not locked by an in-progress game. Validate
      // version fields and rating member fields before deserialization.
      await _ensureUsableSession();
      await _rpc('sweep_seat_presence');
      final result = await _rpc('club_snapshot');
      if (result is! Map) {
        throw const ClubException('服务器返回的数据格式无效');
      }
      if (result['rating_schema_version'] != 1) {
        throw const ClubException('积分功能尚未初始化，请先完成服务端迁移');
      }
      if (result['event_schema_version'] != 1 || result['events'] is! List) {
        throw const ClubException('活动功能尚未初始化，请先完成服务端迁移');
      }
      final members = result['members'];
      if (members is! List ||
          members.any(
            (member) =>
                member is! Map ||
                !member.containsKey('mmr') ||
                !member.containsKey('mmr_baseline'),
          )) {
        throw const ClubException('服务器返回的数据格式无效');
      }
      try {
        return ClubSnapshot.fromJson(Map<String, dynamic>.from(result));
      } on Object {
        throw const ClubException('服务器返回的数据格式无效');
      }
    } on Object catch (error) {
      throw _asClubException(error);
    }
  }

  @override
  Future<void> createMember(String name) =>
      _mutate('create_member', {'p_name': name});

  @override
  Future<void> selectMember(String memberId) => _selectMember(memberId);

  Future<void> _selectMember(String memberId) async {
    try {
      // `select_member` changes the member actor recorded on the server; release the
      // old member's leases before switching so one anonymous session does not leave
      // two identities that can both be renewed.
      await releasePresence();
      await _ensureUsableSession();
      await _rpc('select_member', {'p_member_id': memberId});
    } on Object catch (error) {
      throw _asClubException(error);
    }
  }

  @override
  Future<void> signInAdmin(String username, String password) async {
    final normalizedUsername = username.trim();
    if (!_adminUsername.hasMatch(normalizedUsername)) {
      throw const ClubException('管理员用户名须为 3–32 位小写字母、数字、下划线或短横线');
    }
    if (password.isEmpty) {
      throw const ClubException('请输入管理员密码');
    }

    try {
      // Password sign-in replaces the current Auth session, so release the old
      // identity's seats with the old token first. An administrator account must also
      // be on the server-side administrators allowlist; an email format alone is not
      // sufficient.
      await releasePresence();
      await client.auth.signInWithPassword(
        email: '$normalizedUsername$_adminEmailSuffix',
        password: password,
      );
      await _ensureUsableSession();

      // This snapshot RPC immediately validates `private.administrators`. Successful
      // Auth sign-in alone does not grant administrator access; if validation fails,
      // the cleanup below signs out this unusable session.
      await _rpc('club_snapshot');
    } on Object catch (error) {
      try {
        final user = client.auth.currentUser;
        if (_looksLikeAdminAccount(user)) {
          await client.auth.signOut();
        }
      } on Object {
        // Preserve the original sign-in/provisioning error.
      }
      throw _asClubException(error);
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await releasePresence();
      if (client.auth.currentSession == null) return;
      await client.auth.signOut();
    } on Object catch (error) {
      throw _asClubException(error);
    }
    // Keep the client signed out after sign-out; the next load() creates an anonymous
    // member session only when needed, avoiding a silent replacement with another
    // member identity during sign-out.
  }

  @override
  Future<void> sit(String roomId, Wind wind) async {
    final clientId = _presenceClientId;
    final generation = _presenceGeneration;
    var requestStarted = false;
    try {
      await _ensureUsableSession();
      if (_appClosing || generation != _presenceGeneration) {
        throw const ClubException('座位操作已取消，请重试');
      }
      // Keep the client UUID even if the request fails: the server may have seated
      // the client before the response was lost, so later heartbeats or release must
      // continue using the same owner to converge safely.
      _presenceMayBeOwned = true;
      requestStarted = true;
      await _rpc('sit_down_owned', {
        'p_room_id': roomId,
        'p_wind': wind.name,
        'p_client_id': clientId,
      });
    } on Object catch (error) {
      throw _asClubException(error);
    } finally {
      // The closing callback may reach the server before the in-flight seating
      // request; release once more after the request finishes, using the same UUID
      // to resolve this race.
      if (requestStarted &&
          (_appClosing ||
              generation != _presenceGeneration ||
              clientId != _presenceClientId)) {
        _pendingReleases.add(clientId);
        try {
          await _releaseClient(clientId);
        } on Object {
          // Keep the token after a failed release and retry it on the next heartbeat
          // or explicit sign-out.
        }
      }
    }
  }

  @override
  Future<void> leave(String roomId, {String? memberId}) =>
      _mutate('leave_seat', {'p_room_id': roomId, 'p_member_id': memberId});

  @override
  // Game and event writes pass requestId to the server for idempotent de-duplication;
  // versioned updates also pass expectedVersion, and stale versions return a conflict
  // instead of silently overwriting newer data.
  Future<void> startGame(String roomId, String requestId, {String? eventId}) =>
      _mutate('start_game', {
        'p_room_id': roomId,
        'p_request_id': requestId,
        'p_event_id': eventId,
      });

  @override
  Future<void> saveEvent(EventDraft draft, String requestId) =>
      _mutate('save_event', {
        'p_event_id': draft.id,
        'p_name': draft.name.trim(),
        'p_description': draft.description.trim(),
        'p_starts_at': draft.startsAt.toUtc().toIso8601String(),
        'p_ends_at': draft.endsAt.toUtc().toIso8601String(),
        'p_room_ids': [...draft.roomIds]..sort(),
        'p_expected_version': draft.expectedVersion,
        'p_request_id': requestId,
      });

  @override
  Future<void> saveScore(
    String gameId,
    String memberId,
    int score,
    int expectedVersion,
    String requestId,
  ) => _mutate('save_score', {
    'p_game_id': gameId,
    'p_member_id': memberId,
    'p_score': score,
    'p_expected_version': expectedVersion,
    'p_request_id': requestId,
  });

  @override
  Future<void> correctScores(
    String gameId,
    Map<String, int> scores,
    int expectedVersion,
    String requestId,
  ) => _mutate('correct_scores', {
    'p_game_id': gameId,
    'p_scores': scores,
    'p_expected_version': expectedVersion,
    'p_request_id': requestId,
  });

  @override
  Future<void> cancelGame(
    String gameId,
    String reason,
    int expectedVersion,
    String requestId,
  ) => _mutate('cancel_game', {
    'p_game_id': gameId,
    'p_reason': reason,
    'p_expected_version': expectedVersion,
    'p_request_id': requestId,
  });

  @override
  Future<void> renameRoom(String roomId, String name) =>
      _mutate('rename_room', {'p_room_id': roomId, 'p_name': name});

  @override
  Future<void> heartbeatPresence() async {
    // A browser page may be restored from the back/forward cache; a foreground
    // heartbeat allows normal renewal again.
    _appClosing = false;
    // Heartbeats renew only the short lease for the current anonymous member or
    // administrator session; they do not create a new anonymous session after sign-out.
    // Failed releases are retried without blocking renewal of the new lease.
    if (client.auth.currentSession == null) return;
    try {
      try {
        await _retryPendingReleases();
      } on Object {
        // Failure to release an old lease must not prevent renewal of the current lease.
      }
      await _rpc('touch_seat_presence', {'p_client_id': _presenceClientId});
    } on Object catch (error) {
      throw _asClubException(error);
    }
  }

  @override
  Future<void> releasePresence() async {
    _presenceGeneration++;
    if (_presenceMayBeOwned) {
      // Rotate the UUID before the network request; a delayed closing request can then
      // release only the old UUID and cannot clear seats later acquired by the new
      // identity.
      _pendingReleases.add(_presenceClientId);
      _presenceClientId = _uuid.v4();
      _presenceMayBeOwned = false;
    }
    await _retryPendingReleases();
  }

  Future<void> _retryPendingReleases() async {
    final clientIds = _pendingReleases.toList(growable: false);
    Object? firstError;
    StackTrace? firstStack;
    for (final clientId in clientIds) {
      try {
        await _releaseClient(clientId);
      } on Object catch (error, stack) {
        firstError ??= error;
        firstStack ??= stack;
      }
    }
    if (firstError != null) Error.throwWithStackTrace(firstError, firstStack!);
  }

  Future<void> _releaseClient(String clientId) {
    final inFlight = _releaseRequests[clientId];
    if (inFlight != null) return inFlight;
    _pendingReleases.add(clientId);
    late final Future<void> request;
    request = _rpc('release_seat_presence', {'p_client_id': clientId})
        .then<void>(
          (_) => _pendingReleases.remove(clientId),
          onError: (Object error, StackTrace stack) {
            _pendingReleases.add(clientId);
            Error.throwWithStackTrace(error, stack);
          },
        );
    _releaseRequests[clientId] = request;
    return request.whenComplete(() {
      if (identical(_releaseRequests[clientId], request)) {
        _releaseRequests.remove(clientId);
      }
    });
  }

  @override
  void onAppClosing() {
    if (_appClosing) return;
    _appClosing = true;
    _presenceGeneration++;
    final releaseId = _presenceMayBeOwned ? _presenceClientId : null;
    if (releaseId != null) {
      _pendingReleases.add(releaseId);
      _presenceClientId = _uuid.v4();
      _presenceMayBeOwned = false;
    }
    if (_pendingReleases.isEmpty) return;

    // On the Web, use keepalive to make a best-effort release RPC when closing. A
    // forced process termination, a browser that does not run pagehide, or a network
    // interruption may still drop it; the server relies on lease expiry and the next
    // sweep for cleanup (in-progress games continue to lock seats).
    final exitReleaseId = releaseId ?? _pendingReleases.first;
    final session = client.auth.currentSession;
    final baseUrl = supabaseUrl?.trim();
    final key = publishableKey?.trim();
    if (kIsWeb &&
        baseUrl != null &&
        baseUrl.isNotEmpty &&
        key != null &&
        key.isNotEmpty &&
        session != null) {
      sendExitRequest(
        url:
            '${baseUrl.replaceFirst(RegExp(r'/+$'), '')}/rest/v1/rpc/release_seat_presence',
        headers: {
          'apikey': key,
          'Authorization': 'Bearer ${session.accessToken}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'p_client_id': exitReleaseId}),
      );
    }

    // keepalive covers browser teardown; when the process remains alive during app
    // exit, a normal RPC completes the release. Both paths are best effort.
    unawaited(_retryPendingReleases().catchError((Object _) {}));
  }

  @override
  void dispose() {}

  Future<void> _mutate(String functionName, Map<String, dynamic> params) async {
    // Do not merge local table data here: each write RPC is authorized on the server
    // for the current Auth identity, and the caller loads a new complete snapshot
    // after success.
    try {
      await _ensureUsableSession();
      await _rpc(functionName, params);
    } on Object catch (error) {
      throw _asClubException(error);
    }
  }

  Future<dynamic> _rpc(String functionName, [Map<String, dynamic>? params]) {
    return client.rpc(
      functionName,
      params: params ?? const <String, dynamic>{},
    );
  }

  Future<void> _ensureUsableSession() async {
    final user = client.auth.currentUser;
    final session = client.auth.currentSession;
    if (user == null || session == null) {
      try {
        await client.auth.signInAnonymously();
      } on Object catch (error) {
        if (error is AuthException) {
          throw const ClubException('无法建立成员会话，请检查网络或开启匿名登录');
        }
        rethrow;
      }
      return;
    }
    // Regular members use an anonymous Auth session, and select_member then binds the
    // server-side member actor. Administrators use a password Auth session, which
    // club_snapshot validates against administrators. Only these two session types
    // may call RPCs; the client cannot declare its own permissions.
    if (user.isAnonymous || _looksLikeAdminAccount(user)) {
      return;
    }
    throw const ClubException('当前登录账号不受支持，请退出后使用管理员或成员身份');
  }

  bool _looksLikeAdminAccount(User? user) {
    final email = user?.email?.toLowerCase();
    if (email == null || !email.endsWith(_adminEmailSuffix)) {
      return false;
    }
    final username = email.substring(
      0,
      email.length - _adminEmailSuffix.length,
    );
    return _adminUsername.hasMatch(username);
  }

  ClubException _asClubException(Object error) {
    if (error is ClubException) {
      return error;
    }
    if (error is PostgrestException) {
      final message = error.message.trim();
      if (error.code == '40001') {
        return ClubException(
          message == '活动已被其他人更新，请刷新后重试' ? message : '对局已被其他人更新，请刷新后重试',
          isConflict: true,
        );
      }
      // P0001 is used by the migration for deliberate, user-facing domain
      // errors.  Preserve those Chinese messages while hiding raw SQL,
      // PostgREST, and network details from the app UI.
      if (error.code == 'P0001' || _containsChinese(message)) {
        return ClubException(message.isEmpty ? '操作失败，请稍后重试' : message);
      }
      return const ClubException('网络请求失败，请稍后重试');
    }
    if (error is AuthException) {
      final message = error.message.toLowerCase();
      if (message.contains('network') ||
          message.contains('connection') ||
          message.contains('timeout')) {
        return const ClubException('网络连接失败，请重试');
      }
      if (message.contains('invalid') ||
          message.contains('credential') ||
          message.contains('password') ||
          message.contains('email')) {
        return const ClubException('管理员用户名或密码不正确');
      }
      return const ClubException('管理员登录失败，请检查账号和密码');
    }
    return const ClubException('操作失败，请稍后重试');
  }

  bool _containsChinese(String value) {
    return RegExp(
      r'[\u3400-\u4DBF\u4E00-\u9FFF\u{20000}-\u{2FA1F}]',
      unicode: true,
    ).hasMatch(value);
  }
}
