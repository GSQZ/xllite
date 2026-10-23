import { getColors, ColorPalette } from '../theme/Colors'
import { Typography } from '../theme/Typography'
import { Motion } from '../theme/Motion'

/**
 * 底部导航栏：液态玻璃 / 沉浸光感。
 *
 * 两条渲染路径，运行时二选一，互不替换：
 *
 * | 路径 | 版本 | 手段 |
 * | --- | --- | --- |
 * | 原生沉浸材质 | API 26+ | `systemMaterial(ImmersiveMaterial)` |
 * | 液态玻璃回退 | API 23–25 | `backdropBlur` + 低透明底色 + 漫反射高光 |
 *
 * 26 的适配是原有的，这里只补 23–25 那条。回退不是"灰磨砂"：
 * 磨砂只有模糊，玻璃还要有**底色**、**光线走向**和**通透边缘**，三者缺一就是粉笔灰。
 *
 * 所有玻璃参数都集中在下面这段常量里，调透明度改 TAB_TINT_*，
 * 调模糊强度改 TAB_BLUR，调圆角弧度改 TAB_RADIUS，不必动布局代码。
 */

// ── 玻璃质感参数 ────────────────────────────────────────────────
// 高斯模糊半径。12 以下背景细节太清楚，玻璃会读成"透明塑料"；
// 18 以上细节全部糊死，又退回普通磨砂。12–18 是能同时看出"模糊"和"结构"的区间。
const TAB_BLUR: number = 16

// 深色底色。不是纯黑：纯黑会让玻璃变成一块板，带一点蓝紫才有"玻璃有体温"的感觉。
// alpha 0.28：再低背景抢戏、文字发飘；再高就看不见后面的内容了。
const TAB_TINT_DARK: string = '#47202A3D'
// 浅色底色。比深色更实一点（浅色背景本身亮，太透会失去边界），但仍留给内容透出的余地。
const TAB_TINT_LIGHT: string = '#8CFFFFFF'

// 顶部漫反射高光：光从上方打在玻璃弧面上，越靠上越亮，向下迅速衰减。
// 用渐变而不是描边，是因为描边四边等宽，会读成"贴纸边"。
const TAB_SHEEN_DARK: Array<[ResourceColor, number]> = [
  ['#4D9FC4FF', 0], ['#1F9FC4FF', 0.34], ['#00000000', 0.72], ['#14000000', 1],
]
const TAB_SHEEN_LIGHT: Array<[ResourceColor, number]> = [
  ['#4DFFFFFF', 0], ['#1AFFFFFF', 0.34], ['#00FFFFFF', 0.72], ['#0D000000', 1],
]

// 边缘通透光泽：只在顶沿给一丝边，四圈等宽描边会把栏框死、显得厚重。
const TAB_EDGE_DARK: string = '#33FFFFFF'
const TAB_EDGE_LIGHT: string = '#59FFFFFF'

// 圆角：轻微。全圆半径会读成"悬浮岛"，贴底通栏只要一点弧就够。
const TAB_RADIUS: number = 20
// ────────────────────────────────────────────────────────────────

// 内容高度（不含上下内边距）。栏整体比它高 PAD_Y*2。
const BAR_CONTENT_HEIGHT: number = 48
const PAD_Y: number = 4
const PAD_X: number = 8
const ICON_SIZE: number = 24
// 未选中项的视觉权重：低透明度弱化，但仍然可读。
const IDLE_OPACITY: number = 0.55
// 点击按压：轻微缩小，抬手回弹。不做额外弹窗或位移。
const PRESS_SCALE: number = 0.92

// tab 数据源。当前业务是 3 项，均分逻辑对任意数量都成立：
// 每项都是 layoutWeight(1)，想变成 5 项就往这个数组里补两条，布局自动均分 5 格。
const TABS_LABELS: string[] = ['首页', '课表', '待办', '我的']

@Component
export struct BlurTabBar {
  @Prop currentIndex: number = 0
  onTabChange: (index: number) => void = () => {}
  @StorageLink('isDark') @Watch('onThemeChange') isDark: boolean = false
  @StorageLink('reduceMotion') reduceMotion: boolean = false
  // 底部系统避让区（手势条高度）。由 EntryAbility 从窗口 AvoidArea 取出写入，
  // 等价于 ArkUI 的 SYSTEM_AVOID_BOTTOM：栏整体上移这么多，点击区不会被手势条盖住。
  @StorageLink('safeAreaBottom') safeAreaBottom: number = 0
  @State palette: ColorPalette = getColors(false)
  @State pressingIdx: number = -1

  aboutToAppear(): void { this.onThemeChange() }
  onThemeChange(): void { this.palette = getColors(this.isDark) }

