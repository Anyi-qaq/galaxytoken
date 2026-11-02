import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { ErrorKind, SourceError } from '../model/Types';
import { asObject, truncate } from '../model/JsonValue';
import { BROWSER_UA, HTTP_TIMEOUT_MS, MAX_BODY_CHARS, RAW_SNIPPET_CHARS } from '../common/Constants';
import { Log, redact } from '../common/Logger';

/** 一次 HTTP 请求的描述。 */
export interface HttpCall {
  url: string;
  method: string;
  headers: Record<string, string>;
  body?: string;
  /** 覆盖默认超时。 */
  timeoutMs?: number;
}

/** 一次 HTTP 请求的结果。 */
export interface HttpResult {
  status: number;
  body: string;
  /** 解析后的 JSON 根；非 JSON 或解析失败时为 undefined。 */
  json: Object | undefined;
  headers: Record<string, string>;
}

/** 统一的来源异常，携带可展示的结构化错误。 */
export class FetchError extends Error {
  readonly detail: SourceError;

  constructor(detail: SourceError) {
    super(detail.message);
    this.detail = detail;
  }
}

/** 常用请求头构造。 */
export class Headers {
  static bearer(token: string): Record<string, string> {
    return { 'Authorization': `Bearer ${token}` };
  }

  static rawAuth(token: string): Record<string, string> {
    return { 'Authorization': token };
  }

  static json(): Record<string, string> {
    return { 'Content-Type': 'application/json', 'Accept': 'application/json' };
  }

  static browser(origin?: string, referer?: string): Record<string, string> {
    const headers: Record<string, string> = {
      'User-Agent': BROWSER_UA,
      'Accept': 'application/json, text/plain, */*',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8'
    };
    if (origin !== undefined) {
      headers['Origin'] = origin;
    }
    if (referer !== undefined) {
      headers['Referer'] = referer;
    }
    return headers;
  }

  /** 合并多组头，后面的覆盖前面的。 */
  static merge(...groups: Record<string, string>[]): Record<string, string> {
    const out: Record<string, string> = {};
    for (const group of groups) {
      const keys = Object.keys(group);
      for (const key of keys) {
        out[key] = group[key];
      }
    }
    return out;
  }
}

/** HTTP 客户端：唯一发起外网请求的地方。 */
export class HttpClient {
  /** 发送请求；非 2xx 抛 FetchError。 */
  static async send(call: HttpCall, secrets: string[]): Promise<HttpResult> {
    const result = await HttpClient.exec(call, secrets);
    if (result.status >= 200 && result.status < 300) {
      return result;
    }
    throw buildHttpError(result, secrets);
  }

  /**
   * 发送请求但允许非 2xx；调用方自行判断。
   * 用于需要区分 403/200 语义差异的来源（如 Google disabled 桶、CommandCode 无订阅）。
   */
  static async exec(call: HttpCall, secrets: string[]): Promise<HttpResult> {
    const request = http.createHttp();
    const timeout = call.timeoutMs === undefined ? HTTP_TIMEOUT_MS : call.timeoutMs;
    const options: http.HttpRequestOptions = {
      method: methodOf(call.method),
      header: call.headers,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: timeout,
      readTimeout: timeout,
      usingCache: false
    };
    if (call.body !== undefined && call.body !== '') {
      options.extraData = call.body;
    }
    try {
      const response = await request.request(call.url, options);
      const status = response.responseCode;
      const body = bodyToString(response.result);
      const headers = normalizeHeaders(response.header);
      const json = tryParseJson(body);
      if (body.length > MAX_BODY_CHARS) {
        throw new FetchError({
          kind: ErrorKind.PARSE,
          httpStatus: status,
          message: `响应体过大（${body.length} 字符），已拒绝解析`
        });
      }
      Log.d(`HTTP ${call.method} ${sanitizeUrl(call.url)} -> ${status}`);
      return { status: status, body: body, json: json, headers: headers };
    } catch (error) {
      if (error instanceof FetchError) {
        throw error;
      }
      throw transportError(error, secrets);
    } finally {
      request.destroy();
    }
  }

  /** GET 便捷方法。 */
  static async get(url: string, headers: Record<string, string>, secrets: string[]): Promise<HttpResult> {
    return HttpClient.send({ url: url, method: 'GET', headers: headers }, secrets);
  }

  /** POST JSON 便捷方法。 */
  static async postJson(url: string, headers: Record<string, string>, body: string,
    secrets: string[]): Promise<HttpResult> {
    return HttpClient.send({
      url: url,
      method: 'POST',
      headers: Headers.merge(Headers.json(), headers),
      body: body
    }, secrets);
  }
}

