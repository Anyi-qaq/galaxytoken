import {
  DashboardSnapshot,
  ErrorKind,
  FetchState,
  ProviderConfig,
  ProviderSnapshot,
  QuotaWindow,
  SourceKind,
  WindowKind,
  remainingRatio,
  windowRank
} from '../model/Types';
import { FetchContext } from '../sources/SourceAdapter';
import { ProviderRegistry } from '../sources/ProviderRegistry';
import { toErrorSnapshot } from '../sources/AdapterKit';
import { SecretStore } from '../store/SecretStore';
import { SettingsStore } from '../store/SettingsStore';
import { CustomAdapter } from '../sources/adapters/CustomAdapter';
import { DemoAdapter } from '../sources/adapters/DemoAdapter';
import { Log } from '../common/Logger';

/** 一个可执行的刷新任务。 */
interface RefreshJob {
  config: ProviderConfig;
  context: FetchContext;
}

/**
 * 聚合服务：并发拉取所有启用的来源。
 *
 * 关键约束：
 * - 单个来源失败绝不影响其他来源；
 * - 结果全量写入 preferences，供卡片与冷启动使用；
 * - 不做任何跨来源的数值相加（不同单位不可加）。
 */
export class QuotaService {
  /** 拉取全部启用来源。 */
  static async refreshAll(configs: ProviderConfig[]): Promise<DashboardSnapshot> {
    const now = Date.now();
    const enabled = configs
      .filter((c: ProviderConfig) => c.enabled)
      .sort((a: ProviderConfig, b: ProviderConfig) => a.order - b.order);

    const jobs: RefreshJob[] = [];
    for (const config of enabled) {
      const job = await QuotaService.prepare(config, now);
      if (job !== undefined) {
        jobs.push(job);
      }
    }

    const snapshots: ProviderSnapshot[] = [];
    if (jobs.length > 0) {
      const tasks: Promise<ProviderSnapshot>[] = jobs.map(
        (job: RefreshJob) => QuotaService.runJob(job, now)
      );
      const results = await Promise.all(tasks);
      for (const result of results) {
        snapshots.push(result);
      }
    }

    const dashboard: DashboardSnapshot = {
      providers: snapshots,
      refreshedAt: now
    };
    QuotaService.applyTightest(dashboard);
    try {
      await SettingsStore.saveSnapshot(dashboard);
    } catch (error) {
      Log.w('failed to persist snapshot');
    }
    return dashboard;
  }

  /** 只拉取单个来源（用于「测试连接」）。 */
  static async refreshOne(config: ProviderConfig): Promise<ProviderSnapshot> {
    const now = Date.now();
    const job = await QuotaService.prepare(config, now);
    if (job === undefined) {
      return {
        providerId: config.providerId,
        name: ProviderRegistry.descriptorOf(config.providerId)?.name ?? config.providerId,
        kind: ProviderRegistry.descriptorOf(config.providerId)?.kind ?? SourceKind.BOTH,
        state: FetchState.NEEDS_AUTH,
        windows: [],
        balances: [],
        extra: {},
        fetchedAt: now,
        error: { kind: ErrorKind.UNAUTHORIZED, httpStatus: 0, message: '缺少凭据或适配器未注册' }
      };
    }
    return QuotaService.runJob(job, now);
  }

  /** 组装一个来源的请求上下文。 */
  private static async prepare(config: ProviderConfig, now: number): Promise<RefreshJob | undefined> {
    const adapter = QuotaService.resolveAdapter(config);
    if (adapter === undefined) {
      return undefined;
    }
    const secret = await SecretStore.load(config.providerId);
    const context: FetchContext = {
      plain: config.plainFields === undefined ? {} : config.plainFields,
      secret: secret,
      baseUrl: config.baseUrl,
      now: now
    };
    return { config: config, context: context };
  }

  /** 解析适配器：自定义来源动态构造。 */
  private static resolveAdapter(config: ProviderConfig) {
    if (ProviderRegistry.isCustom(config.providerId)) {
      const custom = new CustomAdapter(config);
      return custom;
    }
    return ProviderRegistry.adapterOf(config.providerId);
  }

  /** 执行一次拉取并收敛异常。 */
  private static async runJob(job: RefreshJob, now: number): Promise<ProviderSnapshot> {
    const adapter = QuotaService.resolveAdapter(job.config);
    const startedAt = Date.now();
    if (adapter === undefined) {
      return {
        providerId: job.config.providerId,
        name: job.config.providerId,
        kind: SourceKind.BOTH,
        state: FetchState.ERROR,
        windows: [],
        balances: [],
        extra: {},
        fetchedAt: now,
        error: { kind: ErrorKind.NOT_FOUND, httpStatus: 0, message: '来源未注册' }
      };
    }
    try {
      const snapshot = await adapter.fetch(job.context);
      snapshot.elapsedMs = Date.now() - startedAt;
      return snapshot;
    } catch (error) {
      const secrets: string[] = Object.keys(job.context.secret).map(
        (key: string) => job.context.secret[key]
      );
      Log.w(`provider ${job.config.providerId} failed: ${error}`);
      return toErrorSnapshot(adapter.descriptor, error, Date.now(), startedAt, secrets);
    }
  }

  /** 计算「最紧张」的窗口，供卡片高亮。 */
  private static applyTightest(dashboard: DashboardSnapshot): void {
    let bestProvider: string | undefined = undefined;
    let bestKind: WindowKind | undefined = undefined;
    let bestRemaining: number = 2;
    for (const snapshot of dashboard.providers) {
      if (snapshot.state !== FetchState.OK && snapshot.state !== FetchState.PARTIAL) {
        continue;
      }
      for (const window of snapshot.windows) {
        const left = remainingRatio(window);
        if (left === undefined) {
          continue;
        }
        if (window.resetAt !== undefined && window.resetAt <= dashboard.refreshedAt) {
          continue;
        }
        if (left < bestRemaining) {
          bestRemaining = left;
          bestProvider = snapshot.providerId;
          bestKind = window.kind;
        }
      }
    }
    dashboard.tightestProviderId = bestProvider;
    dashboard.tightestKind = bestKind;
    dashboard.tightestUsedRatio = bestProvider === undefined ? undefined : 1 - bestRemaining;
  }

  /** 取某个来源的快照。 */
  static find(dashboard: DashboardSnapshot | undefined, providerId: string): ProviderSnapshot | undefined {
    if (dashboard === undefined) {
      return undefined;
    }
    return dashboard.providers.find((p: ProviderSnapshot) => p.providerId === providerId);
  }

  /** 按 H5/WEEK/MONTH 排序窗口。 */
  static sortWindows(windows: QuotaWindow[]): QuotaWindow[] {
    return windows.slice().sort((a: QuotaWindow, b: QuotaWindow) => windowRank(a.kind) - windowRank(b.kind));
  }
}
