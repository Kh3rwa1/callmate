import { describe, it, expect, beforeAll, afterEach, vi } from 'vitest';
import { env } from 'cloudflare:test';
import { migrateTestDb } from './setup-db';
import app from '../src/index';
import { signJWT } from '../src/auth';
import { isMockSarvam } from '../src/utils/secrets';
import { hitRateLimit } from '../src/utils/rate_limit';
import { claimPushSlot } from '../src/services/fcm';

const secret = 'test-jwt-signing-secret-key-32chars-min-length';
const bizId = 'biz_quality';
const userId = 'usr_quality';
const phone = '919830099999';

const prodEnv = {
  ...env,
  ENVIRONMENT: 'production',
  SARVAM_API_KEY: 'sk_test_looks_like_a_placeholder',
  SARVAM_ORG_ID: 'org_q',
  SARVAM_WORKSPACE_ID: 'ws_q',
  SARVAM_ADMISSIONS_APP_ID: 'app_q',
} as any;

let token: string;

const callLead = (leadId: string, targetEnv: any = env) =>
  app.fetch(
    new Request(`http://localhost/leads/${leadId}/call`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    }),
    targetEnv
  );

let leadSeq = 0;
async function seedLead(id: string, extra: { do_not_call?: number; consent?: string } = {}) {
  const leadPhone = `9198000${String(10000 + ++leadSeq)}`;
  await env.DB.prepare(
    `INSERT INTO leads (id, business_id, name, phone, status, consent, do_not_call)
     VALUES (?, ?, 'Quality Lead', ?, 'new', ?, ?)`
  ).bind(id, bizId, leadPhone, extra.consent ?? 'explicit', extra.do_not_call ?? 0).run();
}

async function setAgentHours(start: number, end: number) {
  await env.DB.prepare('UPDATE agents SET calling_hours_start = ?, calling_hours_end = ? WHERE business_id = ?')
    .bind(start, end, bizId).run();
}

