# 课前灵动岛布局

本次仅修改实时活动，不修改桌面课表小组件。正式后台自动结束仍依赖尚未配置的 APNs；现有入口是指定账号的测试功能。

## 布局依据

- [Home Assistant — HADynamicIsland](https://github.com/home-assistant/iOS/blob/main/Sources/Extensions/Widgets/LiveActivity/HADynamicIsland.swift)：展开内容放在 `.bottom` 全宽区域，避免摄像头旁多个区域各自的系统边距导致错位。
- [Home Assistant — HAExpandedContentView](https://github.com/home-assistant/iOS/blob/main/Sources/Extensions/Widgets/LiveActivity/HAExpandedContentView.swift)：同一内容容器内统一对齐、分配间距。
- [Apple Food Truck](https://github.com/apple/sample-food-truck/blob/main/Widgets/TruckActivityWidget.swift)：使用系统日期区间倒计时、固定宽度、等宽数字与文本右对齐。
- [iOS16-Live-Activities](https://github.com/1998code/iOS16-Live-Activities/blob/main/WidgetDemo/WidgetDemo.swift)：检查展开、紧凑和最小展示模式；没有采用其 TimelineView 作为后台执行保证。
- [Apple Live Activities 设计规范](https://developer.apple.com/design/human-interface-guidelines/live-activities)：内容避开圆角，与外轮廓保持一致留白，优先展示可快速读取的信息。

参考以上布局思路，未复制第三方项目代码或素材。

## 当前实现

- 展开：摄像头下方统一三行，状态与倒计时、课程名、教室与上课时间。外边距 16 pt，内容左右再内收 16 pt，文字不贴弧形边缘。
- 课程名最多两行。长地点从中间省略，保留开头的楼名和末尾的教室号。教师信息留在 App 课表内。
- 紧凑：学士帽与固定宽度倒计时；最小：学士帽。点击仍打开课表。
- 深色岛面上提亮主题色，提高倒计时可读性。锁屏使用相同信息顺序并适配系统明暗外观。
- `Text(timerInterval:countsDown:showsHours:)` 不传 `pauseTime`。原来传入区间终点会停在初始倒计时值；它不是安排课程开始后暂停执行的后台 API。
- 测试启动延迟由 8 秒改成 3 秒。模拟 1 分钟后上课、再过 1 分钟结束的规则不变。

## 验证边界

iOS Release 签名构建和 9 项相关 Flutter 测试通过。使用与扩展相同的 SwiftUI 展示组件，检查普通/长课程名、长地点、窄宽度及锁屏明暗布局；原生渲染间隔 3 秒确认倒计时从 1:00 变为 0:57。离线渲染不等同于 iPhone 系统灵动岛截图，圆角、摄像头和系统实际区域仍需真机复核。
