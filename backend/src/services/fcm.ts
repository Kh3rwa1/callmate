/**
 * Firebase Cloud Messaging (FCM) Push Notification Service
 * Sends data messages to business devices for critical events.
 */

import { Env } from '../types';
import { logInfo, logWarn } from '../utils/logger';

export const FCM_TIMEOUT_MS = 8000;
const GOOGLE_TOKEN_URL = 'https://oauth2.googleapis.com/token';
const FCM_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';

interface ServiceAccount {
  project_id?: string;
  client_email?: string;
  private_key?: string;
  mock_simulate_unregistered_tokens?: string[];
}

// In-memory OAuth token cache (per isolate), keyed by service account email.
let cachedAccessToken: { key: string; token: string; expiresAtMs: number } | null = null;

/** Test hook: forget any cached OAuth access token. */
export function resetFcmTokenCache(): void {
  cachedAccessToken = null;
}

function base64UrlEncode(input: Uint8Array | string): string {
  const bytes = typeof input === 'string' ? new TextEncoder().encode(input) : input;
  let binary = '';
  for (let i = 0; i < bytes.byteLength; i++) binary += String.fromCharCode(bytes[i]);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function pemToPkcs8(pem: string): ArrayBuffer {
  const b64 = pem
    .replace(/-----BEGIN [^-]+-----/g, '')
    .replace(/-----END [^-]+-----/g, '')
    .replace(/\\n/g, '')
    .replace(/\s+/g, '');
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

/** Mints (or reuses) an OAuth2 access token for FCM via a self-signed RS256 JWT assertion. */
export async function getFcmAccessToken(sa: ServiceAccount): Promise<string> {
  const key = sa.client_email!;
  if (cachedAccessToken && cachedAccessToken.key === key && cachedAccessToken.expiresAtMs - 60_000 > Date.now()) {
    return cachedAccessToken.token;
  }

  const now = Math.floor(Date.now() / 1000);
  const header = base64UrlEncode(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claims = base64UrlEncode(JSON.stringify({
    iss: sa.client_email,
    scope: FCM_SCOPE,
    aud: GOOGLE_TOKEN_URL,
    iat: now,
    exp: now + 3600,
  }));
  const signingKey = await crypto.subtle.importKey(
    'pkcs8',
    pemToPkcs8(sa.private_key!),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign']
  );
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', signingKey, new TextEncoder().encode(`${header}.${claims}`));
  const assertion = `${header}.${claims}.${base64UrlEncode(new Uint8Array(sig))}`;

  const res = await fetch(GOOGLE_TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion }).toString(),
    signal: AbortSignal.timeout(FCM_TIMEOUT_MS),
  });
  const data: any = await res.json().catch(() => null);
  if (!res.ok || !data?.access_token) {
    throw new Error(`fcm_oauth_failed_http_${res.status}`);
  }
  const ttlSeconds = Number(data.expires_in) > 0 ? Number(data.expires_in) : 3600;
  cachedAccessToken = { key, token: data.access_token, expiresAtMs: Date.now() + ttlSeconds * 1000 };
  return data.access_token;
}

function isUnregistered(status: number, body: any): boolean {
  if (status === 404) return true;
  const err = body?.error;
  if (err?.status === 'UNREGISTERED' || err?.status === 'NOT_FOUND') return true;
  return Array.isArray(err?.details) && err.details.some((d: any) => d?.errorCode === 'UNREGISTERED');
}

export interface PushPayload {
  type: 'hot_lead' | 'campaign' | 'callback' | 'follow_up_ready';
  title: string;
  body: string;
  route: string;
}

/**
 * Checks if a push of given type should be throttled/batched (e.g. max 1 per 10 min for follow_up_ready).
 */
export async function shouldThrottlePush(
  db: D1Database,
  businessId: string,
  type: string,
  cooldownSeconds: number = 600
): Promise<boolean> {
  const recent = await db.prepare(
    `SELECT id FROM push_rate_limits
     WHERE business_id = ? AND type = ? AND created_at > datetime('now', '-' || ? || ' seconds')`
  ).bind(businessId, type, cooldownSeconds).first<{ id: string }>();

  return !!recent;
}

/**
 * Records that a push notification was sent for throttling purposes.
 */
export async function recordPushSent(
  db: D1Database,
  businessId: string,
  type: string
): Promise<void> {
  const id = `prl_${crypto.randomUUID().slice(0, 12)}`;
  await db.prepare(
    `INSERT INTO push_rate_limits (id, business_id, type, created_at)
     VALUES (?, ?, ?, datetime('now'))`
  ).bind(id, businessId, type).run();
}

export function cleanPushTitle(title: string): string {
  if (!title) return '';
  return title.replace(/^[^\p{L}\p{N}]+/u, '').trim();
}

export async function deleteUnregisteredToken(db: D1Database, fcmToken: string): Promise<void> {
  await db.prepare('DELETE FROM devices WHERE fcm_token = ?').bind(fcmToken).run();
}

