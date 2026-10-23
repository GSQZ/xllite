import { TodoTab } from './TodoTab'

/**
 * 待办任务的路由页。
 *
 * 业务与渲染全部在 `TodoTab` 里，这里只做一层壳：待办已经提升为底部导航的
 * 独立一页，但仍保留路由入口，方便从课程卡片、实况窗等处直接跳进来。
 */
@Entry
@Component
struct TodoPage {
  build() {
    Column() {
      TodoTab()
    }
    .width('100%').height('100%')
  }
}