describe('Quality hardening regressions', () => {
  beforeAll(async () => {
    await migrateTestDb();
    await env.DB.batch([
      env.DB.prepare("INSERT OR REPLACE INTO businesses (id, name, category) VALUES (?, 'Quality Academy', 'education')").bind(bizId),
      env.DB.prepare('INSERT OR REPLACE INTO users (id, phone, business_id) VALUES (?, ?, ?)').bind(userId, phone, bizId),
      env.DB.prepare("INSERT OR REPLACE INTO agents (id, business_id, name, role, status, calling_hours_start, calling_hours_end) VALUES ('agt_q', ?, 'Maya', 'Counselor', 'active', 0, 24)").bind(bizId),
      env.DB.prepare("INSERT OR REPLACE INTO usage (id, business_id, included_minutes, minutes_used) VALUES ('usg_q', ?, 1000, 0)").bind(bizId),
    ]);
    token = await signJWT({ sub: userId, phone, business_id: bizId, type: 'access' }, secret, 3600);
  });

  afterEach(async () => {
    vi.restoreAllMocks();
    await setAgentHours(0, 24);
    await env.DB.prepare("UPDATE usage SET minutes_used = 0 WHERE business_id = ?").bind(bizId).run();
    await env.DB.prepare("UPDATE calls SET status = 'completed' WHERE business_id = ? AND status = 'calling'").bind(bizId).run();
  });

  describe('isMockSarvam', () => {
    it('never simulates dialing outside development/test, whatever the key looks like', () => {
      expect(isMockSarvam({ ENVIRONMENT: 'production', SARVAM_API_KEY: 'sk_test_abc' })).toBe(false);
      expect(isMockSarvam({ ENVIRONMENT: 'production', SARVAM_API_KEY: 'mock-abc' })).toBe(false);
      expect(isMockSarvam({ ENVIRONMENT: 'production' })).toBe(false);
      expect(isMockSarvam({ SARVAM_API_KEY: 'sk_test_abc' })).toBe(false);
    });

    it('simulates dialing in development/test with no key or a placeholder key', () => {
      expect(isMockSarvam({ ENVIRONMENT: 'development' })).toBe(true);
      expect(isMockSarvam({ ENVIRONMENT: 'test', SARVAM_API_KEY: 'sk_test_abc' })).toBe(true);
      expect(isMockSarvam({ ENVIRONMENT: 'development', SARVAM_API_KEY: 'mock-x' })).toBe(true);
      expect(isMockSarvam({ ENVIRONMENT: 'development', SARVAM_API_KEY: 'sk_live_real' })).toBe(false);
    });
  });

  describe('POST /leads/:id/call guardrails', () => {
    it('refuses to call a lead who opted out', async () => {
      await seedLead('lead_q_dnc', { do_not_call: 1, consent: 'opt_out' });
      const res = await callLead('lead_q_dnc');
      expect(res.status).toBe(409);
      expect(((await res.json()) as any).code).toBe('do_not_call');
      const n = await env.DB.prepare('SELECT COUNT(*) AS c FROM calls WHERE lead_id = ?').bind('lead_q_dnc').first<{ c: number }>();
      expect(n?.c).toBe(0);
    });

    it('refuses to call outside the agent calling hours', async () => {
      await seedLead('lead_q_hours');
      await setAgentHours(0, 0); // empty window: always outside hours
      const res = await callLead('lead_q_hours');
      expect(res.status).toBe(409);
      expect(((await res.json()) as any).code).toBe('outside_hours');
    });

    it('refuses a 4th call to the same lead within a day', async () => {
      await seedLead('lead_q_daily');
      for (let i = 0; i < 3; i++) {
        await env.DB.prepare(
          `INSERT INTO calls (id, business_id, lead_id, lead_name, lead_phone, status, started_at)
           VALUES (?, ?, 'lead_q_daily', 'Quality Lead', '919800012345', 'completed', datetime('now', '-1 hour'))`
        ).bind(`call_q_daily_${i}`, bizId).run();
      }
      const res = await callLead('lead_q_daily');
      expect(res.status).toBe(409);
      expect(((await res.json()) as any).code).toBe('max_daily_attempts');
    });

    it('refuses when the business has no minutes left', async () => {
      await seedLead('lead_q_minutes');
      await env.DB.prepare('UPDATE usage SET minutes_used = included_minutes WHERE business_id = ?').bind(bizId).run();
      const res = await callLead('lead_q_minutes');
      expect(res.status).toBe(402);
      expect(((await res.json()) as any).code).toBe('exhausted_minutes');
    });

    it('refuses when the business is at its concurrent call cap', async () => {
      await seedLead('lead_q_conc');
      await seedLead('lead_q_busy');
      for (let i = 0; i < 5; i++) {
        await env.DB.prepare(
          `INSERT INTO calls (id, business_id, lead_id, lead_name, lead_phone, status, started_at)
           VALUES (?, ?, 'lead_q_busy', 'Busy Lead', '919800000000', 'calling', datetime('now'))`
        ).bind(`call_q_conc_${i}`, bizId).run();
      }
      const res = await callLead('lead_q_conc');
      expect(res.status).toBe(429);
      expect(((await res.json()) as any).code).toBe('concurrency_limit');
    });

    it('in production a placeholder-looking key still dials for real, and a failed dial is recorded, not hidden', async () => {
      await seedLead('lead_q_fail');
      const fetchSpy = vi.spyOn(globalThis, 'fetch').mockImplementationOnce(
        async () => new Response(JSON.stringify({ error: 'bad number' }), { status: 400 })
      );

      const res = await callLead('lead_q_fail', prodEnv);
      expect(fetchSpy).toHaveBeenCalledTimes(1);
      expect(res.status).toBe(502);
      const body = (await res.json()) as any;
      expect(body.code).toBe('dial_failed');
      expect(JSON.stringify(body)).not.toContain('bad number');

      const call = await env.DB.prepare('SELECT status, failure_reason FROM calls WHERE lead_id = ?').bind('lead_q_fail').first<any>();
      expect(call.status).toBe('failed');
      expect(call.failure_reason).toBe('sarvam_http_400: {"error":"bad number"}');
      const lead = await env.DB.prepare('SELECT status FROM leads WHERE id = ?').bind('lead_q_fail').first<any>();
      expect(lead.status).not.toBe('calling');
    });

    it("a 422 records Sarvam's validation detail without echoing the input", async () => {
      await seedLead('lead_q_422');
      vi.spyOn(globalThis, 'fetch').mockImplementationOnce(async () => new Response(JSON.stringify({
        detail: [{ loc: ['body', 'user_config', 'user_phone_number'], msg: 'invalid number', type: 'value_error', input: '+919999999999' }],
      }), { status: 422 }));

      const res = await callLead('lead_q_422', prodEnv);
      expect(res.status).toBe(502);
      const call = await env.DB.prepare('SELECT failure_reason FROM calls WHERE lead_id = ?').bind('lead_q_422').first<any>();
      expect(call.failure_reason).toBe('sarvam_http_422: body.user_config.user_phone_number: invalid number');
      expect(call.failure_reason).not.toContain('9999');
    });

    it('dials the provider rejected do not use up the 3-per-day cap', async () => {
      await seedLead('lead_q_rejected');
      for (let i = 0; i < 3; i++) {
        await env.DB.prepare(
          `INSERT INTO calls (id, business_id, lead_id, lead_name, lead_phone, status, failure_reason, started_at)
           VALUES (?, ?, 'lead_q_rejected', 'R', '919800000001', 'failed', 'sarvam_http_422', datetime('now'))`
        ).bind(`call_q_rej_${i}`, bizId).run();
      }
      vi.spyOn(globalThis, 'fetch').mockImplementationOnce(async () => new Response(JSON.stringify({ attempt_id: 'att_1' }), { status: 200 }));
      const res = await callLead('lead_q_rejected', prodEnv);
      expect(res.status).toBe(200);
    });

    it('a transient dial failure returns 503 so the client can retry', async () => {
      await seedLead('lead_q_503');
      vi.spyOn(globalThis, 'fetch').mockImplementationOnce(async () => new Response('busy', { status: 503 }));
      const res = await callLead('lead_q_503', prodEnv);
      expect(res.status).toBe(503);
    });

    it('a successful dial stores the interaction id and does not leak the raw provider response', async () => {
      await seedLead('lead_q_ok');
      vi.spyOn(globalThis, 'fetch').mockImplementationOnce(
        async () => new Response(JSON.stringify({ interaction_id: 'int_q_1', internal: 'secret-ish' }), { status: 200 })
      );
      const res = await callLead('lead_q_ok', prodEnv);
      expect(res.status).toBe(200);
      const body = (await res.json()) as any;
      expect(body.sarvam_dispatched).toBe(true);
      expect(body.sarvam_response).toBeUndefined();
      expect(JSON.stringify(body)).not.toContain('secret-ish');

      const call = await env.DB.prepare('SELECT interaction_id, status FROM calls WHERE lead_id = ?').bind('lead_q_ok').first<any>();
      expect(call.interaction_id).toBe('int_q_1');
      expect(call.status).toBe('calling');
      const lead = await env.DB.prepare('SELECT status FROM leads WHERE id = ?').bind('lead_q_ok').first<any>();
      expect(lead.status).toBe('calling');
    });
  });

  describe('Atomic rate limits under concurrency', () => {
    it('hitRateLimit admits exactly `limit` of many simultaneous hits', async () => {
      const bucket = `q_conc_${Date.now()}`;
      const results = await Promise.all(Array.from({ length: 10 }, () => hitRateLimit(env.DB, bucket, 3, 60)));
      expect(results.filter((r) => r.allowed)).toHaveLength(3);
      expect(results.filter((r) => !r.allowed).every((r) => r.retryAfter === 60)).toBe(true);
    });

    it('OTP requests for one phone admit exactly 3 even when fired at once', async () => {
      const otpPhone = '9830077777';
      const responses = await Promise.all(
        Array.from({ length: 6 }, () =>
          app.fetch(
            new Request('http://localhost/auth/otp/request', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json', 'cf-connecting-ip': '10.9.9.9' },
              body: JSON.stringify({ phone: otpPhone }),
            }),
            env
          )
        )
      );
      const statuses = responses.map((r) => r.status);
      expect(statuses.filter((s) => s === 200)).toHaveLength(3);
      expect(statuses.filter((s) => s === 429)).toHaveLength(3);
    });

    it('OTP per-IP limit reports the network message', async () => {
      const prodLike = { ...env, ENVIRONMENT: 'production', MSG91_AUTH_KEY: 'x' } as any;
      vi.spyOn(globalThis, 'fetch').mockImplementation(async () => new Response('{}', { status: 200 }));
      const ip = '10.8.8.8';
      let last: Response | null = null;
      for (let i = 0; i < 11; i++) {
        last = await app.fetch(
          new Request('http://localhost/auth/otp/request', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'cf-connecting-ip': ip },
            body: JSON.stringify({ phone: `98301${String(10000 + i)}` }),
          }),
          prodLike
        );
      }
      expect(last!.status).toBe(429);
      expect(((await last!.json()) as any).message).toContain('network');
    });

    it('claimPushSlot lets exactly one of many simultaneous follow-up pushes through', async () => {
      const biz = `biz_push_${Date.now()}`;
      const results = await Promise.all(Array.from({ length: 5 }, () => claimPushSlot(env.DB, biz, 'follow_up_ready', 600)));
      expect(results.filter(Boolean)).toHaveLength(1);
      expect(await claimPushSlot(env.DB, biz, 'follow_up_ready', 600)).toBe(false);
      expect(await claimPushSlot(env.DB, biz, 'other_type', 600)).toBe(true);
    });

    it('voice proxy admits exactly the remaining budget under concurrency', async () => {
      const sessionToken = await signJWT({ sub: userId, phone, business_id: bizId, type: 'session' }, secret, 3600);
      for (let i = 0; i < 58; i++) {
        await env.DB.prepare("INSERT INTO voice_proxy_rate_limits (id, business_id, created_at) VALUES (?, ?, datetime('now'))")
          .bind(`vprl_q_${i}`, bizId).run();
      }
      vi.spyOn(globalThis, 'fetch').mockImplementation(async () => new Response('{}', { status: 200 }));
      const responses = await Promise.all(
        Array.from({ length: 5 }, () =>
          app.fetch(
            new Request('http://localhost/voice/sarvam-proxy/orgs/org_q/workspaces/ws_q/apps/app_q/ping', {
              headers: { Authorization: `Bearer ${sessionToken}` },
            }),
            prodEnv
          )
        )
      );
      const statuses = responses.map((r) => r.status);
      expect(statuses.filter((s) => s === 429)).toHaveLength(3);
      expect(statuses.filter((s) => s !== 429)).toHaveLength(2);
    });
  });

  describe('Agent calling hours', () => {
    const patchAgent = (body: unknown) =>
      app.fetch(
        new Request('http://localhost/agent', {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
          body: JSON.stringify(body),
        }),
        env
      );

    it('accepts 21 as an exclusive end hour (TRAI: calls until 21:00)', async () => {
      const res = await patchAgent({ calling_hours_start: 9, calling_hours_end: 21 });
      expect(res.status).toBe(200);
      const row = await env.DB.prepare('SELECT calling_hours_end FROM agents WHERE business_id = ?').bind(bizId).first<any>();
      expect(row.calling_hours_end).toBe(21);
    });

    it('rejects end hours outside the TRAI window', async () => {
      expect((await patchAgent({ calling_hours_end: 24 })).status).toBe(400);
      expect((await patchAgent({ calling_hours_end: 25 })).status).toBe(400);
      expect((await patchAgent({ calling_hours_end: 0 })).status).toBe(400);
    });
  });

  describe('Encryption key', () => {
    it('reading calls without ENCRYPTION_KEY fails closed instead of falling back to the JWT key', async () => {
      const noKey = { ...env, ENCRYPTION_KEY: undefined } as any;
      const res = await app.fetch(
        new Request('http://localhost/calls', { headers: { Authorization: `Bearer ${token}` } }),
        noKey
      );
      expect(res.status).toBe(500);
    });
  });
});
