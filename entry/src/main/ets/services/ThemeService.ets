import common from '@ohos.app.ability.common'
import ConfigurationConstant from '@ohos.app.ability.ConfigurationConstant'
import preferences from '@ohos.data.preferences'
import { Logger } from '../utils/Logger'
let systemDark: boolean = false
let themeContext: common.UIAbilityContext | null = null
let themeListener: ((isDark: boolean) => void) | null = null
let prefsTask: Promise<preferences.Preferences> | null = null
let persistenceTask: Promise<void> = Promise.resolve()
let themeRevision: number = 0
let motionRevision: number = 0
let nativeThemeReady: boolean = false
let nativeThemeMode: string = ''

export function setNativeThemeReady(ready: boolean): void {
  nativeThemeReady = ready
  if (!ready) nativeThemeMode = ''
  else applyTheme()
}
function syncNativeTheme(mode: string): void {
  if (!nativeThemeReady || themeContext === null || nativeThemeMode === mode) return
  const previous = nativeThemeMode
  nativeThemeMode = mode
  try {
    themeContext.setColorMode(mode === 'dark' ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
      : mode === 'light' ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT : ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET)
  } catch (_e) { nativeThemeMode = previous }
}

function getPrefs(): Promise<preferences.Preferences> | null {
  if (themeContext === null) return null
  if (prefsTask === null) {
    prefsTask = preferences.getPreferences(themeContext, 'xjit_theme').catch((e: Error) => {
      prefsTask = null
      throw e
    })
  }
  return prefsTask
}
function applyTheme(): void {
  const mode = AppStorage.get<string>('themeMode') ?? 'system'
  const dark = mode === 'dark' || (mode === 'system' && systemDark)
  AppStorage.setOrCreate<boolean>('isDark', dark)
  if (themeListener !== null) themeListener(dark)
  syncNativeTheme(mode)
}
export function updateSystemTheme(isDark: boolean): void { systemDark = isDark; applyTheme() }
export function observeTheme(listener: ((isDark: boolean) => void) | null): void { themeListener = listener }
export async function initTheme(ctx: common.UIAbilityContext): Promise<void> {
  themeContext = ctx
  const revision = themeRevision
  const motionAtStart = motionRevision
  AppStorage.setOrCreate<string>('themeMode', 'system')
  if (AppStorage.get<boolean>('reduceMotion') === undefined) AppStorage.setOrCreate<boolean>('reduceMotion', false)
  try {
    const task = getPrefs()
    if (task !== null) {
      const prefs = await task
      const mode = await prefs.get('mode', 'system')
      const reduceMotion = await prefs.get('reduceMotion', false)
      if (motionAtStart === motionRevision && typeof reduceMotion === 'boolean') {
        AppStorage.setOrCreate<boolean>('reduceMotion', reduceMotion)
      }
      if (revision === themeRevision && (mode === 'system' || mode === 'light' || mode === 'dark')) {
        AppStorage.set<string>('themeMode', mode)
      }
    }
  } catch (_e) {}
  applyTheme()
}
export function setThemeMode(mode: string): Promise<boolean> {
  if (mode !== 'system' && mode !== 'light' && mode !== 'dark') return Promise.resolve(false)
  themeRevision++
  AppStorage.setOrCreate<string>('themeMode', mode)
  applyTheme()
  return persistSetting('mode', mode)
}

/** App-level reduced motion preference; native controls keep their system feedback. */
export function setReduceMotion(enabled: boolean): Promise<boolean> {
  motionRevision++
  AppStorage.setOrCreate<boolean>('reduceMotion', enabled)
  return persistSetting('reduceMotion', enabled)
}

/**
 * 落盘一个设置项，返回是否真的写成功。
 *
 * 不能像以前那样 `.catch(() => {})` 之后返回已解决的 Promise：界面已经按新值
 * 切过去了，用户会以为设置已保存，重启却回到旧值。主题与减少动效都属于
 * 用户显式选择的偏好，静默丢失体验最差，所以失败既要记日志也要让调用方知道。
 */
function persistSetting(key: string, value: string | boolean): Promise<boolean> {
  const write = persistenceTask.then(async (): Promise<boolean> => {
    const task = getPrefs()
    if (task === null) return false
    const prefs = await task
    await prefs.put(key, value)
    await prefs.flush()
    return true
  })
  // 队列本身必须继续推进，否则一次失败会把后续所有写入卡死；结果单独返回。
  persistenceTask = write.then((): void => {}, (): void => {})
  return write.catch((_e: Error): boolean => {
    Logger.warn('Theme', 'setting not persisted key=%{public}s', key)
    return false
  })
}
