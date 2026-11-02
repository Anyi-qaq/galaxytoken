import { FetchContext, SourceAdapter } from '../SourceAdapter';
import {
  BalanceInfo,
  CustomFieldMapping,
  CustomMode,
  CustomSourceConfig,
  FetchState,
  MappingSemantics,
  ProviderConfig,
  ProviderDescriptor,
  ProviderSnapshot,
  QuotaMode,
  QuotaWindow,
  SourceKind,
  WindowKind
} from '../../model/Types';
import { asObject, pickPath, toEpochMs, toNum, toStr, truncate } from '../../model/JsonValue';
import { Headers, HttpClient, HttpResult } from '../../net/HttpClient';
import { ProviderRegistry } from '../ProviderRegistry';
import { BROWSER_UA, RAW_SNIPPET_CHARS } from '../../common/Constants';
import { redact } from '../../common/Logger';

/**
 * 自定义来源：用户填写 HTTPS 端点 + 认证方式 + JSON 字段路径。
 *
 * 用于覆盖没有内置适配器的厂商（例如蚂蚁数科 Token Plan 的控制台接口）。
 * 设计上只做「按路径取数 + 语义解释」，不做任何推测。
 */
export class CustomAdapter implements SourceAdapter {
  readonly descriptor: ProviderDescriptor;
  private readonly config: ProviderConfig;

  constructor(config: ProviderConfig) {
    this.config = config;
    const base = ProviderRegistry.customDescriptor();
    const plan = CustomAdapter.isPlanMode(config);
    const defaultName = plan ? '自定义套餐' : '自定义按量付费';
    this.descriptor = {
      id: config.providerId,
      name: config.displayName === undefined || config.displayName === ''
        ? defaultName : config.displayName,
      kind: plan ? SourceKind.SUBSCRIPTION : SourceKind.BALANCE,
      summary: base.summary,
      // 套餐只声明时间窗口，按量付费只声明余额 —— 声明与实际一致，
      // 卡片就不会为另一方渲染一排「不提供此窗口」。
      supports: plan
        ? { h5: true, week: true, month: true }
        : { h5: false, week: false, month: false },
      credentialFields: base.credentialFields,
      baseUrlEditable: true,
      defaultBaseUrl: config.baseUrl,
      experimental: false,
      usesBrowserSession: false,
      apiNote: base.apiNote
    };
  }

  /** 按配置构造一个 adapter（编辑页只需要它的 descriptor，不发起请求）。 */
  static forConfig(config: ProviderConfig): CustomAdapter {
    return new CustomAdapter(config);
  }

  /** 该自定义来源是不是「套餐」用途。缺省为套餐，兼容旧配置。 */
  static isPlanMode(config: ProviderConfig): boolean {
    const custom = config.custom;
    if (custom === undefined || custom.mode === undefined) {
      return true;
    }
    return custom.mode === CustomMode.PLAN;
  }

  async fetch(context: FetchContext): Promise<ProviderSnapshot> {
    const custom = this.config.custom;
    if (custom === undefined) {
      throw new Error('自定义来源尚未配置');
    }
    const url = context.baseUrl.trim() === '' ? custom.url ?? '' : context.baseUrl.trim();
    if (!isHttpsUrl(url)) {
      throw new Error('自定义来源必须使用 HTTPS 地址');
    }
    const headers = this.buildHeaders(custom, context);
    const method = custom.method === undefined || custom.method === '' ? 'GET' : custom.method.toUpperCase();
    const body = method === 'GET' ? undefined : custom.bodyTemplate;
    const secrets: string[] = Object.keys(context.secret).map((k: string) => context.secret[k]);
    const result: HttpResult = await HttpClient.send(
      { url: url, method: method, headers: headers, body: body },
      secrets
    );
    const root = result.json;
    if (root === undefined) {
      throw new Error('响应不是合法 JSON');
    }
    const plan = CustomAdapter.isPlanMode(this.config);
    const windows: QuotaWindow[] = [];
    const balances: BalanceInfo[] = [];

    if (plan) {
      // 套餐模式：只解析时间窗口，余额路径即使填了也忽略。
      const h5 = mapWindow(WindowKind.H5, custom.h5, root);
      if (h5 !== undefined) {
        windows.push(h5);
      }
      const week = mapWindow(WindowKind.WEEK, custom.week, root);
      if (week !== undefined) {
        windows.push(week);
      }
      const month = mapWindow(WindowKind.MONTH, custom.month, root);
      if (month !== undefined) {
        windows.push(month);
      }
      const missing: string[] = [];
      if (h5 === undefined) {
        missing.push('5 小时');
      }
      if (week === undefined) {
        missing.push('本周');
      }
      if (month === undefined) {
        missing.push('本月');
      }
      if (missing.length === 3) {
        throw new Error(`三个窗口都没取到，请检查字段路径：${truncate(redact(result.body, secrets), RAW_SNIPPET_CHARS)}`);
      }
      // 填了路径但取不到值的窗口，明确标注而不是留空。
      for (const kind of [WindowKind.H5, WindowKind.WEEK, WindowKind.MONTH]) {
        if (windows.find((w: QuotaWindow) => w.kind === kind) !== undefined) {
          continue;
        }
        const label = kind === WindowKind.H5 ? '5 小时' : (kind === WindowKind.WEEK ? '本周' : '本月');
        windows.push({
          kind: kind,
          mode: QuotaMode.RATIO,
          unavailableReason: `未配置${label}窗口的字段路径`
        });
      }
      windows.sort((a: QuotaWindow, b: QuotaWindow) => windowRank(a.kind) - windowRank(b.kind));
    } else {
      // 按量付费模式：只解析余额，窗口路径即使填了也忽略。
      if (custom.balance === undefined) {
        throw new Error('按量付费模式必须填写「余额路径」。');
      }
      const amount = toNum(pickPath(root, custom.balance.path));
      if (amount === undefined) {
        throw new Error(`余额路径「${custom.balance.path}」没有取到数字：${truncate(redact(result.body, secrets), RAW_SNIPPET_CHARS)}`);
      }
      const currency = custom.balanceCurrency === undefined || custom.balanceCurrency === ''
        ? 'CNY' : custom.balanceCurrency;
      const entry: BalanceInfo = { amount: amount, currency: currency, note: '自定义来源' };
      balances.push(entry);
    }
    return {
      providerId: this.descriptor.id,
      name: this.descriptor.name,
      kind: this.descriptor.kind,
      state: FetchState.OK,
      windows: windows,
      balances: balances,
      extra: {},
      fetchedAt: context.now,
      elapsedMs: 0
    };
  }

