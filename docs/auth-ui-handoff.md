# 登录 UI 与业务层对接

本轮分工：Codex 实现认证模型、接口、安全存储、状态控制器与业务测试；Claude 设计并实现 Flutter 原生登录页面。登录页面已接入；后续校园页面见 [校园业务 UI 对接文档](campus-ui-handoff.md)。

## 文件边界

- 业务层：`lib/features/auth/{application,data,domain}/` 和 `lib/features/auth/auth.dart`，由 Codex 维护。
- 业务测试：`test/features/auth/`，由 Codex 维护。
- 页面：`lib/features/auth/presentation/`、`lib/shared/{theme,widgets}/`、`lib/main.dart`、`lib/app.dart` 和页面测试，由 Claude 实现。
- 微信页面可添加 `webview_flutter`、`url_launcher` 以及必要的平台配置。不要另加 UI 组件库或状态管理库。
- 保护已有未提交改动。API 缺口通过协作确认，页面不自行修改业务契约。

## 给 Claude 的设计任务

为新疆理工学院学生使用的「新理Lite」1.0.0 设计并实现登录体验。使用 Flutter 自带 Material/Cupertino Widget、Icons 和动画。视觉清爽、克制、易读，优先表单体验，避免堆叠营销文案和装饰卡片。

交付账号密码登录、微信扫码登录、恢复会话过渡页，以及带退出按钮的登录成功占位页。用占位页验证完整流程，不提前实现首页业务。

支持小屏、安全区、键盘遮挡、字体放大、自动填充、密码显隐、键盘提交和可访问的图标按钮。加载时保留表单布局并阻止重复提交；错误必须可读、可重试。

说明“民间开发版本，不代表学校官方应用”。不要虚构注册、找回密码或政策链接。不要声称密码只在本机处理：客户端通过后端完成认证，仅在客户端持久保存 Token。

## 唯一 UI 入口

```dart
import 'package:xinli_lite/features/auth/auth.dart';

final controller = createAuthController();
await controller.restore();
```

根 StatefulWidget 创建并持有一个控制器，页面通过构造参数接收。`ListenableBuilder(listenable: controller, builder: ...)` 订阅状态。不要在 `build()` 内创建控制器或发请求。根节点销毁时 `dispose()`；单个页面退出不 dispose 全局控制器。

| 方法 | 行为 |
| --- | --- |
| `restore()` | 启动恢复；本地读取失败或过期且断网后，可调用重试 |
| `signIn(username:, password:, captcha:)` | 密码登录，captcha 可省略；只清理学号首尾空白，不修改密码 |
| `startWechat()` | 获取授权入口并开始轮询；在等待扫码时再次调用可更换二维码 |
| `handleWechatRedirect(url)` | 消费匹配当前会话的回调；返回是否已接管该导航 |
| `cancelWechat()` | 取消扫码与轮询；忽略迟到的响应 |
| `refreshSession(force: false)` | 临近到期才续期；同一时刻只进行一次续期 |
| `signOut()` | 清理本地后立即退出，远端注销在后台尽力执行 |
| `clearFailure()` | 仅清理当前可见错误 |

以上异步方法把业务失败写入 `state.failure`，不向 Widget 回调抛出业务异常。页面不自己发 HTTP 请求、不读写安全存储、不解析原始 JSON，也不持久化密码。

## 状态与导航

`controller.state` 为不可变 `AuthState`：

- `phase`：见下表。
- `isAuthenticated`：页面切换的登录依据。
- `isBusy`：提交/恢复/退出/续期中的交互状态；等待扫码本身不是 busy。
- `isRefreshing`：后台续期标记。
- `failure?.message`：可安全展示的错误提示。
- `failure?.operation`：明确标识 `restore`、`signIn`、`refresh`、`signOut` 或 `wechat`。页面依此决定重试动作，不再根据历史状态转换猜测。
- `session`：当前会话，`username` 可能为空；不要展示或记录 `accessToken`。
- `challenge`：当前扫码会话，包括 `authUrl`、`serviceUrl`、`expiresAt`。

