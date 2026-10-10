/**
 * Plan catalogue, trial grants and subscription lifecycle.
 *
 * Lifecycle (usage.plan_status):
 *   trial    – new signup; TRIAL_MINUTES once per phone/email identity, no expiry date.
 *   active   – paid; renewed ONLY by a verified Razorpay payment (see routes/billing.ts).
 *   past_due – the cron found current_period_end in the past with no payment; dialing blocked.
 *   cancelled – reserved (manual); dialing blocked.
 */
import { Env } from '../types';

export type PlanId = 'trial' | 'starter';
export type PlanStatus = 'trial' | 'active' | 'past_due' | 'cancelled';

export const DEFAULT_TRIAL_MINUTES = 30;
export const STARTER_PRICE_INR = 4999;
export const STARTER_MINUTES = 1000;
export const RATE_PER_MINUTE_INR = 6;

export interface Plan {
  id: PlanId;
  name: string;
  priceInr: number;
  includedMinutes: number;
  paid: boolean;
}

export function trialMinutes(env: Pick<Env, 'TRIAL_MINUTES'>): number {
  const n = Number.parseInt(String(env.TRIAL_MINUTES ?? ''), 10);
  return Number.isFinite(n) && n >= 0 ? n : DEFAULT_TRIAL_MINUTES;
}

export function getPlan(id: string | null | undefined, env: Pick<Env, 'TRIAL_MINUTES'> = {}): Plan {
  if (id === 'trial') {
    return { id: 'trial', name: 'Free trial', priceInr: 0, includedMinutes: trialMinutes(env), paid: false };
  }
  return { id: 'starter', name: 'Starter', priceInr: STARTER_PRICE_INR, includedMinutes: STARTER_MINUTES, paid: true };
}

/** The plan a checkout buys. Only one paid plan today. */
export const PAID_PLAN_IDS: readonly PlanId[] = ['starter'];

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

/**
 * Runs from the 10-minute cron. Renewal itself only happens on a verified payment webhook;
 * an active period that ends without one becomes past_due (dialing blocked).
 * Rows with current_period_end NULL (legacy accounts, trials) never expire here.
 */
export async function runBillingRenewals(env: Env): Promise<number> {
  const r = await env.DB.prepare(
    `UPDATE usage SET plan_status = 'past_due'
     WHERE plan_status = 'active' AND current_period_end IS NOT NULL
       AND julianday(current_period_end) <= julianday('now')`
  ).run();
  return r.meta?.changes ?? 0;
}

// ------------------------------------------------------------------ read model

export interface BillingView {
  plan_id: PlanId;
  plan_name: string;
  plan_status: PlanStatus;
  current_period_end: string | null;
  price_inr: number;
  included_minutes: number;
  minutes_used: number;
  minutes_left: number;
  /** What "Upgrade"/"Renew" buys. */
  checkout_plan: { plan_id: PlanId; name: string; price_inr: number; included_minutes: number };
}

export function billingView(row: any, env: Env): BillingView {
  const plan = getPlan(row?.plan_id, env);
  const status = (['trial', 'active', 'past_due', 'cancelled'].includes(row?.plan_status) ? row.plan_status : 'active') as PlanStatus;
  const included = Number(row?.included_minutes ?? 0);
  const used = Number(row?.minutes_used ?? 0);
  const paid = getPlan('starter', env);
  return {
    plan_id: plan.id,
    plan_name: plan.name,
    plan_status: status,
    current_period_end: row?.current_period_end ?? null,
    price_inr: plan.priceInr,
    included_minutes: included,
    minutes_used: used,
    minutes_left: Math.max(0, included - used),
    checkout_plan: { plan_id: paid.id, name: paid.name, price_inr: paid.priceInr, included_minutes: paid.includedMinutes },
  };
}
