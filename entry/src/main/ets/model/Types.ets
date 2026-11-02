/**
 * 星河 Token —— 核心数据契约。
 *
 * 设计原则：
 * 1. 所有额度都归一到一个窗口模型（QuotaWindow），UI 与卡片只消费 ProviderSnapshot。
 * 2. 各来源声明自己支持哪些窗口，不支持的位置显式说明原因，不留空白、不填 0。
 * 3. 语义差异（已用 vs 剩余）只在 adapter 内转换，绝不共用一个 normalize。
 */

/** 额度窗口类型。 */
export enum WindowKind {
  H5 = 'h5',
  WEEK = 'week',
  MONTH = 'month'
}

/** 窗口读数的来源语义。 */
export enum QuotaMode {
  /** 服务端给百分比。 */
  RATIO = 'ratio',
  /** 服务端直接给绝对余量。 */
  ABSOLUTE = 'absolute'
}

/** 来源类型。 */
export enum SourceKind {
  SUBSCRIPTION = 'subscription',
  BALANCE = 'balance',
  BOTH = 'both'
}

/** 单次拉取的状态。 */
export enum FetchState {
  OK = 'ok',
  PARTIAL = 'partial',
  ERROR = 'error',
  NEEDS_AUTH = 'needs_auth'
}

/** 一个额度窗口的读数。 */
export interface QuotaWindow {
  kind: WindowKind;
  mode: QuotaMode;
  /** 已用比例 0..1（mode=ratio 时有效），已裁剪越界值。 */
  usedRatio?: number;
  /** 绝对剩余量（mode=absolute，或 ratio 且能推出分母时）。 */
  remaining?: number;
  /** 绝对总额度；0 表示不限。 */
  limit?: number;
  /** 单位：prompt / credit / USD / CNY / token。 */
  unit?: string;
  /** 重置时刻，epoch 毫秒。 */
  resetAt?: number;
  /** 该窗口不可用的原因（来源不支持、被服务端停用等）。 */
  unavailableReason?: string;
  /** 是否为本地实测/推算值（而非服务端直给）。 */
  derived?: boolean;
}

/** 一条余额信息。 */
export interface BalanceInfo {
  amount: number;
  currency: string;
  granted?: number;
  toppedUp?: number;
  cash?: number;
  voucher?: number;
  /** 额外说明，如「含赠金」。 */
  note?: string;
}

/** 附加配额信息（不参与三窗口，但值得展示）。 */
export interface ExtraQuota {
  creditsBalance?: number;
  creditsUnit?: string;
  resetCreditsAvailable?: number;
  planName?: string;
  renewalAt?: number;
}

/** 错误分类，用于统一文案映射。 */
export enum ErrorKind {
  UNAUTHORIZED = 'unauthorized',
  FORBIDDEN = 'forbidden',
  RATE_LIMITED = 'rate_limited',
  NOT_FOUND = 'not_found',
  NETWORK = 'network',
  TIMEOUT = 'timeout',
  PARSE = 'parse',
  ENVELOPE = 'envelope',
  NO_SUBSCRIPTION = 'no_subscription',
  UNKNOWN = 'unknown'
}

/** 结构化的来源错误。 */
export interface SourceError {
  kind: ErrorKind;
  httpStatus: number;
  message: string;
  /** 脱敏后的响应片段，用于排查字段变化。 */
  rawSnippet?: string;
}

/** 单个来源的一次快照。 */
export interface ProviderSnapshot {
  providerId: string;
  name: string;
  kind: SourceKind;
  state: FetchState;
  windows: QuotaWindow[];
  balances: BalanceInfo[];
  extra: ExtraQuota;
  fetchedAt: number;
  error?: SourceError;
  /** 本次耗时毫秒。 */
  elapsedMs?: number;
}

