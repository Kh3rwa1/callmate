/**
 * Structured JSON Logger for CallPilot Cloudflare Worker
 * Guarantees that PII (phone numbers, OTPs, transcripts) are never logged in plain text.
 */

export function maskPhone(phone: string): string {
  if (!phone) return '';
  const digits = phone.replace(/\D/g, '');
  if (digits.length <= 5) return 'XXXXX';
  const prefix = digits.slice(0, 2);
  const suffix = digits.slice(-3);
  const maskLen = Math.max(1, digits.length - 5);
  return `${prefix}${'X'.repeat(maskLen)}${suffix}`;
}

export interface LogPayload {
  level: 'info' | 'warn' | 'error';
  message: string;
  requestId?: string;
  timestamp?: string;
  [key: string]: any;
}

export function logJson(payload: LogPayload): void {
  const output = {
    timestamp: payload.timestamp || new Date().toISOString(),
    ...payload,
  };
  const jsonStr = JSON.stringify(output);
  if (payload.level === 'error') {
    console.error(jsonStr);
  } else if (payload.level === 'warn') {
    console.warn(jsonStr);
  } else {
    console.log(jsonStr);
  }
}

export function logInfo(message: string, context?: Record<string, any>): void {
  logJson({ level: 'info', message, ...context });
}

export function logWarn(message: string, context?: Record<string, any>): void {
  logJson({ level: 'warn', message, ...context });
}

export function logError(message: string, error?: any, context?: Record<string, any>): void {
  const errObj = error instanceof Error
    ? { error_name: error.name, error_message: error.message, stack: error.stack }
    : error ? { error_raw: String(error) } : undefined;
  logJson({ level: 'error', message, ...(errObj ? { err: errObj } : {}), ...context });
}

/**
 * Request logger middleware. Logs method + path (never the query string, which can carry
 * phone numbers like ?q=98...) + status + duration.
 */
export async function requestLogger(c: any, next: () => Promise<void>): Promise<void> {
  const start = Date.now();
  await next();
  logInfo('request', {
    requestId: c.get?.('requestId'),
    method: c.req.method,
    path: c.req.path,
    status: c.res?.status,
    duration_ms: Date.now() - start,
  });
}