/** 把网络层异常映射为结构化错误。 */
function transportError(error: Object, secrets: string[]): FetchError {
  const be = error as BusinessError;
  const code: number = be !== undefined && be.code !== undefined ? be.code : 0;
  const rawMessage: string = be !== undefined && be.message !== undefined ? be.message : `${error}`;
  const message = redact(rawMessage, secrets);
  let kind: ErrorKind = ErrorKind.UNKNOWN;
  if (code === 2300007 || code === 2300028 || code === 2300050) {
    kind = ErrorKind.TIMEOUT;
  } else if (code >= 2300001 && code <= 2300999) {
    kind = ErrorKind.NETWORK;
  }
  if (message.indexOf('timeout') >= 0 || message.indexOf('Timeout') >= 0) {
    kind = ErrorKind.TIMEOUT;
  }
  Log.w(`transport error code=${code} kind=${kind} msg=${truncate(message, 200)}`);
  return new FetchError({
    kind: kind,
    httpStatus: 0,
    message: kind === ErrorKind.TIMEOUT ? '请求超时' : '网络不可用',
    rawSnippet: message
  });
}

/** 由 HTTP 状态码构造错误。 */
function buildHttpError(result: HttpResult, secrets: string[]): FetchError {
  const snippet = redact(truncate(result.body, RAW_SNIPPET_CHARS), secrets);
  const upstreamMessage = extractUpstreamMessage(result.json);
  let kind: ErrorKind = ErrorKind.UNKNOWN;
  let message = `HTTP ${result.status}`;
  switch (result.status) {
    case 400:
      kind = ErrorKind.PARSE;
      message = upstreamMessage !== undefined ? upstreamMessage : '请求参数被拒绝（HTTP 400）';
      break;
    case 401:
      kind = ErrorKind.UNAUTHORIZED;
      message = '凭证无效或已过期（HTTP 401）';
      break;
    case 403:
      kind = ErrorKind.FORBIDDEN;
      message = upstreamMessage !== undefined ? upstreamMessage : '权限或订阅不足（HTTP 403）';
      break;
    case 404:
      kind = ErrorKind.NOT_FOUND;
      message = '端点已变更或不存在（HTTP 404）';
      break;
    case 429:
      kind = ErrorKind.RATE_LIMITED;
      message = '触发限流（HTTP 429），请稍后重试';
      break;
    default:
      if (result.status >= 500) {
        kind = ErrorKind.NETWORK;
        message = `服务端错误（HTTP ${result.status}）`;
      }
      break;
  }
  return new FetchError({
    kind: kind,
    httpStatus: result.status,
    message: message,
    rawSnippet: snippet
  });
}

/** 从常见错误信封里提取上游 message。 */
function extractUpstreamMessage(json: Object | undefined): string | undefined {
  const root = asObject(json);
  if (root === undefined) {
    return undefined;
  }
  const errorObj = asObject(root['error']);
  if (errorObj !== undefined) {
    const message = errorObj['message'];
    if (typeof message === 'string' && message !== '') {
      return message;
    }
  }
  const message = root['message'];
  if (typeof message === 'string' && message !== '') {
    return message;
  }
  const msg = root['msg'];
  if (typeof msg === 'string' && msg !== '') {
    return msg;
  }
  return undefined;
}

function methodOf(method: string): http.RequestMethod {
  switch (method.toUpperCase()) {
    case 'POST':
      return http.RequestMethod.POST;
    case 'PUT':
      return http.RequestMethod.PUT;
    case 'PATCH':
      return http.RequestMethod.PATCH;
    case 'DELETE':
      return http.RequestMethod.DELETE;
    default:
      return http.RequestMethod.GET;
  }
}

function bodyToString(result: string | Object | ArrayBuffer): string {
  if (typeof result === 'string') {
    return result;
  }
  if (result === undefined || result === null) {
    return '';
  }
  if (result instanceof ArrayBuffer) {
    return arrayBufferToString(result);
  }
  return JSON.stringify(result);
}

function arrayBufferToString(buffer: ArrayBuffer): string {
  const decoder = util.TextDecoder.create('utf-8');
  return decoder.decodeToString(new Uint8Array(buffer));
}

function normalizeHeaders(raw: Object | undefined): Record<string, string> {
  const out: Record<string, string> = {};
  const rec = asObject(raw);
  if (rec === undefined) {
    return out;
  }
  const keys = Object.keys(rec);
  for (const key of keys) {
    const value = rec[key];
    out[key.toLowerCase()] = typeof value === 'string' ? value : `${value}`;
  }
  return out;
}

/** 安全解析 JSON；失败返回 undefined 而不是抛出。 */
export function tryParseJson(body: string): Object | undefined {
  const trimmed = body.trim();
  if (trimmed === '') {
    return undefined;
  }
  try {
    return JSON.parse(trimmed) as Object;
  } catch (error) {
    Log.d('JSON parse failed');
    return undefined;
  }
}

/** 日志中隐藏查询串里的敏感值。 */
function sanitizeUrl(url: string): string {
  const index = url.indexOf('?');
  if (index < 0) {
    return url;
  }
  return `${url.substring(0, index)}?…`;
}
