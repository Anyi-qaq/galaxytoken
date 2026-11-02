import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { AppSettings, ProviderDescriptor } from '../model/Types';
import { SettingsStore } from '../store/SettingsStore';
import { ProviderRegistry } from '../sources/ProviderRegistry';
import { REFRESH_OPTIONS } from '../common/Constants';
import { Log } from '../common/Logger';
import { SideNav } from '../components/AppShell';
import { LayoutMetrics, SizeClass, metricsFor, watchSizeClass } from '../common/Breakpoints';

/** 设置页：刷新间隔、金额精度、缓存清理、来源说明。 */
@Entry
@Component
struct SettingsPage {
  @State settings: AppSettings = {
    refreshIntervalSec: 60,
    moneyDecimals: 2,
    demoMode: false,
    showExperimental: true
  };
  @State saved: boolean = false;
  @State metrics: LayoutMetrics = metricsFor(SizeClass.SM);
  private unwatchSize: (() => void) | undefined = undefined;

  aboutToAppear(): void {
    this.load();
    try {
      this.unwatchSize = watchSizeClass(this.getUIContext(), (sizeClass: SizeClass) => {
        this.metrics = metricsFor(sizeClass);
      });
    } catch (error) {
      Log.w(`size class watch failed: ${error}`);
    }
  }

  aboutToDisappear(): void {
    const unwatch = this.unwatchSize;
    if (unwatch !== undefined) {
      unwatch();
      this.unwatchSize = undefined;
    }
  }

  build() {
    Row() {
      if (this.metrics.sideNav) {
        SideNav({
          current: 'settings',
          metrics: this.metrics,
          onSelect: (key: string) => {
            if (key === 'index') {
              router.back();
            } else if (key === 'providers') {
              router.replaceUrl({ url: 'pages/ProvidersPage' }).catch((error: Object) => {
                Log.w(`nav providers failed: ${error}`);
              });
            }
          }
        })
      }
      Column() {
        Column() {
          this.header()
          Scroll() {
            Column({ space: 14 }) {
              this.refreshBlock()
              this.decimalsBlock()
              this.dataBlock()
              this.sourcesBlock()
              this.aboutBlock()
              Blank().height(30)
            }
            .width('100%')
            .padding({
              left: this.metrics.pagePadding,
              right: this.metrics.pagePadding
            })
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .align(Alignment.Top)
        }
        .width('100%')
        .height('100%')
        .constraintSize({
          maxWidth: this.metrics.maxContentWidth > 0 ? this.metrics.maxContentWidth : 99999
        })
      }
      .layoutWeight(1)
      .height('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#121214')
  }

  @Builder
  header() {
    Row({ space: 10 }) {
      if (!this.metrics.sideNav) {
        Button('返回')
          .fontSize(13)
          .height(32)
          .backgroundColor('#242428')
          .fontColor('#D8D8DC')
          .onClick(() => {
            router.back();
          })
      }
      Text('设置')
        .fontSize(this.metrics.titleSize - 4)
        .fontWeight(FontWeight.Bold)
        .fontColor('#F5F5F7')
        .layoutWeight(1)
      if (this.saved) {
        Text('已保存').fontSize(12).fontColor('#3BA55D')
      }
    }
    .width('100%')
    .padding({
      left: this.metrics.pagePadding,
      right: this.metrics.pagePadding,
      top: 14,
      bottom: 10
    })
  }

  @Builder
  refreshBlock() {
    Column({ space: 8 }) {
      Text('刷新间隔').fontSize(13).fontColor('#C8C8CC').width('100%')
      Row({ space: 8 }) {
        ForEach(REFRESH_OPTIONS, (seconds: number) => {
          Text(this.intervalLabel(seconds))
            .fontSize(12)
            .fontColor(this.settings.refreshIntervalSec === seconds ? '#FFFFFF' : '#9A9A9E')
            .backgroundColor(this.settings.refreshIntervalSec === seconds ? '#3478F6' : '#242428')
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(8)
            .onClick(() => {
              this.updateInterval(seconds);
            })
        }, (seconds: number) => `interval-${seconds}`)
      }
      .width('100%')
      Text('页面在前台时按此间隔自动刷新；退到后台会停止，避免空耗流量。')
        .fontSize(10)
        .fontColor('#5C5C60')
        .width('100%')
    }
    .width('100%')
    .padding(14)
    .backgroundColor('#1C1C1F')
    .borderRadius(12)
  }

  @Builder
  decimalsBlock() {
    Column({ space: 8 }) {
      Text('金额小数位').fontSize(13).fontColor('#C8C8CC').width('100%')
      Row({ space: 8 }) {
        ForEach([0, 2, 4], (decimals: number) => {
          Text(`${decimals} 位`)
            .fontSize(12)
            .fontColor(this.settings.moneyDecimals === decimals ? '#FFFFFF' : '#9A9A9E')
            .backgroundColor(this.settings.moneyDecimals === decimals ? '#3478F6' : '#242428')
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(8)
            .onClick(() => {
              this.updateDecimals(decimals);
            })
        }, (decimals: number) => `dec-${decimals}`)
      }
      .width('100%')
    }
    .width('100%')
    .padding(14)
    .backgroundColor('#1C1C1F')
    .borderRadius(12)
  }

  @Builder
  dataBlock() {
    Column({ space: 8 }) {
      Text('本地数据').fontSize(13).fontColor('#C8C8CC').width('100%')
      Row() {
        Text('清除快照缓存').fontSize(12).fontColor('#9A9A9E').layoutWeight(1)
        Button('清除')
          .fontSize(12)
          .height(28)
          .backgroundColor('#2A2A2E')
          .fontColor('#E8E8EA')
          .onClick(() => {
            this.clearCache();
          })
      }
      .width('100%')
      Text('凭据存放在系统密钥库，不随缓存清理删除；要删除请在该来源的编辑页重新保存。')
        .fontSize(10)
        .fontColor('#5C5C60')
        .width('100%')
    }
    .width('100%')
    .padding(14)
    .backgroundColor('#1C1C1F')
    .borderRadius(12)
  }

  @Builder
  sourcesBlock() {
    Column({ space: 6 }) {
      Text('已注册来源').fontSize(13).fontColor('#C8C8CC').width('100%')
      ForEach(ProviderRegistry.all(), (descriptor: ProviderDescriptor) => {
        Row({ space: 8 }) {
          Text(descriptor.name)
            .fontSize(12)
            .fontColor('#C8C8CC')
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.supportText(descriptor))
            .fontSize(10)
            .fontColor('#6B6B70')
          if (descriptor.experimental) {
            Text('实验')
              .fontSize(9)
              .fontColor('#F2A33C')
              .backgroundColor('#3A2A12')
              .padding({ left: 5, right: 5, top: 1, bottom: 1 })
              .borderRadius(6)
          }
        }
        .width('100%')
        .padding({ top: 4 })
      }, (descriptor: ProviderDescriptor) => `src-${descriptor.id}`)
    }
    .width('100%')
    .padding(14)
    .backgroundColor('#1C1C1F')
    .borderRadius(12)
  }

  @Builder
  aboutBlock() {
    Column({ space: 8 }) {
      Text('关于').fontSize(13).fontColor('#C8C8CC').width('100%')
      Text('星河 Token · 1.0.0')
        .fontSize(12)
        .fontColor('#9A9A9E')
        .width('100%')
      Text('多来源 AI 额度看板：订阅型的 5 小时 / 本周 / 本月窗口，以及标准 API 账户余额。')
        .fontSize(11)
        .fontColor('#6B6B70')
        .width('100%')
      Divider().color('#2C2C30')
      Text('已知限制')
        .fontSize(12)
        .fontColor('#C8C8CC')
        .width('100%')
      ForEach(this.limitations(), (line: string) => {
        Text(`· ${line}`)
          .fontSize(10)
          .fontColor('#6B6B70')
          .width('100%')
      }, (line: string, index: number) => `limit-${index}`)
    }
    .width('100%')
    .padding(14)
    .backgroundColor('#1C1C1F')
    .borderRadius(12)
  }

  private async load(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      await SettingsStore.init(context);
      this.settings = await SettingsStore.loadSettings();
    } catch (error) {
      Log.e(`settings load failed: ${error}`);
    }
  }

