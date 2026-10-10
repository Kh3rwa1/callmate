import { describe, it, expect, beforeAll } from 'vitest';
import { env } from 'cloudflare:test';
import { migrateTestDb } from './setup-db';
import app from '../src/index';
import { signJWT } from '../src/auth';
import { buildDigest, claimDigest, runDailyDigests, DIGEST_HOUR } from '../src/services/digest';
import { localDateAndHour, localMidnightUtc, periodResults, sqlUtc, estimatedValue } from '../src/services/results';
import { getHourInTimezone } from '../src/services/compliance';

const jwtSecret = 'test-jwt-signing-secret-key-32chars-min-length';
let n = 0;

/** 2026-10-10 19:05 in Kolkata (UTC+05:30). */
const DIGEST_NOW = new Date('2026-10-10T13:35:00Z');
/** A moment earlier the same local day (10:30 IST). */
const MORNING = '2026-10-10 05:00:00';

function call(path: string, init: RequestInit = {}, token?: string, e: any = env) {
  const headers: Record<string, string> = { 'Content-Type': 'application/json', ...(init.headers as any) };
  if (token) headers.Authorization = `Bearer ${token}`;
  return app.fetch(new Request(`http://localhost${path}`, { ...init, headers }), e);
}

async function seedBusiness(id: string, opts: { digest?: number; device?: boolean; avg?: number | null; hours?: [number, number]; phone?: string } = {}) {
  const [start, end] = opts.hours ?? [0, 24];
  const stmts = [
    env.DB.prepare('INSERT INTO businesses (id, name, owner_name, digest_enabled, avg_deal_value_inr) VALUES (?, ?, ?, ?, ?)')
      .bind(id, `Biz ${id}`, 'Asha', opts.digest ?? 1, opts.avg ?? null),
    env.DB.prepare(
      `INSERT INTO agents (id, business_id, name, role, calling_hours_start, calling_hours_end) VALUES (?, ?, 'Riya', 'Sales', ?, ?)`
    ).bind(`agent_${id}`, id, start, end),
  ];
  if (opts.device !== false) {
    stmts.push(env.DB.prepare('INSERT INTO devices (id, business_id, fcm_token) VALUES (?, ?, ?)').bind(`dev_${id}`, id, `tok_${id}`));
  }
  const phone = opts.phone ?? `9197${String(++n).padStart(8, '0')}`;
  stmts.push(env.DB.prepare('INSERT INTO users (id, phone, business_id) VALUES (?, ?, ?)').bind(`usr_${id}`, phone, id));
  await env.DB.batch(stmts);
  return signJWT({ sub: `usr_${id}`, phone, business_id: id, type: 'access' }, jwtSecret, 3600);
}

async function seedLead(biz: string, opts: { createdAt?: string; test?: boolean } = {}) {
  const id = `lead_rl_${++n}`;
  await env.DB.prepare(
    `INSERT INTO leads (id, business_id, name, phone, is_owner_test, created_at) VALUES (?, ?, 'Lead', ?, ?, ?)`
  ).bind(id, biz, `9198${String(n).padStart(8, '0')}`, opts.test ? 1 : 0, opts.createdAt ?? sqlUtc(new Date())).run();
  return id;
}

async function seedCall(biz: string, leadId: string, opts: { at?: string; status?: string; temperature?: string | null } = {}) {
  const id = `call_rl_${++n}`;
  await env.DB.prepare(
    `INSERT INTO calls (id, business_id, lead_id, lead_name, lead_phone, status, temperature, started_at)
     VALUES (?, ?, ?, 'Lead', '9100', ?, ?, ?)`
  ).bind(id, biz, leadId, opts.status ?? 'completed', opts.temperature ?? null, opts.at ?? sqlUtc(new Date())).run();
  return id;
}

async function digestNotifications(biz: string) {
  const { results } = await env.DB.prepare("SELECT * FROM notifications WHERE business_id = ? AND type = 'daily_digest'").bind(biz).all<any>();
  return results;
}

