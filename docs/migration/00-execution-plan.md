# Anycast Flutter → iOS 原生迁移：总览与执行计划

> 背景：Google Play 审核无望、个人已无 Android 需求；iOS 端有付费用户——迁移首要目标是**不给现有用户带来任何麻烦**。
> 本文 = 全貌入口 + **唯一执行主线**（M0–M5 按顺序推进、逐条打勾）。01–08 是参考库，**编号是参考编号、不是执行顺序**，执行到对应任务时按引用查。

## 结论速览

1. **可行性：没有阻塞项。** 全部现有功能在 iOS 原生栈（AVPlayer / GRDB / URLSession / Firebase / RevenueCat iOS SDK）上都能等价实现。唯二"原生做不到"的 skip silence 与均衡器，在现网 iOS 版上本来就是无效开关 / 未实现——迁移"保持无效"即完全等价（《04》§9）。
2. **数据兼容性风险可控且完全可测。** 本地数据全部是明文标准 SQLite + tmp 文件缓存 + Keychain（第三方 SDK），无 iCloud、无私有二进制格式（`Documents/anycast.db`、9 张表、v4 schema，详见《01》§9 继承清单）。同 bundle id 覆盖安装后原生版可以直接读。
3. **付费体系延续有明确路径**：RevenueCat 以 Firebase uid 作为 appUserID，原生版继续 `logIn(同一 uid)` + 同 RC 项目/API key → 已订阅用户升级后权益立即可见（《02》§3）。
4. **API 契约有 14 条红线**（认证头格式、短链硬编码 password、15s/10s 轮询节奏、429/5xx 不重试等），逐条列在《02》§6——回归测试逐条覆盖。
5. **UI/交互的最难部分**不是页面数量（约 21 屏），而是少数高定制交互：播放列表长按拖拽排序、歌词滚动跟随+点击行暂停+拖动 seek、频道页手写视差折叠头、多层 modal sheet 栈——这些已逐条落成人工验收清单（《05》§6.3，适合由人来做的部分）。
6. **技术选型有明确答案**（详见《06》）：GRDB（唯一能直接打开旧库）、UIKit 为主 + `@Observable`、AVPlayer + iOS 27 新 Now Playing 框架、Swift 6.2 并发完整替代 Dart isolate。第三方仅约 10 个，UI 层不引入任何整体框架。
7. **UI 采用"原生优先"策略**（详见《07》）：系统组件（iOS 26 Liquid Glass 尽量吃满）→ 成熟库（Kingfisher/ChatLayout/MarqueeLabel/lottie）→ 自绘仅 **1 个中型（歌词视图）+ 10 个小控件**，约 2.5~3 周自绘量；已接受的视觉适配收敛在《07》§1 的 A1–A9 清单内，设计语言与全部手势语义保持不变。

## 文档地图与阅读协议

| 文件 | 性质 | 内容 | 什么时候用 |
|---|---|---|---|
| **00**（本文） | 总览 + 执行计划 | 结论速览、决策速览、M0–M5 任务清单与 DoD | 从这里开始，按它推进 |
| 05-regression-test-plan.md | 方案 | 回归测试方案（等价性定义、真实语料采集规程、L0–L4 分层测试、人工手势验收清单、怪癖决策表 K1–K25、战略决策、发布门禁与灰度） | 贯穿全程的验收依据 |
| 01-baseline-data.md | 事实基线 | 数据层：9 张表逐列、路径推导、缓存布局、继承清单、坑位 | M1 写数据层实现与断言时对照 |
| 02-baseline-api-auth-payment.md | 事实基线 | API/认证/付费：端点全清单、认证流、RevenueCat、14 条契约红线 | M1 写网络层时对照；M3 登录/付费墙时对照 |
| 03-baseline-ui-interaction.md | 事实基线 | UI/交互：21 屏清单、全部手势/动画、颜色字体图标 | M3 逐屏实现时对照行为事实（07 定归属、03 定事实）；M4 人工验收清单的依据 |
| 04-baseline-audio.md | 事实基线 | 音频栈：播放/队列/锁屏/缓存行为、怪癖、原生映射 | M2 写播放层时对照 |
| 06-ios-tech-research.md | 调研（已定稿） | UIKit vs SwiftUI、min target、并发、逐依赖对照、测试工具链 | 建 M1 工程骨架时 |
| 07-ui-native-mapping.md | 方案 | UI 组件映射与自绘边界：系统/成熟库/自绘归属、适配边界 A1–A9、Liquid Glass 计划、拖拽实现注记 | M3 逐屏实施时 |
| 08-implementation-review.md | 评审（**已合稿存档**） | 实施细节评审：哪些 Flutter 妥协应换成 iOS 最佳实践（DB 线程/事务、组合根与生命周期、定时器前后台、音频会话、UI 细节），⛔/⚠️/✅ 三档判定 + 采纳映射表；§12 含三轮全量代码走查的必修级发现 | **2026-09-22 采纳条目已按落点并入《05》（K26–K38、G1/G2/G13 等）与《06》/《07》对应章节、本文 M0–M2 任务——读目标章节即可，本文留作依据出处与未采纳项备忘 |

