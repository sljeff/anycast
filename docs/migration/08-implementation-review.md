# 08 · 实施细节评审：Flutter 妥协 vs iOS 原生最佳实践

> **2026-09-22 合稿说明**：本文全部采纳条目已按 §9/§11.7/§12 的"建议落点"并入目标文档——《05》（K26–K38 新增、K4/K9 增补、G1/G2 拆分、G13 备注、§1.3/§2.3/§4.2/§5.1/§5.3 补断言）、《06》（§4 架构铁律、§6 会话激活策略修订）、《07》（§2.1–§2.6、§6 增补）、《00》（M0–M2 任务）。**后续以目标文档为准，本文转为依据出处与未采纳项备忘存档**；§5.2 原方案"启动早期 setActive(true)"经复核会让冷启动打断他 App 音频，已按《06》§6 修订版执行。
>
> 2026-09-22 生成。评审对象：**迁移实现方式**（不是功能等价性——那由《05》管）。
> 要回答的问题：Flutter 实现里大量"有什么用什么"的妥协（异步 DB 写法、GetX 的同步/异步语义、线程隔离、常驻定时器、build() 里初始化、第三方库的强行适配），换到 Swift/UIKit 后**哪些应该换成平台最佳实践、哪些必须保持原样**。
> 性质：**建议稿**。采纳任何条目按《00》修订规则登记（结构性建议进《06》/《07》对应小节，用户可见的行为变化进《05》§11 决策表）。
> §1–§10 基于迁移文档 + 定点代码核验；**§11 是第二轮全量代码走查（2026-09-22，通读 lib/ 全部实现）的补充发现**，逐条附代码出处。

---

## 0. 判断框架（本评审的纲）

《05》§0 定义的等价性是**可观察行为等价**：数据行内容、请求形态、屏幕呈现、手势结果、付费身份。它没有（也不应该）约束**内部机制**：线程怎么调度、对象怎么组织、数据怎么流动、初始化按什么顺序。

由此得出三条评审原则：

1. **对外可见的语义** → 等价，按《05》执行，没有讨论空间；
2. **内部机制** → 完全按 iOS/Swift 最佳实践重写，**不追求与 Flutter 的"过程等价"**；
3. 冲突判定法：问一句"**用户、后端或回归测试能不能观察到差异**"——观察不到的实现细节全部自由。

风险是不对称的：把 Flutter 的内部机制照搬进 Swift，代价不是"风格不地道"，而是**主线程卡顿、数据竞争、内存泄漏、竞态 bug**（Flutter 的 isolate/Rx 模型天然规避了这些，Swift 没有免费的保护）；反过来，把"内部优化"越界做到用户可见的层面（列表动画、触发判定），则会踩等价性红线。

每条结论给三档判定：

- ⛔ **必须改**：复刻在新栈里有实际风险（卡顿/竞争/泄漏），不改大概率出问题；
- ⚠️ **建议改**：有明显更优解，用户不可见或纯改善；
- ✅ **维持复刻**：等价性要求所迫，或现状已足够好（**"iOS 惯例如此但我们必须反着来"的条目也归这里，并说明为什么**）。

---

## 1. 数据层：异步数据库写法

### 1.1 线程模型 ⛔ P0 —— 全评审最重要的一条

**Flutter 事实**：sqflite 所有操作经 platform channel 在插件后台线程执行，Dart 侧只是 `await`——**UI 永不因 SQL 阻塞**，这是 isolate 模型白送的保证。

**迁移陷阱**：GRDB 的 `read {}` / `write {}` 是**同步阻塞**调用。如果照搬旧结构（controller 里直接调 model 的 DB 方法，即 `@MainActor` 栈上执行 SQL），那么 2s 进度落盘、60s 裁剪、50 订阅刷新的批量写入、OPML 导入都会卡主线程。最危险的是：**Swift 6 编译器对"MainActor 上调用阻塞函数"完全不报警**——这不是数据竞争，是合法代码，属于静默性能陷阱，《06》§4 的并发表没有点名它。

**最佳实践**：
- 分层：`@MainActor` controller ↔ repository（`@concurrent`/nonisolated 函数或 `actor`）↔ GRDB `DatabaseQueue`。controller 拿到的只有结果值。
- 跨界载体只用**值类型**（`Codable + Sendable` struct），不传数据库连接、不传可变引用。
- 用单个 `DatabaseQueue`（不是 `DatabasePool`）：天然串行化免锁、不启用 WAL——正好同时满足《05》§2.4 写回兼容（旧库是 rollback journal）。
- 架构约定当 lint 用：**"DB 访问不允许出现在 `@MainActor` 调用栈上"**，写进《06》§4 与 M1 骨架任务。

### 1.2 事务性 ⚠️ P1

**Flutter 事实**：`historyEpisode.insert` 是**两条独立语句**（先 DELETE 同 enclosureUrl 再 INSERT，无事务，history_episode.dart:76-88）——两步之间存在崩溃窗口（行短暂消失，并发读会 miss）。播放完成 `removeTop` 连删 playlistEpisode + subtitle + translation 同样是逐条独立 await。

**原生建议**：合并为单事务。最终 DB 状态与旧版等价（原子性反而更严格），用户与回归测试均不可观察差异——典型的"内部机制自由"。文件删除（缓存音频）放在事务外，失败不回滚 DB。

（反例确认：`addMany` 用 sqflite batch，本身就是事务性的，✅ 对应 GRDB 单个 `write` 即可。）

### 1.3 可选值建模 ⚠️ P1

**Flutter 事实**：代码里遍布 `!` 强解包（`pubDate!`、`episodes[0]`、`channel.items!.sort`），《05》K5 已记录脏数据崩溃。