describe('Results loop', () => {
  beforeAll(async () => {
    await migrateTestDb();
  });

  describe('local time helpers', () => {
    it('reports the Kolkata date and hour', () => {
      expect(localDateAndHour(DIGEST_NOW)).toEqual({ date: '2026-10-10', hour: 19 });
      // 20:00 UTC is already the next day in India.
      expect(localDateAndHour(new Date('2026-10-10T20:00:00Z'))).toEqual({ date: '2026-10-11', hour: 1 });
    });

    it('finds local midnight in UTC', () => {
      expect(localMidnightUtc(DIGEST_NOW, 0).toISOString()).toBe('2026-10-09T18:30:00.000Z');
      expect(localMidnightUtc(DIGEST_NOW, 1).toISOString()).toBe('2026-10-10T18:30:00.000Z');
      expect(localMidnightUtc(DIGEST_NOW, -6).toISOString()).toBe('2026-10-03T18:30:00.000Z');
    });

    it('estimates value only when an average sale value is set', () => {
      expect(estimatedValue(3, 5000)).toBe(15000);
      expect(estimatedValue(3, null)).toBeNull();
      expect(estimatedValue(3, 0)).toBeNull();
    });
  });

  describe('buildDigest', () => {
    const zero = { enquiries: 0, calls: 0, calls_connected: 0, interested: 0, ready_to_buy: 0, followups_sent: 0 };

    it('is null when nothing happened', () => {
      expect(buildDigest(zero, 0)).toBeNull();
      // Callbacks tomorrow alone are not activity today.
      expect(buildDigest(zero, 2)).toBeNull();
    });

    it('leads with calls and buyers and links to the hot leads', () => {
      const d = buildDigest({ ...zero, calls: 12, calls_connected: 8, interested: 5, ready_to_buy: 3, enquiries: 4 }, 0)!;
      expect(d.body).toBe('Today: 12 calls, 3 ready to buy — tap to see them');
      expect(d.route).toBe('/leads?filter=hot');
    });

    it('mentions interested leads, enquiries and callbacks when nobody is ready to buy', () => {
      const d = buildDigest({ ...zero, calls: 1, calls_connected: 1, interested: 1, enquiries: 2 }, 2)!;
      expect(d.body).toBe('Today: 1 call, 1 interested, 2 new enquiries, 2 callbacks tomorrow — tap to see more');
      expect(d.route).toBe('/leads?filter=warm');
      expect(buildDigest({ ...zero, enquiries: 1 }, 0)!.route).toBe('/leads');
    });
  });

  describe('daily digest cron', () => {
    beforeAll(async () => {
      // Active today: 3 calls, 2 of them hot, 1 enquiry, a callback tomorrow.
      await seedBusiness('biz_dg_active');
      const a1 = await seedLead('biz_dg_active', { createdAt: MORNING });
      const a2 = await seedLead('biz_dg_active', { createdAt: '2026-10-01 05:00:00' });
      await seedCall('biz_dg_active', a1, { at: MORNING, temperature: 'hot' });
      await seedCall('biz_dg_active', a2, { at: MORNING, temperature: 'hot' });
      await seedCall('biz_dg_active', a2, { at: MORNING, status: 'no_answer' });
      // Yesterday's call does not count.
      await seedCall('biz_dg_active', a2, { at: '2026-10-09 10:00:00', temperature: 'hot' });
      await env.DB.prepare(
        `INSERT INTO callbacks (id, business_id, lead_id, lead_name, scheduled_at, status) VALUES ('cb_dg_1', 'biz_dg_active', ?, 'Lead', '2026-10-11T05:00:00Z', 'scheduled')`
      ).bind(a1).run();

      // Opted out, but active.
      await seedBusiness('biz_dg_off', { digest: 0 });
      const o1 = await seedLead('biz_dg_off', { createdAt: MORNING });
      await seedCall('biz_dg_off', o1, { at: MORNING, temperature: 'hot' });

      // Nothing happened today (only an old lead).
      await seedBusiness('biz_dg_quiet');
      await seedLead('biz_dg_quiet', { createdAt: '2026-09-01 05:00:00' });

      // Only the owner's own test call happened.
      await seedBusiness('biz_dg_owner');
      const t1 = await seedLead('biz_dg_owner', { createdAt: MORNING, test: true });
      await seedCall('biz_dg_owner', t1, { at: MORNING, temperature: 'hot' });
    });

    it('computes today without owner test calls', async () => {
      const r = await periodResults(env.DB, 'biz_dg_active', localMidnightUtc(DIGEST_NOW, 0), DIGEST_NOW);
      expect(r).toMatchObject({ enquiries: 1, calls: 3, calls_connected: 2, interested: 2, ready_to_buy: 2 });
      const o = await periodResults(env.DB, 'biz_dg_owner', localMidnightUtc(DIGEST_NOW, 0), DIGEST_NOW);
      expect(o).toMatchObject({ enquiries: 0, calls: 0, ready_to_buy: 0 });
    });

    it('does nothing before DIGEST_HOUR or late at night', async () => {
      expect(DIGEST_HOUR).toBe(19);
      expect(await runDailyDigests(env as any, new Date('2026-10-10T13:00:00Z'))).toEqual({ sent: 0, skipped: 0 }); // 18:30 IST
      expect(await runDailyDigests(env as any, new Date('2026-10-10T17:00:00Z'))).toEqual({ sent: 0, skipped: 0 }); // 22:30 IST
      expect(await digestNotifications('biz_dg_active')).toHaveLength(0);
    });

    it('sends one digest after 19:00 and never twice the same day', async () => {
      const first = await runDailyDigests(env as any, DIGEST_NOW);
      expect(first.sent).toBe(1);

      const notes = await digestNotifications('biz_dg_active');
      expect(notes).toHaveLength(1);
      expect(notes[0].body).toBe('Today: 3 calls, 2 ready to buy, 1 callback tomorrow — tap to see them');
      expect(notes[0].route).toBe('/leads?filter=hot');
      const log = await env.DB.prepare("SELECT date FROM digest_log WHERE business_id = 'biz_dg_active'").first<any>();
      expect(log.date).toBe('2026-10-10');

      // The next cron ticks (10 and 20 minutes later) send nothing more.
      await runDailyDigests(env as any, new Date(DIGEST_NOW.getTime() + 10 * 60_000));
      await runDailyDigests(env as any, new Date(DIGEST_NOW.getTime() + 20 * 60_000));
      expect(await digestNotifications('biz_dg_active')).toHaveLength(1);
      expect(await claimDigest(env.DB, 'biz_dg_active', '2026-10-10')).toBe(false);
    });

    it('skips owners who turned it off, quiet days and owner-only test calls', async () => {
      expect(await digestNotifications('biz_dg_off')).toHaveLength(0);
      expect(await digestNotifications('biz_dg_quiet')).toHaveLength(0);
      expect(await digestNotifications('biz_dg_owner')).toHaveLength(0);
      // Quiet days are not logged, so activity later in the evening still gets a digest.
      const quietLog = await env.DB.prepare("SELECT 1 FROM digest_log WHERE business_id = 'biz_dg_quiet'").first();
      expect(quietLog).toBeNull();
    });

    it('sends the next day again', async () => {
      const a1 = await seedLead('biz_dg_active', { createdAt: '2026-10-11 05:00:00' });
      await seedCall('biz_dg_active', a1, { at: '2026-10-11 05:00:00', temperature: 'warm' });
      const res = await runDailyDigests(env as any, new Date('2026-10-11T13:40:00Z'));
      expect(res.sent).toBe(1);
      const notes = await digestNotifications('biz_dg_active');
      expect(notes).toHaveLength(2);
    });

    it('is wired into the scheduled handler', async () => {
      const waits: Promise<any>[] = [];
      await app.scheduled!({} as any, env as any, { waitUntil: (p: Promise<any>) => waits.push(p), passThroughOnException() {} } as any);
      expect(waits.length).toBeGreaterThanOrEqual(4);
      await Promise.allSettled(waits);
    });
  });

  describe('digest and average sale value settings', () => {
    it('GET /business reports defaults and PATCH changes them', async () => {
      const token = await seedBusiness('biz_settings');
      let res = await call('/business', {}, token);
      let b: any = await res.json();
      expect(b.digest_enabled).toBe(true);
      expect(b.avg_deal_value_inr).toBeNull();

      res = await call('/business', { method: 'PATCH', body: JSON.stringify({ digest_enabled: false, avg_deal_value_inr: 25000 }) }, token);
      expect(res.status).toBe(200);
      b = await res.json();
      expect(b.digest_enabled).toBe(false);
      expect(b.avg_deal_value_inr).toBe(25000);

      // Other edits keep the settings.
      res = await call('/business', { method: 'PATCH', body: JSON.stringify({ name: 'Renamed' }) }, token);
      b = await res.json();
      expect(b).toMatchObject({ name: 'Renamed', digest_enabled: false, avg_deal_value_inr: 25000 });

      res = await call('/business', { method: 'PATCH', body: JSON.stringify({ avg_deal_value_inr: null, digest_enabled: true }) }, token);
      b = await res.json();
      expect(b).toMatchObject({ digest_enabled: true, avg_deal_value_inr: null });

      res = await call('/business', { method: 'PATCH', body: JSON.stringify({ avg_deal_value_inr: -5 }) }, token);
      expect(res.status).toBe(400);
    });
  });

  describe('GET /dashboard/results', () => {
    it('returns this week vs last week with an estimated value', async () => {
      const token = await seedBusiness('biz_results', { avg: 20000 });
      const now = new Date();
      const today = sqlUtc(new Date(now.getTime() - 60_000));
      const lastWeek = sqlUtc(new Date(localMidnightUtc(now, -8).getTime() + 3600_000));
      const l1 = await seedLead('biz_results', { createdAt: today });
      const l2 = await seedLead('biz_results', { createdAt: today });
      const l3 = await seedLead('biz_results', { createdAt: lastWeek });
      await seedCall('biz_results', l1, { at: today, temperature: 'hot' });
      await seedCall('biz_results', l2, { at: today, temperature: 'warm' });
      await seedCall('biz_results', l2, { at: today, status: 'no_answer' });
      await seedCall('biz_results', l3, { at: lastWeek, temperature: 'cold' });
      await env.DB.prepare(
        `INSERT INTO followups (id, business_id, lead_id, message, status, opened_at) VALUES ('fu_rs_1', 'biz_results', ?, 'Hi', 'opened', ?)`
      ).bind(l1, today).run();
      await env.DB.prepare(
        `INSERT INTO followups (id, business_id, lead_id, message, status) VALUES ('fu_rs_2', 'biz_results', ?, 'Hi', 'ready')`
      ).bind(l2).run();
      // The owner's own test call is not a result.
      const t = await seedLead('biz_results', { createdAt: today, test: true });
      await seedCall('biz_results', t, { at: today, temperature: 'hot' });

      const res = await call('/dashboard/results?range=week', {}, token);
      expect(res.status).toBe(200);
      const body: any = await res.json();
      expect(body).toMatchObject({
        range: 'week',
        enquiries: 2,
        calls: 3,
        calls_connected: 2,
        interested: 2,
        ready_to_buy: 1,
        followups_sent: 1,
        estimated_value_inr: 20000,
        avg_deal_value_inr: 20000,
        has_calls: true,
        previous: { enquiries: 1, calls_connected: 1, interested: 0, ready_to_buy: 0, estimated_value_inr: 0 },
      });
    });

    it('leaves the estimate empty without an average sale value, and validates range', async () => {
      const token = await seedBusiness('biz_results_novalue');
      let res = await call('/dashboard/results', {}, token);
      const body: any = await res.json();
      expect(body).toMatchObject({ range: 'week', enquiries: 0, estimated_value_inr: null, avg_deal_value_inr: null, has_calls: false });
      res = await call('/dashboard/results?range=year', {}, token);
      expect(res.status).toBe(400);
      res = await call('/dashboard/results?range=today', {}, token);
      expect(res.status).toBe(200);
    });

    it('requires auth', async () => {
      const res = await call('/dashboard/results');
      expect(res.status).toBe(401);
    });
  });

  describe('POST /agent/test-call', () => {
    it('GET reports the owner phone and calls left', async () => {
      const token = await seedBusiness('biz_tc_info', { phone: '919830012345' });
      const res = await call('/agent/test-call', {}, token);
      expect(await res.json()).toEqual({ phone: '919830012345', remaining_today: 3, limit: 3 });
    });

    it('calls the owner through the lead call path, hidden from customers and stats', async () => {
      const token = await seedBusiness('biz_tc');
      const res = await call('/agent/test-call', { method: 'POST', body: JSON.stringify({ phone: '98300 12345' }) }, token);
      expect(res.status).toBe(200);
      const body: any = await res.json();
      expect(body.call.status).toBe('calling');
      expect(body.remaining_today).toBe(2);
      expect(body.lead_id).toBeTruthy();

      const lead = await env.DB.prepare('SELECT * FROM leads WHERE id = ?').bind(body.lead_id).first<any>();
      expect(lead).toMatchObject({ phone: '919830012345', is_owner_test: 1, consent: 'opt_in', name: 'Asha' });

      // Not a customer, not a stat, not campaign material.
      const leads: any = await (await call('/leads', {}, token)).json();
      expect(leads.items.find((l: any) => l.id === body.lead_id)).toBeUndefined();
      const today: any = await (await call('/dashboard/today', {}, token)).json();
      expect(today).toMatchObject({ leads: 0, calls_today: 0 });
      const results: any = await (await call('/dashboard/results', {}, token)).json();
      expect(results).toMatchObject({ calls: 0, has_calls: false });
      const camp = await call('/campaigns', { method: 'POST', body: JSON.stringify({ purpose: 'x', lead_ids: [body.lead_id] }) }, token);
      expect(camp.status).toBe(400);

      // The same number reuses the same hidden lead.
      await env.DB.prepare("UPDATE calls SET status = 'completed' WHERE lead_id = ?").bind(body.lead_id).run();
      const again: any = await (await call('/agent/test-call', { method: 'POST', body: JSON.stringify({ phone: '+91 98300 12345' }) }, token)).json();
      expect(again.lead_id).toBe(body.lead_id);
      expect(again.remaining_today).toBe(1);
    });

    it('allows 3 test calls a day per business', async () => {
      const token = await seedBusiness('biz_tc_limit');
      const statuses: number[] = [];
      for (let i = 0; i < 4; i++) {
        // Free the concurrency slot between attempts.
        await env.DB.prepare("UPDATE calls SET status = 'completed' WHERE business_id = 'biz_tc_limit'").run();
        const res = await call('/agent/test-call', { method: 'POST', body: JSON.stringify({ phone: '9830099999' }) }, token);
        statuses.push(res.status);
        if (res.status === 429) expect(((await res.json()) as any).code).toBe('test_call_limit');
      }
      expect(statuses).toEqual([200, 200, 200, 429]);
      const info: any = await (await call('/agent/test-call', {}, token)).json();
      expect(info.remaining_today).toBe(0);
    });

    it('keeps every lead-call guard: outside calling hours is refused and does not use up a test call', async () => {
      const h = getHourInTimezone('Asia/Kolkata');
      const start = (h + 1) % 24;
      const token = await seedBusiness('biz_tc_hours', { hours: [start, start + 1] });
      const res = await call('/agent/test-call', { method: 'POST', body: JSON.stringify({ phone: '9830088888' }) }, token);
      expect(res.status).toBe(409);
      expect(((await res.json()) as any).code).toBe('outside_hours');
      const info: any = await (await call('/agent/test-call', {}, token)).json();
      expect(info.remaining_today).toBe(3);
    });

    it('refuses a number that is already a customer, and bad input', async () => {
      const token = await seedBusiness('biz_tc_customer');
      await env.DB.prepare("INSERT INTO leads (id, business_id, name, phone) VALUES ('lead_tc_cust', 'biz_tc_customer', 'C', '919830077777')").run();
      let res = await call('/agent/test-call', { method: 'POST', body: JSON.stringify({ phone: '9830077777' }) }, token);
      expect(res.status).toBe(409);
      expect(((await res.json()) as any).code).toBe('phone_is_customer');
      res = await call('/agent/test-call', { method: 'POST', body: JSON.stringify({}) }, token);
      expect(res.status).toBe(400);
      res = await call('/agent/test-call', { method: 'POST', body: JSON.stringify({ phone: 'abcdefghij' }) }, token);
      expect(res.status).toBe(400);
    });
  });
});
