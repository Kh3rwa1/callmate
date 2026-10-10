import { describe, it, expect, beforeAll, afterEach } from 'vitest';
import { env } from 'cloudflare:test';
import { migrateTestDb } from './setup-db';
import app from '../src/index';
import { signJWT } from '../src/auth';
import {
  checkCallCompliance,
  clampToTraiWindow,
  allowAnyCallingHours,
  TRAI_EARLIEST_HOUR,
  TRAI_LATEST_HOUR,
} from '../src/services/compliance';
import {
  processCampaignJob,
  hasMinutesHeadroom,
  RESERVED_MINUTES_PER_CALL,
  MAX_CONCURRENT_CALLS_PER_BUSINESS,
} from '../src/services/campaign_queue';
import { patchAgentSchema, createCampaignSchema } from '../src/schemas/validation';

const secret = 'test-jwt-signing-secret-key-32chars-min-length';
const bizId = 'biz_polish';
const userId = 'usr_polish';
const phone = '919830077777';
let token: string;

/** A Date at the given wall-clock hour in India (UTC+05:30, no DST). */
function istAt(hour: number, minute = 0): Date {
  return new Date(Date.UTC(2026, 9, 10, hour, minute) - 330 * 60 * 1000);
}

let leadSeq = 0;
async function seedLead(id: string, timezone?: string) {
  const leadPhone = `9197000${String(10000 + ++leadSeq)}`;
  await env.DB.prepare(
    `INSERT OR REPLACE INTO leads (id, business_id, name, phone, status, consent, do_not_call${timezone ? ', timezone' : ''})
     VALUES (?, ?, 'Polish Lead', ?, 'new', 'explicit', 0${timezone ? ', ?' : ''})`
  ).bind(...[id, bizId, leadPhone, ...(timezone ? [timezone] : [])]).run();
}

async function setUsage(included: number, used: number) {
  await env.DB.prepare('UPDATE usage SET included_minutes = ?, minutes_used = ? WHERE business_id = ?')
    .bind(included, used, bizId).run();
}

async function addActiveCalls(n: number) {
  await seedLead('lead_pol_busy');
  for (let i = 0; i < n; i++) {
    await env.DB.prepare(
      `INSERT INTO calls (id, business_id, lead_id, lead_name, lead_phone, status, started_at)
       VALUES (?, ?, 'lead_pol_busy', 'Busy', '919800000000', 'calling', datetime('now'))`
    ).bind(`call_polish_active_${crypto.randomUUID().slice(0, 8)}`, bizId).run();
  }
}

const authed = (path: string, init: RequestInit = {}, targetEnv: any = env) =>
  app.fetch(
    new Request(`http://localhost${path}`, {
      ...init,
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    }),
    targetEnv
  );

