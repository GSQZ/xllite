import preferences from '@ohos.data.preferences'
import common from '@ohos.app.ability.common'

export interface CacheEntry {
  value: Record<string, Object>
  expiresAt: number
  fetchedAt: number
}
const PREFS_NAME: string = 'xjit_http_cache'
const MAX_MEMORY_ENTRIES: number = 128
const cacheStore: Map<string, CacheEntry> = new Map<string, CacheEntry>()
let cacheContext: common.UIAbilityContext | null = null
let prefsTask: Promise<preferences.Preferences> | null = null
let persistenceTask: Promise<void> = Promise.resolve()
let flushTimer: number = -1
let sessionEpoch: number = 0

export function setCacheContext(ctx: common.UIAbilityContext): void { cacheContext = ctx }
export function getCacheEpoch(): number { return sessionEpoch }

function getPrefs(): Promise<preferences.Preferences> | null {
  if (cacheContext === null) return null
  if (prefsTask === null) {
    prefsTask = preferences.getPreferences(cacheContext, PREFS_NAME).catch((e: Error) => {
      prefsTask = null
      throw e
    })
  }
  return prefsTask
}

function enqueue(action: () => Promise<void>): Promise<void> {
  const task = persistenceTask.then(action)
  // 队列本身必须推进（否则一次失败会卡死后续所有写盘），但失败要原样交给调用方。
  // 原先这里 .catch(() => {}) 之后返回，clearAllCachedValues 永不 reject，于是
  // clearSession 的 Promise.all 把它当作成功——磁盘上的课表、成绩、流水缓存
  // 仍然留着，而用户看到的是「已退出登录」。
  persistenceTask = task.then((): void => {}, (): void => {})
  return task
}

function scheduleFlush(): void {
  if (flushTimer >= 0) return
  flushTimer = setTimeout(() => {
    flushTimer = -1
    flushCachedValues().catch((_e: Error) => {})
  }, 300)
}

export function flushCachedValues(): Promise<void> {
  if (flushTimer >= 0) clearTimeout(flushTimer)
  flushTimer = -1
  return enqueue(async () => {
    const task = getPrefs()
    if (task !== null) { const prefs = await task; await prefs.flush() }
  })
}

function remember(key: string, entry: CacheEntry): void {
  cacheStore.delete(key)
  cacheStore.set(key, entry)
  if (cacheStore.size > MAX_MEMORY_ENTRIES) {
    const oldest = cacheStore.keys().next().value as string
    cacheStore.delete(oldest)
    const epoch = sessionEpoch
    // 缓存条目回收是尽力而为：删不掉最多让磁盘多留一条过期数据，
    // 但必须接住拒绝，否则会变成未处理的 Promise 拒绝。
    enqueue(async () => {
      const task = getPrefs()
      if (task === null) return
      const prefs = await task
      if (epoch !== sessionEpoch) return
      await prefs.delete(oldest)
      scheduleFlush()
    }).catch((_e: Error) => {})
  }
}

export async function getCachedValue(key: string): Promise<Record<string, Object> | null> {
  const epoch = sessionEpoch
  const item = cacheStore.get(key)
  if (item !== undefined) {
    // In-memory entries are trusted while the session is live: serve them even past TTL,
    // so the UI keeps showing the last good data and refreshes in the background.
    remember(key, item)
    return item.value
  }
  try {
    const task = getPrefs()
    if (task === null) return null
    const prefs = await task
    const raw = await prefs.get(key, '')
    if (epoch !== sessionEpoch || typeof raw !== 'string' || raw.length === 0) return null
    let persisted: CacheEntry | null = null
    try { persisted = JSON.parse(raw) as CacheEntry } catch (_e) { persisted = null }
    // Unparseable or structurally invalid entries are purged so they are never
    // served and are not re-read (and re-parsed) on every call.
    if (persisted === null || !Number.isFinite(persisted.expiresAt) ||
      persisted.value === undefined || persisted.value === null) {
      await clearCachedValue(key, epoch)
      return null
    }
    remember(key, persisted)
    return persisted.value
  } catch (_e) { return null }
}

// TTL check for stale-while-revalidate: a key is due for a background refresh when
// its persisted entry has no value or its expiresAt has passed (or is unknown).
export function isCacheFresh(key: string): boolean {
  const item = cacheStore.get(key)
  if (item !== undefined) return item.expiresAt > Date.now()
  return false
}

export function setCachedValue(key: string, value: Record<string, Object>, ttlMs: number,
  epoch: number = sessionEpoch): Promise<void> {
  if (epoch !== sessionEpoch) return Promise.resolve()
  const now = Date.now()
  const entry: CacheEntry = { value: value, expiresAt: now + ttlMs, fetchedAt: now }
  remember(key, entry)
  // Publish to memory before persistence; one flush batches the parallel responses.
  return enqueue(async () => {
    const task = getPrefs()
    if (task === null) return
    const prefs = await task
    if (epoch !== sessionEpoch) return
    await prefs.put(key, JSON.stringify(entry))
    scheduleFlush()
  })
}

export function clearCachedValue(key: string, epoch: number = sessionEpoch): Promise<void> {
  if (epoch !== sessionEpoch) return Promise.resolve()
  cacheStore.delete(key)
  return enqueue(async () => {
    const task = getPrefs()
    if (task === null) return
    const prefs = await task
    if (epoch !== sessionEpoch) return
    await prefs.delete(key)
    scheduleFlush()
  })
}

export function clearAllCachedValues(): Promise<void> {
  // Invalidate immediately, including requests still in flight at logout.
  sessionEpoch++
  cacheStore.clear()
  if (flushTimer >= 0) clearTimeout(flushTimer)
  flushTimer = -1
  return enqueue(async () => {
    const task = getPrefs()
    if (task === null) return
    const prefs = await task
    await prefs.clear()
    await prefs.flush()
  })
}
