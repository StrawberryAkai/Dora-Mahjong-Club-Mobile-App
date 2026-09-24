enum Wind {
  east('东'),
  south('南'),
  west('西'),
  north('北');

  const Wind(this.label);
  final String label;
}

enum GameStatus { active, completed, cancelled }

class ClubException implements Exception {
  const ClubException(this.message, {this.isConflict = false});
  final String message;
  final bool isConflict;
  @override
  String toString() => message;
}

double _ratingNumber(
  Map<String, dynamic> json,
  String key, {
  double? legacyDefault,
}) {
  if (!json.containsKey(key) && legacyDefault != null) return legacyDefault;
  final value = json[key];
  if (value is! num || !value.toDouble().isFinite) {
    throw FormatException('Invalid rating value: $key');
  }
  return value.toDouble();
}

class Member {
  const Member({
    required this.id,
    required this.name,
    this.mmr = 1500,
    this.mmrBaseline = 1500,
    this.legacyStats,
    this.currentStats,
  });
  final String id;
  final String name;
  final double mmr;
  final double mmrBaseline;

  /// Immutable statistics at import. Historical games must not be counted again.
  final Map<String, dynamic>? legacyStats;
  final Map<String, dynamic>? currentStats;
  double get ptBaseline => (legacyStats?['total_pt'] as num?)?.toDouble() ?? 0;
  int get gamesPlayedBaseline =>
      (legacyStats?['games_played'] as num?)?.toInt() ?? 0;
  int? get mmrRankBaseline => (legacyStats?['mmr_rank'] as num?)?.toInt();
  int? get ptRankBaseline => (legacyStats?['pt_rank'] as num?)?.toInt();
  factory Member.fromJson(Map<String, dynamic> json) => Member(
    id: json['id'] as String,
    name: json['name'] as String,
    mmr: _ratingNumber(json, 'mmr', legacyDefault: 1500),
    mmrBaseline: _ratingNumber(json, 'mmr_baseline', legacyDefault: 1500),
    legacyStats: json['legacy_stats'] == null
        ? null
        : Map<String, dynamic>.unmodifiable(json['legacy_stats'] as Map),
    currentStats: json['current_stats'] == null
        ? null
        : Map<String, dynamic>.unmodifiable(json['current_stats'] as Map),
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'mmr': mmr,
    'mmr_baseline': mmrBaseline,
    if (legacyStats != null) 'legacy_stats': legacyStats,
    if (currentStats != null) 'current_stats': currentStats,
  };
}

/// An immutable per-player result. Names and seat-based display ranks are not
/// rating keys. Final points are kept so past revisions remain auditable.
class PlayerSettlement {
  const PlayerSettlement({
    required this.memberId,
    required this.finalPoints,
    required this.actualUma,
    required this.pt,
    required this.oldMmr,
    required this.mmrDelta,
    required this.newMmr,
  });

  final String memberId;
  final int finalPoints;
  final double actualUma;
  final double pt;
  final double oldMmr;
  final double mmrDelta;
  final double newMmr;

  factory PlayerSettlement.fromJson(Map<String, dynamic> json) =>
      PlayerSettlement(
        memberId: json['member_id'] as String,
        finalPoints: json['final_points'] as int,
        actualUma: _ratingNumber(json, 'actual_uma'),
        pt: _ratingNumber(json, 'pt'),
        oldMmr: _ratingNumber(json, 'old_mmr'),
        mmrDelta: _ratingNumber(json, 'mmr_delta'),
        newMmr: _ratingNumber(json, 'new_mmr'),
      );

  Map<String, dynamic> toJson() => {
    'member_id': memberId,
    'final_points': finalPoints,
    'actual_uma': actualUma,
    'pt': pt,
    'old_mmr': oldMmr,
    'mmr_delta': mmrDelta,
    'new_mmr': newMmr,
  };
}

/// A versioned settlement in a fixed chronology. Corrections append revisions;
/// they never change the original settlement order or erase old calculations.
class GameSettlement {
  const GameSettlement({
    required this.ruleVersion,
    required this.order,
    required this.revision,
    required this.settledAt,
    required this.players,
    this.sourceGameId,
  });

  final String ruleVersion;
  final int order;
  final int revision;
  final DateTime settledAt;
  final String? sourceGameId;
  final List<PlayerSettlement> players;

  PlayerSettlement? player(String memberId) =>
      players.where((entry) => entry.memberId == memberId).firstOrNull;

  factory GameSettlement.fromJson(Map<String, dynamic> json) => GameSettlement(
    ruleVersion: json['rule_version'] as String,
    order: json['order'] as int,
    revision: json['revision'] as int,
    settledAt: DateTime.parse(json['settled_at'] as String),
    sourceGameId: json['source_game_id'] as String?,
    players: (json['players'] as List)
        .map(
          (entry) => PlayerSettlement.fromJson(
            Map<String, dynamic>.from(entry as Map),
          ),
        )
        .toList(),
  );

  Map<String, dynamic> toJson() => {
    'rule_version': ruleVersion,
    'order': order,
    'revision': revision,
    'settled_at': settledAt.toIso8601String(),
    'source_game_id': sourceGameId,
    'players': players.map((entry) => entry.toJson()).toList(),
  };
}

