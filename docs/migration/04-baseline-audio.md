# 基线盘点 04：音频栈与 iOS 原生层（音频功能回归的事实来源）

> 用途：iOS 原生化迁移的音频行为回归测试设计输入，并回答“相关功能（比如音频设置）都可以在 iOS 上实现吗”。
> 版本基线：app 1.2.1+38（pubspec.yaml:19）；just_audio **0.10.6**、audio_service **0.18.19**、audio_session **0.2.4**（transitive，pubspec.lock 解析结果）、flutter_cache_manager_plus **3.3.2**（sljeff fork，git ref `51211c9`）、retry **3.1.2**、sqflite **2.4.2+1**、share_plus **11.1.0**、flutter_lyric **3.0.7**、audio_video_progress_bar **2.0.3**。
> 说明：本机 pub 缓存已清空（ios/.symlinks 指向的 ~/.pub-cache/hosted 为空），just_audio/audio_service 的原生源码无法本地核对，涉及库行为的部分均标注“库行为（据官方文档）”，其余结论来自项目代码逐行阅读。

---

## 1. 播放能力全清单

### 1.1 基础控制

| 能力 | 实现位置 | 说明 |
|---|---|---|
| 播放/暂停 | `lib/utils/audio_handler.dart:120-130`（`play`/`pause` 覆写） | UI 入口：全屏播放页 Controls（`lib/pages/player.dart:1038-1080`）、mini 播放条（`lib/widgets/bottom_nav_bar.dart:191-207`）、歌词行点击（player.dart:755-768） |
| 绝对 seek | `audio_handler.dart:109-110`；业务封装 `seekAndPlayByEpisode`（96-107 行） | 若目标集与当前集相同则只 seek（**注意：同集也先 `pause()` 一拍再 seek+play**，audio_handler.dart:98-101）；不同则重设数据源。seek 目标只写内存 `episode.playedDuration`，DB 落盘仍依赖 2s timer。进度条拖动入口 `lib/pages/player.dart:434-436` |
| 相对 seek | `seekByRelative`（`audio_handler.dart:138-147`），自动 clamp 到 [0, duration]（`_player.duration!` 为空即抛异常，归 K4 崩溃族） | UI：全屏页回退 10s / 前进 30s（player.dart:1040、1071）。**mini 条前进 30s 是另一条路径**（2026-09-22 核验更正）：`controller.seek(position+30s)` → `seekAndPlayByEpisode`（bottom_nav_bar.dart:208-214）——先 `pause()` 再 seek 再 `play()`（有暂停间歇）、**无 clamp**、目标值取自暂停期可能过期的 `positionData` |
| 上一首/下一首 | **没有真正的切集按钮**。`skipToNext`/`skipToPrevious` 被覆写为 `fastForward()`/`rewind()` = **±10s seek**（`audio_handler.dart:182-191`） | 即锁屏/控制中心的“下一曲/上一曲”实际是快进/快退 10 秒。**已确认为有意设计（播客惯例），迁移复刻**（《05》§11 K1） |
| 停止 | `stop()`（audio_handler.dart:133-136） | 全项目无任何调用点 |

### 1.2 队列管理（核心机制，非 just_audio 队列）

