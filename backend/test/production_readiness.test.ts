import { describe, it, expect, beforeAll, afterEach, vi } from 'vitest';
import { env } from 'cloudflare:test';
import { migrateTestDb } from './setup-db';
import worker from '../src/index';
import { signJWT } from '../src/auth';
import { createCampaignSchema, MAX_CAMPAIGN_LEADS } from '../src/schemas/validation';
import {
  enqueueCampaignJobs,
  handleCampaignQueueBatch,
  handleCampaignDlqBatch,
  isDeadLetterQueue,
  maybeCompleteCampaign,
  processCampaignJob,
  sarvamWebhookConfig,
  MAX_CONCURRENT_CALLS_PER_BUSINESS,
} from '../src/services/campaign_queue';
import { runMaintenance } from '../src/services/maintenance';
import { sendBusinessPushNotification, resetFcmTokenCache } from '../src/services/fcm';
import { assertSafePublicUrl, fetchPublicPage, ingestKnowledge, WEBSITE_MAX_BYTES } from '../src/services/knowledge';
import { KNOWLEDGE_INGEST_LIMIT_PER_HOUR } from '../src/routes/knowledge';
import { parseLimit } from '../src/utils/pagination';
import { timingSafeEqual } from '../src/utils/compare';

const app = worker;
const secret = 'test-jwt-signing-secret-key-32chars-min-length';
const bizId = 'biz_prod_ready';
const userId = 'usr_prod_ready';
const phone = '919830077777';
let token: string;

