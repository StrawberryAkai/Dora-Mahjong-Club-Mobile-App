import 'models.dart';

/// Comparison form for duplicate names. Display names retain their case;
/// player and rating relationships always use memberId.
String normalizeName(String name) => name.trim().toLowerCase();

String? validateName(String input) {
  final name = input.trim();
  if (name.isEmpty || name.runes.length > 20) return '姓名长度须为 1–20 个字符';
  if (!RegExp(
    r'^[a-zA-Z\u3400-\u4DBF\u4E00-\u9FFF\u{20000}-\u{2FA1F}]+$',
    unicode: true,
  ).hasMatch(name)) {
    return '仅支持中文和英文字母，不含数字、空格或符号';
  }
  return null;
}

/// Validates one score. Empty/invalid input must not become a valid zero;
/// the four-player total is validated separately at game level.
int parseScore(String input) {
  final raw = input.trim();
  if (!RegExp(r'^-?\d+$').hasMatch(raw)) {
    throw const ClubException('请输入整数点数，例如 25000 或 -1500');
  }
  final score = int.tryParse(raw);
  if (score == null || score < -2147483600 || score > 2147483600) {
    throw const ClubException('点数超出可保存范围');
  }
  if (score % 100 != 0) throw const ClubException('点数必须是 100 的倍数');
  return score;
}

/// Assigns display ranks, breaking ties by starting seat. Never use these ranks
/// to look up Uma: rating.dart groups equal points and shares the occupied
/// rank bonuses equally among tied players.
List<GamePlayer> rankPlayers(List<GamePlayer> players) {
  if (players.length != 4 || players.any((p) => p.score == null)) {
    throw const ClubException('请填写全部四位成员的点数');
  }
  final sorted = [...players]
    ..sort((a, b) {
      final difference = b.score!.compareTo(a.score!);
      return difference != 0
          ? difference
          : a.wind.index.compareTo(b.wind.index);
    });
  return players
      .map(
        (p) => GamePlayer(
          memberId: p.memberId,
          name: p.name,
          wind: p.wind,
          score: p.score,
          rank: sorted.indexWhere((s) => s.memberId == p.memberId) + 1,
        ),
      )
      .toList();
}

String formatPoints(int score) {
  final digits = score.abs().toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (match) => '${match[1]},',
  );
  return score < 0 ? '-$digits' : digits;
}
