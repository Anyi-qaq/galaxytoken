import { SourceAdapter } from './SourceAdapter';
import { ProviderRegistry } from './ProviderRegistry';
import { setSupportLookup } from '../model/Types';
import { DemoAdapter } from './adapters/DemoAdapter';
import {
  DeepSeekAdapter,
  KimiAdapter,
  NovitaAdapter,
  OpenRouterAdapter,
  SiliconFlowAdapter,
  StepFunAdapter
} from './adapters/BalanceAdapters';
import { GlmAdapter, KimiCodeAdapter, MiniMaxAdapter } from './adapters/SubscriptionAdapters';

/**
 * 内置来源装配。
 *
 * 清单对齐 cc-switch（github.com/farion1231/cc-switch）已验证的实现：
 * `services/balance.rs` 负责余额类，`services/coding_plan.rs` 负责套餐类。
 * 只收「一次请求 + 一个 Key」就能查完的来源，凡是需要 Cookie、OAuth、
 * 二次换取 Token、或只在网页控制台可见的一律不收。
 *
 * 自定义来源（CustomAdapter）不在这里注册 —— 它需要用户填好的配置才能
 * 构造，由服务层在读配置时按需创建，见 ProviderRegistry.customDescriptor()。
 *
 * 新增来源只需在这里追加一行；UI、卡片、服务层都不需要改动。
 * 顺序即首页与来源管理页的默认展示顺序：先余额（最常用），再套餐。
 */
export function registerBuiltinSources(): void {
  const adapters: SourceAdapter[] = [
    new DemoAdapter(),
    // 余额类
    new DeepSeekAdapter(),
    new KimiAdapter(),
    new OpenRouterAdapter(),
    new StepFunAdapter(),
    new SiliconFlowAdapter(),
    new NovitaAdapter(),
    // 套餐类
    new KimiCodeAdapter(),
    new GlmAdapter(),
    new MiniMaxAdapter()
  ];
  ProviderRegistry.init(adapters);
  setSupportLookup((id: string) => ProviderRegistry.supportsOf(id));
}
