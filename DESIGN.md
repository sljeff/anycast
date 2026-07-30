---
version: 0.1.0
name: Anycast 旧版设计
status: legacy-baseline
language: zh-CN
description: 对原 Flutter 版 Anycast 已有产品结构、视觉样式、组件和交互的事实性描述。
scope:
  product: anycast
  implementation: flutter
  platforms:
    - ios
    - android
  theme: dark-only
  describes: original-shipped-design
sources:
  app_shell: lib/main.dart
  theme: lib/styles.dart
  header: lib/widgets/appbar.dart
  first_screen: lib/pages/podcasts.dart
  inbox: lib/pages/feeds.dart
  subscriptions: lib/pages/subscriptions.dart
  cards: lib/widgets/card.dart
  persistent_player: lib/widgets/bottom_nav_bar.dart
information_architecture:
  root_destinations:
    - id: podcast
      label: Podcast
      default: true
      local_modes:
        - Inbox
        - Subscriptions
    - id: playlist
      label: Playlist
    - id: discover
      label: Discover
  secondary_surfaces:
    - Search
    - Settings
    - Episode Detail
    - Channel Detail
    - Player
  persistent_chrome:
    - Mini Player
    - Bottom Navigation
colors:
  primary: "#34D399"
  primary-light: "#A7F3D0"
  primary-light-max: "#ECFDF5"
  primary-dark: "#079669"
  title-gradient-start: "#059669"
  background: "#111316"
  background-secondary: "#30444E"
  surface: "#232830"
  navigation-surface: "#16191D"
  selected: "#6EE7B7"
  action: "#10B981"
  secondary: "#96A7AF"
  muted: "#6B7280"
  input-placeholder: "#4B5563"
  divider: "#9CA3AF"
  warning: "#FFBC25"
  text-on-dark: "#FFFFFF"
typography:
  display:
    family: Comfortaa
    size: 44
    weight: 700
    line-height: 0
    letter-spacing: 4.4
  section-title:
    family: Comfortaa
    size: 24
    weight: 700
    line-height: 0
    letter-spacing: 2.4
  navigation-label:
    family: Comfortaa
    size: 12
    weight: 400
  subscription-title:
    family: Comfortaa
    size: 14
    weight: 700
  episode-title:
    family: PingFang SC
    size: 16
    weight: 500
  episode-metadata:
    family: PingFang SC
    size: 12
    weight:
      - 400
      - 500
  episode-description:
    family: Inter
    size: 12
    weight: 400
  mini-player-title:
    family: system
    size: 16
    weight: 500
  mini-player-metadata:
    family: system
    size: 12
    weight: 400
spacing:
  base: 4
  observed-scale:
    - 4
    - 6
    - 8
    - 12
    - 16
    - 24
  page-horizontal: 24
  list-gap: 12
  card-padding: 8
  artwork-to-copy: 12
radii:
  artwork-small: 8
  search: 12
  artwork-large: 16
  mini-player: 16
  episode-card: 20
  sheet: 24
  circular: 9999
motion:
  card-expand:
    duration-ms: 200
    curve: easeInOut
  root-retap-scroll:
    duration-ms: 300
    curve: easeInOut
  playlist-drag-delay-ms: 150
components:
  app-bar:
    preferred-height: 148
    horizontal-padding: 24
    top-padding: 8
    settings-button: 36
    search-area-height: 56
  episode-card:
    artwork: 80
    border-width: 1
    expanded-actions-height: 60
  subscription-card:
    artwork: 64
    border-width: 1
  mini-player:
    height: 58
    horizontal-margin: 12
    artwork: 36
    control-target: 40
  bottom-navigation:
    height: 96
    horizontal-padding: 24
    bottom-padding: 24
    item-target: 48
    icon: 24
---

# Anycast 旧版设计

> 深色、直接、以播放流为中心。绿色表示当前状态和主要动作，内容、播放与导航始终保持连续。

## 文档定位

本文描述原 Flutter 版 Anycast 已经存在的设计。它回答四个问题：

- 产品原本如何组织；
- 首屏原本包含什么；
- 视觉和组件原本如何表现；
- 哪些地方从未形成一致的设计系统。

本文不是 2.0 设计说明，也不是未来改版规范。它不主张继续沿用所有旧样式，只为后续迁移提供可核对的旧版基线。

当本文与实际行为冲突时，以已发布代码为准。自动化安全、发布流程和数据兼容性由 [`AGENTS.md`](AGENTS.md) 约束，不在本文重复。

## 概览

旧版 Anycast 是一套跨 iOS 和 Android 共用的 Flutter 深色界面。它的主要特征是：

- 全局使用接近黑色的背景和深灰表面；
- 以绿色表示选中、播放和主要操作；
- 使用 Comfortaa 建立标题和导航的品牌感；
- 使用卡片承载 Episode 和订阅节目；
- 将 Mini Player 固定在底部导航上方；
- 使用全屏或底部 Modal 承载搜索、设置、详情和播放器。

