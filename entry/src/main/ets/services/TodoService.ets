import preferences from '@ohos.data.preferences'
import common from '@ohos.app.ability.common'
import { TodoDraft, TodoItem } from '../models/TodoTypes'
import { buildTodoWidgetData } from '../utils/TodoWidgetData'
import { syncTodoReminders, clearTodoReminders, getTodoReminderCount } from './TodoReminderService'
import { reconcileTodoLiveView } from './LiveViewService'
import { publishTodoWidgets } from './WidgetService'

const PREFS_NAME: string = 'xjit_todos'
const KEY_ITEMS: string = 'items'
const KEY_OWNER: string = 'owner'

let todoContext: common.UIAbilityContext | null = null
let todoStore: TodoItem[] = []
let loaded: boolean = false
let cleanupPending: boolean = false
let loadTask: Promise<void> | null = null
let prefsTask: Promise<preferences.Preferences> | null = null
let persistenceTask: Promise<void> = Promise.resolve()
let sessionVersion: number = 0
let todoOwner: string = ''
let remindersEnabled: boolean = false
let reminderStatus: string = '尚未登记任务提醒'
export function getTodoReminderStatus(): string { return reminderStatus }
let liveCleanupStatus: string = ''
export function getTodoLiveCleanupStatus(): string { return liveCleanupStatus }
async function reconcileLiveState(version: number): Promise<void> {
  try {
    await reconcileTodoLiveView(cloneItems(todoStore))
    if (version === sessionVersion) liveCleanupStatus = ''
  } catch (_error) {
    if (version === sessionVersion) liveCleanupStatus = '任务已保存，实况窗结束未完成，请重试清理'
  }
}
export function retryTodoLiveCleanup(): Promise<void> {
  const version = sessionVersion
  const task = persistenceTask.then(async () => {
    if (version !== sessionVersion) return
    await loadTodos()
    if (version === sessionVersion) await reconcileLiveState(version)
  })
  persistenceTask = task.catch((_error: Error) => {})
  return task
}

export function setTodoContext(ctx: common.UIAbilityContext): void {
  todoContext = ctx
}

// Tasks belong to whoever is signed in. The tag is stored next to the rows so a
// later session can tell whose data it is even when sign-out cleanup never
// reached disk, which is the case a plain "delete on logout" cannot cover.
export function setTodoOwner(owner: string): void {
  if (todoOwner === owner) return
  // 账号变了，内存里那一份就属于上一个账号。只换 todoOwner 而不清缓存的话，
  // loaded 仍是 true，下一次 loadTodos 会直接返回内存里的旧行——同进程内
  // 切换账号或登出后仍能读到别人的待办。这里连同读取任务与已加载标记一起作废。
  todoOwner = owner
  if (loaded || loadTask !== null) {
    loaded = false
    loadTask = null
    todoStore = []
  }
}
let idCounter: number = 0
// Two adds inside the same millisecond used to have a 1-in-100000 chance of
// identical ids; a collision makes toggle/delete hit both rows. The counter is
// monotonic per process and the loop still re-checks the live store.
function makeId(existing: TodoItem[]): string {
  const stamp = Date.now()
  let candidate = ''
  do {
    idCounter++
    candidate = stamp.toString() + '_' + idCounter.toString(36) + '_' + Math.floor(Math.random() * 1296).toString(36)
  } while (existing.some((item: TodoItem): boolean => item.id === candidate))
  return candidate
}
function ownerTag(): string {
  if (todoOwner.length === 0) return ''
  let a: number = 5381
  let b: number = 52711
  for (let i = 0; i < todoOwner.length; i++) {
    const c: number = todoOwner.charCodeAt(i)
    a = (a * 33 + c) % 2147483647
    b = (b * 31 + c) % 2147483629
  }
  return a.toString(36) + '-' + b.toString(36)
}

