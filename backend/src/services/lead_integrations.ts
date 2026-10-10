/**
 * Lead integrations: Google Ads lead forms, IndiaMART Lead Manager and Meta (Facebook / Instagram)
 * Lead Ads. Each is a lead_sources kind whose leads go through the SAME speed-to-lead pipeline as
 * the hosted form (services/lead_capture.ts captureLead → consent event → instant AI call through
 * services/dial.ts with every guard). Nothing here dials or writes leads directly.
 *
 *   google_ads  Google POSTs each lead to /hooks/google-ads/:slug with the `google_key` the owner
 *               pasted into the lead form (stored as SHA-256, compared in constant time).
 *   indiamart   Cron pulls the Lead Manager Pull API with the owner's CRM key (encrypted at rest),
 *               at most once per 5 minutes per source; IndiaMART's Push API may also POST to
 *               /hooks/indiamart/:slug?key=<token>.
 *   meta        Meta verifies /hooks/meta/:slug (hub.challenge with our verify token), then POSTs
 *               leadgen events signed with the owner's app secret (X-Hub-Signature-256); the lead's
 *               fields are fetched from the Graph API with the owner's page access token.
 *
 * Providers redeliver and IndiaMART pull windows overlap, so each provider lead id is claimed once
 * in lead_external_ids before capture (and released again if capture crashes, so a retry works).
 */
import { Env } from '../types';
import { encryptAtRest, decryptAtRest } from '../utils/crypto_data';
import { timingSafeEqual } from '../utils/compare';
import { hmacHex } from './plans';
import {
  captureLead, randomToken, sqliteNow, type CaptureInput, type CaptureResult, type LeadSourceRow,
} from './lead_capture';

export const INTEGRATION_KINDS = ['google_ads', 'indiamart', 'meta'] as const;
export type IntegrationKind = typeof INTEGRATION_KINDS[number];

export function isIntegrationKind(kind: string): kind is IntegrationKind {
  return (INTEGRATION_KINDS as readonly string[]).includes(kind);
}

const INTEREST_MAX = 500;
const NAME_MAX = 100;

// ------------------------------------------------------------------ secrets

/** Key the owner pastes into the Google Ads lead form's webhook "Key" field. */
export function newGoogleAdsKey(): string {
  return `cpga${randomToken(32)}`;
}

/** Token in the IndiaMART Push API listener URL (`?key=`). */
export function newIndiaMartPushToken(): string {
  return `cpim${randomToken(32)}`;
}

/** Verify token the owner pastes into the Meta app's webhook settings. */
export function newMetaVerifyToken(): string {
  return `cpmv${randomToken(32)}`;
}

/** Integration secrets the server needs later. Stored only encrypted (lead_sources.config_encrypted). */
export interface IntegrationConfig {
  crm_key?: string;
  app_secret?: string;
  page_access_token?: string;
}

export class IntegrationNotConfiguredError extends Error {
  constructor() {
    super('ENCRYPTION_KEY is not configured');
  }
}

export async function encryptConfig(env: Pick<Env, 'ENCRYPTION_KEY'>, cfg: IntegrationConfig): Promise<string> {
  if (!env.ENCRYPTION_KEY) throw new IntegrationNotConfiguredError();
  return (await encryptAtRest(JSON.stringify(cfg), env.ENCRYPTION_KEY)) as string;
}

/** Decrypted config, or null if missing / undecryptable (e.g. the key was rotated). */
export async function readConfig(env: Pick<Env, 'ENCRYPTION_KEY'>, row: Pick<LeadSourceRow, 'config_encrypted'>): Promise<IntegrationConfig | null> {
  if (!row.config_encrypted || !env.ENCRYPTION_KEY) return null;
  try {
    const plain = await decryptAtRest(row.config_encrypted, env.ENCRYPTION_KEY);
    if (!plain || plain.startsWith('enc:')) return null;
    return JSON.parse(plain) as IntegrationConfig;
  } catch {
    return null;
  }
}

// ------------------------------------------------------------------ errors shown to the owner

/** Problems only the owner can fix: they get one notification when the source starts failing. */
const OWNER_ACTION_ERRORS = new Set(['invalid_key', 'meta_token_invalid', 'config_unreadable']);