  private icon(index: number): Resource {
    if (index === 0) return $r('app.media.nav_home')
    if (index === 1) return $r('app.media.nav_calendar')
    if (index === 2) return $r('app.media.campus_todo')
    return $r('app.media.nav_profile')
  }
  private label(index: number): string { return TABS_LABELS[index] }
  // 选中：品牌色；未选中：次级文字色，再叠 IDLE_OPACITY 弱化。
  private tint(index: number): ResourceColor {
    return this.currentIndex === index ? this.palette.primary : this.palette.onSurfaceVariant
  }
  private sheen(): Array<[ResourceColor, number]> {
    return this.isDark ? TAB_SHEEN_DARK : TAB_SHEEN_LIGHT
  }

  @Builder
  TabItem(index: number) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 4 }) {
        Image(this.icon(index)).width(ICON_SIZE).height(ICON_SIZE)
          .fillColor(this.tint(index))
        Text(this.label(index)).fontSize(Typography.caption.fontSize)
          .fontWeight(this.currentIndex === index ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(this.tint(index))
          .maxLines(1)
      }
      .width('100%').justifyContent(FlexAlign.Center)
    }
    // 均分：数量变化不需要改这里。
    .layoutWeight(1).height(BAR_CONTENT_HEIGHT)
    .backgroundColor(Color.Transparent)
    .borderRadius(TAB_RADIUS - 6)
    // 选中项满不透明，其余项整体压到 IDLE_OPACITY。
    .opacity(this.currentIndex === index ? 1 : IDLE_OPACITY)
    .scale({ x: this.reduceMotion || this.pressingIdx !== index ? 1 : PRESS_SCALE,
      y: this.reduceMotion || this.pressingIdx !== index ? 1 : PRESS_SCALE })
    .animation({ duration: this.reduceMotion ? 0 : Motion.duration.instant, curve: Motion.curve.standard })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) { this.pressingIdx = index }
      else if (event.type === TouchType.Up || event.type === TouchType.Cancel) { this.pressingIdx = -1 }
    })
    .onClick(() => { if (this.currentIndex !== index) this.onTabChange(index) })
    .accessibilityText(this.label(index))
    .accessibilityDescription(this.currentIndex === index ? '已选中' : '切换到' + this.label(index))
  }

  @Builder
  TabRow() {
    Row() {
      ForEach(TABS_LABELS, (_label: string, index: number) => { this.TabItem(index) })
    }
    .width('100%').height(BAR_CONTENT_HEIGHT)
    .padding({ left: PAD_X, right: PAD_X })
    // 图标与文字整体上移 safeAreaBottom，避开系统手势条；点击区不被遮挡。
    .margin({ bottom: PAD_Y + this.safeAreaBottom })
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // ── 玻璃层 ────────────────────────────────────────────────
      // 高度含 safeAreaBottom：玻璃要一路铺到屏幕底边，不能在手势条上方就断掉，
      // 否则栏底会露出一条背景色，看起来像"飘在屏幕上方"。
      // 圆角只给上面两角——贴屏幕底边的那侧必须是直角，否则边缘会露出方形背景。
        // 始终走 backgroundEffect 这条路：它自 API 11 起可用，所有设备都能渲染出
        // 模糊与底色。曾经按版本分流到 systemMaterial，但在渲染不出材质的设备上
        // （模拟器就是）整个玻璃层会变成全透明，课表内容直接压在导航图标上——
        // 导航栏不能有这种「看起来没渲染」的状态，所以这里不再按版本分叉。
        // 真正的沉浸材质仍保留在卡片（NativeGlass）上。
        Column()
          .width('100%').height(BAR_CONTENT_HEIGHT + PAD_Y * 2 + this.safeAreaBottom)
          .borderRadius({ topLeft: TAB_RADIUS, topRight: TAB_RADIUS })
          .clip(true)
          // ① 高斯模糊：透过来的内容被柔化，这是玻璃而非透明的基础。
          .backdropBlur(TAB_BLUR)
          // ② 低透明底色：深色带蓝紫、浅色偏白。决定玻璃有多大分量。
          .backgroundColor(this.isDark ? TAB_TINT_DARK : TAB_TINT_LIGHT)
          // ③ 漫反射高光：上亮下暗，模拟光打在弧面玻璃上的走向。
          .linearGradient({ angle: 180, colors: this.sheen() })
          // ④ 通透边缘：只给顶沿一丝亮边，不做四边描边。
          .border({ width: { top: 1 }, color: this.isDark ? TAB_EDGE_DARK : TAB_EDGE_LIGHT })
      // ── 内容层 ────────────────────────────────────────────────
      this.TabRow()
    }
    .width('100%')
    // 只在顶部留内边距；底部不再留白，玻璃直接坐到屏幕底边。
    .padding({ top: PAD_Y })
  }
}