/** 凭据字段定义，用于动态渲染表单。 */
export interface CredentialField {
  key: string;
  label: string;
  /** secret 会以密码框渲染并在 Asset Store 中加密存放。 */
  kind: FieldKind;
  required: boolean;
  placeholder?: string;
  /** 获取步骤说明，展示在输入框下方。 */
  helpText?: string;
  defaultValue?: string;
  /** 可选值（如 planType）。 */
  options?: string[];
}

export enum FieldKind {
  SECRET = 'secret',
  TEXT = 'text',
  CHOICE = 'choice'
}

/** 窗口支持矩阵。 */
export interface WindowSupport {
  h5: boolean;
  week: boolean;
  month: boolean;
}

/** 来源描述符：注册表与 UI 的唯一入口。 */
export interface ProviderDescriptor {
  id: string;
  name: string;
  kind: SourceKind;
  /** 一句话说明，显示在来源管理与编辑页。 */
  summary: string;
  supports: WindowSupport;
  credentialFields: CredentialField[];
  /** 允许用户改 Base URL（自定义/自建部署场景）。 */
  baseUrlEditable: boolean;
  defaultBaseUrl: string;
  /** 实验性来源：接口未公开或未在真实账号验证，默认不启用并在 UI 上标注。 */
  experimental: boolean;
  /** 依赖浏览器登录态（Cookie/OAuth）的来源。 */
  usesBrowserSession: boolean;
  /** 用于"关于"页与卡片角标的接口来源说明。 */
  apiNote: string;
  /** 该来源期望展示的余额币种（若适用）。 */
  balanceCurrency?: string;
}

/** 用户对某个来源的配置（非密部分，存 preferences）。 */
export interface ProviderConfig {
  providerId: string;
  enabled: boolean;
  /** 排序，小的在前。 */
  order: number;
  baseUrl: string;
  /** 非密字段的值（如 organization、project、workspaceId）。 */
  plainFields: Record<string, string>;
  /** 是否已存有凭据。 */
  hasSecret: boolean;
  /** 自定义来源的映射配置。 */
  custom?: CustomSourceConfig;
  /** 自定义来源的显示名。 */
  displayName?: string;
}

/** 自定义来源的字段映射。 */
export interface CustomFieldMapping {
  /** JSON 路径，如 data.limits[0].percentage。 */
  path: string;
  /** ratio-used / ratio-remaining / absolute。 */
  semantics: MappingSemantics;
  /** 可选分母路径。 */
  limitPath?: string;
  /** 可选重置时间路径。 */
  resetPath?: string;
  /** 可选单位。 */
  unit?: string;
}

export enum MappingSemantics {
  RATIO_USED = 'ratio-used',
  RATIO_REMAINING = 'ratio-remaining',
  ABSOLUTE = 'absolute'
}

/** 自定义来源的用途：套餐额度 / 按量付费余额 / 两者都要。 */
export enum CustomMode {
  /** 套餐：查 5 小时 / 本周 / 本月 三个时间窗口。 */
  PLAN = 'plan',
  /** 按量付费：只查账户余额金额。 */
  PAYG = 'payg'
}

/** 自定义来源完整配置。 */
export interface CustomSourceConfig {
  /**
   * 用途：套餐（时间窗口）还是按量付费（余额）。
   * 缺省视为 PLAN，兼容早期版本存的配置。
   */
  mode?: CustomMode;
  /** 完整 HTTPS 端点；Base URL 留空时使用它。 */
  url: string;
  method: string;
  /** bearer / header / query / none */
  authMode: string;
  authHeaderName?: string;
  authQueryName?: string;
  extraHeaders: Record<string, string>;
  bodyTemplate?: string;
  h5?: CustomFieldMapping;
  week?: CustomFieldMapping;
  month?: CustomFieldMapping;
  balance?: CustomFieldMapping;
  balanceCurrency?: string;
}

/** 首页聚合结果。 */
export interface DashboardSnapshot {
  providers: ProviderSnapshot[];
  refreshedAt: number;
  /** 最紧张的窗口（用于卡片高亮）。 */
  tightestProviderId?: string;
  tightestKind?: WindowKind;
  tightestUsedRatio?: number;
}

