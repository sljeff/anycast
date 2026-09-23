# 回归测试方案（迁移安全网）

> Anycast Flutter → iOS 原生迁移的行为等价性验证方案。
> 配套事实来源：《01-baseline-data.md》（数据）、《02-baseline-api-auth-payment.md》（契约）、《03-baseline-ui-interaction.md》（交互）、《04-baseline-audio.md》（音频）。
> 核心立场：**现网 Flutter 版是唯一参考实现（golden reference）。原生版的验收标准不是"好用"，而是"等价 + 显式声明的增强"。**

---

## 0. 等价性定义（什么算"一致"）

### 0.1 必须严格等价（MUST，任何一条不过即阻断发布）

| 维度 | 定义 |
|---|---|
| **数据不丢** | 同 bundle id 覆盖安装后：订阅、播放列表与顺序、播放进度、历史、转写字幕、翻译、设置、已下载音频、登录态、RevenueCat 订阅身份全部无损，且语义（排序/去重/单位/默认值）与旧版一致 |
| **契约不变** | 对 anycast.website 后端与第三方 RSS 源的请求行为不变：端点、方法、参数、认证头、body 结构、超时、重试、轮询节奏、错误码分支处理 |
| **业务规则同构** | 队列语义（episodes[0] 即当前曲、播完即删、跨列表唯一）、去重规则（enclosureUrl/title/rssFeedUrl）、裁剪规则（上限+每分钟）、缓存规则（LRU 个数 10/30 天/1 天未触碰）一致 |
| **付费状态延续** | 同一 Firebase uid ↔ RevenueCat appUserID 对应关系不变；已订阅用户升级后权益立即可见；不产生重复扣费 |

### 0.2 允许近似等价（SHOULD，记录偏差即可）

- UI 像素级渲染（原生字体渲染与 Flutter 必然不同）、动画曲线细节（时长/缓动近似即可）、过渡效果。
- 系统组件差异：原生 sheet 的橡皮筋效果、键盘行为、复制粘贴菜单等系统默认行为。
- **已定稿的视觉适配边界见《07》§1（A1–A9）**：底栏/sheet 把手/下拉刷新/开关/滑条/选择器/弹窗等采用系统样式——该清单内的差异**不作为回归缺陷**，其余区域仍按原设计对照。
- 性能更好（启动更快、更流畅）总是允许的。

### 0.3 显式增强（MAY，必须先登记再实现）

- 修复旧版已知 bug（见 §11 决策表，默认只修"崩溃类"）；
- 新增能力（CarPlay、播放错误提示、缓存上限设置 UI 等）——不得改变 §0.1 的等价性。

---

## 1. 测试资产建设（"真实使用过的内容"从哪来）

**原则：测试数据必须来自真实世界，而不是开发者现编。** 以下资产在动手写原生代码之前建成，全部进 git（敏感数据脱敏后）。

### 1.1 真实数据库样本（最重要）

**采集规程**：
1. 在一台真实 iPhone 上用现网版本正常使用数日（或直接用作者本人的主力数据）；
2. **采集方式（重要，避免 M0 卡住）**：Xcode 的 Download/Replace Container 通常仅对 **development 签名（get-task-allow）** 的 build 可用，对 App Store / TestFlight 分发版大概率不可用——动手前先在真机验证一次。可行路径按优先级：
   a. **加密备份提取**：Finder 加密备份设备 → 用 iMazing / iPhone Backup Extractor 从备份中提取该 App 的 Documents/Library/tmp（可拿到现网 App Store 版的真实数据）；
   b. **dev-sign 构建 + Replace Container**：从现网版本的 git tag 自编译 dev 签名 build（同 bundle id）装到测试设备，把 a 提取的真实数据经 Xcode Replace Container 灌入（dev 版不能直接覆盖安装到 App Store 版上，删除原 App 前务必确认备份已留存）；
   c. 兜底：dev-sign 版直接正常使用数日，产生语义等价数据；
3. 解包取出：
   - `Documents/anycast.db`（主库）
   - `Library/Application Support/anycast_episode.db`（音频缓存元库）
   - `tmp/anycast_episode/`（音频文件样本，每个样本只保留前 3 个文件以控制仓库体积）
4. 按下表分桶保存到 `test/fixtures/db/`：

| 样本名 | 构造要求 | 覆盖的分支 |
|---|---|---|
| `db_light` | <5 订阅、播放列表 ≤3 集、无字幕 | 新用户/轻用户 |
| `db_heavy` | ≥30 订阅、feed 满额 300、历史满额 300、播放列表 50+ 集、≥10 条字幕+翻译 | 重度用户、上限裁剪、大数据量 |
| `db_dirty` | 手工注入脏数据：NULL duration、NULL pubDate、超长 description（>100KB HTML）、emoji/CJK/RTL 文本标题、空字符串字段 | 边界与脏数据 |
| `db_v3` | 用 SQLite 工具把 `PRAGMA user_version` 改回 3 并删掉 `continuousPlaying` 列 | 老版本升级路径（v3→v4） |
| `db_crashed` | 复制 `db_heavy` 并放入手工构造的非空 `-journal` 文件 | 异常退出恢复 |
| `db_corrupt` | 主库文件本身损坏：截断的 SQLite / 非 SQLite 字节 / 半截写入 | 升级安装路径上的低概率真实场景（兜底见 K25） |
| `db_edge_subs` | 同名不同 rssFeedUrl 的两个订阅（title 撞车）；同一集出现在两个列表的尝试残留 | UNIQUE 语义 |

**脱敏原则**：库内无用户隐私（订阅/播放数据），但如样本取自其他用户设备，需确认授权并删除 `Documents/anycast_subscriptions.xml` 等导出残留。

### 1.2 RSS 源语料库（离线快照，供 RSS 解析回归）

从 `db_heavy` 的 `subscription.rssFeedUrl` 取全部真实源，逐一 `curl -sS -D headers.txt -o <name>.xml` 存档（含响应头），放入 `test/fixtures/rss/`。**必含的分桶**（真实源不足时手工构造，构造时以真实源为模板只改关键属性）：

| 分桶 | 要求 | 覆盖的分支 |
|---|---|---|
| `standard` | 正常 iTunes 兼容 RSS，≥50 items | 主路径 |
| `http_plain` | `http://` 明文源（真实存在不少） | ATS/明文 |
| `missing_fields` | 缺 `itunes:duration` / 缺 `itunes:image` / 缺 `pubDate` / 缺 `itunes:author` | NULL 容忍（rss_fetcher.dart:112-131 实际会崩，见 §11） |
| `giant` | ≥1000 items 或单条 description >1MB | 大解析、isolate/后台线程 |
| `malformed` | 截断的 XML、非 XML 内容（HTML 报错页）、BOM 开头 | 解析失败分支 |
| `redirect` | 301/302 跳转源、跳转到 https | 重定向 |
| `ua_sensitive` | 对无/陌生 UA 返回 403 的源（用 3 种 UA 各存一份结果：浏览器 UA、`Dart/3.x`、无 UA） | UA 策略验证（02 §6.3 红线） |
| `weird_dates` | pubDate 用 RFC822 旧格式/时区缩写/未来时间 | 日期解析 |

### 1.3 API 响应语料（fixture，供契约回放）

对 02 文档的每个端点录制真实响应（可用 Proxyman/Charles 抓现网版流量，或在后端侧导出；无法录制时按 02 的字段说明手工构造），放入 `test/fixtures/api/`。每个端点都要有**成功 + 全部错误分支**：

| 端点 | 必备分支 |
|---|---|
| `GET /api/user` | 正常（plus=0/1 各一、expired_at null/有值）、401、`remaining=0`、JSON 解析失败体 |
| `GET /api/search/channels` | 正常、空 `channel_list`、无结果、**网络失败（触发旧版 response! 崩溃的路径，§11）** |
| `GET /api/search/episodes` | 同上 + `release_date` 多种格式 |
| `GET /api/categories` | 正常、空列表、异常（旧版卡 spinner） |
| `GET /api/top-channels` | 正常、**`data: null`**（02 §1.2 显式分支）、country=49 国任一 |
| `POST /api/subtitles` | processing 帧 ×3（间隔 15s 的真实节奏）、succeeded（英文）、succeeded（含特殊字符/长句 segments）、failed、403（配额尽）、403（`{"error":..,"code":2}` 会话失效）、500、超时、**本地已有 succeeded 但存储文本为空/'null' 的"自愈"重触发**（删本地记录置回 processing 再 POST，pages/player.dart:610-624，K28） |
| `POST /api/subtitles/translate` | 正常（11 种语言至少 3 种）、`translation: null`、慢响应（>10s，旧版无超时的行为） |
| `POST /api/subtitles/chat` | 正常短回复、正常长回复（接近 10s）、非 2xx（body 显示为 AI 消息的行为）、多轮 history |
| `POST /api/shortlink` | 正常、`status!=200`、超时（3s）、连续失败（降级长链） |
| `DELETE /api/user` | 200、非 200 |