旧版只有一套深色主题。iOS 和 Android 共用相同的信息架构与大部分视觉实现，没有分别建立原生平台外壳。

## 产品结构

“旧版有 3 屏”更准确的说法是：旧版有 3 个根目的地，并非只有 3 个页面。

```text
Anycast
├── Podcast
│   ├── Inbox
│   └── Subscriptions
├── Playlist
└── Discover

Secondary surfaces
├── Search
├── Settings
├── Episode Detail
├── Channel Detail
└── Player
```

### 根目的地

`Podcast`、`Playlist` 和 `Discover` 由同一个 `IndexedStack` 承载。切换根目的地时，页面状态会被保留。

- `Podcast` 是默认目的地；
- `Playlist` 管理待播内容和播放顺序；
- `Discover` 负责发现节目与内容。

### Podcast 内部结构

`Podcast` 内部再分为两个页内 Tab：

- `Inbox` 显示新 Episode；
- `Subscriptions` 显示已订阅节目。

两者均保持页面状态。页内 Tab 不改变底部根导航的选中项。

### 二级页面

Search、Settings、Episode Detail、Channel Detail 和 Player 都通过 Modal 或 Sheet 出现。它们是当前任务的延伸，不是新的根目的地。

### 持久播放

存在当前 Episode 时，Mini Player 显示在内容与底部导航之间。用户切换根目的地时，播放状态保持连续。

## 首屏

首屏是 `Podcast` 的默认 `Inbox` 状态。从上到下依次为：

1. 高 148 的共享 App Bar；
2. 右上角 Settings 入口；
3. 渐变大标题 `PODCAST`；
4. 全宽 Search；
5. `Inbox / Subscriptions` 页内 Tab；
6. 可下拉刷新的 Episode 列表，或首次空状态；
7. 条件显示的 Mini Player；
8. `Podcast / Playlist / Discover` 底部导航。

Inbox 中的 Episode 卡片提供三个固定动作：

- 立即播放；
- 加入 Playlist；
- 从 Inbox 移除。

加入 Playlist 时，界面会播放一个从卡片动作飞向底部 `Playlist` 图标的反馈动画。

## 颜色

旧版颜色以 `#111316` 为页面背景，以 `#232830` 为输入框、按钮和局部表面。白色或接近白色的文字承载主要内容，绿色负责状态和动作。

### 绿色角色

旧版没有把绿色收敛为单一语义色，而是同时使用：

- `#34D399`：主题 Primary、Cancel 等交互文字；
- `#059669`：大标题渐变起点；
- `#6EE7B7`：Tab 和底部导航选中态；
- `#10B981`：Explore 等主要 CTA；
- `#079669`：`DarkColor.primaryDark`，与标题使用值并不相同。

这些值共同构成旧版的绿色品牌感，但不能视为一套已经规范化的色阶。

### 表面与层级

层级主要依靠色调差异、边框和透明覆盖建立：

- 页面背景使用 `#111316`；
- 输入框和设置按钮使用 `#232830`；
- 底部区域使用 `#14171A` 到 `#16191D` 的垂直渐变；
- 卡片边界使用深灰细线；
- 播放进度使用白色 10% 或 20% 的覆盖层。

旧版很少依靠阴影建立层级。

### 已知语义偏差

现有 `ColorScheme` 不能直接当作完整设计 token 使用。例如 `onSurface` 与 `surface` 都被设置为 `#111316`，部分 `on*` 角色也与其底色相同。它描述了旧实现，不代表语义映射正确。

## 字体

Comfortaa 是旧版最明显的品牌字体，主要用于：

- 44 的页面大标题；
- 24 的空状态与大号 CTA；
- 12 的 Tab 和底部导航标签；
- 14 的 Subscription 标题。

内容区域并非单一字体体系：

- Episode 标题和元信息使用 PingFang SC；
- Episode 描述使用 Inter；
- 中央样式文件还定义了 Noto Sans 卡片标题；
- Mini Player 和部分页面使用系统默认字体。

因此，旧版的真实字体结构是 Comfortaa、PingFang SC、Inter、Noto Sans 和系统字体并存。它们来自不同组件的局部实现，而不是一套统一的跨平台排版规则。

### 文本层级

- 页面标题：44 / 700，字距 4.4；
- 二级标题与空状态：24 / 700，字距 2.4；
- Episode 标题：16 / 500；
- Subscription 标题：14 / 700；
- 导航、Tab、元信息和描述：12 为主；
- Search 输入：16。

多处文本将 `line-height` 设为 `0`，并放入固定高度容器。这是旧版视觉紧凑感的来源之一，也会增加大字体时的裁切风险。

