# 技术选型调研（iOS 原生）

> 调研时间：2026-09-21（iOS 27 刚发布、Xcode 27 周期）。所有库的版本/维护状态均通过 GitHub Releases / Swift Package Index 逐一查证。
> 结论先行，依据在后。带 ⭐ 的是推荐项。

---

## 1. 总推荐（一张表）

| 决策点 | 推荐 | 备选 |
|---|---|---|
| UI 框架 | ⭐ **UIKit 为主 + `@Observable` 模型层 + 局部 SwiftUI**（详见 §2，尊重你的 UIKit 直觉，且有充分理由） | SwiftUI 为主 + 播放器 UIKit |
| 最低部署目标 | ⭐ **iOS 18（已定稿）**（iOS 26/27 特性走 `#available` 降级） | — |
| 并发模型 | ⭐ Swift 6.2 Approachable Concurrency（默认 MainActor + `@concurrent` 后台） | — |
| 数据库 | ⭐ **GRDB.swift**（唯一能直接打开旧 `anycast.db` 的选项） | — |
| 网络 | ⭐ URLSession async/await（零依赖） | Alamofire |
| 播放 | ⭐ AVPlayer + AVAudioSession + MPNowPlayingInfoCenter/MPRemoteCommandCenter（iOS 27 起可切新 Now Playing 框架） | — |
| 状态管理 | ⭐ `@Observable` 宏 + @MainActor 控制器（无框架） | TCA（不推荐此项目） |
| 图片 | ⭐ Kingfisher | Nuke |
| 付费 | ⭐ RevenueCat purchases-ios（沿用） | — |
| 登录 | ⭐ Firebase iOS SDK + GoogleSignIn-iOS 10.x（沿用） | — |
| 崩溃监控 | ⭐ sentry-cocoa（沿用 DSN） | — |
| HTML 清洗 | ⭐ SwiftSoup | — |
| RSS 解析 | ⭐ FeedKit + Foundation XMLParser（OPML/podcast: 命名空间自写） | 全自写 XMLParser |
| 字体 | ⭐ 字体文件打包（UIAppFonts） | — |
| 测试 | ⭐ Swift Testing（新测试）+ XCTest（UI/性能）+ swift-snapshot-testing + URLProtocol/Replay 回放 | — |

真正需要引入的第三方约 10 个：**GRDB、Firebase/GoogleSignIn、RevenueCat、Sentry、Kingfisher、SwiftSoup、FeedKit（可选）、lottie-ios、ChatLayout（聊天 UI）、MarqueeLabel（跑马灯）**——UI 层不引入任何整体框架，其余全部系统框架或小规模自绘（《07》）。这仍是原生迁移最大的红利。

---

## 2. UIKit vs SwiftUI（2026 年现状与本项目建议）

### 2.1 平台现状（查证）

- **没有任何 UIKit 弃用迹象**。WWDC26 反而新增 "Modernize your UIKit app" 专场；iOS 26 给 UIKit 补齐了 Liquid Glass 全套 API（`UIGlassEffect`、`UIGlassContainerEffect`、`UIBarButtonItem.glass()`）；iOS 27 给 UIKit 新增 `UITabAccessory`（系统级底部迷你播放器）、iPhone 侧边栏、可缩放改造等——**Apple 官方口径是长期共存、增量迁移**（session 272 "Use SwiftUI with AppKit and UIKit"：自家 App（Logic Pro、Xcode）就是混合体，"no expectation that an app become fully SwiftUI"）。
- 社区主流（dev.to 2026、Hacking with Swift 等）是"SwiftUI 为主，撞墙落回 UIKit"；但反方声音一直存在（2026-06 Daring Fireball 转载批评文），争论未终结。
- 2026 年起 `@Observable` 模型可同时驱动 UIKit（`draw/layout` 自动 observation tracking，iOS 18 起 `UIObservationTrackingEnabled`，2026 系统默认开）与 SwiftUI——混合架构的官方粘合剂已成熟。
- 混合的坑（实测文献）：`UIHostingController` 有独立 environment、尺寸协商开销、高频状态跨桥性能问题——桥接应"小片"而非整屏。

