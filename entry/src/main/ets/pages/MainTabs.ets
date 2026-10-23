import { activateCampusCompanion } from '../services/CampusCompanionService'
import { safePush } from '../utils/RouterHelper'
import { HomeTab } from './HomeTab'
import { ScheduleTab } from './ScheduleTab'
import { ProfileTab } from './ProfileTab'
import { TodoTab } from './TodoTab'
import { BlurTabBar } from '../components/BlurTabBar'
import { AmbientBackground } from '../components/AmbientBackground'
import { getUsername } from '../services/AuthManager'
import { prewarmCampusData } from '../services/ApiService'
import { Motion, motionDuration } from '../theme/Motion'
import { ThemeWash } from '../components/common/ThemeWash'

@Entry
@Component
struct MainTabs {
  @StorageLink('campusRoute') @Watch('applyRequestedRoute') campusRoute: string = ''
  @State currentIndex: number = 0
  @State leavingTab: number = -1
  @State scheduleVisited: boolean = false
  @State todoVisited: boolean = false
  @State profileVisited: boolean = false
  private leaveTimer: number = -1
  @StorageLink('isDark') isDark: boolean = false
  @StorageLink('safeAreaBottom') safeAreaBottom: number = 0
  @StorageLink('mainPageActive') mainPageActive: boolean = true
  @StorageLink('appActive') @Watch('onActivityChange') appActive: boolean = true
  private warmupStarted: boolean = false
  private alive: boolean = false
  private warmupTimer: number = -1
  aboutToAppear(): void {
    this.alive = true
    activateCampusCompanion(getUsername()).catch((_e: Error) => {})
    this.applyRequestedRoute()
    this.onActivityChange()
  }
  onPageShow(): void { this.mainPageActive = true; this.applyRequestedRoute(); this.onActivityChange() }
  onPageHide(): void { this.mainPageActive = false; this.cancelWarmupTimer() }
  aboutToDisappear(): void {
    this.alive = false
    this.mainPageActive = false
    this.cancelWarmupTimer()
    this.clearLeaveTimer()
  }
  private clearLeaveTimer(): void {
    if (this.leaveTimer >= 0) clearTimeout(this.leaveTimer)
    this.leaveTimer = -1
  }
  private cancelWarmupTimer(): void {
    if (this.warmupTimer >= 0) clearTimeout(this.warmupTimer)
    this.warmupTimer = -1
  }
  onActivityChange(): void {
    this.cancelWarmupTimer()
    if (!this.alive || !this.mainPageActive || !this.appActive || this.warmupStarted) return
    this.warmupTimer = setTimeout(() => {
      this.warmupTimer = -1
      if (!this.alive || !this.mainPageActive || !this.appActive) return
      this.warmupStarted = true
      prewarmCampusData(getUsername()).catch((_e: Error) => {})
    }, 400)
  }
  applyRequestedRoute(): void {
    if (!this.alive || !this.mainPageActive) return
    const route = this.campusRoute
    if (route === 'schedule') { this.campusRoute = ''; this.selectTab(1) }
    else if (route === 'todo') { this.campusRoute = ''; this.selectTab(2) }
  }
  private selectTab(index: number): void {
    if (!Number.isInteger(index) || index < 0 || index > 3 || index === this.currentIndex) return
    const previous: number = this.currentIndex
    if (index === 1) this.scheduleVisited = true
    if (index === 2) this.todoVisited = true
    if (index === 3) this.profileVisited = true
    // Keep the outgoing instance briefly; opacity switches instantly to avoid text ghosting.
    this.clearLeaveTimer()
    const duration: number = motionDuration(Motion.duration.fast)
    this.leavingTab = duration > 0 ? previous : -1
    this.currentIndex = index
    if (duration === 0) return
    this.leaveTimer = setTimeout(() => {
      this.leaveTimer = -1
      if (this.leavingTab === previous && this.currentIndex !== previous) this.leavingTab = -1
    }, motionDuration(Motion.duration.fast))
  }
  private tabVisible(index: number): boolean {
    return this.currentIndex === index || this.leavingTab === index
  }
  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      AmbientBackground()
      HomeTab({ active: this.currentIndex === 0 })
        .visibility(this.tabVisible(0) ? Visibility.Visible : Visibility.Hidden)
        .opacity(this.currentIndex === 0 ? 1 : 0)
          .hitTestBehavior(this.currentIndex === 0 ? HitTestMode.Default : HitTestMode.None)

      if (this.scheduleVisited) {
        ScheduleTab({ active: this.currentIndex === 1 })
          .visibility(this.tabVisible(1) ? Visibility.Visible : Visibility.Hidden)
          .opacity(this.currentIndex === 1 ? 1 : 0)
          .hitTestBehavior(this.currentIndex === 1 ? HitTestMode.Default : HitTestMode.None)

      }
      // 待办提为一级入口；成绩与财务留在首页「常用服务」里。
      if (this.todoVisited) {
        TodoTab()
          .visibility(this.tabVisible(2) ? Visibility.Visible : Visibility.Hidden)
          .opacity(this.currentIndex === 2 ? 1 : 0)
          .hitTestBehavior(this.currentIndex === 2 ? HitTestMode.Default : HitTestMode.None)

      }
      if (this.profileVisited) {
        ProfileTab({ active: this.currentIndex === 3 })
          .visibility(this.tabVisible(3) ? Visibility.Visible : Visibility.Hidden)
          .opacity(this.currentIndex === 3 ? 1 : 0)
          .hitTestBehavior(this.currentIndex === 3 ? HitTestMode.Default : HitTestMode.None)

      }
      // 底部渐隐衬底。它必须留出可透光的余地：这层如果做实，导航栏的 backdropBlur
      // 背后就没有任何内容可模糊，玻璃会退化成一块纯色板。
      // 所以只压到 60% 左右，够保护文字，又不把背景挡死。
      Column()
        .width('100%').height(this.safeAreaBottom + 88)
        .linearGradient({ angle: 180,
          colors: this.isDark
            ? [['#00152039', 0], ['#66152039', 0.3], ['#99152039', 1]]
            : [['#00EAF0FB', 0], ['#66EAF0FB', 0.3], ['#99EAF0FB', 1]],
        })
        .hitTestBehavior(HitTestMode.None)
      Column() {
        BlurTabBar({ currentIndex: this.currentIndex,
          onTabChange: (index: number) => { this.selectTab(index) } })
      }
      // 左右贴边：栏本身占满宽度，圆角与底部避让都由组件内部处理。
      .width('100%')
      ThemeWash()
    }
    .width('100%').height('100%')
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
