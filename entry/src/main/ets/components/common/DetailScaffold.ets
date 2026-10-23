import { AmbientBackground } from '../AmbientBackground'
import { DetailHeader } from './DetailHeader'
import { ThemeWash } from './ThemeWash'

@Component
export struct DetailScaffold {
  @StorageLink('safeAreaBottom') safeAreaBottom: number = 0
  @Prop title: string = ''
  @Prop subtitle: string = ''
  @Prop action: string = '刷新'
  @Prop actionGlyph: string = ''
  @Prop busy: boolean = false
    // 作为底部导航的一页时不显示返回按钮：Tab 是根级入口，没有上一页可回。
    @Prop showBack: boolean = true
  onBack: () => void = () => {}
  onAction: () => void = () => {}
  @BuilderParam content: () => void
  build() {
    Stack() {
      AmbientBackground()
      Column() {
        DetailHeader({ title: this.title, subtitle: this.subtitle, action: this.action,
          actionGlyph: this.actionGlyph, busy: this.busy,
          showBack: this.showBack, onBack: () => this.onBack(), onAction: () => this.onAction() })
        this.content()
      }.width('100%').height('100%').padding({ bottom: this.safeAreaBottom })
      ThemeWash()
    }.width('100%').height('100%')
  }
}
