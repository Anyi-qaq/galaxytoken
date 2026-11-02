import { SourceAdapter, FetchContext, requireField } from '../SourceAdapter';
import {
  BalanceInfo,
  FetchState,
  FieldKind,
  ProviderDescriptor,
  ProviderSnapshot,
  SourceKind
} from '../../model/Types';
import { asObject, pickBoolean, pickString, toNum } from '../../model/JsonValue';
import { HttpClient, Headers } from '../../net/HttpClient';
import { Endpoints } from '../../common/Constants';
import { balance, firstNumber, firstString } from '../AdapterKit';

/**
 * DeepSeek 余额。
 *
 * GET https://api.deepseek.com/user/balance
 * Authorization: Bearer <key>
 *
 * 返回 balance_infos[]，每项含 currency / total_balance / granted_balance / topped_up_balance，
 * 数值是「字符串」。多币种时优先展示 CNY。
 */
export class DeepSeekAdapter implements SourceAdapter {
  readonly descriptor: ProviderDescriptor = {
    id: 'deepseek',
    name: 'DeepSeek',
    kind: SourceKind.BALANCE,
    summary: 'DeepSeek 开放平台账户余额，含赠金与充值明细。',
    supports: { h5: false, week: false, month: false },
    credentialFields: [
      {
        key: 'apiKey',
        label: 'API Key',
        kind: FieldKind.SECRET,
        required: true,
        placeholder: 'sk-…',
        helpText: '在 platform.deepseek.com → API keys 创建。'
      }
    ],
    baseUrlEditable: true,
    defaultBaseUrl: 'https://api.deepseek.com',
    experimental: false,
    usesBrowserSession: false,
    apiNote: 'GET /user/balance，Bearer 鉴权。',
    balanceCurrency: 'CNY'
  };

  async fetch(context: FetchContext): Promise<ProviderSnapshot> {
    const startedAt = context.now;
    const apiKey = requireField(context, 'apiKey', 'API Key');
    const base = context.baseUrl.trim() === '' ? this.descriptor.defaultBaseUrl : context.baseUrl.trim();
    const url = `${base.replace(/\/$/, '')}/user/balance`;
    const result = await HttpClient.get(url, Headers.bearer(apiKey), [apiKey]);
    const root = asObject(result.json);
    if (root === undefined) {
      throw new Error('响应不是合法 JSON');
    }
    const available = pickBoolean(root, 'is_available');
    const infos = root['balance_infos'];
    const balances: BalanceInfo[] = [];
    const list = Array.isArray(infos) ? infos as Object[] : [];
    for (const item of list) {
      const obj = asObject(item);
      if (obj === undefined) {
        continue;
      }
      const currency = firstString(obj, ['currency']);
      const total = firstNumber(obj, ['total_balance']);
      if (currency === undefined || total === undefined) {
        continue;
      }
      const granted = firstNumber(obj, ['granted_balance']);
      const toppedUp = firstNumber(obj, ['topped_up_balance']);
      const entry = balance(total, currency);
      entry.granted = granted;
      entry.toppedUp = toppedUp;
      balances.push(entry);
    }
    // 多币种优先 CNY，其余按原序附后。
    balances.sort((a: BalanceInfo, b: BalanceInfo) => {
      if (a.currency === b.currency) {
        return 0;
      }
      if (a.currency === 'CNY') {
        return -1;
      }
      if (b.currency === 'CNY') {
        return 1;
      }
      return 0;
    });
    const note = available === false ? '账户余额不足，API 调用会被拒绝' : undefined;
    if (note !== undefined && balances.length > 0) {
      balances[0].note = note;
    }
    return {
      providerId: this.descriptor.id,
      name: this.descriptor.name,
      kind: this.descriptor.kind,
      state: available === false ? FetchState.PARTIAL : FetchState.OK,
      windows: [],
      balances: balances,
      extra: {},
      fetchedAt: context.now,
      elapsedMs: context.now - startedAt
    };
  }
}

/**
 * Kimi / Moonshot 余额。
 *
 * GET https://api.moonshot.cn/v1/users/me/balance（国际站 api.moonshot.ai）
 * 响应是信封 {code, status, data}，必须先判 code==0 && status==true。
 */
