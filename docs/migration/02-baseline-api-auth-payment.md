# 基线盘点 02：网络层 / 认证 / 付费（API 契约的事实来源）

> 用途：iOS 原生化迁移的 API 契约回归测试设计输入。要求：**迁移后继续使用线上已有接口，用户系统和付费系统行为保持一致**。
> 后端 Host：`https://anycast.website`（另有一个短链域名 `https://s.kindjeff.com`）
> HTTP 库：Dart `package:http`（`IOClient`，默认 UA 为 `Dart/x.y (dart:io)`，本项目未自定义任何 UA / header）
> 重要架构事实：除转写/聊天/用户 3 组接口外，**搜索、分类、趋势、翻译、短链均无认证**；RSS 订阅源为**客户端直抓**（不走自家后端）。

---

## 一、API 端点全清单

### 1.1 用户

#### `GET /api/user` — 获取用户信息（需认证）
- 文件：`lib/api/user.dart:33-49`
- 调用：`reqWithAuth('$host/api/user', method: 'GET')`，host 常量 `'https://anycast.website'`（`lib/api/user.dart:8`）
- Header：`Authorization: Bearer <Firebase ID token>`（由 `lib/utils/http_client.dart:28-33` 注入）
- 无参数
- 响应 JSON（逐字段，`User.fromJson`，`lib/api/user.dart:17-31`）：
  - `uid`: string — Firebase uid
  - `expired_at`: string|null — Plus 到期时间，格式 `yyyy-MM-ddTHH:mm:ssZ`（如 `2024-07-29T15:35:52+00:00`），null 表示非 Plus
  - `remaining`: int — 剩余转写次数（免费用户总量；Plus 用户为当月剩余，UI 上配合 `plus` 显示 "(this month)"）
  - `plus`: int — 是否 Plus（1 = Plus，UI 判断 `user.plus == 1`，`lib/pages/login.dart:331`）
- 错误处理：**401 → `ErrorHandler.handle401()` 弹出登录页 bottom sheet，返回 null**（`lib/api/user.dart:36-39`）；**注意 try 块只包住 `User.fromJson`（user.dart:43-48），`jsonDecode(resp.body)` 在 try 之外（user.dart:41）**——2026-09-22 核验更正：① `fromJson` 抛错（字段缺失/类型不符）→ debugPrint + 返回 null（不弹窗）；② **响应体非合法 JSON（如 500 返回 HTML）→ 异常直接冒泡**到 FutureBuilder 的 error 态、UI 永卡 "..."（归 K4 崩溃族修复，回归按②断言）
- 调用点：仅登录页 "Subscription Info" 卡片的 FutureBuilder（`lib/pages/login.dart:323-353`），无缓存，每次打开登录页都请求
- 分页：无

#### `DELETE /api/user` — 删除账号（需认证）
- 文件：`lib/api/user.dart:51-60`
- 无 body。响应：**只看 statusCode，200 即成功**（返回 `true`）；非 200 → `ErrorHandler.handle(statusCode, resp)` 并返回 null
- UI 入口：登录页 "Permanently Delete Account"（`lib/pages/login.dart:752-830`，确认后 `deleteUser()` → `Get.back()` ×2 → `AuthController.signOut()`，即后端删除后本地登出；**Firebase 账号由后端删除——2026-09-22 核实更正：经 Identity Toolkit REST API 而非 Admin SDK**（backend `src/routes/api/user/+server.ts:62-67`），客户端不调用 Firebase 删除）
- 注意：`reqWithAuth` 的 DELETE 分支**不发送 body**（`lib/utils/http_client.dart:59-63`）

### 1.2 播客搜索 / 分类 / 趋势（全部无认证）

#### `GET /api/search/channels?keyword=<text>&limit=20` — 搜索频道
- 文件：`lib/api/podcasts.dart:10-30`
- 通过 `fetchWithRetry`（10s 超时，失败重试 2 次总计，异常时返回 null → 上层 `response!` 会抛错，见 4.2）
- 响应（`lib/api/podcasts.dart:26-29, 32-43`）：
```json
{ "data": { "channel_list": [ {
  "rss_url": string, "title": string, "description": string,
  "small_cover_url": string(封面图), "link": string,
  "keywords": string[](→本地拼成逗号分隔 categories), "author": string
} ] } }
```
- `title/description/author` 客户端会 `.trim()`
- limit 固定 20，**无分页/游标**