export async function setSourceError(env: Env, source: LeadSourceRow, code: string | null): Promise<void> {
  const previous = source.last_error ?? null;
  await env.DB.prepare('UPDATE lead_sources SET last_error = ? WHERE id = ?').bind(code, source.id).run();
  source.last_error = code;
  if (code && code !== previous && OWNER_ACTION_ERRORS.has(code)) {
    const name = source.kind === 'indiamart' ? 'IndiaMART' : source.kind === 'meta' ? 'Facebook & Instagram' : 'Google Ads';
    try {
      await env.DB.prepare(
        `INSERT INTO notifications (id, business_id, type, title, body, route, action_label, is_read, created_at)
         VALUES (?, ?, 'lead_source_error', ?, ?, '/leads/auto', 'Fix', 0, datetime('now'))`
      ).bind(
        `notif_${crypto.randomUUID().slice(0, 12)}`, source.business_id,
        `${name} connection stopped working`,
        'New leads are not coming in. Open "Get leads automatically" and connect it again.',
      ).run();
    } catch (err: any) {
      console.error(JSON.stringify({ msg: 'lead_source_error_notification_failed', error: err?.message }));
    }
  }
}

// ------------------------------------------------------------------ dedupe + capture

/** Claims a provider lead id for this business. False = already seen (redelivery / overlap). */
export async function claimExternalId(db: D1Database, source: LeadSourceRow, externalId: string): Promise<boolean> {
  const res = await db.prepare(
    `INSERT OR IGNORE INTO lead_external_ids (business_id, kind, external_id, lead_source_id, created_at)
     VALUES (?, ?, ?, ?, datetime('now'))`
  ).bind(source.business_id, source.kind, externalId, source.id).run();
  return (res.meta?.changes ?? 0) === 1;
}

export async function releaseExternalId(db: D1Database, source: LeadSourceRow, externalId: string): Promise<void> {
  await db.prepare('DELETE FROM lead_external_ids WHERE business_id = ? AND kind = ? AND external_id = ?')
    .bind(source.business_id, source.kind, externalId).run();
}

export type ExternalCaptureResult = CaptureResult | { status: 'already_seen' };

/**
 * Captures one provider lead exactly once. Without an external id it falls back to the phone
 * dedupe in captureLead alone. If capture throws, the claim is released so a provider retry works.
 * `alreadyClaimed`: the caller claimed `externalId` itself (e.g. before fetching the lead's fields).
 */
export async function captureExternalLead(
  env: Env,
  source: LeadSourceRow,
  externalId: string | null,
  input: CaptureInput,
  opts: { fallbackBaseUrl?: string; waitUntil?: (p: Promise<unknown>) => void; alreadyClaimed?: boolean } = {},
): Promise<ExternalCaptureResult> {
  const id = externalId?.trim().slice(0, 200) || null;
  if (id && !opts.alreadyClaimed && !(await claimExternalId(env.DB, source, id))) return { status: 'already_seen' };
  try {
    const result = await captureLead(env, source, input, { fallbackBaseUrl: opts.fallbackBaseUrl, waitUntil: opts.waitUntil });
    if (id && result.status !== 'invalid_phone') {
      await env.DB.prepare('UPDATE lead_external_ids SET lead_id = ? WHERE business_id = ? AND kind = ? AND external_id = ?')
        .bind(result.leadId, source.business_id, source.kind, id).run();
    }
    return result;
  } catch (err) {
    if (id) await releaseExternalId(env.DB, source, id).catch(() => {});
    throw err;
  }
}

function clip(value: string, max: number): string {
  return value.length > max ? `${value.slice(0, max - 1)}…` : value;
}

function humanize(id: string): string {
  const words = id.toLowerCase().replace(/_/g, ' ').trim();
  return words.charAt(0).toUpperCase() + words.slice(1);
}

/** Answers to extra form questions, as one line for the lead's "interest". */
function interestFrom(parts: Array<[string, string]>): string | null {
  const text = parts
    .filter(([, v]) => v.trim() !== '')
    .map(([k, v]) => (k ? `${k}: ${v.trim()}` : v.trim()))
    .join('; ');
  return text ? clip(text, INTEREST_MAX) : null;
}

export interface MappedLead {
  externalId: string | null;
  input: CaptureInput;
}

// ------------------------------------------------------------------ Google Ads

/** https://developers.google.com/google-ads/webhook/docs/implementation */
export interface GoogleAdsLeadPayload {
  lead_id?: string;
  user_column_data?: Array<{ column_id?: string; column_name?: string; string_value?: string }>;
  google_key?: string;
  is_test?: boolean;
  campaign_id?: number | string;
  form_id?: number | string;
  [k: string]: unknown;
}

