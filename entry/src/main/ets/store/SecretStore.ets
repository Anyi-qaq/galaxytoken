import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { ASSET_ALIAS_PREFIX } from '../common/Constants';
import { Log } from '../common/Logger';

/**
 * 凭据存储。
 *
 * 使用系统 Asset Store（@kit.AssetStoreKit）：
 * - 密钥由系统密钥库加密，密文不落应用沙箱明文；
 * - 一个 provider 一条记录，alias = 前缀 + providerId；
 * - 需要设备解锁后才能读取（DEVICE_UNLOCKED）。
 *
 * 凭据内容以 JSON 字符串形式整体存进 SECRET 字段，读取时再拆成字段表。
 */
export class SecretStore {
  /** 保存一个来源的全部密文字段。 */
  static async save(providerId: string, values: Record<string, string>): Promise<void> {
    const alias = ASSET_ALIAS_PREFIX + providerId;
    const payload = JSON.stringify(values);
    await SecretStore.remove(providerId);
    if (payload === '{}' || values === undefined) {
      return;
    }
    const attrs: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    attrs.set(asset.Tag.SECRET, encodeUtf8(payload));
    attrs.set(asset.Tag.ALIAS, encodeUtf8(alias));
    attrs.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_UNLOCKED);
    attrs.set(asset.Tag.DATA_LABEL_NORMAL_1, encodeUtf8(providerId));
    try {
      await asset.add(attrs);
      Log.secret(`asset saved ${providerId}`, payload);
    } catch (error) {
      const be = error as BusinessError;
      if (be.code === asset.ErrorCode.DUPLICATED) {
        await asset.update(queryByAlias(alias), attrs);
        Log.secret(`asset updated ${providerId}`, payload);
        return;
      }
      Log.e(`asset save failed ${providerId} code=${be.code} msg=${be.message}`);
      throw new Error(`凭据保存失败（错误码 ${be.code}）`);
    }
  }

  /** 读取一个来源的全部密文字段；不存在返回空表。 */
  static async load(providerId: string): Promise<Record<string, string>> {
    const alias = ASSET_ALIAS_PREFIX + providerId;
    const query: asset.AssetMap = queryByAlias(alias);
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    try {
      const rows = await asset.query(query);
      if (rows.length === 0) {
        return {};
      }
      const secret = rows[0].get(asset.Tag.SECRET);
      if (secret === undefined || !(secret instanceof Uint8Array)) {
        return {};
      }
      const text = decodeUtf8(secret);
      return parseFields(text);
    } catch (error) {
      const be = error as BusinessError;
      if (be.code === asset.ErrorCode.NOT_FOUND) {
        return {};
      }
      Log.e(`asset load failed ${providerId} code=${be.code}`);
      return {};
    }
  }

  /** 是否已存在凭据。 */
  static async exists(providerId: string): Promise<boolean> {
    const fields = await SecretStore.load(providerId);
    return Object.keys(fields).length > 0;
  }

  /** 删除一个来源的凭据；不存在时静默。 */
  static async remove(providerId: string): Promise<void> {
    const alias = ASSET_ALIAS_PREFIX + providerId;
    try {
      await asset.remove(queryByAlias(alias));
    } catch (error) {
      const be = error as BusinessError;
      if (be.code !== asset.ErrorCode.NOT_FOUND) {
        Log.w(`asset remove failed ${providerId} code=${be.code}`);
      }
    }
  }
}

function queryByAlias(alias: string): asset.AssetMap {
  const query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
  query.set(asset.Tag.ALIAS, encodeUtf8(alias));
  return query;
}

function parseFields(text: string): Record<string, string> {
  const out: Record<string, string> = {};
  if (text.trim() === '') {
    return out;
  }
  try {
    const parsed = JSON.parse(text) as Object;
    const rec = parsed as Record<string, Object>;
    const keys = Object.keys(rec);
    for (const key of keys) {
      const value = rec[key];
      if (typeof value === 'string') {
        out[key] = value;
      }
    }
  } catch (error) {
    Log.w('credential payload is not valid JSON, ignored');
  }
  return out;
}

function encodeUtf8(text: string): Uint8Array {
  const encoder = new util.TextEncoder();
  return encoder.encodeInto(text);
}

function decodeUtf8(bytes: Uint8Array): string {
  const decoder = util.TextDecoder.create('utf-8');
  return decoder.decodeToString(bytes);
}
