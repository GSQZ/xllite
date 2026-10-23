import http from '@ohos.net.http'
import { saveSchoolSession, clearAccessToken, clearSession, getUsername, getAccessToken, isGatewayAuth } from './AuthManager'
import { getCacheEpoch } from './MemoryCache'

// Unified gateway contract follows the live HTTPS OpenAPI and feature-detail responses.
// Public calendar requests deliberately omit the account bearer token.
export const XLLITE_GATEWAY_BASE: string = 'https://xllite.sayqz.com'

export class GatewayResult {
  ok: boolean = false
  data: Record<string, Object> = {}
  error: string = ''
  statusCode: number = 0
  networkError: boolean = false
}

function gwField(obj: Record<string, Object>, key: string): string {
  const value: Object = obj[key]
  if (value === null || value === undefined) return ''
  return String(value)
}

function gwNum(obj: Record<string, Object>, key: string): number {
  const value: Object = obj[key]
  if (value === null || value === undefined) return 0
  const parsed = Number(value)
  return Number.isFinite(parsed) ? parsed : 0
}

function gwErrorMessage(body: Record<string, Object>, statusCode: number): string {
  const raw = gwField(body, 'error')
  const alt = raw.length === 0 ? gwField(body, 'message') : raw
  const text = alt.length === 0 ? gwField(body, 'msg') : alt
  if (text.length > 0) return text.trim()
  if (statusCode >= 400) return '接口请求失败（HTTP ' + statusCode + '）'
  return '请求失败'
}

async function gwRequest(method: http.RequestMethod, path: string, token: string,
  payload: Record<string, Object> | null): Promise<GatewayResult> {
  const result = new GatewayResult()
  const session = http.createHttp()
  try {
    const headers: Record<string, Object> = { 'Content-Type': 'application/json', 'Accept': 'application/json' }
    if (token.length > 0) headers['Authorization'] = 'Bearer ' + token
    let url = XLLITE_GATEWAY_BASE + path
    let extra = ''
    if (method === http.RequestMethod.GET) {
      const keys: string[] = payload === null ? [] : Object.keys(payload).sort()
      const queryParts: string[] = []
      keys.forEach((k: string): void => {
        if (payload !== null) queryParts.push(encodeURIComponent(k) + '=' + encodeURIComponent(gwField(payload, k)))
      })
      if (queryParts.length > 0) url += '?' + queryParts.join('&')
    } else {
      extra = payload === null ? '{}' : JSON.stringify(payload)
    }
    const res = await session.request(url, {
      method: method,
      header: headers,
      extraData: extra,
      usingCache: false,
      connectTimeout: 12000,
      readTimeout: 45000,
      maxLimit: 2 * 1024 * 1024,
    } as http.HttpRequestOptions)
    result.statusCode = res.responseCode
    let parsed: Object
    try {
      parsed = JSON.parse(String(res.result))
    } catch (_e) {
      result.error = '接口没有返回数据'
      return result
    }
    let body: Record<string, Object>
    if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
      result.error = '接口没有返回数据'
      return result
    }
    body = parsed as Record<string, Object>
    if (res.responseCode >= 400 || body['ok'] !== true) {
      result.error = gwErrorMessage(body, res.responseCode)
      return result
    }
    let data: Object = body['data']
    if (data === null || data === undefined) {
      const empty: Record<string, Object> = {}
      data = empty
    }
    if (typeof data !== 'object' || Array.isArray(data)) { result.error = '接口返回数据格式异常'; return result }
    result.data = data as Record<string, Object>
    result.ok = true
  } catch (_e) {
    result.networkError = result.statusCode === 0
    result.error = result.networkError ? '连接失败，请检查网络后重试' : '接口响应校验未完成，请稍后重试'
  } finally {
    session.destroy()
  }
  return result
}

