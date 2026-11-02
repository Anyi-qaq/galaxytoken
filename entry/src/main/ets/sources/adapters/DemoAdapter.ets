import { SourceAdapter, FetchContext } from '../SourceAdapter';
import {
  CredentialField,
  FetchState,
  FieldKind,
  ProviderDescriptor,
  ProviderSnapshot,
  QuotaMode,
  QuotaWindow,
  SourceKind,
  WindowKind
} from '../../model/Types';

/**
 * 演示来源：不发起任何网络请求，用固定数据展示三窗口 + 余额 + 倒计时。
 *
 * 用途：
 * - 首次安装即可看到完整 UI，不需要真实 Key；
 * - 单元测试与 UI 验收的稳定数据源。
 *
 * 数据刻意设计成「快照时刻 + 偏移」的形式，保证运行多久都不会显示已过期。
 */
export class DemoAdapter implements SourceAdapter {
  readonly descriptor: ProviderDescriptor = {
    id: 'demo',
    name: '演示数据',
    kind: SourceKind.BOTH,
    summary: '内置示例数据，不联网。用于首次体验与界面验收。',
    supports: { h5: true, week: true, month: true },
    credentialFields: [] as CredentialField[],
    baseUrlEditable: false,
    defaultBaseUrl: '',
    experimental: false,
    usesBrowserSession: false,
    apiNote: '本地假数据，不代表任何真实账户。'
  };

  async fetch(context: FetchContext): Promise<ProviderSnapshot> {
    const now = context.now;
    const windows: QuotaWindow[] = [
      {
        kind: WindowKind.H5,
        mode: QuotaMode.RATIO,
        usedRatio: 0.62,
        resetAt: now + 2 * 3600 * 1000 + 44 * 60 * 1000
      },
      {
        kind: WindowKind.WEEK,
        mode: QuotaMode.RATIO,
        usedRatio: 0.31,
        resetAt: now + 4 * 86400 * 1000 + 3 * 3600 * 1000
      },
      {
        kind: WindowKind.MONTH,
        mode: QuotaMode.RATIO,
        usedRatio: 0.18,
        resetAt: now + 21 * 86400 * 1000
      }
    ];
    return {
      providerId: this.descriptor.id,
      name: this.descriptor.name,
      kind: this.descriptor.kind,
      state: FetchState.OK,
      windows: windows,
      balances: [
        { amount: 128.45, currency: 'CNY', granted: 20, toppedUp: 108.45, note: '演示数据' }
      ],
      extra: { planName: '演示套餐 · Develop', creditsBalance: 820, creditsUnit: 'credits' },
      fetchedAt: now,
      elapsedMs: 0
    };
  }
}
