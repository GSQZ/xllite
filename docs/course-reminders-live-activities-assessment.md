# 课前提醒与 Live Activities 可行性评估

评估日期：2026-10-09（Asia/Shanghai）。这是审查文档，不是功能实现或上线承诺。

2026-10-10 更新：客户端课前通知与用户可选的预定灵动岛已实现，详见 [当前实现](course-reminders.md)。本文保留评估时的工程快照，“尚不具备”部分不代表当前代码状态。未配置 APNs 的后台结束限制仍然适用。

## 结论

**总体有条件可行。** 普通课前本地通知、iOS 26 预定启动 Live Activity、系统渲染倒计时均有官方能力支持，可以保持 Flutter 主架构，不需要后台常驻，也不需要为了定时启动而新增服务器。

**完整的“09:45 自动出现 → 10:00 自动切换业务状态 → 10:05 自动结束并消失”，在 App 不执行、无服务器、无人交互的前提下，不能作为已支持的端到端能力承诺。** 当前公开接口支持预定开始，但没有找到对称的预定结束接口。强制退出、系统终止与重启后的预定活动行为，仍须分别实测；不能用文档里“在后台也能开始”替代这些测试。

建议第一版先交付普通课前通知，把 Scheduled Live Activities 作为验证通过后再开放的增强项。若“开课后五分钟自动退出灵动岛”是硬性要求，纯本地无人值守方案目前不满足；需要调整产品要求，或评估 APNs 结束推送，同时接受网络和推送延迟。

## 证据与验证边界

本次实际完成：

- 读取 Apple 最新 ActivityKit API 页面、显示指南、WWDC26/223 内容及本机 SDK 接口。
- 本机是 Xcode 27.0，build 27A5209h，iOS SDK 27.0，Swift 6.4；Flutter 3.44.4 / Dart 3.12.2。
- 已连接设备为 iPhone 17 Pro，设备报告 iOS 27.2。它可用于验证当前系统，但不能替代 iOS 26.x 的兼容性测试。
- SDK 的完整 request 重载带 `@available(iOS 26.0, *)`，Apple 页面也标注 introducedAt 26.0；不是猜测或把传统 request 当成预定接口。
- 在 `/tmp/xinli-activity-audit/api-probe.swift` 创建了不运行的类型检查样例，以 iOS 15 为部署目标，通过 availability guard 验证预定 request、pending 状态、end 调用及 SwiftUI timer API 均可编译。
- 本次没有调用预定 API，没有添加通知，没有安装 Live Activity 原型。已安装的最新版仍是现有 App 与桌面小组件，不能视为 Live Activity 验证。

## 15 个问题的逐项回答