export async function gatewayAcademicCalendar(term: string): Promise<GatewayResult> {
  const result = await gwRequest(http.RequestMethod.GET, '/api/v1/academic-calendar', '', { 'term': term })
  if (!result.ok) return result
  const raw: Object = result.data['calendar']
  if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) {
    result.ok = false; result.error = '校历数据格式异常'; return result
  }
  const calendar = raw as Record<string, Object>
  const first: string = gwField(calendar, 'firstMonday')
  const date: Date = new Date(first + 'T00:00:00+08:00')
  const validDate: boolean = /^\d{4}-\d{2}-\d{2}$/.test(first) && Number.isFinite(date.getTime()) &&
    new Date(date.getTime() + 8 * 3600000).toISOString().slice(0, 10) === first && date.getUTCDay() === 0
  const weeks: number = gwNum(calendar, 'weekCount')
  const overrides: Object = calendar['dateOverrides']
  if (result.data['schemaVersion'] !== 1 || result.data['timezone'] !== 'Asia/Shanghai' ||
    result.data['term'] !== term || result.data['status'] !== 'confirmed' || calendar['term'] !== term ||
    calendar['status'] !== 'confirmed' || !validDate || !Number.isInteger(weeks) || weeks < 1 || weeks > 60 ||
    !Array.isArray(calendar['sectionTimes']) || !Array.isArray(overrides) || (overrides as Object[]).length > 0) {
    result.ok = false; result.data = {}; result.error = '校历尚未满足自动校准条件，请手动确认教学周'
  }
  return result
}

export async function enrichGatewaySchedule(data: Record<string, Object>): Promise<void> {
  data['scheduleFetchedAt'] = Date.now()
  const term: string = gwField(data, 'term')
  if (term.length === 0) return
  const response = await gatewayAcademicCalendar(term)
  if (!response.ok) return
  const calendar = response.data['calendar'] as Record<string, Object>
  data['termStartDate'] = calendar['firstMonday']
  data['totalWeeks'] = calendar['weekCount']
}

// /api/v1/auth/login —— username+password(+captcha/rememberMe)，返回 data{username, accessToken, tokenType, source, expiresAt/expiresInSeconds}
export async function gatewayLogin(username: string, password: string,
  captcha: string = '', rememberMe: boolean = false): Promise<GatewayResult> {
  const payload: Record<string, Object> = { 'username': username, 'password': password }
  if (captcha.length > 0) payload['captcha'] = captcha
  payload['rememberMe'] = rememberMe
  return await gwRequest(http.RequestMethod.POST, '/api/v1/auth/login', '', payload)
}

// /api/v1/auth/refresh —— 用旧 accessToken 换新
export async function gatewayRefresh(accessToken: string): Promise<GatewayResult> {
  return await gwRequest(http.RequestMethod.POST, '/api/v1/auth/refresh', accessToken, {})
}

export async function gatewaySession(accessToken: string): Promise<GatewayResult> {
  return await gwRequest(http.RequestMethod.GET, '/api/v1/auth/session', accessToken, null)
}

export async function gatewayLogout(accessToken: string): Promise<void> {
  await gwRequest(http.RequestMethod.POST, '/api/v1/auth/logout', accessToken, {})
}

// /api/v1/run —— 所有 13 个 feature 的统一业务入口（见 GATEWAY_FEATURE_NAMES）
export async function gatewayRun(feature: string, accessToken: string,
  params: Record<string, Object>): Promise<GatewayResult> {
  const payload: Record<string, Object> = { 'feature': feature, 'params': params }
  const result = await gwRequest(http.RequestMethod.POST, '/api/v1/run', accessToken, payload)
  if (result.ok) {
    const collections: Record<string, string> = {
      'jw.schedule': 'courses', 'jw.grades': 'normalGrades', 'jw.exams': 'exams',
      'newcard.balance': 'accounts', 'newcard.transactions': 'transactions'
    }
    const key: string = collections[feature]
    if (key !== undefined && !Array.isArray(result.data[key])) {
      result.ok = false; result.data = {}; result.error = '业务响应缺少有效的' + key + '集合'
    }
    // 两个支付入口都必须带回 payResult 对象。漏发时订单往往已在服务端创建成功，
    // 若当成成功继续走，页面会在空对象上取属性、被通用 catch 吞成"网络失败"，
    // 用户看不出订单已存在，很可能重复下单。
    if (result.ok && (feature === 'newcard.recharge.create_order' ||
      feature === 'newcard.electricity.recharge.pay')) {
      const payResult: Object = result.data['payResult']
      if (payResult === null || typeof payResult !== 'object' || Array.isArray(payResult)) {
        result.ok = false; result.data = {}
        result.error = '订单可能已创建，但响应缺少支付信息，请先到一卡通账户查询后再决定是否重试'
      }
    }
  }
  return result
}

function gwExpiry(data: Record<string, Object>): number {
  const rawExp: Object = data['expiresAt']
  if (rawExp !== null && rawExp !== undefined) {
    const value = Number(rawExp)
    if (Number.isFinite(value)) return value > 100000000000 ? value : value * 1000
  }
  const sec: Object = data['expiresInSeconds']
  if (sec !== null && sec !== undefined) {
    const value = Number(sec)
    if (Number.isFinite(value) && value > 0) return Date.now() + value * 1000
  }
  return 0
}

