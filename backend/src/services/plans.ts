/**
 * Plan catalogue, trial grants and subscription lifecycle.
 *
 * Lifecycle (usage.plan_status):
 *   trial    – new signup; TRIAL_MINUTES once per phone/email identity, no expiry date.
 *   active   – paid; renewed by a verified Razorpay payment (see routes/billing.ts), or for annual
 *              plans by the cron's monthly re-grant while annual_until is ahead.
 *   past_due – the cron found current_period_end in the past with no payment; dialing blocked.
 *   cancelled – reserved (manual); dialing blocked.
 */
import { Env } from '../types';

export type PlanId = 'trial' | 'starter' | 'growth';
export type PlanStatus = 'trial' | 'active' | 'past_due' | 'cancelled';

export const DEFAULT_TRIAL_MINUTES = 30;
export const STARTER_PRICE_INR = 4999;
export const STARTER_MINUTES = 1000;
export const GROWTH_PRICE_INR = 11999;
export const GROWTH_MINUTES = 3000;
export const RATE_PER_MINUTE_INR = 6;
/** Annual = 10 x the monthly price for 12 monthly grants ("2 months free"). */
export const ANNUAL_PRICE_MONTHS = 10;
export const DEFAULT_GST_RATE = 0.18;

export interface Plan {
  id: PlanId;
  name: string;
  priceInr: number;
  includedMinutes: number;
  paid: boolean;
}

const PAID_PLANS: Record<'starter' | 'growth', Plan> = {
  starter: { id: 'starter', name: 'Starter', priceInr: STARTER_PRICE_INR, includedMinutes: STARTER_MINUTES, paid: true },
  growth: { id: 'growth', name: 'Growth', priceInr: GROWTH_PRICE_INR, includedMinutes: GROWTH_MINUTES, paid: true },
};

export function trialMinutes(env: Pick<Env, 'TRIAL_MINUTES'>): number {
  const n = Number.parseInt(String(env.TRIAL_MINUTES ?? ''), 10);
  return Number.isFinite(n) && n >= 0 ? n : DEFAULT_TRIAL_MINUTES;
}

/** A plan by id; unknown ids fall back to Starter (legacy rows). */
export function getPlan(id: string | null | undefined, env: Pick<Env, 'TRIAL_MINUTES'> = {}): Plan {
  if (id === 'trial') {
    return { id: 'trial', name: 'Free trial', priceInr: 0, includedMinutes: trialMinutes(env), paid: false };
  }
  return id === 'growth' ? PAID_PLANS.growth : PAID_PLANS.starter;
}

// ------------------------------------------------------------------ catalogue (what checkout sells)

export type ProductKind = 'plan' | 'annual' | 'topup';

/** Everything POST /billing/checkout accepts as `plan_id`. */
export const PRODUCT_IDS = ['starter', 'growth', 'starter_annual', 'growth_annual', 'topup_250', 'topup_1000'] as const;
export type ProductId = typeof PRODUCT_IDS[number];

export interface Product {
  id: ProductId;
  kind: ProductKind;
  name: string;
  /** Price before GST, whole rupees. */
  priceInr: number;
  /** Plan products: the plan they activate. Top-ups: null. */
  planId: 'starter' | 'growth' | null;
  /** Plan products: minutes granted each month. Top-ups: minutes added once. */
  minutes: number;
  /** Monthly grants bought: 1 (monthly), 12 (annual), 0 (top-up). */
  months: number;
}

function planProduct(plan: Plan, annual: boolean): Product {
  return {
    id: (annual ? `${plan.id}_annual` : plan.id) as ProductId,
    kind: annual ? 'annual' : 'plan',
    name: annual ? `${plan.name} (annual)` : plan.name,
    priceInr: annual ? plan.priceInr * ANNUAL_PRICE_MONTHS : plan.priceInr,
    planId: plan.id as 'starter' | 'growth',
    minutes: plan.includedMinutes,
    months: annual ? 12 : 1,
  };
}

export const PRODUCTS: Record<ProductId, Product> = {
  starter: planProduct(PAID_PLANS.starter, false),
  growth: planProduct(PAID_PLANS.growth, false),
  starter_annual: planProduct(PAID_PLANS.starter, true),
  growth_annual: planProduct(PAID_PLANS.growth, true),
  topup_250: { id: 'topup_250', kind: 'topup', name: '250 extra minutes', priceInr: 1499, planId: null, minutes: 250, months: 0 },
  topup_1000: { id: 'topup_1000', kind: 'topup', name: '1000 extra minutes', priceInr: 5499, planId: null, minutes: 1000, months: 0 },
};

export function isProductId(id: unknown): id is ProductId {
  return typeof id === 'string' && (PRODUCT_IDS as readonly string[]).includes(id);
}

