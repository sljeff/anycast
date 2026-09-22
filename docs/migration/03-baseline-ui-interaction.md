# 基线盘点 03：UI / 导航 / 手势 / 动画（操作逻辑一致性的事实来源）

> 用途：iOS 原生化迁移的 UI 行为回归测试（人工清单 + 快照基线）设计输入。迁移要求：**操作逻辑与 UI 一致（包含拖拽等交互）**。

## 0. 总览

- 入口：`lib/main.dart` — `GetMaterialApp`，全局**仅暗色主题**（`ThemeData(brightness: Brightness.dark)`，main.dart:92-143），锁定竖屏（main.dart:32-35，iOS Info.plist 实际还声明了横屏，以 Dart 层为准）。状态管理全部使用 GetX（`Get.put` / `Obx`），本地存储 sqflite，播放 just_audio + audio_service。
- 三个主 Tab（`IndexedStack`，main.dart:144-156）+ 常驻底部 `BottomNavBar`（内含 mini player）。**没有使用 Navigator.push 的普通页面栈**——几乎所有二级界面都是 modal bottom sheet（`modal_bottom_sheet` 包的 `showMaterialModalBottomSheet`），少数用 `Get.dialog` 弹 AlertDialog。
- **没有任何 Hero 动画 / 共享元素过渡**（全局 grep `Hero(` 零结果）。mini player → 全屏播放器是“打开一个全高 modal sheet”，非形变过渡。

---

## 1. 导航结构

### 1.1 顶层结构
- `main.dart:144-156`：`Scaffold(body: Obx(IndexedStack(index: homeTabController.selectedIndex, children: [PodcastsPage, Playlists, Discover])), bottomNavigationBar: BottomNavBar())`。`HomeTabController`（states/tab.dart:3-9）只有一个 `selectedIndex`。
- `BottomNavBar`（widgets/bottom_nav_bar.dart:15-74）= 垂直 Column：`PlayerBar`（mini player，详见 §2.9）+ 96px 高的 3 个 `BarIcon`（Podcast `Icons.home_rounded` / Playlist `Icons.video_library_rounded` / Discover `MdiIcons.cloudSearch`，bottom_nav_bar.dart:51-67）。选中色 `0xFF6EE7B7`，未选中 `0xFF6B7280`。
- **再次点击 Tab 0 的行为**（bottom_nav_bar.dart:263-276）：条件只判断主 Tab `index == 0 && selectedIndex == 0`，**不判断 PodcastsPage 内层是 Inbox 还是 Subscriptions**（2026-09-22 核验更正原表述——在 Subscriptions 子页时重复点 Tab0 仍会对不可见的 Inbox 列表回顶/刷新）；列表滚动位置 ≠ 0 则 `animateTo(0, 300ms, easeInOut)` 回顶；已在顶部（或无 client）则直接触发 `refreshController.callRefresh()` 强制刷新。这是 iOS 迁移需要保留的 "tap-to-top" 逻辑（类似 UITabBar 原生行为）。
- 每个 Tab 内部又用 `DefaultTabController + TabBar + TabBarView`（二级 tab）。

### 1.2 页面栈与 push/pop 关系
没有 `Navigator.push`。层级全部通过 modal sheet 叠加，可多层嵌套（sheet 里再开 sheet）：

```
Root(IndexedStack)
├─ Tab0 PodcastsPage
│   ├─ TabBar: Inbox=Feeds / Subscriptions
│   │   ├─ [卡片封面点按] → Detail sheet (标准 showModalBottomSheet + DraggableScrollableSheet)
│   │   └─ [PodcastCard 点按] → Channel sheet (showMaterialModalBottomSheet expand)
│   │         └─ [Channel 内搜索提交] → ChannelSearch sheet（嵌套 sheet）
│   │         └─ [卡片→频道跳转] → 再开一层 Channel sheet
├─ Tab1 Playlists（每个播放列表一个 Tab）
│   └─ [历史弹窗等 Get.dialog]
├─ Tab2 Discover
│   ├─ TabBar: 分类列表
│   └─ [搜索提交] → SearchPage sheet
├─ AppBar 右上齿轮 → SettingsPage sheet
│   └─ [Account] → LoginPage sheet（嵌套）
│         └─ [Email 登录] → EmailLogin sheet（再嵌套，未设 expand）
├─ mini PlayerBar（点按/上拉）→ PlayerPage sheet（全屏）
│   ├─ PageView 三页（设置/主控/AI 字幕）横向滑动
│   ├─ [字幕页 AI 聊天] → ChatPage sheet（嵌套在 PlayerPage 内）
│   └─ [TitleBar 频道图/频道名点按] → Channel sheet（嵌套）
└─ 分享接收（receive_sharing_intent）→ ShareDialog (Get.dialog)
```

### 1.3 modal bottom sheet 清单（回归测试重点）

`showMaterialModalBottomSheet`（modal_bottom_sheet 包，拖拽把手关闭）：

| # | 位置 | 内容 | expand | closeProgressThreshold | 备注 |
|---|------|------|--------|------------------------|------|
| 1 | bottom_nav_bar.dart:102-107 / 111-116 | `PlayerPage` 全屏播放器 | true | 0.9 | 点按或**任意垂直拖动**触发 |
| 2 | card.dart:334-341 | `Channel` 频道页 | true | 0.9 | PodcastCard 点击 |
| 3 | detail.dart:123-130 | `Channel` | true | 0.9 | Detail 内点频道名 |
| 4 | player.dart:405-410 (`jumpToChannel`) | `Channel` | true | 0.9 | 播放器点封面/频道名 |
| 5 | appbar.dart:26-33 | `SettingsPage` | true | 0.9 | AppBar 齿轮 |
| 6 | appbar.dart:101-106 | `SearchPage`（全局搜索） | true | **0.8** | 搜索提交，阈值不同 |
| 7 | settings.dart:113-120 | `LoginPage` | true | 0.9 | |
| 8 | channel.dart:649-655 | `ChannelSearch` | true | 0.9 | 频道内搜索提交 |
| 9 | player.dart:903-909 | `ChatPage` AI 聊天 | true | 0.9 | 字幕页右下角 AI 按钮 |
| 10 | login.dart:135-139 | `EmailLogin` | **未设（非全屏）** | 默认 | |

