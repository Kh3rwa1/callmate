/**
 * Campaign Queue Service: reliable, idempotent outbound call dispatch.
 *
 * State machine for campaign_leads.status:
 *   pending -> queued -> calling -> completed
 *                 |         |
 *                 |         +-> retry_pending -> (re-queued) -> calling ...
 *                 |         +-> failed (attempts exhausted or permanent error)
 *                 +-> rescheduled (outside hours) / skipped_dnc / max_attempts_exceeded
 *
 * The ONLY transition into 'calling' is the atomic claim in processCampaignJob.
 */
import { Env } from '../types';
import { checkCallCompliance } from './compliance';
import { maskPhone } from '../utils/crypto_data';
import { isMockSarvam } from '../utils/secrets';

export interface CampaignJobMessage {
  campaign_id: string;
  lead_id: string;
  business_id: string;
  idempotency_key: string;
  attempts: number; // kept for backward compat; DB `attempts` is the source of truth
  /** Public origin of this worker, captured from the request that started the campaign (for Sarvam webhooks). */
  webhook_base_url?: string;
}

export interface ProcessResult {
  success: boolean;
  retry?: boolean;
  /**
   * Deferral that is not a failure (e.g. concurrency cap): the consumer acks and sends a FRESH
   * delayed message instead of message.retry(), so waiting never burns the queue's max_retries.
   */
  requeue?: boolean;
  delaySeconds?: number;
  reason?: string;
}

export const MAX_DIAL_ATTEMPTS = 3;
export const MAX_CONCURRENT_CALLS_PER_BUSINESS = 5;
/** Cloudflare Queues caps retry/send delay (12h at time of writing; verify in CF docs). */
export const MAX_QUEUE_DELAY_SECONDS = 12 * 60 * 60;
export const CLAIMABLE_STATUSES = ['pending', 'queued', 'rescheduled', 'retry_pending'] as const;
/** campaign_leads statuses that still have work outstanding; a campaign is done when none remain. */
export const UNFINISHED_LEAD_STATUSES = ['pending', 'queued', 'calling', 'retry_pending', 'rescheduled'] as const;

/**
 * Sarvam does not sign webhooks, so each dial carries a per-call token in its webhook URL:
 * HMAC-SHA256(SARVAM_WEBHOOK_SECRET, call_id). A leaked token only authorises that one call's result.
 */
export async function sarvamWebhookToken(secret: string, callId: string): Promise<string> {
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const sig = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(callId));
  return Array.from(new Uint8Array(sig)).map((b) => b.toString(16).padStart(2, '0')).join('');
}

/**
 * Same webhook config for manual and campaign dials. `baseUrl` is the worker's public origin;
 * PUBLIC_API_BASE_URL (if set) wins for queue/cron contexts that have no request.
 */
export async function sarvamWebhookConfig(
  baseUrl: string | null | undefined, secret: string | undefined, callId: string
): Promise<{ url: string; metadata: { call_id: string } } | undefined> {
  const base = (baseUrl || '').trim().replace(/\/+$/, '');
  if (!base || !secret) return undefined;
  const token = await sarvamWebhookToken(secret, callId);
  return { url: `${base}/webhooks/sarvam?call_id=${encodeURIComponent(callId)}&token=${token}`, metadata: { call_id: callId } };
}

/** Caller IDs from SARVAM_AGENT_PHONE_NUMBERS (comma separated), spread across dials. */
export function pickAgentPhoneNumber(env: Pick<Env, 'SARVAM_AGENT_PHONE_NUMBERS'>): string | null {
  const numbers = (env.SARVAM_AGENT_PHONE_NUMBERS || '').split(',').map((n) => n.trim()).filter(Boolean);
  if (numbers.length === 0) return null;
  return numbers[Math.floor(Math.random() * numbers.length)];
}

/** Sarvam wants E.164; leads are stored as bare digits with country code (e.g. 919876543210). */
export function toE164(phone: string): string {
  const digits = phone.replace(/\D/g, '');
  return `+${digits}`;
}

/**
 * Marks a running/paused campaign completed once no lead has outstanding work.
 * Single statement, so concurrent finishers cannot double-complete. Returns true if it transitioned.
 */
