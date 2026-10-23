import { hasNativeAdapter } from '../utils/SchoolRoutes'
import { safePush } from '../utils/RouterHelper'
import { featureByName } from '../utils/Constants'
import { weekdayIndex } from '../utils/CourseCalendar'
import { FeatureDef } from '../models/Types'
import { Course } from '../models/JwTypes'
import { AccountBalance } from '../models/CardTypes'
import { TodoItem } from '../models/TodoTypes'
import { NativeGlass } from '../components/NativeGlass'
import { getCacheEpoch } from '../services/MemoryCache'
import { CampusCard } from '../components/common/CampusCard'
import { CampusIcon } from '../components/common/CampusIcon'
import { CampusHeader } from '../components/common/CampusHeader'
import { getColors, ColorPalette } from '../theme/Colors'
import { Typography } from '../theme/Typography'
import { getUsername, isGatewayAuth } from '../services/AuthManager'
import { callFeature, CallResult } from '../services/ApiService'
import { loadTodos } from '../services/TodoService'
import { getCourseMinutes, formatMinutes, nextClassIndex, sectionsResolved, courseTimeText } from '../utils/ClassTime'
import { isCourseInWeek } from '../utils/WeekParser'

interface TodayCourseItem {
  course: Course
  startMinutes: number
  endMinutes: number
  resolved: boolean
}

interface NextCourseItem {
  title: string
  meta: string
  time: string
}

function readNumber(data: Record<string, Object>, keys: string[], fallback: number): number {
  for (const key of keys) {
    const value = data[key]
    if (value !== undefined && value !== null) {
      const n = Number(value)
      if (!isNaN(n) && isFinite(n) && n > 0) {
        return Math.floor(n)
      }
    }
  }
  return fallback
}


function readCourses(data: Record<string, Object>): Course[] {
  const raw = data['courses']
  if (raw === undefined || raw === null) {
    return []
  }
  return raw as Course[]
}

function readBalanceText(data: Record<string, Object>, fallback: string): string {
  const rawAccounts = data['accounts']
  if (rawAccounts !== undefined && rawAccounts !== null) {
    const accounts = rawAccounts as AccountBalance[]
    if (accounts.length > 0 && accounts[0].balance !== undefined && accounts[0].balance !== null) {
      return '¥' + String(accounts[0].balance)
    }
  }
  const rawBalance = data['balance']
  if (rawBalance !== undefined && rawBalance !== null) {
    return '¥' + String(rawBalance)
  }
  return fallback
}

@Component
export struct HomeTab {
  @Prop @Watch('onActivityChange') active: boolean = true
  @StorageLink('appActive') @Watch('onActivityChange') appActive: boolean = true
  @StorageLink('mainPageActive') @Watch('onActivityChange') mainPageActive: boolean = true
  @StorageLink('safeAreaBottom') safeAreaBottom: number = 0
  @State todayCount: number = 0
  @State weekCount: number = 0
  @State openTodoItems: TodoItem[] = []
  @State courseSummary: NextCourseItem = { title: '正在获取今日课程', meta: '课表同步后显示课程与教室', time: '—' }
  private alive: boolean = false
  private requestBusy: boolean = false
  private summaryTimer: number = -1
  @State username: string = ''
  @State balanceText: string = '--'
  @State term: string = ''
  @StorageLink('scheduleWeekKnown') @Watch('updateSummary') weekKnown: boolean = false
  @StorageLink('currentWeek') @Watch('updateSummary') currentWeek: number = 1
  @StorageLink('totalWeeks') totalWeeks: number = 20
  @State courses: Course[] = []
  @State todos: TodoItem[] = []
  @State loadingBrief: boolean = true
  @State scheduleReady: boolean = false
  @State scheduleError: string = ''
  @State balanceError: boolean = false
  @StorageLink('isDark') @Watch('onThemeChange') isDark: boolean = false
  @State palette: ColorPalette = getColors(false)