#### `GET /api/search/episodes?keyword=<text>&limit=20` — 搜索单集
- 文件：`lib/api/podcasts.dart:52-84`
- 响应：`{ "data": [ episode ] }`，episode 字段（`lib/api/podcasts.dart:69-81`）：
  - `title`: string；`description`: string
  - `duration`: int（**毫秒**，直接存入本地 duration）
  - `url`: string（即 enclosure 音频直链）
  - `release_date`: string ISO8601（`DateTime.parse` 解析，`lib/api/podcasts.dart:77, 86-91`）
  - `cover_url`: string
  - `channel`: 同上 channel 对象（含 `rss_url` 等）
- limit 固定 20，无分页

#### `GET /api/categories` — 分类列表（Discover 页 Tab）
- 文件：`lib/api/podcasts.dart:102-123`
- **裸 `http.get`，无重试、无超时、无错误处理**（异常直接抛给 FutureBuilder）
- 响应：`{ "data": [ { "name": string, "id": string, "image_url": string, "night_image_url": string } ] }`
- UI：Discover 页 Tab 列表（`lib/pages/discover.dart:38-46`）

#### `GET /api/top-channels?category_id=<id>&country=<CODE>` — 某分类某国趋势频道
- 文件：`lib/api/podcasts.dart:125-159`
- 裸 `http.get`，无重试/超时
- 响应：`{ "data": { "list": [channel对象同上] } }`；**`data` 可为 null**（代码显式判空返回空列表，`lib/api/podcasts.dart:142-144`）
- `country` 取自本地设置 `SettingsController.countryCode`（默认 `'US'`，`lib/states/player.dart:263`；49 国列表在 `lib/pages/settings.dart:34-84`）
- 无分页

### 1.3 转写字幕 / 翻译 / AI 聊天

#### `POST /api/subtitles` — 触发转写 & 轮询状态（需认证，核心付费接口）
- 文件：`lib/api/subtitles.dart:35-71`
- Body：`{ "enclosure_url": string }`（音频直链即业务主键）
- Header：Bearer + `Content-Type: application/json`（`reqWithAuth` 有 data 时自动加，`lib/utils/http_client.dart:34-37`）
- 超时 10s；**状态机接口**：同一个 POST 既触发转写又返回当前状态，客户端每 15s 轮询（`lib/states/subtitle.dart:24-48`）
- 响应 JSON：
  - 非 2xx → `ErrorHandler.handle(code, resp)`，本地状态置 `failed`（`lib/api/subtitles.dart:44-47`）
  - `status`: string — `"processing"` / `"succeeded"` / `"failed"`（其他中间值客户端按原样保存，继续轮询）
  - `succeeded` 时：
    - `subtitle.detected_language`: string（如 `"en"`）
    - `subtitle.segments`: `[{ "start": double秒, "end": double秒, "text": string }]`
- 客户端状态流转（`lib/states/subtitle.dart`）：
  - `add(url)`（`lib/api/subtitles.dart` 调用于 `lib/pages/player.dart:524-527` 的 "Generate transcript with AI" 按钮）：先本地 DB 写 `processing` → POST → `succeeded` 存库（含 language + segments JSON）/ `failed` 删本地记录（UI 回到生成按钮，`lib/pages/player.dart:595-609` Retry 按钮）
  - 每 15s 的 Timer 扫所有 `processing` 的 url 重新 POST 轮询（2026-09-22 走查补充：迭代中对 `subtitleUrls` 边遍历边 `remove` 会抛 ConcurrentModificationError、该轮中断下轮恢复——原生遍历快照，勿照抄）
  - **"自愈"重触发分支（K28）**：本地已有 `succeeded` 但存储文本为 null/空/`'null'` 时，删本地记录置回 `processing` 重新 POST（`lib/pages/player.dart:610-624`）——L2 回放必须覆盖
