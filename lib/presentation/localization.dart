import 'package:flutter/widgets.dart';

import '../application/app_preferences.dart';
import '../domain/models.dart';
import '../l10n/feedback_messages.dart';

/// Small, localised string helper for the presentation layer.
///
/// The application deliberately keeps Chinese as its source language.  Keeping
/// the English copy beside each source string makes it possible to translate
/// dynamic UI labels without introducing a generated arb catalogue for this
/// small app.  Controller and repository messages can still be passed through
/// [text] at the display boundary when a translated copy is available.
class DoraStrings {
  const DoraStrings(this.isEnglish);

  final bool isEnglish;

  String text(String chinese, [String? english]) {
    return isEnglish
        ? (english ??
              _knownTranslations[chinese] ??
              englishFeedback(chinese) ??
              chinese)
        : chinese;
  }

  String plural(String chinese, String english, int count) {
    return isEnglish ? '$count $english' : '$count$chinese';
  }

  static const _knownTranslations = <String, String>{
    '管理员': 'Admin',
    '成员': 'Member',
    '俱乐部成员': 'Club member',
    '未选择': 'Not selected',
    '空位': 'Open seat',
    '待录入': 'Pending',
    '记录': 'History',
    '房间': 'Rooms',
    '俱乐部': 'Club',
    '刷新': 'Refresh',
    '返回': 'Back',
    '取消': 'Cancel',
    '保存': 'Save',
    '登录': 'Sign in',
    '退出': 'Sign out',
    '切换成员 / 退出': 'Switch member / sign out',
    '管理员退出': 'Sign out admin',
    '查看修改记录': 'View change log',
    '管理员入口': 'Admin sign in',
    '创建新成员': 'Create member',
    '没有找到成员': 'No members found',
    '先创建一个俱乐部成员。': 'Create a club member first.',
    '试试其他首字，或直接创建新成员。': 'Try another starting letter, or create a new member.',
    '按姓名首字搜索已有成员': 'Search members by first letter',
    '姓名': 'Name',
    '用户名': 'Username',
    '密码': 'Password',
    '重试': 'Retry',
    '创建俱乐部成员': 'Create club member',
    '管理员登录': 'Admin sign in',
    '体验演示管理员': 'Try demo admin',
    '演示': 'Demo',
    '演示模式': 'Demo mode',
    '正在准备牌桌': 'Preparing the tables',
    '暂时无法打开俱乐部': 'The club is temporarily unavailable',
    '请检查网络后重试': 'Check your connection and try again',
    '姓名只用于俱乐部内识别，不需要密码。':
        'Your name is only used within the club; no password is needed.',
    '创建并进入': 'Create and enter',
    '创建中…': 'Creating…',
    '登录中…': 'Signing in…',
    '登录失败，请检查账号信息': 'Sign in failed. Check your account details.',
    '请输入管理员用户名和密码': 'Enter an admin username and password.',
    '房间初始化后会出现在这里。': 'Rooms will appear here after setup.',
    '还没有房间': 'No rooms yet',
    '查看待录入对局': 'View pending games',
    '刷新中…': 'Refreshing…',
    '保存中…': 'Saving…',
    '取消中…': 'Cancelling…',
    '删除': 'Delete',
    '修改房间名称': 'Rename room',
    '清理全部座位': 'Clear all seats',
    '移除玩家': 'Remove player',
    '开始对局': 'Start game',
    '当前对局': 'Current game',
    '开始时间': 'Started',
    '完成时间': 'Completed',
    '取消时间': 'Cancelled',
    '创建者': 'Created by',
    '修改记录': 'Change log',
    '成绩更正与操作者': 'Score changes and operators',
    '还没有修改记录': 'No changes yet',
    '完成成绩更正后，操作会显示在这里。': 'Score corrections will appear here.',
    '更正整场成绩': 'Correct all scores',
    '更正会整场原子保存并重新计算名次，不需要填写原因。':
        'The correction saves atomically and recalculates ranks; no reason is needed.',
    '保存更正': 'Save correction',
    '取消这场对局': 'Cancel this game',
    '确认取消': 'Confirm cancellation',
    '取消原因': 'Cancellation reason',
    '例如：成员临时离开': 'For example: a member had to leave',
    '房间名称已更新': 'Room name updated',
    '显示名称': 'Display name',
    '总分待纠错': 'Total needs correction',
    '准备完成': 'Ready',
    '总分不等于 100,000，请检查。': 'The total is not 100,000. Check the scores.',
    '正在确认成绩…': 'Confirming scores…',
    '待填写你的点数': 'Enter your score',
    '等待其他成员': 'Waiting for other members',
    '我参与的': 'Mine',
    '第一场完成的对局会从这里开始。': 'Completed games will start appearing here.',
    '完成一场对局后，它会出现在这里。': 'Finish a game and it will appear here.',
    '俱乐部还没有记录': 'The club has no history',
    '还没有我的记录': 'No history for me',
    '没有待处理对局': 'No pending games',
    '现在没有待处理对局': 'No pending games right now',
    '完成的对局会自动进入记录。': 'Completed games appear in history automatically.',
    '房间已不存在': 'Room no longer exists',
    '对局已不存在': 'Game no longer exists',
    '本场已取消': 'This game was cancelled',
    '请返回并刷新最新状态。': 'Go back and refresh for the latest state.',
    '对局已取消': 'Game cancelled',
    '点数已保存': 'Score saved',
    '成绩已更正': 'Scores corrected',
    '管理员可管理房间、座位和成绩': 'Admins can manage rooms, seats, and scores',
    '已选择俱乐部成员身份': 'Club member identity selected',
    '刷新俱乐部状态': 'Refresh club status',
    '麻将俱乐部': 'Mahjong Club',
    'UCSD 麻将社': 'Dora Mahjong Club',
    '麻将社': 'Mahjong Club',
    'DORA / CLUB DESK': 'DORA / CLUB DESK',
    '管理员体验': 'Try admin demo',
    '演示模式 · 数据仅保存在此设备': 'Demo mode · data stays on this device',
    '打开个人菜单': 'Open profile menu',
    '打开个人设置': 'Open profile settings',
    '切换为中文': 'Switch to Chinese',
    '切换为 English': 'Switch to English',
    '切换到深色模式': 'Switch to dark mode',
    '切换到浅色模式': 'Switch to light mode',
    '深色模式': 'Dark mode',
    '浅色模式': 'Light mode',
    '中文': 'Chinese',
    'English': 'English',
  };
}