  aboutToAppear(): void {
    this.alive = true
    this.palette = getColors(this.isDark)
    this.username = getUsername()
    this.currentWeek = AppStorage.get<number>('currentWeek') ?? 1
    this.totalWeeks = AppStorage.get<number>('totalWeeks') ?? 20
    this.onActivityChange()
  }

  aboutToDisappear(): void {
    this.alive = false
    this.stopSummaryTimer()
  }

  onThemeChange(): void { this.palette = getColors(this.isDark) }

  private stopSummaryTimer(): void {
    if (this.summaryTimer >= 0) clearInterval(this.summaryTimer)
    this.summaryTimer = -1
  }

  onActivityChange(): void {
    this.stopSummaryTimer()
    if (!this.alive || !this.active || !this.appActive || !this.mainPageActive) return
    this.updateSummary()
    this.loadBrief(false)
    this.summaryTimer = setInterval(() => { this.updateSummary() }, 60 * 1000)
  }

  private updateSummary(): void {
    this.weekCount = this.weekCourses().length
    this.todayCount = this.todayItems().length
    this.openTodoItems = this.todos.filter((item: TodoItem): boolean => !item.done)
    this.courseSummary = this.nextCourse()
  }

  private async loadBrief(forceRefresh: boolean): Promise<void> {
    if (this.requestBusy || !this.alive) return
    this.requestBusy = true
    this.loadingBrief = true
    const username = getUsername()
    const epoch = getCacheEpoch()
    const valid = (): boolean => this.alive && epoch === getCacheEpoch() && username === getUsername()
    const params: Record<string, Object> = forceRefresh ? { '_forceRefresh': true } : {}
    try {
      await Promise.all([
        (async (): Promise<void> => {
          const schedule: CallResult = await callFeature('jw.schedule', username, params)
          if (!valid()) return
          if (schedule.ok) {
            this.scheduleReady = true
            this.scheduleError = ''
            this.term = String(schedule.data['term'] ?? this.term)
            this.totalWeeks = readNumber(schedule.data, ['totalWeeks', 'weeksTotal'], this.totalWeeks)
            this.currentWeek = AppStorage.get<number>('currentWeek') ?? this.currentWeek
            this.courses = readCourses(schedule.data)
            AppStorage.setOrCreate<string>('term', this.term)
            AppStorage.setOrCreate<number>('currentWeek', this.currentWeek)
            AppStorage.setOrCreate<number>('totalWeeks', this.totalWeeks)
          } else { this.scheduleError = schedule.error }
          this.updateSummary()
        })(),
        (async (): Promise<void> => {
          const balance: CallResult = await callFeature('newcard.balance', username, params)
          if (!valid()) return
          this.balanceError = !balance.ok
          if (balance.ok) this.balanceText = readBalanceText(balance.data, '--')
        })(),
        (async (): Promise<void> => {
          const todos = await loadTodos()
          if (!valid()) return
          this.todos = todos
          this.updateSummary()
        })(),
      ])
    } finally {
      this.requestBusy = false
      if (valid()) { this.loadingBrief = false; this.updateSummary() }
    }
  }

  openFeature(f: FeatureDef): void {
    if (f.page === 'SchedulePage') { AppStorage.setOrCreate<string>('campusRoute', 'schedule'); return }
    safePush(this.getUIContext(), {
      url: isGatewayAuth() || hasNativeAdapter(f.name) || f.system === 'local' ? 'pages/' + f.page : 'pages/SchoolServicePage',
      params: { 'feature': f.name, 'title': f.title } as Record<string, Object>,
    })
  }

  private todayName(): string {
    const names: string[] = ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六']
    return names[new Date().getDay()]
  }

  private weekCourses(): Course[] {
    return this.courses.filter((c: Course): boolean => isCourseInWeek(c.weeks, this.currentWeek, this.totalWeeks))
  }

