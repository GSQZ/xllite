import { acceptCampusSchedule } from './CampusCompanionService'
import { getCachedValue, setCachedValue, getCacheEpoch, isCacheFresh } from './MemoryCache'
import { getUsername, getAccessToken, getCardToken, getCardSessionEpoch, getCardCacheNamespace, isGatewayAuth, getTokenExpiresAt } from './AuthManager'
import { callSchoolNative } from './SchoolNativeApi'
import { gatewayRun, refreshGatewayAccount, enrichGatewaySchedule } from './XlliteGateway'
import { schoolFeatureUrl } from '../utils/SchoolRoutes'

export class CallResult {
  ok: boolean = false
  data: Record<string, Object> = {}
  error: string = ''
  fromCache: boolean = false
  statusCode: number = 0
  officialUrl: string = ''
}
const READ_CACHE_TTL_MS: number = 5 * 60 * 1000
const SCHEDULE_CACHE_TTL_MS: number = 30 * 60 * 1000
const warmupTasks: Map<string, Promise<void>> = new Map<string, Promise<void>>()
const inflightRuns: Map<string, Promise<CallResult>> = new Map<string, Promise<CallResult>>()
function shouldCacheFeature(feature: string): boolean {
  return feature === 'jw.schedule' ||
    feature === 'jw.profile' ||
    feature === 'jw.grades' ||
    feature === 'jw.exams' ||
    feature === 'newcard.balance' ||
    feature === 'newcard.transactions' ||
    feature === 'newcard.electricity.account'
}

function ttlForFeature(feature: string): number {
  return feature === 'jw.schedule' ? SCHEDULE_CACHE_TTL_MS : READ_CACHE_TTL_MS
}

function cleanParams(params: Record<string, Object>): Record<string, Object> {
  const cleaned: Record<string, Object> = {}
  Object.keys(params).sort().forEach((key: string) => {
    if (!key.startsWith('_')) {
      cleaned[key] = params[key]
    }
  })
  return cleaned
}

function makeCacheKey(feature: string, username: string, params: Record<string, Object>): string {
  return (isGatewayAuth() ? 'xllite-gateway-v1|' : 'school-native-v1|') + feature + '|' + username + '|' + JSON.stringify(cleanParams(params)) + (feature.startsWith('newcard.') ? '|card-' + getCardCacheNamespace() + '-' + String(getCardSessionEpoch()) : '')
}


async function callViaHttp(feature: string, username: string,
  params: Record<string, Object>): Promise<CallResult> {
  const result = new CallResult()
  result.officialUrl = schoolFeatureUrl(feature)
  if (username.length === 0 || username !== getUsername()) return expiredSessionResult()
  // 会话来自 XLLite 网关时，业务请求走网关统一 /api/v1/run；
  // 学校原生适配器（余额/流水/个人信息）保留直连，网关不可达时不影响已有能力。
  if (isGatewayAuth()) {
    try {
      const epoch: number = getCacheEpoch()
      if (getTokenExpiresAt() - Date.now() < 5 * 60 * 1000) {
        const renewed = await refreshGatewayAccount()
        if (epoch !== getCacheEpoch() || username !== getUsername()) return expiredSessionResult()
        if (!renewed.ok) { result.error = renewed.error; result.statusCode = renewed.statusCode; return result }
      }
      // Refresh precedes the request; never replay a payment after a server error.
      const response = await gatewayRun(feature, getAccessToken(), cleanParams(params))
      if (response.ok && feature === 'jw.schedule') await enrichGatewaySchedule(response.data)
      result.ok = response.ok; result.data = response.data; result.error = response.error; result.statusCode = response.statusCode
    } catch (_e) { result.error = '网关数据校验未完成，请打开学校服务查看' }
    return result
  }
  try {
    const response = await callSchoolNative(feature, cleanParams(params), getCacheEpoch())
    result.ok = response.ok; result.data = response.data; result.error = response.error; result.statusCode = response.statusCode
  } catch (_e) { result.error = '学校数据格式校验未完成，请打开学校服务查看' }
  return result
}
function expiredSessionResult(): CallResult {
  const result = new CallResult(); result.error = '登录状态已变化，请重新登录'; result.statusCode = 401; return result
}
// 鉴权只走 Cookie 与 Bearer Token，密码不参与任何请求。此前这里挂着一个恒为空串的
// password 形参，一路透传却从未被读取，读代码的人会误以为密码进了鉴权链。
export async function callFeature(
  feature: string, username: string, params: Record<string, Object>
): Promise<CallResult> {
  const epoch = getCacheEpoch()
  if (username.length === 0 || username !== getUsername() || getAccessToken().length === 0) return expiredSessionResult()
  if (!isGatewayAuth() && feature.startsWith('newcard.') && getCardToken().length === 0) {
    const result = new CallResult(); result.error = '请先在学校一卡通页面完成认证'; result.statusCode = 401; result.officialUrl = schoolFeatureUrl(feature); return result
  }
  const cardEpoch = getCardSessionEpoch()
  const sessionValid = (): boolean => epoch === getCacheEpoch() && username === getUsername() && getAccessToken().length > 0 &&
    (isGatewayAuth() || !feature.startsWith('newcard.') || (cardEpoch === getCardSessionEpoch() && getCardToken().length > 0))
  const forceRefresh = params['_forceRefresh'] === true
  const cacheable = shouldCacheFeature(feature)
  const cacheKey = makeCacheKey(feature, username, params)
  if (cacheable && !forceRefresh) {
    const cached = await getCachedValue(cacheKey)
    // Stale-while-revalidate: if we have a last-good value, show it immediately and
    // only hit the network when its TTL has lapsed. No redirect/jump on app start.
    if (cached !== null && (feature !== 'jw.schedule' || cached['scheduleFetchedAt'] !== undefined)) {
      if (!sessionValid()) return expiredSessionResult()
      const fresh = isCacheFresh(cacheKey)
      const result = new CallResult()
      result.ok = true
      result.data = cached
      result.fromCache = true
      if (feature === 'jw.schedule') {
        await acceptCampusSchedule(username, cached, epoch).catch((_e: Error) => {})
      }
      if (!fresh) {
        // Background refresh: keep showing the cached value; the in-flight run republishes.
        refreshInBackground(feature, username, params, cacheKey, epoch).catch((_e: Error) => {})
      }
      return result
    }
  }
  if (!sessionValid()) return expiredSessionResult()
  const runKey = String(epoch) + '|' + cacheKey
  const existing = inflightRuns.get(runKey)
  if (existing !== undefined) return existing
  // Include cache publication in the shared task; no gap for a duplicate request.
  const task = (async (): Promise<CallResult> => {
    try {
      const result = await callViaHttp(feature, username, params)
      if (!sessionValid()) return expiredSessionResult()
      if (result.ok && feature === 'jw.schedule') await acceptCampusSchedule(username, result.data, epoch).catch((_e: Error) => {})
      if (!sessionValid()) return expiredSessionResult()
      if (result.ok && cacheable) await setCachedValue(cacheKey, result.data, ttlForFeature(feature), epoch)
      return sessionValid() ? result : expiredSessionResult()
    } finally { inflightRuns.delete(runKey) }
  })()
  inflightRuns.set(runKey, task)
  return task
}

