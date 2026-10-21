/**
 * Built-in UPI payments, used while Razorpay is not set up (migrations/0023_upi_payments.sql).
 *
 * Checkout makes an order with a short reference (e.g. CPK7Q2M9X) and a upi://pay link for our UPI
 * ID with the exact amount and "CallPilot <reference>" as the note. The owner pays from any UPI app
 * and enters the 12-digit UTR. The operator finds the payment in the bank statement and confirms or
 * rejects the order on the ops page; a confirmed order is applied like a Razorpay payment.
 */
import { Env } from '../types';
import { sendBusinessPushNotification } from './fcm';
import { ownerLanguage, ownerText } from './owner_text';
import { recordPayment } from './payments';
import { isProductId, PriceBreakdown, Product, PRODUCTS } from './plans';

/** Catalogue name of a stored plan id (the id itself if it is no longer sold). */
function productName(planId: unknown): string {
  return isProductId(planId) ? PRODUCTS[planId].name : String(planId);
}

export interface UpiPayee {
  vpa: string;
  name: string;
}

/** Our UPI ID and payee name, or null when UPI_PAYEE_VPA is unset or not a UPI ID. */
export function upiPayee(env: Pick<Env, 'UPI_PAYEE_VPA' | 'UPI_PAYEE_NAME'>): UpiPayee | null {
  const vpa = (env.UPI_PAYEE_VPA || '').trim();
  if (!/^[A-Za-z0-9._-]{2,256}@[A-Za-z][A-Za-z0-9.-]{1,63}$/.test(vpa)) return null;
  return { vpa, name: (env.UPI_PAYEE_NAME || '').trim().slice(0, 50) || 'CallPilot' };
}

// No 0/O, 1/I/L: the reference is read off a screen and typed into notes.
const REFERENCE_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

export function newUpiReference(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(7));
  return `CP${[...bytes].map((b) => REFERENCE_ALPHABET[b % REFERENCE_ALPHABET.length]).join('')}`;
}

/** upi://pay link for [amountInr] to [payee], with "CallPilot <reference>" as the note. */
export function upiPayUri(payee: UpiPayee, amountInr: number, reference: string): string {
  // "@" stays readable: some UPI apps don't decode %40 in pa.
  const pa = encodeURIComponent(payee.vpa).replace(/%40/g, '@');
  return `upi://pay?pa=${pa}&pn=${encodeURIComponent(payee.name)}&am=${amountInr.toFixed(2)}`
    + `&cu=INR&tn=${encodeURIComponent(`CallPilot ${reference}`)}`;
}

export interface UpiCheckout {
  order_id: string;
  uri: string;
  vpa: string;
  payee_name: string;
  reference: string;
  amount_inr: number;
}

/** A new order for [product] at [price]; its reference is unique. */
export async function createUpiOrder(
  env: Env, payee: UpiPayee, businessId: string, product: Product, price: PriceBreakdown,
): Promise<UpiCheckout> {
  const id = `upi_${crypto.randomUUID().replace(/-/g, '').slice(0, 12)}`;
  for (let attempt = 0; ; attempt++) {
    const reference = newUpiReference();
    try {
      await env.DB.prepare(
        `INSERT INTO upi_orders (id, reference, business_id, plan_id, kind, amount_paise, base_paise, gst_paise)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)`
      ).bind(id, reference, businessId, product.id, product.kind,
        price.total_inr * 100, price.base_inr * 100, price.gst_inr * 100).run();
      return {
        order_id: id, uri: upiPayUri(payee, price.total_inr, reference), vpa: payee.vpa,
        payee_name: payee.name, reference, amount_inr: price.total_inr,
      };
    } catch (err: any) {
      // A reference clash (31^7 of them) is retried; anything else is a real failure.
      if (attempt >= 2 || !/UNIQUE/i.test(String(err?.message))) throw err;
    }
  }
}