const GOOGLE_IGNORED_COLUMNS = new Set(['PHONE_NUMBER_VERIFIED', 'POSTAL_CODE', 'STREET_ADDRESS', 'REGION', 'COUNTRY', 'WORK_EMAIL', 'WORK_PHONE']);

/** Google Ads lead form → enquiry. Null when there is no phone number to call. */
export function mapGoogleAdsLead(payload: GoogleAdsLeadPayload): MappedLead | null {
  const cols = new Map<string, string>();
  const extra: Array<[string, string]> = [];
  for (const col of Array.isArray(payload.user_column_data) ? payload.user_column_data : []) {
    const id = String(col?.column_id ?? '').toUpperCase();
    const value = typeof col?.string_value === 'string' ? col.string_value.trim() : '';
    if (!value) continue;
    if (['FULL_NAME', 'FIRST_NAME', 'LAST_NAME', 'PHONE_NUMBER', 'EMAIL', 'CITY', 'COMPANY_NAME', 'JOB_TITLE'].includes(id)) {
      cols.set(id, value);
    } else if (GOOGLE_IGNORED_COLUMNS.has(id)) {
      cols.set(id, value);
    } else {
      extra.push([col?.column_name?.trim() || humanize(id || 'answer'), value]);
    }
  }
  const phone = cols.get('PHONE_NUMBER') || cols.get('WORK_PHONE');
  if (!phone) return null;
  const name = cols.get('FULL_NAME') || [cols.get('FIRST_NAME'), cols.get('LAST_NAME')].filter(Boolean).join(' ') || 'Google Ads lead';
  const attributes: Record<string, string> = {};
  const email = cols.get('EMAIL') || cols.get('WORK_EMAIL');
  if (email) attributes.email = email;
  if (cols.get('CITY')) attributes.city = cols.get('CITY')!;
  if (cols.get('COMPANY_NAME')) attributes.company = cols.get('COMPANY_NAME')!;
  if (payload.campaign_id != null) attributes.google_campaign_id = String(payload.campaign_id);
  return {
    externalId: payload.lead_id ? String(payload.lead_id) : null,
    input: { name: clip(name, NAME_MAX), phone, interest: interestFrom(extra), attributes },
  };
}

// ------------------------------------------------------------------ IndiaMART

/** https://help.indiamart.com/knowledge-base/lms-crm-integration-v2/ */
export const INDIAMART_PULL_URL = 'https://mapi.indiamart.com/wservce/crm/crmListing/v2/';
/** IndiaMART allows one pull per key every 5 minutes. */
export const INDIAMART_MIN_INTERVAL_SECONDS = 300;
/** More than 5 hits in a minute blocks the key for 15 minutes. */
export const INDIAMART_BLOCK_SECONDS = 900;
/** Recommended rolling overlap ("Strategy 2"): start 5 min before the previous end. */
export const INDIAMART_OVERLAP_SECONDS = 300;
/** Longest window IndiaMART accepts. */
export const INDIAMART_MAX_WINDOW_SECONDS = 7 * 24 * 3600;
/** After a dead key, try again hourly (the owner may have regenerated it on IndiaMART's side). */
export const INDIAMART_INVALID_KEY_RETRY_SECONDS = 3600;
/** Sources pulled per cron run (each is one HTTP request). */
export const INDIAMART_PULLS_PER_RUN = 50;

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/** IndiaMART time parameter: IST, `DD-Mon-YYYYHH:MM:SS` (e.g. 01-Jan-202209:00:00). */
export function indiaMartTime(date: Date): string {
  const ist = new Date(date.getTime() + 330 * 60_000);
  const p = (n: number) => String(n).padStart(2, '0');
  return `${p(ist.getUTCDate())}-${MONTHS[ist.getUTCMonth()]}-${ist.getUTCFullYear()}`
    + `${p(ist.getUTCHours())}:${p(ist.getUTCMinutes())}:${p(ist.getUTCSeconds())}`;
}

export interface IndiaMartRecord {
  UNIQUE_QUERY_ID?: string | number;
  QUERY_TYPE?: string;
  SENDER_NAME?: string;
  SENDER_MOBILE?: string;
  SENDER_MOBILE_ALT?: string;
  SENDER_EMAIL?: string;
  SENDER_CITY?: string;
  SENDER_COMPANY?: string;
  SUBJECT?: string;
  QUERY_PRODUCT_NAME?: string;
  QUERY_MESSAGE?: string;
  [k: string]: unknown;
}

