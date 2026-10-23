import { safeReplace, safePush } from '../utils/RouterHelper'
import { safeToast } from '../utils/ToastHelper'
import { getColors, ColorPalette } from '../theme/Colors'
import { CampusCard } from '../components/common/CampusCard'
import { CampusIcon } from '../components/common/CampusIcon'
import { CampusHeader } from '../components/common/CampusHeader'
import { getUsername } from '../services/AuthManager'
import { logoutGatewayAccount } from '../services/XlliteGateway'
import { callFeature, CallResult } from '../services/ApiService'
import { getCacheEpoch } from '../services/MemoryCache'
import { setThemeMode, setReduceMotion } from '../services/ThemeService'
import { ProfileData } from '../models/JwTypes'

/**
 * ProfileTab - 我的 tab 内容
 *
 * 三个功能区:
 *   1. 个人信息卡片(头像 + 姓名 + 学号 + 入口 → ProfilePage)
 *   2. 设置:深色模式开关
 *   3. 退出登录
 */
@Component
export struct ProfileTab {
  @Prop @Watch('onActivityChange') active: boolean = true
  @StorageLink('mainPageActive') @Watch('onActivityChange') mainPageActive: boolean = true
  @StorageLink('safeAreaBottom') safeAreaBottom: number = 0
  @StorageLink('themeMode') themeMode: string = 'system'
  @State loggingOut: boolean = false
  private alive: boolean = false
  private requestBusy: boolean = false
  @State username: string = ''
  @State name: string = ''
  @State studentId: string = ''
  @State college: string = ''
  @State major: string = ''
  @State loading: boolean = true
  @State errorMsg: string = ''

  @StorageLink('reduceMotion') reduceMotion: boolean = false
  @StorageLink('isDark') @Watch('onThemeChange') isDark: boolean = false
  @State palette: ColorPalette = getColors(false)

  aboutToAppear(): void {
    this.alive = true
    this.palette = getColors(this.isDark)
    this.username = getUsername()
    this.loadProfile()
  }

  aboutToDisappear(): void { this.alive = false }
  onActivityChange(): void {
    if (this.alive && this.active && this.mainPageActive && !this.loggingOut) this.loadProfile()
  }
  onThemeChange(): void {
    this.palette = getColors(this.isDark)
  }

  async loadProfile(): Promise<void> {
    if (this.requestBusy || !this.alive || this.loggingOut) return
    this.requestBusy = true
    const epoch = getCacheEpoch()
    const username = getUsername()
    this.loading = true
    this.errorMsg = ''
    const empty: Record<string, Object> = {}
    let res: CallResult
    try {
      res = await callFeature('jw.profile', username, empty)
    } catch (_error) {
      if (this.alive && epoch === getCacheEpoch() && username === getUsername()) {
        this.loading = false
        this.errorMsg = '连接未完成，请稍后重试'
      }
      return
    } finally {
      this.requestBusy = false
    }
    if (!this.alive || epoch !== getCacheEpoch() || username !== getUsername()) return
    this.loading = false
    if (res.ok) {
      const p: ProfileData = res.data as Object as ProfileData
      this.name = p.name ?? ''
      this.studentId = p.studentId ?? ''
      this.college = p.college ?? ''
      this.major = p.major ?? ''
    } else {
      this.errorMsg = res.error
      if (this.username.length > 0) {
        this.name = this.username
      }
    }
  }

  async handleLogout(): Promise<void> {
    if (this.loggingOut) return
    this.loggingOut = true
    try {
      await logoutGatewayAccount()
      if (this.alive) {
        safeToast(this.getUIContext(), '已退出登录')
        this.getUIContext().getRouter().clear()
        safeReplace(this.getUIContext(), { url: 'pages/LoginPage' })
      }
    } catch (_error) {
      if (this.alive) safeToast(this.getUIContext(), '本地清理未完成，请再次退出重试')
    } finally {
      this.loggingOut = false
    }
  }

  @Builder
  ThemeOption(label: string, mode: string) {
    Button(label).layoutWeight(1).height(44).fontSize(12)
      .fontColor(this.themeMode === mode ? this.palette.onPrimary : this.palette.onSurfaceVariant)
      .backgroundColor(this.themeMode === mode ? this.palette.primary : this.palette.surfaceVariant)
      .borderRadius(12)
      .onClick(() => {
        setThemeMode(mode).then((saved: boolean) => {
          if (!saved) safeToast(this.getUIContext(), '主题已切换，但未能保存，重启后会恢复原设置')
        }).catch((_e: Error) => {})
      })
  }

  avatarText(): string {
    if (this.name.length === 0) return '?'
    return this.name[0]
  }

  @Builder
  MenuRow(title: string, subtitle: string, icon: ResourceStr, page: string) {
    Row({ space: 12 }) {
      CampusIcon({ source: icon, iconSize: 40, badgeColor: this.palette.primaryContainer })
      Column({ space: 4 }) {
        Text(title).fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.palette.onSurface)
        Text(subtitle).fontSize(12).fontColor(this.palette.onSurfaceVariant)
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Text('›').fontSize(20).fontColor(this.palette.onSurfaceVariant)
    }
      .width('100%').padding({ top: 12, bottom: 12 })
      .onClick(() => safePush(this.getUIContext(), { url: 'pages/' + page }))
      .accessibilityText(title)
  }