/** 应用设置。 */
export interface AppSettings {
  refreshIntervalSec: number;
  moneyDecimals: number;
  demoMode: boolean;
  showExperimental: boolean;
}

/** 窗口类型的中文名。 */
export function windowLabel(kind: WindowKind): string {
  switch (kind) {
    case WindowKind.H5:
      return '5 小时';
    case WindowKind.WEEK:
      return '本周';
    case WindowKind.MONTH:
      return '本月';
    default:
      return '未知';
  }
}

/** 窗口类型排序权重。 */
export function windowRank(kind: WindowKind): number {
  switch (kind) {
    case WindowKind.H5:
      return 0;
    case WindowKind.WEEK:
      return 1;
    case WindowKind.MONTH:
      return 2;
    default:
      return 9;
  }
}

/** 按 H5 / WEEK / MONTH 顺序补齐窗口，缺失的用 unavailableReason 占位。 */
export function normalizeWindows(snapshot: ProviderSnapshot): QuotaWindow[] {
  const result: QuotaWindow[] = [];
  const kinds: WindowKind[] = [WindowKind.H5, WindowKind.WEEK, WindowKind.MONTH];
  const supports: WindowSupport = supportsOf(snapshot.providerId);
  for (const kind of kinds) {
    const hit = snapshot.windows.filter((w: QuotaWindow) => w.kind === kind);
    if (hit.length > 0) {
      result.push(hit[0]);
    } else {
      const supported: boolean = (kind === WindowKind.H5 && supports.h5) ||
        (kind === WindowKind.WEEK && supports.week) ||
        (kind === WindowKind.MONTH && supports.month);
      result.push({
        kind: kind,
        mode: QuotaMode.RATIO,
        unavailableReason: supported ? '本次未返回该窗口' : '该来源不提供此窗口'
      });
    }
  }
  return result;
}

/** 由注册表填充的支持矩阵；未注册的来源全部视为不支持。 */
let supportLookup: (providerId: string) => WindowSupport = (_id: string): WindowSupport => {
  return { h5: true, week: true, month: true };
};

/** 注入支持矩阵查询（由 ProviderRegistry 在启动时调用，避免循环依赖）。 */
export function setSupportLookup(fn: (providerId: string) => WindowSupport): void {
  supportLookup = fn;
}

function supportsOf(providerId: string): WindowSupport {
  return supportLookup(providerId);
}

/** 把任意数值裁剪到 [0,1]。 */
export function clampRatio(value: number): number {
  if (!Number.isFinite(value)) {
    return 0;
  }
  if (value < 0) {
    return 0;
  }
  if (value > 1) {
    return 1;
  }
  return value;
}

/** 取窗口的剩余比例；无读数时返回 undefined。 */
export function remainingRatio(window: QuotaWindow): number | undefined {
  if (window.mode === QuotaMode.RATIO && window.usedRatio !== undefined) {
    return clampRatio(1 - window.usedRatio);
  }
  if (window.mode === QuotaMode.ABSOLUTE && window.remaining !== undefined &&
    window.limit !== undefined && window.limit > 0) {
    return clampRatio(window.remaining / window.limit);
  }
  return undefined;
}

/** 构造一个新的空快照，供各 adapter 作为起点。 */
export function emptySnapshot(descriptor: ProviderDescriptor, now: number): ProviderSnapshot {
  return {
    providerId: descriptor.id,
    name: descriptor.name,
    kind: descriptor.kind,
    state: FetchState.OK,
    windows: [],
    balances: [],
    extra: {},
    fetchedAt: now
  };
}

/** 判断快照是否健康（用于首页聚合）。 */
export function isHealthy(snapshot: ProviderSnapshot): boolean {
  return snapshot.state === FetchState.OK || snapshot.state === FetchState.PARTIAL;
}
