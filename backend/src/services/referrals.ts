/**
 * Referral program: every business gets a short code; a new business that signs up with it is
 * recorded as referred; when the referred business's first payment is applied, both businesses get
 * REFERRAL_BONUS_MINUTES added to usage.included_minutes (once, with a referral_credits ledger row each).
 *
 * Abuse guards:
 *  - a business can't use its own code, nor can a signup sharing the referrer's phone or email;
 *  - a phone identity can be referred once, ever (survives account deletion);
 *  - the reward needs a verified, applied payment, and is applied at most once per referral.
 */
import { Env } from '../types';
import { trialIdentityHashes } from './plans';
import { escapeHtml } from '../routes/legal';

export const DEFAULT_REFERRAL_BONUS_MINUTES = 200;

/** No 0/O, 1/I/L: codes are read out loud and typed from WhatsApp messages. */
export const REFERRAL_ALPHABET = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
export const REFERRAL_CODE_LENGTH = 6;
const CODE_RE = new RegExp(`^[${REFERRAL_ALPHABET}]{${REFERRAL_CODE_LENGTH}}$`);

/** Public path of the landing page (routes/landing.ts). */
export const LANDING_PATH = '/get';

export function referralBonusMinutes(env: Pick<Env, 'REFERRAL_BONUS_MINUTES'>): number {
  const n = Number.parseInt(String(env.REFERRAL_BONUS_MINUTES ?? ''), 10);
  return Number.isFinite(n) && n >= 0 ? n : DEFAULT_REFERRAL_BONUS_MINUTES;
}

export function generateReferralCode(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(REFERRAL_CODE_LENGTH));
  // 256 % 31 bias is negligible for codes that are not secrets.
  return [...bytes].map((b) => REFERRAL_ALPHABET[b % REFERRAL_ALPHABET.length]).join('');
}

/** Upper-cases and strips spaces/dashes; returns null unless it is a well-formed code. */
export function normalizeReferralCode(raw: unknown): string | null {
  if (typeof raw !== 'string') return null;
  const code = raw.toUpperCase().replace(/[\s-]/g, '');
  return CODE_RE.test(code) ? code : null;
}

/** Returns the business's code, creating one on first use. */
export async function ensureReferralCode(env: Env, businessId: string): Promise<string> {
  const row = await env.DB.prepare('SELECT referral_code FROM businesses WHERE id = ?')
    .bind(businessId).first<{ referral_code: string | null }>();
  if (row?.referral_code) return row.referral_code;
  for (let attempt = 0; attempt < 8; attempt++) {
    const code = generateReferralCode();
    try {
      await env.DB.prepare('UPDATE businesses SET referral_code = ? WHERE id = ? AND referral_code IS NULL')
        .bind(code, businessId).run();
    } catch {
      continue; // unique index collision: try another code
    }
    const after = await env.DB.prepare('SELECT referral_code FROM businesses WHERE id = ?')
      .bind(businessId).first<{ referral_code: string | null }>();
    if (after?.referral_code) return after.referral_code;
  }
  throw new Error('Could not allocate a referral code.');
}

/** Absolute (or, without a base, root-relative) landing-page link carrying ?ref=. */
export function referralLink(code: string | null | undefined, baseUrl = ''): string {
  const base = baseUrl.replace(/\/+$/, '');
  const ref = normalizeReferralCode(code);
  return `${base}${LANDING_PATH}${ref ? `?ref=${encodeURIComponent(ref)}` : ''}`;
}

/**
 * Small "Powered by CallPilot" footer for public pages a business shares (e.g. its lead form).
 * Links to the landing page with the business's ref code so new signups are attributed.
 */
export function poweredByFooterHtml(code: string | null | undefined, baseUrl = ''): string {
  const href = escapeHtml(referralLink(code, baseUrl));
  return `<p class="powered-by" style="margin:24px 0 0;text-align:center;font-size:0.8rem;opacity:0.75">`
    + `<a href="${href}" rel="noopener" style="color:inherit">Powered by CallPilot</a>`
    + ` · AI that calls back every enquiry</p>`;
}

export type ReferralSignupResult = 'recorded' | 'invalid_code' | 'self_referral' | 'already_referred' | 'none';

/**
 * Called right after a new account is provisioned (both OTP and Google signup).
 * Never throws: a bad referral code must not break signup.
 */
