import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { AppSettings, DashboardSnapshot, ProviderConfig } from '../model/Types';
import {
  DEFAULT_MONEY_DECIMALS,
  DEFAULT_REFRESH_SEC,
  PREF_KEY_FORM_IDS,
  PREF_KEY_PROVIDERS,
  PREF_KEY_SETTINGS,
  PREF_KEY_SNAPSHOT,
  PREF_STORE_NAME
} from '../common/Constants';
import { Log } from '../common/Logger';

/**
 * 非密配置与快照缓存。
 *
 * 凭据一律不进这里；这里只存开关、排序、Base URL、自定义映射与最近一次快照。
 */
export class SettingsStore {
  private static store: preferences.Preferences | undefined = undefined;

  /** 由 EntryAbility 在启动时注入 context。 */
  static async init(context: common.Context): Promise<void> {
    if (SettingsStore.store !== undefined) {
      return;
    }
    const options: preferences.Options = { name: PREF_STORE_NAME };
    SettingsStore.store = await preferences.getPreferences(context, options);
    Log.i('preferences ready');
  }

  /** 是否已初始化。 */
  static ready(): boolean {
    return SettingsStore.store !== undefined;
  }

  /** 读取来源配置列表。 */
  static async loadProviders(): Promise<ProviderConfig[]> {
    const raw = await SettingsStore.readString(PREF_KEY_PROVIDERS);
    if (raw === undefined || raw === '') {
      return [];
    }
    try {
      const parsed = JSON.parse(raw) as ProviderConfig[];
      if (!Array.isArray(parsed)) {
        return [];
      }
      return parsed;
    } catch (error) {
      Log.w('provider config JSON is corrupted, reset to empty');
      return [];
    }
  }

  /** 写回来源配置列表。 */
  static async saveProviders(list: ProviderConfig[]): Promise<void> {
    await SettingsStore.writeString(PREF_KEY_PROVIDERS, JSON.stringify(list));
  }

  /** 读取应用设置，缺失字段回落到默认值。 */
  static async loadSettings(): Promise<AppSettings> {
    const raw = await SettingsStore.readString(PREF_KEY_SETTINGS);
    const defaults: AppSettings = {
      refreshIntervalSec: DEFAULT_REFRESH_SEC,
      moneyDecimals: DEFAULT_MONEY_DECIMALS,
      demoMode: false,
      showExperimental: true
    };
    if (raw === undefined || raw === '') {
      return defaults;
    }
    try {
      const parsed = JSON.parse(raw) as AppSettings;
      const merged: AppSettings = {
        refreshIntervalSec: typeof parsed.refreshIntervalSec === 'number'
          ? parsed.refreshIntervalSec : defaults.refreshIntervalSec,
        moneyDecimals: typeof parsed.moneyDecimals === 'number'
          ? parsed.moneyDecimals : defaults.moneyDecimals,
        demoMode: typeof parsed.demoMode === 'boolean' ? parsed.demoMode : defaults.demoMode,
        showExperimental: typeof parsed.showExperimental === 'boolean'
          ? parsed.showExperimental : defaults.showExperimental
      };
      return merged;
    } catch (error) {
      return defaults;
    }
  }

  /** 写回应用设置。 */
  static async saveSettings(settings: AppSettings): Promise<void> {
    await SettingsStore.writeString(PREF_KEY_SETTINGS, JSON.stringify(settings));
  }

  /** 读取最近一次快照（卡片与冷启动首屏用）。 */
  static async loadSnapshot(): Promise<DashboardSnapshot | undefined> {
    const raw = await SettingsStore.readString(PREF_KEY_SNAPSHOT);
    if (raw === undefined || raw === '') {
      return undefined;
    }
    try {
      return JSON.parse(raw) as DashboardSnapshot;
    } catch (error) {
      return undefined;
    }
  }

  /** 写入快照。 */
  static async saveSnapshot(snapshot: DashboardSnapshot): Promise<void> {
    await SettingsStore.writeString(PREF_KEY_SNAPSHOT, JSON.stringify(snapshot));
  }

  /** 读取已记录的卡片 id 列表。 */
  static async loadFormIds(): Promise<string[]> {
    const raw = await SettingsStore.readString(PREF_KEY_FORM_IDS);
    if (raw === undefined || raw === '') {
      return [];
    }
    try {
      const parsed = JSON.parse(raw) as string[];
      return Array.isArray(parsed) ? parsed : [];
    } catch (error) {
      return [];
    }
  }

  /** 写回卡片 id 列表。 */
  static async saveFormIds(ids: string[]): Promise<void> {
    await SettingsStore.writeString(PREF_KEY_FORM_IDS, JSON.stringify(ids));
  }

  /** 清空全部缓存（设置页用）。 */
  static async clearSnapshot(): Promise<void> {
    const store = SettingsStore.store;
    if (store === undefined) {
      return;
    }
    await store.delete(PREF_KEY_SNAPSHOT);
    await store.flush();
  }

  private static async readString(key: string): Promise<string | undefined> {
    const store = SettingsStore.store;
    if (store === undefined) {
      return undefined;
    }
    try {
      const value = await store.get(key, '');
      return typeof value === 'string' ? value : undefined;
    } catch (error) {
      Log.w(`preferences read failed: ${key}`);
      return undefined;
    }
  }

  private static async writeString(key: string, value: string): Promise<void> {
    const store = SettingsStore.store;
    if (store === undefined) {
      Log.w(`preferences not ready, skip write: ${key}`);
      return;
    }
    await store.put(key, value);
    await store.flush();
  }
}
