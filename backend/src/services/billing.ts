import { Env } from '../types';

const CONNECTED = new Set(['completed', 'connected', 'answered', 'ended']);

/** Pure + tested. Unanswered calls cost 0. Missing duration on a connected call costs 0 and gets flagged, never a guessed 60s. */
export function billableMinutes(status: string, durationSeconds: number | null | undefined): { minutes: number; seconds: number; flagged: boolean } {
  const s = String(status || '').toLowerCase();
  if (!CONNECTED.has(s)) return { minutes: 0, seconds: 0, flagged: false };
  if (durationSeconds == null || !Number.isFinite(durationSeconds) || durationSeconds < 0) {
    return { minutes: 0, seconds: 0, flagged: true };
  }
  const secs = Math.floor(durationSeconds);
  return { minutes: secs === 0 ? 0 : Math.ceil(secs / 60), seconds: secs, flagged: false };
}

/** Returns true the FIRST time an event key is seen, false on every replay. */
export async function claimWebhookEvent(db: D1Database, eventKey: string, source = 'sarvam'): Promise<boolean> {
  const r = await db.prepare('INSERT OR IGNORE INTO webhook_events (event_key, source) VALUES (?, ?)')
    .bind(eventKey, source).run();
  return (r.meta?.changes ?? 0) > 0;
}

/** Idempotent billing: a call is billed at most once, at the highest duration seen. */
export async function recordCallUsage(env: Env, businessId: string, callId: string, minutes: number, seconds: number): Promise<number> {
  const prev = await env.DB.prepare('SELECT billed_minutes FROM usage_ledger WHERE call_id = ?')
    .bind(callId).first<{ billed_minutes: number }>();
  const isFirstTime = !prev;
  const delta = Math.max(0, minutes - (prev?.billed_minutes ?? 0));

  const stmts = [
    env.DB.prepare(
      `INSERT INTO usage_ledger (call_id, business_id, billable_seconds, billed_minutes)
       VALUES (?, ?, ?, ?)
       ON CONFLICT(call_id) DO UPDATE SET
         billable_seconds = MAX(billable_seconds, excluded.billable_seconds),
         billed_minutes   = MAX(billed_minutes, excluded.billed_minutes),
         updated_at       = datetime('now')`
    ).bind(callId, businessId, seconds, minutes),
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