**阅读协议（写给按本文执行的 Agent）**：① 进入一个阶段（M0–M5），先按上表「什么时候用」列筛出命中本阶段的文档、读完对应章节再动手；② 动手单个条目前，读完该条目引用的全部《X》§Y——条目引用是最低门槛，不是边界；③ 细节存疑而条目无引用时，回上表定位文档查证，不凭记忆决策，查无答案才自行判断并按文末修订规则登记。不要求通读 01–08，也不得以"已经读过"为由跳过②③——跨会话或长对话后，此前所读一律视为不可靠，需要时重查。

## 已定稿决策速览（2026-09-21 拍板）

权威明细在《05》§11（决策表 K1–K25 + 战略决策段）；速览与明细冲突时以《05》为准。

| 决策 | 结果 |
|---|---|
| 最低部署目标 | **iOS 18**（《06》§3；iOS 26/27 特性走 `#available` 降级；iOS 15–17 用户停留在 Flutter 最后一版，权衡已接受） |
| UI 框架 | UIKit 为主 + `@Observable` + 局部 SwiftUI（《06》§2） |
| UI 组件策略 | **原生优先**：系统组件（Liquid Glass 吃满）→ 成熟库 → 自绘仅 1 中型 + 10 小型；视觉适配边界 A1–A9（《07》） |
| iPad 策略 | 首版 **iPhone-only**（TARGETED_DEVICE_FAMILY=1）；iPad 用户走系统 iPhone 兼容模式（≈现网形态），完整适配列 backlog（《05》§11） |
| UA 策略 | 自家 API 用原生 UA（后端已核实无入站过滤，《02》§7）；RSS 直抓固定浏览器 UA |
| 锁屏 ±10s（K1） | 复刻（有意设计，播客惯例） |
| skip silence（K2） | 移除开关，`settings.skipSilence` 字段保留兼容读取 |
| 写回兼容（回滚安全网） | 首版只读兼容 + 相同 schema 写入（《05》§2.4） |
| Share Extension | 保留现有原生 Extension 原样，仅主 App 改为直接读 App Group（《01》§7） |
| 首版增强 | 播放错误提示+重试、show notes 链接可点、聊天错误提示、翻译超时容错、打断/拔耳机处理、锁屏封面兜底、进度退后台保存、坏库隔离重建（《05》§11） |
| 二期 backlog | CarPlay、完整 iPad 适配、缓存上限 UI、.lrc 导出、autoSleepTimer、锁屏快进 +30s（《05》§11） |
| 免费额度文案 | 复刻"3 次"文案（后端实为 10 次/终身，《02》§7；是否改文案另行决定） |

---

## 执行阶段

> 阶段估算（solo + AI 辅助）：M0 ≈1 周 → M1 ≈1–2 周 → M2 ≈1–2 周 → M3 ≈4–6 周 → M4 ≈2 周 → M5 ≈1–2 周 + 7 天放量，全程约 3 个月量级。
> 依赖关系：M0 完全先行；M1→M2 串行（音频测试依赖数据层）；M3 内部各屏可乱序/并行；M4 依赖 M3 全部完成。

## M0 · 资产与基线期（全部在 Flutter 仓库，不写一行原生代码）

**目标**：把"真实世界"固化成可重复的测试资产。**DoD**：golden 与来源记录（manifest/headers）进 git，payload 不进 git、由来源一键重新生成（2026-09-22 修订：原为"fixtures+golden 进 git"，为控制仓库体积改为 provenance 模式，见 test/fixtures/README.md）；TF 基线 build 可装。