export class KimiAdapter implements SourceAdapter {
  readonly descriptor: ProviderDescriptor = {
    id: 'kimi',
    name: 'Kimi / Moonshot',
    kind: SourceKind.BALANCE,
    summary: 'Kimi 开放平台余额，区分现金余额与代金券余额。',
    supports: { h5: false, week: false, month: false },
    credentialFields: [
      {
        key: 'apiKey',
        label: 'API Key',
        kind: FieldKind.SECRET,
        required: true,
        placeholder: 'sk-…',
        helpText: '国内站 platform.kimi.com 与国际站 platform.kimi.ai 的 Key 互相独立，不能混用。'
      },
      {
        key: 'region',
        label: '站点',
        kind: FieldKind.CHOICE,
        required: false,
        options: ['国内站', '国际站'],
        defaultValue: '国内站',
        helpText: '国内站余额单位 CNY，国际站为 USD。'
      }
    ],
    baseUrlEditable: false,
    defaultBaseUrl: 'https://api.moonshot.cn',
    experimental: false,
    usesBrowserSession: false,
    apiNote: 'GET /v1/users/me/balance，Bearer 鉴权。',
    balanceCurrency: 'CNY'
  };

  async fetch(context: FetchContext): Promise<ProviderSnapshot> {
    const startedAt = context.now;
    const apiKey = requireField(context, 'apiKey', 'API Key');
    const region = context.plain['region'];
    const base = region === '国际站' ? Endpoints.KIMI_INTL_BALANCE : Endpoints.KIMI_CN_BALANCE;
    const url = base;
    const result = await HttpClient.get(url, Headers.bearer(apiKey), [apiKey]);
    const root = asObject(result.json);
    if (root === undefined) {
      throw new Error('响应不是合法 JSON');
    }
    const code = firstNumber(root, ['code']);
    const status = pickBoolean(root, 'status');
    if (code !== 0 || status !== true) {
      const msg = firstString(root, ['error.message', 'scode']) ?? '接口返回失败';
      throw new Error(`Kimi 接口返回失败（code=${code ?? '?'}）：${msg}`);
    }
    const data = asObject(root['data']);
    if (data === undefined) {
      throw new Error('响应缺少 data 字段');
    }
    const available = toNum(data['available_balance']);
    if (available === undefined) {
      throw new Error('响应缺少 available_balance');
    }
    const currency = region === '国际站' ? 'USD' : 'CNY';
    const entry = balance(available, currency);
    entry.cash = toNum(data['cash_balance']);
    entry.voucher = toNum(data['voucher_balance']);
    if (entry.cash !== undefined && entry.cash < 0) {
      entry.note = '现金余额为负，表示欠费';
    }
    return {
      providerId: this.descriptor.id,
      name: this.descriptor.name,
      kind: this.descriptor.kind,
      state: FetchState.OK,
      windows: [],
      balances: [entry],
      extra: {},
      fetchedAt: context.now,
      elapsedMs: context.now - startedAt
    };
  }
}

/**
 * OpenRouter credits。
 *
 * GET https://openrouter.ai/api/v1/credits
 * 需要「管理 Key」，普通推理 Key 会返回 403。
 * 余额 = total_credits - total_usage。
 */
export class OpenRouterAdapter implements SourceAdapter {
  readonly descriptor: ProviderDescriptor = {
    id: 'openrouter',
    name: 'OpenRouter',
    kind: SourceKind.BALANCE,
    summary: 'OpenRouter 账户额度：已购总额度减去已用额度。',
    supports: { h5: false, week: false, month: false },
    credentialFields: [
      {
        key: 'apiKey',
        label: '管理 API Key',
        kind: FieldKind.SECRET,
        required: true,
        placeholder: 'sk-or-v1-…',
        helpText: '必须是 Management Key；普通推理 Key 会返回 403。'
      }
    ],
    baseUrlEditable: false,
    defaultBaseUrl: 'https://openrouter.ai',
    experimental: false,
    usesBrowserSession: false,
    apiNote: 'GET /api/v1/credits，Bearer 鉴权，需管理 Key。',
    balanceCurrency: 'USD'
  };