function parseItems(raw: string): TodoItem[] {
  const data = JSON.parse(raw) as Object
  if (!Array.isArray(data)) throw new Error('待办存储结构异常，原数据已保留')
  const valid: TodoItem[] = []
  const ids: Set<string> = new Set<string>()
  for (const value of data as Object[]) {
    if (value === null || typeof value !== 'object') continue
    const item = value as TodoItem
    if (typeof item.id !== 'string' || item.id.length === 0 ||
      typeof item.title !== 'string' || item.title.trim().length === 0 ||
      typeof item.note !== 'string' || typeof item.dueText !== 'string' || typeof item.done !== 'boolean' ||
      !Number.isFinite(item.createdAt) || !Number.isFinite(item.updatedAt) ||
      item.createdAt < 0 || item.updatedAt < item.createdAt) continue
    if (item.dueAt !== undefined && (!Number.isSafeInteger(item.dueAt) || item.dueAt <= 0 || item.dueAt > 8640000000000000)) item.dueAt = undefined
    if (ids.has(item.id)) continue
    ids.add(item.id)
    valid.push(item)
  }
  return valid
}
function cloneItems(items: TodoItem[]): TodoItem[] {
  return items.map((item: TodoItem): TodoItem => {
    return {
      id: item.id,
      title: item.title,
      note: item.note,
      dueText: item.dueText,
      dueAt: item.dueAt,
      done: item.done,
      createdAt: item.createdAt,
      updatedAt: item.updatedAt,
    }
  })
}

function getPrefs(): Promise<preferences.Preferences> | null {
  if (todoContext === null) return null
  if (prefsTask === null) {
    prefsTask = preferences.getPreferences(todoContext, PREFS_NAME).catch((e: Error) => {
      prefsTask = null
      throw e
    })
  }
  return prefsTask
}

function mutate(change: (items: TodoItem[]) => TodoItem[], version: number = sessionVersion, clearing: boolean = false): Promise<TodoItem[]> {
  const writeTask = persistenceTask.then(async (): Promise<TodoItem[]> => {
    if (!clearing) await loadTodos()
    else if (loadTask !== null) {
      try { await loadTask } catch (_error) { /* Explicit clearing does not depend on readable old data. */ }
    }
    if (version !== sessionVersion) throw new Error('待办会话已变化，请重新进入')
    const next = change(cloneItems(todoStore))
    const snapshot = JSON.stringify(next)
    const task = getPrefs()
    if (task === null) throw new Error('待办存储尚未初始化')
    const prefs = await task
    if (clearing) {
      await prefs.put('cleanup_pending', true)
      await prefs.flush()
    }
    // 清理时不要用当前（可能已登出的空）标记覆盖磁盘上的归属。clearSession 先
    // setTodoOwner('') 再 clearTodos()，若这里无条件写 ownerTag() 就会把 owner
    // 写成空串，于是同一个账号下次登录也要白白走一遍「异账号重置」。
    const nextOwner = clearing ? String(await prefs.get(KEY_OWNER, '')) : ownerTag()
    await prefs.put(KEY_OWNER, nextOwner)
    await prefs.put(KEY_ITEMS, snapshot)
    await prefs.flush()
    if (clearing) {
      await prefs.put('cleanup_pending', false)
      await prefs.flush()
    }
    if (version !== sessionVersion) throw new Error('待办会话已变化，旧写入结果已失效')
    todoStore = next
    if (clearing) { loaded = true; cleanupPending = false }
    await reconcileLiveState(version)
    if (version !== sessionVersion) throw new Error('待办会话已变化，旧发布已停止')
    if (todoContext !== null) {
      try { await publishTodoWidgets(todoContext, buildTodoWidgetData(todoStore)) }
      catch (_error) { console.warn('XJITTodo: task saved; widget refresh pending') }
      if (remindersEnabled && version === sessionVersion) {
        try {
          const count = await syncTodoReminders(cloneItems(todoStore), todoContext.abilityInfo.bundleName)
          if (version === sessionVersion) reminderStatus = '已登记 ' + count + ' 条任务提醒'
        } catch (_error) {
          if (version === sessionVersion) reminderStatus = '任务已保存，提醒未同步，请重新登记'
        }
      }
    }
    if (version !== sessionVersion) throw new Error('待办会话已变化，旧保存结果已失效')
    return cloneItems(todoStore)
  })
  persistenceTask = writeTask.then(() => {}).catch((_e: Error) => {})
  return writeTask
}

