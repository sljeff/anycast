# iOS 个人团队真机预览

本文面向需要在个人 iPhone 上检查 Anycast 视觉改动的维护者和自动化代理。目标是在不使用项目所有者签名、不修改当前工作树、不触发发布流程的前提下，构建、安装并验证一个可独立运行的 iOS 预览包。

## 范围

本流程只用于本地视觉检查：

- 使用本机已有的 `Apple Development` 证书和个人开发团队。
- 构建 Flutter `Profile`/AOT 包。
- 使用个人预览 Bundle ID。
- 在隔离工作区临时移除主 App 对 Share Extension 的构建依赖。
- 安装并启动到明确指定的物理 iPhone。
- 保留 DerivedData 缓存，减少后续编译时间。

本流程不执行以下操作：

- 不使用项目所有者团队 `5TQ9AN87D8`。
- 不更改仓库中的发布签名、Bundle ID、entitlements 或 Xcode 配置。
- 不调用发布证书、发布 provisioning profile 或 App Store Connect 密钥。
- 不运行 `scripts/prepare_ios_signing.sh`、发布流水线或商店上传。
- 不自动运行 `scripts/bootstrap.sh`。
- 不创建版本、标签、发布或商店候选。
- 不保证 Firebase 登录、RevenueCat 商品或 Share Extension 在个人预览 Bundle ID 下可用。

## 成功标准

只有同时满足以下条件，才算完成真机预览：

1. 构建日志显示选中的个人 `Apple Development` 证书。
2. App 的 `TeamIdentifier` 与该证书 subject 中的 `OU` 一致。
3. App Bundle ID 是个人预览 ID，不是 `com.kindjeff.anycast`。
4. App 通过嵌套 framework 和主 bundle 的完整签名验证。
5. `devicectl` 成功安装并启动 App。
6. Runner 进程持续存在。
7. 人在 iPhone 或 iPhone Mirroring 中确认首帧已经渲染，不是白屏。
8. 原始仓库的 `git status` 与运行脚本前一致。

进程存在只能证明 App 没有立即退出，不能证明 Flutter 已经绘制首帧。

## 快速路径

先查找物理设备 UDID：

```bash
xcrun xcdevice list --timeout 10
```

再执行只读预检：

```bash
./scripts/ios_personal_device_preview.sh \
  --device <PHYSICAL_IPHONE_UDID> \
  --certificate-id <APPLE_DEVELOPMENT_LABEL_SUFFIX> \
  --flutter-bin /absolute/path/to/flutter-3.38.3/bin/flutter \
  --dry-run
```

预检通过后，构建、安装并启动：

```bash
./scripts/ios_personal_device_preview.sh \
  --device <PHYSICAL_IPHONE_UDID> \
  --certificate-id <APPLE_DEVELOPMENT_LABEL_SUFFIX> \
  --flutter-bin /absolute/path/to/flutter-3.38.3/bin/flutter \
  --open-mirroring
```

如果 Xcode 尚未为个人预览 Bundle ID 创建 development profile，只有在用户明确授权 Xcode 联系 Apple 后，才添加：

```bash
--allow-provisioning-updates
```

这个选项可能在 Apple Developer 账户中创建或刷新 App ID、设备注册和 provisioning profile。自动化代理不得自行添加。

## 身份标识不能互换

Apple 开发签名包含多个看起来相似的十位标识。它们的用途不同。

```yaml
verified_session_2026_07_30:
  certificate_label_suffix: 4Y2CVN4C56
  certificate_subject_uid: D2NF9QKHRQ
  development_team_from_subject_ou: QY9ALBH92W
  personal_profile_expiration: 2026-08-05T05:54:13Z
  project_owner_team_forbidden_in_personal_preview: 5TQ9AN87D8
```

`4Y2CVN4C56` 出现在证书显示名称末尾，用于选择正确的 `Apple Development` 证书。它不是 Xcode 的 `DEVELOPMENT_TEAM`。

Xcode 的 `DEVELOPMENT_TEAM` 必须取自证书 subject 的 `OU`。本次验证中，该值是 `QY9ALBH92W`。