// 把网关登录返回的 data 保存为应用会话（auth_source=xllite-gateway），
// 之后业务请求一律走 gatewayRun；学校原生适配器保留直连，网关不可达时不影响已有能力。
export async function acceptGatewayLogin(username: string, data: Record<string, Object>,
  epoch: number = getCacheEpoch()): Promise<GatewayResult> {
  const result = new GatewayResult()
  const token = gwField(data, 'accessToken').trim()
  const name = gwField(data, 'username').trim()
  if (token.length === 0 || epoch !== getCacheEpoch()) {
    result.error = '登录成功但没有返回 accessToken'
    return result
  }
  const expiresAt: number = gwExpiry(data)
  if (!Number.isFinite(expiresAt) || expiresAt <= Date.now()) {
    result.error = '登录会话有效期无效，请重试'
    return result
  }
  const finalName = name.length > 0 ? name : username
  try {
    await saveSchoolSession(finalName, token, expiresAt, epoch, 'xllite-gateway')
  } catch (_e) {
    result.error = '登录状态保存失败，请重试'
    return result
  }
  if (epoch !== getCacheEpoch()) { result.error = '登录状态已变化，请重试'; return result }
  result.ok = true
  result.data = { 'username': finalName, 'accessToken': token }
  return result
}

// 网关刷新成功后的会话续期：由页面层先调 gatewayRefresh(旧token)，
// 用返回的 data 调这里落盘；失败时保持旧会话不变。
export async function acceptGatewaySessionRefresh(data: Record<string, Object>,
  epoch: number = getCacheEpoch()): Promise<GatewayResult> {
  const result = new GatewayResult()
  const token = gwField(data, 'accessToken').trim()
  const name = getUsername()
  const expiresAt = gwExpiry(data)
  if (token.length === 0 || expiresAt <= 0 || epoch !== getCacheEpoch()) {
    result.error = '会话刷新返回不完整'
    return result
  }
  try {
    await saveSchoolSession(name.length > 0 ? name : 'gateway', token, expiresAt, epoch, 'xllite-gateway')
  } catch (_e) { result.error = '会话刷新保存失败'; return result }
  result.ok = true
  return result
}

export function clearGatewaySession(): Promise<void> {
  return clearAccessToken()
}

let refreshTask: Promise<GatewayResult> | undefined = undefined
let refreshEpoch: number = -1

export function refreshGatewayAccount(): Promise<GatewayResult> {
  const epoch: number = getCacheEpoch()
  if (refreshTask !== undefined && refreshEpoch === epoch) return refreshTask
  const token: string = getAccessToken()
  if (!isGatewayAuth() || token.length === 0) {
    const result = new GatewayResult(); result.error = '登录已过期，请重新登录'
    return Promise.resolve(result)
  }
  refreshEpoch = epoch
  const task: Promise<GatewayResult> = (async (): Promise<GatewayResult> => {
    try {
      const response = await gatewayRefresh(token)
      if (epoch !== getCacheEpoch() || token !== getAccessToken()) {
        const retired = new GatewayResult(); retired.error = '登录状态已变化'; return retired
      }
      if (!response.ok) return response
      return await acceptGatewayLogin(getUsername(), response.data, epoch)
    } finally { if (refreshEpoch === epoch) refreshTask = undefined }
  })()
  refreshTask = task
  return task
}

export async function logoutGatewayAccount(): Promise<void> {
  const token: string = isGatewayAuth() ? getAccessToken() : ''
  await clearSession()
  // Local cleanup is authoritative for navigation; remote revocation is best effort.
  if (token.length > 0) gatewayLogout(token).catch((_error: Error) => {})
}

// 网关支持的 13 个 feature（与 xllite 仓库 XjitFeature 枚举一致）
export const GATEWAY_FEATURE_NAMES: string[] = [
  'jw.profile', 'jw.schedule', 'jw.grades', 'jw.exams',
  'newcard.balance', 'newcard.transactions', 'newcard.campus_code.qrcode',
  'newcard.recharge.config', 'newcard.recharge.create_order',
  'newcard.electricity.account', 'newcard.electricity.recharge.config',
  'newcard.electricity.recharge.pay',
]

export function isGatewayFeature(feature: string): boolean {
  return GATEWAY_FEATURE_NAMES.indexOf(feature) >= 0
}
