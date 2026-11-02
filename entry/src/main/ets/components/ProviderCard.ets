import { LayoutMetrics, SizeClass, metricsFor } from '../common/Breakpoints';
import {
  BalanceInfo,
  FetchState,
  ProviderSnapshot,
  QuotaWindow,
  SourceKind,
  normalizeWindows
} from '../model/Types';
import { moneyText, relativeTime } from '../common/Format';
import { WindowBar } from './WindowBar';

/**
 * 单个来源卡片。
 *
 * 展示：来源名 + 状态徽标 + 三个窗口 + 余额 + 错误信息。
 * 出错时保留卡片（不隐藏），把原因写清楚并允许重试。
 *
 * 响应式：窗口始终纵向排列（多列时单卡宽度有限，并排会挤成一团）；
 * 宽屏的差异体现在列数、留白、字号与卡片内边距上。
 */
@Component
export struct ProviderCard {
  @Prop snapshot: ProviderSnapshot;
  @Prop now: number;
  @Prop moneyDecimals: number = 2;
  @Prop metrics: LayoutMetrics = metricsFor(SizeClass.SM);
  /** 重试回调：@Prop 不能用于函数类型，用普通成员传递。 */
  onRetry: (providerId: string) => void = (_id: string) => {};
  /** 「去配置」回调，跳到来源编辑页。 */
  onConfigure: (providerId: string) => void = (_id: string) => {};

