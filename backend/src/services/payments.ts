import { Env } from '../types';
import { restoreNumberIfEntitled } from './business_numbers';
import { getPlan, Product, RESET_PERIOD_BONUS_SQL } from './plans';
import { onFirstPayment } from './referrals';

/** One payment as received: from the Razorpay webhook, or a UPI order confirmed on the ops page. */
export interface PaymentRecord {
  /** Unique per payment: Razorpay's payment id, or "upi:<utr>". Stored in payments.razorpay_payment_id. */
  paymentId: string;
  linkId: string | null;
  businessId: string;
  product: Product;
  amountPaise: number;
  basePaise: number;
  gstPaise: number;
  currency: string;
  /** Only 'paid' is applied to the plan; the others are kept for a manual refund / credit. */
  status: 'paid' | 'amount_mismatch' | 'needs_review';
  email: string | null;
  phone: string | null;
  method: 'razorpay' | 'upi';
}

/**
 * Records [p] and, when it is paid, applies it to the business's plan or top-up minutes.
 * A payment seen again (redelivered webhook) is recorded once and applied once.
 */
export async function recordPayment(env: Env, p: PaymentRecord): Promise<{ duplicate: boolean }> {
  const db = env.DB;
  const insert = db.prepare(
    `INSERT OR IGNORE INTO payments
       (id, razorpay_payment_id, razorpay_payment_link_id, business_id, plan_id, kind, amount_paise, base_paise, gst_paise,
        currency, status, contact_email, contact_phone, method)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
  ).bind(
    `pay_${crypto.randomUUID().slice(0, 12)}`, p.paymentId, p.linkId,
    p.businessId, p.product.id, p.product.kind, p.amountPaise, p.basePaise, p.gstPaise, p.currency, p.status,
    p.email, p.phone, p.method,
  );

  if (p.status !== 'paid') {
    const r = await insert.run();
    return { duplicate: (r.meta?.changes ?? 0) === 0 };
  }

  const { product, businessId, paymentId } = p;
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
    // Annual: the monthly grant is fixed at purchase (annual_monthly_minutes, used by the renewal
    // cron). A year stacked onto a running one never grants less than the year already paid for.
    const grant = annual
      ? `CASE WHEN annual_until IS NOT NULL AND julianday(annual_until) > julianday('now')
              THEN MAX(COALESCE(annual_monthly_minutes, 0), ?) ELSE ? END`
      : '?';
    apply = db.prepare(
      `UPDATE usage SET
         plan_id = ?, plan_name = ?, plan_status = 'active',
         ${RESET_PERIOD_BONUS_SQL},
         topup_minutes = ${earlyRenewal('MAX(0, MIN(topup_minutes, included_minutes + topup_minutes - minutes_used))', '0')},
         included_minutes = ${grant}, minutes_used = 0, price_inr = ?,
         billing_cycle = ${annual ? `'annual'` : `CASE WHEN annual_until IS NOT NULL AND julianday(annual_until) > julianday('now') THEN 'annual' ELSE 'monthly' END`},
         annual_plan_id = ${annual ? '?' : 'annual_plan_id'},
         annual_monthly_minutes = ${annual ? grant : 'annual_monthly_minutes'},
         annual_until = ${annualUntil},
         current_period_end = datetime(${periodBase}, '+1 month'),
         renews_at = datetime(${periodBase}, '+1 month')
       WHERE business_id = ? AND ${notApplied}`
    ).bind(
      plan.id, plan.name,
      ...(annual ? [plan.includedMinutes, plan.includedMinutes] : [plan.includedMinutes]),
      plan.priceInr,
      ...(annual ? [plan.id, plan.includedMinutes, plan.includedMinutes] : []),
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
  // A business number held after a lapse (or a downgrade) goes live again with the plan.
  await restoreNumberIfEntitled(env, businessId);
  return { duplicate };
}
