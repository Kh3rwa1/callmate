/**
 * Ops alerts, run from the cron (index.ts `scheduled`). Each run looks back over the last hour
 * and, for every check over its threshold, emits ONE alert per type per hour (deduped in
 * D1 `alert_state`):
 *   - a structured `console.error` with msg 'ops_alert' (always; visible in `wrangler tail`)
 *   - a POST to ALERT_WEBHOOK_URL if set (Slack / Discord / Google Chat incoming webhook)
 * Nothing happens when everything is healthy. Never throws.
 */
import { Env } from '../types';

export type AlertType = 'sarvam_dial_failures' | 'stuck_calls' | 'queue_dead_letters' | 'webhook_auth_failures';

/** Count in the last hour at which each alert fires. */
export const ALERT_THRESHOLDS: Record<AlertType, number> = {
  sarvam_dial_failures: 3,
  stuck_calls: 3,
  queue_dead_letters: 1,
  webhook_auth_failures: 10,
};

export const ALERT_DEDUPE_MINUTES = 60;

export type OpsEventKind = 'queue_dead_letter' | 'webhook_auth_failure';

/** Records an event nothing else stores, for the alert checks. Never throws. */
export async function recordOpsEvent(db: D1Database, kind: OpsEventKind, detail?: string | null): Promise<void> {
  try {
    await db.prepare('INSERT INTO ops_events (kind, detail) VALUES (?, ?)')
      .bind(kind, detail ? String(detail).replace(/\d{7,}/g, '<digits>').slice(0, 300) : null).run();
  } catch (err: any) {
    console.error(JSON.stringify({ msg: 'ops_event_record_failed', kind, error: err?.message }));
  }
}

export interface AlertFinding {
  type: AlertType;
  count: number;
  text: string;
}

async function countOpsEvents(db: D1Database, kind: OpsEventKind): Promise<{ n: number; sample: string | null }> {
  const row = await db.prepare(
    `SELECT COUNT(*) AS n, (SELECT detail FROM ops_events WHERE kind = ?1 AND created_at > datetime('now', '-60 minutes')
                            ORDER BY id DESC LIMIT 1) AS sample
     FROM ops_events WHERE kind = ?1 AND created_at > datetime('now', '-60 minutes')`
  ).bind(kind).first<{ n: number; sample: string | null }>();
  return { n: row?.n ?? 0, sample: row?.sample ?? null };
}

/** Runs every check; returns the ones over threshold (no side effects). */
export async function collectAlertFindings(env: Pick<Env, 'DB'>): Promise<AlertFinding[]> {
  const db = env.DB;
  const findings: AlertFinding[] = [];

  const failed = await db.prepare(
    `SELECT COUNT(*) AS n,
            (SELECT failure_reason FROM calls WHERE status = 'failed' AND failure_reason LIKE 'sarvam_%'
               AND started_at > datetime('now', '-60 minutes') ORDER BY started_at DESC LIMIT 1) AS sample
     FROM calls WHERE status = 'failed' AND failure_reason LIKE 'sarvam_%' AND started_at > datetime('now', '-60 minutes')`
  ).first<{ n: number; sample: string | null }>();
  if ((failed?.n ?? 0) >= ALERT_THRESHOLDS.sarvam_dial_failures) {
    findings.push({
      type: 'sarvam_dial_failures', count: failed!.n,
      text: `${failed!.n} Sarvam dials failed in the last hour. Latest: ${failed!.sample ?? 'n/a'}`,
    });
  }

  // Still 'calling' after 45 min, or swept to timed_out by maintenance within the last hour.
  const stuck = await db.prepare(
    `SELECT
       (SELECT COUNT(*) FROM calls WHERE status = 'calling' AND started_at < datetime('now', '-45 minutes')) AS calling,
       (SELECT COUNT(*) FROM calls WHERE status = 'timed_out' AND started_at > datetime('now', '-105 minutes')) AS timed_out`
  ).first<{ calling: number; timed_out: number }>();
  const stuckN = (stuck?.calling ?? 0) + (stuck?.timed_out ?? 0);
  if (stuckN >= ALERT_THRESHOLDS.stuck_calls) {
    findings.push({
      type: 'stuck_calls', count: stuckN,
      text: `${stuckN} calls got no Sarvam webhook within 45 min (${stuck?.calling ?? 0} still calling, ${stuck?.timed_out ?? 0} timed out).`,
    });
  }

  const dlq = await countOpsEvents(db, 'queue_dead_letter');
  if (dlq.n >= ALERT_THRESHOLDS.queue_dead_letters) {
    findings.push({
      type: 'queue_dead_letters', count: dlq.n,
      text: `${dlq.n} campaign jobs hit the dead-letter queue in the last hour (leads marked failed). Latest: ${dlq.sample ?? 'n/a'}`,
    });
  }

  const auth = await countOpsEvents(db, 'webhook_auth_failure');
  if (auth.n >= ALERT_THRESHOLDS.webhook_auth_failures) {
    findings.push({
      type: 'webhook_auth_failures', count: auth.n,
      text: `${auth.n} Sarvam webhooks were rejected as unauthorized in the last hour. Latest: ${auth.sample ?? 'n/a'}`,
    });
  }
  return findings;
}

/** Claims the hourly slot for this type; false if it already alerted within the dedupe window. */
async function claimAlertSlot(db: D1Database, f: AlertFinding): Promise<boolean> {
  const res = await db.prepare(
    `INSERT INTO alert_state (alert_type, last_sent_at, last_count) VALUES (?, datetime('now'), ?)
     ON CONFLICT(alert_type) DO UPDATE SET last_sent_at = excluded.last_sent_at, last_count = excluded.last_count
     WHERE alert_state.last_sent_at <= datetime('now', ?)`
  ).bind(f.type, f.count, `-${ALERT_DEDUPE_MINUTES} minutes`).run();
  return (res.meta?.changes ?? 0) > 0;
}

/** Slack and Google Chat take {text}; Discord takes {content}. Google Chat rejects unknown fields. */
export function alertWebhookBody(url: string, text: string): Record<string, string> {
  return /discord(app)?\.com\//i.test(url) ? { content: text } : { text };
}

async function postWebhook(url: string, text: string): Promise<void> {
  try {
    const res = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(alertWebhookBody(url, text)),
      signal: AbortSignal.timeout(10_000),
    });
    if (!res.ok) console.error(JSON.stringify({ msg: 'ops_alert_webhook_failed', status: res.status }));
  } catch (err: any) {
    console.error(JSON.stringify({ msg: 'ops_alert_webhook_failed', error: err?.message }));
  }
}

/** Cron entry point. Returns the alerts actually sent this run. */
export async function runAlertChecks(env: Env): Promise<AlertFinding[]> {
  const sent: AlertFinding[] = [];
  try {
    await env.DB.prepare(`DELETE FROM ops_events WHERE created_at < datetime('now', '-7 days')`).run();
    const findings = await collectAlertFindings(env);
    const where = env.ENVIRONMENT || 'unknown';
    for (const f of findings) {
      if (!(await claimAlertSlot(env.DB, f))) continue;
      const text = `[CallPilot ${where}] ${f.type}: ${f.text}`;
      console.error(JSON.stringify({ msg: 'ops_alert', env: where, type: f.type, count: f.count, text }));
      if (env.ALERT_WEBHOOK_URL) await postWebhook(env.ALERT_WEBHOOK_URL, text);
      sent.push(f);
    }
  } catch (err: any) {
    console.error(JSON.stringify({ msg: 'ops_alert_check_failed', error: err?.message }));
  }
  return sent;
}
