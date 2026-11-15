# 07 · UI 组件映射与自绘边界（原生优先方案）

> 2026-09-21 定稿。原则（用户确认）：**系统组件（iOS 26/27 优先，Liquid Glass 尽量吃满）→ 成熟库 → 自绘**；自绘仅用于系统与成熟库都做不到的表达；接受由此带来的一定视觉适配，但整体设计语言与交互语义保持一致。
> 事实来源：《03》UI 基线 + 两轮 API/库查证（来源见 §7）。本文回答："哪些用原生、哪些用库、还剩多少自绘"。

---

## 0. 总结论

**"自绘很少"成立。** 全量 UI 元素（约 60 类）的归属统计：

| 归属 | 数量 | 说明 |
|---|---|---|
| 系统组件（iOS 26 玻璃自动获得） | ~45 类 | TabBar/导航/sheet/弹窗/开关/滑条/文本框/分段控件/刷新/列表/空态/分享面板/选择器…… |
| 成熟库 | 4 个 | Kingfisher（图片）、ChatLayout（聊天）、MarqueeLabel（跑马灯）、lottie-ios（动画） |
| 必须自绘 | **1 中型 + 10 小型** | 见 §3 清单：唯一中型是歌词视图（~1 周）；其余全是 0.5~2 天的小控件/小动画 |

**不引入任何整体 UI 框架**——UIKit 本身就是那个"UI 库"。Flutter 时代大量自绘是因为组件库不成熟；UIKit + iOS 26 玻璃体系下这个前提消失了。

---

## 1. 视觉一致性边界（保留 vs 适配）

### 1.1 保留（设计语言不变）

- 暗色底 `#111316`、绿色 accent（`#6EE7B7` / `#10B981`）、`#232830` 卡片底；
- Comfortaa 标题字体（打包 TTF）与现有字号层级；
- 卡片/列表的布局结构、页面导航结构（3 Tab + sheet 栈）、页面信息架构；
- **全部手势与交互语义**：拖拽 150ms 起拖、歌词点击=播放暂停、mini player 垂直轻扫展开、Tab0 重复点击回顶/刷新等（这些是《05》P0 回归项，不因组件更换而改变）；
- 歌词视图、播放器页面、频道折叠头的整体视觉（自定义区域）。

### 1.2 适配为系统样式（已接受的变化）

| # | Flutter 现状 | iOS 方案（iOS 26 视觉） | iOS 18 降级 |
|---|---|---|---|
| A1 | 自绘底栏（Tab 图标 + mini player 竖排） | **UITabBarController 浮层玻璃 tab bar** + **UITabAccessory 容纳 mini player**（玻璃/尺寸系统托管，随 tab bar 折叠联动） | 标准 UITabBar + 自定义 mini player 悬浮 view（自绘小件 #10） |
| A2 | 全屏 sheet + 自定义 42×6 把手 | **UISheetPresentationController**：系统把手、大圆角、半屏内缩、全高变实的玻璃外观；把手"点击关闭"用 header 区 tap 补足（系统把手不可点） | 同 API（iOS 16+），无玻璃 |
| A3 | sheet 拖到 90% 才关（粘性） | 系统默认关闭阈值（**适配**）；实测手感差异大再补自定义 presentation controller（中件，暂不做） | 同左 |
| A4 | 自定义"随进度增长细进度条"下拉刷新 header | **UIRefreshControl 系统玻璃 spinner**（自定义进度条在 iOS 26 无公开做法，且与"移除自定义效果"的官方指南相悖） | UIRefreshControl 标准样式 |
| A5 | Material Switch / 自绘滑条轨道 | **UISwitch / UISlider**（iOS 26 自动玻璃）；滑条 thumb 显数值仍需自定义（自绘小件 #4/#5） | 同 API 无玻璃 |
| A6 | Get.dialog AlertDialog | **UIAlertController**（系统样式、暗色自适应） | 同 |
| A7 | 把手 3 秒提示动画 | 去掉（系统 sheet 的 affordance 足够，属装饰性自绘） | — |
| A8 | CountryCodePicker 弹窗 | 列表 sheet（UICollectionView list + 搜索）或 UIPickerView in sheet | 同 API |
| A9 | 系统分享/文件选择/浏览器 | UIActivityViewController / UIDocumentPickerViewController / SFSafariViewController（本就是系统件） | 同 |

