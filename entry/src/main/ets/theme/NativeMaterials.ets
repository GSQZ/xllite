import uiMaterial from '@ohos.arkui.uiMaterial'
import hilog from '@ohos.hilog'

/**
 * 原生沉浸材质（API 26 / HarmonyOS 7.0 及以上）。
 *
 * 两条经验，都是踩出来的：
 *
 * 1. 档位决定"透不透"。`ImmersiveStyle` 从 `ULTRA_THIN`(0) 到 `ULTRA_THICK`(4)
 *    是一根由透到实的轴，`THICK` 基本就是一层面板。悬浮在内容之上的栏要看清
 *    背后的东西，必须用薄档；实体卡片才用 `REGULAR`。之前两者都传 `THICK`，
 *    材质读出来是一块白板，跟"玻璃"没有关系。
 * 2. `materialColor` 的默认值是 `Color.Transparent`，也就是"不要额外叠色，全部
 *    交给材质本身"。手动填一个半透明白会在这层玻璃上再盖一层白，越叠越实，
 *    直接把折射糊掉。只在需要压暗/提亮时才给极低的 alpha。
 */
const materials: Map<string, uiMaterial.ImmersiveMaterial> = new Map<string, uiMaterial.ImmersiveMaterial>()

export function supportsNativeMaterial(): boolean {
  return uiMaterial.isImmersiveMaterialSupported() && uiMaterial.getMaterialInfo().state !== uiMaterial.MaterialState.DISABLE
}

export function createNativeMaterial(isDark: boolean, interactive: boolean, prominent: boolean): uiMaterial.ImmersiveMaterial {
  const key = String(isDark) + String(interactive) + String(prominent)
  const cached = materials.get(key)
  if (cached !== undefined) return cached
  const material = new uiMaterial.ImmersiveMaterial({
    // 悬浮栏（prominent）用 THIN 保透明；实体卡片用 REGULAR。
    style: prominent ? uiMaterial.ImmersiveStyle.THIN : uiMaterial.ImmersiveStyle.REGULAR,
    // 不额外叠色：让折射出来的画面自己说话。深色主题给一丝压暗，
    // 否则浅色内容从栏底下经过时字会发飘。用 ARGB 字面量而不写 Color.Transparent，
    // 是为了让这段逻辑在 Node 侧的回归里也能直接跑（那边没有 ArkUI 全局枚举）。
    materialColor: isDark ? '#0A000000' : '#00000000',
    applyShadow: true,
    interactive: interactive,
    lightEffect: { color: isDark ? '#66A9C4FF' : '#B3FFFFFF' },
  })
  materials.set(key, material)
  hilog.info(0x0000, 'XJITMaterial', 'Native material created style=%{public}d prominent=%{public}s',
    prominent ? uiMaterial.ImmersiveStyle.THIN : uiMaterial.ImmersiveStyle.REGULAR, String(prominent))
  return material
}