| phase | 页面处理 |
| --- | --- |
| `idle` / `restoring` | 启动过渡页 |
| `signedOut` | 登录表单，并展示可能存在的错误 |
| `signingIn` | 保留表单，按钮 loading、禁用重复操作 |
| `wechatStarting` | 扫码页获取入口中 |
| `wechatPending` | 展示授权 WebView，允许取消、重新获取；失败提示可与页面同时存在 |
| `wechatCompleting` | 正在确认登录，禁止重复操作 |
| `authenticated` | 登录成功占位页；后台错误提示不应覆盖整个页面 |
| `signingOut` | 退出中 |

由应用根节点根据状态切换登录与成功页面。若扫码页使用导航栈，登录成功后关闭它，避免残留。不要因密码提交切换到 `signingIn` 而销毁表单。

清理安全存储失败后，控制器进入 `signedOut` 并显示 storage 错误；本地凭据可能尚未清除，提供 `signOut()` 重试入口。不要用“已安全退出”的成功提示掩盖该情况。

应用恢复前台时调用 `refreshSession()`。校园业务请求已通过独立请求层使用这一入口获取最新状态；查询最多在 401 续期后重放一次，支付不自动重放，详见 [校园业务 UI 对接文档](campus-ui-handoff.md)。

## 微信页面

1. 调用 `startWechat()`。
2. 从 `challenge.authUrl` 加载学校授权页。不要根据 `state` 自己拼二维码。
3. 导航时先调用 `challenge.ticketFromRedirect(url)` 判断是否匹配。匹配则立即阻止 WebView 导航，并交给 `handleWechatRedirect(url)`；其他授权 HTTPS 导航正常进行。
4. 外部跳转仅允许明确需要的微信 scheme，调用失败显示提示。不要盲目打开任意 scheme。
5. 控制器自行串行轮询、处理过期及成功结果。UI 不另写轮询。可按 `expiresAt` 绘制倒计时，但不能自行认定登录成功。
6. 离开或取消扫码页调用 `cancelWechat()`；它在已经登录成功时不会清除登录状态。
7. 提供另一台设备扫码的说明及返回密码登录入口；不要承诺同机截图识别可用。

## 接口与边界

依据：[线上 OpenAPI](https://xllite.sayqz.com/api/v1/openapi.json)，核对日期 2026-10-08。

- `/api/v1/auth/login`：账号密码换取会话。
- `/api/v1/auth/refresh`：Bearer Token 轮换。
- `/api/v1/auth/logout`：撤销 Token。
- `/api/v1/auth/wechat/{start,status,complete}`：扫码会话。
- `/api/v1/auth/session`：扫码成功后读取 API 会话信息，避免把二维码剩余寿命当成 Token 有效期。
- 后端只有通用 `error` 字符串，未提供稳定的业务错误码或验证码获取接口。当前错误采用客户端安全文案，HTTP 401/403 才判定受保护认证请求明确失效，不按错误字符串猜测。
- 目前不做注册、找回密码、预热进度展示或验证码图片流程。
- 旧版安全存储凭据会被删除；重建版要求重新登录，不迁移旧 Token。
- 密码不进入状态和本地存储；Token 用单条带版本的安全存储记录保存。
- 无网络时保留安全存储。尚未过期的会话可恢复，过期或缺少有效期的会话在续期失败后不放行。
- Token 轮换成功但写入存储失败时，当前进程保留新 Token 并提示存储错误；重启恢复不作保证。

## UI 验收

- 入口移除计数器，并接通所有认证状态。
- 注入 fake `AuthRepository` 构建控制器进行 UI 测试，不调用真实账号和学校服务。
- 验证输入、密码显隐、提交禁用、失败重试、登录态切换、扫码返回、小屏/键盘布局。
- 运行 `flutter analyze`、`flutter test`。
- 报告设计选择、修改文件、检查结果和待联调问题。

业务层的自动化测试不代表真机微信回跳、安全存储权限和真实账号认证已经验收；这些需在页面接入后验证。
