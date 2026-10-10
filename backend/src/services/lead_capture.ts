/**
 * Speed-to-lead: capture an enquiry from a business's hosted form or webhook and AI-call it within
 * about a minute.
 *
 * Capture (captureLead) creates the lead with consent 'explicit_opt_in' (the person ticked the
 * consent box / the sender asserted consent), dedupes by phone (one lead per phone per business;
 * a repeat enquiry within 24h is a no-op), then enqueues an `instant_call` message on the campaign
 * queue. The consumer (processInstantCallJob) runs the SAME guards and dial as the owner's manual
 * call (services/dial.ts): calling hours, DNC, daily cap, concurrency, plan and minutes.
 * Outside calling hours the message is re-sent with a delay until the window opens (Queues caps a
 * delay at 12h, so long waits hop more than once and re-check each time).
 */
import { recordConsentEventsForLeads, CONSENT_TEXT_VERSIONS, type ConsentSource } from './consent';
import { Env } from '../types';
import { timingSafeEqual } from '../utils/compare';
import { normalizePhone } from '../utils/phone';
import { placeLeadCall } from './dial';
import { clampDelay, retryDelaySeconds, MAX_DIAL_ATTEMPTS } from './campaign_queue';
import { sendBusinessPushNotification } from './fcm';

export const INSTANT_CALL_KIND = 'instant_call';

export interface InstantCallMessage {
  kind: typeof INSTANT_CALL_KIND;
  business_id: string;
  lead_id: string;
  lead_source_id: string;
  idempotency_key: string;
  /** Dial attempts that failed with a retryable provider error. */
  attempts: number;
  /** UTC 'YYYY-MM-DD HH:MM:SS' when the enquiry arrived: a call placed after this means "already called". */
  enqueued_at: string;
  /** Owner already told what happened to this enquiry (sent once, on the first outcome). */
  notified?: boolean;
  webhook_base_url?: string;
}

export function isInstantCallMessage(body: any): body is InstantCallMessage {
  return body?.kind === INSTANT_CALL_KIND;
}

/** Every kind of lead source. Integrations (services/lead_integrations.ts) reuse this pipeline. */
export const LEAD_SOURCE_KINDS = ['form', 'webhook', 'google_ads', 'indiamart', 'meta'] as const;
export type LeadSourceKind = typeof LEAD_SOURCE_KINDS[number];

export interface LeadSourceRow {
  id: string;
  business_id: string;
  kind: LeadSourceKind;
  public_slug: string;
  secret_hash: string | null;
  auto_call: number;
  created_at: string;
  revoked_at: string | null;
  /** Integrations only (migration 0016). */
  config_encrypted?: string | null;
  last_pulled_at?: string | null;
  last_cursor?: string | null;
  next_pull_at?: string | null;
  last_error?: string | null;
}

/** Public path of a source: the hosted form or the endpoint its provider posts to. */
export function leadSourcePath(kind: LeadSourceKind, slug: string): string {
  switch (kind) {
    case 'form': return `/f/${slug}`;
    case 'webhook': return `/hooks/leads/${slug}`;
    case 'google_ads': return `/hooks/google-ads/${slug}`;
    case 'indiamart': return `/hooks/indiamart/${slug}`;
    case 'meta': return `/hooks/meta/${slug}`;
  }
}

/** Consent-event source recorded for leads from each kind (consent_events.source). */
export function consentSourceFor(kind: LeadSourceKind): ConsentSource {
  return kind === 'meta' ? 'meta_lead_ads' : kind;
}

/**
 * Owner-facing JSON for a source. Never includes the secret hash or the encrypted integration
 * config: secrets are returned once, by POST /lead-sources, and never again.
 */
export function formatLeadSource(row: any, baseUrl: string) {
  const base = baseUrl.replace(/\/+$/, '');
  return {
    id: row.id,
    kind: row.kind,
    slug: row.public_slug,
    url: `${base}${leadSourcePath(row.kind, row.public_slug)}`,
    auto_call: row.auto_call === 1,
    leads_count: row.leads_count ?? 0,
    created_at: row.created_at,
    // Integration health: the last problem the owner should fix, and (IndiaMART) the last good sync.
    last_error: row.last_error ?? null,
    ...(row.kind === 'indiamart' ? { last_synced_at: row.last_cursor ? sqliteNow(new Date(row.last_cursor)) : null } : {}),
  };
}

const BASE62 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

/** Unguessable URL-safe id (rejection sampling, so every character is uniform). */
export function randomToken(length: number): string {
  let out = '';
  while (out.length < length) {
    const bytes = crypto.getRandomValues(new Uint8Array(length * 2));
    for (const b of bytes) {
      if (b < 248 && out.length < length) out += BASE62[b % 62];
    }
  }
  return out;
}