- **从不使用 just_audio 的 playlist**：无 `ConcatenatingAudioSource`、无 `setAudioSources`（全库 grep 证实）。任何时刻 `_player` 只挂**单个 AudioSource**（`setUrl`/`setFilePath`，audio_handler.dart:207-214）。`audio_service` 的 `queue` 永远为空（`skipToQueueItem` 读 `queue.value[index]`，实际不可达，audio_handler.dart:113-117）。
- 队列完全在**应用层**实现：sqlite `playlist` 表默认建 id=1 的 "Default" 播放列表（`lib/models/playlist.dart:12-17`），实为“待播列表（Up Next）”语义；`playlistEpisode` 表用**浮点 position 字段**维护顺序（fractional indexing，`lib/models/playlist_episode.dart:26,90-135`，间距 < 0.0005 时全表重排）。
- `episodes[0]` 恒为“当前播放集”：`PlaylistEpisodeController`（`lib/states/playlist_episode.dart`）。
- **自动连播**：监听 `playerStateStream`，`ProcessingState.completed` 时 `removeTop()`（把播完的集从列表**删除**）→ 列表空则 pause+clear；否则播 `episodes[0]`；若设置 `continuousPlaying=false` 则 pause 并重置进度显示（`lib/states/player.dart:76-103`）。`continuousPlaying` 持久化在 settings 表（默认 true，`lib/models/settings.dart:20`）。
- 重排序/置顶：`move()` 含"涉 index 0 先 pause 后 `setByEpisode` 重装载"逻辑（states/playlist_episode.dart:93-122）；`moveToTop()` 本身纯重排、不 pause 不重装载（同文件 75-82 行，"index==0 且播放中则 pause"的判断在唯一调用方 `lib/pages/playlists.dart:177-182`——2026-09-22 核验更正原合并表述；实践上结论不变：index 0 变更会重装载）。`move()` 换序涉 index 0 时有 `sleep(100ms)` 同步阻塞主 isolate——cargo cult，原生勿移植（08 §11.4）。
- **换序写库的 off-by-one**：对已存在条目的移动，`insertOrUpdateByIndex` 用移动前的 DB 列表取邻居，**下移（to>from）重启后回退**（models/playlist_episode.dart:90-125）——处置见《05》K26（修复 + G1/G2 golden 拆分）。
- **循环/随机**：`setRepeatMode`/`setShuffleMode` 有覆写实现（audio_handler.dart:150-161，映射到 just_audio LoopMode/ShuffleMode），但**全项目无任何调用** —— 死代码，等效于无此功能。

### 1.3 倍速

- `setSpeed` → `_player.setSpeed`（audio_handler.dart:164-167）。
- UI：滑杆 min 0.5 / max 2.0 / **divisions 6**，可选值为 **0.5、0.75、1.0、1.25、1.5、1.75、2.0**（`lib/pages/player.dart:1208-1217`）。
- 持久化：settings 表 `speed` 字段，启动时恢复并应用（`lib/states/player.dart:294、359-366`）；`speedStream` 回写 UI。

### 1.4 Skip Silence

- 有设置项且持久化（`states/player.dart:368-375` → settings 表 `skipSilence`），UI 开关在播放页（player.dart:1285-1318），调用 `_player.setSkipSilenceEnabled`（audio_handler.dart:193-195）。
- **库行为（just_audio 0.10.6 官方文档）**：`setSkipSilenceEnabled` 明确标注 "Currently Android only"，**iOS 上是 no-op**。当前 iOS 版的该开关就是无效但可切换的状态 —— 迁移时保持“开关存在但 iOS 无效果”即为行为对齐。

### 1.5 音量增强 / 均衡器

- **均未实现**。`audio_handler.dart:28-41` 有一段被注释掉的 `AndroidEqualizer`（"set vocal enhancer"）实验代码，从未启用。pubspec 中无 volume booster / DSP 类插件。just_audio 的 `AndroidEqualizer`/`AndroidLoudnessEnhancer` 本身也仅 Android 可用。

### 1.6 音频焦点 / 打断 / 线控

- **应用代码零处理**：全 lib 无 `audio_session`/`AVAudioSession`/`AudioSession` 引用（grep 证实），无打断监听、无 `setAudioAttributes`。焦点/打断完全委托给 just_audio + audio_service 插件默认行为（库行为：just_audio darwin 端默认将 AVAudioSession 设为 playback 并**在播放时激活**；来电/其他 App 抢占由系统 category 机制处理）。Dart 层没有“被打断后恢复播放”的自定义逻辑。
- **激活时机的等价含义（2026-09-22 补充，K18 会话策略的事实依据）**：会话激活只随**起播**发生 ⇒ **冷启动/纯浏览不打断他 App 正在播放的音频**；原生迁移必须保持这一点——启动只 `setCategory(.playback)`、首次起播前才 `setActive(true)`（勿在启动期 setActive，否则冷启动即抢焦点，构成对旧版的可见劣化；详见《06》§6 与《05》§5.3 新增行）。
- iOS 侧唯一相关配置：**Podfile post_install 给所有 pod 注入 `AUDIO_SESSION_MICROPHONE=0`**（ios/Podfile:51-57），即禁用 audio_session 插件的麦克风 category 分支。
- 线控/锁屏命令：见第 2 节（rewind/fastForward ±10s + play/pause + seek）。

