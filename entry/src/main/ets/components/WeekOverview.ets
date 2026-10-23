import { getColors, ColorPalette, withAlpha } from '../theme/Colors'
import { Course } from '../models/JwTypes'
import { ALL_TIMES, ClassTime, classStatus, formatMinutes } from '../utils/ClassTime'
import { scheduleBlocks, ScheduleBlock } from '../utils/ScheduleLayout'
import { stableHash } from '../utils/Hash'

/** Seven-day overview; daily headers also open a fully readable agenda. */
@Component
export struct WeekOverview {
  @Prop @Watch('refreshBlocks') courses: Course[] = []
  @Prop @Watch('refreshBlocks') currentWeek: number = 1
  @Prop @Watch('refreshBlocks') totalWeeks: number = 20
  @Prop actualWeek: number = 1
  @Prop weekKnown: boolean = false
  onCourseTap: (course: Course) => void = (_: Course) => {}
  onDayTap: (day: number) => void = (_: number) => {}
  @StorageLink('isDark') @Watch('onThemeChange') isDark: boolean = false
  @State palette: ColorPalette = getColors(false)
  @State blocks: ScheduleBlock[] = []
  @State availableWidth: number = 360
  private readonly railWidth: number = 40
  private readonly rowHeight: number = 60

  aboutToAppear(): void { this.palette = getColors(this.isDark); this.refreshBlocks() }
  onThemeChange(): void { this.palette = getColors(this.isDark) }
  refreshBlocks(): void { this.blocks = scheduleBlocks(this.courses, this.currentWeek, this.totalWeeks) }
  private dayWidth(): number { return Math.max(1, (this.availableWidth - this.railWidth) / 7) }
  private isToday(day: number): boolean {
    return this.weekKnown && this.currentWeek === this.actualWeek && day === (new Date().getDay() + 6) % 7
  }
  private courseIndex(course: Course): number {
    return stableHash(course.title) % this.palette.courseColors.length
  }
  // 背景由同一个前景色降透明度得到，深浅两套主题共用一份色板，
  // 不再各存一张 16 色硬编码表（原先那批色值绕开了主题 token）。
  // 浅色用 0.10：0.14 时最紧的一项只有 4.54:1，贴着 4.5 门槛；0.10 可回到 4.82:1。
  private courseSurface(course: Course): string {
    return withAlpha(this.palette.courseColors[this.courseIndex(course)], this.isDark ? 0.20 : 0.10)
  }
  private courseText(course: Course): string {
    return this.palette.courseColors[this.courseIndex(course)]
  }
  private dayDate(day: number): string {
    if (!this.weekKnown) return ''
    const date = new Date()
    date.setDate(date.getDate() - (date.getDay() + 6) % 7 + day + (this.currentWeek - this.actualWeek) * 7)
    return (date.getMonth() + 1) + '/' + date.getDate()
  }
  private isCurrent(block: ScheduleBlock): boolean {
    if (!this.isToday(block.day)) return false
    const start = ALL_TIMES[block.first - 1].startMinutes
    const end = ALL_TIMES[block.last - 1].endMinutes
    return classStatus(start, end) === 1
  }
  @Builder
  DayColumn(day: number) {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        ForEach(ALL_TIMES, (_time: ClassTime) => {
          Column().width(this.dayWidth()).height(this.rowHeight)
            .border({ width: { bottom: 0.5, right: 0.5 }, color: this.palette.outline })
        })
      }.width(this.dayWidth())
      ForEach(this.blocks.filter((block: ScheduleBlock): boolean => block.day === day), (block: ScheduleBlock) => {
        Column({ space: 4 }) {
          Text(block.course.title).fontSize(11).fontWeight(FontWeight.Medium)
            .fontColor(this.courseText(block.course)).width('100%')
            .maxLines(block.last > block.first ? 4 : 2).textOverflow({ overflow: TextOverflow.Ellipsis })
          if (block.last > block.first && block.lanes === 1) {
            Text(block.course.location).fontSize(10).fontColor(this.courseText(block.course))
              .width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(block.first + '–' + block.last + '节').fontSize(10).fontColor(this.courseText(block.course))
          }
          if (block.lanes > 1 && block.last > block.first) {
            Text('冲突').fontSize(10).fontColor(this.courseText(block.course))
          }
        }.width(this.dayWidth() / block.lanes - 3).height((block.last - block.first + 1) * this.rowHeight - 4)
          .alignItems(HorizontalAlign.Start).padding({ left: 4, right: 4, top: 7, bottom: 4 })
          .backgroundColor(this.courseSurface(block.course)).borderRadius(8)
          .border({ width: this.isCurrent(block) ? 1.5 : 0, color: this.palette.primary })
          .position({ x: block.lane * this.dayWidth() / block.lanes + 1.5, y: (block.first - 1) * this.rowHeight + 2 })
          .accessibilityGroup(true)
          .accessibilityText(block.course.title + '，' + block.course.location + '，第' + block.first + '至' + block.last + '节' + (block.lanes > 1 ? '，时间冲突' : ''))
          .accessibilityDescription('点击查看完整课程；也可点击星期查看当天清单')
          .onClick(() => this.onCourseTap(block.course))
      }, (block: ScheduleBlock): string => block.key)
    }.width(this.dayWidth()).height(ALL_TIMES.length * this.rowHeight)
  }
  build() {
    Column() {
      Row() {
        Text('节次').width(this.railWidth).fontSize(10).fontColor(this.palette.onSurfaceVariant).textAlign(TextAlign.Center)
        ForEach(['一', '二', '三', '四', '五', '六', '日'], (label: string, day: number) => {
          Column({ space: 4 }) {
            Text('周' + label).fontSize(12).fontWeight(FontWeight.Medium)
              .fontColor(this.isToday(day) ? this.palette.primary : this.palette.onSurface)
            Text(this.dayDate(day)).fontSize(10).fontColor(this.palette.onSurfaceVariant)
          }.width(this.dayWidth()).height(52).justifyContent(FlexAlign.Center)
            .backgroundColor(this.isToday(day) ? this.palette.primaryContainer : Color.Transparent)
            .accessibilityGroup(true).accessibilityText('周' + label + '，' + this.dayDate(day) + '，查看当天完整课程')
            .onClick(() => this.onDayTap(day))
        })
      }.width('100%').backgroundColor(this.palette.surface)
      Row() {
        Column() {
          ForEach(ALL_TIMES, (time: ClassTime, row: number) => {
              // 起止时间都写出来：只给开始时间的话，"几点下课"还要自己加 45 分钟，
              // 在 45 分钟一节的作息下很容易记错。用 formatMinutes 从分钟数直接格式化，
              // 不依赖 label 的字符串分隔符。
              Column({ space: 2 }) {
                Text(String(row + 1)).fontSize(12).fontWeight(FontWeight.Medium).fontColor(this.palette.onSurface)
                Text(formatMinutes(time.startMinutes)).fontSize(9).fontColor(this.palette.onSurfaceVariant)
                Text(formatMinutes(time.endMinutes)).fontSize(8).fontColor(this.palette.onSurfaceVariant).opacity(0.9)
              }.width(this.railWidth).height(this.rowHeight).justifyContent(FlexAlign.Center)
              .border({ width: { bottom: 0.5 }, color: this.palette.outline })
          })
        }.width(this.railWidth)
        ForEach([0, 1, 2, 3, 4, 5, 6], (day: number) => { this.DayColumn(day) })
      }.width('100%').alignItems(VerticalAlign.Top)
    }.width('100%').backgroundColor(this.palette.surface).borderRadius(16).clip(true)
      .onAreaChange((_old: Area, area: Area) => {
        const width = Number(area.width)
        if (width > 0 && Math.abs(width - this.availableWidth) > 0.5) this.availableWidth = width
      })
  }
}
