import { FetchContext, SourceAdapter } from './SourceAdapter';
import {
  CredentialField,
  FieldKind,
  ProviderConfig,
  ProviderDescriptor,
  SourceKind,
  WindowSupport
} from '../model/Types';
import { ProviderIds } from '../common/Constants';

/**
 * 来源注册表。
 *
 * 静态注册所有内置来源；自定义来源按配置动态构造。
 * 新增来源只需在此处追加一行，UI 与卡片不需要任何改动。
 */
export class ProviderRegistry {
  private static adapters: Map<string, SourceAdapter> = new Map<string, SourceAdapter>();
  private static descriptors: ProviderDescriptor[] = [];
  private static initialized: boolean = false;

  /** 注册内置来源。由 EntryAbility 启动时调用一次。 */
  static init(adapters: SourceAdapter[]): void {
    ProviderRegistry.adapters.clear();
    ProviderRegistry.descriptors = [];
    for (const adapter of adapters) {
      ProviderRegistry.adapters.set(adapter.descriptor.id, adapter);
      ProviderRegistry.descriptors.push(adapter.descriptor);
    }
    ProviderRegistry.initialized = true;
  }

  /** 是否已初始化。 */
  static ready(): boolean {
    return ProviderRegistry.initialized;
  }

  /** 全部内置来源描述符（按展示顺序）。 */
  static all(): ProviderDescriptor[] {
    return ProviderRegistry.descriptors.slice();
  }

  /** 按 id 取描述符。 */
  static descriptorOf(id: string): ProviderDescriptor | undefined {
    return ProviderRegistry.adapters.get(id)?.descriptor;
  }

  /** 按 id 取适配器。 */
  static adapterOf(id: string): SourceAdapter | undefined {
    return ProviderRegistry.adapters.get(id);
  }

  /** 窗口支持矩阵查询，供 Types.normalizeWindows 使用。 */
  static supportsOf(id: string): WindowSupport {
    const descriptor = ProviderRegistry.descriptorOf(id);
    if (descriptor === undefined) {
      return { h5: false, week: false, month: false };
    }
    return descriptor.supports;
  }

  /** 生成某个来源的默认配置。 */
  static defaultConfig(descriptor: ProviderDescriptor, order: number): ProviderConfig {
    const plainFields: Record<string, string> = {};
    for (const field of descriptor.credentialFields) {
      if (field.kind !== FieldKind.SECRET && field.defaultValue !== undefined) {
        plainFields[field.key] = field.defaultValue;
      }
    }
    return {
      providerId: descriptor.id,
      enabled: false,
      order: order,
      baseUrl: descriptor.defaultBaseUrl,
      plainFields: plainFields,
      hasSecret: false
    };
  }

  /** 是否为自定义来源 id。 */
  static isCustom(id: string): boolean {
    return id === ProviderIds.CUSTOM || id.startsWith('custom-');
  }

  /** 自定义来源的默认描述符。 */
  static customDescriptor(): ProviderDescriptor {
    const fields: CredentialField[] = [
      {
        key: 'secret',
        label: '凭据值',
        kind: FieldKind.SECRET,
        required: false,
        placeholder: '按所选认证方式填写',
        helpText: '如果认证方式为「无」，可留空。'
      }
    ];
    return {
      id: ProviderIds.CUSTOM,
      name: '自定义来源',
      kind: SourceKind.BOTH,
      summary: '自行填写 HTTPS 端点与 JSON 字段路径，适配任意厂商。',
      supports: { h5: true, week: true, month: true },
      credentialFields: fields,
      baseUrlEditable: true,
      defaultBaseUrl: '',
      experimental: false,
      usesBrowserSession: false,
      apiNote: '用户自定义端点；请求只会发往你填写的域名。'
    };
  }
}
