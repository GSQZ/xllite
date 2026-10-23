import { liveViewManager } from '@kit.LiveViewKit'
import deviceInfo from '@ohos.deviceInfo'
import wantAgent from '@ohos.app.ability.wantAgent'
import { BusinessError } from '@ohos.base'
import { Course } from '../models/JwTypes'
import { TodoItem } from '../models/TodoTypes'
import { LiveViewHandle, LiveViewResult, LiveViewTarget } from '../models/LiveViewTypes'
import { Logger } from '../utils/Logger'

export type { LiveViewHandle }
let currentView: liveViewManager.LiveView | null = null
let currentHandle: LiveViewHandle | null = null
let currentKey: string = ''
let currentTodoId: string = ''
let revision: number = 0
let lastViewId: number = Math.floor(Date.now() / 1000)
function nextViewId(): number {
  lastViewId = lastViewId >= 2147483647 ? -2147483648 : lastViewId + 1
  return lastViewId
}
// SDK 声明 sdkApiVersion: number，取值为纯 API 级（文档示例 12），设备上实测为 26。
// 早先这里按"可能是 60100023 这种八位编码"做了取模归一化，但门槛写成了 1e8，
// 而 60100023 只有六千万，条件永远不成立——真出现该编码时原样返回，
// 所有 api >= N 门控会把 6 千万当成版本号而恒为真，低版本设备反而拿到高版本字段。
// 现在按 6.1.0(23) -> 60100023 的真实构造规则覆盖编码形态，并拦住非法值。
function apiLevel(): number {
  const raw = deviceInfo.sdkApiVersion
  if (!Number.isInteger(raw) || raw <= 0) return 0
  // 编码形态是 主版本 * 1e7 + 次版本 * 1e5 + 补丁 * 1e3 + API，例如 6.1.0(23) -> 60100023。
  if (raw >= 10000000) return raw % 1000
  return raw
}
let operation: Promise<void> = Promise.resolve()
let supportReason: string = '开启后检查系统实况窗能力'
let applicationBundleName: string = 'com.xjit.app'

export function setLiveViewBundleName(bundleName: string): void {
  applicationBundleName = bundleName.length > 0 ? bundleName : 'com.xjit.app'
}

function reasonFor(error: BusinessError): string {
  if (error.code === 1003500005) return '应用尚未获批华为实况窗 TIMER 场景权限（1003500005）'
  if (error.code === 1003500004) return '请在系统设置中允许新理工显示实况窗（1003500004）'
  if (error.code === 801 || error.code === 1003500003) return '当前设备不支持或无法连接实况窗服务（801 / 1003500003）'
  // 下面三条是"重试能好"或"本来就没事"，与设备不支持区分开：
  // 真机上它们比 1003500003 更常见，混在一起会让人误判设备能力。
  if (error.code === 1003500008) return '实况窗创建过于频繁，请稍等几秒再试（1003500008）'
  if (error.code === 1003500011) return '实况窗版本号冲突，请关闭后重新开启（1003500011）'
  if (error.code === 1003500009) return '实况窗已不存在，无需再关闭（1003500009）'
  return '实况窗暂不可用（' + error.code + '）'
}
function setReason(reason: string): void {
  supportReason = reason
  AppStorage.setOrCreate<string>('liveViewStatus', reason)
  // 实况窗的成败只能看系统侧反应，真机验收时靠这条日志判断走到了哪一步：
  // 是系统开关没开、场景权益没批，还是载荷下发被拒。
  Logger.info('LiveView', 'api=%{public}d status=%{public}s', apiLevel(), reason)
}
export function getLiveViewSupportReason(): string { return supportReason }
export async function isLiveViewSupported(): Promise<boolean> {
  try {
    const enabled = await liveViewManager.isLiveViewEnabled()
    setReason(enabled ? '系统实况窗已允许，显示时仍需场景权限' : '系统实况窗未开启')
    return enabled
  } catch (error) { setReason(reasonFor(error as BusinessError)); return false }
}
export function buildCourseLiveTarget(course: Course, startTime: number, endTime: number): LiveViewTarget {
  return { type: 'course', title: course.title, text: course.sections, extra: course.location + ' · ' + course.teacher,
    startTime: startTime, endTime: endTime }
}
export function buildTodoLiveTarget(todo: TodoItem): LiveViewTarget {
  const now = Date.now()
  return { todoId: todo.id, type: 'todo', title: todo.title, text: todo.dueText || '待办计时', extra: todo.note,
    startTime: now, endTime: todo.dueAt === undefined ? now + 3600000 : todo.dueAt }
}
/** 灵动岛胶囊主色：课程用品牌靛蓝，待办用品牌紫，让胶囊一眼可分辨来源。 */
function capsuleColor(type: string): string {
  return type === 'todo' ? '#FF7B5CE6' : '#FF315FC4'
}
/** 胶囊图标放在 rawfile 根目录；不可用时系统回退默认图标。 */
const CAPSULE_ICON = 'liveview_capsule.png'
/**
 * 取计时型胶囊。
 *
 * `capsule` 的类型是三种胶囊的联合类型，计时相关的 `time` / `isCountdown` 只存在于
 * 计时胶囊上，因此必须先按 `type` 收窄，否则 ArkTS 拒绝访问这两个字段。
 */
