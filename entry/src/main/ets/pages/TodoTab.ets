import { getUsername } from '../services/AuthManager'
import { getCacheEpoch } from '../services/MemoryCache'
import notificationManager from '@ohos.notificationManager'
import common from '@ohos.app.ability.common'
import { DetailScaffold } from '../components/common/DetailScaffold'
import { safeBack } from '../utils/RouterHelper'
import { safeToast } from '../utils/ToastHelper'
import { TodoItem } from '../models/TodoTypes'
import { addTodo, countOpenTodos, deleteTodo, loadTodos, toggleTodo, refreshTodoWidgets, registerTodoReminders, disableTodoReminders, getTodoReminderStatus, restoreTodoReminderStatus, getTodoLiveCleanupStatus, retryTodoLiveCleanup } from '../services/TodoService'
import { startTodoLiveView } from '../services/LiveViewService'
import { LiquidGlass } from '../components/LiquidGlass'
import { getColors, withAlpha, ColorPalette } from '../theme/Colors'
import { Radius } from '../theme/Radius'
import { Motion, motionDuration } from '../theme/Motion'

@Component
export struct TodoTab {
  @StorageLink('safeAreaTop') safeAreaTop: number = 0
  @StorageLink('safeAreaBottom') safeAreaBottom: number = 0
  @State todos: TodoItem[] = []
  @State titleInput: string = ''
  @State noteInput: string = ''
  @State dueInput: string = ''
  @State dueAt: number | undefined = undefined
  @State filter: number = 0
  @State reminderStatus: string = '尚未登记任务提醒'
  @State liveCleanupStatus: string = ''
  @State liveCleanupBusy: boolean = false
  async handleRetryLiveCleanup(): Promise<void> {
    if (!this.hasAccount()) return
    if (this.liveCleanupBusy) return
    this.liveCleanupBusy = true
    const version = this.loadVersion
    const epoch = getCacheEpoch()
    const username = getUsername()
    try { await retryTodoLiveCleanup() }
    catch (_error) {
      if (this.isCurrentOperation(version, epoch, username)) safeToast(this.getUIContext(), '实况窗清理未完成，请重试')
    } finally {
      if (this.isCurrentOperation(version, epoch, username)) {
        this.liveCleanupBusy = false
        this.liveCleanupStatus = getTodoLiveCleanupStatus()
      }
    }
  }
  @StorageLink('isDark') @Watch('onThemeChange') isDark: boolean = false
  @State palette: ColorPalette = getColors(false)

  @State loadError: string = ''
  @State reloadBusy: boolean = false
  private hasAccount(): boolean {
    const username = getUsername()
    const stale = this.pageEpoch !== -1 && (this.pageAccount !== username || this.pageEpoch !== getCacheEpoch())
    if (username.length > 0 && !stale) return true
    this.todos = []
    this.titleInput = ''
    this.noteInput = ''
    this.clearDueTime()
    this.reminderStatus = '登录后查看提醒状态'
    this.liveCleanupStatus = ''
    this.loadError = username.length === 0 ? '请先登录后查看待办' : '账号会话已变化，请重新进入待办页'
    return false
  }
  async handleReloadTodos(): Promise<void> {
    if (!this.hasAccount()) return
    if (this.reloadBusy) return
    this.reloadBusy = true
    const version = this.loadVersion
    const epoch = getCacheEpoch()
    const username = getUsername()
    try {
      const items = await loadTodos()
      if (!this.isCurrentOperation(version, epoch, username)) return
      this.todos = items
      this.loadError = ''
      await restoreTodoReminderStatus()
      if (!this.isCurrentOperation(version, epoch, username)) return
      this.reminderStatus = getTodoReminderStatus()
      this.liveCleanupStatus = getTodoLiveCleanupStatus()
      try { await refreshTodoWidgets() }
      catch (_error) {
        if (this.isCurrentOperation(version, epoch, username)) safeToast(this.getUIContext(), '任务已读取，桌面卡片暂未刷新')
      }
    } catch (_error) {
      if (this.isCurrentOperation(version, epoch, username)) this.loadError = '任务读取未完成，原数据保留，请重试'
    } finally {
      if (this.isCurrentOperation(version, epoch, username)) this.reloadBusy = false
    }
  }
  private pageAccount: string = ''
  private pageEpoch: number = -1
  private alive: boolean = false
  private loadVersion: number = 0
  aboutToDisappear(): void { this.alive = false; this.loadVersion++ }
  async aboutToAppear(): Promise<void> {
    this.alive = true
    this.saving = false
    this.reminderBusy = false
    this.liveCleanupBusy = false
    this.reloadBusy = false
    const version = ++this.loadVersion
    const epoch = getCacheEpoch()
    const username = getUsername()
    this.palette = getColors(this.isDark)
    if (this.pageEpoch !== -1 && (this.pageAccount !== username || this.pageEpoch !== epoch)) {
      this.todos = []
      this.titleInput = ''
      this.noteInput = ''
      this.clearDueTime()
      this.reminderStatus = '正在核对提醒状态'
      this.liveCleanupStatus = ''
    }
    this.pageAccount = username
    this.pageEpoch = epoch
    if (!this.hasAccount()) return
    let items: TodoItem[] = []
    try { items = await loadTodos() }
    catch (_error) {
      if (this.isCurrentOperation(version, epoch, username)) {
        this.loadError = '任务读取未完成，原数据保留，请重试'
        safeToast(this.getUIContext(), this.loadError)
      }
      return
    }
    if (!this.isCurrentOperation(version, epoch, username)) return
    this.todos = items
    this.loadError = ''
    await restoreTodoReminderStatus()
    if (!this.isCurrentOperation(version, epoch, username)) return
    this.reminderStatus = getTodoReminderStatus(); this.liveCleanupStatus = getTodoLiveCleanupStatus()
    try { await refreshTodoWidgets() }
    catch (_error) {
      if (this.isCurrentOperation(version, epoch, username)) {
        safeToast(this.getUIContext(), '任务已读取，桌面卡片暂未刷新')
      }
    }
  }