export async function recordReferral(
  env: Env,
  referredBusinessId: string,
  rawCode: string | null | undefined,
  identity: { phone?: string | null; email?: string | null },
): Promise<ReferralSignupResult> {
  if (rawCode == null || String(rawCode).trim() === '') return 'none';
  try {
    const code = normalizeReferralCode(rawCode);
    if (!code) return 'invalid_code';
    const referrer = await env.DB.prepare('SELECT id FROM businesses WHERE referral_code = ?')
      .bind(code).first<{ id: string }>();
    if (!referrer) return 'invalid_code';
    if (referrer.id === referredBusinessId) return 'self_referral';

    const referredHashes = await trialIdentityHashes(env, identity);
    const owners = await env.DB.prepare('SELECT phone, email FROM users WHERE business_id = ?')
      .bind(referrer.id).all<{ phone: string | null; email: string | null }>();
    const ownerHashes = new Set<string>();
    for (const o of owners.results ?? []) {
      for (const h of await trialIdentityHashes(env, { phone: o.phone, email: o.email })) ownerHashes.add(h);
    }
    if (referredHashes.some((h) => ownerHashes.has(h))) return 'self_referral';

    if (referredHashes.length > 0) {
      const placeholders = referredHashes.map(() => '?').join(',');
      const seen = await env.DB.prepare(`SELECT 1 FROM referrals WHERE referred_identity_hash IN (${placeholders}) LIMIT 1`)
        .bind(...referredHashes).first();
      if (seen) return 'already_referred';
    }

    const r = await env.DB.prepare(
      `INSERT OR IGNORE INTO referrals (id, referrer_business_id, referred_business_id, code, status, referred_identity_hash)
       VALUES (?, ?, ?, ?, 'signed_up', ?)`
    ).bind(`ref_${crypto.randomUUID().slice(0, 12)}`, referrer.id, referredBusinessId, code, referredHashes[0] ?? null).run();
    return (r.meta?.changes ?? 0) > 0 ? 'recorded' : 'already_referred';
  } catch (err: any) {
    console.error(JSON.stringify({ msg: 'referral_record_failed', error: String(err?.message ?? err) }));
    return 'none';
  }
}

/**
 * Billing hook: call after a payment is applied (routes/billing.ts webhook). If [businessId] was
 * referred and has an applied payment, credits both businesses once. Safe to call on every
 * (re)delivery: a referral already rewarded, or a business with no referral, is a no-op.
 * Never throws (the payment itself is already recorded).
 */
export async function onFirstPayment(env: Env, businessId: string): Promise<boolean> {
  try {
    const ref = await env.DB.prepare(
      `SELECT id, referrer_business_id FROM referrals WHERE referred_business_id = ? AND status = 'signed_up'`
    ).bind(businessId).first<{ id: string; referrer_business_id: string }>();
    if (!ref) return false;
    const paid = await env.DB.prepare(
      `SELECT 1 FROM payments WHERE business_id = ? AND status = 'paid' AND applied_at IS NOT NULL LIMIT 1`
    ).bind(businessId).first();
    if (!paid) return false;

    const minutes = referralBonusMinutes(env);
    const nonce = crypto.randomUUID();
    const won = `EXISTS (SELECT 1 FROM referrals WHERE id = ? AND reward_nonce = ?)`;
    const credit = (bizId: string) => env.DB.prepare(
      `INSERT OR IGNORE INTO referral_credits (id, referral_id, business_id, minutes) SELECT ?, ?, ?, ? WHERE ${won}`
    ).bind(`rc_${crypto.randomUUID().slice(0, 12)}`, ref.id, bizId, minutes, ref.id, nonce);

    // One transaction. Only the call whose UPDATE flipped signed_up -> rewarded owns the nonce,
    // so concurrent or redelivered webhooks can't credit twice.
    const results = await env.DB.batch([
      env.DB.prepare(
        `UPDATE referrals SET status = 'rewarded', rewarded_at = datetime('now'), reward_nonce = ?
         WHERE id = ? AND status = 'signed_up'`
      ).bind(nonce, ref.id),
      env.DB.prepare(
        `UPDATE usage SET included_minutes = included_minutes + ? WHERE business_id IN (?, ?) AND ${won}`
      ).bind(minutes, businessId, ref.referrer_business_id, ref.id, nonce),
      credit(businessId),
      credit(ref.referrer_business_id),
    ]);
    return (results[0].meta?.changes ?? 0) > 0;
  } catch (err: any) {
    console.error(JSON.stringify({ msg: 'referral_reward_failed', business_id: businessId, error: String(err?.message ?? err) }));
    return false;
  }
}

export interface ReferralSummary {
  code: string;
  link: string;
  bonus_minutes: number;
  signed_up: number;
  rewarded: number;
  minutes_earned: number;
}

export async function referralSummary(env: Env, businessId: string, baseUrl: string): Promise<ReferralSummary> {
  const code = await ensureReferralCode(env, businessId);
  const counts = await env.DB.prepare(
    `SELECT COUNT(*) AS signed_up, COALESCE(SUM(CASE WHEN status = 'rewarded' THEN 1 ELSE 0 END), 0) AS rewarded
     FROM referrals WHERE referrer_business_id = ?`
  ).bind(businessId).first<{ signed_up: number; rewarded: number }>();
  const earned = await env.DB.prepare('SELECT COALESCE(SUM(minutes), 0) AS m FROM referral_credits WHERE business_id = ?')
    .bind(businessId).first<{ m: number }>();
  return {
    code,
    link: referralLink(code, baseUrl),
    bonus_minutes: referralBonusMinutes(env),
    signed_up: Number(counts?.signed_up ?? 0),
    rewarded: Number(counts?.rewarded ?? 0),
    minutes_earned: Number(earned?.m ?? 0),
  };
}

/** Account deletion: keep referral rows (abuse guard + ledger) but replace business ids with the pseudonym. */
export function referralDeletionStatements(env: Env, businessId: string, anonId: string): D1PreparedStatement[] {
  return [
    env.DB.prepare('UPDATE referrals SET referrer_business_id = ? WHERE referrer_business_id = ?').bind(anonId, businessId),
    env.DB.prepare('UPDATE referrals SET referred_business_id = ? WHERE referred_business_id = ?').bind(anonId, businessId),
    env.DB.prepare('UPDATE referral_credits SET business_id = ? WHERE business_id = ?').bind(anonId, businessId),
  ];
}