> 以上 A1–A9 即"整体一致"边界内的全部视觉变化；除此之外的界面均按 §1.1 保留原设计。

---

## 2. 逐组件映射总表

### 2.1 导航与容器

| Flutter 现状（《03》出处） | iOS 方案 | 说明 |
|---|---|---|
| IndexedStack 三 Tab + KeepAlive | **UITabBarController**，子 VC 常驻 | 状态保持语义天然等价；iOS 26 浮层玻璃 tab bar；可选 `tabBarMinimizeBehavior = .onScrollDown`；**启动时对三个子 VC `loadViewIfNeeded()` 预热**（否则子 VC 首次选中才 loadView、首切有构建延迟，与旧版"秒切"不等价，08 §7.1）——预热含 Discover 随首帧预取 `/api/categories` 的行为照旧复刻（IndexedStack 全量挂载即请求，08 §11.6） |
| mini player（PlayerBar） | **iOS 26：`UITabAccessory`（`bottomAccessory`）**，玻璃与尺寸系统托管，`UITraitTabAccessoryEnvironment` 响应 inline/regular | 注意：装的是 **UIView 不是 VC**（子 VC 自行管理）；**无内建展开手势**——点按/垂直轻扫展开播放页由我们实现（与现状一致）；**无 isHidden——隐藏机制靠 `bottomAccessory = nil` 增删**（旧版无播放集时整个 PlayerBar `SizedBox.shrink` 收起，bottom_nav_bar.dart:87，此行为要复刻）；与锁屏无关（Now Playing 走 MediaPlayer，正交）；iOS 18 降级版（自绘 #10）用常规 isHidden 即可 |
| mini player（iOS 18 降级） | 自定义悬浮 view 置于 tab bar 上方（自绘小件 #10） | `additionalSafeAreaInsets` 避让 |
| 10 个全屏 modal sheet（closeProgressThreshold 0.9/0.8） | **UISheetPresentationController + custom detents**（iOS 16 API，iOS 26 无新 detent API） | 三层 sheet 嵌套无官方限制（从最顶层 VC present 即可）；粘性关闭见 A3 |
| Detail 的 DraggableScrollableSheet（0.7/0.6） | custom detent（.fraction(0.7)/.fraction(0.6)）+ 滚动联动 | 系统自带"滚内容→缩 sheet"行为 |
| Tab0 重复点击：回顶/刷新 | `UITabBarControllerDelegate.didSelect` + 自实现 | 与 UITabBar 原生行为同型 |
| 二级 tab（Inbox/Subscriptions、Discover 分类、Channels/Episodes） | **自绘细下划线 tab 条（小件 #6，~150 行）** | UIKit 无该形态系统控件（UISegmentedControl 视觉不同）；Music/Podcasts 同款也是 Apple 私有实现 |
| 播放器 PageView 三页横滑 + 胶囊 PageTab | **UIPageViewController(.scroll)**；胶囊选择器自绘（小件 #7） | UIPageViewController 仍是 2026 标准，无新 paging 容器；UIPageControl 样式与胶囊不符 |
| 全局搜索栏（AppBar 内） | `navigationItem.searchController`（标准）；**可选** iOS 26 `UISearchTab`（tab bar 搜索形态） | 现状是首页内嵌搜索框，保守做法保留内嵌（自定义 UITextField + 玻璃容器）；UISearchTab 作为可选增强评估 |

### 2.2 列表与卡片

| Flutter 现状 | iOS 方案 |
|---|---|
| ListView.separated 卡片流（Inbox/订阅/搜索/频道） | **UICollectionView + Compositional Layout**，卡片 cell（常规布局代码，非自绘）；Diffable/批量更新默认 `withoutAnimation`（旧版是无动画整表重建，默认带动画是用户可见差异；将来要动画是一行业务决策，08 §7.2） |
| 下拉刷新 + refreshOnStart + 自动刷新定时器 | **UIRefreshControl**（A4 适配）+ 定时器逻辑照搬 |
| Card 整卡点按展开按钮条（AnimatedContainer 0↔60） | cell 高度动画（`UIView.animate`），同列表互斥由 controller 管 |
| 播放进度背景条（mini player / 卡片） | cell/view 上叠 CAShapeLayer/CALayer 宽度更新（小，随 positionData 驱动，等价实现） |
| 下载进度环 CircularPercentIndicator | CAShapeLayer + strokeEnd（小件 #8） |
| 空态（ImportBlock / "No results" / "Network Error" / "No history"） | **UIContentUnavailableConfiguration（系统 API，iOS 17+）**——标题/描述/按钮系统样式；DZNEmptyDataSet 已死不用 |
| ReorderableListView 拖拽排序 | 见 §6 专节（系统 reordering + 自定义 150ms 手势） |