> **2026-09-22 进度**：自动化资产全部建成（`native` 分支）——RSS 语料 9 桶（真实源 22 个 + 作者真实订阅 25 源 + 构造桶）、API fixtures 10 端点、DB 9 桶（7 桶真实语料合成、`db_user`/`db_device` 见下方修订）、音频 8 类、OPML 4 份、封面 8 张、G1–G16 golden 全量导出、一键脚本 `tool/m0/regen_all.sh`、目录说明 `test/fixtures/README.md`。**待人工**：真机容器采集验证（降级至 M4 顺带做）、真机数据样本替换（已由 `db_user`+`db_device` 实质满足）、~~golden 人工抽查 ≥3 组~~（已抽查 G4/G9/G13 + 现网只读复核）、~~TF 基线 build~~（锚定现网商店版）、招募用户（放宽为尽力而为）。生成细节见 test/fixtures/README.md；基线文档已按实测修正三处（01 §1.2 缓存列名、05 §1.5 G1/G13）。
>
> **2026-09-22 修订（真机数据路径：模拟器实机产出）**：新增 `rss/user_subs` 语料桶（作者真实订阅导出 25 源，24 可解析，bowuzhi.fm 死源如实保留）与两个 DB 桶——**`db_user`**（同一语料经真实模型写入路径生成的确定性 fixture）和 **`db_device`**（iOS 模拟器实机产出：`integration_test/m0_seed_test.dart` 启动真实 App、走分享导入真实代码路径导入全部订阅、入队并真实播放一集，容器在测试保活窗口内由 `simctl get_app_container` 提取）。实机数据确认：真实音频缓存位于 `Library/Caches/anycast_episode/`（非 `tmp/`），fixture 按实机布局收编。
>
> 为此打通本机 Xcode 27 构建：`purchases_flutter ^9.9.9 → ^10.13.1`（RC 5.49.2 在 Xcode 27 编译失败；10.x 经 PurchasesHybridCommon 19.2.0 升 RevenueCat 5.90.1，所用 API 面兼容、analyze 干净）；`ios/Podfile` post_install 钳 pod deployment target ≥15.0；Share Extension target 补 `FRAMEWORK_SEARCH_PATHS` 并按 08 §12.1-4 方案 B 把 `SharedMediaFile`/`SharedMediaType` vendor 进扩展（`ios/Share Extension/SharedMediaTypes.swift`，顺带消掉 M1 的一个坑）；macOS 27 自带 `lipo -verify_arch` 只收单 arch，flutter_tools 的多 arch 调用失败——本机 SDK 打了逐 arch 补丁（`darwin.dart` thinFramework），属本地工具链 workaround、不进仓库。TF 内部组招募因用户基数不足放宽为"作者本人回归 + 招募尽力而为"（05 §11 决策段口径）。
>
> **2026-09-22 基线口径裁定（Flutter 线分叉）**：origin/main 曾领先本地 14 个提交（PR #1–#8：CI、agent 约束、**Anycast 2.0 视觉刷新**、IME/状态修复、测试覆盖），均**未 bump 版本号、未随任何发布出去**——golden 参考实现锁定 **1.2.1+38（现网版）**。已把 main 同步到 origin/main 并将 `native` rebase 其上（无内容丢失：本地旧提交内容均已在远端）。**rebase 后核验**：golden 依赖的全部纯逻辑函数行为与 1.2.1+38 一致，唯 `getTextSafeColor` 被视觉刷新 PR 删除——G14 导出器已 vendor 旧实现（golden 不变），原生仍须实现该已发布行为（歌词取色）。远端另有一套 `test/compatibility/`（schema v3/v4 fixtures + DB 兼容测试，PR #7）与 M0 的 `test/fixtures/db/` 并存——M1 时评估合流，避免两处维护 schema 基准。