标准 `showModalBottomSheet`（Material 原生，`useSafeArea: true, isScrollControlled: true`）：
- card.dart:131-137 → `Detail`（剧集详情，内部是 `DraggableScrollableSheet`，initialChildSize 0.7 / minChildSize 0.6，detail.dart:41-44）
- import_export.dart:49-56、feeds.dart:246-253 → `ImportInstructions`（也是 DraggableScrollableSheet 0.7/0.6，import_export.dart:271-274）
- playlists.dart:297-322 → 历史 item 点按开 `Detail`

`Get.bottomSheet`（GetX）：settings.dart:327-348 / 375-397 / 425-447 → `SettingsBottomContainer`（高 200，含 `CupertinoPicker`）。

**拖拽关闭行为**：`closeProgressThreshold: 0.9` 表示 sheet 需拖到 90% 高度才关闭（很“粘”）；SearchPage 是 0.8。iOS 迁移建议自定义 presentation（类似“near-full drag-to-dismiss”）。所有 sheet 顶部都有 42×6 圆角白色把手 `Handler`（widgets/handler.dart）。

### 1.4 Hero / 共享元素
无。播放器从 mini player 打开是普通 modal sheet 滑入，**背景无缩放暗化**，需要注意与 iOS 常见的做法（present page sheet）区分。

---

## 2. 逐页面清单

### 2.1 PodcastsPage（lib/pages/podcasts.dart）
- 用途：Tab0 容器。`MyAppBar(title: 'PODCAST')` + 2 个 Tab：**Inbox**（`FluentIcons.mail_inbox_all_24_filled`）→ `Feeds`；**Subscriptions**（`FluentIcons.library_24_filled`）→ `Subscriptions`（podcasts.dart:21-40）。TabBarView 外包 `KeepAliveWrapper` 保持滚动状态。
- 主题 TabBar 样式（main.dart:125-142）：选中 `0xFF6EE7B7`，indicator 按 label 宽，字号 12，comfortaa 字体。

### 2.2 MyAppBar / 全局 SearchBar（lib/widgets/appbar.dart）
- 结构（appbar.dart:17-75）：AppBar（全局 toolbarHeight 156，preferredSize 148）内 Column：右上 36×36 圆形设置按钮（`Icons.settings_rounded`，底色 `0xFF232830`，点按开 SettingsPage）；标题 `GradientText`（**自上而下 #059669 → 透明的渐变大字**，44px comfortaa w700 letterSpacing 4.4，simple_gradient_text 包）；下方 `SearchBar`。
- `SearchBar`（appbar.dart:81-182）：高 56 圆角 12 输入框，hint "Shows,Episodes,and more"，底色 `0xFF232830`，`Icons.search` 前缀。onChanged 更新 `searchText`（非空时右侧出现绿色 "Cancel" 文本按钮，点按清空并失焦）；onSubmitted 非空则打开 SearchPage sheet。onTapOutside 收起键盘。

### 2.3 Feeds（Inbox，lib/pages/feeds.dart:22-138）
- 布局：左右 24 padding + `EasyRefresh` 包裹的 `ListView.separated`（间距 12，底部 padding 64 避开 mini player）。
- 下拉刷新（**easy_refresh 配置**，feeds.dart:31-61）：`onRefresh` → `fetchNewEpisodes()` 拉全部订阅 RSS；`refreshOnStart: true`（进入即自动刷新一次）；header 是 `BezierHeader(clamping: false, triggerOffset: 1, spinInCenter: true)`，spinner 区域是一条**随进度增长的 LinearProgressIndicator**（绿色，高 1px，progress 来自 `controller.progress.value`，feeds.dart:48-57）。**无上拉加载**（无 footer、无 onLoad）。
- 自动刷新：FeedEpisodeController 每 `autoRefreshInterval` 分钟（**DB 默认 300s**；Rx 初值 180 属首启竞态，口径以 DB 为准——《01》§2 裁定）触发 `callRefresh`（states/feed_episode.dart:110-132），启动后 2 秒也自动刷一次；每分钟裁剪 Inbox/History 超量条目（states/player.dart:344-349）。
- 每个 item 是 `Card`（见 §2.11），展开后的 3 个圆形白底操作按钮（feeds.dart:84-131）：
  1. 播放（`Ic.round_play_arrow`）：加入播放列表顶部 → 从 Inbox 移除 → 播放；
  2. 加入播放列表（`Ic.round_playlist_add`）：先播放 **AnimatedPlaylistIndicator 飞入动画**（加号按钮 → 底部 Playlist tab 图标，600ms，黑底圆角矩形从 200×48 缩到 24×24 淡出，widgets/animation.dart:3-88），再入列表并从 Inbox 移除；
  3. 移除（`Ic.round_clear`）。
- 空态（feeds.dart:140-267 `ImportBlock`）："It's empty here. Let's change that!" 大字 + 绿色 Explore 按钮（跳 Tab2）+ 白描边 "Import OPML" 按钮（`Get.dialog(ImportExportBlock)`）+ 圆形 `Ic.round_help` 帮助按钮（开 ImportInstructions sheet）。

### 2.4 Subscriptions（lib/pages/subscriptions.dart）
- `PodcastCard` 列表（ListView.separated，间距 12）。点击任意卡 → `Channel` sheet（card.dart:330-342）。
- 空态："Whoops! Looks like your podcast galaxy is still unexplored."（subscriptions.dart:15-32）。

### 2.5 Playlists（Tab1，lib/pages/playlists.dart:24-59）
- 每个播放列表一个 Tab（DefaultTabController length = playlists.length，实际数据里通常 1 个默认列表），TabBarView 内容是 `PlaylistEpisodesList`。
- `PlaylistEpisodesList`（playlists.dart:61-238）：
  - **核心：`ReorderableListView.builder` 拖拽排序**（详见 §3.2）。
  - 每个 Card 的 3 个按钮（playlists.dart:170-228）：播放/暂停（`PlayIcon`，若正在播且 index==0 则暂停，否则 moveToTop + 播放）；AI 转写（`AIIcon`，四态：默认/processing(robot lottie)/succeeded(check)/failed，点击按状态发不同 snackbar）；移除（`Ic.round_clear`，index==0 时同时 `playerController.clear()`）。
  - 空态（playlists.dart:71-123）："All caught up? Explore new shows!" + 绿色 Explore 按钮（跳 Tab2）。
- `HistoryBlock`（playlists.dart:240-421，从设置页 `Get.dialog` 打开的 400×300 Dialog）：历史列表，每行 48×48 封面 + **Marquee 跑马灯标题**（blankSpace 72，startAfter 1s，playlists.dart:342-355）+ 绿色频道名 + 白色圆形删除按钮；点行开 Detail sheet；底部红色 "Clear All" 按钮。加载态 CircularProgressIndicator；空态绿色 AlertDialog "No history"。

