# MV · Figma anycast-v2.0 原生落地（v2 视觉 + IA 重构）

> 本文是 MV 里程碑的**规格事实源与任务清单**（V0 审计产出，2026-10-01）。
> 执行主线仍在《00》：MV 位于 M3 与 M4 之间——**M4 的发布门验收对象是 v2**。
> 设计源：Figma 文件 `anycast-v2.0`——完整链接存 Infisical `/app-config` 的 `FIGMA_ANYCAST_V2_URL`，由 `scripts/bootstrap.sh` 物化到本地 `native/.env`（gitignored，不入库；不是仓库根 `.env`），主画板 `4:1749`。
> Token 语义源：`lib/design_system/anycast_theme.dart`（Flutter 侧已合并、未发布，自称 "ported from the UIKit source of truth"）。

## 0. 已拍板决策（2026-10-01）

| 决策 | 结果 | 备注 |
|---|---|---|
| 发布顺序 | v2 先落地，M4/M5 直接验收 v2 | 完整手工回归只做一轮；与 Flutter 线已合并的 2.0 刷新方向一致 |
| 深浅色 | **light + dark 双主题** | 移除 root 的 dark 强制；player 屏按 tokens 保持固定暖深色 |
| 范围 | **完整 v2：IA + 视觉** | 锚定 Figma `📋 Implemented Index`（14 个已验证引用）；探索性功能排除（见 §7） |
| 设计基准 | **sand 系为准** | 与 Flutter v2 tokens 逐值一致；cream/Young Serif 帧为候选，逐屏清单见 §6，默认不采用 |
| 版本号 | 不动（1.2.1+38） | bump 是独立发布步骤（AGENTS） |
| DB schema | **预判无变更** | 见 §8 能力核对；若实施中发现需持久化新偏好，走 DB v5 + 迁移纪律 |
| 展示字体 | **未定稿，待拍板** | Figma 实测三种衬线并存：sand 系帧 Cormorant Garamond、cream 系 Young Serif、另有 Instrument Serif（mini player 卡片态标题 `149:3499`、Index 克隆帧 header 动作字 `1202:23074`（24/36）实测；主画板另有 Young Serif specimen `637:9487`）；V3 批次 5 前拍板，未定稿不随包新增字体文件 |
| 交互件实现 | **原生优先（native-first）**【2026-10-02】 | 交互件默认系统控件与系统交互；自绘准入仅限 ① Figma 帧明确要求系统无法表达的形态（胶囊 pill、独立玻璃圆钮、thumb 显值 slider）② 实测原生达不到。逐件裁定见 §7a，存量自绘件随 V3 批次复核；凡自绘 → 原生的切换属行为变更，先改基线文档（03 对应条目 / 05 §11 K 表）再改实现 |
| 内容避让语义 | **避让到胶囊顶（维持锚点语义）+ 退役 64pt 双重避让**【2026-10-02 拍板，批次1 前置】 | `additionalSafeAreaInsets.bottom` 锚点维持现状（空队列 pill 顶+14 / 播放中胶囊顶+14），静止内容永不被胶囊遮挡（系统浮层 accessory idiom）；列表全出血，滚动时内容本就从 scrim/胶囊下连续流过。v1 Dart-parity 的 64pt 底部 section inset 与上述避让双重计算（Inbox/Subscriptions 两处，滚到底空白主因）一并退役，03 §2.3/§2.4 已注记。否决项：锚 pill 顶（Figma 字面）——末卡静止时被白 80% 胶囊遮住约 58pt |

## 1. Figma 文件地图与工具坑

页面（CANVAS）：

| 页面 | nodeId | 用途 |
|---|---|---|
| `v2.0——————👀` | `4:1749` | **主画板**：全部屏帧 + 组件 + 原型区（swipe/tap card/font size prototype） |
| `📋 Implemented Index` | `1199:18477` | "Session References 2026-05-08"：14 个克隆引用 + Swift 文件名（v2 UIKit 原型的实现索引，范围锚点）。注意：其中 category strip 原件 `637:9227` 与 w/ mini player 原件 `744:7569` **已从主画板删除**，实施以 Index 内克隆帧 `1202:23067`/`1202:23125` 为准。References section 内、14 引用之后是 §6 全部 10 个 cream 帧（1241–1243 区段，见下；注意 cream welcome `1241:8561` 与 sign up 引用 `1202:23523` 同格位叠放——两者均在 580,2732，cream 在上层，Index 页内 sign up 引用被遮盖，取用一律按 nodeId 定位）；section 之外另有：两个按钮规格帧 "🔘 Buttons Inventory"（`1371:15651`/`1376:15839`，见 §5）、无标注探针帧 `1202:25678`（工具产物，忽略） |
| `micro motion` | `247:3993` | 自定义 loading/星形动画组件（body/face 形变、Star） |
| `component` | `4:1578` | 组件库（Tier 1–4 分区注记；含 sheet 族源件：audio setting 1/2 `1429:10290`/`1429:10324`（416 宽 sand1）、playback speed chip 集 `413:5050` + overlay `413:5099` + 实例 `1429:10434`/`1429:10435`、stepper `1382:22220`、font setting `399:4090`、menu-item `1549:12645`、loading `464:9575`、drag down animation `464:9581`；另有一份 font size prototype section `1408:14940`） |
| `visual` / `thumbnail` / `web` / `old` / `Page 10` / `prototype example` | — | 视觉草稿/缩略图/web 探索/v1 归档，**不作为实施依据** |

**工具坑（重要）**：Figma MCP 对本文件做无 depth 全量拉取会因插件产生的 `CUSTOM` paint 整树报错（`Unknown paint type: CUSTOM`）。**必须带 `depth`（1–4）分层拉取**；仍拉不出的子树用 `download_figma_images` 按 nodeId 导 PNG 目测。另注意：主画板这类超大页面即便 depth 1 也会被 MCP 结果预算截断（NODES 清单不完整但 COMPONENTS/COMPONENT_SETS 段完整），清单尾部节点需按 nodeId 单独拉取核对，勿据截断输出断言"无遗漏"（V0.7 实测）。Figma 内的深浅色靠变量模式（values 已由 Flutter tokens 的 Any/Dark 对给出，直接采用，不需要从 Figma 逐帧解析 dark 值）。

两代风格（§6 逐屏裁定）：

- **sand 系（Gen-A，基准）**：背景 sand1-4 / sandDark1-4，gold 强调，Inter（iOS 落地为 SF Pro），Material Symbols Rounded 图标。覆盖 inbox/queue/library/player/settings/show detail/session 引用全部。
- **cream 系（Gen-B，候选）**：`#F4EFE6` 奶油底、`#1B1A18` 文字、Young Serif 衬线展示字、按钮深色渐变（welcome/login 主 CTA `#1B1A18→#000`；`#524538→#2E261F` 棕渐变实测仅见 paywall 价位卡 `1241:8673`/`1241:8676`，见 §10 ⑮）。节点 ID 更新（1241–1243 区段，**全部位于 `📋 Implemented Index` 页 References section 内（14 引用之后），非主画板**），覆盖 welcome/login/paywall/audio sheet/speed sheet/transcript/search/show-detail-loading/history/clear-all。**Flutter tokens 无任何 cream 值**。

**主画板/component 页未登记帧清单（V0.5 实测、V0.6/V0.7 补全；不在 §4 映射与 §7 排除内，实施相关屏时按需取用、默认不做）**：第二 queue 帧 `684:10880`、queue episode card 集 `688:11411`、sort by new&old `596:30234`、archive 帧 `464:9302`、episode block `1084:8645`、float button set `185:4601`/`360:4217`、subscribe button group `360:5461`、episode status 集 `114:3309`、logo 件 `116:3013`/`1112:8419`/`1112:8431`、sleep timer 第二实例 `1505:11893`；**V0.6 补**：player queue header `1493:15870`（内含 queue chip 组件集 `1493:15953`）、episdoe detail-backup `439:7947`、player control 组件 `147:3377`、transcript action 组件集 `332:3308`（+实例 `332:3840`）、chat content 组件 `1549:9089`、inbox 卡松散实例 `1022:7679`、login button 组件 `449:8216`、sleep timer icon 组件 `1505:12042`、无名组件集 `343:13428`/`452:8689`、Liquid Glass 试件 `512:23826`/`751:7843`/`752:7231`/`752:7255`/`752:7245`/`785:10198`/`785:10558`、progress slider 附属 drag/hover 演示帧 `335:3808`/`335:3809`；**V0.7 补（主画板散件）**：第二 library block 组件集 `1575:9948`（"continue=Default" 变体 ×3，392 宽列块、padding 16 0/gap 12，与 `628:6406` 并存的另一版 Library 内容块设计——**Library 屏（V3 批次 2）实施前裁定取舍**）、cover 组件集 `625:31595`（4 变体装饰封面：星形/箭头图形彩底 + 图片填充变体，封面/占位 artwork 件）、状态 chip 行组件 `636:9047`（"episodes 计数 / favorite / wand_stars / delete" pill 行，sandAlpha4 底 pill、SF Pro/MS Rounded 12）、option 行变体 `1545:10128`（sandAlpha3 底 pill、padding 8，内含 4× drawer button，源件=component 页 `1546:10217`）；主画板另存 M3 套件残件组件（App bar `1025:8865`、Button-Content Area `1029:11019`、List `1127:9048`、Sheet-Full Screen `1127:10504`，与 Snackbar `123:7023` 同批 M3 kit 件，仅 Snackbar 被 S20 采用）、Iconify 系图标实例 `198:3684`/`198:3730`/`198:3734`/`198:3738`/`198:3742`、小占位/文字注记帧（`752:7228-7230` 三色小帧、`1816:7987`、`603:30380-82`、`596:30244`、`740:7970-72` 图标名注记、`335:3766-3777` drag 标签、component 页 `1429:10483-10494` press/default 注记）——**均忽略**；已登记组件的松散实例（`123:7061`/`1081:8372`/`507:14810`/`1589:9079`/`515:24880`/`1429:10546` 等）与已映射屏的子组件（`1449:9329`/`512:24431`/`387:4010`/`449:8239`/`1112:8943`/`1090:8365`/`1549:12126`/`240:7240`/`452:8637` 等）**不逐一登记**，按需取用。component 页另有 player button 按压态三组件集 `365:5008`/`638:9549`/`1496:9535`（**S12 实施相关**：pressed 态带 blur/形变处理，V3 批次 3 取用）、Toggle-Switch `247:5480`、.text option `1389:9007`、.icon-24-44 `1389:9002`、.stepper/item `1382:22235`、popover option group `1552:9662`、font setting 实例 `1408:14939`（component 页 Tier 分区内其余组件源件/实例为组件库本体，不逐一登记，按需取用）。**非规格参考（忽略）**：web 样式目录 Styles `76:2988`（黑底、Roboto Flex 字阶与 #383838/#FFF/#000 色板，非 v2 iOS 规格）、画板参考截图 `600:30377`/`603:30378`/`603:30379`/`590:30229`/`629:6552`/`629:6553`/`651:9561`、component 页黑底试片 `1565:11329`。

## 2. Token 对拍表（Figma ↔ Flutter ↔ native 落地）

### 2.1 颜色

原生落地方式（V1 实测为**两种机制并存**）：**raw 刻度 token**（Sand/SandDark/Gold/GoldDark/player 静态组）为单外观 colorset，一 token 一个，dark 侧以 `SandDark*`/`GoldDark*` 分立 colorset 表达；**语义层与 alpha 档**为 Any+Dark 双外观 colorset（Any=light 值、Dark=dark 值），由 `Theme.swift` 语义访问器读取（§2.2，语义 colorset 全量清单见 §2.2a）。下表左两列已逐值核对一致（Figma 主画板取样 vs `anycast_theme.dart`；唯一例外见 playerGradient 行注）。