const str = (v: unknown) => (typeof v === 'string' ? v.trim() : typeof v === 'number' ? String(v) : '');

/**
 * IndiaMART lead → enquiry. Null when there is nothing to call (no mobile) or it is not an
 * enquiry: catalog views (QUERY_TYPE 'BIZ') mean a buyer only looked at the catalogue, they did not
 * ask to be contacted, so they are never auto-called.
 */
export function mapIndiaMartRecord(rec: IndiaMartRecord): MappedLead | null {
  if (str(rec.QUERY_TYPE).toUpperCase() === 'BIZ') return null;
  const phone = str(rec.SENDER_MOBILE) || str(rec.SENDER_MOBILE_ALT);
  if (!phone) return null;
  const product = str(rec.QUERY_PRODUCT_NAME) || str(rec.SUBJECT);
  const message = str(rec.QUERY_MESSAGE).replace(/\s+/g, ' ');
  const attributes: Record<string, string> = {};
  if (str(rec.SENDER_EMAIL)) attributes.email = str(rec.SENDER_EMAIL);
  if (str(rec.SENDER_CITY)) attributes.city = str(rec.SENDER_CITY);
  if (str(rec.SENDER_COMPANY)) attributes.company = str(rec.SENDER_COMPANY);
  return {
    externalId: str(rec.UNIQUE_QUERY_ID) || null,
    input: {
      name: clip(str(rec.SENDER_NAME) || 'IndiaMART Buyer', NAME_MAX),
      phone,
      interest: interestFrom([['', product], ['', message]].filter(([, v]) => v) as Array<[string, string]>),
      attributes,
    },
  };
}

/** Leads in an IndiaMART body: pull responses carry an array, push webhooks one object. */
export function indiaMartRecords(body: any): IndiaMartRecord[] {
  const inner = body?.RESPONSE ?? body?.body?.RESPONSE;
  if (Array.isArray(inner)) return inner.filter((r) => r && typeof r === 'object');
  if (inner && typeof inner === 'object') return [inner];
  return [];
}

export interface PullOutcome {
  sourceId: string;
  status: 'ok' | 'no_leads' | 'rate_limited' | 'blocked' | 'invalid_key' | 'bad_request' | 'upstream_error' | 'config_unreadable' | 'skipped';
  captured?: number;
}

/**
 * One pull for one source. The caller has already claimed the 5-minute slot (last_pulled_at).
 * Window: from 5 minutes before the previous end (or the source's creation) to now, at most 7 days.
 */
