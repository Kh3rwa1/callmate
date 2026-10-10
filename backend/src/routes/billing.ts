import { Hono } from 'hono';
import { Env, AuthUser } from '../types';
import { timingSafeEqual } from '../utils/compare';
import { isDevEnv } from '../utils/secrets';
import { hitRateLimit } from '../utils/rate_limit';
import { checkoutSchema } from '../schemas/validation';
import {
  billingView, getPlan, hmacHex, isProductId, priceWithGst, Product, PRODUCTS, RESET_PERIOD_BONUS_SQL,
} from '../services/plans';
import { onFirstPayment } from '../services/referrals';

const billingApp = new Hono<{ Bindings: Env; Variables: { user: AuthUser } }>();

const RAZORPAY_PAYMENT_LINKS = 'https://api.razorpay.com/v1/payment_links';

/** Dev/test with placeholder keys: checkout returns a fake URL instead of calling Razorpay. */
export function isMockRazorpay(env: Env): boolean {
  if (!isDevEnv(env)) return false;
  const key = env.RAZORPAY_KEY_ID || '';
  return key.startsWith('mock') || key.startsWith('rzp_test_mock');
}

export const TOPUP_NEEDS_ACTIVE_PLAN_BODY = {
  message: 'Extra minutes can be added to an active plan. Buy or renew a plan first.',
  code: 'plan_not_active',
} as const;

function productDescription(p: Product): string {
  if (p.kind === 'topup') return `CallPilot – ${p.minutes} extra minutes (valid until your plan renews)`;
  if (p.kind === 'annual') return `CallPilot ${p.name} – ${p.minutes} minutes / month for 12 months`;
  return `CallPilot ${p.name} – ${p.minutes} minutes / month`;
}

// GET /billing
billingApp.get('/billing', async (c) => {
  const user = c.get('user');
  const row = await c.env.DB.prepare('SELECT * FROM usage WHERE business_id = ?').bind(user.business_id).first<any>();
  if (!row) return c.json({ message: 'No plan found for this account.', code: 'not_found' }, 404);
  return c.json(billingView(row, c.env));
});