  onThemeChange(): void {
    this.palette = getColors(this.isDark)
  }

  private emptyTitle(): string {
    if (this.loadError.length > 0) return '任务读取未完成'
    if (this.filter === 1) return '暂无未完成任务'
    if (this.filter === 2) return '暂无已完成任务'
    return '暂无待办'
  }
  private visibleTodos(): TodoItem[] {
    if (this.filter === 1) {
      return this.todos.filter((item: TodoItem): boolean => !item.done)
    }
    if (this.filter === 2) {
      return this.todos.filter((item: TodoItem): boolean => item.done)
    }
    return this.todos
  }

  selectDueTime(date: Date, hour: number, minute: number): void {
    if (!Number.isFinite(date.getTime()) || !Number.isInteger(hour) || !Number.isInteger(minute) || hour < 0 || hour > 23 || minute < 0 || minute > 59) return
    const value = new Date(date.getFullYear(), date.getMonth(), date.getDate(), hour, minute).getTime()
    if (value <= Date.now()) { safeToast(this.getUIContext(), '请选择未来时间'); return }
    this.dueAt = value
    const month = (date.getMonth() + 1).toString().padStart(2, '0')
    const day = date.getDate().toString().padStart(2, '0')
    this.dueInput = date.getFullYear() + '-' + month + '-' + day + ' ' + hour.toString().padStart(2, '0') + ':' + minute.toString().padStart(2, '0')
  }
  clearDueTime(): void { this.dueAt = undefined; this.dueInput = '' }
  chooseDueTime(): void {
    if (!this.hasAccount()) return
    const version = this.loadVersion
    const epoch = getCacheEpoch()
    const username = getUsername()
    const selected = this.dueAt === undefined ? new Date() : new Date(this.dueAt)
    this.getUIContext().showDatePickerDialog({ selected: selected,
      onAccept: (result: DatePickerResult) => {
        if (!this.isCurrentOperation(version, epoch, username)) return
        if (result.year === undefined || result.month === undefined || result.day === undefined) return
        const date = new Date(result.year, result.month, result.day)
        this.getUIContext().showTimePickerDialog({ selected: selected, useMilitaryTime: true,
          onAccept: (time: TimePickerResult) => {
            if (!this.isCurrentOperation(version, epoch, username)) return
            if (time.hour !== undefined && time.minute !== undefined) this.selectDueTime(date, time.hour, time.minute)
          } })
      } })
  }
  @State saving: boolean = false
  private async handleAdd(): Promise<void> {
    if (!this.hasAccount()) return
    if (this.saving) return
    if (this.dueAt !== undefined && this.dueAt <= Date.now()) {
      safeToast(this.getUIContext(), '任务时间已过，请重新选择'); return
    }
    if (this.titleInput.trim().length === 0) {
      safeToast(this.getUIContext(), '先写下要做什么')
      return
    }
    this.saving = true
    const version = this.loadVersion
    const epoch = getCacheEpoch()
    const username = getUsername()
    try {
      const items = await addTodo({
        title: this.titleInput,
        note: this.noteInput,
        dueText: this.dueInput,
        dueAt: this.dueAt,
      })
      if (!this.isCurrentOperation(version, epoch, username)) return
      this.todos = items
      this.titleInput = ''
      this.noteInput = ''
      this.clearDueTime()
    } catch (_error) {
      if (this.isCurrentOperation(version, epoch, username)) {
        safeToast(this.getUIContext(), '任务保存未完成，请重试')
      }
    } finally {
      if (this.isCurrentOperation(version, epoch, username)) {
        this.saving = false; this.reminderStatus = getTodoReminderStatus(); this.liveCleanupStatus = getTodoLiveCleanupStatus()
      }
    }
  }