- **错误分流补充（2026-09-22 走查）**：`ErrorHandler.handle` 内部对 401 也分流 `handle401`（`lib/api/error_handler.dart:15-21`）——即 subtitles/chat 的非 2xx 若为 401 同样弹登录 sheet，不只 `getUser` 的专门分支；后台轮询路径的错误弹窗/中断语义按《05》K27 处置（主动触发弹窗、轮询静默）
- **配额/付费墙完全在服务端**：免费额度（新用户 3 次，登录页文案 `lib/pages/login.dart:46`）或 Plus 月 50 次用尽时后端返回非 2xx（403 + error 文案），客户端只弹 ErrorHandler 对话框；`remaining` 仅用于展示

#### `POST /api/subtitles/translate` — 字幕翻译（**无认证！**）
- 文件：`lib/api/subtitles.dart:73-99`
- Body：`{ "enclosure_url": string, "language": string }`（language 为目标语言代码如 `"zh"`，11 种，见 `lib/pages/settings.dart:20-32`）
- Header：仅 `Content-Type: application/json`，**无 Authorization**；裸 `http.post`，**无超时、无重试、无 try/catch**
- 响应：`{ "translation": [ { "start": double, "end": double, "text": string } ] }` 或 `{ "translation": null }`（null → 返回 null，不翻译）
- 触发逻辑（`lib/states/translation.dart:20-35`）：每 10s Timer，对本地已 `succeeded` 的字幕且 `targetLanguage != ''` 且字幕 `detected_language != 目标语言` 时请求；结果持久化本地 DB（TranslationModel），语言切换会清空 translationUrls 重新触发（`lib/states/player.dart:452-458`）

#### `POST /api/subtitles/chat` — AI 聊天（需认证，**非流式！**）
- 文件：`lib/api/subtitles.dart:101-122`
- Body：
```json
{ "enclosure_url": string,
  "user_input": string,
  "history": [ {"human": "文本"}, {"ai": "回复"} ... ] }
```
  - history 格式特殊：**每个元素是单键 map，键为 `"human"` 或 `"ai"`**（`lib/states/chat.dart:26-35`：取最近 10 条，倒序恢复时间正序）
- **不是 SSE / 不是流式**：单次 POST，等完整响应；超时 10s（`reqWithAuth` 默认）
- 响应：`{ "result": string }`；**非 2xx 时直接把 `resp.body` 原文当作 AI 回复显示**（`lib/api/subtitles.dart:115-117`，如 403 的 error JSON 会显示成聊天消息——迁移时建议保持同样宽松处理或改进）
- UI：`lib/pages/chat.dart`（flutter_chat_ui），AI 占位消息 "..."，返回后整条替换（`lib/states/chat.dart:40-71`）

### 1.4 分享短链

#### `POST https://anycast.website/api/shortlink` — 生成短链（无认证）
- 文件：`lib/api/share.dart:12-53`
- Body：`{ "cmd": "add", "url": string(完整分享URL), "password": "cjp2PGN3zuf5cfh"(**硬编码**), "key": md5(url) }`
- 超时 **3s**，`retry` maxAttempts **3**（仅 SocketException/TimeoutException）
- 响应：`{ "status": 200, "key": string }` → 拼成 `https://s.kindjeff.com/<key>`；status≠200 / 请求失败 → 返回 null，**降级使用原始长链**（各调用点逻辑一致）
- 被短链的目标 URL（Web 分享页）：
  - `https://anycast.website/player?rssfeedurl=<RSS>&enclosureurl=<音频>`（`lib/pages/player.dart:178-186`、`lib/widgets/detail.dart:165-172`）
  - `https://anycast.website/channel?rssfeedurl=<RSS>`（`lib/pages/channel.dart:361-367`）
  - 注意 query key 全小写

---

## 二、认证流全流程

### 2.1 登录方式与 Firebase 调用（`lib/states/user.dart:18-233`）

| 方式 | Firebase 方法 | 细节 |
|---|---|---|
| Google | `FirebaseAuth.signInWithCredential(GoogleAuthProvider.credential(idToken))` | `lib/states/user.dart:61-83`。Google 侧用 **google_sign_in 7.x 新 API**：`GoogleSignIn.instance.initialize()`（`:38-42`，**无任何参数**，未传 serverClientID）→ `authenticate()` → `googleUser.authentication.idToken` → 构造 credential（**只用 idToken，无 accessToken**，`:11-16`，测试 `test/google_sign_in_credential_test.dart` 断言了这一点） |
| Apple | `FirebaseAuth.signInWithProvider(AppleAuthProvider()..addScope('email')..addScope('name'))` | `lib/states/user.dart:85-94`，走 iOS 原生 ASAuthorization；entitlements 已开 `com.apple.developer.applesignin`（`ios/Runner/Runner.entitlements`） |
| Email | `signInWithEmailAndPassword` | `lib/states/user.dart:163-223`；**注册功能被注释禁用**（`:96-161` 注释掉的 `registerWithEmail`；UI 点 Register 弹 "We don't support email registration yet"，`lib/pages/login.dart:923-941`） |
| 匿名 | **无** | 未使用匿名登录 |

