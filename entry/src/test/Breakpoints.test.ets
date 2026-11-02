import { describe, expect, it } from '@ohos/hypium';
import {
  LayoutMetrics,
  SizeClass,
  isWideCard,
  metricsFor,
  shouldCenter,
  sizeClassOf
} from '../main/ets/common/Breakpoints';

/**
 * 断点与布局参数测试。
 *
 * 覆盖手机竖屏、手机横屏 / 小折叠、平板、2in1 四档，
 * 以及极端宽度下不会出现 0 列或负留白。
 */
export default function breakpointsTest() {
  describe('sizeClassOf', () => {
    it('maps_widths_to_breakpoints', 0, () => {
      // 手机竖屏
      expect(sizeClassOf(320)).assertEqual(SizeClass.SM);
      expect(sizeClassOf(360)).assertEqual(SizeClass.SM);
      expect(sizeClassOf(599)).assertEqual(SizeClass.SM);
      // 手机横屏 / 小折叠展开 / 小平板竖屏
      expect(sizeClassOf(600)).assertEqual(SizeClass.MD);
      expect(sizeClassOf(720)).assertEqual(SizeClass.MD);
      expect(sizeClassOf(839)).assertEqual(SizeClass.MD);
      // 平板
      expect(sizeClassOf(840)).assertEqual(SizeClass.LG);
      expect(sizeClassOf(1280)).assertEqual(SizeClass.LG);
      expect(sizeClassOf(1439)).assertEqual(SizeClass.LG);
      // 2in1 / 大屏
      expect(sizeClassOf(1440)).assertEqual(SizeClass.XL);
      expect(sizeClassOf(2560)).assertEqual(SizeClass.XL);
    });

    it('handles_degenerate_widths', 0, () => {
      expect(sizeClassOf(0)).assertEqual(SizeClass.SM);
      expect(sizeClassOf(-100)).assertEqual(SizeClass.SM);
    });
  });

  describe('metricsFor', () => {
    it('sm_is_single_column_without_side_nav', 0, () => {
      const metrics = metricsFor(SizeClass.SM);
      expect(metrics.columns).assertEqual(1);
      expect(metrics.sideNav).assertFalse();
      expect(metrics.maxContentWidth).assertEqual(0);
      expect(metrics.pagePadding).assertEqual(16);
    });

    it('md_is_two_columns_without_side_nav', 0, () => {
      const metrics = metricsFor(SizeClass.MD);
      expect(metrics.columns).assertEqual(2);
      expect(metrics.sideNav).assertFalse();
    });

    it('lg_is_two_columns_with_side_nav_and_max_width', 0, () => {
      const metrics = metricsFor(SizeClass.LG);
      expect(metrics.columns).assertEqual(2);
      expect(metrics.sideNav).assertTrue();
      expect(metrics.maxContentWidth).assertEqual(1100);
    });

    it('xl_is_three_columns_with_wider_max_width', 0, () => {
      const metrics = metricsFor(SizeClass.XL);
      expect(metrics.columns).assertEqual(3);
      expect(metrics.sideNav).assertTrue();
      expect(metrics.maxContentWidth).assertEqual(1400);
    });

    it('all_breakpoints_are_usable', 0, () => {
      const classes: SizeClass[] = [SizeClass.SM, SizeClass.MD, SizeClass.LG, SizeClass.XL];
      for (const sizeClass of classes) {
        const metrics: LayoutMetrics = metricsFor(sizeClass);
        expect(metrics.columns >= 1).assertTrue();
        expect(metrics.pagePadding > 0).assertTrue();
        expect(metrics.cardGap > 0).assertTrue();
        expect(metrics.titleSize > 0).assertTrue();
      }
    });
  });

  describe('layoutHelpers', () => {
    it('isWideCard_is_true_only_for_tablet_and_desktop', 0, () => {
      expect(isWideCard(metricsFor(SizeClass.SM))).assertFalse();
      expect(isWideCard(metricsFor(SizeClass.MD))).assertFalse();
      expect(isWideCard(metricsFor(SizeClass.LG))).assertTrue();
      expect(isWideCard(metricsFor(SizeClass.XL))).assertTrue();
    });

    it('shouldCenter_matches_max_width', 0, () => {
      expect(shouldCenter(metricsFor(SizeClass.SM))).assertFalse();
      expect(shouldCenter(metricsFor(SizeClass.LG))).assertTrue();
      expect(shouldCenter(metricsFor(SizeClass.XL))).assertTrue();
    });
  });
}