| Token | Light | Dark | native colorset 名 |
|---|---|---|---|
| sand1 | `FDFDFC` | —（仅 light 用） | Sand1 |
| sand2 | `F9F9F8` | — | Sand2 |
| sand3 | `F1F0EF` | — | Sand3 |
| sand4 | `E9E8E6` | — | Sand4 |
| sand6 | `DAD9D6` | — | Sand6 |
| sand7 | `CFCECA` | — | Sand7 |
| sand9 | `8D8D86` | — | Sand9 |
| sand10 | `82827C` | — | Sand10 |
| sand11 | `63635E` | — | Sand11 |
| sand12 | `21201C` | — | Sand12 |
| sandDark1 | — | `111110` | SandDark1 |
| sandDark2 | — | `191918` | SandDark2 |
| sandDark3 | — | `222221` | SandDark3 |
| sandDark4 | — | `2A2A28` | SandDark4 |
| sandDark6 | — | `3B3A37` | SandDark6 |
| sandDark9 | — | `B5B3AD` | SandDark9 |
| sandDark11 | — | `D2D0CA` | SandDark11 |
| sandDark12 | — | `EEEEEC` | SandDark12 |
| gold9 / gold10 | `978365` / `8C7A5E` | — | Gold9 / Gold10 |
| goldDark9 / goldDark10 | — | `CBB99F` / `D8C8AE` | GoldDark9 / GoldDark10 |
| goldSoft | `F4F0E7` | 同 | GoldSoft |
| orange10 | `EF5F00` | 同 | Orange10 |
| grass9 | `46A758` | `63C174` | Grass9（双外观） |
| tertiary（ Flutter 内联） | `EF5F00` | `FF8B3E` | Tertiary（双外观） |
| error | `BA1A1A` | `FF8B8B` | Error（双外观） |
| sandAlpha2 | `rgba(37,37,0,.03)` | `rgba(246,246,245,.05)` | SandAlpha2（双外观） |
| sandAlpha3 | `rgba(32,16,0,.06)` | `rgba(246,246,245,.08)` | SandAlpha3 |
| sandAlpha4 | `rgba(31,21,0,.10)` | `rgba(254,254,243,.12)` | SandAlpha4 |
| sandAlpha5 | `rgba(31,24,0,.13)` | `rgba(251,251,235,.17)` | SandAlpha5 |
| sandAlpha8 | `rgba(25,21,1,.29)` | `rgba(255,249,235,.34)` | SandAlpha8 |
| sandAlpha9 | `rgba(15,15,0,.47)` | `rgba(255,250,233,.48)` | SandAlpha9 |
| sandAlpha10 | `rgba(12,12,0,.51)` | `rgba(255,253,238,.58)` | SandAlpha10 |
| sandAlpha11 | `rgba(8,8,0,.63)` | `rgba(255,252,244,.72)` | SandAlpha11 |
| sandAlpha12 | `rgba(6,5,0,.89)` | `rgba(255,255,253,.93)` | SandAlpha12 |
| goldAlpha2 | `rgba(157,138,0,.05)` | `rgba(249,226,157,.08)` | GoldAlpha2 |
| goldAlpha3 | `rgba(117,96,0,.09)` | `rgba(248,236,187,.14)` | GoldAlpha3 |
| goldAlpha7 | `rgba(99,66,0,.33)` | `rgba(255,224,164,.42)` | GoldAlpha7 |
| goldAlpha9 | `rgba(83,50,0,.60)` | `rgba(255,219,166,.70)` | GoldAlpha9 |
| goldAlpha10 | `rgba(73,45,0,.63)` | `rgba(254,223,176,.80)` | GoldAlpha10 |
| playerWarm / playerBackground | `867D75` / `222221`（静态，双主题不变） | 同 | PlayerWarm / PlayerBackground |
| playerText / playerSecondary | `EEEEEC` / `D2D0CA`（静态） | 同 | PlayerText / PlayerSecondary |
| playerArtworkScrim | `rgba(0,0,0,.50)` | 同 | PlayerArtworkScrim |
| transcriptSurface | `rgba(0,0,0,.32)` | 同 | TranscriptSurface |
| playerGradient overlays | Flutter overlay 5 档 `.20/.25/.376/.40/.50` 叠 playerWarm；Figma 帧实测为 `0/.20/.38/.40/.50`（stop 0/25/50/75/100%）——**两侧既存微差，实现以 Flutter 为准**（`Theme.playerGradientStops` 已按 Flutter 落地） | 同 | 代码常量（PlayerGradient） |

v1 的 16 个 colorset（PrimaryColor 0x34D399 系等）**整体退役**，同一 PR 内删旧建新，`Theme.x` 访问点全量改写；歌词两字面 token（lyricGrey200/lyricGreenAccent，现为 Theme.swift 内 UIColor 字面量）随 Transcript 屏 v2 化一并处置。

### 2.2 语义层映射（`Theme.swift`，随 trait 自动切换）

按 Flutter `_build(brightness)`：`background=sand2/sandDark2`、`surface=sand1/sandDark1`、`surfaceContainer=sand3/sandDark3`、`surfaceContainerHigh=sand4/sandDark4`、`surfaceContainerHighest=sand6/sandDark6`、`outline=sand6/sandDark6`、`outlineVariant=sandAlpha4`、`onSurface=sand12/sandDark12`、`onSurfaceVariant=sand11/sandDark11`、`primary=gold9/goldDark9`、`onPrimary=sand1/sand12`、`inversePrimary=goldDark9/gold9`…（其余见 anycast_theme.dart 213-244 行，逐条搬）。

**2.2a 语义 colorset 清单（V1 实际落盘，16 个 Any+Dark + 1 个单值，`Theme.swift` 语义访问器逐一读取）**：`Background`=sand2/sandDark2、`Surface`=sand1/sandDark1、`SurfaceContainer`=sand3/sandDark3、`SurfaceContainerHigh`=sand4/sandDark4、`SurfaceContainerHighest`=sand6/sandDark6、`Outline`=sand6/sandDark6、`OutlineVariant`=sandAlpha4、`OnSurface`=sand12/sandDark12、`OnSurfaceVariant`=sand11/sandDark11、`Primary`=gold9/goldDark9、`OnPrimary`=sand1/sand12、`PrimaryContainer`=sandAlpha4、`OnPrimaryContainer`=sand12/sandDark12、`SecondaryContainer`=sand3/sandDark3、`InversePrimary`=goldDark9/gold9、`InverseSurface`=sand12/sandDark12，另单值 `AccentColor`=#FFBC25（app tint）。加上 §2.1 表内 47 个 raw token colorset，共 **64** 个（与 §10 进度一致）。Flutter ColorScheme 其余语义**有意未落盘**：secondary（=sand11/sandDark11）、onSecondary/onTertiary/onError/onInverseSurface（=surface）、onSecondaryContainer（=onSurface）、surfaceContainerLowest（=surface）、surfaceContainerLow（=background）、shadow/scrim（=black）——均为已有 token 的别名；V3 逐屏需要时按需增补，非遗漏。

### 2.3 间距 / 圆角 / 动效

- `Spacing`：4pt 网格命名刻度 `xxs2 xs4 sm6 md8 row10 gap12 chip14 pageH16 cardInner20 pageHeader24 sectionGap28 large32 pageSection36 xl40 xxl48` + 派生 `sheetTitleH64 rowH70 pageBottomSafe88 floatingOutset8 compactProgress4 playerProgress6 hairline1`。
- `Radius`：`sm8 md16 artwork18 card24 largeCard32 modal58 pill999`。
- `Motion`：`quick180ms standard280ms emphasized420ms`，曲线 easeOutCubic——控制点 `(0.215, 0.61, 0.355, 1)`，`Metrics.swift` 的 `Motion.standardCurve` 已按此落地（此前记录的 `(0.33,0,0.2,1)` 属另一条曲线，作废）。

### 2.4 字体（Typography v2）

系统字体（SF Pro；Figma 的 Inter 是系统字体代理，Flutter 侧同样落 `.AppleSystemUIFont`）+ `UIFontMetrics` 动态字体：

| 样式 | size/line | weight |
|---|---|---|
| displayLarge | 48/48 | w900 |
| displayMedium | 34/41 | w400 |
| displaySmall | 28/34 | w400 |
| headlineLarge | 28/34 | w600 |
| headlineMedium | 22/28 | w600 |
| headlineSmall | 17/22 | w600 |
| titleLarge | 20/25 | w600 |
| titleMedium | 16/21 | w500 |
| titleSmall | 15/20 | w600 |
| bodyLarge | 17/22 | w400 |
| bodyMedium | 15/20 | w400 |
| bodySmall | 13/18 | w400 |
| labelLarge | 17/22 | w600 |
| labelMedium | 12/16 | w600 |
| labelSmall | 11/13 | w500 |

展示字（wordmark/营销标题）**未定稿，见 §0 决策表**：Figma 实测 sand 系帧用 Cormorant Garamond（"anycast" 44pt / 0.1em / TITLE）、cream 系用 Young Serif，另有 Instrument Serif 出现；拍板前不随包新增字体文件（当前 `TypographyV2` 为纯系统字）。v1 的 Comfortaa/NotoSans/MPLUSRounded1c/Roboto/RobotoMono 在逐屏迁移后按实际引用清退。

### 2.5 图标（Material Symbols Rounded → SF Symbols 初版映射）

`AppIcons.swift` 重写。已从帧中实测的图标名 → 建议映射（终版在 V1 随图标审计敲定）：

| Material Symbols | SF Symbols |
|---|---|
| inbox | tray.fill（已落地 AppIcons） |
| subscriptions | play.rectangle.on.rectangle |
| collections_bookmark | bookmark.square.grid.2x2 |
| search | magnifyingglass |
| cloud_download | icloud.and.arrow.down |
| wand_shine | wand.and.stars |
| bookmark | bookmark |
| keyboard_arrow_right | chevron.right |
| moon / bell | moon / bell |
| more | ellipsis |
| play_arrow / pause | play.fill / pause.fill |
| replay_10 / forward_10 / forward_30 | gobackward.10 / goforward.10 / goforward.30 |
| speed | speedometer |
| timer / bedtime | timer / moon.zzz |
| share | square.and.arrow.up |
| add / close / check | plus / xmark / checkmark |
| history | clock.arrow.circlepath |
| settings 齿轮 | gearshape |
| delete | trash |

4 个品牌 SVG（aiChat/tablerTopology/newDoc/aiTranscript）按 v2 视觉重导出。

注：cream 帧内少量图标为 Material Icons 而非 Material Symbols Rounded（history 行 `chevron_right`、clear all `close`、cream login `account_circle/mail/lock/arrow_forward/apple`），映射按语义等价处理。

## 3. IA 变更清单（v1 → v2）