  private isCurrentOperation(version: number, epoch: number, username: string): boolean {
    return this.alive && version === this.loadVersion && epoch === getCacheEpoch() && username === getUsername()
  }
  private async handleToggle(item: TodoItem): Promise<void> {
    await this.updateTask(item, false)
  }

  private async handleDelete(item: TodoItem): Promise<void> {
    await this.updateTask(item, true)
  }
  private async updateTask(item: TodoItem, deleting: boolean): Promise<void> {
    if (!this.hasAccount()) return
    const version = this.loadVersion
    const epoch = getCacheEpoch()
    const username = getUsername()
    try {
      const items = deleting ? await deleteTodo(item.id) : await toggleTodo(item.id)
      if (this.isCurrentOperation(version, epoch, username)) this.todos = items
    } catch (_error) {
      if (this.isCurrentOperation(version, epoch, username)) {
        safeToast(this.getUIContext(), deleting ? '任务删除未完成，请重试' : '任务状态未保存，请重试')
      }
    } finally {
      if (this.isCurrentOperation(version, epoch, username)) {
        this.reminderStatus = getTodoReminderStatus(); this.liveCleanupStatus = getTodoLiveCleanupStatus()
      }
    }
  }

  @State reminderBusy: boolean = false
  async handleDisableReminders(): Promise<void> {
    if (!this.hasAccount()) return
    if (this.reminderBusy) return
    this.reminderBusy = true
    const version = this.loadVersion
    const epoch = getCacheEpoch()
    const username = getUsername()
    try {
      await disableTodoReminders()
      if (this.isCurrentOperation(version, epoch, username)) safeToast(this.getUIContext(), '已取消任务提醒，任务仍保留')
    } catch (_error) {
      if (this.isCurrentOperation(version, epoch, username)) safeToast(this.getUIContext(), '自动同步已关闭，系统提醒取消未完成，请重试')
    } finally {
      if (this.isCurrentOperation(version, epoch, username)) { this.reminderBusy = false; this.reminderStatus = getTodoReminderStatus(); this.liveCleanupStatus = getTodoLiveCleanupStatus() }
    }
  }
  async handleReminders(): Promise<void> {
    if (!this.hasAccount()) return
    if (this.reminderBusy) return
    this.reminderBusy = true
    const version = this.loadVersion
    const epoch = getCacheEpoch()
    const username = getUsername()
    try {
      const enabled = await notificationManager.isNotificationEnabled()
      if (!this.isCurrentOperation(version, epoch, username)) return
      if (!enabled) {
        await notificationManager.requestEnableNotification(this.getUIContext().getHostContext() as common.UIAbilityContext)
        if (!this.isCurrentOperation(version, epoch, username)) return
      }
      const count = await registerTodoReminders()
      if (this.isCurrentOperation(version, epoch, username)) safeToast(this.getUIContext(), '已登记 ' + count + ' 条任务提醒；本次会话内随任务变更同步')
    } catch (_error) {
      if (this.isCurrentOperation(version, epoch, username)) safeToast(this.getUIContext(), '任务保留，提醒登记未完成，请检查通知设置后重试')
    } finally {
      if (this.isCurrentOperation(version, epoch, username)) { this.reminderBusy = false; this.reminderStatus = getTodoReminderStatus(); this.liveCleanupStatus = getTodoLiveCleanupStatus() }
    }
  }
  private async handleLiveView(item: TodoItem): Promise<void> {
    if (!this.hasAccount()) return
    const version = this.loadVersion
    const epoch = getCacheEpoch()
    const username = getUsername()
    try {
      const result = await startTodoLiveView(item)
      if (this.isCurrentOperation(version, epoch, username)) {
        safeToast(this.getUIContext(), result.ok ? '系统实况窗已更新' : (result.reason !== undefined ? result.reason : '当前不可用'))
      }
    } catch (_error) {
      if (this.isCurrentOperation(version, epoch, username)) safeToast(this.getUIContext(), '实况窗更新未完成，请稍后重试')
    }
  }