export async function loadTodos(): Promise<TodoItem[]> {
  const version = sessionVersion
  if (cleanupPending) throw new Error('上一会话待办清理未完成，请重试退出清理')
  if (loaded) return cloneItems(todoStore)
  if (loadTask === null) {
    loadTask = (async (): Promise<void> => {
      const task = getPrefs()
      if (task === null) return
      const prefs = await task
      const pending = await prefs.get('cleanup_pending', false)
      const storedOwner = await prefs.get(KEY_OWNER, '')
      if (typeof storedOwner !== 'string') throw new Error('待办归属标记异常，原数据已保留')
      // 没有账号时既不读也不写：下面「异账号」分支会清空行并把 owner 写成当前标记，
      // 而当前标记此时正是空串——等于用户只是没登录，就把盘上那个账号的待办抹掉了。
      // 读不到数据是安全的，销毁别人的数据不是。
      const owner = ownerTag()
      if (owner.length === 0) {
        if (version !== sessionVersion || cleanupPending) throw new Error('待办会话已变化，旧读取已失效')
        todoStore = []
        loaded = true
        return
      }
      const sameOwner = storedOwner === owner
      if (!sameOwner) {
        // Rows, and any cleanup marker, left behind by a different sign-in. Reset
        // both: the marker describes the previous owner's interrupted cleanup and
        // would otherwise stall this account on every later read.
        await prefs.put(KEY_OWNER, owner)
        await prefs.put(KEY_ITEMS, '[]')
        await prefs.put('cleanup_pending', false)
        await prefs.flush()
        if (version !== sessionVersion || cleanupPending) throw new Error('待办会话已变化，旧读取已失效')
        todoStore = []
        loaded = true
        return
      }
      if (pending !== false) {
        cleanupPending = true
        throw new Error('上一会话待办清理未完成，请重试退出清理')
      }
      const raw = await prefs.get(KEY_ITEMS, '')
      if (version !== sessionVersion || cleanupPending) throw new Error('待办会话已变化，旧读取已失效')
      if (typeof raw !== 'string') throw new Error('待办存储类型异常，原数据已保留')
      if (raw.length > 0) todoStore = parseItems(raw)
      loaded = true
    })()
  }
  const task = loadTask
  try { await task } finally { if (loadTask === task) loadTask = null }
  if (version !== sessionVersion || cleanupPending) throw new Error('待办会话已变化，旧读取已失效')
  return cloneItems(todoStore)
}

export async function addTodo(draft: TodoDraft): Promise<TodoItem[]> {
  if (draft.dueAt !== undefined && (!Number.isSafeInteger(draft.dueAt) || draft.dueAt <= 0 || draft.dueAt > 8640000000000000)) {
    throw new Error('请选择有效的任务时间')
  }
  const version = sessionVersion
  await loadTodos()
  const now = Date.now()
  const item: TodoItem = {
    id: makeId(todoStore),
    title: draft.title.trim(),
    note: draft.note.trim(),
    dueText: draft.dueText.trim(),
    dueAt: draft.dueAt,
    done: false,
    createdAt: now,
    updatedAt: now,
  }
  if (item.title.length === 0) {
    return cloneItems(todoStore)
  }
  return mutate((items: TodoItem[]): TodoItem[] => { items.unshift(item); return items }, version)
}