/** GST_RATE as a fraction in [0, 1]; default 0.18. */
export function gstRate(env: Pick<Env, 'GST_RATE'>): number {
  const raw = String(env.GST_RATE ?? '').trim();
  const n = raw === '' ? NaN : Number(raw);
  return Number.isFinite(n) && n >= 0 && n <= 1 ? n : DEFAULT_GST_RATE;
}

export interface PriceBreakdown {
  base_inr: number;
  gst_inr: number;
  /** What Razorpay charges: base + GST, rounded to whole rupees. */
  total_inr: number;
}

export function priceWithGst(baseInr: number, env: Pick<Env, 'GST_RATE'>): PriceBreakdown {
  const total = Math.round(baseInr * (1 + gstRate(env)));
  return { base_inr: baseInr, gst_inr: total - baseInr, total_inr: total };
}

// ------------------------------------------------------------------ minute balances

/**
 * Three balances (see migration 0014):
 *   included_minutes – this period's plan grant, reset at every renewal / annual month;
 *   topup_minutes    – packs bought this period, expire at current_period_end (reset at renewal);
 *   bonus_minutes    – referral / goodwill credit, never reset by renewal.
 * minutes_used counts all consumption this period. Consumption order: plan, then top-up, then
 * bonus — so only usage beyond plan + top-up eats into bonus, and that part is deducted from
 * bonus_minutes when the period resets (RESET_PERIOD_BONUS_SQL).
 */
export interface MinuteBalances {
  included_minutes?: number | null;
  topup_minutes?: number | null;
  bonus_minutes?: number | null;
  minutes_used?: number | null;
}

const n0 = (v: unknown) => {
  const n = Number(v ?? 0);
  return Number.isFinite(n) ? n : 0;
};

/** Minutes the business can still call with: plan + top-up + bonus - used (never negative). */
export function minutesRemaining(row: MinuteBalances | null | undefined): number {
  if (!row) return 0;
  return Math.max(0, n0(row.included_minutes) + n0(row.topup_minutes) + n0(row.bonus_minutes) - n0(row.minutes_used));
}

/** Where this period's usage currently sits, in consumption order. */
export function minutesBreakdown(row: MinuteBalances | null | undefined) {
  const used = n0(row?.minutes_used);
  const plan = n0(row?.included_minutes);
  const topup = n0(row?.topup_minutes);
  const bonus = n0(row?.bonus_minutes);
  const fromPlan = Math.min(used, plan);
  const fromTopup = Math.min(Math.max(0, used - plan), topup);
  const fromBonus = Math.min(Math.max(0, used - plan - topup), bonus);
  return {
    plan_left: plan - fromPlan,
    topup_left: topup - fromTopup,
    bonus_left: bonus - fromBonus,
    remaining: minutesRemaining(row),
  };
}

/** SELECT columns every "minutes remaining" check needs. */
export const MINUTE_BALANCE_COLUMNS = 'included_minutes, topup_minutes, bonus_minutes, minutes_used';

/**
 * SQL assignment for a period reset (plan payment, annual month): bonus loses what was consumed
 * beyond plan + top-up this period. Must run in the same UPDATE that resets minutes_used/topup.
 */
export const RESET_PERIOD_BONUS_SQL =
  `bonus_minutes = MAX(0, bonus_minutes - MAX(0, minutes_used - included_minutes - topup_minutes))`;

/**
 * Adds bonus minutes that survive plan renewals (referral rewards, goodwill credit).
 * Returns true if a usage row was updated.
 */
export async function addBonusMinutes(env: Pick<Env, 'DB'>, businessId: string, minutes: number, reason: string): Promise<boolean> {
  const m = Math.floor(Number(minutes));
  if (!Number.isFinite(m) || m <= 0) return false;
  const r = await env.DB.prepare('UPDATE usage SET bonus_minutes = bonus_minutes + ? WHERE business_id = ?')
    .bind(m, businessId).run();
  const ok = (r.meta?.changes ?? 0) > 0;
  console.log(JSON.stringify({ msg: 'bonus_minutes_added', business_id: businessId, minutes: m, reason, applied: ok }));
  return ok;
}

/** Kept for callers that only need the plan ids a checkout can activate. */
export const PAID_PLAN_IDS: readonly PlanId[] = ['starter', 'growth'];

// ------------------------------------------------------------------ dialing guard

export const PLAN_BLOCKED_BODY = {
  message: 'Your plan payment is due. Renew your plan to keep calling.',
  code: 'plan_inactive',
} as const;

export function statusBlocksDialing(status: string | null | undefined): boolean {
  return status === 'past_due' || status === 'cancelled';
}