**原生建议**：Swift model 的可选性**如实镜像 schema**（description/pubDate/duration/author/lastUpdated 本来就 nullable，《01》§9 坑位⑦），边界处（RSS 解析、DB 读取）防御，`try!`/`!` 禁止出现在解析路径。这不是风格问题——`db_dirty` fixture 的用例直接依赖这一点。

### 1.4 ✅ 必须抵制的"最佳实践"（等价性优先）

两处 iOS 惯例会说"应该用 X"，但数据兼容要求保持 Y：

- **设置存 SQLite 单行**而非 UserDefaults——旧数据在那张表里，原生版必须继续读写同表（已定，重申防止实现时"顺手规范化"）；
- **播放队列即 DB 表**（playlistEpisode 按浮点 position 排序）而非内存队列+快照——同上，且锁屏/重启恢复语义依赖它。

---

## 2. 状态管理与生命周期（GetX → @Observable）

### 2.1 Rx → @Observable 语义映射 ✅ 基本吻合，两处要留心

GetX Rx = 同步读最新值 + Obx 按读取粒度自动重建；`@Observable` 属性同样是同步读，语义对得上。留心两点：

- `withObservationTracking` 是**一次性**跟踪（每次变更后需 re-arm），UIKit 绑定要写成 re-arm 循环或对高频属性改用 Combine/闭包回调；
- **每帧级更新不要走 observation**：mini player 进度条、卡片进度背景这类由 positionData 驱动的 UI，旧版就是 stream 直驱（`ever(positionData)`），原生用 periodic time observer / CADisplayLink 直驱视图，别套 observation（每帧 re-arm 是白付的开销）。

### 2.2 controller 生命周期 ⛔ P0 —— 最不应移植的 Flutter-ism

**Flutter 事实**：十几个 controller 在 widget `build()` 里 `Get.put`（main.dart:75-89）；Channel 页用 PopScope + **500ms 延迟** `Get.delete`（channel.dart 收尾）；`Get.lazyPut` 造成 180/300 竞态（《01》§2 已裁定）。这些是 Flutter 无所有权模型下的妥协，副作用是初始化时机不确定、清理靠延时玄学。

**原生做法**：
- **组合根（composition root）**：AppEnvironment 在启动时显式构造全部长生命周期对象（播放/缓存/设置/网络/认证），依赖以构造参数注入，服务定位器（`Get.find` 等价物）不出现；
- **页面级状态归 VC 所有**：ChannelController 之类随 VC `deinit` 消亡，PopScope+500ms 这类 hack 一个都不带过来；
- 这直接消灭"初始化竞态"这一整类 bug 的生存土壤（180/300 只是已显形的一个）。

### 2.3 启动时序 ⚠️ P1

**Flutter 事实**：main() 里 dotenv → AudioService.init → Firebase → Sentry(init 包裹 runApp)（main.dart:38-52；2026-09-22 二次核验更正，原文"dotenv → Sentry → AudioService.init → Firebase"顺序有误），然后 build() 里同步 Get.put 一把梭、各自的异步 `_load` 自由竞速；定时器在 controller onInit 里各自起。

**原生最佳实践**：显式启动 DAG，每步有确定先后：

```
Sentry → Firebase/RC 配置（不阻塞首帧）→ DB open/迁移/K25 兜底
→ settings 加载完成 → 恢复播放器指针（currentPlaylistId）
→ 调度全部定时器 → 首帧
```

关键点：**定时器（300s 自动刷新 / 15s 转写 / 10s 翻译 / 60s 裁剪）一律在 settings 加载完成后调度**——这从根上消除 180/300 竞态（比"裁定口径"更彻底），首启行为自然等于 DB 值。建议写进 M1 骨架任务。

### 2.4 全局错误弹窗 ✅（实现注记）

`ErrorHandler` 靠 `Get.context` 任意位置弹窗；原生等价物是 window 根 / topmost presented VC 上 present `UIAlertController`。行为等价（任何页面任何时刻 401/403 都能弹），实现常规，无需特殊设计。

---

## 3. UI 与网络的线程隔离、数据传递

### 3.1 数据流形状 ⚠️ P1（一条铁律 + 编译器帮忙）

**Flutter 事实**：单 isolate，网络回调直接更新主 isolate 的 Rx；只有 RSS 抓取/解析进 isolate。

**原生铁律**：URLSession completion 在任意队列；**decode/parse 一律 `@concurrent`，值类型（Sendable struct）是唯一跨界载体，落地 `@MainActor` 更新 @Observable**。禁止在后台队列触碰 @Observable / UIView。Swift 6 strict 模式会把越界直接变成编译错误——这正是《06》§4 说的"编译报错就是免费的架构评审"，但前提是模型层从第一天就是值类型（呼应 §1.1/§1.3）。

### 3.2 大 payload ⚠️ P1：50 订阅刷新的 RSS XML 合计可达数 MB，解码必须后台（《06》§4 已有条目，强调它在 300s 自动刷新路径上是常态而非边缘）；HTML show notes 见 §7.4。

---

## 4. 定时器与轮询（首页刷新方案）

### 4.1 常驻 Timer.periodic ⚠️ P1

**Flutter 事实**：15s 转写轮询、10s 翻译轮询、60s 裁剪、300s 自动刷新——四个常驻定时器，不看前后台、不看有没有活干（无 processing 项时 15s 空转）。

**iOS 事实与建议**：
- 后台挂起时 timer 本来就不跑 → 后台行为天然等价，无需处理；
- 前台侧用 DispatchSourceTimer / Task.sleep 循环，**scene 进入 background 时暂停、回前台 resume 并立即补一轮**（回前台那一下正好覆盖"后台错过了 15s 轮询"的用户预期，比旧版体验略好且观察不到节奏差异）；
- "无 processing 项时不起 15s 轮询、有了才起"是合法优化（空转没有任何可观察输出）——但**"有 processing 时 15s 一次"的节奏本身是《02》红线 5，不能动**。