export async function maybeCompleteCampaign(db: D1Database, campaignId: string): Promise<boolean> {
  const placeholders = UNFINISHED_LEAD_STATUSES.map(() => '?').join(',');
  const res = await db.prepare(
    `UPDATE campaigns SET status = 'completed', completed_at = datetime('now')
     WHERE id = ? AND status IN ('running', 'paused')
       AND NOT EXISTS (SELECT 1 FROM campaign_leads WHERE campaign_id = ? AND status IN (${placeholders}))`
  ).bind(campaignId, campaignId, ...UNFINISHED_LEAD_STATUSES).run();
  return (res.meta?.changes ?? 0) > 0;
}

export function clampDelay(seconds: number): number {
  return Math.max(1, Math.min(MAX_QUEUE_DELAY_SECONDS, Math.floor(seconds)));
}

/** Exponential backoff: 60s, 120s, 240s ... capped at 15 min. */
export function retryDelaySeconds(attemptsSoFar: number): number {
  return Math.min(900, 60 * 2 ** Math.max(0, attemptsSoFar - 1));
}

export type DialResult =
  | { ok: true; interactionId: string | null }
  | { ok: false; retryable: boolean; error: string };

export interface DialRequest {
  callId: string;
  phone: string;
  agentVariables: Record<string, unknown>;
  webhookBaseUrl?: string | null;
}

/**
 * What Sarvam said was wrong, for failure_reason and logs. Its 422 is documented as
 * `detail: [{loc, msg}]` but other shapes occur, so fall back to message/error/raw text.
 * Never keep `input`, and mask digit runs so a phone number can't leak into logs.
 */
export function sarvamErrorDetail(data: any, rawText = ''): string | null {
  const detail = data?.detail;
  let out: string | null = null;
  if (Array.isArray(detail) && detail.length > 0) {
    out = detail.map((d: any) => `${Array.isArray(d?.loc) ? d.loc.join('.') : '?'}: ${d?.msg ?? '?'}`).join('; ');
  } else if (typeof detail === 'string') {
    out = detail;
  } else {
    const msg = data?.message ?? data?.error?.message ?? data?.error;
    out = rawText.trim() || (typeof msg === 'string' ? msg : null);
  }
  return out ? out.replace(/\d{7,}/g, '<digits>').slice(0, 500) : null;
}

/** Instant outbound call: POST /api/outbounds/v1/orgs/{org}/workspaces/{ws}/outbounds. */
export async function dialSarvam(env: Env, req: DialRequest): Promise<DialResult> {
  const orgId = env.SARVAM_ORG_ID;
  const workspaceId = env.SARVAM_WORKSPACE_ID;
  const appVersion = Number(env.SARVAM_APP_VERSION);
  const agentPhone = pickAgentPhoneNumber(env);
  if (!env.SARVAM_API_KEY || !orgId || !workspaceId || !env.SARVAM_ADMISSIONS_APP_ID
      || !Number.isInteger(appVersion) || !env.SARVAM_CONNECTION_ID || !agentPhone) {
    return { ok: false, retryable: false, error: 'sarvam_not_configured' };
  }
  const body = {
    app_config: {
      app_id: env.SARVAM_ADMISSIONS_APP_ID,
      app_version: appVersion,
      connection_config: { connection_id: env.SARVAM_CONNECTION_ID, agent_phone_number: agentPhone },
      agent_variables: req.agentVariables,
    },
    user_config: { user_phone_number: toE164(req.phone) },
    webhook_config: await sarvamWebhookConfig(req.webhookBaseUrl, env.SARVAM_WEBHOOK_SECRET, req.callId),
  };
  try {
    const res = await fetch(
      `https://apps.sarvam.ai/api/outbounds/v1/orgs/${orgId}/workspaces/${workspaceId}/outbounds`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-API-Key': env.SARVAM_API_KEY! },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(15_000),
      }
    );
    const rawText = await res.text().catch(() => '');
    let data: any = null;
    try { data = JSON.parse(rawText); } catch { /* non-JSON body */ }
    if (!res.ok) {
      // 429 / 5xx are transient; other 4xx are our fault (bad number, bad config): don't hammer.
      const retryable = res.status === 429 || res.status >= 500;
      const detail = sarvamErrorDetail(data, rawText);
      return { ok: false, retryable, error: `sarvam_http_${res.status}${detail ? `: ${detail}` : ''}` };
    }
    const interactionId = data?.attempt_id ?? data?.interaction_id ?? data?.id ?? null;
    return { ok: true, interactionId };
  } catch (err: any) {
    // Network error / timeout: transient
    return { ok: false, retryable: true, error: `sarvam_network: ${err?.message ?? err}` };
  }
}

