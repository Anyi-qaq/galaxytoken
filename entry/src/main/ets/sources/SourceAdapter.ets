import { ProviderDescriptor, ProviderSnapshot } from '../model/Types';

/** 一次拉取需要的全部输入。 */
export interface FetchContext {
  /** 非密字段（organization、project、workspaceId 等）。 */
  plain: Record<string, string>;
  /** 密文字段（apiKey、cookie、accessToken 等）。 */
  secret: Record<string, string>;
  /** 生效的 Base URL。 */
  baseUrl: string;
  /** 当前时间戳，便于测试注入。 */
  now: number;
}

/**
 * 一个来源的适配器。
 *
 * 约定：
 * - 不要在内部捕获并吞掉异常；直接抛 FetchError 让 QuotaService 统一收敛。
 * - 不要修改 descriptor。
 * - 语义转换（已用/剩余）必须在本适配器内完成。
 */
export interface SourceAdapter {
  readonly descriptor: ProviderDescriptor;

  /**
   * 拉取一次快照。
   * @throws FetchError 网络/鉴权/解析失败
   */
  fetch(context: FetchContext): Promise<ProviderSnapshot>;
}

/** 适配器里可复用的凭据读取。 */
export function requireField(context: FetchContext, key: string, label: string): string {
  const value = context.secret[key];
  if (value !== undefined && value.trim() !== '') {
    return value.trim();
  }
  const plain = context.plain[key];
  if (plain !== undefined && plain.trim() !== '') {
    return plain.trim();
  }
  throw new Error(`缺少「${label}」`);
}

/** 读取可选字段。 */
export function optionalField(context: FetchContext, key: string): string | undefined {
  const secret = context.secret[key];
  if (secret !== undefined && secret.trim() !== '') {
    return secret.trim();
  }
  const plain = context.plain[key];
  if (plain !== undefined && plain.trim() !== '') {
    return plain.trim();
  }
  return undefined;
}

/** 解析 Base URL，缺省回落到 descriptor 默认值。 */
export function effectiveBaseUrl(context: FetchContext, descriptor: ProviderDescriptor, path: string): string {
  const base = context.baseUrl !== undefined && context.baseUrl.trim() !== ''
    ? context.baseUrl.trim()
    : descriptor.defaultBaseUrl;
  return joinUrl(base, path);
}

/** 拼接 URL，避免双斜杠。 */
export function joinUrl(base: string, path: string): string {
  const trimmedBase = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  if (path === '') {
    return trimmedBase;
  }
  const trimmedPath = path.startsWith('/') ? path.substring(1) : path;
  return `${trimmedBase}/${trimmedPath}`;
}