### 4.2 自动刷新（300s）✅ 方案本身维持：前台常驻 timer + `refreshOnStart`（UIRefreshControl beginRefreshing 复刻）。**不要**引入 BGAppRefreshTask——那是后台刷新语义，行为会变（用户没见过"后台悄悄刷新"）。

### 4.3 进度 2s 落盘 ⚠️ P2：旧版独立 Timer.periodic + 独立数据源；原生已经有 periodic time observer（进度 UI 用），**同一个 observer 里做 2s 节流落盘**即可，少一个时钟、天然同步（K24 的 pause/退后台补存也挂同一处）。

---

## 5. 音频栈

### 5.1 单 AVPlayer + 应用层队列 ✅ 已定（《04》§9/《06》§6），维持。⚠️ P2 可选增强：临近结尾（如剩 30s）**预创建下一个 AVPlayerItem 并 prepare**，完成事件里直接 swap——不改"播完即删"的数据语义（removeTop 照旧），但消除换集时的网络静默间隙。属用户可感知的纯改善，采纳则按《00》规则登记。

### 5.2 AVAudioSession 激活策略 ⚠️ P1

方案已有"启动早期 setCategory(.playback) + setActive(true)"（必做项）。**补充两条最佳实践**：
- **pause/停止播放时 `setActive(false, options: .notifyOthersOnDeactivation)`**——让用户之前在听的 Spotify/播客恢复播放，这是音频 App 的平台礼仪，旧版由插件行为随机决定、未保证。旧版行为未知（插件默认），所以这是"不劣于 + 更礼貌"，登记增强；
- `setActive(false)` 在特定系统状态下会抛 `error 560030880`（其他 App 持有音频焦点），要吞掉——iOS 已知怪癖，不处理会成为新的崩溃源。

### 5.3 流播 + 下载"双倍流量" 💡 backlog（典型的轻重缓急取舍）

**Flutter 事实**：`autoSet` 未命中缓存时 `setUrl` 流播，**同时并行** `getFileStream` 整文件下载（audio_handler.dart:197-220）——同一字节拉两遍，用带宽换实现简单。这是旧版的隐性浪费，不是契约。

**新栈更优解**：`AVAssetResourceLoaderDelegate` 自定义 scheme 做单飞缓存（Kingfisher 思路），播放与缓存共享一次网络流。**但**：resource loader 在进程内执行，自定义 scheme 的 asset **可能无法 AirPlay**（系统转发需要能独立取流）——AirPlay 用户真实存在（耳机/音箱），CarPlay 在 backlog 但 AirPlay 不在。**建议：首版复刻双拉（等价、零风险），single-flight 列为独立调研项，先补 AirPlay 回归用例再动**。收益（省一半带宽）真实，但风险面大、非首版必须——这正是"轻重缓急"里放后面的那种。

### 5.4 锁屏 ±10s / NowPlayingInfo ✅ 已定（K1/K19），维持。

---

## 6. 缓存与下载

- **按"个数"LRU（默认 10）** ✅ 等价性要求保持——删除行为用户可见（《05》§5.5 有断言）。字节上限进 backlog 已定，勿在首版"顺手规范化"。
- **下载无取消** ✅→⚠️：URLSession `task.cancel()` 是免费的，删除条目时取消下载属"不差于旧版"（05 已允许）；注意 K3 连带删除语义优先于取消时序。

---

## 7. UI 实现细节

### 7.1 Tab 子 VC 预热 ⚠️ P1

**事实差异**：`IndexedStack` 是**全量立即挂载**（Discover Tab 从第一帧就构建好，切换零延迟）；`UITabBarController` 的子 VC **首次选中才 loadView**——不处理的话，首次点 Discover/Playlist 会有可感知的构建延迟，与旧版"秒切"不等价。
**做法**：启动时对三个子 VC `loadViewIfNeeded()`（一行，代价可控）。建议补进《07》§2.1"子 VC 常驻"一句。

### 7.2 列表更新 ⚠️ P2

旧版 ListView 变更是**无动画整表重建**。原生用 Diffable DataSource（惯用、高效），但 apply 默认带插入/删除动画——**这是用户可见差异**，除非按《05》§0.2"性能更好允许"豁免。建议：默认 `withoutAnimation` 保持等价，不自行升级；将来想要动画是一行业务决策，不是技术约束。

### 7.3 跑马灯触发判定 ⚠️ P2（从"错的近似"到"对的精确"）

**Flutter 事实**：`title.length × 24 > 可用宽`——按字符数估宽，CJK 与拉丁混排必然误判（中文字形 ≈字号宽，拉丁 ≈一半），实际表现是部分中文标题误跑马灯、部分英文长标题不跑。
**原生做法**：`NSAttributedString.boundingRect` 真实测宽再决定。严格说这是用户可见差异，但方向是从 bug 到正确（类似 K4/K5 的"崩溃类修复"逻辑）——建议登记为微增强条目（新 K），注明"触发条件由字符估算改为实测宽度"。

### 7.4 HTML show notes 渲染 ⚠️ P1

`NSAttributedString(html:)` 同步且**不宜在主线程**（新 iOS 打运行时警告 + 卡顿）。min iOS 18 下用 `NSAttributedString.loadFromHTML`（iOS 15+ 异步 API）在后台解析、主线程落地；100KB 病态 HTML 退 WKWebView（《07》§2.4 已提）。补充：**同一 description 会在 Detail 与播放器第 0 页各解析一次**，结果按 episode 缓存一份（内存即可，纯内部机制）。