### 1.4 音频语料

`test/fixtures/audio/`（真实播客音频，取版权宽松或自有内容）：

| 样本 | 用途 |
|---|---|
| 极短（<10s） | 播完即删队列的快速验证 |
| 中长（30-60min，典型播客） | 主路径、2s 进度落盘 |
| 超长（>2h） | 进度恢复、缓存上限 |
| 含长静音段 | skip silence 开关行为（预期无变化） |
| VBR mp3 / 不同码率 / aac | AVPlayer 兼容性、时长报告准确性 |
| 不支持 Range 的服务器（可用本地 python http server 模拟） | 流播/缓存行为 |
| 404 / 500 / Content-Type 异常的 URL | 错误路径（旧版无提示，见 §11 决策） |

### 1.5 Golden 导出器（双实现对拍的基础设施）★

**在 Flutter 仓库新建 `tool/golden_export.dart`**（Dart CLI 脚本）：输入上面全部 fixtures，跑现有 Dart 实现的纯逻辑函数，把期望输出写成 JSON golden 文件到 `test/golden/`。**原生 Swift 测试直接加载这些 golden 断言**。这样"对拍"的期望值永远来自旧版真实实现，而不是人手写第二遍。

需要导出的 golden（每个 = 一组输入 → 期望输出）：

| # | 逻辑 | Dart 源 | golden 内容 |
|---|---|---|---|
| G1 | playlist position 插入/重排 | models/playlist_episode.dart:90-135 | **仅插入场景**逐字节复刻旧算法。两个序列：①连续插头部 200 次（头部插入间距恒 0.0015、**永不触发重排**——2026-09-22 导出实测裁定，原表述"触发重排的饱和序列"不成立）；②中点饱和序列（预置 2 条后连续 index=1 插入，间距逐次减半，第 3 次中插 <0.0005 触发 `_reorder` 重排为整数列）。**移动场景不导出旧算法 golden**，单独按 K26 修复语义断言——旧算法对已存在条目用移动前的 DB 列表取邻居，下移换序的中点落回旧位置、重启后回退（08 §12.1-1） |
| G2 | `insertOrUpdateByIndex` | 同上 | index 越界/0/末尾（同样只按插入场景导出 golden） |
| G3 | `toLrc()` / `formatLrcTime` | models/subtitle.dart:101-116、formatters.dart:180-185 | 多语言字幕 → LRC 文本逐字节（含 `[mm:ss.mmm]` 毫秒位） |
| G4 | 导出字幕全文格式 | pages/player.dart:950-978 | `# 标题 - 频道\n\n---\n\n` + 主 LRC + `--- Translation ---` 段拼接结果 |
| G5 | `htmlToText` / `sanitizeHtml` 后为空的回退 / `renderHtml` 的 `startsWith('<')` 判定 | utils/formatters.dart:80-110、rss_fetcher.dart:159-179 | 每条 RSS description 的输出文本 |
| G6 | OPML 解析 | pages/feeds.dart:269-300 | 每个 fixture OPML → `[{xmlUrl,title}]` 列表（嵌套 outline、缺 title 回退 text、缺 xmlUrl 跳过） |
| G7 | RSS 字段映射 | utils/rss_fetcher.dart:75-179 | 每条 fixture RSS → episode/channel 结构（duration 字符串→毫秒、pubDate→毫秒、categories 逗号拼接、onlyFirstEpisode、按 pubDate 倒序） |
| G8 | `saveNewEpisodes` 合并语义 | pages/feeds.dart:321-357 | 本地 lastUpdated vs RSS 最新 pubDate 的 3 分支（本地赢/线上赢/首次） |
| G9 | settings 编解码 | models/settings.dart | `autoSleepTimer` CSV ↔ 值、speed 档位集合、11 语言列表、49 国列表、**autoRefreshInterval=300 口径**（《01》§2 竞态裁定）、**locale 推导 fixture**（Dart `Platform.localeName` 下划线格式 `zh_Hans_CN` ↔ iOS `Locale.preferredLanguages` 连字符格式 `zh-Hans-CN`；取首段=语言、末段=国家的拆分规则写死为 fixture，确保新装默认国家一致） |
| G10 | 时间/时长格式化 | utils/formatters.dart | `getPlayedAndTotalTime`（含 NULL duration）、timeago `en_short`、`M-d / y-M-d` 日期 |
| G11 | `User.fromJson` | api/user.dart:17-31 | `expired_at` 各格式、null |
| G12 | 短链请求参数 | api/share.dart:12-53 | `key = md5(url)` 的十六进制小写字符串、body JSON 结构 |
| G13 | 聊天 history 数组构造 | states/chat.dart:26-35 | N 轮对话 → `[{human:..},{ai:..}]`。**实测裁定（2026-09-22，golden 已按实际行为导出）**：InMemoryChatController.insertMessage 是**尾部追加**（新消息在列表末尾），而构造循环取的是列表**前 10 条再倒序**——总条数 ≤10 时恰为最近 10 条、末元素即当前这条 user_input 的重复（sendMessage 先 insertMessage 再构造）；**总条数 >10 时发送的是最旧 10 条、当前输入不在内**（旧版实际行为，原生按 golden 复刻、不得"修复"）（单键 map、倒序恢复正序） |
| G14 | `getTextSafeColor` | utils/formatters.dart:139-153 | 一组颜色 → 判定结果（luminance<0.2 阈值附近取值）。**2026-09-22 增补**：该函数被基线之后的视觉刷新 PR（未发布）从 Flutter 线删除——golden 锁定 1.2.1+38 已发布行为，导出器已 vendor 旧实现，原生仍须实现（歌词取色用途） |
| G15 | DB 规范化 dump | — | 对 §1.1 每个样本库输出"规范化行集合"（按表、按稳定排序、字段逐个），供原生读取后对拍 |
| G16 | 搜索结果 trim | api/podcasts.dart:26-43 | 带首尾空白的 title/description/author → trim 后值 |

**运行环境（实现路径，避免 M0 第一天踩坑）**：`tool/golden_export.dart` **不能用 `dart run` 直接跑**——`lib/models/*` 传递依赖 sqflite → flutter → dart:ui，纯 Dart VM 编译不过。定为：导出器写成 **flutter test 环境里的测试文件**（如 `test/golden/export_golden_test.dart`；`flutter test` 下 dart:io 文件读写可用、导出全程无网络需求）；G15 需要打开真实 SQLite fixture 的部分用 **sqflite_common_ffi** 在测试 VM 里跑真 SQLite 读文件。后续若想脱离 flutter test 再抽纯 Dart 模块，非必需。

### 1.6 资产目录结构（约定）

```
test/
  fixtures/
    db/            # anycast.db 样本 + 元数据库样本
    rss/           # RSS 原始 XML + 响应头
    api/           # API 响应 JSON（按端点+分支命名）
    audio/         # 音频样本（LFS 或外部脚本下载）
    opml/          # 真实导出的 OPML（App 内 Export + Overcast/小宇宙导出各一）
    images/        # 封面图样本（取色对拍用）
  golden/          # golden_export.dart 的输出，进 git
tool/golden_export.dart
```

---

## 2. L0 数据兼容与迁移测试（自动化，最高优先级）

**被测对象**：原生版的"旧数据读取 + 迁移"模块。工具：GRDB/raw SQLite + Swift Testing。

### 2.1 读取矩阵（每个格子一条测试用例）

