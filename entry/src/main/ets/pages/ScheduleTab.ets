import { getColors, ColorPalette } from '../theme/Colors'
import { Course } from '../models/JwTypes'
import { getCacheEpoch } from '../services/MemoryCache'
import { loadUiState, saveUiState } from '../services/UiStateCache'
import { callFeature, CallResult } from '../services/ApiService'
import { getUsername } from '../services/AuthManager'
import { getTerm } from '../utils/SemesterService'
import { isCourseInWeek } from '../utils/WeekParser'
import { WeekSelector } from '../components/WeekSelector'
import { ScheduleGrid } from '../components/ScheduleGrid'
import { WeekOverview } from '../components/WeekOverview'
import { NextClassCard } from '../components/NextClassCard'
import { CampusCard } from '../components/common/CampusCard'
import { CampusHeader } from '../components/common/CampusHeader'
import { navToMap } from '../utils/MapDeepLink'
import { safePush } from '../utils/RouterHelper'
import { getCourseMinutes, formatMinutes, classStatus, sectionsResolved, courseTimeText } from '../utils/ClassTime'
import { unresolvedCourses, weekdayIndex } from '../utils/CourseCalendar'
import { Radius } from '../theme/Radius'
import { safeToast } from '../utils/ToastHelper'
import { startCourseLiveView } from '../services/LiveViewService'

interface TodayCourseItem {
  course: Course
  startMinutes: number
  endMinutes: number
  resolved: boolean
}

function readNumber(data: Record<string, Object>, keys: string[], fallback: number): number {
  for (const key of keys) {
    const value = data[key]
    if (value !== undefined && value !== null) {
      const n = Number(value)
      if (Number.isInteger(n) && n >= 1 && n <= 60) {
        return n
      }
    }
  }
  return fallback
}


@Component
export struct ScheduleTab {
  @Prop @Watch('onActivityChange') active: boolean = true
  @StorageLink('appActive') @Watch('onActivityChange') appActive: boolean = true
  @StorageLink('mainPageActive') @Watch('onActivityChange') mainPageActive: boolean = true
  @StorageLink('safeAreaBottom') safeAreaBottom: number = 0
  @State filteredCourses: Course[] = []
  @State sortedToday: TodayCourseItem[] = []
  @State unresolvedThisWeek: Course[] = []
  private alive: boolean = false
  private requestBusy: boolean = false
  private hasLoaded: boolean = false
  @State term: string = ''
  @State allCourses: Course[] = []
  @State loading: boolean = true
  @State refreshing: boolean = false
  @State errorMsg: string = ''
  @State @Watch('updateDerived') selectedWeek: number = 1
  @State @Watch('saveUi') viewMode: number = 1
  @State @Watch('saveUi') detailedWeek: boolean = false
  private restoredWeek: number = 0
  @StorageLink('scheduleWeekKnown') weekKnown: boolean = false
  @StorageLink('liveViewEnabled') liveEnabled: boolean = false
  @StorageLink('liveViewStatus') liveStatus: string = '未开启'
  @StorageLink('currentWeek') currentWeek: number = 1
  @StorageLink('totalWeeks') @Watch('updateDerived') totalWeeks: number = 20
  @StorageLink('isDark') @Watch('onThemeChange') isDark: boolean = false
  @State palette: ColorPalette = getColors(false)

