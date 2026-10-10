/**
 * The single-lead dial: every guard a call to one lead must pass, then the Sarvam dial.
 *
 * Shared by the owner's manual call (POST /leads/:id/call in routes/calls.ts) and the speed-to-lead
 * instant call (services/lead_capture.ts), so both always apply the same rules in the same order:
 * calling hours (TRAI-clamped, lead timezone), do-not-call / opt-out, max 3 calls per lead per day,
 * the per-business concurrency cap, plan status and minutes headroom. Campaign dispatch has its own
 * claim-based state machine (services/campaign_queue.ts) but uses the same guard functions.
 */
import { Env } from '../types';
import { maskPhone } from '../utils/crypto_data';
import { isMockSarvam } from '../utils/secrets';
import { checkCallCompliance, allowAnyCallingHours, ComplianceCheckResult } from './compliance';
import { dialSarvam, MAX_CONCURRENT_CALLS_PER_BUSINESS, hasMinutesHeadroom } from './campaign_queue';
import { isPlanBlocked } from './plans';
import { buildCallAgentVariables } from './call_variables';

export type PlaceCallOutcome =
  | { ok: true; callId: string; dispatched: boolean; lead: any }
  | { ok: false; code: 'not_found' }
  | {
      ok: false;
      code: 'blocked';
      reason: NonNullable<ComplianceCheckResult['reason']>;
      reschedule: boolean;
      delaySeconds?: number;
    }
  | { ok: false; code: 'concurrency_limit' }
  | { ok: false; code: 'plan_blocked' }
  | { ok: false; code: 'exhausted_minutes' }
  | { ok: false; code: 'dial_failed'; retryable: boolean; error: string; callId: string };

export interface PlaceCallParams {
  businessId: string;
  leadId: string;
  /** Public origin for the Sarvam webhook when PUBLIC_API_BASE_URL is unset (the request origin). */
  fallbackBaseUrl?: string | null;
  /** Injectable clock for tests (calling-hours check). */
  now?: Date;
}

/**
 * Runs the guards and, if they pass, records the call ('calling') and dials Sarvam. In mock mode
 * (dev/test without a real key) the call is recorded and the lead marked calling without dialing;
 * the mock webhook or the maintenance sweeper completes it.
 */
export async function placeLeadCall(env: Env, p: PlaceCallParams): Promise<PlaceCallOutcome> {
  const { businessId, leadId } = p;

  const lead = await env.DB.prepare('SELECT * FROM leads WHERE id = ? AND business_id = ?').bind(leadId, businessId).first<any>();
  if (!lead) return { ok: false, code: 'not_found' };

  const agent = await env.DB.prepare('SELECT * FROM agents WHERE business_id = ?').bind(businessId).first<any>();

  const compliance = await checkCallCompliance(env.DB, {
    businessId,
    leadId,
    hoursStart: agent?.calling_hours_start,
    hoursEnd: agent?.calling_hours_end,
    timezone: lead.timezone || 'Asia/Kolkata',
    skipTraiClamp: allowAnyCallingHours(env),
    now: p.now,
  });
  if (!compliance.allowed) {
    return {
      ok: false,
      code: 'blocked',
      reason: compliance.reason!,
      reschedule: compliance.reschedule === true,
      delaySeconds: compliance.rescheduleDelaySeconds,
    };
  }

  const active = await env.DB.prepare(
    `SELECT COUNT(*) AS cnt FROM calls
     WHERE business_id = ? AND status = 'calling' AND started_at > datetime('now', '-20 minutes')`
  ).bind(businessId).first<{ cnt: number }>();
  if ((active?.cnt ?? 0) >= MAX_CONCURRENT_CALLS_PER_BUSINESS) return { ok: false, code: 'concurrency_limit' };

  if (await isPlanBlocked(env.DB, businessId)) return { ok: false, code: 'plan_blocked' };
  const usage = await env.DB.prepare('SELECT included_minutes, minutes_used FROM usage WHERE business_id = ?')
    .bind(businessId).first<{ included_minutes: number; minutes_used: number }>();
  if (usage && !hasMinutesHeadroom(usage, active?.cnt ?? 0)) return { ok: false, code: 'exhausted_minutes' };

  const business = await env.DB.prepare('SELECT name FROM businesses WHERE id = ?').bind(businessId).first<any>();
  const callId = `call_${crypto.randomUUID().slice(0, 12)}`;

  await env.DB.prepare(`
    INSERT INTO calls (id, business_id, lead_id, lead_name, lead_phone, status, started_at, created_at)
    VALUES (?, ?, ?, ?, ?, 'calling', datetime('now'), datetime('now'))
  `).bind(callId, businessId, lead.id, lead.name, lead.phone).run();

  const markLeadCalling = env.DB.prepare(
    `UPDATE leads SET status = 'calling', updated_at = datetime('now') WHERE id = ? AND business_id = ?`
  ).bind(leadId, businessId);

  if (isMockSarvam(env)) {
    // Dev/test: the mock webhook or maintenance sweeper completes the call.
    await markLeadCalling.run();
    return { ok: true, callId, dispatched: false, lead };
  }

  const dial = await dialSarvam(env, {
    callId,
    phone: lead.phone,
    // Only SARVAM_AGENT_VARIABLES are sent: Sarvam 422s the dial on any undeclared variable.
    agentVariables: await buildCallAgentVariables(env, {
      businessId, business, agent, lead, callId,
    }),
    webhookBaseUrl: env.PUBLIC_API_BASE_URL || p.fallbackBaseUrl,
  });

  if (dial.ok) {
    await env.DB.batch([
      env.DB.prepare('UPDATE calls SET interaction_id = ? WHERE id = ? AND business_id = ?')
        .bind(dial.interactionId, callId, businessId),
      markLeadCalling,
    ]);
    return { ok: true, callId, dispatched: true, lead };
  }

  console.error(JSON.stringify({ msg: 'sarvam_manual_dial_failed', lead: maskPhone(lead.phone), error: dial.error }));
  await env.DB.prepare(`UPDATE calls SET status = 'failed', failure_reason = ? WHERE id = ? AND business_id = ?`)
    .bind(dial.error, callId, businessId).run();
  return { ok: false, code: 'dial_failed', retryable: dial.retryable, error: dial.error, callId };
}