| 输入 | × 状态 | 断言 |
|---|---|---|
| `db_light` / `db_heavy` / `db_dirty` | tmp 有音频 + 元 DB 齐全 | ① 打开成功，`user_version=4`；② 每张表行数与 G15 golden 一致；③ 字段值逐一相等（注意：毫秒 INTEGER、bool 0/1、position REAL、JSON TEXT 列解析成结构体后与 golden 相等）；④ playlist 按 position ASC、feed 按 pubDate DESC、history 按 **id DESC**、subscription 按 **title ASC 且 SQLite BINARY collation**（大写 < 小写 < 非 ASCII，subscription.dart:78——2026-09-22 增补：原生**不得**顺手用 localized/大小写不敏感排序，那是用户可见的列表顺序差异）；⑤ settings 各字段类型正确（CSV/枚举集合成员校验） |
| 同上 | tmp 空（模拟系统清理）+ 元 DB 还在 | 容忍：下载状态显示为未下载，不崩溃，孤儿元 DB 记录被清理或忽略 |
| 同上 | 元 DB 不在 + tmp 有文件 | 容忍：无法映射的文件视为不存在（可清理） |
| `db_v3` | — | 迁移到 v4：`continuousPlaying` 默认 1；其余数据不变 |
| `db_crashed` | 非空 `-journal` | SQLite 自动恢复后打开成功，数据一致（不为崩溃损失额外数据） |
| `db_corrupt` | 主库字节损坏 | **兜底增强（K25）**：隔离坏库（改名保留 `.corrupt`）+ 重建默认新库 + Sentry 上报，**不得 crash loop**（旧版 openDatabase 抛异常同样起不来，此项为显式增强；隔离仅由确定性损坏信号触发，见 K25 触发条件） |
| 空目录（全新安装） | — | 建库/默认行为与旧版全新安装一致：playlist 默认行 (1,'Default',1)、player 默认行 (1,NULL)、settings 默认行（countryCode/targetLanguage 来自系统 locale 的推导规则一致，含 iOS 连字符格式 fixture——见 G9；darkMode=0, speed=1.0, skipSilence=0, autoSleepTimer='0,0,0', maxCacheCount=10, autoRefreshInterval=300（《01》§2 口径裁定）, max=100/100, continuousPlaying=1） |

### 2.2 语义陷阱专项（每条一测，来自 01 §9 坑位清单）

- [ ] 所有时间字段按 **Unix 毫秒** 解析（不是秒！不是 ISO 字符串！）
- [ ] bool 为 INTEGER 0/1（不是 0/1 之外的 truthy 判断）
- [ ] `subtitle.subtitle` / `translation.translation` 的 JSON 数组：`start/end` 为 **double 秒**（含小数）
- [ ] `settings.autoSleepTimer` 为 `"a,b,c"` CSV，b/c 是**索引**不是值（索引→{OFF,10,20,30,40,50,60}）
- [ ] `translation` 表存在 `sqlite_sequence` 行，读取不得报错
- [ ] `subtitle.summary` 恒 NULL，读取不得当错误
- [ ] 各表大量列可 NULL（description/pubDate/duration/author/email/lastUpdated…）
- [ ] 历史表"最新"语义 = `ORDER BY id DESC`（**不是** pubDate）
- [ ] `playlistEpisode.enclosureUrl` 全表 UNIQUE：同一集不能加入第二个列表（现网实际行为：`getByEnclosureUrl` 全表查到后 `update` **不改 playlistId**——行留在旧列表、position 却按目标列表序被污染；2026-09-23 勘误，原生按 K14 新裁定 = 移动到新列表）
- [ ] `subscription` title UNIQUE：导入同名频道会**整行替换旧订阅（id 改变）**
- [ ] 翻译语言切换覆盖旧翻译（UNIQUE enclosureUrl）

### 2.3 写回与后续行为（迁移后的读写闭环）

- [ ] 迁移后播放一集：`playedDuration` 正确 UPDATE 到**队首**那一行（按 enclosureUrl 定位）
- [ ] 播完一首：队首行 + 其 subtitle/translation 行 + 缓存文件/元 DB 行**全部删除**（连带删除语义）
- [ ] 收件箱/历史 60s 裁剪到 max 值；裁剪后行数精确，且**保留侧行正确**：feed 留 pubDate 最新的 N 条、history 留 id 最新的 N 条（`removeOld` 按列表序保留前 N、删除其余 enclosureUrl，states/feed_episode.dart:134-148、states/history.dart:54-68——2026-09-22 增补保留侧断言）
- [ ] 新写入的行 id 分配不与旧数据冲突（非 AUTOINCREMENT 表 insert 顺序 max(id)+1）
- [ ] 暂停→继续（resume）→ 历史行重插但 **id 不变、排序位置不变**（`HistoryEpisodeModel.fromMap(playlistEpisode.toMap())` 带入 playlist 行 id，delete+INSERT(显式 id, REPLACE) 原样保留；原表述"移顶、id 改变"系勘误，2026-09-23 sqflite 实测确认，states/player.dart:243/280 + models/history_episode.dart:70-77，K30）
- [ ] 队列播空（`clear()` 删 player 行）后重启 → 缺行视为"无播放状态"，不抛错（旧版 `PlayerModel.get` 对空结果 `maps[0]` 抛错导致恢复链断裂，models/player.dart:49-55，K31 修复）

### 2.4 写回兼容（回滚安全网，已定稿：首版只读兼容 + 相同 schema 写入，见 §11 战略决策）

若要求保留"原生版写坏后能用 Flutter 版回滚救数据"的能力：原生版**不得改 schema、不得启用 WAL**、新增数据必须放在旧 schema 能容纳的形式。首版原生**只读兼容 + 相同 schema 写入**，任何 schema 演进放到原生版稳定后的第二版。

**覆盖两个库，不只是主库（2026-09-22 增补）**：
- `Documents/anycast.db`：同 schema（user_version=4、9 张表）+ 不启用 WAL；
- `Library/Application Support/anycast_episode.db`（缓存元数据库，cacheObject 表 **v3 schema**）：**同 schema + 同语义写入**——`touched` 在访问时更新的口径、`validTill` 的计算口径、新下载文件名沿用 **UUIDv1 + mime 扩展名约定**（audio/mpeg→.mp3 等，含"换扩展名删旧文件"行为，《01》§4）都不得改；原生若改 schema 或字段语义，回滚 Flutter 后缓存索引错位、已下载音频全部"丢失"（文件在、索引不认，只能重新下载）。LRU 裁决参数（个数 10 / 30 天 stale / 仅删 >1 天未触碰 / 清理最短间隔 10s / 单轮限 100 行）照 fork 语义复刻。

### 2.5 升级安装实测（半自动，真机，每个里程碑跑一轮）

**这是唯一无法纯自动化的数据测试**，规程：
1. 装 **dev 签名**的现网 Flutter 版（TestFlight/App Store 分发版无法 Replace Container，见 §1.1 采集规程）→ 把 `db_heavy` 数据经 Xcode **Replace Container** 灌入；
2. 登录真实 Google 账号（有 Plus 的测试账号）；
3. 覆盖安装原生 TF build（同 bundle id，更高 build 号）；
4. 逐项核对：启动不崩、订阅列表完整、播放列表顺序正确、当前曲与进度正确（误差 ≤2s）、字幕/翻译在、设置在、下载状态在、**无需重新登录**（Keychain 继承）、登录页显示 Plus 与 remaining 正确（RevenueCat uid 延续）；
5. 再播 5 分钟 → 覆盖安装下一个 build → 进度仍正确（原生写回的数据原生能读）；
6. **回滚方向实测（2026-09-22 增补，至少 M4 跑一轮）**：原生版播放/下载/改设置产生写入后，覆盖安装 **dev 签名 Flutter 版**（更高 build 号）→ 断言：订阅/列表/进度/设置可读（主库回滚），**已下载音频仍被缓存索引识别、可离线播放**（元数据库回滚，§2.4）。

---

## 3. L1 纯逻辑对拍测试（自动化，Swift Testing + golden）

对 §1.5 的 G1–G16 逐条实现 Swift 侧测试：加载 `fixtures` + `golden`，调用原生对应模块，断言相等。**这层测试可以（也应该）在原生 UI 还没写时就开始跑**——它是迁移的第一块基石。

补充说明几个容易漏的断言细节：
- G3/G4：LRC 文本要**逐字节**比较（时间戳毫秒位、行尾、`--- Translation ---` 分隔）。
- G7：`itunes:duration` 有两种合法形式（`HH:MM:SS` 与纯秒数），两种都要在 fixtures 里。
- G9：speed 的 7 档值必须精确等于 {0.5,0.75,1.0,1.25,1.5,1.75,2.0}（滑条 divisions 语义）。
- G10：`getPlayedAndTotalTime` 在 duration=NULL 时的表现（旧版行为是什么就断言什么）。
- G12：md5 输出为 32 位小写 hex。
- G14：取色对拍单独做——用同一批封面图（§1.6 images/），旧版 palette_generator 的 dominantColor 输出导出为 golden，原生用 CoreImage 实现，断言 **ΔE < 阈值**（建议 CIEDE2000 < 10，肉眼不可分），不做精确相等。

