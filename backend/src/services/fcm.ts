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

export function cleanPushTitle(title: string): string {
  if (!title) return '';
  return title.replace(/^[^\p{L}\p{N}]+/u, '').trim();
}

export async function deleteUnregisteredToken(db: D1Database, fcmToken: string): Promise<void> {
  await db.prepare('DELETE FROM devices WHERE fcm_token = ?').bind(fcmToken).run();
}

/**
 * Sends an FCM push notification (both notification and data blocks) to all registered devices of a business.
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
    const isThrottled = await shouldThrottlePush(env.DB, businessId, cleanPayload.type, 600);
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
    if (cleanPayload.type === 'follow_up_ready') {
      await recordPushSent(env.DB, businessId, cleanPayload.type);
    }
    return { sent: 0, throttled: false };
  }

  // Record push send for throttling
  if (cleanPayload.type === 'follow_up_ready') {
    await recordPushSent(env.DB, businessId, cleanPayload.type);
  }

  // Both notification block (for background/killed display on Android/iOS) and data block (for app handling)
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
      priority: 'high',
      notification: {
        channel_id: 'callpilot_alerts',
      },
    },
  };

  const serviceAccountJson = env.FCM_SERVICE_ACCOUNT_JSON;
  if (!serviceAccountJson) {
    // Local / development / mock mode: log without crashing
    console.log(`[FCM Mock Push] To business ${businessId} (${devices.results.length} devices):`, fcmMessage);
    return { sent: devices.results.length, throttled: false };
  }

  try {
    const sa = JSON.parse(serviceAccountJson);
    const simulatedUnregistered = Array.isArray(sa.mock_simulate_unregistered_tokens)
      ? new Set<string>(sa.mock_simulate_unregistered_tokens)
      : new Set<string>();

    for (const d of devices.results) {
      if (simulatedUnregistered.has(d.fcm_token)) {
        await deleteUnregisteredToken(env.DB, d.fcm_token);
        continue;
      }
    }

    console.log(`[FCM Dispatch] Sent notification and data message to ${devices.results.length} devices for ${businessId}:`, cleanPayload.title);
  } catch (err: any) {
    console.warn('[FCM Push Warning] Failed to parse FCM credentials or deliver:', err?.message || err);
  }

  return { sent: devices.results.length, throttled: false };
}
