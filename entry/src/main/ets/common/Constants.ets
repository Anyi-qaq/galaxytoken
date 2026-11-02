/** 全局常量：端点、超时、刷新间隔、偏好键名。 */

/** 网络超时（毫秒）。很多控制台网关较慢，留足余量。 */
export const HTTP_TIMEOUT_MS: number = 15000;

/** 部分来源需要串行节流，两次请求之间的最小间隔。 */
export const MIN_REQUEST_GAP_MS: number = 300;

/** 响应体超过此大小直接判为异常并截断。 */
export const MAX_BODY_CHARS: number = 1024 * 1024;

/** 错误摘要保留的原文长度。 */
export const RAW_SNIPPET_CHARS: number = 512;

/** 刷新间隔可选项（秒）。 */
export const REFRESH_OPTIONS: number[] = [60, 300, 900, 1800];

/** 默认刷新间隔（秒）。 */
export const DEFAULT_REFRESH_SEC: number = 60;

/** 默认金额小数位。 */
export const DEFAULT_MONEY_DECIMALS: number = 2;

/** preferences 实例名。 */
export const PREF_STORE_NAME: string = 'galaxy_token_store';

/** preferences 键名。 */
export const PREF_KEY_PROVIDERS: string = 'providers_config';
export const PREF_KEY_SETTINGS: string = 'app_settings';
export const PREF_KEY_SNAPSHOT: string = 'dashboard_snapshot';

/** 已添加到桌面的卡片 id 列表（主应用据此主动推送）。 */
export const PREF_KEY_FORM_IDS: string = 'form_ids';

/** Asset Store 别名前缀，实际 alias = 前缀 + providerId。 */
export const ASSET_ALIAS_PREFIX: string = 'galaxy_token_provider_';

/** 统一浏览器 UA —— 部分网关会拒绝非浏览器 UA。 */
export const BROWSER_UA: string =
  'Mozilla/5.0 (Linux; Android 15; HarmonyOS) AppleWebKit/537.36 (KHTML, like Gecko) ' +
    'Chrome/143.0.0.0 Mobile Safari/537.36';

/**
 * 端点常量。
 *
 * 清单与实现细节对齐 cc-switch（github.com/farion1231/cc-switch）已验证的
 * services/balance.rs 与 services/coding_plan.rs：只收录有公开出处或长期
 * 稳定实测的接口，每一条都在注释里写明出处。
 */
export class Endpoints {
  // ── 余额类（官方文档明确）────────────────────────────────
  /** DeepSeek 官方文档：api-docs.deepseek.com/zh-cn/api/get-user-balance */
  static readonly DEEPSEEK_BALANCE: string = 'https://api.deepseek.com/user/balance';
  /** Kimi 官方文档：platform.kimi.com/docs/api/balance */
  static readonly KIMI_CN_BALANCE: string = 'https://api.moonshot.cn/v1/users/me/balance';
  static readonly KIMI_INTL_BALANCE: string = 'https://api.moonshot.ai/v1/users/me/balance';
  /** OpenRouter 官方文档；需要 Management Key，普通 Key 会 403。 */
  static readonly OPENROUTER_CREDITS: string = 'https://openrouter.ai/api/v1/credits';
  /** 阶跃星辰余额；cc-switch 实测可用。 */
  static readonly STEPFUN_ACCOUNTS: string = 'https://api.stepfun.com/v1/accounts';
  /** 硅基流动余额（国内 / 国际两套域名）。 */
  static readonly SILICONFLOW_CN_INFO: string = 'https://api.siliconflow.cn/v1/user/info';
  static readonly SILICONFLOW_EN_INFO: string = 'https://api.siliconflow.com/v1/user/info';
  /** Novita AI 余额，金额单位是 0.0001 USD。 */
  static readonly NOVITA_BALANCE: string = 'https://api.novita.ai/v3/user/balance';

  // ── 套餐类（有官方套餐页，额度接口未公开但长期稳定）────────
  /** Kimi Code 套餐用量：GET /coding/v1/usages。 */
  static readonly KIMI_CODING_USAGES_CN: string = 'https://api.kimi.com/coding/v1/usages';
  static readonly KIMI_CODING_USAGES_INTL: string = 'https://api.kimi.ai/coding/v1/usages';
  /** 智谱 GLM Coding Plan；Authorization 不加 Bearer 前缀。 */
  static readonly GLM_CN_QUOTA: string = 'https://open.bigmodel.cn/api/monitor/usage/quota/limit';
  static readonly GLM_INTL_QUOTA: string = 'https://api.z.ai/api/monitor/usage/quota/limit';
  /** 智谱账户余额：只在没有 Coding Plan 时回落使用。 */
  static readonly GLM_CN_ACCOUNT: string = 'https://open.bigmodel.cn/api/biz/account/query-customer-account-report';
  static readonly GLM_INTL_ACCOUNT: string = 'https://api.z.ai/api/biz/account/query-customer-account-report';
  /** MiniMax Coding Plan：老域名才有公开出处，国内用 api.minimaxi.com。 */
  static readonly MINIMAX_CODING_CN: string = 'https://api.minimaxi.com/v1/api/openplatform/coding_plan/remains';
  static readonly MINIMAX_CODING_INTL: string = 'https://api.minimax.io/v1/api/openplatform/coding_plan/remains';
  /** MiniMax Token Plan（订阅制额度查询，官方 FAQ 有 curl 示例）。 */
  static readonly MINIMAX_TOKEN_PLAN_CN: string = 'https://www.minimax.cn/v1/token_plan/remains';
  static readonly MINIMAX_TOKEN_PLAN_INTL: string = 'https://www.minimax.io/v1/token_plan/remains';
  /** OpenCode Go：只有 Bearer 能查用量，推理侧用的是 x-api-key。 */
  static readonly OPENCODE_GO_USAGE: string = 'https://opencode.ai/zen/go/v1/usage';
}

/** 来源 id 常量，避免各文件硬编码字符串。 */
export class ProviderIds {
  static readonly DEMO: string = 'demo';
  static readonly DEEPSEEK: string = 'deepseek';
  static readonly KIMI: string = 'kimi';
  static readonly OPENROUTER: string = 'openrouter';
  static readonly STEPFUN: string = 'stepfun';
  static readonly SILICONFLOW: string = 'siliconflow';
  static readonly NOVITA: string = 'novita';
  static readonly KIMI_CODE: string = 'kimi-code';
  static readonly GLM: string = 'glm';
  static readonly MINIMAX: string = 'minimax';
  static readonly MINIMAX_TOKEN: string = 'minimax-token';
  static readonly OPENCODE_GO: string = 'opencode-go';
  static readonly CUSTOM: string = 'custom';
}

/** 自定义来源的固定 id（同一时刻只允许一条自定义来源则用后缀区分）。 */
export const CUSTOM_ID_PREFIX: string = 'custom';