/** True when the business's plan is past_due/cancelled. A missing usage row is not blocked here. */
export async function isPlanBlocked(db: D1Database, businessId: string): Promise<boolean> {
  const row = await db.prepare('SELECT plan_status FROM usage WHERE business_id = ?')
    .bind(businessId).first<{ plan_status: string | null }>();
  return statusBlocksDialing(row?.plan_status);
}

/** Campaign dispatch: pause the campaign (like exhausted minutes) and ack the job. */
export async function pauseCampaignForBilling(db: D1Database, campaignId: string, businessId: string) {
  await db.prepare(`UPDATE campaigns SET status = 'paused' WHERE id = ? AND business_id = ?`)
    .bind(campaignId, businessId).run();
  return { success: true, reason: 'plan_inactive' };
}

// ------------------------------------------------------------------ trial grants

function identitySecret(env: Env): string {
  const s = (env.OTP_PEPPER || env.ENCRYPTION_KEY || '').trim();
  if (s.length < 16) throw new Error('OTP_PEPPER (or ENCRYPTION_KEY) is required to hash trial identities.');
  return s;
}

export async function hmacHex(secret: string, message: string): Promise<string> {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey('raw', enc.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const sig = await crypto.subtle.sign('HMAC', key, enc.encode(message));
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

/** HMAC'd identity keys (phone digits, lower-cased email). Raw values are never stored. */
export async function trialIdentityHashes(env: Env, identity: { phone?: string | null; email?: string | null }): Promise<string[]> {
  const secret = identitySecret(env);
  const keys: string[] = [];
  const phone = (identity.phone ?? '').replace(/\D/g, '');
  if (phone) keys.push(await hmacHex(secret, `trial:phone:${phone}`));
  const email = (identity.email ?? '').trim().toLowerCase();
  if (email) keys.push(await hmacHex(secret, `trial:email:${email}`));
  return keys;
}

/**
 * Trial minutes a new signup gets: TRIAL_MINUTES the first time any of its identities is seen,
 * 0 if the phone or email already had a trial (e.g. delete account + sign up again).
 * Records the identities either way.
 */
export async function claimTrialMinutes(env: Env, identity: { phone?: string | null; email?: string | null }): Promise<number> {
  const hashes = await trialIdentityHashes(env, identity);
  if (hashes.length === 0) return 0;
  const minutes = trialMinutes(env);
  const placeholders = hashes.map(() => '?').join(',');
  const seen = await env.DB.prepare(`SELECT COUNT(*) AS n FROM trial_grants WHERE identity_hash IN (${placeholders})`)
    .bind(...hashes).first<{ n: number }>();
  const granted = (seen?.n ?? 0) > 0 ? 0 : minutes;
  await env.DB.batch(hashes.map((h) =>
    env.DB.prepare('INSERT OR IGNORE INTO trial_grants (identity_hash, minutes) VALUES (?, ?)').bind(h, granted)));
  return granted;
}

/** Statements that remember identities at account deletion (covers accounts created before trial_grants). */
export async function rememberTrialIdentities(env: Env, identity: { phone?: string | null; email?: string | null }): Promise<D1PreparedStatement[]> {
  const hashes = await trialIdentityHashes(env, identity);
  return hashes.map((h) => env.DB.prepare('INSERT OR IGNORE INTO trial_grants (identity_hash, minutes) VALUES (?, 0)').bind(h));
}

/** Stable pseudonym for a deleted business, so retained ledger/payment rows still group together. */
export async function anonymisedBusinessId(env: Env, businessId: string): Promise<string> {
  return `anon_${(await hmacHex(identitySecret(env), `biz:${businessId}`)).slice(0, 24)}`;
}

// ------------------------------------------------------------------ renewal cron

/** SQL CASE mapping a plan id expression to a value of its catalogue plan (starter is the fallback). */
function planCase(column: string, pick: (p: Plan) => string | number): string {
  const v = (x: string | number) => (typeof x === 'number' ? String(x) : `'${x.replace(/'/g, "''")}'`);
  return `CASE ${column} WHEN 'growth' THEN ${v(pick(PAID_PLANS.growth))} ELSE ${v(pick(PAID_PLANS.starter))} END`;
}

/** An annual plan still has more than a day left after the current monthly period. */
const ANNUAL_HAS_MORE_MONTHS =
  `annual_until IS NOT NULL AND julianday(annual_until) - julianday(current_period_end) > 1`;

/**
 * Runs from the 10-minute cron.
 * 1. Annual plans: a monthly period that ended is re-granted (minutes reset, next month) without a
 *    payment while annual_until is ahead. The last period ends exactly at annual_until.
 * 2. Any other active period that ended without a payment becomes past_due (dialing blocked).
 * Rows with current_period_end NULL (legacy accounts, trials) never expire here.
 * Returns the number of plans moved to past_due.
 */
export async function runBillingRenewals(env: Env): Promise<number> {
  const annualPlan = 'COALESCE(annual_plan_id, plan_id)';
  const nextEnd = `CASE WHEN julianday(datetime(current_period_end, '+1 month')) > julianday(annual_until)
                        THEN annual_until ELSE datetime(current_period_end, '+1 month') END`;
  const ended = `plan_status = 'active' AND current_period_end IS NOT NULL
                 AND julianday(current_period_end) <= julianday('now')`;
  const regrant = await env.DB.prepare(
    `UPDATE usage SET
       plan_id = ${planCase(annualPlan, (p) => p.id)},
       plan_name = ${planCase(annualPlan, (p) => p.name)},
       included_minutes = ${planCase(annualPlan, (p) => p.includedMinutes)},
       price_inr = ${planCase(annualPlan, (p) => p.priceInr)},
       billing_cycle = 'annual', ${RESET_PERIOD_BONUS_SQL}, minutes_used = 0, topup_minutes = 0,
       current_period_end = ${nextEnd},
       renews_at = ${nextEnd}
     WHERE ${ended} AND ${ANNUAL_HAS_MORE_MONTHS}`
  ).run();
  const regranted = regrant.meta?.changes ?? 0;
  if (regranted > 0) console.log(JSON.stringify({ msg: 'annual_month_regranted', count: regranted }));

  const r = await env.DB.prepare(
    `UPDATE usage SET plan_status = 'past_due'
     WHERE ${ended} AND NOT (${ANNUAL_HAS_MORE_MONTHS})`
  ).run();
  return r.meta?.changes ?? 0;
}

// ------------------------------------------------------------------ read model

export interface CatalogueItem {
  plan_id: ProductId;
  kind: ProductKind;
  name: string;
  /** Before GST (older apps show this as the price). */
  price_inr: number;
  gst_inr: number;
  /** What the payment page charges. */
  total_inr: number;
  /** Plans: minutes per month. Top-ups: minutes added once. */
  included_minutes: number;
  /** Monthly grants bought: 1, 12, or 0 for a top-up. */
  months: number;
}

export interface BillingView {
  plan_id: PlanId;
  plan_name: string;
  plan_status: PlanStatus;
  billing_cycle: 'monthly' | 'annual';
  current_period_end: string | null;
  annual_until: string | null;
  price_inr: number;
  /** This period's plan grant. */
  included_minutes: number;
  /** Top-up minutes bought this period (expire at current_period_end). */
  topup_minutes: number;
  /** Bonus minutes (referrals etc.), kept across renewals. */
  bonus_minutes: number;
  minutes_used: number;
  /** plan + top-up + bonus - used. */
  minutes_left: number;
  gst_rate: number;
  /** What "Upgrade"/"Renew" buys: the current paid plan monthly, or Starter. */
  checkout_plan: CatalogueItem;
  /** Plans the picker offers (monthly + annual). */
  plans: CatalogueItem[];
  /** Top-up packs; buyable only while plan_status is active. */
  topups: CatalogueItem[];
  can_buy_topup: boolean;
}

export function catalogueItem(p: Product, env: Pick<Env, 'GST_RATE'>): CatalogueItem {
  const price = priceWithGst(p.priceInr, env);
  return {
    plan_id: p.id, kind: p.kind, name: p.name,
    price_inr: price.base_inr, gst_inr: price.gst_inr, total_inr: price.total_inr,
    included_minutes: p.minutes, months: p.months,
  };
}

export function billingView(row: any, env: Env): BillingView {
  const plan = getPlan(row?.plan_id, env);
  const status = (['trial', 'active', 'past_due', 'cancelled'].includes(row?.plan_status) ? row.plan_status : 'active') as PlanStatus;
  const included = Number(row?.included_minutes ?? 0);
  const used = Number(row?.minutes_used ?? 0);
  const renew = PRODUCTS[plan.id === 'growth' ? 'growth' : 'starter'];
  const all = PRODUCT_IDS.map((id) => catalogueItem(PRODUCTS[id], env));
  return {
    plan_id: plan.id,
    plan_name: plan.name,
    plan_status: status,
    billing_cycle: row?.billing_cycle === 'annual' ? 'annual' : 'monthly',
    current_period_end: row?.current_period_end ?? null,
    annual_until: row?.annual_until ?? null,
    price_inr: plan.priceInr,
    included_minutes: included,
    topup_minutes: Number(row?.topup_minutes ?? 0),
    bonus_minutes: Number(row?.bonus_minutes ?? 0),
    minutes_used: used,
    minutes_left: minutesRemaining(row),
    gst_rate: gstRate(env),
    checkout_plan: catalogueItem(renew, env),
    plans: all.filter((p) => p.kind !== 'topup'),
    topups: all.filter((p) => p.kind === 'topup'),
    can_buy_topup: status === 'active',
  };
}