  @Builder
  BackButton() {
    Button({ type: ButtonType.Circle }) {
      Text('‹')
        .fontSize(24)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.palette.primary)
        .offset({ y: -1 })
    }
    .width(36).height(36)
    .backgroundColor(this.palette.primaryContainer)
    .accessibilityText('返回上一页')
    .onClick(() => { safeBack(this.getUIContext()) })
  }

  @Builder
  FilterChip(label: string, value: number) {
    Text(label)
      .fontSize(12)
      .fontWeight(this.filter === value ? FontWeight.Bold : FontWeight.Regular)
      .fontColor(this.filter === value ? this.palette.onPrimary : this.palette.onSurfaceVariant)
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .height(34)
      .backgroundColor(this.filter === value ? this.palette.primary : Color.Transparent)
      .borderRadius(Radius.sm)
      .onClick(() => { this.filter = value })
  }

  @Builder
  StatusDot(done: boolean) {
    Text(done ? '✓' : '')
      .fontSize(15)
      .fontWeight(FontWeight.Bold)
      .fontColor(this.palette.onPrimary)
      .textAlign(TextAlign.Center)
      .width(28)
      .height(28)
      .backgroundColor(done ? this.palette.success : this.palette.surfaceVariant)
      .borderRadius(14)
      .border({
        width: done ? 0 : 1,
        color: this.palette.outline,
      })
  }

  @Builder
  TodoRow(item: TodoItem) {
    Column() {
      LiquidGlass({ contentPadding: 14, radius: 18 }) {
        Row() {
          Column() {
            this.StatusDot(item.done)
          }
          .onClick(() => { this.handleToggle(item) })

        Column() {
          Text(item.title)
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(item.done ? this.palette.onSurfaceVariant : this.palette.onSurface)
            .decoration({ type: item.done ? TextDecorationType.LineThrough : TextDecorationType.None })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          if (item.note.length > 0 || item.dueText.length > 0) {
            Text((item.dueText.length > 0 ? item.dueText : '待安排') + (item.note.length > 0 ? ' · ' + item.note : ''))
              .fontSize(12)
              .fontColor(this.palette.onSurfaceVariant)
              .margin({ top: 5 })
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 12, right: 10 })
        .onClick(() => { this.handleToggle(item) })

        Text('窗')
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette.primary)
          .width(32)
          .height(32)
          .textAlign(TextAlign.Center)
          .backgroundColor(this.palette.primaryContainer)
          .borderRadius(16)
          .onClick(() => { this.handleLiveView(item) })

        Text('删')
          .fontSize(12)
          .fontColor(this.palette.error)
          .width(32)
          .height(32)
          .textAlign(TextAlign.Center)
          .backgroundColor(withAlpha(this.palette.error, this.isDark ? 0.12 : 0.10))
          .borderRadius(16)
          .margin({ left: 8 })
          .onClick(() => { this.handleDelete(item) })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
    }
    .margin({ left: 16, right: 16, top: 10 })
  }

  build() {
    Stack() {
      DetailScaffold({ title: '待办任务', subtitle: countOpenTodos(this.todos).toString() + ' 项待完成 · 安排好今天的每一件事', action: '',
        showBack: false }) {
      Scroll() {
        Column() {
          Column() {
            LiquidGlass({ contentPadding: 16, radius: 22 }) {
              Column() {
              TextInput({ placeholder: '新增待办', text: this.titleInput })
                .fontColor(this.palette.onSurface).placeholderColor(this.palette.onSurfaceVariant)
                .caretColor(this.palette.primary)
                .height(42)
                .fontSize(15)
                .backgroundColor(this.palette.surfaceVariant)
                .borderRadius(Radius.sm)
                .onChange((value: string) => { this.titleInput = value })

              Row({ space: 8 }) {
                Button(this.dueInput.length > 0 ? this.dueInput : '选择任务时间')
                  .fontColor(this.palette.onSurfaceVariant).layoutWeight(1).height(38).fontSize(12)
                  .backgroundColor(this.palette.surfaceVariant).borderRadius(Radius.sm)
                  .onClick(() => this.chooseDueTime())
                if (this.dueAt !== undefined) {
                  Button('清除').fontSize(12).backgroundColor(Color.Transparent)
                    .fontColor(this.palette.onSurfaceVariant).onClick(() => this.clearDueTime())
                }
                TextInput({ placeholder: '备注', text: this.noteInput })
                  .fontColor(this.palette.onSurface).placeholderColor(this.palette.onSurfaceVariant)
                  .caretColor(this.palette.primary)
                  .layoutWeight(1)
                  .height(38)
                  .fontSize(13)
                  .backgroundColor(this.palette.surfaceVariant)
                  .borderRadius(Radius.sm)
                  .onChange((value: string) => { this.noteInput = value })
              }
              .width('100%')
              .margin({ top: 10 })

              Text('添加')
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.palette.onPrimary)
                .textAlign(TextAlign.Center)
                .width('100%')
                .height(42)
                .backgroundColor(this.palette.primary)
                .borderRadius(Radius.md)
                .margin({ top: 12 })
                .onClick(() => { this.handleAdd() })
              }
              .width('100%')
            }
          }
          .margin({ left: 16, right: 16, top: 4 })

          if (this.loadError.length > 0) {
            Text(this.loadError).fontSize(13).fontColor(this.palette.onSurfaceVariant)
            Button(this.reloadBusy ? '读取中…' : '重新读取').enabled(!this.reloadBusy)
              .onClick(() => this.handleReloadTodos())
          }
          Button(this.reminderBusy ? '登记中…' : '登记任务提醒').enabled(!this.reminderBusy)
            .fontSize(13).fontColor(this.palette.primary).backgroundColor(this.palette.primaryContainer)
            .margin({ left: 16, right: 16, top: 12 }).onClick(() => this.handleReminders())
          if (this.liveCleanupStatus.length > 0) {
            Text(this.liveCleanupStatus).fontSize(12).fontColor(this.palette.onSurfaceVariant)
            Button('重试结束任务实况窗').enabled(!this.liveCleanupBusy)
              .onClick(() => this.handleRetryLiveCleanup())
          }
          Text(this.reminderStatus).fontSize(12).fontColor(this.palette.onSurfaceVariant)
            .margin({ left: 16, right: 16, top: 8 })
          Button('取消任务提醒').enabled(!this.reminderBusy).fontSize(12)
            .fontColor(this.palette.onSurfaceVariant).backgroundColor(Color.Transparent)
            .onClick(() => this.handleDisableReminders())
          Row() {
            this.FilterChip('全部', 0)
            this.FilterChip('未完成', 1)
            this.FilterChip('已完成', 2)
          }
          .height(42)
          .padding(4)
          .margin({ left: 16, right: 16, top: 14 })
          .backgroundColor(this.palette.surfaceVariant)
          .borderRadius(Radius.md)

          if (this.visibleTodos().length === 0) {
            Column() {
              LiquidGlass({ contentPadding: 20, radius: 22 }) {
                Column() {
                  Text(this.emptyTitle())
                    .fontSize(18)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.palette.onSurface)
                  Text(this.loadError.length > 0 ? '原数据保留，请使用上方重新读取。' : '把课程作业、社团事项和生活提醒放在这里。')
                    .fontSize(12)
                    .fontColor(this.palette.onSurfaceVariant)
                    .margin({ top: 8 })
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
              }
            }
            .margin({ left: 16, right: 16, top: 16 })
          } else {
            ForEach(this.visibleTodos(), (item: TodoItem) => {
              this.TodoRow(item)
            }, (item: TodoItem): string => item.id)
          }
        }
        .width('100%')
          // 底部留出悬浮导航栏的高度，否则最后一条待办会被栏压住。
          .padding({ bottom: this.safeAreaBottom + 104 })
      }
      .layoutWeight(1).align(Alignment.TopStart)

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