脚本不会接受手工猜测的 Team ID。它通过证书后缀选择唯一证书，再从证书 `OU` 自动推导 Team ID；如果推导结果是项目所有者团队 `5TQ9AN87D8`，脚本立即退出。

可用以下命令人工复核：

```bash
security find-identity -v -p codesigning
security find-certificate \
  -c 'Apple Development: <account> (<certificate-label-suffix>)' \
  -p |
  openssl x509 -noout -subject -nameopt RFC2253
```

不要把证书 label 后缀、subject `UID`、subject `OU` 和 provisioning profile UUID 当成同一个值。

## 自动化执行内容

`scripts/ios_personal_device_preview.sh` 按以下顺序执行。

1. 验证 macOS、Flutter `3.38.3` 和所需系统命令。
2. 验证指定 UDID 对应一个当前可用的物理 iPhone。
3. 用证书 label 后缀选择 identity，并确认个人 Team 下只有一个有效的 `Apple Development` identity。
4. 从证书 subject `OU` 推导 `DEVELOPMENT_TEAM`。
5. 拒绝项目所有者团队和正式 Bundle ID。
6. 验证 `.env`、`GoogleService-Info.plist` 和 `firebase_options.dart` 与仓库审核过的摘要一致，但不打印内容。
7. 查找匹配个人 Team、预览 Bundle ID、目标设备和 iOS 平台，且尚未过期的 development profile。
8. 在 `build/ios/personal-device-preview/workspace` 创建隔离副本。
9. 在隔离副本中执行 `flutter pub get --enforce-lockfile`。
10. 排除原工作区已有的 Flutter 绝对路径生成文件，并在完整 project 仍保留 Share Extension host 关系时执行 `flutter build ios --config-only --profile --no-codesign`；该命令重新生成隔离路径配置并执行 `pod install`。
11. 只在隔离 Xcode project 中应用个人 Profile 签名设置。
12. 只在隔离 project 中移除 Runner 对 Share Extension 的依赖和嵌入阶段。
13. 构建 `Profile`/AOT Runner。
14. 扫描 `Runner.app/Frameworks` 第一层 frameworks，补签未签名项，再重新签名主 App；最后用递归严格验证兜底。
15. 验证 Xcode 实际选择的签名 identity 与用户指定证书完全一致，并核对 Team ID 和 Bundle ID。
16. 解码 App 实际嵌入的 provisioning profile，重新核对 Team、application identifier、development 权限、目标设备、iOS 平台和有效期。
17. 安装并启动 App。
18. 用已安装 App 的精确容器 URL 轮询设备进程，确认该 Runner 没有立即退出。
19. 确认运行前后的仓库 `git status` 摘要一致。
20. 删除包含本地配置副本的隔离工作区，保留 DerivedData 和日志缓存。

完整构建日志写入：

```text
build/ios/personal-device-preview/logs/
```

脚本只在失败时打印日志末尾，避免把数十万行 Xcode 输出送入代理上下文。

## 本次事故复盘

### 把证书后缀当成 Team ID

用户明确指定 `4Y2CVN4C56`，但 Xcode 的 `DEVELOPMENT_TEAM` 不接受这个值。证书 subject 显示 `OU=QY9ALBH92W`，这才是实际 Team ID。

正确动作是通过证书后缀选择 identity，再从 subject `OU` 推导 Team ID。不要人工复制看起来相似的十位字符串。

### 误用项目所有者团队

项目中发布设置使用 `5TQ9AN87D8`。本地视觉预览没有权限借用该团队，也不应为了让 Bundle ID 或 Firebase 警告消失而切回它。

正确动作是使用个人 Team、个人 Bundle ID 和 development profile。自动化必须显式拒绝项目所有者团队。

### 直接启动 Flutter Debug 包

通过 `devicectl` 直接启动 Debug 包时，Flutter 输出：

```text
Cannot create a FlutterEngine instance in debug mode without Flutter tooling or Xcode.
```

iOS 14 及以上的 Flutter Debug 包需要 Flutter tooling 或 Xcode 调试会话。进程会立即退出，这不是样式代码崩溃。

正确动作是：

- 临时调试时由 Xcode 或 `flutter run` 启动；或
- 视觉验收默认使用可独立运行的 `Profile`/AOT 包。

