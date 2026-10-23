import { FeatureDef } from '../models/Types'

export const SCHOOL_CAS: string = 'https://cas.xjit.edu.cn/cas/login'
export const SCHOOL_SUPERAPP: string = 'https://superapp.xjit.edu.cn'
export const SCHOOL_PERSONAL_API: string = 'https://authx-service.xjit.edu.cn/personal'
export const SCHOOL_PORTAL_API: string = 'https://portal.xjit.edu.cn/portal-api'
export const SCHOOL_CARD: string = 'https://newcard.xjit.edu.cn'
export const SCHOOL_CARD_API: string = SCHOOL_CARD + '/server'

export const FEATURES: FeatureDef[] = [
  { name: 'newcard.campus_code.qrcode', title: '校园付款码', system: 'newcard', icon: '付', page: 'QRCodePage' },
  { name: 'newcard.balance', title: '校园卡余额', system: 'newcard', icon: '卡', page: 'BalancePage' },
  { name: 'newcard.transactions', title: '交易流水', system: 'newcard', icon: '流', page: 'TransactionsPage' },
  { name: 'newcard.recharge.config', title: '一卡通充值', system: 'newcard', icon: '充', page: 'RechargePage' },
  { name: 'newcard.electricity.account', title: '电费查询', system: 'newcard', icon: '电', page: 'ElectricityPage' },
  { name: 'jw.schedule', title: '课表查询', system: 'jw', icon: '课', page: 'SchedulePage' },
  { name: 'jw.grades', title: '成绩查询', system: 'jw', icon: '绩', page: 'GradesPage' },
  { name: 'jw.exams', title: '考试安排', system: 'jw', icon: '考', page: 'ExamsPage' },
  { name: 'jw.profile', title: '个人信息', system: 'jw', icon: '人', page: 'ProfilePage' },
  { name: 'local.todos', title: '待办任务', system: 'local', icon: '办', page: 'TodoPage' },
]

const FALLBACK_FEATURE: FeatureDef =
  { name: 'unknown', title: '服务入口未配置', system: 'local', icon: '?', page: 'SchoolServicePage' }

// 按 name 取功能定义。页面此前用 FEATURES[4] 这类下标硬编码，
// 一旦调整数组顺序或插入新项，入口就会静默打开错误的页面。
export function featureByName(name: string): FeatureDef {
  for (let i = 0; i < FEATURES.length; i++) {
    if (FEATURES[i].name === name) return FEATURES[i]
  }
  return FALLBACK_FEATURE
}

export function systemLabel(s: string): string {
  if (s === 'newcard') return '一卡通服务'
  if (s === 'jw') return '教务服务'
  if (s === 'local') return '本地工具'
  return s
}
