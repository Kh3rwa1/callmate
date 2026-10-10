import { describe, it, expect, beforeAll, vi, afterEach } from 'vitest';
import { env } from 'cloudflare:test';
import { migrateTestDb } from './setup-db';
import app from '../src/index';
import { signJWT } from '../src/auth';
import { billableMinutes, MIN_BILLABLE_SECONDS } from '../src/services/billing';
import {
  callCostInr, callDurationSeconds, costRates, economicsReport, maxCallMinutes, runLongCallWatchdog,
} from '../src/services/economics';
import { isInvalidNumberOutcome, isRetryableOutcome, RETRY_SPACING_SECONDS } from '../src/services/call_outcomes';
import { processCampaignJob, sarvamWebhookToken, MAX_DIAL_ATTEMPTS } from '../src/services/campaign_queue';

const jwtSecret = 'test-jwt-signing-secret-key-32chars-min-length';
const BIZ = 'biz_econ';
const USER = 'usr_econ';
const PHONE = '919830099001';

function sent() {
  const msgs: { body: any; opts: any }[] = [];
  return { msgs, queue: { send: async (body: any, opts: any) => { msgs.push({ body, opts }); }, sendBatch: async () => {} } };
}

async function seedLead(id: string, phone: string, extra = '') {
  await env.DB.prepare(
    `INSERT OR REPLACE INTO leads (id, business_id, name, phone, status, consent${extra ? ', phone_invalid' : ''})
     VALUES (?, ?, 'Lead', ?, 'calling', 'granted'${extra ? `, ${extra}` : ''})`
  ).bind(id, BIZ, phone).run();
}

async function seedCall(callId: string, leadId: string, campaignId: string | null = null, startedAgo = '-1 minutes') {
  await env.DB.prepare(
    `INSERT OR REPLACE INTO calls (id, business_id, lead_id, lead_name, lead_phone, campaign_id, status, started_at)
     VALUES (?, ?, ?, 'Lead', '919800000000', ?, 'calling', datetime('now', ?))`
  ).bind(callId, BIZ, leadId, campaignId, startedAgo).run();
}