### 1.7 睡眠定时器

- **手动倒计时**：有。播放页 COUNTDOWN 滑杆 0–60 分钟（divisions 6，即 10 分钟一档）（player.dart:1240-1275）；`SettingsController` 每秒 Timer，**仅播放中递减**，到 0 → `PlayerController.pause()`（`states/player.dart:320-333`）；`noCountdown = Duration(days: -1000)` 哨兵值表示关闭。
- **自动入睡（时间段+倒计时）**：设置数据结构完整（startHour/endHour/countdownMin 三元组持久化于 settings 表 `autoSleepTimer`，`states/player.dart:377-434`），选择器 UI `AutoSleepPicker` 存在（player.dart:1374-1514）—— **但触发函数 `autoSetCountdown()` 的唯一调用点被注释**（audio_handler.dart:121），即该功能当前处于“可配置但不生效”状态。回归时应视作无效功能。
- **倒计时滑杆拖到 0 的竞态（2026-09-22 走查）**：`onChanged` 即 `setCountdown(Duration.zero)`（player.dart:1252-1254），若 1s timer 先触发会执行 `pause()`、`onChangeEnd` 才 `stopCountdown`——“拖到 0（= OFF）”可能顺带暂停播放（时序相关）。**已定修复（K38）：滑到 0 = OFF 不触发 pause，仅倒计时自然递减到 0 才 pause。**

### 1.8 2026-09-22 走查补充（播放链路隐藏行为）

- **每次恢复播放都写一条历史**：`play()` 在已有 audioSource（resume）时也执行 `HistoryController.insert`（states/player.dart:169-173）→ 暂停/继续 N 次 = 历史刷新 N 次 id（K30 复刻 + 《05》§2.3 断言）。
- **装载 Future 被丢弃**：`autoSet` 不 await `setUrl`/`setFilePath`（audio_handler.dart:207-214）——装载失败完全静默（比"无错误处理"更彻底）；mediaItem 在发起加载后**立即**更新、不等加载完成（M2 状态机时序断言来源，《08》§12.2）。
- **completed 但 `currentPlaylistId == null`**：直接 return，播放器停留 completed 态无任何处理（states/player.dart:84-87）。
- **队列播空 `clear()` 连带删 player 表记录**（states/player.dart:211-219 → PlayerModel.delete）→ 之后冷启动无 currentPlaylistId 可恢复，且 `PlayerModel.get` 对空结果抛错（K31）。
- **MyAudioHandler 是进程单例**（static `_internal` + factory，audio_handler.dart:22-24）——原生由组合根持有 PlaybackService 等价替代（08 §11.4）。

---

## 2. 后台播放与系统集成（audio_service）

### 2.1 初始化与配置

`lib/main.dart:39-48`：

```dart
await AudioService.init(
  builder: () => MyAudioHandler(),
  config: const AudioServiceConfig(
    androidNotificationChannelId: 'com.kindjeff.anycast.audio',
    ... // 全部是 android* 键
  ),
);
```

- config 仅含 Android 通知渠道参数，iOS 无对应项。未设置 `fastForwardInterval`/`rewindInterval`（库默认 30s，但实际执行的是 handler 覆写的 ±10s —— 见下）。

### 2.2 状态桥接（MyAudioHandler 构造器，audio_handler.dart:44-64）

`_player.playbackEventStream` 每事件 → `playbackState.add(PlaybackState(...))`：
- **controls**：恒为 `[MediaControl.rewind, 播放中?pause:play, MediaControl.fastForward]`，`androidCompactActionIndices: [0,1,2]`；
- **systemActions**：仅 `{MediaAction.seek}`；
- 携带 processingState（just_audio 枚举按下标映射 audio_service 枚举）、playing、updateTime/updatePosition/bufferedPosition、speed。

