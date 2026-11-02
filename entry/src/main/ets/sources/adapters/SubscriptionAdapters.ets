import { FetchContext, SourceAdapter, requireField } from '../SourceAdapter';
import {
  FetchState,
  FieldKind,
  ProviderDescriptor,
  ProviderSnapshot,
  QuotaMode,
  QuotaWindow,
  SourceKind,
  WindowKind
} from '../../model/Types';
import { asArray, asObject, pickPath, toEpochMs, toNum, toStr } from '../../model/JsonValue';
import { ErrorKind, clampRatio } from '../../model/Types';
import { FetchError, Headers, HttpClient, HttpResult } from '../../net/HttpClient';
import { Endpoints } from '../../common/Constants';
import { ratioWindow, unavailableWindow } from '../AdapterKit';



/** percent 是 0-100 的「已用」值，个别情况下可能已是 0-1。 */
function normalizeUsedRatio(percent: number): number {
  const ratio = percent > 1 ? percent / 100 : percent;
  if (!Number.isFinite(ratio) || ratio < 0) {
    return 0;
  }
  return ratio > 1 ? 1 : ratio;
}

/**
 * MiniMax M Plan / Token Plan。
 *
 * GET https://www.minimax.cn/v1/token_plan/remains
 * Authorization: Bearer <订阅 Key>
 *
 * 关键陷阱：
 * 1. HTTP 200 也可能失败 —— 必须判 base_resp.status_code === 0；
 * 2. current_interval_usage_count 是「剩余量」不是已用量；
 * 3. 窗口长度不固定（general 5h、video 24h），要按行内 start_time/end_time 判断。
 */
export class MiniMaxAdapter implements SourceAdapter {
  readonly descriptor: ProviderDescriptor = {
    id: 'minimax',
    name: 'MiniMax M Plan',
    kind: SourceKind.SUBSCRIPTION,
    summary: 'MiniMax 订阅套餐的 5 小时与每周窗口（非视频模型）。',
    supports: { h5: true, week: true, month: false },
    credentialFields: [
      {
        key: 'apiKey',
        label: '订阅 Key',
        kind: FieldKind.SECRET,
        required: true,
        placeholder: '订阅 Key（不是按量付费 API Key）',
        helpText: '在 MiniMax「套餐详情」中获取订阅 Key；按量计费 Key 不能用。'
      }
    ],
    baseUrlEditable: false,
    defaultBaseUrl: 'https://www.minimax.cn',
    experimental: false,
    usesBrowserSession: false,
    apiNote: 'GET /v1/token_plan/remains；HTTP 200 也可能返回业务错误。'
  };

  async fetch(context: FetchContext): Promise<ProviderSnapshot> {
    const startedAt = context.now;
    const apiKey = requireField(context, 'apiKey', '订阅 Key');
    const result = await HttpClient.get(Endpoints.MINIMAX_TOKEN_PLAN_CN, Headers.bearer(apiKey), [apiKey]);
    const root = asObject(result.json);
    if (root === undefined) {
      throw new Error('响应不是合法 JSON');
    }
    const baseResp = asObject(root['base_resp']);
    const statusCode = baseResp === undefined ? undefined : toNum(baseResp['status_code']);
    if (statusCode !== undefined && statusCode !== 0) {
      const message = baseResp === undefined ? undefined : toStr(baseResp['status_msg']);
      throw new FetchError({
        kind: statusCode === 1004 ? ErrorKind.UNAUTHORIZED : ErrorKind.ENVELOPE,
        httpStatus: 200,
        message: `MiniMax 返回业务错误（status_code=${statusCode}）：${message ?? '无说明'}`
      });
    }
    const windows: QuotaWindow[] = parseMiniMaxWindows(root);
    if (windows.length === 0) {
      throw new Error('响应中没有任何额度窗口');
    }
    windows.push(unavailableWindow(WindowKind.MONTH, 'MiniMax 不提供月度窗口'));
    return {
      providerId: this.descriptor.id,
      name: this.descriptor.name,
      kind: this.descriptor.kind,
      state: FetchState.OK,
      windows: windows,
      balances: [],
      extra: {},
      fetchedAt: context.now,
      elapsedMs: context.now - startedAt
    };
  }
}