---

## 4. L2 API 契约测试（自动化）

**被测对象**：原生网络层。工具：URLProtocol 注入回放 §1.3 fixtures（或 mattt/Replay 录制回放）。

### 4.1 请求形态断言（发出方）

对每个端点构造调用，拦截请求，断言：

| 断言项 | 期望（来自 02） |
|---|---|
| 方法与路径 | 逐字符一致（如 `POST https://anycast.website/api/subtitles`） |
| Authorization | `Bearer <token>`；仅 4 个需认证端点有；翻译/短链/搜索/分类/趋势**无** |
| Content-Type | **仅 body 非空时** `application/json`；GET/DELETE 不带 |
| body JSON | 字段名精确（`enclosure_url` 下划线风格、`user_input`、`history` 单键结构、`cmd/password/key`） |
| 超时 | reqWithAuth 系 10s；shortlink 3s；categories/top-channels 无超时（原生若加，不得小于旧值语义——见 §11 决策） |
| 重试 | 仅 SocketException/Timeout 等价错误重试；总尝试 2 次（shortlink 3 次）；**HTTP 429/5xx 一律不重试** |
| 轮询节奏 | 转写 15s ±1s、翻译 10s ±1s（不得更快） |
| 并发度 | RSS 批量抓取每批 8 并发 |
| 429 处理 | 等同其他非 2xx（弹错误），无退避（除非决策表改变） |

### 4.2 响应处理断言（接收方）

- 每个错误分支 fixture → 断言状态流转与 UI 信号（如 403 `code==2` → 登录页信号；非 2xx → 错误弹窗信号带原始 body）。
- `data: null`（top-channels）→ 空列表而非错误。
- chat 非 2xx → body 文本进入 AI 消息流（或按决策表改为错误提示）。
- shortlink 失败 → **自动降级长链**，分享面板仍弹出。
- `GET /api/user` 401 → 登录页 + 返回 nil（不崩溃、不清数据）。
- 401 在任意带认证端点同样走登录页：`ErrorHandler.handle` 对 subtitles/chat 的非 2xx 若为 401 也会弹登录 sheet（error_handler.dart:15-21，《02》§1.3 更正）；后台轮询路径的错误处理按 K27 静默（仅 401 仍走登录页）。

### 4.3 UA 策略（已定稿）

旧版 UA 是 `Dart/x.y (dart:io)`，原生会变成 URLSession 默认 UA。**后端源码已核实（《02》§7）：入站无任何 UA 过滤**，且后端自己的出站抓取也硬编码 Chrome UA（印证外部源对 UA 敏感）。结论：自家 API 直接用原生 UA，无需影子验证；**RSS 直抓固定一个通用浏览器 UA**（优于旧版裸 Dart UA）。残余风险仅 Cloudflare 边缘规则（如有），灰度期通过 Sentry 的 API 错误率观察即可。

---

## 5. L3 播放器行为测试（单元 + 半自动）

### 5.1 播放状态机（可单元化的部分，用本地音频 fixture + 注入 AVPlayer 替身）

| 用例 | 期望（来自 04） |
|---|---|
| 缓存命中装载 | 播本地文件 + `initialPosition=playedDuration`；同时不再重复下载 |
| 缓存未命中装载 | 播 URL + **并行**整文件下载；进度回调进入 UI |
| 播完一集 | 队首删除（连带字幕/翻译/缓存）→ 播下一集；`continuousPlaying=off` → 暂停 |
| 队列播空 | pause + clear（player 表 id=1 行删除） |
| seek 边界 | 两条路径分别断言：全屏 −10s/+30s 走 `seekByRelative`（clamp 到 [0,duration]；`duration!` 为空即崩的旧缺陷按 K4 崩溃族修复）；mini player +30s 走 `seekAndPlayByEpisode`（**先 pause 再 seek 再 play、无 clamp**、目标取自暂停期可能过期的 positionData，audio_handler.dart:96-107，《04》§1.1 更正） |
| 进度落盘 | 播放中每 2s 写库（误差允许 ±500ms）；pause/退后台**补存一次**（K24 已定增强，进首版；实现上并入 periodic time observer 同一处节流，08 §4.3） |
| 冷启动恢复 | UI 显示 position=playedDuration/duration；不预载音频；点播放才装载 |
| 进度事件过滤 | 旧版过滤四种事件：`!isPlaying || isLoading || position==0 || buffered==0`（player.dart:105-115）——原生保持或不保持都可（UI 表现需一致：起播/暂停/加载中进度不跳变） |

### 5.2 锁屏/控制中心（真机人工 + 部分可 XCUITest 断言 NowPlayingInfo）

- [ ] 锁屏按钮组 = 后退/播放暂停/快进三键，**后退=−10s、快进=+10s**（怪癖复刻，除非决策表改变）
- [ ] 无上一集/下一集命令
- [ ] 进度条可拖动 = seek
- [ ] NowPlayingInfo：title=集标题、album=频道名、duration=RSS 时长、artwork=封面、rate=倍速
- [ ] 倍速 1.5x 时锁屏进度推进速度正确
- [ ] artwork 弱网时无图不崩溃（旧版即如此）

### 5.3 系统事件矩阵（真机人工，每版本全跑一遍）

| 事件 | 旧版行为（基线） | 原生预期 |
|---|---|---|
| 来电（蜂窝） | 系统暂停音频 | 同；挂断后**手动**恢复（旧版无自动恢复） |
| FaceTime/微信语音 | 同上 | 同 |
| Siri | 音频中断后回 App | 同 |
| 另一音频 App 起播 | 本 App 被压低/暂停 | 同（.playback category 独占语义） |
| **他 App 音频播放中冷启动本 App** | 不影响他 App（会话激活只随起播发生，just_audio 插件行为，《04》§2.4） | 同：启动只 `setCategory(.playback)`、**不 `setActive`**；首次起播前才 `setActive(true)`（K18 会话策略，详见《06》§6） |
| 本 App 暂停（播放中→暂停） | 锁屏 Now Playing 卡片仍在（会话保持激活） | 同：暂停不 deactivate；仅队列播空/stop 时 `setActive(false, .notifyOthersOnDeactivation)` |
| 拔耳机/断蓝牙 | 旧版：插件默认（多数情况暂停） | **建议**显式 routeChange 监听暂停（增强，登记） |
| 锁屏 30 分钟+ | 持续播放（UIBackgroundModes=audio） | 同 |
| 后台超过 1 小时 | 持续 | 同 |
| 音频服务重置（罕见） | 未知 | 至少不崩溃 |
| AirPods 单耳切换/设备切换 | 默认 | 同 |

### 5.4 网络与错误（真机，弱网模拟：Network Link Conditioner）

| 场景 | 旧版行为 | 原生预期 |
|---|---|---|
| 起播时断网 | 无限 buffering（loading 动画常驻），无提示 | 等价（或按决策表加提示，登记增强） |
| 播放中断网 | buffering 常驻；恢复网络后**不会自动续上**（just_audio 行为） | 等价或增强 |
| 音频 URL 404/失效 | 无限 loading，无提示 | 等价或增强 |
| 缓存命中时断网播放 | 正常离线播放 | 同（核心离线能力） |
| 2G/极慢网 | 长 buffering 后可播 | 不差于旧版 |

### 5.5 下载与缓存

- [ ] 手动下载：进度环 0→1（`CircularPercentIndicator` 等价视觉）、完成变绿勾
- [ ] 播放一集 = 顺带整集缓存（播放列表卡显示已下载）
- [ ] 缓存上限 10 个：下载第 11 个时最旧（且 >1 天未触碰）的被删——**语义按个数不按字节**
- [ ] 30 天 stale 清理
- [ ] 删除列表条目连带删缓存文件 + 元 DB 行
- [ ] 下载中删除条目：取消下载（旧版不支持取消，删除即停）——原生可用 cancel，行为不差于旧版
- [ ] 升级后（§2.5 场景）旧下载的音频能离线播放

### 5.6 倍速/睡眠定时/skip silence

- [ ] 7 档倍速切换即时生效且音调保持（`audioTimePitchAlgorithm` 语音优化）；持久化、下次启动恢复
- [ ] COUNTDOWN 滑条 7 档（OFF/10/20/30/40/50/60）；**仅播放中递减**；暂停不减；到 0 → pause
- [ ] skip silence：开关已移除（决策 K2），但 `settings.skipSilence` 字段仍兼容读取（有值不报错、不显示、不写入）
- [ ] autoSleepTimer 设置字段读写兼容（功能本身是死代码，保留字段不激活）