### 2.2 对本项目的具体分析

**支持 UIKit 为主的理由（适用于 Anycast）**：
1. 这个 App 的 UI 是**高度自定义的暗色设计**（非系统风格）：全屏 modal sheet 栈、手写视差折叠头、自定义歌词滚动、拖拽排序无把手、跑马灯、自绘进度条/滑条 thumb、中央形变动画——SwiftUI 做这些一样要大量自定义（甚至 `UIViewRepresentable` 包 UIKit），SwiftUI 的"声明式省代码"红利在这里很小；
2. Liquid Glass 的自动受益给用系统组件的 App——采用《07》定稿的**原生优先边界**（系统 chrome 全部换系统组件、仅保留设计语言与少量自绘）后，Anycast 可以吃到绝大部分玻璃效果，UIKit 侧的 `UITabAccessory`/`UIGlassEffect` 等 API 完整可用；
3. 你本人倾向 UIKit 且可长期维护是第一优先级。

**SwiftUI 仍值得局部使用的场景**（同一套 `@Observable` 模型，不冲突）：
- 设置页这类表单列表（静态、系统风格）；
- 登录页表单；
- 未来新功能页。

**关键提醒**：iOS 26 的 `UITabAccessory` + `tabBarController.bottomAccessory` 是官方"Apple Music 式 mini player"组件——Anycast 的 mini player 正是这个形态，建议 iOS 26+ 用它、iOS 18 用自定义视图降级（正好符合"尽量用原生组件"的愿望）。iOS 27 的**新 Now Playing 框架**（声明式 `MediaSessionRepresentable`，取代 MPNowPlayingInfoCenter/MPRemoteCommandCenter，自动同步锁屏/控制中心/灵动岛/StandBy/CarPlay）对播客 App 是白拿的能力，同样 `#available` 双路径。

### 2.3 结论

⭐ **UIKit 为主（Tab/导航/列表/播放器/歌词/所有自定义交互）+ `@Observable` 模型层贯穿 + 表单类新页面可用 SwiftUI**。不引入任何 UI 桥接大架构，桥接只做小片。

---

## 3. 最低部署目标：iOS 18（已定稿）

**决策**（2026-09-21 拍板）：min target = **iOS 18**。iOS 26/27 专属能力（Liquid Glass 组件、`UITabAccessory`、新 Now Playing 框架）一律 `#available` 分支 + iOS 18 降级 UI。

**依据**：
- iOS 26 与 iOS 27 的设备边界重合（均为 A13/iPhone 11+）；**iOS 18 的设备边界更宽**——A12 机型（iPhone XS/XR）能升到 18 但永久停在 18，选 18 即把这批存量也纳入可升级范围，同时获得现代 API 基线：Observation（`@Observable`）、UISheetPresentationController 自定义 detents、Swift Testing 全部可用；
- 不选 iOS 26：会立刻失去约 20% 存量设备（含永远无法升级到 iOS 26 的 A12 机型上的付费用户）；
- **已接受的权衡**：现网 Flutter 版 min 15，iOS 15–17 的用户将停留在 Flutter 最后一版、无法升级到原生版（min target 只影响"谁能升级"，不影响旧版继续可用）。发布后可用 App Store Connect 的 Platform Version 报表持续观察这部分占比。

**背景数据**（2026 年查证）：iOS 26 已装于约 79% 全量 iPhone（近 4 年机型 86%，2026-06 口径）；iOS 18.x 约 10–13%；iOS 26/27 均要求 A13（iPhone 11+），iPhone XS/XR（A12）永久停在 iOS 18；iOS 27 刚发布仍在爬坡。

---

## 4. 并发模型：Dart isolate → Swift