/**
 * 解析 MiniMax 的 model_remains[]。
 *
 * current_interval_usage_count 是「剩余量」；窗口长度按行内 start/end 推断，
 * 超过 6 小时的（如视频模型 24h）不算作 5 小时窗口。
 */
export function parseMiniMaxWindows(root: Record<string, Object>): QuotaWindow[] {
  const rows = root['model_remains'];
  const list = Array.isArray(rows) ? rows as Object[] : [];
  const windows: QuotaWindow[] = [];
  let h5: QuotaWindow | undefined = undefined;
  let weekly: QuotaWindow | undefined = undefined;
  for (const item of list) {
    const row = asObject(item);
    if (row === undefined) {
      continue;
    }
    const intervalTotal = toNum(row['current_interval_total_count']);
    const intervalRemaining = toNum(row['current_interval_usage_count']);
    const intervalStart = toEpochMs(row['start_time']);
    const intervalEnd = toEpochMs(row['end_time']);
    const weeklyTotal = toNum(row['weekly_total_count']);
    const weeklyRemaining = toNum(row['weekly_usage_count']);
    const weeklyEnd = toEpochMs(row['weekly_end_time']);
    if (h5 === undefined && intervalTotal !== undefined && intervalRemaining !== undefined) {
      const spanHours = intervalStart !== undefined && intervalEnd !== undefined
        ? Math.round((intervalEnd - intervalStart) / 3600000) : 5;
      if (spanHours <= 6) {
        h5 = {
          kind: WindowKind.H5,
          mode: QuotaMode.ABSOLUTE,
          remaining: intervalRemaining,
          limit: intervalTotal,
          unit: 'prompt',
          resetAt: intervalEnd
        };
      }
    }
    if (weekly === undefined && weeklyTotal !== undefined && weeklyRemaining !== undefined) {
      weekly = {
        kind: WindowKind.WEEK,
        mode: QuotaMode.ABSOLUTE,
        remaining: weeklyRemaining,
        limit: weeklyTotal,
        unit: 'prompt',
        resetAt: weeklyEnd
      };
    }
  }
  if (h5 !== undefined) {
    windows.push(h5);
  }
  if (weekly !== undefined) {
    windows.push(weekly);
  }
  return windows;
}



/**
 * 智谱 GLM Coding Plan。
 *
 * GET https://open.bigmodel.cn/api/monitor/usage/quota/limit?type=1
 * Authorization: <裸 Key，不带 Bearer>
 * bigmodel-organization / bigmodel-project：团队套餐必填
 *
 * limits[] 里 unit 是枚举：3=5 小时、6=周、1=天、5=分钟；
 * percentage 是已用百分比，nextResetTime 是 epoch 毫秒。
 */