export async function processCampaignJob(env: Env, job: CampaignJobMessage): Promise<ProcessResult> {
  const { campaign_id, lead_id, business_id } = job;

  // 1. Campaign must be running
  const campaign = await env.DB.prepare(
    'SELECT status, calling_hours_start, calling_hours_end FROM campaigns WHERE id = ? AND business_id = ?'
  ).bind(campaign_id, business_id).first<{ status: string; calling_hours_start: number; calling_hours_end: number }>();
  if (!campaign || campaign.status !== 'running') return { success: true, reason: 'campaign_not_running' };

  // 2. Cheap pre-check (the real guard is the atomic claim in step 6)
  const campLead = await env.DB.prepare(
    'SELECT status, attempts FROM campaign_leads WHERE campaign_id = ? AND lead_id = ?'
  ).bind(campaign_id, lead_id).first<{ status: string; attempts: number }>();
  if (!campLead) return { success: true, reason: 'lead_not_in_campaign' };
  if (!(CLAIMABLE_STATUSES as readonly string[]).includes(campLead.status)) {
    return { success: true, reason: `not_claimable:${campLead.status}` };
  }

  // 3. Concurrency cap
  const active = await env.DB.prepare(
    `SELECT COUNT(*) AS cnt FROM calls
     WHERE business_id = ? AND status = 'calling' AND started_at > datetime('now', '-20 minutes')`
  ).bind(business_id).first<{ cnt: number }>();
  if ((active?.cnt ?? 0) >= MAX_CONCURRENT_CALLS_PER_BUSINESS) {
    return { success: false, retry: true, requeue: true, delaySeconds: 15 + Math.floor(Math.random() * 15), reason: 'concurrency_limit' };
  }

  // 4. Lead + compliance
  const lead = await env.DB.prepare('SELECT * FROM leads WHERE id = ? AND business_id = ?')
    .bind(lead_id, business_id).first<any>();
  if (!lead) return { success: true, reason: 'lead_not_found' };

  const compliance = await checkCallCompliance(env.DB, {
    businessId: business_id,
    leadId: lead_id,
    campaignId: campaign_id,
    hoursStart: campaign.calling_hours_start,
    hoursEnd: campaign.calling_hours_end,
    timezone: lead.timezone || 'Asia/Kolkata',
  });

  if (!compliance.allowed) {
    const statusFor: Record<string, string> = {
      outside_hours: 'rescheduled',
      do_not_call: 'skipped_dnc',
      max_daily_attempts: 'rescheduled',
      max_campaign_attempts: 'max_attempts_exceeded',
    };
    const newStatus = statusFor[compliance.reason!] ?? 'failed';
    await env.DB.prepare('UPDATE campaign_leads SET status = ? WHERE campaign_id = ? AND lead_id = ?')
      .bind(newStatus, campaign_id, lead_id).run();
    if (compliance.reschedule) {
      return { success: false, retry: true, delaySeconds: clampDelay(compliance.rescheduleDelaySeconds ?? 3600), reason: compliance.reason };
    }
    await maybeCompleteCampaign(env.DB, campaign_id);
    return { success: true, reason: compliance.reason };
  }

  // 5. Billing guard
  const usage = await env.DB.prepare('SELECT included_minutes, minutes_used FROM usage WHERE business_id = ?')
    .bind(business_id).first<{ included_minutes: number; minutes_used: number }>();
  if (usage && usage.included_minutes - usage.minutes_used <= 0) {
    await env.DB.prepare(`UPDATE campaigns SET status = 'paused' WHERE id = ? AND business_id = ?`)
      .bind(campaign_id, business_id).run();
    return { success: true, reason: 'exhausted_minutes' };
  }

  // 6. ATOMIC CLAIM: only one worker can move this lead into 'calling'
  const callId = `call_${crypto.randomUUID().slice(0, 12)}`;
  const claim = await env.DB.prepare(
    `UPDATE campaign_leads
       SET status = 'calling', attempts = attempts + 1, last_attempt_at = datetime('now'), call_id = ?
     WHERE campaign_id = ? AND lead_id = ?
       AND status IN ('pending','queued','rescheduled','retry_pending')
       AND attempts < ?`
  ).bind(callId, campaign_id, lead_id, MAX_DIAL_ATTEMPTS).run();
  if ((claim.meta?.changes ?? 0) === 0) return { success: true, reason: 'claimed_elsewhere_or_exhausted' };

  const attemptsNow = (campLead.attempts ?? 0) + 1;

  await env.DB.prepare(
    `INSERT INTO calls (id, business_id, lead_id, lead_name, lead_phone, campaign_id, status, started_at, created_at)
     VALUES (?, ?, ?, ?, ?, ?, 'calling', datetime('now'), datetime('now'))`
  ).bind(callId, business_id, lead.id, lead.name, lead.phone, campaign_id).run();

  // Mock mode (dev / CI): leave the call in 'calling'; the mock webhook or maintenance sweeper finishes it.
  if (isMockSarvam(env)) {
    return { success: true, reason: 'mock_dial' };
  }

  const business = await env.DB.prepare('SELECT name FROM businesses WHERE id = ?').bind(business_id).first<any>();
  const agent = await env.DB.prepare('SELECT name, role, voice, languages FROM agents WHERE business_id = ?').bind(business_id).first<any>();

  const dial = await dialSarvam(env, {
    callId,
    phone: lead.phone,
    agentVariables: {
      call_id: callId,
      campaign_id,
      lead_id: lead.id,
      lead_name: lead.name,
      business_name: business?.name ?? 'our business',
      agent_name: agent?.name ?? 'Riya',
      agent_role: agent?.role ?? 'Assistant',
      interest: lead.interest ?? '',
      // No voice variables (gender, speaker, ...): Sarvam rejects the whole dial with a 422
      // unless the agent declares every variable sent. Add them to the agent first.
    },
    webhookBaseUrl: env.PUBLIC_API_BASE_URL || job.webhook_base_url,
  });

  if (dial.ok) {
    await env.DB.batch([
      env.DB.prepare('UPDATE calls SET interaction_id = ? WHERE id = ? AND business_id = ?')
        .bind(dial.interactionId, callId, business_id),
      // Only mark the LEAD as calling once the dial was actually accepted
      env.DB.prepare(`UPDATE leads SET status = 'calling', updated_at = datetime('now') WHERE id = ? AND business_id = ?`)
        .bind(lead_id, business_id),
    ]);
    return { success: true };
  }

  // Dial failed: release the call slot and decide retry vs terminal
  const canRetry = dial.retryable && attemptsNow < MAX_DIAL_ATTEMPTS;
  console.error(JSON.stringify({ msg: 'sarvam_dial_failed', lead: maskPhone(lead.phone), error: dial.error, attemptsNow, canRetry }));

  await env.DB.batch([
    env.DB.prepare(`UPDATE calls SET status = 'failed', failure_reason = ? WHERE id = ? AND business_id = ?`)
      .bind(dial.error, callId, business_id),
    env.DB.prepare(`UPDATE campaign_leads SET status = ?, error = ? WHERE campaign_id = ? AND lead_id = ?`)
      .bind(canRetry ? 'retry_pending' : 'failed', dial.error, campaign_id, lead_id),
  ]);

  if (!canRetry) {
    await maybeCompleteCampaign(env.DB, campaign_id);
    return { success: true, reason: `dial_failed_terminal:${dial.error}` };
  }
  return { success: false, retry: true, delaySeconds: retryDelaySeconds(attemptsNow), reason: dial.error };
}