### 7.5 图片 ✅ Kingfisher：后台解码、缓存策略对齐旧 maxNrOfCacheObjects=200/30 天即可；淡入时长注意与旧版 `cached_network_image` 默认（500ms）对齐，避免可见差异。

### 7.6 占位图 placehold.co 💡 P3

旧版占位图是第三方网络服务（`placehold.co`）——离线/该服务不可用则无图，还多一个外部依赖面。原生建议本地纯色/图标占位。可见差异极小、健壮性提升，登记后可做。

---

## 8. 第三方库（"不得不忍受它的逻辑"清单）

| 旧妥协 | 原生处置 | 判定 |
|---|---|---|
| flutter_chat_ui 强绑一套聊天框架 | ChatLayout 纯布局，自定义 cell 极薄——**换对了** | ✅ |
| flutter_chat_ui 自带输入栏 | InputBarAccessoryView 又是一个库：纯文本输入 **30 行自写**更划算（《07》§2.6 已留口子，建议定死自写，少一个依赖） | ⚠️ P3 |
| google_fonts 运行时拉字体（首帧字体闪烁） | TTF 打包——已是方案，首帧闪烁顺带消失 | ✅ |
| webfeed_plus（fork 维护） | FeedKit **可选**：若 G7 golden 对拍全绿，XMLParser 一个就够，可砍掉 FeedKit | ⚠️ P3 |
| modal_bottom_sheet/easy_refresh 自绘容器 | 系统件（A2/A4 已定） | ✅ |
| get（DI+路由+状态三合一巨石） | 组合根 + @Observable + UIKit 容器（§2.2） | ⛔ 见 §2 |

---

## 9. 汇总与采纳映射

| # | 条目 | 判定 | 优先级 | 建议落点 |
|---|---|---|---|---|
| 1.1 | DB 访问禁止出现在 @MainActor 栈；repository @concurrent + 值类型跨界 + 单 DatabaseQueue | ⛔ | **P0** | 《06》§4 增补 + M1 骨架任务 |
| 2.2 | 组合根替代 build() 里 Get.put；页面状态随 VC deinit；废除延时删除 hack | ⛔ | **P0** | 《06》§7 #24 增补 + M1 骨架任务 |
| 1.2 | history insert / removeTop 连删包事务（文件删除在事务外） | ⚠️ | P1 | 实现约定，写进 M1 数据层任务 |
| 1.3 | Swift 可选性镜像 schema；解析路径禁 `!`/`try!` | ⚠️ | P1 | 实现约定 |
| 2.3 | 启动 DAG：settings 加载完成才调度定时器 | ⚠️ | P1 | M1 骨架任务 |
| 3.1 | decode 在 @concurrent、Sendable struct 跨界、@MainActor 落地 | ⚠️ | P1 | 《06》§4 增补 |
| 4.1 | 定时器前后台感知（background 暂停 / 回前台补一轮）；空转不调度 | ⚠️ | P1 | 实现约定 |
| 5.2 | setActive(false, notifyOthersOnDeactivation) + 吞 error 560030880 | ⚠️ | P1 | 《05》§11 登记增强 + M2 任务 |
| 7.1 | 启动时三个 Tab 子 VC loadViewIfNeeded 预热 | ⚠️ | P1 | 《07》§2.1 增补 |
| 7.4 | loadFromHTML 后台解析 + 按 episode 缓存解析结果 | ⚠️ | P1 | 《07》§2.4 增补 |
| 4.3 | 进度落盘并入 periodic time observer 节流 | ⚠️ | P2 | M2 实现约定 |
| 5.1 | 下一集 AVPlayerItem 预创建（不改 removeTop 语义） | ⚠️ | P2 | 《05》§11 登记可选增强 |
| 7.2 | Diffable 默认 withoutAnimation（保持无动画变更等价） | ⚠️ | P2 | 《07》§2.2 增补 |
| 7.3 | 跑马灯按实测宽度触发（纠错级可见差异） | ⚠️ | P2 | 《05》§11 新 K 条目 |
| 5.3 | single-flight 缓存（AirPlay 风险，先补回归用例） | 💡 | backlog | 《05》§11 backlog 段 |
| 7.6 | 本地占位图替代 placehold.co | 💡 | P3 | 《05》§11 登记 |
| 8 | 砍 InputBarAccessoryView（自写输入栏）、可选砍 FeedKit | ⚠️ | P3 | 《07》§2.6 / 《06》§7 |
| 1.4 | 设置留 DB / 队列即 DB 表——**抵制** UserDefaults/内存队列的"规范化" | ✅ | — | 已定，防实现时顺手改 |
| 2.1 | 每帧 UI 不走 observation；Rx→@Observable 语义映射 | ✅ | — | 实现约定 |
| 4.2 | 自动刷新不引 BGAppRefreshTask | ✅ | — | 已定 |
| 6 | 缓存按个数 LRU 维持；下载 cancel 免费增强 | ✅ | — | 已定 |

**给 M1 骨架的三句话版**：① DB 与解码永不出现在主线程调用栈，跨界只传 Sendable 值；② 组合根显式构造一切，页面状态随 VC 生灭，settings 加载完成前不起任何定时器；③ 等价性只锁可观察行为，上面两条与一切内部机制按 Swift 最佳实践自由发挥。

---

## 10. 本次评审引用的代码事实（备查）