1. **底部 Tab**：Podcasts(Inbox+Subscriptions)/Playlists/Discover → **Inbox / queue / library** 三 tab + **圆形搜索按钮**。
   - 规格（Buttom Tab 组件 `243:7288`，light 实测）：外层渐变 scrim `linear(180°, transparent→sand1)` + blur(10)；内层**浮动胶囊** `rgba(255,255,255,.8)` + `Radius.pill` + 阴影 `0 20 40 /10%`（**无描边**——2026-10-02 复测确认），padding 4；tab 按钮 100×64（icon 24 + SF Pro 12 **Regular·TITLE 大写** label，间距 4），激活态 `goldAlpha2` 底 + `sandAlpha4` 0.5px 描边 + pill 圆角，icon/label 色 `goldAlpha9`；非激活色 `sandAlpha10`、无底无描边。图标：inbox→`inbox`、queue→`subscriptions`、library→`collections_bookmark`。**scrim 根节点实测（同日）**：padding 24/16（pill 上方仅 24pt 渐隐带）；pill 深色形态未定——组件 fill 为静态 `rgba(255,255,255,.8)` 非变量（无 dark 模式值），native 落地 `Theme.surface` 80%（深色近黑胶囊），深色下是否应白色系待设计复核。
   - **搜索按钮**：72×72 玻璃圆钮（`rgba(177,177,177,.3)` + 高光描边渐变 + 48pt 白 30% blur2.5 高光层 + 双层渐变描边 2px/0.5px + 阴影 `0 30 30 /10%`，图标 **MS Rounded 32pt**）位于 scrim 行内 **pill 右侧**（组件 243:7288 节点树实测：row = pill(fill) + gap12 + 圆钮；activeTab4-6 的 72 高输入条形态同样在右侧）。**勘误（2026-10-02）**：本条原文"居中悬浮"为 V0 误读，"居中"仅指与 pill 垂直居中（alignItems: center）；native 落地右置正确。注意玻璃规格实测于 Inbox 变体的圆钮 `240:7217`（glass 子层填充 + 双层 highlight 描边，阴影 `0 30 30 /10%`；Index 克隆帧 `1202:23122` 内同款）；queue/library 变体内的圆钮（`243:7294`/`243:7307`）仍是旧版白底 `rgba(255,255,255,.8)`+`sandAlpha4` 0.5px——**以 Inbox 变体玻璃规格为准**。在 activeTab4-6 变体中展开为 72 高胶囊输入条（`goldAlpha2` 底 + `sandAlpha4` 描边 + "search | ask anything"）——即搜索与 AI 提问合体的入口。落地：首版做**点击推入 Search 屏**，"ask anything" 输入形态记入待裁定（与 chat 入口合并）。
   - **bar 底部摆位（2026-10-02 实测补记）**：克隆帧 `1202:23125`（479×993）pill 底位于屏高 93.5%（y928），与 home indicator（y956）间 ~28pt 空隙——落地为 pill 底距 bottom safe-area 边 12pt（`BottomTabBarView.bottomGutter`），scrim 高度随 safe inset 联动（`ChromeMetrics.barOverlayHeight(safeBottom:)`）。首版曾钉物理底 -12 导致 pill 下缘压 indicator 线。
   - **chip 分布（2026-10-02 实测补记）**：组件内 chip 固定 100 宽 + pill 内 `space-between`（480/479 base 间隙 ~27pt）；402 屏按比例落地：chip 宽 = pill 宽 × 300/363，首尾 chip 钉 pill 内缘、中 chip 居中（等间隙 ~21pt）。首版曾等宽吃满 + 4pt 死间隙（挤成连体）。
   - Flutter 侧 nav bar（72 高透明 + sandAlpha2 indicator）是简化版；native 按 Figma 胶囊规格实现。
2. **Inbox**：新增 **category strip**（`637:9506` 组件；原帧 `637:9227` 已从主画板删除，以 Index 克隆帧 `1202:23067` 为准）：胶囊项 icon+label、高 44——**选中** = `state=selected` 变体（`599:30269`）：`goldAlpha7` 底 + `sandAlpha4` 1px 描边 + pill，icon（MS Rounded 24）/label（SF Pro 590·16/21）色 `sand1`；**未选中** = `sandAlpha2` 底 pill（`599:30275`，min 54×44；Figma 实例上残留 `selected:true` 属性误标，判别以变体组件为准）+ "see all podcast" 提示卡片（`599:30354`，`sandAlpha2` 底 radius16）。已落盘 `CategoryStripView` 选中态误用 `sandAlpha2`（`CategoryStripView.swift:118`），修正任务见 §10 V2。数据源 = `subscription.categories`（逗号分隔，已有列）。
3. **Subscriptions 屏** → 并入 **library** tab（`86:2814`，library block 组件 `628:6406`：封面横滚 + 内容块 + membership 块）。
4. **Playlists tab** → **queue** tab（`1020:7525` QueueView v2：顶部 archive 封面带 + header + 队列卡片列表）。
5. **Discover 屏**退役：分类浏览并入 search - browse（`1243:8561`，Browse 列表）；发现能力入口 = 搜索按钮。
6. **mini player 常驻胶囊**（`83:2616`/`1202:23705` 三态组件 MiniPlayerAccessory）：a) 列表尾通栏条（440×70）；b) 卡片态（420 pill）；c) player 胶囊态（392 pill，`rgba(255,255,255,.8)` + `sandAlpha4` 1px 描边 + 阴影 `0 8 10 /5%`；克隆帧在 16pt 边距下实宽 408，落地按页边距自适应）。iOS 26 `UITabAccessory` 保留、iOS 18 悬浮实现改胶囊。
7. **新增 Welcome 屏**（`131:2742`）+ **SignUp 流程**（`131:2540`）：signup 能力现状见 §8。
8. **v2 header**（`624:30831`）：单行 `title + status info + clear 动作`（padding 0 12）取代 v1 大标题渐变 AppBar + 内嵌搜索框（搜索移至 tab 条圆钮）。设置入口（齿轮）随 header 重排。

## 4. 屏幕映射表（S1–S21 → v2 帧）

| v1 屏 | v2 帧（nodeId） | 处置 |
|---|---|---|
| S1/S2 Inbox | `76:2614`(dark)/`1787:7899`/`1787:8175`/`1634:8632`；category strip 克隆帧 `1202:23067`（原件 `637:9227` 已删）；w/ mini player 克隆帧 `1202:23125`（原件 `744:7569` 已删） | 重设计（三态） |
| S3 Subscriptions | 并入 `86:2814` library | 合并重构 |
| S4 Channel | `365:4610` show detail（+ loading 骨架 `1243:8631`★cream） | 重设计 |
| S5 Episode Detail | `507:14681` episdoe detail modal 集（`1784:7538` 等 5 帧） | 重设计（sheet） |
| S6 Playlists | `1020:7525` queue（QueueView v2） | 重构为 queue tab |
| S7 History 对话框 | `1243:8672` history section + `1243:8716` clear all★cream | 重设计（cream 候选） |
| S8 Discover | 退役；browse 并入 search `1243:8561`★cream / sand 版 `186:1866` 等 | IA 变更 |
| S9 Search | `186:1866`/`1565:11791`/`1565:11491`（sand）+ `1243:8561`★cream | 重设计 |
| S10 Mini player | `83:2616`/`1202:23705` 三态组件 | 重设计 |
| S11 播放器设置页 | sheet 族：`1505:11577` sleep timer / `1425:9670` podcast setting / `1408:9059` transcript setting / `1408:8905` audio | 重设计 |
| S12 播放器主控 | `83:3123`/`446:7951`/`1496:11374`/`1505:11474`/`1525:8898`(palette 渐变)/`446:8021`/`449:8412`；拖动态 `140:4362` | 重设计 |
| S13/S14 转写/歌词 | `1242:8704` transcript★cream + item `1525:9086` + segment control `399:5076` + `398:4865` transcript block | 重设计（cream 候选） |
| S15 Chat | `186:1969` default / `1549:9223` type in / ai mode `353:3528` | 换肤 + 输入栏重设计 |
| S16 Settings | `100:4132` + section `1445:9295` + Ai Intelligence `1459:9176` | 重设计 |
| S17 Login(+welcome) | `131:2742` welcome / `439:7134` Apple / `439:7045` mail / login control `449:8207` | 重设计 |
| S18 Email 登录 | `439:7045` login mail + `131:2485` forgot password | 重设计 |
| S19 导入/导出 | **无 v2 帧** | 保持结构换肤 |
| S20 401 登录 sheet/错误弹窗 | Snackbar `123:7024`（M3 组件集） | 换肤 |
| S21 Paywall | `149:8891` membership + `149:9033` plus entrance + feature block `1112:8981` | 重设计 |
| — 新增 Welcome | `131:2742` | 新建 |
| — 新增 SignUp | `131:2540` | 新建（能力见 §8） |
| — ImportInstructions | 无 v2 帧 | 换肤 |

## 5. 关键组件规格备忘（实现时直接引用）

- **inbox 卡片**（Container 组件集 `363:3558`，`744:9107` inbox card 变体）：**2026-10-02 批次1 复测更正——白底 radius **34**（原记 16 系误读）、内边距 16/20/8（上/左右/下），发丝描边 rgba(32,16,0,.06)=sandAlpha3（非 outlineVariant 档）、阴影 0 1 20 /4%**；结构 = 标题 17 onSurface·TITLE 大写 + 描述 14（属性 `description`）+ 60pt 状态行（36 圆节目封面 + 节目名 12 TITLE + 日期 12，间距 12；计数 pill goldAlpha3 底/goldAlpha9 字 14；`more` 60×60 位 MS Rounded 24 sandAlpha9）；属性开关 `Show transcripted / state icon(cloud_download) / state icon2(wand_shine) / download(bool) / downloaded(icon) / episode count / more / description / shows background / Show state / episode art`（Figma 实际属性名；download 族图标位未随批次1 落地，`shows background` 装饰背景板暂不采用，`episode count` 语义未证实暂映射时长★）。已落盘 `InboxEpisodeCardCell`（2026-10-02）。
- **queue item** `112:4497`：行 padding 12 0 0、顶描边 `sand4 1px 0 0`。
- **player content** `1489:13974`：column、居中、gap24（**padding 注记（2026-10-02 实测）：组件属性为 `0 36`，但屏帧（`83:3123` 等）实测两侧 inset 24（封面 354@402 屏）——组件与屏帧不一致，暂以屏帧为准（native 现值 24），★V3 批次 3 实施时终裁**）；main control `1496:10849`（row gap12 高100）、button group `1496:10850`（pill `sandAlpha3` 底、padding 12 24、gap24）。
- **Scrubber** `125:7117` + progress slider 集 `332:5016`。
- **sheet** `1382:22149`（416 宽、底部 16 padding、透明底）+ option item `1382:22093`。
- **episode detail modal** `507:14630`：`sand1` 底 radius48、shadow `0 0 10 /6% + 0 10 20 /13% + inset 0 4 4 2 rgba(255,255,255,.25)`。
- **show detail** `512:24219`：`#CECCC9` 系封面头 + control header `1597:10129`（高64）+ scroll header `1593:10380`（白渐隐 scrim）。
- **Snackbar** `123:7024`：M3 elevation3、radius4→落地按 v2 收敛为 radius16。
- **Buttons Inventory**（Index 页 `1371:15651`/`1376:15839`，标注 "Synced 2026-05-12"）：v2 UIKit 原型的按钮规格总账，4 列（Primary/Secondary/圆形 Secondary/圆形 Primary），注明 "3 ButtonStyle abstractions in DesignSystem/Buttons.swift · 22 size/padding variants"（指原型工程，非本仓库）；并明确 **production 按钮语言 = Liquid Glass：Primary `glass.tint(sand12)`、Secondary 透明 `glass.regular`，帧内实色填充仅为清单可读性**。V1 GlassContainerView 与 V3 组件库按钮族 reskin 以此为规格锚点复核。
- **动效**（micro motion `247:3993`）：loading 组件 = body/face 形变三态 + 星形（Star 1/2）；`515:25133` loading 集 440 方形（Gen-B cream 方向，若 §6 裁定采用）。落地：Lottie 重制或 CADisplayLink 自绘，**V3 批次 1 前拍板**（原记 "V1 定"，V1 收尾时未决顺延；首个消费者为 ShowDetail loading 骨架 `1243:8631`）。

## 6. 两代风格逐屏裁定表（默认 sand；★=cream 候选，待人工终裁）