class ClubRoom {
  const ClubRoom({required this.id, required this.name, this.seats = const {}});
  final String id;
  final String name;
  final Map<Wind, String> seats;
  factory ClubRoom.fromJson(Map<String, dynamic> json) => ClubRoom(
    id: json['id'] as String,
    name: json['name'] as String,
    seats: (json['seats'] as Map<String, dynamic>? ?? {}).map(
      (key, value) => MapEntry(Wind.values.byName(key), value as String),
    ),
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'seats': seats.map((key, value) => MapEntry(key.name, value)),
  };
}

class ClubEvent {
  const ClubEvent({
    required this.id,
    required this.name,
    required this.description,
    required this.startsAt,
    required this.endsAt,
    required this.roomIds,
    required this.createdAt,
    this.version = 0,
  });

  final String id;
  final String name;
  final String description;
  final DateTime startsAt;
  final DateTime endsAt;
  final List<String> roomIds;
  final DateTime createdAt;
  final int version;

  bool isActiveAt(DateTime now) =>
      !now.isBefore(startsAt) && now.isBefore(endsAt);

  factory ClubEvent.fromJson(Map<String, dynamic> json) => ClubEvent(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String,
    startsAt: DateTime.parse(json['starts_at'] as String),
    endsAt: DateTime.parse(json['ends_at'] as String),
    roomIds: List<String>.from(json['room_ids'] as List),
    createdAt: DateTime.parse(json['created_at'] as String),
    version: json['version'] as int,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'starts_at': startsAt.toUtc().toIso8601String(),
    'ends_at': endsAt.toUtc().toIso8601String(),
    'room_ids': List<String>.from(roomIds),
    'created_at': createdAt.toUtc().toIso8601String(),
    'version': version,
  };
}

/// An administrator's draft. Authentication and authority come from the
/// repository session, never from fields supplied by the editor.
class EventDraft {
  const EventDraft({
    this.id,
    this.expectedVersion,
    required this.name,
    required this.description,
    required this.startsAt,
    required this.endsAt,
    required this.roomIds,
  });

  final String? id;
  final int? expectedVersion;
  final String name;
  final String description;
  final DateTime startsAt;
  final DateTime endsAt;
  final List<String> roomIds;

  Map<String, dynamic> toJson() => {
    'id': id,
    'expected_version': expectedVersion,
    'name': name.trim(),
    'description': description.trim(),
    'starts_at': startsAt.toUtc().toIso8601String(),
    'ends_at': endsAt.toUtc().toIso8601String(),
    'room_ids': [...roomIds]..sort(),
  };
}

class GamePlayer {
  const GamePlayer({
    required this.memberId,
    required this.name,
    required this.wind,
    this.score,
    this.rank,
  });
  final String memberId;
  final String name;
  final Wind wind;
  // null means awaiting input; zero is a valid submitted score.
  final int? score;
  final int? rank;
  factory GamePlayer.fromJson(Map<String, dynamic> json) => GamePlayer(
    memberId: json['member_id'] as String,
    name: json['name'] as String,
    wind: Wind.values.byName(json['wind'] as String),
    score: json['score'] as int?,
    rank: json['rank'] as int?,
  );
  Map<String, dynamic> toJson() => {
    'member_id': memberId,
    'name': name,
    'wind': wind.name,
    'score': score,
    'rank': rank,
  };
}

class ClubGame {
  const ClubGame({
    required this.id,
    required this.roomId,
    required this.creatorId,
    required this.players,
    required this.startedAt,
    this.status = GameStatus.active,
    this.completedAt,
    this.cancelledAt,
    this.cancelReason,
    this.cancelledBy,
    this.version = 0,
    this.settlement,
    this.settlementHistory = const [],
    this.eventId,
  });
  final String id;
  final String roomId;
  final String creatorId;
  final List<GamePlayer> players;
  final DateTime startedAt;
  final GameStatus status;
  final DateTime? completedAt;
  final DateTime? cancelledAt;
  final String? cancelReason;
  final String? cancelledBy;
  final int version;
  final GameSettlement? settlement;
  final List<GameSettlement> settlementHistory;
  final String? eventId;
  int get total => players.fold(0, (sum, player) => sum + (player.score ?? 0));
  int get enteredCount => players.where((p) => p.score != null).length;
  bool get allEntered => enteredCount == 4;
  bool get needsCorrection =>
      status == GameStatus.active && allEntered && total != 100000;
  bool involves(String? memberId) =>
      memberId != null && players.any((p) => p.memberId == memberId);
  factory ClubGame.fromJson(Map<String, dynamic> json) => ClubGame(
    id: json['id'] as String,
    roomId: json['room_id'] as String,
    creatorId: json['creator_id'] as String,
    players: (json['players'] as List)
        .map((p) => GamePlayer.fromJson(Map<String, dynamic>.from(p as Map)))
        .toList(),
    startedAt: DateTime.parse(json['started_at'] as String),
    status: GameStatus.values.byName(json['status'] as String),
    completedAt: json['completed_at'] == null
        ? null
        : DateTime.parse(json['completed_at'] as String),
    cancelledAt: json['cancelled_at'] == null
        ? null
        : DateTime.parse(json['cancelled_at'] as String),
    cancelReason: json['cancel_reason'] as String?,
    cancelledBy: json['cancelled_by'] as String?,
    version: json['version'] as int? ?? 0,
    eventId: json['event_id'] as String?,
    settlement: json['settlement'] == null
        ? null
        : GameSettlement.fromJson(
            Map<String, dynamic>.from(json['settlement'] as Map),
          ),
    settlementHistory: (json['settlement_history'] as List? ?? [])
        .map(
          (entry) =>
              GameSettlement.fromJson(Map<String, dynamic>.from(entry as Map)),
        )
        .toList(),
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'room_id': roomId,
    'creator_id': creatorId,
    'players': players.map((p) => p.toJson()).toList(),
    'started_at': startedAt.toIso8601String(),
    'status': status.name,
    'completed_at': completedAt?.toIso8601String(),
    'cancelled_at': cancelledAt?.toIso8601String(),
    'cancel_reason': cancelReason,
    'cancelled_by': cancelledBy,
    'version': version,
    'event_id': eventId,
    'settlement': settlement?.toJson(),
    'settlement_history': settlementHistory
        .map((entry) => entry.toJson())
        .toList(),
  };
}

