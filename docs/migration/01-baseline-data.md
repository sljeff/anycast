# 基线盘点 01：本地数据层（数据兼容性的事实来源）

> 用途：iOS 原生化迁移（同 bundle id `com.kindjeff.anycast` 覆盖更新）的数据兼容性回归测试设计输入。
> 基线版本：App 1.2.1+38（pubspec.yaml:19）；iOS 部署目标 15.0；主 target `com.kindjeff.anycast`，Share Extension target `com.kindjeff.anycast.Share-Extension`。
> 本文所有结论均附代码出处，行为以此为准，不以本文转述为准。

---

## 1. SQLite 数据库清单

### 1.1 主数据库 `anycast.db`

**路径构造**（lib/models/helper.dart:48-49，逐字摘录）：
```dart
String databasesPath = await getDatabasesPath();
String path = join(databasesPath, 'anycast.db');
```
**iOS 实际解析位置**：sqflite_darwin 的 `getDatabasesPath` 在 iOS 上返回 **Documents 目录**（sqflite_darwin `SqflitePlugin.m:762-768`，逐字摘录）：
```objc
// getDatabasesPath
// returns the Documents directory on iOS
- (void)handleGetDatabasesPath:(FlutterMethodCall*)call result:(FlutterResult)result {
    NSArray* paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    result(paths.firstObject);
}
```
→ 绝对路径：`<App Container>/Documents/anycast.db`。sqflite 未启用 WAL，事务期间可能出现临时的 `<Container>/Documents/anycast.db-journal`（rollback journal）。

**打开与版本**（helper.dart:55-77）：
```dart
Database db = await openDatabase(
  path,
  version: 4,
  onCreate: ... // 顺序执行 tableCreators 中 9 个建表函数
  onUpgrade: (db, oldVersion, newVersion) {
    var sorted = migrations.keys.toList()..sort();
    for (int version in sorted) {
      if (oldVersion < version) {
        for (String sql in migrations[version]!) { db.execute(sql); }
      }
    }
  },
);
```

**迁移历史**（helper.dart:27-32，全部内容，历史上仅此一次 schema 变更，v3→v4）：
```dart
var migrations = {
  // 3 -> 4
  4: [
    'ALTER TABLE settings ADD COLUMN continuousPlaying INTEGER DEFAULT 1',
  ],
};
```

**建表顺序**（helper.dart:15-25）：`feedEpisodeTableCreator, playlistEpisodeTableCreator, subscriptionTableCreator, playlistTableCreator, playerTableCreator, settingsTableCreator, subtitleTableCreator, historyEpisodeTableCreator, translationCreateTable`。

#### 表 1：`feedEpisode`（收件箱/订阅的最新单集，lib/models/feed_episode.dart:7-19）
```sql
CREATE TABLE IF NOT EXISTS feedEpisode (
  id INTEGER PRIMARY KEY,
  title TEXT,
  description TEXT,
  duration INTEGER,
  enclosureUrl TEXT UNIQUE,
  pubDate INTEGER,
  imageUrl TEXT,
  channelTitle TEXT,
  rssFeedUrl TEXT
)
```
| 列 | 类型 | 含义 |
|---|---|---|
| id | INTEGER PK | 行 id（非 AUTOINCREMENT，按 insert 顺序） |
| title/description | TEXT | 单集标题/show notes |
| duration | INTEGER | **毫秒**（itunes:duration 换算，rss_fetcher.dart:129） |
| enclosureUrl | TEXT UNIQUE | 音频 enclosure URL，全局去重键 |
| pubDate | INTEGER | **Unix 毫秒**（`millisecondsSinceEpoch`，rss_fetcher.dart:131） |
| imageUrl/channelTitle/rssFeedUrl | TEXT | 封面、频道名、RSS 地址 |

读取顺序 `ORDER BY pubDate DESC`（feed_episode.dart:55）。批量写入用 `ConflictAlgorithm.replace`（feed_episode.dart:79-87，按 enclosureUrl 唯一约束替换）。

#### 表 2：`playlistEpisode`（播放队列成员，lib/models/playlist_episode.dart:8-23）
```sql
CREATE TABLE IF NOT EXISTS playlistEpisode (
  id INTEGER PRIMARY KEY,
  title TEXT,
  description TEXT,
  duration INTEGER,
  enclosureUrl TEXT UNIQUE,
  pubDate INTEGER,
  imageUrl TEXT,
  channelTitle TEXT,
  rssFeedUrl TEXT,
  playlistId INTEGER,
  position REAL,
  playedDuration INTEGER
)
```
特有列：`playlistId`（所属播放列表）、`position`（**REAL 浮点分数排序**，`ORDER BY position ASC` 查询，playlist_episode.dart:73-74）、`playedDuration`（INTEGER，**毫秒**，播放进度）。
- `enclosureUrl` 的 UNIQUE 是**全表**约束 → 同一集只能存在于一个播放列表（原生迁移必须保留此语义）。
- 插入算法：`insertOrUpdateByIndex`（playlist_episode.dart:90-125）取左右邻居 position 的中点；`minPositionGap = 0.0005`（playlist_episode.dart:26），间距过小时触发 `_reorder` 将整个列表 position 重排为 0,1,2,…（playlist_episode.dart:127-135）。