| 问题 | 结论 | 依据、限制 |
| --- | --- | --- |
| 1. 总体是否可行？ | 有条件可行 | 提醒与预定开始可做；无人执行时的精确结束是缺口。 |
| 2. iOS 26 API 能否预定课前 15 分钟启动？ | 官方支持 | `request(attributes:content:pushType:style:alertConfiguration:start:)` 的 start 可传入该次课程实际开始前 15 分钟的日期。选择 `.standard`、`pushType: nil`。注册请求需在前台执行，App Intents 是另一个单独的例外。 |
| 3. 不打开 App 能否保证到点出现在灵动岛？ | 不可无条件保证 | 官方明确系统会在指定日期启动，即使 App 在后台；但首次仍须提前注册成功。权限、活动额度、用户移除、系统展示竞争均会影响结果。活动被启动也不等于一定以某种灵动岛布局展示。 |
| 4. 用户手动划掉 App 后？ | 尚需真机验证 | 本次官方资料没有明确给出 scheduled activity 在 force-quit 下的完整契约。系统终止与手动划掉应分别测试；不能直接套用传统后台任务或推送的行为。 |
| 5. 无后台定时器的秒级倒计时？ | 官方支持 | SwiftUI `Text(timerInterval:pauseTime:countsDown:showsHours:)` 或日期 timer，由系统显示。显示频率仍受锁屏、Always-On 等系统环境影响，不承诺所有显示模式每秒重绘。 |
| 6. 到上课时自动切换“上课中”？ | 部分支持，需区分 | 日期文本自动变化并不等于任意 SwiftUI `if Date.now...` 会定时重算，也不等于 ContentState 自动更新。可靠的业务 phase 切换需 ActivityKit update/推送，或单独验证系统支持的时间驱动展示方式。不能把桌面 Widget 的 TimelineProvider 直接移植为 Live Activity 调度器。 |
| 7. 开课五分钟后自动结束？ | 当前纯本地严格方案不可承诺 | SDK 没有预定 end 参数；staleDate、after、timestamp 均不是预定结束。App 有执行机会时可 end，或由 APNs 发 end；后台定时器/BGTask 无法兜底精确时刻。 |
| 8. 数量与未来时间限制？ | 有额度，固定数字及跨度未核实 | 官方明确 pending 与 ongoing 共用活动额度，具体数量受多个因素影响；没有查到可依赖的固定 N 或统一最长提前天数。一天、多天、一周必须实测，不按“无限预定”设计。活跃期一般最多 8 小时，不应把它误解为只能提前 8 小时预定。 |
| 9. 需要 APNs/服务器/额外服务吗？ | 预定开始不需要 | `pushType: nil` 可走本地。远程开始、更新、结束才引入 APNs 和服务端；APNs 不要求购买第三方推送服务，但 Apple 开发者资格、签名和服务器维护仍有成本。 |
| 10. 与本地通知如何避免重复？ | 统一选择提醒来源 | Scheduled Live Activity 必须带 AlertConfiguration，同一课程不默认再注册同一时刻的普通通知。见下方提醒策略及其取舍。 |
| 11. 可以只写 Dart 吗？ | 不可以 | 课程计算可共享；ActivityKit 桥接和系统 Live Activity 视图仍需要 Swift/SwiftUI。 |
| 12. 现有工程容易添加扩展吗？ | 已有扩展，可复用 | 当前 ClassWidget target 已存在且已签名安装，不需再手动新建另一个 target；在 WidgetBundle 中加入 ActivityConfiguration。 |
| 13. 构建、签名、分发影响？ | 有配置及验证工作 | 主 App 增加 NSSupportsLiveActivities；属性模型编进 App 与扩展；主 App 和扩展分别签名、版本一致。当前 App Group 可复用，仍须检查重签工具保留扩展与权限。 |
| 14. iOS 26 以下如何降级？ | 本地通知优先 | iOS 16.1+ 可在前台或用户交互后启动普通 Live Activity；16.2+ 使用 ActivityContent 重载。旧系统没有本次预定开始 API，不能靠本地通知送达自动执行 Dart 来启动它。 |
| 15. 更简单可靠的路线？ | 先通知，再增强 | 通知作为默认提醒能力；点击后打开课程页，支持的系统可由用户主动开启 Live Activity。Scheduled Live Activity 经真机矩阵验证后作为独立增强选项开放。 |

## 容易误用的几个 API

### 开始与授权

Apple 对 scheduled request 的描述明确写道：“The system starts the Live Activity at the specified date, even if the app is in the background.” 注册阶段则要求 App 在前台，除非采用符合 `LiveActivityIntent` 的特定交互入口。App Intents 不是一个任意时间启动 App 的后台定时器。

`AlertConfiguration` 在此重载中是必填，包含 title、body、sound，目的是让用户知道 App 自动开启了活动。不能假设这个提醒在 iPhone 上等同于一条具有完全相同标题/正文的普通通知：Apple 的 Live Activity 指南说明，iPhone/iPad 可能以展开的灵动岛或锁屏样式横幅提示，Apple Watch 使用 title/body。须实测锁屏、解锁、无灵动岛、通知关闭与活动开启的组合。

普通通知授权与 `ActivityAuthorizationInfo.areActivitiesEnabled` 分开查询。检查时通过不代表未来触发时权限不会变化。

### 显示倒计时与业务状态

