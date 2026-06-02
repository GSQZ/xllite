# 新理Lite 开发路线

## Phase 0: 工程启动

- 初始化 Flutter 工程
- 设置应用名和包名
- 接入基础主题
- 接入 go_router
- 接入 Riverpod
- 接入 dio
- 建立 XJIT API client
- 建立安全存储

验收：

- Android/iOS 可运行默认页面
- `flutter analyze` 通过
- 可以请求 `/health`

## Phase 1: 登录和首页

- 登录页
- 保存 CAS 凭据
- 退出登录
- 首页模块入口
- 首页请求个人信息
- 首页展示常用摘要占位

验收：

- 首次启动进入登录页
- 有凭据后进入首页
- 退出后清除本地凭据
- 空数据能提示，不误判为登录成功

## Phase 2: 核心查询

- 课表页面
- 成绩页面
- 考试页面
- 校园卡余额页面
- 宿舍电费页面

验收：

- 每个功能可独立刷新
- 有 loading、error、empty、success 四种状态
- 最近一次成功结果可缓存

## Phase 3: 校园卡流水和体验完善

- 校园卡流水页面
- 日期范围筛选
- 分页加载
- 首页摘要接入真实余额和电费
- 页面细节打磨

验收：

- 流水支持分页
- 日期筛选可用
- 首页摘要能从缓存恢复

## Phase 4: 内测打包

- Android release APK
- iOS unsigned archive/IPA
- 应用图标
- 隐私说明
- 民间版本免责声明
- 基础异常日志策略

验收：

- Android 真机安装可用
- iOS 可通过开发者签名测试
- 登录凭据不会出现在日志中

## 第一版页面优先级

1. 登录
2. 首页
3. 课表
4. 考试
5. 校园卡余额
6. 宿舍电费
7. 成绩
8. 校园卡流水
9. 个人信息/设置

## 风险点

- 后端可能返回 `ok: true` 但 `data` 为空。
- CAS 可能触发验证码，第一版先保留字段和错误提示，验证码 UI 后续根据真实返回补齐。
- 学校系统接口不稳定时，需要缓存兜底。
- 校园卡、电费、教务三个系统的数据结构可能不完全一致，模型解析要宽松。

## 打包目标

Android:

```bash
flutter build apk --release
```

iOS:

```bash
flutter build ipa --release --no-codesign
```

后续如果要上架或 TestFlight，再补签名和证书流程。