### 2.3 频道页

| Flutter 现状 | iOS 方案 |
|---|---|
| pinned 折叠头（封面 120→60 缩小左移、文字 1/4 处淡出、palette 渐变背景） | Compositional Layout `pinToVisibleBounds` header + `scrollViewDidScroll` 插值（布局代码；**无系统视差 API，已查证**；~1 天）+ CAGradientLayer 背景；**插值优先改 transform/anchor 约束而非每 tick 重排子视图**（CALayer transform + opacity 远低于布局循环，旧版 SliverPersistentHeader 每 tick 重算布局是 Flutter 机制，勿照搬，08 §11.2）；palette 取色按 imageUrl 内存缓存（旧版每次打开/换集都重新解码取色，结果等价速度更快） |
| ExpandableText（2 行截断→全文弹窗） | UILabel + ~40 行（boundingRect 判截断→"More"→展开）；ExpandableLabel 库已死不用 |
| 订阅三态胶囊按钮 / 分享圆钮 | UIButton Configuration（iOS 26 `.glass()`/`.prominentGlass()` 自动玻璃） |
| Newest/Oldest 切换 | 下划线 tab 条同款（小件 #6 复用） |
| RSS 域名点击复制 + snackbar | UIPasteboard + 触觉反馈 + 20 行 toast（小件 #9） |

### 2.4 播放器

| Flutter 现状 | iOS 方案 |
|---|---|
| palette 三段渐变背景 | CAGradientLayer + CoreImage 取色（系统） |
| 长标题 Marquee 跑马灯（2 处） | **MarqueeLabel 4.5.3**（成熟库；2025-09 专门修过 iOS 26 UIGlassEffect 兼容；UIKit 无系统跑马灯，已查证）；触发条件两处不同、勿互相污染（08 §11.6）：播放器标题改 `boundingRect` **实测宽度**触发（旧版 `title.length × 24` 字符估宽，CJK/拉丁混排必误判，K33 微增强）；**历史列表保持 always-scroll**（不测宽、短标题也滚，配 startAfter≈1s） |
| MyProgressBar（缓冲段、剩余时间标签、发光 thumb） | 自定义 UISlider 子类 + 叠加缓冲层（小件 #4，~半天） |
| SPEED/COUNTDOWN 滑条（thumb 内显数值、7 档步进） | 同款自定义 thumb UISlider（小件 #5） |
| SKIP SILENCE / CONTINUOUS PLAY Switch | **UISwitch**（系统；skip silence 开关已按 K2 移除，只剩后者） |
| 中央 72×72 圆形播放/暂停（含 loading Lottie） | UIButton + PlayIcon 等价（lottie-ios 播 loading） |
| replay_10 / forward_30 | 系统 SF Symbols 按钮 |
| 封面分享短链→系统分享面板 | UIActivityViewController（转圈期间用系统 activity） |
| HTML show notes（flutter_widget_from_html + sanitize） | **SwiftSoup 清洗 + `NSAttributedString.loadFromHTML`（iOS 15+ 异步 API）后台解析、主线程落地**——`NSAttributedString(html:)` 同步且不宜在主线程（新 iOS 运行时警告 + 卡顿），勿用（08 §7.4，2026-09-22 修订本表原方案）；**同一 description 按 episode 缓存解析结果**（Detail 与播放器第 0 页共享一份，纯内存即可）；`htmlToText`（卡片列表纯文本）同样按输入串缓存 + 后台执行（旧版每张卡片每次 build 重新 parse HTML，是列表卡顿的结构性疑点，08 §11.1）；链接可点=K7 增强顺带达成；超长/复杂 HTML 退 WKWebView |

### 2.5 歌词（唯一中型自绘）