  /** 根据认证方式构造请求头。 */
  private buildHeaders(custom: CustomSourceConfig, context: FetchContext): Record<string, string> {
    const groups: Record<string, string>[] = [Headers.browser()];
    const secret = context.secret['secret'];
    const mode = custom.authMode === undefined ? 'none' : custom.authMode;
    if (mode === 'bearer' && secret !== undefined && secret !== '') {
      groups.push(Headers.bearer(secret));
    } else if (mode === 'header' && secret !== undefined && secret !== '') {
      const name = custom.authHeaderName === undefined || custom.authHeaderName === ''
        ? 'Authorization' : custom.authHeaderName;
      const headerMap: Record<string, string> = {};
      headerMap[name] = secret;
      groups.push(headerMap);
    }
    const extras: Record<string, string> = custom.extraHeaders === undefined
      ? ({} as Record<string, string>) : custom.extraHeaders;
    groups.push(extras);
    return Headers.merge(...groups);
  }
}

/** 把一个映射解释成窗口。 */
function mapWindow(kind: WindowKind, mapping: CustomFieldMapping | undefined,
  root: Object): QuotaWindow | undefined {
  if (mapping === undefined || mapping.path === undefined || mapping.path.trim() === '') {
    return undefined;
  }
  const raw = pickPath(root, mapping.path);
  const value = toNum(raw);
  if (value === undefined) {
    return undefined;
  }
  const resetAt = mapping.resetPath === undefined ? undefined : toEpochMs(pickPath(root, mapping.resetPath));
  if (mapping.semantics === MappingSemantics.ABSOLUTE) {
    const limit = mapping.limitPath === undefined ? 0 : toNum(pickPath(root, mapping.limitPath)) ?? 0;
    return {
      kind: kind,
      mode: QuotaMode.ABSOLUTE,
      remaining: value,
      limit: limit,
      unit: mapping.unit,
      resetAt: resetAt
    };
  }
  let usedRatio = 0;
  if (mapping.semantics === MappingSemantics.RATIO_REMAINING) {
    usedRatio = 1 - normalizeRatio(value);
  } else {
    usedRatio = normalizeRatio(value);
  }
  return {
    kind: kind,
    mode: QuotaMode.RATIO,
    usedRatio: clampRatioValue(usedRatio),
    resetAt: resetAt
  };
}

/** 兼容 0..1 与 0..100 两种百分比口径。 */
function normalizeRatio(value: number): number {
  if (!Number.isFinite(value)) {
    return 0;
  }
  return value > 1 ? value / 100 : value;
}

function clampRatioValue(value: number): number {
  if (!Number.isFinite(value) || value < 0) {
    return 0;
  }
  if (value > 1) {
    return 1;
  }
  return value;
}

function isHttpsUrl(url: string): boolean {
  return url.startsWith('https://');
}

/** 窗口展示顺序：5 小时 → 本周 → 本月。 */
function windowRank(kind: WindowKind): number {
  if (kind === WindowKind.H5) {
    return 0;
  }
  if (kind === WindowKind.WEEK) {
    return 1;
  }
  return 2;
}