/**
 * Atomically claims the cooldown slot for a push type: records the send and returns true only if
 * no push of this type went out within the cooldown. Concurrent callers cannot both win.
 */
export async function claimPushSlot(
  db: D1Database,
  businessId: string,
  type: string,
  cooldownSeconds: number = 600
): Promise<boolean> {
  const res = await db.prepare(
    `INSERT INTO push_rate_limits (id, business_id, type, created_at)
     SELECT ?, ?, ?, datetime('now')
     WHERE NOT EXISTS (
       SELECT 1 FROM push_rate_limits
       WHERE business_id = ? AND type = ? AND created_at > datetime('now', '-' || ? || ' seconds')
     )`
  ).bind(`prl_${crypto.randomUUID().slice(0, 12)}`, businessId, type, businessId, type, cooldownSeconds).run();
  return (res.meta?.changes ?? 0) > 0;
}

/**
 * Sends an FCM push notification (both notification and data blocks) to all registered devices of a business,
 * via the FCM HTTP v1 API. Never logs titles/bodies (they contain lead names): counts only.
 */
export async function sendBusinessPushNotification(
  env: Env,
  businessId: string,
  payload: PushPayload
): Promise<{ sent: number; throttled: boolean }> {
  const title = cleanPushTitle(payload.title);
  const cleanPayload: PushPayload = {
    ...payload,
    title,
  };

  // If follow-up ready, enforce max 1 per 10 minutes (600s) batching limit
  if (cleanPayload.type === 'follow_up_ready') {
    const claimed = await claimPushSlot(env.DB, businessId, cleanPayload.type, 600);
    if (!claimed) {
      logInfo('fcm_push_throttled', { type: cleanPayload.type });
      return { sent: 0, throttled: true };
    }
  }

  // Retrieve device FCM tokens
  const devices = await env.DB.prepare(
    'SELECT fcm_token FROM devices WHERE business_id = ?'
  ).bind(businessId).all<{ fcm_token: string }>();

  if (!devices.results || devices.results.length === 0) {
    return { sent: 0, throttled: false };
  }

  // Both notification block (for background/killed display on Android) and data block (for app handling)
  const fcmMessage = {
    notification: {
      title: cleanPayload.title,
      body: cleanPayload.body,
    },
    data: {
      type: cleanPayload.type,
      title: cleanPayload.title,
      body: cleanPayload.body,
      route: cleanPayload.route,
    },
    android: {
      priority: 'HIGH',
      notification: {
        channel_id: 'callpilot_alerts',
      },
    },
  };

  const serviceAccountJson = env.FCM_SERVICE_ACCOUNT_JSON;
  if (!serviceAccountJson) {
    // Local / development / mock mode: log counts only, without crashing
    logInfo('fcm_mock_push', { type: cleanPayload.type, devices: devices.results.length });
    return { sent: devices.results.length, throttled: false };
  }

  let sa: ServiceAccount;
  try {
    sa = JSON.parse(serviceAccountJson);
  } catch {
    logWarn('fcm_invalid_service_account_json');
    return { sent: 0, throttled: false };
  }

  if (!sa.private_key || !sa.client_email || !sa.project_id) {
    // Credential-less mock config (tests/dev): simulate unregistered tokens, send nothing.
    const simulatedUnregistered = new Set<string>(
      Array.isArray(sa.mock_simulate_unregistered_tokens) ? sa.mock_simulate_unregistered_tokens : []
    );
    let removed = 0;
    for (const d of devices.results) {
      if (simulatedUnregistered.has(d.fcm_token)) {
        await deleteUnregisteredToken(env.DB, d.fcm_token);
        removed++;
      }
    }
    logInfo('fcm_mock_push', { type: cleanPayload.type, devices: devices.results.length, removed });
    return { sent: devices.results.length - removed, throttled: false };
  }

  let accessToken: string;
  try {
    accessToken = await getFcmAccessToken(sa);
  } catch (err: any) {
    logWarn('fcm_oauth_failed', { error: err?.message });
    return { sent: 0, throttled: false };
  }

  const endpoint = `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(sa.project_id)}/messages:send`;
  let sent = 0;
  let failed = 0;
  let removed = 0;
  for (const d of devices.results) {
    try {
      const res = await fetch(endpoint, {
        method: 'POST',
        headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ message: { token: d.fcm_token, ...fcmMessage } }),
        signal: AbortSignal.timeout(FCM_TIMEOUT_MS),
      });
      if (res.ok) {
        sent++;
        continue;
      }
      const body: any = await res.json().catch(() => null);
      if (isUnregistered(res.status, body)) {
        await deleteUnregisteredToken(env.DB, d.fcm_token);
        removed++;
      } else {
        failed++;
      }
    } catch {
      failed++;
    }
  }

  logInfo('fcm_dispatch', { type: cleanPayload.type, devices: devices.results.length, sent, failed, removed });
  return { sent, throttled: false };
}
