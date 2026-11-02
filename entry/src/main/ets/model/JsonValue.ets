/**
 * JSON 读取工具。
 *
 * ArkTS 不允许用 `any`，所以所有解析都从这里走：先取 `Object`，再逐层收窄。
 * 这些函数全部是纯函数，可直接单测。
 */

enum SegmentKind {
  KEY = 'key',
  INDEX = 'index'
}

interface PathSegment {
  kind: SegmentKind;
  key: string;
  index: number;
}

/** 把 `a.b[2].c` 拆成段。非法语法整体判为不可解析。 */
function splitPath(path: string): PathSegment[] {
  const segments: PathSegment[] = [];
  let buffer = '';
  let i = 0;
  while (i < path.length) {
    const ch = path.charAt(i);
    if (ch === '.') {
      if (buffer !== '') {
        segments.push({ kind: SegmentKind.KEY, key: buffer, index: -1 });
        buffer = '';
      }
      i += 1;
      continue;
    }
    if (ch === '[') {
      if (buffer !== '') {
        segments.push({ kind: SegmentKind.KEY, key: buffer, index: -1 });
        buffer = '';
      }
      const close = path.indexOf(']', i);
      if (close < 0) {
        return [];
      }
      const inner = path.substring(i + 1, close).trim();
      const parsed = Number(inner);
      if (!Number.isInteger(parsed) || parsed < 0) {
        return [];
      }
      segments.push({ kind: SegmentKind.INDEX, key: '', index: parsed });
      i = close + 1;
      continue;
    }
    buffer += ch;
    i += 1;
  }
  if (buffer !== '') {
    segments.push({ kind: SegmentKind.KEY, key: buffer, index: -1 });
  }
  return segments;
}

/** 把任意值当作对象读取。 */
export function asObject(value: Object | undefined | null): Record<string, Object> | undefined {
  if (value === undefined || value === null) {
    return undefined;
  }
  if (typeof value !== 'object') {
    return undefined;
  }
  return value as Record<string, Object>;
}

/** 把任意值当作数组读取。 */
export function asArray(value: Object | undefined | null): Object[] | undefined {
  if (value === undefined || value === null) {
    return undefined;
  }
  if (!Array.isArray(value)) {
    return undefined;
  }
  return value as Object[];
}

/** 读取对象上的一个键；键不存在或不是对象时返回 undefined。 */
export function pick(obj: Object | undefined | null, key: string): Object | undefined {
  const rec = asObject(obj);
  if (rec === undefined) {
    return undefined;
  }
  return rec[key];
}

/** 读取嵌套路径，支持 `a.b[2].c` 语法。任意一段缺失即返回 undefined。 */
export function pickPath(root: Object | undefined | null, path: string): Object | undefined {
  if (root === undefined || root === null) {
    return undefined;
  }
  const trimmed = path.trim();
  if (trimmed === '') {
    return undefined;
  }
  let current: Object | undefined = root;
  const segments: PathSegment[] = splitPath(trimmed);
  for (const segment of segments) {
    if (current === undefined) {
      return undefined;
    }
    if (segment.kind === SegmentKind.INDEX) {
      const arr = asArray(current);
      if (arr === undefined) {
        return undefined;
      }
      if (segment.index < 0 || segment.index >= arr.length) {
        return undefined;
      }
      current = arr[segment.index];
    } else {
      current = pick(current, segment.key);
    }
  }
  return current;
}

/** 按候选路径列表依次尝试，返回第一个非空值。 */
export function pickFirstPath(root: Object | undefined | null, paths: string[]): Object | undefined {
  for (const path of paths) {
    const hit = pickPath(root, path);
    if (hit !== undefined && hit !== null) {
      return hit;
    }
  }
  return undefined;
}

/** 读取字符串；数字会被转成字符串，其他类型返回 undefined。 */
export function pickString(root: Object | undefined | null, path: string): string | undefined {
  return toStr(pickPath(root, path));
}