#### 表 3：`subscription`（订阅，lib/models/subscription.dart:5-18）
```sql
CREATE TABLE IF NOT EXISTS subscription (
  id INTEGER PRIMARY KEY,
  rssFeedUrl TEXT UNIQUE,
  title TEXT UNIQUE,
  description TEXT,
  imageUrl TEXT,
  link TEXT,
  categories TEXT,
  author TEXT,
  email TEXT,
  lastUpdated INTEGER
)
```
- `title` 也是 UNIQUE（注意：同名不同 URL 的频道会互相顶掉，见 §8）。
- `categories`：逗号分隔字符串（subscription.dart:28、rss_fetcher.dart:108）。
- `lastUpdated`：Unix **毫秒**；取值为该频道最新单集的 pubDate，无单集时为导入时间（rss_fetcher.dart:138-142）。
- 批量写入 `ConflictAlgorithm.replace`（subscription.dart:86-95）；删除条件 `rssFeedUrl = ? or title = ?`（subscription.dart:97-102）。

#### 表 4：`playlist`（lib/models/playlist.dart:4-18）
```sql
CREATE TABLE IF NOT EXISTS playlist (
  id INTEGER PRIMARY KEY,
  title TEXT,
  position INTEGER
)
```
建表后立即插入默认行（逐字摘录，playlist.dart:12-16）：
```sql
INSERT OR IGNORE INTO $tableName (id, title, position)
VALUES (1, 'Default', 1)
```

#### 表 5：`player`（播放器指针，lib/models/player.dart:4-17）
```sql
CREATE TABLE IF NOT EXISTS player (
  id INTEGER PRIMARY KEY,
  currentPlaylistId INTEGER
)
```
默认行（player.dart:11-15）：`INSERT OR IGNORE INTO player (id, currentPlaylistId) VALUES (1, NULL)`。更新为 `INSERT OR REPLACE ... VALUES (1, ?)`（player.dart:44-46）；清空即删除 id=1 行（player.dart:57-59）。

#### 表 6：`settings`（lib/models/settings.dart:6-38）
```sql
CREATE TABLE IF NOT EXISTS settings (
  id INTEGER PRIMARY KEY,
  darkMode INTEGER,
  speed REAL,
  skipSilence INTEGER,
  autoSleepTimer TEXT,
  maxCacheCount INTEGER,
  countryCode TEXT,
  targetLanguage TEXT,
  autoRefreshInterval INTEGER,
  maxFeedEpisodes INTEGER,
  maxHistoryEpisodes INTEGER,
  continuousPlaying INTEGER DEFAULT 1
)
```
默认行（settings.dart:33-36，注意 `continuousPlaying` 不在 INSERT 列表中，靠 `DEFAULT 1` 兜底；countryCode/targetLanguage 由 `Platform.localeName` 解析，如 `zh_Hans_CN` → country=`CN`, language=`zh`）：
```sql
INSERT OR IGNORE INTO settings (id, darkMode, speed, skipSilence, autoSleepTimer, maxCacheCount, countryCode, targetLanguage, autoRefreshInterval, maxFeedEpisodes, maxHistoryEpisodes)
VALUES (1, 0, 1.0, 0, '0,0,0', 10, '$country', '$language', 300, 100, 100)
```
详见 §2。

#### 表 7：`subtitle`（转写，lib/models/subtitle.dart:9-18）
```sql
CREATE TABLE IF NOT EXISTS subtitle (
  id INTEGER PRIMARY KEY,
  enclosureUrl TEXT UNIQUE,
  status TEXT,
  subtitle TEXT,
  language TEXT,
  summary TEXT
)
```
- `subtitle` 列为 **JSON 字符串**：`jsonEncode(List<Subtitle>)`，元素 `{"start":double秒,"end":double秒,"text":string}`（api/subtitles.dart:13-17、states/subtitle.dart:39-40）。
- `insert` 有校验：subtitle 为 null/空/字符串 `'null'` 或 language 为 null 时**不落库**（subtitle.dart:68-75）→ **库里只有 status='succeeded' 的完整行**，'processing' 状态仅存内存（states/subtitle.dart:51-61 插入空串会被该校验拦截）。
- `summary` 列建了但**从未写入**（残留列，恒 NULL）。

#### 表 8：`historyEpisode`（播放历史，lib/models/history_episode.dart:7-19）
```sql
CREATE TABLE IF NOT EXISTS historyEpisode (
  id INTEGER PRIMARY KEY,
  title TEXT,
  description TEXT,
  duration INTEGER,
  enclosureUrl TEXT UNIQUE,
  pubDate INTEGER,
  imageUrl TEXT,
  channelTitle TEXT,
  rssFeedUrl TEXT
)
```
结构与 feedEpisode 完全相同。写入是“先 DELETE 同 enclosureUrl 再 INSERT”（history_episode.dart:76-88）→ 重新播放会把该集挪到最新（`ORDER BY id DESC` 读取，history_episode.dart:55）。