// POST /billing/checkout  {plan_id?} → { url, id, plan_id, base_inr, gst_inr, total_inr }
billingApp.post('/billing/checkout', async (c) => {
  const user = c.get('user');
  const body: unknown = await c.req.json().catch(() => ({}));
  const parsed = checkoutSchema.safeParse(body ?? {});
  if (!parsed.success) {
    return c.json({ message: 'Unknown plan.', code: 'invalid_plan' }, 400);
  }
  const product = PRODUCTS[parsed.data.plan_id ?? 'starter'];

  if (product.kind === 'topup') {
    const usage = await c.env.DB.prepare('SELECT plan_status FROM usage WHERE business_id = ?')
      .bind(user.business_id).first<{ plan_status: string }>();
    if (usage?.plan_status !== 'active') return c.json(TOPUP_NEEDS_ACTIVE_PLAN_BODY, 409);
  }

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

  const price = priceWithGst(product.priceInr, c.env);
  const priceOut = { plan_id: product.id, base_inr: price.base_inr, gst_inr: price.gst_inr, total_inr: price.total_inr };
  const nonce = crypto.randomUUID().replace(/-/g, '').slice(0, 12);
  // Razorpay caps reference_id at 40 chars; biz ids are 16.
  const referenceId = `${user.business_id}_${nonce}`.slice(0, 40);

  if (isMockRazorpay(c.env)) {
    return c.json({ url: `https://rzp.io/mock/${referenceId}`, id: `plink_mock_${nonce}`, mock: true, ...priceOut });
  }

  const payload: Record<string, unknown> = {
    // Razorpay charges exactly this: base price + GST.
    amount: price.total_inr * 100,
    currency: 'INR',
    accept_partial: false,
    reference_id: referenceId,
    description: `${productDescription(product)} (₹${price.base_inr} + ₹${price.gst_inr} GST)`,
    customer: { contact: `+${String(user.phone).replace(/\D/g, '')}` },
    notify: { sms: false, email: false },
    reminder_enable: false,
    // Read back by the webhook: what was bought and the GST split it was priced at.
    notes: {
      business_id: user.business_id,
      plan_id: product.id,
      base_paise: String(price.base_inr * 100),
      gst_paise: String(price.gst_inr * 100),
      total_paise: String(price.total_inr * 100),
    },
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
  return c.json({ url: data.short_url, id: data.id, ...priceOut });
});

// ------------------------------------------------------------------ webhook

export async function verifyRazorpaySignature(rawBody: string, signature: string | undefined, secret: string): Promise<boolean> {
  if (!signature) return false;
  const expected = await hmacHex(secret, rawBody);
  return timingSafeEqual(signature.trim().toLowerCase(), expected);
}

function paiseNote(v: unknown): number | null {
  const n = Number(v);
  return Number.isInteger(n) && n >= 0 ? n : null;
}

/**
 * What a paid link must have charged and how it splits into base + GST.
 * Links created by this version carry base/gst/total in their notes (set by us, delivered in a
 * signed webhook). Links created before GST (no notes) were charged the base price only.
 */
export function expectedCharge(product: Product, notes: Record<string, unknown>, paidPaise: number):
  { minPaise: number; basePaise: number; gstPaise: number } {
  const floor = product.priceInr * 100;
  const total = paiseNote(notes.total_paise);
  const base = paiseNote(notes.base_paise);
  const gst = paiseNote(notes.gst_paise);
  if (total !== null && total >= floor && base !== null && gst !== null && base + gst === total) {
    return { minPaise: total, basePaise: base, gstPaise: gst };
  }
  return { minPaise: floor, basePaise: paidPaise, gstPaise: 0 };
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
  const linkNotes = (link.notes && typeof link.notes === 'object') ? link.notes : {};
  const notes = { ...(payment.notes ?? {}), ...linkNotes };
  const businessId = notes.business_id;
  const paymentId = payment?.id;
  if (typeof businessId !== 'string' || !businessId || typeof paymentId !== 'string' || !paymentId) {
    return c.json({ message: 'Payment is missing business or payment id.', code: 'invalid_payload' }, 400);
  }
  // Links from before the catalogue only sold Starter.
  const notedPlan: unknown = notes.plan_id;
  const product = PRODUCTS[isProductId(notedPlan) ? notedPlan : 'starter'];
  const amount = Number(payment.amount ?? link.amount_paid ?? 0);
  const currency = String(payment.currency ?? link.currency ?? 'INR');
  const charge = expectedCharge(product, notes, amount);
  const amountOk = currency === 'INR' && amount >= charge.minPaise;

  const db = env.DB;
  // Top-ups only extend an active plan (checkout enforces it; this catches a plan that lapsed
  // between checkout and payment). Such a payment is kept for a manual refund / credit.
  let status = amountOk ? 'paid' : 'amount_mismatch';
  if (amountOk && product.kind === 'topup') {
    const u = await db.prepare('SELECT plan_status FROM usage WHERE business_id = ?').bind(businessId).first<{ plan_status: string }>();
    if (u?.plan_status !== 'active') status = 'needs_review';
  }

  const insert = db.prepare(
    `INSERT OR IGNORE INTO payments
       (id, razorpay_payment_id, razorpay_payment_link_id, business_id, plan_id, kind, amount_paise, base_paise, gst_paise,
        currency, status, contact_email, contact_phone)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
  ).bind(
    `pay_${crypto.randomUUID().slice(0, 12)}`, paymentId, typeof link.id === 'string' ? link.id : null,
    businessId, product.id, product.kind, amount, charge.basePaise, charge.gstPaise, currency, status,
    typeof payment.email === 'string' ? payment.email : null,
    typeof payment.contact === 'string' ? payment.contact : null,
  );

  if (status !== 'paid') {
    const r = await insert.run();
    console.error(JSON.stringify({ msg: status === 'needs_review' ? 'razorpay_topup_on_inactive_plan' : 'razorpay_amount_mismatch', business_id: businessId, plan_id: product.id, amount, currency }));
    return c.json({ received: true, applied: false, duplicate: (r.meta?.changes ?? 0) === 0, status });
  }

  // One transaction: record the payment, then apply it only if it has not been applied yet.
  // A redelivered webhook hits INSERT OR IGNORE and the applied_at IS NULL guards → no double credit.
  const notApplied = `EXISTS (SELECT 1 FROM payments WHERE razorpay_payment_id = ? AND applied_at IS NULL)`;
  // A renewal paid during an active period extends from its end; otherwise the period starts now.
  const earlyRenewal = (then: string, otherwise: string) =>
    `CASE WHEN plan_status = 'active' AND current_period_end IS NOT NULL
               AND julianday(current_period_end) > julianday('now')
          THEN ${then} ELSE ${otherwise} END`;
  const periodBase = earlyRenewal('current_period_end', `datetime('now')`);

  let apply: D1PreparedStatement;
  if (product.kind === 'topup') {
    apply = db.prepare(
      `UPDATE usage SET topup_minutes = topup_minutes + ?
       WHERE business_id = ? AND plan_status = 'active' AND ${notApplied}`
    ).bind(product.minutes, businessId, paymentId);
  } else {
    const plan = getPlan(product.planId, env);
    const annual = product.kind === 'annual';
    // Annual: 12 monthly grants. This payment grants month 1; the renewal cron re-grants the
    // rest while annual_until is ahead. Buying another year early stacks onto the current one.
    const annualUntil = annual
      ? `datetime(CASE WHEN annual_until IS NOT NULL AND julianday(annual_until) > julianday('now')
                       THEN annual_until ELSE ${periodBase} END, '+12 months')`
      : 'annual_until';
    apply = db.prepare(
      `UPDATE usage SET
         plan_id = ?, plan_name = ?, plan_status = 'active',
         ${RESET_PERIOD_BONUS_SQL},
         topup_minutes = ${earlyRenewal('MAX(0, MIN(topup_minutes, included_minutes + topup_minutes - minutes_used))', '0')},
         included_minutes = ?, minutes_used = 0, price_inr = ?,
         billing_cycle = ${annual ? `'annual'` : `CASE WHEN annual_until IS NOT NULL AND julianday(annual_until) > julianday('now') THEN 'annual' ELSE 'monthly' END`},
         annual_plan_id = ${annual ? '?' : 'annual_plan_id'},
         annual_until = ${annualUntil},
         current_period_end = datetime(${periodBase}, '+1 month'),
         renews_at = datetime(${periodBase}, '+1 month')
       WHERE business_id = ? AND ${notApplied}`
    ).bind(
      plan.id, plan.name, plan.includedMinutes, plan.priceInr,
      ...(annual ? [plan.id] : []),
      businessId, paymentId,
    );
  }

  const results = await db.batch([
    insert,
    apply,
    db.prepare(
      `UPDATE payments SET applied_at = datetime('now'),
         period_end = (SELECT current_period_end FROM usage WHERE business_id = ?)
       WHERE razorpay_payment_id = ? AND applied_at IS NULL`
    ).bind(businessId, paymentId),
  ]);
  const duplicate = (results[0].meta?.changes ?? 0) === 0;
  await onFirstPayment(env, businessId); // referral bonus; idempotent, so redeliveries are safe
  return c.json({ received: true, applied: !duplicate, duplicate, plan_id: product.id });
}

export { billingApp };
