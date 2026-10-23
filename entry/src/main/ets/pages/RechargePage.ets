import { DetailScaffold } from '../components/common/DetailScaffold'
import { PageState } from '../components/common/PageState'
import { RefreshNotice } from '../components/common/RefreshNotice'
import { CampusCard } from '../components/common/CampusCard'
import { getCacheEpoch } from '../services/MemoryCache'
import { getColors } from '../theme/Colors'
import { safeBack } from '../utils/RouterHelper'
import { safeToast } from '../utils/ToastHelper'
import webview from '@ohos.web.webview'
import util from '@ohos.util'
import common from '@ohos.app.ability.common'
import { BusinessError } from '@kit.BasicServicesKit'
import { callFeature, CallResult } from '../services/ApiService'
import { getUsername } from '../services/AuthManager'
import { AmountOption, PayMethod, RechargeOrderResult } from '../models/CardTypes'
import { Motion, motionDuration } from '../theme/Motion'

/**
 * 收银台 H5 里点微信/支付宝，浏览器内核只会当成"打不开的链接"，
 * 必须由我们自己交给系统。这里只放行已知的支付 scheme——收银台地址由服务端
 * 返回，若响应被污染，白名单之外的一切都应留在 Web 内，绝不能交给系统去
 * 启动任意应用。http/https/data/about/javascript/blob/file 一律留在 Web 内。
 */
const PAYMENT_SCHEMES: string[] = ['weixin://', 'weixinurl://', 'alipays://', 'alipay://',
  'unionpay://', 'uppay://', 'upwallet://']

function isExternalScheme(url: string): boolean {
  const lower: string = url.trim().toLowerCase()
  if (lower.length === 0) return false
  for (let i = 0; i < PAYMENT_SCHEMES.length; i++) {
    if (lower.startsWith(PAYMENT_SCHEMES[i])) return true
  }
  return false
}

function schemeAppName(url: string): string {
  const lower: string = url.toLowerCase()
  if (lower.indexOf('alipay') >= 0) return '支付宝'
  if (lower.indexOf('weixin') >= 0 || lower.indexOf('wechat') >= 0) return '微信'
  if (lower.indexOf('unionpay') >= 0 || lower.indexOf('uppay') >= 0) return '云闪付'
  return '支付应用'
}

@Entry
@Component
struct RechargePage {
  @StorageLink('safeAreaTop') safeAreaTop: number = 0
  @StorageLink('safeAreaBottom') safeAreaBottom: number = 0
  @StorageLink('isDark') isDark: boolean = false
  @State step: number = 1
  @State balance: string = ''
  @State amountOptions: AmountOption[] = []
  @State payMethods: PayMethod[] = []
  @State selectedAmount: string = ''
  @State selectedPayCode: string = ''
  @State loading: boolean = true
  @State paying: boolean = false
  @State errorMsg: string = ''
  @State payContent: string = ''
  @State payContentType: 'url' | 'html' = 'url'
  @State payError: string = ''
  private alive: boolean = false
  private configVersion: number = 0
  private webController: webview.WebviewController = new webview.WebviewController()

  private htmlToDataUrl(html: string): string {
    try {
      const enc = new util.TextEncoder()
      const helper = new util.Base64Helper()
      const b64 = helper.encodeToStringSync(enc.encodeInto(html))
      return 'data:text/html;base64,' + b64
    } catch (_e) {
      return ''
    }
  }