**查证结论**：Swift 6.2（Xcode 26 起，2026 年新工程默认）的 Approachable Concurrency 已完整覆盖 isolate 的所有用途；Swift 是真多线程，**不需要 isolate 等价物**——重活只要不在 MainActor 上执行即可。

| Anycast 里的 Dart 用法 | Swift 对应 | 说明 |
|---|---|---|
| RSS 批量抓取：独立 isolate + `Future.wait` 每批 8 并发（rss_fetcher.dart:75-157） | `withTaskGroup`/`withDiscardingTaskGroup` 扇出，每批 8 个 child Task；或 `AsyncChannel` 汇聚 | 结构化并发天然支持取消与背压 |
| OPML 大文件解析防卡 UI | 解析函数标 `nonisolated` + Swift 6.2 的 `@concurrent`（强制跑并行池）；或 `Task.detached(priority: .utility)` | `JSONDecoder`/`XMLParser` 值语义，后台执行安全 |
| 巨型 RSS（1000 items）解析 | 同上；必要时专门 `actor ParseEngine` | 用 Instruments Hangs 模板验证（回归测试 §9 有对应用例） |
| 可变共享状态（播放器/缓存控制器） | `actor`（如 `actor CacheStore`）；播放器 UI 状态用 `@MainActor final class` | Swift 6 strict concurrency 编译期消数据竞争 |
| http 客户端 | `URLSession.data(for:)` async | 原生 async/await |

实践法则：**UI 层默认 MainActor；IO/CPU 层 nonisolated/@concurrent + actor；不写 GCD 队列配对**。Swift 6 语言模式的编译报错本身就是免费的架构评审。迁移期可先用 Xcode 默认（Swift 5 模式 + Approachable Concurrency），逐模块收紧。

**架构铁律（2026-09-22 自《08》并入，M1 骨架即生效、当 lint 用）**：

1. **DB 访问不允许出现在 @MainActor 调用栈上**。GRDB 的 `read {}` / `write {}` 是同步阻塞调用；sqflite 时代由插件后台线程白送的"UI 永不因 SQL 阻塞"保护消失了，而 Swift 6 对"MainActor 上调用阻塞函数"**完全不报警**（合法代码、静默性能陷阱）。分层：`@MainActor` controller ↔ repository（`@concurrent`/nonisolated 函数或 `actor`）↔ 单个 `DatabaseQueue`（天然串行化免锁、**不启用 WAL**——DatabaseQueue 默认保持 rollback journal，正好满足《05》§2.4 写回兼容；勿用 DatabasePool）。跨界载体只用值类型（`Codable + Sendable` struct），不传数据库连接、不传可变引用。
2. **网络解码与 HTML/RSS/JSON 解析一律 `@concurrent`**，值类型是唯一跨界载体，落地 `@MainActor` 更新 `@Observable`；禁止在后台队列触碰 @Observable / UIView。大 payload（50 订阅刷新的数 MB RSS XML）的解码是 300s 自动刷新路径上的常态，不是边缘。
3. **组合根（composition root）**：AppEnvironment 在启动时显式构造全部长生命周期对象（播放/缓存/设置/网络/认证），依赖以构造参数注入；服务定位器（`Get.find` 等价物）、build() 里注册、`lazyPut`、延时删除一律不移植（《08》§2.2——GetX 生命周期 hack 是 Flutter 无所有权模型下的妥协，副作用是初始化竞态与清理玄学）。
4. **启动 DAG**：Sentry → Firebase/RC 配置 → DB open/迁移/K25 → settings 加载完成 → 恢复播放器指针 → 调度全部定时器 → 首帧。定时器（300s/15s/10s/60s）一律在 settings 加载完成后调度，从根上消除 180/300 竞态；RC `configure` 完成后才 `logIn(uid)`（《08》§2.3/§12.1-5）。

---

## 5. 数据层：GRDB（决定性理由）