- **无匿名/游客模式**，未登录时 `getToken()` 返回 null。

### 2.2 Google Sign-In 配置（iOS 迁移重点）

- iOS `Info.plist` 中**没有 `GIDClientID`**；URL Scheme 为 `com.googleusercontent.apps.1092551717876-ugib9p1irmilcqr6hcshcmnj9sg6edfm`（`ios/Runner/Info.plist:44-52`）
- google_sign_in_ios 6.1.0+ 在 Info.plist 无 `GIDClientID` 时会**回退读取 `FirebaseApp.options.clientID`**（即 `ios/Runner/GoogleService-Info.plist` 的 `CLIENT_ID = 1092551717876-ugib9p1irmilcqr6hcshcmnj9sg6edfm.apps.googleusercontent.com`，Firebase 项目 `anycast-412313`）。因此 **ID token 的 audience 是这个 iOS client ID**，由 Firebase Auth 换取 Firebase 自有 token，后端只验 Firebase ID token，audience 问题被 Firebase Auth 屏蔽
- `serverClientID` 从未配置（`initialize()` 无参）——**迁移原生后若需要直连 Google 拿 ID token，务必沿用同一 Firebase 项目与 client ID，或仍走 Firebase Auth 的 `signIn(with:)`**

### 2.3 Token 的获取与传递

- `AuthController.getToken()`（`lib/states/user.dart:44-51`）：`user.value!.getIdToken()` — Firebase SDK 缓存的 ID token，**过期时 SDK 用 refresh token 静默刷新**（`forceRefresh: false`）
- 传递：`reqWithAuth` 每次 `headers['Authorization'] = 'Bearer $token'`（`lib/utils/http_client.dart:33`）
- **后端无自有 session**：每个需认证请求都带 Firebase ID token，服务端逐请求验证（客户端代码里没有任何 session cookie / refresh 端点 / token 存储逻辑）
- 未登录时 `reqWithAuth` 直接返回合成的 `http.Response('Unauthorized', 401)`，不发请求（`lib/utils/http_client.dart:29-31`）

### 2.4 401 / 403 的行为（`lib/api/error_handler.dart`）

- `handle401()`（`:44-53`）：**弹出 LoginPage 的全屏 material bottom sheet**（`closeProgressThreshold: 0.9`）。**不静默刷新 token、不清任何本地数据**（token 新鲜度完全依赖 Firebase SDK）
- `handle403(response)`（`:55-86`）：解析 body `{ "error": string, "code": int }`
  - `code == 2` → 视为会话失效，转 `handle401()`（弹登录页）
  - 其他 → 弹 AlertDialog 显示 `error` 文案（配 "OK"）
- 其他非 2xx（含 404/429/5xx）：`handle()`（`:11-42`）弹 `Error <code>` 对话框，内容为原始 `response.body`。**429 没有任何专门处理**（无退避、无提示重试节奏）
- 登录页的两个入口：ErrorHandler 401/403-2；设置页 "Account"（`lib/pages/settings.dart:111-121`）

### 2.5 登出与删除

- `signOut()`（`lib/states/user.dart:225-232`）：顺序为 `RevenueCatController.signOut()`（`Purchases.logOut()`，**离线时捕获 PlatformException 继续登出**，`lib/states/user.dart:308-318`，测试 `test/revenue_cat_controller_test.dart` 覆盖）→ `FirebaseAuth.signOut()` → `GoogleSignIn.signOut()`（仅当已 initialize）。Apple 登出无额外处理（token 撤销未做）。**不清理本地订阅/字幕/播放列表数据库**
- 删除账号：`DELETE /api/user` 成功后走上述 signOut（`lib/pages/login.dart:785-800`）

---

## 三、RevenueCat 付费系统