describe('Compliance polish', () => {
  beforeAll(async () => {
    await migrateTestDb();
    await env.DB.batch([
      env.DB.prepare("INSERT OR REPLACE INTO businesses (id, name, category) VALUES (?, 'Polish Traders', 'retail')").bind(bizId),
      env.DB.prepare('INSERT OR REPLACE INTO users (id, phone, business_id) VALUES (?, ?, ?)').bind(userId, phone, bizId),
      env.DB.prepare("INSERT OR REPLACE INTO agents (id, business_id, name, role, status, calling_hours_start, calling_hours_end) VALUES ('agt_polish', ?, 'Maya', 'Sales', 'active', 0, 24)").bind(bizId),
      env.DB.prepare("INSERT OR REPLACE INTO usage (id, business_id, included_minutes, minutes_used) VALUES ('usg_polish', ?, 1000, 0)").bind(bizId),
    ]);
    token = await signJWT({ sub: userId, phone, business_id: bizId, type: 'access' }, secret, 3600);
  });

  afterEach(async () => {
    await setUsage(1000, 0);
    await env.DB.prepare("UPDATE calls SET status = 'completed' WHERE business_id = ? AND status = 'calling'").bind(bizId).run();
    await env.DB.prepare('UPDATE agents SET calling_hours_start = 0, calling_hours_end = 24 WHERE business_id = ?').bind(bizId).run();
  });

  describe('TRAI calling window (09:00-21:00 lead local time)', () => {
    it('clamps any stored window into 09-21', () => {
      expect(clampToTraiWindow(0, 24)).toEqual({ start: TRAI_EARLIEST_HOUR, end: TRAI_LATEST_HOUR });
      expect(clampToTraiWindow(10, 19)).toEqual({ start: 10, end: 19 });
      expect(clampToTraiWindow(22, 23)).toEqual({ start: 22, end: 21 }); // empty: never
    });

    it('blocks a stored 0-24 window before 09:00 and from 21:00 IST', async () => {
      await seedLead('lead_pol_clamp');
      const base = { businessId: bizId, leadId: 'lead_pol_clamp', hoursStart: 0, hoursEnd: 24, timezone: 'Asia/Kolkata' };
      for (const [hour, minute] of [[8, 59], [21, 0], [23, 30], [2, 0]]) {
        const r = await checkCallCompliance(env.DB, { ...base, now: istAt(hour, minute) });
        expect(r.allowed, `${hour}:${minute}`).toBe(false);
        expect(r.reason).toBe('outside_hours');
        expect(r.reschedule).toBe(true);
      }
      for (const [hour, minute] of [[9, 0], [12, 0], [20, 59]]) {
        const r = await checkCallCompliance(env.DB, { ...base, now: istAt(hour, minute) });
        expect(r.allowed, `${hour}:${minute}`).toBe(true);
      }
    });

    it('reschedules to 09:00 when the stored start is earlier', async () => {
      await seedLead('lead_pol_resched');
      const r = await checkCallCompliance(env.DB, {
        businessId: bizId, leadId: 'lead_pol_resched', hoursStart: 0, hoursEnd: 24, timezone: 'Asia/Kolkata', now: istAt(6),
      });
      expect(r.rescheduleDelaySeconds).toBe(3 * 3600);
    });

    it("uses the lead's own timezone", async () => {
      await seedLead('lead_pol_tz');
      // 12:00 IST is 02:30 in New York: outside the TRAI window there.
      const r = await checkCallCompliance(env.DB, {
        businessId: bizId, leadId: 'lead_pol_tz', hoursStart: 0, hoursEnd: 24, timezone: 'America/New_York', now: istAt(12),
      });
      expect(r.allowed).toBe(false);
      expect(r.reason).toBe('outside_hours');
    });

    it('the dev-only bypass skips the clamp but never the stored window', async () => {
      await seedLead('lead_pol_bypass');
      const base = { businessId: bizId, leadId: 'lead_pol_bypass', timezone: 'Asia/Kolkata', now: istAt(23), skipTraiClamp: true };
      expect((await checkCallCompliance(env.DB, { ...base, hoursStart: 0, hoursEnd: 24 })).allowed).toBe(true);
      expect((await checkCallCompliance(env.DB, { ...base, hoursStart: 0, hoursEnd: 0 })).allowed).toBe(false);
    });

    it('the bypass is only honoured in development/test', () => {
      expect(allowAnyCallingHours({ ENVIRONMENT: 'development', DEV_ALLOW_ANY_CALLING_HOURS: 'true' })).toBe(true);
      expect(allowAnyCallingHours({ ENVIRONMENT: 'test', DEV_ALLOW_ANY_CALLING_HOURS: 'true' })).toBe(true);
      expect(allowAnyCallingHours({ ENVIRONMENT: 'production', DEV_ALLOW_ANY_CALLING_HOURS: 'true' })).toBe(false);
      expect(allowAnyCallingHours({ ENVIRONMENT: 'staging', DEV_ALLOW_ANY_CALLING_HOURS: 'true' })).toBe(false);
      expect(allowAnyCallingHours({ DEV_ALLOW_ANY_CALLING_HOURS: 'true' })).toBe(false);
      expect(allowAnyCallingHours({ ENVIRONMENT: 'development' })).toBe(false);
    });
  });

  describe('Calling-hours validation', () => {
    it('agent schema accepts 9-21 and rejects anything outside', () => {
      expect(patchAgentSchema.safeParse({ calling_hours_start: 9, calling_hours_end: 21 }).success).toBe(true);
      expect(patchAgentSchema.safeParse({ calling_hours_start: 8 }).success).toBe(false);
      expect(patchAgentSchema.safeParse({ calling_hours_end: 22 }).success).toBe(false);
      expect(patchAgentSchema.safeParse({ calling_hours_end: 24 }).success).toBe(false);
      expect(patchAgentSchema.safeParse({ calling_hours_start: 15, calling_hours_end: 12 }).success).toBe(false);
      expect(patchAgentSchema.safeParse({ calling_hours_start: 12, calling_hours_end: 12 }).success).toBe(false);
    });

    it('campaign schema enforces the same window', () => {
      expect(createCampaignSchema.safeParse({ calling_hours_start: 9, calling_hours_end: 21 }).success).toBe(true);
      expect(createCampaignSchema.safeParse({ calling_hours_start: 0, calling_hours_end: 24 }).success).toBe(false);
      expect(createCampaignSchema.safeParse({ calling_hours_start: 7, calling_hours_end: 12 }).success).toBe(false);
      expect(createCampaignSchema.safeParse({ calling_hours_start: 12, calling_hours_end: 22 }).success).toBe(false);
      expect(createCampaignSchema.safeParse({ calling_hours_start: 15, calling_hours_end: 12 }).success).toBe(false);
    });

    it('PATCH /agent rejects out-of-window hours with 400', async () => {
      const res = await authed('/agent', { method: 'PATCH', body: JSON.stringify({ calling_hours_start: 0, calling_hours_end: 24 }) });
      expect(res.status).toBe(400);
    });

    it('PATCH /agent clamps a legacy stored bound when the other one changes', async () => {
      // Stored 0-24 predates validation; changing only the start must not keep end = 24.
      const res = await authed('/agent', { method: 'PATCH', body: JSON.stringify({ calling_hours_start: 10 }) });
      expect(res.status).toBe(200);
      const row = await env.DB.prepare('SELECT calling_hours_start, calling_hours_end FROM agents WHERE business_id = ?').bind(bizId).first<any>();
      expect(row).toMatchObject({ calling_hours_start: 10, calling_hours_end: 21 });
    });

    it('PATCH /agent rejects a change that leaves start >= end', async () => {
      await env.DB.prepare('UPDATE agents SET calling_hours_start = 10, calling_hours_end = 12 WHERE business_id = ?').bind(bizId).run();
      const res = await authed('/agent', { method: 'PATCH', body: JSON.stringify({ calling_hours_start: 15 }) });
      expect(res.status).toBe(400);
    });
  });

  describe('Minutes headroom', () => {
    it('reserves RESERVED_MINUTES_PER_CALL for each running call plus the new one', () => {
      expect(RESERVED_MINUTES_PER_CALL).toBe(5);
      expect(hasMinutesHeadroom({ included_minutes: 100, minutes_used: 95 }, 0)).toBe(true);
      expect(hasMinutesHeadroom({ included_minutes: 100, minutes_used: 96 }, 0)).toBe(false);
      expect(hasMinutesHeadroom({ included_minutes: 100, minutes_used: 90 }, 1)).toBe(true);
      expect(hasMinutesHeadroom({ included_minutes: 100, minutes_used: 91 }, 1)).toBe(false);
      expect(hasMinutesHeadroom({ included_minutes: 100, minutes_used: 100 - 5 * MAX_CONCURRENT_CALLS_PER_BUSINESS }, MAX_CONCURRENT_CALLS_PER_BUSINESS - 1)).toBe(true);
    });

    it('manual call: refuses when remaining minutes cannot cover running calls + 1', async () => {
      await seedLead('lead_pol_min_block');
      await addActiveCalls(2);
      await setUsage(100, 86); // 14 left, needs 15
      const res = await authed('/leads/lead_pol_min_block/call', { method: 'POST' });
      expect(res.status).toBe(402);
      expect(((await res.json()) as any).code).toBe('exhausted_minutes');
    });

    it('manual call: allowed with exactly enough headroom', async () => {
      await seedLead('lead_pol_min_ok');
      await addActiveCalls(2);
      await setUsage(100, 85); // 15 left, needs 15
      const res = await authed('/leads/lead_pol_min_ok/call', { method: 'POST' });
      expect(res.status).toBe(200);
    });

    it('campaign dispatch: pauses the campaign when headroom runs out', async () => {
      await seedLead('lead_pol_camp');
      const campId = `camp_pol_${Date.now()}`;
      await env.DB.batch([
        env.DB.prepare("INSERT INTO campaigns (id, business_id, purpose, status, total_leads, calling_hours_start, calling_hours_end) VALUES (?, ?, 'Polish', 'running', 1, 0, 24)").bind(campId, bizId),
        env.DB.prepare("INSERT INTO campaign_leads (campaign_id, lead_id, status, attempts) VALUES (?, 'lead_pol_camp', 'queued', 0)").bind(campId),
      ]);
      await setUsage(100, 97); // 3 left, below one call's reserve
      const result = await processCampaignJob(env as any, {
        campaign_id: campId, lead_id: 'lead_pol_camp', business_id: bizId, idempotency_key: `${campId}:lead_pol_camp`, attempts: 0,
      });
      expect(result.reason).toBe('exhausted_minutes');
      const camp = await env.DB.prepare('SELECT status FROM campaigns WHERE id = ?').bind(campId).first<any>();
      expect(camp.status).toBe('paused');
      const calls = await env.DB.prepare("SELECT COUNT(*) AS c FROM calls WHERE lead_id = 'lead_pol_camp'").first<{ c: number }>();
      expect(calls?.c).toBe(0);
    });
  });

  describe('Public legal pages', () => {
    for (const path of ['/legal/privacy', '/legal/terms', '/legal/delete-account']) {
      it(`${path} is public, self-contained HTML`, async () => {
        const res = await app.fetch(new Request(`http://localhost${path}`), env);
        expect(res.status).toBe(200);
        expect(res.headers.get('content-type')).toContain('text/html');
        expect(res.headers.get('content-security-policy')).toContain("default-src 'none'");
        const html = await res.text();
        expect(html).toContain('<meta name="viewport"');
        expect(html).not.toMatch(/<script/i);
        expect(html).not.toMatch(/(src|href)="https?:\/\//i);
        expect(html).toContain('Last updated:');
        expect(html).toContain('support@callpilot.app');
      });
    }

    it('uses SUPPORT_EMAIL and LEGAL_ENTITY_NAME, escaped', async () => {
      const res = await app.fetch(
        new Request('http://localhost/legal/privacy'),
        { ...env, SUPPORT_EMAIL: 'help@example.in', LEGAL_ENTITY_NAME: 'Acme <Pvt> Ltd' } as any
      );
      const html = await res.text();
      expect(html).toContain('mailto:help@example.in');
      expect(html).toContain('Acme &lt;Pvt&gt; Ltd');
      expect(html).not.toContain('Acme <Pvt> Ltd');
    });

    it('privacy policy names the processors and data categories', async () => {
      const html = await (await app.fetch(new Request('http://localhost/legal/privacy'), env)).text();
      for (const s of ['Cloudflare', 'Sarvam AI', 'Google Firebase', 'recordings', 'transcripts', 'contacts', 'Microphone', 'Grievance Officer', 'DPDP']) {
        expect(html).toContain(s);
      }
    });

    it('delete-account page explains the in-app path and email route', async () => {
      const html = await (await app.fetch(new Request('http://localhost/legal/delete-account'), env)).text();
      expect(html).toContain('<strong>Agent</strong> tab');
      expect(html).toContain('<strong>Delete account</strong>');
      expect(html).toContain('mailto:support@callpilot.app');
    });
  });
});