- 使用系统日期视图，避免 Dart/Swift 每秒 update。
- `Text(date, style: .timer)` 会在目标时间前倒数、目标时间后正数；若不希望继续计数，使用有明确范围与暂停点的 timerInterval。
- 不能把 `if Date.now >= startsAt` 写进 body 就视为系统已安排重绘。`TimelineView` 也不能凭编译通过就获得 Live Activity 的后台执行或更新保证。
- `staleDate = startsAt` 会触发 stale 语义，`ActivityViewContext.isStale` 可供视图响应；这是一种系统过期信号，不是通用的“开课 phase”调度器，也不能再顺便结束活动。可列入原型比较，但不建议把内容过期语义作为完整课程状态机。
- 第一版可用固定的“10:00 开始”和系统倒计时表达已知时间；不要在无法更新时保留“15 分钟后”之类静态相对文案。

### 自动结束与移除

| API/状态 | 实际含义 | 不能用于 |
| --- | --- | --- |
| `ActivityContent.staleDate` | 到时把内容标为 stale | 自动 end、自动退出灵动岛 |
| `end(..., dismissalPolicy: .after(date))` | 调用时结束活动，指定结束后锁屏卡片保留到何时，最多约四小时 | 让活动继续到 date 才结束 |
| `end(..., timestamp: date)` | 该 payload 的生成时间，用于丢弃比之前更新更旧的数据 | 未来执行时间 |
| `.transient` | 临时交互活动，锁屏、收起、离开 App 等操作可使其结束 | 持续 20 分钟的课前课程活动 |
| ActivityKit 最长活跃期 | 一般最多 8 小时，到期系统结束，灵动岛移除；锁屏最长另留 4 小时 | 精确的 10:05 截止时间 |

结束生命周期、退出灵动岛、锁屏卡片移除是三个需分别观察的结果。只有实际执行了 end，`.immediate` 才能表达立即移除；提前 end 加 `.after` 不是预约活动结束。

模式 A/B/C 都有同样的生命周期缺口。模式 C 可展示距下课的系统倒计时，但到下课时仍需要结束执行机会，不能因上课较长就认为问题消失。

### 额度、持久化与课程变化

- 捕获 targetMaximumExceeded、globalMaximumExceeded、denied、visibility、persistenceFailure 等原生错误，不把它们统一吞掉。
- 建议先以“下一门课”或很少量近期活动做实验。额度数字、跨日/跨周 start 及额度释放时机由真机结果决定。
- `Activity.activities` 用于重启后的对账；SDK 存在 pending 状态，但其枚举可见性、系统重启后是否仍 pending、取消 pending 后是否真的不触发，均需记录测试结果。
- 用 pending 活动的 `end(... .immediate)` 作为取消验证入口；本次仅验证签名可编译，尚未验证运行语义，不把它写成已经实测成功。
- 更新活动 start 不能靠修改显示数据完成；调课后应取消旧预定、重新申请新活动，并处理取消失败、申请失败及接近触发时刻的竞态。
- App 从未再次打开时，没有无限补充未来活动的保证；不能依赖精确定时 BGTask 或普通通知送达回调补队列。
- 离线可使用已取得的课程数据；离线期间学校临时调课无法自动获知。系统重启、升级、重签、权限修改的恢复行为需独立测试。

## 项目适配性（以当前代码为准）

可复用：

- `lib/features/campus/domain/academic_models.dart`：Schedule、学期和校历状态。
- `lib/features/campus/domain/schedule_planner.dart`：Asia/Shanghai 校园时区、教学周、单双周、实际节次、日期调休/停课覆盖、重复课程去重，以及 CourseOccurrence 的 UTC 起止时刻。应复用这里的实际发生日期，不新增一套按周重复的课表解析。
- `lib/features/campus/application/home_controller.dart`：与历史学期浏览隔离的当前学期数据。
- `lib/features/campus/data/default_campus_repository.dart`、`campus_store.dart`：账号与 API 来源隔离的缓存，学业数据当前最长读取年龄为 30 天。缓存读取有效期不等于提醒正确性或通知有效期，应另设调度有效期与最后同步时间。
- 已有 MethodChannel、ClassWidget extension、共享 App Group `group.com.sayqz.xinliLite`、主 App 与扩展的自动签名配置。