| 候选 | 2026 状态（查证） | 能否直接打开旧 `anycast.db` |
|---|---|---|
| ⭐ **GRDB.swift** | v7.11.1（2026-06），活跃，Swift 6/Sendable 原生支持，迁移系统成熟，FTS5 | **能**。标准 SQLite 文件直接打开；把旧 schema 作为 migrator 起点续写版本 |
| SwiftData | iOS 26 修了一批 bug 但复杂查询/迁移/CloudKit 短板仍在（大量"回退 Core Data/GRDB"的生产案例） | **不能**（自管 schema 元数据） |
| Core Data | 成熟但重 | **不能**（同上） |
| SQLite.swift | 维护迟缓（141 open issues） | 能，但不推荐 |

对本项目的具体做法：首启只读打开 `Documents/anycast.db` 验证 schema（`PRAGMA user_version` 应为 4）→ GRDB migrator 从 v4 续写 → 保持旧 schema 写入（回滚安全，见测试方案 §2.4）。注意 sqflite 未启用 WAL（rollback journal），首启遇到 `-journal` 残留让 SQLite 自行恢复即可。

---

## 6. 音频栈（详见《04-baseline-audio.md》§9 映射表）

- **播放**：单 `AVPlayer`（复刻"单源 + 应用层队列"架构最直接；`AVQueuePlayer` 会改变"播完即删"语义，不建议）；`seek(to:toleranceBefore:0, toleranceAfter:0)`、`addPeriodicTimeObserver` 对应 positionDataStream。
- **会话**（激活策略 2026-09-22 修订，《08》§5.2 原方案"启动即 setActive(true)"会让**冷启动打断他 App 音频**——旧版（just_audio 插件行为，《04》§2.4）激活只随起播发生，冷启动/浏览不打断他 App，等价性要求新版本一致）：
  - 启动早期只 `AVAudioSession.setCategory(.playback)`——**这是迁移必做项**（原生不显式设置 category 则后台播放会断；setCategory 本身不抢音频焦点，随时可做）；
  - **首次起播前**才 `setActive(true)`（AVPlayer 在 .playback 下 play() 会隐式激活，显式调用便于捕错与打断恢复）；
  - 暂停**保持激活**（锁屏 Now Playing 卡片不消失，等价旧版插件行为）；
  - 队列播空/stop 时 `setActive(false, options: .notifyOthersOnDeactivation)`——让用户之前在听的 Spotify/播客恢复，平台礼仪增强；
  - `setActive(false)` 在其他 App 持有音频焦点时会抛 `error 560030880`，要吞掉（iOS 已知怪癖，不处理会成为新崩溃源）；
  - 监听 `interruptionNotification`/`routeChangeNotification`（K18 增强，旧版零处理）。
  回归断言见《05》§5.3 新增行（他 App 播放中冷启动本 App → 他 App 不受影响）。
- **锁屏**：iOS 18–26 用 `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter`（`skipBackward/skipForward` 的 `preferredIntervals=[10s]` 精确复刻 ±10s 怪癖）；**iOS 27 起切新 Now Playing 框架**（`MediaSessionRepresentable`，内置 Podcast content type，`#available` 双路径）。
- **倍速**：`player.rate` + `audioTimePitchAlgorithm = .timeDomain`（语音质量、支持 1/32–32x，7 档覆盖）。
- **下载缓存**：`URLSession.downloadTask`(delegate 进度) + 保留旧元数据库映射（见《01》§4.1，文件名是 UUIDv1、映射在 `anycast_episode.db`）。
- **第三方封装库不可用**（查证：SwiftAudio 仓库已删除 404、SwiftAudioPlayer 2022 年停更、MonsterPod/Ariadne 不存在）——自建 `PlaybackService`，反而少一个弃维护风险。
- **skip silence / EQ**：iOS 无公开 API；现网本就无效/未实现，等价 = 不做（详见测试方案 §11 K2）。
- **CarPlay**（可选二期）：`CPTemplateApplicationScene` + `CPNowPlayingTemplate`，需申请 entitlement；WWDC26 起播放类 App 自动获得 MiniPlayer。工作量 1-2 周级。

