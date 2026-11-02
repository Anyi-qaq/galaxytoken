import { mediaquery } from '@kit.ArkUI';
import { Log } from './Logger';

/**
 * 断点与布局参数。
 *
 * 按 HarmonyOS 官方断点：
 * - sm  [320, 600)  手机竖屏
 * - md  [600, 840)  手机横屏 / 小折叠展开 / 小平板竖屏
 * - lg  [840, 1440) 平板
 * - xl  [1440, ∞)   2in1 / 大屏
 *
 * 决策只看可用宽度，不看设备类型 —— 手机上分屏、平板竖屏都能落到正确档位。
 */
export enum SizeClass {
  SM = 'sm',
  MD = 'md',
  LG = 'lg',
  XL = 'xl'
}

/** 某个断点下的布局参数。 */
export interface LayoutMetrics {
  sizeClass: SizeClass;
  /** 卡片列表列数。 */
  columns: number;
  /** 页面左右留白（vp）。 */
  pagePadding: number;
  /** 卡片间距（vp）。 */
  cardGap: number;
  /** 内容最大宽度；0 表示不限制。 */
  maxContentWidth: number;
  /** 是否使用侧边导航（宽屏）。 */
  sideNav: boolean;
  /** 标题字号。 */
  titleSize: number;
}

/** 由断点推导布局参数。 */
export function metricsFor(sizeClass: SizeClass): LayoutMetrics {
  switch (sizeClass) {
    case SizeClass.MD:
      return {
        sizeClass: sizeClass,
        columns: 2,
        pagePadding: 20,
        cardGap: 14,
        maxContentWidth: 0,
        sideNav: false,
        titleSize: 24
      };
    case SizeClass.LG:
      return {
        sizeClass: sizeClass,
        columns: 2,
        pagePadding: 28,
        cardGap: 16,
        maxContentWidth: 1100,
        sideNav: true,
        titleSize: 26
      };
    case SizeClass.XL:
      return {
        sizeClass: sizeClass,
        columns: 3,
        pagePadding: 36,
        cardGap: 18,
        maxContentWidth: 1400,
        sideNav: true,
        titleSize: 28
      };
    default:
      return {
        sizeClass: SizeClass.SM,
        columns: 1,
        pagePadding: 16,
        cardGap: 12,
        maxContentWidth: 0,
        sideNav: false,
        titleSize: 22
      };
  }
}

/** 由宽度推导断点。 */
export function sizeClassOf(widthVp: number): SizeClass {
  if (widthVp >= 1440) {
    return SizeClass.XL;
  }
  if (widthVp >= 840) {
    return SizeClass.LG;
  }
  if (widthVp >= 600) {
    return SizeClass.MD;
  }
  return SizeClass.SM;
}

/**
 * 监听窗口宽度变化，返回取消订阅函数。
 *
 * 不依赖 @State，避免在 build 里做副作用；调用方拿到回调后自己 setState。
 */
export function watchSizeClass(uiContext: UIContext,
  onChange: (sizeClass: SizeClass, widthVp: number) => void): () => void {
  const listeners: mediaquery.MediaQueryListener[] = [];
  const query = uiContext.getMediaQuery();
  // 三个门槛各注册一个监听；回调里用最新的 matches 拼出断点。
  const conditions: string[] = ['(width >= 600vp)', '(width >= 840vp)', '(width >= 1440vp)'];
  const matches: boolean[] = [false, false, false];
  const evaluate = (): void => {
    let level = 0;
    if (matches[0]) {
      level = 1;
    }
    if (matches[1]) {
      level = 2;
    }
    if (matches[2]) {
      level = 3;
    }
    const sizeClass = level >= 3 ? SizeClass.XL
      : (level === 2 ? SizeClass.LG : (level === 1 ? SizeClass.MD : SizeClass.SM));
    onChange(sizeClass, level >= 3 ? 1440 : (level === 2 ? 840 : (level === 1 ? 600 : 360)));
  };
  for (let i = 0; i < conditions.length; i++) {
    const index = i;
    try {
      const listener = query.matchMediaSync(conditions[index]);
      matches[index] = listener.matches;
      listener.on('change', (result: mediaquery.MediaQueryResult) => {
        matches[index] = result.matches;
        evaluate();
      });
      listeners.push(listener);
    } catch (error) {
      Log.w(`media query failed: ${conditions[index]}`);
    }
  }
  evaluate();
  return () => {
    for (const listener of listeners) {
      try {
        listener.off('change');
      } catch (error) {
        Log.w('media query off failed');
      }
    }
  };
}

/**
 * 是否属于宽屏（平板及以上）。
 *
 * 注意：宽屏的多列布局会让单卡变窄，所以窗口仍然纵向排列。
 * 这个判定只用于决定是否显示侧边导航等整体结构差异。
 */
export function isWideCard(metrics: LayoutMetrics): boolean {
  return metrics.sizeClass === SizeClass.LG || metrics.sizeClass === SizeClass.XL;
}

/** 该断点下是否需要限制内容宽度并居中。 */
export function shouldCenter(metrics: LayoutMetrics): boolean {
  return metrics.maxContentWidth > 0;
}