async function postSarvam(callId: string, payload: Record<string, unknown>, e: any = env) {
  const token = await sarvamWebhookToken(env.SARVAM_WEBHOOK_SECRET!, callId);
  return app.fetch(new Request(`http://localhost/webhooks/sarvam?call_id=${callId}&token=${token}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload),
  }), e);
}

const minutesUsed = async () =>
  (await env.DB.prepare('SELECT minutes_used FROM usage WHERE business_id = ?').bind(BIZ).first<any>()).minutes_used as number;

describe('Unit economics', () => {
  beforeAll(async () => {
    await migrateTestDb();
    await env.DB.batch([
      env.DB.prepare("INSERT OR REPLACE INTO businesses (id, name) VALUES (?, 'Econ Biz')").bind(BIZ),
      env.DB.prepare('INSERT OR REPLACE INTO users (id, phone, business_id) VALUES (?, ?, ?)').bind(USER, PHONE, BIZ),
      env.DB.prepare(
        `INSERT OR REPLACE INTO usage (id, business_id, plan_id, plan_status, plan_name, included_minutes, minutes_used)
         VALUES ('usg_econ', ?, 'growth', 'active', 'Growth', 3000, 0)`
      ).bind(BIZ),
    ]);
  });

  afterEach(() => vi.restoreAllMocks());

  describe('pure helpers', () => {
    it('bills connected calls >= 10 s per started minute and never voicemail', () => {
      expect(MIN_BILLABLE_SECONDS).toBe(10);
      expect(billableMinutes('completed', 9).minutes).toBe(0);
      expect(billableMinutes('completed', 10).minutes).toBe(1);
      expect(billableMinutes('connected', 95.4).minutes).toBe(2);
      for (const s of ['voicemail', 'no_answer', 'busy', 'failed']) expect(billableMinutes(s, 120).minutes).toBe(0);
    });

    it('costs every started minute at Sarvam + telephony rates', () => {
      expect(costRates({})).toEqual({ sarvam: 2, telephony: 0.6, total: 2.6 });
      expect(costRates({ COST_PER_MIN_SARVAM_INR: '1.5', COST_PER_MIN_TELEPHONY_INR: 'x' })).toEqual({ sarvam: 1.5, telephony: 0.6, total: 2.1 });
      expect(callCostInr({}, 0)).toBe(0);
      expect(callCostInr({}, 5)).toBe(2.6);
      expect(callCostInr({}, 61)).toBe(5.2);
      expect(callDurationSeconds(95.9)).toBe(95);
      expect(callDurationSeconds(null)).toBe(0);
      expect(callDurationSeconds('abc')).toBe(0);
      expect(maxCallMinutes({})).toBe(8);
      expect(maxCallMinutes({ MAX_CALL_MINUTES: '12' })).toBe(12);
      expect(maxCallMinutes({ MAX_CALL_MINUTES: '0' })).toBe(8);
    });

    it('classifies retryable and invalid-number outcomes', () => {
      expect(RETRY_SPACING_SECONDS).toBe(3 * 3600);
      expect(MAX_DIAL_ATTEMPTS).toBe(3);
      for (const s of ['busy', 'no_answer', 'NO_ANSWER', 'not_answered']) expect(isRetryableOutcome(s)).toBe(true);
      for (const s of ['failed', 'voicemail', 'rejected', 'completed', null]) expect(isRetryableOutcome(s)).toBe(false);
      expect(isInvalidNumberOutcome('invalid_number', null)).toBe(true);
      expect(isInvalidNumberOutcome('not_reachable', null)).toBe(true);
      expect(isInvalidNumberOutcome('failed', 'exotel: Invalid phone number')).toBe(true);
      expect(isInvalidNumberOutcome('failed', 'vobiz: The number you have dialled is not in service')).toBe(true);
      expect(isInvalidNumberOutcome('failed', 'exotel: Phone number is registered under TRAI NDNC')).toBe(false);
      expect(isInvalidNumberOutcome('busy', undefined)).toBe(false);
    });
  });

  describe('Sarvam webhook billing + cost', () => {
    it('connected 95 s bills 2 minutes and stores billed_minutes + cost', async () => {
      await seedLead('lead_e1', '919811100001');
      await seedCall('call_e1', 'lead_e1');
      const before = await minutesUsed();
      const res = await postSarvam('call_e1', { status: 'connected', duration: 95.4 });
      expect(res.status).toBe(200);
      const call = await env.DB.prepare('SELECT billed_minutes, cost_inr, duration_seconds FROM calls WHERE id = ?').bind('call_e1').first<any>();
      expect(call).toMatchObject({ billed_minutes: 2, cost_inr: 5.2, duration_seconds: 95 });
      expect(await minutesUsed()).toBe(before + 2);
      const ledger = await env.DB.prepare('SELECT * FROM usage_ledger WHERE call_id = ?').bind('call_e1').first<any>();
      expect(ledger).toMatchObject({ billed_minutes: 2, duration_seconds: 95, cost_inr: 5.2, plan_id: 'growth' });
    });

    it('a 6 s connected call and a 40 s voicemail bill 0 minutes but record our cost', async () => {
      await seedLead('lead_e2', '919811100002');
      await seedLead('lead_e3', '919811100003');
      await seedCall('call_e2', 'lead_e2');
      await seedCall('call_e3', 'lead_e3');
      const before = await minutesUsed();
      expect((await postSarvam('call_e2', { status: 'connected', duration: 6 })).status).toBe(200);
      expect((await postSarvam('call_e3', { status: 'voicemail', duration: 40 })).status).toBe(200);
      expect(await minutesUsed()).toBe(before);
      const c2 = await env.DB.prepare('SELECT status, billed_minutes, cost_inr FROM calls WHERE id = ?').bind('call_e2').first<any>();
      expect(c2).toMatchObject({ status: 'completed', billed_minutes: 0, cost_inr: 2.6 });
      const c3 = await env.DB.prepare('SELECT status, billed_minutes, cost_inr FROM calls WHERE id = ?').bind('call_e3').first<any>();
      expect(c3).toMatchObject({ status: 'voicemail', billed_minutes: 0, cost_inr: 2.6 });
      const l3 = await env.DB.prepare('SELECT duration_seconds FROM usage_ledger WHERE call_id = ?').bind('call_e3').first<any>();
      expect(l3.duration_seconds).toBe(40);
    });
  });

  describe('waste control: retries and invalid numbers', () => {
    async function campaignCall(n: string, attempts = 1) {
      const camp = `camp_w${n}`;
      const lead = `lead_w${n}`;
      const callId = `call_w${n}`;
      await env.DB.prepare(
        `INSERT OR REPLACE INTO campaigns (id, business_id, purpose, status, calling_hours_start, calling_hours_end, total_leads)
         VALUES (?, ?, 'Waste', 'running', 0, 24, 2)`
      ).bind(camp, BIZ).run();
      await seedLead(lead, `91981120000${n}`);
      await env.DB.prepare(
        "INSERT OR REPLACE INTO campaign_leads (campaign_id, lead_id, call_id, status, attempts) VALUES (?, ?, ?, 'calling', ?)"
      ).bind(camp, lead, callId, attempts).run();
      await seedCall(callId, lead, camp);
      return { camp, lead, callId };
    }

    it('busy is retried once more, 3 h later', async () => {
      const { lead, callId } = await campaignCall('1');
      const q = sent();
      expect((await postSarvam(callId, { status: 'busy', duration: null }, { ...env, CAMPAIGN_QUEUE: q.queue })).status).toBe(200);
      const cl = await env.DB.prepare('SELECT status FROM campaign_leads WHERE call_id = ?').bind(callId).first<any>();
      expect(cl.status).toBe('retry_pending');
      expect(q.msgs).toHaveLength(1);
      expect(q.msgs[0].body.lead_id).toBe(lead);
      expect(q.msgs[0].opts.delaySeconds).toBe(RETRY_SPACING_SECONDS);
    });

    it('no_answer on the last allowed attempt fails instead of retrying', async () => {
      const { callId } = await campaignCall('2', MAX_DIAL_ATTEMPTS);
      const q = sent();
      await postSarvam(callId, { status: 'no_answer' }, { ...env, CAMPAIGN_QUEUE: q.queue });
      expect((await env.DB.prepare('SELECT status FROM campaign_leads WHERE call_id = ?').bind(callId).first<any>()).status).toBe('failed');
      expect(q.msgs).toHaveLength(0);
    });

    it('a generic failure is not retried and does not mark the number invalid', async () => {
      const { lead, callId } = await campaignCall('3');
      const q = sent();
      await postSarvam(callId, { status: 'failed', failure_reason: 'exotel: provider error' }, { ...env, CAMPAIGN_QUEUE: q.queue });
      expect((await env.DB.prepare('SELECT status FROM campaign_leads WHERE call_id = ?').bind(callId).first<any>()).status).toBe('failed');
      expect(q.msgs).toHaveLength(0);
      expect((await env.DB.prepare('SELECT phone_invalid FROM leads WHERE id = ?').bind(lead).first<any>()).phone_invalid).toBe(0);
    });

    it('an invalid number marks the lead phone_invalid; dispatch then skips it', async () => {
      const { camp, lead, callId } = await campaignCall('4');
      const q = sent();
      await postSarvam(callId, { status: 'failed', failure_reason: 'exotel: Invalid phone number' }, { ...env, CAMPAIGN_QUEUE: q.queue });
      expect(q.msgs).toHaveLength(0);
      expect((await env.DB.prepare('SELECT phone_invalid FROM leads WHERE id = ?').bind(lead).first<any>()).phone_invalid).toBe(1);

      // Even if it were queued again, dispatch skips it without dialling.
      await env.DB.prepare("UPDATE campaign_leads SET status = 'retry_pending' WHERE call_id = ?").bind(callId).run();
      await env.DB.prepare("UPDATE campaigns SET status = 'running' WHERE id = ?").bind(camp).run();
      const r = await processCampaignJob(env as any, { campaign_id: camp, lead_id: lead, business_id: BIZ, idempotency_key: 'k', attempts: 0 });
      expect(r).toMatchObject({ success: true, reason: 'phone_invalid' });
      expect((await env.DB.prepare('SELECT status FROM campaign_leads WHERE call_id = ?').bind(callId).first<any>()).status).toBe('skipped_invalid');
    });

    it('campaign start skips phone_invalid leads; editing the phone clears the flag', async () => {
      const token = await signJWT({ sub: USER, phone: PHONE, business_id: BIZ, type: 'access' }, jwtSecret, 3600);
      await seedLead('lead_inv_a', '919811300001', '1');
      await env.DB.batch([
        env.DB.prepare("INSERT OR REPLACE INTO campaigns (id, business_id, purpose, status, calling_hours_start, calling_hours_end, total_leads) VALUES ('camp_inv', ?, 'Inv', 'draft', 0, 24, 1)").bind(BIZ),
        env.DB.prepare("INSERT OR REPLACE INTO campaign_leads (campaign_id, lead_id, status, attempts) VALUES ('camp_inv', 'lead_inv_a', 'pending', 0)"),
      ]);
      const res = await app.fetch(new Request('http://localhost/campaigns/camp_inv/start', {
        method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` }, body: '{}',
      }), env);
      expect(res.status).toBe(200);
      const cl = await env.DB.prepare("SELECT status FROM campaign_leads WHERE campaign_id = 'camp_inv'").first<any>();
      expect(cl.status).toBe('skipped_invalid');

      const lead = await app.fetch(new Request('http://localhost/leads/lead_inv_a', {
        headers: { Authorization: `Bearer ${token}` },
      }), env);
      expect(((await lead.json()) as any).phone_invalid).toBe(true);

      const same = await app.fetch(new Request('http://localhost/leads/lead_inv_a', {
        method: 'PATCH', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
        body: JSON.stringify({ name: 'Renamed' }),
      }), env);
      expect(((await same.json()) as any).phone_invalid).toBe(true);
      const fixed = await app.fetch(new Request('http://localhost/leads/lead_inv_a', {
        method: 'PATCH', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
        body: JSON.stringify({ phone: '9811300009' }),
      }), env);
      expect(fixed.status).toBe(200);
      expect(((await fixed.json()) as any).phone_invalid).toBe(false);
    });
  });

  describe('long-call watchdog', () => {
    it('flags calls past MAX_CALL_MINUTES once', async () => {
      await seedLead('lead_long', '919811400001');
      await seedCall('call_long', 'lead_long', null, '-9 minutes');
      await seedCall('call_short', 'lead_long', null, '-2 minutes');
      const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
      expect(await runLongCallWatchdog(env as any)).toBeGreaterThanOrEqual(1);
      expect(warn.mock.calls.some((c) => String(c[0]).includes('call_long'))).toBe(true);
      expect(warn.mock.calls.some((c) => String(c[0]).includes('call_short'))).toBe(false);
      const flagged = await env.DB.prepare('SELECT overrun_flagged_at FROM calls WHERE id = ?').bind('call_long').first<any>();
      expect(flagged.overrun_flagged_at).toBeTruthy();
      expect(await runLongCallWatchdog(env as any)).toBe(0);
      expect(await runLongCallWatchdog({ ...env, MAX_CALL_MINUTES: '1' } as any)).toBe(1); // call_short now
    });
  });

  describe('GET /admin/economics', () => {
    const get = (qs = '', headers: Record<string, string> = {}, e: any = { ...env, HEALTH_CHECK_SECRET: 'hc_secret' }) =>
      app.fetch(new Request(`http://localhost/admin/economics${qs}`, { headers }), e);

    it('is guarded by HEALTH_CHECK_SECRET and validates days', async () => {
      expect((await get('', {}, env)).status).toBe(500);
      expect((await get()).status).toBe(401);
      expect((await get('', { 'x-health-key': 'nope' })).status).toBe(401);
      expect((await get('?days=0', { 'x-health-key': 'hc_secret' })).status).toBe(400);
      expect((await get('?days=abc', { authorization: 'Bearer hc_secret' })).status).toBe(400);
    });

    it('reports revenue ex-GST, minutes, cost, margin and waste per plan', async () => {
      const before = await economicsReport(env as any, 30);
      await env.DB.batch([
        env.DB.prepare(
          `INSERT INTO payments (id, razorpay_payment_id, business_id, plan_id, kind, amount_paise, base_paise, gst_paise, status)
           VALUES ('pe1', 'pay_econ_1', ?, 'growth', 'plan', 1415900, 1199900, 216000, 'paid'),
                  ('pe2', 'pay_econ_2', ?, 'topup_250', 'topup', 176900, 149900, 27000, 'paid'),
                  ('pe3', 'pay_econ_3', ?, 'growth', 'plan', 100, 100, 0, 'amount_mismatch'),
                  ('pe4', 'pay_econ_4', ?, 'growth', 'plan', 1415900, 1199900, 216000, 'paid')`
        ).bind(BIZ, BIZ, BIZ, BIZ),
        // An old payment outside the window.
        env.DB.prepare("UPDATE payments SET created_at = datetime('now', '-90 days') WHERE id = 'pe4'"),
        env.DB.prepare(
          `INSERT INTO usage_ledger (call_id, business_id, billable_seconds, billed_minutes, duration_seconds, cost_inr, plan_id)
           VALUES ('led_e1', ?, 600, 10, 600, 26, 'growth'), ('led_e2', ?, 0, 0, 125, 7.8, 'growth')`
        ).bind(BIZ, BIZ),
      ]);
      const res = await get('?days=30', { 'x-health-key': 'hc_secret' });
      expect(res.status).toBe(200);
      const r = (await res.json()) as any;
      expect(r.days).toBe(30);
      expect(r.cost_per_min_inr.total).toBe(2.6);
      const growth = r.by_plan.find((p: any) => p.plan_id === 'growth');
      const growthBefore = before.by_plan.find((p: any) => p.plan_id === 'growth') ?? { revenue_inr: 0, minutes_billed: 0, cost_inr: 0, wasted_minutes: 0 };
      expect(growth.revenue_inr - growthBefore.revenue_inr).toBeCloseTo(11999, 2);
      expect(growth.minutes_billed - growthBefore.minutes_billed).toBe(10);
      expect(growth.cost_inr - growthBefore.cost_inr).toBeCloseTo(33.8, 2);
      expect(growth.wasted_minutes - growthBefore.wasted_minutes).toBe(3);
      expect(r.by_plan.find((p: any) => p.plan_id === 'topup').revenue_inr).toBeCloseTo(1499, 2);
      expect(r.total.gst_collected_inr - before.total.gst_collected_inr).toBeCloseTo(2430, 2);
      expect(r.total.payments - before.total.payments).toBe(2);
      expect(r.total.gross_margin_inr).toBeCloseTo(r.total.revenue_inr - r.total.cost_inr, 2);
      expect(r.total.gross_margin_pct).toBeGreaterThan(0);
      expect(r.by_product.find((p: any) => p.product_id === 'topup_250')).toMatchObject({ kind: 'topup', payments: 1 });
    });
  });
});