  aboutToAppear(): void { this.alive = true; this.loadConfig() }
  aboutToDisappear(): void { this.alive = false; this.configVersion++; this.loading = false }
  async loadConfig(force: boolean = false): Promise<void> {
    if (!this.alive || this.loading && this.configVersion > 0 || this.paying) return
    this.loading = true
    this.errorMsg = ''
    const version = ++this.configVersion
    const epoch = getCacheEpoch()
    const username = getUsername()
    try {
      const res = await callFeature('newcard.recharge.config', username, { '_forceRefresh': force })
      if (!this.alive || version !== this.configVersion || epoch !== getCacheEpoch() || username !== getUsername()) return
      if (res.ok) {
        const d = res.data
        this.balance = typeof d['balance'] === 'string' ? d['balance'] as string : ''
        this.amountOptions = Array.isArray(d['amountOptions']) ? d['amountOptions'] as AmountOption[] : []
        this.payMethods = Array.isArray(d['payMethods']) ? d['payMethods'] as PayMethod[] : []
        if (!this.amountOptions.some((opt: AmountOption): boolean => opt.amount === this.selectedAmount)) this.selectedAmount = ''
        if (!this.payMethods.some((m: PayMethod): boolean => m.code === this.selectedPayCode)) this.selectedPayCode = ''
      } else { this.errorMsg = res.error || '充值信息暂不可用' }
    } catch (_error) {
      if (this.alive && version === this.configVersion && epoch === getCacheEpoch() && username === getUsername()) this.errorMsg = '连接未完成，请稍后重试'
    } finally {
      if (this.alive && version === this.configVersion) this.loading = false
    }
  }

  async handlePay(): Promise<void> {
    if (this.paying || !this.alive || this.loading || this.selectedAmount.length === 0 || this.selectedPayCode.length === 0) return
    // 服务端契约要求金额大于 0 且最多两位小数。档位来自服务端配置，
    // 配置异常时不能把非法金额直接发出去。
    if (!/^\d+(\.\d{1,2})?$/.test(this.selectedAmount) || Number(this.selectedAmount) <= 0) {
      this.payError = '充值金额无效，请重新选择'
      return
    }
    this.paying = true
    this.payError = ''
    const params: Record<string, Object> = {
      'amount': this.selectedAmount,
      'payCode': this.selectedPayCode,
      'tradeType': 'WAP',
    }
    const epoch = getCacheEpoch()
    const username = getUsername()
    try {
    const res: CallResult = await callFeature('newcard.recharge.create_order', username, params)
    if (!this.alive || epoch !== getCacheEpoch() || username !== getUsername()) return
    if (res.ok) {
      const order: RechargeOrderResult = res.data as Object as RechargeOrderResult
      // 订单可能已在服务端创建成功，只是漏发 payResult。此处必须给出与网络
      // 失败不同的说法，否则用户会重复下单。
      if (!order.payResult) {
        this.payError = '订单已创建，但响应缺少支付入口字段，请到一卡通账户查询后再决定是否重试'
        safeToast(this.getUIContext(), '订单已创建，请先到一卡通账户查询结果')
        return
      }
      if (order.payResult.htmlPost && order.payResult.htmlPost.length > 0) {
        const dataUrl: string = this.htmlToDataUrl(order.payResult.htmlPost)
        if (dataUrl.length > 0) {
          this.payContent = dataUrl
          this.payContentType = 'html'
          this.step = 3
        } else {
          safeToast(this.getUIContext(), '支付页面打开失败，请稍后重试')
        }
      } else if (order.payResult.officialTransferUrl && order.payResult.officialTransferUrl.length > 0) {
        this.payContent = order.payResult.officialTransferUrl
        this.payContentType = 'url'
        this.step = 3
      } else if (order.payResult.h5Url && order.payResult.h5Url.length > 0) {
        this.payContent = order.payResult.h5Url
        this.payContentType = 'url'
        this.step = 3
      } else {
        this.payError = '订单已创建，但服务端没有返回支付入口，请到一卡通账户查询结果'
        safeToast(this.getUIContext(), '订单已创建，请到一卡通账户查询充值结果')
      }
    } else {
      this.payError = res.error
      safeToast(this.getUIContext(), res.error)
    }
    } catch (_error) {
      if (this.alive && epoch === getCacheEpoch() && username === getUsername()) {
        this.payError = '支付请求未完成，请先查询充值结果再尝试'
        safeToast(this.getUIContext(), '支付请求未完成，请先查询充值结果再尝试')
      }
    } finally { this.paying = false }
  }

  cancelPay(): void {
    this.payContent = ''
    this.step = 1
  }

