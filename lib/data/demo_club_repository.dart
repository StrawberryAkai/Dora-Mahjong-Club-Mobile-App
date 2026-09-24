import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../domain/event_rules.dart';
import '../domain/models.dart';
import '../domain/rating.dart';
import '../domain/rules.dart';
import 'club_repository.dart';

/// Local demo repository with no network connection. It shares the cloud
/// implementation's behavioral constraints for snapshots, idempotent requests, and
/// version checks, making offline demos and restoration of persisted data possible.
class DemoClubRepository extends ClubRepository {
  DemoClubRepository({Map<String, dynamic>? saved, this.persist})
    : _state = saved == null ? _seed() : _loadSaved(saved),
      _requests = _readRequests(saved) {
    _pendingDepartures = _readPendingDepartures(saved);
    if (!_state.isAdmin && _state.memberId != null) {
      _pendingMetadataDirty = _pendingDepartures.add(_state.memberId!);
    }
  }

  final Future<void> Function(Map<String, dynamic>)? persist;
  ClubSnapshot _state;
  final Map<String, String> _requests;
  late Set<String> _pendingDepartures;
  bool _pendingMetadataDirty = false;
  Future<void> _queue = Future.value();
  static const _uuid = Uuid();
  static const _ratingSchemaVersion = 1;
  static const _eventSchemaVersion = 1;

  @override
  bool get isDemo => true;

  @override
  Future<ClubSnapshot> load() async {
    await _flushPendingDepartures();
    await _queue;
    return ClubSnapshot.fromJson(_state.toJson());
  }

  ClubSnapshot _copy({
    List<Member>? members,
    List<ClubRoom>? rooms,
    List<ClubGame>? games,
    List<ScoreAudit>? audits,
    List<ClubEvent>? events,
    int? eventSchemaVersion,
    String? memberId,
    bool replaceIdentity = false,
    bool? isAdmin,
    String? adminName,
  }) => ClubSnapshot(
    members: members ?? _state.members,
    rooms: rooms ?? _state.rooms,
    games: games ?? _state.games,
    audits: audits ?? _state.audits,
    events: events ?? _state.events,
    eventSchemaVersion: eventSchemaVersion ?? _state.eventSchemaVersion,
    memberId: replaceIdentity ? memberId : _state.memberId,
    isAdmin: isAdmin ?? _state.isAdmin,
    adminName: replaceIdentity ? adminName : _state.adminName,
    ratingSchemaVersion: _ratingSchemaVersion,
  );