#### 表 9：`translation`（翻译，lib/models/translation.dart:10-18）
```sql
CREATE TABLE IF NOT EXISTS translation (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  enclosureUrl TEXT UNIQUE,
  status TEXT,
  translation TEXT,
  language TEXT
)
```
- **唯一使用 AUTOINCREMENT 的表**（会产生 `sqlite_sequence` 表，迁移时注意）。
- `translation` 列为 JSON 字符串，格式同 subtitle（`[{start,end,text}]`，start/end 为 double 秒）。
- 注意矛盾点：查询用 `enclosureUrl + language` 双键（translation.dart:52-58），但 UNIQUE 只在 enclosureUrl 上 → **同一集只能存一种语言的翻译**（后开的语言 replace 前者）。

**索引**：全部为 UNIQUE 隐式索引（subscription.rssFeedUrl、subscription.title、各 episode 表的 enclosureUrl），无任何显式 `CREATE INDEX`。

### 1.2 缓存元数据库（flutter_cache_manager_plus 自动创建，两个）

由 fork（sljeff/flutter_cache_manager@51211c，pubspec.yaml `flutter_cache_manager_plus`）的 `CacheObjectProvider` 创建：

- **`<Container>/Library/Application Support/anycast_episode.db`** — 音频缓存索引（cacheKey=`anycast_episode`，states/cache.dart:11）
- **`<Container>/Library/Application Support/libCachedImageData.db`** — 封面图片缓存索引（cached_network_image 使用 `DefaultCacheManager`，其 `key = 'libCachedImageData'`）

表结构（fork 的 cache_object_provider.dart，version 3）：表 `cacheObject`，列 `_id INTEGER PRIMARY KEY / url TEXT / key TEXT / relativePath TEXT / eTag TEXT / validTill INTEGER / touched INTEGER / length INTEGER`，外加 `CREATE UNIQUE INDEX cacheObjectkey ON cacheObject (key)`（2026-09-22 核验更正：id 列名实为 `_id`、路径列名实为 `relativePath`，非早期转述的 id/path；`relativePath` 只存**文件名** `<uuidv1>.<ext>`，由 `<Library/Caches>/<cacheKey>/` 前缀解析——cache_object.dart:9-16、file_system_io.dart:28-35）。onUpgrade：v1→v2 加 `key` 列（`set key = url where key is null`）；v2→v3 加 `length` 列。库版本 3。
**2026-09-23 实机勘误（M2，依据 `db_device` 真实容器，simctl 提取）**：① **`key` 列的行内值就是该资源的 URL 本身**（`url` 与 `key` 两列逐行相同），不是 Config 的 cacheKey 字面量——`Config(cacheKey)` 只决定库文件名与文件目录；原生按 `WHERE url = ?`（或 `key = url`）查行，按字面 cacheKey 查会永远 miss。② 实机库 `sqlite_master` 中**没有** `cacheObjectkey` 唯一索引（只有建表语句；fork 源里的 CREATE UNIQUE INDEX 在实机上未出现）——原生建库时不建该索引、与实机一致。③ `validTill` 非固定 30 天：实机行 `validTill − touched ≈ 604,796,775 ms ≈ 7 天`，与响应 `Cache-Control: max-age=604800` 吻合 → **validTill 按 HTTP 缓存头（Date + max-age）计算，无头时才落默认 stalePeriod 30 天**。④ `touched`/`validTill` 均为毫秒（实机值 1.79e12 量级）。⑤ 扩展名取自响应 Content-Type（实机 `.m4a` URL 存为 `.mp4`，即 audio/mp4 → .mp4）。
**旧版路径迁移**：该 fork 会检查 `getDatabasesPath()/<key>.db`（即 Documents/）下的旧库文件并 rename 到新位置（V2 之前的老安装用户）。

---

## 2. SettingsController 与设置项

存储方式：**全部在 SQLite `settings` 表单行（id=1），不使用 shared_preferences**（整个 pubspec 无 shared_preferences 依赖，GeneratedPluginRegistrant.m 中也无该插件）。读写集中在 lib/states/player.dart 的 `SettingsController`（254-488 行）与 lib/models/settings.dart。

| key（列名） | 类型 | 默认值 | 取值范围（来自 UI） |
|---|---|---|---|
| darkMode | INTEGER(bool 0/1) | 0 | 0/1；读取时 `map['darkMode'] == 1`（settings.dart:77）。注：主题实际硬编码深色，此开关目前无 UI 写入 |
| speed | REAL | 1.0 | 播放页 Slider min 0.5 / max 2.0 / divisions 6 → {0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0}（pages/player.dart:1208-1216） |
| skipSilence | INTEGER(bool 0/1) | 0 | 0/1 |
| autoSleepTimer | TEXT | `'0,0,0'` | CSV `startHour,endHour,minsIndex`：两个 0-23 小时索引 + 0-6 索引映射 {OFF,10,20,30,40,50,60} 分钟（states/player.dart:273-283、125） |
| maxCacheCount | INTEGER | 10 | **无修改 UI**（全库 grep 无调用 setMaxCacheCount 的 UI）；用作音频缓存 maxNrOfCacheObjects |
| countryCode | TEXT | 系统区域（如 'US'） | 49 国列表（pages/settings.dart:34-84） |
| targetLanguage | TEXT | 系统语言（如 'en'） | `targetLangList` 11 种语言 code（en/fr/de/es/it/ja/zh/pt/nl/uk/ru，pages/settings.dart:20-32）+ `''`（关闭翻译） |
| autoRefreshInterval | INTEGER | 300（秒） | {60,180,300,600,1800}（minutes=[1,3,5,10,30]×60，pages/settings.dart:321） |
| maxFeedEpisodes | INTEGER | 100 | {50,100,200,300}（pages/settings.dart:387） |
| maxHistoryEpisodes | INTEGER | 100 | {50,100,200,300}（pages/settings.dart:437） |
| continuousPlaying | INTEGER(bool 0/1) | 1 | 0/1 |