| 屏 | sand 帧 | cream 帧（节点更新，均位于 Index 页） | 默认 |
|---|---|---|---|
| welcome/login/paywall | `1202:23399`/`1202:23443`/`1202:23657`（session 引用，sand） | `1241:8561`/`1241:8585`/`1241:8631` | sand |
| audio/speed sheet、transcript、search-browse、show-detail loading、history、clear-all | 见 §4 各行（sheet 族 `1505:11577`/`1425:9670`/`1408:9059`/`1408:8905`、transcript `398:4865`+`1525:9086`、search `186:1866` 族、speed sheet 源件=component 页 `413:5099`/`413:5050`+`1429:10434`） | `1242:8561`/`1242:8647`/`1242:8704`/`1243:8561`/`1243:8631`/`1243:8672`/`1243:8716` | sand |
| 其余全部屏 | 主画板 | 无 cream 版 | sand |

裁定规则：如逐屏改判 cream，需同步 ① 新增 cream token 组（`F4EFE6/1B1A18/6F6A60/FDFCFA/rgba(27,26,24,*)`、散值 `#C8AE80`（Subscribed pill）/`#A8A294`（弱化次级文字，见 §6a 补记）、链接/星号辅助绿 `#33A852`（"Forgot password?"/"Sign up" 链接与必填星号，cream login `1241:8585` 实测）、按钮渐变 `524538→2E261F`）② Young Serif 字体入包 ③ 更新本表与 00 进度注记。**cream 帧形态注记（V0.5 实测）**：audio sheet（`1242:8561`）= 黑色 scrim + 悬浮 `#FDFCFA` 卡（408×580、r34、`rgba(27,26,24,.05)` 描边）；speed sheet（`1242:8647`）= 黑 scrim + 底部 `#F4EFE6` sheet（440×600、顶 r28、grabber `rgba(27,26,24,.2)`、内卡 `#FDFCFA` r24）——两帧非整屏奶油底，改判 cream 时按此结构落地。另注意：show-detail loading（`1243:8631`）、history（`1243:8672`）、clear all（`1243:8716`）**仅有 cream 帧**——按默认 sand 裁定执行时，结构照 cream 帧、用色按下表换算落地。

### 6a. cream→sand 换算表（cream-only 帧按 sand 落地；草案，V3 批次 2 首屏前终裁）

适用对象：上表"仅有 cream 帧"的三处——show detail loading（`1243:8631`）、history section（`1243:8672`）、clear all（`1243:8716`）。原则：**按角色换语义 token，不做数值折算**（与 §2.1 playerGradient "实现以 Flutter 为准"同思路），alpha 档位差异接受。左列为 2026-10-01 Figma 实测（来源注记：history 行=`1243:8672`、clear all 行=`1243:8716`、loading 补记行=`1243:8631`；"输入底"`.03` 实测于 cream login 邮箱输入位 `1241:8601`——本表作 cream→sand 角色总表使用，取值来源不限于三帧本身）。

| cream 帧实测 | 角色 | sand 落地（Any/Dark 自动切换） |
|---|---|---|
| `#F4EFE6` | 页面底 | `Theme.background` |
| `#FDFCFA` + `rgba(27,26,24,.05)` 1px 描边、radius24 | 卡片/浮面 | `Theme.surface` + `Theme.outlineVariant` |
| `#1B1A18` | 主文字 | `Theme.onSurface` |
| `rgba(27,26,24,.4)`（36pt "history"） | 大号弱化标题 | `Theme.onSurface` + 40% alpha（或 `AnycastColor.sandAlpha9` 近似档）★终裁 |
| `#6F6A60` | 次级文字 | `Theme.onSurfaceVariant` |
| `rgba(27,26,24,.03)` | 内嵌输入底 | `Theme.surfaceContainer`（inset 角色取 container，不折 alpha） |
| `rgba(27,26,24,.04)` | 圆形 icon chip 底 | `AnycastColor.sandAlpha2` |
| `rgba(27,26,24,.06)` | 行分隔 hairline | `Theme.outlineVariant` |
| `#736357` | history 行缩略占位底 | `Theme.surfaceContainerHighest`（占位非语义色，★终裁） |
| `rgba(245,158,11,.2)` 底 + `#C2410C` 字 | clear all 动作 pill | 字 `Theme.tertiary`（同橙族 EF5F00）+ 底 tertiary 20% alpha；若裁定破坏性语义则 `Theme.error` 系 ★终裁 |
| `#C8AE80` 底 + `#1B1A18` 字（Subscribed pill，`1243:8644`） | 强调动作 pill（loading 帧） | 底 `Theme.primaryContainer` + 字 `Theme.primary`（或 goldSoft 底）★终裁 |
| `#A8A294`（"Loading episodes…"、行描述） | 弱化次级文字 | `Theme.onSurfaceVariant` |
| `rgba(27,26,24,.15)` / `.6`（spinner 轨/弧，`1243:8655`/`1243:8656`） | 加载指示 | `Theme.outlineVariant` / `Theme.onSurface` |
| Young Serif 24（"Just pod" 标题，`1243:8640`） | 展示标题（loading 帧） | 展示字未定稿（§0），暂以 `titleLarge` 占位 ★终裁 |

cream 帧内出现未列取值时按"最接近语义角色"处置并在本表补记。若逐屏改判 cream，走 §6 裁定规则 ①②③，不用本表。

## 7. 明确不做（探索性功能，后端/产品未验证）

share clips（`387:3797`）、saved clip（`377:3785`）、AI summary 块（`965:7905`）、notebook or collection（`452:8518`）、popover（`949:7293`）、"ask anything" 输入态合体（首版仅搜索推屏）。另：Index 区两个无标注帧 profile（`1222:8561`）、inbox - empty（`1233:8561`）不在 14 引用锚点内、无对应规格与需求，默认不做。主画板 "login android" 帧（`125:7253`，登录屏的 Android 变体）亦不在任何映射与锚点内，iOS 迁移默认不做。设计保留在 Figma，产品决策后另开任务。

## 7a. 交互件原生优先裁定（2026-10-02 登记，随 V3 批次落实）

**原则**：交互件默认采用系统控件与系统交互，自绘仅限两种准入——① Figma 帧明确要求系统无法表达的形态（胶囊 pill、独立玻璃圆钮、thumb 显值 slider 等）；② 实测原生达不到设计效果。论据：sheet 族全线走 `UISheetPresentationController` 后近零维护成本，对照胶囊 tab 条自绘付出的三轮修补与 §9a 两条地雷；设计侧亦已背书（§5 Buttons Inventory：production 按钮语言 = Liquid Glass，即系统玻璃）。B 类件换肤时只改皮不改交互结构；C 类切换属行为变更，按修订规则先改基线文档再改实现。

**A. 已原生（保持，勿自绘化）**：sheet 族（`AppSheets` detents、Detail 0.7/0.6 自定义 detent）；玻璃（`GlassContainerView` → iOS 26 `UIGlassEffect` / 18 降级 blur）；列表（compositional + diffable）；下拉刷新 `UIRefreshControl`；分享 `UIActivityViewController`；简单弹窗 `UIAlertController`；取值件 `UIPickerView`/`UISwitch`；下拉菜单 `UIMenu`（login more、字幕 more 两处）；键盘避让 `keyboardLayoutGuide` + interactive dismiss；播放器 pager `UIPageViewController`。

**B. 自绘保留（准入理由）**：`BottomTabBarView`（胶囊 + 独立玻璃圆钮非 UITabBar 形态；成本已付，勿再扩大自绘面）；`PlayerProgressBar`（无 thumb 胶囊 + buffered 层 + §9 点击显数/松手回退交互）；`PlayerValueSlider`（thumb 内显值文字，`UISlider` 不可表达）；`CategoryStripView`（无原生 chip 控件）；`ToastPresenter`（iOS 无原生 toast）；`MarqueeLabel`/`ProgressRingView`/`EpisodeProgressBackdrop`/`PlayPauseIconControl` 等纯视觉件。

**C. 换原生候选（挂批次，实施时终裁）**：

| # | 现状 | 原生替代 | 挂点 | 前置 |
|---|---|---|---|---|
| C1 | 列表卡操作 = 整卡点击展开 60pt 卡内操作条（`CardExpandCoordinator`，03 §2.11 Dart parity）；全仓无 context menu / swipe actions | `UIContextMenuConfiguration`（preview 可复用 Detail sheet）+ `UISwipeActionsConfiguration`；v2 inbox 卡 `more` 属性 → `UIMenu` pull-down | 批次1 Inbox 卡【**Inbox 全量落地，2026-10-02：context menu 半边 + 批次1 半场补齐 swipe/more，见 §10 进度注记**】；Channel/Search 卡随所属批次跟进 | 行为变更：先改 03 §2.11 与 05 §11 K 条目（实施时 K 表无相关条目，落在 05 §6.1/§6.3） |
| C2 | SearchEntry = sheet 内自定义 `UITextField`；SearchPage 输入同构 | `UISearchController`/`UISearchBar`（取消/清空/键盘管理/iPad 适配）；至少字段本体换 `UISearchBar` 换肤 | 批次4 v2 搜索屏重建时评估（"ask anything" 合体仍按 §7 排除） | — |
| C3 | `UnderlineTabBarView`（v1 皮 + 自管 tap/指示条；Comfortaa/legacy token 待换） | 对照 iOS 26 `UISegmentedControl` 新设计与 Figma segment control `399:5076` 终裁；iOS 18 降级路径一并裁定（Dynamic Type/a11y 为原生免费收益） | 批次3 transcript / 批次4 search tabs | — |
| C4 | `DialogBaseViewController` 族（Import/Export、Share、History 居中暗卡，Get.dialog parity） | form sheet 化（`AppSheets.presentForm`）；History 已有 v2 帧（`1243:8672`） | 批次2 History；批次5 Import/Export/Share（S19 无 v2 帧，结构裁定权在本条） | 03 §2.15 同步 |
| C5 | `SettingsTooltipOverlay` 自绘 2s 浮层；Figma stepper `1382:22220` 未落地 | 长按 `UIMenu` 替代 tooltip；stepper 优先 `UIStepper` 换肤 | 批次3 sheet 族 | — |

## 8. 能力核对结论（2026-10-01 实测）

- **SignUp**：Flutter `lib/states/user.dart` 的 `registerWithEmail`（Firebase createUser）**是注释掉的死代码**，`login.dart` 有 registerWidget UI 但未接线。native v2 同口径：**SignUp UI 按 Figma 落地，auth 接线留 TODO 并在 00 注记**（产品决定后再启用，不私自开通注册能力）。
- **category strip 数据**：`subscription.categories` 列已存在（rss_fetcher 写入，逗号分隔）→ **无 schema 变更**。分组逻辑纯客户端。
- **queue tab** = 现有 playlist 表 + PlaybackService 队列语义（episodes[0] 即当前曲）；**library tab** = subscription + playlist + membership 卡（RC entitlement）。均无 schema 变更。
- **Import/Export、OPML**：无 v2 帧，结构保持 v1。
- **K 表（05 §11，现有 K1–K40）**：纯视觉类 K 条目不受 v2 影响；交互类如有变化（如 §9）按"先改基线文档（03/05）再改实现"纪律登记。

## 9. 交互备注（从 Figma 画板文本摘录，需落入 03 对应条目与 05 §11 K 表）

- `335:3763`（progress slider）：点击进度条出现当前进度数字，拖拽切换数字+进度，松手**回到点击前视觉但保留进度**。
- swipe/tap card/font size prototype 三区（`106:4490`/`149:9826`/`1408:11856`）：卡片点开原型、字号缩放原型——实施对应屏时以原型区动效为准复核。

## 9a. 迁移地雷清单（实施时逐屏核查）

