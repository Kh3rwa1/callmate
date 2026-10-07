import { describe, it, expect, beforeAll } from 'vitest';
import { env } from 'cloudflare:test';
import { migrateTestDb } from './setup-db';
import app from '../src/index';
import { signJWT } from '../src/auth';
import { sendBusinessPushNotification, cleanPushTitle } from '../src/services/fcm';

describe('Phase 8: Push Notifications, Device Registration & Token Cleanup', () => {
  const secret = 'test-jwt-signing-secret-key-32chars-min-length';
  const otpPepper = 'test-otp-pepper-secret-32chars-min-length';
  const bizId = 'biz_p8_test';
  const userId = 'usr_p8_test';
  const phone = '919876543333';
  let token: string;

  beforeAll(async () => {
    await migrateTestDb();

    await env.DB.batch([
      env.DB.prepare("INSERT OR REPLACE INTO businesses (id, name, category) VALUES (?, 'Apex Academy', 'coaching')").bind(bizId),
      env.DB.prepare("INSERT OR REPLACE INTO users (id, phone, business_id) VALUES (?, ?, ?)").bind(userId, phone, bizId),
    ]);

    token = await signJWT({ sub: userId, phone, business_id: bizId, type: 'access' }, secret, 3600);
  });

  describe('Part 1: POST /devices and DELETE /devices/:token', () => {
    it('POST /devices registers device token and upserts without duplicates', async () => {
      const fcmToken = 'fcm_token_test_123';
      const res1 = await app.fetch(
        new Request('http://localhost/devices', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${token}`,
          },
          body: JSON.stringify({ token: fcmToken, platform: 'android' }),
        }),
        { ...env, JWT_SIGNING_KEY: secret, OTP_PEPPER: otpPepper }
      );

      expect(res1.status).toBe(200);
      const data1: any = await res1.json();
      expect(data1.registered).toBe(true);

      const d1 = await env.DB.prepare('SELECT COUNT(*) as cnt FROM devices WHERE business_id = ? AND fcm_token = ?').bind(bizId, fcmToken).first<{ cnt: number }>();
      expect(d1?.cnt).toBe(1);

      // Re-registering same token updates platform and does not duplicate row
      const res2 = await app.fetch(
        new Request('http://localhost/devices', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${token}`,
          },
          body: JSON.stringify({ token: fcmToken, platform: 'ios' }),
        }),
        { ...env, JWT_SIGNING_KEY: secret, OTP_PEPPER: otpPepper }
      );

      expect(res2.status).toBe(200);
      const d2 = await env.DB.prepare('SELECT COUNT(*) as cnt, platform FROM devices WHERE business_id = ? AND fcm_token = ?').bind(bizId, fcmToken).first<{ cnt: number; platform: string }>();
      expect(d2?.cnt).toBe(1);
      expect(d2?.platform).toBe('ios');
    });

    it('DELETE /devices/:token removes the registered device token', async () => {
      const fcmToken = 'fcm_token_to_delete_456';
      await env.DB.prepare(
        "INSERT INTO devices (id, business_id, fcm_token, platform) VALUES ('dev_del_1', ?, ?, 'android')"
      ).bind(bizId, fcmToken).run();

      const res = await app.fetch(
        new Request(`http://localhost/devices/${fcmToken}`, {
          method: 'DELETE',
          headers: {
            Authorization: `Bearer ${token}`,
          },
        }),
        { ...env, JWT_SIGNING_KEY: secret, OTP_PEPPER: otpPepper }
      );

      expect(res.status).toBe(200);
      const check = await env.DB.prepare('SELECT id FROM devices WHERE fcm_token = ?').bind(fcmToken).first();
      expect(check).toBeNull();
    });
  });

  describe('Part 2: Push Title Sanitization (Strip Stray Leading Spaces & Emojis)', () => {
    it('cleanPushTitle strips leading spaces and emojis', () => {
      expect(cleanPushTitle(' Hot Lead Alert')).toBe('Hot Lead Alert');
      expect(cleanPushTitle(' Follow-up Ready')).toBe('Follow-up Ready');
      expect(cleanPushTitle('🔥 Hot Lead Alert')).toBe('Hot Lead Alert');
      expect(cleanPushTitle('💬 Follow-up Ready')).toBe('Follow-up Ready');
      expect(cleanPushTitle('Callback Scheduled')).toBe('Callback Scheduled');
    });
  });

  describe('Part 3: Notification Block Alongside Data and Token Deletion on Unregistered', () => {
    it('deletes token from devices when FCM reports token as unregistered', async () => {
      const badToken = 'unregistered_fcm_token_789';
      await env.DB.prepare(
        "INSERT INTO devices (id, business_id, fcm_token, platform) VALUES ('dev_bad_1', ?, ?, 'android')"
      ).bind(bizId, badToken).run();

      // Configure mock FCM service account that triggers unregistered error
      const mockEnv = {
        ...env,
        FCM_SERVICE_ACCOUNT_JSON: JSON.stringify({
          project_id: 'test-project',
          mock_simulate_unregistered_tokens: [badToken],
        }),
      };

      await sendBusinessPushNotification(mockEnv as any, bizId, {
        type: 'hot_lead',
        title: 'Hot Lead Alert',
        body: 'Rohan Sharma is very interested',
        route: '/leads/lead_123',
      });

      // The unregistered token should be deleted from DB
      const check = await env.DB.prepare('SELECT id FROM devices WHERE fcm_token = ?').bind(badToken).first();
      expect(check).toBeNull();
    });
  });
});
