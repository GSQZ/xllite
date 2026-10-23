import { DetailHeader } from '../components/common/DetailHeader'
import { AmbientBackground } from '../components/AmbientBackground'
import { ThemeWash } from '../components/common/ThemeWash'
import { getCacheEpoch } from '../services/MemoryCache'
import { getColors } from '../theme/Colors'
import { safeBack } from '../utils/RouterHelper'
import { callFeature, CallResult } from '../services/ApiService'
import { getUsername, loadElectricityRoom, saveElectricityRoom } from '../services/AuthManager'
import { ElectricityAccount, ElecRechargeConfig, ElecRechargePayResult, AmountOption, PayMethod } from '../models/CardTypes'
import { Motion, motionDuration } from '../theme/Motion'

@Entry
@Component
struct ElectricityPage {
  @StorageLink('safeAreaTop') safeAreaTop: number = 0
  @StorageLink('safeAreaBottom') safeAreaBottom: number = 0
  @StorageLink('isDark') isDark: boolean = false
  private alive: boolean = false
  private requestVersion: number = 0
  async aboutToAppear(): Promise<void> {
    this.alive = true
    const version = ++this.requestVersion
    const epoch = getCacheEpoch()
    const username = getUsername()
    try {
      const room = await loadElectricityRoom()
      if (!this.alive || version !== this.requestVersion || epoch !== getCacheEpoch() || username !== getUsername()) return
      if (this.roomQuery.length === 0 && room.length > 0) {
        this.roomQuery = room
        await this.queryElectricity()
      }
    } catch (_error) {
      if (this.alive && version === this.requestVersion && epoch === getCacheEpoch() && username === getUsername()) {
        this.errorMsg = '宿舍绑定读取失败，请重新查询'
      }
    }
  }
  aboutToDisappear(): void { this.alive = false; this.requestVersion++; this.loading = false; this.paymentPassword = '' }
  @State step: number = 1
  @State roomQuery: string = ''
  @State electricity: ElectricityAccount | null = null
  @State rechargeConfig: ElecRechargeConfig | null = null
  @State selectedAmount: string = ''
  @State selectedPayCode: string = ''
  @State paymentPassword: string = ''
  @State showPasswordInput: boolean = false
  @State loading: boolean = false
  @State paying: boolean = false
  @State errorMsg: string = ''
  @State resultMsg: string = ''