---

## 6. L4 UI 回归（快照 + XCUITest + 人工）

### 6.1 屏幕快照基线（swift-snapshot-testing）

屏幕清单（来自 03，按页面 × 状态组织；每屏在 iPhone 标准 + 小屏（SE 类）两尺寸截取）：

| # | 屏幕 | 必备状态 |
|---|---|---|
| S1 | Inbox 有数据 / 空态（ImportBlock） | 两种 |
| S2 | Inbox 卡片展开态（3 按钮） | |
| S3 | Subscriptions 列表 / 空态 | |
| S4 | Channel 展开头 / 折叠头（滚动后）/ 订阅按钮三态 | 三种 |
| S5 | Detail sheet（0.7 高） | |
| S6 | 播放列表（含进度背景条卡、下载三态） | |
| S7 | 历史弹窗 / 空 | |
| S8 | Discover 分类 Tab / Network Error / loading | |
| S9 | SearchPage：Channels 有/无结果、Episodes 有/无结果、已加列表态 | |
| S10 | mini player（播放中/暂停） | |
| S11 | 播放器第 0 页（Settings：HTML 描述长/短、SPEED/COUNTDOWN/Switch；skip silence 开关已按决策 K2 移除，只剩 Continuous Play 一个开关） | |
| S12 | 播放器第 1 页（主控：默认/palette 深色封面/长标题跑马灯帧） | |
| S13 | 播放器第 2 页五态：未生成/processing/failed/翻译中/就绪（双语歌词） | 五种 |
| S14 | 歌词拖动横条帧 | |
| S15 | ChatPage（用户消息+AI 回复+占位"..."） | |
| S16 | SettingsPage 全页（翻译开/关两种） | |
| S17 | LoginPage：未登录/已登录 Basic/已登录 Plus | |
| S18 | EmailLogin | |
| S19 | ImportExport 对话框 / ImportInstructions | |
| S20 | 401 登录 sheet、错误弹窗（Error code + body） | |
| S21 | 付费墙（月/年选中态、Carousel） | |

快照注意（来自技术调研）：Liquid Glass/毛玻璃区域不做像素断言改布局断言；基准图按 OS 版本分目录（iOS 18/26/27）；**每轮对照时同 OS 同设备录旧版 Flutter 截图一张并排存档供人工比对**（不做像素 diff，做"结构对照"）。

### 6.2 XCUITest 冒烟（每次 CI/提交跑，目标 <10 分钟）

1. 冷启动 → 三 Tab 切换 → 各滑动列表
2. 搜索 → 进 Channel → 订阅 → Inbox 出现 → 播放 → mini player 出现 → 打开全屏播放器 → 三页横滑 → 倍速改 1.5 → 返回
3. 播放列表：加一集 → 拖拽换序（长按 150ms 起拖）→ 删除
4. 设置：改国家/语言/上限 → 杀进程重启 → 断言设置保持
5. 转写按钮状态流转（用 mock API 回放 processing→succeeded）
6. 登录页打开（sandbox UI 不点穿）

### 6.3 人工手势与动效清单（分配给用户的主体工作）

> 方法：**双设备/双 build 并排对照**——设备 A 装 Flutter 版，设备 B 装原生版，同一份数据（§2.5 灌数据法各灌一份），逐条操作对比。每条带 checkbox，记录"一致/近似/不一致+描述"。
> 完整手势事实在《03》§3，此处为可执行的验收单（P0=必须逐条过，P1=尽量过）。

**导航与容器（P0）**
- [ ] 三 Tab 切换保持各 Tab 滚动位置（IndexedStack 等价）
- [ ] Tab0 二级 Tab（Inbox/Subscriptions）横滑
- [ ] **再次点击 Tab0**：列表不在顶部 → 平滑回顶；已在顶部 → 触发刷新（进度条出现）
- [ ] 所有全屏 sheet 上滑打开、下拉关闭（**关闭阈值采用系统默认**——《07》A3 适配，不再复刻 90% 粘性）；把手区点击可关（仅 Detail/SearchPage，经 header 区 tap 实现——《07》A2，系统把手本身不可点）
- [ ] sheet 套 sheet：播放器→频道→频道内搜索，层层可开可回，状态不串
- [ ] 竖屏锁定（iPad 上也允许竖屏两个方向）

**卡片与列表（P0）**
- [ ] 整卡点按展开按钮条（200ms，高 60），同列表互斥，再点收起
- [ ] 封面点按开 Detail（0.7 高 sheet，内滚联动缩放 0.7→0.6）
- [ ] Detail 内点频道名：关当前开 Channel
- [ ] Inbox 三按钮：播放（加顶+移出收件箱+开播）、加列表（**飞入动画 600ms** 后加入+移出）、移除
- [ ] 加列表飞入动画的起点/终点/缩小/淡出节奏（4 个触发点：Inbox/Channel/ChannelSearch/Search）

**播放列表拖拽（P0，最高风险手势）**
- [ ] 长按 ~150ms 后整卡可拖（无把手提示）
- [ ] 拖起时卡片放大到 1.1x，其余列表正常
- [ ] 拖动中展开条自动收起
- [ ] 拖到顶部替换当前曲：先暂停 ~100ms 再无缝换源播放
- [ ] 当前曲拖走：同上无缝切换
- [ ] 普通换序：position 重排正确（快速连续拖 20 次不乱序、不丢集）
- [ ] index==0 的移除按钮：同时停止播放并清 player 状态

**播放器（P0）**
- [ ] mini player：点按开全屏；**任意方向的垂直轻扫也开全屏**（旧版无阈值怪癖）
- [ ] mini player 进度背景条随播放增长；点播放/暂停、+30s 即时生效
- [ ] 全屏三页横滑 + 底部胶囊双向联动（点按钮动画切页 300ms）
- [ ] 关闭播放器后再开：回到第 1 页（主控）
- [ ] 进度条：拖动 seek；时间标签显示**剩余时间**在上方；缓存段可见
- [ ] 倍速滑条 7 档、thumb 内显示数字；COUNTDOWN 同款交互
- [ ] 封面取色渐变背景（深色封面回退绿色文字）
- [ ] 分享按钮：转圈 → 系统分享面板 → 短链正确打开 web 播放页

**歌词（P0）**
- [ ] 逐行滚动跟随、当前行居中高亮放大
- [ ] 点击任意行 = 播放/暂停切换 + 屏幕中央 play/pause 形变动画（200ms，500ms 后消失）
- [ ] 拖动歌词出现时间横条（时间 + 横线 + 播放钮）；点播放钮 seek 到该时间
- [ ] 拖动后**不自动回位跟随**（neverResume）；~3s 后活动行恢复跟随
- [ ] 双语：主行灰/活动绿、译文反色；行距
- [ ] 转写五态视觉（生成按钮/机器人动画/Retry/翻译中/就绪）
- [ ] 导出字幕：分享面板内容 = `# 标题 - 频道` + LRC（+翻译段），.txt

**频道页折叠头（P1，视觉细节多）**
- [ ] 上滑折叠：封面 120→60 左移、标题左移嵌入、次要信息在 1/4 处开始淡出
- [ ] 头部背景 palette 渐变
- [ ] RSS 域名点按复制 + "Copied" snackbar
- [ ] 描述 2 行截断、点开全文弹窗
- [ ] Newest/Oldest 切换 + 指示条动画
- [ ] 订阅三态按钮

**发现/搜索/设置/登录（P1）**
- [ ] Discover 分类横滚 Tab、切换国家后列表刷新
- [ ] 搜索：输入即显 Cancel、提交开 sheet、无结果态、Episodes 已加列表的图标变体
- [ ] 设置各弹窗（国家/语言/三个上限 picker）
- [ ] 登录三入口、付费墙 Carousel 自动轮播、月/年点选、订阅信息卡文案（Basic/Plus、remaining、到期时间）
- [ ] OPML 导入（文件选择器）、导出（分享）、错误弹窗
- [ ] 从系统分享菜单分享 OPML 文件给 App → ShareDialog 出现（Share Extension 重写后）

**动效验收（P1）**
- ~~把手提示动画~~（已按《07》A7 移除，不再验收）
- [ ] 跑马灯：播放器长标题、历史长标题（1s 后开始、循环间隙）
- [ ] 各 Lottie（loading/robot）
- [ ] 展开条/拖拽放大/Tab 回顶等已含在上面的项