/// Reads the app preference scope while allowing presentation widgets to be
/// used in isolation by older tests that do not yet wrap the app in the scope.
/// Chinese remains the safe default until the scope is present.
DoraStrings doraStrings(BuildContext context) {
  try {
    return DoraStrings(AppPreferencesScope.of(context).isEnglish);
  } catch (_) {
    return const DoraStrings(false);
  }
}

extension DoraLocalization on BuildContext {
  DoraStrings get strings => doraStrings(this);

  String t(String chinese, [String? english]) => strings.text(chinese, english);
}

String doraWindLabel(BuildContext context, Wind wind, {bool compact = false}) {
  if (!context.strings.isEnglish) return wind.label;
  if (compact) return wind.name[0].toUpperCase();
  return switch (wind) {
    Wind.east => 'East',
    Wind.south => 'South',
    Wind.west => 'West',
    Wind.north => 'North',
  };
}

/// Maps stable domain/controller feedback at the point where it is rendered.
/// User entered names and reasons are retained verbatim in the fallback copy.
String doraMessage(BuildContext context, String message) {
  if (!context.strings.isEnglish) return message;
  const messages = <String, String>{
    '请检查网络后重试': 'Check your connection and try again.',
    '创建失败，请重试': 'Could not create the member. Try again.',
    '登录失败，请检查账号信息': 'Sign in failed. Check your account details.',
    '保存失败，请重试': 'Could not save. Try again.',
    '取消失败，请重试': 'Could not cancel. Try again.',
    '房间名称须为 1–30 个字符': 'Room names must be 1–30 characters.',
    '请输入管理员用户名和密码': 'Enter an admin username and password.',
    '请填写取消原因': 'Enter a cancellation reason.',
    '对局已取消': 'Game cancelled.',
    '点数已保存': 'Score saved.',
    '成绩已更正': 'Scores corrected.',
    '请先选择成员身份': 'Choose a member identity first.',
    '房间不存在': 'Room no longer exists.',
    '对局不存在': 'Game no longer exists.',
    '仅创建者或管理员可以操作': 'Only the creator or an admin can do this.',
    '只能填写自己的点数': 'You can only enter your own score.',
    '该成员未参与本场对局': 'That member is not part of this game.',
    '请填写本场全部四人的点数': 'Enter scores for all four players.',
    '点数必须是 100 的倍数': 'Scores must be multiples of 100.',
    '点数超出可保存范围': 'That score is outside the allowed range.',
    '请输入整数点数，例如 25000 或 -1500': 'Enter a whole number, such as 25000 or -1500.',
    '服务器返回的数据格式无效': 'The club returned an invalid response.',
    '网络请求失败，请稍后重试': 'The request failed. Try again later.',
    '网络连接失败，请重试': 'The network connection failed. Try again.',
    '管理员用户名或密码不正确': 'The admin username or password is incorrect.',
    '管理员登录失败，请检查账号和密码':
        'Admin sign in failed. Check the username and password.',
    '操作失败，请稍后重试': 'The operation failed. Try again later.',
    '这个名字已存在，请搜索并选择': 'That name already exists. Search and select it.',
    '成员不存在，请重新搜索': 'Member not found. Search again.',
    '这个座位已有人入座': 'That seat is already taken.',
    '客户端会话无效': 'The app session is invalid. Reopen the app and try again.',
    '座位操作已取消，请重试': 'The seating request was cancelled. Please try again.',
    '有成员座位已失效，请刷新房间后重试':
        'A member is no longer seated. Refresh the room and try again.',
    '本地演示离座记录无效': 'The saved local seat departure data is invalid.',
    '玩家已移除': 'Player removed.',
    '请先完成或取消当前对局，再调整座位':
        'Finish or cancel the current game before changing seats.',
    '你已经入座，请先离开原座位': 'You already have a seat. Leave it first.',
    '只能离开自己的座位': 'You can only leave your own seat.',
    '只有在座成员可以开始对局': 'Only seated members can start a game.',
    '四位不同成员入座后才能开始': 'Four different members must be seated to start.',
    '只能取消未完成的对局': 'Only unfinished games can be cancelled.',
    '取消原因最多 500 个字符': 'Cancellation reasons can be at most 500 characters.',
    '仅管理员可以修改房间名称': 'Only admins can rename a room.',
    '活动至少需要一个房间': 'Select at least one room for the event.',
    '活动房间无效': 'The event contains an invalid room.',
    '活动房间不能重复': 'Each event room must be unique.',
    '活动包含不存在的房间': 'The event contains a room that no longer exists.',
    '活动名称长度须为 1–80 个字符': 'Event names must be 1–80 characters long.',
    '活动说明不能超过 2000 个字符': 'Event descriptions can be at most 2,000 characters.',
    '活动时间无效': 'Enter valid event times.',
    '活动结束时间必须晚于活动开始时间': 'The event must end after it starts.',
    '活动结束时间必须晚于开始时间': 'The event must end after it starts.',
    '活动 id 和版本必须同时提供': 'An event id and version must be provided together.',
    '活动 id 无效': 'The event id is invalid.',
    '活动版本无效': 'The event version is invalid.',
    '编辑活动需要活动 id': 'An event id is required when editing.',
    '修改活动需要提供当前版本': 'The current event version is required when editing.',
    '活动时间范围不能排除已关联的对局': 'The time range cannot exclude a linked game.',
    '活动房间范围不能排除已关联的对局': 'The room list cannot exclude a linked game.',
    '活动已被更新，请刷新后重试': 'The event changed. Refresh and try again.',
    '仅管理员可以管理活动': 'Only admins can manage events.',
    '活动不存在，请刷新后重试': 'The event no longer exists. Refresh and try again.',
    '只能选择当前进行中的活动': 'Only an active event can be selected.',
    '该活动不包含当前房间': 'This event does not include the current room.',
  };
  final exact = messages[message];
  if (exact != null) return exact;
  final catalog = englishFeedback(message);
  if (catalog != null) return catalog;
  final scoreTotal = RegExp(r'^当前合计 (.+)，必须为 100,000$').firstMatch(message);
  if (scoreTotal != null) {
    return 'Current total ${scoreTotal.group(1)}; it must be 100,000.';
  }
  return message;
}