- [x] 分支策略落地：`main` 冻结为 Flutter 维护线（保持可构建可提审，回滚保险，05 §10.1）；**原生代码定稿落位（2026-09-22 拍板）：同仓库新目录 `native/` 放 Xcode 工程**——M0 采集的 `test/fixtures` 与 `test/golden` 由 Swift Testing 按相对路径直接读，零共享成本；CI 在同仓加原生 job（XCUITest 冒烟宿主，05 §6.2）→ **`native` 长期分支已建（自 main），全部迁移工作落此分支**
- [ ] 验证容器采集可行性：真机确认 Xcode Download/Replace Container 对 dev 签名可用、对现网 App Store 版不可用（05 §1.1 修正规程）【降级至 M4 覆盖安装准备时顺带做；db_device 已由模拟器实机产出兜底】
- [x] 按 05 §1.1 三级路径采集/构造 DB 样本：`db_light / db_heavy / db_user / db_device / db_dirty / db_v3 / db_crashed / db_corrupt（truncated/notadb/partial 三型）/ db_edge_subs` + 两个缓存元数据库 + tmp 音频样本（每桶 ≤3 文件）——`db_user`/`db_device` 之外的 7 桶（light/heavy/dirty/v3/crashed/corrupt/edge_subs）为合成路径（真实 RSS 语料喂真实建表/插入代码，真机 `db_heavy` 灌入后可直接替换同名文件）；`db_user`（真实订阅经真实模型写入）与 `db_device`（模拟器实机产出）见 2026-09-22 修订；生成器 `test/fixtures/generate_db_fixtures_test.dart`（`db_device` 另由 `integration_test/m0_seed_test.dart` 实机产出）
- [x] RSS 语料 9 桶（05 §1.2）：standard(10)/http_plain(6)/redirect(6 源 3xx 交换，仅 2 源留有 .final.xml)/ua_sensitive(2×3UA) 为真实采集（后端发现接口 441 候选 + 精选清单，385 源元数据入 `channels_index.json`）；user_subs(25) 为作者真实订阅导出（24 可解析，bowuzhi.fm 死源如实保留，采集脚本 `tool/m0/fetch_user_subs.sh`）；missing_fields(5)/giant(1200 items+1MB 描述)/malformed(3)/weird_dates(12 种日期) 以真实源为模板构造；采集脚本 `tool/m0/fetch_rss.sh` + `construct_rss_buckets.py`
- [x] API fixtures（05 §1.3）：10 端点 × 成功+全部错误分支（401、403 code=2、403 其他、429、5xx、超时、`data:null`、转写 processing 多帧、K28 自愈分支、翻译 translation:null 等）；无认证端点与 401 路径**实采**（含真实 404 `{"message":"No Transcription Found"}`），需认证成功态按《02》规格构造；脚本 `tool/m0/fetch_api.sh`
- [x] 音频样本 8 类（05 §1.4，ffmpeg 确定性合成：8s/30min/2h05m/含静音/VBR/AAC/128k/伪 mp3 + 404/500/错误 Content-Type/无 Range 本地服务器 `tool/m0/serve_local.py`）+ OPML（App 导出=真实 generateOPML 产出 + Overcast/小宇宙风格构造 + 500 源巨型）+ 封面图样本 8 张（真实封面 800px，取色对拍 golden 已导出）
- [x] 写 `test/golden/export_golden_test.dart`（flutter test 环境 + sqflite_common_ffi，05 §1.5 运行环境说明），导出 **G1–G16 全量 golden**——G1/G2 **仅插入场景**逐字节导出（含头部 200 连插与中点饱和重排两序列），移动场景按 K26 修复语义单测断言（05 §1.5）；G13 含当前 user_input 重复逐字节复刻；另导出 G_palette（palette_generator dominantColor）；**G4/G7/G8/G13 为单一事实来源做了 4 处纯函数提取**（buildExportText / parseFeedResponse / computeNewEpisodes / buildChatHistory，行为不变，flutter analyze 通过）
- [x] golden 复核抽查 ≥3 组（人工确认导出值与旧版运行表现一致）【2026-09-22 完成：G4 导出文本 `# title - channel`+`---`+LRC+`--- Translation ---` 与 buildExportText 一致；G9 settings CSV 回环、`mins_value` 取 countdown 索引、speed/language 常量一致；G13 ≤10 条倒序且末元素即当前输入、>10 条发送最旧 10 条（K27 怪癖如实保留）；另对现网做只读复核：短链 302→`/player?rssfeedurl&enclosureurl`、`categories`/`search` 的 `{msg,code,data}` 封套、`subtitles` 404 形状均与抓包一致】
- [x] ~~发最后一个 Flutter 版 TestFlight build~~【2026-09-22 决策：覆盖安装测试的"旧版"锚定现网 App Store 版 1.2.1+38，不发内容相同的 TF build；双设备对照同理用商店版】
- [ ] 招募 2–3 位重度用户进 TF 内部组（决策 D8）【放宽：作者本人回归 + 尽力而为；用户基数不足，见修订注记】

## M1 · 原生骨架 + 数据/契约层（05 的 L0–L2 全绿）

**目标**：证明"读旧数据 + 说同一套 API 协议"成立。**DoD**：05 §2（数据迁移矩阵）、§3（G1–G16 对拍）、§4（契约回放）自动化测试全绿。

