import { QuotaWindow, WindowKind, remainingRatio, windowLabel } from '../model/Types';
import { absoluteText, countdownText, progressColor, toProgressValue } from '../common/Format';

/**
 * 单个额度窗口：标题 + 百分比 + 进度条 + 余量/倒计时。
 *
 * 不处理数据获取，只负责展示；不支持的窗口显示为灰色说明行。
 */
@Component
export struct WindowBar {
  @Prop window: QuotaWindow;
  @Prop now: number;
  @Prop moneyDecimals: number = 2;

  build() {
    Column({ space: 4 }) {
      Row() {
        Text(this.labelText())
          .fontSize(13)
          .fontColor('#8A8A8E')
          .layoutWeight(1)
        Text(this.valueText())
          .fontSize(13)
          .fontColor(this.isUnavailable() ? '#6B6B6B' : '#E8E8EA')
          .fontWeight(FontWeight.Medium)
      }
      .width('100%')

      if (this.isUnavailable()) {
        Text(this.window.unavailableReason ?? '无数据')
          .fontSize(11)
          .fontColor('#6B6B6B')
          .width('100%')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      } else {
        Progress({ value: toProgressValue(this.window), total: 100, type: ProgressType.Linear })
          .color(progressColor(this.window))
          .backgroundColor('#2A2A2E')
          .height(6)
          .width('100%')

        Row({ space: 8 }) {
          Text(this.subText())
            .fontSize(11)
            .fontColor('#8A8A8E')
            .flexShrink(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Blank()
          if (this.countdown() !== '') {
            Text(this.countdown())
              .fontSize(11)
              .fontColor('#8A8A8E')
              .flexShrink(0)
          }
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding({ top: 6, bottom: 6 })
  }

  private isUnavailable(): boolean {
    return remainingRatio(this.window) === undefined;
  }

  private labelText(): string {
    return windowLabel(this.window.kind);
  }

  private valueText(): string {
    if (this.isUnavailable()) {
      return '—';
    }
    const ratio = remainingRatio(this.window);
    if (ratio === undefined) {
      return '—';
    }
    return `${Math.round(ratio * 100)}%`;
  }

  private subText(): string {
    // 只有货币单位才用金额小数位；prompt / credit 一律取整。
    const unit = this.window.unit ?? '';
    const isMoney = unit === 'CNY' || unit === 'USD' || unit === 'EUR';
    const absolute = absoluteText(this.window, isMoney ? this.moneyDecimals : 0);
    if (absolute !== '') {
      return `余量 ${absolute}`;
    }
    if (this.window.derived === true) {
      return '按服务端百分比推算';
    }
    return '服务端百分比';
  }

  private countdown(): string {
    return countdownText(this.window.resetAt, this.now);
  }
}