/** Enqueue only leads that are actually claimable. Never resurrects completed leads. */
export async function enqueueCampaignJobs(
  env: Env, campaignId: string, businessId: string, leadIds: string[], webhookBaseUrl?: string
): Promise<number> {
  // Set-based transition (one statement per chunk; D1 caps bound parameters at 100 per query).
  const toQueue: string[] = [];
  const chunkSize = 80;
  for (let i = 0; i < leadIds.length; i += chunkSize) {
    const slice = leadIds.slice(i, i + chunkSize);
    const placeholders = slice.map(() => '?').join(',');
    const { results } = await env.DB.prepare(
      `UPDATE campaign_leads SET status = 'queued'
       WHERE campaign_id = ? AND lead_id IN (${placeholders}) AND status IN ('pending','rescheduled','retry_pending')
       RETURNING lead_id`
    ).bind(campaignId, ...slice).all<{ lead_id: string }>();
    for (const r of results ?? []) toQueue.push(r.lead_id);
  }

  const messages: CampaignJobMessage[] = toQueue.map((lid) => ({
    campaign_id: campaignId, lead_id: lid, business_id: businessId,
    idempotency_key: `${campaignId}:${lid}`, attempts: 0,
    ...(webhookBaseUrl ? { webhook_base_url: webhookBaseUrl } : {}),
  }));

  if (env.CAMPAIGN_QUEUE) {
    for (let i = 0; i < messages.length; i += 100) {
      await env.CAMPAIGN_QUEUE.sendBatch(messages.slice(i, i + 100).map((body) => ({ body })));
    }
  } else {
    // Local fallback without a queue binding: single pass, no retries (dev only)
    for (const m of messages) await processCampaignJob(env, m);
  }
  return toQueue.length;
}