  aboutToAppear(): void {
    this.alive = true
    this.palette = getColors(this.isDark)
    this.term = getTerm()
    this.selectedWeek = this.currentWeek
    // 会话内恢复上次浏览的周次/视图（登出后缓存已清空，不会跨账号泄露）。
    const saved: Record<string, Object> | null = loadUiState('schedule-tab', 0)
    if (saved !== null) {
      const week: number = Number(saved['selectedWeek'])
      if (Number.isInteger(week) && week >= 1 && week <= this.totalWeeks) { this.selectedWeek = week; this.restoredWeek = week }
      const mode: number = Number(saved['viewMode'])
      if (Number.isFinite(mode) && (mode === 0 || mode === 1)) this.viewMode = mode
      this.detailedWeek = saved['detailedWeek'] === true
    }
    this.onActivityChange()
  }
  aboutToDisappear(): void { this.alive = false }
  onThemeChange(): void { this.palette = getColors(this.isDark) }
  onActivityChange(): void {
    if (!this.alive || !this.active || !this.appActive || !this.mainPageActive) return
    this.updateDerived()
    this.loadSchedule(false)
  }
  updateDerived(): void {
    this.filteredCourses = this.allCourses.filter((c: Course): boolean =>
      isCourseInWeek(c.weeks, this.selectedWeek, this.totalWeeks))
    const todayIndex: number = (new Date().getDay() + 6) % 7
    this.sortedToday = this.filteredCourses.filter((c: Course): boolean => weekdayIndex(c.day) === todayIndex)
      .map((c: Course): TodayCourseItem => {
        const range = getCourseMinutes(c.sections)
        return { course: c, startMinutes: range[0], endMinutes: range[1], resolved: sectionsResolved(c.sections) }
      }).sort((a: TodayCourseItem, b: TodayCourseItem): number =>
        a.resolved === b.resolved ? a.startMinutes - b.startMinutes : (a.resolved ? -1 : 1))
    this.unresolvedThisWeek = unresolvedCourses(this.allCourses, this.selectedWeek, this.totalWeeks)
    this.saveUi()
  }
  saveUi(): void {
    if (!this.alive) return
    saveUiState('schedule-tab', 0, {
      'selectedWeek': this.selectedWeek, 'viewMode': this.viewMode, 'detailedWeek': this.detailedWeek,
    } as Record<string, Object>)
  }
  private async loadSchedule(forceRefresh: boolean): Promise<void> {
    if (this.requestBusy || !this.alive) return
    this.requestBusy = true
    this.refreshing = forceRefresh
    this.loading = !this.hasLoaded
    const username = getUsername()
    const epoch = getCacheEpoch()
    try {
      const params: Record<string, Object> = forceRefresh ? { '_forceRefresh': true } : {}
      const res: CallResult = await callFeature('jw.schedule', username, params)
      if (!this.alive || epoch !== getCacheEpoch() || username !== getUsername()) return
      if (res.ok) {
        this.errorMsg = ''
        this.term = String(res.data['term'] ?? this.term)
        this.totalWeeks = readNumber(res.data, ['totalWeeks', 'weeksTotal'], this.totalWeeks)
        this.currentWeek = AppStorage.get<number>('currentWeek') ?? this.currentWeek
        // 首次加载时若已恢复用户上次浏览的周次，则保留并做范围收敛，不回退到当前周。
        const preferredWeek: number = (this.hasLoaded || this.restoredWeek > 0) ? this.selectedWeek : this.currentWeek
        this.selectedWeek = Number.isInteger(preferredWeek) ? Math.max(1, Math.min(preferredWeek, this.totalWeeks)) : 1
        this.hasLoaded = true
        AppStorage.setOrCreate<string>('term', this.term)
        this.allCourses = (res.data['courses'] ?? []) as Course[]
        this.updateDerived()
    
      } else if (!this.hasLoaded) { this.errorMsg = res.error }
      else if (forceRefresh) { safeToast(this.getUIContext(), '更新失败，保留已有课表') }
    } catch (_error) {
      if (!this.alive || epoch !== getCacheEpoch() || username !== getUsername()) return
      if (!this.hasLoaded) this.errorMsg = '连接未完成，请稍后重试'
      else if (forceRefresh) safeToast(this.getUIContext(), '更新失败，保留已有课表')
    } finally {
      this.requestBusy = false
      if (this.alive && epoch === getCacheEpoch()) { this.loading = false; this.refreshing = false }
    }
  }

  private todayName(): string {
    const names: string[] = ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六']
    return names[new Date().getDay()]
  }

  private weekCourses(): Course[] { return this.filteredCourses }
  private todayItems(): TodayCourseItem[] { return this.sortedToday }

  private statText(): string {
    const todayCount = this.todayItems().length
    const weekCount = this.weekCourses().length
    return `第 ${this.selectedWeek} 周 · 当天 ${todayCount} 门 · 本周 ${weekCount} 门`
  }

  private unresolvedListText(): string {
    return this.unresolvedThisWeek.map((c: Course): string => c.day + ' ' + c.sections + ' ' + c.title).join('；')
  }

  private openCourseLocation(course: Course): void {
    this.getUIContext().getPromptAction().showDialog({ title: course.title,
      message: course.day + ' · ' + course.sections + '\n' + course.weeks + '\n' + course.location + '\n' + course.teacher,
      buttons: [{ text: '关闭', color: this.palette.onSurfaceVariant }, { text: '教室导航', color: this.palette.primary }]
    }).then((result) => { if (result.index === 1) navToMap(course.location, this.getUIContext()) }).catch((_e: Error) => {})
  }

