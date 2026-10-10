/**
 * Owner-facing results: what the AI employee achieved in a period. Shared by
 * GET /dashboard/results (home results card) and the daily digest push (services/digest.ts).
 *
 * The owner's own test calls (leads.is_owner_test = 1, POST /agent/test-call) never count.
 */

/** Businesses have no timezone column yet; every owner is assumed to be in India. */
export const DEFAULT_BUSINESS_TIMEZONE = 'Asia/Kolkata';

/** SQLite datetime('now') format (UTC, no zone): `YYYY-MM-DD HH:MM:SS`. */
export function sqlUtc(d: Date): string {
  return d.toISOString().slice(0, 19).replace('T', ' ');
}

interface LocalParts { year: number; month: number; day: number; hour: number; minute: number }

function localParts(now: Date, tz: string): LocalParts {
  let fmt: Intl.DateTimeFormat;
  try {
    fmt = new Intl.DateTimeFormat('en-US', {
      timeZone: tz, year: 'numeric', month: 'numeric', day: 'numeric', hour: 'numeric', minute: 'numeric', hourCycle: 'h23',
    });
  } catch {
    return localParts(now, DEFAULT_BUSINESS_TIMEZONE);
  }
  const p: Record<string, number> = {};
  for (const part of fmt.formatToParts(now)) {
    if (part.type !== 'literal') p[part.type] = parseInt(part.value, 10);
  }
  return { year: p.year, month: p.month, day: p.day, hour: p.hour % 24, minute: p.minute };
}

/** The owner's local calendar date (`YYYY-MM-DD`) and hour (0-23) at [now]. */
export function localDateAndHour(now: Date, tz: string = DEFAULT_BUSINESS_TIMEZONE): { date: string; hour: number } {
  const p = localParts(now, tz);
  const date = `${p.year}-${String(p.month).padStart(2, '0')}-${String(p.day).padStart(2, '0')}`;
  return { date, hour: p.hour };
}

/**
 * UTC instant of local midnight [dayOffset] days from the local day containing [now]
 * (0 = today's midnight, 1 = tomorrow's, -6 = six days ago).
 */
export function localMidnightUtc(now: Date, dayOffset: number, tz: string = DEFAULT_BUSINESS_TIMEZONE): Date {
  const p = localParts(now, tz);
  // Offset of tz from UTC at [now], in minutes (whole-minute zones such as +05:30).
  const asUtc = Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute);
  const offsetMin = Math.round((asUtc - Math.floor(now.getTime() / 60000) * 60000) / 60000);
  return new Date(Date.UTC(p.year, p.month - 1, p.day + dayOffset) - offsetMin * 60000);
}

export interface PeriodResults {
  /** New leads (enquiries) added in the period. */
  enquiries: number;
  /** Calls placed in the period (any outcome). */
  calls: number;
  /** Calls that connected. */
  calls_connected: number;
  /** Distinct leads scored warm or hot on a connected call. */
  interested: number;
  /** Distinct leads scored hot ("wants to buy") on a connected call. */
  ready_to_buy: number;
  /** WhatsApp follow-ups the owner opened/sent. */
  followups_sent: number;
}

const NOT_OWNER_TEST = 'lead_id NOT IN (SELECT id FROM leads WHERE business_id = ?1 AND is_owner_test = 1)';

/** Results for one business over [start, end) (UTC). */
export async function periodResults(db: D1Database, businessId: string, start: Date, end: Date): Promise<PeriodResults> {
  const s = sqlUtc(start);
  const e = sqlUtc(end);
  const [enq, calls, fu] = await db.batch([
    db.prepare(
      `SELECT COUNT(*) AS n FROM leads
       WHERE business_id = ?1 AND is_owner_test = 0 AND created_at >= ?2 AND created_at < ?3`
    ).bind(businessId, s, e),
    db.prepare(
      `SELECT
         COUNT(*) AS calls,
         SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) AS connected,
         COUNT(DISTINCT CASE WHEN status = 'completed' AND temperature IN ('hot', 'warm') THEN lead_id END) AS interested,
         COUNT(DISTINCT CASE WHEN status = 'completed' AND temperature = 'hot' THEN lead_id END) AS hot
       FROM calls
       WHERE business_id = ?1 AND started_at >= ?2 AND started_at < ?3 AND ${NOT_OWNER_TEST}`
    ).bind(businessId, s, e),
    db.prepare(
      `SELECT COUNT(*) AS n FROM followups
       WHERE business_id = ?1 AND status IN ('opened', 'done')
         AND COALESCE(opened_at, created_at) >= ?2 AND COALESCE(opened_at, created_at) < ?3
         AND ${NOT_OWNER_TEST}`
    ).bind(businessId, s, e),
  ]);
  const c = (calls.results?.[0] ?? {}) as any;
  return {
    enquiries: Number((enq.results?.[0] as any)?.n ?? 0),
    calls: Number(c.calls ?? 0),
    calls_connected: Number(c.connected ?? 0),
    interested: Number(c.interested ?? 0),
    ready_to_buy: Number(c.hot ?? 0),
    followups_sent: Number((fu.results?.[0] as any)?.n ?? 0),
  };
}

/** Scheduled callbacks due in [start, end) (UTC). scheduled_at may be stored as ISO-8601 or SQLite text. */
export async function callbacksDue(db: D1Database, businessId: string, start: Date, end: Date): Promise<number> {
  const row = await db.prepare(
    `SELECT COUNT(*) AS n FROM callbacks
     WHERE business_id = ?1 AND status = 'scheduled'
       AND datetime(scheduled_at) >= ?2 AND datetime(scheduled_at) < ?3
       AND ${NOT_OWNER_TEST}`
  ).bind(businessId, sqlUtc(start), sqlUtc(end)).first<{ n: number }>();
  return Number(row?.n ?? 0);
}

export function estimatedValue(readyToBuy: number, avgDealValueInr: number | null | undefined): number | null {
  if (avgDealValueInr === null || avgDealValueInr === undefined || avgDealValueInr <= 0) return null;
  return readyToBuy * avgDealValueInr;
}