尚不具备：

- 当前 pubspec 没有 flutter_local_notifications、timezone、live_activities 等相关依赖。
- 当前 iOS 主 App 没有 NSSupportsLiveActivities，也没有 ActivityAttributes/ActivityConfiguration、通知调度和通知授权管理。
- 当前桌面 Widget 的 timeline 是显示快照，不会唤醒 App 去启动或结束 ActivityKit 活动。
- ScheduleCourse 没有稳定 courseId。需要标准化 occurrenceKey（账号作用域、学期、课程标识或规范化课程特征、实际起止时间），另存内容指纹识别地点等变更。不要使用可能跨进程不稳定的 Dart hashCode 作为系统通知 ID。
- 需要独立的调度登记表：course occurrence → notification identifier / activity ID / content fingerprint / scheduled status / last reconciliation。清显示缓存不能顺带丢掉系统任务登记表；退出登录则必须取消所属账号的任务。
- 当前 Android 已有桌面小组件的重启接收与非精确刷新，但没有课程通知授权、精确闹钟授权或课程通知重建机制，不能把小组件定时器视为提醒调度器。

## 推荐模块与依赖（仅建议，不在本次创建）

| 新增/修改位置 | 职责 |
| --- | --- |
| `lib/features/campus/domain/course_reminder.dart` | 从现有 CourseOccurrence 生成标准日程；稳定键、提前量、冲突合并、内容版本 |
| `lib/features/campus/application/course_reminder_controller.dart` | 有限滚动队列、差量对账、权限变化、提醒来源选择、账号切换清理 |
| `lib/features/campus/data/reminder_store.dart` | 保存偏好与调度登记；与普通缓存清理分离 |
| `lib/features/campus/data/ios_course_activity_host.dart` | MethodChannel；能力、预定、查询、取消、更新、结束；返回原生错误码 |
| `ios/Runner/CourseActivityAttributes.swift` | 两个 target 共编的 Codable 模型，静态/动态总 payload 控制在 4 KB 内 |
| `ios/Runner/CourseActivityService.swift` | ActivityKit 调用、授权、pending/active 对账；不得依赖存活的 Dart Timer |
| `ios/ClassWidget/CourseLiveActivity.swift` | ActivityConfiguration：锁屏、compact leading/trailing、minimal、expanded |
| `ios/ClassWidget/ClassWidget.swift` | 将 Live Activity 配置加入现有 WidgetBundle，按 iOS 版本保护 |
| `ios/Runner/AppDelegate.swift`、`SceneDelegate.swift`、`Info.plist` | 注册桥接，课程深链，NSSupportsLiveActivities；普通通知代理与 Flutter 插件避免相互覆盖 |
| Android manifest、Gradle、通知适配层 | 通知权限、精确闹钟访问、重启恢复、通知渠道，必要的 desugaring 配置 |
| 设置页 | 通知/实时活动分别显示状态、已安排到哪天、最近同步时间、失败提示与关闭入口 |

最低可以使用三个新增 Swift 文件（Attributes / Service / LiveActivity UI），复用现有扩展与 Flutter 通道基础。主 App 不需要原生重写。

插件核查：截至本次查询，`flutter_local_notifications` 最新为 22.3.1，可评估与 `timezone` 配合生成 Asia/Shanghai 一次性通知；须按选定版本的 Android 编译与 desugaring 要求集成。`live_activities` 2.6.0 的发布源码使用传统 request，没有封装本次带 start 与 alertConfiguration 的预定开始重载。其 scheduled dismissal 相关代码是结束后锁屏保留，不是预定开始/未来结束。建议直接写少量 Swift 桥接，不为迁就插件改变需求。