// Background stale-while-revalidate refresh: reuses the shared in-flight run when one
// already exists for the same key, otherwise starts one. The cached value already shown
// is kept until the fresh result republishes; session/epoch guards stop it on logout.
async function refreshInBackground(feature: string, username: string,
  params: Record<string, Object>, cacheKey: string, epoch: number): Promise<void> {
  if (!shouldCacheFeature(feature)) return
  const cardEpoch = getCardSessionEpoch()
  const sessionValid = (): boolean => epoch === getCacheEpoch() && username === getUsername() &&
    getAccessToken().length > 0 &&
    (isGatewayAuth() || !feature.startsWith('newcard.') || (cardEpoch === getCardSessionEpoch() && getCardToken().length > 0))
  if (!sessionValid()) return
  const runKey = String(epoch) + '|' + cacheKey
  const existing = inflightRuns.get(runKey)
  if (existing !== undefined) { await existing; return }
  const task = (async (): Promise<CallResult> => {
    try {
      const result = await callViaHttp(feature, username, params)
      if (!sessionValid()) return result
      if (result.ok && feature === 'jw.schedule') await acceptCampusSchedule(username, result.data, epoch).catch((_e: Error) => {})
      if (!sessionValid()) return result
      if (result.ok) await setCachedValue(cacheKey, result.data, ttlForFeature(feature), epoch)
      return result
    } finally { inflightRuns.delete(runKey) }
  })()
  inflightRuns.set(runKey, task)
  await task
}

export async function prewarmCampusData(username: string): Promise<void> {
  if (username.length === 0 || getAccessToken().length === 0 || AppStorage.get<boolean>('appActive') === false ||
    AppStorage.get<boolean>('mainPageActive') === false) return
  const epoch = getCacheEpoch()
  const key = String(epoch) + '|' + username
  const existing = warmupTasks.get(key)
  if (existing !== undefined) return existing
  const task = (async (): Promise<void> => {
    try {
      // At most two warmup requests at once; respect valid cache and share in-flight reads.
      await Promise.all([
        callFeature('jw.profile', username, {}),
        (isGatewayAuth() || getCardToken().length > 0) ? callFeature('newcard.balance', username, {}) : Promise.resolve(new CallResult()),
      ])
      if (epoch !== getCacheEpoch() || AppStorage.get<boolean>('appActive') === false ||
        AppStorage.get<boolean>('mainPageActive') === false) return
      await Promise.all([
        (isGatewayAuth() || getCardToken().length > 0) ? callFeature('newcard.transactions', username, {}) : Promise.resolve(new CallResult()),
      ])
    } finally { warmupTasks.delete(key) }
  })()
  warmupTasks.set(key, task)
  return task
}
