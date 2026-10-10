import { describe, it, expect, beforeAll } from 'vitest';
import { env } from 'cloudflare:test';
import { migrateTestDb } from './setup-db';
import app from '../src/index';
import { signJWT } from '../src/auth';
import { verifyRazorpaySignature, isMockRazorpay } from '../src/routes/billing';
import { runBillingRenewals, trialMinutes, getPlan, billingView, statusBlocksDialing } from '../src/services/plans';
import { processCampaignJob } from '../src/services/campaign_queue';

const WEBHOOK_SECRET = 'rzp_webhook_test_secret';
const jwtSecret = 'test-jwt-signing-secret-key-32chars-min-length';

async function hmacHex(secret: string, body: string): Promise<string> {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey('raw', enc.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const sig = await crypto.subtle.sign('HMAC', key, enc.encode(body));
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

const billingEnv = (extra: Record<string, unknown> = {}) => ({ ...env, RAZORPAY_WEBHOOK_SECRET: WEBHOOK_SECRET, ...extra });

function call(path: string, init: RequestInit = {}, e: any = env, token?: string) {
  const headers: Record<string, string> = { 'Content-Type': 'application/json', ...(init.headers as any) };
  if (token) headers.Authorization = `Bearer ${token}`;
  return app.fetch(new Request(`http://localhost${path}`, { ...init, headers }), e);
}

async function registerPhone(phone: string, name = 'Trial Biz') {
  const ip = `10.9.${Math.floor(Math.random() * 250)}.${Math.floor(Math.random() * 250)}`;
  const otpRes = await call('/auth/otp/request', { method: 'POST', body: JSON.stringify({ phone }), headers: { 'cf-connecting-ip': ip } });
  const { debug_otp } = (await otpRes.json()) as any;
  const reg = await call('/auth/register', { method: 'POST', body: JSON.stringify({ phone, otp: debug_otp, business_name: name }), headers: { 'cf-connecting-ip': ip } });
  expect(reg.status).toBe(200);
  const tokens = (await reg.json()) as any;
  const user = await env.DB.prepare('SELECT id, business_id FROM users WHERE phone = ?').bind(phone).first<any>();
  return { token: tokens.access_token as string, userId: user.id as string, businessId: user.business_id as string };
}

function paidEvent(businessId: string, paymentId: string, amount = 499900) {
  return JSON.stringify({
    entity: 'event',
    event: 'payment_link.paid',
    payload: {
      payment_link: { entity: { id: 'plink_test', amount, amount_paid: amount, currency: 'INR', notes: { business_id: businessId, plan_id: 'starter' }, status: 'paid' } },
      payment: { entity: { id: paymentId, amount, currency: 'INR', status: 'captured', email: 'owner@example.com', contact: '+919800000001' } },
    },
  });
}

async function postWebhook(body: string, sig?: string) {
  return call('/webhooks/razorpay', {
    method: 'POST',
    body,
    headers: sig === undefined ? {} : { 'X-Razorpay-Signature': sig },
  }, billingEnv());
}

async function seedBiz(id: string, usage: { plan_id: string; plan_status: string; included: number; used: number; period_end: string | null }) {
  await env.DB.batch([
    env.DB.prepare("INSERT OR REPLACE INTO businesses (id, name) VALUES (?, 'Plan Biz')").bind(id),
    env.DB.prepare(
      `INSERT OR REPLACE INTO usage (id, business_id, plan_id, plan_status, current_period_end, plan_name, included_minutes, minutes_used)
       VALUES (?, ?, ?, ?, ?, 'x', ?, ?)`
    ).bind(`usg_${id}`, id, usage.plan_id, usage.plan_status, usage.period_end, usage.included, usage.used),
  ]);
}

describe('Plans, trials and Razorpay billing', () => {
  beforeAll(async () => {
    await migrateTestDb();
  });

  describe('plan catalogue', () => {
    it('trial minutes come from TRIAL_MINUTES with a 30 fallback', () => {
      expect(trialMinutes({})).toBe(30);
      expect(trialMinutes({ TRIAL_MINUTES: '45' })).toBe(45);
      expect(trialMinutes({ TRIAL_MINUTES: 'abc' })).toBe(30);
      expect(getPlan('starter')).toMatchObject({ priceInr: 4999, includedMinutes: 1000, paid: true });
      expect(getPlan('trial')).toMatchObject({ priceInr: 0, includedMinutes: 30, paid: false });
      expect(statusBlocksDialing('past_due')).toBe(true);
      expect(statusBlocksDialing('cancelled')).toBe(true);
      expect(statusBlocksDialing('trial')).toBe(false);
      expect(statusBlocksDialing('active')).toBe(false);
    });

    it('billingView reports minutes left and the checkout plan', () => {
      const v = billingView({ plan_id: 'trial', plan_status: 'trial', included_minutes: 30, minutes_used: 40 }, env as any);
      expect(v).toMatchObject({ plan_id: 'trial', plan_status: 'trial', minutes_left: 0, checkout_plan: { plan_id: 'starter', price_inr: 4999 } });
    });
  });

  describe('trial grants', () => {
    it('new signup gets TRIAL_MINUTES; same phone after account deletion gets 0', async () => {
      const phone = '919830077701';
      const first = await registerPhone(phone);
      const usage = await env.DB.prepare('SELECT * FROM usage WHERE business_id = ?').bind(first.businessId).first<any>();
      expect(usage).toMatchObject({ plan_id: 'trial', plan_status: 'trial', included_minutes: 30, minutes_used: 0, current_period_end: null });

      const usageRes = await call('/usage', {}, env, first.token);
      const u = (await usageRes.json()) as any;
      expect(u.subscription).toMatchObject({ plan_id: 'trial', plan_status: 'trial', included_minutes: 30 });

      const del = await call('/auth/account', { method: 'DELETE' }, env, first.token);
      expect(del.status).toBe(200);

      const again = await registerPhone(phone, 'Second Try');
      const usage2 = await env.DB.prepare('SELECT * FROM usage WHERE business_id = ?').bind(again.businessId).first<any>();
      expect(usage2).toMatchObject({ plan_id: 'trial', plan_status: 'trial', included_minutes: 0 });
    });

    it('trial_grants stores only hashes, never the raw phone', async () => {
      const phone = '919830077702';
      await registerPhone(phone);
      const rows = await env.DB.prepare('SELECT identity_hash FROM trial_grants').all<any>();
      expect(rows.results.length).toBeGreaterThan(0);
      for (const r of rows.results) {
        expect(r.identity_hash).toMatch(/^[0-9a-f]{64}$/);
        expect(r.identity_hash).not.toContain('9830077702');
      }
    });
  });

  describe('GET /billing and POST /billing/checkout', () => {
    it('returns the plan view', async () => {
      const { token } = await registerPhone('919830077703');
      const res = await call('/billing', {}, env, token);
      expect(res.status).toBe(200);
      expect(await res.json()).toMatchObject({ plan_id: 'trial', plan_status: 'trial', minutes_left: 30, current_period_end: null, price_inr: 0 });
    });

    it('checkout without Razorpay keys returns 503 billing_not_configured', async () => {
      const { token } = await registerPhone('919830077704');
      const res = await call('/billing/checkout', { method: 'POST', body: '{}' }, env, token);
      expect(res.status).toBe(503);
      expect(((await res.json()) as any).code).toBe('billing_not_configured');
    });

    it('checkout with mock keys in development returns a fake URL', async () => {
      const { token } = await registerPhone('919830077705');
      const e = billingEnv({ RAZORPAY_KEY_ID: 'mock_key', RAZORPAY_KEY_SECRET: 'mock_secret' });
      expect(isMockRazorpay(e as any)).toBe(true);
      expect(isMockRazorpay({ ...e, ENVIRONMENT: 'production' } as any)).toBe(false);
      const res = await call('/billing/checkout', { method: 'POST', body: '{}' }, e, token);
      expect(res.status).toBe(200);
      const d = (await res.json()) as any;
      expect(d.url).toMatch(/^https:\/\/rzp\.io\/mock\//);
    });

    it('checkout rejects unknown plans', async () => {
      const { token } = await registerPhone('919830077706');
      const e = billingEnv({ RAZORPAY_KEY_ID: 'mock_key', RAZORPAY_KEY_SECRET: 'mock_secret' });
      const res = await call('/billing/checkout', { method: 'POST', body: JSON.stringify({ plan_id: 'trial' }) }, e, token);
      expect(res.status).toBe(400);
    });
  });

  describe('Razorpay webhook', () => {
    it('verifies signatures in constant time helper', async () => {
      const body = '{"a":1}';
      const good = await hmacHex(WEBHOOK_SECRET, body);
      expect(await verifyRazorpaySignature(body, good, WEBHOOK_SECRET)).toBe(true);
      expect(await verifyRazorpaySignature(body, good.replace(/.$/, good.endsWith('0') ? '1' : '0'), WEBHOOK_SECRET)).toBe(false);
      expect(await verifyRazorpaySignature(body, undefined, WEBHOOK_SECRET)).toBe(false);
    });

    it('rejects a missing or invalid signature and changes nothing', async () => {
      await seedBiz('biz_rzp_bad', { plan_id: 'trial', plan_status: 'trial', included: 30, used: 30, period_end: null });
      const body = paidEvent('biz_rzp_bad', 'pay_bad_1');
      expect((await postWebhook(body)).status).toBe(401);
      expect((await postWebhook(body, 'deadbeef')).status).toBe(401);
      expect((await postWebhook(body, await hmacHex('wrong-secret', body))).status).toBe(401);
      const row = await env.DB.prepare('SELECT plan_status FROM usage WHERE business_id = ?').bind('biz_rzp_bad').first<any>();
      expect(row.plan_status).toBe('trial');
      const pay = await env.DB.prepare('SELECT COUNT(*) AS n FROM payments WHERE razorpay_payment_id = ?').bind('pay_bad_1').first<any>();
      expect(pay.n).toBe(0);
    });

    it('returns 503 when the webhook secret is not configured', async () => {
      const res = await call('/webhooks/razorpay', { method: 'POST', body: '{}' }, env);
      expect(res.status).toBe(503);
    });

    it('payment_link.paid activates the plan exactly once (idempotent replay)', async () => {
      await seedBiz('biz_rzp_paid', { plan_id: 'trial', plan_status: 'trial', included: 30, used: 25, period_end: null });
      const body = paidEvent('biz_rzp_paid', 'pay_ok_1');
      const sig = await hmacHex(WEBHOOK_SECRET, body);

      const r1 = await postWebhook(body, sig);
      expect(r1.status).toBe(200);
      expect(await r1.json()).toMatchObject({ applied: true, duplicate: false });

      const row = await env.DB.prepare('SELECT * FROM usage WHERE business_id = ?').bind('biz_rzp_paid').first<any>();
      expect(row).toMatchObject({ plan_id: 'starter', plan_status: 'active', included_minutes: 1000, minutes_used: 0, price_inr: 4999 });
      const end = new Date(`${row.current_period_end.replace(' ', 'T')}Z`).getTime();
      expect(end - Date.now()).toBeGreaterThan(27 * 86400_000);
      expect(end - Date.now()).toBeLessThan(32 * 86400_000);

      // Use some minutes, then the webhook is redelivered: no reset, no extension, one payment row.
      await env.DB.prepare('UPDATE usage SET minutes_used = 12 WHERE business_id = ?').bind('biz_rzp_paid').run();
      const r2 = await postWebhook(body, sig);
      expect(await r2.json()).toMatchObject({ applied: false, duplicate: true });
      const row2 = await env.DB.prepare('SELECT * FROM usage WHERE business_id = ?').bind('biz_rzp_paid').first<any>();
      expect(row2.minutes_used).toBe(12);
      expect(row2.current_period_end).toBe(row.current_period_end);

      const pays = await env.DB.prepare('SELECT * FROM payments WHERE business_id = ?').bind('biz_rzp_paid').all<any>();
      expect(pays.results).toHaveLength(1);
      expect(pays.results[0]).toMatchObject({ amount_paise: 499900, status: 'paid', plan_id: 'starter' });
      expect(pays.results[0].applied_at).toBeTruthy();
      expect(pays.results[0].period_end).toBe(row.current_period_end);
    });

    it('an underpaid amount is recorded but never activates the plan', async () => {
      await seedBiz('biz_rzp_under', { plan_id: 'trial', plan_status: 'trial', included: 30, used: 30, period_end: null });
      const body = paidEvent('biz_rzp_under', 'pay_under_1', 100);
      const res = await postWebhook(body, await hmacHex(WEBHOOK_SECRET, body));
      expect(res.status).toBe(200);
      expect(await res.json()).toMatchObject({ applied: false });
      const row = await env.DB.prepare('SELECT plan_status FROM usage WHERE business_id = ?').bind('biz_rzp_under').first<any>();
      expect(row.plan_status).toBe('trial');
    });

    it('ignores other events', async () => {
      const body = JSON.stringify({ event: 'payment.failed', payload: {} });
      const res = await postWebhook(body, await hmacHex(WEBHOOK_SECRET, body));
      expect(res.status).toBe(200);
      expect(await res.json()).toMatchObject({ ignored: 'payment.failed' });
    });

    it('a payment on a past_due plan renews it from now', async () => {
      await seedBiz('biz_rzp_renew', { plan_id: 'starter', plan_status: 'past_due', included: 1000, used: 1000, period_end: '2020-01-01 00:00:00' });
      const body = paidEvent('biz_rzp_renew', 'pay_renew_1');
      await postWebhook(body, await hmacHex(WEBHOOK_SECRET, body));
      const row = await env.DB.prepare('SELECT * FROM usage WHERE business_id = ?').bind('biz_rzp_renew').first<any>();
      expect(row).toMatchObject({ plan_status: 'active', minutes_used: 0, included_minutes: 1000 });
      expect(new Date(`${row.current_period_end.replace(' ', 'T')}Z`).getTime()).toBeGreaterThan(Date.now());
    });
  });

  describe('renewal cron', () => {
    it('marks expired active plans past_due and leaves the rest alone', async () => {
      await seedBiz('biz_cron_expired', { plan_id: 'starter', plan_status: 'active', included: 1000, used: 10, period_end: '2020-01-01 00:00:00' });
      await seedBiz('biz_cron_future', { plan_id: 'starter', plan_status: 'active', included: 1000, used: 10, period_end: '2999-01-01 00:00:00' });
      await seedBiz('biz_cron_legacy', { plan_id: 'starter', plan_status: 'active', included: 1000, used: 10, period_end: null });
      await seedBiz('biz_cron_trial', { plan_id: 'trial', plan_status: 'trial', included: 30, used: 0, period_end: null });

      await runBillingRenewals(env as any);

      const status = async (id: string) =>
        (await env.DB.prepare('SELECT plan_status, minutes_used FROM usage WHERE business_id = ?').bind(id).first<any>());
      expect(await status('biz_cron_expired')).toMatchObject({ plan_status: 'past_due', minutes_used: 10 });
      expect((await status('biz_cron_future')).plan_status).toBe('active');
      expect((await status('biz_cron_legacy')).plan_status).toBe('active');
      expect((await status('biz_cron_trial')).plan_status).toBe('trial');
    });

    it('the scheduled handler runs the billing sweep', async () => {
      await seedBiz('biz_cron_sched', { plan_id: 'starter', plan_status: 'active', included: 1000, used: 0, period_end: '2020-01-01 00:00:00' });
      const waits: Promise<any>[] = [];
      await app.scheduled!({} as any, env as any, { waitUntil: (p: Promise<any>) => waits.push(p), passThroughOnException() {} } as any);
      await Promise.allSettled(waits);
      const row = await env.DB.prepare('SELECT plan_status FROM usage WHERE business_id = ?').bind('biz_cron_sched').first<any>();
      expect(row.plan_status).toBe('past_due');
    });
  });

  describe('dialing is blocked when the plan is past_due', () => {
    const bizId = 'biz_blocked';
    let token: string;
    beforeAll(async () => {
      await seedBiz(bizId, { plan_id: 'starter', plan_status: 'past_due', included: 1000, used: 0, period_end: '2020-01-01 00:00:00' });
      await env.DB.batch([
        env.DB.prepare("INSERT OR REPLACE INTO users (id, phone, business_id) VALUES ('usr_blocked', '919830077799', ?)").bind(bizId),
        env.DB.prepare("INSERT OR REPLACE INTO leads (id, business_id, name, phone, status, consent) VALUES ('lead_blocked', ?, 'Blocked Lead', '919830077798', 'new', 'explicit')").bind(bizId),
        env.DB.prepare("INSERT OR REPLACE INTO agents (id, business_id, name, role, status, calling_hours_start, calling_hours_end) VALUES ('agent_blocked', ?, 'Maya', 'Sales', 'active', 0, 24)").bind(bizId),
        env.DB.prepare("INSERT OR REPLACE INTO campaigns (id, business_id, purpose, status, total_leads, calling_hours_start, calling_hours_end, created_at) VALUES ('cmp_blocked', ?, 'x', 'running', 1, 0, 24, datetime('now'))").bind(bizId),
        env.DB.prepare("INSERT OR REPLACE INTO campaign_leads (campaign_id, lead_id, status) VALUES ('cmp_blocked', 'lead_blocked', 'queued')"),
      ]);
      token = await signJWT({ sub: 'usr_blocked', phone: '919830077799', business_id: bizId, type: 'access' }, jwtSecret, 3600);
    });

    it('POST /leads/:id/call returns 402 plan_inactive', async () => {
      const res = await call('/leads/lead_blocked/call', { method: 'POST', body: '{}' }, env, token);
      expect(res.status).toBe(402);
      expect(((await res.json()) as any).code).toBe('plan_inactive');
    });

    it('POST /campaigns/:id/start returns 402 plan_inactive', async () => {
      const res = await call('/campaigns/cmp_blocked/start', { method: 'POST', body: '{}' }, env, token);
      expect(res.status).toBe(402);
      expect(((await res.json()) as any).code).toBe('plan_inactive');
    });

    it('queued campaign dispatch pauses the campaign instead of dialing', async () => {
      const r = await processCampaignJob(env as any, { campaign_id: 'cmp_blocked', business_id: bizId, lead_id: 'lead_blocked', idempotency_key: 'k', attempts: 0 });
      expect(r.reason).toBe('plan_inactive');
      const camp = await env.DB.prepare("SELECT status FROM campaigns WHERE id = 'cmp_blocked'").first<any>();
      expect(camp.status).toBe('paused');
      const calls = await env.DB.prepare('SELECT COUNT(*) AS n FROM calls WHERE business_id = ?').bind(bizId).first<any>();
      expect(calls.n).toBe(0);
    });
  });

  describe('account deletion keeps anonymised billing records', () => {
    it('anonymises ledger and payments, keeps trial grant', async () => {
      const phone = '919830077710';
      const { token, businessId } = await registerPhone(phone);
      const body = paidEvent(businessId, 'pay_del_1');
      await postWebhook(body, await hmacHex(WEBHOOK_SECRET, body));
      await env.DB.prepare(
        "INSERT INTO usage_ledger (call_id, business_id, billable_seconds, billed_minutes) VALUES ('call_del_1', ?, 120, 2)"
      ).bind(businessId).run();
      const grantsBefore = (await env.DB.prepare('SELECT COUNT(*) AS n FROM trial_grants').first<any>()).n;

      const del = await call('/auth/account', { method: 'DELETE' }, env, token);
      expect(del.status).toBe(200);

      const pay = await env.DB.prepare("SELECT * FROM payments WHERE razorpay_payment_id = 'pay_del_1'").first<any>();
      expect(pay).toBeTruthy();
      expect(pay.business_id).toMatch(/^anon_[0-9a-f]{24}$/);
      expect(pay.contact_email).toBeNull();
      expect(pay.contact_phone).toBeNull();
      expect(pay.anonymized_at).toBeTruthy();
      expect(pay.amount_paise).toBe(499900);

      const ledger = await env.DB.prepare("SELECT * FROM usage_ledger WHERE call_id = 'call_del_1'").first<any>();
      expect(ledger).toBeTruthy();
      expect(ledger.business_id).toBe(pay.business_id);
      expect(ledger.billed_minutes).toBe(2);

      expect(await env.DB.prepare('SELECT COUNT(*) AS n FROM payments WHERE business_id = ?').bind(businessId).first<any>())
        .toMatchObject({ n: 0 });
      expect((await env.DB.prepare('SELECT COUNT(*) AS n FROM trial_grants').first<any>()).n).toBe(grantsBefore);
      expect(await env.DB.prepare('SELECT id FROM usage WHERE business_id = ?').bind(businessId).first()).toBeNull();
    });
  });
});