| Flutter 现状 | iOS 方案 |
|---|---|
| flutter_lyric 逐行滚动跟随、当前行居中放大高亮 | **自建**（小件 #1，~1 周）：UICollectionView + 行跟随（时间戳定位 + scrollToItem 弹性）、NSAttributedString |
| 双语行内混排（主行/译文反色） | 单 UILabel + NSAttributedString 两段样式（无库可用：AMLL 全家是 TS/Rust，SpotlightLyrics 2020 年死，SwiftSubtitles 只有解析无 UI——且我们数据本就是 JSON segments，**连 LRC 解析都不需要**） |
| 点击行=播放/暂停 + 中央 80×80 形变动画 | tap 手势（标准）+ 中央形变小自绘（小件 #3；或降级为 SF Symbol bounce 效果——适配选项） |
| 拖动歌词出现时间横条（时间+横线+播放钮，点击 seek） | 自绘横条（小件 #2 的组成部分；`neverResume` 拖后不回位、3s 后恢复跟随的节奏照搬） |
| 右下黑 87% 浮层（AI 聊天 + more 菜单） | **iOS 26：`UIGlassContainerEffect` + 嵌套 `UIGlassEffect` 成组玻璃 + `UIButton.Configuration.glass()`**；iOS 18：半透明底 + 圆角 |
| 转写五态 UI | 常规 view + lottie-ios（robot_loading 资产直接复用） |

### 2.6 聊天

| Flutter 现状 | iOS 方案 |
|---|---|
| flutter_chat_ui（气泡、输入栏、键盘避让、占位"..."替换） | **ChatLayout 2.5.1**（2026-09-18 发版，维护热度高；custom layout 定制强、已适配 iOS 18+ 变更与 Swift 6）+ **纯文本输入栏定为自写 ~30 行**（砍掉 InputBarAccessoryView，少一个依赖——08 §8 定稿）；纯文本自定义 cell 极薄 |

> 不选 MessageKit（功能够但 22 个月无 release）、不选 Stream Chat SDK（绑定其云后端 + 专有许可）。

### 2.7 设置 / 登录 / 付费墙 / 导入

| Flutter 现状 | iOS 方案 |
|---|---|
| SettingsPage 分组列表 | **UICollectionView list（.insetGrouped）**（iOS 26 重编译即得玻璃分组观感，去掉自定义背景即可） |
| Tooltip 长按说明 | UILongPressGestureRecognizer + 小浮层（或 context menu） |
| 三个上限/间隔选择（CupertinoPicker×3 in bottom sheet） | UIPickerView in sheet（UIPickerView 无 iOS 26 改版、暗色自适应，照用） |
| Carousel 付费介绍图（autoPlay） | Compositional Layout orthogonal scrolling + paging + 定时滚动（标准） |
| ExpansionTile（PlusIntro、导入说明） | list disclosure 展开行（系统行为） |
| 月/年套餐选择卡 | 常规自定义 cell（选中态绿底） |
| 登录三按钮 | UIButton（系统） |
| OPML 导入进度环 | 复用下载进度环（#8） |
| ImportExport 对话框 | UIAlertController + UIDocumentPickerViewController |

### 2.8 图标 / 字体 / 颜色

- 图标：**SF Symbols 优先**（material/fluent/remix 九成有近似对应）+ 品牌类 SVG 直接进 Asset Catalog（iconify 的 4 个自定义 SVG 原样打包，视觉零损失）；
- 字体：Comfortaa/notoSans/inter/mPlusRounded1c/roboto TTF 打包 `UIAppFonts`（可子集化）；
- 颜色：沿用《03》§5.1 token 表建 Asset Catalog 颜色。

---

## 3. 必须自绘清单（全部）

