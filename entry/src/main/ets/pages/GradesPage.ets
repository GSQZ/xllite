import { GradesTab } from './GradesTab'

/**
 * 成绩查询的路由页。
 *
 * 业务与渲染全部在 `GradesTab` 里，这里只做一层壳：同一条页面既能作为
 * 「我的 → 成绩查询」的独立路由打开，也能作为底部导航的一个 Tab 挂载，
 * 两边共用一份实现，不会出现两套逻辑各自演化。
 */
@Entry
@Component
struct GradesPage {
  build() {
    Column() {
      GradesTab()
    }
    .width('100%').height('100%')
  }
}