- **CGColor 快照冻结**：v1 colorset 是单外观，`someUIColor.cgColor` 处处安全；v2 双外观下 `.cgColor` 在配置时刻按当前 trait 冻结，且 CAShapeLayer/CAGradientLayer 不会随 trait 变化自动重取。逐屏迁移时：player 族一律用静态 player token；其余 layer 用色点必须收敛到「`resolvedColor(with: traitCollection)` + `traitCollectionDidChange` 重取」模式（V4 trait 翻转前全量核查一遍 `grep -rn "\.cgColor" Anycast/Sources`）。
- **UIVisualEffectView 禁 mask**（2026-10-02 底栏 scrim 实测）：给 effect view 自身或任何祖先视图加 layer mask（渐隐 blur 的常见尝试）会让 blur **整体静默失效**——不报错、不留 View Debugger 线索，只是渲染成完全透明。需要"blur 边缘渐隐"效果时改用梯度分片 + `UIViewPropertyAnimator.fractionComplete`（逐片强度）或干脆用不透明度递增的 surface 渐变替代（底栏终案）。
- **配置按钮 isSelected 注入矩形底**（2026-10-02 底栏 chip 实测）：iOS 26+ 上 `UIButton.Configuration.plain()` 按钮设 `isSelected = true` 时系统会以 tint 色画一层**直角矩形**底（`config.background = .clear()` 盖不住选中态）——表面看像"圆角没生效"，实际是按钮层叠加物（藏掉按钮后 chip 自身胶囊完好，像素级可证）。凡用容器表达选中态的配置按钮，改用 `accessibilityTraits .selected`（XCUIElement.isSelected 与 VoiceOver 均读该 trait）。
- **UIColor(named:) 解析环境**：脱离 `installDarkBase` 直接构造的视图（尤其测试）在 light trait 下解析 light 值——测试断言色值一律 `resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))` 显式钉死（TypographyTests 已按此更新）。
- **桥接语义漂移**：legacy 访问器指向 v2 语义后，视觉近似但不等于 v1；凡断言旧色值的测试改期望值（不改强度），凡快照基线一律 V4 重录，不做中间态对拍。
- **list section 的 swipe 必须走配置级 provider**（2026-10-02 批次1 实测，iOS 27）：`UICollectionViewDelegate.collectionView(_:trailingSwipeActionsConfigurationForRowAt:)` 对**混合布局**（compositional section provider 内返回的 `NSCollectionLayoutSection.list`）里的 list section **静默不生效**——selector 不触发、滑动无反应、无任何报错或日志；把闭包挂到 `UICollectionLayoutListConfiguration.trailingSwipeActionsConfigurationProvider` 即正常。另注意 `performsFirstActionWithFullSwipe` 默认 true：快速全幅滑动直接执行首个动作（native 删除习惯），测试探针须用慢速短拖（press+drag）只露出不执行。
- **sheet 系统层不跟随 dark override（iOS 26+ 实测，2026-10-02 Detail v2 轮）**：① **medium detent 卡片化**——含 `.medium()` 的 pageSheet 在 iOS 26+ 渲染为**内缩系统卡片**（左右 ~9pt 边距、圆角 ~48、自带浅色 plate），plate 层无视 `overrideUserInterfaceStyle`（view 级与 VC 级都试过），在强制 dark 的 app 里呈现为压在内容上的白色圆角卡（Detail v2 首版实测白卡 y415-510）；规避 = 单一近全高自定义 detent（fraction ~0.93，大高度 sheet 保持全宽无 plate）。② **`UIVisualEffectView` 的 blur 材质同样无视 override**——强制 dark 下 systemThinMaterial 渲染为白色磨砂；V4 trait 真翻转前，需要"磨砂"语义的面板一律用 surface 渐变纱替代（§5 episode detail modal 的 blur50/blur25 落地为此降级），V4 后再回归真 blur。

## 10. 任务清单

> **2026-10-01 进度（V0/V1 完成，V2 开局）**：V0 审计与本文档成文；00 已插 MV 里程碑。V1 落地：64 个 v2 colorset（16 个 v1 colorset 退役）、`Theme.swift` 重写（语义层 + `AnycastColor` 刻度 + legacy 桥接段——**桥接段访问器随 V3 逐屏删除，勿新增引用**）、`TypographyV2` 15 档系统字阶、`Metrics.swift`（Spacing/Radius/Motion）、`PlayerProgressBar` 改静态 player token（CGColor 冻结地雷首例，见 §9a）。V2 组件落地：`BottomTabBarView` 胶囊 Tab（3 chip + 72pt 玻璃搜索钮 + 渐变 scrim，+3 测试）、`CategoryStripView` 分类条（含 `CategoryStripModel` 纯逻辑去重/排序，+3 测试，**尚未接入 Inbox 屏**）。测试：AnycastAppTests **304/304**（色值断言更新为 dark 显式解析 + 新增 v2 双外观/token/组件测试）、AnycastTests L0–L2 **106/106** 零回归、AnycastUITests 全过（快照套件按门禁跳过，V4 重录）。**注意：xcodegen 为静态文件清单，新增 Swift 文件后必须 `xcodegen generate` 再构建。** 待续：MainTabBarController 胶囊化翻转（等 Library 屏就绪后一次切换）、CategoryStrip 接线、Library 屏、Welcome/SignUp、V3 五批次、V4 重基线。**V0.1 复核修订（同日，逐项经 Figma/代码实测）**：① §1/§3/§4 死链 `637:9227`/`744:7569` 改指 Index 克隆帧 `1202:23067`/`1202:23125`；② §2.1 退役数 19→16、`ErrorColor`→`Error`、playerGradient 行改为 Flutter/Figma 双源注记（实现以 Flutter 为准）；③ 新增 §2.2a 语义 colorset 清单（16 Any+Dark + AccentColor，47+17=64）；④ §2.3 Motion 曲线更正为 easeOutCubic `(0.215,0.61,0.355,1)`；⑤ 展示字体未定稿提入 §0 决策表；⑥ §6 注明 show-detail loading/history/clear-all 仅有 cream 帧；⑦ §7 登记 profile/inbox-empty 默认不做；⑧ K 表定位到 05 §11；⑨ `.env` 位置更正为 `native/.env`；⑩ §2.5 inbox 落地为 tray.fill。**V0.2 复审修订（同日，Figma/代码/落盘三方复核）**：⑪ `OnPrimary`/`InversePrimary` 双外观 Any/Dark 原落盘相对 Flutter 源颠倒（三元 `isDark ? A : B` 误读为 light=A/dark=B），colorset 已按 `anycast_theme.dart` 对齐（`OnPrimary`=sand1/sand12、`InversePrimary`=goldDark9/gold9；改前无消费者与测试断言，零风险），§2.2/§2.2a 同步更正；⑫ V4 快照基线数 19→20（S1–S19b，共 80 张）；⑬ §5 sheet 宽 440→416；⑭ 新增 §6a cream→sand 换算表（草案，V3 批次 2 首屏前终裁）；⑮ 补充实测：cream welcome/login 主 CTA 为 `1B1A18→#000` 深色渐变，`524538→2E261F` 棕渐变实测见于 paywall 价位卡（`1241:8673`/`1241:8676`）。**V0.3 复审修订（同日，文档↔代码↔Figma 三方独立复核：token 值/colorset 清单/nodeId/组件规格/测试数约 60 项抽证零错误）**：⑯ §1/§5 登记 Index 页 Buttons Inventory（`1371:15651`/`1376:15839`，Liquid Glass 按钮语言：Primary `glass.tint(sand12)`/Secondary 透明 `glass.regular`）与探针帧 `1202:25678`，V1/V3 按钮族任务改以此为规格锚点；⑰ cream 帧位置写明（全部在 Index 页 References 区段下方，§1/§6 表头），§1 cream 按钮渐变描述按 ⑮ 回改（原文未同步 ⑮ 的内部不一致）；⑱ §2.2a 补未落盘语义注记（ColorScheme 其余 10 项为已有 token 别名，按需增补，非遗漏）；⑲ §5 动效落地决策顺延至 V3 批次 1 前拍板（原记 "V1 定" 已到期未决）；⑳ V4 补快照增减规则（S3/S8 随 IA 退役删基线，Library/Welcome/SignUp 补基线，清单随 05 §6 更新）。**V0.4 复审修订（同日，Figma 侧全量独立复核：页面地图/两处删除原件 404 反证/Index 14 引用/cream 帧取值/§3§5 组件规格数值约 70 项抽证零错误）**：㉑ §7 补登记主画板 `125:7253` "login android"（iOS 迁移默认不做）；㉒ §1 两处 cream 帧位置更正为「References section 内、14 引用之后」（Buttons Inventory/探针帧/profile/inbox-empty 才在 section 外）；㉓ §6 裁定规则 ① cream token 组补链接/星号辅助绿 `#33A852`（cream login `1241:8585` 实测）；㉔ §0 补 Instrument Serif 实证 nodeId（mini player 卡片态标题 `149:3499`）、§2.5 补 cream 帧 Material Icons 注记。**V0.5 Figma 全量复核修订（同日，自 Figma 侧独立复核：10 页面全集、Index 14 引用+10 cream 帧逐个、§3/§5 组件规格与 §6a 实测值逐值、Buttons Inventory 标注逐字、64 colorset 落盘对账）**：㉕ §3.2 category strip 选中态更正为 `goldAlpha7` 底+`sandAlpha4` 描边+`sand1` 文字（变体 `599:30269`/克隆帧 `1202:23067` 实测；`CategoryStripView.swift:118` 落盘值相悖，修正任务已入 V2 清单——此前"§3§5 约 70 项抽证零错误"结论对此条失效）；㉖ §6 补 cream audio/speed 帧"黑 scrim+奶油卡/sheet"形态注记、speed sheet sand 源件（component 页 `413:5099`/`413:5050`+`1429:10434`）、裁定规则 ① 补散值 `#C8AE80`/`#A8A294`；㉗ §6a 补 loading 帧四行（Subscribed pill/spinner 轨弧/弱化文字/Young Serif 标题）与取值来源注记；㉘ §1 补主画板/component 页未登记帧清单（queue `684:10880`、queue episode card `688:11411`、sort by `596:30234` 等）与 Styles `76:2988` 非规格注记、component 页 sheet 族源件展开；㉙ §0 补 Instrument Serif header 实证 `1202:23074`、§5 inbox 卡属性名对齐 Figma 实名、§3.6 mini player 克隆帧实宽 408 注记、§2.5 补 `apple` 图标。**V0.6 Figma 独立复审（同日，自 Figma 侧全量重审：10 页面全集、两删除原件反证缺位、Index 14 引用 + 10 cream 帧 nodeId 逐一落位、§2.1 约 25 值（含 alpha 全档抽样）、§3.1/§3.2/§3.6 组件规格全数值、§5 组件规格逐值、§6a 全行、Buttons Inventory 标注逐字、本地 64 colorset 计数；既有内容零错误，本轮仅完备性/歧义修正）**：㉚ §1 未登记帧清单补缺项（player queue header `1493:15870`、detail-backup `439:7947`、player button 按压态组件集 `365:5008`/`638:9549`/`1496:9535` 等，并注明组件库源件不逐一登记）；㉛ §1 Index 补 cream welcome 克隆 `1241:8561` 与 sign up 引用 `1202:23523` 同格位叠放、后者被遮盖注记（取用按 nodeId）；㉜ §3.1 搜索圆钮玻璃规格注明出处为 Inbox 变体 `240:7217`（queue/library 变体内为旧白底圆钮，以前者为准）；㉝ §2.5 补 forward_30（mini player 胶囊态前进键实测）→ goforward.30。**V0.7 Figma 独立复审（2026-10-02，自 Figma 侧全量对账：10 页面地图、Index 14 引用与 10 cream 帧逐个落位（含 580,2732 叠放与黑 scrim 形态）、§3.1 Buttom Tab 与玻璃圆钮子层逐值、§3.2 变体逐值、§5 规格抽证、§6a history 帧逐行、两处 Instrument Serif 实证（`149:3499` 16/24、`1202:23074` 24/36）与 Cormorant/Young Serif 标本——既有内容零错误、文中登记的全部 nodeId 均实存；唯一缺陷是 §1 未登记清单对主画板散件不完备，本轮补齐）**：㉞ §1 补 4 个实施相关未登记件：第二 library block 组件集 `1575:9948`（与 `628:6406` 并存，Library 屏实施前裁定，§10 V3 批次 2 已加提示）、cover 组件集 `625:31595`（4 变体装饰封面）、状态 chip 行 `636:9047`、option 行变体 `1545:10128`（含 drawer button 源件 `1546:10217`）；㉟ §1 补「忽略/不逐一登记」兜底注记（M3 套件残件 `1025:8865`/`1029:11019`/`1127:9048`/`1127:10504`、Iconify 图标实例 5 件、小占位/注记帧、已登记组件松散实例与已映射屏子组件）——V0.6 的「补全」结论对散件类不成立，本轮回正；㊱ §1 工具坑补注：超大页面 depth 1 拉取亦受 MCP 结果预算截断，NODES 尾部需按 nodeId 单独核验。