> **2026-09-23 进度**：**DoD 达成——L0（14）+ L1（26，含 G_palette 2 项 CIEDE2000<10）+ L2（12）+ 资产可用性（2）= 54 个 Swift Testing 测试全绿**（iOS 18.6 模拟器，测试 TZ 钉 Asia/Shanghai；建议 `-parallel-testing-enabled NO`，见 native/README）。工程与实现要点：
>
> - **工程**：`native/` xcodegen 工程（`project.yml` 为唯一事实，勿手改 pbxproj）。AnycastKit（动态 framework，`SWIFT_DEFAULT_ACTOR_ISOLATION=Nonisolated` + `@concurrent` repository——SQL 永不落在 MainActor 栈）+ Anycast app（MainActor 默认）+ ShareExtension（vendored 源码迁入）+ AnycastTests。min iOS 18、Swift Approachable Concurrency（6.2 引入的特性集；language mode 6.0）、UIScene 生命周期、Privacy manifest（UserDefaults CA92.1 + 文件时间戳 C617.1，app 与扩展各一份）。
> - **依赖**：GRDB 7.11.1 / Firebase(Auth+Core) / GoogleSignIn / RevenueCat / Sentry / Kingfisher / SwiftSoup / lottie / ChatLayout / MarqueeLabel。**FeedKit 砍掉**：其仓库 tag 的 Package.swift 是 Swift tools 3.1，Xcode 27 SPM 直接拒绝解析（08 §8 本就预判"XMLParser 一个就够可砍"）；RSS 解析改为自写 XMLParser 逐语义对齐 webfeed_plus，G7 对拍通过（52 fixtures；redirect/ua_sensitive 为传输层语料，不进 RSS 映射对拍）。
> - **架构铁律落地**：组合根 `AppEnvironment` + 启动 DAG `StartupSequence`（Sentry → Firebase/RC configure → DB open（K25 在内）→ settings → player 指针 → RC `logIn(uid)`（configure 完成后、失败重试 3 次、上报）——settings 加载前无任何定时器）；DB 用 `DatabaseQueue`（rollback journal，不启 WAL，写回兼容）。
> - **G7/G8 字节级对拍的两个硬前提**（后续改动勿破坏）：① Dart `List.sort` 是不稳定双轴快排，等值 pubDate 的次序被 golden 锁定 → 移植了 SDK 的 `DartSort`（32 阈值插入排序——`right - left <= 32` 即 33 元素内走插入排序，SDK sort.dart 实义；2026-09-23 曾按 `<` 误植，33 元素等值区间偏离 Dart 次序，已修正并有专项边界测试）；② Dart-intl 宽松解析（如 Feb 29 2027 滚动到 Mar 1、未知时区缩写按 0）与 webfeed 时区表全部按源码移植（`DartDate`/`RSSDate`）。
> - **G11 裁定（Jiffy 时区怪癖，按 golden 复刻）**：`User.fromJson` 的 `expired_at` 经 Jiffy `yyyy-MM-ddTHH:mm:ssZ` 解析后是**墙钟时间按设备本地时区**取值、串内偏移被丢弃（golden 在 UTC+8 主机导出：`09:30:00+00:00` → 01:30Z）。原生按同语义实现（剥偏移后按本地时区解析）。
> - **subtitle processing 行不落库（按 1.2.1+38 基线）**：`a0b7f66`（2026-07-31，未随任何发布出去的 Flutter 线改动）允许 processing 行落库——**不属于现网基线，不移植**；原生按 01 §1.1 口径（只有完整 succeeded 行落库）。若后续确认现网 1.2.1+38 实际包含该改动，再修订 01 与两边断言。
> - **K 决策落实**：K2（skipSilence 只读不写）、K5（RSS 缺字段容忍——golden 中 `parse_error_null` 的 missing_fields 条目按"容忍解析成功"断言，malformed/空文件仍失败；user_subs 0 字节死源如实按失败处理）、K8（chat 非 2xx 不再当 AI 回复）、K9（翻译 30s 超时）、K10（429 无退避复刻）、K13/K14/K15（UNIQUE 替换语义，L0 专项断言）、K25（坏库 `.corrupt` 隔离+重建+上报、再开不重复隔离）、K26（repository 移动按移动后邻居；G1 场景按旧算法逐字节重放）、K28/K29/K31（L0/L1 断言）。
> - **十四红线**：L2 逐条断言（Bearer 仅 4 认证端点、Content-Type 仅随 body、10s/3s/30s/无超时、传输层失败才重试（2/3 次总计）、429/5xx 不重试、翻译无 Authorization、短链 body 逐字节对 G12、未登录合成 401 零请求、RSS 8 并发+浏览器 UA+失败源跳过（URLProtocol 实测 max-in-flight==8））。
> - **`test/compatibility/` 合流评估（M0 遗留）**：**不合流**。它是 Flutter 维护线自身的模型守卫（跑 Dart 模型、`flutter test`），与原生 L0（读真实语料桶+golden）职责不同、各自保留。约束记录：未来 schema 变更需同步三处——`native/AnycastKit/.../Schema.swift`、`test/compatibility/fixtures/*.sql`、`test/fixtures/generate_db_fixtures_test.dart`（M0 生成器）。
> - **待 M2/M3 顺带**：Firebase/RC 为 SDK 层联调（代码就绪、随 App target 编译），真机级登录/entitlement 验证并入 M3 登录屏与 M4 付费矩阵；模拟器上 `Auth` 的真登录流程未跑。Sentry dSYM 上传脚本已挂 Release 构建阶段（build phase；无 `SENTRY_AUTH_TOKEN` 时静默跳过，CI 注入 token 后生效）。
>
> **2026-09-23 深度 review 修订**（代码级对照 Dart 源逐项复核后修复，测试 44→47 全绿）：① RSS 解析容忍未定义 XML 实体（Dart xml 按字面保留 `&nbsp;`；Foundation XMLParser 原本整文档失败，野生源会被静默跳过——P0）；② DartSort 阈值修正 `right - left <= 32`（见上）；③ K14 跨列表加入改为全表查重并移动到新列表（原先只查目标列表、跨列表加入会撞表级 UNIQUE 抛错），补跨列表断言；④ K26 修复语义补专项测试（下移/上移 + 重开验证；此前生产 `movePosition` 零覆盖，G1 golden 锁的是旧算法）；⑤ RC 绑定补 Firebase auth 状态监听（晚到/后登录的 uid 不再整会话匿名）且不再随 DB 降级整体跳过；⑥ 查询编码按 Dart `Uri.encodeQueryComponent`（`+`→`%2B`、空格→`+`；原 URLComponents 会把字面 `+` 让服务端解成空格）；⑦ L2 断言修复（no-Auth 改为全端点累积断言——原先 per-endpoint reset 把证据抹掉了；Bearer 补齐 4/4 端点）；⑧ `deleteUser` 返回 ErrorSignal（原先吞掉全部错误信号）；⑨ 测试 scheme TZ 钉 Asia/Shanghai（G10/G11 golden 为 UTC+8 主机导出，原先换时区机器必挂）；⑩ 缓存元 DB 的 `validTill`/`touched` 注释 seconds→milliseconds（fork 实存毫秒，防 M2 LRU 差 1000 倍）；⑪ 冷启动 URL 经 connectionOptions 接线、缺 `GoogleService-Info.plist` 优雅降级、Apple 登录协调器用后即清；⑫ pbxproj 重生成并修正 Sentry dSYM 脚本键名（xcodegen 只认 `postBuildScripts`，原 `buildScripts` 键被静默丢弃、脚本阶段从未生成过）。**遗留待办**：转写 15s/翻译 10s 轮询节奏与红线 11 断言（M2）、search_episodes 等未回放 fixtures（M2 补）、Sentry `--org sentinel` slug 人工对证（仓库内无从验证）、sentry-cocoa 8.x vs 06 研究文档 9.29+ 取舍、RSS 野生输入差异集（zh_CN 日期回退、时区 token trim、嵌套 image 等）。
>
> **2026-09-23 二次复核修订（外部深度 review 逐条对照 Dart 源与 pub-cache 实测后采纳）**：① K25 上报接线补齐——`StartupSequence` 传 `onQuarantine` → Sentry（此前 hook 只在 L0 测试接线，生产路径静默，与上文"上报"声明不符）；② `parseFeedResponse` lastUpdated 恢复 Dart 语义——非空时取 `feedEpisodes[0].pubDate`（可为 NULL；原 `?? now` 吞 NULL 后 `local >= fetched` 会把该订阅后续集数永久冻结），`computeNewEpisodes` 同步对齐 local==NULL 的首集分支；③ 播放列表 position 邻居数组改 `[Double?]` 对齐全量下标（NULL position 行在 Dart 里=该侧无邻居，原 `compactMap` 挤掉 NULL 行导致邻居查找整体偏移，补脏行断言）；④ K39/K40 新裁定入《05》§11：htmlToText 对齐 Dart 收 script/style 文本、`dartTrimmed()` 对齐 trim 字符集（实测差异两个字符且方向相反：Dart 多裁 FEFF、Swift 多裁零宽空格 200B）；⑤ K14/K30 基线勘误（见《05》§11）：K14 现网实为"留旧列表+position 污染"（原生按行为变更=移动到新列表）；K30 现网实为"resume 重插但 id 不变不移顶"（sqflite 实测；原生 history 行保留 playlist 行 id）；⑥ 小项：`Uri.encodeQueryComponent` 字符集对齐（`!'()*` 应编码，实测）、`itunes:duration` 数字容忍空白（`int.tryParse(' 3600')`=3600）、`<enclosure>` 无 `url` 属性时保留该集（Dart 行为，enclosureUrl=NULL 落库）、RFC822 年份宽度 `\d{1,6}`（intl `yyyy` 贪婪，实测 `20241` 年可解析）、`authorizedSend` 死代码清理、RC `logLevel` 门控 `#if DEBUG`、Google credential 注释改准确（iOS API 强制 accessToken 参数，随 verifyAssertion 上行、idToken 优先，无害）。**未采纳**：外部 review 的"RSS `findElements` 后代搜索"指控（xml 6.6.1 源码 `findElements` 为直接子元素，原生行为一致）；其 trim 论据修正为"仅差 FEFF"（NBSP 例不成立）。**记录在案不修**：重试面宽于 Dart（TLS/重定向等也重试一次，终态相同仅多 ~200ms；M2 轮询节奏断言时再评估）、`URLSession.timeoutInterval` 字节间隔语义 vs Dart 整请求上限（慢速滴流响应可超名义 10s/3s）、Apple 登录 sha256 nonce（M3 登录屏落地）、JSON `\b`/`\f` 简写与 ≥1e15 整值的字节差、`expired_at` 纯日期宽容差异（服务端固定发完整 ISO）、M3 移植 `importPodcastsByUrls` 时保留 `s = {}` 死过滤器原样（修好会让重导触发 title UNIQUE REPLACE 换 id）。

