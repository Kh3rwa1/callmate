import { Env } from '../types';
import { MinuteBalances, minutesRemaining } from './plans';

/** Maximum simultaneous calls for one business. */
export const MAX_CONCURRENT_CALLS_PER_BUSINESS = 5;
/** Default Sarvam organisation limit for the configured pay-as-you-go plan. */
export const DEFAULT_SARVAM_MAX_CONCURRENT_CALLS = 4;
/** Minutes held back for every call that is (or is about to be) in progress. */
export const RESERVED_MINUTES_PER_CALL = 5;

export function sarvamMaxConcurrentCalls(env: Pick<Env, 'SARVAM_MAX_CONCURRENT_CALLS'>): number {
  const n = Number.parseInt(String(env.SARVAM_MAX_CONCURRENT_CALLS ?? ''), 10);
  return Number.isFinite(n) && n > 0 ? n : DEFAULT_SARVAM_MAX_CONCURRENT_CALLS;
}

/** True when every Sarvam call slot (all businesses together) is taken by a call in progress. */
export async function sarvamSlotsFull(env: Pick<Env, 'DB' | 'SARVAM_MAX_CONCURRENT_CALLS'>): Promise<boolean> {
  const row = await env.DB.prepare(
    `SELECT COUNT(*) AS cnt FROM calls WHERE status = 'calling' AND started_at > datetime('now', '-20 minutes')`
  ).first<{ cnt: number }>();
  return (row?.cnt ?? 0) >= sarvamMaxConcurrentCalls(env);
}

/** True when the remaining minutes cover all calls in progress plus one more. */
export function hasMinutesHeadroom(usage: MinuteBalances, activeCalls: number): boolean {
  return minutesRemaining(usage) >= (activeCalls + 1) * RESERVED_MINUTES_PER_CALL;
}

export interface OutboundCallSlot {
  callId: string;
  businessId: string;
  leadId: string;
  leadName: string;
  leadPhone: string;
  campaignId?: string;
}

/**
 * One-statement call-slot reservation. Counting active calls and inserting the new `calling` row
 * must be the same database write; a read followed by an insert lets parallel requests overbook.
 * For campaign calls the campaign and its claimed lead are checked in this same statement too.
 */
export function reserveOutboundCallStatement(
  env: Pick<Env, 'DB' | 'SARVAM_MAX_CONCURRENT_CALLS'>,
  slot: OutboundCallSlot,
): D1PreparedStatement {
  const campaignGuard = slot.campaignId
    ? `AND EXISTS (
         SELECT 1 FROM campaigns
         WHERE id = ? AND business_id = ? AND status = 'running'
       )
       AND EXISTS (
         SELECT 1 FROM campaign_leads
         WHERE campaign_id = ? AND lead_id = ? AND status = 'calling' AND call_id = ?
       )`
    : '';

  const params: unknown[] = [
    slot.callId,
    slot.businessId,
    slot.leadId,
    slot.leadName,
    slot.leadPhone,
    slot.campaignId ?? null,
    slot.businessId,
    MAX_CONCURRENT_CALLS_PER_BUSINESS,
    sarvamMaxConcurrentCalls(env),
    slot.businessId,
    slot.leadId,
    slot.businessId,
    slot.businessId,
    slot.businessId,
    RESERVED_MINUTES_PER_CALL,
  ];
  if (slot.campaignId) {
    params.push(slot.campaignId, slot.businessId, slot.campaignId, slot.leadId, slot.callId);
  }

  return env.DB.prepare(`
    INSERT INTO calls (id, business_id, lead_id, lead_name, lead_phone, campaign_id, status, started_at, created_at)
    SELECT ?, ?, ?, ?, ?, ?, 'calling', datetime('now'), datetime('now')
    WHERE (SELECT COUNT(*) FROM calls
           WHERE business_id = ? AND status = 'calling' AND started_at > datetime('now', '-20 minutes')) < ?
      AND (SELECT COUNT(*) FROM calls
           WHERE status = 'calling' AND started_at > datetime('now', '-20 minutes')) < ?
      AND NOT EXISTS (
        SELECT 1 FROM calls
        WHERE business_id = ? AND lead_id = ? AND status = 'calling'
          AND started_at > datetime('now', '-20 minutes')
      )
      AND (
        NOT EXISTS (SELECT 1 FROM usage WHERE business_id = ?)
        OR (
          (SELECT COALESCE(included_minutes, 0) + COALESCE(topup_minutes, 0)
                  + COALESCE(bonus_minutes, 0) - COALESCE(minutes_used, 0)
           FROM usage WHERE business_id = ?) >=
          ((SELECT COUNT(*) FROM calls
            WHERE business_id = ? AND status = 'calling'
              AND started_at > datetime('now', '-20 minutes')) + 1) * ?
        )
      )
      ${campaignGuard}
  `).bind(...params);
}
