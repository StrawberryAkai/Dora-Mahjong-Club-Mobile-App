import 'models.dart';

void validateEventDraft(EventDraft draft, List<ClubRoom> rooms) {
  _validateDraftShape(draft);

  final validRoomIds = rooms.map((room) => room.id).toSet();
  if (draft.roomIds.any((roomId) => !validRoomIds.contains(roomId))) {
    throw const ClubException('活动包含不存在的房间');
  }
}

/// Edits cannot exclude games already linked to the event. Validate game start
/// times against [start, end) so edits cannot silently change ranking eligibility.
void validateEventEdit(EventDraft draft, List<ClubGame> games) {
  _validateDraftShape(draft);
  final eventId = draft.id;
  if (eventId == null) {
    throw const ClubException('编辑活动需要活动 id');
  }

  for (final game in games) {
    if (game.eventId != eventId) continue;
    final startsOutsideWindow = game.startedAt.isBefore(draft.startsAt);
    final endsOutsideWindow = !game.startedAt.isBefore(draft.endsAt);
    if (startsOutsideWindow || endsOutsideWindow) {
      throw const ClubException('活动时间范围不能排除已关联的对局');
    }
    if (!draft.roomIds.contains(game.roomId)) {
      throw const ClubException('活动房间范围不能排除已关联的对局');
    }
  }
}

List<ClubEvent> eligibleEvents(
  ClubSnapshot snapshot,
  String roomId,
  DateTime now,
) {
  final result = snapshot.events
      .where((event) => event.isActiveAt(now) && event.roomIds.contains(roomId))
      .toList();
  result.sort((a, b) {
    final startComparison = a.startsAt.compareTo(b.startsAt);
    if (startComparison != 0) return startComparison;
    final nameComparison = a.name.compareTo(b.name);
    if (nameComparison != 0) return nameComparison;
    return a.id.compareTo(b.id);
  });
  return result;
}

void _validateDraftShape(EventDraft draft) {
  final nameLength = draft.name.trim().runes.length;
  if (nameLength < 1 || nameLength > 80) {
    throw const ClubException('活动名称长度须为 1–80 个字符');
  }

  final descriptionLength = draft.description.trim().runes.length;
  if (descriptionLength > 2000) {
    throw const ClubException('活动说明不能超过 2000 个字符');
  }

  if (!_isFiniteDateTime(draft.startsAt) || !_isFiniteDateTime(draft.endsAt)) {
    throw const ClubException('活动时间无效');
  }
  if (!draft.startsAt.isBefore(draft.endsAt)) {
    throw const ClubException('活动结束时间必须晚于开始时间');
  }

  if (draft.roomIds.isEmpty) {
    throw const ClubException('活动至少需要一个房间');
  }
  if (draft.roomIds.any((roomId) => roomId.trim().isEmpty)) {
    throw const ClubException('活动房间无效');
  }
  if (draft.roomIds.toSet().length != draft.roomIds.length) {
    throw const ClubException('活动房间不能重复');
  }

  final hasId = draft.id != null;
  final hasVersion = draft.expectedVersion != null;
  if (hasId != hasVersion) {
    throw const ClubException('活动 id 和版本必须同时提供');
  }
  if (draft.id != null && draft.id!.trim().isEmpty) {
    throw const ClubException('活动 id 无效');
  }
  if (draft.expectedVersion != null && draft.expectedVersion! < 0) {
    throw const ClubException('活动版本无效');
  }
}

bool _isFiniteDateTime(DateTime value) {
  try {
    // DateTime values are normally finite by construction. Serializing the
    // value also catches an out-of-range implementation supplied by a caller.
    value.toUtc().toIso8601String();
    return true;
  } on Object {
    return false;
  }
}