**iOS 表现（库行为，audio_service 0.18 darwin）**：controls 映射到 `MPRemoteCommandCenter` 的 skipBackward / play-pause toggle / skipForward；`MediaAction.seek` 启用 `changePlaybackPositionCommand`；进度/时长/速率经 `MPNowPlayingInfoCenter` 持续刷新。即锁屏可：回退（执行 handler.rewind = **-10s**）、播放/暂停、快进（= **+10s**）、拖动进度条（= `seek`）。**没有下一集/上一集命令**。

### 2.3 Now Playing 元数据

每集播放时 `mediaItem.add(episode.toMediaItem())`（audio_handler.dart:93；`lib/models/playlist_episode.dart:166-174`）：
- `id` = enclosureUrl；`title` = 集标题；`album` = channelTitle；`artUri` = **网络图片 URL 原样传入**（`Uri.parse(imageUrl)`）；`duration` = RSS 提供的 duration（毫秒）。
- artwork 由 audio_service iOS 端异步下载渲染。注意 artUri 无本地缓存/回退兜底。

### 2.4 后台时长 / category

- Info.plist 已声明 `UIBackgroundModes = [audio]`（ios/Runner/Info.plist:61-64）——iOS 后台播放在正确设置 playback category 后无时长限制；**Dart 层没有任何显式设置 category 的代码**（见 1.6）。
- CarPlay：**未实现**。README.md:91 TODO 明确列出 "Carplay support"；Info.plist 无 `com.apple.developer.playable-content` 相关配置，entitlements 无 CarPlay；audio_service 0.18 本身不提供 CarPlay。

---

## 3. 播放进度持久化与恢复

### 3.1 保存

- **时机**：`PlayerController.onInit` 起 `Timer.periodic(2 秒)`，条件是 `isPlaying` 且当前集有效，写 `episodes[0]`（`lib/states/player.dart:64-74`）→ `PlaylistEpisodeController.updatePlayedDuration`（states/playlist_episode.dart:84-91）→ SQL `UPDATE playlistEpisode SET playedDuration=? WHERE enclosureUrl=?`（`lib/models/playlist_episode.dart:154-157`）。
- **没有** pause 时保存、没有 App 生命周期监听（全库无 `WidgetsBindingObserver`/`didChangeAppLifecycleState`，grep 证实）、没有退出保存 —— 最坏丢 2 秒进度。
- 进度单位毫秒，存于 sqflite 数据库 `anycast.db`（version 4）`playlistEpisode.playedDuration`。

### 3.2 冷启动恢复

- `PlayerController.load()` 读 `player` 表的 `currentPlaylistId`（models/player.dart:49-55；states/player.dart:118-124）。
- `PlaylistController.load()` 载入该列表的集合并把 `episodes[0]` 设为当前集，**仅恢复 UI 进度显示**（position = playedDuration, duration = RSS duration），**不预装音频源**（states/playlist.dart:33-48）。
- 点击播放时因 `audioSource == null` 走 `playByEpisode` 全新装载，`initialPosition = playedDuration`（states/player.dart:165-176；audio_handler.dart:88-91 → `autoSet(initialPosition:)` 传入 `setUrl/setFilePath`）。

### 3.3 跨设备

- **无任何同步**。`playedDuration` 只存本地 sqlite；后端仅用于登录/字幕/翻译/聊天/分享短链。同一集在另一设备从头开始（0 或 RSS 无进度）。

---

## 4. 流式播放细节

`MyAudioHandler.autoSet`（audio_handler.dart:197-220）是唯一装载入口：

1. 先查缓存：`cacheManager.getFileFromCache(url)` 命中 → `_player.setFilePath(本地路径, preload: true, initialPosition:)`（离线直读本地文件）；
2. 未命中 → `_player.setUrl(url, preload: true, initialPosition:)` **直接播 URL**（边下边播），同时**并行**启动 `cacheManager.getFileStream(url, withProgress: true)` 做整文件下载缓存（进度进 `CacheController.key2FileResponse`）。