### 2.6 Discover（Tab2，lib/pages/discover.dart:19-102）
- `listCategories()` FutureBuilder → 横向可滚动 TabBar（分类）+ TabBarView。每个分类页 `listChannelsByCategoryId(c.id, countryCode)` → `PodcastCard` ListView。
- 状态：加载中转圈；channels 空 → 居中白字 **"Network Error"**（discover.dart:73-78）。
- 分类页用 `KeepAliveWrapper + Obx`，切换国家后依赖 countryCode 响应式重建。
- `SearchPage`（discover.dart:104-313，modal sheet）：顶部 `Handler`（**点按关闭**）、"You are searching for" + 绿色关键词、2 个 Tab（Channels/Episodes）。Channels → PodcastCard 列表；Episodes → Card 列表，2 个按钮（播放 / 加列表，已在列表时图标变 `Ic.round_playlist_add_check`——**2026-09-22 核验更正：点击并非无效**，无守卫、无条件调 `addToPlaylist`，已存在时会把该集**移动到播放列表顶部附近**（states/playlist_episode.dart:38-42 的移动分支）；带 `if (inPlaylist) return` 守卫的只有频道页与频道搜索页（channel.dart:152-155、831-834）——三种卡的按钮语义分别断言，《05》§6.3）。空结果 "No results"；底部也挂 `PlayerBar`（**无 `bottomSafe`**，与 Channel/ChannelSearch 不同，2026-09-22 核验）。CardListController 是全局新 put 的（跨 tab 互斥展开）。

### 2.7 Channel（频道页，lib/pages/channel.dart:26-197，modal sheet）
- 布局：`CustomScrollView` + **pinned `SliverPersistentHeader`（ChannelHeaderDelegate）** 折叠头（channel.dart:248-541）：
  - minExtent = statusBar + 148；maxExtent = statusBar + 460。
  - 头部背景为 **palette 动态主色 → `0xFF111316` 的垂直渐变**（channel.dart:275-285）。
  - 展开态：Handler 把手 → 左返回（`Ic.round_arrow_back` 圆形 40×40 半透明白）+ 右侧 [订阅按钮 | 分享按钮] → 居中 120×120 圆角 16 封面 → 标题（20px comfortaa bold）→ 作者 → **RSS 域名文本（点按复制 + 1s snackbar）** → `ExpandableText` 描述（2 行截断，点击弹全文 AlertDialog，widgets/expandable_text.dart:32-72）→ 白底圆角 36 "Latest Episode" 播放按钮（184×40）。
  - 滚动折叠：封面随 shrinkOffset 从 120 缩到 60 并左移到 16；标题向左嵌入（padding `min(60+24, shrinkOffset)`）；作者/域名/描述/播放按钮在 shrinkOffset ≥ maxExtent/4 后整体 Opacity 淡出（channel.dart:423-536）——**这是一套纯手写的视差折叠头，iOS 迁移需逐项对齐**。
  - `SubscriptionButton`（channel.dart:543-620）：Loading(转圈)/Subscribe(半透明白底 `Ic.round_add_circle_outline`)/Unsubscribe(白底黑字 `Ic.round_clear`) 三态胶囊按钮（高 40，圆角 36）。
- body：频道内 `SearchBar`（hint "Search episodes"，提交开 ChannelSearch sheet）→ Newest/Oldest 排序切换（`OrderChooser`，选中白字 24px、**未选中灰 `0xFF6B7280`**（2026-09-22 核验更正）+ 选中下有 48×4 圆角白色指示条，channel.dart:199-246）→ 1px `0xFF232830` 分隔线 → 剧集 Card SliverList（播放 / 加列表按钮，逻辑同 §2.6）。bottomNavigationBar 挂 `PlayerBar(bottomSafe: true)`。
- 空列表转圈（channel.dart:113-116）；PopScope 关闭后 500ms 延迟删除 GetX controller。

### 2.8 ChatPage（AI 聊天，lib/pages/chat.dart + states/chat.dart）
- 从播放器字幕页打开的 modal sheet。AppBar：深紫底（`Colors.deepPurpleAccent`）、圆形黑底关闭 X、标题（episode 标题，2 行省略）、右侧垃圾桶清空。
- 主体是 **flutter_chat_ui 的 `Chat`**（chat.dart:60-75）：`InMemoryChatController`、`ChatTheme.dark()`、`onMessageSend`、`resolveUser`（'human'→You / 'ai'→AI）。**非流式**：发送后先插入 "..." 占位 AI 消息，`chatAPI` POST（api/subtitles.dart:101-121，带最近 10 条历史）返回后整条 `updateMessage` 替换（states/chat.dart:40-71）。isLoading 时禁止发送。PopScope 关闭即清空会话。未配置 markdown/typing indicator 等高级参数（均为库默认）。

### 2.9 PlayerBar（mini player，widgets/bottom_nav_bar.dart:76-241）
- 无播放内容时 `SizedBox.shrink`（86-88 行）。
- 高 58、左右 margin 12、圆角 16、白色 10% 底；内部 Stack：底层一条**按播放进度增长的白 20% 进度条背景**（宽度 = (屏宽-24)×pos%，91-98 行），上层 Row：36×36 圆角 8 封面 + 标题（16px w500 单行省略）+ 灰色 "已播/总时长"（`PlaylistEpisodeModel.getPlayedAndTotalTime`）+ 播放/暂停 `PlayIcon`(32) + `Remix.forward_30_fill`(32) 快进 30s。
- **手势**：整条 bar `onTap` 打开全屏播放器；`onVerticalDragUpdate`（任意方向任意位移即触发，无阈值判断）也打开全屏播放器（bottom_nav_bar.dart:100-117）。播放/快进按钮是内层独立 GestureDetector，不会冒泡打开全屏。

### 2.10 PlayerPage（全屏播放器，lib/pages/player.dart:40-87）★重点
- 结构：`PopScope`（关闭时 `pageIndex` 重置回 1，player.dart:45-50）→ 背景 **三层垂直渐变：palette 主色 → `0xFF111316` → `0xFF111316`**（52-61 行，主色来自封面 palette_generator）→ SafeArea → Column[`Handler` 把手, `PageView`(3 页，**可左右滑动切换**), `PageTab` 底部胶囊选择器]。
- `PageTab`（89-116 行）：高 56 圆角 36 胶囊（描边 `0xFF4B5563`，底 `0x19232830`），3 个 48×48 按钮（设置 `Ic.round_settings` / 主控 `Ic.round_podcasts` / AI `tablerTopology` 自定义 SVG）。选中态白底黑图标。点击 `animateToPage(300ms, easeInOut)`（1009-1021 行）。