  async fetch(context: FetchContext): Promise<ProviderSnapshot> {
    const startedAt = context.now;
    const apiKey = requireField(context, 'apiKey', '管理 API Key');
    const result = await HttpClient.get(Endpoints.OPENROUTER_CREDITS, Headers.bearer(apiKey), [apiKey]);
    const root = asObject(result.json);
    if (root === undefined) {
      throw new Error('响应不是合法 JSON');
    }
    // 两版信封都见过：{data:{...}} 与裸顶层。
    const data = asObject(root['data']);
    const scope = data !== undefined ? data : root;
    const totalCredits = firstNumber(scope, ['total_credits']);
    const totalUsage = firstNumber(scope, ['total_usage']);
    if (totalCredits === undefined) {
      throw new Error('响应缺少 total_credits');
    }
    const used = totalUsage === undefined ? 0 : totalUsage;
    const remaining = Math.round((totalCredits - used) * 10000) / 10000;
    const entry = balance(remaining, 'USD');
    entry.note = `已购 ${totalCredits}，已用 ${used}`;
    return {
      providerId: this.descriptor.id,
      name: this.descriptor.name,
      kind: this.descriptor.kind,
      state: FetchState.OK,
      windows: [],
      balances: [entry],
      extra: {},
      fetchedAt: context.now,
      elapsedMs: context.now - startedAt
    };
  }
}

/**
 * 阶跃星辰余额。
 *
 * GET https://api.stepfun.com/v1/accounts
 * 返回 { object, type, balance, total_cash_balance, total_voucher_balance }。
 */
export class StepFunAdapter implements SourceAdapter {
  readonly descriptor: ProviderDescriptor = {
    id: 'stepfun',
    name: '阶跃星辰',
    kind: SourceKind.BALANCE,
    summary: '阶跃星辰开放平台账户余额，区分现金与代金券。',
    supports: { h5: false, week: false, month: false },
    credentialFields: [
      {
        key: 'apiKey',
        label: 'API Key',
        kind: FieldKind.SECRET,
        required: true,
        placeholder: 'sk-…',
        helpText: '在 platform.stepfun.com 的「API Keys」里创建。'
      }
    ],
    baseUrlEditable: false,
    defaultBaseUrl: 'https://api.stepfun.com',
    experimental: false,
    usesBrowserSession: false,
    apiNote: 'GET /v1/accounts，Bearer 鉴权。',
    balanceCurrency: 'CNY'
  };

  async fetch(context: FetchContext): Promise<ProviderSnapshot> {
    const startedAt = context.now;
    const apiKey = requireField(context, 'apiKey', 'API Key');
    const result = await HttpClient.get(Endpoints.STEPFUN_ACCOUNTS, Headers.bearer(apiKey), [apiKey]);
    const root = asObject(result.json);
    if (root === undefined) {
      throw new Error('响应不是合法 JSON');
    }
    const total = toNum(root['balance']);
    if (total === undefined) {
      throw new Error('响应缺少 balance 字段');
    }
    const entry = balance(total, 'CNY');
    entry.cash = toNum(root['total_cash_balance']);
    entry.voucher = toNum(root['total_voucher_balance']);
    return {
      providerId: this.descriptor.id,
      name: this.descriptor.name,
      kind: this.descriptor.kind,
      state: FetchState.OK,
      windows: [],
      balances: [entry],
      extra: {},
      fetchedAt: context.now,
      elapsedMs: context.now - startedAt
    };
  }
}

/**
 * 硅基流动余额。
 *
 * GET https://api.siliconflow.cn/v1/user/info（国际站 .com）
 * 返回 { code, data: { balance, chargeBalance, totalBalance } }。
 */