/** Re-enqueue a single lead with a delay (used by webhook no-answer + maintenance sweeper). */
export async function requeueLead(
  env: Env, campaignId: string, businessId: string, leadId: string, delaySeconds: number, webhookBaseUrl?: string
) {
  if (!env.CAMPAIGN_QUEUE) return;
  await env.CAMPAIGN_QUEUE.send(
    {
      campaign_id: campaignId, lead_id: leadId, business_id: businessId, idempotency_key: `${campaignId}:${leadId}`, attempts: 0,
      ...(webhookBaseUrl ? { webhook_base_url: webhookBaseUrl } : {}),
    },
    { delaySeconds: clampDelay(delaySeconds) }
  );
}

export function isDeadLetterQueue(queueName: string | undefined): boolean {
  return /-dlq(-|$)/.test(queueName ?? '');
}

/**
 * Dead-letter consumer: a job that exhausted its queue retries must not leave its lead stuck in
 * 'queued' forever. Mark it failed (only if still waiting) and let the campaign complete.
 */
export async function handleCampaignDlqBatch(batch: MessageBatch<CampaignJobMessage>, env: Env): Promise<void> {
  for (const message of batch.messages) {
    try {
      const { campaign_id, lead_id } = message.body ?? ({} as CampaignJobMessage);
      if (campaign_id && lead_id) {
        await env.DB.prepare(
          `UPDATE campaign_leads SET status = 'failed', error = 'queue_retries_exhausted'
           WHERE campaign_id = ? AND lead_id = ? AND status IN ('pending','queued','rescheduled','retry_pending')`
        ).bind(campaign_id, lead_id).run();
        await maybeCompleteCampaign(env.DB, campaign_id);
      }
      message.ack();
    } catch (err: any) {
      console.error(JSON.stringify({ msg: 'dlq_job_crashed', key: message.body?.idempotency_key, error: err?.message }));
      message.retry({ delaySeconds: 60 });
    }
  }
}

export async function handleCampaignQueueBatch(batch: MessageBatch<CampaignJobMessage>, env: Env): Promise<void> {
  for (const message of batch.messages) {
    try {
      const result = await processCampaignJob(env, message.body);
      if (result.retry && result.requeue && env.CAMPAIGN_QUEUE) {
        // Fresh message: waiting for a free call slot must not consume max_retries (and eventually DLQ).
        await env.CAMPAIGN_QUEUE.send(message.body, { delaySeconds: clampDelay(result.delaySeconds ?? 30) });
        message.ack();
      } else if (result.retry) message.retry({ delaySeconds: clampDelay(result.delaySeconds ?? 30) });
      else message.ack();
    } catch (err: any) {
      console.error(JSON.stringify({ msg: 'queue_job_crashed', key: message.body?.idempotency_key, error: err?.message }));
      message.retry({ delaySeconds: 60 });
    }
  }
}