  private async updateInterval(seconds: number): Promise<void> {
    const next: AppSettings = {
      refreshIntervalSec: seconds,
      moneyDecimals: this.settings.moneyDecimals,
      demoMode: this.settings.demoMode,
      showExperimental: this.settings.showExperimental
    };
    this.settings = next;
    await SettingsStore.saveSettings(next);
    this.flashSaved();
  }

  private async updateDecimals(decimals: number): Promise<void> {
    const next: AppSettings = {
      refreshIntervalSec: this.settings.refreshIntervalSec,
      moneyDecimals: decimals,
      demoMode: this.settings.demoMode,
      showExperimental: this.settings.showExperimental
    };
    this.settings = next;
    await SettingsStore.saveSettings(next);
    this.flashSaved();
  }

  private async clearCache(): Promise<void> {
    await SettingsStore.clearSnapshot();
    this.flashSaved();
  }

  private flashSaved(): void {
    this.saved = true;
    setTimeout(() => {
      this.saved = false;
    }, 1500);
  }

  private intervalLabel(seconds: number): string {
    if (seconds < 60) {
      return `${seconds} 秒`;
    }
    return `${Math.round(seconds / 60)} 分钟`;
  }

  private supportText(descriptor: ProviderDescriptor): string {
    const parts: string[] = [];
    if (descriptor.supports.h5) {
      parts.push('5h');
    }
    if (descriptor.supports.week) {
      parts.push('周');
    }
    if (descriptor.supports.month) {
      parts.push('月');
    }
    if (descriptor.kind === 'balance' || descriptor.kind === 'both') {
      parts.push('余额');
    }
    return parts.length === 0 ? '—' : parts.join(' · ');
  }

  private limitations(): string[] {
    return [
      '只收录「一次请求 + 一个 Key」就能查完的来源，需要 Cookie 或 OAuth 的不做。',
      'DeepSeek、Kimi、OpenRouter 的余额接口有官方文档；其余为长期稳定的公开接口。',
      'OpenRouter 必须用 Management Key，普通推理 Key 会返回 403。',
      'Novita 的金额单位是 0.0001 USD，已自动换算成美元。',
      '套餐类来源不提供月度窗口，卡片里会写明「不提供」而不是留空。',
      'Kimi Code 新套餐已取消每周上限，只显示 5 小时滚动窗口。',
      'GLM 团队套餐需要 Organization ID 与 Project ID 两个上下文头。',
      '桌面卡片最快 30 分钟刷新一次，秒级实时依赖应用在前台运行。',
      '不做汇率换算，多币种分行展示。'
    ];
  }
}
