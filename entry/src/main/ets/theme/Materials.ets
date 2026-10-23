import type uiMaterial from '@ohos.arkui.uiMaterial'
import deviceInfo from '@ohos.deviceInfo'

let checkSupport: (() => boolean) | null = null
let createMaterial: ((isDark: boolean, interactive: boolean, prominent: boolean) => uiMaterial.ImmersiveMaterial) | null = null
let loading: Promise<boolean> | null = null

export function supportsImmersiveMaterial(): boolean {
  try { return checkSupport !== null && checkSupport() } catch (_error) { return false }
}
export function loadImmersiveMaterial(): Promise<boolean> {
  const rawApi = deviceInfo.sdkApiVersion
  // 与 LiveViewService 的 apiLevel 保持同一套规则：编码形态 6.1.0(23) -> 60100023，
  // 门槛必须低于该量级，否则八位编码会原样参与比较而把所有版本判断顶成真。
  if (!Number.isInteger(rawApi) || rawApi <= 0) return Promise.resolve(false)
  const api = rawApi >= 10000000 ? rawApi % 1000 : rawApi
  if (!Number.isInteger(api) || api < 26) return Promise.resolve(false)
  if (checkSupport !== null) return Promise.resolve(supportsImmersiveMaterial())
  if (loading !== null) return loading
  loading = import('./NativeMaterials').then((adapter) => {
    checkSupport = adapter.supportsNativeMaterial
    createMaterial = adapter.createNativeMaterial
    return supportsImmersiveMaterial()
  }).catch((): boolean => false).finally(() => { loading = null })
  return loading
}
export function glassMaterial(isDark: boolean, interactive: boolean = false,
  prominent: boolean = false): uiMaterial.ImmersiveMaterial {
  if (createMaterial === null) throw new Error('Native material not loaded')
  return createMaterial(isDark, interactive, prominent)
}