写入统一 `UPDATE settings SET <field> = ? WHERE id = 1`（settings.dart:142-149 通用 `set`，及各专用方法）；bool 一律 `? 1 : 0` 参数化写入。
加载：`SettingsController._load`（states/player.dart:290-311）在 onInit 时读一次。`setTargetLanguage` 会清空内存中的 translationUrls 缓存（states/player.dart:452-458）。

**autoRefreshInterval 口径裁定（2026-09-21，勿改）**：DB 默认行是 **300**（settings.dart:33），但 Rx 初值是 **180**（states/player.dart:265 `autoRefreshInterval = 180.obs`），且自动刷新定时器在 `initAutoRefresher` 里**一次性读取当前值**（states/feed_episode.dart:124-131）——首个自动刷新周期取决于 DB 异步 `_load()` 与首页 build 的先后（首启竞态），稳态一律为 DB 值。**迁移口径：以 DB 300 为准**，首启竞态视为不可观察差异、不作为回归不等价项（G9 与《05》§2.1 按 300 断言）。

---

## 3. 播放器状态持久化与恢复

- **持久化内容极小**：`player` 表只存 `currentPlaylistId`（models/player.dart）。**队列即该 playlistId 下的 `playlistEpisode` 行（position ASC），“当前曲目”恒为队列第 0 行**（states/player.dart:50-56、states/playlist.dart:36-47）。
- **播放进度**：每 2 秒定时器把 `myAudioHandler.playedDuration`（毫秒）写入队首 `playlistEpisode.playedDuration`（states/player.dart:64-74 → states/playlist_episode.dart:84-91 → `UPDATE playlistEpisode SET playedDuration=? WHERE enclosureUrl=?`，models/playlist_episode.dart:154-157）。
- **恢复逻辑**：启动时 `PlaylistController.load`（states/playlist.dart:22-52）加载所有 playlist 及其 episodes；若 `player.currentPlaylistId != null`，取该列表 episodes[0] 为当前曲目，并把 UI 进度初始化为 `position = playedDuration ms, duration = duration ms`。真正起播时 `MyAudioHandler.autoSet`（utils/audio_handler.dart:197-220）优先用缓存文件 `setFilePath(info.file.path, initialPosition: playedDuration)`，否则 `setUrl` 流播 + 后台经 CacheManager 下载。
- **播完一首**：`ProcessingState.completed` → `peController.removeTop()`（**删除队首行 + 关联 subtitle/translation/缓存文件**，states/playlist_episode.dart:53-68）→ 播下一首；`continuousPlaying=false` 时暂停（states/player.dart:83-102）。
- **清空**：`clear()` 删除 player 行并清内存（states/player.dart:211-219）。
- 播放/续播时会写 historyEpisode（states/player.dart:136-137、173-174）。
- 队列没有独立持久化：不存 audio_service 的 queue，锁屏信息来自 `MediaItem`（内存）。

---

## 4. 文件缓存与下载

### 4.1 音频缓存（CacheController，lib/states/cache.dart:10-15）
```dart
var cacheManager = CacheManager(
  Config(
    'anycast_episode',
    maxNrOfCacheObjects: Get.find<SettingsController>().maxCacheCount.value,
  ),
);
```
- **cacheKey**：`anycast_episode`；**maxNrOfCacheObjects = maxCacheCount（默认 10，按对象个数，非字节）**；**stalePeriod 未传 → fork 默认 30 天**（_config_io.dart：`stalePeriod ?? const Duration(days: 30)`）。
- **文件位置（2026-09-23 实机勘误，M2）**：`<Container>/Library/Caches/anycast_episode/<uuid_v1>.<ext>`——**不是早期从 fork 源推得的 `tmp/`**。依据：`db_device`（模拟器实机容器，simctl 提取，见《00》M0 修订注记与 test/fixtures/README.md）中音频文件实际位于 `Library/Caches/anycast_episode/`（`1a92d670-….mp4` 等），目录下无 tmp 残留。封面缓存同一套 IOFileSystem 代码路径，同在 `Library/Caches/libCachedImageData/`。**原生写入必须落在同一路径**，否则回滚 Flutter 后索引指不到文件（05 §2.4 写回兼容）。
  → 音频文件绝对路径：`<Container>/Library/Caches/anycast_episode/<uuid_v1>.<ext>`。
