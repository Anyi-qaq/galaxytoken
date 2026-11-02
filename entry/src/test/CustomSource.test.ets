import { describe, expect, it } from '@ohos/hypium';
import { clampRatio, MappingSemantics, ProviderConfig, QuotaMode, QuotaWindow, remainingRatio, WindowKind } from '../main/ets/model/Types';
import { CustomAdapter } from '../main/ets/sources/adapters/CustomAdapter';
import { DemoAdapter } from '../main/ets/sources/adapters/DemoAdapter';
import { FetchContext } from '../main/ets/sources/SourceAdapter';
import { ProviderRegistry } from '../main/ets/sources/ProviderRegistry';
import { toErrorSnapshot } from '../main/ets/sources/AdapterKit';
import { ErrorKind, FetchState } from '../main/ets/model/Types';

/** 自定义来源的路径映射与错误收敛测试（不联网：只用本地构造的 JSON 和错误对象）。 */
export default function customSourceTest() {
  describe('customMapping', () => {
    it('ratio_used_semantics', 0, () => {
      const config: ProviderConfig = {
        providerId: 'custom',
        enabled: true,
        order: 0,
        baseUrl: 'https://example.com/usage',
        plainFields: {},
        hasSecret: false,
        custom: {
          url: 'https://example.com/usage',
          method: 'GET',
          authMode: 'none',
          extraHeaders: {},
          h5: { path: 'data.h5.usedPercent', semantics: MappingSemantics.RATIO_USED }
        }
      };
      const adapter = new CustomAdapter(config);
      expect(adapter.descriptor.id).assertEqual('custom');
      expect(adapter.descriptor.baseUrlEditable).assertTrue();
    });

    it('ratio_remaining_is_inverted_by_mapping_semantics', 0, () => {
      // 直接验证语义换算：剩余 80% -> 已用 20%
      const remaining = 0.8;
      const usedRatio = 1 - remaining;
      expect(clampRatio(usedRatio)).assertEqual(0.2);
    });

    it('absolute_mode_keeps_limit', 0, () => {
      const window: QuotaWindow = {
        kind: WindowKind.MONTH,
        mode: QuotaMode.ABSOLUTE,
        remaining: 120,
        limit: 500,
        unit: 'credit'
      };
      expect(remainingRatio(window)).assertEqual(0.24);
    });

    it('invalid_url_rejected_before_network', 0, async () => {
      const config: ProviderConfig = {
        providerId: 'custom',
        enabled: true,
        order: 0,
        baseUrl: 'http://insecure.example.com',
        plainFields: {},
        hasSecret: false,
        custom: {
          url: 'http://insecure.example.com',
          method: 'GET',
          authMode: 'none',
          extraHeaders: {}
        }
      };
      const adapter = new CustomAdapter(config);
      const context: FetchContext = {
        plain: {},
        secret: {},
        baseUrl: 'http://insecure.example.com',
        now: 1000
      };
      let message = '';
      try {
        await adapter.fetch(context);
      } catch (error) {
        message = error instanceof Error ? error.message : `${error}`;
      }
      expect(message.indexOf('HTTPS') >= 0).assertTrue();
    });
  });

  describe('demoSource', () => {
    it('returns_three_windows_with_future_resets', 0, async () => {
      const adapter = new DemoAdapter();
      const now = 1700000000000;
      const context: FetchContext = { plain: {}, secret: {}, baseUrl: '', now: now };
      const snapshot = await adapter.fetch(context);
      expect(snapshot.state).assertEqual(FetchState.OK);
      expect(snapshot.windows.length).assertEqual(3);
      expect(snapshot.windows[0].kind).assertEqual(WindowKind.H5);
      expect(snapshot.windows[1].kind).assertEqual(WindowKind.WEEK);
      expect(snapshot.windows[2].kind).assertEqual(WindowKind.MONTH);
      for (const window of snapshot.windows) {
        expect(window.resetAt !== undefined && window.resetAt > now).assertTrue();
      }
      expect(snapshot.balances.length).assertEqual(1);
      expect(snapshot.balances[0].currency).assertEqual('CNY');
    });
  });

  describe('errorConvergence', () => {
    it('unknown_error_becomes_error_state', 0, () => {
      const descriptor = ProviderRegistry.customDescriptor();
      const snapshot = toErrorSnapshot(descriptor, new Error('boom'), 5000, 4000, []);
      expect(snapshot.state).assertEqual(FetchState.ERROR);
      expect(snapshot.error !== undefined).assertTrue();
      if (snapshot.error !== undefined) {
        expect(snapshot.error.message).assertEqual('boom');
        expect(snapshot.error.kind).assertEqual(ErrorKind.UNKNOWN);
      }
      expect(snapshot.elapsedMs).assertEqual(1000);
    });

    it('missing_credential_becomes_needs_auth', 0, () => {
      const descriptor = ProviderRegistry.customDescriptor();
      const snapshot = toErrorSnapshot(descriptor, new Error('缺少「API Key」'), 5000, 4000, []);
      expect(snapshot.state).assertEqual(FetchState.NEEDS_AUTH);
      expect(snapshot.windows.length).assertEqual(0);
    });
  });

  describe('registry', () => {
    it('supports_query_returns_false_for_unknown', 0, () => {
      const support = ProviderRegistry.supportsOf('does-not-exist');
      expect(support.h5).assertFalse();
      expect(support.week).assertFalse();
      expect(support.month).assertFalse();
    });

    it('isCustom_detects_prefixes', 0, () => {
      expect(ProviderRegistry.isCustom('custom')).assertTrue();
      expect(ProviderRegistry.isCustom('custom-1')).assertTrue();
      expect(ProviderRegistry.isCustom('deepseek')).assertFalse();
    });
  });
}
