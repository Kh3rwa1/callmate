/**
 * Consent evidence trail (table consent_events, DPDP Act 2023 s.6(10): the Data Fiduciary must be
 * able to prove consent). One row per consent change on a lead: the value, where it came from,
 * which version of the wording the person or owner saw, and a hash of the request IP.
 *
 * Writers today: POST /leads, PATCH /leads/:id, POST /leads/import, campaign start with the
 * owner's attestation, and in-call opt-outs (Sarvam webhook). Lead-capture forms, lead-source
 * webhooks and lead integrations (services/lead_integrations.ts) record 'form' / 'webhook' /
 * 'google_ads' / 'indiamart' / 'meta_lead_ads' through captureLead.
 */
import { Env } from '../types';
import { hmacHex } from './plans';
import { globalDncSecret } from './global_dnc';

export type ConsentSource =
  | 'form' | 'webhook' | 'import_attestation' | 'manual' | 'in_call_opt_out'
  | 'google_ads' | 'indiamart' | 'meta_lead_ads';

/**
 * Version labels of the wording behind each kind of event. Bump the matching label whenever the
 * text the person or owner agrees to changes, so old evidence stays tied to old wording.
 */
export const CONSENT_TEXT_VERSIONS = {
  /** Owner adds or edits a lead in the app and picks its consent status. */
  manual: 'owner-entry-2026-10',
  /** Owner imports a file / contacts; each row's consent is the owner's statement. */
  import: 'import-2026-10',
  /** Owner ticks "I have consent to call these customers" when starting a campaign. */
  campaignAttestation: 'campaign-attestation-2026-10',
  /** Opt-out detected in the call (services/compliance.ts isOptOutRequest). */
  inCallOptOut: 'opt-out-detector-v1',
  /** Person ticked the consent box on the hosted enquiry form (routes/lead_capture_public.ts). */
  form: 'enquiry-form-2026-10',
  /** Integration posted `consent: true` to the lead webhook. */
  webhook: 'lead-webhook-2026-10',
  /** Person submitted a Google Ads lead form (asked the advertiser to contact them). */
  google_ads: 'google-ads-lead-form-2026-10',
  /** Buyer sent the seller an enquiry / call / buy requirement on IndiaMART. */
  indiamart: 'indiamart-enquiry-2026-10',
  /** Person submitted a Meta (Facebook / Instagram) Lead Ads instant form. */
  meta_lead_ads: 'meta-lead-ads-2026-10',
} as const;

export interface ConsentEventInput {
  businessId: string;
  leadId: string;
  consentValue: string;
  source: ConsentSource;
  textVersion: string;
  ipHash?: string | null;
}

/**
 * Insert statement for one event, for use inside a DB batch. Writes nothing if the lead does not
 * exist in that business (e.g. an INSERT OR IGNORE earlier in the batch skipped it).
 */
export function consentEventStatement(db: D1Database, e: ConsentEventInput): D1PreparedStatement {
  return db.prepare(
    `INSERT INTO consent_events (id, business_id, lead_id, consent_value, source, text_version, ip_hash, created_at)
     SELECT ?, ?, ?, ?, ?, ?, ?, datetime('now')
     WHERE EXISTS (SELECT 1 FROM leads WHERE id = ? AND business_id = ?)`
  ).bind(
    `ce_${crypto.randomUUID()}`, e.businessId, e.leadId, e.consentValue, e.source, e.textVersion, e.ipHash ?? null,
    e.leadId, e.businessId,
  );
}

/** Records one consent event. Shared helper for every writer (forms, webhooks, routes). */
export async function recordConsentEvent(db: D1Database, e: ConsentEventInput): Promise<void> {
  await consentEventStatement(db, e).run();
}

/**
 * One event per listed lead, taking each lead's CURRENT consent value (set-based: a handful of
 * statements however many leads). `consentValue` overrides the stored value (e.g. 'owner_attested').
 */
export async function recordConsentEventsForLeads(
  db: D1Database,
  businessId: string,
  leadIds: string[],
  e: { source: ConsentSource; textVersion: string; ipHash?: string | null; consentValue?: string },
): Promise<void> {
  const chunk = 80; // D1 caps bound parameters at 100 per statement
  const stmts: D1PreparedStatement[] = [];
  for (let i = 0; i < leadIds.length; i += chunk) {
    const slice = leadIds.slice(i, i + chunk);
    stmts.push(db.prepare(
      `INSERT INTO consent_events (id, business_id, lead_id, consent_value, source, text_version, ip_hash, created_at)
       SELECT 'ce_' || lower(hex(randomblob(16))), business_id, id, COALESCE(?, consent, 'unknown'), ?, ?, ?, datetime('now')
       FROM leads WHERE business_id = ? AND id IN (${slice.map(() => '?').join(',')})`
    ).bind(e.consentValue ?? null, e.source, e.textVersion, e.ipHash ?? null, businessId, ...slice));
  }
  for (let i = 0; i < stmts.length; i += 50) await db.batch(stmts.slice(i, i + 50));
}

/** HMAC of the client IP (never the IP itself); null if no IP or no key. */
export async function hashIp(env: Pick<Env, 'OTP_PEPPER' | 'ENCRYPTION_KEY'>, ip: string | null | undefined): Promise<string | null> {
  const secret = globalDncSecret(env);
  const value = (ip || '').trim();
  if (!secret || !value) return null;
  return hmacHex(secret, `ip:${value}`);
}

/** Client IP as Cloudflare reports it. */
export function clientIp(c: { req: { header: (name: string) => string | undefined } }): string | null {
  return c.req.header('cf-connecting-ip') || c.req.header('x-forwarded-for')?.split(',')[0]?.trim() || null;
}