---

## 7. 依赖逐项对照表（26 项全查证）

| # | Flutter 依赖 | iOS 推荐 | 2026 维护状态 | 一句话理由 |
|---|---|---|---|---|
| 1 | sqflite | ⭐ **GRDB.swift** | 活跃（v7.11.1, 2026-06, Swift 6.1+） | 直接复用现有 SQLite 文件与 schema |
| 2 | just_audio + audio_service | ⭐ AVPlayer + AVAudioSession + MPRemoteCommandCenter | 系统（第三方封装已全灭：SwiftAudio 404） | 系统 API 一步到位，无弃维护风险 |
| 3 | firebase_auth + google_sign_in | ⭐ Firebase iOS SDK 12.x + GoogleSignIn-iOS 10.x | 双双活跃（12.19.2 / 10.0.0, 2026-09） | credential 流程与 Flutter 一一对应；注意 GoogleSignIn 10.0 最低 iOS 15 |
| 4 | purchases_flutter | ⭐ RevenueCat purchases-ios 5.90+ | 极活跃（2026-09-18） | 保留现有订阅体系与 uid 对应 |
| 5 | http | ⭐ URLSession(async/await) | 系统 | 零依赖最干净；Alamofire 5.12.2 活跃可选 |
| 6 | sentry_flutter | ⭐ sentry-cocoa 9.29+ | 极活跃（2026-09-17） | 配置直接平移 |
| 7 | webfeed_plus + xml + sanitize_html | ⭐ FeedKit + XMLParser(OPML/podcast:) + SwiftSoup | FeedKit 2026-09 有新提交；SwiftSoup 2.13.9 活跃 | RSS 用库、OPML 自写、HTML 清洗 Safelist 白名单 |
| 8 | receive_sharing_intent | ⭐ Share Extension target + NSItemProvider + App Group | 系统机制 | iOS 唯一正解，需独立小 target（旧 Extension 逻辑可参考） |
| 9 | flutter_chat_ui | ⭐ **ChatLayout**（+ InputBarAccessoryView 或自写输入栏） | ChatLayout 2.5.1（2026-09-18）极活跃；MessageKit 22 个月无 release；Stream 专有许可 | 纯文本 AI 聊天用自定义 cell 定制；二轮查证后由"自建"改为采用 ChatLayout（《07》§2.6） |
| 10 | flutter_lyric | ⭐ 自建（UICollectionView/CADisplayLink + 渐变 mask 高亮） | **iOS 无可用现成库**（已查证，均为 2020 年前后停更小项目） | 逐行歌词 + 拖动横条 + 点击行行为全部要自控；未来要逐字歌词可上 TTML |
| 11 | marquee | ⭐ **MarqueeLabel 4.5.3** | 2025-09 发版并专门修过 iOS 26 UIGlassEffect 兼容；UIKit 无系统跑马灯（已查证） | 事实标准库，两处跑马灯直接用（《07》§2.4） |
| 12 | lottie | ⭐ lottie-ios 4.6+ | 活跃（2026-06, Swift 6） | JSON 资产直接复用 |
| 13 | carousel_slider | ⭐ Compositional Layout orthogonal scrolling | 系统 | 原生分页轮播，无手势冲突 |
| 14 | easy_refresh | ⭐ UIRefreshControl + prefetching | 系统 | 采用系统玻璃 spinner（用户已接受适配，《07》A4）；自定义"进度条 header"在 iOS 26 无公开做法且违背官方"移除自定义效果"指南 |
| 15 | modal_bottom_sheet | ⭐ UISheetPresentationController + custom detents | 系统（iOS 16+） | 90% 粘性关闭阈值需自定义 presentation 复刻 |
| 16 | audio_video_progress_bar / percent_indicator | ⭐ 自建 UISlider 子类 / CAShapeLayer | — | 旧版本就是自绘，工作量小 |
| 17 | cached_network_image + flutter_cache_manager | ⭐ Kingfisher 8.12（备选 Nuke 13.2） | 均活跃、Swift 6/iOS 26 就绪 | Kingfisher 生态与功能覆盖最全 |
| 18 | google_fonts | ⭐ 字体 TTF 打包 + UIAppFonts | **Google 无 iOS SDK**（官方方向就是自托管） | comfortaa/notoSans/inter/mPlusRounded1c/roboto 五族打包（可子集化） |
| 19 | palette_generator | ⭐ CoreImage（CIAreaAverage/简化 k-means） | 系统 | 对拍验证：与旧版 dominantColor ΔE < 阈值（测试方案 G14） |
| 20 | 图标库 ×4 | ⭐ SF Symbols 优先 + SVG 入 Asset Catalog | 系统（iOS 26 Liquid Glass/Icon Composer） | material/fluent 九成有对应；品牌图标 SVG 保留原视觉（iconify 的自定义 SVG 直接打包） |
| 21 | country_code_picker | ⭐ 列表 sheet + 搜索（UICollectionView list） | 系统 | 49 国白名单数据在代码里直接搬；无结果态用 UIContentUnavailableConfiguration（《07》§2.7） |
| 22 | timeago / jiffy | ⭐ Foundation Format API + Calendar | SwiftDate 已沉寂（2023-09） | 但注意复刻 timeago `en_short` 的具体文案（测试 G10） |
| 23 | url_launcher / share_plus / file_picker | ⭐ UIApplication.open / UIActivityViewController / UIDocumentPicker | 系统 | 一一对应 |
| 24 | provider / get | ⭐ @Observable + @MainActor 控制器（UIKit 用 withObservationTracking/Combine 绑定） | Apple 主推 | 不引入巨型框架；GetX 的 DI/路由职责由显式 AppEnvironment + UIKit 容器承担 |
| 25 | uuid / crypto / retry / dotenv | ⭐ Foundation UUID / CryptoKit（Insecure.MD5）/ 自写 20 行 / xcconfig + 私有 plist | 系统 | 四项零第三方 |
| 26 | Dart isolate | ⭐ async/await + TaskGroup + actor + @concurrent | Swift 6.2 标准 | 见 §4 |

