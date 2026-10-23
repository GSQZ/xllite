import reminderAgentManager from '@ohos.reminderAgentManager'
import notificationManager from '@ohos.notificationManager'
import { TodoItem } from '../models/TodoTypes'
import { buildTodoReminderPlans } from '../utils/TodoReminderPlan'
import { cancelReminderGroup, TODO_REMINDER_GROUP } from './ReminderGroups'

let reminderQueue: Promise<void> = Promise.resolve()
let reminderVersion: number = 0

export function getTodoReminderCount(): Promise<number> {
  const task = reminderQueue.then(async (): Promise<number> => {
    const reminders = await reminderAgentManager.getAllValidReminders()
    return reminders.filter((item: reminderAgentManager.ReminderInfo): boolean => item.reminderReq.groupId === TODO_REMINDER_GROUP).length
  })
  reminderQueue = task.then(() => {}).catch((_error: Error) => {})
  return task
}
export function clearTodoReminders(): Promise<void> {
  reminderVersion++
  const task = reminderQueue.then(() => cancelReminderGroup(TODO_REMINDER_GROUP))
  reminderQueue = task.catch((_error: Error) => {})
  return task
}

export function syncTodoReminders(items: TodoItem[], bundleName: string): Promise<number> {
  const snapshot = items.map((item: TodoItem): TodoItem => ({ id: item.id, title: item.title, note: '', dueText: '',
    dueAt: item.dueAt, done: item.done, createdAt: item.createdAt, updatedAt: item.updatedAt }))
  const version = reminderVersion
  const task = reminderQueue.then(() => version === reminderVersion ? replaceTodoReminders(snapshot, bundleName, version) : 0)
  reminderQueue = task.then(() => {}).catch((_error: Error) => {})
  return task
}
async function replaceTodoReminders(items: TodoItem[], bundleName: string, version: number): Promise<number> {
  const plans = buildTodoReminderPlans(items)
  if (plans.length > 0 && !await notificationManager.isNotificationEnabled()) throw new Error('请允许通知后再登记待办提醒')
  await cancelReminderGroup(TODO_REMINDER_GROUP)
  let count: number = 0
  try {
    for (const plan of plans) {
      if (version !== reminderVersion) return 0
      if (plan.triggerAt <= Date.now()) continue
      const trigger = new Date(plan.triggerAt)
      const request: reminderAgentManager.ReminderRequestCalendar = {
        reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
        dateTime: { year: trigger.getFullYear(), month: trigger.getMonth() + 1, day: trigger.getDate(),
          hour: trigger.getHours(), minute: trigger.getMinutes() },
        title: '待办任务 · ' + plan.title, content: '点击查看并管理任务', expiredContent: '任务时间已到',
        wantAgent: { pkgName: bundleName, abilityName: 'EntryAbility', parameters: { campusRoute: plan.route } },
        notificationId: 9400 + count, groupId: TODO_REMINDER_GROUP,
        slotType: notificationManager.SlotType.SERVICE_INFORMATION, tapDismissed: true,
        ringDuration: 0, snoozeTimes: 0,
      }
      const reminderId: number = await reminderAgentManager.publishReminder(request)
      count++
      // publishReminder 是异步的：检查通过到真正登记完成之间，用户可能已经登出。
      // 登出时 cancelReminderGroup 早已跑完，若这里不补一次撤销，这条提醒就留在
      // 系统里，会在下一个账号登录后照常弹出。按返回的 reminderId 精确撤销。
      if (version !== reminderVersion) {
        try { await reminderAgentManager.cancelReminder(reminderId) }
        catch (_error) {
          try { await cancelReminderGroup(TODO_REMINDER_GROUP) } catch (_e2) { /* 留给登出重试 */ }
        }
        return 0
      }
    }
  } catch (error) {
    try { await cancelReminderGroup(TODO_REMINDER_GROUP) }
    catch (cleanupError) {
      throw new Error('提醒登记失败：' + (error as Error).message + '；清理未完成：' + (cleanupError as Error).message)
    }
    throw error as Error
  }
  return count
}
