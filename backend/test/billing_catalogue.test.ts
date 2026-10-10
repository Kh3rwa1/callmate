import { describe, it, expect, beforeAll, vi, afterEach } from 'vitest';
import { env } from 'cloudflare:test';
import { migrateTestDb } from './setup-db';
import app from '../src/index';
import { signJWT } from '../src/auth';
import { expectedCharge } from '../src/routes/billing';
import {
  billingView, gstRate, priceWithGst, PRODUCTS, PRODUCT_IDS, runBillingRenewals, getPlan,
  addBonusMinutes, minutesRemaining, minutesBreakdown,
} from '../src/services/plans';
import { hasMinutesHeadroom } from '../src/services/campaign_queue';

const WEBHOOK_SECRET = 'rzp_webhook_test_secret';
const jwtSecret = 'test-jwt-signing-secret-key-32chars-min-length';

async function hmacHex(secret: string, body: string): Promise<string> {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey('raw', enc.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const sig = await crypto.subtle.sign('HMAC', key, enc.encode(body));
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

const mockKeys = { RAZORPAY_KEY_ID: 'mock_key', RAZORPAY_KEY_SECRET: 'mock_secret' };

async function seedBiz(id: string, usage: {
  plan_id: string; plan_status: string; included: number; used: number; period_end: string | null;
  annual_until?: string | null; annual_plan_id?: string | null; topup?: number;
}) {
  await env.DB.batch([
    env.DB.prepare("INSERT OR REPLACE INTO businesses (id, name) VALUES (?, 'Cat Biz')").bind(id),
    env.DB.prepare('INSERT OR REPLACE INTO users (id, phone, business_id) VALUES (?, ?, ?)').bind(`usr_${id}`, `9198${id.length}${Math.floor(Math.random() * 1e7)}`, id),
    env.DB.prepare(
      `INSERT OR REPLACE INTO usage (id, business_id, plan_id, plan_status, current_period_end, plan_name, included_minutes,
         minutes_used, annual_until, annual_plan_id, topup_minutes, billing_cycle)
       VALUES (?, ?, ?, ?, ?, 'x', ?, ?, ?, ?, ?, ?)`
    ).bind(`usg_${id}`, id, usage.plan_id, usage.plan_status, usage.period_end, usage.included, usage.used,
      usage.annual_until ?? null, usage.annual_plan_id ?? null, usage.topup ?? 0, usage.annual_until ? 'annual' : 'monthly'),
  ]);
}

async function tokenFor(id: string) {
  const u = await env.DB.prepare('SELECT phone FROM users WHERE business_id = ?').bind(id).first<any>();
  return signJWT({ sub: `usr_${id}`, phone: u.phone, business_id: id, type: 'access' }, jwtSecret, 3600);
}

function checkout(token: string, body: unknown, extra: Record<string, unknown> = mockKeys) {
  return app.fetch(new Request('http://localhost/billing/checkout', {
    method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: typeof body === 'string' ? body : JSON.stringify(body),
  }), { ...env, ...extra });
}

/** A payment_link.paid event as created by this version's checkout (notes carry the GST split). */
function paidEvent(businessId: string, paymentId: string, productId: string, opts: { amount?: number; legacy?: boolean } = {}) {
  const p = PRODUCTS[productId as keyof typeof PRODUCTS];
  const price = priceWithGst(p.priceInr, {});
  const amount = opts.amount ?? price.total_inr * 100;
  const notes: Record<string, string> = { business_id: businessId, plan_id: productId };
  if (!opts.legacy) {
    notes.base_paise = String(price.base_inr * 100);
    notes.gst_paise = String(price.gst_inr * 100);
    notes.total_paise = String(price.total_inr * 100);
  }
  return JSON.stringify({
    entity: 'event', event: 'payment_link.paid',
    payload: {
      payment_link: { entity: { id: `plink_${paymentId}`, amount, amount_paid: amount, currency: 'INR', notes, status: 'paid' } },
      payment: { entity: { id: paymentId, amount, currency: 'INR', status: 'captured' } },
    },
  });
}

async function pay(body: string) {
  const res = await app.fetch(new Request('http://localhost/webhooks/razorpay', {
    method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Razorpay-Signature': await hmacHex(WEBHOOK_SECRET, body) }, body,
  }), { ...env, RAZORPAY_WEBHOOK_SECRET: WEBHOOK_SECRET });
  expect(res.status).toBe(200);
  return (await res.json()) as any;
}

const usageOf = (id: string) => env.DB.prepare('SELECT * FROM usage WHERE business_id = ?').bind(id).first<any>();
const ts = (s: string) => new Date(`${s.replace(' ', 'T')}Z`).getTime();
const DAY = 86400_000;

describe('Plan catalogue, GST and top-ups', () => {
  beforeAll(async () => {
    await migrateTestDb();
  });
  afterEach(() => vi.restoreAllMocks());

  describe('catalogue + GST', () => {
    it('prices every product and adds GST rounded to whole rupees', () => {
      expect(PRODUCT_IDS).toEqual(['starter', 'growth', 'starter_annual', 'growth_annual', 'topup_250', 'topup_1000']);
      expect(PRODUCTS.starter).toMatchObject({ priceInr: 4999, minutes: 1000, kind: 'plan', months: 1 });
      expect(PRODUCTS.growth).toMatchObject({ priceInr: 11999, minutes: 3000, kind: 'plan' });
      expect(PRODUCTS.starter_annual).toMatchObject({ priceInr: 49990, minutes: 1000, kind: 'annual', months: 12, planId: 'starter' });
      expect(PRODUCTS.growth_annual).toMatchObject({ priceInr: 119990, minutes: 3000, kind: 'annual', planId: 'growth' });
      expect(PRODUCTS.topup_250).toMatchObject({ priceInr: 1499, minutes: 250, kind: 'topup', planId: null });
      expect(PRODUCTS.topup_1000).toMatchObject({ priceInr: 5499, minutes: 1000, kind: 'topup' });
      expect(getPlan('growth')).toMatchObject({ includedMinutes: 3000, priceInr: 11999 });

      expect(gstRate({})).toBe(0.18);
      expect(gstRate({ GST_RATE: '0.05' })).toBe(0.05);
      expect(gstRate({ GST_RATE: '0' })).toBe(0);
      expect(gstRate({ GST_RATE: '7' })).toBe(0.18);
      expect(gstRate({ GST_RATE: 'abc' })).toBe(0.18);
      expect(priceWithGst(4999, {})).toEqual({ base_inr: 4999, gst_inr: 900, total_inr: 5899 });
      expect(priceWithGst(11999, {})).toEqual({ base_inr: 11999, gst_inr: 2160, total_inr: 14159 });
      expect(priceWithGst(1499, {})).toEqual({ base_inr: 1499, gst_inr: 270, total_inr: 1769 });
      expect(priceWithGst(4999, { GST_RATE: '0' })).toEqual({ base_inr: 4999, gst_inr: 0, total_inr: 4999 });
    });

    it('billingView lists plans and top-ups with GST and gates top-ups on an active plan', () => {
      const trial = billingView({ plan_id: 'trial', plan_status: 'trial', included_minutes: 30, minutes_used: 0 }, env as any);
      expect(trial.can_buy_topup).toBe(false);
      expect(trial.checkout_plan).toMatchObject({ plan_id: 'starter', price_inr: 4999, gst_inr: 900, total_inr: 5899 });
      expect(trial.plans.map((p) => p.plan_id)).toEqual(['starter', 'growth', 'starter_annual', 'growth_annual']);
      expect(trial.topups.map((p) => p.plan_id)).toEqual(['topup_250', 'topup_1000']);
      const growth = billingView({ plan_id: 'growth', plan_status: 'active', included_minutes: 3250, minutes_used: 10, topup_minutes: 250, billing_cycle: 'annual', annual_until: '2027-10-01 00:00:00' }, env as any);
      expect(growth).toMatchObject({ plan_id: 'growth', can_buy_topup: true, topup_minutes: 250, billing_cycle: 'annual', annual_until: '2027-10-01 00:00:00', gst_rate: 0.18 });
      expect(growth.checkout_plan.plan_id).toBe('growth');
    });

    it('expectedCharge trusts our notes only when they add up, else falls back to the base price', () => {
      const p = PRODUCTS.starter;
      expect(expectedCharge(p, { base_paise: '499900', gst_paise: '90000', total_paise: '589900' }, 589900))
        .toEqual({ minPaise: 589900, basePaise: 499900, gstPaise: 90000 });
      // Legacy link (no notes): base only, no GST.
      expect(expectedCharge(p, {}, 499900)).toEqual({ minPaise: 499900, basePaise: 499900, gstPaise: 0 });
      // Inconsistent / below-catalogue notes are ignored.
      expect(expectedCharge(p, { base_paise: '100', gst_paise: '0', total_paise: '100' }, 100).minPaise).toBe(499900);
    });
  });

  describe('POST /billing/checkout', () => {
    it('accepts every catalogue id and returns the GST breakdown (mock Razorpay)', async () => {
      await seedBiz('biz_cat_active', { plan_id: 'starter', plan_status: 'active', included: 1000, used: 0, period_end: '2999-01-01 00:00:00' });
      const token = await tokenFor('biz_cat_active');
      for (const id of ['growth', 'starter_annual', 'topup_1000']) {
        const res = await checkout(token, { plan_id: id });
        expect(res.status).toBe(200);
        const d = (await res.json()) as any;
        expect(d.plan_id).toBe(id);
        expect(d.total_inr).toBe(priceWithGst(PRODUCTS[id as 'growth'].priceInr, {}).total_inr);
      }
      const dflt = (await (await checkout(token, {})).json()) as any;
      expect(dflt).toMatchObject({ plan_id: 'starter', base_inr: 4999, gst_inr: 900, total_inr: 5899 });
      const nul = (await (await checkout(token, { plan_id: null })).json()) as any;
      expect(nul.plan_id).toBe('starter');
    });

    it('rejects unknown plans and top-ups without an active plan', async () => {
      await seedBiz('biz_cat_trial', { plan_id: 'trial', plan_status: 'trial', included: 30, used: 0, period_end: null });
      const token = await tokenFor('biz_cat_trial');
      for (const bad of [{ plan_id: 'trial' }, { plan_id: 'platinum' }, { plan_id: 5 }]) {
        const res = await checkout(token, bad);
        expect(res.status).toBe(400);
        expect(((await res.json()) as any).code).toBe('invalid_plan');
      }
      const topup = await checkout(token, { plan_id: 'topup_250' });
      expect(topup.status).toBe(409);
      expect(((await topup.json()) as any).code).toBe('plan_not_active');
      expect((await checkout(token, { plan_id: 'growth_annual' })).status).toBe(200);
    });

    it('charges Razorpay base + GST and stores the split in the link notes', async () => {
      await seedBiz('biz_cat_rzp', { plan_id: 'trial', plan_status: 'trial', included: 30, used: 0, period_end: null });
      const token = await tokenFor('biz_cat_rzp');
      const fetchSpy = vi.spyOn(globalThis, 'fetch').mockResolvedValue(
        new Response(JSON.stringify({ id: 'plink_x', short_url: 'https://rzp.io/i/x' }), { status: 200 }),
      );
      const res = await checkout(token, { plan_id: 'growth' }, { RAZORPAY_KEY_ID: 'rzp_test_real', RAZORPAY_KEY_SECRET: 's' });
      expect(res.status).toBe(200);
      expect(await res.json()).toMatchObject({ url: 'https://rzp.io/i/x', plan_id: 'growth', total_inr: 14159 });
      const sentBody = JSON.parse(String((fetchSpy.mock.calls[0][1] as RequestInit).body));
      expect(sentBody.amount).toBe(1415900);
      expect(sentBody.notes).toMatchObject({ plan_id: 'growth', base_paise: '1199900', gst_paise: '216000', total_paise: '1415900' });
      expect(sentBody.description).toContain('GST');
    });
  });

  describe('payment_link.paid', () => {
    it('growth monthly with GST activates Growth and records base + GST', async () => {
      await seedBiz('biz_pay_growth', { plan_id: 'trial', plan_status: 'trial', included: 30, used: 20, period_end: null });
      const r = await pay(paidEvent('biz_pay_growth', 'pay_g1', 'growth'));
      expect(r).toMatchObject({ applied: true, plan_id: 'growth' });
      expect(await usageOf('biz_pay_growth')).toMatchObject({
        plan_id: 'growth', plan_name: 'Growth', plan_status: 'active', included_minutes: 3000, minutes_used: 0,
        price_inr: 11999, billing_cycle: 'monthly', annual_until: null,
      });
      const p = await env.DB.prepare("SELECT * FROM payments WHERE razorpay_payment_id = 'pay_g1'").first<any>();
      expect(p).toMatchObject({ kind: 'plan', amount_paise: 1415900, base_paise: 1199900, gst_paise: 216000, status: 'paid' });
    });

    it('paying only the pre-GST price for a GST link is an amount mismatch', async () => {
      await seedBiz('biz_pay_short', { plan_id: 'trial', plan_status: 'trial', included: 30, used: 0, period_end: null });
      const r = await pay(paidEvent('biz_pay_short', 'pay_short', 'starter', { amount: 499900 }));
      expect(r).toMatchObject({ applied: false, status: 'amount_mismatch' });
      expect((await usageOf('biz_pay_short')).plan_status).toBe('trial');
    });

    it('a legacy (pre-GST, no notes) starter link still activates', async () => {
      await seedBiz('biz_pay_legacy', { plan_id: 'trial', plan_status: 'trial', included: 30, used: 0, period_end: null });
      expect((await pay(paidEvent('biz_pay_legacy', 'pay_legacy', 'starter', { amount: 499900, legacy: true }))).applied).toBe(true);
      const p = await env.DB.prepare("SELECT base_paise, gst_paise FROM payments WHERE razorpay_payment_id = 'pay_legacy'").first<any>();
      expect(p).toEqual({ base_paise: 499900, gst_paise: 0 });
    });

    it('annual sets one month now and annual_until 12 months out, idempotently', async () => {
      await seedBiz('biz_pay_annual', { plan_id: 'trial', plan_status: 'trial', included: 30, used: 5, period_end: null });
      const body = paidEvent('biz_pay_annual', 'pay_a1', 'starter_annual');
      expect((await pay(body)).applied).toBe(true);
      const u = await usageOf('biz_pay_annual');
      expect(u).toMatchObject({ plan_id: 'starter', plan_status: 'active', included_minutes: 1000, minutes_used: 0, billing_cycle: 'annual', annual_plan_id: 'starter' });
      expect(ts(u.current_period_end) - Date.now()).toBeGreaterThan(27 * DAY);
      expect(ts(u.current_period_end) - Date.now()).toBeLessThan(32 * DAY);
      expect(ts(u.annual_until) - Date.now()).toBeGreaterThan(364 * DAY);
      expect(ts(u.annual_until) - Date.now()).toBeLessThan(367 * DAY);

      await env.DB.prepare("UPDATE usage SET minutes_used = 50 WHERE business_id = 'biz_pay_annual'").run();
      expect(await pay(body)).toMatchObject({ applied: false, duplicate: true });
      const again = await usageOf('biz_pay_annual');
      expect(again.minutes_used).toBe(50);
      expect(again.annual_until).toBe(u.annual_until);
      const p = await env.DB.prepare("SELECT kind, base_paise FROM payments WHERE razorpay_payment_id = 'pay_a1'").first<any>();
      expect(p).toEqual({ kind: 'annual', base_paise: 4999000 });
    });

    it('a top-up adds minutes to an active plan once and keeps the period', async () => {
      await seedBiz('biz_pay_topup', { plan_id: 'starter', plan_status: 'active', included: 1000, used: 990, period_end: '2999-01-01 00:00:00' });
      const body = paidEvent('biz_pay_topup', 'pay_t1', 'topup_250');
      expect((await pay(body)).applied).toBe(true);
      expect(await pay(body)).toMatchObject({ duplicate: true });
      const u = await usageOf('biz_pay_topup');
      expect(u).toMatchObject({
        plan_id: 'starter', included_minutes: 1000, topup_minutes: 250, minutes_used: 990, current_period_end: '2999-01-01 00:00:00',
      });
      expect(minutesRemaining(u)).toBe(260);
      const p = await env.DB.prepare("SELECT kind, status, applied_at FROM payments WHERE razorpay_payment_id = 'pay_t1'").first<any>();
      expect(p.kind).toBe('topup');
      expect(p.applied_at).toBeTruthy();

      // Renewing early (period still running) keeps the unused top-up minutes; plan minutes reset.
      await env.DB.prepare("UPDATE usage SET minutes_used = 1100 WHERE business_id = 'biz_pay_topup'").run();
      await pay(paidEvent('biz_pay_topup', 'pay_t1_renew', 'starter'));
      expect(await usageOf('biz_pay_topup')).toMatchObject({ included_minutes: 1000, topup_minutes: 150, minutes_used: 0 });
    });

    it('top-ups expire at period end: paying after the period resets them', async () => {
      await seedBiz('biz_pay_topup_exp', { plan_id: 'starter', plan_status: 'past_due', included: 1000, used: 1000, topup: 250, period_end: '2020-01-01 00:00:00' });
      await pay(paidEvent('biz_pay_topup_exp', 'pay_t_exp', 'starter'));
      expect(await usageOf('biz_pay_topup_exp')).toMatchObject({ plan_status: 'active', included_minutes: 1000, topup_minutes: 0, minutes_used: 0 });
    });

    it('a top-up paid on a lapsed plan is recorded for review, not applied', async () => {
      await seedBiz('biz_pay_topup_due', { plan_id: 'starter', plan_status: 'past_due', included: 1000, used: 1000, period_end: '2020-01-01 00:00:00' });
      const errSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
      expect(await pay(paidEvent('biz_pay_topup_due', 'pay_t2', 'topup_1000'))).toMatchObject({ applied: false, status: 'needs_review' });
      expect(errSpy).toHaveBeenCalled();
      expect(await usageOf('biz_pay_topup_due')).toMatchObject({ included_minutes: 1000, plan_status: 'past_due' });
      const p = await env.DB.prepare("SELECT status, applied_at FROM payments WHERE razorpay_payment_id = 'pay_t2'").first<any>();
      expect(p).toEqual({ status: 'needs_review', applied_at: null });
    });
  });

  describe('minute balances: plan, top-up, bonus', () => {
    it('remaining = plan + top-up + bonus - used, consumed in that order', () => {
      const row = { included_minutes: 1000, topup_minutes: 250, bonus_minutes: 100, minutes_used: 1200 };
      expect(minutesRemaining(row)).toBe(150);
      expect(minutesBreakdown(row)).toEqual({ plan_left: 0, topup_left: 50, bonus_left: 100, remaining: 150 });
      expect(minutesBreakdown({ ...row, minutes_used: 400 })).toMatchObject({ plan_left: 600, topup_left: 250, bonus_left: 100 });
      expect(minutesBreakdown({ ...row, minutes_used: 1300 })).toMatchObject({ plan_left: 0, topup_left: 0, bonus_left: 50 });
      expect(minutesRemaining({ ...row, minutes_used: 5000 })).toBe(0);
      expect(minutesRemaining(null)).toBe(0);
      expect(minutesRemaining({ included_minutes: 30, minutes_used: 10 })).toBe(20);
      expect(hasMinutesHeadroom({ included_minutes: 100, minutes_used: 100, bonus_minutes: 5 }, 0)).toBe(true);
      expect(hasMinutesHeadroom({ included_minutes: 100, minutes_used: 100, topup_minutes: 4 }, 0)).toBe(false);
    });

    it('addBonusMinutes adds credit and ignores bad amounts', async () => {
      await seedBiz('biz_bonus_add', { plan_id: 'trial', plan_status: 'trial', included: 30, used: 30, period_end: null });
      vi.spyOn(console, 'log').mockImplementation(() => {});
      expect(await addBonusMinutes(env as any, 'biz_bonus_add', 60, 'referral')).toBe(true);
      expect(await addBonusMinutes(env as any, 'biz_bonus_add', 0, 'referral')).toBe(false);
      expect(await addBonusMinutes(env as any, 'biz_bonus_add', -5, 'referral')).toBe(false);
      expect(await addBonusMinutes(env as any, 'biz_missing', 10, 'referral')).toBe(false);
      const u = await usageOf('biz_bonus_add');
      expect(u.bonus_minutes).toBe(60);
      expect(minutesRemaining(u)).toBe(60);
      // GET /usage reports the combined balance.
      const token = await tokenFor('biz_bonus_add');
      const res = await app.fetch(new Request('http://localhost/usage', { headers: { Authorization: `Bearer ${token}` } }), env);
      const body = (await res.json()) as any;
      expect(body.minutes_remaining).toBe(60);
      expect(body.subscription).toMatchObject({ bonus_minutes: 60, topup_minutes: 0, included_minutes: 30 });
    });

    it('a plan renewal keeps unused bonus and deducts only bonus that was consumed', async () => {
      // Unused bonus: used < plan.
      await seedBiz('biz_bonus_keep', { plan_id: 'starter', plan_status: 'past_due', included: 1000, used: 500, period_end: '2020-01-01 00:00:00' });
      await env.DB.prepare("UPDATE usage SET bonus_minutes = 100 WHERE business_id = 'biz_bonus_keep'").run();
      await pay(paidEvent('biz_bonus_keep', 'pay_bonus_keep', 'growth'));
      expect(await usageOf('biz_bonus_keep')).toMatchObject({ plan_id: 'growth', included_minutes: 3000, bonus_minutes: 100, minutes_used: 0 });

      // Consumed past plan + top-up: 1300 used of 1000 + 250 → 50 came from bonus.
      await seedBiz('biz_bonus_used', { plan_id: 'starter', plan_status: 'past_due', included: 1000, used: 1300, topup: 250, period_end: '2020-01-01 00:00:00' });
      await env.DB.prepare("UPDATE usage SET bonus_minutes = 100 WHERE business_id = 'biz_bonus_used'").run();
      await pay(paidEvent('biz_bonus_used', 'pay_bonus_used', 'starter'));
      expect(await usageOf('biz_bonus_used')).toMatchObject({ bonus_minutes: 50, topup_minutes: 0, minutes_used: 0, included_minutes: 1000 });
    });

    it('the annual monthly re-grant expires top-ups and keeps bonus', async () => {
      await seedBiz('biz_bonus_annual', {
        plan_id: 'starter', plan_status: 'active', included: 1000, used: 1270, topup: 250,
        period_end: '2020-01-01 00:00:00', annual_until: '2999-01-01 00:00:00', annual_plan_id: 'starter',
      });
      await env.DB.prepare("UPDATE usage SET bonus_minutes = 40 WHERE business_id = 'biz_bonus_annual'").run();
      await runBillingRenewals(env as any);
      expect(await usageOf('biz_bonus_annual')).toMatchObject({ topup_minutes: 0, bonus_minutes: 20, minutes_used: 0, included_minutes: 1000 });
    });
  });

  describe('renewal cron with annual plans', () => {
    it('re-grants an annual month without payment, and expires it at annual_until', async () => {
      await seedBiz('biz_cron_annual', {
        plan_id: 'growth', plan_status: 'active', included: 3250, used: 2000, topup: 250,
        period_end: '2020-01-01 00:00:00', annual_until: '2999-01-01 00:00:00', annual_plan_id: 'growth',
      });
      await seedBiz('biz_cron_annual_end', {
        plan_id: 'starter', plan_status: 'active', included: 1000, used: 10,
        period_end: '2020-01-01 00:00:00', annual_until: '2020-01-01 00:00:00', annual_plan_id: 'starter',
      });
      await seedBiz('biz_cron_annual_cap', {
        plan_id: 'starter', plan_status: 'active', included: 1000, used: 10,
        period_end: datetimeAgo(1), annual_until: datetimeAhead(10), annual_plan_id: 'starter',
      });
      // A monthly Growth payment during a Starter annual: re-grants go back to the annual plan.
      await seedBiz('biz_cron_annual_mix', {
        plan_id: 'growth', plan_status: 'active', included: 3000, used: 10,
        period_end: '2020-01-01 00:00:00', annual_until: '2999-01-01 00:00:00', annual_plan_id: 'starter',
      });

      await runBillingRenewals(env as any);

      expect(await usageOf('biz_cron_annual')).toMatchObject({
        plan_status: 'active', plan_id: 'growth', included_minutes: 3000, minutes_used: 0, topup_minutes: 0,
        current_period_end: '2020-02-01 00:00:00',
      });
      expect((await usageOf('biz_cron_annual_end')).plan_status).toBe('past_due');
      const cap = await usageOf('biz_cron_annual_cap');
      expect(cap.plan_status).toBe('active');
      expect(cap.current_period_end).toBe(cap.annual_until); // last month ends at annual_until
      expect(await usageOf('biz_cron_annual_mix')).toMatchObject({ plan_id: 'starter', included_minutes: 1000 });
    });
  });
});

function sqlDate(d: Date) {
  return d.toISOString().replace('T', ' ').slice(0, 19);
}
function datetimeAgo(days: number) {
  return sqlDate(new Date(Date.now() - days * DAY));
}
function datetimeAhead(days: number) {
  return sqlDate(new Date(Date.now() + days * DAY));
}