### 3.1 配置与初始化（`lib/states/user.dart:235-326`）

- **API key**：`flutter_dotenv` 读 `.env`（`lib/main.dart:37` 加载；`.env` 打进 assets，`pubspec.yaml:144`）
  - iOS：`PURCHASES_IOS_API_KEY=appl_oplkVfezqWHLgIoUNZyXCJNWiiJ`
  - Android：`PURCHASES_ANDROID_API_KEY=goog_EmWWZmTQMDJLEkEdixtJeubvctF`
- `initPlatformState()`（`lib/states/user.dart:254-275`）：`PurchasesConfiguration(key)`；若 Firebase 已登录则 `configuration.appUserID = user.uid`；`Purchases.setLogLevel(LogLevel.debug)`；`getCustomerInfo()` 后 `addCustomerInfoUpdateListener`
- **appUserID = Firebase uid**：登录态变化时再显式 `Purchases.logIn(uid)`（`lib/states/user.dart:29-34, 53-59`）——**RevenueCat 账号体系与 Firebase uid 一一对应，迁移原生后必须保持同一 uid，否则用户订阅丢失**

### 3.2 Entitlement / 产品

- **Entitlement 标识：`plus`**（`lib/pages/login.dart:379`：`customerInfo.entitlements.active['plus']`）
- 判断订阅活跃：`entitlements.active.isNotEmpty`（任意 entitlement，`lib/states/user.dart:303-306`）
- **产品标识**：iOS `anycast_monthly`（默认选中，`lib/states/user.dart:239`）；Android `anycast_plus:monthly`（`:249-251`）。年费包靠 `packageType == PackageType.annual` 识别（`lib/pages/login.dart:608`）
- Offerings：`Purchases.getOfferings()` → `offerings.current.availablePackages`（`lib/pages/login.dart:469-477`），按 identifier 与 `choosenPlan` 匹配

### 3.3 购买 / 恢复 / 展示

- **购买入口唯一：登录页付费墙卡**（`_buildPaywall`，`lib/pages/login.dart:417-602`）。流程：选 Monthly/Yearly 卡片（tap 改 `choosenPlan`）→ "Confirm purchase"（`:498-534`）→ `purchasePackage`（`PurchaseParams.package(pkg)` → `Purchases.purchase`，`lib/states/user.dart:277-286`）→ 成功后 `_updateCustomerInfo` 驱动 Obx 刷新；**失败仅 print，无错误弹窗**
- **恢复购买**：付费墙下方 "restore purchases"（`lib/pages/login.dart:546-589`）→ `Purchases.restorePurchases()`；`entitlements.active.isEmpty` → "No active entitlements" 弹窗，否则 "Restored purchases" 成功弹窗
- 订阅状态展示（`lib/pages/login.dart:319-415`）：
  - 未订阅 → "Basic Plan" + `remaining` " Transcriptions left"
  - 已订阅 → "Anycast Plus" + `Plan expires on <expirationDate 本地化 yyyy-MM-dd HH:mm>` + `remaining` " Transcriptions left (this month)"
  - **过期/退款表现**：RevenueCat listener 推送后 `isSubscribed` 变 false → 卡片自动降回 "Basic Plan"；`remaining` 重新由 `/api/user` 的服务端口径决定。无专门的过期弹窗
- Plus 权益文案（`lib/pages/login.dart:676-750`）：每月 50 次 AI 转写、无限字幕翻译、导出字幕到笔记软件

### 3.4 付费墙位置（关键结论）

- **客户端没有用 `isSubscribed` 挡任何功能**。全局 grep 确认 `isSubscribed` 只在登录页做展示
- 真正的闸门在服务端：`POST /api/subtitles`（转写，免费 3 次/Plus 月 50 次）、聊天/翻译的服务端策略；客户端只呈现 `remaining`/`plus` 与 403 弹窗
- **迁移原生时若在客户端加付费墙，属行为增强而非契约破坏，但要保持服务端 403 文案展示逻辑一致**

### 3.5 deleteUser 时的 RevenueCat

- 删除账号**只调用自家后端 `DELETE /api/user`**，客户端不调用任何 RevenueCat 删除 API；随后 `signOut()` → `Purchases.logOut()`（本地登出，RevenueCat 后台账号仍存）。**后端如何联动 RevenueCat（webhook / API key）需迁移时向后端确认**

