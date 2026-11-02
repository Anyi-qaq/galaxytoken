import { FormExtensionAbility, formBindingData, formInfo, formProvider } from '@kit.FormKit';
import formInfoModule from '@ohos.app.form.formInfo';
import { Want } from '@kit.AbilityKit';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import {
  DashboardSnapshot,
  FetchState,
  ProviderSnapshot,
  QuotaWindow,
  WindowKind,
  remainingRatio
} from '../model/Types';
import { PREF_KEY_FORM_IDS, PREF_KEY_SNAPSHOT, PREF_STORE_NAME } from '../common/Constants';
import { Log } from '../common/Logger';
import { registerBuiltinSources } from '../sources/Bootstrap';

/**
 * 服务卡片的生命周期。
 *
 * 卡片不能做长时间后台任务，所以策略是：
 * 1. onAddForm / onUpdateForm 时先读主应用写入的快照缓存，立即渲染；
 * 2. 再尝试一次轻量刷新（只在有缓存时触发，避免冷启动卡顿）；
 * 3. 推送失败不抛异常，保留上一次的显示。
 */
export default class QuotaFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    Log.i('form onAddForm');
    try {
      registerBuiltinSources();
    } catch (error) {
      Log.e(`form register failed: ${error}`);
    }
    // onAddForm 必须同步返回首屏数据，因此这里用同步读取的缓存；
    // 拿不到就返回占位数据，等下一次 onUpdateForm 再补。
    // 记录 formId，主应用前台刷新后可以主动推送。
    const identity = want.parameters === undefined ? undefined : want.parameters[formInfoModule.FormParam.IDENTITY_KEY];
    if (typeof identity === 'string' || typeof identity === 'number') {
      this.rememberFormId(`${identity}`);
    }
    const data = this.readCacheSync();
    return formBindingData.createFormBindingData(data);
  }

  onUpdateForm(formId: string): void {
    Log.i('form onUpdateForm');
    this.refresh(formId);
  }

  onFormEvent(formId: string, message: string): void {
    Log.i(`form onFormEvent: ${message}`);
    if (message === 'refresh') {
      this.refresh(formId);
    }
  }

  onRemoveForm(formId: string): void {
    Log.i('form onRemoveForm');
  }

  onAcquireFormState(want: Want): formInfo.FormState {
    return formInfo.FormState.READY;
  }

  /** 把 formId 写进 preferences，供主应用推送时使用。 */
  private rememberFormId(formId: string): void {
    if (formId === '') {
      return;
    }
    try {
      const store = preferences.getPreferencesSync(this.context, { name: PREF_STORE_NAME });
      const raw = store.getSync(PREF_KEY_FORM_IDS, '');
      const ids: string[] = typeof raw === 'string' && raw !== '' ? JSON.parse(raw) as string[] : [];
      if (ids.indexOf(formId) < 0) {
        ids.push(formId);
        store.putSync(PREF_KEY_FORM_IDS, JSON.stringify(ids));
        store.flush();
        Log.i(`form id remembered: ${formId}`);
      }
    } catch (error) {
      Log.w(`remember form id failed: ${error}`);
    }
  }

  /**
   * 同步读取快照缓存。
   *
   * 卡片进程拿不到主应用的 Preferences 实例缓存，这里用 getPreferencesSync
   * 读一次；失败则返回占位数据，不影响卡片上屏。
   */
  private readCacheSync(): Record<string, Object> {
    try {
      const store = preferences.getPreferencesSync(this.context, { name: PREF_STORE_NAME });
      const raw = store.getSync(PREF_KEY_SNAPSHOT, '');
      if (typeof raw !== 'string' || raw === '') {
        return this.emptyData();
      }
      const snapshot = JSON.parse(raw) as DashboardSnapshot;
      return buildBindingData(snapshot);
    } catch (error) {
      Log.w(`form cache read failed: ${error}`);
      return this.emptyData();
    }
  }

  private async refresh(formId: string): Promise<void> {
    try {
      const context = this.context as common.ExtensionContext;
      const store = await preferences.getPreferences(context, { name: PREF_STORE_NAME });
      const raw = await store.get(PREF_KEY_SNAPSHOT, '');
      if (typeof raw !== 'string' || raw === '') {
        return;
      }
      const snapshot = JSON.parse(raw) as DashboardSnapshot;
      const data = buildBindingData(snapshot);
      await formProvider.updateForm(formId, formBindingData.createFormBindingData(data));
      Log.i('form updated from cache');
    } catch (error) {
      Log.w(`form refresh failed: ${error}`);
    }
  }

  private emptyData(): Record<string, Object> {
    return {
      'headlineTitle': '星河 Token',
      'headlineLabel': '尚未刷新',
      'headlineValue': '—',
      'headlinePercent': 0,
      'headlineReset': '',
      'headlineColor': '#9A9A9E',
      'rowCount': 0,
      'row1': '',
      'row2': '',
      'row3': '',
      'balanceText': '',
      'updatedText': '打开应用以获取数据'
    };
  }
}