> **2026-10-02 进度（V2 外壳与 IA 完成）**：MainTabBarController 胶囊化翻转落地——`UITabBarController` 退役为自管子 VC 容器（`BottomTabBarView` 3 chip + 72pt 玻璃搜索圆钮，三子 VC 常驻预热、纯可见性切换），IA = **Inbox / queue（PlaylistsPageViewController 换 v2 header，archive 带+队列卡重构留批次2）/ library（新 `LibraryViewController`：v2 header + membership 占位块（goldAlpha2 底+sandAlpha4 描边 r16，点击动作留 V3 批次5 接 paywall）+ 内嵌 SubscriptionsPageViewController 全出血，状态行 "{n} shows"）**；**Discover 从 tab 退役**（VC 类保留编译待批次4处置），发现入口 = 搜索圆钮 → 新 `SearchEntryViewController` 过渡入口 sheet（"search | ask anything" 输入 → 既有 SearchPage 推屏；v2 搜索屏/browse = 批次4），两处空态 Explore 同改搜索入口；`PodcastsTabContainer`/`PodcastsTabStrip`/`PagingTabsContainer` 删除。v2 header 组件 `HeaderView`（624:30831：title 48pt displayLarge 大写 + status 12pt sand9 caption + 右侧 48×48 齿轮 slot；Figma slot 内为 3D avatar 占位，落地映射为设置入口）替换三 tab 的 v1 AppBar（含 GradientTextLabel 用法），内嵌搜索框随 AppBar 退役；**组件留有 trailing action 位（Figma label="clear" 属性在两实例帧内均无可见渲染），clear 动作接线随批次1 Inbox 裁定**。Inbox 接线：header 状态行（"updated {rel} - {n} unlistened"，`headerStatusText` 纯函数）+ `CategoryStripView` 接入（数据源 `subscription.categories`，`InboxCategoryFilter` 纯逻辑：feed→category 集合 + 大小写不敏感过滤，选中项随源消失回落 all）+ "see all podcast" 提示卡片（599:30354，sandAlpha2 r16）；**header/strip/提示卡为固定区（Figma 位于滚动流内），随内容滚动的形态随批次1 Inbox 三态改造**。CategoryStripView 选中态已按 §3.2 修正（goldAlpha7 底 + sandAlpha4 1px 描边 + sand1 文字、未选中 sandAlpha2 底，chip 高 36→44、字 13 medium→16 semibold），+色值断言（dark 显式解析，§9a 纪律）。mini player：`PlayerBarView` 新增 `.capsule` 样式（83:2562：surface 80% 底 + sandAlpha4 1px 描边 + 阴影 0 8 10 /5% + 圆形 36pt 封面 + 单行居中标题、无时间行、进度底改 sandAlpha4），悬浮于 pill 上方 8pt、页边距 16 自适应（Figma 408 宽语义）；**自定义 pill bar 下无 UITabBarController 可挂 UITabAccessory——§3.6 "iOS 26 accessory 保留"被 V2 翻转决策取代，两 OS 统一为悬浮胶囊**；三态中的列表尾通栏条（83:2563）/卡片态（149:3478）无当前消费屏，随批次2 queue 屏落地。Welcome 屏 + SignUp UI 落地（`WelcomeViewController` 131:2742 / `SignUpViewController` 131:2540 + `AuthFieldView` 输入件 48pt/surfaceContainer 底/radius12）：mail → 既有 EmailLoginViewController，Apple/注册提交按 §8 留 TODO（弹提示，不开通能力），**入口接线随批次5 auth 重构**（当前 401 仍走 v1 LoginViewController，勿混用）；展示字未定稿 → 系统字占位（§0 决策仍开放）。fly-in endpoint 改读 `pillButtons` 中位 chip（queue）。UITests 全量改 pill 标识符（tab-0/1/2/tab-search）：ShellNavigation（+搜索圆钮推屏断言）、SmokeFlows（搜索流改 tab-search→search-entry-field；Subscriptions 流改 library tab）、QACrawl（currentTab 存 chip 标识符，discover checkpoint→library，subscriptions checkpoint→tab-2，搜索→tab-search）；ShellWiringTests 移除 inner-strip 用例、UIFixRegressionTests 移除 Discover 指示器用例（随 IA 退役）。新增 `V2ShellTests`（header 渲染/折叠、分类投影、Inbox/Library 状态行、胶囊 chrome、Welcome/SignUp 冒烟——live-shell 门控跳过模式）。**实施期修正（同日）**：① `HeaderView` 初版 titleColumn 仅 centerY 对齐、高度歧义被解析为 670pt 把列表挤成 0 高——改为 titleColumn 上下贯穿的决定性垂直链（header 高度 = title 行 54 + status caption）；② 自管子 VC 切换从 `isHidden` 改为**挂载/卸载**（未选中子 VC 无 window，对齐 UITabBarController 语义，避免 walk 型 QA 扫到未布局的隐藏列表——LayoutSanityTests 因此过）；pin 约束在挂载时重激活（UIKit 卸载时自动失效），并在 shell 已上窗后手动驱动 begin/endAppearanceTransition（Subscriptions/playlist 列表的 viewWillAppear 静默刷新依赖它）；③ BottomTabBarView 选中 chip 补 `isSelected`（a11y + UITest 断言）。快照采集套件适配：S3 走 library tab、原 S8 Discover 采集位改采 Library 屏（`Library-library`，正式清单随 05 §6 在 V4 定稿）。**测试收官**：AnycastAppTests **310/310**（+V2ShellTests 6、+CategoryStrip 色值断言；ShellWiring 移除 inner-strip 用例、UIFix 移除 Discover 指示器用例随 IA 退役）、AnycastTests L0–L2 **106/106** 零回归、AnycastUITests 全过（ShellNavigation/SmokeFlows，iOS 27 主模拟器）；实施期测试修正两处：UIFix Inbox expand 用例改先 scrollToItem（v2 固定 chrome 后目标卡不在首屏）、player spaceEvenly 用例的底块测量改量真实最后可见块（**既有测量缺陷**：K6 retry 行可见时 transport 不是栈底块，gap4 被 retry 行高撑大——与本次改动无关，由跑序触发），Welcome 冒烟用例抓出 viewDidLoad 约束无共同祖先的崩溃（CTA/authRow 未 addSubview 先激活约束，已修）。iOS 27 三 tab 截图视觉核验通过（queue 胶囊 mini player、library membership 卡/all shows/节目卡均正常渲染）。

> **2026-10-02 视觉审计修复轮（V2 收尾；crawl 截图/AX/Figma 参考帧等审计产物已于验收后清理）**：crawl 17 状态 + 29 张 Figma 参考帧 + 4 批 subagent 审计（axdump 几何 + PIL 像素 + 源码三方交叉）后的修复：① **Library 塌陷（P1）**——membership 占位卡无高度约束被拉成 685pt、内嵌 Subscriptions 列表 0 高全不可见、"all shows" 行埋进 tab 胶囊；改 textColumn 上下贯穿决定高度链。② **两处 CGColor 冻结（P1，§9a 地雷首两案）**——`PlayerPageContainer` 渐变尾档在 Task 上下文解析成 Light Sand2 #F9F9F8（三屏文字白底白字批量消失）；`ChannelHeaderView`/`blendOverBackground` 在 light traits 下混合出头带浅色（标题/按钮不可读）；均改 `resolvedColor(with: dark)` 显式解析（player/Channel 按设计固定暖深），Channel 补 traitCollectionDidChange 重取。③ **tab 条**——pill/圆钮改距 bottom safe-area 12pt（原钉物理底 -12 压 home indicator；克隆帧实测 pill 底 93.5% 屏高），`ChromeMetrics` 全组改 safeBottom 参数化（barOverlayHeight/restingClearance/capsuleClearance，safeBottom=0 复现旧值），chip 由"等宽吃满+4pt 死间隙"改按 300/363 比例 + 首尾钉边中 chip 居中（space-between 语义，402 屏 ~79pt chip/~21pt 间隙；**实施期修正**：首版宽度约束把三 chip 总宽当单 chip 造成 234pt 互叠，被 UITest 抓出后改 `chipWidthRatio/3`）；scrim 带点击穿透（hitTest 仅 pill/圆钮拦截，内容在渐隐带下仍可点）；**mini player 胶囊整条悬浮于 scrim 带上方**（restingClearance 改锚 barOverlayHeight+8——原锚 pillTop 导致胶囊下 1/3 沉在 scrim 模糊后面，即用户指出的 tab 条"覆盖"问题，也是 UITest mini-player 点击失败的根因之一）。④ **HeaderView**——齿轮 slot 24→48（`Spacing.xxl`，原误用 `pageHeader`=24 且低于 44pt 命中目标）、左右边距 chip14→pageH16（与页网格统一，原 14/16/24 三套并存）。⑤ **EpisodeCardCell/Inbox**——卡片左右 inset 24→16、radius 20→`Radius.md`16、封面 16→`Radius.artwork`18、内 padding/gap 12→16（§5 规格）、cardRowHeight 104→112。⑥ Settings 列表卡与 country 列表卡改 `Theme.surfaceContainer`（原系统 insetGrouped 灰阶非 token）；import RSS 输入框去系统黑底改 surfaceContainer+outlineVariant。⑦ Channel 页 mini player standalone→capsule（16pt 边距悬浮）。⑧ 字幕面板 32% 黑改 `Theme.transcriptSurface` token。**测试适配（不改强度）**：v2 布局变化暴露两处 UITest 对旧几何的隐式依赖——ColdStart 的列表 swipeDown 按压点落在胶囊上（胶囊 any-direction pan 开播放器的 Dart quirk，03 §2.9）→ 改上半屏坐标拖拽；ShellNavigation 搜索 sheet 变第一响应者后被顶到 large 档、单次下拖只收回 medium → 改两段式拖拽关闭，mini-player 步骤加一次重试。**文档勘误同步**：§3.1 搜索钮"居中悬浮"改右置（节点树实测）、新增 bar 底部摆位与 chip 分布实测补记、§5 player content padding 组件 36 vs 屏帧 24 不一致注记（暂以帧为准，★批次3 终裁）。**测试**：AnycastUITests 11/11、AnycastAppTests 310/310、AnycastTests 106/106 全绿。**本轮未动**：mini player 与 pill 间距语义（现 8pt vs 克隆帧折算 ~40pt，待设计复核记入批次2）、搜索玻璃圆钮视觉重量（Liquid Glass 语言，§5 Buttons Inventory 裁定）、player/queue/detail 等 v1 结构项（各批次范围）。

