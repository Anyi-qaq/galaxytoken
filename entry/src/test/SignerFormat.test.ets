import { describe, expect, it } from '@ohos/hypium';
import { acs3DateNow, buildCanonicalQuery, hmacSha256Hex, sha256Hex } from '../main/ets/net/Acs3Signer';
import { countdownText, formatNumber, moneyText, relativeTime, absoluteText, toProgressValue } from '../main/ets/common/Format';
import { QuotaMode, QuotaWindow, WindowKind } from '../main/ets/model/Types';
import { buildBindingData } from '../main/ets/widgetability/QuotaFormAbility';
import { DashboardSnapshot, FetchState, ProviderSnapshot, SourceKind } from '../main/ets/model/Types';

/** 签名、格式化与卡片数据压缩的测试。 */
export default function signerAndFormatTest() {
  describe('acs3', () => {
    it('sha256_empty_string_matches_known_vector', 0, async () => {
      const digest = await sha256Hex('');
      expect(digest).assertEqual('e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
    });

    it('sha256_abc_matches_known_vector', 0, async () => {
      const digest = await sha256Hex('abc');
      expect(digest).assertEqual('ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    });

    it('hmac_sha256_matches_rfc4231_case2', 0, async () => {
      // RFC 4231 Test Case 2: key="Jefe", data="what do ya want for nothing?"
      const mac = await hmacSha256Hex('Jefe', 'what do ya want for nothing?');
      expect(mac).assertEqual('5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843');
    });

    it('canonical_query_sorts_and_encodes', 0, () => {
      const query: Record<string, string> = {};
      query['b'] = '2';
      query['a'] = '1 2';
      expect(buildCanonicalQuery(query)).assertEqual('a=1%202&b=2');
    });

    it('canonical_query_empty', 0, () => {
      expect(buildCanonicalQuery({})).assertEqual('');
    });

    it('date_format_is_iso_seconds_without_millis', 0, () => {
      const text = acs3DateNow(1700000000123);
      expect(text).assertEqual('2023-11-14T22:13:20Z');
    });
  });

  describe('format', () => {
    it('formatNumber_trims_trailing_zeros', 0, () => {
      expect(formatNumber(128.45, 2)).assertEqual('128.45');
      expect(formatNumber(128.0, 2)).assertEqual('128');
      expect(formatNumber(0.5, 2)).assertEqual('0.5');
      expect(formatNumber(3.14159, 4)).assertEqual('3.1416');
    });

    it('moneyText_uses_currency_symbol', 0, () => {
      expect(moneyText(128.45, 'CNY', 2)).assertEqual('¥128.45');
      expect(moneyText(3.2, 'USD', 2)).assertEqual('$3.2');
      expect(moneyText(-5, 'CNY', 2)).assertEqual('¥-5');
      expect(moneyText(1, 'EUR', 2)).assertEqual('€1');
    });

    it('countdownText_handles_boundaries', 0, () => {
      const now = 1000000;
      // 2 小时 44 分
      expect(countdownText(now + 9840000, now)).assertEqual('2小时44分');
      // 4 天 3 小时
      expect(countdownText(now + 363600000, now)).assertEqual('4天3小时');
      // 已过期
      expect(countdownText(now - 1000, now)).assertEqual('即将重置');
      // 无重置时间
      expect(countdownText(undefined, now)).assertEqual('');
      // 不足 1 小时
      expect(countdownText(now + 300000, now)).assertEqual('5分');
    });

    it('relativeTime_buckets', 0, () => {
      const now = 100000000;
      expect(relativeTime(now - 1000, now)).assertEqual('刚刚更新');
      expect(relativeTime(now - 180000, now)).assertEqual('3 分钟前');
      expect(relativeTime(now - 7200000, now)).assertEqual('2 小时前');
      expect(relativeTime(now - 172800000, now)).assertEqual('2 天前');
      expect(relativeTime(0, now)).assertEqual('从未更新');
    });

    it('absoluteText_includes_limit', 0, () => {
      const withLimit: QuotaWindow = {
        kind: WindowKind.H5,
        mode: QuotaMode.ABSOLUTE,
        remaining: 820,
        limit: 1000,
        unit: 'prompt'
      };
      expect(absoluteText(withLimit, 2)).assertEqual('820 / 1000 prompt');
      const noLimit: QuotaWindow = {
        kind: WindowKind.MONTH,
        mode: QuotaMode.ABSOLUTE,
        remaining: 50,
        limit: 0,
        unit: 'credit'
      };
      expect(absoluteText(noLimit, 2)).assertEqual('50 credit');
    });

    it('toProgressValue_inverts_to_remaining', 0, () => {
      const window: QuotaWindow = { kind: WindowKind.H5, mode: QuotaMode.RATIO, usedRatio: 0.25 };
      expect(toProgressValue(window)).assertEqual(75);
    });
  });

  describe('widgetBinding', () => {
    it('picks_tightest_window_and_formats_rows', 0, () => {
      const snapshot: DashboardSnapshot = {
        providers: [
          {
            providerId: 'a',
            name: '来源A',
            kind: SourceKind.SUBSCRIPTION,
            state: FetchState.OK,
            windows: [
              { kind: WindowKind.H5, mode: QuotaMode.RATIO, usedRatio: 0.9 },
              { kind: WindowKind.WEEK, mode: QuotaMode.RATIO, usedRatio: 0.2 }
            ],
            balances: [],
            extra: {},
            fetchedAt: 1000
          },
          {
            providerId: 'b',
            name: '来源B',
            kind: SourceKind.BALANCE,
            state: FetchState.OK,
            windows: [],
            balances: [{ amount: 128.45, currency: 'CNY' }],
            extra: {},
            fetchedAt: 1000
          }
        ],
        refreshedAt: 1000
      };
      const data = buildBindingData(snapshot);
      // 最紧张的是来源A 的 5h（剩余 10%）
      expect(data['headlineTitle']).assertEqual('来源A');
      expect(data['headlineValue']).assertEqual('10%');
      expect(data['headlinePercent']).assertEqual(10);
      expect(data['headlineColor']).assertEqual('#F2A33C');
      expect(data['row1']).assertEqual('来源A｜5h 10% 周 80%');
      expect(data['balanceText']).assertEqual('来源B CNY 128.45');
    });

    it('empty_snapshot_uses_placeholder', 0, () => {
      const snapshot: DashboardSnapshot = { providers: [], refreshedAt: 0 };
      const data = buildBindingData(snapshot);
      expect(data['headlineLabel']).assertEqual('暂无可用数据');
      expect(data['headlineValue']).assertEqual('—');
    });

    it('error_providers_are_skipped', 0, () => {
      const snapshot: DashboardSnapshot = {
        providers: [{
          providerId: 'x',
          name: '坏来源',
          kind: SourceKind.SUBSCRIPTION,
          state: FetchState.ERROR,
          windows: [{ kind: WindowKind.H5, mode: QuotaMode.RATIO, usedRatio: 0.99 }],
          balances: [],
          extra: {},
          fetchedAt: 1
        }],
        refreshedAt: 1
      };
      const data = buildBindingData(snapshot);
      expect(data['headlineLabel']).assertEqual('暂无可用数据');
      expect(data['rowCount']).assertEqual(0);
    });
  });
}