export const SLUG_LENGTH = 12;
export const WEBHOOK_TOKEN_PREFIX = 'cplh_';

export function newWebhookToken(): string {
  return `${WEBHOOK_TOKEN_PREFIX}${randomToken(40)}`;
}

export async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, '0')).join('');
}

/** Constant-time check of a presented bearer token against the stored SHA-256. */
export async function verifyWebhookToken(token: string | null | undefined, secretHash: string | null): Promise<boolean> {
  if (!token || !secretHash) return false;
  return timingSafeEqual(await sha256Hex(token), secretHash);
}

/** Active (not revoked) source for a public slug, or null. */
export async function findActiveSource(db: D1Database, slug: string, kind: LeadSourceKind): Promise<LeadSourceRow | null> {
  if (!/^[A-Za-z0-9]{8,64}$/.test(slug)) return null;
  return db.prepare(
    'SELECT * FROM lead_sources WHERE public_slug = ? AND kind = ? AND revoked_at IS NULL'
  ).bind(slug, kind).first<LeadSourceRow>();
}

/** SQLite datetime('now') format, so it compares with stored timestamps. */
export function sqliteNow(now: Date = new Date()): string {
  return now.toISOString().replace('T', ' ').slice(0, 19);
}

export interface CaptureInput {
  name: string;
  phone: string;
  interest?: string | null;
  /** Extra details shown on the lead (e.g. email, city), stored in leads.attributes on create. */
  attributes?: Record<string, string>;
}

export type CaptureResult =
  | { status: 'created' | 'updated'; leadId: string; autoCall: boolean }
  | { status: 'duplicate'; leadId: string; autoCall: boolean }
  | { status: 'invalid_phone' };

function isUniqueViolation(err: any): boolean {
  return /UNIQUE constraint failed/i.test(String(err?.message ?? err));
}

/**
 * Creates (or refreshes) the lead for an enquiry and starts the instant call when the source has
 * auto-call on. Same phone within 24h of the lead's last enquiry (or creation) = duplicate: nothing
 * changes and nobody is called again.
 */
export async function captureLead(
  env: Env,
  source: LeadSourceRow,
  input: CaptureInput,
  opts: { fallbackBaseUrl?: string; waitUntil?: (p: Promise<unknown>) => void; ipHash?: string | null } = {},
): Promise<CaptureResult> {
  const phone = normalizePhone(input.phone);
  if (!phone) return { status: 'invalid_phone' };
  const name = input.name.trim().slice(0, 100) || 'Customer';
  const interest = input.interest?.trim().slice(0, 500) || null;
  const businessId = source.business_id;
  const autoCall = source.auto_call === 1;

  const existing = await env.DB.prepare(
    `SELECT id, (COALESCE(last_enquiry_at, created_at) > datetime('now', '-1 day')) AS recent
     FROM leads WHERE business_id = ? AND phone = ?`
  ).bind(businessId, phone).first<{ id: string; recent: number }>();

  let status: 'created' | 'updated';
  let leadId: string;
  if (existing) {
    if (existing.recent === 1) return { status: 'duplicate', leadId: existing.id, autoCall };
    // A fresh enquiry from a known number: record the new opt-in, but never override an opt-out or
    // the owner's do-not-call (the call guards skip those leads).
    await env.DB.prepare(
      `UPDATE leads SET
         interest = COALESCE(?, interest),
         consent = CASE WHEN do_not_call = 1 OR consent = 'opt_out' THEN consent ELSE 'explicit_opt_in' END,
         lead_source_id = ?, last_enquiry_at = datetime('now'), updated_at = datetime('now')
       WHERE id = ? AND business_id = ?`
    ).bind(interest, source.id, existing.id, businessId).run();
    status = 'updated';
    leadId = existing.id;
  } else {
    leadId = `lead_${crypto.randomUUID().slice(0, 12)}`;
    try {
      await env.DB.prepare(
        `INSERT INTO leads (id, business_id, name, phone, interest, source, status, attributes, do_not_call, consent, timezone,
                            lead_source_id, last_enquiry_at, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, 'new', ?, 0, 'explicit_opt_in', 'Asia/Kolkata', ?, datetime('now'), datetime('now'), datetime('now'))`
      ).bind(leadId, businessId, name, phone, interest, source.kind, JSON.stringify(input.attributes ?? {}), source.id).run();
    } catch (err) {
      // Lost a race with a concurrent enquiry from the same phone: that one wins.
      if (!isUniqueViolation(err)) throw err;
      const winner = await env.DB.prepare('SELECT id FROM leads WHERE business_id = ? AND phone = ?')
        .bind(businessId, phone).first<{ id: string }>();
      return { status: 'duplicate', leadId: winner?.id ?? leadId, autoCall };
    }
    status = 'created';
  }

  // Evidence of the opt-in this enquiry carried (shown in the lead's consent history).
  // Records the lead's stored value: a repeat enquiry never overrides an earlier opt-out.
  await recordConsentEventsForLeads(env.DB, businessId, [leadId], {
    source: consentSourceFor(source.kind), textVersion: CONSENT_TEXT_VERSIONS[consentSourceFor(source.kind) as keyof typeof CONSENT_TEXT_VERSIONS],
    ipHash: opts.ipHash ?? null,
  });

  if (autoCall) {
    await enqueueInstantCall(env, {
      kind: INSTANT_CALL_KIND,
      business_id: businessId,
      lead_id: leadId,
      lead_source_id: source.id,
      idempotency_key: `instant:${leadId}:${Date.now()}`,
      attempts: 0,
      enqueued_at: sqliteNow(),
      ...(opts.fallbackBaseUrl ? { webhook_base_url: opts.fallbackBaseUrl } : {}),
    }, opts.waitUntil);
  } else {
    await notifyOwner(env, businessId, leadId, name, 'manual', opts.waitUntil);
  }
  return { status, leadId, autoCall };
}