export class SiliconFlowAdapter implements SourceAdapter {
  readonly descriptor: ProviderDescriptor = {
    id: 'siliconflow',
    name: '硅基流动',
    kind: SourceKind.BALANCE,
    summary: '硅基流动账户余额，国内站人民币、国际站美元。',
    supports: { h5: false, week: false, month: false },
    credentialFields: [
      {
        key: 'apiKey',
        label: 'API Key',
        kind: FieldKind.SECRET,
        required: true,
        placeholder: 'sk-…',
        helpText: '在 cloud.siliconflow.cn 的「API 密钥」里创建。'
      },
      {
        key: 'region',
        label: '站点',
        kind: FieldKind.CHOICE,
        required: false,
        options: ['国内站', '国际站'],
        defaultValue: '国内站',
        helpText: '国内站余额单位 CNY，国际站为 USD。'
      }
    ],
    baseUrlEditable: false,
    defaultBaseUrl: 'https://api.siliconflow.cn',
    experimental: false,
    usesBrowserSession: false,
    apiNote: 'GET /v1/user/info，取 data.totalBalance。',
    balanceCurrency: 'CNY'
  };

  async fetch(context: FetchContext): Promise<ProviderSnapshot> {
    const startedAt = context.now;
    const apiKey = requireField(context, 'apiKey', 'API Key');
    const region = context.plain['region'];
    const url = region === '国际站' ? Endpoints.SILICONFLOW_EN_INFO : Endpoints.SILICONFLOW_CN_INFO;
    const result = await HttpClient.get(url, Headers.bearer(apiKey), [apiKey]);
    const root = asObject(result.json);
    if (root === undefined) {
      throw new Error('响应不是合法 JSON');
    }
    const data = asObject(root['data']);
    if (data === undefined) {
      throw new Error('响应缺少 data 字段');
    }
    const total = toNum(data['totalBalance']);
    if (total === undefined) {
      throw new Error('响应缺少 totalBalance');
    }
    const currency = region === '国际站' ? 'USD' : 'CNY';
    const entry = balance(total, currency);
    entry.toppedUp = toNum(data['chargeBalance']);
    entry.granted = toNum(data['balance']);
    return {
      providerId: this.descriptor.id,
      name: this.descriptor.name,
      kind: this.descriptor.kind,
      state: FetchState.OK,
      windows: [],
      balances: [entry],
      extra: {},
      fetchedAt: context.now,
      elapsedMs: context.now - startedAt
    };
  }
}

/**
 * Novita AI 余额。
 *
 * GET https://api.novita.ai/v3/user/balance
 * availableBalance 的单位是 0.0001 USD，展示前要除以 10000。
 */
export class NovitaAdapter implements SourceAdapter {
  readonly descriptor: ProviderDescriptor = {
    id: 'novita',
    name: 'Novita AI',
    kind: SourceKind.BALANCE,
    summary: 'Novita AI 账户可用余额。',
    supports: { h5: false, week: false, month: false },
    credentialFields: [
      {
        key: 'apiKey',
        label: 'API Key',
        kind: FieldKind.SECRET,
        required: true,
        placeholder: 'sk_…',
        helpText: '在 novita.ai 的「Key Management」里创建。'
      }
    ],
    baseUrlEditable: false,
    defaultBaseUrl: 'https://api.novita.ai',
    experimental: false,
    usesBrowserSession: false,
    apiNote: 'GET /v3/user/balance，金额需除以 10000。',
    balanceCurrency: 'USD'
  };

  async fetch(context: FetchContext): Promise<ProviderSnapshot> {
    const startedAt = context.now;
    const apiKey = requireField(context, 'apiKey', 'API Key');
    const result = await HttpClient.get(Endpoints.NOVITA_BALANCE, Headers.bearer(apiKey), [apiKey]);
    const root = asObject(result.json);
    if (root === undefined) {
      throw new Error('响应不是合法 JSON');
    }
    const raw = toNum(root['availableBalance']);
    if (raw === undefined) {
      throw new Error('响应缺少 availableBalance');
    }
    // 上游单位 0.0001 USD。
    const amount = raw / 10000;
    return {
      providerId: this.descriptor.id,
      name: this.descriptor.name,
      kind: this.descriptor.kind,
      state: FetchState.OK,
      windows: [],
      balances: [balance(amount, 'USD')],
      extra: {},
      fetchedAt: context.now,
      elapsedMs: context.now - startedAt
    };
  }
}