  private openDay(day: number): void {
    const names: string[] = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日']
    const courses = this.filteredCourses.filter((course: Course): boolean => course.day === names[day])
      .sort((a: Course, b: Course): number => getCourseMinutes(a.sections)[0] - getCourseMinutes(b.sections)[0])
    const message = courses.length === 0 ? '这一天没有课程，可以安排自己的计划。' : courses.map((course: Course): string =>
      courseTimeText(course.sections) + '  ' + course.title + '\n' + course.location + ' · ' + course.teacher + '\n' + course.sections
    ).join('\n\n')
    this.getUIContext().getPromptAction().showDialog({ title: '第 ' + this.selectedWeek + ' 周 · ' + names[day], message,
      buttons: [{ text: '关闭', color: this.palette.primary }] }).catch((_e: Error) => {})
  }

  private async tryCourseLiveView(item: TodayCourseItem): Promise<void> {
    const date = new Date()
    const start = new Date(date.getFullYear(), date.getMonth(), date.getDate(), Math.floor(item.startMinutes / 60), item.startMinutes % 60)
    const end = new Date(date.getFullYear(), date.getMonth(), date.getDate(), Math.floor(item.endMinutes / 60), item.endMinutes % 60)
    const result = await startCourseLiveView(item.course, start.getTime(), end.getTime())
    safeToast(this.getUIContext(), result.ok ? '系统实况窗已更新' : (result.reason !== undefined ? result.reason : '当前不可用'))
  }

  private timelineStatus(item: TodayCourseItem): number {
    return this.weekKnown && this.selectedWeek === this.currentWeek ? classStatus(item.startMinutes, item.endMinutes) : 0
  }
  private statusLabel(status: number): string {
    if (status === 1) return '进行中'
    if (status === 2) return '已结束'
    return '未开始'
  }

  private statusColor(status: number): string {
    if (status === 1) return this.palette.success
    if (status === 2) return this.palette.onSurfaceVariant
    return this.palette.primary
  }

  private switchViewMode(mode: number): void {
    this.viewMode = mode
  }