export type UtrResult =
  | { ok: true; reference: string; total_inr: number }
  | { ok: false; code: 'invalid_utr' | 'not_found' | 'utr_used' | 'order_closed' };

/**
 * The owner's UTR for one of their orders. A new UTR replaces one entered before, and a rejected
 * order can be sent again (e.g. after a typo); a confirmed order is closed.
 */
export async function submitUpiUtr(env: Env, businessId: string, orderId: string, utrInput: unknown): Promise<UtrResult> {
  const utr = typeof utrInput === 'string' ? utrInput.replace(/\s/g, '') : '';
  if (!/^\d{12}$/.test(utr)) return { ok: false, code: 'invalid_utr' };
  const order = await env.DB.prepare('SELECT * FROM upi_orders WHERE id = ? AND business_id = ?')
    .bind(orderId, businessId).first<any>();
  if (!order) return { ok: false, code: 'not_found' };
  if (order.status === 'confirmed') return { ok: false, code: 'order_closed' };
  const paid = await env.DB.prepare('SELECT 1 FROM payments WHERE razorpay_payment_id = ?').bind(`upi:${utr}`).first();
  if (paid) return { ok: false, code: 'utr_used' };
  try {
    const r = await env.DB.prepare(
      `UPDATE upi_orders SET utr = ?, status = 'submitted', submitted_at = datetime('now'), decided_at = NULL
       WHERE id = ? AND status != 'confirmed'`
    ).bind(utr, orderId).run();
    if ((r.meta?.changes ?? 0) === 0) return { ok: false, code: 'order_closed' };
  } catch (err: any) {
    if (/UNIQUE/i.test(String(err?.message))) return { ok: false, code: 'utr_used' };
    throw err;
  }
  console.log(JSON.stringify({ msg: 'upi_payment_submitted', reference: order.reference, plan_id: order.plan_id, amount_paise: order.amount_paise }));
  return { ok: true, reference: order.reference, total_inr: order.amount_paise / 100 };
}

export interface PendingPayment {
  order_id: string;
  reference: string;
  plan_id: string;
  plan_name: string;
  total_inr: number;
  status: 'submitted' | 'rejected';
  submitted_at: string | null;
}

/** The owner's latest UPI payment still waiting for the operator, or rejected in the last 7 days. */
export async function pendingUpiPayment(env: Env, businessId: string): Promise<PendingPayment | null> {
  const row = await env.DB.prepare(
    `SELECT * FROM upi_orders WHERE business_id = ? AND status IN ('submitted', 'rejected', 'confirmed')
     ORDER BY submitted_at DESC LIMIT 1`
  ).bind(businessId).first<any>();
  if (!row) return null;
  const recentReject = row.status === 'rejected'
    && row.decided_at && Date.parse(`${row.decided_at.replace(' ', 'T')}Z`) > Date.now() - 7 * 86_400_000;
  if (row.status !== 'submitted' && !recentReject) return null;
  return {
    order_id: row.id, reference: row.reference, plan_id: row.plan_id,
    plan_name: productName(row.plan_id),
    total_inr: row.amount_paise / 100, status: row.status, submitted_at: row.submitted_at ?? null,
  };
}

export interface SubmittedUpiOrder {
  id: string;
  reference: string;
  plan_name: string;
  total_inr: number;
  utr: string;
  submitted_at: string;
}

/** Orders waiting for the operator, oldest first. No business details: the bank statement is enough. */
export async function submittedUpiOrders(env: Env): Promise<SubmittedUpiOrder[]> {
  const { results } = await env.DB.prepare(
    `SELECT id, reference, plan_id, amount_paise, utr, submitted_at FROM upi_orders
     WHERE status = 'submitted' ORDER BY submitted_at LIMIT 50`
  ).all<any>();
  return (results ?? []).map((r) => ({
    id: r.id, reference: r.reference, plan_name: productName(r.plan_id),
    total_inr: r.amount_paise / 100, utr: r.utr, submitted_at: r.submitted_at,
  }));
}