export async function pullIndiaMartSource(env: Env, source: LeadSourceRow, now: Date = new Date()): Promise<PullOutcome> {
  const outcome = (status: PullOutcome['status'], captured?: number): PullOutcome => ({ sourceId: source.id, status, ...(captured != null ? { captured } : {}) });
  const cfg = await readConfig(env, source);
  if (!cfg?.crm_key) {
    await setSourceError(env, source, 'config_unreadable');
    return outcome('config_unreadable');
  }

  const end = now;
  const previousEnd = source.last_cursor ? new Date(source.last_cursor) : new Date(`${source.created_at.replace(' ', 'T')}Z`);
  let start = new Date(previousEnd.getTime() - INDIAMART_OVERLAP_SECONDS * 1000);
  const earliest = new Date(end.getTime() - INDIAMART_MAX_WINDOW_SECONDS * 1000 + 60_000);
  if (Number.isNaN(start.getTime()) || start < earliest) start = earliest;

  const url = `${INDIAMART_PULL_URL}?glusr_crm_key=${encodeURIComponent(cfg.crm_key)}`
    + `&start_time=${encodeURIComponent(indiaMartTime(start))}&end_time=${encodeURIComponent(indiaMartTime(end))}`;

  let body: any;
  try {
    const res = await fetch(url, { headers: { Accept: 'application/json' }, signal: AbortSignal.timeout(20_000) });
    body = await res.json().catch(() => null);
    if (!body || typeof body !== 'object') {
      await setSourceError(env, source, 'upstream_error');
      return outcome('upstream_error');
    }
  } catch {
    await setSourceError(env, source, 'upstream_error');
    return outcome('upstream_error');
  }

  const code = Number(body.CODE);
  const message = String(body.MESSAGE ?? '');
  const advance = (extraSql = '', ...binds: unknown[]) => env.DB.prepare(
    `UPDATE lead_sources SET last_cursor = ?, next_pull_at = NULL${extraSql} WHERE id = ?`
  ).bind(end.toISOString(), ...binds, source.id).run();

  if (code === 200 || code === 204) {
    let captured = 0;
    for (const rec of code === 200 ? indiaMartRecords(body) : []) {
      const mapped = mapIndiaMartRecord(rec);
      if (!mapped) continue;
      const r = await captureExternalLead(env, source, mapped.externalId, mapped.input);
      if (r.status === 'created' || r.status === 'updated') captured++;
    }
    await advance();
    if (source.last_error) await setSourceError(env, source, null);
    return outcome(code === 200 ? 'ok' : 'no_leads', captured);
  }
  if (code === 429) {
    // "Too Many Requests" = the key is blocked for 15 minutes. Otherwise it is the 5-minute rule:
    // last_pulled_at (already set by the claim) keeps us away for the next 5 minutes.
    if (/too many/i.test(message)) {
      await env.DB.prepare('UPDATE lead_sources SET next_pull_at = ? WHERE id = ?')
        .bind(sqliteNow(new Date(now.getTime() + INDIAMART_BLOCK_SECONDS * 1000)), source.id).run();
      await setSourceError(env, source, 'rate_limited');
      return outcome('blocked');
    }
    await env.DB.prepare('UPDATE lead_sources SET next_pull_at = NULL WHERE id = ?').bind(source.id).run();
    await setSourceError(env, source, 'rate_limited');
    return outcome('rate_limited');
  }
  if (code === 401) {
    await env.DB.prepare('UPDATE lead_sources SET next_pull_at = ? WHERE id = ?')
      .bind(sqliteNow(new Date(now.getTime() + INDIAMART_INVALID_KEY_RETRY_SECONDS * 1000)), source.id).run();
    await setSourceError(env, source, 'invalid_key');
    return outcome('invalid_key');
  }
  if (code === 400) {
    // Window rejected (e.g. older than 365 days or > 7 days): restart from now rather than loop.
    await advance();
    await setSourceError(env, source, 'bad_request');
    return outcome('bad_request');
  }
  await setSourceError(env, source, 'upstream_error');
  return outcome('upstream_error');
}

/**
 * Cron: pulls every IndiaMART source that is due. A source is claimed atomically (last_pulled_at)
 * so overlapping cron runs never hit IndiaMART twice within 5 minutes for the same key.
 */
export async function runIndiaMartPulls(env: Env, opts: { now?: Date; limit?: number } = {}): Promise<PullOutcome[]> {
  const now = opts.now ?? new Date();
  const nowSql = sqliteNow(now);
  const dueBefore = sqliteNow(new Date(now.getTime() - INDIAMART_MIN_INTERVAL_SECONDS * 1000));
  const dueSql = `kind = 'indiamart' AND revoked_at IS NULL
    AND (last_pulled_at IS NULL OR last_pulled_at <= ?)
    AND (next_pull_at IS NULL OR next_pull_at <= ?)`;
  const results: PullOutcome[] = [];
  try {
    const { results: due } = await env.DB.prepare(
      `SELECT * FROM lead_sources WHERE ${dueSql} ORDER BY COALESCE(last_pulled_at, '') ASC LIMIT ?`
    ).bind(dueBefore, nowSql, opts.limit ?? INDIAMART_PULLS_PER_RUN).all<LeadSourceRow>();
    for (const source of due ?? []) {
      const claim = await env.DB.prepare(`UPDATE lead_sources SET last_pulled_at = ? WHERE id = ? AND ${dueSql}`)
        .bind(nowSql, source.id, dueBefore, nowSql).run();
      if ((claim.meta?.changes ?? 0) !== 1) {
        results.push({ sourceId: source.id, status: 'skipped' });
        continue;
      }
      try {
        results.push(await pullIndiaMartSource(env, source, now));
      } catch (err: any) {
        console.error(JSON.stringify({ msg: 'indiamart_pull_failed', source: source.id, error: err?.message }));
        results.push({ sourceId: source.id, status: 'upstream_error' });
      }
    }
  } catch (err: any) {
    console.error(JSON.stringify({ msg: 'indiamart_pulls_failed', error: err?.message }));
  }
  if (results.length) console.log(JSON.stringify({ msg: 'indiamart_pulls', count: results.length }));
  return results;
}

