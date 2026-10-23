# 校园卡支付 payCode 契约核对

2026-10-19，仅核对本地代码与 XLLite 在线 feature detail/OpenAPI，不发起真实下单，不新增未证实的 SDK 接入代码。

## 结论：契约已齐，无需接入微信/支付宝 SDK

校园卡充值（`newcard.recharge.create_order`）走 XLLite 网关统一 `/api/v1/run`，服务端完成下单后返回支付入口（`payResult`），App 侧只需在 WebView 里加载 `h5Url` 或提交 `htmlPost`，不需要端侧集成微信/支付宝 SDK 或 JSAPI 签名调用。

## payCode 枚举（依据）

| code | 渠道 | 来源 |
| --- | --- | --- |
| 01 | 支付宝 | 在线 feature detail `newcard.recharge.config`/`create_order` 示例；学校原生 JS 按 code 分支注入 `daLianPayInfo.aliWeb.htmlPost` |
| 02 | 微信 | 同上；原生 JS 按 tradeType 走 `wechatJsapi`/`wechatH5.webUrl`/`wechatApplet` |
| 06 | 一卡通余额 | 电费页默认 payCode，原生 JS 走余额支付分支 |
| 07 | 余额兜底 | 电费页 `daLianPayEnable=false` 时回退码 |
| 14 | 农行 abcPay | 原生 JS 特殊分支 |
| CCBAP / ICBCH5 | 建行渠道 | 原生 JS 分支 |

`RechargePage.ets` 不硬编码任何 payCode 数值：从 `newcard.recharge.config` 拉到的 `payMethods[].code` 动态渲染选项，下单时回传 `selectedPayCode`，与网关/原生契约一致。

## 已核对的代码文件

- `entry/src/main/ets/pages/RechargePage.ets`：config → 选金额/支付方式 → create_order → 按以下优先级取支付入口，命中即进入 WebView：
  1. `payResult.htmlPost` 转 dataUrl 内联渲染（html）；
  2. `payResult.officialTransferUrl` 直接加载（url）；
  3. `payResult.h5Url` 直接加载（url）。

  三者都没有时如实提示"订单已创建，但服务端没有返回支付入口"，并引导到一卡通账户查询——不能当成功，也不能当失败让用户重下单。`htmlPost` 排在最前是因为它把整段表单内联，不受外部页面可达性影响。
- `entry/src/main/ets/pages/QRCodePage.ets`：只消费 `newcard.campus_code.qrcode`，生成付款码，与充值下单契约无重叠，本次无改动。
- `entry/src/main/ets/services/ApiService.ets`：网关会话下所有业务（含 create_order）经 `gatewayRun` 走 `/api/v1/run`；仅 `jw.schedule`/`jw.profile`/`jw.grades`/`jw.exams`/`jw.training`/`newcard.balance`/`newcard.transactions`/`newcard.electricity.account` 走读缓存。
- `entry/src/main/ets/services/XlliteGateway.ets`：`GATEWAY_FEATURE_NAMES` 覆盖 13 个 feature，含 `newcard.recharge.config`/`create_order`。`gatewayRun` 对六项业务校验 `data` 里的集合字段（`jw.schedule`→`courses`、`jw.grades`→`normalGrades`、`jw.exams`→`exams`、`jw.training`→`training`、`newcard.balance`→`accounts`、`newcard.transactions`→`transactions`）；充值下单与电费缴费这两个支付入口不校验集合，但**单独校验 `payResult` 必须是对象**——漏发时订单往往已在服务端创建成功，当成成功继续走会在空对象上取属性、被通用 catch 吞成"网络失败"，用户看不出订单已存在，很可能重复下单。

## 文档缺口（已补齐）

`docs/SCHOOL-NATIVE-API.md` 仅标记 `newcard.recharge.create_order`「尚未实施」，未沉淀 payCode 枚举与网关契约。本次核对补入本文件。

create_order 返回支付入口，下单不等于支付成功，与本文一致。

## 后续条件

- 若真实运行发现 `payResult` 的 `h5Url`/`htmlPost` 缺省或格式变化（例如服务端改走 `officialTransferUrl` 或 `daLianPayInfo` 新字段），需先取回服务端契约证据再调整页面加载逻辑，不预先补未证实分支。
- 若要在 App 内闭环微信 JSAPI 支付（不跳 WebView），需服务端先提供 JSAPI 签名（`wechatJsapi` 完整字段）及 App 侧可用的调起通道；当前网关响应示例里 `wechatJsapi` 为 null，尚无该能力契约，暂不实现。

## 2026-10-20 模拟器实测：链路通，受充值营业时间限制

在 `com.xjit.app.acceptance` 上走通了「充值页 → 选金额/支付方式 → 点支付」的完整端侧路径，实测证据：

- `newcard.recharge.config` 正常返回，页面上渲染出 `01 支付宝`、`02 微信` 两个选项，`payMethods` 动态渲染链路成立。
- 点「支付 ¥50」后按钮进入「正在支付…」，`POST` 到网关 `/api/v1/run` 实际发出，`LogHttpInfo` 记录 `response_code: 400`、`total_time` 约 1–2.4 秒。
- 服务端 400 的业务文案为 **「充值开放时间为每日 01:30-23:30 请稍后再试」**。实测时刻为 23:38，在关闭窗口内，因此**下单被拒是营业时间所致，不是契约不符或端侧缺陷**。
- 结论：端侧支付的发送链路已通，`payResult` 与 Web 收银台需要**在 01:30–23:30 窗口内**才能验证。尚未取得任何 `payResult` 实测样本，故不声称微信/支付宝已能被调起。

同一轮补的两处端侧缺陷（与营业时间无关、独立成立）：

- `RechargePage.ets` 的 `Web` 组件缺少 `onLoadIntercept`。收银台 H5 里点微信/支付宝产生 `weixin://`、`alipays://` 等 scheme 时，Web 内核只会当成打不开的链接，不会交给系统，表现为点了没反应。现已按 `isExternalScheme` 判定、`startAbility({ uri })` 交给系统，跳不起来时提示缺哪个应用。
- 支付失败原因原先只有一闪而过的 Toast。现落盘到 `payError` 并在支付按钮上方常显，用户能读到服务端原话（本次正是靠它才看清「01:30-23:30」这条规则）。