**第 0 页 PlayerSettings（118-144 行）**：episode 描述 HTML（`renderHtml`）+ 底部 `Settings` 组件（1148-1372 行）：
- SPEED 滑条：0.5–2.0，divisions 6（步进 0.25），**thumb 是自绘 `CustomSliderThumbCircle`（半径 20 白圆内绘倍速数字）**，Stadium 胶囊底 `0xFF232830`（1084-1146、1194-1222 行）。
- COUNTDOWN 滑条：0–60 分钟，divisions 6（步进 10），label 用 `formatCountdown`（mm:ss / 1h / OFF），拖到 0 附近 `stopCountdown`（1225-1275 行）。
- SKIP SILENCE / CONTINUOUS PLAY 两个 Material Switch（FittedBox 放大，白 thumb），后者带点按 Tooltip（1277-1368 行）。
- `AutoSleepPicker`（1374-1514 行，三个 CupertinoPicker 选起止小时+倒计时）**已定义但当前未被引用**（疑似预留/废弃），可迁移时忽略或向作者确认。

**第 1 页 PlayerMain（146-235 行）**：
- 居中 `width-48` 见方圆角 8 封面；右下角 36×36 半透明黑圆钮 `Ic.round_ios_share` 分享（生成 anycast.website/player 短链 → `Get.dialog` 转圈 → 系统分享面板，175-224 行）。
- `TitleBar`（300-399 行）：64×64 圆角 12 频道图（**点击跳转 Channel sheet**，319-335 行）+ 标题（24px 'PingFang SC' w600；**当 `title.length×24 > 可用宽` 时换 `Marquee` 跑马灯**，pauseAfterRound 1s、blankSpace 40，350-357 行）+ 频道名（16px，颜色用 `getTextSafeColor(backgroundColor)`——palette 色太暗(luminance<0.2)时回退 `0xFF10B981`，formatters.dart:139-153；**也点击跳频道**）。
- `MyProgressBar`（413-460 行，audio_video_progress_bar）：进度条**时间标签在上方**、显示剩余时间（`TimeLabelType.remainingTime`）；thumb 白色半径 16 + 光晕 20（glow 黑 20%）；bar 高 40、圆头；已播白、缓存白 5%、底槽 `0xFF232830`；`onSeek → controller.seek`。
- `Controls`（1028-1082 行）：`Icons.replay_10`(48) / 中央 72×72 圆形 `0xFF10B981` 播放暂停钮（`PlayIcon`：加载中显示 lottie，播放中 `Ic.round_pause`，暂停 `Ic.round_play_arrow`）/ `Icons.forward_30`(48)。快退快进走 `seekByRelative(±10/30s)`。

**第 2 页 PlayerAI（237-298 行）**：圆角 8 描边容器；头部 60px（频道图 + 标题 12px comfortaa w700 两行省略）+ Divider → `Subtitles`。
- `Subtitles`（462-689 行）五态：
  1. **未生成**：居中提示 "Generate transcript with AI (Beta)" + 绿色圆形问号（点按 Tooltip 10s "AI transcript may take about 2 ~ 5 minutes"）+ 绿色大按钮（`newDoc` sparkle 图标）触发 `controller.add(url)`；
  2. **processing**：`Lottie robot_loading.json` + "Generating with AI ... / It may take 2 ~ 5 minutes ... / Feel free to explore or come back later."（后台每 15s 轮询，states/subtitle.dart:24-48）；
  3. **failed**：蓝色 Retry 按钮；
  4. **翻译中**：主歌词 + 底部 RefreshProgressIndicator "Translating subtitles..."（652-675 行）；
  5. **就绪**：`LyricsWithShare`（**双语**：`subtitle.toLrc()` 主 + `translation.toLrc()` 译文）。
- **flutter_lyric 用法（LyricsWithShare，691-948 行）**：
  - 逐**行**歌词（非逐字）：LRC 由 `[{start}]文本` + `[{end}]` 空行组成（models/subtitle.dart:101-116），翻译行内嵌在 `loadLyric(main, translationLyric:)`。
  - 样式（717-742 行）：主行 `GoogleFonts.mPlusRounded1c` 14px 灰[200]，**活动行 16px greenAccent**，译文行 14px greenAccent（活动译文灰[300]）；lineGap 12 / 译文 6；anchorPosition 0.5（当前行居中）；contentPadding top:100。
  - **滚动跟随**：`ever(positionData)` → `_lyricController.setProgress(position)`（771-773 行）；自动回位配置 `selectLineResumeMode: neverResume`（拖动后不自动回位）、`selectLineResumeDuration 300ms`、`activeLineResumeDuration 3000ms`。
  - **点击行 = 切换播放/暂停**：`setOnTapLineCallback` → `togglePlay()` 并在屏幕中央 Overlay 弹 `PlayPauseAnimation`（80×80 自绘 play/pause 形变 CustomPaint，200ms，widgets/animation.dart:90-175）500ms 后移除（754-768 行）。
  - **拖动选择横条**（813-883 行）：`SelectListenableBuilder`——拖动歌词时在拖动中心行显示一条 [mm:ss 白色 20px comfortaa 带阴影] — [白色 2px 横线] — [36×36 半透明白圆播放钮（点击 `stopSelection()` + `seek(state.duration)`）] 的横条。
  - 右下角黑 87% 圆角浮层（884-944 行）：绿色 AI 聊天图标（`aiChat` 自定义 SVG，点按开 ChatPage sheet）+ `Icons.more_vert_rounded` PopupMenu → "Export subtitles"（`Ic.baseline_offline_share`）→ 导出 `# 标题 - 频道` + LRC 正文 (+ Translation 段) 为 .txt 走系统分享（951-978 行）。
  - `AutomaticKeepAliveClientMixin` 保活。

