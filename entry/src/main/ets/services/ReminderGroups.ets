import reminderAgentManager from '@ohos.reminderAgentManager'

/**
 * 提醒分组名。注册与取消必须引用这里，不能各写字面量——两侧拼写只要差一个
 * 字符，取消就一条都匹配不到，系统提醒会在退出登录后继续弹给下一个账号。
 * 分组名也是"哪些系统提醒属于本应用某个功能"的唯一凭据。
 */
export const COURSE_REMINDER_GROUP: string = 'campus_courses'
export const TODO_REMINDER_GROUP: string = 'campus_todos'

export async function cancelReminderGroup(groupId: string): Promise<void> {
  if (groupId.length === 0) throw new Error('提醒分组不能为空')
  const reminders = await reminderAgentManager.getAllValidReminders()
  let firstError: Error | null = null
  for (const reminder of reminders) {
    if (reminder.reminderReq.groupId === groupId) {
      try { await reminderAgentManager.cancelReminder(reminder.reminderId) }
      catch (error) { if (firstError === null) firstError = error as Error }
    }
  }
  if (firstError !== null) throw firstError
}