  build() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(this.snapshot.name)
          .fontSize(this.metrics.sizeClass === SizeClass.SM ? 16 : 17)
          .fontWeight(FontWeight.Medium)
          .fontColor('#F2F2F4')
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.stateBadge())
          .fontSize(10)
          .fontColor(this.stateColor())
          .backgroundColor(this.stateBg())
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .borderRadius(10)
      }
      .width('100%')

      if (this.snapshot.state === FetchState.NEEDS_AUTH) {
        this.needsAuthBlock()
      } else if (this.snapshot.state === FetchState.ERROR) {
        this.errorBlock()
      } else {
        // 纯余额来源不显示三个空窗口 —— 它们没有时间窗口概念，
        // 画三行「不提供此窗口」只会挤占真正要看的金额。
        if (this.snapshot.kind !== SourceKind.BALANCE) {
          this.narrowWindowBlock()
        }
        this.balanceBlock()
        this.extraBlock()
      }

      Row() {
        Text(relativeTime(this.snapshot.fetchedAt, this.now))
          .fontSize(10)
          .fontColor('#5C5C60')
          .layoutWeight(1)
        if (this.snapshot.elapsedMs !== undefined && this.snapshot.elapsedMs > 0) {
          Text(`${this.snapshot.elapsedMs} ms`)
            .fontSize(10)
            .fontColor('#5C5C60')
        }
      }
      .width('100%')
    }
    .width('100%')
    .padding(this.metrics.sizeClass === SizeClass.SM ? 14 : 16)
    .backgroundColor('#1C1C1F')
    .borderRadius(14)
    .border({ width: 1, color: '#2C2C30' })
  }

  /** 手机：纵向三窗口。 */
  @Builder
  narrowWindowBlock() {
    Column({ space: 2 }) {
      ForEach(this.windows(), (item: QuotaWindow) => {
        WindowBar({ window: item, now: this.now, moneyDecimals: this.moneyDecimals })
      }, (item: QuotaWindow) => `${this.snapshot.providerId}-${item.kind}`)
    }
    .width('100%')
  }

  @Builder
  balanceBlock() {
    if (this.snapshot.balances.length > 0) {
      Column({ space: 4 }) {
        Divider().color('#2C2C30')
        ForEach(this.snapshot.balances, (item: BalanceInfo, index: number) => {
          Row() {
            Text(index === 0 ? '余额' : '')
              .fontSize(13)
              .fontColor('#8A8A8E')
              .width(44)
            Text(moneyText(item.amount, item.currency, this.moneyDecimals))
              .fontSize(this.metrics.sizeClass === SizeClass.SM ? 18 : 20)
              .fontWeight(FontWeight.Medium)
              .fontColor(item.amount < 0 ? '#E84026' : '#F2F2F4')
              .layoutWeight(1)
          }
          .width('100%')

          if (item.note !== undefined && item.note !== '') {
            Text(item.note)
              .fontSize(11)
              .fontColor(item.amount < 0 ? '#E84026' : '#8A8A8E')
              .width('100%')
          }
          if (item.granted !== undefined || item.toppedUp !== undefined) {
            Text(this.balanceDetail(item))
              .fontSize(11)
              .fontColor('#6B6B6B')
              .width('100%')
          }
        }, (item: BalanceInfo, index: number) => `${this.snapshot.providerId}-bal-${index}`)
      }
      .width('100%')
    }
  }

  @Builder
  extraBlock() {
    if (this.hasExtra()) {
      Column({ space: 2 }) {
        Divider().color('#2C2C30')
        if (this.snapshot.extra.planName !== undefined) {
          this.extraRow('套餐', this.snapshot.extra.planName)
        }
        if (this.snapshot.extra.creditsBalance !== undefined) {
          this.extraRow('积分余额',
            `${Math.floor(this.snapshot.extra.creditsBalance)} ${this.snapshot.extra.creditsUnit ?? ''}`)
        }
        if (this.snapshot.extra.resetCreditsAvailable !== undefined) {
          this.extraRow('可用重置次数', `${this.snapshot.extra.resetCreditsAvailable}`)
        }
      }
      .width('100%')
    }
  }

  @Builder
  extraRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(12)
        .fontColor('#8A8A8E')
        .layoutWeight(1)
      Text(value)
        .fontSize(12)
        .fontColor('#C8C8CC')
    }
    .width('100%')
    .padding({ top: 3 })
  }

  /** 缺少凭据：引导去配置，而不是报红错。 */
  @Builder
  needsAuthBlock() {
    Column({ space: 8 }) {
      Text(this.authHint())
        .fontSize(13)
        .fontColor('#9FB8E8')
        .width('100%')
      Row({ space: 8 }) {
        Button('去配置')
          .fontSize(12)
          .height(28)
          .backgroundColor('#2B4A7A')
          .fontColor('#DCE8FF')
          .onClick(() => {
            this.onConfigure(this.snapshot.providerId);
          })
        Button('重试')
          .fontSize(12)
          .height(28)
          .backgroundColor('#2A2A2E')
          .fontColor('#8A8A8E')
          .onClick(() => {
            this.onRetry(this.snapshot.providerId);
          })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 4 })
  }

  @Builder
  errorBlock() {
    Column({ space: 6 }) {
      Text(this.errorTitle())
        .fontSize(13)
        .fontColor('#E84026')
        .width('100%')
      if (this.errorDetail() !== '') {
        Text(this.errorDetail())
          .fontSize(11)
          .fontColor('#A05A50')
          .width('100%')
          .maxLines(4)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      Button('重试')
        .fontSize(12)
        .height(28)
        .backgroundColor('#2A2A2E')
        .fontColor('#E8E8EA')
        .onClick(() => {
          this.onRetry(this.snapshot.providerId);
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 4 })
  }

  private windows(): QuotaWindow[] {
    return normalizeWindows(this.snapshot);
  }

  /** 纯余额来源没有窗口，卡片更矮，内边距也收紧一点。 */
  private isBalanceOnly(): boolean {
    return this.snapshot.kind === SourceKind.BALANCE;
  }

  private hasExtra(): boolean {
    const extra = this.snapshot.extra;
    return extra.planName !== undefined || extra.creditsBalance !== undefined ||
      extra.resetCreditsAvailable !== undefined;
  }

  private balanceDetail(item: BalanceInfo): string {
    const parts: string[] = [];
    if (item.granted !== undefined) {
      parts.push(`赠金 ${item.granted}`);
    }
    if (item.toppedUp !== undefined) {
      parts.push(`充值 ${item.toppedUp}`);
    }
    if (item.cash !== undefined) {
      parts.push(`现金 ${item.cash}`);
    }
    if (item.voucher !== undefined) {
      parts.push(`代金券 ${item.voucher}`);
    }
    return parts.join(' · ');
  }

  private stateBadge(): string {
    switch (this.snapshot.state) {
      case FetchState.OK:
        return '正常';
      case FetchState.PARTIAL:
        return '部分可用';
      case FetchState.NEEDS_AUTH:
        return '待配置';
      default:
        return '失败';
    }
  }

  private stateColor(): string {
    switch (this.snapshot.state) {
      case FetchState.OK:
        return '#3BA55D';
      case FetchState.PARTIAL:
        return '#F2A33C';
      case FetchState.NEEDS_AUTH:
        return '#7AA2F7';
      default:
        return '#E84026';
    }
  }

  private stateBg(): string {
    switch (this.snapshot.state) {
      case FetchState.OK:
        return '#14351F';
      case FetchState.PARTIAL:
        return '#3A2A12';
      case FetchState.NEEDS_AUTH:
        return '#17233A';
      default:
        return '#3A1A16';
    }
  }

  /** 待配置时的引导文案：说明缺什么、去哪填。 */
  private authHint(): string {
    const error = this.snapshot.error;
    if (error !== undefined && error.message !== '') {
      return `${error.message}，点「去配置」填写后即可显示额度。`;
    }
    return '尚未配置凭据，点「去配置」填写后即可显示额度。';
  }

  private errorTitle(): string {
    const error = this.snapshot.error;
    if (error === undefined) {
      return '未知错误';
    }
    return error.message;
  }

  private errorDetail(): string {
    const error = this.snapshot.error;
    if (error === undefined) {
      return '';
    }
    return error.rawSnippet ?? '';
  }
}