class ScoreAudit {
  const ScoreAudit({
    required this.id,
    required this.gameId,
    required this.actor,
    required this.at,
    required this.before,
    required this.after,
  });
  final String id;
  final String gameId;
  final String actor;
  final DateTime at;
  final Map<String, int> before;
  final Map<String, int> after;
  factory ScoreAudit.fromJson(Map<String, dynamic> json) => ScoreAudit(
    id: json['id'] as String,
    gameId: json['game_id'] as String,
    actor: json['actor'] as String,
    at: DateTime.parse(json['at'] as String),
    before: Map<String, int>.from(json['before'] as Map),
    after: Map<String, int>.from(json['after'] as Map),
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'game_id': gameId,
    'actor': actor,
    'at': at.toIso8601String(),
    'before': before,
    'after': after,
  };
}

class ClubSnapshot {
  const ClubSnapshot({
    this.members = const [],
    this.rooms = const [],
    this.games = const [],
    this.audits = const [],
    this.memberId,
    this.isAdmin = false,
    this.adminName,
    this.ratingSchemaVersion = 1,
    this.events = const [],
    this.eventSchemaVersion = 1,
  });
  final List<Member> members;
  final List<ClubRoom> rooms;
  final List<ClubGame> games;
  final List<ScoreAudit> audits;
  final String? memberId;
  final bool isAdmin;
  final String? adminName;
  final int ratingSchemaVersion;
  final List<ClubEvent> events;
  final int eventSchemaVersion;
  Member? get currentMember =>
      members.where((m) => m.id == memberId).firstOrNull;
  ClubGame? activeGame(String roomId) => games
      .where((g) => g.roomId == roomId && g.status == GameStatus.active)
      .firstOrNull;
  String memberName(String id) =>
      members.where((m) => m.id == id).firstOrNull?.name ?? '未知成员';
  String roomName(String id) =>
      rooms.where((r) => r.id == id).firstOrNull?.name ?? '房间';
  factory ClubSnapshot.fromJson(Map<String, dynamic> json) => ClubSnapshot(
    members: (json['members'] as List? ?? [])
        .map((v) => Member.fromJson(Map<String, dynamic>.from(v as Map)))
        .toList(),
    rooms: (json['rooms'] as List? ?? [])
        .map((v) => ClubRoom.fromJson(Map<String, dynamic>.from(v as Map)))
        .toList(),
    games: (json['games'] as List? ?? [])
        .map((v) => ClubGame.fromJson(Map<String, dynamic>.from(v as Map)))
        .toList(),
    audits: (json['audits'] as List? ?? [])
        .map((v) => ScoreAudit.fromJson(Map<String, dynamic>.from(v as Map)))
        .toList(),
    memberId: json['member_id'] as String?,
    isAdmin: json['is_admin'] as bool? ?? false,
    adminName: json['admin_name'] as String?,
    ratingSchemaVersion: json['rating_schema_version'] as int? ?? 0,
    events: (json['events'] as List? ?? [])
        .map(
          (entry) =>
              ClubEvent.fromJson(Map<String, dynamic>.from(entry as Map)),
        )
        .toList(),
    eventSchemaVersion: json['event_schema_version'] as int? ?? 0,
  );
  Map<String, dynamic> toJson() => {
    'members': members.map((v) => v.toJson()).toList(),
    'rooms': rooms.map((v) => v.toJson()).toList(),
    'games': games.map((v) => v.toJson()).toList(),
    'audits': audits.map((v) => v.toJson()).toList(),
    'member_id': memberId,
    'is_admin': isAdmin,
    'admin_name': adminName,
    'rating_schema_version': ratingSchemaVersion,
    'events': events.map((entry) => entry.toJson()).toList(),
    'event_schema_version': eventSchemaVersion,
  };
}