export type DecideResult =
  | { ok: true; reference: string; applied: boolean }
  | { ok: false; code: 'not_found' | 'already_decided' };

/**
 * The operator found the payment: the order is applied to the plan (a top-up on a plan that lapsed
 * meanwhile is kept for a manual credit, as with Razorpay) and the owner is told.
 */
export async function confirmUpiOrder(env: Env, orderId: string): Promise<DecideResult> {
  const order = await env.DB.prepare('SELECT * FROM upi_orders WHERE id = ?').bind(orderId).first<any>();
  if (!order) return { ok: false, code: 'not_found' };
  const claimed = await env.DB.prepare(
    `UPDATE upi_orders SET status = 'confirmed', decided_at = datetime('now') WHERE id = ? AND status = 'submitted'`
  ).bind(orderId).run();
  if ((claimed.meta?.changes ?? 0) === 0) return { ok: false, code: 'already_decided' };

  const planId: unknown = order.plan_id;
  const product = PRODUCTS[isProductId(planId) ? planId : 'starter'];
  let status: 'paid' | 'needs_review' = 'paid';
  if (product.kind === 'topup') {
    const u = await env.DB.prepare('SELECT plan_status FROM usage WHERE business_id = ?')
      .bind(order.business_id).first<{ plan_status: string }>();
    if (u?.plan_status !== 'active') status = 'needs_review';
  }
  await recordPayment(env, {
    paymentId: `upi:${order.utr}`, linkId: order.id, businessId: order.business_id, product,
    amountPaise: order.amount_paise, basePaise: order.base_paise, gstPaise: order.gst_paise, currency: 'INR',
    status, email: null, phone: null, method: 'upi',
  });
  console.log(JSON.stringify({ msg: 'upi_payment_confirmed', reference: order.reference, plan_id: product.id, status }));
  if (status === 'paid') {
    const t = ownerText(await ownerLanguage(env, order.business_id));
    await notifyPayment(env, order.business_id, t.upiConfirmedTitle, t.upiConfirmedBody(product.name));
  }
  return { ok: true, reference: order.reference, applied: status === 'paid' };
}

/** The operator found no such payment: the owner is told and can enter the UTR again. */
export async function rejectUpiOrder(env: Env, orderId: string): Promise<DecideResult> {
  const order = await env.DB.prepare('SELECT * FROM upi_orders WHERE id = ?').bind(orderId).first<any>();
  if (!order) return { ok: false, code: 'not_found' };
  const r = await env.DB.prepare(
    `UPDATE upi_orders SET status = 'rejected', decided_at = datetime('now') WHERE id = ? AND status = 'submitted'`
  ).bind(orderId).run();
  if ((r.meta?.changes ?? 0) === 0) return { ok: false, code: 'already_decided' };
  console.log(JSON.stringify({ msg: 'upi_payment_rejected', reference: order.reference }));
  const t = ownerText(await ownerLanguage(env, order.business_id));
  await notifyPayment(env, order.business_id, t.upiRejectedTitle, t.upiRejectedBody(order.reference));
  return { ok: true, reference: order.reference, applied: false };
}

/** In-app notification + push that opens the usage screen. Best effort. */
async function notifyPayment(env: Env, businessId: string, title: string, body: string): Promise<void> {
  try {
    const lang = await ownerLanguage(env, businessId);
    await env.DB.prepare(
      `INSERT INTO notifications (id, business_id, type, title, body, route, action_label, is_read, created_at)
       VALUES (?, ?, 'payment', ?, ?, '/usage', ?, 0, datetime('now'))`
    ).bind(`notif_${crypto.randomUUID().slice(0, 12)}`, businessId, title, body, ownerText(lang).view).run();
    await sendBusinessPushNotification(env, businessId, { type: 'payment', title, body, route: '/usage' });
  } catch (err: any) {
    console.error(JSON.stringify({ msg: 'upi_payment_notify_failed', error: err?.message }));
  }
}