function timerCapsule(view: liveViewManager.LiveView): liveViewManager.TimerCapsule | null {
  const capsule = view.liveViewData.capsule
  if (capsule === undefined) return null
  if (capsule.type !== liveViewManager.CapsuleType.CAPSULE_TYPE_TIMER) return null
  return capsule as liveViewManager.TimerCapsule
}
/**
 * 胶囊与主区文案。
 *
 * 系统会用 ${placeholder.timer} 替换主区里的计时占位符，由系统每秒刷新，
 * 因此主区不需要我们自己算剩余时间——这正是灵动岛能持续走秒的原因。
 */
function capsuleContent(type: string, started: boolean): string {
  if (type === 'todo') return '待办计时'
  return started ? '上课中' : '距上课'
}
/**
 * 主区文案。
 *
 * 计时占位符必须与正文处在同一个文本字符串里：系统是按字符串做替换的，
 * 把占位符单独放进 content 数组的另一个元素，它就没有可依附的计时上下文，
 * 那一格会渲染成未解析的占位文本而不是剩余时间。
 */
function primaryContent(target: LiveViewTarget, started: boolean): string {
  const detail = target.extra.slice(0, 60)
  const state = target.type === 'todo' ? '待办计时' : (started ? '上课中' : '距上课')
  return detail.length > 0 ? `${detail} · ${state} ${'${placeholder.timer}'}` : `${state} ${'${placeholder.timer}'}`
}
async function stopCurrent(): Promise<void> {
  if (currentView === null) return
  const view = currentView
  const previousStatus = view.liveViewData.capsule?.status
  const previousKeepTime = view.liveViewData.primary.keepTime
  // Same reasoning as in updateLiveView: a refused stop leaves the system version
  // where it was, so the local counter has to follow it back.
  const previousSequence = view.sequence
  view.sequence = (view.sequence ?? 0) + 1
  if (view.liveViewData.capsule !== undefined) view.liveViewData.capsule.status = -1
  view.liveViewData.primary.keepTime = 0
  try {
    const result = await liveViewManager.stopLiveView(view)
    if (result.resultCode !== 0) throw new Error('系统结束实况窗失败（' + result.resultCode + '）')
  } catch (error) {
    const code = (error as BusinessError).code
    if (code !== 1003500009 && code !== 1003500010) {
      if (view.liveViewData.capsule !== undefined && previousStatus !== undefined) view.liveViewData.capsule.status = previousStatus
      view.liveViewData.primary.keepTime = previousKeepTime
      view.sequence = previousSequence
      throw error as Error
    }
  }
  currentView = null; currentHandle = null; currentKey = ''; currentTodoId = ''
}
async function startTarget(target: LiveViewTarget, captured: number): Promise<LiveViewResult> {
  if (AppStorage.get<boolean>('liveViewEnabled') !== true) return { ok: false, reason: '请先在「桌面与提醒」开启实况窗' }
  if (!Number.isSafeInteger(target.startTime) || !Number.isSafeInteger(target.endTime) ||
    target.endTime > 8640000000000000 || target.endTime <= Date.now() ||
    target.startTime < 1000000000000 || target.startTime >= target.endTime) {
    return { ok: false, reason: '时间无效或已结束' }
  }
  if (!await isLiveViewSupported()) return { ok: false, reason: supportReason }
  if (captured !== revision || AppStorage.get<boolean>('liveViewEnabled') !== true) return { ok: false, reason: '实况窗已关闭' }
  const key = JSON.stringify([target.type, target.todoId ?? '', target.title, target.startTime, target.endTime])
  if (currentKey === key && currentHandle !== null && currentView !== null) {
    if (target.startTime <= Date.now() && currentView.liveViewData.capsule?.content === '距上课') {
      const previousTimer = currentView.timer
      const capsule = timerCapsule(currentView)
      // The capsule is mutated in place, so snapshot the scalar fields rather than
      // the object reference: keeping the reference would restore the mutated values.
      const previousContent = capsule === null ? '' : capsule.content
      const previousTime = capsule === null ? 0 : (capsule.time ?? 0)
      // A refused update leaves the system version untouched, so the local counter
      // is rolled back together with the payload.
      const previousSequence = currentView.sequence
      currentView.sequence = (currentView.sequence ?? 0) + 1
      if (apiLevel() >= 12) {
        currentView.timer = { time: Math.max(0, target.endTime - Date.now()), isCountdown: true }
      }
      // Mutate the existing capsule instead of replacing it: the dynamic-island icon
      // and tail affordances set at creation time live on this object, and rebuilding
      // it from scratch would drop them and leave a bare capsule on HarmonyOS 6.0.
      if (capsule !== null) {
        capsule.content = '上课中'
        capsule.time = Math.max(0, target.endTime - Date.now())
        capsule.isCountdown = true
      }
      try {
        const result = await liveViewManager.updateLiveView(currentView)
        if (result.resultCode !== 0) {
          currentView.timer = previousTimer
          currentView.sequence = previousSequence
          if (capsule !== null) {
            capsule.content = previousContent
            capsule.time = previousTime
          }
          setReason('实况窗更新失败（' + result.resultCode + '）')
          return { ok: false, reason: supportReason }
        }
      } catch (error) {
        currentView.timer = previousTimer
        currentView.sequence = previousSequence
        if (capsule !== null) {
          capsule.content = previousContent
          capsule.time = previousTime
        }
        setReason(reasonFor(error as BusinessError))
        return { ok: false, reason: supportReason }
      }
    }
    setReason('实况窗已显示')
    return { ok: true, handle: { id: currentHandle.id, startTime: currentHandle.startTime, targetType: currentHandle.targetType } }
  }
  await stopCurrent()
  if (captured !== revision) return { ok: false, reason: '实况窗已关闭' }
  try {
    let action: object | null = null
    try {
      action = await wantAgent.getWantAgent({ wants: [{ bundleName: applicationBundleName, abilityName: 'EntryAbility',
        parameters: { campusRoute: target.type === 'course' ? 'schedule' : 'todo' } }],
        operationType: wantAgent.OperationType.START_ABILITY, requestCode: 8201,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG] })
    } catch (error) {
      const code = (error as BusinessError).code
      if (code === 401 || code === 403 || code === 201 || code === 1003500004 || code === 1003500005) {
        setReason('实况窗返回点击未开放（' + code + '）')
        return { ok: false, reason: supportReason }
      }
      setReason(reasonFor(error as BusinessError))
      return { ok: false, reason: supportReason }
    }
    if (action === null) return { ok: false, reason: '实况窗返回入口获取失败' }
    const clickAction: object = action
    const deadline = target.startTime > Date.now() ? target.startTime : target.endTime
    const duration = Math.max(0, deadline - Date.now())
    // Every member below is gated by the API level that actually introduced it.
    // Passing a member that the running release does not know hands the system an
    // undefined value, and omitting one that it does know leaves the surface
    // without that capability, so the gates are per member, not per feature.
    //   timer                    5.0.0(12)
    //   capsule.icon             4.1.0(11)
    //   capsule.isContentDisplayed 5.0.3(15)
    //   capsule.tailIcon / isTailIconDisplayed 6.0.0(20)
    //   primary.aliveTime        6.1.1(24)
    //   lifeCycleMode            26.0.0
    const api = apiLevel()
    const started = target.startTime <= Date.now()
    const capsule: liveViewManager.TimerCapsule = {
      type: liveViewManager.CapsuleType.CAPSULE_TYPE_TIMER, status: 1,
      content: capsuleContent(target.type, started), time: duration, isCountdown: true,
      backgroundColor: capsuleColor(target.type),
    }
    if (api >= 11) {
      capsule.icon = CAPSULE_ICON
    }
    if (api >= 15) {
      capsule.isContentDisplayed = true
    }
    if (api >= 20) {
      // HarmonyOS 6.0 added the dynamic-island tail affordances.
      capsule.tailIcon = CAPSULE_ICON
      capsule.isTailIconDisplayed = true
    }
    const view: liveViewManager.LiveView = {
      id: nextViewId(), event: 'TIMER', sequence: 0, isMute: true,
      liveViewData: {
        primary: { title: target.title.slice(0, 40),
          // The timer placeholder has to sit inside a single text string. Handing
          // the system a separate array entry for it leaves it without a timer
          // context to resolve against, and the slot then renders as a literal
          // unresolved token instead of the remaining time.
          content: [{ text: primaryContent(target, started) }],
          clickAction: clickAction },
        capsule: capsule,
      },
    }
    if (api >= 12) {
      const timer: liveViewManager.LiveViewTimer = { time: duration, isCountdown: true }
      if (api >= 20) {
        // When the countdown reaches zero the system swaps in these texts, so the
        // surface never falls back to a raw zero or an unresolved placeholder.
        timer.countdownPreset = { presetTitle: target.title.slice(0, 40), presetContent: '已结束' }
        timer.capsuleCountdownPreset = { presetTitle: '已结束', presetContent: '已结束' }
      }
      view.timer = timer
    }
    if (api >= 26) view.lifeCycleMode = liveViewManager.LifeCycleMode.AUTO_STOP_WHEN_APP_TERMINATE
    if (api >= 24) {
      view.liveViewData.primary.aliveTime = Math.max(15, Math.min(28800, Math.ceil((target.endTime - Date.now()) / 1000)))
    }
    if (captured !== revision || AppStorage.get<boolean>('liveViewEnabled') !== true) return { ok: false, reason: '实况窗已关闭' }
    const result = await liveViewManager.startLiveView(view)
    if (result.resultCode !== 0) {
      // Partial result may still leave a primary area: retain and stop it.
      currentView = view
      try {
        await stopCurrent()
      } catch (_error) {
        // The system refused the cleanup too. Keep currentView set so a later
        // finishAllLiveViews can retry, but never leave currentHandle stale.
        currentHandle = null; currentKey = ''; currentTodoId = ''
        setReason('实况窗显示不完整且回收未完成（' + result.resultCode + '）')
        return { ok: false, reason: supportReason }
      }
      setReason('实况窗显示不完整（' + result.resultCode + '）')
      return { ok: false, reason: supportReason }
    }
    currentView = view; currentKey = key; currentTodoId = target.todoId ?? ''
    currentHandle = { id: String(view.id), startTime: target.startTime, targetType: target.type }
    if (captured !== revision || AppStorage.get<boolean>('liveViewEnabled') !== true) {
      await stopCurrent(); return { ok: false, reason: '实况窗已关闭' }
    }
    setReason('实况窗已显示')
    return { ok: true, handle: { id: currentHandle.id, startTime: currentHandle.startTime, targetType: currentHandle.targetType } }
  } catch (error) { setReason(reasonFor(error as BusinessError)); return { ok: false, reason: supportReason } }
}
export function startLiveView(target: LiveViewTarget): Promise<LiveViewResult> {
  const captured = revision
  const snapshot: LiveViewTarget = { todoId: target.todoId, type: target.type, title: target.title, text: target.text,
    extra: target.extra, startTime: target.startTime, endTime: target.endTime }
  const task = operation.then(() => startTarget(snapshot, captured))
  operation = task.then(() => {}).catch((_e: Error) => {})
  return task
}
export function startCourseLiveView(course: Course, startTime: number, endTime: number): Promise<LiveViewResult> {
  return startLiveView(buildCourseLiveTarget(course, startTime, endTime))
}
export function startTodoLiveView(todo: TodoItem): Promise<LiveViewResult> {
  if (todo.done) return Promise.resolve<LiveViewResult>({ ok: false, reason: '任务已完成，无需启动实况窗' })
  return startLiveView(buildTodoLiveTarget(todo))
}
function matchesCurrentHandle(handle: LiveViewHandle): boolean {
  return currentHandle !== null && handle.id === currentHandle.id &&
    handle.startTime === currentHandle.startTime && handle.targetType === currentHandle.targetType
}
export async function updateLiveView(handle: LiveViewHandle, course: Course, now: number): Promise<void> {
  const title = course.title.slice(0, 40)
  const snapshot: LiveViewHandle = { id: handle.id, startTime: handle.startTime, targetType: handle.targetType }
  const task = operation.then(async () => {
    if (currentView === null || !matchesCurrentHandle(snapshot)) return
    const view = currentView
    const previousTitle = view.liveViewData.primary.title
    // The system only accepts an update whose version is greater than the one it
    // currently holds. A rejected update leaves the system version untouched, so
    // the local counter has to be rolled back with the payload; otherwise the
    // next attempt skips a version and the system reports a sequence conflict.
    const previousSequence = view.sequence
    view.sequence = (view.sequence ?? 0) + 1
    view.liveViewData.primary.title = title
    try {
      const result = await liveViewManager.updateLiveView(view)
      if (result.resultCode !== 0) {
        setReason('实况窗更新失败（' + result.resultCode + '）')
        throw new Error('系统实况窗更新失败：' + result.resultCode)
      }
    } catch (error) {
      view.liveViewData.primary.title = previousTitle
      view.sequence = previousSequence
      if ((error as BusinessError).code !== undefined) setReason(reasonFor(error as BusinessError))
      throw error as Error
    }
  })
  operation = task.catch((_e: Error) => {})
  return task
}
export function finishLiveView(handle: LiveViewHandle): Promise<void> {
  const snapshot: LiveViewHandle = { id: handle.id, startTime: handle.startTime, targetType: handle.targetType }
  const task = operation.then(async () => {
    if (matchesCurrentHandle(snapshot)) await stopCurrent()
  })
  operation = task.catch((_e: Error) => {})
  return task
}
export function reconcileTodoLiveView(items: TodoItem[]): Promise<void> {
  const openIds = items.filter((item: TodoItem): boolean => !item.done).map((item: TodoItem): string => item.id)
  const task = operation.then(async () => {
    if (currentHandle?.targetType === 'todo' && currentTodoId.length > 0 && !openIds.includes(currentTodoId)) {
      await stopCurrent()
    }
  })
  operation = task.catch((_e: Error) => {})
  return task
}
export function finishAllLiveViews(): Promise<void> {
  revision++
  const task = operation.then(() => stopCurrent())
  operation = task.catch((_e: Error) => {})
  return task
}
export function getCurrentHandle(): LiveViewHandle | null {
  if (currentHandle === null) return null
  return { id: currentHandle.id, startTime: currentHandle.startTime, targetType: currentHandle.targetType }
}
