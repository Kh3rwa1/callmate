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
}

export interface ProcessResult {
  success: boolean;
  retry?: boolean;
  delaySeconds?: number;
  reason?: string;
}

export const MAX_DIAL_ATTEMPTS = 3;
export const MAX_CONCURRENT_CALLS_PER_BUSINESS = 5;
/** Cloudflare Queues caps retry/send delay (12h at time of writing; verify in CF docs). */
export const MAX_QUEUE_DELAY_SECONDS = 12 * 60 * 60;
export const CLAIMABLE_STATUSES = ['pending', 'queued', 'rescheduled', 'retry_pending'] as const;

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

export async function dialSarvam(env: Env, body: unknown): Promise<DialResult> {
  const orgId = env.SARVAM_ORG_ID;
  const workspaceId = env.SARVAM_WORKSPACE_ID;
  if (!env.SARVAM_API_KEY || !orgId || !workspaceId) {
    return { ok: false, retryable: false, error: 'sarvam_not_configured' };
  }
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
    const data: any = await res.json().catch(() => null);
    if (!res.ok) {
      // 429 / 5xx are transient; other 4xx are our fault (bad number, bad config): don't hammer.
      const retryable = res.status === 429 || res.status >= 500;
      return { ok: false, retryable, error: `sarvam_http_${res.status}` };
    }
    const interactionId = data?.interaction_id ?? data?.id ?? data?.attempt_id ?? null;
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
    return { success: false, retry: true, delaySeconds: 15 + Math.floor(Math.random() * 15), reason: 'concurrency_limit' };
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
  const agent = await env.DB.prepare('SELECT name, role FROM agents WHERE business_id = ?').bind(business_id).first<any>();

  const dial = await dialSarvam(env, {
    app_config: { app_id: env.SARVAM_ADMISSIONS_APP_ID },
    user_config: { phone_number: lead.phone },
    agent_variables: {
      call_id: callId,
      campaign_id,
      lead_id: lead.id,
      lead_name: lead.name,
      business_name: business?.name ?? 'our business',
      agent_name: agent?.name ?? 'Riya',
      agent_role: agent?.role ?? 'Assistant',
      interest: lead.interest ?? '',
    },
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

  return canRetry
    ? { success: false, retry: true, delaySeconds: retryDelaySeconds(attemptsNow), reason: dial.error }
    : { success: true, reason: `dial_failed_terminal:${dial.error}` };
}

/** Enqueue only leads that are actually claimable. Never resurrects completed leads. */
export async function enqueueCampaignJobs(env: Env, campaignId: string, businessId: string, leadIds: string[]): Promise<number> {
  const toQueue: string[] = [];
  for (const lid of leadIds) {
    const r = await env.DB.prepare(
      `UPDATE campaign_leads SET status = 'queued'
       WHERE campaign_id = ? AND lead_id = ? AND status IN ('pending','rescheduled','retry_pending')`
    ).bind(campaignId, lid).run();
    if ((r.meta?.changes ?? 0) > 0) toQueue.push(lid);
  }

  const messages: CampaignJobMessage[] = toQueue.map((lid) => ({
    campaign_id: campaignId, lead_id: lid, business_id: businessId,
    idempotency_key: `${campaignId}:${lid}`, attempts: 0,
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
export async function requeueLead(env: Env, campaignId: string, businessId: string, leadId: string, delaySeconds: number) {
  if (!env.CAMPAIGN_QUEUE) return;
  await env.CAMPAIGN_QUEUE.send(
    { campaign_id: campaignId, lead_id: leadId, business_id: businessId, idempotency_key: `${campaignId}:${leadId}`, attempts: 0 },
    { delaySeconds: clampDelay(delaySeconds) }
  );
}

export async function handleCampaignQueueBatch(batch: MessageBatch<CampaignJobMessage>, env: Env): Promise<void> {
  for (const message of batch.messages) {
    try {
      const result = await processCampaignJob(env, message.body);
      if (result.retry) message.retry({ delaySeconds: clampDelay(result.delaySeconds ?? 30) });
      else message.ack();
    } catch (err: any) {
      console.error(JSON.stringify({ msg: 'queue_job_crashed', key: message.body?.idempotency_key, error: err?.message }));
      message.retry({ delaySeconds: 60 });
    }
  }
}