不需要频繁推送时，不启用频繁 Live Activity 更新配置。只做本地 ActivityKit 不需要 aps-environment；将来接入 APNs 再按推送能力配置。

## 提醒可靠性与重复提醒的取舍

第一版建议两层策略：

1. 默认路径：一次性本地课前通知，使用实际发生日期，用户点击进入对应课程；支持 Live Activities 的系统可由用户主动开启。
2. 实验增强路径：通过真机验证的 iOS 26+ 设备，用户选择让预定 Live Activity 接管某次课前提示；注册失败或不支持时为该次课程安排普通通知。

同一次课使用统一 occurrenceKey，仅选择一个自动提醒来源，差量更新时核查系统中已有的请求。Apple 的两个子系统不提供跨本地通知和 ActivityKit 的统一事务；应记录执行进度并在下一次前台对账，处理崩溃时的部分完成。

必须明确：**如果 scheduled request 已成功，但用户随后禁用实时活动且不再打开 App，纯本地代码不能保证在触发时自动检测失败、补发本地通知，同时又保证成功时绝不双提醒。** 提前安排两种提醒会重复；只安排一种则不能兜住全部未来变更。若“至少一条普通通知”优先级最高，第一版应保留普通通知为唯一自动提醒，Live Activity 通过用户交互启动，不能承诺两者都自动且永不重复。

通知授权关闭时无法保证普通通知；专注模式、通知摘要、静音和系统策略也会改变提醒可见性/声音。对用户应显示真实状态，不用“保证提醒”掩盖这些限制。

iOS 本地待处理通知按插件当前说明有 64 条限制。应采用低于上限、给其他通知留余量的有限队列并读取系统 pending 请求对账。这是插件维护方说明，本次未找到当前 Apple UserNotifications 文档重新明确 64 的页面，不把它写成新版 Apple 文档提供的最新数量契约；也不依赖超过上限后的保留顺序。

## Android 路线

- 共享 Dart 课程计算，采用一次性本地通知，不做“每周某日”无限重复。
- Android 13+ 单独申请 POST_NOTIFICATIONS；Android 12+ 精确闹钟视 API 使用方式和目标版本处理特别访问，使用 canScheduleExactAlarms 查询。
- 优先审慎使用用户授予的 SCHEDULE_EXACT_ALARM；不能为了省掉授权无条件采用适用范围及商店政策受限的 USE_EXACT_ALARM。
- 无精确闹钟访问时可退化为非精确提醒，但必须明确可能延迟；不把它承诺为精确的课前 15 分钟。
- 闹钟在重启后需从登记表恢复；权限撤销会取消未来精确闹钟。用户 force-stop 与厂商后台限制也需测试。
- 不无条件创建长期前台服务；普通持续通知或系统支持的进度通知可后续单独评估。

## 签名与非 App Store 分发

ActivityKit 不是仅对 App Store 安装开放的能力，开发签名原型可测试；但不意味着所有自签工具都能保留所需 App Extension 与权限。

现有工程已能把主 App 和 ClassWidget 一起签名安装，并具备共享 App Group。新增本地 Live Activity 重点是 Info.plist、共享 Attributes、ActivityConfiguration 和正确嵌入，不应凭空增加所谓万能 ActivityKit entitlement。

开发/Ad Hoc/符合条件的企业分发都需有效描述文件、正确的主 App/扩展 bundle ID 关系、证书和授权。企业分发有适用人群限制，不能当作面向全部学生的通用替代。换团队重签时固定 App Group 可能不可用，必须根据实际团队配置并核对共享数据；证书过期、扩展被工具剥离或权限被删时不承诺系统任务继续可用。

本机当前使用 Xcode beta。最终 App Store 提交仍须核对当时 App Store Connect 接受的工具链；本地编译成功和开发签名安装不等于可提交商店。

## P0 最小验证计划（尚未执行）

在当前工程之外建立独立原型 App + Widget Extension，以独立 bundle ID 和测试课程隔离现有 App；也可在后续明确开发时使用仅 Debug 可见入口。不要修改现有教务业务。

