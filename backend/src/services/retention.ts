/**
 * Data retention (DPDP Act 2023 s.8(7): erase personal data once the purpose is served).
 *
 * Every cron run clears the conversation content of calls older than RETENTION_DAYS (default 180):
 * transcript, recording link, summary and the raw webhook payload (which repeats the transcript).
 * Call metadata (status, duration, time, score, temperature, intent) stays for analytics and billing.
 * Batched: at most RETENTION_BATCH calls per run, so a backlog drains over several runs.
 */
import { Env } from '../types';
import { warnIfCallerIdsNotDlt } from './compliance';

export const DEFAULT_RETENTION_DAYS = 180;
/** Never shorter than this, whatever RETENTION_DAYS says (a typo must not wipe this week's calls). */
export const MIN_RETENTION_DAYS = 7;
export const RETENTION_BATCH = 500;

export function retentionDays(env: Pick<Env, 'RETENTION_DAYS'>): number {
  const n = Number.parseInt(String(env.RETENTION_DAYS ?? '').trim(), 10);
  if (!Number.isFinite(n) || n <= 0) return DEFAULT_RETENTION_DAYS;
  return Math.max(MIN_RETENTION_DAYS, n);
}

/** Clears content of up to RETENTION_BATCH expired calls. Returns how many were cleared. */
export async function runRetention(env: Pick<Env, 'DB' | 'RETENTION_DAYS'>): Promise<number> {
  const days = retentionDays(env);
  const res = await env.DB.prepare(
    `UPDATE calls SET transcript = NULL, recording_url = NULL, summary = NULL, raw_metadata = NULL
     WHERE id IN (
       SELECT id FROM calls
       WHERE started_at < datetime('now', ?)
         AND (transcript IS NOT NULL OR recording_url IS NOT NULL OR summary IS NOT NULL OR raw_metadata IS NOT NULL)
       LIMIT ?
     )`
  ).bind(`-${days} days`, RETENTION_BATCH).run();
  const cleared = res.meta?.changes ?? 0;
  if (cleared > 0) console.log(JSON.stringify({ msg: 'retention_cleared_calls', cleared, days }));
  return cleared;
}

/** Cron entry point for regulatory housekeeping: DLT caller-ID warning, then retention. */
export async function runComplianceCron(env: Env): Promise<void> {
  warnIfCallerIdsNotDlt(env);
  await runRetention(env);
}