/** 把快照压缩成卡片能直接渲染的扁平字段。 */
export function buildBindingData(snapshot: DashboardSnapshot): Record<string, Object> {
  const tightest = pickTightest(snapshot);
  const data: Record<string, Object> = {};
  if (tightest === undefined) {
    data['headlineTitle'] = '星河 Token';
    data['headlineLabel'] = '暂无可用数据';
    data['headlineValue'] = '—';
    data['headlinePercent'] = 0;
    data['headlineReset'] = '';
    data['headlineColor'] = '#9A9A9E';
  } else {
    const ratio = remainingRatio(tightest.window);
    const percent = ratio === undefined ? 0 : Math.round(ratio * 100);
    data['headlineTitle'] = tightest.snapshot.name;
    data['headlineLabel'] = windowLabelOf(tightest.window.kind);
    data['headlineValue'] = `${percent}%`;
    data['headlinePercent'] = percent;
    data['headlineReset'] = countdown(tightest.window.resetAt, snapshot.refreshedAt);
    data['headlineColor'] = percent <= 10 ? '#F0523A' : (percent <= 30 ? '#F2A33C' : '#3BA55D');
  }

  const rows: string[] = [];
  for (const provider of snapshot.providers) {
    if (rows.length >= 3) {
      break;
    }
    if (provider.state !== FetchState.OK && provider.state !== FetchState.PARTIAL) {
      continue;
    }
    const summary = summarize(provider);
    if (summary !== '') {
      rows.push(`${provider.name}｜${summary}`);
    }
  }
  data['rowCount'] = rows.length;
  data['row1'] = rows.length > 0 ? rows[0] : '';
  data['row2'] = rows.length > 1 ? rows[1] : '';
  data['row3'] = rows.length > 2 ? rows[2] : '';

  const balances: string[] = [];
  for (const provider of snapshot.providers) {
    for (const item of provider.balances) {
      balances.push(`${provider.name} ${item.currency} ${trimNumber(item.amount)}`);
    }
  }
  data['balanceText'] = balances.length === 0 ? '' : balances.slice(0, 2).join(' · ');
  data['updatedText'] = snapshot.refreshedAt > 0 ? '已更新' : '打开应用以获取数据';
  return data;
}

interface TightestEntry {
  snapshot: ProviderSnapshot;
  window: QuotaWindow;
}

/** 找出剩余最少且未过期的窗口。 */
function pickTightest(snapshot: DashboardSnapshot): TightestEntry | undefined {
  let best: TightestEntry | undefined = undefined;
  let bestRatio = 2;
  for (const provider of snapshot.providers) {
    if (provider.state !== FetchState.OK && provider.state !== FetchState.PARTIAL) {
      continue;
    }
    for (const window of provider.windows) {
      const ratio = remainingRatio(window);
      if (ratio === undefined) {
        continue;
      }
      if (window.resetAt !== undefined && window.resetAt <= snapshot.refreshedAt) {
        continue;
      }
      if (ratio < bestRatio) {
        bestRatio = ratio;
        best = { snapshot: provider, window: window };
      }
    }
  }
  return best;
}

/** 一个来源的紧凑摘要：三窗口剩余百分比。 */
function summarize(provider: ProviderSnapshot): string {
  const parts: string[] = [];
  for (const window of provider.windows) {
    const ratio = remainingRatio(window);
    if (ratio === undefined) {
      continue;
    }
    parts.push(`${shortLabel(window.kind)}${Math.round(ratio * 100)}%`);
  }
  if (parts.length === 0 && provider.balances.length > 0) {
    const first = provider.balances[0];
    return `${first.currency} ${trimNumber(first.amount)}`;
  }
  return parts.join(' ');
}

function shortLabel(kind: WindowKind): string {
  switch (kind) {
    case WindowKind.H5:
      return '5h ';
    case WindowKind.WEEK:
      return '周 ';
    case WindowKind.MONTH:
      return '月 ';
    default:
      return '';
  }
}

function windowLabelOf(kind: WindowKind): string {
  switch (kind) {
    case WindowKind.H5:
      return '5 小时窗口';
    case WindowKind.WEEK:
      return '本周窗口';
    case WindowKind.MONTH:
      return '本月窗口';
    default:
      return '额度';
  }
}

function countdown(resetAt: number | undefined, now: number): string {
  if (resetAt === undefined) {
    return '';
  }
  const delta = resetAt - now;
  if (delta <= 0) {
    return '即将重置';
  }
  const minutes = Math.floor(delta / 60000);
  const hours = Math.floor(minutes / 60);
  if (hours >= 24) {
    return `${Math.floor(hours / 24)} 天后重置`;
  }
  if (hours > 0) {
    return `${hours} 小时后重置`;
  }
  return `${minutes} 分钟后重置`;
}

function trimNumber(value: number): string {
  const fixed = value.toFixed(2);
  if (fixed.endsWith('.00')) {
    return fixed.substring(0, fixed.length - 3);
  }
  return fixed;
}
