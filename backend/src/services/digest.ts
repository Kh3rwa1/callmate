/**
 * Daily hot-lead digest: one push per business per local day, shortly after DIGEST_HOUR
 * ("Today: 12 calls, 3 ready to buy - tap to see them"). Runs from the 10-minute cron.
 *
 * - Local time is Asia/Kolkata (businesses have no timezone column yet).
 * - Sent between DIGEST_HOUR and DIGEST_HOUR + DIGEST_WINDOW_HOURS, so a cron outage never
 *   produces a late-night push.
 * - Deduplicated by digest_log(business_id, date): the row is claimed before the push.
 * - Skipped when the owner turned it off (businesses.digest_enabled = 0), when the business has
 *   no registered device, and when nothing happened today (no enquiries and no calls). A skipped
 *   zero-activity day is not logged, so activity later in the window still gets a digest.
 */

import { Env } from '../types';
import { sendBusinessPushNotification } from './fcm';
import { logInfo, logWarn } from '../utils/logger';
import { DEFAULT_BUSINESS_TIMEZONE, callbacksDue, localDateAndHour, localMidnightUtc, periodResults, PeriodResults } from './results';

export const DIGEST_HOUR = 19;
export const DIGEST_WINDOW_HOURS = 3;
/** Upper bound of businesses handled per cron run (the next run picks up the rest). */
export const DIGEST_BATCH_LIMIT = 200;

export interface DigestContent {
  title: string;
  body: string;
  route: string;
}

function plural(n: number, one: string, many: string): string {
  return `${n} ${n === 1 ? one : many}`;
}

/** Push text for a day's results; null when there is nothing worth telling the owner. */
export function buildDigest(r: PeriodResults, callbacksTomorrow: number): DigestContent | null {
  if (r.enquiries === 0 && r.calls === 0) return null;
  const parts: string[] = [];
  if (r.calls > 0) parts.push(plural(r.calls, 'call', 'calls'));
  if (r.ready_to_buy > 0) parts.push(`${r.ready_to_buy} ready to buy`);
  else if (r.interested > 0) parts.push(`${r.interested} interested`);
  if (r.enquiries > 0 && (r.calls === 0 || r.ready_to_buy === 0)) parts.push(plural(r.enquiries, 'new enquiry', 'new enquiries'));
  if (callbacksTomorrow > 0) parts.push(plural(callbacksTomorrow, 'callback tomorrow', 'callbacks tomorrow'));
  const route = r.ready_to_buy > 0 ? '/leads?filter=hot' : (r.interested > 0 ? '/leads?filter=warm' : '/leads');
  const cta = r.ready_to_buy > 0 ? 'tap to see them' : 'tap to see more';
  return {
    title: 'Your day with CallPilot',
    body: `Today: ${parts.join(', ')} — ${cta}`,
    route,
  };
}

/** Claims today's digest slot for a business. False if it was already sent (or claimed) today. */
export async function claimDigest(db: D1Database, businessId: string, date: string): Promise<boolean> {
  const res = await db.prepare('INSERT OR IGNORE INTO digest_log (business_id, date) VALUES (?, ?)').bind(businessId, date).run();
  return (res.meta?.changes ?? 0) > 0;
}

export async function runDailyDigests(env: Env, now: Date = new Date()): Promise<{ sent: number; skipped: number }> {
  const tz = DEFAULT_BUSINESS_TIMEZONE;
  const { date, hour } = localDateAndHour(now, tz);
  if (hour < DIGEST_HOUR || hour >= DIGEST_HOUR + DIGEST_WINDOW_HOURS) return { sent: 0, skipped: 0 };

  const dayStart = localMidnightUtc(now, 0, tz);
  const tomorrowStart = localMidnightUtc(now, 1, tz);
  const dayAfter = localMidnightUtc(now, 2, tz);

  let sent = 0;
  let skipped = 0;
  try {
    const { results: businesses } = await env.DB.prepare(
      `SELECT b.id FROM businesses b
       WHERE b.digest_enabled = 1
         AND EXISTS (SELECT 1 FROM devices d WHERE d.business_id = b.id)
         AND NOT EXISTS (SELECT 1 FROM digest_log g WHERE g.business_id = b.id AND g.date = ?)
       LIMIT ?`
    ).bind(date, DIGEST_BATCH_LIMIT).all<{ id: string }>();

    for (const b of businesses ?? []) {
      try {
        const today = await periodResults(env.DB, b.id, dayStart, now);
        const callbacks = await callbacksDue(env.DB, b.id, tomorrowStart, dayAfter);
        const content = buildDigest(today, callbacks);
        if (!content) {
          skipped++;
          continue;
        }
        if (!(await claimDigest(env.DB, b.id, date))) continue;

        await env.DB.prepare(
          `INSERT INTO notifications (id, business_id, type, title, body, route, action_label, is_read, created_at)
           VALUES (?, ?, 'daily_digest', ?, ?, ?, 'See results', 0, datetime('now'))`
        ).bind(`notif_${crypto.randomUUID().slice(0, 12)}`, b.id, content.title, content.body, content.route).run();
        await sendBusinessPushNotification(env, b.id, { type: 'daily_digest', ...content });
        sent++;
      } catch (err: any) {
        logWarn('daily_digest_business_failed', { error: err?.message });
      }
    }
  } catch (err: any) {
    logWarn('daily_digest_failed', { error: err?.message });
  }
  if (sent > 0 || skipped > 0) logInfo('daily_digest_run', { sent, skipped });
  return { sent, skipped };
}
