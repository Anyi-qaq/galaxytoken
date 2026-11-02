import { util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';

/**
 * 阿里云 ACS3-HMAC-SHA256 签名。
 *
 * 规范：
 *   CanonicalRequest =
 *     HTTPMethod + '\n' +
 *     CanonicalURI + '\n' +
 *     CanonicalQueryString + '\n' +
 *     CanonicalHeaders + '\n' +
 *     SignedHeaders + '\n' +
 *     Hex(SHA256(RequestPayload))
 *   StringToSign = 'ACS3-HMAC-SHA256' + '\n' + Hex(SHA256(CanonicalRequest))
 *   Signature    = Hex(HMAC-SHA256(SecretKey, StringToSign))
 *
 * 头部要求：x-acs-date（ISO8601 UTC，去掉毫秒）、x-acs-signature-nonce、
 *           x-acs-content-sha256（请求体哈希）、x-acs-version、host。
 *
 * 注意：这里是纯函数，便于用已知向量单测；不涉及网络。
 */

/** 签名输入。 */
export interface Acs3Request {
  method: string;
  /** 例如 https://modelstudio.cn-beijing.aliyuncs.com */
  endpoint: string;
  /** 例如 /modelstudio/cli/generateAccessToken */
  path: string;
  /** 已排序的查询参数（可为空）。 */
  query: Record<string, string>;
  body: string;
  accessKeyId: string;
  accessKeySecret: string;
  /** 'yyyy-MM-ddTHH:mm:ssZ' */
  dateIso: string;
  nonce: string;
  /** x-acs-version，例如 '2024-01-01'。 */
  version: string;
  /** 额外参与签名的头（不含 x-acs-*，会自动加入）。 */
  extraSignedHeaders: Record<string, string>;
}

/** 签名结果。 */
export interface Acs3Result {
  headers: Record<string, string>;
  signature: string;
  stringToSign: string;
  canonicalRequest: string;
}

/** 计算签名并返回应当附加到请求上的全部头。 */
export async function signAcs3(request: Acs3Request): Promise<Acs3Result> {
  const payloadHash = await sha256Hex(request.body);
  const host = extractHost(request.endpoint);

  const signedHeaderMap: Record<string, string> = {};
  signedHeaderMap['host'] = host;
  signedHeaderMap['x-acs-date'] = request.dateIso;
  signedHeaderMap['x-acs-signature-nonce'] = request.nonce;
  signedHeaderMap['x-acs-content-sha256'] = payloadHash;
  signedHeaderMap['x-acs-version'] = request.version;
  const extraKeys = Object.keys(request.extraSignedHeaders);
  for (const key of extraKeys) {
    signedHeaderMap[key.toLowerCase()] = request.extraSignedHeaders[key];
  }

  const headerNames: string[] = Object.keys(signedHeaderMap).sort();
  const canonicalHeadersLines: string[] = [];
  for (const name of headerNames) {
    canonicalHeadersLines.push(`${name}:${trimValue(signedHeaderMap[name])}`);
  }
  const canonicalHeaders = canonicalHeadersLines.join('\n');
  const signedHeaders = headerNames.join(';');

  const canonicalQuery = buildCanonicalQuery(request.query);
  const canonicalRequest = [
    request.method.toUpperCase(),
    request.path,
    canonicalQuery,
    `${canonicalHeaders}\n`,
    signedHeaders,
    payloadHash
  ].join('\n');

  const canonicalHash = await sha256Hex(canonicalRequest);
  const stringToSign = `ACS3-HMAC-SHA256\n${canonicalHash}`;
  const signature = await hmacSha256Hex(request.accessKeySecret, stringToSign);

  const headers: Record<string, string> = {};
  for (const name of headerNames) {
    headers[name] = trimValue(signedHeaderMap[name]);
  }
  headers['Authorization'] = `ACS3-HMAC-SHA256 Credential=${request.accessKeyId},` +
    `SignedHeaders=${signedHeaders},Signature=${signature}`;

  return {
    headers: headers,
    signature: signature,
    stringToSign: stringToSign,
    canonicalRequest: canonicalRequest
  };
}

/** 查询参数规范化：按 key 排序，值做 URI 编码。 */
export function buildCanonicalQuery(query: Record<string, string>): string {
  const keys = Object.keys(query).sort();
  const parts: string[] = [];
  for (const key of keys) {
    parts.push(`${percentEncode(key)}=${percentEncode(query[key])}`);
  }
  return parts.join('&');
}

/** 生成 ISO8601 UTC 时间（秒级，不带毫秒）。 */
export function acs3DateNow(epochMs: number): string {
  const date = new Date(epochMs);
  const iso = date.toISOString();
  return iso.substring(0, 19) + 'Z';
}

/** 生成随机 nonce。 */
export function acs3Nonce(): string {
  const bytes = new Uint8Array(16);
  const random = cryptoFramework.createRandom();
  const blob = random.generateRandomSync(16);
  const data = blob.data;
  for (let i = 0; i < bytes.length && i < data.length; i++) {
    bytes[i] = data[i];
  }
  const hex: string[] = [];
  for (const byte of bytes) {
    hex.push(byte.toString(16).padStart(2, '0'));
  }
  return hex.join('');
}

/** SHA-256 十六进制小写。 */
export async function sha256Hex(text: string): Promise<string> {
  const md = cryptoFramework.createMd('SHA256');
  const encoder = new util.TextEncoder();
  const dataBlob: cryptoFramework.DataBlob = { data: encoder.encodeInto(text) };
  await md.update(dataBlob);
  const digest = await md.digest();
  return toHex(digest.data);
}

/** HMAC-SHA256 十六进制小写。 */
export async function hmacSha256Hex(key: string, text: string): Promise<string> {
  const encoder = new util.TextEncoder();
  const mac = cryptoFramework.createMac('SHA256');
  const keyBlob: cryptoFramework.DataBlob = { data: encoder.encodeInto(key) };
  const symKey = await cryptoFramework.createSymKeyGenerator('HMAC').convertKey(keyBlob);
  await mac.init(symKey);
  const dataBlob: cryptoFramework.DataBlob = { data: encoder.encodeInto(text) };
  await mac.update(dataBlob);
  const result = await mac.doFinal();
  return toHex(result.data);
}

function toHex(bytes: Uint8Array): string {
  const parts: string[] = [];
  for (const byte of bytes) {
    parts.push(byte.toString(16).padStart(2, '0'));
  }
  return parts.join('');
}

function extractHost(endpoint: string): string {
  let host = endpoint.trim();
  if (host.startsWith('https://')) {
    host = host.substring(8);
  } else if (host.startsWith('http://')) {
    host = host.substring(7);
  }
  const slash = host.indexOf('/');
  if (slash >= 0) {
    host = host.substring(0, slash);
  }
  return host;
}

/** 头值去首尾空白并把连续空白压成单空格。 */
function trimValue(value: string): string {
  return value.trim().replace(/\s+/g, ' ');
}

/** RFC 3986 的严格编码（阿里云要求 & 也编码）。 */
function percentEncode(value: string): string {
  return encodeURIComponent(value)
    .replace(/\+/g, '%20')
    .replace(/\*/g, '%2A')
    .replace(/%7E/g, '~');
}
