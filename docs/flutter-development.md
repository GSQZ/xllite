# Flutter 开发文档

## 技术栈

```text
Flutter: 3.41.7+
Dart: 3.11.5+
Platforms: Android, iOS only
State: flutter_riverpod
Routing: go_router
Network: dio
Model: freezed, json_serializable
Secure storage: flutter_secure_storage
Cache: secure storage first, drift later if needed
Lint: flutter_lints
```

选择 Flutter 的原因：新理Lite 的主体是 Android/iOS 双端数据查询和展示，Flutter 可以用一套代码同时覆盖两端，并且适合做课表、列表、卡片摘要和本地缓存。本项目不维护 Web、Windows、Linux、macOS 桌面端。

## 工程初始化建议

```bash
flutter create --org com.sayqz --project-name xinli_lite .
```

如果当前目录不是空目录，先确认不要覆盖已有文件。

## 推荐目录结构

```text
lib/
  main.dart
  app.dart
  core/
    config/
    http/
    router/
    storage/
    theme/
    utils/
    widgets/
  api/
    xjit_api_client.dart
    xjit_features.dart
    xjit_models.dart
  auth/
    data/
    domain/
    presentation/
  features/
    home/
    schedule/
    grades/
    exams/
    card/
    electricity/
    profile/
    settings/
```

## 分层约定

- `core/`: 全局基础设施，不依赖具体业务页面。
- `api/`: 对后端统一接口的封装，只处理请求、响应和 API 错误。
- `auth/`: CAS 凭据、本地安全存储、登录状态。
- `features/*/data`: 数据仓库、远端请求、本地缓存。
- `features/*/domain`: 业务模型和转换逻辑。
- `features/*/presentation`: 页面、组件、状态 provider。

## 状态管理

统一使用 Riverpod：

- 页面异步数据使用 `AsyncValue`。
- 每个功能模块暴露一个 repository provider。
- 需要刷新、分页、筛选的页面使用 `AsyncNotifier` 或 `Notifier`。
- 登录凭据只通过 auth provider 访问，不在页面之间手动传递密码。

## 路由规划

使用 `go_router`：

```text
/login
/home
/schedule
/grades
/exams
/card
/electricity
/profile
/settings
```

登录状态由路由重定向统一处理：

- 没有本地凭据时进入 `/login`
- 有本地凭据时进入 `/home`
- 退出登录后清除凭据并回到 `/login`

## UI 方向

新理Lite 应该是清爽、密度适中的校园工具 App：

- 首页突出「今天要看什么」。
- 课表页面优先可读性，不做花哨背景。
- 成绩页面突出汇总数据和学期筛选。
- 校园卡、电费页面用明确数字和状态提示。
- 避免过度营销式首页，打开就是可用功能。
- 颜色建议使用干净的浅色底，主色可以从新疆理工学院识别色中取一支，但整体不要做成单一蓝色堆叠。

## 网络层约定

统一通过 `XjitApiClient` 调用：

```dart
Future<XjitRunResponse<Map<String, dynamic>>> run(
  XjitFeature feature, {
  required String username,
  required String password,
  Map<String, dynamic> params = const {},
  String? captcha,
  bool? rememberMe,
});
```

网络层只做三件事：

- 拼请求
- 解析统一响应
- 抛出或返回规范化错误

业务层负责判断 `data` 是否符合该功能的有效结构。

## 错误处理约定

后端统一响应：

```json
{
  "ok": true,
  "data": {}
}
```

或：

```json
{
  "ok": false,
  "error": "账号不能为空"
}
```

注意：实测空账号调用 `jw.profile` 可能返回 `ok: true, data: {}`。所以每个业务模块必须做数据有效性校验，例如：

- `jw.profile`: 必须至少有 `studentId` 或 `name`
- `jw.schedule`: `courses` 是数组
- `jw.grades`: `summary` 或成绩数组存在
- `newcard.balance`: `accounts` 是数组
- `newcard.electricity.account`: `remainingElectricity.value` 存在

## 本地存储

### 安全存储

使用 `flutter_secure_storage` 保存：

- 学号
- CAS 密码
- 最近一次登录时间

禁止保存：

- 后端完整原始响应中的敏感字段
- 调试日志里的账号密码

### 普通缓存

第一阶段优先用 `flutter_secure_storage` 保存少量本地偏好和最近一次成功结果：

- 首页摘要
- 课表
- 考试
- 成绩汇总
- 校园卡余额
- 最近宿舍号

后续如果要做更完整的历史记录，再切到 `drift`。

## 代码生成

数据模型使用 `freezed` 和 `json_serializable` 时，统一通过：

```bash
dart run build_runner build --delete-conflicting-outputs
```

## 检查命令

开发中至少跑：

```bash
flutter analyze
flutter test
```

打包前跑：

```bash
flutter clean
flutter pub get
flutter analyze
flutter test
flutter build apk --release
flutter build ipa --release --no-codesign
```

## 版本策略

建议语义版本：

```text
0.1.0: MVP 内测版
0.2.0: UI 和缓存完善版
1.0.0: 功能稳定公开版
```