### 2.11 Card（通用剧集卡，widgets/card.dart:30-297）
- 注释即规格（card.dart:1-8）：三种场景（Inbox/播放列表/频道页），播放列表卡有**播放进度背景条**。
- 布局：100 高圆角 20 描边（grey[800]）Row：80×80 圆角 16 封面（**点按开 Detail sheet**，129-154 行）+ 右侧标题（16px PingFang 单行）+ [频道名（maxWidth 114）| 右侧时长·时间文本] + 描述 HTML 转纯文本（12px 灰 `0xFF6B7280`，inter，2 行）。
- **整卡点按**：`clController.expand(index)` 切换底部 **AnimatedContainer 高 0↔60 的操作按钮条**（200ms easeInOut，279-291 行）；同组卡片互斥（一个 CardListController per 列表）。
- 播放列表卡：`pe.enclosureUrl == 当前播放` 时进度条宽度实时取 positionData（71-79 行），否则取 playedDuration/duration；右侧文本换 "xx remaining"。
- 右下角**下载指示**（仅播放列表卡，232-275 行）：未下载 = 16×16 蓝 70% 圆形 `Ic.round_download`（点按开始下载）；下载中 = `CircularPercentIndicator`(半径 8, 线宽 3, 蓝色)；完成 = 绿色 `IconParkSolid.check_one`。

### 2.12 PodcastCard（频道卡，card.dart:323-453）
圆角 20 描边行卡：64×64 圆角 12 封面 + 标题（14px comfortaa w700）+ 描述（12px PingFang 2 行）。整卡点按开 Channel sheet。

### 2.13 SettingsPage（lib/pages/settings.dart:86-492）
ListView 分组（`SettingsGroup` 圆角 12 底 `0xFF232830`）：
- Account（点按开 LoginPage）；
- Transcript & Translation：Country（CountryCodePicker，黑底圆角 12 弹窗、无搜索、无旗子）+ Enable Transcript Translation Switch + Target Language（开关开启后出现的缩进行，前缀 `Ph.arrow_elbow_down_right_bold`）；
- Podcast：Import / Export（Get.dialog ImportExportBlock）、History（Get.dialog HistoryBlock）；
- Other：Auto Refresh Interval（1/3/5/10/30 min，点按弹 Get.bottomSheet + CupertinoPicker）、Max Episodes in Inbox、Max Episodes in History（各 50/100/200/300）；
- Contact：mailto 链接；`Privacy`（Privacy Policy / EULA，`launchUrl inAppBrowserView`，widgets/privacy.dart）。
- 每项都有点按 2s 的 `Icons.info_outline` Tooltip 说明文案。

### 2.14 LoginPage（lib/pages/login.dart:17-169）
- 未登录：logo 100×100 + "Sign up now & Get 3 free audio transcriptions!" + 三个白底圆角 24 登录按钮：Sign in with Apple（`Ic.round_apple`）/ Google（`Ri.google_fill`）/ Email（黑 12% 底，开 EmailLogin sheet）。Apple/Google 点击有全屏转圈（login.dart:76-83、105-113）；**Email 无转圈**、直接开 sheet（login.dart:134-141，2026-09-22 核验更正"均有"）。
- 已登录：User Info 卡（头像图标 + email + PopupMenu：Copy email / Sign out（红字确认 AlertDialog））；订阅信息卡（Basic/Plus、剩余转写数、到期时间 Jiffy 格式化）；**Paywall**：`CarouselSlider` 两张介绍图（aspectRatio 2:1、viewportFraction 1、**autoPlay: true**，447-468 行）+ PlusIntro ExpansionTile（默认展开）+ 月/年套餐卡（点选变绿底）+ Confirm purchase / restore purchases；`RemoveAccount`（红色删号确认 AlertDialog）。
- EmailLogin（832-1010 行）：Email/Password 输入 + Login；"Register" 按钮实际弹“暂不支持注册”提示。

### 2.15 ImportExportBlock / ShareDialog
- ImportExportBlock（widgets/import_export.dart:22-264）：AlertDialog：Import（file_picker 选 OPML → ImportIndicator 确定值进度环 → 导入 → snackbar）/ Export（写 OPML 文件 → 系统分享）/ 手输 RSS URL 提交导入（错误时红字 AlertDialog "Invalid RSS Feed URL"）。右上 `Ic.round_help` 开 ImportInstructions（Castro/Overcast/Pocket Casts/小宇宙/其他 的 ExpansionTile 步骤说明，小宇宙条目为中文文案）。
- ShareDialog（widgets/share.dart）：接收外部分享的 OPML（receive_sharing_intent）→ 列出可导入频道 → Import（ImportProgressIndicator 进度环）。

---

## 3. 手势与交互清单（回归测试直接输入）

### 3.1 全部 GestureDetector 一览（含行为细节）

| 文件:行 | 组件/位置 | 手势 | 行为 |
|---|---|---|---|
| bottom_nav_bar.dart:100-108 | mini player 整条 | onTap | 打开全屏 PlayerPage sheet（expand, threshold 0.9） |
| bottom_nav_bar.dart:110-117 | mini player | onVerticalDragUpdate | **任何垂直位移立即**打开 PlayerPage（无方向/阈值判断，向下拖也会打开） |
| bottom_nav_bar.dart:191-207 | mini player 播放钮 | onTap | 播放/暂停 |
| bottom_nav_bar.dart:208-224 | mini player 快进钮 | onTap | seek(+30s) |
| bottom_nav_bar.dart:262-277 | BarIcon | onTap | 切 tab；Tab0 重复点击=回顶或刷新 |
| card.dart:109-112 | Card 卡身 | onTap | 展开/收起底部按钮条（AnimatedContainer 0↔60，200ms easeInOut），同列表互斥 |
| card.dart:129-138 | Card 封面 | onTap | 打开 Detail sheet（标准 Material sheet + DraggableScrollableSheet 0.7→0.6） |
| card.dart:242-260 | 下载小圆钮 | onTap | 开始下载（仅播放列表卡） |
| card.dart:330-342 | PodcastCard | onTap | 打开 Channel sheet |
| detail.dart:53-58 | Detail 顶部 Handler | onTap | 关闭 sheet |
| detail.dart:113-131 | Detail 频道名 | onTap | **不关闭 Detail**、直接在其上再叠一层 Channel sheet（**sheet 套 sheet**；2026-09-22 核验更正——§3.1 原"关闭当前"表述与 §1.2 树状图矛盾，以代码为准） |
| detail.dart:163-192 | Detail 分享钮 | onTap | 转圈→短链→系统分享 |
| expandable_text.dart:32-55 | ExpandableText | onTap | 超过 2 行时弹全文 AlertDialog（Scrollable+Scrollbar，右上白色关闭钮） |
| channel.dart:333-338 | 返回按钮 | onTap | Get.back + 清理 controller |
| channel.dart:359-394 | 分享按钮 | onTap | 分享频道短链 |
| channel.dart:442-453 | RSS 域名文本 | onTap | 复制到剪贴板 + 1s 黑底 snackbar "Copied" |
| channel.dart:605-617 | 订阅按钮 | onTap | subscribe/unsubscribe |
| channel.dart:702-719 | 频道内搜索 "Clear" | onTap | 清空输入 |
| player.dart:175-204 | 封面右下分享圆钮 | onTap | 生成短链分享 |
| player.dart:319-335 | TitleBar 频道图 | onTap | jumpToChannel（Channel sheet） |
| player.dart:376-392 | TitleBar 频道名 | onTap | 同上 |
| player.dart:859-877 | 歌词拖动条播放钮 | onTap | stopSelection + seek 到该行时间 |
| player.dart:900-911 | 歌词右下 AI 图标 | onTap | 打开 ChatPage sheet |
| player.dart:1009-1021 | PageTab 按钮 | onTap | PageView animateToPage 300ms easeInOut |
| appbar.dart:24-50 | 齿轮按钮 | onTap | 打开 SettingsPage sheet |
| appbar.dart:154-171 | 搜索 "Cancel" | onTap | 清空搜索框并失焦 |
| feeds.dart（ImportBlock 按钮）/ settings.dart:111-292（Account/Import/History/mailto）/ login.dart:545-760（restore/套餐卡/删号）/ privacy.dart:15-51（两个链接）/ playlists.dart:295（历史行） | onTap | 各自打开 sheet/dialog/链接 |

