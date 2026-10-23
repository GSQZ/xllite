/**
 * 节次 → 时段映射(已确认 2026 秋季作息，Asia/Shanghai，2026-10-21 用户确认含晚自习)
 *
 * 上午 10:00-13:40、下午 16:00-19:40、晚自习 20:30-22:10，三段同构：
 * 45 分钟一节，小节间小课间 10 分钟，大节间休息 20 分钟(午间、傍晚另计)。
 * 节次索引 0-9，前八小节为四个大节，第九、十小节为第五大节晚自习。
 */

export interface ClassTime {
  startMinutes: number
  endMinutes: number
  label: string
}

const TIMES: ClassTime[] = [
  { startMinutes: 600, endMinutes: 645, label: '10:00 - 10:45' },
  { startMinutes: 655, endMinutes: 700, label: '10:55 - 11:40' },
  { startMinutes: 720, endMinutes: 765, label: '12:00 - 12:45' },
  { startMinutes: 775, endMinutes: 820, label: '12:55 - 13:40' },
  { startMinutes: 960, endMinutes: 1005, label: '16:00 - 16:45' },
  { startMinutes: 1015, endMinutes: 1060, label: '16:55 - 17:40' },
  { startMinutes: 1080, endMinutes: 1125, label: '18:00 - 18:45' },
  { startMinutes: 1135, endMinutes: 1180, label: '18:55 - 19:40' },
  { startMinutes: 1230, endMinutes: 1275, label: '20:30 - 21:15' },
  { startMinutes: 1285, endMinutes: 1330, label: '21:25 - 22:10' },
]

/**
 * "第一大节" → 索引 0
 * 解析失败返回 -1
 */
export function slotIndex(slot: string): number {
  const cnMap: Record<string, number> = {
    '一': 1, '二': 2, '三': 3, '四': 4, '五': 5,
    '六': 6, '七': 7, '八': 8, '九': 9, '十': 10,
  }
  for (const cn of Object.keys(cnMap)) {
    if (slot.indexOf(cn) >= 0) {
      return cnMap[cn] - 1
    }
  }
  // 兼容 "第1大节" / "1"
  const m = slot.match(/[0-9]+/)
  if (m) {
    const n = parseInt(m[0], 10)
    if (n >= 1 && n <= TIMES.length) return n - 1
  }
  return -1
}

/**
 * "1-2节" → [startMinutes, endMinutes]
 * "3节"   → [startMinutes, endMinutes]
 */
export function sectionNumbers(sections: string): number[] {
  const clean = sections.replace(/[第节\[\]\s]/g, '').replace(/[，、]/g, ',').replace(/[–—~至]/g, '-')
  if (clean.length === 0) return []
  const values: number[] = []
  for (const part of clean.split(',')) {
    if (!/^\d+(-\d+)?$/.test(part)) return []
    const pair = part.split('-').map((v: string): number => Number(v))
    const lo = Math.min(pair[0], pair[pair.length - 1])
    const hi = Math.max(pair[0], pair[pair.length - 1])
    if (lo < 1 || hi > TIMES.length) return []
    for (let n = lo; n <= hi; n++) { if (!values.includes(n)) values.push(n) }
  }
  return values.sort((a: number, b: number): number => a - b)
}

export function parseSections(sections: string): [number, number] {
  const values = sectionNumbers(sections)
  if (values.length === 0) return [0, 0]
  return [TIMES[values[0] - 1].startMinutes, TIMES[values[values.length - 1] - 1].endMinutes]
}

/**
 * 课程时间区间(直接由 sections 解析,更精确)
 */
export function getCourseMinutes(sections: string): [number, number] {
  return parseSections(sections)
}

/** 节次能否映射到当前作息表;例如超出 10 节的 "11-12节" 返回 false */
export function sectionsResolved(sections: string): boolean {
  return sectionNumbers(sections).length > 0
}

/** "1-2节" → "10:00 – 11:40";无法解析时明确标注,不把 00:00 当成上课时间 */
export function courseTimeText(sections: string): string {
  const range = parseSections(sections)
  if (range[0] === 0 && range[1] === 0) return '节次待确认'
  return formatMinutes(range[0]) + ' – ' + formatMinutes(range[1])
}

/**
 * 分钟数 → "08:00" 格式
 */
export function formatMinutes(m: number): string {
  if (m < 0) return '--:--'
  const h = Math.floor(m / 60)
  const mm = m % 60
  return `${h.toString().padStart(2, '0')}:${mm.toString().padStart(2, '0')}`
}

/**
 * 课程状态: 0 未开始 / 1 进行中 / 2 已结束
 */
export function classStatus(startM: number, endM: number, now: Date = new Date()): number {
  const nowM = now.getHours() * 60 + now.getMinutes()
  if (nowM < startM) return 0
  if (nowM >= endM) return 2
  return 1
}

/**
 * 找今天(给定课程列表)的"下一节"
 * @returns 数组下标, -1 表示今天课程都上完了
 */
export interface CourseMinutes {
  startMinutes: number
  endMinutes: number
}

export function nextClassIndex(
  courses: CourseMinutes[],
  now: Date = new Date(),
): number {
  const nowM = now.getHours() * 60 + now.getMinutes()
  for (let i = 0; i < courses.length; i++) {
    if (courses[i].endMinutes > nowM) return i
  }
  return -1
}

/** 所有节次时段(供 ScheduleGrid 渲染时间轴) */
export const ALL_TIMES = TIMES
