import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import {
  AppSettings,
  DashboardSnapshot,
  FetchState,
  ProviderConfig,
  ProviderSnapshot
} from '../model/Types';
import { ProviderRegistry } from '../sources/ProviderRegistry';
import { QuotaService } from '../service/QuotaService';
import { FormBridge } from '../service/FormBridge';
import { SettingsStore } from '../store/SettingsStore';
import { ProviderCard } from '../components/ProviderCard';
import { SideNav } from '../components/AppShell';
import { LayoutMetrics, SizeClass, metricsFor, watchSizeClass } from '../common/Breakpoints';
import { relativeTime } from '../common/Format';
import { Log } from '../common/Logger';

/**
 * 首页：所有已启用来源的额度看板。
 *
 * 生命周期：
 * - onPageShow：立即刷新一次并启动轮询；
 * - onPageHide：停止轮询，避免后台空耗；
 * - 下拉刷新：手动触发。
 */
@Entry
@Component
struct Index {
  @State dashboard: DashboardSnapshot | undefined = undefined;
  @State configs: ProviderConfig[] = [];
  @State settings: AppSettings = {
    refreshIntervalSec: 60,
    moneyDecimals: 2,
    demoMode: false,
    showExperimental: true
  };
  @State refreshing: boolean = false;
  @State now: number = Date.now();
  @State errorText: string = '';
  @State loading: boolean = true;
  /** 当前断点对应的布局参数；窗口尺寸变化时更新。 */
  @State metrics: LayoutMetrics = metricsFor(SizeClass.SM);

  private timerId: number = -1;
  private clockId: number = -1;
  private visible: boolean = false;
  private bootstrapped: boolean = false;
  private unwatchSize: (() => void) | undefined = undefined;

  aboutToAppear(): void {
    this.bootstrap();
    // 监听窗口宽度：平板横竖屏切换、2in1 自由缩放、手机分屏都能实时重排。
    try {
      this.unwatchSize = watchSizeClass(this.getUIContext(), (sizeClass: SizeClass) => {
        this.metrics = metricsFor(sizeClass);
      });
    } catch (error) {
      Log.w(`size class watch failed: ${error}`);
    }
  }

  onPageShow(): void {
    this.visible = true;
    this.startClock();
    if (this.bootstrapped) {
      this.reloadConfigs();
    }
    this.startPolling();
  }

  onPageHide(): void {
    this.visible = false;
    this.stopPolling();
    this.stopClock();
  }

