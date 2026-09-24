# 开发维护指南

本文帮助接手的开发者找到业务入口，并说明修改时需要保留的约束。配置与产品说明见 [README](README.md)。代码统一使用英文注释，重点解释设计原因；实际行为以当前实现和测试为准。

## 从哪里开始读

| 路径 | 职责与阅读重点 |
| --- | --- |
| `lib/main.dart` | 读取 `.env`、选择仓库、恢复设备偏好、注册前后台与关闭回调 |
| `lib/application/club_controller.dart` | 页面操作入口、共享快照、提交状态、重试标识、轮询与心跳 |
| `lib/data/club_repository.dart` | 本地与 Supabase 共用的业务接口 |
| `lib/data/demo_club_repository.dart` | 本地快照持久化、校验、结算和历史重放 |
| `lib/data/supabase_club_repository.dart` | 身份会话、RPC 调用、快照解析、座位租约 |
| `lib/domain/models.dart` | `memberId`、对局、活动、结算修订与快照的数据结构 |
| `lib/domain/rules.dart` / `rating.dart` | 姓名与点数校验、场内展示名次、纯函数 PT/MMR 计算 |
| `lib/domain/leaderboard.dart` / `game_result_summary.dart` | 总榜与活动榜口径、对局积分与排名变化的展示数据 |
| `lib/application/leaderboard_browser.dart` | 搜索、分批展示、当前成员定位所需的数据范围 |
| `lib/presentation/dora_app.dart` | 主题、登录、房间、录分、更正、个人页和通用组件 |
| `lib/presentation/leaderboard_page.dart` / `event_pages.dart` | 排行榜滚动与活动页面 |
| `lib/application/app_preferences.dart` / `lib/presentation/localization.dart` | 设备语言/主题偏好与界面翻译；后端错误翻译另见 `lib/l10n/feedback_messages.dart` |
| `lib/platform/app_exit*.dart` | 平台条件导出；Web 使用 `pagehide` 和尽力发送的关闭请求 |
| `supabase/migrations/` | 数据库约束、权限、事务和 RPC 的迁移记录 |

## 一次操作怎样同步

页面持有输入草稿 → 调用 `ClubController` → 调用 `ClubRepository` → 写入成功后重新 `load()` → 更新 `snapshot` 并通知页面。

- `local` 使用 `DemoClubRepository`，数据存在本设备的 SharedPreferences；保留 `dora.demo.v1` 这个旧键是为了兼容已有演示数据。不会自动上传到数据库。
- `development` 使用 Supabase。客户端调用业务 RPC，不直接写表；`club_snapshot` 返回页面所需的快照。前台每 5 秒轮询刷新，目前没有 Supabase Realtime 订阅。
- `busy` 防止本客户端同时提交；`_revision` 防止早先发起的刷新覆盖后来的操作结果。它们不能替代服务端锁和版本检查。
- `expectedVersion` 用于识别过期编辑；`requestId` 用于识别同一次重试。请求键包含操作内容及相关版本；失败保留 UUID，成功后移除。这个映射仅在内存中，不是跨重启的待发送队列。
- 保存成功、刷新失败时，数据可能已经落库。界面会明确提示这一状态，不能直接当作“未保存”。

普通成员通过匿名 Supabase 会话选择成员身份；这不是证明姓名所有权的密码登录。管理员使用独立认证入口，权限由服务端判断。`.env` 会打包到客户端，只能包含公开配置，不能放管理员密码或高权限密钥。

## 不能误改的业务规则

### 点数、马点与 MMR

- `score == null` 是等待录入，`score == 0` 是有效成绩。非法值不能默认为零。
- 四个不同 `memberId`，每人点数为 100 的倍数；齐全且总和为 100000 才能完成并结算。零分和负分允许。
- `rankPlayers` 的座位顺序只决定场内展示名次。实际 Uma 按点数同分组平分占用顺位的马点，不能用展示名次代入。
- PT 是 `(finalPoints - 25000) / 1000 + actualUma`。MMR 表现值的点数差权重为 0.4，不能用 `PT - expectedUma` 替换。
- MMR 四人使用同一组旧值，先调整正负表现倍率，再中心化，再计算对手倍率。最终变化总和不要求为零，不能再次归零。只在显示时格式化小数。
- 关联使用 `memberId`，不要使用姓名。结算保存规则版本、顺序和计算前后 MMR；旧的无结算对局不能因显示页面而自动补算。

正式模式的权威结算在服务端事务中完成，必须一起保存对局状态、积分明细和成员 MMR。本地纯函数用于演示与验证，不能成为客户端直接覆盖服务端余额的依据。

更正历史会影响后续场次的旧 MMR，包括后来与相关成员交手的其他人。需要从可信基线按固定结算顺序重放，保留旧修订；不能简单从当前余额扣回旧变化再加新变化。总榜累计 PT 为导入基线加上导入后各场当前有效结算；旧修订用于审计而不能重复累计。活动 PT 不包含导入基线。

