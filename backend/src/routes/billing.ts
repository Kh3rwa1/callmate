import { Hono } from 'hono';
import { Env, AuthUser } from '../types';
import { timingSafeEqual } from '../utils/compare';
import { isDevEnv } from '../utils/secrets';
import { hitRateLimit } from '../utils/rate_limit';
import { billingView, getPlan, hmacHex, PAID_PLAN_IDS, PlanId } from '../services/plans';
import { onFirstPayment } from '../services/referrals';

const billingApp = new Hono<{ Bindings: Env; Variables: { user: AuthUser } }>();

const RAZORPAY_PAYMENT_LINKS = 'https://api.razorpay.com/v1/payment_links';

/** Dev/test with placeholder keys: checkout returns a fake URL instead of calling Razorpay. */
export function isMockRazorpay(env: Env): boolean {
  if (!isDevEnv(env)) return false;
  const key = env.RAZORPAY_KEY_ID || '';
  return key.startsWith('mock') || key.startsWith('rzp_test_mock');
}

// GET /billing
billingApp.get('/billing', async (c) => {
  const user = c.get('user');
  const row = await c.env.DB.prepare('SELECT * FROM usage WHERE business_id = ?').bind(user.business_id).first<any>();
  if (!row) return c.json({ message: 'No plan found for this account.', code: 'not_found' }, 404);
  return c.json(billingView(row, c.env));
});