- `lib/models/history_episode.dart:76-88`：DELETE+INSERT 无事务；
- `lib/pages/feeds.dart:321-357`：saveNewEpisodes 内存合并后两次 addMany（batch 事务性）；
- `lib/main.dart:70-89`：Get.put 风暴位于 NavigationBarApp.build()；FeedEpisodeController lazyPut（180/300 竞态源，《01》§2 已裁定）；
- `lib/states/feed_episode.dart:121-133`：initAutoRefresher 一次性读 Rx 值建 Timer；
- `lib/states/subtitle.dart:25` / `translation.dart:20` / `player.dart:64-74、320-333`：15s/10s/60s/2s/1s 常驻定时器；
- `lib/utils/audio_handler.dart:197-220`：setUrl 流播 + 并行 getFileStream 整文件下载（双倍流量）；
- `lib/states/player.dart:105-115`：positionDataStream 四条件过滤（主 isolate stream 直驱 UI）；
- 《03》§2.10/《03》§4：跑马灯 `title.length × 24` 估宽判定；placehold.co 占位。

---

## 11. 第二轮：全量代码走查补充（以代码为源，补 §1–§10 未覆盖处）

> 覆盖范围：lib/ 全部页面/控制器/模型/API（login 页细节以《02》为准未重读）。与 §1–§10 重复的证据仅引用不重复展开。

### 11.1 渲染与解析（HTML/MD）

**先澄清一个事实：全 App 没有 Markdown 渲染路径**——show notes 只有两条路：`renderHtml`（HTML 白名单渲染，Detail/播放器第 0 页）与 `htmlToText`（去标签纯文本，卡片列表）。原生侧无需考虑 MD。

- ⚠️ P1 **解析无缓存且在 UI 线程**：`renderHtml` 每次 build 都执行 `sanitizeHtml`（完整 HTML 解析+白名单过滤，formatters.dart:80-110）；`htmlToText` 在**每张卡片每次 build** 都重新 parse HTML（card.dart:213）。100KB 级 show notes 反复解析是旧版列表卡顿的合理怀疑点。原生：解析一次按 episode（HTML）/按输入串（纯文本）缓存，后台执行（§7.4 已有方案，此处补证据：不是"可能慢"，是"结构性重复解析"）。
- ⚠️ P2 `ExpandableText` 的 TextPainter 测宽是正确做法（对比 §7.3 跑马灯的字符数估算），原生照此思路用 boundingRect 即可。

### 11.2 频道页（动效与数据获取）

- ⚠️ P1 **每次打开频道页都全量抓取并解析整个 RSS，且不落库**：`listAllEpisodes()`（subscription.dart:101-108）→ `fetchPodcastsByUrls(单 URL, onlyFistEpisode: false)`。可观察行为="频道页永远最新"（不依赖收件箱刷新）。原生**默认维持全量抓取**（等价）；可选的不可见优化是 HTTP 条件请求（ETag/If-Modified-Since，304 时结果相同），但多数播客服务器支持参差，列 P3 调研，不做首版依赖。
- ⚠️ P2 **palette 每次打开/每次换集都重新解码图片取色**：ChannelController._updateColor（states/channel.dart:36-43）与 PlayerController._updateEpisode（states/player.dart:232-249）每次都调 `updatePaletteGenerator`。原生：按 imageUrl 缓存取色结果（内存即可），颜色值不变、速度变快，用户不可见。
- ⚠️ P2 播放路径上的 `getOrFetch`：每次 `_updateEpisode` 查频道信息，DB miss 时（如搜索结果直接播放）会**在起播同时发起一次整频道 RSS 抓取**（subscription.dart:114-119）。原生：频道信息按 rssFeedUrl 做内存/DB 缓存，避免重复抓取（结果等价）。
- ⚠️ P1 折叠头实现注记：旧版是 SliverPersistentHeader 每 scroll tick 重算布局（ChannelHeaderDelegate.build）。原生用 07 已定的 pinToVisibleBounds + `scrollViewDidScroll` 插值，但**优先改 transform/anchor 约束而非重排子视图**（CALayer transform + opacity 代价远低于布局循环），手势语义与视觉不变。
- 💡 "Latest Episode" 按钮 `episodes[0]`（channel.dart:500）与频道内搜索 `e.title!`（channel.dart:760）都是强解包，空/NULL 即崩——归入 §1.3 可选值建模统一处理。

### 11.3 搜索

- 全局搜索：仅 submit 触发、limit 20、无搜索历史/联想——功能形态保持即可；输入防抖/历史属新增功能，不做。
- 频道内搜索：内存 `contains` 过滤已加载的 episodes（channel.dart:759-763），数据量 ≤ 单频道全集，原生同构即可，无索引需求。
- K4 的 `response!` 家族再+1：`searchEpisodes` 里 `parsePubDate(...)!.millisecondsSinceEpoch`（api/podcasts.dart:77）——release_date 为 null 即崩，与 K4 同修。

### 11.4 勿移植清单（模式怪癖，第二轮新证据）

| 旧实现 | 原生处置 |
|---|---|
| `move()` 换序涉 index 0 时 `sleep(100ms)` **同步阻塞主 isolate**（playlist_episode.dart:107-119）——最高风险手势路径上的可感知卡顿，且 sleep 本身是 cargo cult（单 isolate 内等待无意义） | 直接去掉：pause → await 重排 → setByEpisode 顺序化。属"消除缺陷"级改善，登记后纳入 |
| `MyAudioHandler()` factory 单例 + 各处 `static final MyAudioHandler()`（player.dart:417/1031、states/player.dart:41/285）——能工作但初始化顺序脆弱 | PlaybackService 由组合根持有（§2.2），UI 只经 PlayerController 调用 |
| `BottomNavBar.static final playerController = Get.find(...)` 类字段期求值 | 组合根注入 |
| ShareController 冷启动分享 `Future.delayed(2s)` 再弹窗（states/share.dart:47-53）——魔法延时等 UI 就绪 | scene/首帧就绪回调后展示，无任意延时 |
| `Get.put(HistoryController())`/`Get.lazyPut` 循环写在 build() 里（playlists.dart:29,36-41；feeds.dart:26；discover.dart:803） | 构造期/组合根注册（§2.2） |
| 生产代码 `print(...)`（feeds.dart 移除按钮等） | 删除，Sentry breadcrumb 替代（如需要） |