**长按**：仅播放列表拖拽（见 3.2）。**双击：无**。**侧滑删除（Dismissible）：无**——删除一律走展开按钮或独立按钮。**侧滑抽屉：无**。

### 3.2 播放列表拖拽排序（playlists.dart:134-239 + 423-439）★
- `ReorderableListView.builder`：`buildDefaultDragHandles: false`（无默认把手，**整卡作为拖拽热区**）；item 外包自定义 `MyReorderableDelayedDragStartListener(delay: 150ms)` → `DelayedMultiDragGestureRecognizer`：**长按 150ms 后即可拖动整张卡**（无视觉把手，长按即拖）。
- `onReorderStart`：先 `clController.close()` 收起展开按钮（136-138 行）。
- `proxyDecorator`（140-154 行）：拖拽浮起时 **scale 1→1.1（easeInOut）**。
- `onReorder: controller.move`（states/playlist_episode.dart:93-122）：from==0 或 to==0 时先 pause → sleep 100ms → `setByEpisode(episodes[0])`（正在播的集被拖走/新集拖到顶部时无缝切源）；`to > from` 时 `to -= 1`（ReorderableListView 语义）。
- item key = `episode.enclosureUrl`；底部 footer 12px；列表 padding top 12 / bottom 64。

### 3.3 下拉刷新 / 上拉加载
- 唯一的 easy_refresh 在 Feeds（§2.3）：BezierHeader、triggerOffset 1、clamping false、spinInCenter、进度条 spinner、refreshOnStart；**controlFinishRefresh: true** 手动 finishRefresh + resetFooter（states/feed_episode.dart:20-23，feeds.dart:32-36）。**无上拉加载**。
- 其余列表（Subscriptions、Channel、Discover、Search）均为普通 ListView，**无下拉刷新**。

### 3.4 DraggableScrollableSheet（详情/导入说明）
detail.dart:41-44、import_export.dart:271-274：initial 0.7 / min 0.6 / expand:false；内容 ScrollView 绑定 sheet 的 scrollController（先滚内容、到顶后联动缩 sheet）；顶部 Handler 可点关闭（Detail 有 onTap，ImportInstructions 的 Handler 无 onTap）。

### 3.5 其他滚动交互
- PlayerPage `PageView` 横滑三页（默认 physics），onPageChanged 更新 pageIndex；底部 PageTab 同步高亮（player.dart:69-79）。
- Podcasts/Playlists/Discover/SearchPage 的 TabBarView 横滑切 Tab。
- Discover 分类 TabBar `isScrollable: true`（可横滚）。
- Channel 折叠头随 CustomScrollView 滚动做 pinned 视差（§2.7）。
- 进度条/滑条：ProgressBar onSeek；两个 Slider（倍速/倒计时）带 divisions 离散刻度；CupertinoPicker 滚轮（设置页×3、AutoSleepPicker×3 未用）。
- CountryCodePicker 弹窗、ExpansionTile（导入说明×5、PlusIntro）、PopupMenuButton（字幕导出、账号菜单）。

---

## 4. 动画清单

| 类型 | 位置 | 细节 |
|---|---|---|
| **Lottie** | assets/lottie/{loading,loading_black,robot_loading}.json | `loading(_black)`：PlayIcon 加载态（play_icon.dart:34-38，白色图标用白色版）；`robot_loading`：AI 转写生成中（player.dart:576、play_icon.dart:69 AIIcon processing 态） |
| **Marquee 跑马灯** | player.dart:351-356（播放器标题过长时；pauseAfterRound 1s、blankSpace 40）；playlists.dart:342-355（历史标题；blankSpace 72、startAfter 1s、startPadding 12） | 判定条件 player 是 `title.length * 24 > rightWidth`（粗略估宽） |
| **carousel_slider** | login.dart:447-468 | Paywall 两张介绍图，autoPlay: true，aspectRatio 2:1，viewportFraction 1，无手动指示器 |
| **Handler 把手提示动画** | widgets/handler.dart:20-61 | 打开 sheet 3 秒后播放一次：TweenSequence 下移 0.8（600ms 中 60% easeOutCubic）再回弹（40% easeInQuad），只播一次；**每次 build 都会播**（`_hasShownAnimation` 恒 false） |
| **AnimatedPlaylistIndicator 飞入动画** | widgets/animation.dart:3-88；调用点 feeds.dart:94-122、channel.dart:147-181、channel.dart:826-860、discover.dart:283-293 | 加号按钮全局坐标 → Playlist tab 图标坐标（`BottomNavBar.getPlaylistPosition()`），600ms easeInOut：位置插值 + 尺寸 200×48→24×24 + 背景 0.8→0，黑底圆角 24 带 play 图标，完成后移除 OverlayEntry |
| **PlayPauseAnimation** | widgets/animation.dart:90-175；调用点 player.dart:758-767 | 点击歌词行切换播放时屏幕中央 80×80 CustomPaint：play 三角 ↔ pause 双条 200ms easeInOut 形变，Overlay 500ms 后移除 |
| **AnimatedContainer 展开条** | card.dart:279-291 | Card 操作按钮条高 0↔60，200ms Curves.easeInOut |
| **proxyDecorator 拖拽放大** | playlists.dart:140-154 | 拖拽项 scale 1→1.1（AnimatedBuilder + lerpDouble） |
| **animateToPage / animateTo** | player.dart:1015-1019（PageTab 300ms easeInOut）；bottom_nav_bar.dart:270-272（Tab0 回顶 300ms easeInOut） | |
| **Channel 头部折叠** | channel.dart:266-540 | 纯布局响应 shrinkOffset：封面 120→60 尺寸/位移、标题左移、次要信息 Opacity 淡出（shrinkOffset ≥ maxExtent/4 全隐） |
| **进度条/mini player 进度** | bottom_nav_bar.dart:91-137；card.dart:54-96 | 无动画直接随 positionData 重绘（每帧） |
| **页面转场** | modal_bottom_sheet 包默认 material 转场（上滑渐入）；无自定义 PageRouteBuilder/自定义转场；无 Hero | |