export class GlmAdapter implements SourceAdapter {
  readonly descriptor: ProviderDescriptor = {
    id: 'glm',
    name: '智谱 GLM Coding Plan',
    kind: SourceKind.SUBSCRIPTION,
    summary: 'GLM Coding Plan 的 5 小时、每周与每月工具配额。',
    supports: { h5: true, week: true, month: true },
    credentialFields: [
      {
        key: 'apiKey',
        label: 'API Key',
        kind: FieldKind.SECRET,
        required: true,
        placeholder: '粘贴 Key 原文即可',
        helpText: '按智谱官方 ZCode 的实现，Authorization 使用 Bearer 前缀；未带时自动补上。'
      },
      {
        key: 'organization',
        label: 'Organization ID',
        kind: FieldKind.TEXT,
        required: false,
        placeholder: 'org-xxx',
        helpText: '团队套餐必填。浏览器登录 bigmodel.cn/coding-plan 后，在 DevTools 的 quota/limit 请求头中查看。'
      },
      {
        key: 'project',
        label: 'Project ID',
        kind: FieldKind.TEXT,
        required: false,
        placeholder: 'proj_xxx',
        helpText: '团队套餐必填，与 Organization ID 同处获取。'
      },
      {
        key: 'planType',
        label: '套餐类型',
        kind: FieldKind.CHOICE,
        required: false,
        options: ['个人', '团队'],
        defaultValue: '个人'
      },
      {
        key: 'site',
        label: '站点',
        kind: FieldKind.CHOICE,
        required: false,
        options: ['国内', '国际'],
        defaultValue: '国内'
      }
    ],
    baseUrlEditable: false,
    defaultBaseUrl: 'https://open.bigmodel.cn',
    experimental: false,
    usesBrowserSession: false,
    apiNote: 'GET /api/monitor/usage/quota/limit；TOKENS_LIMIT(unit=3,number=5)=5 小时、TOKENS_LIMIT(unit=6)=每周、TIME_LIMIT(unit=5,number=1)=每月工具配额。语义依据智谱官方开源仓库 zai-org/ZCode。'
  };

  async fetch(context: FetchContext): Promise<ProviderSnapshot> {
    const startedAt = context.now;
    const apiKey = requireField(context, 'apiKey', 'API Key');
    const site = context.plain['site'] === undefined ? '国内' : context.plain['site'];
    const planType = context.plain['planType'] === undefined ? '个人' : context.plain['planType'];
    const base = site === '国际' ? Endpoints.GLM_INTL_QUOTA : Endpoints.GLM_CN_QUOTA;
    const query = planType === '团队' ? '?type=2' : '?type=1';
    // 智谱官方 ZCode 的做法：未带 Bearer 时自动补。
    const authValue = /^Bearer\s/i.test(apiKey) ? apiKey : `Bearer ${apiKey}`;
    const headers: Record<string, string> = {
      'Authorization': authValue,
      'Accept': 'application/json',
      'Accept-Language': 'zh-CN,zh;q=0.9'
    };
    const org = context.plain['organization'];
    const project = context.plain['project'];
    if (org !== undefined && org.trim() !== '') {
      headers['bigmodel-organization'] = org.trim();
    }
    if (project !== undefined && project.trim() !== '') {
      headers['bigmodel-project'] = project.trim();
    }
    const result = await HttpClient.get(`${base}${query}`, headers, [apiKey, authValue]);
    const root = asObject(result.json);
    if (root === undefined) {
      throw new Error('响应不是合法 JSON');
    }
    const data = asObject(root['data']);
    if (data === undefined || Object.keys(data).length === 0) {
      throw new Error('响应 data 为空：团队套餐请填写 Organization ID 与 Project ID');
    }
    const limits = data['limits'];
    const list = Array.isArray(limits) ? limits as Object[] : [];
    if (list.length === 0) {
      throw new Error('响应中没有 limits 数组');
    }
    const windows: QuotaWindow[] = [];
    const specs: GlmWindowSpec[] = GLM_WINDOW_SPECS;
    for (const spec of specs) {
      const row = findGlmLimit(list, spec);
      if (row === undefined) {
        windows.push(unavailableWindow(spec.kind, `响应中没有${spec.label}额度条目`));
        continue;
      }
      const percentage = toNum(row['percentage']);
      if (percentage === undefined) {
        windows.push(unavailableWindow(spec.kind, `${spec.label}条目缺少 percentage 字段`));
        continue;
      }
      // 官方语义：percentage 是「已用占比」，0..100。
      const usedRatio = clampRatio(percentage > 1 ? percentage / 100 : percentage);
      windows.push(ratioWindow(spec.kind, usedRatio, toEpochMs(row['nextResetTime'])));
    }
    if (windows.every((w: QuotaWindow) => w.unavailableReason !== undefined)) {
      throw new Error('没有识别到任何额度窗口（type/unit 枚举可能已变化）');
    }
    return {
      providerId: this.descriptor.id,
      name: this.descriptor.name,
      kind: this.descriptor.kind,
      state: FetchState.OK,
      windows: windows,
      balances: [],
      extra: {},
      fetchedAt: context.now,
      elapsedMs: context.now - startedAt
    };
  }
}