async function hmacHex(body: string, key: string): Promise<string> {
  const enc = new TextEncoder();
  const k = await crypto.subtle.importKey('raw', enc.encode(key), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const sig = await crypto.subtle.sign('HMAC', k, enc.encode(body));
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

const post = (path: string, body: unknown, headers: Record<string, string> = {}, targetEnv: any = env) =>
  app.fetch(new Request(`http://localhost${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...headers },
    body: JSON.stringify(body),
  }), targetEnv);

const authed = (path: string, init: RequestInit = {}, tk = token, targetEnv: any = env) => {
  const headers = new Headers(init.headers || {});
  headers.set('Authorization', `Bearer ${tk}`);
  if (init.body && !headers.has('Content-Type')) headers.set('Content-Type', 'application/json');
  return app.fetch(new Request(`http://localhost${path}`, { ...init, headers }), targetEnv);
};

async function requestOtp(p: string): Promise<string> {
  const res = await post('/auth/otp/request', { phone: p });
  expect(res.status).toBe(200);
  return ((await res.json()) as any).debug_otp;
}

let seq = 0;
async function seedCampaign(opts: { leads: number; leadStatus?: string; campStatus?: string } ) {
  const n = ++seq;
  const campId = `cmp_pr_${n}_${Date.now()}`;
  const stmts: D1PreparedStatement[] = [
    env.DB.prepare(
      `INSERT INTO campaigns (id, business_id, purpose, status, total_leads, calling_hours_start, calling_hours_end)
       VALUES (?, ?, 'PR', ?, ?, 0, 24)`
    ).bind(campId, bizId, opts.campStatus ?? 'running', opts.leads),
  ];
  const leadIds: string[] = [];
  for (let i = 0; i < opts.leads; i++) {
    const leadId = `lead_pr_${n}_${i}_${Date.now()}`;
    leadIds.push(leadId);
    stmts.push(
      env.DB.prepare(`INSERT INTO leads (id, business_id, name, phone, status, consent) VALUES (?, ?, 'PR Lead', ?, 'new', 'explicit_opt_in')`)
        .bind(leadId, bizId, `9197${String(n).padStart(4, '0')}${String(i).padStart(4, '0')}`),
      env.DB.prepare(`INSERT INTO campaign_leads (campaign_id, lead_id, status) VALUES (?, ?, ?)`)
        .bind(campId, leadId, opts.leadStatus ?? 'pending'),
    );
  }
  for (let i = 0; i < stmts.length; i += 80) await env.DB.batch(stmts.slice(i, i + 80));
  return { campId, leadIds };
}

const campaignStatus = async (id: string) =>
  (await env.DB.prepare('SELECT status FROM campaigns WHERE id = ?').bind(id).first<{ status: string }>())?.status;
const leadStatus = async (campId: string, leadId: string) =>
  (await env.DB.prepare('SELECT status FROM campaign_leads WHERE campaign_id = ? AND lead_id = ?').bind(campId, leadId).first<{ status: string }>())?.status;

describe('Production readiness fixes', () => {
  beforeAll(async () => {
    await migrateTestDb();
    await env.DB.batch([
      env.DB.prepare("INSERT OR REPLACE INTO businesses (id, name, category) VALUES (?, 'PR Academy', 'education')").bind(bizId),
      env.DB.prepare('INSERT OR REPLACE INTO users (id, phone, business_id) VALUES (?, ?, ?)').bind(userId, phone, bizId),
      env.DB.prepare("INSERT OR REPLACE INTO agents (id, business_id, name, role, status, calling_hours_start, calling_hours_end) VALUES ('agt_pr', ?, 'Maya', 'Counselor', 'active', 0, 24)").bind(bizId),
      env.DB.prepare("INSERT OR REPLACE INTO usage (id, business_id, included_minutes, minutes_used) VALUES ('usg_pr', ?, 100000, 0)").bind(bizId),
    ]);
    token = await signJWT({ sub: userId, phone, business_id: bizId, type: 'access' }, secret, 3600);
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  // ---------------------------------------------------------------- 1. OTP brute force
  describe('1. OTP verification', () => {
    it('concurrent wrong guesses can never exceed 5 attempts, and the code is then locked', async () => {
      const p = '9830011111';
      const otp = await requestOtp(p);
      const wrong = otp === '111111' ? '222222' : '111111';
      const results = await Promise.all(
        Array.from({ length: 12 }, () => post('/auth/register', { phone: p, otp: wrong, business_name: 'Brute' }))
      );
      const codes = await Promise.all(results.map(async (r) => ((await r.json()) as any).code));
      expect(codes.filter((c) => c === 'invalid_otp').length).toBe(5);
      expect(codes.filter((c) => c === 'otp_locked').length).toBe(7);

      const row = await env.DB.prepare('SELECT attempts FROM otp_codes WHERE phone = ?').bind('919830011111').first<any>();
      expect(row.attempts).toBe(5);

      // Even the right code is refused once locked
      const right = await post('/auth/register', { phone: p, otp, business_name: 'Brute' });
      expect(right.status).toBe(429);
    });

    it('a correct code works exactly once', async () => {
      const p = '9830022222';
      const otp = await requestOtp(p);
      const [a, b] = await Promise.all([
        post('/auth/register', { phone: p, otp, business_name: 'Once A' }),
        post('/auth/register', { phone: p, otp, business_name: 'Once B' }),
      ]);
      expect([a.status, b.status].sort()).toEqual([200, 400]);
    });

    it('expired codes are reported as expired, missing codes as invalid', async () => {
      await env.DB.prepare(
        "INSERT OR REPLACE INTO otp_codes (phone, otp_hash, attempts, expires_at) VALUES ('919830033333', 'x', 0, ?)"
      ).bind(new Date(Date.now() - 60_000).toISOString()).run();
      const expired = await post('/auth/login', { phone: '9830033333', otp: '123456' });
      expect(expired.status).toBe(400);
      expect(((await expired.json()) as any).code).toBe('otp_expired');

      const missing = await post('/auth/login', { phone: '9830044444', otp: '123456' });
      expect(((await missing.json()) as any).code).toBe('invalid_otp');
    });

    it('rate-limits login/register per IP in production', async () => {
      const prodEnv = { ...env, ENVIRONMENT: 'production' } as any;
      const ip = { 'cf-connecting-ip': '203.0.113.77' };
      for (let i = 0; i < 20; i++) {
        const r = await post('/auth/login', { phone: '9830055555', otp: '123456' }, ip, prodEnv);
        expect(r.status).toBe(400);
      }
      const limited = await post('/auth/register', { phone: '9830055555', otp: '123456', business_name: 'x' }, ip, prodEnv);
      expect(limited.status).toBe(429);
      expect(limited.headers.get('Retry-After')).toBe('600');
    });
  });

  // ---------------------------------------------------------------- 2. Refresh rotation race
  describe('2. Refresh token rotation', () => {
    it('two concurrent refreshes of one token: exactly one wins, the other is treated as reuse', async () => {
      const p = '9830066666';
      const otp = await requestOtp(p);
      const reg = await post('/auth/register', { phone: p, otp, business_name: 'Race Co' });
      const { refresh_token } = (await reg.json()) as any;

      const [a, b] = await Promise.all([
        post('/auth/refresh', { refresh_token }),
        post('/auth/refresh', { refresh_token }),
      ]);
      expect([a.status, b.status].sort()).toEqual([200, 401]);
      const loser = a.status === 401 ? a : b;
      expect(((await loser.json()) as any).code).toBe('token_reuse_detected');

      // Reuse revokes the whole family, including the token the winner just received
      const live = await env.DB.prepare(
        "SELECT COUNT(*) AS n FROM refresh_tokens_v2 t JOIN users u ON u.id = t.user_id WHERE u.phone = '919830066666' AND t.is_revoked = 0"
      ).first<{ n: number }>();
      expect(live?.n).toBe(0);
    });
  });

  // ---------------------------------------------------------------- 3. Campaign limits
  describe('3. Campaign creation limits and set-based enqueue', () => {
    it(`rejects more than ${MAX_CAMPAIGN_LEADS} leads and start >= end calling hours`, async () => {
      const tooMany = Array.from({ length: MAX_CAMPAIGN_LEADS + 1 }, (_, i) => `l${i}`);
      expect(createCampaignSchema.safeParse({ lead_ids: tooMany }).success).toBe(false);
      expect(createCampaignSchema.safeParse({ calling_hours_start: 18, calling_hours_end: 9 }).success).toBe(false);
      expect(createCampaignSchema.safeParse({ calling_hours_start: 10, calling_hours_end: 10 }).success).toBe(false);
      expect(createCampaignSchema.safeParse({ calling_hours_start: 9, calling_hours_end: 18 }).success).toBe(true);

      const res = await authed('/campaigns', { method: 'POST', body: JSON.stringify({ purpose: 'x', calling_hours_start: 20, calling_hours_end: 8 }) });
      expect(res.status).toBe(400);
      expect(((await res.json()) as any).code).toBe('validation_error');
    });

    it('enqueues many leads with chunked set-based updates and skips non-claimable ones', async () => {
      const { campId, leadIds } = await seedCampaign({ leads: 170 });
      await env.DB.prepare("UPDATE campaign_leads SET status = 'completed' WHERE campaign_id = ? AND lead_id = ?").bind(campId, leadIds[0]).run();
      const sent: any[] = [];
      const fakeEnv = { ...env, CAMPAIGN_QUEUE: { sendBatch: async (m: any[]) => { sent.push(...m); } } } as any;
      const n = await enqueueCampaignJobs(fakeEnv, campId, bizId, leadIds, 'https://api.example.test');
      expect(n).toBe(169);
      expect(sent.length).toBe(169);
      expect(sent[0].body.webhook_base_url).toBe('https://api.example.test');
      const queued = await env.DB.prepare("SELECT COUNT(*) AS n FROM campaign_leads WHERE campaign_id = ? AND status = 'queued'").bind(campId).first<{ n: number }>();
      expect(queued?.n).toBe(169);
      expect(await leadStatus(campId, leadIds[0])).toBe('completed');
    });
  });

  // ---------------------------------------------------------------- 4. Queue retries & DLQ
  describe('4. Queue deferral and dead-letter handling', () => {
    it('concurrency cap acks and re-sends a fresh delayed message instead of retry()', async () => {
      const { campId, leadIds } = await seedCampaign({ leads: 1, leadStatus: 'queued' });
      const busy: D1PreparedStatement[] = [];
      for (let i = 0; i < MAX_CONCURRENT_CALLS_PER_BUSINESS; i++) {
        busy.push(env.DB.prepare(
          "INSERT INTO calls (id, business_id, lead_id, lead_name, lead_phone, status, started_at) VALUES (?, ?, ?, 'x', 'x', 'calling', datetime('now'))"
        ).bind(`call_pr_busy_${campId}_${i}`, bizId, leadIds[0]));
      }
      await env.DB.batch(busy);

      const send = vi.fn(async () => {});
      const ack = vi.fn();
      const retry = vi.fn();
      const body = { campaign_id: campId, lead_id: leadIds[0], business_id: bizId, idempotency_key: 'k', attempts: 0 };
      await handleCampaignQueueBatch({ messages: [{ body, ack, retry }] } as any, { ...env, CAMPAIGN_QUEUE: { send } } as any);

      expect(retry).not.toHaveBeenCalled();
      expect(ack).toHaveBeenCalledTimes(1);
      expect(send).toHaveBeenCalledTimes(1);
      const [sentBody, opts] = (send.mock.calls[0] as any[]);
      expect(sentBody).toEqual(body);
      expect(opts.delaySeconds).toBeGreaterThanOrEqual(15);

      await env.DB.prepare("UPDATE calls SET status = 'completed' WHERE id LIKE ?").bind(`call_pr_busy_${campId}_%`).run();
    });

    it('DLQ consumer marks still-waiting leads failed and completes the campaign', async () => {
      const { campId, leadIds } = await seedCampaign({ leads: 2, leadStatus: 'queued' });
      await env.DB.prepare("UPDATE campaign_leads SET status = 'completed' WHERE campaign_id = ? AND lead_id = ?").bind(campId, leadIds[1]).run();
      const ack = vi.fn();
      const batch: any = {
        queue: 'callpilot-campaign-dlq',
        messages: leadIds.map((lid) => ({
          body: { campaign_id: campId, lead_id: lid, business_id: bizId, idempotency_key: `${campId}:${lid}`, attempts: 0 },
          ack, retry: vi.fn(),
        })),
      };
      await worker.queue(batch, env as any);
      expect(ack).toHaveBeenCalledTimes(2);
      expect(await leadStatus(campId, leadIds[0])).toBe('failed');
      expect(await leadStatus(campId, leadIds[1])).toBe('completed'); // never downgraded
      expect(await campaignStatus(campId)).toBe('completed');
    });

    it('DLQ consumer retries on DB errors and tolerates malformed bodies', async () => {
      const retry = vi.fn();
      const ack = vi.fn();
      const brokenEnv = { DB: { prepare: () => { throw new Error('d1 down'); } } } as any;
      await handleCampaignDlqBatch({ messages: [{ body: { campaign_id: 'c', lead_id: 'l' }, ack, retry }] } as any, brokenEnv);
      expect(retry).toHaveBeenCalledWith({ delaySeconds: 60 });
      await handleCampaignDlqBatch({ messages: [{ body: null, ack, retry }] } as any, env as any);
      expect(ack).toHaveBeenCalledTimes(1);
    });

    it('routes batches by queue name', () => {
      expect(isDeadLetterQueue('callpilot-campaign-dlq')).toBe(true);
      expect(isDeadLetterQueue('callpilot-campaign-dlq-staging')).toBe(true);
      expect(isDeadLetterQueue('callpilot-campaign-dispatch')).toBe(false);
      expect(isDeadLetterQueue(undefined)).toBe(false);
    });
  });

  // ---------------------------------------------------------------- 5. FCM HTTP v1
  describe('5. FCM HTTP v1 delivery', () => {
    async function serviceAccount(email: string) {
      const kp = await crypto.subtle.generateKey(
        { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' },
        true, ['sign', 'verify']
      ) as CryptoKeyPair;
      const der = new Uint8Array(await crypto.subtle.exportKey('pkcs8', kp.privateKey) as ArrayBuffer);
      const b64 = btoa(String.fromCharCode(...der)).match(/.{1,64}/g)!.join('\n');
      return JSON.stringify({
        project_id: 'callpilot-test',
        client_email: email,
        private_key: `-----BEGIN PRIVATE KEY-----\n${b64}\n-----END PRIVATE KEY-----\n`,
      });
    }

    it('mints + caches an OAuth token, sends per device, deletes UNREGISTERED tokens and never logs PII', async () => {
      resetFcmTokenCache();
      const fcmBiz = 'biz_fcm_v1';
      await env.DB.batch([
        env.DB.prepare("INSERT INTO businesses (id, name) VALUES (?, 'FCM')").bind(fcmBiz),
        env.DB.prepare("INSERT INTO devices (id, business_id, fcm_token, platform) VALUES ('dev_v1_ok', ?, 'tok_ok', 'android')").bind(fcmBiz),
        env.DB.prepare("INSERT INTO devices (id, business_id, fcm_token, platform) VALUES ('dev_v1_gone', ?, 'tok_gone', 'android')").bind(fcmBiz),
      ]);
      const calls: { url: string; init: any }[] = [];
      vi.spyOn(globalThis, 'fetch').mockImplementation(async (input: any, init: any) => {
        const url = String(input);
        calls.push({ url, init });
        if (url === 'https://oauth2.googleapis.com/token') {
          return new Response(JSON.stringify({ access_token: 'ya29.test', expires_in: 3600 }), { status: 200 });
        }
        const msg = JSON.parse(init.body).message;
        if (msg.token === 'tok_gone') {
          return new Response(JSON.stringify({ error: { status: 'NOT_FOUND', details: [{ errorCode: 'UNREGISTERED' }] } }), { status: 404 });
        }
        return new Response(JSON.stringify({ name: 'projects/x/messages/1' }), { status: 200 });
      });
      const logSpy = vi.spyOn(console, 'log');
      const fcmEnv = { ...env, FCM_SERVICE_ACCOUNT_JSON: await serviceAccount('fcm-a@callpilot-test.iam.gserviceaccount.com') } as any;
      const payload = { type: 'hot_lead' as const, title: 'Hot Lead Alert', body: 'Rohan Sharma is very interested', route: '/leads/x' };

      const r1 = await sendBusinessPushNotification(fcmEnv, fcmBiz, payload);
      expect(r1.sent).toBe(1);

      const oauth = calls.filter((c) => c.url === 'https://oauth2.googleapis.com/token');
      expect(oauth.length).toBe(1);
      const assertion = new URLSearchParams(oauth[0].init.body).get('assertion')!;
      expect(assertion.split('.').length).toBe(3);
      expect(JSON.parse(atob(assertion.split('.')[0].replace(/-/g, '+').replace(/_/g, '/')))).toEqual({ alg: 'RS256', typ: 'JWT' });

      const sends = calls.filter((c) => c.url.startsWith('https://fcm.googleapis.com/v1/projects/callpilot-test/messages:send'));
      expect(sends.length).toBe(2);
      expect(sends[0].init.headers.Authorization).toBe('Bearer ya29.test');
      expect(sends[0].init.signal).toBeDefined();
      const sentMsg = JSON.parse(sends[0].init.body).message;
      expect(sentMsg.notification.title).toBe('Hot Lead Alert');
      expect(sentMsg.data.route).toBe('/leads/x');

      const gone = await env.DB.prepare("SELECT id FROM devices WHERE fcm_token = 'tok_gone'").first();
      expect(gone).toBeNull();

      // Second send reuses the cached token
      await sendBusinessPushNotification(fcmEnv, fcmBiz, payload);
      expect(calls.filter((c) => c.url === 'https://oauth2.googleapis.com/token').length).toBe(1);

      const logged = logSpy.mock.calls.map((a) => a.join(' ')).join('\n');
      expect(logged).not.toContain('Rohan');
      expect(logged).not.toContain('Hot Lead Alert');
    });

    it('reports failures without deleting tokens and survives OAuth / bad JSON errors', async () => {
      resetFcmTokenCache();
      const fcmBiz = 'biz_fcm_v1_err';
      await env.DB.batch([
        env.DB.prepare("INSERT INTO businesses (id, name) VALUES (?, 'FCM err')").bind(fcmBiz),
        env.DB.prepare("INSERT INTO devices (id, business_id, fcm_token, platform) VALUES ('dev_v1_err', ?, 'tok_err', 'android')").bind(fcmBiz),
      ]);
      const sa = await serviceAccount('fcm-b@callpilot-test.iam.gserviceaccount.com');

      // OAuth failure -> nothing sent
      vi.spyOn(globalThis, 'fetch').mockImplementation(async () => new Response('{"error":"invalid_grant"}', { status: 400 }));
      expect((await sendBusinessPushNotification({ ...env, FCM_SERVICE_ACCOUNT_JSON: sa } as any, fcmBiz,
        { type: 'campaign', title: 't', body: 'b', route: '/' })).sent).toBe(0);
      vi.restoreAllMocks();

      // FCM 500 / network error -> counted as failed, token kept
      let n = 0;
      vi.spyOn(globalThis, 'fetch').mockImplementation(async (input: any) => {
        if (String(input).includes('oauth2')) return new Response(JSON.stringify({ access_token: 'tok' }), { status: 200 });
        if (n++ === 0) return new Response('oops', { status: 500 });
        throw new Error('network');
      });
      const fcmEnv = { ...env, FCM_SERVICE_ACCOUNT_JSON: sa } as any;
      expect((await sendBusinessPushNotification(fcmEnv, fcmBiz, { type: 'campaign', title: 't', body: 'b', route: '/' })).sent).toBe(0);
      expect((await sendBusinessPushNotification(fcmEnv, fcmBiz, { type: 'campaign', title: 't', body: 'b', route: '/' })).sent).toBe(0);
      expect(await env.DB.prepare("SELECT id FROM devices WHERE fcm_token = 'tok_err'").first()).not.toBeNull();

      // Invalid JSON secret
      expect((await sendBusinessPushNotification({ ...env, FCM_SERVICE_ACCOUNT_JSON: '{not json' } as any, fcmBiz,
        { type: 'campaign', title: 't', body: 'b', route: '/' })).sent).toBe(0);
    });
  });

  // ---------------------------------------------------------------- 7/8. Campaign completion
  describe('7/8. Campaign completion paths', () => {
    it('maintenance sweeper completes the campaign when it terminally fails the last lead', async () => {
      const { campId, leadIds } = await seedCampaign({ leads: 1, leadStatus: 'calling' });
      const callId = `call_pr_sweep_${campId}`;
      await env.DB.batch([
        env.DB.prepare("UPDATE campaign_leads SET attempts = 3, call_id = ? WHERE campaign_id = ?").bind(callId, campId),
        env.DB.prepare(
          "INSERT INTO calls (id, business_id, lead_id, lead_name, lead_phone, campaign_id, status, started_at) VALUES (?, ?, ?, 'x', 'x', ?, 'calling', datetime('now', '-2 hours'))"
        ).bind(callId, bizId, leadIds[0], campId),
      ]);
      await runMaintenance(env as any);
      expect(await leadStatus(campId, leadIds[0])).toBe('failed');
      expect(await campaignStatus(campId)).toBe('completed');
    });

    it('starting a campaign whose leads are all skipped completes it immediately', async () => {
      const { campId, leadIds } = await seedCampaign({ leads: 2, campStatus: 'draft' });
      await env.DB.prepare(`UPDATE leads SET do_not_call = 1 WHERE id IN (?, ?)`).bind(leadIds[0], leadIds[1]).run();
      const res = await authed(`/campaigns/${campId}/start`, { method: 'POST', body: '{}' });
      expect(res.status).toBe(200);
      expect(((await res.json()) as any).status).toBe('completed');
    });

    it('a terminal dial failure on the last lead completes the campaign', async () => {
      const { campId, leadIds } = await seedCampaign({ leads: 1, leadStatus: 'queued' });
      vi.spyOn(globalThis, 'fetch').mockImplementation(async () => new Response('bad number', { status: 400 }));
      const liveEnv = { ...env, SARVAM_API_KEY: 'live-key', SARVAM_ORG_ID: 'o', SARVAM_WORKSPACE_ID: 'w', SARVAM_ADMISSIONS_APP_ID: 'a' } as any;
      const r = await processCampaignJob(liveEnv, { campaign_id: campId, lead_id: leadIds[0], business_id: bizId, idempotency_key: 'k', attempts: 0 });
      expect(r.reason).toContain('dial_failed_terminal');
      expect(await campaignStatus(campId)).toBe('completed');
    });

    it('a stale queued job for an already completed lead is acked without dialing', async () => {
      const { campId, leadIds } = await seedCampaign({ leads: 2, leadStatus: 'completed' });
      const ack = vi.fn();
      const retry = vi.fn();
      const fetchSpy = vi.spyOn(globalThis, 'fetch');
      await handleCampaignQueueBatch({ messages: [{ body: { campaign_id: campId, lead_id: leadIds[0], business_id: bizId, idempotency_key: 'k', attempts: 0 }, ack, retry }] } as any, env as any);
      expect(ack).toHaveBeenCalledTimes(1);
      expect(retry).not.toHaveBeenCalled();
      expect(fetchSpy).not.toHaveBeenCalled();
    });

    it('maybeCompleteCampaign leaves campaigns with outstanding work alone', async () => {
      const { campId } = await seedCampaign({ leads: 1, leadStatus: 'retry_pending' });
      expect(await maybeCompleteCampaign(env.DB, campId)).toBe(false);
      expect(await campaignStatus(campId)).toBe('running');
    });
  });

  // ---------------------------------------------------------------- 9. Campaign webhook_config
  describe('9. Campaign dials include webhook_config', () => {
    it('passes the same webhook config shape as the manual dial', async () => {
      expect(sarvamWebhookConfig('https://api.x.test/')).toEqual({ webhook_url: 'https://api.x.test/webhooks/sarvam' });
      expect(sarvamWebhookConfig(undefined)).toBeUndefined();

      const { campId, leadIds } = await seedCampaign({ leads: 1, leadStatus: 'queued' });
      let dialBody: any = null;
      vi.spyOn(globalThis, 'fetch').mockImplementation(async (_u: any, init: any) => {
        dialBody = JSON.parse(init.body);
        return new Response(JSON.stringify({ interaction_id: `int_${campId}` }), { status: 200 });
      });
      const liveEnv = { ...env, SARVAM_API_KEY: 'live-key', SARVAM_ORG_ID: 'o', SARVAM_WORKSPACE_ID: 'w', SARVAM_ADMISSIONS_APP_ID: 'a' } as any;
      const r = await processCampaignJob(liveEnv, {
        campaign_id: campId, lead_id: leadIds[0], business_id: bizId, idempotency_key: 'k', attempts: 0,
        webhook_base_url: 'https://worker.example.test',
      });
      expect(r.success).toBe(true);
      expect(dialBody.webhook_config).toEqual({ webhook_url: 'https://worker.example.test/webhooks/sarvam' });
      await env.DB.prepare("UPDATE calls SET status = 'completed' WHERE campaign_id = ?").bind(campId).run();
    });
  });

  // ---------------------------------------------------------------- 10. Non-terminal webhooks
  describe('10. Webhook status whitelist', () => {
    it('acknowledges intermediate statuses without side effects', async () => {
      const callId = 'call_pr_ringing';
      await env.DB.batch([
        env.DB.prepare("INSERT INTO leads (id, business_id, name, phone) VALUES ('lead_pr_ring', ?, 'Ring', '919811100009')").bind(bizId),
        env.DB.prepare(
          "INSERT INTO calls (id, business_id, lead_id, lead_name, lead_phone, status, started_at) VALUES (?, ?, 'lead_pr_ring', 'x', 'x', 'calling', datetime('now'))"
        ).bind(callId, bizId),
      ]);
      const body = JSON.stringify({ call_id: callId, status: 'ringing' });
      const res = await post('/webhooks/sarvam', JSON.parse(body), { 'X-Sarvam-Signature': await hmacHex(body, env.SARVAM_WEBHOOK_SECRET) });
      expect(res.status).toBe(200);
      expect(((await res.json()) as any).ignored).toBe(true);
      const call = await env.DB.prepare('SELECT status FROM calls WHERE id = ?').bind(callId).first<any>();
      expect(call.status).toBe('calling');
      const ev = await env.DB.prepare('SELECT COUNT(*) AS n FROM webhook_events WHERE event_key LIKE ?').bind(`sarvam:${callId}:%`).first<{ n: number }>();
      expect(ev?.n).toBe(0);

      // A terminal failure status is still processed
      const busyBody = JSON.stringify({ call_id: callId, status: 'busy' });
      const busy = await post('/webhooks/sarvam', JSON.parse(busyBody), { 'X-Sarvam-Signature': await hmacHex(busyBody, env.SARVAM_WEBHOOK_SECRET) });
      expect(busy.status).toBe(200);
      expect((await env.DB.prepare('SELECT status FROM calls WHERE id = ?').bind(callId).first<any>()).status).toBe('busy');
    });
  });

  // ---------------------------------------------------------------- 12. Knowledge limits
  describe('12. Knowledge ingest limits', () => {
    it('validates title, content and type', async () => {
      const longTitle = await authed('/knowledge', { method: 'POST', body: JSON.stringify({ type: 'text', title: 'x'.repeat(201), content: 'hi' }) });
      expect(longTitle.status).toBe(400);
      const badType = await authed('/knowledge', { method: 'POST', body: JSON.stringify({ type: 'exe', content: 'hi' }) });
      expect(badType.status).toBe(400);
      const huge = await authed('/knowledge', { method: 'POST', body: JSON.stringify({ type: 'text', content: 'a'.repeat(200_001) }) });
      expect(huge.status).toBe(400);

      const form = new FormData();
      form.append('type', 'nonsense');
      form.append('content', 'hello');
      const badForm = await authed('/knowledge', { method: 'POST', body: form });
      expect(badForm.status).toBe(400);
    });

    it(`rate-limits ingestion to ${KNOWLEDGE_INGEST_LIMIT_PER_HOUR}/hour per business`, async () => {
      const kBiz = 'biz_pr_kn_limit';
      const kUser = 'usr_pr_kn_limit';
      await env.DB.batch([
        env.DB.prepare("INSERT INTO businesses (id, name) VALUES (?, 'K')").bind(kBiz),
        env.DB.prepare("INSERT INTO users (id, phone, business_id) VALUES (?, '919830088888', ?)").bind(kUser, kBiz),
      ]);
      // Pre-fill the bucket instead of ingesting 30 documents
      const fill: D1PreparedStatement[] = [];
      for (let i = 0; i < KNOWLEDGE_INGEST_LIMIT_PER_HOUR; i++) {
        fill.push(env.DB.prepare('INSERT INTO rate_limits (id, bucket) VALUES (?, ?)').bind(`rl_kn_${i}`, `knowledge:biz:${kBiz}`));
      }
      await env.DB.batch(fill);
      const kToken = await signJWT({ sub: kUser, phone: '919830088888', business_id: kBiz, type: 'access' }, secret, 3600);
      const res = await authed('/knowledge', { method: 'POST', body: JSON.stringify({ type: 'text', content: 'hi' }) }, kToken);
      expect(res.status).toBe(429);
    });

    it('only fetches public https URLs', () => {
      expect(assertSafePublicUrl('https://example.com/about').hostname).toBe('example.com');
      for (const bad of [
        'http://example.com', 'ftp://example.com', 'https://localhost/x', 'https://app.localhost',
        'https://127.0.0.1/', 'https://10.1.2.3/', 'https://169.254.169.254/latest', 'https://192.168.1.1',
        'https://172.20.0.1', 'https://[::1]/', 'https://printer.local', 'https://user:pw@example.com',
        'https://example.com:8443/', 'https://intranet', 'not a url',
      ]) {
        expect(() => assertSafePublicUrl(bad), bad).toThrow();
      }
    });

    it('re-validates redirects, caps redirects and response size', async () => {
      vi.spyOn(globalThis, 'fetch').mockImplementation(async (input: any) => {
        const u = String(input);
        if (u === 'https://good.example/') return new Response(null, { status: 301, headers: { Location: '/page' } });
        if (u === 'https://good.example/page') return new Response('<p>Hello world</p>', { status: 200 });
        if (u === 'https://evil.example/') return new Response(null, { status: 302, headers: { Location: 'https://169.254.169.254/' } });
        if (u.startsWith('https://loop.example/')) return new Response(null, { status: 302, headers: { Location: `https://loop.example/${Math.random()}` } });
        if (u === 'https://big.example/') return new Response('x'.repeat(WEBSITE_MAX_BYTES + 1), { status: 200 });
        if (u === 'https://declared.example/') return new Response('small', { status: 200, headers: { 'Content-Length': String(WEBSITE_MAX_BYTES + 1) } });
        return new Response('nope', { status: 500 });
      });
      expect(await fetchPublicPage('https://good.example/')).toContain('Hello world');
      await expect(fetchPublicPage('https://evil.example/')).rejects.toThrow('not allowed');
      await expect(fetchPublicPage('https://loop.example/')).rejects.toThrow('redirects');
      await expect(fetchPublicPage('https://big.example/')).rejects.toThrow('too large');
      await expect(fetchPublicPage('https://declared.example/')).rejects.toThrow('too large');
      await expect(fetchPublicPage('https://down.example/')).rejects.toThrow('HTTP 500');

      const srcId = 'kn_pr_web';
      await env.DB.prepare("INSERT INTO knowledge_sources (id, business_id, type, title, status) VALUES (?, ?, 'website', 'Web', 'processing')").bind(srcId, bizId).run();
      await ingestKnowledge(env as any, bizId, { id: srcId, type: 'website', url: 'https://good.example/' });
      expect((await env.DB.prepare('SELECT status FROM knowledge_sources WHERE id = ?').bind(srcId).first<any>()).status).toBe('ready');
    });
  });

  // ---------------------------------------------------------------- 13. Limits
  describe('13. List limits', () => {
    it('parses limit params safely', () => {
      expect(parseLimit(undefined, 20, 100)).toBe(20);
      expect(parseLimit('abc', 20, 100)).toBe(20);
      expect(parseLimit('0', 20, 100)).toBe(1);
      expect(parseLimit('5000', 20, 100)).toBe(100);
      expect(parseLimit('7', 200, 200)).toBe(7);
    });

    it('leads/calls tolerate a non-numeric limit; list endpoints honour ?limit', async () => {
      expect((await authed('/leads?limit=abc')).status).toBe(200);
      expect((await authed('/calls?limit=NaN')).status).toBe(200);
      const camps = (await (await authed('/campaigns?limit=1')).json()) as any[];
      expect(camps.length).toBeLessThanOrEqual(1);
      expect((await authed('/followups?limit=1')).status).toBe(200);
      expect((await authed('/callbacks?limit=1')).status).toBe(200);
      expect((await authed('/knowledge?limit=1')).status).toBe(200);
    });
  });

  // ---------------------------------------------------------------- 14. voiceApp onError
  describe('14. Voice proxy errors use the JSON error shape', () => {
    it('returns server_error JSON with a request id', async () => {
      const res = await app.fetch(new Request('http://localhost/voice/sarvam-proxy/orgs/x', {
        headers: { Authorization: 'Bearer abc', 'X-Request-Id': 'req-pr-14' },
      }), { ...env, JWT_SIGNING_KEY: '' } as any);
      expect(res.status).toBe(500);
      const body = (await res.json()) as any;
      expect(body.code).toBe('server_error');
      expect(body.request_id).toBe('req-pr-14');
    });
  });

  // ---------------------------------------------------------------- 16. SMS failures
  describe('16. SMS send failures', () => {
    it('returns 502 and drops the code when the provider fails or times out', async () => {
      const smsEnv = { ...env, MSG91_AUTH_KEY: 'k' } as any;
      vi.spyOn(globalThis, 'fetch').mockImplementationOnce(async (_u: any, init: any) => {
        expect(init.signal).toBeDefined();
        return new Response('err', { status: 500 });
      });
      const res = await post('/auth/otp/request', { phone: '9830099991' }, {}, smsEnv);
      expect(res.status).toBe(502);
      const body = (await res.json()) as any;
      expect(body.message).toBe("Couldn't send the code. Try again.");
      expect(body.error).toBe('sms_send_failed');
      expect(await env.DB.prepare("SELECT phone FROM otp_codes WHERE phone = '919830099991'").first()).toBeNull();

      vi.spyOn(globalThis, 'fetch').mockImplementationOnce(async () => { throw new Error('timeout'); });
      expect((await post('/auth/otp/request', { phone: '9830099992' }, {}, smsEnv)).status).toBe(502);
    });
  });

  // ---------------------------------------------------------------- 17. Proxy timeout
  describe('17. Voice proxy timeout', () => {
    it('forwards non-upgrade requests with an abort signal', async () => {
      const sessionToken = await signJWT({ sub: userId, phone, business_id: bizId, type: 'session' }, secret, 3600);
      let seenSignal: any;
      vi.spyOn(globalThis, 'fetch').mockImplementationOnce(async (_u: any, init: any) => {
        seenSignal = init.signal;
        return new Response('{}', { status: 200 });
      });
      const proxyEnv = { ...env, SARVAM_ORG_ID: 'org1', SARVAM_WORKSPACE_ID: 'ws1', SARVAM_ADMISSIONS_APP_ID: 'app1' } as any;
      const res = await app.fetch(new Request('http://localhost/voice/sarvam-proxy/orgs/org1/workspaces/ws1/apps/app1/x', {
        headers: { Authorization: `Bearer ${sessionToken}` },
      }), proxyEnv);
      expect(res.status).toBe(200);
      expect(seenSignal).toBeInstanceOf(AbortSignal);
    });
  });

  // ---------------------------------------------------------------- 18/21/22. Headers, logging, health
  describe('18/21/22. Security headers, request logging, deep health', () => {
    it('sets security headers and serves R2 downloads as attachments', async () => {
      const health = await app.fetch(new Request('http://localhost/health'), env);
      expect(health.headers.get('X-Content-Type-Options')).toBe('nosniff');
      expect(health.headers.get('X-Frame-Options')).toBeTruthy();

      const key = `${bizId}/doc-pr.txt`;
      await env.KNOWLEDGE_BUCKET!.put(key, '<script>alert(1)</script>', { httpMetadata: { contentType: 'text/html' } });
      const dl = await authed(`/r2/${key}`);
      expect(dl.status).toBe(200);
      expect(dl.headers.get('X-Content-Type-Options')).toBe('nosniff');
      expect(dl.headers.get('Content-Disposition')).toBe('attachment; filename="doc-pr.txt"');
      await dl.text();
    });

    it('never logs query strings', async () => {
      const spy = vi.spyOn(console, 'log');
      await authed('/leads?q=9876543210');
      const lines = spy.mock.calls.map((a) => a.join(' ')).filter((l) => l.includes('"request"'));
      expect(lines.some((l) => l.includes('"path":"/leads"'))).toBe(true);
      expect(lines.join('\n')).not.toContain('9876543210');
    });

    it('compares the deep health key in constant time and still authorises correctly', async () => {
      expect(timingSafeEqual('abc', 'abc')).toBe(true);
      expect(timingSafeEqual('abc', 'abd')).toBe(false);
      expect(timingSafeEqual('abc', 'abcd')).toBe(false);
      const hEnv = { ...env, HEALTH_CHECK_SECRET: 'health-secret-1' } as any;
      expect((await app.fetch(new Request('http://localhost/health/deep', { headers: { 'x-health-key': 'health-secret-2' } }), hEnv)).status).toBe(401);
      expect([200, 503]).toContain((await app.fetch(new Request('http://localhost/health/deep', { headers: { 'x-health-key': 'health-secret-1' } }), hEnv)).status);
    });
  });

  // ---------------------------------------------------------------- 19. Account deletion
  describe('19. Account deletion and maintenance pruning', () => {
    it('removes push/rate-limit/otp rows for the deleted account', async () => {
      const dBiz = 'biz_pr_del';
      const dUser = 'usr_pr_del';
      const dPhone = '919830012121';
      await env.DB.batch([
        env.DB.prepare("INSERT INTO businesses (id, name) VALUES (?, 'Del')").bind(dBiz),
        env.DB.prepare('INSERT INTO users (id, phone, business_id) VALUES (?, ?, ?)').bind(dUser, dPhone, dBiz),
        env.DB.prepare("INSERT INTO push_rate_limits (id, business_id, type) VALUES ('prl_pr_del', ?, 'hot_lead')").bind(dBiz),
        env.DB.prepare('INSERT INTO rate_limits (id, bucket) VALUES (?, ?)').bind('rl_pr_del', `chat:user:${dUser}`),
        env.DB.prepare("INSERT INTO otp_codes (phone, otp_hash, attempts, expires_at) VALUES (?, 'h', 0, '2099-01-01T00:00:00.000Z')").bind(dPhone),
        env.DB.prepare("INSERT INTO otp_rate_limits (id, phone, ip) VALUES ('orl_pr_del', ?, '1.2.3.4')").bind(dPhone),
      ]);
      const dToken = await signJWT({ sub: dUser, phone: dPhone, business_id: dBiz, type: 'access' }, secret, 3600);
      const res = await authed('/auth/account', { method: 'DELETE' }, dToken);
      expect(res.status).toBe(200);
      for (const [sql, arg] of [
        ['SELECT 1 FROM push_rate_limits WHERE business_id = ?', dBiz],
        ['SELECT 1 FROM rate_limits WHERE bucket = ?', `chat:user:${dUser}`],
        ['SELECT 1 FROM otp_codes WHERE phone = ?', dPhone],
        ['SELECT 1 FROM otp_rate_limits WHERE phone = ?', dPhone],
      ] as const) {
        expect(await env.DB.prepare(sql).bind(arg).first(), sql).toBeNull();
      }
      // The deleted account's still-valid token no longer works
      expect((await authed('/business', {}, dToken)).status).toBe(401);
    });

    it('maintenance prunes push_rate_limits older than a day', async () => {
      await env.DB.batch([
        env.DB.prepare("INSERT INTO push_rate_limits (id, business_id, type, created_at) VALUES ('prl_old', ?, 'x', datetime('now', '-2 days'))").bind(bizId),
        env.DB.prepare("INSERT INTO push_rate_limits (id, business_id, type, created_at) VALUES ('prl_new', ?, 'x', datetime('now'))").bind(bizId),
      ]);
      await runMaintenance(env as any);
      expect(await env.DB.prepare("SELECT 1 FROM push_rate_limits WHERE id = 'prl_old'").first()).toBeNull();
      expect(await env.DB.prepare("SELECT 1 FROM push_rate_limits WHERE id = 'prl_new'").first()).not.toBeNull();
    });
  });

  // ---------------------------------------------------------------- 20. Unique races
  describe('20. Lead phone uniqueness', () => {
    it('PATCH to another lead\'s phone returns 409 JSON', async () => {
      await env.DB.batch([
        env.DB.prepare("INSERT INTO leads (id, business_id, name, phone) VALUES ('lead_pr_u1', ?, 'U1', '919811100001')").bind(bizId),
        env.DB.prepare("INSERT INTO leads (id, business_id, name, phone) VALUES ('lead_pr_u2', ?, 'U2', '919811100002')").bind(bizId),
      ]);
      const res = await authed('/leads/lead_pr_u2', { method: 'PATCH', body: JSON.stringify({ phone: '9811100001' }) });
      expect(res.status).toBe(409);
      expect(((await res.json()) as any).code).toBe('lead_phone_exists');
    });

    it('concurrent creates of the same phone: one succeeds, the other gets 409', async () => {
      const mk = () => authed('/leads', { method: 'POST', body: JSON.stringify({ name: 'Dup', phone: '9811100003' }) });
      const [a, b] = await Promise.all([mk(), mk()]);
      expect([a.status, b.status].sort()).toEqual([200, 409]);
    });

    it('concurrent imports of the same phone never fail and count it once', async () => {
      const mk = () => authed('/leads/import', { method: 'POST', body: JSON.stringify({ leads: [{ name: 'Imp', phone: '9811100004' }] }) });
      const [a, b] = await Promise.all([mk(), mk()]);
      expect(a.status).toBe(200);
      expect(b.status).toBe(200);
      const ja = (await a.json()) as any;
      const jb = (await b.json()) as any;
      expect(ja.imported + jb.imported).toBe(1);
      expect(ja.skipped + jb.skipped).toBe(1);
    });
  });
});