| # | 组件 | 规模 | 说明 |
|---|---|---|---|
| 1 | **歌词视图**（行跟随 + 双语 + 拖动横条 + 点击行） | **中，~1 周** | 全项目唯一中型自绘；无可用库（§2.5 调研结论） |
| 2 | 歌词拖动时间横条 | 已含在 #1 | — |
| 3 | 中央 play/pause 形变动画（80×80） | 小，~0.5 天 | 或降级 SF Symbol bounce（适配） |
| 4 | 播放进度条（缓冲段 + 剩余时间标签 + 发光 thumb） | 小-中，~0.5 天 | UISlider 子类 |
| 5 | thumb 显数值滑条（倍速/倒计时） | 小，~0.5 天 | 同上复用 |
| 6 | 下划线 tab 条 | 小，~0.5 天 | 二级 tab/排序切换复用 |
| 7 | 播放器 PageTab 胶囊选择器 | 小，~0.5 天 | — |
| 8 | 下载/导入进度环 | 小，~0.5 天 | CAShapeLayer |
| 9 | Toast/snackbar（"Copied" 等） | 小，~20 行 | 库都停滞且场景太小（调研结论） |
| 10 | mini player iOS 18 降级版 | 小-中，~1 天 | iOS 26 走系统 UITabAccessory |
| 11 | "加列表"飞入动画（4 触发点） | 小，~0.5 天 + 终点推导 | overlay 位移动画；**终点需从 tabBar 子视图 frame 推导**——旧版终点是 BottomNavBar.playlistKey（GlobalKey）的中心点（bottom_nav_bar.dart:17-23 `getPlaylistPosition()`），换系统 UITabBar 后无 GlobalKey 等价物，且 iOS 26 tab bar 可折叠、折叠态坐标不同。**已定默认：取当前布局下 playlist Tab 图标的实际 frame 中心（展开/折叠两态各自取），取不到时退化为可见 tab bar 区域中心**（属 A1 已接受适配内） |
| 12 | 渐变大标题文字（AppBar logo） | 小，~20 行 | CAGradientLayer mask |

合计约 **2.5~3 周自绘工作量**，其中歌词独占 1/3。其余 90%+ 界面为系统组件或成熟库。

---

## 4. Liquid Glass 采用计划（iOS 26/27）

**自动获得（用 iOS 26 SDK 编译即可，去掉自定义背景/appearance）：**
UINavigationBar、UITabBar、UIToolbar、UISplitViewController、UIButton、UISwitch、UISlider、UIStepper、UISegmentedControl、UITextField，以及全部 sheet/action sheet/popover 呈现（大圆角、半屏内缩、全高变实）。

**主动采用：**
- `UITabBarController.bottomAccessory`（UITabAccessory）承载 mini player（A1）；
- 歌词右下浮层/播放器胶囊等自定义浮层：`UIGlassContainerEffect` + 嵌套 `UIGlassEffect`（成组融合渲染）、`UIButton.Configuration.glass()/prominentGlass()`、圆角走 `UIView.cornerConfiguration`（iOS 26 新结构；注意 `cornerConfiguration` 在 UIView 上，不在 UIGlassEffect 上）；
- 列表页 `UIScrollEdgeEffect`（滚动边缘软效果）默认 `.automatic`，不覆写。

**iOS 27 相关（实现期注意）：**
- **UIScene 生命周期强制**（新 SDK 构建不用 scene 则无法启动）——新工程默认满足；
- **App 可缩放**：`UIScreen.main` 禁用（用 `windowScene`/trait/`effectiveGeometry`）、布局按 size class 不按 idiom；**竖屏声明在可缩放环境降级为"偏好"**；**iPhone-only App 在 iOS 27 的 iPad 上是全尺寸可缩放窗口（任意宽高比）——硬性验收：任意窗口尺寸不崩不溢出（允许观感一般，《05》§11/§10.3）**，全部布局用 view bounds/trait、**禁一切按屏宽计算**（现版 `(屏宽-24)×pos%` 类写法不得照搬）、不依赖 `UIRequiresFullscreen`（WWDC25 口径将被忽略），最小窗口尺寸限制 API 列 M1/M2 调研兜底（2026-09-22 升级为验收标准）；**已决策首版 iPhone-only**（《05》§11，`TARGETED_DEVICE_FAMILY=1`）——iPad 由系统 iPhone 兼容/可缩放模式承载，完整 iPad 适配列 backlog；
- 可选增强：`navigationItem.barMinimizationBehavior`（导航栏滚动折叠）、`prominentTabIdentifier`；Now Playing 框架见《06》§6。

**iOS 18 降级总策略**：玻璃效果统一封装为一个"玻璃容器"组件——iOS 26 用 `UIGlassEffect`，iOS 18 用 `UIBlurEffect(.systemChromeMaterial)` + `cornerRadius` 模拟；所有 `#available(iOS 26, *)` 分支集中在该封装与 TabAccessory/浮层三处，不散落业务代码。

---

## 5. 与回归测试的衔接