---

## 5. 主题与视觉

### 5.1 颜色 token（lib/styles.dart，DarkColor 类）
| Token | 值 | 用途 |
|---|---|---|
| primary | `0xFF34D399` | 主绿（Cancel 按钮文字等） |
| primaryLightPlus1 | `0xFFA7F3D0` | （定义少量使用） |
| primaryLightMax | `0xFFECFDF5` | 主文本白（标题样式） |
| primaryDark | `0xFF079669` | |
| primaryBackground | `0xFF30444E` | |
| **primaryBackgroundDark** | `0xFF111316` | **全局页面底色/sheet 底色**（main.dart:114-124 bottomSheetTheme） |
| accentColor | `0xFFFFBC25` | error 色映射 |
| secondaryColor | `0xFF96A7AF` | 次要文本 |
其他高频硬编码色：`0xFF232830`（输入框/胶囊/卡片底）、`0xFF6EE7B7`（tab/链接/频道名高亮绿）、`0xFF10B981`（品牌按钮绿、播放键、Explore）、`0xFF6B7280`（次级文本灰）、`0xFF4B5563`（hint 灰）、`0xFF1E1E1E`（登录卡片）、`0xFF059669→0x00059669`（AppBar 标题渐变）。
**无浅色模式**（darkMode 字段存在但未接 Theme；SettingsController.darkMode 仅存库，states/player.dart:256）。

### 5.2 字体（google_fonts）
- **comfortaa**：所有标题/按钮/tab/时间标签（DarkColor.mainTitle 44px w700 letterSpacing 4.4、secondaryTitle 24px、defaultMainText 14px；全局散布 ~60 处）。
- **notoSans**：cardTitleBold/defaultTitle 16px w700。
- **inter**：卡片描述等正文 12px。
- **mPlusRounded1c**：歌词主/译行（player.dart:718-729）。
- **roboto**：登录菜单小字（login.dart:237 等）；**robotoMono**：HTML 渲染错误文本（formatters.dart:100）。
- 硬编码系统字体：`'PingFang SC'`（card.dart:168 等，iOS 已是系统字体，迁移直接用系统中文栈即可）。

### 5.3 图标库（4 套 + Material）
- **Material Icons**：home_rounded、video_library_rounded、search、settings_rounded、replay_10、forward_30、play_arrow_rounded、image、image_not_supported、more_vert_rounded、person、info、info_outline、exit_to_app、close、delete_outline、question_mark_rounded、check…（SF Symbols 基本都有对应）。
- **material_design_icons_flutter (Mdi)**：仅 `MdiIcons.cloudSearch`（Discover tab，bottom_nav_bar.dart:63）。
- **remixicon**：`Remix.forward_30_fill`（mini player 快进）、`Ri.google_fill`（Google 登录）。
- **fluentui_system_icons**：`FluentIcons.mail_inbox_all_24_filled`、`FluentIcons.library_24_filled`（podcasts.dart:25/29）。
- **iconify_flutter（内联 SVG 字符串）**——迁移需自备 SVG/自绘：
  - `ic` 集：round_settings、round_podcasts、round_play_arrow、round_pause、round_download、round_clear、round_playlist_add、round_playlist_add_check、round_ios_share、round_arrow_back、round_add_circle_outline、round_help、round_check_circle、round_sms_failed、round_file_download、round_apple、email、content_copy、baseline_explore、outline_explore、baseline_offline_share、clear；
  - `icon_park_solid`：check_one（下载完成）；`ph`：arrow_elbow_down_right_bold；
  - 自定义 SVG 常量：`aiChat`（聊天气泡 A，player.dart:38）、`tablerTopology`（AI tab 拓扑图，card.dart:456）、`newDoc`（星光文档，card.dart:458）、`aiTranscript`（AI 转写文档，play_icon.dart:83）。

### 5.4 palette_generator 动态取色
- `updatePaletteGenerator(imageUrl)`（formatters.dart:167-177）：`PaletteGenerator.fromImageProvider(CachedNetworkImageProvider)` 取 **dominantColor**（无兜底处理时默认 `0xFF111316`）。
- 用于两处渐变背景：**PlayerPage**（states/player.dart:232-249 `_updateEpisode` → backgroundColor → player.dart:52-61 三段渐变，第三段起为纯背景色）；**Channel 头部**（states/channel.dart:36-43 → channel.dart:275-285 两段渐变）。
- 配套安全色函数：`getTextSafeColor`（luminance<0.2 → `0xFF10B981`，用于播放器频道名）；`getBackgroundSafeColor` 已定义未用。

---

## 6. 聊天 UI（flutter_chat_ui / flutter_chat_core）
- 仅 `Chat` widget（chat.dart:60-75）：`chatController: InMemoryChatController`、`currentUserId: 'human'`、`theme: ChatTheme.dark()`、`onMessageSend`（isLoading 拦截 + `sendMessage(text, enclosureUrl)`）、`resolveUser`（You/AI）。其余（头像、消息气泡样式、输入框）全用库默认暗色配置。
- **无流式打字效果**：占位 "..." → 一次性整条替换（states/chat.dart:44-70）。无 markdown 定制。历史取最近 10 条（chat.dart:26-35）。