- **文件命名规则**（fork cache_manager.dart:209-214 与 web_helper.dart `_setDataFromHeaders`）：首次 `relativePath = '${Uuid().v1()}$fileExtension'`，扩展名由 HTTP 响应 `Content-Type` 映射（mime_converter.dart，如 `audio/mpeg → .mp3`，未知类型 `.$subType`，`application/octet-stream → .bin`）；服务器返回新文件且扩展名变化时会换新 UUID 文件名并删旧文件。**文件名与 URL 无哈希关系，唯一映射靠 `anycast_episode.db` 的 `url/key/relativePath` 列** —— 原生迁移若想保留已下载音频，必须先读该元数据库再找文件。
- **下载触发**：播放页下载按钮（widgets/card.dart:244 → `CacheController.download` → `getFileStream(url, withProgress: true)`，states/cache.dart:51-56）；起播时也会顺带 `getFileStream`（audio_handler.dart:215-219）。
- **清理逻辑**（fork cache_store.dart）：定时器（最短间隔 10s）在每次 DB 读后调度：① 超容量对象（`getObjectsOverCapacity`：touched 最旧优先、且超过 1 天未触碰的才删，限 100 行/次）；② 超过 stalePeriod 30 天的对象。删除即删文件+DB 行。
- **删除单集**：`CacheController.remove → cacheManager.removeFile(url)`（states/cache.dart:65-68）。
- **无字节上限、无仅 WiFi 等约束。**

### 4.2 封面图片缓存
`cached_network_image`（3.4.1）→ `DefaultCacheManager`（key `libCachedImageData`，默认 maxNrOfCacheObjects=200、stalePeriod=30 天）：
- 文件：`<Container>/Library/Caches/libCachedImageData/<uuid_v1>.<ext>`（2026-09-23 勘误，同 §4.1）
- 元数据：`<Container>/Library/Application Support/libCachedImageData.db`

### 4.3 字幕/LRC 文件
- 字幕正文存 DB（subtitle/translation 表 JSON 列），**不落独立文件**。
- 仅“导出字幕”时写临时文件：`getTemporaryDirectory()/<title - channel>.txt`（LRC 格式，`[mm:ss.mmm]` 时间戳两行一句，pages/player.dart:951-978、utils/formatters.dart `formatLrcTime`），随后 share_plus 分享。

### 4.4 iOS 沙盒目录推导汇总
| 内容 | 绝对路径 |
|---|---|
| 主 DB | `<Container>/Documents/anycast.db`（+ 事务期 `-journal`） |
| OPML 导出产物 | `<Container>/Documents/anycast_subscriptions.xml` |
| 音频缓存文件 | `<Container>/Library/Caches/anycast_episode/`（2026-09-23 实机勘误，原记 tmp/） |
| 音频缓存元 DB | `<Container>/Library/Application Support/anycast_episode.db` |
| 图片缓存文件 | `<Container>/Library/Caches/libCachedImageData/` |
| 图片缓存元 DB | `<Container>/Library/Application Support/libCachedImageData.db` |
| 字幕导出临时文件 | `<Container>/tmp/*.txt` |

---

## 5. OPML 导入导出

### 导出（lib/widgets/import_export.dart:133-152、388-400）
- 写入 `getApplicationDocumentsDirectory()/anycast_subscriptions.xml`（UTF-8 bytes），再经 share_plus 以 `text/xml` 分享。每次导出**覆盖同一文件名**。
- 格式（generateOPML）：`OpmlHeadBuilder().title('Anycast Subscriptions')`；每个订阅一个 outline，属性：`title` = 订阅 title、`text` = description、`type='rss'`、`xmlUrl` = rssFeedUrl；`toXmlString(pretty: true)`（opml 0.4.0）。

### 导入（file_picker 路径）
- `FilePicker.platform.pickFiles(type: FileType.any)` 单文件（import_export.dart:75-77）→ `parseOPML(path)`。
- `parseOPML`（lib/pages/feeds.dart:269-297）：用 xml 包解析，遍历**所有** `<outline>` 元素（含嵌套），取属性 `xmlUrl`（必需）与 `title`（缺失时回退 `text`），二者齐全才收录。
- 之后 `importPodcastsByUrls(urls)` 并发（8 路，rss_fetcher.dart:82-85）抓取 RSS，成功者写 `subscription` + 首条 `feedEpisode`（import_export.dart:90-97）。

### 导入（系统分享路径）
- Share Extension（iOS 原生，`ios/Share Extension/ShareViewController.swift`）把分享的文件**复制到 App Group 容器根目录**（保留原文件名；图片写到 `TempImage.png`；视频缩略图为 `base64(文件名).jpg`），并将 `[SharedMediaFile]` JSON 写入 App Group UserDefaults；主 App 由 `ReceiveSharingIntentPlugin.swift` 读取后 `ShareController._parseOPML`（states/share.dart:63-74）解析同一 parseOPML。

