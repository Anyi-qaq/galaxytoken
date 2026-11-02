import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import {
  CustomMode,
  CustomSourceConfig,
  FetchState,
  ProviderConfig,
  ProviderDescriptor,
  ProviderSnapshot
} from '../model/Types';
import { ProviderRegistry } from '../sources/ProviderRegistry';
import { SettingsStore } from '../store/SettingsStore';
import { SecretStore } from '../store/SecretStore';
import { QuotaService } from '../service/QuotaService';
import { Log } from '../common/Logger';
import { SideNav } from '../components/AppShell';
import { LayoutMetrics, SizeClass, metricsFor, watchSizeClass } from '../common/Breakpoints';

/** 来源管理页：启用开关、排序、进入编辑、删除自定义来源。 */
@Entry
@Component
struct ProvidersPage {
  @State configs: ProviderConfig[] = [];
  @State loading: boolean = true;
  @State testing: string = '';
  @State testResult: Record<string, string> = {};
  @State metrics: LayoutMetrics = metricsFor(SizeClass.SM);
  private unwatchSize: (() => void) | undefined = undefined;

  /**
   * 拦截系统返回键 / 侧滑返回。
   *
   * 顶级页面之间用 replaceUrl 互切，页面栈里只有当前页，系统返回会直接退出
   * 应用。这里改成回总览，符合「按返回是退一层，不是退出去」的直觉。
   * 返回 true 表示已消费该事件。
   */
  onBackPress(): boolean {
    router.replaceUrl({ url: 'pages/Index' }).catch((error: Object) => {
      Log.w(`back to index failed: ${error}`);
    });
    return true;
  }

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
          current: 'providers',
          metrics: this.metrics,
          onSelect: (key: string) => {
            // 顶级页面之间一律 replaceUrl：动画一致，且不会堆出多余的返回栈。
            if (key === 'index') {
              router.replaceUrl({ url: 'pages/Index' }).catch((error: Object) => {
                Log.w(`nav index failed: ${error}`);
              });
            } else if (key === 'settings') {
              router.replaceUrl({ url: 'pages/SettingsPage' }).catch((error: Object) => {
                Log.w(`nav settings failed: ${error}`);
              });
            }
          }
        })
      }
      Column() {
        Column() {
          this.header()
          if (this.loading) {
            this.loadingView()
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
    Row({ space: 10 }) {
      if (!this.metrics.sideNav) {
        Button('返回')
          .fontSize(13)
          .height(36)
          .backgroundColor('#242428')
          .fontColor('#D8D8DC')
          .onClick(() => {
            this.goBack();
          })
      }
      Text('数据来源')
        .fontSize(this.metrics.titleSize - 4)
        .fontWeight(FontWeight.Bold)
        .fontColor('#F5F5F7')
        .layoutWeight(1)
      Button('添加')
        .fontSize(13)
        .height(36)
        .backgroundColor('#2D66D8')
        .fontColor('#FFFFFF')
        .bindMenu(this.addMenu())
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
      LoadingProgress().width(32).height(32).color('#9A9A9E')
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  listView() {
    List({ space: 10 }) {
      ForEach(this.sortedConfigs(), (config: ProviderConfig) => {
        ListItem() {
          this.row(config)
        }
      }, (config: ProviderConfig) => `${config.providerId}-${config.enabled}-${config.order}`)

      ListItem() {
        Text('未启用的来源不会发起任何网络请求。')
          .fontSize(11)
          .fontColor('#8A8A8E')
          .width('100%')
          .padding({ top: 10, bottom: 24 })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .padding({
      left: this.metrics.pagePadding,
      right: this.metrics.pagePadding
    })
    .scrollBar(BarState.Off)
  }

  @Builder
  row(config: ProviderConfig) {
    Column({ space: 8 }) {
      Row({ space: 10 }) {
        Column({ space: 3 }) {
          Row({ space: 6 }) {
            Text(this.nameOf(config))
              .fontSize(15)
              .fontColor('#F2F2F4')
              .fontWeight(FontWeight.Medium)
            if (this.isExperimental(config)) {
              Text('实验')
                .fontSize(10)
                .fontColor('#F2A33C')
                .backgroundColor('#3A2A12')
                .padding({ left: 5, right: 5, top: 1, bottom: 1 })
                .borderRadius(6)
            }
            if (this.needsAuth(config)) {
              Text('待配置')
                .fontSize(10)
                .fontColor('#7AA2F7')
                .backgroundColor('#17233A')
                .padding({ left: 5, right: 5, top: 1, bottom: 1 })
                .borderRadius(6)
            }
          }
          Text(this.summaryOf(config))
            .fontSize(11)
            .fontColor('#9A9A9E')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: config.enabled })
          .selectedColor('#2D66D8')
          .accessibilityText(`启用 ${this.nameOf(config)}`)
          .onChange((isOn: boolean) => {
            this.toggle(config.providerId, isOn);
          })
      }
      .width('100%')

      Row({ space: 8 }) {
        Button('编辑')
          .fontSize(11)
          .height(34)
          .backgroundColor('#2A2A2E')
          .fontColor('#C8C8CC')
          .onClick(() => {
            this.edit(config.providerId);
          })
        if (config.enabled) {
          Button(this.testing === config.providerId ? '测试中…' : '测试')
            .fontSize(11)
            .height(34)
            .backgroundColor('#2A2A2E')
            .fontColor('#C8C8CC')
            .enabled(this.testing !== config.providerId)
            .onClick(() => {
              this.testOne(config);
            })
        }
        if (ProviderRegistry.isCustom(config.providerId)) {
          Button('删除')
            .fontSize(11)
            .height(34)
            .backgroundColor('#2B0F0B')
            .fontColor('#F0523A')
            .onClick(() => {
              this.removeCustom(config.providerId);
            })
        }
        Blank()
        Button('上移')
          .fontSize(11)
          .height(34)
          .backgroundColor('#2A2A2E')
          .fontColor('#C8C8CC')
          .onClick(() => {
            this.move(config.providerId, -1);
          })
        Button('下移')
          .fontSize(11)
          .height(34)
          .backgroundColor('#2A2A2E')
          .fontColor('#C8C8CC')
          .onClick(() => {
            this.move(config.providerId, 1);
          })
      }
      .width('100%')

      if (this.testResult[config.providerId] !== undefined) {
        Text(this.testResult[config.providerId])
          .fontSize(11)
          .fontColor(this.testOk(config.providerId) ? '#3BA55D' : '#F0523A')
          .width('100%')
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor('#1C1C1F')
    .borderRadius(12)
    .border({ width: 1, color: '#2C2C30' })
  }

  private async load(): Promise<void> {
    this.loading = true;
    try {
      const context = getContext(this) as common.UIAbilityContext;
      await SettingsStore.init(context);
      const stored = await SettingsStore.loadProviders();
      const merged = stored.slice();
      let order = merged.length;
      for (const descriptor of ProviderRegistry.all()) {
        if (merged.some((c: ProviderConfig) => c.providerId === descriptor.id)) {
          continue;
        }
        merged.push(ProviderRegistry.defaultConfig(descriptor, order));
        order += 1;
      }
      this.configs = merged;
      await SettingsStore.saveProviders(merged);
    } catch (error) {
      Log.e(`providers load failed: ${error}`);
    } finally {
      this.loading = false;
    }
  }

  private sortedConfigs(): ProviderConfig[] {
    return this.configs.slice().sort((a: ProviderConfig, b: ProviderConfig) => a.order - b.order);
  }

  private nameOf(config: ProviderConfig): string {
    if (config.displayName !== undefined && config.displayName !== '') {
      return config.displayName;
    }
    const descriptor = ProviderRegistry.descriptorOf(config.providerId);
    return descriptor === undefined ? config.providerId : descriptor.name;
  }

  private summaryOf(config: ProviderConfig): string {
    const descriptor = ProviderRegistry.descriptorOf(config.providerId);
    if (descriptor !== undefined) {
      return descriptor.summary;
    }
    if (ProviderRegistry.isCustom(config.providerId)) {
      return '自定义端点与字段映射';
    }
    return '';
  }

  private isExperimental(config: ProviderConfig): boolean {
    const descriptor = ProviderRegistry.descriptorOf(config.providerId);
    return descriptor !== undefined && descriptor.experimental;
  }

  private needsAuth(config: ProviderConfig): boolean {
    return config.enabled && !config.hasSecret && this.requiresSecret(config.providerId);
  }

  private requiresSecret(providerId: string): boolean {
    if (providerId === 'demo') {
      return false;
    }
    const descriptor = ProviderRegistry.descriptorOf(providerId);
    if (descriptor === undefined) {
      return true;
    }
    return descriptor.credentialFields.some((f) => f.kind === 'secret' && f.required);
  }

  private testOk(providerId: string): boolean {
    const result = this.testResult[providerId];
    return result !== undefined && result.startsWith('OK');
  }

  private async toggle(providerId: string, isOn: boolean): Promise<void> {
    this.configs = this.configs.map((c: ProviderConfig) => {
      if (c.providerId !== providerId) {
        return c;
      }
      const copy: ProviderConfig = {
        providerId: c.providerId,
        enabled: isOn,
        order: c.order,
        baseUrl: c.baseUrl,
        plainFields: c.plainFields,
        hasSecret: c.hasSecret,
        displayName: c.displayName,
        custom: c.custom
      };
      return copy;
    });
    await SettingsStore.saveProviders(this.configs);
  }

  private async move(providerId: string, delta: number): Promise<void> {
    const sorted = this.sortedConfigs();
    const index = sorted.findIndex((c: ProviderConfig) => c.providerId === providerId);
    const target = index + delta;
    if (index < 0 || target < 0 || target >= sorted.length) {
      return;
    }
    const a = sorted[index];
    const b = sorted[target];
    const tmp = a.order;
    a.order = b.order;
    b.order = tmp;
    // 重新归一化，避免 order 值发散。
    const renumbered = sorted.slice().sort((x: ProviderConfig, y: ProviderConfig) => x.order - y.order);
    for (let i = 0; i < renumbered.length; i++) {
      renumbered[i].order = i;
    }
    this.configs = renumbered;
    await SettingsStore.saveProviders(renumbered);
  }

  private async testOne(config: ProviderConfig): Promise<void> {
    this.testing = config.providerId;
    try {
      const snapshot: ProviderSnapshot = await QuotaService.refreshOne(config);
      if (snapshot.state === FetchState.OK || snapshot.state === FetchState.PARTIAL) {
        this.testResult[config.providerId] = `OK · ${this.describe(snapshot)}`;
      } else {
        const message = snapshot.error === undefined ? '未知错误' : snapshot.error.message;
        this.testResult[config.providerId] = `失败：${message}`;
      }
    } catch (error) {
      this.testResult[config.providerId] = `失败：${error instanceof Error ? error.message : error}`;
    } finally {
      this.testing = '';
    }
  }

  private describe(snapshot: ProviderSnapshot): string {
    const parts: string[] = [];
    if (snapshot.windows.length > 0) {
      parts.push(`${snapshot.windows.length} 个窗口`);
    }
    if (snapshot.balances.length > 0) {
      parts.push(`余额 ${snapshot.balances[0].amount} ${snapshot.balances[0].currency}`);
    }
    return parts.length === 0 ? '已连通' : parts.join('，');
  }

  private edit(providerId: string): void {
    router.pushUrl({ url: 'pages/ProviderEditPage', params: { providerId: providerId } })
      .catch((error: Object) => {
        Log.w(`open edit failed: ${error}`);
      });
  }

  /** 「添加」按钮的菜单：先选用途，再进编辑页。 */
  private addMenu(): MenuElement[] {
    return [
      {
        value: '添加套餐来源',
        action: () => {
          this.addCustom(CustomMode.PLAN);
        }
      },
      {
        value: '添加按量付费来源',
        action: () => {
          this.addCustom(CustomMode.PAYG);
        }
      }
    ];
  }

  /** 新增一条自定义来源。mode 决定它是查套餐窗口还是查余额。 */
  private async addCustom(mode: CustomMode): Promise<void> {
    let index = 0;
    let id = 'custom';
    while (this.configs.some((c: ProviderConfig) => c.providerId === id)) {
      index += 1;
      id = `custom-${index}`;
    }
    const plan = mode === CustomMode.PLAN;
    const baseName = plan ? '自定义套餐' : '自定义按量付费';
    const custom: CustomSourceConfig = {
      mode: mode,
      url: '',
      method: 'GET',
      authMode: 'bearer',
      extraHeaders: {}
    };
    const config: ProviderConfig = {
      providerId: id,
      enabled: false,
      order: this.configs.length,
      baseUrl: '',
      plainFields: {},
      hasSecret: false,
      displayName: `${baseName} ${index + 1}`,
      custom: custom
    };
    this.configs = this.configs.concat([config]);
    await SettingsStore.saveProviders(this.configs);
    this.edit(id);
  }

  private async removeCustom(providerId: string): Promise<void> {
    this.configs = this.configs.filter((c: ProviderConfig) => c.providerId !== providerId);
    await SettingsStore.saveProviders(this.configs);
    await SecretStore.remove(providerId);
  }

  /**
   * 窄屏「返回」回总览。
   *
   * 顶级页面之间用 replaceUrl 切换，页面栈里没有上一页可 back，所以这里必须
   * 显式 replace 回首页，否则返回按钮点了没反应。
   */
  private goBack(): void {
    router.replaceUrl({ url: 'pages/Index' }).catch((error: Object) => {
      Log.w(`nav index failed: ${error}`);
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