/**
 * 一个 GLM 额度窗口的匹配条件。
 *
 * 全部取自智谱官方开源仓库 zai-org/ZCode（Apache-2.0）：
 *   packages/ui/src/CodingPlanUsageRemainingPanel.tsx:261-263
 *     findCodingPlanQuotaLimit(limits, "TOKENS_LIMIT", 3, 5)   → 5 小时
 *     findCodingPlanQuotaLimit(limits, "TOKENS_LIMIT", 6)      → 每周
 *     findCodingPlanQuotaLimit(limits, "TIME_LIMIT", 5, 1)     → 每月工具配额
 * 且 packages/ui/src/lib/codingPlanQuotaPresentation.ts:8-13 的注释明确写着
 * 「unit=3,number=5 → 5 小时窗口；unit=6 → 每周」。
 */
interface GlmWindowSpec {
  kind: WindowKind;
  label: string;
  /** 主 type；z.ai 团队套餐用 CREDIT_LIMIT，与 TOKENS_LIMIT 等价。 */
  type: string;
  /** 等价的 type 集合。 */
  altTypes: string[];
  unit: number;
  /** 可选的 number 精确匹配；undefined 表示该 type 下不看 number。 */
  number?: number;
}

const GLM_WINDOW_SPECS: GlmWindowSpec[] = [
  {
    kind: WindowKind.H5,
    label: '5 小时',
    type: 'TOKENS_LIMIT',
    altTypes: ['CREDIT_LIMIT'],
    unit: 3,
    number: 5
  },
  {
    kind: WindowKind.WEEK,
    label: '每周',
    type: 'TOKENS_LIMIT',
    altTypes: ['CREDIT_LIMIT'],
    unit: 6
  },
  {
    kind: WindowKind.MONTH,
    label: '每月工具',
    type: 'TIME_LIMIT',
    altTypes: [],
    unit: 5,
    number: 1
  }
];

/** 在 limits[] 中按 spec 找第一条匹配项。 */
function findGlmLimit(list: Object[], spec: GlmWindowSpec): Record<string, Object> | undefined {
  for (const item of list) {
    const row = asObject(item);
    if (row === undefined) {
      continue;
    }
    const type = toStr(row['type']);
    if (type === undefined) {
      continue;
    }
    const typeOk = type === spec.type || spec.altTypes.indexOf(type) >= 0;
    if (!typeOk) {
      continue;
    }
    if (toNum(row['unit']) !== spec.unit) {
      continue;
    }
    if (spec.number !== undefined && toNum(row['number']) !== spec.number) {
      continue;
    }
    return row;
  }
  return undefined;
}

/** 兼容旧调用名：unit 枚举 3=5 小时、6=周（不含 type 过滤）。 */
export function glmWindowKind(unit: number | undefined): WindowKind | undefined {
  if (unit === 3) {
    return WindowKind.H5;
  }
  if (unit === 6) {
    return WindowKind.WEEK;
  }
  return undefined;
}

/**
 * Kimi Code 套餐用量。
 *
 * GET https://api.kimi.com/coding/v1/usages（国际站 api.kimi.ai）
 * 响应含 limits[]（每项 detail.limit / detail.remaining / detail.resetTime）
 * 与 usage（整体周窗口，同结构）。服务端给的是「剩余量」，需要反算已用比例。
 *
 * 新套餐取消了每周上限，只保留 5 小时滚动窗口；老套餐两个都有。
 * 所以 weekly 缺失属于正常情况，不当作错误。
 */