- [x] 新建 Xcode 工程：min iOS 18、Swift 6.2 Approachable Concurrency、UIKit 为主、UIScene 生命周期（iOS 27 强制，06 §3/§4）
- [x] 引入依赖（06 §1）：GRDB、Firebase/GoogleSignIn、RevenueCat、Sentry、Kingfisher、SwiftSoup、lottie-ios、ChatLayout、MarqueeLabel（FeedKit 经评估砍掉，见上）
- [x] 架构铁律入骨架（08 §1.1/§2.2/§3.1，当 lint 用）：组合根 + DB/解码不出 MainActor 栈（AnycastKit Nonisolated 默认 + `@concurrent` + 值类型跨界 + 单 `DatabaseQueue` 不启 WAL）
- [x] 启动 DAG（08 §2.3/§12.1-5）：Sentry → Firebase/RC 配置 → DB open/迁移/K25 兜底 → settings 加载完成 → 恢复播放器指针 → settings 加载完成前不起任何定时器 → 首帧；RC configure 完成后才 logIn(uid)、失败重试
- [x] Share Extension 编译依赖供给（08 §12.1-4）：源码（含 vendored SharedMediaTypes.swift）迁入 native/ShareExtension，bundle id `com.kindjeff.anycast.Share-Extension`、App Group 与 `ShareMedia-` scheme 保持
- [x] Privacy manifest：app 级 `PrivacyInfo.xcprivacy`（UserDefaults CA92.1 + 文件时间戳 C617.1；扩展同报）+ 各 SDK 自带 manifest 随包；App Store 隐私标签核对留 M5
- [x] GRDB 打开 `Documents/anycast.db`：schema 只读校验（user_version=4、9 张表）+ migrator 从 v4 续写（migration map 与 Dart 同构）+ 写回兼容（相同 schema、rollback journal）+ 坏库兜底（K25）
- [x] 语义层实现：毫秒时间 / bool 0-1 / position REAL / JSON 列（Dart 风格 double 编码写回）/ autoSleepTimer CSV / 历史 id DESC 等全部按《01》§9
- [x] L0 测试跑绿：05 §2.1 矩阵全行（G15 七桶逐行对拍；db_corrupt×3 → K25 断言；空目录默认行含 zh-Hans-CN→zh/CN 推导；autoRefreshInterval=300）
- [x] 网络层：URLSession 实现 02 §6 十四红线逐条（L2 全绿背书）
- [x] L1 golden 对拍跑绿（G1–G16 + G_palette，Swift Testing）
- [x] L2 契约回放跑绿（URLProtocol 回放 §1.3 fixtures，05 §4.1–4.2）
- [x] Sentry 接入（DSN/全量采样平移）+ dSYM 符号上传配置（Release + token 门控构建脚本）
- [x] Firebase Auth 三登录 + RevenueCat（logIn(Firebase uid)、entitlement `plus`、产品 `anycast_monthly`）——SDK 层完成；UI 与真机联调留 M3/M4