  build() {
    Column() {
      CampusHeader({ title: '我的', subtitle: '校园身份与账户' })
      Scroll() {
        Column({ space: 24 }) {
          CampusCard({ contentPadding: 20, radius: 24 }) {
            Row({ space: 16 }) {
              Text(this.avatarText()).fontSize(26).fontWeight(FontWeight.Bold)
                .fontColor(this.palette.primary).textAlign(TextAlign.Center)
                .width(64).height(64).backgroundColor(this.palette.primaryContainer).borderRadius(22)
              Column({ space: 7 }) {
                Text(this.name.length > 0 ? this.name : this.username)
                  .fontSize(21).fontWeight(FontWeight.Bold).fontColor(this.palette.onSurface)
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                Text('学号 ' + (this.studentId.length > 0 ? this.studentId : this.username))
                  .fontSize(12).fontColor(this.palette.onSurfaceVariant)
                if (this.college.length > 0 || this.major.length > 0) {
                  Text(this.college + (this.major.length > 0 ? ' · ' + this.major : ''))
                    .fontSize(12).fontColor(this.palette.onSurfaceVariant)
                    .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                }
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              if (this.loading) { LoadingProgress().width(20).height(20).color(this.palette.primary) }
            }.width('100%')
            if (!this.loading && this.errorMsg.length > 0) {
              Row() {
                Text('个人资料暂未更新').fontSize(12).fontColor(this.palette.onSurfaceVariant).layoutWeight(1)
                Button('重试').height(36).fontSize(12).fontColor(this.palette.primary)
                  .backgroundColor(Color.Transparent).onClick(() => this.loadProfile())
              }.width('100%').margin({ top: 10 })
            }
          }
          Column() {
            Text('我的教务').fontSize(17).fontWeight(FontWeight.Bold).fontColor(this.palette.onSurface)
              .width('100%').margin({ bottom: 12 })
            CampusCard({ contentPadding: 16 }) {
              this.MenuRow('个人资料', '学籍、院系与班级信息', $r('app.media.campus_profile'), 'ProfilePage')
              Divider().color(this.palette.outline)
              this.MenuRow('成绩查询', '课程成绩与学分', $r('app.media.campus_grades'), 'GradesPage')
              Divider().color(this.palette.outline)
              this.MenuRow('考试安排', '考试时间与考场', $r('app.media.campus_exams'), 'ExamsPage')
            }
          }.width('100%')
          Column() {
            CampusCard({ contentPadding: 16 }) {
              this.MenuRow('桌面与提醒', '桌面课表 · 课前提醒 · 实况窗', $r('app.media.campus_schedule'), 'CampusSettingsPage')
            }
            Blank().height(20)
            Text('偏好设置').fontSize(17).fontWeight(FontWeight.Bold).fontColor(this.palette.onSurface)
              .width('100%').margin({ bottom: 12 })
            CampusCard({ contentPadding: 16 }) {
              Row({ space: 12 }) {
                CampusIcon({ source: $r('app.media.campus_theme'), iconSize: 40, badgeColor: this.palette.primaryContainer })
                Column({ space: 5 }) {
                  Text('显示外观').fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.palette.onSurface)
                  Text('默认跟随系统，也可以单独选择').fontSize(12).fontColor(this.palette.onSurfaceVariant)
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              }.width('100%')
              Row({ space: 6 }) {
                this.ThemeOption('跟随系统', 'system')
                this.ThemeOption('浅色', 'light')
                this.ThemeOption('深色', 'dark')
              }.width('100%').margin({ top: 14 })
              Divider().color(this.palette.outline).margin({ top: 18, bottom: 14 })
              Row({ space: 12 }) {
                Column({ space: 5 }) {
                  Text('减少动效').fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.palette.onSurface)
                  Text('减少界面动画，操作更直接').fontSize(12).fontColor(this.palette.onSurfaceVariant)
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.reduceMotion }).selectedColor(this.palette.primary)
                  .accessibilityText('减少动效').onChange((enabled: boolean) => {
                    setReduceMotion(enabled).then((saved: boolean) => {
                      if (!saved) safeToast(this.getUIContext(), '已切换，但未能保存，重启后会恢复原设置')
                    }).catch((_e: Error) => {})
                  })
              }.width('100%')
            }
          }.width('100%')
          Button(this.loggingOut ? '退出中…' : '退出登录').enabled(!this.loggingOut).width('100%').height(48).fontSize(15)
            .fontColor(this.palette.error).backgroundColor(this.palette.surface).borderRadius(16)
            .border({ width: 0.5, color: this.palette.outline }).onClick(() => this.handleLogout())
          Text('掌上新理工 · 1.0.0').fontSize(12).fontColor(this.palette.onSurfaceVariant)
        }
          .width('100%')
          .padding({ left: 20, right: 20, top: 4, bottom: this.safeAreaBottom + 104 })
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
    }.width('100%').height('100%').backgroundColor(Color.Transparent)
  }
}