/** Sends the message now (no delay). Without a queue binding (bare local dev) it runs in-process. */
export async function enqueueInstantCall(
  env: Env, message: InstantCallMessage, waitUntil?: (p: Promise<unknown>) => void,
): Promise<void> {
  if (env.CAMPAIGN_QUEUE) {
    await env.CAMPAIGN_QUEUE.send(message);
    return;
  }
  const run = processInstantCallJob(env, message).catch((err) =>
    console.error(JSON.stringify({ msg: 'instant_call_inline_failed', error: err?.message })));
  if (waitUntil) waitUntil(run);
  else await run;
}

/** What the owner is told about an enquiry. */
export type EnquiryNotice = 'calling' | 'scheduled' | 'manual' | 'not_called_dnc' | 'not_called_minutes' | 'not_called_failed';

function firstName(name: string): string {
  return name.trim().split(/\s+/)[0] || name;
}

export function enquiryNoticeText(kind: EnquiryNotice, leadName: string): { title: string; body: string } {
  const title = `New enquiry from ${firstName(leadName)}`;
  const body = {
    calling: 'Your AI employee is calling them now.',
    scheduled: 'Your AI employee will call them when calling hours start.',
    manual: 'Auto-call is off. Open the lead to call them.',
    not_called_dnc: 'Not called: this number is on your do-not-call list.',
    not_called_minutes: 'Not called: add calling minutes to auto-call new enquiries.',
    not_called_failed: 'The AI call could not be placed. Open the lead to try again.',
  }[kind];
  return { title, body };
}

/** In-app notification row + push ("New enquiry from X — calling now"). Best effort. */
export async function notifyOwner(
  env: Env, businessId: string, leadId: string, leadName: string, kind: EnquiryNotice,
  waitUntil?: (p: Promise<unknown>) => void,
): Promise<void> {
  const { title, body } = enquiryNoticeText(kind, leadName);
  const route = `/leads/${leadId}`;
  try {
    await env.DB.prepare(
      `INSERT INTO notifications (id, business_id, type, title, body, route, action_label, is_read, created_at)
       VALUES (?, ?, 'new_lead', ?, ?, ?, 'View', 0, datetime('now'))`
    ).bind(`notif_${crypto.randomUUID().slice(0, 12)}`, businessId, title, body, route).run();
  } catch (err: any) {
    console.error(JSON.stringify({ msg: 'enquiry_notification_failed', error: err?.message }));
  }
  const push = sendBusinessPushNotification(env, businessId, { type: 'new_lead', title, body, route })
    .catch((err) => console.error(JSON.stringify({ msg: 'enquiry_push_failed', error: err?.message })));
  if (waitUntil) waitUntil(push);
  else await push;
}

export interface InstantCallResult {
  /** 'ack' = done; 'requeue' = send `message` again after `delaySeconds`. */
  action: 'ack' | 'requeue';
  reason: string;
  delaySeconds?: number;
  message?: InstantCallMessage;
}

/**
 * One instant-call attempt. Never throws for business outcomes; the caller acks or re-sends.
 */