---

## 四、错误处理与加载态

### 4.1 HTTP 层（`lib/utils/http_client.dart`）

- `my_retry`（`:10-19`）：`retry` 包，**仅对 `SocketException` / `TimeoutException` 重试**；HTTP 5xx 是正常返回值**不重试**；`maxAttempts: 2`（共尝试 2 次）；retry 包默认退避 base 200ms、±25% 抖动、上限 30s
- `reqWithAuth`（`:21-71`）：默认超时 **10s**；GET/POST/PUT/DELETE 分派；body 存在时 `jsonEncode` + `Content-Type: application/json`；DELETE 不带 body
- `fetchWithRetry`（`:73-83`）：GET 专用，10s 超时 + 重试，**吞掉所有异常返回 null**
- `fetchConcurrentWithRetry`（`:85-116`）：RSS 并发抓取，**每批 8 个并发**

### 4.2 各页面表现汇总

| 场景 | loading | 错误 | 空态 |
|---|---|---|---|
| 搜索 Channels/Episodes（`lib/pages/discover.dart:182-300`） | CircularProgressIndicator | `fetchWithRetry` 返回 null 时 `response!.bodyBytes` **抛空断言异常**（潜在 bug，FutureBuilder 进 error 态，UI 卡 spinner） | "No results" |
| Discover 分类 Tab | spinner（categories） | 异常 → 卡 spinner；`data.list` 空/`data==null` → "Network Error"（`lib/pages/discover.dart:72-79`） | "Network Error" |
| 转写（`lib/pages/player.dart:462-689`） | 未请求：绿色 "Generate transcript with AI (Beta)" 按钮；`processing`：Lottie 机器人 + "Generating with AI ... It may take 2 ~ 5 minutes ..." | `failed`：蓝色 Retry 按钮；非 2xx：ErrorHandler 弹窗 | — |
| 翻译 | "Translating subtitles..." + RefreshProgressIndicator（`lib/pages/player.dart:652-675`） | 无错误 UI（getTranslation 异常直接冒泡，Timer 内未捕获） | — |
| 聊天 | AI 气泡占位 "..."，`isLoading` 时禁止发送 | 非 2xx 的 body 原文显示为 AI 消息 | — |
| 用户信息卡 | `'...'`（getUser null/加载中） | 同左 | — |
| Offerings | spinner | 无 | — |
| RSS 刷新（`lib/pages/feeds.dart`） | EasyRefresh BezierHeader + 线性进度条（`(progress+8)/total`，`lib/pages/feeds.dart:32-59, 303-323`） | 单个 RSS 失败跳过（isolate 里返回 null） | 空收件箱显示 ImportBlock |
| OPML 导入 | ImportProgressIndicator 圆形进度 | 解析失败/空 → "no valid links" 对话框（`lib/widgets/share.dart:14-49`） | — |

### 4.3 已有测试

- `test/google_sign_in_credential_test.dart`：断言 credential 只含 idToken 无 accessToken
- `test/revenue_cat_controller_test.dart`：mock `purchases_flutter` channel，断言离线时 `logOut` 抛 PlatformException 也能完成 signOut
- `test/widget_test.dart`：仅构造根 Widget

---

## 五、第三方网络行为

### 5.1 Sentry（`lib/main.dart:54-66`）

- DSN `https://9168d8befab4c7bb5eeecd15beb2daa2@o359483.ingest.us.sentry.io/4507654787170304`，`tracesSampleRate 1.0`、`profilesSampleRate 1.0`（**全量采样**）
- `SentryFlutter.init` 包裹 `runApp` → 自动捕获未处理 Flutter 异常；**代码中无任何手动 `Sentry.captureException/captureMessage`**；Dart http 客户端未接 SentryHttpClient（API 请求本身不被 trace，除非 SDK 内部 hook）
- Firebase Analytics：**完全未使用**（pubspec 无 analytics 包，grep 无引用）

### 5.2 Firebase（`lib/main.dart:50-52`）

- 仅 `Firebase.initializeApp(DefaultFirebaseOptions.currentPlatform)`；项目 `anycast-412313`，iOS appId `1:1092551717876:ios:5c9c489a2d619ca074ffa1`，apiKey `AIzaSyAH3IukjkrqakBZiTjgAI-3uSfUzYeTU3U`（`lib/firebase_options.dart:61-65`）；bundle id `com.kindjeff.anycast`
- 只用 Auth（三种登录），无 Crashlytics/Messaging/Remote Config