## 7. WebView / HTML
- `flutter_widget_from_html` 仅一处封装：`renderHtml(context, html)`（formatters.dart:80-110），用于：播放器 Settings 页 episode 描述（player.dart:132）、Detail 详情描述（detail.dart:218）。逻辑：空→SizedBox；`trim().startsWith('<')` → **`sanitizeHtml(html)`** 后交 `HtmlWidget`（白字 14px 行高 1.2；onErrorBuilder 红色 robotoMono 错误文本）；sanitize 后为空则退回 `htmlToText` 纯文本；非 HTML 字符串直接 Text。
- `sanitize_html` 处理内容：RSS 描述中的脚本/危险标签（默认白名单策略），保证 show notes 安全渲染。
- **链接点击行为**：HtmlWidget 未配 `onTapUrl`/自定义 builder——**HTML 内链接当前不可点（无 url_launcher 拦截）**；App 内 url_launcher 用在：Privacy/EULA（`inAppBrowserView`，privacy.dart:17-44）、mailto 反馈（settings.dart:460-468）。
- 卡片列表处的描述是 `htmlToText()` 去标签纯文本（card.dart:213）。

## 8. 无障碍与本地化
- **无 i18n**：无 intl/AppLocalizations/flutter_localizations；全部 UI 文案硬编码英文（例外：ImportInstructions “小宇宙” 步骤与国家/语言列表含中文及多语名称；timeago 固定 `en_short` locale，formatters.dart:17）。日期格式为手动拼 `M-d / y-M-d`。
- **无障碍缺失**：全局 grep `Semantics/semanticLabel/excludeSemantics` 零结果；无 `textScaleFactor/textScalerOf` 处理（系统字体缩放会原生生效，布局可能溢出——迁移时建议对齐这一行为或明确约束）。图标均为纯 Icon/Iconify 无标签。
- 手势可发现性补偿：Handler 动画（§4）、Tooltip（设置/播放器/登录共 8 处，tap 触发）。

## 9. 平台差异代码
- **Theme.of(context).platform：无**（grep 零结果）。无 CupertinoApp/CupertinoPageRoute/Cupertino 导航栏——**仅** `CupertinoPicker`×6（settings.dart:329/377/427 + player.dart AutoSleepPicker×3 未用）。
- `Platform.isAndroid` 仅 2 处（states/user.dart:249/257）：RevenueCat API key 选择与 Android 默认套餐 id——iOS 路径即 else 分支（`PURCHASES_IOS_API_KEY`）。
- **SafeArea**：PlayerPage/Channel（`bottom:false` 头部 + body 全）/Settings/Login/EmailLogin/Discover SearchPage 用 SafeArea；Channel/ChannelSearch/SearchPage 底部挂 `PlayerBar(bottomSafe: true)` 包 SafeArea（bottom_nav_bar.dart:234-238）；标准 `showModalBottomSheet` 均 `useSafeArea: true`。ChannelHeaderDelegate 的 min/maxExtent 手动加 `MediaQuery.padding.top`（channel.dart:254-258）。
- 竖屏锁定（main.dart:32-35：portraitUp+portraitDown；注意 iOS Info.plist 声明与 Dart 层不一致，迁移取竖屏为准）。
- audio_service 配置为 Android 通知栏常驻（main.dart:39-48）；iOS 侧等效物为锁屏/控制中心 Remote Command Center（just_audio 默认提供）。`receive_sharing_intent` 接收外部 OPML 分享（states/share.dart）→ iOS 需 Share Extension / Document types 对接。
- Firebase（Auth/Google Sign-In）、RevenueCat、Sentry 已是跨平台 SDK。

---

## 10. 迁移回归清单速览（最高风险点 Top 10）
1. 播放列表长按 150ms 整卡拖拽排序（无把手）+ 1.1x 浮起 + 拖到/拖出 index 0 时无缝换源（playlists.dart:134-239、states/playlist_episode.dart:93-122）。
2. mini player 点按 / 任意垂直拖动 → 全屏播放器（closeProgressThreshold 0.9，bottom_nav_bar.dart:100-117）。
3. PlayerPage PageView 三页横滑 + 底部胶囊 PageTab 双向联动（player.dart:69-81、1009-1021）。
4. flutter_lyric 歌词：逐行滚动跟随、点击行=播放/暂停（中央形变动画）、拖动出时间横条可 seek、neverResume 拖后不自动回位、双语行内混排（player.dart:691-948）。
5. Channel pinned 折叠头的视差/淡出手写动画（channel.dart:248-541）。
6. palette 封面取色 → 播放器/频道页渐变背景 + getTextSafeColor 回退（formatters.dart:139-177）。
7. sheet 套 sheet 的多层导航（播放器→频道→频道内搜索；设置→登录→Email 登录）与各自关闭阈值。
8. Card 展开按钮条 AnimatedContainer + 同列表互斥 + 播放进度背景条实时刷新（card.dart:46-296）。
9. AnimatedPlaylistIndicator 加列表飞入动画（4 个触发点）与 Marquee 标题两处（触发条件为粗略的字符宽度估算）。
10. easy_refresh 下拉（进度条 header、refreshOnStart、自动刷新定时器）+ Tab0 重复点击回顶/刷新逻辑。

### 10.1 2026-09-22 走查补充（本文遗漏的交互事实）

- **401/403 code=2 自动弹登录 sheet**：`lib/api/error_handler.dart:44-53` 在任意 API 401（及 403 code=2）时 `showMaterialModalBottomSheet` 打开 LoginPage（expand true / threshold 0.9）——这是 §1.3 表之外的第 11 个 material sheet 调用点（任何页面任何时刻都可能弹出）；`error_handler.dart:28-41、72-85` 另有两种错误 AlertDialog。M3 的错误处理与《05》§6.1 S20 均以此为依据。
- **Detail 内操作按钮点击后自动 pop 关闭 Detail**（`lib/widgets/detail.dart:30-39` 的 wrapper：`action.onPressed(); Navigator.pop(context)`）。
- **BottomNavBar 容器自带垂直渐变背景** `0xF014171A → 0xFF16191D`（bottom_nav_bar.dart:29-35）——§5.1 色表未收录，A1 适配时注意底部渐变消失属预期。
- **Feeds 空态仍可下拉刷新**：ImportBlock 包在 `AlwaysScrollableScrollPhysics` 的滚动容器中并绑定 scrollController（feeds.dart:64-69）。
- **Playlists 页没有可见 TabBar**、只有 TabBarView（playlists.dart:43-55）——多播放列表仅能横滑切换，M3 实现勿凭空加 Tab 条。
- 同会话内重开频道页复用旧实例不重抓（K34）；频道内搜索 `e.title!` 空即崩（归 K4 崩溃族）；"Latest Episode" 按钮 `episodes[0]` 同理（channel.dart:500、760）。
