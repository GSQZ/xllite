# 原生玻璃材质接入

应用：掌上新理工（`com.xjit.app`）。本文说明 HarmonyOS 沉浸玻璃材质的接入方式、能力检测与回退路径。

## 入口与结构

入口链路为 `EntryAbility → LoginPage → MainTabs`，底部导航为「首页 / 课表 / 我的」。

`entry/src/main/ets/components/Materials.ets` 与 `NativeGlass.ets` 使用 `@ohos.arkui.uiMaterial` 的 `ImmersiveMaterial` 与 `systemMaterial` 构建材质表面。

## 接入约束

材质节点本身不叠加自绘模糊、描边或阴影。这与 `backgroundEffect` 系列 API 的分工一致：`uiMaterial` 负责系统级材质，`backdropBlur` / `backgroundBlurStyle` 只暴露半径参数，不能用来模拟玻璃。

回退路径上的 `backgroundEffect` 则由 `backgroundEffect` 自身承担模糊与饱和度，材质节点仍然不叠加自绘模糊。

底部导航的主题渐变衬底是独立节点，并且不截获触摸事件，避免遮挡导航点击区域。

## 能力检测与回退

运行时读取 `deviceInfo.sdkApiVersion` 判断设备是否支持 `uiMaterial`。该字段存在两种编码：`"60100023"` 与 `"23"`，统一按 `raw >= 100000000 ? raw % 1000 : raw` 归一化后再比较。

检测同时覆盖设备支持状态与 `DISABLE` 状态。任一条件不满足时回退为普通表面，界面结构与交互不变，仅材质效果降级。

### 沉浸光感在 HarmonyOS 6.0 的实现路径

| 能力 | 起始版本 | 说明 |
| --- | --- | --- |
| `uiMaterial.ImmersiveMaterial` + `systemMaterial` | API 26（HarmonyOS 7.0） | 原生沉浸材质，折射窗口后方真实场景 |
| `backgroundEffect`（含 `saturation`） | API 11 | ArkUI 背景特效，低版本唯一的光感模糊通道 |
| `SystemAdaptiveOptions` | API 19 | 允许系统按算力与负载自动降级特效 |

`uiMaterial` 整包标注 `@since 26.0.0`，HarmonyOS 6.0 走不到；本机 SDK 也没有环境光传感器 API。因此 6.0 及以下的"沉浸光感"只能由 ArkUI `backgroundEffect` 承担。

分界点是 `saturation`（取值 `[0,+∞)`，推荐 `[0,50]`，默认 1）：**`saturation > 1` 才是玻璃与灰模糊的区别**——它把透过的颜色推向更高饱和度；纯 `backdropBlur` / `backgroundBlurStyle` 只暴露半径参数，透过去是灰的。

- `saturation`：深色 1.5 / 浅色 1.9；强调卡 1.7 / 2.1。
- `brightness`：固定 1.0。实测调高会远超线性地把卡片提亮成白纸，实体感应来自 `color` 的 alpha 而非亮度。
- `adaptiveColor`：必须用 `AdaptiveColor.DEFAULT`。`AVERAGE` 会把遮罩色换成内容区平均色，卡片与背景收敛、边缘消失。
- 前提是玻璃背后必须有色彩层次：`AmbientBackground` 用靛蓝 `#315EDA` / 青 `#12B5C9` / 紫 `#7B5CE6` 三团 radialGradient 光晕，模糊纯色等于没有效果。

### 降级路径实测（API 26 模拟器，浅色模式）

在模拟器上把材质门槛临时放开，使 `backgroundEffect` 分支生效，再对首页同一张玻璃卡采样（`backgroundEffect` 自 API 11 起提供，渲染行为与 API 23 设备一致）：

| 变体 | 卡内 luma 均值 | 卡外 luma 均值 | 卡/背比值 | 垂直边界剖面 |
| --- | --- | --- | --- | --- |
| `DEFAULT` + saturation 1.5 | 245.8 | 228.3 | **1.076** | 245.7 → 244.7，存在台阶 |
| `AVERAGE` + saturation 1.5 | 219.5 | 213.6 | 1.027 | 215.3 → 215.3，完全平坦 |
| `DEFAULT` + saturation 2.2 | 244.9 | 228.2 | **1.073** | 244.8 → 243.9，存在台阶 |
| `AVERAGE` + saturation 2.2 | 219.3 | 213.7 | 1.026 | 215.2 → 215.2，完全平坦 |

结论：`AVERAGE` 下卡片与背景收敛为同一亮度、边界台阶消失；`DEFAULT` 保留可辨识的边界。提高 `saturation` 在浅色模式下对比度几乎不变（1.076 → 1.073），说明饱和度影响的是色彩鲜艳度而非明暗分离，卡片是否"看得见"由 `adaptiveColor` 决定。

深色模式尚未取得样本，模拟器的深色开关不可写。

`backgroundEffect` 每帧实时渲染，功耗较高；内容静止时应改用静态 `effectKit.Filter.blur`。

## 运行状态

在 API 26 模拟器上读取到的材质状态为 `supported=true`、`level=0`（`EXQUISITE`）、`state=0`（`DEFAULT`）。这证明 API 分支可以正常进入并返回有效材质等级。

## 未验收项

模拟器渲染出的高光与折射强度明显弱于预期，液态玻璃的视觉效果需要支持该材质能力的鸿蒙真机确认。FPS 与功耗均未测量。历史 `.preview` 图与构建成功记录不作为视觉效果证据。

## 相关文档

- 系统功能（课表卡片、课程提醒、实况窗）的实现见 [系统功能实施报告](CAMPUS-COMPANION.md)。
- 设备侧验收门槛见 [API23 设备验收门槛](API23-DEVICE-GATE.md)。