export class KimiCodeAdapter implements SourceAdapter {
  readonly descriptor: ProviderDescriptor = {
    id: 'kimi-code',
    name: 'Kimi Code 套餐',
    kind: SourceKind.SUBSCRIPTION,
    summary: 'Kimi Code 会员的 5 小时滚动窗口（老套餐另有每周窗口）。',
    supports: { h5: true, week: true, month: false },
    credentialFields: [
      {
        key: 'apiKey',
        label: 'API Key',
        kind: FieldKind.SECRET,
        required: true,
        placeholder: 'sk-kimi-…',
        helpText: '订阅 Key 与普通开放平台 Key 不同，需在 Kimi Code 订阅页获取。'
      },
      {
        key: 'region',
        label: '站点',
        kind: FieldKind.CHOICE,
        required: false,
        options: ['国内站', '国际站'],
        defaultValue: '国内站',
        helpText: '国内站 api.kimi.com，国际站 api.kimi.ai。'
      }
    ],
    baseUrlEditable: false,
    defaultBaseUrl: 'https://api.kimi.com',
    experimental: false,
    usesBrowserSession: false,
    apiNote: 'GET /coding/v1/usages，服务端给剩余量，需反算已用。'
  };

  async fetch(context: FetchContext): Promise<ProviderSnapshot> {
    const startedAt = context.now;
    const apiKey = requireField(context, 'apiKey', 'API Key');
    const region = context.plain['region'];
    const url = region === '国际站'
      ? Endpoints.KIMI_CODING_USAGES_INTL
      : Endpoints.KIMI_CODING_USAGES_CN;
    const result = await HttpClient.get(url, Headers.bearer(apiKey), [apiKey]);
    const root = asObject(result.json);
    if (root === undefined) {
      throw new Error('响应不是合法 JSON');
    }

    const windows: QuotaWindow[] = [];
    // 5 小时窗口：limits[] 里每一项的 detail。
    const limits = asArray(root['limits']);
    if (limits !== undefined) {
      for (const item of limits) {
        const row = asObject(item);
        if (row === undefined) {
          continue;
        }
        const detail = asObject(row['detail']);
        if (detail === undefined) {
          continue;
        }
        const ratio = remainingRatioOf(detail);
        if (ratio !== undefined) {
          windows.push(ratioWindow(WindowKind.H5, ratio, toEpochMs(detail['resetTime'])));
          break;
        }
      }
    }

    // 周窗口：usage 对象。
    const usage = asObject(root['usage']);
    if (usage !== undefined) {
      const ratio = remainingRatioOf(usage);
      if (ratio !== undefined) {
        windows.push(ratioWindow(WindowKind.WEEK, ratio, toEpochMs(usage['resetTime'])));
      }
    }

    if (windows.length === 0) {
      throw new Error('响应里没有可识别的额度窗口');
    }
    if (windows.find((w: QuotaWindow) => w.kind === WindowKind.H5) === undefined) {
      windows.unshift(unavailableWindow(WindowKind.H5, '本次响应未含 5 小时窗口'));
    }
    if (windows.find((w: QuotaWindow) => w.kind === WindowKind.WEEK) === undefined) {
      windows.push(unavailableWindow(WindowKind.WEEK, '新套餐已取消每周上限'));
    }
    windows.push(unavailableWindow(WindowKind.MONTH, 'Kimi Code 不提供月度窗口'));
    return {
      providerId: this.descriptor.id,
      name: this.descriptor.name,
      kind: this.descriptor.kind,
      state: FetchState.OK,
      windows: windows,
      balances: [],
      extra: {},
      fetchedAt: context.now,
      elapsedMs: context.now - startedAt
    };
  }
}

/** 把 {limit, remaining} 反算成「已用比例」。 */
function remainingRatioOf(detail: Object): number | undefined {
  const row = asObject(detail);
  if (row === undefined) {
    return undefined;
  }
  const limit = toNum(row['limit']);
  const remaining = toNum(row['remaining']);
  if (limit === undefined || remaining === undefined || limit <= 0) {
    return undefined;
  }
  const used = limit - remaining;
  if (used < 0) {
    return 0;
  }
  return clampRatio(used / limit);
}