export async function toggleTodo(id: string): Promise<TodoItem[]> {
  const version = sessionVersion
  await loadTodos()
  const now = Date.now()
  return mutate((items: TodoItem[]): TodoItem[] => items.map((item: TodoItem): TodoItem => {
    if (item.id !== id) {
      return item
    }
    return {
      id: item.id,
      title: item.title,
      note: item.note,
      dueText: item.dueText,
      dueAt: item.dueAt,
      done: !item.done,
      createdAt: item.createdAt,
      updatedAt: now,
    }
  }), version)
}

export async function deleteTodo(id: string): Promise<TodoItem[]> {
  const version = sessionVersion
  await loadTodos()
  return mutate((items: TodoItem[]): TodoItem[] => items.filter((item: TodoItem): boolean => item.id !== id), version)
}

export function disableTodoReminders(): Promise<void> {
  const version = sessionVersion
  remindersEnabled = false
  const task = persistenceTask.then(async () => {
    if (version !== sessionVersion) return
    remindersEnabled = false
    try {
      await clearTodoReminders()
      if (version === sessionVersion) reminderStatus = '任务提醒已取消'
    } catch (error) {
      if (version === sessionVersion) reminderStatus = '自动同步已关闭，系统提醒取消未完成，请重试'
      throw error as Error
    }
  })
  persistenceTask = task.catch((_error: Error) => {})
  return task
}
export function registerTodoReminders(): Promise<number> {
  const version = sessionVersion
  const task = persistenceTask.then(async (): Promise<number> => {
    await loadTodos()
    if (version !== sessionVersion || todoContext === null) throw new Error('待办会话已变化，请重新进入')
    try {
      const count = await syncTodoReminders(cloneItems(todoStore), todoContext.abilityInfo.bundleName)
      if (version !== sessionVersion) throw new Error('待办会话已变化，登记结果已失效')
      remindersEnabled = true
      reminderStatus = '已登记 ' + count + ' 条任务提醒'
      return count
    } catch (error) {
      if (version === sessionVersion) reminderStatus = '任务保留，提醒登记未完成，请重试'
      throw error as Error
    }
  })
  persistenceTask = task.then(() => {}).catch((_error: Error) => {})
  return task
}
export function restoreTodoReminderStatus(): Promise<void> {
  const version = sessionVersion
  const task = persistenceTask.then(async () => {
    if (version !== sessionVersion) return
    try {
      const count = await getTodoReminderCount()
      if (version === sessionVersion) reminderStatus = '系统现有 ' + count + ' 条任务提醒；' +
        (remindersEnabled ? '本次会话自动同步已开启' : '自动同步未开启，可重新登记')
    } catch (_error) {
      if (version === sessionVersion) reminderStatus = '系统任务提醒状态未知，请重试查询或重新登记'
    }
  })
  persistenceTask = task.catch((_error: Error) => {})
  return task
}
export function refreshTodoWidgets(): Promise<void> {
  const version = sessionVersion
  const refresh = persistenceTask.then(async () => {
    await loadTodos()
    if (version !== sessionVersion || todoContext === null) return
    await publishTodoWidgets(todoContext, buildTodoWidgetData(todoStore))
  })
  persistenceTask = refresh.catch((_error: Error) => {})
  return refresh
}
export async function clearTodos(): Promise<void> {
  if (todoContext === null) throw new Error('待办存储尚未初始化，退出清理未完成，请重试')
  cleanupPending = true
  sessionVersion++
  remindersEnabled = false
  reminderStatus = '尚未登记任务提醒'
  liveCleanupStatus = ''
  // A failed clear must keep the marker: the rows on disk may be half-cleared, so
  // reading them would show inconsistent data. Recovery stays explicit through a
  // second clear, which is what the regression suite pins down.
  await mutate((_items: TodoItem[]): TodoItem[] => [], sessionVersion, true)
}
export function countOpenTodos(items: TodoItem[]): number {
  return items.filter((item: TodoItem): boolean => !item.done).length
}