## 布局与间距

旧版没有正式的 spacing token，但多数尺寸围绕 4 的倍数出现。最常见的节奏是 8、12、16 和 24。

### 页面节奏

- 主内容左右边距：24；
- 列表顶部：12；
- 列表项间距：12；
- 卡片内部边距：8；
- 封面与文字间距：12；
- 列表底部预留：64。

### 首屏尺寸

- App Bar：Theme 声明高 156，`MyAppBar` 实际首选高度为 148；
- Settings：36 × 36；
- Search 区域：高 56，内部垂直边距 8；
- Episode 封面：80 × 80；
- Subscription 封面：64 × 64；
- Mini Player：高 58，左右外边距 12；
- Mini Player 封面：36 × 36；
- Mini Player 控件：40 × 40；
- 底部导航：高 96，左右和底部边距 24；
- 底栏项目目标区：48 × 48；
- 底栏图标：24。

这些值是从组件中归纳出的旧版事实，不代表项目曾经存在一份正式尺寸表。

## 形状与深度

旧版大量使用圆角，但圆角角色未统一命名。

- 8：Mini Player 封面、播放器主封面；
- 12：Search、Subscription 封面；
- 16：Episode 封面、Mini Player；
- 20：Episode 卡片和 Subscription 卡片；
- 24：Modal Sheet 顶部和部分胶囊按钮；
- 圆形：Settings、卡片动作和导航目标区。

主要内容卡片使用 1px 深灰边框。播放进度通过半透明白色背景在卡片或 Mini Player 内从左向右增长。阴影不是旧版的主要深度手段。

## 导航

### 底部导航

底部导航固定提供三个入口：

- `Podcast`；
- `Playlist`；
- `Discover`。

每个入口同时显示 24 的图标和 12 的文字。选中态使用 `#6EE7B7`，未选中态使用 `#6B7280`。

用户在已经位于 `Podcast` 时再次点击该入口：

- 如果列表不在顶部，滚动回顶部；
- 如果列表已经在顶部，触发刷新。

### 页内 Tab

`Inbox` 和 `Subscriptions` 使用图标加文字。选中态使用绿色文字和指示器，未选中态使用浅灰文字。

### Search 与 Settings

Search 是共享 App Bar 的一部分。提交关键词后，结果以全屏 Modal Sheet 打开，并在 `Channels / Episodes` 之间切换。

Settings 由右上角圆形按钮打开全屏 Modal Sheet。

## 组件

### App Bar

App Bar 同时承担品牌、设置和搜索三种职责。

- 左右边距为 24；
- Settings 位于右上角；
- 标题使用从绿色到透明的纵向渐变；
- Search 使用深灰实色表面和 12 圆角；
- 输入内容非空时，右侧出现绿色 `Cancel`。

### Episode Card

Episode Card 的默认内容顺序是：

1. 80 × 80 封面；
2. 单行 Episode 标题；
3. 节目名；
4. 时长与发布日期，或剩余时长；
5. 最多两行描述。

点击卡片主体会展开高 60 的动作区。点击封面会打开 Episode Detail。Playlist 中的同一组件还会用背景宽度表示播放进度，并显示下载状态。

Episode Card 在三种场景复用，但动作不同：

- Inbox：Play、Add to Playlist、Remove；
- Playlist：Play、AI、Remove；
- Channel：Play、Add to Playlist。

### Subscription Card

Subscription Card 使用 64 × 64 封面、单行标题和最多两行描述。点击整张卡片会打开 Channel Detail。

### Mini Player

Mini Player 只在存在当前 Episode 时显示。它包含：

- 36 × 36 封面；
- 单行标题；
- 已播时间与总时长；
- Play / Pause；
- Forward 30。

整条 Mini Player 可点击或上拉，以打开全屏 Player。背景覆盖宽度表示播放进度。

### Empty State

Inbox 首次为空时显示：

- `It’s empty here. Let’s change that!`；
- 主要操作 `Explore`；
- 次要操作 `Import OPML`；
- Help 入口。

Subscriptions 为空时显示：

- `Whoops! Looks like your podcast galaxy is still unexplored.`

Playlist 为空时显示：

- `All caught up? Explore new shows!`；
- `Explore` 操作。

## 动效

旧版动效用于说明状态变化或操作去向：

- Episode Card 动作区以 200ms `easeInOut` 展开和收起；
- 重复点击 `Podcast` 时，以 300ms `easeInOut` 回到列表顶部；
- 加入 Playlist 时，图标从卡片飞向底部 `Playlist`；
- Playlist 长按约 150ms 后进入拖动，拖动项放大到约 1.1 倍；
- Mini Player 的进度覆盖随播放位置增长。

旧版没有统一的 Reduced Motion 处理。

## 状态

### Inbox

已存在的状态包括：