---

## 8. 测试工具链（与《05-regression-test-plan.md》配套）

| 用途 | 工具 | 2026 状态（查证） |
|---|---|---|
| 单元测试 | ⭐ Swift Testing | Xcode 27 与 XCTest 双向互操作；官方口径：新测试一律 Swift Testing，**UI 自动化/性能测试留在 XCTest**；参数化测试逐条并行 |
| UI 自动化 | ⭐ XCUITest | 无 EarlGrey 3（2.x 低活跃且跑在 XCUITest 上）；限制：系统弹窗只能 addUIInterruptionMonitor、启动慢 |
| 快照测试 | ⭐ pointfreeco/swift-snapshot-testing | Liquid Glass 注意：玻璃效果需 app target + `drawHierarchy: true` 才渲得出；基准图按 OS 版本分目录 |
| 网络 mock/回放 | ⭐ URLProtocol 注入 + mattt/Replay（HAR 录制回放） | Replay 2025-12 发布、Swift Testing trait；DVR 已停更 |
| 数据迁移测试 | 旧 SQLite fixture 进 test bundle → migrator 跑一遍 → 断言 schema/行/字段 | GRDB migrator 幂等可测 |
| 人工回归组织 | TestFlight Internal（每日冒烟）+ External（发布前回归）+ checklist 分组 | — |

---

## 9. 同 bundle id 覆盖更新注意事项（查证 + 代码盘点交叉）