> **2026-10-02 修复补丁轮（用户视觉反馈驱动；Figma 组件 243:7288/240:7235/240:7217 逐值实测对拍）**：用户报告两类问题——Library 顶部排布错乱、tab 条"层层嵌套/大小不匹配/过高空白多"。修复：① **tab pill 描边移除**——Figma 胶囊为 fill(白 80%)+阴影、无描边；原 1pt `sandAlpha4` 描边与激活 chip 0.5pt 描边叠出嵌套观感（嵌套报告主因）；② **tab 图标钉 24pt**（`preferredSymbolConfigurationForImage`，原未设、SF Symbol 落默认 ~17pt）、**label 12 Regular + TITLE 大写**（原 semibold + 原样大小写）；③ 搜索圆钮图标 32pt 复核无误（240:7217 实测 MS Rounded 32），不动；④ **scrim 收敛**：`scrimAbovePill` 36→24（组件根 padding 24 实测）、模糊 `systemChromeMaterial`→`systemThinMaterial`（Figma backdrop blur 10）；⑤ **Library 对齐**：内嵌 Subscriptions 卡片 inset 24→16、all shows 行 6→16（三套边距 16/6/24 并存修正，与 Inbox 审计轮同款改法）。**登记未决（新）**：⑥ **内容避让语义**——`additionalSafeAreaInsets.bottom` 现锚全 scrim 带（resting ~150 / playing ~216），列表滚到底在 pill 上方留大片空白（"空白太多"另一半成因）；Figma scrim 语义为内容滚动至渐隐带之下（克隆帧卡片在 scrim 后连续滚动）。裁定项：改锚 pill 顶（内容流入 scrim 下）vs 维持全避让，涉及全部列表屏滚动到底手感与 UITest 几何，**批次1 Inbox 改造前拍板**；⑦ **pill 深色形态**（本轮已按设计帧实测裁定，见下条补丁轮②——保留原登记背景）；⑧ **PodcastCardCell v1 皮肤**（legacy 色/圆角 20/v1 字体）随 Library 嵌入与新 chrome 直接混排，其 reskin（原 V1 清单未勾项）建议提前并入批次2 Library 深化。

> **2026-10-02 修复补丁轮 2（用户复检驱动："矩形套矩形套胶囊套胶囊"）**：补丁轮 1 的视觉验证有缺陷（对视觉模型提了引导性问题，"通过"结论不可信），本轮改用像素级测量复检，抓出三个真实根因并修复：① **pill 圆角自 V2 初版起就缺失**——`BottomTabBarView` 的 pill 从未设 `cornerRadius`，渲染为 72pt 硬边矩形（用户"生硬矩形"主因）；补 `pillHeight/2` + continuous，像素验证左缘曲率（dy=0 缩进 49px→中部回收 48px=16pt 引边）。② pill 深色形态（当时按用户深色截图裁定为 surfaceContainerHigh@80%——**轮 3 已勘误反转，见下**）。③ **磨砂矩形整条移除**——`UIVisualEffectView` 铺满 scrim 带形成全宽硬边矩形（用户"第二个生硬矩形"）；先试祖先 gradient mask 渐隐 → **实测 mask 令 blur 整体静默失效**（§9a 新增地雷），且去掉后内容从 8% 透明度的长渐变下直透出来；终案：去掉 blur 视图，`GradientFadeView` locations 改 `[0, 0.845]`（surface 全量在 pill 底+24 处达成，对齐 Figma scrim 根的 24/pill/24 结构），内容在 pill 区被 ~20-60% tint 压暗，无任何硬边。搜索圆钮 72×72 维持（240:7217 规格，=pill 等高）。**教训登记**：视觉验证一律中性提问+像素测量；二手截图（带窗口白边/缩放）不可作为取值依据，**取值一律用 download_figma_images 原帧**。

> **2026-10-02 修复补丁轮 3（用户复检驱动：选中 chip"矩形高亮框"、mini player 与 tab 栏间距过大）**：**⑦ 反转（重要勘误）**——补丁轮 2 从用户带白边窗口截图量得的"深色 pill=#252523"是被窗口背景污染的误读；本轮从 Figma 下载原帧渲染（76:2614 深色 inbox，2x PNG）实测：**pill 深色下仍为白 80%（实测 219），mini player 卡同为亮面（lum 195-221），间距 = 卡底距 pill 顶 14pt**。结论：**底栏 chrome 族 = 静态 light 表面**（同 §9a player 族纪律），全族落地：pill 改 `UIColor(white:1,α:.8)` 静态、chip 一族 token 全部钉 light 变体（goldAlpha2 填充/sandAlpha4 发丝/goldAlpha9·sandAlpha10 墨色，`resolvedColor(with: light)` 冻结）、搜索圆钮图标改 light 墨、**mini player 胶囊按 §3.6 字面规格 `rgba(255,255,255,.8)` 改白 80% + 内容墨色/进度底/占位全钉 light 变体**（原 `Theme.surface@80%` 深色下近黑不可见）、`ChromeMetrics.capsuleGap` 8→14（锚 pill 顶，非 scrim 顶；此前"克隆帧折算 ~40pt"注记作废，以 76:2614 实测为准）。**"矩形高亮框"真凶（§9a 新地雷）**：chip 几何一直是胶囊（不透明填充注入实验+测试进程隔离渲染双重证实：藏掉按钮后暖色轮廓即对称胶囊），矩形来自配置按钮 `isSelected = true` 时系统注入的 tint 色直角底（`config.background = .clear()` 盖不住选中态）；已改 `accessibilityTraits .selected`（XCUIElement.isSelected 与 VoiceOver 语义不变），设备像素验证暖色轮廓恢复对称胶囊（dy=2 宽 129→中部 235→dy=170 宽 163）。新增 `TabChipRenderingTests`（不透明填充注入的胶囊几何回归 + 按钮无底 + pill 白 80 静态断言）。

> **2026-10-02 原生优先落地轮（§7a-C1 Inbox 先行；基线先行纪律）**：基线注记已同步——03 §2.3/§2.11/§3.1、05 §6.1 S2（展开态基线标退役）/§6.3 卡片清单均加 v2 裁定注记。实现：**Inbox 卡操作全面原生化**——整卡点按改开 Detail sheet（原为展开操作条）、**长按 context menu**（Play / Add to playlist / Remove from inbox，三动作与 `InboxActionPlanner` 执行路径逐字不变）；`EpisodeCardCell` 新增 `menuActions` 通道，把同一载荷镜像为标题上的 VoiceOver custom actions（AX 对等替代操作条按钮，rotor 可达）；飞入动画起点在无操作条卡上取卡片中心；`CardExpandCoordinator`/`CardExpandAnimator`/操作条本体保留（Channel/Search/Playlist/History 仍在用，随各自批次处置）。**swipe actions 经查暂不可行**：Inbox 列表是自定义 compositional layout，`UISwipeActionsConfiguration` 需 list configuration——留批次1 Inbox 重设计换布局时再评估（§7a-C1 的 swipe 半边挂批次1）。测试：新增 `UIFixRegressionTests.inboxNativeCardInteractions`（菜单三项断言 + AX 镜像 + 卡点开 Detail）；原 `inboxExpandReliability` 操作条高度回归**挪至 playlist 列表**（同 cell+animator，strip 风险面仍在保留操作条的屏）；SmokeFlows 飞入用例改长按→菜单触发（实跑通过）。**顺带修复既有测试缺陷**：case 5 的 `defer { list.dismiss }` 在 list 之上叠有 Detail 时只撕链顶、list 自身残留并静默吞掉后续测试的 present（新用例首次暴露，诊断输出证实 top 恒为 PlaylistEpisodeListViewController）——两处 defer 改从 presenting 侧 `presenter?.dismiss` 撕整条链。**测试**：AnycastAppTests **314/314**、AnycastTests L0–L2 **106/106**、AnycastUITests 10 过 + 5 门控跳过（QACrawl 工具族 + playbackFailure seed 门控，fly-in 长按流实跑通过）。

> **2026-10-02 Detail modal v2 轮（批次1 后半场之一；基线先行）**：03 §1.3/§3.4 与 05 §6.1 S5 裁定注记先行。**实现**（规范帧 `1784:7538` 开态 + `1593:10342` expanded，组件级取数入档）：`DetailViewController` 整屏重做——**单一近全高自定义 detent 0.93**（复刻 v1 的 fraction resolver 配方；开态 modal 顶 y62 ≈ 0.93）、**去掉 `.medium`**（iOS 26+ medium detent 会渲染成内缩系统卡片——白 plate 压内容的实测地雷，见 §9a 新增两条）、grabber 36×5 sandAlpha4（把手区 ≤32pt 点击关闭的 A2 适配保留）；内容 = 全宽 hero artwork（≈屏高一半，底部黑渐隐 140pt）+ 渐变磨砂面板压 hero 尾 24pt（surface 渐变纱 0→0.55→1，**blur50 降级为渐变纱**：blur 材质无视 dark override，§9a；V4 trait 翻转后回归真 blur）——32pt semibold 标题（帧内白字压暗 hero，无真 blur 下改 onSurface 保可读，偏差登记）+ 元数据行 14 大写（日期 + 时长 MIN，新增 `Episode.durationSeconds`）+ 状态 tag pill 行（sandAlpha4/h22/12 TITLE；Inbox 侧传入 ["inbox"] + 队列含该集时加 "queued"）+ 节目名 16（点击仍在其上叠 Channel）+ 描述 14/28；**底部渐变播放条 = 金 pill "ADD TO QUEUE"（gold9 底 sand1 字，按 accessibilityLabel 从注入 actions 匹配）+ 深色 play 圆钮（sand12 底）——Remove 从 Detail 退役**（列表 swipe/长按菜单承担，§7a-C1 语义闭环）；share 改 hero 右上 44×44 浮圆钮（sand1 + 阴影，保 "Share episode" AX 与 shortlink→系统分享链路）；动作触发后自动 dismiss（03 §10.1 quirk）与频道叠加行为逐字保留。**顺带修复**：`HTMLContentRenderer.postProcess` 剥离 WebKit 导入盖上的 `.backgroundColor`（浅色底块 artifact）。**测试**：UIFix playlistDetailPlayButtonIcon（Play 图标断言）与 SmokeFlows testCardTapOpensDetailSheet（改随卡定位后新增 v2 截图附件）实跑通过；LayoutSanity `inboxCardDescriptions` 补"仅统计已挂窗 label"过滤（私有 shell 里未挂载的预取 cell 报零高属 harness 误报，沿同文件既有纪律）。**过程教训（§9a 登记）**：白块排查五轮——HTML 背景→渐变 trait→blur 材质→染色二分→detent 卡片化，最终像素+VLM+二分法定位为系统 medium 卡 plate；视觉模型对原帧/截图的中性读数两轮均被数据证实可靠（含 EP456 中文样张）。**余量**：expanded 态钉顶 scroll header（48 mini artwork + 标题 + share 渐显）、元数据 size 值（无数据源）、真 blur 回归（V4）。