- 自动刷新；
- 下拉刷新；
- 线性刷新进度；
- 空状态；
- Episode 列表；
- 卡片展开；
- 当前播放；
- Mini Player 显示或隐藏。

Inbox 没有独立的初始 Loading 状态。数据库内容尚未返回时，界面可能先显示空状态。

### Episode Card

已存在的状态包括：

- 默认；
- 展开；
- 当前播放或已有进度；
- 未下载；
- 下载中；
- 已下载。

### Mini Player

已存在的状态包括：

- 隐藏；
- Loading；
- Playing；
- Paused。

### Search

已存在的状态包括：

- 输入；
- Channels 结果；
- Episodes 结果；
- Loading；
- No results。

## 图标

旧版没有统一图标库：

- 根导航主要使用 Material Icons；
- `Inbox / Subscriptions` 使用 Fluent UI System Icons；
- Mini Player 使用 Remix Icon；
- 卡片和页面动作大量使用 Iconify。

同一视觉层级可能出现不同线宽、填充方式和光学尺寸。这是旧实现的一部分，不应被误读为一套有意混搭的图标规范。

## 文案

旧版以英文为主，语气直接、轻松，空状态带有明显的鼓励感。

- 页面大标题使用全大写单词，如 `PODCAST`、`PLAYLIST`；
- 根导航使用单数名词；
- 空状态先说明现状，再给出 `Explore` 或 `Import OPML`；
- 进度和状态尽量使用短标签。

旧文案存在标点、大小写和命名不一致。例如 Search placeholder 使用 `Shows,Episodes,and more`，逗号后缺少空格。这些差异属于历史实现，不是文案规则。

## 无障碍现状

旧版具备一些基础：

- 底部导航同时提供图标和文字；
- 长标题和描述使用行数限制与省略号；
- 多个 Modal 使用 Safe Area；
- 底栏目标区为 48 × 48。

但首屏仍有明确缺口：

- Settings 只有 36 × 36；
- Mini Player 控件只有 40 × 40；
- 下载按钮只有 16 × 16；
- 多个交互使用裸 `GestureDetector`；
- 首屏组件缺少稳定的 `Semantics`、`semanticLabel` 或 `Tooltip`；
- 固定高度和 `line-height: 0` 不利于系统文字缩放；
- 部分 12px 灰色文字在深色背景上的对比度不足；
- 没有语义、文字缩放或 Golden Test 覆盖。

本文如实记录这些限制，不把它们定义为应继续遵循的规范。

## 已知漂移

旧版已经形成鲜明外观，但没有形成完整设计系统。

- 颜色只有一部分集中在 `DarkColor`，其余散落在组件中；
- 同一绿色语义使用多个色值；
- 字体在 Comfortaa、PingFang SC、Inter、Noto Sans 和系统字体之间切换；
- 间距和圆角没有集中 token；
- 图标库混用；
- 触控目标从 16 到 48 不等；
- Theme 的 App Bar 高度为 156，`MyAppBar` 的首选高度为 148；
- 主题的部分 `ColorScheme` 语义映射不正确；
- [`lib/pages/styles.dart`](lib/pages/styles.dart) 中的 `AppStyles` 没有被引用。

## 复刻检查

当需要还原旧版界面、制作迁移对照或核对截图时，应确认：

- 根导航仍为 `Podcast / Playlist / Discover`；
- `Inbox / Subscriptions` 仍属于 `Podcast` 内部；
- Search 和 Settings 仍是二级 Modal；
- Episode Detail、Channel Detail 和 Player 没有变成根目的地；
- 当前 Episode 存在时，Mini Player 位于内容与底部导航之间；
- 页面使用深色背景、绿色选中态和 Comfortaa 大标题；
- Episode Card 保留展开动作区和三种上下文动作；
- 空状态保留通向 Discover 或 OPML Import 的出口；
- 页面状态在根导航和页内 Tab 之间保持。

## 源码索引

- 产品根结构：[`lib/main.dart`](lib/main.dart)
- 旧版颜色与字体：[`lib/styles.dart`](lib/styles.dart)
- 共享 App Bar：[`lib/widgets/appbar.dart`](lib/widgets/appbar.dart)
- Podcast 首屏：[`lib/pages/podcasts.dart`](lib/pages/podcasts.dart)
- Inbox：[`lib/pages/feeds.dart`](lib/pages/feeds.dart)
- Subscriptions：[`lib/pages/subscriptions.dart`](lib/pages/subscriptions.dart)
- Episode 与 Subscription 卡片：[`lib/widgets/card.dart`](lib/widgets/card.dart)
- Mini Player 与底部导航：[`lib/widgets/bottom_nav_bar.dart`](lib/widgets/bottom_nav_bar.dart)
- 播放图标状态：[`lib/widgets/play_icon.dart`](lib/widgets/play_icon.dart)