- 沙盒数据（Documents/Library/tmp）与 Keychain 在同 bundle id 更新时全部保留（数据继承清单见《01》§9）。
- **Firebase 登录态**：存 Keychain（service `firebase_auth_1:1092551717876:...`），原生 Firebase iOS SDK 与 FlutterFire 底层同一套——沿用同一 `GoogleService-Info.plist`（同 GOOGLE_APP_ID）即无缝继承。**坑**：新旧 build 的 keychain access group / entitlements 不一致会读不到旧凭据——entitlements 必须逐项对齐（sign in with apple、app group、background modes、URL schemes）。
- **RevenueCat**：匿名/登录 appUserID 存 Keychain + 自有 UserDefaults suite，同 RC 项目 + 同 API key（`appl_...`）+ 继续以 Firebase uid `logIn` → 订阅身份无缝延续。
- **审核**：完全重写不违规；风险点是准则 2.3（元数据准确）与 2.3.12（重大变化写入 What's New）——保持产品定位一致并在更新说明中写明即可。
- **上线前必做**：TestFlight 覆盖安装实测（测试方案 §2.5），断言 `Auth.auth().currentUser != nil` 与 entitlement 激活。

---

## 10. 参考来源（主要查证）

- [GRDB.swift Releases](https://github.com/groue/GRDB.swift/releases) / [Swift Package Index: GRDB](https://swiftpackageindex.com/groue/GRDB.swift)
- [purchases-ios Releases](https://github.com/revenuecat/purchases-ios/releases) / [RevenueCat Docs: Identifying Customers](https://www.revenuecat.com/docs/customer-identification)
- [GoogleSignIn-iOS Releases](https://github.com/google/GoogleSignIn-iOS/releases) / [firebase-ios-sdk Releases](https://github.com/firebase/firebase-ios-sdk/releases)
- [Kingfisher](https://github.com/onevcat/Kingfisher/releases) / [Nuke](https://github.com/kean/Nuke/releases) / [sentry-cocoa](https://github.com/getsentry/sentry-cocoa/releases) / [lottie-ios](https://github.com/airbnb/lottie-ios/releases) / [SwiftSoup](https://github.com/scinfu/SwiftSoup/releases) / [FeedKit](https://github.com/nmdias/FeedKit)
- [WWDC25 Session 243: What's new in UIKit](https://developer.apple.com/videos/play/wwdc2025/243) / [Session 284: Build a UIKit app with the new design](https://developer.apple.com/videos/play/wwdc2025/284) / [Session 219: Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219)
- WWDC26 session 笔记（[ivan-magda/wwdc26-notes](https://github.com/ivan-magda/wwdc26-notes)）：269 What's new in SwiftUI、272 Use SwiftUI with AppKit and UIKit、278 Modernize your UIKit app、**312 Meet the Now Playing framework**、212 Rev up your CarPlay app、267 Migrate to Swift Testing
- [Avanderlee: Approachable Concurrency in Swift 6.2](https://www.avanderlee.com/swift/approachable-concurrency/)
- [Fatbobman: Key Considerations Before Using SwiftData](https://fatbobman.com/en/posts/key-considerations-before-using-swiftdata) / [Michael Tsai: Returning to Core Data](https://mjtsai.com/blog/2024/10/16/returning-to-core-data/)
- Apple Newsroom iOS 26 发布（2025-06）；MacRumors/AppleInsider iOS 26 采用率（2026-02/06）；StatCounter iOS 版本份额（2026-08）
- [Marco Arment: Podcast App Playback Speeds](https://marco.org/2013/10/18/podcast-app-playback-speeds) / [just_audio #83: audioTimePitchAlgorithm](https://github.com/ryanheise/just_audio/issues/83)
- [mattt/Replay](https://github.com/mattt/Replay) / [pointfreeco/swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing)
- [Apple: App Store Review Guidelines 2.3/2.3.12](https://developer.apple.com/news/?id=8cm677wd)