  /** 把 weixin:// alipays:// 交给系统；跳不起来说明设备上没装对应应用，给出准确名字 */
  private openExternalScheme(url: string): void {
    const host = this.getUIContext().getHostContext()
    const ctx: common.UIAbilityContext | undefined = host as common.UIAbilityContext
    if (!ctx) {
      safeToast(this.getUIContext(), '支付跳转未就绪，请重试')
      return
    }
    const appName: string = schemeAppName(url)
    ctx.startAbility({ uri: url }, (err: BusinessError): void => {
      if (!err || err.code === undefined || err.code === 0) return
      if (!this.alive) return
      safeToast(this.getUIContext(), '未安装' + appName + '，无法跳转完成支付')
    })
  }

  build() {
    Stack() {
      DetailScaffold({ title: this.step === 3 ? '正在支付' : '一卡通充值', subtitle: '选择金额与支付方式',
        action: this.step === 3 ? '取消支付' : '刷新', actionGlyph: this.step === 3 ? '×' : '',
        busy: this.loading || this.paying,
        onBack: () => { if (this.step === 3) this.cancelPay(); else safeBack(this.getUIContext()) },
        onAction: () => { if (this.step === 3) this.cancelPay(); else this.loadConfig(true) } }) {
        if (this.step === 3) {
          Web({ src: this.payContent, controller: this.webController }).width('100%').layoutWeight(1)
            .onLoadIntercept((event: OnLoadInterceptEvent): boolean => {
              const target: string = event.data.getRequestUrl()
              if (!isExternalScheme(target)) return false
              this.openExternalScheme(target)
              return true
            })
            // 收银台从右侧滑入、同时淡入，形成"换了一屏"的方向感——直接硬切会让
            // 用户在输密码前不知道界面变了。进场用减速曲线（快入慢停），出场用加速
            // 曲线，符合"东西被推着走"的直觉。减少动效偏好下两段时长都为 0。
            .transition(TransitionEffect.asymmetric(
              TransitionEffect.OPACITY.combine(TransitionEffect.translate({ x: 72 }))
                .animation({ duration: motionDuration(Motion.duration.base), curve: Motion.curve.decelerate }),
              TransitionEffect.OPACITY
                .animation({ duration: motionDuration(Motion.duration.fast), curve: Motion.curve.accelerate })
            ))
        } else if (this.loading && this.amountOptions.length === 0) {
          PageState({ kind: 'loading', title: '正在获取充值信息', message: '正在同步金额与支付方式' })
        } else if (this.errorMsg.length > 0 && this.amountOptions.length === 0) {
          PageState({ kind: 'error', schoolFeature: 'newcard.recharge.config', title: '充值信息暂不可用', message: this.errorMsg, action: '重新加载', onAction: () => this.loadConfig(true) })
        } else if (this.amountOptions.length === 0 || this.payMethods.length === 0) {
          PageState({ title: '暂无可用的充值方式', message: '请稍后刷新，或前往校园一卡通服务点', action: '刷新看看', onAction: () => this.loadConfig(true) })
        } else {
          if (this.errorMsg.length > 0) RefreshNotice({ message: '更新失败，已保留上次充值信息', busy: this.loading, onRetry: () => this.loadConfig(true) })
          Scroll() {
            Column({ space: 24 }) {
              CampusCard({ contentPadding: 22 }) {
                Column({ space: 8 }) {
                  Text('校园卡余额').fontSize(14).fontColor(getColors(this.isDark).onSurfaceVariant)
                  Text('¥ ' + this.balance).fontSize(36).fontWeight(FontWeight.Bold).fontColor(getColors(this.isDark).onSurface)
                }.width('100%').alignItems(HorizontalAlign.Start)
              }
              Column({ space: 12 }) {
                Text('选择充值金额').fontSize(17).fontWeight(FontWeight.Bold).fontColor(getColors(this.isDark).onSurface)
                Flex({ wrap: FlexWrap.Wrap }) {
                  ForEach(this.amountOptions, (opt: AmountOption) => {
                    Button(opt.name).height(48).constraintSize({ minWidth: 88 }).margin({ right: 8, bottom: 8 }).borderRadius(16)
                      .backgroundColor(this.selectedAmount === opt.amount ? getColors(this.isDark).primary : getColors(this.isDark).surfaceVariant)
                      .fontColor(this.selectedAmount === opt.amount ? getColors(this.isDark).onPrimary : getColors(this.isDark).onSurface)
                      .onClick(() => { this.selectedAmount = opt.amount })
                  }, (opt: AmountOption): string => opt.id)
                }.width('100%')
              }.width('100%').alignItems(HorizontalAlign.Start)
              CampusCard({ contentPadding: 18 }) {
                Column({ space: 8 }) {
                  Text('选择支付方式').fontSize(17).fontWeight(FontWeight.Bold).fontColor(getColors(this.isDark).onSurface).width('100%')
                  ForEach(this.payMethods, (m: PayMethod) => {
                    Row({ space: 10 }) {
                      Radio({ value: m.code, group: 'pay' }).checked(this.selectedPayCode === m.code)
                        .onChange((checked: boolean) => { if (checked) this.selectedPayCode = m.code })
                      Text(m.name).fontSize(16).fontColor(getColors(this.isDark).onSurface).layoutWeight(1)
                    }.width('100%').constraintSize({ minHeight: 48 }).onClick(() => { this.selectedPayCode = m.code })
                  }, (m: PayMethod): string => m.code)
                }.width('100%')
              }
              if (this.payError.length > 0) {
                Text(this.payError).fontSize(13).lineHeight(20).fontColor(getColors(this.isDark).error)
                  .width('100%').textAlign(TextAlign.Center).padding({ left: 4, right: 4 })
              }
              Button(this.paying ? '正在支付…' : (this.selectedAmount.length > 0 ? '支付 ¥' + this.selectedAmount : '请选择金额'))
                .width('100%').height(52).borderRadius(18).fontSize(16).fontWeight(FontWeight.Medium)
                .backgroundColor(getColors(this.isDark).primary).fontColor(getColors(this.isDark).onPrimary)
                .enabled(this.selectedAmount.length > 0 && this.selectedPayCode.length > 0 && !this.paying && !this.loading)
                .onClick(() => this.handlePay())
            }.width('100%').padding({ left: 20, right: 20, top: 12, bottom: 28 })
          }.layoutWeight(1).width('100%').align(Alignment.Top).scrollBar(BarState.Off)
            // 金额页退场时轻微缩小并淡出，让收银台的滑入有"从上面压过来"的层次；
            // 只有进场给淡入，避免返回时和收银台出场动画互相抢。
            .transition(TransitionEffect.asymmetric(
              TransitionEffect.OPACITY.animation({ duration: motionDuration(Motion.duration.fast) }),
              TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.97, y: 0.97 }))
                .animation({ duration: motionDuration(Motion.duration.base), curve: Motion.curve.accelerate })
            ))
        }
      }
    }.width('100%').height('100%')
  }

  // 统一页面过渡：前进时新页右侧 30% 淡入、底层静止；返回时镜像右出淡出。
  // 减少动效偏好下时长为 0（同时禁用设备默认页面动画，保持瞬时切换）。
  pageTransition(): void {
    PageTransitionEnter({ type: RouteType.Push, duration: motionDuration(Motion.duration.base), curve: Motion.curve.decelerate })
      .translate({ x: motionDuration(Motion.duration.base) > 0 ? '30%' : '0%' }).opacity(motionDuration(Motion.duration.base) > 0 ? 0 : 1)
    PageTransitionExit({ type: RouteType.Push, duration: motionDuration(Motion.duration.base) })
    PageTransitionEnter({ type: RouteType.Pop, duration: motionDuration(Motion.duration.base) })
    PageTransitionExit({ type: RouteType.Pop, duration: motionDuration(Motion.duration.base), curve: Motion.curve.accelerate })
      .translate({ x: motionDuration(Motion.duration.base) > 0 ? '30%' : '0%' }).opacity(motionDuration(Motion.duration.base) > 0 ? 0 : 1)
  }

}