## M2 · 音频期（05 §5 自动部分全绿）

**目标**：播放行为等价（含怪癖复刻）。**DoD**：§5.1 状态机单测 + 真机 smoke 通过。

- [ ] `PlaybackService`（@MainActor）：单 AVPlayer + 应用层队列，复刻"episodes[0] 即当前曲、播完 removeTop 连拍、队列空 pause+clear"（K3，《04》§1.2）
- [ ] AVAudioSession 会话策略（K18，**冷启动不得打断他 App 音频**——旧版激活只随起播发生）：启动早期只 `setCategory(.playback)`（**必做项**，原生不设置则后台播放断；setCategory 本身不抢音频焦点）；**首次起播前**才 `setActive(true)`（AVPlayer 会隐式激活，显式调用便于捕错）；暂停**保持激活**（锁屏 Now Playing 卡片不消失）；队列播空/stop 时 `setActive(false, options: .notifyOthersOnDeactivation)`（让他 App 恢复播放，平台礼仪增强）并吞 error 560030880；打断/路由监听不劣于旧版（08 §5.2 + 2026-09-22 修订：原文"启动早期 setActive(true)"会让冷启动打断他 App，已纠正）
- [ ] 锁屏：MPRemoteCommandCenter——skipBackward/skipForward = ±10s（K1 复刻）、toggle、changePlaybackPosition；NowPlayingInfo（title/album/duration/rate/artwork + 本地兜底 K19）
- [ ] 进度：2s 落盘 + pause/退后台补存（K24）；进度事件四条件过滤或等价视觉（K11）
- [ ] 倍速 7 档 + `.timeDomain` 保音调 + 持久化恢复；睡眠定时（仅播放中递减）；skip silence 开关不实现（K2 移除）
- [ ] 下载缓存：URLSession downloadTask + 读旧元数据库映射（`anycast_episode.db` 的 url/key/path）+ LRU 语义（个数 10 / 30 天 / 1 天未触碰）+ 删除联动 + 播放即缓存
- [ ] 播放错误提示 + 手动重试（K6）
- [ ] §5.1 状态机单测全绿；§5.5/5.6 缓存与设置项测试全绿
- [ ] 真机 smoke：起播/后台 30min/来电/拔耳机/锁屏 ±10s（§5.2–5.4 先粗过一轮，细测留 M4）
- [ ] 【验证项】iOS 27 竖屏"偏好"语义实测（07 §4 风险项）

## M3 · UI 期（07 映射逐屏实施，顺序可调）

**目标**：21 屏全部落地。**DoD**：快照基线齐全 + XCUITest 冒烟 <10min + 每屏对应人工条目标注"可验"。

