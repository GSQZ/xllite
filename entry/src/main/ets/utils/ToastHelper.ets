import { UIContext } from '@ohos.arkui.UIContext'
import { BusinessError } from '@ohos.base'
import { Logger } from './Logger'

/**
 * 弹一条短提示。
 *
 * 提示失败不抛异常：调用点都是"操作已完成后告知结果"，此时把异常再抛出去会把
 * 已经成功的写入回滚成失败态。但也不能像以前那样静默吞掉——这些提示在多数
 * 场景是用户唯一的结果反馈，悄无声息地不显示，出问题后无从查起。
 * 现改为把失败的 code 与文案记进日志，窗口未就绪这类问题可以从 hilog 定位。
 *
 * 返回是否真的弹出来了，调用点需要区分时可以用。
 */
export function safeToast(uiContext: UIContext, message: string): boolean {
  if (message.length === 0) return false
  try {
    uiContext.getPromptAction().showToast({ message })
    return true
  } catch (error) {
    const code = (error as BusinessError).code
    Logger.warn('Toast', 'showToast failed code=%{public}d message=%{public}s', code ?? -1, message)
    return false
  }
}