### 11.5 新发现的数据/契约语义（须进等价测试或登记决策）

这一组是本轮最重要的产出——**三处会影响回归断言的隐藏语义、两处建议登记的行为修正**：

1. ⚠️ P1 **每次恢复播放都会把该集顶到历史最新**：`play()` 在 audioSource 已存在（即"从暂停恢复"）时也执行 `HistoryController.insert`（states/player.dart:169-173）→ DELETE+INSERT → 行 id 改变、排到最前。含义：暂停/继续 N 次 = 历史里该集刷新 N 次 id。这是数据层"操作逻辑"，**默认复刻**，并补《05》§2.3 断言（pause→resume→history 行移动到顶、id 变化）。
2. ⚠️ P1 **聊天 history 数组包含"当前这条 user_input"**：sendMessage 先 insertMessage(userMsg) 再从 messages 取最近 10 条构造 history（states/chat.dart:29-40）→ 当前输入同时出现在 `user_input` 与 `history` 末元素。**这是会改变 AI 回答的契约细节**：G13 golden 与 L2 请求断言必须逐字节包含这个重复，不得"顺手去重"。
3. ⚠️ P2 **改 autoRefreshInterval 会立即重启定时器，但 picker 每 tick 都重置一次**（§12.4 更正，原表述有误）：`setAutoRefreshInterval` 末尾调用 `initAutoRefresher()`（states/player.dart:459-466）→ 先 cancel 再按新值重建 Timer.periodic；因 CupertinoPicker 的 onSelectedItemChanged 每 tick 触发，**滚动选择过程中定时器每 tick 被取消重建**（周期从零重计）。复刻要点：改动即时生效 + 接受滚动期重置。
4. 🔧 登记 **后台轮询的错误弹窗与中断语义**：15s 轮询的每次非 2xx 都会 `ErrorHandler.handle` **弹模态错误框**（api/subtitles.dart:44-47）——token 过期时登录页会随机弹出、Cloudflare 429 弹 Error 429；且任何一次瞬时 5xx 都会把本地 processing 记录删掉、UI 回到 Generate 按钮（subtitle timer 的 failed 分支）。建议原生：**用户主动触发的 add() 保持弹窗；后台轮询的错误静默**（5xx/超时保持 processing 继续轮询——服务端按 enclosure_url 幂等不重复计费，《02》§7；401 仍走登录页）。属行为改变，按《00》规则进《05》§11 新 K。
5. 🔧 登记 **翻译失败永久重试**：`getTranslation` 返回 null（HTTP 错误/translation:null）后 `translationUrls` 停在 'processing'，10s 定时器**每拍重发 forever**（states/translation.dart:44-77），UI"Translating subtitles..."常驻、服务器被打。K9 已定 30s 超时+异常捕获，补：**重试上限（如 5 次退避）+ 失败后展示原文并移除 Translating 条**。属行为改变，并入 K9 的原生实施口径。

### 11.6 UI 更新模式与杂项

- mini player（bottom_nav_bar.dart:86-240 整个 Obx 读 positionData）与播放列表当前集卡片（card.dart:46-96）都是**每 position tick 全组件重建**——Flutter 下可容忍，原生必须走 layer 直驱（§2.1 已定原则，此为两个具体热点的证据）。
- ⚠️ P2 **Discover 随首帧即发起 /api/categories**：IndexedStack 全量挂载 ⇒ 启动即请求即使用户没打开 Discover（discover.dart:730-732）。§7.1 的 Tab 预热若照做 loadViewIfNeeded 会自然复刻该行为（保持）；若只想预热视图不预取数据，首次打开 Discover 变慢——**二选一须与旧版对齐：预热视图+照常预取**。
- ⚠️ P2 **历史列表 Marquee 无条件滚动**（playlists.dart:342-355，不测宽，短标题也滚）——与播放器标题的"测宽才滚"不同。MarqueeLabel 映射时注意：历史行=always scroll（配 startAfter≈1s 等效参数），播放器标题=overflow 才滚（§7.3）。两处行为不要互相污染。
- 💡 P1 `exportSubtitles` 用 `$title - $channel.txt` 作文件名（player.dart:968）——标题含 `/` 等非法路径字符时写文件抛异常，导出必崩。原生 sanitize 文件名（崩溃类修复，同 K4/K5 性质）。
- 💡 占位图域名笔误证据补全：channel/card/detail/history 用 `placeholder.co`（疑为 `placehold.co` 笔误，channel.dart:304、card.dart:146/379、detail.dart:536、playlists.dart:330），player.dart 用 `placehold.co`——多数占位图可能从未加载成功。§7.6 本地占位方案顺带修复，无需保留域名差异。
- 💡 `SubscriptionController.remove` 的 `removeAt(indexWhere==−1)` 潜在 RangeError（states/subscription.dart:35-40）——guard 归入 §1.3。

### 11.7 第二轮汇总（并入 §9 采纳映射）