> **2026-10-02 决策⑥拍板 + 批次1 Inbox 半场轮（用户拍板驱动；基线先行）**：**① 决策⑥拍板（用户裁定）**：内容避让语义 = **避让到胶囊顶（维持锚点语义）+ 退役 64pt 双重避让**——`additionalSafeAreaInsets` 锚点不变（空队列 pill 顶+14 / 播放中胶囊顶+14，静止内容永不被胶囊遮挡，系统浮层 accessory idiom；否决项：锚 pill 顶的 Figma 字面读法——末卡静止时会被白 80% 胶囊遮住 ~58pt）。**拍板前新发现**：Inbox/Subscriptions 的 64pt 底部 section inset 是 v1 Dart 手动避让残留（03 §2.3"底部 padding 64 避开 mini player"），与外壳避让双重计算——playing 态静止点 ≈ 216+64 ≈ 280pt，pill 顶上方 ~146pt 纯空白，即用户"空白太多"反馈的主因；两处 bottom inset 归零（PlaylistEpisodeList 为推屏页不在本轮范围），03 §2.3/§2.4 + §0 决策表已注记。**② 批次1 Inbox 半场落地**（03 §2.3 批次1 裁定注记先行）：**v2 inbox 卡**（组件 744:9107 复测 + 76:2614 原帧像素核实）= 新 `InboxEpisodeCardCell`——文字主导：标题 17 onSurface·TITLE 大写（3 行截断，AX 读原始大小写）+ 描述 14 onSurfaceVariant（3 行）+ 60pt 状态行（36 圆节目封面 + 节目名 12 TITLE + 日期 12 间距 12 + goldAlpha3/goldAlpha9 计数 pill + `more` 60×60）；卡 = surface 底 + **sandAlpha3 发丝**（组件实测 rgba(32,16,0,.06)，非 outlineVariant 的 sandAlpha4 档）+ 阴影 0/1/20/4% + **radius 34**（§5 原记 16 系误读，§5 已更正）；12pt 列间距内衬在 cell 上下各 6pt（list section 无行距）。**滚动流 chrome**：header/分类条/提示卡改列表 cell（`ChromeHostingCell` 寄宿共享视图、自算高），收集视图全出血顶（状态栏下滚动、safe-area inset 定位）；列 gap 12 = chrome section 底 inset + 卡内衬。**swipe + more 落地**（§7a-C1 批次1 挂账清偿）：卡 section 改 `NSCollectionLayoutSection.list`，**trailing swipe = Remove（destructive，全幅快滑直删）**；`more` 按钮 = UIMenu 下拉（与长按 context menu 同三动作载荷）；**swipe 走配置级 provider**——委托 selector 对混合布局里的 list section 静默失效（§9a 新地雷，附 `performsFirstActionWithFullSwipe` 测试探针注记）。列表尾 history 入口 pill（1787:7899 尾件，接既有 HistoryDialog，v2 History 屏=批次2）；空态时滚动列整体塌缩（ImportBlock 自带头部）；飞入动画起点取卡中心。**计数 badge 语义未证实**（帧内一律 "99+"、属性名 episode count）——暂映射单集时长大写文本，★待设计复核。**③ 视觉核验**：iOS 27 截图像素级核验（ASCII 结构 + 圆角曲率实测 ≈34、16pt 边距、状态行封面/pill/more 齐备；当前 app 强制 dark 属 V4 前预期）。**④ 测试**：UIFix inboxNativeCardInteractions 扩（section 3 定位 + more 菜单断言 + swipe 委托断言）、LayoutSanity 新增 `inboxV2CardLayout` 确定性布局测试、SmokeFlows 改 `inbox-card-more` 定位 + 新增 `testInboxSwipeRevealsRemove`（慢速短拖只露出不执行，避免消耗种子数据；首版用 `.fast` 全幅滑误触真删并消耗了一条种子，已重灌 db_smoke）、QACrawl 三处同步（gated）。**测试收官：AnycastAppTests 315/315、AnycastTests 106/106、AnycastUITests 11 过 + 5 门控跳过。⑤ 未动（批次1 余量）**：Detail modal v2 三态（drag=false 关 `1787:8175`/开 `1787:7899` @y62 + expanded `1634:8632`：440×600 artwork 顶置 + radius48 + grabber 36×5 + 底部 progress blur 124 + blur25 播放条，取数已完成）、ShowDetail（365:4610 + loading 骨架 1243:8631）、header trailing clear 接线（帧内无可见渲染，仍悬置）、download/wand_shine 图标位与 `shows background` 装饰板（属性语义未证实，未采用）。

### V1 · 设计系统层

- [x] Theme.swift + Assets.xcassets 全量替换（§2.1/§2.2；Any+Dark 双外观；v1 colorset 退役 + legacy 桥接段）【2026-10-01】
- [ ] 移除 `installDarkBase` 的 dark 强制；root/状态栏/键盘随 trait；player 屏固定暖深【留在 V4 翻转，见 §9a】
- [x] Typography v2 字阶（§2.4，`TypographyV2`）；展示字体待 §6 裁定（Figma 出现第三种衬线 Instrument Serif，wordmark 字体未定稿）【2026-10-01】
- [x] Spacing/Radius/Motion 三刻度（§2.3，`Metrics.swift`）【2026-10-01】
- [ ] GlassContainerView v2：卡片语言=surface+outlineVariant 描边+radius+阴影；Liquid Glass 收敛悬浮件（按钮族规格锚点=Index Buttons Inventory，§5）【随 V3 逐屏】
- [ ] 组件库 reskin：EpisodeCardCell/PodcastCardCell/按钮族（以 §5 Buttons Inventory 为准）/输入框/segment control/Snackbar toast【随 V3 逐屏】
- [ ] AppIcons v2 映射补全（§2.5；已用安全集：queue=play.rectangle.on.rectangle、library=books.vertical.fill——collections_bookmark 的 iOS 18 可用性待 iOS 18 模拟器核实后可换）
- [ ] 素材：app icon/logo/paywall 介绍图/Google G（download_figma_images，补 M3 T11 遗留）【挪至 V3 批次 5 按 slot 导出；Figma thumbnail 页无 app icon，仅有 440×260 网页缩略图组件】

### V2 · 外壳与 IA

- [x] `BottomTabBarView` 胶囊组件（3 chip + 72pt 玻璃搜索圆钮 + 渐变 scrim；retap 语义；3 项测试）【2026-10-01】
- [x] MainTabBarController 胶囊化翻转（UITabBarController→自管子 VC + BottomTabBarView；三子 VC 常驻预热、纯可见性切换；fly-in endpoint 改读 pillButtons；UITests 改用 accessibilityIdentifier tab-0/1/2/tab-search；**§3.6 的 iOS 26 UITabAccessory 路径随翻转消失，两 OS 统一悬浮胶囊**）【2026-10-02】
- [x] mini player 胶囊三态（`PlayerBarView.capsule` = 状态 c 落地：surface 80% + sandAlpha4 1px + 阴影 0 8 10 /5% + 圆封面 + 单行标题；状态 a 列表尾通栏条/状态 b 卡片态无当前消费屏，随 V3 批次2 queue 屏落地）【2026-10-02】
- [x] v2 header 替换 AppBar（`HeaderView` 组件 624:30831，三 tab 统一；设置入口 = header 右侧 48×48 齿轮 slot；trailing action 位已留、clear 接线随批次1裁定）【2026-10-02】
- [x] `CategoryStripView` 组件 + `CategoryStripModel` 纯逻辑（+3 测试；接入 Inbox 屏随 IA 翻转）【2026-10-01】
- [x] CategoryStripView 选中态修正（§3.2：`goldAlpha7` 底 + `sandAlpha4` 1px 描边 + `sand1` 文字；未选中 `sandAlpha2` 底；chip 高 44、字 16 semibold；+色值断言 dark 显式解析；接线 Inbox + `InboxCategoryFilter` 过滤 + 状态行 + 提示卡片同日落盘）【2026-10-02】
- [x] Library 屏（`LibraryViewController`：v2 header + membership 占位块 + 内嵌 Subscriptions；V3 批次 2 深化）【2026-10-02】
- [x] Welcome 屏 + SignUp UI（auth 接线按 §8 留 TODO；入口接线随 V3 批次5 auth 重构）【2026-10-02】
- [x] 导航图重梳（Discover 退役出 tab、搜索圆钮推 SearchEntry→SearchPage、library/queue 入口就位；两处空态 Explore 改搜索入口；`PodcastsTabContainer`/`PodcastsTabStrip`/`PagingTabsContainer` 删除）【2026-10-02】
- [x] 修复补丁轮（3 轮）：pill 圆角补齐+无描边、tab 图标 24pt/label 12 Regular·大写、scrim 收敛 24pt 渐变（blur 移除，mask 地雷见 §9a）、底栏 chrome 族改静态白 80 + chip/mini player token 钉 light 变体（76:2614 原帧实测， isSelected 矩形底地雷见 §9a）、mini player 间距 14pt、Library inset 统一 16（内容避让语义裁定项仍开放，见进度注记⑥）【2026-10-02】

### V3 · 逐屏重设计（§4 映射表逐行落实）

- [ ] 批次1 Feeds：Inbox 三态 / ShowDetail / Detail sheet（§7a-C1 Inbox 侧全量落地 2026-10-02：context menu + 批次1 半场的滚动流 chrome/v2 卡 `InboxEpisodeCardCell`/swipe/more/history 尾钮，见 §10 进度注记；**余量 = Detail modal v2 三态（1787:7496/1593:10342）+ ShowDetail（365:4610 + loading 骨架 1243:8631）**）
- [ ] 批次2 Queue/Library：QueueView / History / Library blocks（Library 内容块有 `628:6406`/`1575:9948` 两版组件，实施前裁定，见 §1 未登记清单；History 居中卡 form sheet 化终裁，§7a-C4）
- [ ] 批次3 Player 族：容器/Scrubber/main control/sheet 族/Transcript（sheet 族取值件优先 `UIStepper` 等原生换肤、tooltip → `UIMenu`，§7a-C5；segment control 对照 `UISegmentedControl` 终裁，§7a-C3）
- [ ] 批次4 Discover(退役)/Search/Chat（搜索重建评估 `UISearchController`/`UISearchBar`，§7a-C2；search tabs 同 C3 裁定）
- [ ] 批次5 Settings/Auth（含 Welcome/SignUp/Paywall）（Import/Export/Share 对话框 form sheet 化终裁，§7a-C4）
- [ ] 每屏双外观验证（iOS 27 主目标模拟器）

### V4 · 测试与基线

- [ ] AnycastSnapshotTests 20 基线重录（S1–S19b，×2 OS ×2 外观 = 80 张）：iOS-27+iOS-18 × Light/Dark；v1 基线删除。基线清单随 §4 处置同步：S3/S8 随 IA 退役删基线，新增 Library/Welcome/SignUp 屏补基线，最终清单与编号随 05 §6 一并更新（20/80 相应变化）
- [ ] AnycastAppTests 期望值更新（只改期望不改强度）；LayoutSanityTests 扩双外观
- [ ] tool/ui_qa crawl 重跑 + VLM 复核；axdiff 对 IA 变更屏降级为结构断言
- [ ] §9 交互备注落入 03/05；K 表 re-triage 增补 v2 条目

### V5 · 收尾

- [ ] 本文档进度注记 + 00 执行计划 MV 勾选
- [ ] 03 §5 标注 v1-legacy；07 适配清单 A1–A9 re-triage
- [ ] CI native-ios 保持绿；进入 M4

## 修订规则

沿用《00》：行为与基线不符先改基线文档；新决策写入本文对应小节；cream/sand 逐屏改判、探索性功能解禁均需产品拍板后登记。

**私有信息纪律（2026-10-01 增补；2026-10-08 改为 Infisical 物化）**：Figma 链接与 file key 属私有设计源，只存 Infisical `/app-config` 的 `FIGMA_ANYCAST_V2_URL`，由 `scripts/bootstrap.sh` 物化到本地 `native/.env`（`.gitignore` 的 `*.env` 规则覆盖，永不入库；注意仓库根 `.env` 是另一文件，不含该变量）；禁止写入任何入库内容（代码、注释、文档、提交信息、PR 描述）。后续实施会话需要设计数据时从 `native/.env` 读取。文档内的 node-id 无访问凭据、离开 file key 无法定位文件，保留作为实施映射索引。
