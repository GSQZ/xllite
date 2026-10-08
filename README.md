# 新理Lite

面向新疆理工学院学生的轻量校园服务 App，使用 Flutter 开发，支持 Android 和 iOS。

> 本项目为民间开发，不代表新疆理工学院官方应用。

## 项目状态

**1.0.0 重构版开发中，尚未正式发布。**

`v1.0.0` 分支基于重新初始化的 Flutter 工程开发。旧版实现可通过 Git 历史查阅。当前已接入原生登录、首页、课表、成绩、考试、校园卡及宿舍电费页面。

本版本独立维护在 `v1.0.0`，功能分支的 PR 必须以 `v1.0.0` 为合并目标，不合入 `main`。提交按功能拆分，合并时保留提交历史。

认证支持密码登录、微信扫码、Token 恢复与续期、安全存储和退出。校园业务层覆盖个人信息、课表、成绩、考试、毕业情况、校园卡余额与流水、付款码、校园卡充值以及宿舍电费查询和支付，共 13 个公开业务接口。

查询支持按账号隔离的持久化缓存、后台刷新、异常处理和分页；宿舍查询成功后自动记忆，下次启动恢复。一卡通及电费充值包含配置、确认、学校收银台、外部支付跳转和结果核对；未核对充值标记跨重启保留。后端已按官方校历配置 2026–2027 两个学期与确认的作息，App 自动计算教学周与课程时间。外部支付实际到账仍需真实付款验证，自动测试不扣款。详见 [缓存与充值说明](docs/cache-and-recharge.md)。

状态、调用方式和协作边界见 [登录 UI 对接文档](docs/auth-ui-handoff.md) 与 [校园业务 UI 对接文档](docs/campus-ui-handoff.md)。

Android / iOS 桌面课表小组件共享 Flutter 计算的展示数据，支持点击进入课表、同步主题色和退出清理。iOS 使用同一 App Group 连接主应用与 Widget Extension。

课前灵动岛目前仅开放指定测试账号的「我的 → 灵动岛测试」。iOS 26 及以上在开启测试 3 秒后预约显示；旧系统需要 iOS 16.2 及以上并立即显示。已具备按大课计算课前 15 分钟、开课后 1 分钟的时间窗口，但正式自动提醒尚未启用：App 被挂起或关闭后的可靠结束仍需 APNs 支持。详见 [灵动岛实现与验证边界](docs/course-live-activity-ui.md)。

`pubspec.yaml` 中的 `1.0.0+1` 是重建工程的起始版本号，不代表正式版已经发布。

## 开发环境

当前工程使用以下开发工具版本：

| 工具 | 版本 |
| --- | --- |
| Flutter | 3.44.4 stable |
| Dart | 3.12.2 |

- Android 开发需要 Android SDK 和兼容的 JDK，当前工程使用 Java 17 编译目标。
- iOS 开发需要 macOS、Xcode 及对应的模拟器或真机环境。
- 认证层使用 Dio 请求接口、`flutter_secure_storage` 保存会话、Flutter 自带 `ChangeNotifier` 通知页面状态。

环境安装可参考 [Flutter 官方文档](https://docs.flutter.dev/get-started/install)。

## 本地运行

在项目根目录执行：

```bash
flutter doctor
flutter pub get
flutter devices
flutter run
```

连接多台设备时，使用 `flutter run -d <device-id>` 指定目标设备。

## 开发检查

```bash
dart format lib test
flutter analyze
flutter test
```

测试覆盖认证与校园接口契约、状态切换、续期、退出竞争、页面交互、课表时间推导、流水分页、付款码失效和支付防重。接口测试使用公开文档示例和模拟响应，不调用真实账号或执行真实扣款。

目标为 `v1.0.0` 的 Pull Request 和该分支的推送会运行 Quality 工作流，执行静态分析和 Flutter 测试。macOS 上还可以单独检查原生小组件时间线：

```bash
xcrun swiftc ios/Runner/WidgetSnapshotStore.swift test/native/widget_timeline_test.swift -o /tmp/xinli-widget-test
/tmp/xinli-widget-test
```

## 项目结构

```text
lib/
  main.dart           # 应用入口
  app.dart            # 根节点、认证生命周期与主题
  features/auth/
    auth.dart         # 页面调用的统一入口
    application/      # 认证状态控制器
    data/             # HTTP 接口与安全存储
    domain/           # 模型与仓库契约
    presentation/     # 登录与认证页面
  features/campus/
    campus.dart       # 校园业务统一入口
    application/      # 首页、查询、分页、付款码与支付状态
    data/             # 统一业务请求与仓库实现
    domain/           # 业务模型、仓库契约与课表计算
    presentation/     # 校园页面、充值表单与学校收银台
  shared/             # 主题及通用组件
test/
  features/auth/      # 认证业务测试
  features/campus/    # 校园业务测试及公开接口示例
  presentation/       # 页面交互测试
  widget_test.dart    # 应用入口测试
docs/
  auth-ui-handoff.md  # 登录 UI 对接约定
  campus-ui-handoff.md # 校园业务与页面接入说明
android/              # Android 平台工程
ios/                  # iOS 平台工程
pubspec.yaml          # 版本与依赖声明
analysis_options.yaml # 静态分析规则
LICENSE               # 开源许可证
```

## 构建

```bash
# Android APK
flutter build apk --release

# iOS 应用，仅限 macOS，不包含代码签名
flutter build ios --release --no-codesign
```

当前使用模板构建配置：Android release 构建仍采用 debug 签名，iOS 上述命令生成未签名应用。正式分发前需要重新配置发布签名与发布流程；旧版自动发布工作流已移除。

iOS 主应用与 `ClassWidget` 扩展需要同一个开发团队，并同时具备 `group.com.sayqz.xinliLite` 的 App Group 权限。项目已包含扩展 target。真机测试可通过 Xcode 构建参数 `XINLI_APP_BUNDLE_IDENTIFIER=com.sayqz.xinliLite.dev` 使用独立标识；主应用与扩展的版本号统一读取 Flutter 配置。

应用标识保持不变：

| 平台 | 标识 |
| --- | --- |
| Android applicationId | `com.sayqz.xinli_lite` |
| iOS Bundle ID | `com.sayqz.xinliLite` |

## 许可证

本项目采用 [GNU Affero General Public License v3.0](LICENSE) 授权。