- [ ] TabBarController 三 Tab + 子 VC 常驻（IndexedStack 等价）+ Tab0 重复点击回顶/刷新 + iOS 26 `UITabAccessory` mini player（iOS 18 降级自绘 #10）；A1 适配
- [ ] 列表卡片组：Inbox（UIRefreshControl A4 + 空态 `UIContentUnavailableConfiguration`）/ Subscriptions / Discover 分类 / SearchPage；Card 展开/进度条/下载三态；飞入动画 #11
- [ ] Channel：折叠头视差（pinToVisibleBounds + 插值）+ ExpandableText（#自建 40 行）+ palette 渐变 + 订阅三态
- [ ] 播放器：三页 UIPageViewController + PageTab 胶囊（#7）+ 背景 palette 渐变 + MarqueeLabel 标题 + 进度条（#4）+ 倍速/倒计时滑条（#5）+ 分享短链
- [ ] **歌词视图（最大自绘件，~1 周，#1–#3）**：逐行跟随/双语/拖动横条 seek/点击行暂停 + 中央形变动画 + 玻璃浮层（UIGlassContainerEffect）
- [ ] 聊天：ChatLayout + 输入栏；错误不伪装回复（K8）
- [ ] 设置页：UICollectionView list insetGrouped + UIPickerView 弹窗 + 国家列表 sheet；skip silence 开关不出现（K2）
- [ ] 登录/付费墙：三登录按钮 + Carousel + 月/年选择 + restore + 订阅信息卡；EmailLogin
- [ ] OPML 导入导出 + ShareDialog + 主 App 直读 App Group（Extension 原样保留）
- [ ] 转写五态 UI（Lottie 资产复用）+ LRC 导出（.txt，K21）
- [ ] 下划线 tab 条（#6）/ toast（#9）/ 渐变标题（#12）等小件按 07 §3 清单收尾
- [ ] 每屏完成即补：快照基线（05 §6.1，按 OS 分目录）+ XCUITest 冒烟扩充
- [ ] 无障碍/动态字体不崩溃不溢出（旧版无处理，新实现首次接触，《03》§8）；**iPad 硬性验收（05 §11/§10.3）：任意窗口尺寸/宽高比（iOS 27 可缩放窗口）布局不崩不溢出——全部布局用 view bounds/trait、禁按屏宽计算（现版 mini player 进度条 `(屏宽-24)×pos%` 这类写法不得照搬）、不依赖 UIRequiresFullscreen；最小窗口尺寸限制 API（scene size restrictions，名字以 SDK 为准）在 M1/M2 调研后兜底**

## M4 · 集成期（人工回归主战场）

**目标**：Release Gate 全绿。**DoD**：05 §10.3 清单逐项打勾。

- [ ] 升级安装实测循环 ≥3 轮（05 §2.5：dev 签名旧版 + `db_heavy` + Plus 账号 → 原生 TF 覆盖 → 12 项数据断言；含"原生写回→再升级"一轮）
- [ ] 付费矩阵（05 §8：7 个测试账号 × sandbox 购买/恢复/过期/退款/删号后恢复购买）
- [ ] 系统事件 + 弱网人工矩阵（§5.3/5.4 全表，Network Link Conditioner）
- [ ] 人工回归 P0/P1 全清单（§6.3 双设备对照，结果记 `rounds/RC-<date>.md`；A1–A9 适配项按豁免处理）
- [ ] 性能回归（§9：50 订阅刷新 hang=0、巨型 OPML、300 条滚动、冷启动）
- [ ] **K 表全量 re-triage（排期纪律，2026-09-22 增补）**：对《05》§11 K1–K38 与《08》全部条目逐条核对落实状态——已实现/有意延后/已被实现细节改变口径，防止 M1–M3 实现期间静默漂移（§10.3 Gate 的"决策表已落实到代码"以此为准）
- [ ] 埋点就位：迁移执行/成功/失败兜底计数、首启关键路径
- [ ] 回滚预案演练：Flutter 维护线出一个可提审 build 走通流程
- [ ] Release Gate 自查（§10.3 全绿）

## M5 · 灰度发布期

- [ ] TF Internal ≥1 周（作者 + 志愿者，冒烟节奏）
- [ ] 提审：What's New 说明完全重构（准则 2.3.12）；元数据/截图与新版一致（2.3）
- [ ] Phased Release 7 天：每日比对 Sentry（崩溃率/`/api/subtitles` 错误率/hang 率）vs Flutter 版最后 30 天基线；异常即暂停放量
- [ ] 观察期后收尾：确认放量 100% 无异常 → 冻结回滚窗口 → backlog 排期讨论（CarPlay、iPad 适配、缓存上限 UI、.lrc 等）

---

## 明确不在本计划内（二期 backlog，05 §11）

CarPlay、完整 iPad 适配、maxCacheCount 设置 UI、导出 .lrc、autoSleepTimer 删除或实现、锁屏快进对齐 +30s、登录页"3 次"文案改"10 次"（纯客户端变更可随时单独做）。

## 执行中的修订规则

- 发现旧版行为与 01–04 基线不符 → **先改基线文档**（附代码出处），再改测试断言；
- 新增做/不做决策 → 写进 05 §11（K 表或战略决策段），不另开文件；
- 阶段顺序可交叉（如 M3 的歌词可提前到 M2 后期启动），但 M0 未完成不得进 M1，M4 未 Gate 全绿不得进 M5。