// POST /billing/checkout  → { url }
billingApp.post('/billing/checkout', async (c) => {
  const user = c.get('user');
  const body: any = await c.req.json().catch(() => ({}));
  const planId = (typeof body?.plan_id === 'string' ? body.plan_id : 'starter') as PlanId;
  if (!PAID_PLAN_IDS.includes(planId)) {
    return c.json({ message: 'Unknown plan.', code: 'invalid_plan' }, 400);
  }
  const plan = getPlan(planId, c.env);

  const keyId = c.env.RAZORPAY_KEY_ID?.trim();
  const keySecret = c.env.RAZORPAY_KEY_SECRET?.trim();
  if (!keyId || !keySecret) {
    return c.json({ message: 'Online payments are not set up yet. Our team will contact you.', code: 'billing_not_configured' }, 503);
  }

  const { allowed, retryAfter } = await hitRateLimit(c.env.DB, `billing:checkout:${user.business_id}`, 10, 3600);
  if (!allowed) {
    c.header('Retry-After', String(retryAfter));
    return c.json({ message: 'Too many payment attempts. Please try again later.', code: 'rate_limited' }, 429);
  }

  const nonce = crypto.randomUUID().replace(/-/g, '').slice(0, 12);
  // Razorpay caps reference_id at 40 chars; biz ids are 16.
  const referenceId = `${user.business_id}_${nonce}`.slice(0, 40);

  if (isMockRazorpay(c.env)) {
    return c.json({ url: `https://rzp.io/mock/${referenceId}`, id: `plink_mock_${nonce}`, mock: true });
  }

  const payload: Record<string, unknown> = {
    amount: plan.priceInr * 100,
    currency: 'INR',
    accept_partial: false,
    reference_id: referenceId,
    description: `CallPilot ${plan.name} – ${plan.includedMinutes} minutes / month`,
    customer: { contact: `+${String(user.phone).replace(/\D/g, '')}` },
    notify: { sms: false, email: false },
    reminder_enable: false,
    notes: { business_id: user.business_id, plan_id: plan.id },
  };
  const returnUrl = c.env.BILLING_RETURN_URL?.trim();
  if (returnUrl) {
    payload.callback_url = returnUrl;
    payload.callback_method = 'get';
  }

  let res: Response;
  try {
    res = await fetch(RAZORPAY_PAYMENT_LINKS, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Basic ${btoa(`${keyId}:${keySecret}`)}`,
      },
      body: JSON.stringify(payload),
    });
  } catch (err: any) {
    console.error(JSON.stringify({ msg: 'razorpay_unreachable', error: String(err?.message ?? err) }));
    return c.json({ message: "Couldn't start the payment. Please try again.", code: 'billing_unavailable' }, 502);
  }
  const data: any = await res.json().catch(() => ({}));
  if (!res.ok || typeof data?.short_url !== 'string') {
    console.error(JSON.stringify({ msg: 'razorpay_payment_link_failed', status: res.status, code: data?.error?.code }));
    return c.json({ message: "Couldn't start the payment. Please try again.", code: 'billing_unavailable' }, 502);
  }
  return c.json({ url: data.short_url, id: data.id });
});

// ------------------------------------------------------------------ webhook

export async function verifyRazorpaySignature(rawBody: string, signature: string | undefined, secret: string): Promise<boolean> {
  if (!signature) return false;
  const expected = await hmacHex(secret, rawBody);
  return timingSafeEqual(signature.trim().toLowerCase(), expected);
}

/** POST /webhooks/razorpay (public; authenticated by X-Razorpay-Signature). */
export async function handleRazorpayWebhook(c: any): Promise<Response> {
  const env: Env = c.env;
  const secret = env.RAZORPAY_WEBHOOK_SECRET?.trim();
  if (!secret) {
    return c.json({ message: 'Billing webhook is not configured.', code: 'billing_not_configured' }, 503);
  }
  const rawBody = await c.req.text();
  if (!(await verifyRazorpaySignature(rawBody, c.req.header('X-Razorpay-Signature'), secret))) {
    return c.json({ message: 'Invalid signature.', code: 'invalid_signature' }, 401);
  }

  let event: any;
  try {
    event = JSON.parse(rawBody);
  } catch {
    return c.json({ message: 'Malformed JSON payload.', code: 'invalid_json' }, 400);
  }
  if (event?.event !== 'payment_link.paid') {
    return c.json({ received: true, ignored: event?.event ?? 'unknown' });
  }

  const link = event?.payload?.payment_link?.entity ?? {};
  const payment = event?.payload?.payment?.entity ?? {};
  const notes = { ...(link.notes ?? {}), ...(payment.notes ?? {}) };
  const businessId = typeof link?.notes?.business_id === 'string' ? link.notes.business_id : notes.business_id;
  const paymentId = payment?.id;
  if (typeof businessId !== 'string' || !businessId || typeof paymentId !== 'string' || !paymentId) {
    return c.json({ message: 'Payment is missing business or payment id.', code: 'invalid_payload' }, 400);
  }
  const plan = getPlan(typeof link?.notes?.plan_id === 'string' ? link.notes.plan_id : 'starter', env);
  const amount = Number(payment.amount ?? link.amount_paid ?? 0);
  const currency = String(payment.currency ?? link.currency ?? 'INR');
  const amountOk = plan.paid && currency === 'INR' && amount >= plan.priceInr * 100;

  const db = env.DB;
  const insert = db.prepare(
    `INSERT OR IGNORE INTO payments
       (id, razorpay_payment_id, razorpay_payment_link_id, business_id, plan_id, amount_paise, currency, status, contact_email, contact_phone)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
  ).bind(
    `pay_${crypto.randomUUID().slice(0, 12)}`, paymentId, typeof link.id === 'string' ? link.id : null,
    businessId, plan.id, amount, currency, amountOk ? 'paid' : 'amount_mismatch',
    typeof payment.email === 'string' ? payment.email : null,
    typeof payment.contact === 'string' ? payment.contact : null,
  );

  if (!amountOk) {
    const r = await insert.run();
    console.error(JSON.stringify({ msg: 'razorpay_amount_mismatch', business_id: businessId, amount, currency }));
    return c.json({ received: true, applied: false, duplicate: (r.meta?.changes ?? 0) === 0 });
  }

  // One transaction: record the payment, then apply it only if it has not been applied yet.
  // A redelivered webhook hits INSERT OR IGNORE and the applied_at IS NULL guards → no double credit.
  const results = await db.batch([
    insert,
    db.prepare(
      `UPDATE usage SET
         plan_id = ?, plan_name = ?, plan_status = 'active',
         included_minutes = ?, minutes_used = 0, price_inr = ?,
         current_period_end = datetime(
           CASE WHEN plan_status = 'active' AND current_period_end IS NOT NULL
                     AND julianday(current_period_end) > julianday('now')
                THEN current_period_end ELSE 'now' END, '+1 month'),
         renews_at = datetime(
           CASE WHEN plan_status = 'active' AND current_period_end IS NOT NULL
                     AND julianday(current_period_end) > julianday('now')
                THEN current_period_end ELSE 'now' END, '+1 month')
       WHERE business_id = ?
         AND EXISTS (SELECT 1 FROM payments WHERE razorpay_payment_id = ? AND applied_at IS NULL)`
    ).bind(plan.id, plan.name, plan.includedMinutes, plan.priceInr, businessId, paymentId),
    db.prepare(
      `UPDATE payments SET applied_at = datetime('now'),
         period_end = (SELECT current_period_end FROM usage WHERE business_id = ?)
       WHERE razorpay_payment_id = ? AND applied_at IS NULL`
    ).bind(businessId, paymentId),
  ]);
  const duplicate = (results[0].meta?.changes ?? 0) === 0;
  await onFirstPayment(env, businessId); // referral bonus; idempotent, so redeliveries are safe
  return c.json({ received: true, applied: !duplicate, duplicate });
}

export { billingApp };
