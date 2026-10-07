import { describe, it, expect, beforeAll } from 'vitest';
import { env } from 'cloudflare:test';
import { migrateTestDb } from './setup-db';
import app from '../src/index';
import { requireSecret, isDevEnv } from '../src/utils/secrets';
import { hitRateLimit } from '../src/utils/rate_limit';
import { runMaintenance } from '../src/services/maintenance';
import { signJWT } from '../src/auth';

describe('Phase 4: Auth, Secrets Hardening, Rate Limits, Maintenance Cron', () => {
  const secret = 'test-jwt-signing-secret-key-32chars-min-length';
  const otpPepper = 'test-otp-pepper-secret-32chars-min-length';
  const bizId = 'biz_p4_test';
  const userId = 'usr_p4_test';
  const phone = '919876543210';
  let token: string;

  beforeAll(async () => {
    await migrateTestDb();

    await env.DB.batch([
      env.DB.prepare("INSERT OR REPLACE INTO businesses (id, name, category) VALUES (?, 'Phase 4 Biz', 'education')").bind(bizId),
      env.DB.prepare("INSERT OR REPLACE INTO users (id, phone, business_id) VALUES (?, ?, ?)").bind(userId, phone, bizId),
      env.DB.prepare("INSERT OR REPLACE INTO agents (id, business_id, name, role, status) VALUES ('agent_p4', ?, 'Maya', 'Counselor', 'active')").bind(bizId),
      env.DB.prepare("INSERT OR REPLACE INTO usage (id, business_id, plan_name, included_minutes, renews_at, price_inr, minutes_used, calls_made, rate_per_minute_inr) VALUES ('usg_p4', ?, 'Founding', 1000, datetime('now', '+30 days'), 4999, 0, 0, 6)").bind(bizId),
    ]);

    token = await signJWT({ sub: userId, phone, business_id: bizId, type: 'access' }, secret, 3600);
  });

  describe('Part 1: Secrets & Environment Checks', () => {
    it('requireSecret throws when secret is missing or shorter than minLen', () => {
      expect(() => requireSecret({}, 'MISSING')).toThrow(/missing or shorter/);
      expect(() => requireSecret({ SHORT: 'short' }, 'SHORT', 32)).toThrow(/missing or shorter/);
      expect(requireSecret({ VALID: '  this-is-a-valid-long-secret-key-1234567890  ' }, 'VALID', 16)).toBe(
        'this-is-a-valid-long-secret-key-1234567890'
      );
    });

    it('isDevEnv only returns true for development or test', () => {
      expect(isDevEnv({ ENVIRONMENT: 'development' })).toBe(true);
      expect(isDevEnv({ ENVIRONMENT: 'test' })).toBe(true);
      expect(isDevEnv({ ENVIRONMENT: 'production' })).toBe(false);
      expect(isDevEnv({ ENVIRONMENT: 'staging' })).toBe(false);
      expect(isDevEnv({})).toBe(false);
    });
  });

  describe('Part 2: Rate Limiting & /voice/chat Hardening', () => {
    it('hitRateLimit correctly counts and throttles after limit', async () => {
      const bucket = `test_bucket_${crypto.randomUUID()}`;
      for (let i = 0; i < 3; i++) {
        const res = await hitRateLimit(env.DB, bucket, 3, 60);
        expect(res.allowed).toBe(true);
        expect(res.retryAfter).toBe(0);
      }

      const blocked = await hitRateLimit(env.DB, bucket, 3, 60);
      expect(blocked.allowed).toBe(false);
      expect(blocked.retryAfter).toBe(60);
    });

    it('/voice/chat rejects messages longer than 1000 characters', async () => {
      const longMessage = 'A'.repeat(1001);
      const res = await app.fetch(
        new Request('http://localhost/voice/chat', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${token}`,
          },
          body: JSON.stringify({ message: longMessage }),
        }),
        { ...env, JWT_SIGNING_KEY: secret, OTP_PEPPER: otpPepper }
      );

      expect(res.status).toBe(400);
      const data: any = await res.json();
      expect(data.code).toBe('invalid_request');
      expect(data.message).toBe('Message too long.');
    });

    it('/voice/chat throttles after 20 requests per user with 429 and Retry-After', async () => {
      const chatUser = `usr_chat_${crypto.randomUUID().slice(0, 8)}`;
      const chatPhone = '919876543299';
      await env.DB.prepare("INSERT INTO users (id, phone, business_id) VALUES (?, ?, ?)").bind(chatUser, chatPhone, bizId).run();
      const chatToken = await signJWT({ sub: chatUser, phone: chatPhone, business_id: bizId, type: 'access' }, secret, 3600);

      // Pre-fill 20 hits for this user's rate limit bucket
      const userBucket = `chat:user:${chatUser}`;
      for (let i = 0; i < 20; i++) {
        await env.DB.prepare('INSERT INTO rate_limits (id, bucket) VALUES (?, ?)').bind(crypto.randomUUID(), userBucket).run();
      }

      const res = await app.fetch(
        new Request('http://localhost/voice/chat', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${chatToken}`,
          },
          body: JSON.stringify({ message: 'Hello' }),
        }),
        { ...env, JWT_SIGNING_KEY: secret, OTP_PEPPER: otpPepper }
      );

      expect(res.status).toBe(429);
      expect(res.headers.get('Retry-After')).toBe('60');
      const data: any = await res.json();
      expect(data.code).toBe('rate_limited');
    });
  });

  describe('Part 3: OTP Hashing & Environment Debug Leaks', () => {
    it('request OTP and verify registration succeeds with HMAC hashOtp', async () => {
      const regPhone = '919811122233';
      const reqRes = await app.fetch(
        new Request('http://localhost/auth/otp/request', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ phone: regPhone }),
        }),
        { ...env, JWT_SIGNING_KEY: secret, OTP_PEPPER: otpPepper, ENVIRONMENT: 'development' }
      );

      expect(reqRes.status).toBe(200);
      const reqData: any = await reqRes.json();
      expect(reqData.debug_otp).toBeDefined();

      const otp = reqData.debug_otp;

      // Verify OTP is hashed (not raw or plain sha256) in otp_codes table
      const stored = await env.DB.prepare('SELECT * FROM otp_codes WHERE phone = ?').bind(regPhone).first<any>();
      expect(stored).toBeDefined();
      expect(stored.otp_hash).toBeDefined();
      expect(stored.otp_hash).not.toBe(otp);

      // Register with the OTP
      const regRes = await app.fetch(
        new Request('http://localhost/auth/register', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            phone: regPhone,
            otp,
            business_name: 'HMAC Test Academy',
          }),
        }),
        { ...env, JWT_SIGNING_KEY: secret, OTP_PEPPER: otpPepper, ENVIRONMENT: 'development' }
      );

      expect(regRes.status).toBe(200);
      const regData: any = await regRes.json();
      expect(regData.access_token).toBeDefined();
    });

    it('OTP in production mode does NOT leak debug_otp and enforces 10 IP limit', async () => {
      const prodPhone = '919822233344';
      const prodIp = '198.51.100.5';

      const reqRes = await app.fetch(
        new Request('http://localhost/auth/otp/request', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'cf-connecting-ip': prodIp,
          },
          body: JSON.stringify({ phone: prodPhone }),
        }),
        { ...env, JWT_SIGNING_KEY: secret, OTP_PEPPER: otpPepper, ENVIRONMENT: 'staging' }
      );

      expect(reqRes.status).toBe(200);
      const reqData: any = await reqRes.json();
      expect(reqData.debug_otp).toBeUndefined();

      // Pre-fill IP rate limits to 10
      for (let i = 0; i < 9; i++) {
        await env.DB.prepare('INSERT INTO otp_rate_limits (id, phone, ip) VALUES (?, ?, ?)')
          .bind(crypto.randomUUID().slice(0, 12), `91989999000${i}`, prodIp).run();
      }

      const blockedRes = await app.fetch(
        new Request('http://localhost/auth/otp/request', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'cf-connecting-ip': prodIp,
          },
          body: JSON.stringify({ phone: '919833344455' }),
        }),
        { ...env, JWT_SIGNING_KEY: secret, OTP_PEPPER: otpPepper, ENVIRONMENT: 'staging' }
      );

      expect(blockedRes.status).toBe(429);
      const blockedData: any = await blockedRes.json();
      expect(blockedData.code).toBe('rate_limited');
    });
  });

  describe('Part 4: Maintenance Sweeper & Scheduled Cron', () => {
    it('runMaintenance prunes expired tables and sweeps stuck calling calls', async () => {
      // 1. Seed old rate limits and expired otp
      await env.DB.batch([
        env.DB.prepare("INSERT INTO rate_limits (id, bucket, created_at) VALUES ('rl_old', 'test', datetime('now', '-3 days'))"),
        env.DB.prepare("INSERT INTO webhook_events (event_key, source, received_at) VALUES ('ev_old', 'sarvam', datetime('now', '-31 days'))"),
        env.DB.prepare("INSERT OR REPLACE INTO otp_codes (phone, otp_hash, attempts, expires_at) VALUES ('919999999999', 'hash', 0, datetime('now', '-10 minutes'))"),
        env.DB.prepare("INSERT INTO voice_sessions (id, business_id, user_id, status, started_at) VALUES ('vs_stale', ?, ?, 'active', datetime('now', '-2 hours'))").bind(bizId, userId),
      ]);

      // 2. Seed a stuck call (>45 min in 'calling') for a campaign lead
      const campId = `camp_stuck_${crypto.randomUUID().slice(0, 8)}`;
      const leadId = `lead_stuck_${crypto.randomUUID().slice(0, 8)}`;
      const callId = `call_stuck_${crypto.randomUUID().slice(0, 8)}`;

      await env.DB.batch([
        env.DB.prepare("INSERT INTO campaigns (id, business_id, purpose, status) VALUES (?, ?, 'Stuck Camp', 'running')").bind(campId, bizId),
        env.DB.prepare("INSERT INTO leads (id, business_id, name, phone, status) VALUES (?, ?, 'Stuck Lead', '919888877771', 'calling')").bind(leadId, bizId),
        env.DB.prepare("INSERT INTO campaign_leads (campaign_id, lead_id, status, attempts, call_id) VALUES (?, ?, 'calling', 1, ?)").bind(campId, leadId, callId),
        env.DB.prepare("INSERT INTO calls (id, business_id, lead_id, lead_name, lead_phone, campaign_id, status, started_at) VALUES (?, ?, ?, 'Stuck Lead', '919888877771', ?, 'calling', datetime('now', '-50 minutes'))").bind(callId, bizId, leadId, campId),
      ]);

      const mockSent: any[] = [];
      const testEnv = {
        ...env,
        CAMPAIGN_QUEUE: {
          send: async (msg: any, opts: any) => { mockSent.push({ msg, opts }); },
        } as any,
      };

      await runMaintenance(testEnv);

      // Verify prunings
      const oldRl = await env.DB.prepare("SELECT * FROM rate_limits WHERE id = 'rl_old'").first();
      expect(oldRl).toBeNull();

      const oldEv = await env.DB.prepare("SELECT * FROM webhook_events WHERE event_key = 'ev_old'").first();
      expect(oldEv).toBeNull();

      const expiredOtp = await env.DB.prepare("SELECT * FROM otp_codes WHERE phone = '919999999999'").first();
      expect(expiredOtp).toBeNull();

      const vs = await env.DB.prepare("SELECT * FROM voice_sessions WHERE id = 'vs_stale'").first<any>();
      expect(vs.status).toBe('ended');
      expect(vs.ended_at).toBeDefined();

      // Verify stuck call swept
      const sweptCall = await env.DB.prepare("SELECT * FROM calls WHERE id = ?").bind(callId).first<any>();
      expect(sweptCall.status).toBe('timed_out');
      expect(sweptCall.failure_reason).toBe('no_webhook_45m');

      // Verify campaign lead updated to retry_pending and requeued
      const cl = await env.DB.prepare("SELECT * FROM campaign_leads WHERE call_id = ?").bind(callId).first<any>();
      expect(cl.status).toBe('retry_pending');
      expect(mockSent.length).toBe(1);
      expect(mockSent[0].msg.campaign_id).toBe(campId);
      expect(mockSent[0].opts.delaySeconds).toBe(1800);
    });

    it('scheduled worker handler triggers runMaintenance via ctx.waitUntil', async () => {
      let waitUntilPromise: Promise<any> | null = null;
      const fakeCtx: any = {
        waitUntil: (p: Promise<any>) => { waitUntilPromise = p; },
      };

      await app.scheduled({} as any, env, fakeCtx);
      expect(waitUntilPromise).not.toBeNull();
      await waitUntilPromise;
    });
  });

  describe('Part 5: CORS Hardening', () => {
    it('returns Access-Control-Allow-Origin: * in development mode', async () => {
      const res = await app.fetch(
        new Request('http://localhost/health', {
          headers: { Origin: 'https://any-dev-site.com' },
        }),
        { ...env, ENVIRONMENT: 'development' }
      );

      expect(res.headers.get('Access-Control-Allow-Origin')).toBe('*');
    });

    it('in production mode, respects ALLOWED_ORIGINS allow-list', async () => {
      const allowedEnv = {
        ...env,
        ENVIRONMENT: 'production',
        ALLOWED_ORIGINS: 'https://callpilot.in,https://app.callpilot.in',
      };

      const okRes = await app.fetch(
        new Request('http://localhost/health', {
          headers: { Origin: 'https://app.callpilot.in' },
        }),
        allowedEnv
      );
      expect(okRes.headers.get('Access-Control-Allow-Origin')).toBe('https://app.callpilot.in');

      const blockedRes = await app.fetch(
        new Request('http://localhost/health', {
          headers: { Origin: 'https://malicious-site.com' },
        }),
        allowedEnv
      );
      expect(blockedRes.headers.get('Access-Control-Allow-Origin')).toBeNull();
    });
  });
});