  @Builder
  ModeSegment(label: string, mode: number) {
    Column() {
      Text(label)
        .fontSize(13)
        .fontWeight(this.viewMode === mode ? FontWeight.Bold : FontWeight.Regular)
        .fontColor(this.viewMode === mode ? this.palette.onPrimaryContainer : this.palette.onSurfaceVariant)
        .textAlign(TextAlign.Center)
    }
    .layoutWeight(1)
    .height(44)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.viewMode === mode ? this.palette.primaryContainer : Color.Transparent)
    .borderRadius(Radius.sm)
    .onClick(() => { this.switchViewMode(mode) })
    .accessibilityText(label + (this.viewMode === mode ? '，已选中' : '，切换视图'))
  }

  @Builder
  ModeSwitch() {
    Row() {
      this.ModeSegment('今日清单', 0)
      this.ModeSegment('整周课表', 1)
    }
    .height(52)
    .padding(4)
    .margin({ left: 20, right: 20, top: 2, bottom: 10 })
    .backgroundColor(this.palette.surface)
    .borderRadius(Radius.md)
    .border({ width: 0.5, color: this.palette.outline })
  }

  @Builder
  TodayTimeline() {
    if (this.todayItems().length === 0) {
      Column() {
        CampusCard({ contentPadding: 20, radius: 20 }) {
          Column() {
            Text(this.selectedWeek === this.currentWeek ? '今天没有课' : '所选周的当天没有课')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.palette.onSurface)
            Text('可以安排作业、运动或自己的计划。')
              .fontSize(12)
              .fontColor(this.palette.onSurfaceVariant)
              .margin({ top: 8 })
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .height(60)
        }
      }
      .margin({ left: 16, right: 16, top: 12 })
    } else {
      Column() {
        ForEach(this.todayItems(), (item: TodayCourseItem, index: number) => {
          Row() {
            Column() {
              if (item.resolved) {
                Text(formatMinutes(item.startMinutes))
                  .fontSize(13)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.palette.onSurface)
                Text(formatMinutes(item.endMinutes))
                  .fontSize(11)
                  .fontColor(this.palette.onSurfaceVariant)
                  .margin({ top: 2 })
              } else {
                Text('待确认')
                  .fontSize(11)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.palette.onSurfaceVariant)
              }
            }
            .width(56)
            .alignItems(HorizontalAlign.Start)

            Column() {
              Row().width(9).height(9).borderRadius(4.5)
                .backgroundColor(this.statusColor(this.timelineStatus(item)))
              if (index < this.todayItems().length - 1) {
                Divider()
                  .vertical(true)
                  .height(76)
                  .strokeWidth(1)
                  .color(this.palette.outline)
              }
            }
            .width(18)
            .alignItems(HorizontalAlign.Center)

            Column() {
              CampusCard({ contentPadding: 16, radius: 18 }) {
                Column() {
                  Row() {
                    Text(item.course.title)
                      .fontSize(15)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(this.palette.onSurface)
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .layoutWeight(1)
                    Text(!item.resolved ? '节次待确认' : (!this.weekKnown ? '周次待确认' : (this.selectedWeek === this.currentWeek ? this.statusLabel(this.timelineStatus(item)) : '第 ' + this.selectedWeek.toString() + ' 周')))
                      .fontSize(11)
                      .fontColor(this.statusColor(this.timelineStatus(item)))
                      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                      .backgroundColor(this.palette.surfaceVariant)
                      .borderRadius(Radius.sm)
                  }
                  .width('100%')

                  Text(item.course.teacher + ' · ' + item.course.location)
                    .fontSize(12)
                    .fontColor(this.palette.onSurfaceVariant)
                    .margin({ top: 6 })
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })

                  Row() {
                    Text(item.course.sections + ' · ' + item.course.weeks)
                      .fontSize(11)
                      .fontColor(this.palette.onSurfaceVariant)
                      .layoutWeight(1)
                    if (item.resolved && this.weekKnown && this.selectedWeek === this.currentWeek && this.liveEnabled && this.timelineStatus(item) !== 2) {
                    Text('实况窗')
                      .fontSize(12)
                      .fontColor(this.palette.accent)
                      .padding({ left: 12, right: 12 }).constraintSize({ minHeight: 44 }).textAlign(TextAlign.Center)
                      .backgroundColor(this.palette.accentContainer)
                      .borderRadius(Radius.sm)
                      .margin({ right: 8 })
                      .onClick(() => this.tryCourseLiveView(item))
                    }
                    Text('导航')
                      .fontSize(12)
                      .fontColor(this.palette.primary)
                      .padding({ left: 12, right: 12 }).constraintSize({ minHeight: 44 }).textAlign(TextAlign.Center)
                      .backgroundColor(this.palette.primaryContainer)
                      .borderRadius(Radius.sm)
                      .onClick(() => this.openCourseLocation(item.course))
                  }
                  .width('100%')
                  .margin({ top: 10 })
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
              }
            }
            .layoutWeight(1)
            .onClick(() => this.openCourseLocation(item.course))
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8 })
        }, (item: TodayCourseItem): string => item.course.day + item.course.sections + item.course.title)
      }
      .width('100%')
    }
  }

  build() {
    Column() {
      CampusHeader({
        title: '我的课表',
        subtitle: this.term.length > 0 ? this.term + ' 学期' : '课程、时间与教室',
        action: '刷新', loading: this.refreshing || this.loading,
        onAction: () => { this.loadSchedule(true) },
      })

      if (!this.loading && this.errorMsg.length === 0) {
        Text(this.statText())
          .fontSize(12)
          .fontColor(this.palette.onSurfaceVariant)
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 8 })

        if (!this.weekKnown) {
          Text('请确认当前教学周 ›').fontSize(12).fontColor(this.palette.primary).width('100%')
            .padding({ left: 16, bottom: 8 }).onClick(() => safePush(this.getUIContext(), { url: 'pages/CampusSettingsPage' }))
        }
        this.ModeSwitch()
      }

      Scroll() {
        Column() {
          if (!this.loading && this.errorMsg.length === 0) {
            WeekSelector({
              currentWeek: this.selectedWeek,
              totalWeeks: this.totalWeeks,
              onWeekChange: (w: number) => { this.selectedWeek = w },
            })

            if (this.viewMode === 0 && this.weekKnown && this.selectedWeek === this.currentWeek && this.todayItems().length > 0) {
              NextClassCard({
                active: this.active && this.appActive && this.mainPageActive,
                courses: this.todayItems().map((item: TodayCourseItem): Course => item.course),
                onTapNavigate: (loc: string) => { navToMap(loc, this.getUIContext()) },
              })
              .padding({ left: 16, right: 16, top: 2, bottom: 8 })
            }

            // 实况窗状态条。真机上最常问的是"我开了开关，胶囊怎么没出现"——
            // 原因可能是系统开关没开、场景权益没批、还没进入课前十分钟，也可能是
            // 载荷被拒。这些只在设置页能看到，而用户是在课表页等结果的。
            if (this.liveEnabled && this.liveStatus.length > 0 && this.liveStatus !== '未开启') {
              Row({ space: 8 }) {
                Image($r('app.media.nav_calendar')).width(15).height(15)
                  .fillColor(this.palette.primary)
                Text(this.liveStatus).fontSize(12).lineHeight(18).layoutWeight(1)
                  .fontColor(this.palette.onSurfaceVariant)
              }
              .width('100%').padding({ left: 16, right: 16, top: 10, bottom: 10 })
              .margin({ left: 16, right: 16, bottom: 8 })
              .borderRadius(12).backgroundColor(this.palette.surfaceVariant)
              .accessibilityText('实况窗状态：' + this.liveStatus)
            }
          }

          if (this.loading) {
            Column() {
              LoadingProgress().width(32).height(32).color(this.palette.primary)
              Text('正在整理课表...')
                .fontSize(14)
                .fontColor(this.palette.onSurfaceVariant)
                .margin({ top: 12 })
            }
            .height(360)
            .width('100%')
            .justifyContent(FlexAlign.Center)
          } else if (this.errorMsg.length > 0) {
            Column() {
              CampusCard({ contentPadding: 20, radius: 20 }) {
                Column() {
                  Text('学校课表')
                    .fontSize(18)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.palette.error)
                  Text(this.errorMsg)
                    .fontSize(13)
                    .fontColor(this.palette.onSurfaceVariant)
                    .margin({ top: 8 })
                  Button('重新同步课表').height(44)
                    .fontSize(13)
                    .fontColor(this.palette.onPrimary)
                    .padding({ left: 18, right: 18 })
                    .backgroundColor(this.palette.primary)
                    .borderRadius(Radius.sm)
                    .margin({ top: 14 })
                    .onClick(() => this.loadSchedule(true))
                }
                .alignItems(HorizontalAlign.Start)
                .width('100%')
              }
            }
            .margin({ left: 16, right: 16, top: 18 })
          } else if (this.viewMode === 0) {
            this.TodayTimeline()
          } else {
            Column({ space: 12 }) {
              if (this.unresolvedThisWeek.length > 0) {
                Column({ space: 4 }) {
                  Text('有 ' + this.unresolvedThisWeek.length + ' 门课的节次不在当前作息表中，未排进时间轴')
                    .fontSize(12).fontWeight(FontWeight.Bold).fontColor(this.palette.error).width('100%')
                  Text(this.unresolvedListText()).fontSize(11).fontColor(this.palette.onSurfaceVariant).width('100%')
                }
                .padding(12).width('100%').borderRadius(Radius.sm).backgroundColor(this.palette.surfaceVariant)
              }
              Row({ space: 8 }) {
                Text('第 ' + this.selectedWeek + ' 周').fontSize(16).fontWeight(FontWeight.Bold)
                  .fontColor(this.palette.onSurface).layoutWeight(1)
                Button(this.detailedWeek ? '七天总览' : '放大课表').height(44).padding({ left: 12, right: 12 })
                  .fontSize(12).fontColor(this.palette.primary).backgroundColor(this.palette.primaryContainer).borderRadius(14)
                  .onClick(() => { this.detailedWeek = !this.detailedWeek })
              }.width('100%')
              if (this.detailedWeek) {
                ScheduleGrid({
                  courses: this.allCourses, currentWeek: this.selectedWeek, totalWeeks: this.totalWeeks,
                  actualWeek: this.currentWeek, weekKnown: this.weekKnown,
                  onCourseTap: (c: Course) => { this.openCourseLocation(c) },
                  onCourseLongPress: (c: Course) => { this.openCourseLocation(c) },
                })
              } else {
                Text('点击星期查看当天清单 · 点击课程查看详情').fontSize(11).fontColor(this.palette.onSurfaceVariant).width('100%')
                WeekOverview({
                  courses: this.allCourses, currentWeek: this.selectedWeek, totalWeeks: this.totalWeeks,
                  actualWeek: this.currentWeek, weekKnown: this.weekKnown,
                  onCourseTap: (c: Course) => { this.openCourseLocation(c) },
                  onDayTap: (day: number) => { this.openDay(day) },
                })
              }
            }.width('100%').padding({ left: 12, right: 12, top: 4, bottom: 16 })
          }
        }
        .width('100%')
        .padding({ bottom: this.safeAreaBottom + 104 })
      }
      .scrollBar(BarState.Off)
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
  }
}