  private todayItems(): TodayCourseItem[] {
    // 用 weekdayIndex 容错解析而不是"星期X"字符串精确比较：
    // 课表里可能出现「周一」「Mon」「1」等写法，精确比较会让这些课在今日列表里消失。
    const todayIndex: number = (new Date().getDay() + 6) % 7
    return this.weekCourses()
      .filter((c: Course): boolean => weekdayIndex(c.day) === todayIndex)
      .map((c: Course): TodayCourseItem => {
        const se: number[] = getCourseMinutes(c.sections)
        return { course: c, startMinutes: se[0], endMinutes: se[1], resolved: sectionsResolved(c.sections) }
      })
      .sort((a: TodayCourseItem, b: TodayCourseItem): number =>
        a.resolved === b.resolved ? a.startMinutes - b.startMinutes : (a.resolved ? -1 : 1))
  }

  private nextCourse(): NextCourseItem {
    if (!this.scheduleReady) {
      return {
        title: this.loadingBrief ? '正在获取今日课程' : '课表暂未加载',
        meta: this.loadingBrief ? '课表同步后显示课程与教室' : '点右上角刷新，或进入课表重试',
        time: '—',
      }
    }
    if (!this.weekKnown) return { title: '请确认当前教学周', meta: '进入课表，按学校校历校准本周', time: '待确认' }
    const today = this.todayItems()
    const resolvedToday = today.filter((item: TodayCourseItem): boolean => item.resolved)
    const pending = today.filter((item: TodayCourseItem): boolean => !item.resolved)
    const idx = nextClassIndex(resolvedToday)
    if (idx < 0) {
      // 节次无法解析时不能声称“已结束”：给出明确待确认提示，而不是静默当无课。
      if (pending.length > 0) {
        return {
          title: '节次待确认的课程',
          meta: pending.map((item: TodayCourseItem): string => item.course.title).join('、') + ' · 进入课表查看',
          time: '待确认',
        }
      }
      return {
        title: today.length === 0 ? '今天没有课' : '今日课程已结束',
        meta: today.length === 0 ? '可以安排作业、运动或自己的计划' : '查看明天的安排，提前准备好',
        time: today.length === 0 ? '无课' : '已结束',
      }
    }
    const item = resolvedToday[idx]
    return {
      title: item.course.title,
      meta: item.course.location + ' · ' + item.course.teacher,
      time: courseTimeText(item.course.sections),
    }
  }

  private courseLabel(): string {
    if (!this.scheduleReady || !this.weekKnown) return '今日安排'
    const today = this.todayItems().filter((item: TodayCourseItem): boolean => item.resolved)
    const index = nextClassIndex(today)
    if (index < 0) return '今日安排'
    const now = new Date()
    const minutes = now.getHours() * 60 + now.getMinutes()
    return minutes >= today[index].startMinutes && minutes < today[index].endMinutes ? '正在上课' : '下一节课'
  }

  private dateLabel(): string {
    const date = new Date()
    return (date.getMonth() + 1).toString() + '月' + date.getDate().toString() + '日 · ' + this.todayName()
  }

  private quickFeatures(): FeatureDef[] {
    // 8 项常用服务全部平铺可见，不再折叠：电费查询与一卡通充值排前两位。
    return [featureByName('newcard.electricity.account'), featureByName('newcard.recharge.config'),
      featureByName('jw.schedule'), featureByName('jw.grades'), featureByName('jw.exams'),
      featureByName('newcard.transactions'), featureByName('local.todos')]
  }

  private featureIcon(item: FeatureDef): ResourceStr {
    if (item.page === 'QRCodePage') return $r('app.media.campus_pay')
    if (item.page === 'SchedulePage') return $r('app.media.campus_schedule')
    if (item.page === 'GradesPage') return $r('app.media.campus_grades')
    if (item.page === 'ExamsPage') return $r('app.media.campus_exams')
    if (item.page === 'RechargePage') return $r('app.media.campus_recharge')
    if (item.page === 'ElectricityPage') return $r('app.media.campus_electric')
    if (item.page === 'TransactionsPage') return $r('app.media.campus_transactions')
    if (item.page === 'TodoPage') return $r('app.media.campus_todo')
    return $r('app.media.campus_training')
  }