本文和自动化选择第二种方法。

### Xcode 停在 LLDB 符号加载提示

本次会话中，Xcode 曾显示：

```text
Launching “Runner” is taking longer than expected.
LLDB is likely reading from device memory to resolve symbols.
```

提示框被其他窗口遮挡时，设备上会出现进程，但调试启动没有完成，用户只看到白屏。

点击 Continue 可以继续 Debug 启动，但这仍然不是稳定的视觉验收路径。Profile/AOT 不依赖该 LLDB 启动阶段。

### Debug 连接因应用在后台而断开

本次会话中，Xcode 控制台随后显示：

```text
The OS has terminated the Flutter debug connection for being inactive in the background for too long.
There are no errors with your Flutter application.
```

设备进程仍可能存在，但 Flutter 调试连接已经失效。再次点击桌面图标不能替代新的工具启动。

正确动作是重新由 Xcode/Flutter 启动 Debug，或改用 Profile/AOT。不要把后台断连误判为应用逻辑崩溃。

### `flutter run` 触发 CocoaPods host target 错误

临时移除 Runner 对 Share Extension 的引用后再执行 `flutter run`，Flutter 会自动调用 `pod install`。CocoaPods 随即报告找不到 Share Extension 的 host target。

正确顺序是：

1. 先在完整 project 中准备或复用 Pods。
2. 再只在隔离 project 中移除 Share Extension 的预览依赖。
3. 用 `xcodebuild` 构建主 Runner。

脚本按这个顺序执行。

### `Podfile.lock` 与 `Pods/Manifest.lock` 不一致

本次环境中的 `Podfile.lock` 记录 CocoaPods `1.16.2`，现有 Pods 由 `1.17.0` 生成。仅版本标记不一致也会触发 `[CP] Check Pods Manifest.lock`。

复制现有 `Pods.xcodeproj` 也不可取。Flutter plugin 的相对路径会按隔离工作区重新解释，可能错误指向 `build/ios/.pub-cache`。

脚本不复制原工作区的 `Generated.xcconfig` 和 `flutter_export_environment.sh`。它在隔离副本中、修改 Xcode target 关系之前执行一次：

```bash
flutter build ios --config-only --profile --no-codesign
```

Flutter 会重新生成指向隔离副本的绝对路径配置并调用 `pod install`。CocoaPods 使用本机缓存，生成与隔离路径一致的 project 和 `Manifest.lock`。脚本随后校验 `FLUTTER_APPLICATION_PATH`，路径仍指向原工作区时立即退出。

原始 `Podfile.lock` 和 Pods 不会被改写。

### Share Extension 阻止个人预览构建

Share Extension 依赖正式 App Group 和单独签名配置。它的 Debug/Profile 编译还可能无法解析 Runner 使用的 Flutter module。

视觉预览不需要 Share Extension。正确动作是只在隔离 project 中移除：

- Runner 的 Share Extension target dependency。
- Runner 的 Embed Foundation Extensions 阶段。

不要修改仓库中的正式扩展配置，也不要删除扩展源代码。

### 嵌套 framework 未签名

首次 Profile 安装被 iOS 拒绝：

```text
Failed to verify code signature ... RevenueCat.framework
0xe800801c (No code signature found.)
```

主 App 已签名并不代表 `Runner.app/Frameworks` 第一层的每个 framework 都已签名。

正确动作是：

1. 对 `Runner.app/Frameworks/*.framework` 逐个执行严格验证。
2. 只补签验证失败的 framework。
3. 重新签名主 App。
4. 对整个 App 执行 `codesign --verify --deep --strict`。

脚本会自动完成并核对最终 identity 与 Team ID。

### Firebase Bundle ID 警告不是缺少密钥

个人预览 Bundle ID 与审核过的 Firebase iOS 配置不同，因此控制台会提示：

```text
The project's Bundle ID is inconsistent with ... GoogleService-Info.plist
```

本次本机已经存在：

- `.env`
- `ios/Runner/GoogleService-Info.plist`
- `lib/firebase_options.dart`

`scripts/bootstrap.sh` 会生成并验证正式 `com.kindjeff.anycast` 配置。它不会为个人预览 Bundle ID 生成一套新的 Firebase 项目，也不会修复这个预期警告。