  /// All local writes are serialized through one queue and first build a complete
  /// next state. The in-memory snapshot, pending departure records, and request
  /// ledger are replaced only after persist succeeds, so a callback failure leaves
  /// the old state in memory. requestId and fingerprint together provide safe retries
  /// and content validation.
  Future<void> _write(
    ClubSnapshot Function() update, {
    String? requestId,
    String? fingerprint,
    Set<String> Function(ClubSnapshot next, Set<String> pending)?
    pendingTransform,
  }) {
    final result = _queue.then((_) async {
      if (requestId != null && _requests.containsKey(requestId)) {
        if (_requests[requestId] != fingerprint) {
          throw const ClubException('重复请求内容不一致，请刷新后重试');
        }
        return;
      }

      final proposed = update();
      final pending = Set<String>.of(_pendingDepartures);
      final transformedPending =
          pendingTransform?.call(proposed, pending) ?? pending;
      final cleanup = _cleanPendingDepartures(
        proposed,
        Set<String>.of(transformedPending),
      );
      final next = cleanup.snapshot;
      final nextPending = cleanup.pending;
      final requests = <String, String>{..._requests};
      if (requestId != null) {
        if (fingerprint == null) {
          throw const ClubException('请求缺少幂等指纹');
        }
        requests[requestId] = fingerprint;
      }
      if (persist != null) {
        final payload = next.toJson()
          ..['requests'] = requests
          ..['pending_seat_departures'] = (nextPending.toList()..sort());
        await persist!(payload);
      }
      _state = next;
      _pendingDepartures = nextPending;
      _pendingMetadataDirty = false;
      _requests
        ..clear()
        ..addAll(requests);
    });
    _queue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<void> _flushPendingDepartures() async {
    await _queue;
    if (!_pendingMetadataDirty &&
        !_hasActionablePendingDepartures(_state, _pendingDepartures)) {
      return;
    }
    await _write(() => _state);
  }

  // Demo mode has no cross-device leases; a heartbeat only attempts to persist
  // deferred departures and cannot provide the automatic expiry or cross-process
  // coordination available when a cloud session is lost.
  @override
  Future<void> heartbeatPresence() => _flushPendingDepartures();

  @override
  Future<void> releasePresence() => _write(
    () => _state,
    pendingTransform: (next, pending) {
      if (!next.isAdmin && next.memberId != null) {
        pending.add(next.memberId!);
      }
      return pending;
    },
  );

  // The demo snapshot's isAdmin/memberId fields simulate the two identities; in the
  // cloud, permissions are still determined by Auth and server-side RPCs, so local
  // branches must not be treated as a security boundary.
  String get _actor =>
      _state.isAdmin ? '管理员（演示）' : _state.currentMember?.name ?? '成员';

  String _member() =>
      _state.memberId ?? (throw const ClubException('请先选择成员身份'));

  ClubRoom _room(String id) =>
      _state.rooms.where((r) => r.id == id).firstOrNull ??
      (throw const ClubException('房间不存在'));

  ClubGame _game(String id) =>
      _state.games.where((g) => g.id == id).firstOrNull ??
      (throw const ClubException('对局不存在'));

  void _manager(ClubGame game) {
    if (!_state.isAdmin && _state.memberId != game.creatorId) {
      throw const ClubException('仅创建者或管理员可以操作');
    }
  }

  void _unlocked(String roomId) {
    if (_state.activeGame(roomId) != null) {
      throw const ClubException('请先完成或取消当前对局，再调整座位');
    }
  }

  void _version(ClubGame game, int version) {
    // expectedVersion permits updates only against the version the user saw, preventing
    // concurrent updates from being overwritten.
    if (game.version != version) {
      throw const ClubException('对局已被更新，请刷新后重试；已输入的点数会保留', isConflict: true);
    }
  }

  List<ClubRoom> _replaceRoom(ClubRoom room) =>
      _state.rooms.map((r) => r.id == room.id ? room : r).toList();

  List<ClubGame> _replaceGame(ClubGame game) =>
      _state.games.map((g) => g.id == game.id ? game : g).toList();

  @override
  Future<void> createMember(String name) => _write(() {
    final error = validateName(name);
    if (error != null) throw ClubException(error);
    if (_state.members.any(
      (m) => normalizeName(m.name) == normalizeName(name),
    )) {
      throw const ClubException('这个名字已存在，请搜索并选择');
    }
    final member = Member(
      id: _uuid.v4(),
      name: name.trim(),
      mmr: initialMmr,
      mmrBaseline: initialMmr,
    );
    return _copy(
      members: [..._state.members, member],
      replaceIdentity: true,
      memberId: member.id,
      isAdmin: false,
    );
  });

  @override
  Future<void> selectMember(String memberId) => _write(() {
    if (!_state.members.any((m) => m.id == memberId)) {
      throw const ClubException('成员不存在，请重新搜索');
    }
    return _copy(replaceIdentity: true, memberId: memberId, isAdmin: false);
  });

  @override
  Future<void> signInAdmin(String username, String password) => _write(() {
    if (username != 'demo' || password != 'demo') {
      throw const ClubException('当前为本地演示，请使用“体验管理员”入口');
    }
    return _copy(replaceIdentity: true, isAdmin: true, adminName: '演示管理员');
  });

  @override
  Future<void> signOut() {
    return _write(
      () {
        return _copy(replaceIdentity: true, isAdmin: false);
      },
      pendingTransform: (_, pending) {
        final departingMemberId = _state.isAdmin ? null : _state.memberId;
        if (departingMemberId != null) pending.add(departingMemberId);
        return pending;
      },
    );
  }

  @override
  Future<void> sit(String roomId, Wind wind) {
    String? memberId;
    return _write(() {
      memberId = _member();
      _unlocked(roomId);
      final room = _room(roomId);
      if (room.seats[wind] == memberId) return _state;
      if (room.seats.containsKey(wind)) {
        throw const ClubException('这个座位已有人入座');
      }
      final sourceRooms = _state.rooms
          .where((source) => source.seats.containsValue(memberId))
          .toList();
      for (final source in sourceRooms) {
        _unlocked(source.id);
      }

      return _copy(
        rooms: _state.rooms.map((current) {
          if (current.id != room.id && !current.seats.containsValue(memberId)) {
            return current;
          }
          final seats = Map<Wind, String>.of(current.seats)
            ..removeWhere((_, occupant) => occupant == memberId);
          if (current.id == room.id) seats[wind] = memberId!;
          return ClubRoom(id: current.id, name: current.name, seats: seats);
        }).toList(),
      );
    }, pendingTransform: (_, pending) => pending..remove(memberId));
  }

  @override
  Future<void> leave(String roomId, {String? memberId}) => _write(() {
    if (!_state.isAdmin && _state.memberId == null) _member();
    final target = memberId ?? _member();
    _unlocked(roomId);
    final room = _room(roomId);
    return _copy(
      rooms: _replaceRoom(
        ClubRoom(
          id: room.id,
          name: room.name,
          seats: Map.of(room.seats)..removeWhere((_, value) => value == target),
        ),
      ),
    );
  });

  @override
  Future<void> startGame(String roomId, String requestId, {String? eventId}) =>
      _write(
        () {
          final creator = _member();
          final room = _room(roomId);
          _unlocked(roomId);
          if (!room.seats.containsValue(creator)) {
            throw const ClubException('只有在座成员可以开始对局');
          }
          if (room.seats.length != 4 || room.seats.values.toSet().length != 4) {
            throw const ClubException('四位不同成员入座后才能开始');
          }
          final startedAt = DateTime.now().toUtc();
          if (eventId != null) {
            final event = _state.events
                .where((entry) => entry.id == eventId)
                .firstOrNull;
            if (event == null) throw const ClubException('活动不存在，请刷新后重试');
            if (!event.isActiveAt(startedAt)) {
              throw const ClubException('只能选择当前进行中的活动');
            }
            if (!event.roomIds.contains(roomId)) {
              throw const ClubException('该活动不包含当前房间');
            }
          }
          final game = ClubGame(
            id: _uuid.v4(),
            roomId: roomId,
            creatorId: creator,
            startedAt: startedAt,
            eventId: eventId,
            players: Wind.values
                .map(
                  (wind) => GamePlayer(
                    memberId: room.seats[wind]!,
                    name: _state.memberName(room.seats[wind]!),
                    wind: wind,
                  ),
                )
                .toList(),
          );
          return _copy(games: [game, ..._state.games]);
        },
        requestId: requestId,
        fingerprint: eventId == null
            ? 'start:$roomId'
            : 'start:$roomId:event:$eventId',
      );

  @override
  Future<void> saveEvent(EventDraft draft, String requestId) {
    // Copy the mutable room list before the request enters the serial queue so the
    // fingerprint matches the draft that is actually written; otherwise, callers
    // could continue modifying draft and invalidate the idempotency check.
    final captured = EventDraft(
      id: draft.id,
      expectedVersion: draft.expectedVersion,
      name: draft.name,
      description: draft.description,
      startsAt: draft.startsAt,
      endsAt: draft.endsAt,
      roomIds: List<String>.from(draft.roomIds),
    );
    return _write(
      () {
        if (!_state.isAdmin) throw const ClubException('仅管理员可以管理活动');

        final normalized = _normalizeEventDraft(captured);
        validateEventDraft(normalized, _state.rooms);

        if (normalized.id == null) {
          if (normalized.expectedVersion != null) {
            throw const ClubException('新建活动不能指定版本');
          }
          final now = DateTime.now().toUtc();
          final event = ClubEvent(
            id: _uuid.v4(),
            name: normalized.name,
            description: normalized.description,
            startsAt: normalized.startsAt.toUtc(),
            endsAt: normalized.endsAt.toUtc(),
            roomIds: normalized.roomIds,
            createdAt: now,
            version: 0,
          );
          return _copy(events: [event, ..._state.events]);
        }

        final current = _state.events
            .where((entry) => entry.id == normalized.id)
            .firstOrNull;
        if (current == null) throw const ClubException('活动不存在，请刷新后重试');
        final expectedVersion = normalized.expectedVersion;
        if (expectedVersion == null) {
          throw const ClubException('修改活动需要提供当前版本');
        }
        if (current.version != expectedVersion) {
          throw const ClubException('活动已被更新，请刷新后重试', isConflict: true);
        }
        validateEventEdit(normalized, _state.games);
        final replacement = ClubEvent(
          id: current.id,
          name: normalized.name,
          description: normalized.description,
          startsAt: normalized.startsAt.toUtc(),
          endsAt: normalized.endsAt.toUtc(),
          roomIds: normalized.roomIds,
          createdAt: current.createdAt,
          version: current.version + 1,
        );
        return _copy(
          events: _state.events
              .map((event) => event.id == replacement.id ? replacement : event)
              .toList(),
        );
      },
      requestId: requestId,
      fingerprint: _eventFingerprint(captured),
    );
  }

  @override
  Future<void> saveScore(
    String gameId,
    String memberId,
    int score,
    int expectedVersion,
    String requestId,
  ) => _write(
    () {
      final game = _game(gameId);
      if (game.status != GameStatus.active) {
        throw const ClubException('对局已结束，请刷新查看；修改成绩请使用更正功能');
      }
      _version(game, expectedVersion);
      if (!_state.isAdmin &&
          _state.memberId != game.creatorId &&
          _state.memberId != memberId) {
        throw const ClubException('只能填写自己的点数');
      }
      if (!game.involves(memberId)) throw const ClubException('该成员未参与本场对局');
      parseScore('$score');
      var players = game.players
          .map(
            (p) => p.memberId == memberId
                ? GamePlayer(
                    memberId: p.memberId,
                    name: p.name,
                    wind: p.wind,
                    score: score,
                  )
                : p,
          )
          .toList();
      final complete =
          players.every((p) => p.score != null) &&
          players.fold<int>(0, (s, p) => s + (p.score ?? 0)) == 100000;
      if (!complete) {
        return _copy(
          games: _replaceGame(
            ClubGame(
              id: game.id,
              roomId: game.roomId,
              creatorId: game.creatorId,
              players: players,
              startedAt: game.startedAt,
              status: GameStatus.active,
              version: game.version + 1,
              eventId: game.eventId,
            ),
          ),
        );
      }

      players = rankPlayers(players);
      final completedGame = ClubGame(
        id: game.id,
        roomId: game.roomId,
        creatorId: game.creatorId,
        players: players,
        startedAt: game.startedAt,
        status: GameStatus.completed,
        completedAt: DateTime.now(),
        version: game.version + 1,
        eventId: game.eventId,
      );
      final calculation = _calculateSettlement(
        completedGame,
        _memberMmr(),
        order: _nextSettlementOrder(),
        revision: 1,
        settledAt: completedGame.completedAt!,
      );
      final nextMembers = _applyResults(_state.members, calculation.results);
      return _copy(
        members: nextMembers,
        games: _replaceGame(
          ClubGame(
            id: completedGame.id,
            roomId: completedGame.roomId,
            creatorId: completedGame.creatorId,
            players: completedGame.players,
            startedAt: completedGame.startedAt,
            status: completedGame.status,
            completedAt: completedGame.completedAt,
            version: completedGame.version,
            eventId: completedGame.eventId,
            settlement: calculation.settlement,
          ),
        ),
      );
    },
    requestId: requestId,
    fingerprint: 'save:$gameId:$memberId:$score:$expectedVersion',
  );

  @override
  Future<void> correctScores(
    String gameId,
    Map<String, int> scores,
    int expectedVersion,
    String requestId,
  ) => _write(
    () {
      final game = _game(gameId);
      _manager(game);
      _version(game, expectedVersion);
      if (game.status != GameStatus.completed) {
        throw const ClubException('只有已完成对局可以更正成绩');
      }
      if (scores.length != 4 ||
          game.players.length != 4 ||
          game.players.any((p) => !scores.containsKey(p.memberId))) {
        throw const ClubException('请填写本场全部四人的点数');
      }
      for (final score in scores.values) {
        parseScore('$score');
      }
      final sum = scores.values.fold(0, (sum, value) => sum + value);
      if (sum != 100000) {
        throw ClubException('当前合计 ${formatPoints(sum)}，必须为 100,000');
      }
      if (game.players.any((p) => p.score == null)) {
        throw const ClubException('历史对局缺少原始点数，无法更正');
      }
      final players = rankPlayers(
        game.players
            .map(
              (p) => GamePlayer(
                memberId: p.memberId,
                name: p.name,
                wind: p.wind,
                score: scores[p.memberId],
              ),
            )
            .toList(),
      );
      final audit = ScoreAudit(
        id: _uuid.v4(),
        gameId: game.id,
        actor: _actor,
        at: DateTime.now(),
        before: {for (final p in game.players) p.memberId: p.score!},
        after: Map<String, int>.from(scores),
      );
      final correctedGame = ClubGame(
        id: game.id,
        roomId: game.roomId,
        creatorId: game.creatorId,
        players: players,
        startedAt: game.startedAt,
        status: GameStatus.completed,
        completedAt: game.completedAt,
        version: game.version + 1,
        eventId: game.eventId,
        settlement: game.settlement,
        settlementHistory: game.settlementHistory,
      );
      var games = _replaceGame(correctedGame);
      var members = _state.members;
      if (game.settlement != null) {
        final replay = _replayRatedHistory(games, gameId, members);
        games = replay.games;
        members = replay.members;
      }
      return _copy(
        members: members,
        games: games,
        audits: [audit, ..._state.audits],
      );
    },
    requestId: requestId,
    fingerprint: 'correct:$gameId:${_canonicalScores(scores)}:$expectedVersion',
  );

  @override
  Future<void> cancelGame(
    String gameId,
    String reason,
    int expectedVersion,
    String requestId,
  ) => _write(
    () {
      final game = _game(gameId);
      _manager(game);
      _version(game, expectedVersion);
      if (game.status != GameStatus.active) {
        throw const ClubException('只能取消未完成的对局');
      }
      if (reason.trim().isEmpty) throw const ClubException('请填写取消原因');
      if (reason.trim().length > 500) {
        throw const ClubException('取消原因最多 500 个字符');
      }
      return _copy(
        games: _replaceGame(
          ClubGame(
            id: game.id,
            roomId: game.roomId,
            creatorId: game.creatorId,
            players: game.players,
            startedAt: game.startedAt,
            status: GameStatus.cancelled,
            cancelledAt: DateTime.now(),
            cancelledBy: _actor,
            cancelReason: reason.trim(),
            version: game.version + 1,
            eventId: game.eventId,
          ),
        ),
      );
    },
    requestId: requestId,
    fingerprint: 'cancel:$gameId:$reason:$expectedVersion',
  );

  @override
  Future<void> renameRoom(String roomId, String name) => _write(() {
    if (!_state.isAdmin) throw const ClubException('仅管理员可以修改房间名称');
    if (name.trim().isEmpty || name.trim().runes.length > 30) {
      throw const ClubException('房间名称须为 1–30 个字符');
    }
    final room = _room(roomId);
    return _copy(
      rooms: _replaceRoom(
        ClubRoom(id: room.id, name: name.trim(), seats: room.seats),
      ),
    );
  });

  EventDraft _normalizeEventDraft(EventDraft draft) {
    final roomIds = draft.roomIds.map((roomId) => roomId.trim()).toList()
      ..sort();
    return EventDraft(
      id: draft.id,
      expectedVersion: draft.expectedVersion,
      name: draft.name.trim(),
      description: draft.description.trim(),
      startsAt: draft.startsAt.toUtc(),
      endsAt: draft.endsAt.toUtc(),
      roomIds: roomIds,
    );
  }

  static String _eventFingerprint(EventDraft draft) {
    final roomIds = draft.roomIds.map((roomId) => roomId.trim()).toList()
      ..sort();
    return jsonEncode({
      'id': draft.id,
      'expected_version': draft.expectedVersion,
      'name': draft.name.trim(),
      'description': draft.description.trim(),
      'starts_at': draft.startsAt.toUtc().toIso8601String(),
      'ends_at': draft.endsAt.toUtc().toIso8601String(),
      'room_ids': roomIds,
    });
  }

  Map<String, double> _memberMmr() => {
    for (final member in _state.members) member.id: member.mmr,
  };

  int _nextSettlementOrder() {
    var largest = 0;
    for (final game in _state.games) {
      final order = game.settlement?.order;
      if (order != null && order > largest) largest = order;
    }
    return largest + 1;
  }

  static _SettlementComputation _calculateSettlement(
    ClubGame game,
    Map<String, double> oldMmr, {
    required int order,
    required int revision,
    required DateTime settledAt,
    String? sourceGameId,
  }) {
    if (game.players.length != 4 ||
        game.players.any((player) => player.score == null)) {
      throw const ClubException('评分必须包含四位成员');
    }
    final results = calculateRatings(
      game.players
          .map(
            (player) => RatingInput(
              memberId: player.memberId,
              finalPoints: player.score,
              oldMmr:
                  oldMmr[player.memberId] ??
                  (throw const ClubException('缺少成员评分状态')),
            ),
          )
          .toList(),
    );
    final settlement = GameSettlement(
      ruleVersion: ratingRuleVersion,
      order: order,
      revision: revision,
      settledAt: settledAt,
      sourceGameId: sourceGameId,
      players: results
          .map(
            (result) => PlayerSettlement(
              memberId: result.memberId,
              finalPoints: game.players
                  .firstWhere((player) => player.memberId == result.memberId)
                  .score!,
              actualUma: result.actualUma,
              pt: result.pt,
              oldMmr: result.oldMmr,
              mmrDelta: result.mmrDelta,
              newMmr: result.newMmr,
            ),
          )
          .toList(),
    );
    return _SettlementComputation(settlement, results);
  }

  static List<Member> _applyResults(
    List<Member> members,
    List<RatingResult> results,
  ) {
    final byId = {for (final result in results) result.memberId: result};
    return members
        .map(
          (member) => byId[member.id] == null
              ? member
              : Member(
                  id: member.id,
                  name: member.name,
                  mmr: byId[member.id]!.newMmr,
                  mmrBaseline: member.mmrBaseline,
                ),
        )
        .toList();
  }

  _ReplayResult _replayRatedHistory(
    List<ClubGame> games,
    String correctedGameId,
    List<Member> members,
  ) {
    // After correcting a historical game, recompute from each member's trusted
    // baseline in settlement.order. The target game and affected later games retain
    // their old settlements in history and receive new revisions. Reject corrections
    // that would change records before the target, avoiding a silent rewrite of the
    // established history order.
    final rated = games.where((game) => game.settlement != null).toList()
      ..sort(
        (left, right) =>
            left.settlement!.order.compareTo(right.settlement!.order),
      );
    if (rated.every((game) => game.id != correctedGameId)) {
      throw const ClubException('更正的对局缺少评分记录');
    }
    final mmr = {
      for (final member in members)
        member.id: _finiteMmr(member.mmrBaseline, '成员评分基线无效'),
    };
    final nextGames = List<ClubGame>.from(games);
    var targetSeen = false;
    for (final game in rated) {
      final oldSettlement = game.settlement!;
      final calculation = _calculateSettlement(
        game,
        mmr,
        order: oldSettlement.order,
        revision: oldSettlement.revision + 1,
        settledAt: DateTime.now(),
        sourceGameId: correctedGameId,
      );
      final changed = !_sameSettlement(game, calculation.results);
      final target = game.id == correctedGameId;
      if (!targetSeen && !target && changed) {
        throw const ClubException('更正影响了更早的评分记录');
      }
      if (target || changed) {
        final next = ClubGame(
          id: game.id,
          roomId: game.roomId,
          creatorId: game.creatorId,
          players: game.players,
          startedAt: game.startedAt,
          status: game.status,
          completedAt: game.completedAt,
          cancelledAt: game.cancelledAt,
          cancelReason: game.cancelReason,
          cancelledBy: game.cancelledBy,
          version: target ? game.version : game.version + 1,
          eventId: game.eventId,
          settlement: calculation.settlement,
          settlementHistory: [...game.settlementHistory, oldSettlement],
        );
        final index = nextGames.indexWhere((entry) => entry.id == game.id);
        nextGames[index] = next;
      }
      for (final result in calculation.results) {
        mmr[result.memberId] = result.newMmr;
      }
      if (target) targetSeen = true;
    }
    final nextMembers = members
        .map(
          (member) => Member(
            id: member.id,
            name: member.name,
            mmr: mmr[member.id] ?? (throw const ClubException('缺少成员评分状态')),
            mmrBaseline: member.mmrBaseline,
          ),
        )
        .toList();
    return _ReplayResult(nextGames, nextMembers);
  }

  static bool _sameSettlement(ClubGame game, List<RatingResult> results) {
    final old = game.settlement!;
    if (old.ruleVersion != ratingRuleVersion || old.players.length != 4) {
      return false;
    }
    final byId = {for (final result in results) result.memberId: result};
    if (byId.length != 4) return false;
    for (final player in game.players) {
      final result = byId[player.memberId];
      final previous = old.player(player.memberId);
      if (result == null || previous == null || player.score == null) {
        return false;
      }
      if (previous.finalPoints != player.score ||
          previous.actualUma != result.actualUma ||
          previous.pt != result.pt ||
          previous.oldMmr != result.oldMmr ||
          previous.mmrDelta != result.mmrDelta ||
          previous.newMmr != result.newMmr) {
        return false;
      }
    }
    return true;
  }

  static double _finiteMmr(double value, String message) {
    if (!value.isFinite) throw ClubException(message);
    return value;
  }

  static String _canonicalScores(Map<String, int> scores) {
    final keys = scores.keys.toList()..sort();
    return jsonEncode({for (final key in keys) key: scores[key]});
  }

  static ClubSnapshot _loadSaved(Map<String, dynamic> saved) {
    // On load, validate the rating and event versions first, then verify that MMR can
    // be replayed from the settlement chain, preventing an old format or partial write
    // from entering the demo state.
    _validateRawRatingMetadata(saved);
    _validateRawEventMetadata(saved);
    try {
      final parsed = ClubSnapshot.fromJson(saved);
      final events = saved['events'] is List
          ? parsed.events
          : _legacyDemoEvents(parsed.rooms);
      final upgraded = ClubSnapshot(
        members: parsed.members
            .map(
              (member) => Member(
                id: member.id,
                name: member.name,
                mmr: member.mmr,
                mmrBaseline: member.mmrBaseline,
              ),
            )
            .toList(),
        rooms: parsed.rooms,
        games: parsed.games,
        audits: parsed.audits,
        events: events,
        eventSchemaVersion: _eventSchemaVersion,
        memberId: parsed.memberId,
        isAdmin: parsed.isAdmin,
        adminName: parsed.adminName,
        ratingSchemaVersion: _ratingSchemaVersion,
      );
      _validateSnapshot(upgraded);
      return upgraded;
    } on ClubException {
      rethrow;
    } catch (_) {
      throw const ClubException('本地演示数据中的评分元数据无效');
    }
  }

  static Map<String, String> _readRequests(Map<String, dynamic>? saved) {
    if (saved == null || saved['requests'] == null) return {};
    final raw = saved['requests'];
    if (raw is! Map) throw const ClubException('本地演示请求记录无效');
    final requests = <String, String>{};
    for (final entry in raw.entries) {
      if (entry.key is! String || entry.value is! String) {
        throw const ClubException('本地演示请求记录无效');
      }
      requests[entry.key as String] = entry.value as String;
    }
    return requests;
  }

  static Set<String> _readPendingDepartures(Map<String, dynamic>? saved) {
    if (saved == null || saved['pending_seat_departures'] == null) return {};
    final raw = saved['pending_seat_departures'];
    if (raw is! List) throw const ClubException('本地演示离座记录无效');
    final departures = <String>{};
    for (final value in raw) {
      if (value is! String || value.isEmpty || !departures.add(value)) {
        throw const ClubException('本地演示离座记录无效');
      }
    }
    return departures;
  }

  static bool _hasActionablePendingDepartures(
    ClubSnapshot snapshot,
    Set<String> pending,
  ) => pending.any(
    (memberId) => !snapshot.rooms.any(
      (room) =>
          room.seats.containsValue(memberId) &&
          snapshot.activeGame(room.id) != null,
    ),
  );

  static _DepartureCleanup _cleanPendingDepartures(
    ClubSnapshot snapshot,
    Set<String> pending,
  ) {
    // Deferred departures run only when a room has no in-progress game; locked seats
    // remain pending and are retried by the next load/heartbeat or by a write after
    // the game ends.
    if (pending.isEmpty) return _DepartureCleanup(snapshot, pending);

    var rooms = snapshot.rooms;
    var roomsChanged = false;
    for (final memberId in pending.toList()) {
      var hasLockedSeat = false;
      final nextRooms = <ClubRoom>[];
      for (final room in rooms) {
        final hasSeat = room.seats.containsValue(memberId);
        if (!hasSeat) {
          nextRooms.add(room);
          continue;
        }
        if (snapshot.activeGame(room.id) != null) {
          hasLockedSeat = true;
          nextRooms.add(room);
          continue;
        }
        final seats = Map<Wind, String>.of(room.seats)
          ..removeWhere((_, occupant) => occupant == memberId);
        nextRooms.add(ClubRoom(id: room.id, name: room.name, seats: seats));
        roomsChanged = true;
      }
      rooms = nextRooms;
      if (!hasLockedSeat) pending.remove(memberId);
    }

    if (!roomsChanged) return _DepartureCleanup(snapshot, pending);
    return _DepartureCleanup(
      ClubSnapshot(
        members: snapshot.members,
        rooms: rooms,
        games: snapshot.games,
        audits: snapshot.audits,
        events: snapshot.events,
        eventSchemaVersion: snapshot.eventSchemaVersion,
        memberId: snapshot.memberId,
        isAdmin: snapshot.isAdmin,
        adminName: snapshot.adminName,
        ratingSchemaVersion: snapshot.ratingSchemaVersion,
      ),
      pending,
    );
  }

  static void _validateRawEventMetadata(Map<String, dynamic> saved) {
    final rawSchema = saved['event_schema_version'];
    if (rawSchema != null && rawSchema is! int) {
      throw const ClubException('本地演示活动版本无效');
    }
    final schema = rawSchema as int? ?? 0;
    if (schema != 0 && schema != _eventSchemaVersion) {
      throw const ClubException('本地演示活动版本不受支持');
    }

    final rawEvents = saved['events'];
    if (rawEvents != null && rawEvents is! List) {
      throw const ClubException('本地演示活动数据无效');
    }
    final eventIds = <String>{};
    for (final value in (rawEvents as List? ?? const [])) {
      if (value is! Map) throw const ClubException('本地演示活动数据无效');
      try {
        final event = ClubEvent.fromJson(Map<String, dynamic>.from(value));
        if (!eventIds.add(event.id) ||
            event.id.isEmpty ||
            event.version < 0 ||
            !event.endsAt.isAfter(event.startsAt) ||
            event.name.trim().isEmpty ||
            event.name.trim().runes.length > 80 ||
            event.description.trim().runes.length > 2000 ||
            event.roomIds.isEmpty ||
            event.roomIds.length != event.roomIds.toSet().length) {
          throw const ClubException('本地演示活动数据无效');
        }
      } on ClubException {
        rethrow;
      } catch (_) {
        throw const ClubException('本地演示活动数据无效');
      }
    }
  }

  static List<ClubEvent> _legacyDemoEvents(List<ClubRoom> rooms) {
    if (rooms.isEmpty) return const [];
    final now = DateTime.now().toUtc();
    final roomIds = rooms.map((room) => room.id).toList()..sort();
    return [
      ClubEvent(
        id: 'legacy-demo-active-event',
        name: 'Demo 当前活动展示',
        description: '本地演示活动，仅用于展示当前活动信息。',
        startsAt: now.subtract(const Duration(hours: 1)),
        endsAt: now.add(const Duration(days: 1)),
        roomIds: roomIds,
        createdAt: now,
      ),
      ClubEvent(
        id: 'legacy-demo-upcoming-event',
        name: '演示即将开始活动',
        description: '本地演示活动，仅用于展示即将开始的活动信息。',
        startsAt: now.add(const Duration(days: 2)),
        endsAt: now.add(const Duration(days: 3)),
        roomIds: roomIds,
        createdAt: now,
      ),
    ];
  }

  static void _validateRawRatingMetadata(Map<String, dynamic> saved) {
    final rawSchema = saved['rating_schema_version'];
    if (rawSchema != null && rawSchema is! int) {
      throw const ClubException('本地演示评分版本无效');
    }
    final schema = rawSchema as int? ?? 0;
    if (schema != 0 && schema != _ratingSchemaVersion) {
      throw const ClubException('本地演示评分版本不受支持');
    }

    final rawMembers = saved['members'];
    if (rawMembers != null && rawMembers is! List) {
      throw const ClubException('本地演示成员评分数据无效');
    }
    var completeMemberRatings = 0;
    var legacyMembers = 0;
    for (final value in (rawMembers as List? ?? const [])) {
      if (value is! Map) throw const ClubException('本地演示成员数据无效');
      final member = Map<String, dynamic>.from(value);
      final hasMmr = member.containsKey('mmr');
      final hasBaseline = member.containsKey('mmr_baseline');
      if (hasMmr != hasBaseline) {
        throw const ClubException('本地演示成员评分数据不完整');
      }
      if (hasMmr) {
        completeMemberRatings++;
        _validateFiniteNumber(member['mmr'], '本地演示成员 MMR 无效');
        _validateFiniteNumber(member['mmr_baseline'], '本地演示成员评分基线无效');
      } else {
        legacyMembers++;
      }
    }
    if (completeMemberRatings > 0 && legacyMembers > 0) {
      throw const ClubException('本地演示成员评分数据不完整');
    }
    if (schema == 0 && completeMemberRatings > 0) {
      throw const ClubException('本地演示评分版本不完整');
    }
    if (schema == _ratingSchemaVersion && legacyMembers > 0) {
      throw const ClubException('本地演示成员评分数据不完整');
    }

    var hasSettlement = false;
    final rawGames = saved['games'];
    if (rawGames != null && rawGames is! List) {
      throw const ClubException('本地演示对局数据无效');
    }
    for (final value in (rawGames as List? ?? const [])) {
      if (value is! Map) throw const ClubException('本地演示对局数据无效');
      final game = Map<String, dynamic>.from(value);
      final rawSettlement = game['settlement'];
      if (rawSettlement != null) {
        hasSettlement = true;
        _validateRawSettlement(rawSettlement);
      }
      final rawHistory = game['settlement_history'];
      if (rawHistory != null && rawHistory is! List) {
        throw const ClubException('本地演示评分历史无效');
      }
      final history = rawHistory as List? ?? const [];
      if (history.isNotEmpty) {
        hasSettlement = true;
        if (rawSettlement == null) {
          throw const ClubException('本地演示评分历史缺少当前版本');
        }
        for (final entry in history) {
          _validateRawSettlement(entry);
        }
      }
    }
    if (hasSettlement && (completeMemberRatings == 0 || legacyMembers > 0)) {
      throw const ClubException('本地演示评分成员状态不完整');
    }
  }

  static void _validateRawSettlement(dynamic value) {
    if (value is! Map) throw const ClubException('本地演示结算数据无效');
    final settlement = Map<String, dynamic>.from(value);
    const required = [
      'rule_version',
      'order',
      'revision',
      'settled_at',
      'source_game_id',
      'players',
    ];
    if (required.any((key) => !settlement.containsKey(key))) {
      throw const ClubException('本地演示结算数据不完整');
    }
    if (settlement['rule_version'] != ratingRuleVersion) {
      throw const ClubException('本地演示包含未知评分规则');
    }
    if (settlement['order'] is! int || (settlement['order'] as int) <= 0) {
      throw const ClubException('本地演示结算顺序无效');
    }
    if (settlement['revision'] is! int ||
        (settlement['revision'] as int) <= 0) {
      throw const ClubException('本地演示结算版本无效');
    }
    if (settlement['source_game_id'] != null &&
        settlement['source_game_id'] is! String) {
      throw const ClubException('本地演示结算来源无效');
    }
    if (settlement['settled_at'] is! String) {
      throw const ClubException('本地演示结算时间无效');
    }
    try {
      DateTime.parse(settlement['settled_at'] as String);
    } catch (_) {
      throw const ClubException('本地演示结算时间无效');
    }
    final rawPlayers = settlement['players'];
    if (rawPlayers is! List || rawPlayers.length != 4) {
      throw const ClubException('本地演示结算成员数据不完整');
    }
    final ids = <String>{};
    for (final value in rawPlayers) {
      if (value is! Map) throw const ClubException('本地演示结算成员数据无效');
      final player = Map<String, dynamic>.from(value);
      const playerRequired = [
        'member_id',
        'final_points',
        'actual_uma',
        'pt',
        'old_mmr',
        'mmr_delta',
        'new_mmr',
      ];
      if (playerRequired.any((key) => !player.containsKey(key))) {
        throw const ClubException('本地演示结算成员数据不完整');
      }
      final memberId = player['member_id'];
      if (memberId is! String || memberId.isEmpty || !ids.add(memberId)) {
        throw const ClubException('本地演示结算成员无效');
      }
      if (player['final_points'] is! int) {
        throw const ClubException('本地演示结算点数无效');
      }
      for (final key in const [
        'actual_uma',
        'pt',
        'old_mmr',
        'mmr_delta',
        'new_mmr',
      ]) {
        _validateFiniteNumber(player[key], '本地演示结算数值无效');
      }
    }
  }

  static void _validateFiniteNumber(dynamic value, String message) {
    if (value is! num || !value.toDouble().isFinite) {
      throw ClubException(message);
    }
  }

  static void _validateSnapshot(ClubSnapshot snapshot) {
    if (snapshot.ratingSchemaVersion != _ratingSchemaVersion) {
      throw const ClubException('本地演示评分版本不受支持');
    }
    if (snapshot.eventSchemaVersion != _eventSchemaVersion) {
      throw const ClubException('本地演示活动版本不受支持');
    }
    final roomIds = snapshot.rooms.map((room) => room.id).toSet();
    final eventIds = <String>{};
    for (final event in snapshot.events) {
      if (!eventIds.add(event.id) ||
          event.id.isEmpty ||
          event.version < 0 ||
          event.name.trim().isEmpty ||
          event.name.trim().runes.length > 80 ||
          event.description.trim().runes.length > 2000 ||
          !event.endsAt.isAfter(event.startsAt) ||
          event.roomIds.isEmpty ||
          event.roomIds.length != event.roomIds.toSet().length ||
          event.roomIds.any((id) => !roomIds.contains(id))) {
        throw const ClubException('本地演示活动数据无效');
      }
    }
    final memberIds = <String>{};
    final expectedMmr = <String, double>{};
    for (final member in snapshot.members) {
      if (!memberIds.add(member.id)) {
        throw const ClubException('本地演示成员 ID 重复');
      }
      _finiteMmr(member.mmr, '本地演示成员 MMR 无效');
      _finiteMmr(member.mmrBaseline, '本地演示成员评分基线无效');
      if (member.mmrBaseline != initialMmr) {
        throw const ClubException('本地演示成员评分基线不是可信初始值');
      }
      expectedMmr[member.id] = member.mmrBaseline;
    }
    final orders = <int>{};
    final ratedGames = <ClubGame>[];
    for (final game in snapshot.games) {
      final gamePlayerIds = game.players
          .map((player) => player.memberId)
          .toSet();
      if (game.players.length != 4 ||
          gamePlayerIds.length != 4 ||
          gamePlayerIds.any((id) => !memberIds.contains(id))) {
        throw const ClubException('本地演示对局缺少成员评分状态');
      }
      final current = game.settlement;
      if (current == null) {
        if (game.settlementHistory.isNotEmpty) {
          throw const ClubException('本地演示评分历史缺少当前版本');
        }
        continue;
      }
      if (game.status != GameStatus.completed) {
        throw const ClubException('本地演示未完成对局不能有结算');
      }
      if (!orders.add(current.order)) {
        throw const ClubException('本地演示结算顺序重复');
      }
      ratedGames.add(game);
      _validateSettlement(current, game, memberIds);
      var previousRevision = 0;
      for (final history in game.settlementHistory) {
        if (history.order != current.order ||
            history.revision <= previousRevision) {
          throw const ClubException('本地演示结算历史顺序无效');
        }
        _validateSettlement(history, game, memberIds, checkScores: false);
        previousRevision = history.revision;
      }
      if (game.settlementHistory.isNotEmpty &&
          game.settlementHistory.last.revision >= current.revision) {
        throw const ClubException('本地演示结算版本无效');
      }
    }
    ratedGames.sort(
      (left, right) =>
          left.settlement!.order.compareTo(right.settlement!.order),
    );
    for (final game in ratedGames) {
      for (final player in game.settlement!.players) {
        final previous = expectedMmr[player.memberId];
        if (previous == null || player.oldMmr != previous) {
          throw const ClubException('本地演示结算 MMR 链不连续');
        }
        expectedMmr[player.memberId] = player.newMmr;
      }
    }
    for (final member in snapshot.members) {
      if (member.mmr != expectedMmr[member.id]) {
        throw const ClubException('本地演示成员 MMR 与结算历史不一致');
      }
    }
  }

  static void _validateSettlement(
    GameSettlement settlement,
    ClubGame game,
    Set<String> memberIds, {
    bool checkScores = true,
  }) {
    if (settlement.ruleVersion != ratingRuleVersion ||
        settlement.order <= 0 ||
        settlement.revision <= 0 ||
        settlement.players.length != 4) {
      throw const ClubException('本地演示结算数据无效');
    }
    final gamePlayerIds = game.players.map((player) => player.memberId).toSet();
    final settlementPlayerIds = <String>{};
    for (final player in settlement.players) {
      if (!memberIds.contains(player.memberId) ||
          !settlementPlayerIds.add(player.memberId) ||
          !gamePlayerIds.contains(player.memberId) ||
          !player.actualUma.isFinite ||
          !player.pt.isFinite ||
          !player.oldMmr.isFinite ||
          !player.mmrDelta.isFinite ||
          !player.newMmr.isFinite) {
        throw const ClubException('本地演示结算成员状态无效');
      }
      if (checkScores) {
        final score = game.players
            .firstWhere((entry) => entry.memberId == player.memberId)
            .score;
        if (score == null || score != player.finalPoints) {
          throw const ClubException('本地演示结算点数与对局不一致');
        }
      }
    }
    if (settlementPlayerIds.length != gamePlayerIds.length ||
        gamePlayerIds.length != 4) {
      throw const ClubException('本地演示结算成员不完整');
    }
  }

  static ClubSnapshot _seed() {
    const members = [
      Member(id: 'andy', name: 'Andy'),
      Member(id: 'zoey', name: 'Zoey'),
      Member(id: 'jin', name: 'Jin'),
      Member(id: 'xiong', name: 'Xiong'),
      Member(id: 'amy', name: 'Amy'),
      Member(id: 'xiaoming', name: '小明'),
    ];
    final now = DateTime.now().toUtc();
    final historicalStartedAt = now.subtract(const Duration(days: 1, hours: 2));
    final historicalCompletedAt = now.subtract(const Duration(days: 1));
    final historicalEvent = ClubEvent(
      id: 'demo-event-history',
      name: '演示历史活动',
      description: '已结束的本地演示活动，展示历史活动战绩。',
      startsAt: now.subtract(const Duration(days: 3)),
      endsAt: now.subtract(const Duration(hours: 12)),
      roomIds: const ['room-7699'],
      createdAt: now.subtract(const Duration(days: 3)),
    );
    final activeEvent = ClubEvent(
      id: 'demo-event-active',
      name: 'Demo 进行中活动',
      description: '当前进行中的本地演示活动。',
      startsAt: now.subtract(const Duration(hours: 2)),
      endsAt: now.add(const Duration(hours: 12)),
      roomIds: const ['room-9162'],
      createdAt: now.subtract(const Duration(days: 1)),
    );
    final futureEvent = ClubEvent(
      id: 'demo-event-future',
      name: '演示未来活动',
      description: '即将开始的本地演示活动。',
      startsAt: now.add(const Duration(days: 1)),
      endsAt: now.add(const Duration(days: 2)),
      roomIds: const ['room-7699', 'room-9162'],
      createdAt: now,
    );
    final activePlayers = [
      for (var i = 0; i < 4; i++)
        GamePlayer(
          memberId: members[i].id,
          name: members[i].name,
          wind: Wind.values[i],
          score: <int?>[32500, 27800, 24700, null][i],
        ),
    ];
    final historicalGame = ClubGame(
      id: 'demo-history',
      roomId: 'room-7699',
      creatorId: 'andy',
      players: rankPlayers([
        for (var i = 0; i < 4; i++)
          GamePlayer(
            memberId: members[i].id,
            name: members[i].name,
            wind: Wind.values[i],
            score: [38200, 27100, 20900, 13800][i],
          ),
      ]),
      startedAt: historicalStartedAt,
      completedAt: historicalCompletedAt,
      status: GameStatus.completed,
      version: 4,
      eventId: historicalEvent.id,
    );
    final seedCalculation = _calculateSettlement(
      historicalGame,
      {for (final member in members) member.id: member.mmr},
      order: 1,
      revision: 1,
      settledAt: historicalGame.completedAt!,
    );
    final settledMembers = _applyResults(members, seedCalculation.results);
    final settledHistory = ClubGame(
      id: historicalGame.id,
      roomId: historicalGame.roomId,
      creatorId: historicalGame.creatorId,
      players: historicalGame.players,
      startedAt: historicalGame.startedAt,
      status: historicalGame.status,
      completedAt: historicalGame.completedAt,
      version: historicalGame.version,
      eventId: historicalGame.eventId,
      settlement: seedCalculation.settlement,
    );
    return ClubSnapshot(
      members: settledMembers,
      rooms: const [
        ClubRoom(id: 'room-7699', name: '7699'),
        ClubRoom(
          id: 'room-9162',
          name: '9162',
          seats: {
            Wind.east: 'andy',
            Wind.south: 'zoey',
            Wind.west: 'jin',
            Wind.north: 'xiong',
          },
        ),
      ],
      games: [
        ClubGame(
          id: 'demo-active',
          roomId: 'room-9162',
          creatorId: 'andy',
          players: activePlayers,
          startedAt: now.subtract(const Duration(minutes: 48)),
          version: 3,
          eventId: activeEvent.id,
        ),
        settledHistory,
      ],
      ratingSchemaVersion: _ratingSchemaVersion,
      events: [historicalEvent, activeEvent, futureEvent],
      eventSchemaVersion: _eventSchemaVersion,
    );
  }
}

class _SettlementComputation {
  const _SettlementComputation(this.settlement, this.results);

  final GameSettlement settlement;
  final List<RatingResult> results;
}

class _ReplayResult {
  const _ReplayResult(this.games, this.members);

  final List<ClubGame> games;
  final List<Member> members;
}

class _DepartureCleanup {
  const _DepartureCleanup(this.snapshot, this.pending);

  final ClubSnapshot snapshot;
  final Set<String> pending;
}
