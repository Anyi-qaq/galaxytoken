import { QuotaWindow, WindowKind, clampRatio, remainingRatio, windowLabel } from '../model/Types';

/** 格式化工具与小组件共用。 */

/** 用剩余比例生成一句人话描述。 */
export function describeRemaining(window: QuotaWindow): string {
  const ratio = remainingRatio(window);
  if (ratio === undefined) {
    return window.unavailableReason !== undefined ? window.unavailableReason : '无数据';
  }
  return `剩余 ${Math.round(ratio * 100)}%`;
}

/** 倒计时文本：2小时44分 / 4天3小时 / 已重置。 */
export function countdownText(resetAt: number | undefined, now: number): string {
  if (resetAt === undefined) {
    return '';
  }
  const delta = resetAt - now;
  if (delta <= 0) {
    return '即将重置';
  }
  const minutes = Math.floor(delta / 60000);
  const days = Math.floor(minutes / (60 * 24));
  const hours = Math.floor((minutes - days * 60 * 24) / 60);
  const mins = minutes % 60;
  if (days > 0) {
    return `${days}天${hours}小时`;
  }
  if (hours > 0) {
    return `${hours}小时${mins}分`;
  }
  return `${mins}分`;
}

/** 绝对余量文本：820 / 1000 prompt。 */
export function absoluteText(window: QuotaWindow, decimals: number): string {
  if (window.remaining === undefined) {
    return '';
  }
  const remaining = formatNumber(window.remaining, decimals);
  if (window.limit === undefined || window.limit <= 0) {
    return `${remaining} ${window.unit ?? ''}`.trim();
  }
  return `${remaining} / ${formatNumber(window.limit, decimals)} ${window.unit ?? ''}`.trim();
}

/** 金额文本：¥128.45 / $3.20。 */
export function moneyText(amount: number, currency: string, decimals: number): string {
  const symbol = currencySymbol(currency);
  return `${symbol}${formatNumber(amount, decimals)}`;
}

function currencySymbol(currency: string): string {
  switch (currency.toUpperCase()) {
    case 'CNY':
      return '¥';
    case 'USD':
      return '$';
    case 'EUR':
      return '€';
    default:
      return `${currency} `;
  }
}

/** 保留指定位数，去掉多余的 0。 */
export function formatNumber(value: number, decimals: number): string {
  if (!Number.isFinite(value)) {
    return '0';
  }
  const fixed = value.toFixed(decimals);
  if (fixed.indexOf('.') < 0) {
    return fixed;
  }
  let end = fixed.length;
  while (end > 0 && fixed.charAt(end - 1) === '0') {
    end -= 1;
  }
  if (end > 0 && fixed.charAt(end - 1) === '.') {
    end -= 1;
  }
  return fixed.substring(0, end);
}

/** 进度条颜色：紧张度分档。 */
export function progressColor(window: QuotaWindow): string {
  const ratio = remainingRatio(window);
  if (ratio === undefined) {
    return '#4A4A4A';
  }
  if (ratio <= 0.1) {
    return '#F0523A';
  }
  if (ratio <= 0.3) {
    return '#F2A33C';
  }
  return '#3BA55D';
}

/** 窗口徽标文字。 */
export function windowBadge(kind: WindowKind): string {
  return windowLabel(kind);
}

/** 相对时间：刚刚 / 3 分钟前 / 2 小时前。 */
export function relativeTime(timestamp: number, now: number): string {
  if (timestamp <= 0) {
    return '从未更新';
  }
  const delta = now - timestamp;
  if (delta < 60000) {
    return '刚刚更新';
  }
  const minutes = Math.floor(delta / 60000);
  if (minutes < 60) {
    return `${minutes} 分钟前`;
  }
  const hours = Math.floor(minutes / 60);
  if (hours < 24) {
    return `${hours} 小时前`;
  }
  return `${Math.floor(hours / 24)} 天前`;
}

/** 把 0..1 比例转成 Progress 的 value（0..100）。 */
export function toProgressValue(window: QuotaWindow): number {
  const ratio = remainingRatio(window);
  if (ratio === undefined) {
    return 0;
  }
  return clampRatio(ratio) * 100;
}

/** 错误分类的中文文案。 */
export function errorTitle(message: string): string {
  return message;
}