### 5.3 RSS 抓取 —— 客户端直抓，不走后端

- `lib/utils/rss_fetcher.dart:75-157`：在**独立 Isolate** 中按 **8 个一批并发** `http.get` RSS 原始 URL（无代理、无自定义 UA、无认证；`NSAppTransportSecurity` 在 iOS 上 `NSAllowsArbitraryLoads=true` 允许 http 明文源，`ios/Runner/Info.plist:61-66`）
- 解析全在客户端：`webfeed_plus` 的 `RssFeed.parse`（XML）+ `html` 包做 description 的 HTML→text（`rss_fetcher.dart:96-111, 159-179`）；取 `itunes:image/author/duration/summary`、按 pubDate 倒序、**默认只取第一集**（`onlyFistEpisode`）
- 触发点：手动下拉刷新/自动刷新（**DB 默认 300s**——Rx 初值为 180 且定时器一次性读取，首启存在竞态，**口径以 DB 300 为准**，《01》§2 裁定；可 1/3/5/10/30 分钟，`lib/states/player.dart:265`、`lib/states/feed_episode.dart:110-132`〔2026-09-22 更正：原误作 pages/feeds.dart；`autoFetch` 的 1 分钟节流在 `:110-119`、`initAutoRefresher` 在 `:121-132`〕）、订阅频道页 `listAllEpisodes`（`lib/models/subscription.dart:104-105`）、OPML 导入（`lib/widgets/share.dart:105-119`）、播放器补 channel 信息 `getOrFetch`（`lib/models/subscription.dart:114-119`）
- 节奏补充（2026-09-22 走查）：**启动 2 秒后自动拉取一次**（`lib/states/feed_episode.dart:34-36`），与定时刷新同受 `autoFetch` 1 分钟节流去抖；手动下拉与定时刷新**无互斥**、可并发两轮 fetch；RSS 直抓同样走 `fetchWithRetry`（10s 超时 + 仅网络异常重试 2 次、失败跳过该源）；`Purchases.logIn` 失败仅 print 吞掉（`lib/states/user.dart:53-59`，原生按《00》M1 启动 DAG 修复时序）
- 后端存在客户端未调用的 `/api/proxy`（转发用，默认 UA `Mozilla/5.0`）——**非客户端契约，迁移时勿误纳入回放**
- OPML 解析在 `lib/pages/feeds.dart:269-300`（本地 XML，`outline` 元素的 `xmlUrl`/`title`/`text`）

### 5.4 音频与其余第三方请求

- 音频：`just_audio` 直接 `setUrl(enclosureUrl)` 播放（`lib/utils/audio_handler.dart:197-220`），配合 fork 版 `flutter_cache_manager` 做文件缓存；无自定义 header
- 图片：`cached_network_image`；占位图 `https://placehold.co/...`（`lib/pages/player.dart:168, 271`）
- 外链：隐私政策 `https://privacy.anycast.website`、Apple EULA、mailto 反馈（`lib/widgets/privacy.dart:18`、`lib/pages/settings.dart:461-468`），`url_launcher` inAppBrowserView

---

## 六、iOS 原生迁移注意点（契约红线）

