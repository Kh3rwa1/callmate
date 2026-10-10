import { Env } from '../types';
import { callCostInr } from './economics';

const CONNECTED = new Set(['completed', 'connected', 'answered', 'ended']);

/** Connected calls shorter than this are not billed (hang-ups, wrong person, IVR blips). */
export const MIN_BILLABLE_SECONDS = 10;

/**
 * Pure + tested. What the owner is billed for a call: every started minute (ceil(seconds / 60)) of a
 * connected call that lasted at least MIN_BILLABLE_SECONDS. Unanswered / busy / failed / voicemail
 * calls and connected calls under 10 s cost the owner 0 (we still record our cost separately).
 * Missing duration on a connected call costs 0 and gets flagged, never a guessed 60s.
 * `seconds` is the billed length (0 when not billed for an unanswered call).
 */
export function billableMinutes(status: string, durationSeconds: number | null | undefined): { minutes: number; seconds: number; flagged: boolean } {
  const s = String(status || '').toLowerCase();
  if (!CONNECTED.has(s)) return { minutes: 0, seconds: 0, flagged: false };
  if (durationSeconds == null || !Number.isFinite(durationSeconds) || durationSeconds < 0) {
    return { minutes: 0, seconds: 0, flagged: true };
  }
  const secs = Math.floor(durationSeconds);
  return { minutes: secs < MIN_BILLABLE_SECONDS ? 0 : Math.ceil(secs / 60), seconds: secs, flagged: false };
}

/** Returns true the FIRST time an event key is seen, false on every replay. */
export async function claimWebhookEvent(db: D1Database, eventKey: string, source = 'sarvam'): Promise<boolean> {
  const r = await db.prepare('INSERT OR IGNORE INTO webhook_events (event_key, source) VALUES (?, ?)')
    .bind(eventKey, source).run();
  return (r.meta?.changes ?? 0) > 0;
}

/** Releases a webhook claim so a failed call attempt or crash can be retried cleanly. */
export async function releaseWebhookEvent(db: D1Database, eventKey: string): Promise<void> {
  await db.prepare('DELETE FROM webhook_events WHERE event_key = ?').bind(eventKey).run();
}

/**
 * Idempotent billing: a call is billed at most once, at the highest duration seen.
 * `durationSeconds` is the real call length (our cost basis, billed or not); defaults to `seconds`.
 * Also stamps calls.billed_minutes / calls.cost_inr with the ledger's final values.
 */
export async function recordCallUsage(
  env: Env, businessId: string, callId: string, minutes: number, seconds: number, durationSeconds: number = seconds,
): Promise<number> {
  const prev = await env.DB.prepare('SELECT billed_minutes FROM usage_ledger WHERE call_id = ?')
    .bind(callId).first<{ billed_minutes: number }>();
  const isFirstTime = !prev;
  const delta = Math.max(0, minutes - (prev?.billed_minutes ?? 0));
  const duration = Math.max(seconds, durationSeconds);
  const cost = callCostInr(env, duration);

  const stmts = [
    env.DB.prepare(
      `INSERT INTO usage_ledger (call_id, business_id, billable_seconds, billed_minutes, duration_seconds, cost_inr, plan_id)
       VALUES (?, ?, ?, ?, ?, ?, (SELECT plan_id FROM usage WHERE business_id = ?))
       ON CONFLICT(call_id) DO UPDATE SET
         billable_seconds = MAX(billable_seconds, excluded.billable_seconds),
         billed_minutes   = MAX(billed_minutes, excluded.billed_minutes),
         duration_seconds = MAX(duration_seconds, excluded.duration_seconds),
         cost_inr         = MAX(cost_inr, excluded.cost_inr),
         updated_at       = datetime('now')`
    ).bind(callId, businessId, seconds, minutes, duration, cost, businessId),
    env.DB.prepare(
      `UPDATE calls SET
         billed_minutes = (SELECT billed_minutes FROM usage_ledger WHERE call_id = ?),
         cost_inr       = (SELECT cost_inr FROM usage_ledger WHERE call_id = ?)
       WHERE id = ? AND business_id = ?`
    ).bind(callId, callId, callId, businessId),
  ];
  if (isFirstTime) {
    stmts.push(
      env.DB.prepare(
        'UPDATE usage SET minutes_used = minutes_used + ?, calls_made = calls_made + 1 WHERE business_id = ?'
      ).bind(delta, businessId)
    );
  } else if (delta > 0) {
    stmts.push(
      env.DB.prepare('UPDATE usage SET minutes_used = minutes_used + ? WHERE business_id = ?').bind(delta, businessId)
    );
  }
  await env.DB.batch(stmts);
  return delta;
}
