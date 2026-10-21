import { describe, it, expect, beforeAll } from 'vitest';
import { env } from 'cloudflare:test';
import { migrateTestDb } from './setup-db';
import app from '../src/index';
import { upiPayee, upiPayUri, newUpiReference } from '../src/services/upi';

const OPS_KEY = 'ops-key-for-upi-tests-correct-horse';
const VPA = 'tumdah@okhdfcbank';

async function sha256(text: string): Promise<string> {
  const d = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
  return [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

let upiEnv: any;

function call(path: string, init: RequestInit = {}, e: any = upiEnv, token?: string) {
  const headers: Record<string, string> = { 'Content-Type': 'application/json', ...(init.headers as any) };
  if (token) headers.Authorization = `Bearer ${token}`;
  return app.fetch(new Request(`http://localhost${path}`, { ...init, headers }), e);
}

async function registerPhone(phone: string) {
  const ip = `10.7.${Math.floor(Math.random() * 250)}.${Math.floor(Math.random() * 250)}`;
  const otpRes = await call('/auth/otp/request', { method: 'POST', body: JSON.stringify({ phone }), headers: { 'cf-connecting-ip': ip } });
  const { debug_otp } = (await otpRes.json()) as any;
  const reg = await call('/auth/register', {
    method: 'POST', body: JSON.stringify({ phone, otp: debug_otp, business_name: 'UPI Biz' }), headers: { 'cf-connecting-ip': ip },
  });
  expect(reg.status).toBe(200);
  const tokens = (await reg.json()) as any;
  const user = await env.DB.prepare('SELECT business_id FROM users WHERE phone = ?').bind(phone).first<any>();
  return { token: tokens.access_token as string, businessId: user.business_id as string };
}

const checkout = async (token: string, planId = 'starter', e: any = upiEnv) =>
  call('/billing/checkout', { method: 'POST', body: JSON.stringify({ plan_id: planId }) }, e, token);
const submitUtr = (token: string, orderId: string, utr: string) =>
  call(`/billing/upi/${orderId}/utr`, { method: 'POST', body: JSON.stringify({ utr }) }, upiEnv, token);
const usage = async (token: string) => (await (await call('/usage', {}, upiEnv, token)).json()) as any;

/** POST to the ops page as a form, with the right key. */
const ops = (action: string) => app.fetch(new Request('http://localhost/ops/numbers', {
  method: 'POST',
  headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'cf-connecting-ip': '203.0.113.9' },
  body: new URLSearchParams({ key: OPS_KEY, action }).toString(),
}), upiEnv);

describe('Built-in UPI payments', () => {
  beforeAll(async () => {
    await migrateTestDb();
    upiEnv = { ...env, UPI_PAYEE_VPA: VPA, UPI_PAYEE_NAME: 'Tumdah', OPS_KEY_SHA256: await sha256(OPS_KEY) };
  });

  describe('payee and link', () => {
    it('is off without a valid UPI ID', () => {
      expect(upiPayee({ UPI_PAYEE_VPA: '' })).toBeNull();
      expect(upiPayee({ UPI_PAYEE_VPA: 'not a vpa' })).toBeNull();
      expect(upiPayee({ UPI_PAYEE_VPA: ` ${VPA} ` })).toEqual({ vpa: VPA, name: 'CallPilot' });
      expect(upiPayee({ UPI_PAYEE_VPA: VPA, UPI_PAYEE_NAME: 'Tumdah' })).toEqual({ vpa: VPA, name: 'Tumdah' });
    });

    it('builds a upi://pay link with the exact amount and the reference as the note', () => {
      expect(upiPayUri({ vpa: VPA, name: 'Tumdah Pvt Ltd' }, 5899, 'CPABCDEFG'))
        .toBe('upi://pay?pa=tumdah@okhdfcbank&pn=Tumdah%20Pvt%20Ltd&am=5899.00&cu=INR&tn=CallPilot%20CPABCDEFG');
      expect(newUpiReference()).toMatch(/^CP[A-HJKMNP-Z2-9]{7}$/);
    });
  });

  describe('checkout', () => {
    it('makes a UPI order when Razorpay is not set up', async () => {
      const { token, businessId } = await registerPhone('919830055501');
      const res = await checkout(token);
      expect(res.status).toBe(200);
      const d = (await res.json()) as any;
      expect(d.url).toBeUndefined();
      expect(d).toMatchObject({ plan_id: 'starter', base_inr: 4999, gst_inr: 900, total_inr: 5899 });
      expect(d.upi).toMatchObject({ vpa: VPA, payee_name: 'Tumdah', amount_inr: 5899 });
      expect(d.id).toBe(d.upi.order_id);
      expect(d.upi.uri).toBe(`upi://pay?pa=${VPA}&pn=Tumdah&am=5899.00&cu=INR&tn=CallPilot%20${d.upi.reference}`);
      const row = await env.DB.prepare('SELECT * FROM upi_orders WHERE id = ?').bind(d.upi.order_id).first<any>();
      expect(row).toMatchObject({ business_id: businessId, plan_id: 'starter', amount_paise: 589900, status: 'pending', utr: null });
    });

    it('uses Razorpay when its keys are set', async () => {
      const { token } = await registerPhone('919830055502');
      const res = await checkout(token, 'starter', { ...upiEnv, RAZORPAY_KEY_ID: 'mock_key', RAZORPAY_KEY_SECRET: 'mock_secret' });
      expect(res.status).toBe(200);
      const d = (await res.json()) as any;
      expect(d.url).toMatch(/^https:\/\/rzp\.io\/mock\//);
      expect(d.upi).toBeUndefined();
    });

    it('still says payments are not set up without a UPI ID', async () => {
      const { token } = await registerPhone('919830055503');
      const res = await checkout(token, 'starter', { ...upiEnv, UPI_PAYEE_VPA: '' });
      expect(res.status).toBe(503);
      expect(((await res.json()) as any).code).toBe('billing_not_configured');
    });
  });

  describe('UTR, ops page and plan', () => {
    it('takes the UTR, shows it on the ops page and starts the plan on confirm', async () => {
      const { token, businessId } = await registerPhone('919830055511');
      const { upi } = (await (await checkout(token)).json()) as any;

      expect((await submitUtr(token, upi.order_id, '12345')).status).toBe(400);
      const other = await registerPhone('919830055512');
      expect((await submitUtr(other.token, upi.order_id, '400011112222')).status).toBe(404);

      const ok = await submitUtr(token, upi.order_id, '4000 1111 2222');
      expect(ok.status).toBe(200);
      expect(await ok.json()).toEqual({ status: 'submitted', reference: upi.reference, total_inr: 5899 });
      expect((await usage(token)).pending_payment).toMatchObject({
        order_id: upi.order_id, reference: upi.reference, plan_name: 'Starter', total_inr: 5899, status: 'submitted',
      });

      // The same UTR can't pay a second order.
      const second = (await (await checkout(other.token)).json()) as any;
      const reused = await submitUtr(other.token, second.upi.order_id, '400011112222');
      expect(reused.status).toBe(409);
      expect(((await reused.json()) as any).code).toBe('utr_used');

      const list = await (await ops('list')).text();
      expect(list).toContain(upi.reference);
      expect(list).toContain('400011112222');
      expect(list).toContain(`value="upi_confirm:${upi.order_id}"`);
      expect(list).toContain(VPA);

      const confirmed = await ops(`upi_confirm:${upi.order_id}`);
      expect(confirmed.status).toBe(200);
      expect(await confirmed.text()).toContain(`Confirmed ${upi.reference}. The plan is active`);

      const u = await env.DB.prepare('SELECT plan_id, plan_status, included_minutes FROM usage WHERE business_id = ?').bind(businessId).first<any>();
      expect(u).toMatchObject({ plan_id: 'starter', plan_status: 'active' });
      const pay = await env.DB.prepare('SELECT * FROM payments WHERE razorpay_payment_id = ?').bind('upi:400011112222').first<any>();
      expect(pay).toMatchObject({ business_id: businessId, plan_id: 'starter', method: 'upi', status: 'paid', amount_paise: 589900 });
      expect(pay.applied_at).not.toBeNull();
      const note = await env.DB.prepare("SELECT title FROM notifications WHERE business_id = ? AND type = 'payment'").bind(businessId).first<any>();
      expect(note?.title).toBe('Payment received');
      expect((await usage(token)).pending_payment).toBeNull();

      // Confirming twice changes nothing; a confirmed order takes no new UTR.
      expect(await (await ops(`upi_confirm:${upi.order_id}`)).text()).toContain('already confirmed or rejected');
      expect((await submitUtr(token, upi.order_id, '400011113333')).status).toBe(409);
      const n = await env.DB.prepare('SELECT COUNT(*) AS n FROM payments WHERE business_id = ?').bind(businessId).first<any>();
      expect(n.n).toBe(1);
    });

    it('rejects, tells the owner, and lets them enter the UTR again', async () => {
      const { token, businessId } = await registerPhone('919830055521');
      const { upi } = (await (await checkout(token)).json()) as any;
      expect((await submitUtr(token, upi.order_id, '500011112222')).status).toBe(200);

      expect(await (await ops(`upi_reject:${upi.order_id}`)).text()).toContain(`Rejected ${upi.reference}`);
      expect((await usage(token)).pending_payment).toMatchObject({ reference: upi.reference, status: 'rejected' });
      const note = await env.DB.prepare("SELECT body FROM notifications WHERE business_id = ? AND type = 'payment'").bind(businessId).first<any>();
      expect(note?.body).toContain(upi.reference);
      const u = await env.DB.prepare('SELECT plan_status FROM usage WHERE business_id = ?').bind(businessId).first<any>();
      expect(u.plan_status).toBe('trial');

      expect((await submitUtr(token, upi.order_id, '500011113333')).status).toBe(200);
      expect((await usage(token)).pending_payment).toMatchObject({ status: 'submitted' });
    });

    it('keeps extra minutes for a lapsed plan for a manual credit', async () => {
      const { token, businessId } = await registerPhone('919830055531');
      await env.DB.prepare("UPDATE usage SET plan_id = 'starter', plan_status = 'active' WHERE business_id = ?").bind(businessId).run();
      const { upi } = (await (await checkout(token, 'topup_250')).json()) as any;
      expect((await submitUtr(token, upi.order_id, '600011112222')).status).toBe(200);
      await env.DB.prepare("UPDATE usage SET plan_status = 'past_due' WHERE business_id = ?").bind(businessId).run();

      expect(await (await ops(`upi_confirm:${upi.order_id}`)).text()).toContain('credit them by hand');
      const pay = await env.DB.prepare('SELECT status, applied_at FROM payments WHERE razorpay_payment_id = ?').bind('upi:600011112222').first<any>();
      expect(pay).toEqual({ status: 'needs_review', applied_at: null });
    });

    it('refuses an unknown order on the ops page', async () => {
      const res = await ops('upi_confirm:upi_nope');
      expect(res.status).toBe(400);
      expect(await res.text()).toContain('not in the list');
    });
  });
});
