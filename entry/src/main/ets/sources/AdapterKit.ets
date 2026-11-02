import { FetchError } from '../net/HttpClient';
import {
  BalanceInfo,
  ErrorKind,
  FetchState,
  ProviderDescriptor,
  ProviderSnapshot,
  QuotaMode,
  QuotaWindow,
  SourceError,
  SourceKind,
  WindowKind
} from '../model/Types';
import { toNum, toStr, truncate } from '../model/JsonValue';
import { RAW_SNIPPET_CHARS } from '../common/Constants';

/** adapter 公共工具。 */

/** 构造一个已用比例窗口。 */
export function ratioWindow(kind: WindowKind, usedRatio: number, resetAt?: number): QuotaWindow {
  return {
    kind: kind,
    mode: QuotaMode.RATIO,
    usedRatio: usedRatio,
    resetAt: resetAt
  };
}

/** 构造一个绝对余量窗口。 */
export function absoluteWindow(kind: WindowKind, remaining: number, limit: number,
  unit: string, resetAt?: number): QuotaWindow {
  return {
    kind: kind,
    mode: QuotaMode.ABSOLUTE,
    remaining: remaining,
    limit: limit,
    unit: unit,
    resetAt: resetAt
  };
}

/** 构造一个明确不可用的窗口。 */
export function unavailableWindow(kind: WindowKind, reason: string): QuotaWindow {
  return {
    kind: kind,
    mode: QuotaMode.RATIO,
    unavailableReason: reason
  };
}

/** 构造余额条目。 */
export function balance(amount: number, currency: string, extra?: Partial<BalanceInfo>): BalanceInfo {
  const out: BalanceInfo = { amount: amount, currency: currency };
  if (extra !== undefined) {
    if (extra.granted !== undefined) {
      out.granted = extra.granted;
    }
    if (extra.toppedUp !== undefined) {
      out.toppedUp = extra.toppedUp;
    }
    if (extra.cash !== undefined) {
      out.cash = extra.cash;
    }
    if (extra.voucher !== undefined) {
      out.voucher = extra.voucher;
    }
    if (extra.note !== undefined) {
      out.note = extra.note;
    }
  }
  return out;
}

/** 统一收尾：填入 providerId/name/kind/fetchedAt。 */
export function finalize(descriptor: ProviderDescriptor, now: number, windows: QuotaWindow[],
  balances: BalanceInfo[], startedAt: number): ProviderSnapshot {
  return {
    providerId: descriptor.id,
    name: descriptor.name,
    kind: descriptor.kind,
    state: FetchState.OK,
    windows: windows,
    balances: balances,
    extra: {},
    fetchedAt: now,
    elapsedMs: now - startedAt
  };
}

/**
 * 把任意异常收敛为可展示的快照。
 * adapter 内部只抛 FetchError；其他异常按未知错误处理并保留脱敏原文。
 */
export function toErrorSnapshot(descriptor: ProviderDescriptor, error: Object, now: number,
  startedAt: number, secrets: string[]): ProviderSnapshot {
  let detail: SourceError = {
    kind: ErrorKind.UNKNOWN,
    httpStatus: 0,
    message: '未知错误'
  };
  if (error instanceof FetchError) {
    detail = {
      kind: error.detail.kind,
      httpStatus: error.detail.httpStatus,
      message: error.detail.message,
      rawSnippet: error.detail.rawSnippet
    };
  } else {
    const message = error instanceof Error ? error.message : `${error}`;
    detail.message = message;
    if (message.startsWith('缺少「')) {
      return {
        providerId: descriptor.id,
        name: descriptor.name,
        kind: descriptor.kind,
        state: FetchState.NEEDS_AUTH,
        windows: [],
        balances: [],
        extra: {},
        fetchedAt: now,
        elapsedMs: now - startedAt,
        error: { kind: ErrorKind.UNAUTHORIZED, httpStatus: 0, message: message }
      };
    }
  }
  const needsAuth = detail.kind === ErrorKind.UNAUTHORIZED || detail.kind === ErrorKind.NO_SUBSCRIPTION;
  return {
    providerId: descriptor.id,
    name: descriptor.name,
    kind: descriptor.kind,
    state: needsAuth ? FetchState.NEEDS_AUTH : FetchState.ERROR,
    windows: [],
    balances: [],
    extra: {},
    fetchedAt: now,
    elapsedMs: now - startedAt,
    error: detail
  };
}

/** 给错误信息追加来源专属提示。 */
export function withHint(message: string, hint: string | undefined): string {
  if (hint === undefined || hint === '') {
    return message;
  }
  return `${message}。${hint}`;
}

/** 从 JSON 中按候选路径取第一个数字。 */
export function firstNumber(root: Object | undefined, candidates: string[]): number | undefined {
  for (const path of candidates) {
    const raw = dig(root, path);
    const num = toNum(raw);
    if (num !== undefined) {
      return num;
    }
  }
  return undefined;
}

/** 从 JSON 中按候选路径取第一个字符串。 */
export function firstString(root: Object | undefined, candidates: string[]): string | undefined {
  for (const path of candidates) {
    const raw = dig(root, path);
    const str = toStr(raw);
    if (str !== undefined && str !== '') {
      return str;
    }
  }
  return undefined;
}

/** 按路径取值（内部小工具，避免跨模块循环依赖）。 */
function dig(root: Object | undefined, path: string): Object | undefined {
  if (root === undefined) {
    return undefined;
  }
  let current: Object | undefined = root;
  const parts = path.split('.');
  for (const part of parts) {
    if (current === undefined) {
      return undefined;
    }
    const rec = current as Record<string, Object>;
    current = rec[part];
  }
  return current;
}

/** 生成脱敏后的响应片段。 */
export function snippet(body: string, secrets: string[], redactor: (text: string, secrets: string[]) => string): string {
  return redactor(truncate(body, RAW_SNIPPET_CHARS), secrets);
}

/** 判断两个描述符是否都声明为订阅型。 */
export function isSubscription(kind: SourceKind): boolean {
  return kind === SourceKind.SUBSCRIPTION || kind === SourceKind.BOTH;
}
