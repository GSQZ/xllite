# 课前提醒与自动灵动岛

实现日期：2026-10-10。范围为 iOS 客户端，没有配置或部署 APNs，Android 课表小组件保持现状。

## 使用

「我的 → 课前提醒」对全部 iOS 登录账号开放，默认关闭。主动开启主开关才向系统请求通知授权。iOS 15 起使用普通通知；iOS 26 及以上可另外开启自动灵动岛。系统实时活动权限与通知权限分别检查。拒绝授权后保留用户偏好，并提供系统设置入口。

开关按 API 来源和账号隔离。用户确认灵动岛的后台结束限制后才启用。切换账号清理旧账号的通知及实时活动；重新登录可恢复该账号偏好。旧测试开关及测试方法已移除，之前的测试活动会在前台恢复时清理。

设置弹层与校园卡/电费共用主色强调面板及毛玻璃分组：主开关突出「提前 15 分钟」，灵动岛只显示简短副标题，底部保留实际安排次数和同步操作。工作方式、最晚安排时间与更新时间放入「提醒说明」，权限及同步问题只保留最需要处理的一项。

## 调度

- 复用 `CourseReminderPlanner` 与首页当前学期校历，按校园 UTC+8、单双周、调休、停课和实际节次计算，7–10 节按两次大课提醒。历史课表不参与。
- 普通通知在课前 15 分钟触发，点击进入课表。已过提醒时间不补发过时的普通通知。
- 自动灵动岛最多保留最近两次课程的活动；系统预定 API 负责启动，其余课程使用普通通知。容量或预约错误逐课降级，不把失败标成成功。
- 同一课程只选择一种自动提醒。课程标识含学期、实际起止时间及内容，原生端再与账号作用域做 SHA-256，系统标识不暴露学号。地点/教师变化后旧任务移除，新任务重新安排。
- 日程有限于未来七天，最多 48 次，给系统其他通知留余量。前台启动、恢复、课表变化、主题变化及每分钟前台核对补充；不能依赖后台常驻无限补充整个学期。
- 原生日程、安排记录与用户偏好使用独立版本化存储，不因显示缓存清理而丢失。系统 pending 请求和 ActivityKit 活动用于对账。用户移除过的灵动岛不会反复重新预约。
- 登录恢复期间保留已有原生安排。课表/校历尚不可用时不以空列表覆盖已安排提醒；明确的空课表会清理旧安排。断网保留已有数据，并显示刷新失败提示。
- 关闭提醒、退出、账号切换会清理 pending/delivered 通知及活动。Flutter 和原生均串行安排/清理，避免旧请求在退出后恢复旧账号任务。

## 结束与可靠性边界

显示使用系统日期倒计时。开课时通过 stale 语义显示“已开始上课”，不是后台业务状态推送。App 有执行机会时在开课一分钟后执行 end；前台恢复也清理过期活动。没有 APNs，App 被挂起或强制关闭时不能保证此时刻退出灵动岛，系统可能继续保留。设置页和开启确认均说明，不能把 `staleDate` 或 Swift Task 当作定时结束保证。

用户在安排之后关闭通知/实时活动权限、使用专注模式、清理活动、系统资源额度、重启等均会影响展示。只安排一种来源时，App 不执行就不能自动感知未来权限变化并补发另一种提醒。两个系统子系统没有统一事务：替换普通通知前先移除旧请求，预约失败后恢复通知，下次前台继续对账；进程在中途终止仍有短暂任务缺失可能。

七天安排来自最近获取的课表，长期未打开时不会自动获知临时调课。安排更新时间不是学校数据新鲜度或真实送达证明。进入 App、课表刷新和系统再次允许执行时补充/恢复安排。

## 工程入口

- Dart：`course_activity_controller.dart` 负责账号、偏好状态、计划同步与权限反馈；`course_reminder_sheet.dart` 提供设置。
- Swift：`CourseReminderSchedule.swift` 验证绝对时刻、稳定标识、有限日程；`CourseActivityService.swift` 负责本地通知、预定实时活动、持久化对账和清理。
- 点击通知复用现有课表路由，AppDelegate 与 SceneDelegate 同时处理运行中和冷启动；其他插件通知回调继续交给 Flutter 基类。
- `CourseActivityAttributes.accountScope` 为可选字段，兼容此前活动结构。主 App 与扩展共编属性模型。

## 验证

Flutter 回归覆盖普通账号启用、仅显式操作申请权限、计划去重、主题变化、缺少校历、明确空课表、后台返回补充、退出竞争、权限拒绝、错误重试及启动恢复。页面覆盖开启确认、取消、权限设置、小屏大字体和 Android 隐藏入口。

本次 `flutter analyze --no-pub` 无问题、`flutter test --no-pub` 293 项通过、原生日程检查通过、`flutter build ios --release --no-codesign --no-pub` 通过。未签名构建包含主应用与 ClassWidget 扩展。

原生计算检查：

```bash
xcrun swiftc ios/Runner/CourseReminderSchedule.swift test/native/course_reminder_schedule_test.swift -o /tmp/xinli-reminder-native-test
/tmp/xinli-reminder-native-test
```

2026-10-10 项目作者已在真机验证灵动岛正常工作（系统预定触发与锁屏/灵动岛呈现）。通知声音、通知点击冷启动、权限变更、手动移除、重启，以及被挂起/关闭后的实际结束行为仍需实测确认；自动化测试和未签名构建不替代这些验证。

API 依据：[Apple 预定实时活动](https://developer.apple.com/documentation/activitykit/activity/request(attributes:content:pushtype:style:alertconfiguration:start:))、[Apple 实时活动推送](https://developer.apple.com/documentation/ActivityKit/starting-and-updating-live-activities-with-activitykit-push-notifications)、[Apple 通知授权](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications)。
