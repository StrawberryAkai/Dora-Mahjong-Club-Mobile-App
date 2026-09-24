/// Translates known application feedback without changing domain rules or data.
/// Member names, room names and user-written notes must not pass through here.
String? englishFeedback(String message) {
  final known = _feedback[message];
  if (known != null) return known;
  final total = RegExp(r'^当前合计 (-?[\d,]+)，必须为 100,000$').firstMatch(message);
  if (total != null) {
    return 'Current total: ${total[1]}. It must equal 100,000.';
  }
  final correction = RegExp(
    r'^四人合计必须为 100,000，当前为 (-?[\d,]+)$',
  ).firstMatch(message);
  if (correction != null) {
    return 'The four scores must total 100,000. Current total: ${correction[1]}.';
  }
  return null;
}

const _feedback = <String, String>{
  '活动已创建': 'Event created.',
  '活动已更新': 'Event updated.',
  '活动不存在，请刷新后重试': 'This event no longer exists. Refresh and try again.',
  '只能选择当前进行中的活动': 'Choose an event that is currently running.',
  '该活动不包含当前房间': 'This event does not include the current room.',
  '仅管理员可以管理活动': 'Only an admin can manage events.',
  '新建活动不能指定版本': 'The new event details are invalid. Try again.',
  '修改活动需要提供当前版本': 'Refresh this event before saving changes.',
  '活动已被更新，请刷新后重试': 'Someone else updated this event. Refresh and try again.',
  '活动至少需要一个房间': 'Choose at least one room for the event.',
  '活动房间无效': 'An event room is invalid.',
  '活动房间不能重复': 'Choose each room only once.',
  '活动包含不存在的房间': 'One of the selected rooms no longer exists.',
  '编辑活动需要活动 id': 'Choose an event to edit.',
  '活动时间范围不能排除已关联的对局':
      'The event dates must still include all games already linked to it.',
  '活动房间范围不能排除已关联的对局':
      'Keep every room that already has a game linked to this event.',
  '活动名称长度须为 1–80 个字符': 'Event names must contain 1–80 characters.',
  '活动说明不能超过 2000 个字符': 'Event descriptions can contain up to 2,000 characters.',
  '活动时间无效': 'Choose valid event dates and times.',
  '活动结束时间必须晚于开始时间': 'The event must end after its start time.',
  '活动 id 和版本必须同时提供': 'The event details are incomplete. Refresh and try again.',
  '活动 id 无效': 'The selected event is invalid.',
  '活动版本无效': 'The event version is invalid. Refresh and try again.',
  '活动已被其他人更新，请刷新后重试': 'Someone else updated this event. Refresh and try again.',
  '只有管理员可以管理活动': 'Only an admin can manage events.',
  '活动不存在': 'This event no longer exists.',
  '活动房间编号无效': 'An event room is invalid.',
  '活动名称须为 1–80 个字符': 'Event names must contain 1–80 characters.',
  '活动时间必须是有限时间': 'Choose valid event dates and times.',
  '新活动不能携带版本号': 'The new event details are invalid. Try again.',
  '更新活动必须携带版本号': 'Refresh this event before saving changes.',
  '活动房间范围不能移除已有对局':
      'Keep every room that already has a game linked to this event.',
  '活动时间范围不能移除已有对局':
      'The event dates must still include all games already linked to it.',
  '活动当前不在进行时间内': 'This event is not currently running.',
  '活动不包含所选房间': 'The selected room is not part of this event.',
  '对局开始后不能修改活动关联': 'A game’s event cannot change after it starts.',
  '活动功能尚未初始化，请先完成服务端迁移':
      'Events are not initialized. Ask an admin to complete the server migration.',
  '评分必须包含四位成员': 'Ratings require four players.',
  '成员 ID 不能为空': 'A player ID is missing.',
  '成员 ID 不能重复': 'Each player must have a different member ID.',
  'MMR 必须是有限数值': 'MMR must be a finite number.',
  '点数合计必须为 100,000': 'The four scores must total 100,000.',
  '马点参数必须包含四个有限数值': 'The Uma settings must contain four finite values.',
  '评分参数无效': 'The rating settings are invalid.',
  '无法计算有效的顺位概率': 'The rank probabilities could not be calculated.',
  '缺少成员评分状态': 'A player’s rating is missing. Refresh and try again.',
  '更正的对局缺少评分记录': 'This game’s rating record is missing.',
  '成员评分基线无效': 'The player’s rating baseline is invalid.',
  '更正影响了更早的评分记录':
      'Earlier rating history is inconsistent. Ask an admin to check the records.',
  '请求缺少幂等指纹': 'The request is incomplete. Refresh and try again.',
  '历史对局缺少原始点数，无法更正':
      'This game is missing its original scores and cannot be corrected.',
  '成绩必须是整数且不能为 null': 'Enter a whole-number score for every player.',
  '更正成绩包含无效成员或成绩': 'Check the players and corrected scores.',
  '评级控制状态缺失': 'Ratings are not initialized. Ask an admin to check the setup.',
  '评级结算顺序状态无效':
      'The rating order is invalid. Ask an admin to check the records.',
  '评级结算数据无效': 'The rating settlement is invalid.',
  '评级结算必须包含四位成员': 'A rating settlement requires four players.',
  '评级基线可信状态缺失': 'The trusted rating baseline is missing.',
  '发现不受支持的既有 MMR 状态，请先完成基线迁移':
      'Existing MMR data needs an approved baseline migration.',
  '当前 MMR 与不可变评级历史不一致，请先完成基线迁移':
      'Current MMR does not match the rating history. Ask an admin to review the baseline.',
  '评级历史中找不到待更正对局': 'This game is missing from the rating history.',
  '评级历史包含未知规则版本': 'The rating history uses an unsupported rule version.',
  '评级结算顺序不唯一': 'The rating order contains duplicate entries.',
  '评级历史对局成员数量无效': 'A game in the rating history has an invalid player count.',
  '更正点之前的评级历史不一致，请先完成审核迁移':
      'Earlier rating history is inconsistent. Ask an admin to review it before correcting this game.',
  '评级结果包含未知成员': 'The rating results contain an unknown player.',
  '评级必须包含四位成员': 'Ratings require four players.',
  '评级成员不能为空': 'A player ID is missing.',
  '评级成员必须互不相同': 'Each player must have a different member ID.',
  '四人成绩合计必须为 100,000': 'The four scores must total 100,000.',
  '评级概率计算失败': 'The rating probabilities could not be calculated.',
  '评级结果不是有限数值': 'The rating calculation produced an invalid value.',
  '积分功能尚未初始化，请先完成服务端迁移':
      'Ratings are not initialized. Ask an admin to complete the server migration.',
  '创建失败，请重试': 'Unable to create the member. Try again.',
  '本场对局已不存在，请返回刷新。': 'This game no longer exists. Go back and refresh.',
  '已刷新本场版本，输入已保留，请再次保存。':
      'The latest game is loaded. Your draft is kept; save again to submit it.',
  '已刷新本场版本，保留你当前的更正输入，请再次保存。':
      'The latest game is loaded. Your corrections are kept; save again to submit them.',
  '已刷新本场版本，取消原因已保留，请再次确认。':
      'The latest game is loaded. Your cancellation reason is kept; confirm again.',
  '姓名长度须为 1–20 个字符': 'Names must contain 1–20 characters.',
  '仅支持中文和英文字母，不含数字、空格或符号':
      'Use Chinese characters or English letters, without numbers, spaces or symbols.',
  '姓名须为 1–20 个中文或英文字母，不能含数字、空格或符号':
      'Use 1–20 Chinese characters or English letters, without numbers, spaces or symbols.',
  '请输入整数点数，例如 25000 或 -1500':
      'Enter a whole-number score, such as 25000 or -1500.',
  '点数超出可保存范围': 'This score is outside the supported range.',
  '点数必须是 100 的倍数': 'Scores must be multiples of 100.',
  '请填写全部四位成员的点数': 'Enter scores for all four players.',
  '请填写本场全部四人的点数': 'Enter scores for all four players in this game.',
  '暂时无法保存或获取数据，请检查网络后重试':
      'Unable to save or load data. Check your connection and try again.',
  '操作已保存，但页面刷新失败。请刷新查看最新状态':
      'Your change was saved, but the page could not refresh. Refresh to see the latest state.',
  '成员已创建': 'Member created.',
  '身份已切换': 'Member switched.',
  '已进入管理': 'Signed in as admin.',
  '已退出当前身份': 'Signed out.',
  '已入座': 'Seat joined.',
  '已离座': 'Seat left.',
  '对局已开始': 'Game started.',
  '点数已保存': 'Score saved.',
  '成绩已更正，修改记录已保留': 'Scores corrected and change log saved.',
  '对局已取消': 'Game cancelled.',
  '房间名称已更新': 'Room name updated.',
  '重复请求内容不一致，请刷新后重试': 'Refresh before trying this change again.',
  '请先选择成员身份': 'Choose a member first.',
  '请先选择成员': 'Choose a member first.',
  '房间不存在': 'This room no longer exists.',
  '对局不存在': 'This game no longer exists.',
  '仅创建者或管理员可以操作': 'Only the game creator or an admin can do this.',
  '请先完成或取消当前对局，再调整座位':
      'Finish or cancel the current game before changing seats.',
  '对局已被更新，请刷新后重试；已输入的点数会保留':
      'The game has changed. Refresh and try again; your draft score will be kept.',
  '对局已被其他人更新，请刷新后重试': 'Someone else updated the game. Refresh and try again.',
  '这个名字已存在，请搜索并选择':
      'This name already exists. Search for it and select the member.',
  '姓名已存在': 'This name already exists.',
  '成员不存在，请重新搜索': 'This member no longer exists. Search again.',
  '成员不存在': 'This member no longer exists.',
  '当前为本地演示，请使用“体验管理员”入口': 'This is a local demo. Use the demo admin option.',
  '这个座位已有人入座': 'This seat is already occupied.',
  '该座位已被占用': 'This seat is already occupied.',
  '你已经入座，请先离开原座位': 'Leave your current seat before joining another.',
  '只能离开自己的座位': 'You can only leave your own seat.',
  '普通成员只能离开自己的座位': 'Members can only leave their own seat.',
  '只有在座成员可以开始对局': 'Only a seated member can start the game.',
  '四位不同成员入座后才能开始': 'Four different members must be seated to start.',
  '需要四位成员入座后才能开始': 'Four members must be seated to start.',
  '对局已结束，请刷新查看；修改成绩请使用更正功能':
      'This game has ended. Refresh to view it, or use score correction to make changes.',
  '该对局已经结束，需使用更正流程':
      'This game has ended. Use score correction to make changes.',
  '只能填写自己的点数': 'You can only enter your own score.',
  '该成员未参与本场对局': 'This member is not a player in this game.',
  '该成员不在本场对局中': 'This member is not a player in this game.',
  '没有代填该成员成绩的权限': 'You cannot enter a score for this member.',
  '只有已完成对局可以更正成绩': 'Only completed games can have scores corrected.',
  '只有已完成对局可以更正': 'Only completed games can have scores corrected.',
  '只能取消未完成的对局': 'Only unfinished games can be cancelled.',
  '只有进行中的对局可以取消': 'Only games in progress can be cancelled.',
  '请填写取消原因': 'Enter a cancellation reason.',
  '取消原因最多 500 个字符': 'The reason must be no longer than 500 characters.',
  '取消原因不能为空，长度不能超过 500 个字符': 'Enter a reason of no more than 500 characters.',
  '仅管理员可以修改房间名称': 'Only an admin can rename rooms.',
  '只有管理员可以修改房间名称': 'Only an admin can rename rooms.',
  '房间名称须为 1–30 个字符': 'Room names must contain 1–30 characters.',
  '房间名称不能为空，长度不能超过 30 个字符': 'Enter a room name of 1–30 characters.',
  '服务器返回的数据格式无效': 'The club data could not be read. Try refreshing.',
  '管理员用户名须为 3–32 位小写字母、数字、下划线或短横线':
      'Admin usernames must be 3–32 lowercase letters, digits, underscores or hyphens.',
  '请输入管理员密码': 'Enter the admin password.',
  '无法建立成员会话，请检查网络或开启匿名登录':
      'Unable to sign in. Check your connection or ask an admin to enable member access.',
  '当前登录账号不受支持，请退出后使用管理员或成员身份':
      'This account is unsupported. Sign out and choose a member or admin account.',
  '操作失败，请稍后重试': 'The action failed. Try again shortly.',
  '网络请求失败，请稍后重试': 'Unable to connect. Try again shortly.',
  '网络连接失败，请重试': 'Connection failed. Try again.',
  '管理员用户名或密码不正确': 'Incorrect admin username or password.',
  '管理员登录失败，请检查账号和密码': 'Admin sign-in failed. Check your username and password.',
  '请先登录': 'Sign in first.',
  '此账号不是俱乐部管理员，请退出后使用成员身份':
      'This account is not an admin. Sign out and choose a member.',
  '管理员账号不占座，请先使用普通成员身份':
      'Admin accounts cannot take a seat. Choose a member first.',
  '管理员请使用独立账号': 'Use the separate admin sign-in.',
  '此账号不能使用普通成员流程': 'This account cannot be used as a member.',
  '找不到操作人身份': 'Your identity could not be found. Sign in again.',
  '无效的座位': 'This seat is not valid.',
  '请求编号不能为空': 'The change could not be submitted. Refresh and try again.',
  '请求编号已用于其他操作': 'Refresh before submitting this change again.',
  '此账号不能选择普通成员': 'Sign out before choosing a member.',
  '管理员请直接退出管理员账号': 'Sign out of the admin account first.',
  '对局进行中，暂不能调整座位': 'Seats cannot change while a game is in progress.',
  '同一成员不能同时坐在两个房间': 'A member can only take one seat at a time.',
  '对局进行中，暂不能离座': 'You cannot leave a seat while a game is in progress.',
  '管理员清理座位时必须指定成员': 'Choose the member whose seat you want to clear.',
  '此账号不能操作座位': 'This account cannot change seats.',
  '该房间已有进行中的对局': 'This room already has a game in progress.',
  '更正成绩格式无效': 'The corrected scores are not valid. Check the entries.',
  '只有本场创建者或管理员可以更正成绩': 'Only the game creator or an admin can correct scores.',
  '请一次提交本场四位成员的成绩': 'Save all four players’ scores together.',
  '更正成绩包含无效成员': 'A selected player is not valid for this game.',
  '成绩必须是整数': 'Scores must be whole numbers.',
  '更正成绩包含非本场成员': 'Only players in this game can have scores corrected.',
  '更正后四人成绩合计必须为 100,000': 'The four corrected scores must total 100,000.',
  '只有本场创建者或管理员可以取消对局':
      'Only the game creator or an admin can cancel this game.',
};
