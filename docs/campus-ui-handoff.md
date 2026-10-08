# 校园业务层与 Flutter UI 对接

核对日期：2026-10-08。依据 [OpenAPI](https://xllite.sayqz.com/api/v1/openapi.json) 和 [功能详情](https://xllite.sayqz.com/api/v1/features/detail)。当前公开的 13 个业务功能均有类型化接口、模型与页面可订阅的控制器。测试 fixture 为当日公开示例，不含真实学生信息。

本次交付业务层，不改现有登录视觉或替 Claude 实现首页。实际学校账号、外部支付 WebView 和真机 UI 仍需接入后联调；模拟契约通过不等于所有学校实际响应已经验证。

最近验证：`flutter analyze --no-pub` 无问题；`flutter test --no-pub` 共 152 项全部通过，包含原有认证与页面测试。测试不访问真实账号、不下单、不扣款。

## 分工和初始化

- Codex：`lib/features/campus/{application,data,domain}/`、`campus.dart`、相关业务测试。
- Claude：首页、课表、成绩、考试、校园卡、电费和个人页，使用 Flutter 原生 Widget。
- 页面仅导入 `features/campus/campus.dart`，不导入 `data/`、不解析 JSON、不自行持有 Token。
- 控制器与认证控制器同生命周期；不要在 build 中创建，不要在单页退出时销毁全局业务控制器。

在 `XinliApp` 的 State 中接入：

```dart
late final AuthController _auth;
late final CampusController _campus;

@override
void initState() {
  super.initState();
  _auth = widget.createController();
  _campus = createCampusController(_auth);
  // 保留已有 WidgetsBindingObserver 注册逻辑。
  _auth.restore();
}

@override
void dispose() {
  // 保留已有 Observer 注销逻辑。
  _campus.dispose();
  _auth.dispose();
  super.dispose();
}
```

为 `AuthGate` 和登录后的页面增加构造参数，传递 `_campus`。测试可直接传 `CampusController(auth: auth, repository: fake)`。构造本身不会请求任何业务接口。根节点观察登录态，进入登录后页面时才加载对应内容；认证失效仍由现有 AuthGate 返回登录页。

应用生命周期变更时调用 `campus.campusCode.setForeground(state == AppLifecycleState.resumed)`；只有付款码页面可见才 `setVisible(true)`，切 tab、push 覆盖页面、离开时 `setVisible(false)`。前台且首页可见时 `home.setActive(true)`，否则 false。退出账号会自动停止时钟并清空全部内存数据。

## 页面调用表

| 内容 | 调用 | 订阅 |
| --- | --- | --- |
| 首页 | `home.load()`；下拉 `home.load(refresh: true)` | `home`，读取 `home.state` |
| 个人信息 | `loadProfile()` | `profile` |
| 课表 | `loadSchedule(term: selectedTerm)` | `schedule` |
| 成绩 | `loadGrades(term: selectedTerm, mode: GradeMode.bestByCourse)` | `grades` |
| 考试 | `loadExams()` | `exams` |
| 毕业情况 | `loadTraining()` | `training` |
| 校园卡余额 | `loadBalance()` | `balance` |
| 流水 | `transactions.load(query: TransactionQuery(...))` / `loadMore()` | `transactions` |
| 电量 | `loadElectricity(room)` | `electricity` |
| 付款码 | `campusCode.setVisible(true)` / `refresh()` | `campusCode` |
| 卡充值配置 | `payments.loadCardConfig()` | `payments.cardConfig` |
| 电费充值配置 | `payments.loadElectricityConfig(room)` | `payments.electricityConfig` |
| 创建卡充值订单 | `payments.submitCard(...)` | `payments` |
| 电费支付 | `payments.submitElectricity(...)` | `payments` |

资源加载方法支持 `refresh: true`。课表/成绩刷新须继续传当前筛选值，例如 `loadSchedule(term: campus.selectedTerm, refresh: true)`；term 不传表示学校默认学期。成绩默认使用后端 `best_by_course` 汇总，不在页面自行计算 GPA；保留正常、补考、失败课程和数据来源字段。成绩“优秀/缓考”等保留原文，可选 numeric 属性为 null 时不能当零分。

### 普通资源状态

`ListenableBuilder(listenable: campus.schedule, ...)`，读取 `campus.schedule.state`：

- `idle`：尚未加载；不要显示“暂无数据”。
- `loading`：首屏加载；`isRefreshing` 为 true 时已有旧数据，可以保留并显示轻量刷新状态。
- `ready`：成功；列表为空才显示空状态。
- `failure`：显示 `failure.message` 与重试按钮；`isStale` 表示刷新失败但保留旧数据，展示更新时间 `updatedAt`。
- `failure.operation`：对应业务名，例如 `jw.schedule`，无需 UI 猜错误来源。

加载方法将错误存入状态，UI 回调无需 try/catch。重复加载同一资源会合并，修改筛选条件会丢弃旧请求结果。查询快照通过安全存储按 API 地址和账号隔离；页面先显示快照再后台刷新，`fromCache/updatedAt` 标识来源和真实更新时间。成功查询的宿舍号持久化，`restorePreferences()` 自动恢复。退出清空页面内存；同账号重新登录可恢复自己的快照，正常 Token 轮换不清空。策略和清理入口见 [缓存与充值说明](cache-and-recharge.md)。

流水是单独的 `TransactionsState`：`items/isLoading/hasLoaded/hasMore/pageNo/failure/updatedAt`。首次加载和刷新用 `load()`；改变筛选用 `load(query: newQuery)`；触底 `loadMore()`。失败重试不会跳页，合并时按非空流水号去重。API 没有总条数，满页后可能需要再查一次空页才能确定结束。日期按选择器的年/月/日原样传递，页码从 1 开始，pageSize 为 1–100。

## 首页与校历边界

首页建议问候、下一节课、常用入口、今日课程与考试列表。`home.load()` 独立加载个人信息、当前课表、考试，某一项失败不会覆盖其他模块。历史学期课表与首页当前课表分开持有。

`home.state` 提供 `profile/schedule/exams` 三个资源状态、`now/day/upcomingExams/undatedExams`。未识别的考试时间保留在 `undatedExams`，必须可见，不伪造日期或倒计时。

后端 `jw.schedule` 已增加 `calendar/calendarStatus/termLabel`，App 自动解析并由首页使用相应校历；课表页优先使用当前所选学期的校历。一般不再调用 `configureCalendar`，该方法仅保留给测试或明确的手动配置。旧后端无校历字段时仍能显示课表，不猜测开学日。

2026–2027 两个学期已按教务处官方日历配置：第一学期第一周周一 2026-08-31，第二学期 2027-02-22；共19周，其中前18周教学、第19周考试。每小节45分钟、节间10分钟，10节作息由维护者确认，配置统一在后端 `config/academic-calendars.json`。上午10:00开始、13:40结束，下午16:00–19:40，晚间20:30–22:10。

公共只读 `GET /api/v1/academic-calendar?term=2026-2027-1` 提供已配置学期与校历；App 的课表请求已携带校历，无需额外请求。可配置停课或补另一日期的课表；补课同时使用来源日期的星期和周次，实际上课时刻落在目标日期。未配置的法定假日不自动猜测调休。

`SchedulePlanner.today(schedule, calendar, now)` 可供课表页面复用。当前按 UTC+8 学校时间计算；`AcademicCalendar.firstMonday` 是民用日期，`CourseOccurrence.startsAt/endsAt` 则是真实 UTC 时间点。UI 按学校时间显示时用 `campusNow()`。`SectionTime.endSection` 允许服务端仅知道整大节时间时表达范围，不能用它猜测单小节时刻；目前配置为10个独立小节。

`home.state.day`：

- null：课表还不可用，依 schedule 状态显示加载或错误。
- `needsCalendar`：校历缺失或学期不匹配。保留课表入口和原始信息，隐藏准确倒计时。
- `outsideTerm`：当前日期不在配置的教学周内。
- `incomplete`：存在无法解析的周次/节次/星期，展示 `unresolved`，不能宣称“今天没课”。
- `noClasses/upcoming/inClass/finished`：已具备完整计算依据，可分别渲染。

支持范围、离散周次、单双周和常用中文分隔符；不连续节次拆成多个上课区间。`current/next` 只针对当天；若 incomplete，则即使存在已解析的 next 也不要声称它一定是下一节。未配置 dateOverrides 时不能承诺自动处理学校临时调课。校历故障/格式错误只停用准确计算，不影响原始课程展示。

学校的 `07-08-09-10节` 按明确枚举解析为第7至10节；`01-02-05-06节` 则拆为两个区间。Planner 会合并相同课程、教师、地点及起止时间的重复单元格，不能只按课程名去重。全天实践课在学校隐藏详情中可能都写成 `01节`，后端仅在核实的完整五大节重复模式下按单元格位置还原节次，附带 `originalSections/sectionSource` 供排查；页面使用修正后的 `sections`，保留每天五个不同时间段。第7周跨节课和第17–18周全天实践均已有业务及页面回归测试。

## 付款码

读取 `campusCode.usableCode` 绘制二维码，**不要直接用 `state.data.value`**。过期、离开页面、退后台时 usableCode 为 null，状态中的凭证也会被清除；页面重新可见时获取新码。成功后按有效期自动刷新，失败后显式重试，避免持续请求学校服务。

按 `displayInfo/displayBalance` 决定是否显示身份和余额。付款码不写缓存、不记录日志。UI 根据 expiresAt 绘制倒计时，不自行延长有效期。

## 充值与电费支付

1. 先加载对应配置，按 `payMethods`、`amountOptions`、`needPaymentPassword` 等字段渲染。
2. 用户确认金额、宿舍和支付方式后，调用 submit；不要在初始化、build、刷新或返回前台时调用。
3. `PaymentState.canSubmit` 控制按钮；submitting 阻止重复点击。控制器检查配置、宿舍匹配、支付方式、正金额（最多两位小数）和需要的密码。支付密码只作为请求参数，不保存到状态或磁盘。
4. `awaitingExternalPayment`：已创建订单/获得支付入口，**不是支付成功**。`order.result` 包含 `type/htmlPost/h5Url/officialTransferUrl/wechatJsapi`，未知 type 使用 `unsupported`。
5. 微信 WAP 优先 `preferredUrl`（officialTransferUrl 优先）；fallback h5 按 `h5Headers` 加学校 Referer。HTML/URL/JSAPI 为外部支付材料，页面需要单独的支付视图和受控导航，不把它们当成可信任的任意原生指令。当前业务层不启动外部 App、不执行 HTML。
6. 仅电费的明确 `balance_payment` 成功响应会进入 `completed`。完成后刷新电量、余额和流水。
7. 超时、5xx 或无法识别的支付成功响应进入 `outcomeUnknown`，提示核对余额/流水，不能一键自动重试。
8. 外部支付返回后也只刷新余额/流水；后端无订单查询接口，不能根据返回 URL 或关闭 WebView 宣称支付成功。
9. 开始另一笔交易用 `beginNewPayment()`；前一笔 pending/unknown 时必须由用户核对后 `beginNewPayment(previousOutcomeChecked: true)`，然后重新加载配置。不要在页面重建时自动调用。

充值页面和学校收银台已接入。待支付/结果未知的最小操作标记按账号持久化，重启后仍需用户核对；支付密码、HTML 和支付链接不写入该标记。没有服务端幂等键或订单状态接口，客户端只能保留核对提示，不能自动确认外部支付最终到账。

## 请求与安全边界

业务统一 POST `/api/v1/run`，Bearer 放请求头，body 只包含 feature/params。请求前使用 AuthController 续期；查询 401 最多续期后重放一次，支付从不自动重放。403 是功能权限错误，不强制退出账号。二次 401 会条件性清理被拒绝的当前会话，旧 Token 的迟到响应不能踢掉新会话。

后端只有非结构化错误文本；页面展示客户端安全文案，不把原始响应、账号密码、Token、付款码或支付 HTML 打到日志。未知学校错误不按文案猜测为 Token 过期。

## 给 Claude 的任务

请先阅读本文及 `docs/design-system.md`，基于 `features/campus/campus.dart` 完成 Flutter 原生首页和后续校园功能页面。首页先实现顶部问候、课程主卡、课表/成绩/考试/电费入口、今日安排，以及首页/课表/我的三个 tab。使用真实业务状态，覆盖加载、成功空列表、失败重试、刷新失败保留旧数据及校历缺失，不在 UI 编造业务数据。保持现有登录视觉，保护其他人的未提交改动。业务接口变更先列出缺口交由 Codex 处理。