- 《05》§6.1 的快照/结构对照在本文 §1 边界内执行：**A1–A9 适配项不作为视觉回归差异报 bug**，其余区域仍按原设计对照；
- 手势语义（拖拽 150ms、歌词点击/拖动、mini player 轻扫、Tab0 重复点击等）不因组件更换放松——仍为《05》§6.3 P0；
- 《05》§0.2"允许近似"一节以本文 §1 为准绳。

## 6. 播放列表拖拽排序实现注记（150ms + 1.1x 的系统做法）

查证结论（详见 §7 来源）：
- `UICollectionViewDiffableDataSource.reorderingHandlers` 是 **iOS 14 API**（iOS 26/27 无新排序 API），与 Compositional Layout + Diffable 完全兼容；
- 系统内建长按默认 **0.5s 且不可配置** → 复刻 150ms：关掉 `installsStandardGestureForInteractiveMovement`，自建 `UILongPressGestureRecognizer(minimumPressDuration: 0.15)` 驱动 `beginInteractiveMovementForItem(at:)` / `updateInteractiveMovementTargetPosition` / `endInteractiveMovement()`，排序事务统一走 `reorderingHandlers.didReorder`（不再实现 `moveItemAt`）；
- 系统浮起（lift）视觉**不可定制** → 保留 1.1x 放大的两条路：a) 改走 `UICollectionViewDragDelegate` 路线，用 `previewProvider` 自定义拖拽预览（推荐，交互手感保留）；b) 接受系统浮起视觉（列入适配，随时可切）；
- 拖动靠边自动滚动系统自带；`onReorderStart` 收起展开条、涉及 index 0 的暂停换源逻辑在 `didReorder` 事务后照搬《03》§3.2；
- **写库算法按 K26 修复语义**：对已存在条目的移动，邻居取**移动后**的列表（旧算法取移动前 DB 列表，下移 off-by-one、重启后回退）；插入语义逐字节复刻旧算法（G1 golden 对拍口径，《05》§1.5）。

## 7. 主要依据

- [Adopting Liquid Glass（Apple 官方，自动采用清单/浮层 tab bar/移除自定义背景）](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)
- [UITabAccessory](https://developer.apple.com/documentation/uikit/uitabaccessory) / [UIGlassEffect](https://developer.apple.com/documentation/uikit/uiglasseffect) / [UIGlassContainerEffect](https://developer.apple.com/documentation/uikit/uiglasscontainereffect)（Apple 文档）
- [sebvidal: What's new in UIKit (iOS 26)](https://sebvidal.com/blog/whats-new-in-uikit-26)（bottomAccessory/Environment/minimizeBehavior/UIColorEffect/cornerConfiguration/搜索 API 组）
- [WWDC26 Session 278 笔记: Modernize your UIKit app](https://wwdcnotes.com/documentation/wwdc26-278-modernize-your-uikit-app)（iOS 27 强制 scene、可缩放、barMinimization）
- [UICollectionViewDiffableDataSource.reorderingHandlers（iOS 14+）](https://developer.apple.com/documentation/uikit/uicollectionviewdiffabledatasource/reorderinghandlers) / [WWDC20 10045](https://developer.apple.com/videos/play/wwdc2020/10045)
- [pinToVisibleBounds](https://developer.apple.com/documentation/uikit/uicollectionviewboundarysupplementaryitem/pintovisiblebounds) / [UIContentUnavailableConfiguration](https://developer.apple.com/documentation/uikit/uicontentunavailableconfiguration)
- [ChatLayout releases](https://github.com/ekazaev/ChatLayout/releases)（2.5.1, 2026-09-18）/ [MessageKit releases](https://github.com/MessageKit/MessageKit/releases)（5.0.0, 2024-12）/ [MarqueeLabel releases](https://github.com/cbpowell/MarqueeLabel/releases)（4.5.3, 2025-09，含 UIGlassEffect 修复）/ [Kingfisher releases](https://github.com/onevcat/Kingfisher/releases)（8.12.0, 2026-08）
- 歌词库调研：[AMLL org（TS/Rust，无原生组件）](https://github.com/amll-dev)、SpotlightLyrics（2020 停更）、[SwiftSubtitles（仅解析）](https://swiftpackageindex.com/dagronf/SwiftSubtitles)
- 相对时间：`RelativeDateTimeFormatter` + `.abbreviated` 本机实测输出 "5m ago"（匹配 timeago en_short；<45s 的 "just now" 需自加分支，最终以《05》G10 golden 导出的 Dart 实际字符串为准）