  aboutToDisappear(): void {
    this.stopPolling();
    this.stopClock();
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
          current: 'index',
          metrics: this.metrics,
          onSelect: (key: string) => {
            this.onNavSelect(key);
          }
        })
      }
      Column() {
        Column() {
          this.header()
          if (this.loading) {
            this.loadingView()
          } else if (this.errorText !== '') {
            this.errorView()
          } else if (this.activeSnapshots().length === 0) {
            this.emptyView()
          } else {
            this.listView()
          }
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
    Row() {
      Column({ space: 2 }) {
        Text('星河 Token')
          .fontSize(this.metrics.titleSize)
          .fontWeight(FontWeight.Bold)
          .fontColor('#F5F5F7')
        Text(this.subtitleText())
          .fontSize(11)
          .fontColor('#6B6B70')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (!this.metrics.sideNav) {
        Button('来源')
          .fontSize(13)
          .height(32)
          .backgroundColor('#242428')
          .fontColor('#D8D8DC')
          .onClick(() => {
            this.openPage('pages/ProvidersPage');
          })
        Button('设置')
          .fontSize(13)
          .height(32)
          .margin({ left: 8 })
          .backgroundColor('#242428')
          .fontColor('#D8D8DC')
          .onClick(() => {
            this.openPage('pages/SettingsPage');
          })
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
  loadingView() {
    Column() {
      LoadingProgress().width(36).height(36).color('#6B6B70')
      Text('正在读取来源配置…').fontSize(12).fontColor('#6B6B70').margin({ top: 10 })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  errorView() {
    Column({ space: 10 }) {
      Text('初始化失败').fontSize(15).fontColor('#E84026')
      Text(this.errorText).fontSize(12).fontColor('#A05A50').textAlign(TextAlign.Center)
      Button('重新加载')
        .fontSize(13)
        .backgroundColor('#2A2A2E')
        .fontColor('#E8E8EA')
        .onClick(() => {
          this.bootstrapped = false;
          this.loading = true;
          this.errorText = '';
          this.bootstrap();
        })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding(24)
  }

  @Builder
  emptyView() {
    Column({ space: 12 }) {
      Text('还没有启用的来源').fontSize(15).fontColor('#C8C8CC')
      Text('去「来源」里打开至少一个数据源；想先看效果可以启用「演示数据」。')
        .fontSize(12)
        .fontColor('#6B6B70')
        .textAlign(TextAlign.Center)
      Row({ space: 10 }) {
        Button('选择来源')
          .fontSize(13)
          .backgroundColor('#3478F6')
          .fontColor('#FFFFFF')
          .onClick(() => {
            this.openPage('pages/ProvidersPage');
          })
        Button('启用演示')
          .fontSize(13)
          .backgroundColor('#2A2A2E')
          .fontColor('#E8E8EA')
          .onClick(() => {
            this.enableDemo();
          })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding(24)
  }

  @Builder
  listView() {
    Refresh({ refreshing: $$this.refreshing }) {
      Scroll() {
        Column({ space: this.metrics.cardGap }) {
          this.grid()
          Text(`共 ${this.activeSnapshots().length} 个来源 · ${relativeTime(this.refreshedAt(), this.now)}`)
            .fontSize(11)
            .fontColor('#5C5C60')
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ top: 8, bottom: 24 })
        }
        .width('100%')
        .padding({
          left: this.metrics.pagePadding,
          right: this.metrics.pagePadding
        })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
    }
    .onRefreshing(() => {
      this.refresh(true);
    })
    .width('100%')
    .layoutWeight(1)
  }

  /**
   * 卡片网格：按断点分列。
   *
   * 用可换行的 Flex 而不是 Grid —— 卡片高度不一致时 Flex 不会出现行高被拉齐的空白。
   */
  @Builder
  grid() {
    Flex({
      direction: FlexDirection.Row,
      wrap: FlexWrap.Wrap,
      justifyContent: FlexAlign.Start
    }) {
      ForEach(this.activeSnapshots(), (item: ProviderSnapshot) => {
        Column() {
          ProviderCard({
            snapshot: item,
            now: this.now,
            moneyDecimals: this.settings.moneyDecimals,
            metrics: this.metrics,
            onRetry: (id: string) => {
              this.retryOne(id);
            },
            onConfigure: (id: string) => {
              this.openEdit(id);
            }
          })
        }
        .width(this.cardWidth())
        .padding({ right: this.columnGap(), bottom: this.metrics.cardGap })
      }, (item: ProviderSnapshot) => `${item.providerId}-${item.fetchedAt}`)
    }
    .width('100%')
  }

  /**
   * 实际生效的列数。
   *
   * 来源数少于断点列数时按来源数收窄，避免「一个来源只占半屏」的塌陷感；
   * 例如 2in1 上只启用 1 个来源时，卡片会铺满一行。
   */
  private effectiveColumns(): number {
    const count = this.activeSnapshots().length;
    if (count <= 0) {
      return 1;
    }
    return Math.min(this.metrics.columns, count);
  }

  /** 卡片宽度：单列满宽；多列按比例并扣除间隙。 */
  private cardWidth(): string {
    const columns = this.effectiveColumns();
    if (columns <= 1) {
      return '100%';
    }
    return `${100 / columns}%`;
  }

  /** 列间距用右内边距实现，最后一列会多一点右侧留白，视觉上可接受。 */
  private columnGap(): number {
    return this.metrics.cardGap;
  }

  /** 初始化：注册来源、读配置、首次刷新。 */
  private async bootstrap(): Promise<void> {
    this.loading = true;
    this.errorText = '';
    try {
      const context = getContext(this) as common.UIAbilityContext;
      await SettingsStore.init(context);
      this.settings = await SettingsStore.loadSettings();
      const stored = await SettingsStore.loadProviders();
      this.configs = await this.mergeWithRegistry(stored);
      const cached = await SettingsStore.loadSnapshot();
      if (cached !== undefined) {
        this.dashboard = cached;
      }
      this.loading = false;
      this.bootstrapped = true;
      await this.refresh(false);
      this.startPolling();
    } catch (error) {
      const message = error instanceof Error ? error.message : `${error}`;
      Log.e(`bootstrap failed: ${message}`);
      this.errorText = message;
      this.loading = false;
    }
  }

  /** 从其他页面返回时重新读配置（来源可能在别处被改动）。 */
  private async reloadConfigs(): Promise<void> {
    this.settings = await SettingsStore.loadSettings();
    this.configs = await this.mergeWithRegistry(await SettingsStore.loadProviders());
    await this.refresh(false);
  }

  /**
   * 把注册表里的新来源补进配置，并清掉已经从注册表移除的旧来源。
   *
   * 「移除」这件事必须做：用户升级前存过已经下线的来源（例如早期版本的
   * commandcode），不清掉就会在来源列表里留下一条只有 id、没有名字的僵尸项。
   * 自定义来源（custom-*）不算移除，它们由用户自己维护。
   */
  private async mergeWithRegistry(stored: ProviderConfig[]): Promise<ProviderConfig[]> {
    const result: ProviderConfig[] = [];
    let changed = false;
    for (const config of stored) {
      if (ProviderRegistry.isCustom(config.providerId)) {
        result.push(config);
        continue;
      }
      const descriptor = ProviderRegistry.descriptorOf(config.providerId);
      if (descriptor === undefined) {
        // 注册表里已经没有这个来源了：丢弃，并标记需要回写。
        Log.w(`drop retired provider: ${config.providerId}`);
        changed = true;
        continue;
      }
      result.push(config);
    }
    let order = result.length;
    for (const descriptor of ProviderRegistry.all()) {
      const existing = result.find((c: ProviderConfig) => c.providerId === descriptor.id);
      if (existing !== undefined) {
        continue;
      }
      const config = ProviderRegistry.defaultConfig(descriptor, order);
      order += 1;
      result.push(config);
      changed = true;
    }
    if (changed) {
      await SettingsStore.saveProviders(result);
    }
    return result;
  }

  /** 拉取所有启用来源。 */
  private async refresh(manual: boolean): Promise<void> {
    if (manual) {
      this.refreshing = true;
    }
    try {
      const snapshot = await QuotaService.refreshAll(this.configs);
      this.dashboard = snapshot;
      this.now = Date.now();
      // 前台拿到新数据后主动推一次卡片，弥补系统 30 分钟的刷新上限。
      FormBridge.push(snapshot).catch((error: Object) => {
        Log.w(`form push failed: ${error}`);
      });
    } catch (error) {
      Log.e(`refresh failed: ${error}`);
    } finally {
      this.refreshing = false;
    }
  }

  /** 单来源重试。 */
  private async retryOne(providerId: string): Promise<void> {
    const config = this.configs.find((c: ProviderConfig) => c.providerId === providerId);
    if (config === undefined) {
      return;
    }
    const snapshot = await QuotaService.refreshOne(config);
    const current = this.dashboard;
    const list: ProviderSnapshot[] = current === undefined ? [] : current.providers.slice();
    const index = list.findIndex((p: ProviderSnapshot) => p.providerId === providerId);
    if (index >= 0) {
      list[index] = snapshot;
    } else {
      list.push(snapshot);
    }
    this.dashboard = {
      providers: list,
      refreshedAt: Date.now(),
      tightestProviderId: current === undefined ? undefined : current.tightestProviderId,
      tightestKind: current === undefined ? undefined : current.tightestKind,
      tightestUsedRatio: current === undefined ? undefined : current.tightestUsedRatio
    };
    this.now = Date.now();
  }

  /** 轮询：按设置的间隔周期性刷新。 */
  private startPolling(): void {
    this.stopPolling();
    const interval = Math.max(this.settings.refreshIntervalSec, 30) * 1000;
    this.timerId = setInterval(() => {
      if (this.visible) {
        this.refresh(false);
      }
    }, interval);
  }

  private stopPolling(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  /** 倒计时用的秒级心跳，只更新本地时间，不触发网络。 */
  private startClock(): void {
    this.stopClock();
    this.clockId = setInterval(() => {
      this.now = Date.now();
    }, 1000);
  }

  private stopClock(): void {
    if (this.clockId >= 0) {
      clearInterval(this.clockId);
      this.clockId = -1;
    }
  }

  /** 启用演示来源。 */
  private async enableDemo(): Promise<void> {
    const updated: ProviderConfig[] = [];
    for (const config of this.configs) {
      if (config.providerId === 'demo') {
        updated.push({
          providerId: config.providerId,
          enabled: true,
          order: config.order,
          baseUrl: config.baseUrl,
          plainFields: config.plainFields,
          hasSecret: config.hasSecret,
          displayName: config.displayName,
          custom: config.custom
        });
      } else {
        updated.push(config);
      }
    }
    this.configs = updated;
    await SettingsStore.saveProviders(updated);
    await this.refresh(true);
  }

  private activeSnapshots(): ProviderSnapshot[] {
    const dashboard = this.dashboard;
    if (dashboard === undefined) {
      return [];
    }
    return dashboard.providers.slice().sort((a: ProviderSnapshot, b: ProviderSnapshot) => {
      return this.orderOf(a.providerId) - this.orderOf(b.providerId);
    });
  }

  private orderOf(providerId: string): number {
    const config = this.configs.find((c: ProviderConfig) => c.providerId === providerId);
    return config === undefined ? 999 : config.order;
  }

  private refreshedAt(): number {
    return this.dashboard === undefined ? 0 : this.dashboard.refreshedAt;
  }

  private subtitleText(): string {
    const total = this.activeSnapshots().length;
    if (total === 0) {
      return '未启用来源';
    }
    const failed = this.activeSnapshots().filter(
      (p: ProviderSnapshot) => p.state === FetchState.ERROR || p.state === FetchState.NEEDS_AUTH
    ).length;
    const interval = this.settings.refreshIntervalSec >= 60
      ? `${Math.round(this.settings.refreshIntervalSec / 60)} 分钟`
      : `${this.settings.refreshIntervalSec} 秒`;
    if (failed > 0) {
      return `${total} 个来源 · ${failed} 个异常 · 每 ${interval} 刷新`;
    }
    return `${total} 个来源 · 每 ${interval} 刷新`;
  }

  /** 侧边导航选择。 */
  private onNavSelect(key: string): void {
    if (key === 'providers') {
      this.openPage('pages/ProvidersPage');
      return;
    }
    if (key === 'settings') {
      this.openPage('pages/SettingsPage');
      return;
    }
    // index：已经在本页，直接刷新。
    this.refresh(true);
  }

  /** 跳到某个来源的编辑页。 */
  private openEdit(providerId: string): void {
    router.pushUrl({ url: 'pages/ProviderEditPage', params: { providerId: providerId } })
      .catch((error: Object) => {
        Log.w(`open edit failed: ${error}`);
      });
  }

  /**
   * 跳转到另一个顶级页面。
   *
   * 三个顶级页面（总览 / 来源 / 设置）之间是平级关系，用 replaceUrl 而不是
   * pushUrl，页面栈里始终只有一个顶级页：
   *   - 三者之间的转场动画完全一致（都是 Replace，走同一套 pageTransition）
   *   - 不会出现「设置 → 返回 → 却回到来源」这种回退错位
   */
  private openPage(url: string): void {
    router.replaceUrl({ url: url }).catch((error: Object) => {
      Log.w(`open page failed: ${error}`);
    });
  }

  /**
   * 顶级页面统一转场。
   *
   * 总览 / 来源 / 设置三者是平级关系，一律用 replaceUrl 互切，所以只需要一套
   * 淡入淡出：不区分 Push/Pop，也就不存在「从哪里来回哪里去」的方向差异。
   * 幅度刻意做小（位移 8vp、时长 180ms），避免每次切导航都像翻页一样晃眼。
   */
  pageTransition() {
    PageTransitionEnter({ duration: 180, curve: Curve.EaseOut })
      .opacity(0)
      .translate({ x: 8 })
    PageTransitionExit({ duration: 180, curve: Curve.EaseIn })
      .opacity(0)
      .translate({ x: -8 })
  }

}