export async function processInstantCallJob(
  env: Env, job: InstantCallMessage, opts: { now?: Date } = {},
): Promise<InstantCallResult> {
  const { business_id: businessId, lead_id: leadId } = job;

  // The owner can switch auto-call off or revoke the source while the call waits for hours.
  const source = await env.DB.prepare(
    'SELECT auto_call, revoked_at FROM lead_sources WHERE id = ? AND business_id = ?'
  ).bind(job.lead_source_id, businessId).first<{ auto_call: number; revoked_at: string | null }>();
  if (!source || source.revoked_at || source.auto_call !== 1) return { action: 'ack', reason: 'auto_call_off' };

  // Redelivery / the owner already called this lead since the enquiry arrived: don't call twice.
  // A dial the provider rejected never rang the lead, so it doesn't count (as in compliance.ts).
  const already = await env.DB.prepare(
    `SELECT 1 AS hit FROM calls
     WHERE lead_id = ? AND business_id = ? AND started_at >= ?
       AND NOT (status = 'failed' AND interaction_id IS NULL)
     LIMIT 1`
  ).bind(leadId, businessId, job.enqueued_at).first<{ hit: number }>();
  if (already) return { action: 'ack', reason: 'already_called' };

  const placed = await placeLeadCall(env, {
    businessId, leadId, fallbackBaseUrl: job.webhook_base_url, now: opts.now,
  });

  const leadName = async (): Promise<string> => {
    if (placed.ok) return placed.lead.name;
    const row = await env.DB.prepare('SELECT name FROM leads WHERE id = ? AND business_id = ?')
      .bind(leadId, businessId).first<{ name: string }>();
    return row?.name ?? 'a customer';
  };
  const notifyOnce = async (kind: EnquiryNotice): Promise<boolean> => {
    if (job.notified) return true;
    await notifyOwner(env, businessId, leadId, await leadName(), kind);
    return true;
  };

  if (placed.ok) {
    await notifyOnce('calling');
    return { action: 'ack', reason: placed.dispatched ? 'called' : 'mock_dial' };
  }

  switch (placed.code) {
    case 'not_found':
      return { action: 'ack', reason: 'lead_not_found' };
    case 'blocked':
      if (placed.reason === 'outside_hours') {
        const notified = await notifyOnce('scheduled');
        return {
          action: 'requeue',
          reason: 'outside_hours',
          delaySeconds: clampDelay(placed.delaySeconds ?? 3600),
          message: { ...job, notified },
        };
      }
      if (placed.reason === 'do_not_call') await notifyOnce('not_called_dnc');
      // max_daily_attempts: the lead was just called repeatedly; one more enquiry doesn't add a 4th call.
      return { action: 'ack', reason: placed.reason };
    case 'concurrency_limit':
      return {
        action: 'requeue',
        reason: 'concurrency_limit',
        delaySeconds: 15 + Math.floor(Math.random() * 15),
        message: job,
      };
    case 'plan_blocked':
    case 'exhausted_minutes':
      await notifyOnce('not_called_minutes');
      return { action: 'ack', reason: placed.code };
    case 'dial_failed': {
      const attempts = (job.attempts ?? 0) + 1;
      if (placed.retryable && attempts < MAX_DIAL_ATTEMPTS) {
        return {
          action: 'requeue',
          reason: `dial_failed_retry:${placed.error}`,
          delaySeconds: retryDelaySeconds(attempts),
          message: { ...job, attempts },
        };
      }
      await notifyOnce('not_called_failed');
      return { action: 'ack', reason: `dial_failed_terminal:${placed.error}` };
    }
  }
}

/** Queue consumer for instant_call messages (they share the campaign dispatch queue). */
export async function handleInstantCallMessages(messages: readonly Message<any>[], env: Env): Promise<void> {
  for (const message of messages) {
    try {
      const result = await processInstantCallJob(env, message.body as InstantCallMessage);
      if (result.action === 'requeue' && result.message && env.CAMPAIGN_QUEUE) {
        // Fresh message: waiting for calling hours or a free slot must not consume max_retries.
        await env.CAMPAIGN_QUEUE.send(result.message, { delaySeconds: clampDelay(result.delaySeconds ?? 30) });
      } else if (result.action === 'requeue') {
        message.retry({ delaySeconds: clampDelay(result.delaySeconds ?? 30) });
        continue;
      }
      message.ack();
    } catch (err: any) {
      console.error(JSON.stringify({ msg: 'instant_call_job_crashed', key: message.body?.idempotency_key, error: err?.message }));
      message.retry({ delaySeconds: 60 });
    }
  }
}