| # | 条目 | 判定 | 优先级 | 落点 |
|---|---|---|---|---|
| 11.1 | HTML/纯文本解析按输入缓存 + 后台执行 | ⚠️ | P1 | 《07》§2.4 增补 |
| 11.2 | 频道页维持全量抓取；palette/频道信息按 URL 缓存 | ⚠️ | P1/P2 | 实现约定 |
| 11.2 | 折叠头用 transform 而非布局重排 | ⚠️ | P1 | 《07》§2.3 增补 |
| 11.3 | `parsePubDate!` 并入 K4 修复 | 💡 | P1 | 《05》K4 补出处 |
| 11.4 | sleep(100ms)/factory 单例/魔法延时/build 内注册/print 清单 | ⛔ | P1 | 实现约定（勿移植） |
| 11.5-1 | 恢复播放顶历史 → 复刻 + 补 §2.3 断言 | ⚠️ | P1 | 《05》§2.3 增补 |
| 11.5-2 | 聊天 history 含当前消息 → G13/L2 逐字节复刻 | ⚠️ | P1 | 《05》§1.5 G13 备注 |
| 11.5-3 | autoRefreshInterval 改动即时重启定时器（picker 每 tick 重置）→ 复刻 | ⚠️ | P2 | 实现约定（§12.4 已更正） |
| 11.5-4 | 后台轮询错误静默 + 5xx 继续轮询 | 🔧 | P1（登记） | 《05》§11 新 K |
| 11.5-5 | 翻译重试上限 + 失败态 | 🔧 | P1（并入 K9） | 《05》K9 增补 |
| 11.6 | 导出文件名 sanitize | 💡 | P1 | 《05》§11 新 K（崩溃类） |
| 11.6 | Tab 预热含 Discover 预取；历史 Marquee always-scroll 配置 | ⚠️ | P2 | 《07》§2.1/§2.4 增补 |
| 11.6 | 本地占位图（含 placeholder.co 笔误证据） | 💡 | P3 | 《05》§11（§7.6 已有） |

---

## 12. 第三轮：8 路子代理全量走查合并（2026-09-22）

> 方法：8 个并发只读代理逐行走查 lib/ 全部与 ios/ 目录（各带同一评审简报与已知结论排除清单），返回约 200 条原始发现。本节是**全局过滤 + 去重 + 抽查验证后**的采纳集；标 ✅ 的条目我已亲自复核源码。此方法的价值已自证：它纠正了 §11.5-3 的错误结论，并发现了下面第 1 条这种单靠通读容易滑过去的算法级缺陷。
> 代理结论仅作参考的两个实例：其一称 clear() 后"启动即崩"——实际 Dart 未捕获 async 异常不崩 App，正确表述是"恢复静默失败"（见 12.1-3）；过滤是必要的。

### 12.1 必修级新发现（实施前必须拍板）

1. ⛔✅ **下移拖拽不落库（off-by-one）**：`insertOrUpdateByIndex`（models/playlist_episode.dart:90-125）对"已存在条目的移动"用**移动前的 DB 列表**取邻居——上移（from>to）恰好正确，**下移（to>from）算出的中点落在旧位置**，间隙 ≥0.0005 时永不触发 `_reorder` 兜底 → 下移拖拽重启后回退（会话内 UI 是对的）。推演：[A,B,C,D] 拖 A 到 index2 → 内存 [B,A,C,D]，DB 写 A.position=(A旧0+B1)/2=0.5 → 重载仍 [A,B,C,D]。**连锁影响测试设计**：G1/G2 golden 若原样导出旧算法输出，原生"修复版"对拍必失败——需先拍板（建议：修，同 K4/K5 的缺陷修复逻辑），G1/G2 拆成"插入场景逐字节复刻旧算法 / 移动场景按正确语义断言"两部分。进《05》§11 新 K。
2. ⛔✅ **duration 为 NULL 的集陷入无限重建循环**：MyProgressBar 的 Obx 里 `duration==zero → initProgress()`（player.dart:426-429），而 initProgress 对无时长元数据的集写回的 duration 仍为 0 → 条件恒真，且 PositionData 未实现 `==`（每次新实例都触发）→ 热循环直到真实播放事件。修复：记忆进度展示移出渲染路径（崩溃类）。
3. ⛔✅ **clear() 后重启，播放状态恢复静默失败**：`clear()` 删 player 行而默认行只在建库时插入；重启后 `PlayerModel.get` 对空结果 `maps[0]` 抛 RangeError（models/player.dart:49-55，未捕获 async → 不崩但 load 链断）→ 队列在、当前曲与进度不恢复。原生：缺行视为"无播放状态"。进《05》§2.3 断言 + 新 K。
4. ⛔✅ **Share Extension 的编译依赖是方案级缺口**：扩展 `import receive_sharing_intent`（ShareViewController.swift:10），该模块由 Runner 的 pods 经 `inherit! :search_paths` 供给；插件是 **git 依赖且本机 pub-cache 副本已不存在**。"保留 Extension 原样"必须附带其一：继续以 pod/SPM 拉该 git 仓库，或把插件 Swift 源（Constants/SharedMediaFile/SharedMediaType，量很小）vendor 进扩展 target。**建议补进《00》M1 任务与《05》§11 对应决策**。
5. ⚠️✅ **RC configure 与 Firebase 恢复的顺序竞态**：RC 在 controller onInit 同步 configure，此刻 Firebase 登录态异步恢复大概率未完成 → appUserID 实际靠后续 authStateChanges 的 `logIn(uid)` 补绑；若 authStateChanges 先于 configure 完成触发，logIn 因 RC 未就绪抛错且只 print、**整个会话 RC 保持匿名**（states/user.dart:261-265 + main.dart:85-86 顺序）。原生：configure 完成后再 logIn、失败重试——正是 §2.3 启动 DAG 的具体用例，进 M1 骨架。
6. ⚠️✅ **subtitle 轮询的 ConcurrentModificationError**：15s timer 在 `for (url in subtitleUrls.keys)` 迭代中调 `remove(url)`（states/subtitle.dart:29-47）→ 抛 CME、该轮中断（下一轮恢复）。原生遍历快照，勿照抄。
7. ⚠️ **登录页重复请求风暴**：订阅信息卡 `FutureBuilder(getUser())` 在 Obx 内联（login.dart:323-324）→ customerInfo 每次变化重发 `GET /api/user`；offerings 同理（login.dart:469-477，且 `offerings.current!` 强解包）。原生：进页取一次 + 缓存；401 弹层还会叠加（handle401 无去重）。