### 去重逻辑
- `importPodcastsByUrls` 里的“已订阅过滤”被**显式短路**：`s = {};`（rss_fetcher.dart:25-26，逐字），即不做内存去重。
- 实际去重完全靠 DB 唯一约束：`SubscriptionModel.addMany` batch `ConflictAlgorithm.replace`（subscription.dart:86-95，撞 rssFeedUrl 或 title 即整行替换、id 变化）；`FeedEpisodeModel.insertMany` 同理按 enclosureUrl 替换（feed_episode.dart:79-87）。

---

## 6. 与服务端的数据同步

**结论：订阅、播放列表、历史均为纯本地数据，无服务端同步；服务器只提供搜索/转写/翻译/聊天/账户接口。**

- 服务端 host：`anycast.website`（api/podcasts.dart:8、api/user.dart:8、api/subtitles.dart:6）。已用 API：
  - `GET /api/search/channels`、`GET /api/search/episodes`（limit=20）、`GET /api/categories`、`GET /api/top-channels`（发现页，无鉴权）
  - `POST /api/subtitles`（鉴权，转写状态轮询：内存里 status='processing' 的每 15s 轮询一次，states/subtitle.dart:24-49）
  - `POST /api/subtitles/translate`（**无鉴权**）
  - `POST /api/subtitles/chat`（鉴权；仅带最近 10 条历史，states/chat.dart:28-35；聊天记录本身 InMemoryChatController **不持久化**）
  - `GET/DELETE /api/user`（账户信息/注销）
  - `POST /api/shortlink`（分享短链）
- **刷新**：`fetchNewEpisodes`（pages/feeds.dart:299-319）**直接并发抓取所有订阅的 RSS 源**（不经服务端），`saveNewEpisodes`（feeds.dart:321-357）以 `subscription.lastUpdated`（ms）为准：本地 ≥ 拉取值 → 跳过（**本地赢**）；本地旧 → 用 RSS 抓取结果整行 replace 订阅、插入更新的单集（**线上/RSS 赢**）。首次（lastUpdated==null）只加第一条单集。
- **历史不上传**；转写/翻译结果由服务端生成后仅落本地库。
- **登录/登出对本地数据零影响**：`signOut`（states/user.dart:225-232）只做 `Purchases.logOut` + Firebase signOut + GoogleSignIn signOut，**不清任何本地表/文件**；注销账户（pages/login.dart:796-799）也只调 `DELETE /api/user` 后 signOut。登录的副作用仅是：Firebase uid 变化 → `Purchases.logIn(uid)`（RevenueCat 换匿名/实名用户，states/user.dart:53-59、261-265）。
- 回归测试含义：换账号登录/登出后，订阅、播放列表、历史、设置、缓存全部保留原样。

---

## 7. iCloud / Keychain / App Group / UserDefaults

- **iCloud：完全未使用**（Runner.entitlements 无任何 iCloud 键；无 CloudKit/NSUbiquitousKeyValueStore 代码）。
- **App Group：`group.com.kindjeff.ShareExtention`**（注意拼写 "Extention"；Runner.entitlements 与 Share Extension.entitlements 均声明；pbxproj `CUSTOM_GROUP_ID`）。
  - Extension 写入：App Group 容器根目录的分享文件副本 + `UserDefaults(suiteName: group...)`：key `"ShareKey"`（Data，`[SharedMediaFile]` 的 JSON）与 `"ShareMessageKey"`（String 文本）（ShareViewController.swift `saveAndRedirect`；插件侧常量 `kUserDefaultsKey = "ShareKey"`，ReceiveSharingIntentPlugin.swift:6-7、163-169）。主 App Info.plist 的 `AppGroupId` = `$(CUSTOM_GROUP_ID)` 提供读取入口。
  - **最终决策**：保留现有 Share Extension target **原样不动**（它本就是原生 Swift、与 Flutter 无耦合），仅主 App 侧从"经 receive_sharing_intent 插件读取"改为原生直接读同 group id 的容器文件与 `ShareKey`/`ShareMessageKey`（《05》§11）。