- **无 headers**（setUrl 第三参未用）、**无自定义 proxy**、无 just_audio 自带锁屏缓存配置；HTTP Range/重定向全部交给 just_audio/iOS（AVPlayer）默认行为。
- **播放错误重试：没有**。`playerErrorStream` 无人订阅（grep 证实），网络失败表现为无限 buffering 或静默失败，无 UI 错误提示、无自动重试。`retry` 包只用于 API HTTP 层（`lib/utils/http_client.dart:10-19`：`retryIf: SocketException || TimeoutException`，maxAttempts 2；`reqWithAuth` 超时 10s）。
- 弱网：无自定义超时；buffering 状态经 `isLoading`（ProcessingState.loading/buffering，states/player.dart:79-82）驱动 PlayIcon 的 Lottie loading 动画（lib/widgets/play_icon.dart:29-36）。
- 注意 `positionDataStream` 监听里过滤了 **四种事件**：`!isPlaying || isLoading || position==0 || buffered==0`（states/player.dart:105-115），意味着暂停中/加载中/刚起播/回退到 0 时 UI 进度不刷新。

---

## 5. 下载 / 离线

- **触发**：纯手动、逐集。播放列表集卡片右下角下载小按钮（`lib/widgets/card.dart:232-275`）→ `CacheController.download(url)`（`lib/states/cache.dart:51-56`：`getFileStream(url, withProgress: true)`）。此外任何一次在线播放也会顺带把整集缓存下来（autoSet 第 215-219 行）。
- **进度显示**：`key2FileResponse` map 存 `DownloadProgress`（0–1）→ 卡片上 `CircularPercentIndicator`；完成显示绿色对勾（card.dart:262-274）。
- **暂停/取消**：**不支持**。flutter_cache_manager 无暂停 API，唯一删除手段是 `CacheController.remove(url)` → `removeFile`（cache.dart:65-68），由删除列表条目触发（states/playlist_episode.dart:53-68，连带删字幕/翻译/缓存）。
- **文件与路径**：详见《01-baseline-data.md》§4 —— 文件在 `<Container>/tmp/anycast_episode/<uuid_v1>.<ext>`，元数据在 `Library/Application Support/anycast_episode.db`。
- **清理策略 = 按“对象个数”的 LRU**，上限 `settings.maxCacheCount`（默认 10），**不是按字节数**；超限时淘汰最旧（且 >1 天未触碰）。
- **离线改写**：即第 4 节 —— 播放前查缓存，命中即 `setFilePath(本地文件)`，URL 本身不改。
- **手动清理入口**：**设置页没有**（settings.dart 全文核对）。`SettingsController.setMaxCacheCount` 存在（states/player.dart:436-443）但无任何 UI 调用（grep 证实）—— 上限实际锁死在首次读取的 10。启动时 CacheController.onInit 会核对 Default 列表（playlistId=1）各集缓存状态用于卡片显示（cache.dart:18-32）。

---

## 6. 字幕 / 转写 / 双语 / LRC

### 6.1 转写触发

- 用户手动：播放页第 3 页签（AI）中 "Generate transcript with AI (Beta)" 按钮（player.dart:480-560）→ `SubtitleController.add(url)`（`lib/states/subtitle.dart:51-80`）：本地立即记 `processing`，POST `https://anycast.website/api/subtitles`，body `{"enclosure_url": ...}`，**带 Firebase Bearer token**（`lib/api/subtitles.dart:35-47`，经 `reqWithAuth`）。当前**必须登录**才能用 ASR（自定义 ASR 免登录是 README 待办）；客户端代码未做订阅门槛判断（RevenueCat 订阅对象存在，`lib/states/user.dart:235+`，但字幕按钮不检查 `isSubscribed`）。
- 每集一次（按 enclosureUrl 幂等存储）；后台任务 **每 15s 轮询**一次所有 `processing` 状态的集（subtitle.dart:24-49）；`failed` 则删本地记录（可重试按钮，player.dart:595-608）。
- 提示文案：约 2~5 分钟（player.dart:512、580）。

### 6.2 字幕 JSON 结构（逐字段）