// ------------------------------------------------------------------ Meta Lead Ads

export const DEFAULT_META_GRAPH_VERSION = 'v21.0';

export function metaGraphVersion(env: Pick<Env, 'META_GRAPH_API_VERSION'>): string {
  const v = env.META_GRAPH_API_VERSION?.trim();
  return v && /^v\d+\.\d+$/.test(v) ? v : DEFAULT_META_GRAPH_VERSION;
}

/** X-Hub-Signature-256 = `sha256=` + hex HMAC-SHA256(app secret, raw body). Constant-time compare. */
export async function verifyMetaSignature(appSecret: string, rawBody: string, header: string | null | undefined): Promise<boolean> {
  if (!header || !appSecret) return false;
  const m = /^sha256=([0-9a-fA-F]{64})$/.exec(header.trim());
  if (!m) return false;
  return timingSafeEqual(await hmacHex(appSecret, rawBody), m[1].toLowerCase());
}

/** leadgen ids in a Page webhook body: entry[].changes[] with field 'leadgen'. */
export function metaLeadgenIds(payload: any): string[] {
  const ids: string[] = [];
  for (const entry of Array.isArray(payload?.entry) ? payload.entry : []) {
    for (const change of Array.isArray(entry?.changes) ? entry.changes : []) {
      const id = change?.field === 'leadgen' ? str(change?.value?.leadgen_id) : '';
      if (id) ids.push(id);
    }
  }
  return ids;
}

/** Graph API lead `field_data` → enquiry. Null when there is no phone number. */
export function mapMetaLead(leadgenId: string, fieldData: unknown): MappedLead | null {
  const fields = new Map<string, string>();
  const extra: Array<[string, string]> = [];
  for (const f of Array.isArray(fieldData) ? fieldData : []) {
    const key = str(f?.name).toLowerCase();
    const value = (Array.isArray(f?.values) ? f.values : []).map(str).filter(Boolean).join(', ');
    if (!key || !value) continue;
    if (['full_name', 'first_name', 'last_name', 'phone_number', 'email', 'city', 'company_name'].includes(key)) fields.set(key, value);
    else if (!['zip_code', 'post_code', 'street_address', 'state', 'province', 'country'].includes(key)) extra.push([humanize(key), value]);
  }
  const phone = fields.get('phone_number');
  if (!phone) return null;
  const name = fields.get('full_name') || [fields.get('first_name'), fields.get('last_name')].filter(Boolean).join(' ') || 'Facebook lead';
  const attributes: Record<string, string> = {};
  if (fields.get('email')) attributes.email = fields.get('email')!;
  if (fields.get('city')) attributes.city = fields.get('city')!;
  if (fields.get('company_name')) attributes.company = fields.get('company_name')!;
  return { externalId: leadgenId, input: { name: clip(name, NAME_MAX), phone, interest: interestFrom(extra), attributes } };
}

export type MetaFetchResult =
  | { ok: true; fieldData: unknown }
  | { ok: false; transient: boolean; error: string };

/** GET /{leadgen_id} with the page token (+ appsecret_proof, which Meta accepts and may require). */
export async function fetchMetaLead(env: Env, leadgenId: string, cfg: IntegrationConfig): Promise<MetaFetchResult> {
  const token = cfg.page_access_token ?? '';
  const proof = cfg.app_secret ? await hmacHex(cfg.app_secret, token) : null;
  const url = `https://graph.facebook.com/${metaGraphVersion(env)}/${encodeURIComponent(leadgenId)}`
    + `?fields=id,created_time,field_data&access_token=${encodeURIComponent(token)}`
    + (proof ? `&appsecret_proof=${proof}` : '');
  try {
    const res = await fetch(url, { headers: { Accept: 'application/json' }, signal: AbortSignal.timeout(15_000) });
    const body: any = await res.json().catch(() => null);
    if (res.ok && body && Array.isArray(body.field_data)) return { ok: true, fieldData: body.field_data };
    const transient = res.status >= 500 || res.status === 429 || body?.error?.is_transient === true;
    return { ok: false, transient, error: body?.error?.type ?? `http_${res.status}` };
  } catch (err: any) {
    return { ok: false, transient: true, error: err?.name === 'TimeoutError' ? 'timeout' : 'network' };
  }
}