---

## 7. 人工回归执行表模板

每次发布候选（RC build）用以下表格记录（放 `docs/migration/rounds/RC-<date>.md`）：

```
| 项 | 结果 | 备注 |
| 环境：iPhone __ (iOS __)，数据样本：db_heavy，账号：test-plus-01
| §6.3 导航与容器 7 条 | ☐☐☐☐☐☐☐ | 
| §6.3 播放列表拖拽 7 条 | |
| ... 
| §5.3 系统事件 10 条 | |
| §5.4 弱网 5 条 | |
| 发现的问题：...
```

---

## 8. 账号与付费回归（TestFlight + Sandbox）

### 8.1 账号矩阵

| 账号 | 状态 |
|---|---|
| `test-anon` | 未登录 |
| `test-free` | Google 登录，免费（remaining=0 与 >0 两种状态） |
| `test-apple` | Apple 登录 |
| `test-email` | Email 登录 |
| `test-plus` | Plus 订阅中（sandbox 月付） |
| `test-expired` | Plus 已过期（sandbox 快速续订验证） |
| `test-plus-refund` | 退款后（RevenueCat 后台操作） |

### 8.2 用例（P0）

- [ ] 未登录：浏览/播放/订阅全可用；转写按钮 → 401 → 登录 sheet 弹出
- [ ] Google/Apple/Email 三登录在原生版完成；登录后 `remaining` 正确显示
- [ ] **升级用户**（§2.5）：旧版已登录 → 原生版启动无需登录，且 `/api/user` 正常（uid 相同）
- [ ] **升级用户 Plus**：登录页直接显示 "Anycast Plus" + 到期时间（RevenueCat 身份延续，不要求重新购买）
- [ ] sandbox 购买：选月付 → 系统购买流程 → entitlement 激活 → remaining 变 50/月口径
- [ ] 购买失败/取消：无错误弹窗（旧版仅 print）或按决策表增强
- [ ] 恢复购买：有订阅 → "Restored purchases"；无 → "No active entitlements"
- [ ] 订阅过期（sandbox 加速）：卡片自动降回 Basic（listener 推送）
- [ ] 退款：entitlement 消失，remaining 恢复免费口径；**不弹额外窗**
- [ ] 登出：本地数据全保留（订阅/列表/历史/设置/缓存），回到未登录 UI；RevenueCat logOut（离线时也成功）
- [ ] 删号：确认弹窗 → 后端删除（已核实会联动删 Firebase 用户 + RevenueCat subscriber + 自家记录，《02》§7）→ 自动登出 → **本地数据仍保留**（旧版行为）
- [ ] 删号后同邮箱重新注册：**新 Firebase uid**，全新 remaining=10（后端 `FREE_USER_REMAINING=10`；注意登录页文案写 3 次，文案与实现不一致，《02》§7——迁移按复刻文案处理）
- [ ] 删号后重装 + 恢复购买：Plus 应恢复（RC 基于收据重建订阅者，绑定新 uid）
- [ ] 403（code=2）→ 登录页；403（其他）→ error 文案弹窗
- [ ] 登录后转写走通全流程（15s 轮询直到 succeeded）

### 8.3 StoreKit/RevenueCat 技术校验（一次性）

- [ ] RevenueCat 后台：升级安装的原生版首次 `logIn(uid)` 后，**同一 customer 记录**（不出现新匿名用户分裂）
- [ ] 同一 Apple ID 在两设备（旧版+原生版）登录同账号：entitlement 同步
- [ ] 价格本地化显示与旧版一致（Offerings 数据一致）

---

## 9. 并发与性能回归

| 用例 | 方法 | 标准 |
|---|---|---|
| 50 订阅全量刷新 | 真机 + `db_heavy`，触发下拉刷新 | 主线程无卡顿（Instruments Hangs / MetricKit hang 数为 0）；总时长不显著差于旧版（8 并发×批） |
| 巨型 OPML 导入（500 源） | §1.6 opml fixture 扩展 | 进度环平滑推进、可完成、无 OOM；导入中 UI 可操作（旧版 isolate 等价） |
| 巨型 RSS 解析（1000 items） | §1.2 giant | 解析在后台线程（Swift 侧 nonisolated/@concurrent），主线程不卡 |
| Inbox/历史 300 条滚动 | 真机 | 60fps、内存稳定（与旧版同数量级） |
| 封面墙快速滚动 | Discover | Kingfisher 等缓存下不闪不涨内存 |
| 冷启动时间 | Instruments App Launch | 不差于旧版 20% 以上 |
| 大 HTML show notes 渲染 | `db_dirty` 的 100KB description | 不卡主线程；渲染不崩溃 |
| 后台播放 1h 掉电 | 真机（可选） | 与旧版同数量级 |

---

## 10. 发布策略与灰度

### 10.1 分支与回滚策略

- **main 分支冻结为 Flutter 维护线**：保持随时可构建、可提审的状态（热修保险）。原生开发在新分支/新目录进行。
- 原生版发布后 4~8 周内不删 Flutter 工程与构建配置——**保留"提审回滚到 Flutter 版"的退路**（App Store 不支持回滚二进制，回滚=再提审旧代码 + 版本号递增）。
- 配合 §2.4 写回兼容策略，保证回滚不丢用户数据。

### 10.2 发布节奏

1. **TestFlight Internal**（≤100 人，含作者本人 + 若干真实重度用户志愿者）：跑完 §6.3 全部 P0 + §5.3/5.4 + §8 全部，至少 1 周；
2. **Phased Release 7 天**（App Store 分阶段放量 1/2/5/10/20/50/100%）：
   - 每日看 Sentry：崩溃率、`/api/subtitles` 与 `/api/user` 错误率、卡顿率（hang）——与 Flutter 版最后 30 天基线对比；
   - 关键埋点（原生版新增）：迁移执行次数/成功数/失败兜底数、首启时长、首启崩溃；
   - 异常指标 → **暂停放量**（Phased release 可暂停），评估修复或回滚提审；
3. What's New 按 2.3.12 说明重写（"完全重构为原生应用"级别的事实在文案中说明）。

### 10.3 发布门禁（Release Gate，全绿才提审）

- [ ] L0 数据迁移测试（§2.1–2.3）100% 通过
- [ ] L1 golden 对拍（G1–G16）100% 通过
- [ ] L2 契约测试（§4.1–4.2）100% 通过
- [ ] §2.5 升级安装实测 ≥3 轮通过（含 db_heavy + Plus 账号组合）
- [ ] §6.3 人工清单 P0 全过、P1 ≥90%
- [ ] §5.3/5.4 系统事件与弱网全过
- [ ] §8 付费矩阵全过（含升级用户 Plus 延续）
- [ ] §9 性能不劣化
- [ ] **iPad（iOS 27 模拟器/真机）任意窗口尺寸/宽高比下布局不崩不溢出**（§11 战略决策硬性验收；含分屏宽度抽查 ≥3 档）
- [ ] §11 决策表全部条目已决策并落实到代码
- [ ] Sentry 埋点就位；回滚预案（Flutter 线可构建）演练过一次

---

## 11. 怪癖/已知 bug 决策表（迁移前必须逐条拍板）

> **2026-09-21 拍板 K1–K25**（原文档索引中的"默认建议"即采纳结果）；**2026-09-22 并入《08》三轮走查结论：K26–K38 新增、K4/K9 增补**。默认原则：怪癖复刻（安全），崩溃修（必须），体验增强（登记后纳入）。