响应体（api/subtitles.dart:49-71）：`{ status: 'succeeded'|..., subtitle: { detected_language: 'xx', segments: [{ start: double(秒), end: double(秒), text: string }, ...] } }`。
本地 `subtitle` 表（lib/models/subtitle.dart:8-19）：`enclosureUrl UNIQUE / status / subtitle(TEXT=segments 数组的 jsonEncode) / language / summary`。空的 subtitle 会被 insert 校验拒绝并回退 processing（models/subtitle.dart:68-82；player.dart:614-624）。

### 6.3 LRC 导出 / 生成

- `SubtitleModel.toLrc()`（models/subtitle.dart:101-116）：每段输出两行 `[mm:ss.mmm]text` + `[mm:ss.mmm]`（行尾空时间戳行），时间格式化 `formatLrcTime`（`lib/utils/formatters.dart:180-185`，三位毫秒）。Translation 同构（models/translation.dart:74-89）。
- **导出实现**（player.dart:950-978）：拼 `# 标题 - 频道\n\n---\n\n` + 主 LRC + `\n--- Translation ---\n` + 翻译 LRC，写入**临时目录 `.txt` 文件**，`share_plus` 系统分享。注意扩展名是 `.txt` 不是 `.lrc`。

### 6.4 翻译 / 双语

- `TranslationController` **每 10s 轮询**：targetLanguage 非空 且字幕 succeeded 且未翻译 → `loadTranslation`（`lib/states/translation.dart:20-79`）：先查本地 `translation` 表（按 enclosureUrl+language），无则 POST `/api/subtitles/translate` `{enclosure_url, language}` —— **这个接口不带 Authorization 头**（api/subtitles.dart:80-83 用裸 `http.post`，与其他 API 不同）。返回 `{translation: [{start,end,text},...]}`。
- 检测语言 == 目标语言则跳过（translation.dart:48-50）；切换目标语言会清内存映射（states/player.dart:452-458）。
- 双语渲染：flutter_lyric 的 `LyricView`，`loadLyric(mainLyric, translationLyric:)` 双 LRC（player.dart:646-680、776-781）；译文样式/行距定制在 707-742 行。

### 6.5 与播放进度同步

- 单向推进：`ever(positionData)` → `_lyricController.setProgress(position)`（player.dart:771-773）—— 由 flutter_lyric 内部按 LRC 时间戳二分定位当前行/滚动；起播时先手动 setProgress 一次（751-752）。
- 反向交互：点歌词行 = 播放/暂停切换（755-768）；拖选歌词行出现的时间条+播放按钮 → `seek(state.duration)`（859-877）。
- 附带：AI 聊天（`/api/subtitles/chat`，带鉴权与 history，api/subtitles.dart:101-122），聊天页 `lib/pages/chat.dart`。

---

## 7. iOS 原生层现状

- **AppDelegate.swift**（ios/Runner/AppDelegate.swift，全文 13 行）：仅 `GeneratedPluginRegistrant.register(with: self)`。**没有任何音频初始化、没有 MethodChannel/EventChannel、没有 AVAudioSession 代码**。Bridging header 为空壳。
- **Info.plist**（ios/Runner/Info.plist）关键项：
  - `UIBackgroundModes = [audio]`（61-64 行）✔ 后台音频已开
  - ATS：`NSAllowsArbitraryLoads=true` + `NSAllowsArbitraryLoadsForMedia=true`（52-58 行）→ 允许任意 http 媒体源（播客 enclosure 常 http）
  - URL Schemes：`com.googleusercontent.apps.1092551717876-...`（Google 登录回跳，34 行）+ `ShareMedia-$(PRODUCT_BUNDLE_IDENTIFIER)`（receive_sharing_intent，42 行）
  - `AppGroupId = $(CUSTOM_GROUP_ID)`（5-6 行，构建变量）；`CADisableMinimumFrameDurationOnPhone=true`（120Hz）
  - **无** 麦克风/隐私权限声明、无 query schemes、无 CarPlay 相关键