  private openTodos(): TodoItem[] {
    return this.todos.filter((item: TodoItem): boolean => !item.done)
  }

  @Builder
  SectionHeading(title: string, action: string, item: FeatureDef) {
    Row() {
      Text(title).fontSize(Typography.subtitle.fontSize).fontWeight(FontWeight.Bold).fontColor(this.palette.onSurface)
      Blank()
      Button(action).fontSize(12).fontColor(this.palette.primary).backgroundColor(Color.Transparent)
        .height(44).padding({ left: 8, right: 0 }).onClick(() => this.openFeature(item))
    }.width('100%').margin({ bottom: 10 })
  }

  @Builder
  QuickAction(item: FeatureDef) {
    Column({ space: 9 }) {
      CampusIcon({ source: this.featureIcon(item), iconSize: 44, badgeColor: (item.page === 'ElectricityPage' || item.page === 'RechargePage') ? this.palette.accentContainer : this.palette.primaryContainer })
      Text(item.title.replace('校园', '').replace('一卡通', '').replace('查询', ''))
        .fontSize(12).fontColor(this.palette.onSurface).maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
      .layoutWeight(1).height(76).justifyContent(FlexAlign.Center)
      .onClick(() => this.openFeature(item))
      .accessibilityText(item.title)
  }

  @Builder
  CourseOverview() {
    NativeGlass({ contentPadding: 20, radius: 26, prominent: true, interactive: true }) {
      Column({ space: 14 }) {
        Row() {
          Row({ space: 7 }) {
            Row().width(6).height(6).borderRadius(3).backgroundColor(this.palette.accent)
            Text(this.courseLabel()).fontSize(Typography.label.fontSize).fontWeight(FontWeight.Medium).fontColor(this.palette.onSurface)
          }
          Blank()
          Text(this.weekKnown ? '第 ' + this.currentWeek + ' 周' : '周次待确认')
            .fontSize(Typography.caption.fontSize).fontColor(this.palette.onSurfaceVariant)
            .padding({ left: 11, right: 11, top: 6, bottom: 6 })
            .backgroundColor(this.isDark ? '#402C4666' : '#80FFFFFF').borderRadius(12)
        }.width('100%')
        Column({ space: 8 }) {
          Text(this.courseSummary.title).fontSize(23).fontWeight(FontWeight.Bold)
            .fontColor(this.palette.onSurface).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
          Text(this.courseSummary.meta).fontSize(Typography.bodySm.fontSize).fontColor(this.palette.onSurfaceVariant)
            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        }.width('100%').alignItems(HorizontalAlign.Start)
        Divider().color(this.isDark ? '#407A98BC' : '#803F6A99')
        Row({ space: 16 }) {
          Column({ space: 4 }) {
            Text(this.scheduleReady ? this.courseSummary.time : '待同步')
              .fontSize(Typography.headline.fontSize).fontWeight(FontWeight.Bold).fontColor(this.palette.onSurface)
            Text(this.scheduleReady ? '今天 ' + this.todayCount + ' 门课' : '下一节课，随时掌握')
              .fontSize(Typography.caption.fontSize).fontColor(this.palette.onSurfaceVariant)
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          Text('查看课表  ↗').fontSize(Typography.label.fontSize).fontWeight(FontWeight.Medium).fontColor(this.palette.primary)
            .padding({ left: 12, right: 12, top: 12, bottom: 12 })
            .backgroundColor(this.isDark ? '#70223A60' : '#A8FFFFFF').borderRadius(16)
        }.width('100%')
      }.alignItems(HorizontalAlign.Start).width('100%')
        .onClick(() => this.openFeature(featureByName('jw.schedule')))
        .accessibilityGroup(true).accessibilityText('今日安排，' + this.courseSummary.title + '，' + this.courseSummary.meta)
        .accessibilityDescription('点击查看完整课表')
    }
  }

  @Builder
  CampusBalance() {
    CampusCard({ contentPadding: 16, radius: 22 }) {
      Column({ space: 10 }) {
        Row({ space: 12 }) {
          CampusIcon({ source: $r('app.media.campus_card'), iconSize: 40, badgeColor: this.palette.primaryContainer })
          Column({ space: 4 }) {
            Text('校园卡 · 可用余额').fontSize(11).fontColor(this.palette.onSurfaceVariant)
            Text(this.balanceText).fontSize(23).fontWeight(FontWeight.Bold).fontColor(this.palette.onSurface)
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            .accessibilityGroup(true).accessibilityText('校园卡可用余额，' + this.balanceText + '，查看余额详情')
            .onClick(() => this.openFeature(featureByName('newcard.balance')))
          Button('付款码').height(46).padding({ left: 18, right: 18 }).fontSize(14).fontWeight(FontWeight.Medium)
            .fontColor(this.palette.onPrimary).backgroundColor(this.palette.primary).borderRadius(14)
            .onClick(() => this.openFeature(featureByName('newcard.campus_code.qrcode')))
        }.width('100%')
        if (this.balanceError) {
          Text('余额暂未更新，点击余额可重新查询').fontSize(12).fontColor(this.palette.onSurfaceVariant).width('100%')
        }
      }.width('100%').alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  TodoPreview(item: TodoItem) {
    Row({ space: 12 }) {
      Row().width(16).height(16).borderRadius(8)
        .border({ width: 1.5, color: this.palette.outline })
      Column({ space: 5 }) {
        Text(item.title).fontSize(14).fontColor(this.palette.onSurface)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(item.dueText.length > 0 ? item.dueText : '未设置截止时间')
          .fontSize(Typography.caption.fontSize).fontColor(this.palette.onSurfaceVariant)
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      Text('›').fontSize(18).fontColor(this.palette.onSurfaceVariant)
    }.width('100%').padding({ top: 10, bottom: 10 }).onClick(() => this.openFeature(featureByName('local.todos')))
  }

  build() {
    Column() {
      CampusHeader({
        title: '', subtitle: this.dateLabel(), action: '刷新', loading: this.loadingBrief,
        onAction: () => { this.loadBrief(true) },
      })
      Scroll() {
        Column({ space: 20 }) {
          this.CourseOverview()
          if (this.scheduleError.length > 0) {
            Text(this.scheduleReady ? '课表更新失败，暂时显示已有数据' : '课表暂不可用，请刷新重试')
              .fontSize(12).fontColor(this.palette.onSurfaceVariant).width('100%')
          }
          Column() { this.CampusBalance() }.width('100%')
          Column() {
            Row() {
              Text('常用服务').fontSize(17).fontWeight(FontWeight.Bold).fontColor(this.palette.onSurface).layoutWeight(1)
            }.width('100%').margin({ bottom: 4 })
            CampusCard({ contentPadding: 10 }) {
              Column({ space: 10 }) {
                Row() {
                  ForEach(this.quickFeatures().slice(0, 4), (item: FeatureDef) => { this.QuickAction(item) },
                    (item: FeatureDef): string => item.name)
                }.width('100%')
                Divider().color(this.palette.outline)
                Row() {
                  ForEach(this.quickFeatures().slice(4, 8), (item: FeatureDef) => { this.QuickAction(item) },
                    (item: FeatureDef): string => item.name)
                }.width('100%')
              }.width('100%')
            }
          }.width('100%')
          // 待办已提升为底部导航的独立一页，首页不再重复展示它的摘要：
          // 同一个东西出现在两处，用户会分不清「在首页勾掉」和「进待办页处理」
          // 是不是同一件事。首页只留概览性内容。
        }
          .width('100%')
          .padding({ left: 20, right: 20, top: 4, bottom: this.safeAreaBottom + 104 })
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
    }.width('100%').height('100%').backgroundColor(Color.Transparent)
  }
}