### 12.2 契约/数据语义补充（进等价测试）

- **addToPlaylist 插入位置规则**：目标列表是当前播放列表且非当前集 → 插到 index 1（不扰动队首）；否则插顶；恰为当前集 → 返回现有行不动（states/feed_episode.dart:80-100）。
- **mediaItem 时序**：setByEpisode 发起加载后**立即**更新 mediaItem（不等加载完成）；`setUrl/setFilePath` 的 Future 被丢弃、加载失败静默；initialPosition 是加载期参数而非加载后 seek（audio_handler.dart:197-220）——M2 状态机时序断言的来源。
- **播放完成链**：completed → removeTop → 空：pause+clear；非空：playByEpisode(新队首) 后 `!continuousPlaying` → pause + 100ms 后 initProgress（states/player.dart:81-104）。
- **搜索结果卡与 Inbox 卡的按钮语义不同**：播放不从任何列表移除、加列表无飞入动画（discover.dart:251-292）——回归清单按两种卡分别断言。
- **同会话内重开频道页不刷新剧集**：`Get.lazyPut(ChannelController, tag)` 不删除、复用旧实例（card.dart:332-341 / player.dart:401-410）——可见语义，登记复刻（原生：频道 VM 按 URL 缓存，随 sheet 关闭释放或保留需拍板，默认保留=复刻）。
- **手动下拉刷新与 300s 定时刷新无互斥**，可并发两轮 fetch（autoFetch 的 1 分钟 guard 只挡自动路径）；进度回调传 chunk 起始下标（rss_fetcher.dart:153），两条进度公式不同（2026-09-22 更正原"永不走满"表述）：**导入 `p0/p1`（import_export.dart:86）永不走满**（分子是批起始下标，末批 < 1）；**刷新 `(progress+8)/total`（feeds.dart:313）末批 overshoot ≥1、经 widget clamp 会走满**——两者分别复刻。
- **冷启动分享弹窗 `barrierDismissible:false`**（热路径无此参数）；处理后必须 `reset()` 清 ShareKey；主 App 需注册 `ShareMedia-com.kindjeff.anycast:share` scheme，冷启动走 launchOptions/connectionOptions、热启动走 openURLContexts——**新工程改 UIScene 生命周期后回调入口不同，注意迁移**。
- **扩展 bundle id 推导规则**：ShareViewController 去掉扩展 id 最后一个 `.` 段反推宿主 id → 新工程扩展 id 必须保持 `<宿主id>.<后缀>` 形态且宿主仍为 com.kindjeff.anycast。
- **PlayerPage 背景渐变未包 Obx**（player.dart:51-62）→ 换集时背景色不更新、重开播放器才对——可见怪癖，登记后决定复刻或修复。
- 'failed' 转写分支无 Expanded（布局与其他态不一致）；PlayPauseAnimation 的正确显示靠"读旧值取反"的碰巧竞态（player.dart:755-761）——原生显式计算目标状态。

### 12.3 崩溃路径与小笔误清单（并入 K4/K5 修复族）

- 崩溃族补遗：`seekByRelative` 的 `_player.duration!`（时长未知即崩）；discover `episodes[index].episode!`；`moveToTop` 按 id 匹配（null==null 会移错条）；`toMediaItem` 的 `imageUrl!`；`getPlaylistPosition` 强转；导出 OPML 的 `title!/description!`；`urlToDomain` 畸形 URL；`handle403` 的 as 强转；`getUser` 的 jsonDecode 在 try 外（500 HTML → UI 永卡 '...'）。
- 笔误族：**反馈邮箱 UI 显示与 mailto 实发不一致**（kindjeff.com@gmail.com vs kindjeffcom@gmail.com，需拍板以哪个为准）；"Import  successfully" 双空格；空 OPML 也弹成功；'playlits' tag 拼写；EmailLogin 大段死代码（注册流程注释）；writeOPML/CenterPlayArrow/`updateProgress` 死代码；AIIcon default 分支忽略传入 color；PlayIcon loading 态用 `color == Colors.white` 判黑白 spinner。
- iOS 新工程易漏键：`ITSAppUsesNonExemptEncryption=false`；扩展 `CFBundleVersion=$(FLUTTER_BUILD_NUMBER)` 在无 Generated.xcconfig 的扩展 target 上**解析为空字符串**（已随 38 个 build 上架，新工程给显式值即可，勿照抄悬空引用）；扩展显示名 = `INFOPLIST_KEY_CFBundleDisplayName="Share Extension"`（分享面板里显示的就是它）；扩展的 `AppGroupId` Info key 与 `CUSTOM_GROUP_ID` build setting **二者缺一即运行时崩溃**（containerURL 强解包）。

### 12.4 对本文档的更正

- **§11.5-3 原结论错误，已更正**：`setAutoRefreshInterval` 会立即调 `initAutoRefresher()` 取消并重建定时器（states/player.dart:461-466，本次由两路子代理独立指出、我复核源码确认）。真实怪癖是"picker 滚动过程中每 tick 重置定时器"。教训与《00》修订规则一致：**事实以代码为准，子代理走查 + 人工复核的双保险值得保留为流程**。