- **Runner.entitlements**：`com.apple.developer.applesignin=[Default]` + `com.apple.security.application-groups=[group.com.kindjeff.ShareExtention]`。**无** push、无 associated domains、**无 CarPlay/playable-content entitlement**。
- **Share Extension**（com.kindjeff.anycast.Share-Extension）：接受文本与 1 个文件的 share 扩展（OPML 订阅导入），有同 group entitlement（ios/Share Extension/）。`Share OMPL extension` 目录只剩 Base.lproj（残留）。
- **Podfile**（ios/Podfile）：`platform :ios, '15.0'`；`use_frameworks!` + modular headers；`Pod::PICKER_DOCUMENT=true`（file_picker 文档模式）；post_install 全 pod 注入 `AUDIO_SESSION_MICROPHONE=0`（51-57 行）。**未锁定任何 pod 版本**，全部经 Flutter podhelper 从 .symlinks 引入；磁盘上无 Podfile.lock。实际安装的外部 pods（ios/Pods/）：Firebase/Core+Auth、GoogleSignIn、RevenueCat/PurchasesHybridCommon、Sentry、AppAuth、GTM*、PromisesObjC。
- **部署版本**：Runner 各 target `IPHONEOS_DEPLOYMENT_TARGET = 15.0`（project.pbxproj 615/671/714/754/869/918 行）；Flutter 框架 `AppFrameworkInfo.plist MinimumOSVersion = 13.0`。
- 插件注册（GeneratedPluginRegistrant.m）：18 个插件，音频相关为 `audio_service`、`audio_session`、`just_audio`，另有 `wakelock_plus`、`video_player_avfoundation`（fwfh_just_audio 传递引入，服务于 HTML 富文本内嵌音频）。

---

## 8. just_audio 在 iOS 上的已知限制与本项目 workaround

- **iOS 平台分支代码：零**。lib 中仅有 `Platform.isAndroid`（RevenueCat 套餐 id，states/user.dart:249/257）与 firebase_options，播放链路无任何 `Platform.isIOS` 判断 —— 即**代码未对 iOS 做任何特殊处理**，也**没有**倍速/音量方面的 iOS 插件 workaround（无 volume_booster 之类依赖）。
- 由此推出的现状结论：
  - **skip silence**：设置项在 iOS 上可切换、会持久化，但据官方文档 **iOS 端 no-op**（0.10.6 文档原文 "Currently Android only"）。→ 现网 iOS 版该功能本来就无效，迁移“保持无效”即等价。
  - **均衡器/人声增强**：仅 Android 可用（`AndroidEqualizer`），项目里也从未启用（audio_handler.dart:28-41 注释代码）。
  - **倍速**：just_audio darwin 走 `AVPlayer.rate`，0.5–2.0 区间 iOS 原生支持，无已知限制（音高保持取决于库内 audioTimePitchAlgorithm 设置，迁移到原生时需自选 `AVAudioTimePitchAlgorithmTimeDomain`）。
  - **headers**：本项目未用；若未来需要，just_audio darwin 走本地 proxy 支持自定义 header，AVPlayer 原生需 `AVURLAsset` options 或自建 server —— 现状无此需求。
  - **artwork**：`artUri` 为远程 URL 直接交给 audio_service，无本地兜底（弱网锁屏可能无图）。

---

## 9. 原生迁移能力映射初判（AVFoundation 侧）