| # | 现状（出处） | 影响 | 最终决策 |
|---|---|---|---|
| K1 | 锁屏"上一曲/下一曲"实为 ±10s，且无切集命令（audio_handler.dart:182-191） | 高频使用路径 | **复刻**（经确认为有意设计：播客惯例。锁屏 ±10s、App 内全屏播放器 −10s/+30s、mini player +30s 全部保持原样；"锁屏快进对齐 +30s"列二期 backlog） |
| K2 | skip silence 开关在 iOS 无效（just_audio Android only） | 设置项无效 | **移除开关**（判定依据"能实现就实现，否则去掉"：iOS 无公开 API，真做需弃 AVPlayer 换 AVAudioEngine 自建管线，代价大且威胁流播/缓存/后台播放稳定性）。`settings.skipSilence` 字段保留 schema 兼容读取（不显示、不写入） |
| K3 | 播完一集即从播放列表删除（removeTop） | 队列语义 | **复刻**（数据语义，改动会改变用户列表内容） |
| K4 | 搜索接口网络失败时 `response!` 抛异常 → UI 卡 spinner（podcasts.dart:22,64） | 崩溃级 bug | **修复**：显示错误态（正常路径不变，属崩溃类）。崩溃族一并修复（08 §12.3）：`searchEpisodes` 的 `parsePubDate(...)!.millisecondsSinceEpoch`（podcasts.dart:77，release_date null 即崩）、`seekByRelative` 的 `_player.duration!`（audio_handler.dart:143）、`toMediaItem` 的 `title!/imageUrl!`、discover `episodes[index].episode!`、`moveToTop` 按 id 匹配（null==null 移错条）、OPML 导出 `title!/description!`、`urlToDomain` 畸形 URL、`handle403` as 强转、`getUser` 的 `jsonDecode` 在 try 外（api/user.dart:41，非 JSON 响应异常冒泡）、**`getOrFetch` 的 `data[0]`（subscription.dart:120，DB miss 且 RSS 抓取失败/解析为空即 RangeError——播放起播路径上，搜索结果直接播放可触发）** |
| K5 | RSS 缺 pubDate/duration 时解析崩（rss_fetcher.dart:112-131 `pubDate!`） | 脏数据崩溃 | **修复**：容忍 NULL（§1.2 missing_fields 分桶覆盖） |
| K6 | 播放失败无任何提示/重试（playerErrorStream 无人订阅） | 弱网体验 | 建议增强（错误 toast + 手动重试），至少不劣于旧版 |
| K7 | HTML show notes 内链接不可点（HtmlWidget 未配 onTapUrl） | 功能缺失 | 建议增强（打开外链）；登记 |
| K8 | chat 非 2xx 的 body 显示为 AI 回复（subtitles.dart:115-117） | 误导用户 | 建议修复为错误提示；至少 401/403 不当回复显示 |
| K9 | 翻译接口无认证、无超时、Timer 内异常未捕获（translation.dart / subtitles.dart:80-83） | 稳定性 | 保持无认证（契约）；补超时（>服务端耗时，如 30s）与异常捕获；**重试上限（如 5 次退避）+ 失败后展示原文并移除 "Translating subtitles..." 常驻条**（旧版 `getTranslation` 返回 null 后 `translationUrls` 停在 'processing'，10s 定时器每拍重发 forever、服务器被打，states/translation.dart:44-77——08 §11.5-5 增补） |
| K10 | 429 无退避（error_handler.dart） | 契约相关 | 复刻（无退避）——【后端已核实：应用层无 429/限流逻辑，配额不足走 403（《02》§7），429 只可能来自 Cloudflare 边缘】 |
| K11 | 进度事件四条件过滤（!isPlaying/isLoading/position==0/buffered==0，player.dart:105-115） | 起播/暂停/加载中 UI | 复刻或等价视觉 |
| K12 | 历史按 id DESC 而非时间排序（history_episode.dart:55） | 数据语义 | **复刻**（排序语义改变会导致"最新历史"内容不同） |
| K13 | 同名订阅互相顶掉（subscription.title UNIQUE） | 数据语义 | **复刻**（改会改变数据行为） |
| K14 | 同一集跨列表加入（playlistEpisode 表级 UNIQUE(enclosureUrl)）。现网实际行为：`getByEnclosureUrl` 全表查到后 `update` **不改 playlistId**——行留在旧列表、position 却按目标列表序计算（视觉上等于没加进新列表、旧列表序被污染，models/playlist_episode.dart:90-125；原表"移动到新列表"的表述与代码不符，2026-09-23 勘误） | 数据语义 | **行为变更（2026-09-23 拍板）**：跨列表加入 = 移动到新列表（playlistId 更新），不复刻现网怪癖；L0 补跨列表断言 |
| K15 | 换目标语言覆盖旧翻译（translation UNIQUE） | 数据语义 | **复刻**（同上） |
| K16 | maxCacheCount 无 UI（锁死 10）（states/player.dart:436-443） | 隐藏功能 | 复刻缺省；增强（加设置项）可放后续版本 |
| K17 | autoSleepTimer 可配置但不生效（死代码，audio_handler.dart:121） | 死功能 | 复刻（不激活）；后续版本决定删除或实现 |
| K18 | 播放无音频焦点自定义处理（无打断监听） | 系统行为 | 允许增强（显式打断/route 监听），行为不得差于旧版 |
| K19 | artwork 弱网无兜底 | 锁屏视觉 | 允许增强（本地缓存 artwork） |
| K20 | UA 从 `Dart/x.y` 变为原生 UA（02 §6.3） | 后端/RSS 兼容 | RSS 用固定浏览器 UA（优于现状）；自家 API 用原生 UA（后端已核实无入站 UA 过滤，《02》§7） |
| K21 | 导出字幕扩展名 .txt 而非 .lrc（player.dart:951-978） | 用户习惯 | 复刻 .txt（含 LRC 内容）；是否加 .lrc 选项由用户定 |
| K22 | timeago 固定 en_short、无 i18n、硬编码英文文案 | 一致性 | 复刻英文文案（不改语言） |
| K23 | Info.plist 允许任意 http（ATS off） | 安全 vs 兼容 | 复刻（否则 http 源无法播）；不可收紧 |
| K24 | 进度只在播放中每 2s 落盘，无生命周期保存 | 最坏丢 2s | 增强（pause/退后台时补一次保存），进首版 |
| K25 | 主库文件损坏（截断/非 SQLite 字节）无兜底，openDatabase 抛异常同样起不来 | 升级安装低概率真实场景 | **增强**：隔离坏库（改名保留 `.corrupt`）+ 重建默认库 + Sentry 上报，不 crash loop（fixtures 见 §1.1 `db_corrupt`、断言见 §2.1）。**触发条件（防误伤）**：仅由确定性损坏信号触发——打开阶段即返回 `SQLITE_NOTADB`，或 open/integrity-check 报 `SQLITE_CORRUPT`；其余读错误（IO 瞬态、锁等）走重试，**不得**触发隔离，避免把好库误判后"兜底"清空用户数据 |
| K26 | 拖拽**下移**换序 off-by-one：`insertOrUpdateByIndex` 对已存在条目用**移动前的 DB 列表**取邻居，下移算出的中点落回旧位置、间隙 ≥0.0005 永不触发 `_reorder` 兜底 → 下移重启后回退（会话内 UI 正确）（models/playlist_episode.dart:90-125；states/playlist_episode.dart:38-42 传移动后 index） | 数据正确性 | **修复**（同 K4/K5 缺陷修复逻辑）：邻居按移动后列表取。G1/G2 golden 拆分口径见 §1.5；已有旧数据的 position 值不回填重排（升级场景等价） |
| K27 | 后台轮询（15s 转写/10s 翻译）非 2xx 每次都 `ErrorHandler.handle` 弹模态错误框（token 过期时登录页随机弹、429 弹 Error 429）；任何一次瞬时 5xx 会删本地 processing 记录、UI 回退 Generate（api/subtitles.dart:44-47、subtitle timer failed 分支） | 稳定性 | **修复（行为变更）**：用户主动触发的 add() 保持弹窗；后台轮询错误静默——5xx/超时保持 processing 继续轮询（服务端按 enclosure_url 幂等不重复计费，《02》§7）；401 仍走登录页（08 §11.5-4） |
| K28 | 转写"自愈"重触发：本地 succeeded 但存储文本为空/'null' 时删记录置回 processing 重新 POST（pages/player.dart:610-624） | 契约 | **复刻**；L2 回放须覆盖该分支（§1.3 已补） |
| K29 | 导出字幕文件名 `$title - $channel.txt` 未 sanitize，标题含 `/` 等非法路径字符即写文件抛异常、导出必崩（pages/player.dart:968） | 崩溃类 | **修复**：sanitize 文件名（K4/K5 族） |
| K30 | 每次恢复播放（resume）也会重插历史行——但 `fromMap(playlistEpisode.toMap())` 带入 playlist 行 id，delete+INSERT(显式 id, REPLACE) 后 **id 不变、历史排序位置不变**（原表述"移顶、id 改变"系勘误，2026-09-23 sqflite 实测确认，states/player.dart:243/280 + models/history_episode.dart:70-77；仅"已播完重新入列再播"才因 playlist 新行 id 而置顶） | 数据语义 | **复刻（勘误后口径）** + §2.3 断言：resume 重插后 id 不变、排序位置不变 |
| K31 | 队列播空 `clear()` 删 player 行（默认行只在建库时插入），重启后 `PlayerModel.get` 对空结果 `maps[0]` 抛错 → 未捕获 async 不崩但 load 链断，当前曲/进度恢复静默失败（models/player.dart:49-55） | 数据恢复 | **修复（泛化口径，2026-09-22 升级）**：**DB open 时幂等 `INSERT OR IGNORE` 补齐三行默认行**（playlist `(1,'Default',1)`、player `(1,NULL)`、settings 全默认）——同族的 `SettingsModel.get` 的 `maps[0]`（settings.dart:94）一并消掉，且 K25 坏库重建天然复用同一逻辑；读侧仍防御缺行（视为默认值）。§2.3 补断言 |
| K32 | MyProgressBar 在 duration==0 时 build 内反复调 `initProgress()`（条件恒真 + PositionData 未实现 ==，每次新实例触发重建）→ 热循环直到真实播放事件（pages/player.dart:426-429） | 渲染 | **修复**：进度展示移出渲染路径（崩溃族，08 §12.1-2） |
| K33 | 跑马灯触发按 `title.length × 24` 字符数估宽，CJK/拉丁混排必然误判（《03》§2.10） | 视觉 | **微增强**：播放器标题改 `boundingRect` 实测宽度触发；**历史列表的 always-scroll 行为保持**（不测宽、短标题也滚，playlists.dart:342-355）——两处不互相污染（08 §7.3/§11.6） |
| K34 | 同会话内重开频道页复用旧 Controller 实例、不重抓剧集（Get.lazyPut(tag) 不删除，card.dart:332-341 / player.dart:401-410） | 可见语义 | **复刻**（频道 VM 按 URL 缓存、随 sheet 关闭保留 = 复刻；08 §12.2） |
| K35 | PlayerPage 背景渐变未包响应式 → 换集时背景色不更新、重开播放器才对（pages/player.dart:51-62） | 可见怪癖 | **修复（2026-09-22 拍板）**：换集时背景随 palette 更新——旧版是忘包响应式的明显 bug，零风险纯改善 |
| K36 | autoRefreshInterval 改动即时重启定时器；CupertinoPicker 滚动过程每 tick 都取消重建一次（周期从零重计）（states/player.dart:459-466） | 定时器语义 | **复刻**：改动即时生效 + 接受滚动期重置（08 §11.5-3，§12.4 已更正原表述） |
| K37 | 反馈邮箱 UI 显示 `kindjeff.com@gmail.com` 与 mailto 实发 `kindjeffcom@gmail.com` 不一致（pages/settings.dart:460-471） | 笔误 | **统一为 `kindjeff.com@gmail.com`（2026-09-22 拍板）**：显示与实发同址。注：Gmail 忽略点号、两者本是同一邮箱，投递行为不变，仅显示一致性修复 |
| K38 | 睡眠倒计时滑条拖到 0（= OFF）时，`onChanged` 即置 zero，若 1s timer 先触发会 `pause()`——"关闭倒计时"可能顺带暂停播放（player.dart:1252-1254 + states/player.dart:324-327，时序相关；《04》§1.7） | 竞态 | **修复（2026-09-22 定）**：滑到 0 = OFF 不触发 pause，仅倒计时**自然递减到 0** 才 pause |
| K39 | `htmlToText` 的 Dart `body.text` **包含** `<script>`/`<style>` 文本内容（html 包把其内容存为 TextNode；实测 `a<script>var x=1;</script><style>.y{}</style>b` → `avar x=1;.y{}b`，utils/rss_fetcher.dart:165-185；原生初版误裁且 parity 注释写反，2026-09-23 发现） | 数据字节 | **复刻（2026-09-23 拍板）**：原生把 script/style 内容收进文本（SwiftSoup DataNode），订阅 description 写回字节同构；专项测试钉住该 case（一致性优先于观感——描述里混 JS 属垃圾文本，但分歧成本更高） |
| K40 | Dart `String.trim()` 裁 Unicode White_Space ∪ **U+FEFF**；Swift `.whitespacesAndNewlines` = White_Space ∪ **U+200B**——差异两个字符且方向相反（Dart 多裁 FEFF、Swift 多裁零宽空格 200B；NBSP/U+0085/U+3000/U+2000–200A 等两者同裁，2026-09-23 双侧实测）。`subscription.title` 是 UNIQUE 键，尾部差一字符即成两行 | 数据字节 | **复刻（2026-09-23 拍板）**：`dartTrimmed()`（whitespacesAndNewlines − 200B + FEFF）应用于全部 Dart `.trim()` 对应点（RSS 字段、订阅 title/description、G16 搜索映射、renderHtml 路由），探针测试钉住两个差集字符 |

