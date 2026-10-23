import { getColors } from '../theme/Colors'
import { Typography } from '../theme/Typography'
import { safeBack } from '../utils/RouterHelper'
import { callFeature } from '../services/ApiService'
import { getUsername } from '../services/AuthManager'
import { getCacheEpoch } from '../services/MemoryCache'
import { DetailScaffold } from '../components/common/DetailScaffold'
import { PageState } from '../components/common/PageState'
import { RefreshNotice } from '../components/common/RefreshNotice'
import { CampusCard } from '../components/common/CampusCard'
import { GradeItem, GradeSummary } from '../models/JwTypes'
import { ListDataSource } from '../utils/ListDataSource'
import { Motion, motionDuration } from '../theme/Motion'

@Component
export struct GradesTab {
  @StorageLink('isDark') isDark: boolean = false
  @State grades: GradeItem[] = []
  @State gpa: string = '—'
  @State credits: string = '—'
  @State failedCount: string = '—'
  private readonly rows: ListDataSource<GradeItem> = new ListDataSource<GradeItem>()

  @State loading: boolean = false
  @State loaded: boolean = false
  @State errorMsg: string = ''
  private alive: boolean = false
  private requestVersion: number = 0
  aboutToAppear(): void { this.alive = true; this.load() }
  aboutToDisappear(): void { this.alive = false; this.requestVersion++; this.loading = false }
  async load(force: boolean = false): Promise<void> {
    if (this.loading || !this.alive) return
    this.loading = true
    this.errorMsg = ''
    const version = ++this.requestVersion
    const epoch = getCacheEpoch()
    const username = getUsername()
    try {
      const res = await callFeature('jw.grades', username, { '_forceRefresh': force })
      if (!this.alive || version !== this.requestVersion || epoch !== getCacheEpoch() || username !== getUsername()) return
      if (res.ok) {
        const data = res.data['normalGrades'] as GradeItem[]
        this.grades = Array.isArray(data) ? data : []
        this.rows.replace(this.grades)
        const summary = res.data['summary'] as GradeSummary
        this.gpa = summary && Number.isFinite(summary.weightedGradePoint) ? summary.weightedGradePoint.toFixed(2) : '—'
        this.credits = summary && Number.isFinite(summary.totalCredits) ? summary.totalCredits.toFixed(1) : '—'
        this.failedCount = summary && Number.isFinite(summary.failedCourseCount) ? summary.failedCourseCount.toString() : '—'
        this.loaded = true
      } else { this.errorMsg = res.error || '暂时无法更新，请稍后重试' }
    } catch (_error) {
      if (this.alive && version === this.requestVersion && epoch === getCacheEpoch() && username === getUsername()) this.errorMsg = '连接未完成，请稍后重试'
    } finally {
      if (this.alive && version === this.requestVersion) this.loading = false
    }
  }
  @Builder
  Metric(label: string, value: string, color: string) {
    Column({ space: 8 }) {
      Text(label).fontSize(Typography.caption.fontSize).fontColor(getColors(this.isDark).onSurfaceVariant)
      Text(value).fontSize(Typography.headline.fontSize).fontWeight(FontWeight.Bold).fontColor(color)
    }.layoutWeight(1)
  }

  build() {
    Stack() {
    DetailScaffold({ title: '成绩查询', subtitle: '每一份努力，都留下记录', busy: this.loading,
      onBack: () => safeBack(this.getUIContext()), onAction: () => this.load(true) }) {
      if (!this.loaded && this.loading) {
        PageState({ kind: 'loading', title: '正在获取成绩记录', message: '马上就好，请稍候' })
      } else if (!this.loaded && this.errorMsg.length > 0) {
        PageState({ kind: 'error', schoolFeature: 'jw.grades', title: '成绩记录暂未更新', message: this.errorMsg,
          action: '重新加载', onAction: () => this.load(true) })
      } else {
        if (this.errorMsg.length > 0) {
          RefreshNotice({ message: '更新失败，已保留上次数据', busy: this.loading, onRetry: () => this.load(true) })
        }
        if (this.grades.length === 0) {
          PageState({ title: '暂无成绩记录', message: '成绩公布后可在这里查看', action: '刷新看看', onAction: () => this.load(true) })
        } else {
          Column() {
            CampusCard({ contentPadding: 20 }) {
              Row({ space: 12 }) {
                this.Metric('平均绩点', this.gpa, getColors(this.isDark).primary)
                this.Metric('累计学分', this.credits, getColors(this.isDark).onSurface)
                this.Metric('未通过', this.failedCount, this.failedCount === '0' ? getColors(this.isDark).success :
                  this.failedCount === '—' ? getColors(this.isDark).onSurfaceVariant : getColors(this.isDark).error)
              }.width('100%')
            }
          }.width('100%').padding({ left: 20, right: 20, bottom: 16 })
          List({ space: 10 }) {
            LazyForEach(this.rows, (g: GradeItem) => {
              ListItem() {
                CampusCard({ contentPadding: 18 }) {
                  Column({ space: 12 }) {
                    Text(g.courseName).fontSize(Typography.bodyLg.fontSize).fontWeight(FontWeight.Medium)
                      .fontColor(getColors(this.isDark).onSurface).width('100%')
                    Row({ space: 12 }) {
                      Column({ space: 5 }) {
                        Text(g.term).fontSize(Typography.caption.fontSize).fontColor(getColors(this.isDark).onSurfaceVariant)
                        Text(g.credit + ' 学分 · 绩点 ' + g.gradePoint).fontSize(Typography.bodySm.fontSize)
                          .fontColor(getColors(this.isDark).onSurfaceVariant)
                      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                      Text(g.score).fontSize(Typography.headline.fontSize).fontWeight(FontWeight.Bold)
                        .fontColor(getColors(this.isDark).onSurface)
                    }.width('100%')
                  }.width('100%')
                }
              }
            }, (g: GradeItem, index: number): string => g.term + '|' + g.courseCode + '|' + g.courseName + '|' + index)
          }.layoutWeight(1).width('100%').padding({ left: 20, right: 20, bottom: 24 }).scrollBar(BarState.Off)
        }
      }
    }
    }.width('100%').height('100%')
  }

  // 统一页面过渡：前进时新页右侧 30% 淡入、底层静止；返回时镜像右出淡出。
  // 减少动效偏好下时长为 0（同时禁用设备默认页面动画，保持瞬时切换）。
  pageTransition(): void {
    PageTransitionEnter({ type: RouteType.Push, duration: motionDuration(Motion.duration.base), curve: Motion.curve.decelerate })
      .translate({ x: motionDuration(Motion.duration.base) > 0 ? '30%' : '0%' }).opacity(motionDuration(Motion.duration.base) > 0 ? 0 : 1)
    PageTransitionExit({ type: RouteType.Push, duration: motionDuration(Motion.duration.base) })
    PageTransitionEnter({ type: RouteType.Pop, duration: motionDuration(Motion.duration.base) })
    PageTransitionExit({ type: RouteType.Pop, duration: motionDuration(Motion.duration.base), curve: Motion.curve.accelerate })
      .translate({ x: motionDuration(Motion.duration.base) > 0 ? '30%' : '0%' }).opacity(motionDuration(Motion.duration.base) > 0 ? 0 : 1)
  }

}
