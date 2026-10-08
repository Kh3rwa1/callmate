import { Context } from 'hono';
import { logError } from './logger';

/** Shared JSON error handler: generic message + request id, structured log (no PII, no query string). */
export function jsonErrorHandler(err: Error, c: Context<any>) {
  const requestId = (c.get as any)('requestId') || c.req.header('X-Request-Id') || crypto.randomUUID();
  logError('Unhandled Server Error', err, {
    requestId,
    method: c.req.method,
    path: c.req.path,
  });
  return c.json({
    message: 'An internal server error occurred.',
    code: 'server_error',
    request_id: requestId,
  }, 500);
}
