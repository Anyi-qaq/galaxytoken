import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x9527;
const TAG: string = 'GalaxyToken';

/** 日志封装：永不打印凭据本身，只打印长度和指纹。 */
export class Log {
  static d(message: string): void {
    hilog.debug(DOMAIN, TAG, '%{public}s', message);
  }

  static i(message: string): void {
    hilog.info(DOMAIN, TAG, '%{public}s', message);
  }

  static w(message: string): void {
    hilog.warn(DOMAIN, TAG, '%{public}s', message);
  }

  static e(message: string): void {
    hilog.error(DOMAIN, TAG, '%{public}s', message);
  }

  /** 打印凭据的脱敏描述，绝不输出原文。 */
  static secret(tag: string, value: string): void {
    hilog.info(DOMAIN, TAG, '%{public}s', `${tag}: len=${value.length}`);
  }
}

/** 对可能含凭据的文本做脱敏，用于错误原文摘要。 */
export function redact(text: string, secrets: string[]): string {
  let out = text;
  for (const secret of secrets) {
    if (secret === undefined || secret === null) {
      continue;
    }
    const trimmed = secret.trim();
    if (trimmed.length < 6) {
      continue;
    }
    out = replaceAll(out, trimmed, mask(trimmed));
  }
  out = replaceAll(out, 'Bearer ', 'Bearer ***');
  return out;
}

function mask(secret: string): string {
  if (secret.length <= 8) {
    return '***';
  }
  return `${secret.substring(0, 4)}***${secret.substring(secret.length - 2)}`;
}

function replaceAll(haystack: string, needle: string, replacement: string): string {
  if (needle === '') {
    return haystack;
  }
  const parts: string[] = haystack.split(needle);
  return parts.join(replacement);
}
