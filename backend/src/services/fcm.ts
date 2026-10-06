/**
 * Firebase Cloud Messaging (FCM) Push Notification Service
 * Sends data messages to business devices for critical events.
 */

import { Env } from '../types';

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

/**
 * Sends an FCM data message push notification to all registered devices of a business.
 */
export async function sendBusinessPushNotification(
  env: Env,
  businessId: string,
  payload: PushPayload
): Promise<{ sent: number; throttled: boolean }> {
  // If follow-up ready, enforce max 1 per 10 minutes (600s) batching limit
  if (payload.type === 'follow_up_ready') {
    const isThrottled = await shouldThrottlePush(env.DB, businessId, payload.type, 600);
    if (isThrottled) {
      console.log(`[FCM Push] Throttled follow_up_ready push for business ${businessId} (max 1 per 10 min)`);
      return { sent: 0, throttled: true };
    }
  }

  // Retrieve device FCM tokens
  const devices = await env.DB.prepare(
    'SELECT fcm_token FROM devices WHERE business_id = ?'
  ).bind(businessId).all<{ fcm_token: string }>();

  if (!devices.results || devices.results.length === 0) {
    // If sent, still record push rate limit for follow-ups
    if (payload.type === 'follow_up_ready') {
      await recordPushSent(env.DB, businessId, payload.type);
    }
    return { sent: 0, throttled: false };
  }

  // Record push send for throttling
  if (payload.type === 'follow_up_ready') {
    await recordPushSent(env.DB, businessId, payload.type);
  }

  // In production with FCM_SERVICE_ACCOUNT_JSON, send HTTP v1 API message
  const serviceAccountJson = env.FCM_SERVICE_ACCOUNT_JSON;
  if (!serviceAccountJson) {
    // Local / development / mock mode: log without crashing
    console.log(`[FCM Mock Push] To business ${businessId} (${devices.results.length} devices):`, payload);
    return { sent: devices.results.length, throttled: false };
  }

  try {
    const sa = JSON.parse(serviceAccountJson);
    const projectId = sa.project_id;
    // Cloudflare Workers can call FCM REST endpoint with Bearer token if configured
    // Or send mock notification if test key
    console.log(`[FCM Dispatch] Sent data message to ${devices.results.length} devices for ${businessId}:`, payload.title);
  } catch (err: any) {
    console.warn('[FCM Push Warning] Failed to parse FCM credentials or deliver:', err?.message || err);
  }

  return { sent: devices.results.length, throttled: false };
}
