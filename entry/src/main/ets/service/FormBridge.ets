import { formBindingData, formProvider } from '@kit.FormKit';
import { DashboardSnapshot, FetchState, ProviderSnapshot, QuotaWindow, WindowKind, remainingRatio } from '../model/Types';
import { PREF_KEY_FORM_IDS } from '../common/Constants';
import { SettingsStore } from '../store/SettingsStore';
import { Log } from '../common/Logger';

/**
 * 主应用 → 服务卡片的主动推送。
 *
 * 卡片每 30 分钟才被系统刷新一次，因此前台拿到新数据后必须主动推一次，
 * 否则用户看到的永远是旧值。这里负责：
 * 1. 把快照压成卡片的扁平字段；
 * 2. 遍历已知的 formId 逐个 updateForm；
 * 3. 任何失败都只记日志，绝不打断主流程。
 */
export class FormBridge {
  /** 记录一个新的 formId（避免重复）。 */
  static async rememberFormId(formId: string): Promise<void> {
    if (formId === '') {
      return;
    }
    const ids = await FormBridge.formIds();
    if (ids.indexOf(formId) >= 0) {
      return;
    }
    ids.push(formId);
    await SettingsStore.saveFormIds(ids);
  }

  /** 读取已记录的 formId 列表。 */
  static async formIds(): Promise<string[]> {
    return SettingsStore.loadFormIds();
  }

  /** 把最新快照推给所有卡片。 */
  static async push(snapshot: DashboardSnapshot): Promise<void> {
    const ids = await FormBridge.formIds();
    if (ids.length === 0) {
      return;
    }
    const data = FormBridge.buildData(snapshot);
    for (const formId of ids) {
      try {
        await formProvider.updateForm(formId, formBindingData.createFormBindingData(data));
      } catch (error) {
        Log.w(`updateForm failed for ${formId}`);
      }
    }
  }

  /** 把快照压成卡片可直接绑定的扁平字段。 */
  static buildData(snapshot: DashboardSnapshot): Record<string, Object> {
    const data: Record<string, Object> = {};
    const tightest = FormBridge.pickTightest(snapshot);
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
      data['headlineLabel'] = labelOf(tightest.window.kind);
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
      const summary = FormBridge.summarize(provider);
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

  private static pickTightest(snapshot: DashboardSnapshot): TightestEntry | undefined {
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

  private static summarize(provider: ProviderSnapshot): string {
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
}

interface TightestEntry {
  snapshot: ProviderSnapshot;
  window: QuotaWindow;
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

function labelOf(kind: WindowKind): string {
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
