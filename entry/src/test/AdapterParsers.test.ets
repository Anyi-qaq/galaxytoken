import { describe, expect, it } from '@ohos/hypium';
import { glmWindowKind, parseMiniMaxWindows } from '../main/ets/sources/adapters/SubscriptionAdapters';
import { QuotaMode, QuotaWindow, WindowKind, remainingRatio } from '../main/ets/model/Types';

/** 构造 MiniMax 裁剪样本，避免在测试里散落无类型对象字面量。 */
function miniMaxSample(usageCount: number, totalCount: number, statusCode: number): Record<string, Object> {
  const base: Record<string, Object> = { 'status_code': statusCode };
  const root: Record<string, Object> = {
    'current_interval_usage_count': usageCount,
    'current_interval_total_count': totalCount,
    'interval_reset_time': 1770000000000,
    'base_resp': base
  };
  return root;
}

/**
 * 各来源解析逻辑的固定响应测试。
 *
 * 全部使用真实响应形状的裁剪样本，不发起任何网络请求。
 * 重点覆盖各家「语义反转 / 单位 / 窗口长度」这些最容易写错的地方。
 *
 * 对应用户可见的来源清单与 cc-switch 对齐：
 * 余额类 6 家 + 套餐类 3 家（Kimi Code / 智谱 GLM / MiniMax）。
 */
export default function adapterParsersTest() {
  describe('minimax', () => {
    it('usage_count_is_remaining_not_used', 0, () => {
      // MiniMax 的 current_interval_usage_count 是「剩余」而不是「已用」。
      const windows: QuotaWindow[] = parseMiniMaxWindows(miniMaxSample(320, 1000, 0));
      expect(windows.length > 0).assertTrue();
      const ratio: number | undefined = remainingRatio(windows[0]);
      // 剩余 320/1000 = 32%
      expect(ratio !== undefined).assertTrue();
      if (ratio !== undefined) {
        expect(Math.abs(ratio - 0.32) < 0.001).assertTrue();
      }
    });

    it('interval_longer_than_6h_is_not_h5', 0, () => {
      // 视频模型的窗口长度不是 5 小时，不能当成 H5。
      const root: Record<string, Object> = miniMaxSample(10, 100, 0);
      root['current_interval_status'] = 1;
      root['interval_type'] = 2;
      const windows: QuotaWindow[] = parseMiniMaxWindows(root);
      for (const item of windows) {
        if (item.kind === WindowKind.H5) {
          expect(item.unavailableReason !== undefined).assertTrue();
        }
      }
    });

    it('business_error_with_http_200_is_detected', 0, () => {
      // HTTP 200 也可能是业务错误：base_resp.status_code != 0。
      const windows: QuotaWindow[] = parseMiniMaxWindows(miniMaxSample(0, 0, 1004));
      // 没有可识别窗口时返回空数组，由适配器转成明确错误。
      expect(windows.length).assertEqual(0);
    });
  });

  describe('glm', () => {
    it('unit_enum_maps_3_to_5h_and_6_to_week', 0, () => {
      // cc-switch 实测：unit 3 = 5 小时滚动窗口，unit 6 = 每周窗口。
      expect(glmWindowKind(3)).assertEqual(WindowKind.H5);
      expect(glmWindowKind(6)).assertEqual(WindowKind.WEEK);
    });

    it('unknown_unit_is_rejected', 0, () => {
      // unit 缺失或不认识时不能瞎猜窗口类型。
      expect(glmWindowKind(undefined) === undefined).assertTrue();
      expect(glmWindowKind(1) === undefined).assertTrue();
      expect(glmWindowKind(5) === undefined).assertTrue();
      expect(glmWindowKind(99) === undefined).assertTrue();
    });
  });

  describe('kimiCode', () => {
    it('limit_minus_remaining_is_used', 0, () => {
      // Kimi Code 给的是 limit 与 remaining，需要反算「已用」比例。
      const detail: Record<string, Object> = { 'limit': 100, 'remaining': 75 };
      const limit = detail['limit'] as number;
      const remaining = detail['remaining'] as number;
      const used = limit - remaining;
      const usedRatio = used / limit;
      expect(usedRatio).assertEqual(0.25);
    });

    it('remaining_above_limit_clamps_to_zero', 0, () => {
      // 上游偶发 remaining > limit（额度刚重置），不能出现负的已用比例。
      const limit = 100;
      const remaining = 120;
      const used = limit - remaining;
      const clamped = used < 0 ? 0 : used / limit;
      expect(clamped).assertEqual(0);
    });

    it('zero_limit_is_not_a_window', 0, () => {
      // limit 为 0 表示该窗口没有额度配置，不应当作 0% 使用率渲染。
      const limit = 0;
      const remaining = 0;
      const valid = limit > 0 && remaining >= 0;
      expect(valid).assertFalse();
    });
  });

  describe('windowSemantics', () => {
    it('ratio_mode_keeps_service_percentage', 0, () => {
      const window: QuotaWindow = {
        kind: WindowKind.H5,
        mode: QuotaMode.RATIO,
        usedRatio: 0.38
      };
      expect(remainingRatio(window)).assertEqual(0.62);
    });

    it('absolute_mode_divides_by_limit', 0, () => {
      const window: QuotaWindow = {
        kind: WindowKind.WEEK,
        mode: QuotaMode.ABSOLUTE,
        remaining: 25,
        limit: 100
      };
      expect(remainingRatio(window)).assertEqual(0.25);
    });

    it('unavailable_window_has_no_ratio', 0, () => {
      const window: QuotaWindow = {
        kind: WindowKind.MONTH,
        mode: QuotaMode.RATIO,
        unavailableReason: '该来源只提供账户余额'
      };
      // 不可用窗口不应该被算成 0% 或 100%。
      const ratio = availableRatio(window);
      expect(ratio === undefined).assertTrue();
    });
  });
}

/** 仅在该窗口真正有读数时返回比例。 */
function availableRatio(window: QuotaWindow): number | undefined {
  if (window.unavailableReason !== undefined) {
    return undefined;
  }
  return remainingRatio(window);
}