| 现有能力 | iOS 原生对应 | 可行性 |
|---|---|---|
| 播放/暂停/seek/±10s/±30s | `AVPlayer` + `seek(to:toleranceBefore:0, toleranceAfter:0)`；进度条 `addPeriodicTimeObserver`（对应 positionDataStream） | 完全可行 |
| 单源播放 + 应用层队列 + 播完 removeTop + 自动连播 | 单 `AVPlayer` + `AVPlayerItemDidPlayToEndTime` 通知复刻现有逻辑即可（无需 AVQueuePlayer；若想真 gapless 可选 AVQueuePlayer，但会改变“播完即删”语义） | 完全可行 |
| 锁屏/控制中心（rewind/play-pause/ff/seek） | `MPRemoteCommandCenter`：`skipBackwardCommand`(preferredIntervals=[10s]) / `togglePlayPauseCommand` / `skipForwardCommand` / `changePlaybackPositionCommand`；注意现网“快进按钮=+10s、无切集命令”的怪癖需一比一复刻。iOS 27 起可换用新 Now Playing 框架（声明式） | 完全可行 |
| Now Playing 元数据 | `MPNowPlayingInfoCenter`：title/album(channel)/artwork(需自行下载缓存再设 `MPMediaItemArtwork`)/duration/position/playbackRate | 完全可行（还能做得更好：本地缓存 artwork） |
| 后台播放 | `UIBackgroundModes=audio`（已有）+ `AVAudioSession.sharedInstance().setCategory(.playback)` + `setActive`；无时长限制 | 完全可行 |
| 音频焦点/打断（来电、Siri、抢占） | `AVAudioSession.interruptionNotification` + `routeChangeNotification`（拔耳机暂停建议补上，现网未做） | 可行且应优于现状（现网零自定义处理） |
| 倍速 0.5–2.0（7 档） | `player.rate` + `audioTimePitchAlgorithm`（保音高） | 完全可行 |
| **Skip silence** | **iOS 无公开 API**。just_audio 在 iOS 也是 no-op → 迁移后保持“开关存在、iOS 无效”即为对齐；若要真做需 `AVAudioEngine`+`AVAudioUnitTimePitch` 自建管线做静音检测+时间压缩，成本高 | **降级项**（建议保持无效或砍掉开关） |
| **均衡器/音量增强** | **iOS 无全局/系统 EQ API**。自绘需 `AVAudioEngine` + `AVAudioUnitEQ`（即弃 AVPlayer 直播、改 AVAudioPlayerNode 调度渲染）；现网本就没实现 → 迁移等价为“不做” | **无需实现**（本来就无此功能） |
| 睡眠定时器（手动 0–60min；auto-sleep 死代码） | 普通 Timer/WorkItem，逻辑照抄（含“仅播放中递减”） | 完全可行 |
| 进度 2s 落盘 + 冷启动恢复 | sqlite（GRDB 直接读旧 anycast.db）；建议补 pause/App 切后台时保存 | 完全可行 |
| URL 直播 + 整文件并行缓存 + 缓存命中播本地 | `AVURLAsset`/`AVPlayerItem(url:)` + `URLSession.downloadTask`(withDelegate 进度)；播放前查本地文件改 `fileURLWithPath` | 完全可行 |
| 缓存 LRU（按个数，默认 10）+ 无暂停取消 | 目录扫大小 + 文件 mtime LRU 淘汰，照抄语义；下载取消 `task.cancel()`（比现在更强） | 完全可行 |
| 字幕/翻译/AI 聊天/LRC 导出/双语歌词 | 纯网络 + JSON + 本地渲染：`URLSession` + GRDB + 自绘歌词 ScrollView（时间戳匹配照抄 `setProgress` 模式）；导出走 `UIActivityViewController` | 完全可行，与播放器无耦合 |
| CarPlay（TODO 未实现） | `com.apple.developer.playable-content` entitlement + `CPNowPlayingTemplate`（+ 可选 CPListTemplate 浏览）；AVFoundation 播放层天然兼容 | 可行，但属于新增特性而非迁移 |
| 无播放错误处理 | 原生补 `AVPlayerItemFailedToPlayToEndTime`/KVO status 错误兜底（建议顺手修复，非等价要求） | 建议增强 |

**结论**：全部现有音频功能在 iOS 原生（AVPlayer + AVAudioSession + MPRemoteCommandCenter/MPNowPlayingInfoCenter + URLSession）上均可等价实现；唯一客观做不到的是 skip silence（无公开 API）与系统级 EQ/音量增强 —— 而这两项在现网 iOS 版本上本就是 no-op/未实现，因此**严格回归等价没有任何阻塞项**。

**迁移时需特意复刻的行为怪癖**：锁屏“上一曲/下一曲”实为 ±10s（**已确认为有意设计，复刻**，《05》§11 K1）、播放完成即从列表删除该集、2s 进度落盘、auto-sleep 死代码、缓存上限 UI 缺失（锁死 10 个）、翻译接口无鉴权头。