/** 读取数字；字符串数字会被解析。 */
export function pickNumber(root: Object | undefined | null, path: string): number | undefined {
  return toNum(pickPath(root, path));
}

/** 读取布尔。 */
export function pickBoolean(root: Object | undefined | null, path: string): boolean | undefined {
  const v = pickPath(root, path);
  if (typeof v === 'boolean') {
    return v;
  }
  return undefined;
}

/** 读取数组。 */
export function pickArray(root: Object | undefined | null, path: string): Object[] | undefined {
  return asArray(pickPath(root, path));
}

/** 把任意值转成字符串。 */
export function toStr(value: Object | undefined | null): string | undefined {
  if (value === undefined || value === null) {
    return undefined;
  }
  if (typeof value === 'string') {
    return value;
  }
  if (typeof value === 'number') {
    return `${value}`;
  }
  if (typeof value === 'boolean') {
    return value ? 'true' : 'false';
  }
  return undefined;
}

/** 把任意值转成数字；支持千分位与空白，0 是合法值不会当成缺失。 */
export function toNum(value: Object | undefined | null): number | undefined {
  if (value === undefined || value === null) {
    return undefined;
  }
  if (typeof value === 'number') {
    return Number.isFinite(value) ? value : undefined;
  }
  if (typeof value === 'string') {
    const cleaned = value.trim().replace(/,/g, '').replace(/\s/g, '');
    if (cleaned === '') {
      return undefined;
    }
    const parsed = Number(cleaned);
    return Number.isFinite(parsed) ? parsed : undefined;
  }
  if (typeof value === 'boolean') {
    return value ? 1 : 0;
  }
  return undefined;
}

/** 时间值归一为 epoch 毫秒。支持 epoch 秒/毫秒与 ISO 8601 字符串。 */
export function toEpochMs(value: Object | undefined | null): number | undefined {
  if (value === undefined || value === null) {
    return undefined;
  }
  if (typeof value === 'number') {
    return normalizeEpochNumber(value);
  }
  if (typeof value === 'string') {
    const trimmed = value.trim();
    if (trimmed === '') {
      return undefined;
    }
    const asNumber = Number(trimmed);
    if (Number.isFinite(asNumber) && /^[+-]?\d+(\.\d+)?$/.test(trimmed)) {
      return normalizeEpochNumber(asNumber);
    }
    const parsed = Date.parse(trimmed);
    return Number.isFinite(parsed) ? parsed : undefined;
  }
  return undefined;
}

/** 小于 1e11 的数值按秒处理（约公元 5138 年之前都成立）。 */
function normalizeEpochNumber(value: number): number | undefined {
  if (!Number.isFinite(value) || value <= 0) {
    return undefined;
  }
  if (value < 1e11) {
    return Math.round(value * 1000);
  }
  return Math.round(value);
}

/** 计算已用比例，兼容 0..1 与 0..100 两种口径（只在适配器明确要求时使用）。 */
export function ratioFromPercent(value: number): number {
  if (!Number.isFinite(value)) {
    return 0;
  }
  const asRatio = value > 1 ? value / 100 : value;
  return clamp01(asRatio);
}

/** 裁剪到 [0,1]。 */
export function clamp01(value: number): number {
  if (!Number.isFinite(value)) {
    return 0;
  }
  if (value < 0) {
    return 0;
  }
  if (value > 1) {
    return 1;
  }
  return value;
}

/** 截断字符串，用于错误原文摘要。 */
export function truncate(text: string, max: number): string {
  if (text.length <= max) {
    return text;
  }
  return `${text.substring(0, max)}…`;
}

/** 对象是否为空（无键）。 */
export function isEmptyObject(rec: Record<string, Object> | undefined): boolean {
  if (rec === undefined) {
    return true;
  }
  return Object.keys(rec).length === 0;
}