1. **认证 header 逐字节一致**：`Authorization: Bearer <Firebase ID token>`；**有 body 才带 `Content-Type: application/json`，GET/DELETE 无 Content-Type**。后端若对无谓 header 敏感（或 WAF 规则匹配），原生实现应照抄
2. **后端无 session，每次都验 Firebase ID token**：原生端用 Firebase Auth iOS SDK 的 `user.getIDToken()`（同样有内部缓存+静默刷新），不要自建 token 存储；401 时不要自行刷新重试——现有行为就是直接弹登录页
3. **User-Agent 变化**：当前所有自家 API 请求 UA 是 `Dart/x.y (dart:io)`；RSS 直抓也是。换成 URLSession 默认 UA（`Anycast/1.2.1 CFNetwork/... Darwin/...`）后，**自家后端风控（若有）与第三方 RSS 服务器（不少对 UA 敏感、会 403 curl/Dart 类 UA）都可能表现不同**——RSS 抓取建议保留一个通用浏览器 UA 或做回退策略，自家 API 建议先以原生 UA 回归测试
4. **聊天不是流式**：`POST /api/subtitles/chat` 一次性返回 `{result}`；**10s 超时**是现有契约（长回答风险后端已适配）。原生实现 URLSession `dataTask` 即可，无需 SSE/WebView
5. **转写是"同接口触发+轮询"状态机**：POST `/api/subtitles` 幂等触发；客户端 15s 轮询直到 `succeeded/failed`。迁移时保持轮询节奏（15s）与失败即删本地记录的行为，避免对后端造成更高频的打点
6. **翻译接口无认证**：`/api/subtitles/translate` 目前裸调；原生不要"顺手"加 Authorization 以外的行为差异（加了大概率也无害，但需回归）；该接口**无超时**，原生要补超时的话注意别小于服务端实际耗时
7. **短链硬编码契约**：`password: 'cjp2PGN3zuf5cfh'`、`key = md5(url)`、`cmd: "add"`、3s 超时、3 次尝试、失败降级长链；短链域名 `s.kindjeff.com`。必须逐字保留
8. **重试语义**：仅网络层异常（socket/timeout）重试；`reqWithAuth` 总尝试 2 次、退避 ~200ms 抖动；HTTP 5xx/429 不重试。原生不要对 5xx 自动重试（尤其 `/api/subtitles`，可能重复触发转写计费/计数）
9. **错误协议**：403 body 是 `{error: string, code: int}`，`code==2` = 会话失效 → 登录页；其余非 2xx 弹原始 body。429 无专属处理（弹 Error 429 对话框）——迁移时如做退避，需确认后端 429 语义
10. **RevenueCat 对齐**：entitlement `plus`；iOS 产品 `anycast_monthly`；`appUserID = Firebase uid`（`logIn(uid)`）；登出必须 `Purchases.logOut()` 且离线容错。用同一个 RC 项目与 key（`appl_...`），原生 SDK 版本不同不影响契约
11. **分享 URL 格式**：`anycast.website/player?rssfeedurl=&enclosureurl=`、`/channel?rssfeedurl=`（**全小写 query key**），是 Web 端页面契约，别改大小写
12. **数据格式细节**：`duration`/`release_date`（ISO8601）、`expired_at`（`yyyy-MM-ddTHH:mm:ssZ`）、`remaining`/`plus` 语义、segments 的 `start/end` 为**秒（double）**、搜索 `limit=20` 固定、country 用 ISO 3166-1 alpha-2（49 国白名单）
13. **搜索空结果崩溃隐患**：`fetchWithRetry` 失败返回 null 时 `searchChannels`/`searchEpisodes` 用 `response!` 会抛异常（`lib/api/podcasts.dart:22, 64`）——这是 bug 不是契约，原生实现应返回失败态
14. **ATS**：现配置允许任意 http（很多 RSS 是 http），原生迁移若收紧 ATS 会导致部分旧源无法订阅

---

## 七、后端核实补充（2026-09-21，读 `~/proj/anycast-backend` 源码核实）

1. **免费额度实为 10 次/终身**（`src/lib/server/quota.ts:5` `FREE_USER_REMAINING = 10`），非登录页文案所写的 3 次；Plus = 50 次/自然月（月初重置）。§1.3 中"新用户 3 次"为客户端文案口径，非服务端行为。
2. **DELETE /api/user 已联动 RevenueCat**：删 Firebase 用户 → `DELETE api.revenuecat.com/v1/subscribers/{uid}` → 删库记录（`src/routes/api/user/+server.ts:56-88`）。
3. **应用层无任何 429/限流逻辑**：配额不足统一 403 + `{error, code}`；429 只可能来自 Cloudflare 边缘。
4. **入站无 UA 过滤**；后端出站抓 iTunes 系接口时硬编码 Chrome UA（外部源 UA 敏感的印证）。
5. plus/过期状态双通道更新：RC webhook（`/api/revenuecat/webhook`，SHA-256 恒时验签后回查 RC 写 `users.plus/expiredAt`）+ `GET /api/user` 惰性过期检查；配额幂等键为 `userSubtitles(uid, key=enclosure_url)`（重复请求不重复扣量）。