  async queryElectricity(): Promise<void> {
    if (!this.alive || this.loading || this.paying) return
    if (this.roomQuery.trim().length === 0) {
      this.errorMsg = '请输入宿舍号'
      return
    }
    this.loading = true
    this.errorMsg = ''
    const params: Record<string, Object> = { 'roomQuery': this.roomQuery.trim() }
    const version = ++this.requestVersion
    const epoch = getCacheEpoch()
    const username = getUsername()
    try {
    const res: CallResult = await callFeature('newcard.electricity.account', username, params)
    if (!this.alive || version !== this.requestVersion || epoch !== getCacheEpoch() || username !== getUsername()) return
    if (res.ok) {
      this.electricity = res.data as Object as ElectricityAccount
      this.step = 2
      // 保存宿舍号是「记住上次输入」的便利功能，失败不影响本次查询结果，
      // 但要让用户知道下次还得重输，而不是默默当作已记住。
      try {
        const saved: boolean = await saveElectricityRoom(params['roomQuery'] as string)
        if (!saved && this.alive && version === this.requestVersion && epoch === getCacheEpoch() && username === getUsername()) {
          this.errorMsg = '电量已查询，宿舍绑定未保存，请稍后重新查询'
        }
      } catch (_error) {
        if (this.alive && version === this.requestVersion && epoch === getCacheEpoch() && username === getUsername()) {
          this.errorMsg = '电量已查询，宿舍绑定未保存，请稍后重新查询'
        }
      }
    } else {
      this.errorMsg = res.error
    }
    } catch (_error) {
      if (this.alive && version === this.requestVersion && epoch === getCacheEpoch() && username === getUsername()) {
        this.errorMsg = '连接未完成，请稍后重试'
      }
    } finally { if (this.alive && version === this.requestVersion) this.loading = false }
  }
  async loadRechargeConfig(): Promise<void> {
    if (!this.alive || this.loading || this.paying) return
    this.loading = true
    this.errorMsg = ''
    const params: Record<string, Object> = { 'roomQuery': this.roomQuery.trim() }
    const version = ++this.requestVersion
    const epoch = getCacheEpoch()
    const username = getUsername()
    try {
    const res: CallResult = await callFeature('newcard.electricity.recharge.config', username, params)
    if (!this.alive || version !== this.requestVersion || epoch !== getCacheEpoch() || username !== getUsername()) return
    if (res.ok) {
      this.rechargeConfig = res.data as Object as ElecRechargeConfig
      this.showPasswordInput = this.rechargeConfig.needPaymentPassword
      this.step = 3
    } else {
      this.errorMsg = res.error
    }
    } catch (_error) {
      if (this.alive && version === this.requestVersion && epoch === getCacheEpoch() && username === getUsername()) {
        this.errorMsg = '连接未完成，请稍后重试'
      }
    } finally { if (this.alive && version === this.requestVersion) this.loading = false }
  }
  async handlePay(): Promise<void> {
    if (!this.alive || this.loading || this.paying) return
    if (this.selectedAmount.length === 0) return
    if (this.showPasswordInput && this.paymentPassword.length === 0) {
      this.errorMsg = '请输入支付密码'
      return
    }
    this.paying = true
    this.errorMsg = ''
    const params: Record<string, Object> = {
      'roomQuery': this.roomQuery.trim(),
      'amount': this.selectedAmount,
      'payCode': this.selectedPayCode.length > 0 ? this.selectedPayCode : '06',
    }
    if (this.showPasswordInput) {
      params['paymentPassword'] = this.paymentPassword
    }
    const version = ++this.requestVersion
    const epoch = getCacheEpoch()
    const username = getUsername()
    try {
    const res: CallResult = await callFeature('newcard.electricity.recharge.pay', username, params)
    if (!this.alive || version !== this.requestVersion || epoch !== getCacheEpoch() || username !== getUsername()) return
    if (res.ok) {
      const order: ElecRechargePayResult = res.data as Object as ElecRechargePayResult
      // res.ok only proves the gateway accepted the order. The balance moves on the
      // campus-card side and there is no order-status endpoint to confirm it, so
      // reporting "充值成功" here would fabricate a payment result.
      const paid = typeof order.amount === 'string' && order.amount.trim().length > 0
        ? Number(order.amount) : Number(this.selectedAmount)
      this.resultMsg = '支付请求已提交' + (Number.isFinite(paid) && paid > 0 ? '，金额 ¥' + paid.toFixed(2) : '') +
        '。请到一卡通账户核对到账结果'
      this.step = 4
    } else {
      this.errorMsg = res.error
    }
    } catch (_error) {
      if (this.alive && version === this.requestVersion && epoch === getCacheEpoch() && username === getUsername()) {
        this.errorMsg = '支付请求未完成，请先查询电量与交易结果再尝试'
      }
    } finally { if (this.alive && version === this.requestVersion) this.paying = false }
  }
  changeRoom(): void {
    if (this.paying) return
    this.requestVersion++
    this.loading = false
    this.step = 1
    this.electricity = null
    this.rechargeConfig = null
    this.selectedAmount = ''
    this.selectedPayCode = ''
    this.paymentPassword = ''
    this.errorMsg = ''
  }
  back(): void {
    if (this.paying) return
    this.requestVersion++
    this.loading = false
    if (this.step === 1) {
      safeBack(this.getUIContext())
    } else if (this.step === 2) {
      this.step = 1
      this.electricity = null
    } else if (this.step === 3) {
      this.step = 2
      this.rechargeConfig = null
      this.selectedAmount = ''
      this.selectedPayCode = ''
      this.paymentPassword = ''
    } else if (this.step === 4) {
      safeBack(this.getUIContext())
    }
  }

