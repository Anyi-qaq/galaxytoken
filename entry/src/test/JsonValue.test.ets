import { describe, expect, it } from '@ohos/hypium';
import { asArray, asObject, clamp01, isEmptyObject, pickArray, pickBoolean, pickNumber, pickPath, pickString, toEpochMs, toNum, toStr, truncate } from '../main/ets/model/JsonValue';
import {
  clampRatio,
  FetchState,
  normalizeWindows,
  ProviderSnapshot,
  QuotaMode,
  QuotaWindow,
  remainingRatio,
  setSupportLookup,
  SourceKind,
  WindowKind,
  WindowSupport,
  windowLabel,
  windowRank
} from '../main/ets/model/Types';

/** JSON 路径与数值归一化的纯函数测试。 */
export default function jsonValueTest() {
  describe('jsonValue', () => {
    it('pickPath_reads_nested_objects_and_arrays', 0, () => {
      const root = JSON.parse('{"data":{"list":[{"a":1},{"a":2}],"name":"x"}}') as Object;
      expect(pickNumber(root, 'data.list[1].a')).assertEqual(2);
      expect(pickNumber(root, 'data.list[0].a')).assertEqual(1);
      expect(pickString(root, 'data.name')).assertEqual('x');
    });

    it('pickPath_returns_undefined_out_of_range', 0, () => {
      const root = JSON.parse('{"data":{"list":[1,2]}}') as Object;
      expect(pickPath(root, 'data.list[5]')).assertUndefined();
      expect(pickPath(root, 'data.missing.deep')).assertUndefined();
      expect(pickPath(root, 'data.list[-1]')).assertUndefined();
    });

    it('pickPath_handles_empty_path', 0, () => {
      const root = JSON.parse('{"a":1}') as Object;
      expect(pickPath(root, '')).assertUndefined();
      expect(pickPath(root, '   ')).assertUndefined();
    });

    it('toNum_accepts_string_numbers_and_zero', 0, () => {
      expect(toNum('128.45')).assertEqual(128.45);
      expect(toNum('1,280.00')).assertEqual(1280);
      expect(toNum(' 42 ')).assertEqual(42);
      expect(toNum('0')).assertEqual(0);
      expect(toNum(0)).assertEqual(0);
      expect(toNum('-3.5')).assertEqual(-3.5);
      expect(toNum('')).assertUndefined();
      expect(toNum('abc')).assertUndefined();
      expect(toNum(undefined)).assertUndefined();
      expect(toNum(null)).assertUndefined();
    });

    it('toStr_converts_scalars', 0, () => {
      expect(toStr('a')).assertEqual('a');
      expect(toStr(12)).assertEqual('12');
      expect(toStr(true)).assertEqual('true');
      expect(toStr(null)).assertUndefined();
      expect(toStr(undefined)).assertUndefined();
    });

    it('toEpochMs_normalizes_seconds_ms_and_iso', 0, () => {
      // 秒 -> 毫秒
      expect(toEpochMs(1700000000)).assertEqual(1700000000000);
      // 毫秒保持
      expect(toEpochMs(1700000000000)).assertEqual(1700000000000);
      // 字符串秒
      expect(toEpochMs('1700000000')).assertEqual(1700000000000);
      // ISO 8601
      expect(toEpochMs('2023-11-14T22:13:20Z')).assertEqual(1700000000000);
      // 非法值
      expect(toEpochMs(0)).assertUndefined();
      expect(toEpochMs('')).assertUndefined();
      expect(toEpochMs('not-a-date')).assertUndefined();
      expect(toEpochMs(undefined)).assertUndefined();
    });

    it('clamp01_bounds_values', 0, () => {
      expect(clamp01(-1)).assertEqual(0);
      expect(clamp01(0.5)).assertEqual(0.5);
      expect(clamp01(2)).assertEqual(1);
      expect(clamp01(Number.NaN)).assertEqual(0);
    });

    it('truncate_keeps_short_and_cuts_long', 0, () => {
      expect(truncate('abc', 10)).assertEqual('abc');
      expect(truncate('abcdef', 3).startsWith('abc')).assertTrue();
    });

    it('isEmptyObject_detects_empty', 0, () => {
      expect(isEmptyObject({})).assertTrue();
      expect(isEmptyObject(undefined)).assertTrue();
      const rec: Record<string, Object> = {};
      rec['a'] = 1;
      expect(isEmptyObject(rec)).assertFalse();
    });

    it('asObject_and_asArray_reject_wrong_types', 0, () => {
      expect(asObject('x')).assertUndefined();
      expect(asObject(JSON.parse('{"a":1}') as Object) !== undefined).assertTrue();
      expect(asArray('x')).assertUndefined();
      expect(asArray(JSON.parse('[1,2]') as Object)?.length).assertEqual(2);
    });

    it('type_guards_work', 0, () => {
      const root = JSON.parse('{"s":"v","b":true,"arr":[1]}') as Object;
      expect(pickString(root, 's')).assertEqual('v');
      expect(pickBoolean(root, 'b')).assertTrue();
      expect(pickArray(root, 'arr')?.length).assertEqual(1);
    });
  });

  describe('windowModel', () => {
    it('windowLabel_and_rank_are_stable', 0, () => {
      expect(windowLabel(WindowKind.H5)).assertEqual('5 小时');
      expect(windowLabel(WindowKind.WEEK)).assertEqual('本周');
      expect(windowLabel(WindowKind.MONTH)).assertEqual('本月');
      expect(windowRank(WindowKind.H5)).assertEqual(0);
      expect(windowRank(WindowKind.WEEK)).assertEqual(1);
      expect(windowRank(WindowKind.MONTH)).assertEqual(2);
    });

    it('clampRatio_clamps_out_of_range', 0, () => {
      expect(clampRatio(-0.5)).assertEqual(0);
      expect(clampRatio(0.42)).assertEqual(0.42);
      expect(clampRatio(1.9)).assertEqual(1);
      expect(clampRatio(Number.NaN)).assertEqual(0);
    });

    it('remainingRatio_inverts_used_ratio', 0, () => {
      const window: QuotaWindow = { kind: WindowKind.H5, mode: QuotaMode.RATIO, usedRatio: 0.75 };
      expect(remainingRatio(window)).assertEqual(0.25);
    });

    it('remainingRatio_computes_from_absolute', 0, () => {
      const window: QuotaWindow = {
        kind: WindowKind.WEEK,
        mode: QuotaMode.ABSOLUTE,
        remaining: 250,
        limit: 1000,
        unit: 'prompt'
      };
      expect(remainingRatio(window)).assertEqual(0.25);
    });

    it('remainingRatio_is_undefined_when_incomplete', 0, () => {
      const noData: QuotaWindow = { kind: WindowKind.H5, mode: QuotaMode.RATIO };
      expect(remainingRatio(noData)).assertUndefined();
      const zeroLimit: QuotaWindow = {
        kind: WindowKind.MONTH,
        mode: QuotaMode.ABSOLUTE,
        remaining: 5,
        limit: 0
      };
      expect(remainingRatio(zeroLimit)).assertUndefined();
    });

    it('normalizeWindows_fills_missing_with_reason', 0, () => {
      const support: WindowSupport = { h5: true, week: true, month: false };
      setSupportLookup((_id: string): WindowSupport => support);
      const snapshot: ProviderSnapshot = {
        providerId: 'test',
        name: 'test',
        kind: SourceKind.SUBSCRIPTION,
        state: FetchState.OK,
        windows: [{ kind: WindowKind.H5, mode: QuotaMode.RATIO, usedRatio: 0.2 }],
        balances: [],
        extra: {},
        fetchedAt: 0
      };
      const windows = normalizeWindows(snapshot);
      expect(windows.length).assertEqual(3);
      expect(windows[0].kind).assertEqual(WindowKind.H5);
      expect(windows[1].unavailableReason !== undefined).assertTrue();
      expect(windows[2].unavailableReason).assertEqual('该来源不提供此窗口');
    });
  });
}