**首版纳入的增强项汇总**（K6/K7/K8/K9/K18/K19/K24/K25 + 2026-09-22 并入的 K26/K27/K29/K31/K32/K33/K35/K38）：播放错误提示+手动重试、show notes 链接可点、聊天错误不再伪装成 AI 回复（401/403 绝不当回复显示）、翻译请求 30s 超时+异常捕获+重试上限+失败态、音频打断/拔耳机显式处理（不劣于旧版）、锁屏封面本地缓存兜底、进度退后台时补一次保存、损坏数据库隔离重建不 crash loop、拖拽下移 off-by-one 修复、后台轮询错误静默、导出文件名 sanitize、clear 后重启恢复修复（open 幂等补默认行）、duration==0 渲染循环修复、跑马灯实测宽度触发、换集背景渐变即时更新、倒计时滑到 0（OFF）不误触 pause。

**二期 backlog（不进迁移首版）**：CarPlay、maxCacheCount 设置 UI、导出 .lrc 选项、autoSleepTimer 的删除或实现、锁屏快进秒位对齐 App 内（+30s）、**完整 iPad 适配**。

**战略决策（同日拍板）**：最低部署目标 **iOS 18**（iOS 26/27 特性走 `#available` 降级，iOS 15–17 用户停留在 Flutter 最后一版，已接受此权衡）；UI 框架 **UIKit 为主 + `@Observable` + 局部 SwiftUI**（《06》§2）；写回兼容 **首版只读兼容 + 相同 schema 写入**（§2.4，含缓存元数据库同语义写入）；**Share Extension 保留现有原生 target 原样**（它本就是 Swift、与 Flutter 无耦合），仅主 App 侧改为直接读 App Group；人工回归 = 作者本人 + TestFlight 内部组（2–3 位重度用户志愿者）；**iPad 策略：首版 iPhone-only**（`TARGETED_DEVICE_FAMILY=1`，现 App 实为 universal 但 Dart 锁竖屏的手机 UI 拉伸形态）——iPad 用户继续收到更新；**iOS 27 起 iPhone-only App 在 iPad 上是全尺寸可缩放窗口（任意宽高比，不止竖屏拉伸），据此定硬性验收（2026-09-22 升级）：任意窗口尺寸/宽高比下布局不崩不溢出（允许观感一般）、全部布局用 view bounds/trait 禁按屏宽计算、不依赖 `UIRequiresFullscreen`（WWDC25 口径将被忽略），最小窗口尺寸限制 API 列 M1/M2 调研兜底**；完整 iPad 适配列 backlog。

---

## 12. 里程碑（测试先行的工作流）

| 阶段 | 内容 | 产出 |
|---|---|---|
| **M0 资产期**（先于任何原生代码） | §1 全部资产 + `tool/golden_export.dart` + golden 全量生成（UA 策略与全部决策已定稿，无需再做矩阵探测/拍板轮） | fixtures/golden 进 git |
| **M1 契约期** | 原生网络层 + 数据读取层（GRDB）实现；L0/L1/L2 测试套件建成并跑绿 | 纯逻辑层等价性已证明 |
| **M2 音频期** | AVPlayer 播放服务 + 缓存 + 锁屏；§5 单元部分自动化 | 播放行为可测 |
| **M3 UI 期** | 页面逐个迁移，每页完成即补快照 + 对应人工条目；XCUITest 冒烟逐步扩充 | 屏幕清单逐屏打勾 |
| **M4 集成期** | §2.5 升级安装实测循环；§8 付费矩阵；§9 性能 | RC 候选 |
| **M5 灰度期** | TF Internal → Phased Release，§10.2 监控 | 正式发布 |

---

## 13. 与本文档配套但另行维护的内容

- `docs/migration/rounds/`：每轮 RC 的人工回归记录（§7 模板）
- 后端契约核实结论已并入《02》§7（删号联动 RevenueCat、无 429/限流、无入站 UA 过滤、免费额度实为 10 次/终身）