  build() {
    Stack() {
      AmbientBackground()
      Column() {
        DetailHeader({ title: this.step === 4 ? '支付已提交' : '电费服务', subtitle: '查询宿舍电量与充值', action: '',
          showBack: true, onBack: () => this.back(), onAction: () => {} })
        Scroll() {
          Column() {
      if (this.step === 1) {
        Column() {
          Text('输入宿舍号').fontColor(getColors(this.isDark).onSurface).fontSize(15).margin({ top: 24, bottom: 12 }).alignSelf(ItemAlign.Start).width('90%')
          TextInput({ placeholder: '如 9#312', text: this.roomQuery })
            .fontColor(getColors(this.isDark).onSurface).placeholderColor(getColors(this.isDark).onSurfaceVariant)
            .caretColor(getColors(this.isDark).primary).backgroundColor(getColors(this.isDark).surfaceVariant)
            .onChange((v: string) => { this.roomQuery = v })
            .height(48)
            .width('90%')

          if (this.errorMsg.length > 0) {
            Text(this.errorMsg).fontColor(getColors(this.isDark).error).fontSize(14).margin({ top: 8 }).alignSelf(ItemAlign.Start).width('90%')
          }

          Button(this.loading ? '查询中...' : '查询电费')
            .width('90%').height(48).backgroundColor(getColors(this.isDark).primary).borderRadius(16)
            .margin({ top: 16 })
            .enabled(!this.loading)
            .onClick(() => { this.queryElectricity() })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      } else if (this.step === 2 && this.electricity) {
        Column() {
          Column() {
            Text('剩余电量').fontSize(14).fontColor(getColors(this.isDark).onSurfaceVariant)
            Text(this.electricity.remainingElectricity.value + ' ' + this.electricity.remainingElectricity.unit)
              .fontSize(40)
              .fontWeight(FontWeight.Bold)
              .fontColor(Number(this.electricity.remainingElectricity.value) < 10 ? getColors(this.isDark).error : getColors(this.isDark).primary)
              .margin({ top: 8 })
            Text(this.electricity.room.buildingName + ' ' + this.electricity.room.roomName)
              .fontSize(13).fontColor(getColors(this.isDark).onSurfaceVariant).margin({ top: 8 })
          }
          .width('90%')
          .padding(24)
          .backgroundColor(getColors(this.isDark).primaryContainer)
          .borderRadius(16)
          .margin({ top: 24 })
          .alignItems(HorizontalAlign.Center)

          Row() {
            Button('去充值')
              .height(48).layoutWeight(1).backgroundColor(getColors(this.isDark).primary).borderRadius(16)
              .fontColor(getColors(this.isDark).onPrimary)
              .margin({ right: 8 })
              .enabled(!this.loading && !this.paying)
              .onClick(() => { this.loadRechargeConfig() })
            Button(this.loading ? '刷新中…' : '刷新电量')
              .height(48).layoutWeight(1).backgroundColor(getColors(this.isDark).surfaceVariant).borderRadius(16)
              .fontColor(getColors(this.isDark).onSurface)
              .enabled(!this.loading && !this.paying)
              .onClick(() => { this.queryElectricity() })
          }
          .width('90%')
          .margin({ top: 24 })
          Button('更换宿舍').backgroundColor(Color.Transparent)
            .fontColor(getColors(this.isDark).onSurfaceVariant).enabled(!this.paying)
            .onClick(() => this.changeRoom()).margin({ top: 12 })

          if (this.errorMsg.length > 0) {
            Text(this.errorMsg).fontColor(getColors(this.isDark).error).fontSize(12).margin({ top: 12 })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      } else if (this.step === 3 && this.rechargeConfig) {
        Column() {
          Column() {
            Text('电费充值').fontColor(getColors(this.isDark).onSurface).fontSize(16).fontWeight(FontWeight.Bold).alignSelf(ItemAlign.Start)
            Text('当前电量: ' + this.rechargeConfig.remainingElectricity.value + this.rechargeConfig.remainingElectricity.unit)
              .fontSize(13).fontColor(getColors(this.isDark).onSurfaceVariant).margin({ top: 6 })
            Text('账户余额: ¥' + this.rechargeConfig.cardBalance.value)
              .fontSize(13).fontColor(getColors(this.isDark).onSurfaceVariant).margin({ top: 2 })
            Text('电价: ' + this.rechargeConfig.price.value + ' 元/' + this.rechargeConfig.price.unit)
              .fontSize(13).fontColor(getColors(this.isDark).onSurfaceVariant).margin({ top: 2 })
          }
          .width('90%')
          .padding(16)
          .backgroundColor(getColors(this.isDark).surface)
          .borderRadius(12)
          .margin({ top: 16 })
          .alignItems(HorizontalAlign.Start)

          Text('选择充值金额').fontColor(getColors(this.isDark).onSurface).fontSize(15).fontWeight(FontWeight.Medium)
            .margin({ top: 20, bottom: 12 }).width('90%')
          Row() {
            ForEach(this.rechargeConfig.amountOptions, (opt: AmountOption) => {
              Button(opt.name)
                .height(48)
                .layoutWeight(1)
                .backgroundColor(this.selectedAmount === opt.amount ? getColors(this.isDark).primary : getColors(this.isDark).surfaceVariant)
                .fontColor(this.selectedAmount === opt.amount ? getColors(this.isDark).onPrimary : getColors(this.isDark).onSurface)
                .borderRadius(16)
                .margin({ right: 8 })
                .onClick(() => { this.selectedAmount = opt.amount })
            }, (opt: AmountOption): string => opt.id)
          }
          .width('90%')

          if (this.showPasswordInput) {
            Text('支付密码').fontColor(getColors(this.isDark).onSurface).fontSize(15).fontWeight(FontWeight.Medium)
              .margin({ top: 20, bottom: 8 }).width('90%')
            TextInput({ placeholder: '请输入一卡通支付密码', text: this.paymentPassword })
              .fontColor(getColors(this.isDark).onSurface).placeholderColor(getColors(this.isDark).onSurfaceVariant)
              .caretColor(getColors(this.isDark).primary).backgroundColor(getColors(this.isDark).surfaceVariant)
              .type(InputType.Password)
              .onChange((v: string) => { this.paymentPassword = v })
              .height(48).width('90%')
          }

          if (this.errorMsg.length > 0) {
            Text(this.errorMsg).fontColor(getColors(this.isDark).error).fontSize(12).margin({ top: 12 }).width('90%')
          }

          Button(this.paying ? '支付中...' : '确认支付')
            .width('90%').height(48).backgroundColor(getColors(this.isDark).primary).borderRadius(16)
            .fontColor(getColors(this.isDark).onPrimary)
            .margin({ top: 20 })
            .enabled(this.selectedAmount.length > 0 && !this.paying)
            .onClick(() => { this.handlePay() })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      } else if (this.step === 4) {
        Column() {
          // 这里只是"请求已提交"，不是支付成功。用强调色或粗体渲染会让用户
          // 把这一屏读成结果页，所以按正文样式呈现，判断留给一卡通账户。
          Text(this.resultMsg)
            .fontSize(16).fontWeight(FontWeight.Normal).fontColor(getColors(this.isDark).onSurface)
            .margin({ top: 60 })
          Button('回到首页')
            .width('90%').height(48).backgroundColor(getColors(this.isDark).primary).borderRadius(16)
            .fontColor(getColors(this.isDark).onPrimary)
            .margin({ top: 32 })
            .onClick(() => { safeBack(this.getUIContext()) })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      }

          }.width('100%').padding({ bottom: 28 })
        }.width('100%').layoutWeight(1).scrollBar(BarState.Off)
      }.width('100%').height('100%').padding({ bottom: this.safeAreaBottom })
      ThemeWash()
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