- **Keychain（均为第三方 SDK 写入，非业务数据）**：
  - **Firebase Auth（pubspec 约束 firebase_auth ^6.1.2，**lockfile 实解析 6.5.7**，pubspec.lock:316-323 → FirebaseAuth iOS SDK）**：登录态持久化在 iOS Keychain（firebase-ios-sdk `Auth.swift:1817-1818` 的 `keychainServiceForAppID` 与 `:1847-1854` 的 `"firebase_auth_\(app.options.googleAppID)"`）：`service = "firebase_auth_\(app.options.googleAppID)"`，本 App 即 **`firebase_auth_1:1092551717876:ios:5c9c489a2d619ca074ffa1`**；item 为 `kSecClassGenericPassword`，account 前缀 `firebase_auth_1_`（AuthKeychainServices.swift:22），`kSecUseDataProtectionKeychain=true`（AuthKeychainServices.swift:233）、`kSecAttrAccessible=AfterFirstUnlockThisDeviceOnly`（AuthKeychainServices.swift:193；2026-09-22 核验更正：原文误作 WhenUnlockedThisDeviceOnly——该属性意味着设备首次解锁前读不到登录态，自动恢复登录的可用窗口按此口径设计）。→ 原生 App 若继续用同一 Firebase 项目（GOOGLE_APP_ID 不变）并走 Firebase Auth，**登录态可无缝继承**；若原生改用其他登录体系，需要读取该 Keychain 值做一次性迁移（值为序列化的 user JSON）。
  - **Google Sign-In（pubspec 约束 google_sign_in ^7.2.0，**lockfile google_sign_in_ios 实解析 6.3.0**，pubspec.lock:588-595 / GTMAppAuth）**：OAuth 状态存 Keychain（`kSecClassGenericPassword`；service 前缀未在本仓库 Pods 中证实——GTMAppAuth Swift 版 service 由调用方传入，KeychainHelper.swift:45 仅确认 item 类型；2026-09-22 核验备注）。
  - **RevenueCat（purchases_flutter 9.16.1，约束 ^9.9.9）**：缓存 CustomerInfo 于**自己的 UserDefaults suite**（非 standard，key 前缀 `com.revenuecat.*`）；新版 SDK 的离线权益数据涉及 Keychain。App 以 Firebase uid 作为 `appUserID`（states/user.dart:261-265），原生侧保持 `Purchases.logIn(同一 uid)` 即可延续订阅身份。
  - Sign in with Apple entitlement（`com.apple.developer.applesignin: Default`）。
- **UserDefaults/NSUserDefaults**：业务代码零使用（无 shared_preferences）。间接使用：receive_sharing_intent（App Group suite，见上）、RevenueCat（自有 suite）、Sentry（少量标志位）。
- **Sentry（pubspec 约束 sentry_flutter ^9.8.0，**lockfile 实解析 9.26.0**，pubspec.lock:1077-1084；DSN 见 main.dart:56-57）**：未发送的事件/envelope 缓存在 App 的 Caches 目录（`<Container>/Library/Caches/sentry-*`），SDK 自管理，迁移可放弃。
- `.env`（含 `PURCHASES_IOS_API_KEY=appl_...`）打包进 assets（pubspec assets + dotenv.load，main.dart:37），不写沙盒。
- URL Scheme：`com.googleusercontent.apps.1092551717876-...`（Google 登录回调）与 `ShareMedia-$(PRODUCT_BUNDLE_IDENTIFIER)`（分享跳回）。

---

## 8. 数据量级与边界（供边界测试数据设计）

| 维度 | 约束 | 位置 |
|---|---|---|
| 收件箱 feedEpisode | 上限 maxFeedEpisodes ∈ {50,100,200,300}，每 60s 定时裁剪（`removeOld`） | states/player.dart:344-349、states/feed_episode.dart:134-147 |
| 历史 historyEpisode | 上限 maxHistoryEpisodes ∈ {50,100,200,300}，同样每 60s 裁剪 | states/history.dart:54-67 |
| 音频缓存 | 上限 maxCacheCount 个对象（默认 10，无 UI 改），stale 30 天；超容量且 >1 天未触碰才删 | states/cache.dart:10-15 + fork cache_store |
| 图片缓存 | 200 对象 / 30 天 | DefaultCacheManager 默认 |
| RSS 抓取 | 每批 8 个 URL 并发；每个订阅全量 items 解析、按 pubDate 降序 | rss_fetcher.dart:82-85、112-114 |
| 搜索 | limit=20 固定 | api/podcasts.dart:17、59 |
| 聊天 | 仅最近 10 条历史随请求发送 | states/chat.dart:28-35 |
| position 排序 | REAL 浮点；minPositionGap=0.0005；邻距过近触发全表重排为整数 | models/playlist_episode.dart:26、102-135 |
| `removeByEnclosureUrls`/`deleteMany` | 动态拼 `IN (?,?,...)` 占位符——一次删除量过大时可能触碰 SQLite 变量数上限（老版本默认 999），适合边界用例 | feed_episode.dart:71-77、history_episode.dart:90-97 |
| subscription 唯一性 | rssFeedUrl 与 title 双 UNIQUE + INSERT OR REPLACE：**同名不同源会顶掉旧订阅（id 改变）** | subscription.dart:6-9、86-95 |
| playlistEpisode 唯一性 | enclosureUrl 全表 UNIQUE：**同一集不能同时存在于两个播放列表** | playlist_episode.dart:14 |
| translation 唯一性 | enclosureUrl UNIQUE（language 不参与）：换目标语言会覆盖旧翻译 | translation.dart:13 |
| 文本字段 | 无任何长度校验/截断；description 直接存 RSS 原文（可能非常大、含 HTML） | rss_fetcher.dart:127-128 |
| pubDate/duration 空值 | RSS 缺 itunes:duration 时 duration 为 NULL；pubDate 理论可 NULL（`pubDate!.millisecondsSinceEpoch` 实际会崩，`channel.items!.sort` 同）——脏数据边界 | rss_fetcher.dart:112-131 |
| 睡眠定时 | hours 0-23；countdown 索引 0-6（OFF/10/20/30/40/50/60min） | states/player.dart:273-283 |

---

## 9. 迁移继承清单汇总表（同 bundle id 覆盖安装后可读到的全部数据）