### 座位与退出

空位可直接入座或换座；点击自己离座，点击其他人可打开移除菜单。对局开始后锁定座位。弹窗打开期间其他设备可能开局，所以点击确认时仍须检查最新状态，服务端也必须校验。

普通成员退出时，空闲座位释放；进行中的对局保留座位，结束或取消后再清理离线成员。客户端每 15 秒续期，服务端租约有效期 60 秒。后台停止续期，短暂 `inactive` 不停止。

关闭页面的请求只是尽力发送，强制结束进程可能没有回调。租约超时由后续快照刷新、心跳或入座等触发清理，并非一个独立定时任务。租约绑定客户端标识，旧客户端不能释放新客户端拥有的座位。本地模式用持久化的待离座状态处理重启。

### 排行榜与活动

总榜先根据完整数据排名，再搜索和分页，因此搜索结果保留真实名次。同分使用连续并列排名，例如 `40、40、40、41`；姓名或 ID 的稳定排列不应改变名次。

目前每批 50 人是客户端展示分页，网络仍获取完整快照。按需绘制条目减少渲染量，但不减少快照下载量。定位“我”时会先展开到本人所在批次，再滚动到对应行。

活动榜仅统计关联活动的已完成、已结算对局，使用 PT 排名。活动归属来自对局的 `eventId`，不能通过当前活动时间重新猜测。编辑活动不能排除已经关联的对局，时间范围按开局时间的 `[开始, 结束)` 校验。

## 常见修改入口

- 产品名称为 `Dora Helper`；社团中文名为 `UCSD 麻将社`，英文名为 `Dora Mahjong Club`。产品名用于系统应用名称和网页标题，社团名称用于页面品牌与徽标说明。
- 首版 `0.1.0.1` 在 `pubspec.yaml` 使用 `0.1.0+1`，分别映射为版本 `0.1.0` 和构建号 `1`。后续上传递增构建号，避免重复使用。
- Android 发布标识为 `dora.dora_mahjong`；iOS 为 `dora.doraMahjong`，测试目标追加 `.RunnerTests`。Android 的内部 namespace/Kotlin 包名独立于发布标识，保留现有值即可。Dart 包名、偏好存储键和管理员邮箱后缀也不随产品显示名更改。

- 登录图片：`dora_app.dart` 的 `_MemberEntryPage`，资源为 `assets/images/club_logo.png`，在 `pubspec.yaml` 注册。原图带透明留白，图片组件的尺寸不完全等于可见图案的尺寸。
- 登录图片和语言按钮位于滚动区域外的同一个 `Row`，通过 `crossAxisAlignment.center` 垂直居中。
- 创建成员示例：`_CreateMemberSheet` 的 `hintText`。中英文通过 `strings.text(中文, 英文)` 一起维护。
- 录分冲突：`_ScoreEditorSheetState` 保留输入，刷新对局版本后需要用户再次保存。不要让自动刷新覆盖输入草稿。
- 语言和主题是设备偏好，与当前成员无关；切换身份不应重置。

## 本地检查与预览（Git Bash）

```bash
cd "/d/Self Project/Dora-Mahjong-Club-Mobile-App"
./.tools/flutter/bin/cache/dart-sdk/bin/dart.exe analyze lib
./.tools/flutter/bin/flutter.bat test --no-pub
./.tools/flutter/bin/flutter.bat build web --no-pub --no-wasm-dry-run --optimization-level=1
node tool/serve_preview.mjs 8766
```

打开 `http://127.0.0.1:8766/`。预览脚本只提供 `build/web` 静态文件，不会自动编译；代码、资源或 `.env` 修改后需重新构建并刷新。脚本本身不连数据库，但构建后的 development 应用会连接配置的 Supabase。

出现 `EADDRINUSE` 表示端口已有进程监听，可使用已有预览或改为 `node tool/serve_preview.mjs 8767`。本项目的 Dart/Flutter 测试用于本地逻辑和界面验证；不要把操作真实 Supabase 数据当成普通 UI 验证步骤。

## 数据库与版本交接

不要把仓库里的初始化 SQL 当成当前线上数据库的完整镜像。项目曾适配导入的 `players` 数据及自定义 `club_snapshot`；接手时应核对目标项目实际 schema、RPC 和已应用迁移，不要直接重跑初始化覆盖已有数据。本文不证明任何目标环境的迁移状态。

`.gitignore` 保留 `supabase/` 中的迁移和脚本、`test/`、`docs/`，供开发者共同维护；只排除缓存、构建结果、本机配置及数据库备份等本地文件。`pubspec.lock`、`.metadata`、平台工程和资源也应提交。真实 `.env` 与签名文件不提交，使用 `.env.example` 说明所需配置。交接前检查 `git status`，确保需要的文件已经纳入版本管理。