正确动作是验证现有配置摘要，然后接受个人视觉预览中的 Bundle ID 警告。不要为消除警告而改用正式 Bundle ID、项目所有者 Team 或发布密钥。

### RevenueCat 商品不可用不阻止视觉检查

RevenueCat 商品与正式 App Store Bundle ID 绑定。个人预览可能输出 offerings 或产品加载失败。

这不阻止检查颜色、文字、间距和基本导航。不要把个人预览当作订阅购买、恢复购买或商店集成验收。

### PID 不能替代画面验证

Runner PID 持续存在时，Flutter 仍可能停在白色 launch view 或初始化阶段。

正确动作是打开 iPhone Mirroring 或直接查看手机。若系统要求 Mac 登录密码，自动化代理必须把输入交给用户；不得读取、代填或记录密码。

## 配置与 `bootstrap`

自动化只验证本机现有配置，不生成配置。

当以下文件缺失或摘要不一致时，脚本会在编译前退出：

```text
.env
ios/Runner/GoogleService-Info.plist
lib/firebase_options.dart
```

只有获得当前对话中的明确授权，并确认使用 Infisical `dev` 环境后，维护者才能人工运行：

```bash
./scripts/bootstrap.sh dev
```

不要因为一次本地构建缺少配置就自动运行 bootstrap。不要使用 `release` 环境完成普通视觉预览。

## 失败处理

### 没有匹配的 development profile

先在 Xcode 的个人账号下为预览 Bundle ID 创建 profile，或在明确授权后添加：

```bash
--allow-provisioning-updates
```

如果 Xcode 请求账号登录、密码、双重验证、信任或设备设置，用户必须亲自完成。

本次验证的个人 profile 将于 `2026-08-05T05:54:13Z` 到期。到期后预检会把它视为不匹配；不要为了绕过到期检查而关闭验证。

### 手机锁定导致启动失败

安装可以在手机锁定时完成，但 SpringBoard 会拒绝启动并报告：

```text
Unable to launch ... because the device was not, or could not be, unlocked.
```

解锁手机后，不要重新编译。直接重试：

```bash
xcrun devicectl device process launch \
  --device <PHYSICAL_IPHONE_UDID> \
  --terminate-existing \
  <PERSONAL_PREVIEW_BUNDLE_ID>
```

### 安装完整性验证失败

查看安装日志：

```text
build/ios/personal-device-preview/logs/devicectl-install.log
```

如果错误仍指向嵌套 framework，先确认脚本输出包含完整 App 签名验证成功，再重试。不要关闭设备安全检查。

### App 仍然白屏

先确认运行的是 Profile 包，而不是 Debug 包：

```bash
xcrun devicectl device info processes --device <PHYSICAL_IPHONE_UDID>
```

然后用 Profile console 重新启动并观察初始化日志：

```bash
xcrun devicectl device process launch \
  --device <PHYSICAL_IPHONE_UDID> \
  --terminate-existing \
  --console \
  <PERSONAL_PREVIEW_BUNDLE_ID>
```

如果日志已经出现 Flutter semantics、页面控制器或网络请求，必须继续做真实画面检查。不要只凭 PID 或 “Launched application” 判断完成。

### 需要重新开始

DerivedData 缓存位于：

```text
build/ios/personal-device-preview/
```

它属于本地 ignored build output。只有在确认没有预览脚本正在运行后，才清理这个明确目录。不要删除仓库根目录、用户目录、Xcode 全局 DerivedData 或 provisioning profiles 来解决一次预览失败。

## 最终核对

每次交付真机预览前，确认：

- 证书是用户指定的 `Apple Development` identity。
- Team ID 来自该证书 `OU`，不是证书 label 后缀。
- Team ID 不是 `5TQ9AN87D8`。
- Bundle ID 不是 `com.kindjeff.anycast`。
- 构建模式是 Profile/AOT。
- App 和所有嵌套 frameworks 通过签名验证。
- 手机实际首帧可见。
- `git status --short --branch` 没有出现脚本造成的改动。
- 没有运行 bootstrap、release signing、tag、upload 或 store 操作。