| # | 路径（App 容器内） | 内容/格式 | 原生读取方式与注意点 |
|---|---|---|---|
| 1 | `Documents/anycast.db` | SQLite，user_version=4，9 张表（§1） | 直接 SQLite 打开。**坑**：① 所有布尔为 INTEGER 0/1；② 所有时间为 Unix **毫秒** INTEGER（pubDate/lastUpdated/duration/playedDuration），无 ISO 字符串、无时区问题；③ `playlistEpisode.position` 是 REAL 浮点排序键；④ `subtitle.subtitle`、`translation.translation` 是 JSON 数组字符串 `[{start:秒(double),end:秒(double),text}]`；⑤ `settings.autoSleepTimer` 是 `"a,b,c"` CSV；⑥ `translation` 是 AUTOINCREMENT（存在 `sqlite_sequence` 行）；⑦ 大量列可空（description/pubDate/duration 等）；⑧ `subtitle.summary` 恒 NULL；⑨ TEXT 无长度约束；⑩ 历史表"最新"按 id DESC 而非时间排序 |
| 2 | `Documents/anycast.db-journal` | 事务残留 | 仅在异常退出时存在；迁移时先正常打开让 SQLite 恢复/回滚，不要只拷贝主文件 |
| 3 | `Library/Caches/anycast_episode/`（2026-09-23 实机勘误，原记 tmp/） | 已下载音频，文件名 `UUIDv1.<mime扩展名>` | **必须**配合 #4 的 `relativePath` 列定位；系统可能清理该目录，需容忍空目录；同 enclosureUrl 的 URL→文件映射只在 DB 里（`url` 与 `key` 列均为资源 URL，见 §1.2 勘误） |
| 4 | `Library/Application Support/anycast_episode.db` | SQLite v3，表 cacheObject（_id/url/key/relativePath/eTag/validTill/touched/length） | 保留即可继承“已下载”状态；不迁移则下载进度/离线音频全部丢失（但可重新流播） |
| 5 | `Library/Caches/libCachedImageData/` + `Library/Application Support/libCachedImageData.db` | 封面缓存 | 纯缓存，可放弃，重下即可 |
| 6 | `Documents/anycast_subscriptions.xml` | 上次 OPML 导出文件（UTF-8） | 遗留产物，原生可无视或提示用户 |
| 7 | `tmp/*.txt` | 字幕导出的 LRC 临时文件 | 短命，可无视 |
| 8 | App Group `group.com.kindjeff.ShareExtention/` 容器 | 分享进来的 OPML/文件副本（原名）、`TempImage.png`、`<base64>.jpg` | 若保留同 group id 的 Extension 需继续兼容；旧残留文件可清理 |
| 9 | App Group UserDefaults | `ShareKey`=Data（SharedMediaFile JSON）、`ShareMessageKey`=String | 原生复刻分享接收时按同 key 读 |
| 10 | Keychain service `firebase_auth_1:1092551717876:ios:5c9c489a2d619ca074ffa1`（GenericPassword，account 前缀 `firebase_auth_1_`） | Firebase 登录用户 | 继续用 Firebase Auth + 同 GOOGLE_APP_ID 则自动继承；否则需读取迁移后删除 |
| 11 | Keychain（GTMAppAuth / Google 条目） | Google 登录 OAuth 状态 | 换原生 GoogleSignIn 同理可继承 |
| 12 | UserDefaults（RevenueCat 自有 suite，`com.revenuecat.*`） | 缓存的 CustomerInfo、appUserID | 原生 RevenueCat SDK 同配置会自动续用；关键是 logIn 同一 Firebase uid |
| 13 | `Library/Caches/sentry-*` | Sentry 待发事件 | 可放弃 |

**Flutter/Dart 序列化格式的原生坑位清单**：
- 没有任何 Dart `DateTime.toIso8601String` 落盘 —— 时间全是 int 毫秒（rss_fetcher.dart:131/139）。
- bool → INTEGER 0/1（settings.dart:103 等）。
- 复合结构 → TEXT 存 `jsonEncode`（subtitle/translation），数字为 Dart double（转写秒数，含小数）。
- OPML/AudioService 无二进制私有格式；数据库由 sqflite (iOS FMDB 系) 创建，标准 SQLite 文件，无加密、无自定义 header。
- **无 shared_preferences / NSUserDefaults 业务数据、无 iCloud、无 Keychain 业务数据、无加密** —— 除 #10/#11/#12 外全部在文件系统明文。

**关键风险点（建议进回归用例）**：① `tmp` 音频缓存被系统清理但元 DB 还在（fork 会自动删孤儿记录——原生侧需同样容错）；② subscription 的 title-UNIQUE 替换语义；③ playlistEpisode 跨列表唯一性；④ DB v3→v4 迁移路径（老用户连续播放开关默认值）；⑤ 历史表 id DESC 排序语义；⑥ position 浮点重排；⑦ 换语言覆盖翻译；⑧ 同 bundle id 覆盖安装后 Documents/LAS/tmp/Keychain 均保留、`tmp` 可能被清 —— 启动时对旧库的打开与默认行 `INSERT OR IGNORE` 的幂等性。