原型只需按钮：授权状态、预定、列出活动、取消 pending、更新 phase、结束、导出测试日志。日志记录 OS/设备/时间、activity ID、pending/active/stale/ended/dismissed、异常错误码和实际显示时间。

基本时间压缩为：T+60 秒系统启动，T+120 秒模拟开课，T+180 秒目标结束。先观察纯系统行为，不让 Timer、调试器保持进程存活或后台音频掩盖结果。Release/脱离调试器重复测试。

| 测试 | 观察与验收 |
| --- | --- |
| 前台预定 | request 成功、pending 可见、指定时刻 active，记录实际偏差与系统提醒 |
| 按 Home 后锁屏 | 未打开 App 仍显示；分别录制锁屏和灵动岛 |
| 系统终止 / 用户划掉 | 分开执行；不把调试器 stop 等同于所有终止场景 |
| 飞行模式 | 已注册任务在无网络时的开始、倒计时、权限提示 |
| 重启（含未首次解锁） | 任务是否保留、到点是否出现；重启后首次打开再查询对账 |
| 时间越过 startsAt | 单纯 timer、isStale 响应、主动 phase update 三种方式分别观察 |
| 时间越过目标结束点 | 不调用 end 的对照组是否仍活动；验证 stale/after/timestamp 不等于未来结束 |
| 取消 pending / 临时调课 | 取消后不出现，重新安排只提醒一次；测试接近触发时刻 |
| 通知/活动权限四种组合 | 不将两个授权混为一谈；观察声音、横幅、锁屏、Apple Watch |
| 数量与跨度 | 顺序增加小量活动直到报错后清理；另测明日、三日、一周。不得直接对用户账号批量注册整个学期 |
| 并发活动与连续课程 | 已有音乐、导航或其他活动时的展示；本 App 课程重叠合并与优先级 |
| 签名 / 版本 | 当前 iOS 27.2 与至少一台 iOS 26.x 真机；无灵动岛设备验证锁屏降级；目标自签方式验证扩展完整性 |

是否进入 P1：预定启动在目标系统矩阵达到预期，重复提醒策略明确，且产品接受“自动结束”限制或批准服务器方案。否则先上线普通通知；不把 P0 的一个成功案例当成所有用户的系统保证。

## 官方与源码参考

1. [Apple：预定 request（iOS 26.0+）](https://developer.apple.com/documentation/activitykit/activity/request(attributes:content:pushtype:style:alertconfiguration:start:))
2. [Apple：Displaying live data with Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)
3. [WWDC26/223：Live Activities essentials](https://developer.apple.com/videos/play/wwdc2026/223/)
4. [Apple：staleDate](https://developer.apple.com/documentation/activitykit/activitycontent/staledate)
5. [Apple：ActivityUIDismissalPolicy.after](https://developer.apple.com/documentation/activitykit/activityuidismissalpolicy/after(_:))
6. [Apple：end(_:dismissalPolicy:timestamp:)](https://developer.apple.com/documentation/activitykit/activity/end(_:dismissalpolicy:timestamp:))
7. [Apple：Displaying dynamic dates](https://developer.apple.com/documentation/widgetkit/displaying-dynamic-dates)
8. [Apple：本地通知调度](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app)
9. [Apple：ActivityAuthorizationInfo](https://developer.apple.com/documentation/activitykit/activityauthorizationinfo)
10. [Apple：ActivityKit push notifications](https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications)
11. [Android：Schedule alarms](https://developer.android.com/develop/background-work/services/alarms/schedule)
12. [Android：Notification runtime permission](https://developer.android.com/develop/ui/views/notifications/notification-permission)
13. [flutter_local_notifications 22.3.1](https://pub.dev/packages/flutter_local_notifications/versions/22.3.1)
14. [live_activities 2.6.0](https://pub.dev/packages/live_activities/versions/2.6.0)

官方页面原始内容与未执行的 Swift 类型检查样例保存在 `/tmp/xinli-activity-audit/`，属于临时核验材料；本报告记录了结论及稳定来源链接。
