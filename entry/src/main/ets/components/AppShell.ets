import { LayoutMetrics, SizeClass } from '../common/Breakpoints';

/** 侧边导航里的一个入口。 */
export interface NavItem {
  key: string;
  label: string;
  icon: string;
}

/**
 * 宽屏（平板横屏 / 2in1）左侧常驻导航条。
 *
 * 只在 sideNav=true 时渲染；窄屏完全退化成首页顶部的两个按钮。
 */
@Component
export struct SideNav {
  @Prop current: string = 'index';
  @Prop metrics: LayoutMetrics;
  onSelect: (key: string) => void = (_key: string) => {};

  private items: NavItem[] = [
    { key: 'index', label: '额度总览', icon: '◉' },
    { key: 'providers', label: '数据来源', icon: '☰' },
    { key: 'settings', label: '设置', icon: '⚙' }
  ];

  build() {
    Column({ space: 4 }) {
      Row({ space: 8 }) {
        Text('星')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#0E0E10')
          .backgroundColor('#F5F5F7')
          .width(30)
          .height(30)
          .borderRadius(9)
          .textAlign(TextAlign.Center)
          .accessibilityLevel('no')
        Text('星河 Token')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#F2F2F4')
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .padding({ left: 6, right: 6, top: 2, bottom: 14 })

      ForEach(this.items, (item: NavItem) => {
        Row({ space: 10 }) {
          Text(item.icon)
            .fontSize(13)
            .fontColor(this.current === item.key ? '#FFFFFF' : '#8A8A8E')
            .width(18)
            .textAlign(TextAlign.Center)
            .accessibilityLevel('no')
          Text(item.label)
            .fontSize(13)
            .fontColor(this.current === item.key ? '#FFFFFF' : '#A8A8AC')
            .layoutWeight(1)
        }
        .width('100%')
        .height(40)
        .padding({ left: 10, right: 10 })
        .borderRadius(10)
        .backgroundColor(this.current === item.key ? '#2C2C31' : '#00000000')
        .focusable(true)
        .hoverEffect(HoverEffect.Highlight)
        .accessibilityLevel('yes')
        .accessibilityText(this.current === item.key ? `${item.label}，当前页面` : item.label)
        .onClick(() => {
          this.onSelect(item.key);
        })
      }, (item: NavItem) => `nav-${item.key}`)

      Blank()

      Text(this.hint())
        .fontSize(10)
        .fontColor('#8A8A8E')
        .width('100%')
        .padding({ left: 8, right: 8, bottom: 10 })
    }
    .width(184)
    .height('100%')
    .padding({ left: 10, right: 10, top: 16 })
    .backgroundColor('#151517')
    .border({ width: { right: 1 }, color: '#26262A' })
  }

  private hint(): string {
    if (this.metrics.sizeClass === SizeClass.XL) {
      return '桌面宽屏布局 · 三列';
    }
    return '平板布局 · 两列';
  }
}

/**
 * 内容容器：宽屏限制最大宽度并居中，窄屏满宽。
 *
 * 用 Column 包一层而不是直接改各行 padding，能让所有子页共享同一套留白规则。
 */
@Component
export struct ContentShell {
  @Prop metrics: LayoutMetrics;
  @BuilderParam content: () => void;

  build() {
    Column() {
      Column() {
        this.content()
      }
      .width('100%')
      .constraintSize({ maxWidth: this.metrics.maxContentWidth > 0 ? this.metrics.maxContentWidth : 99999 })
      .padding({ left: this.metrics.pagePadding, right: this.metrics.pagePadding })
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
  }
}
