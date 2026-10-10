/**
 * Calling Compliance Guardrails (TRAI & Tenant Calling Rules)
 */
import { isInGlobalDnc } from './global_dnc';

export interface ComplianceCheckResult {
  allowed: boolean;
  reason?: 'outside_hours' | 'do_not_call' | 'max_daily_attempts' | 'max_campaign_attempts' | 'platform_frequency_cap';
  reschedule?: boolean;
  rescheduleDelaySeconds?: number;
}

/**
 * TRAI: promotional/commercial calls only between 09:00 and 21:00 in the recipient's local time.
 * Whatever an owner stores, calls never go out before TRAI_EARLIEST_HOUR or from TRAI_LATEST_HOUR on.
 */
export const TRAI_EARLIEST_HOUR = 9;
/** Exclusive end hour: calls allowed while hour < 21. */
export const TRAI_LATEST_HOUR = 21;

/**
 * Narrows a stored calling window to the TRAI window. The result may be empty (start >= end),
 * which means "never".
 */
export function clampToTraiWindow(startHour: number, endHour: number): { start: number; end: number } {
  return {
    start: Math.max(startHour, TRAI_EARLIEST_HOUR),
    end: Math.min(endHour, TRAI_LATEST_HOUR),
  };
}

/**
 * Local development/test only: lets automated tests dial at any time of day by skipping the TRAI clamp
 * (the stored window still applies). Never honoured outside ENVIRONMENT=development|test.
 */
export function allowAnyCallingHours(env: { ENVIRONMENT?: string; DEV_ALLOW_ANY_CALLING_HOURS?: string }): boolean {
  return (env.ENVIRONMENT === 'development' || env.ENVIRONMENT === 'test') && env.DEV_ALLOW_ANY_CALLING_HOURS === 'true';
}

/** Distinct businesses that may call one phone number in a rolling 24h (platform-wide). */
export const PLATFORM_MAX_BUSINESSES_PER_PHONE = 3;

/**
 * TRAI: commercial voice calls must come from the 140 (promotional) or 160 (service/transactional)
 * number series. True only if every configured caller ID is +91140... or +91160...
 */
export function callerIdsAreDltSeries(env: { SARVAM_AGENT_PHONE_NUMBERS?: string }): boolean {
  const numbers = (env.SARVAM_AGENT_PHONE_NUMBERS || '').split(',')
    .map((n) => n.replace(/[\s()-]/g, '')).filter(Boolean);
  return numbers.length > 0 && numbers.every((n) => /^\+91(140|160)\d+$/.test(n));
}

/** Production only: one warning per cron run while the caller IDs are not 140/160 series. */
export function warnIfCallerIdsNotDlt(env: { ENVIRONMENT?: string; SARVAM_AGENT_PHONE_NUMBERS?: string }): boolean {
  if (env.ENVIRONMENT !== 'production' || callerIdsAreDltSeries(env)) return false;
  console.warn(JSON.stringify({
    msg: 'caller_ids_not_dlt_series',
    detail: 'SARVAM_AGENT_PHONE_NUMBERS should all be TRAI 140/160-series numbers (COMPLIANCE.md)',
  }));
  return true;
}

/**
 * Returns current hour (0-23) in the target timezone.
 */
export function getHourInTimezone(tz: string = 'Asia/Kolkata', now: Date = new Date()): number {
  try {
    const formatter = new Intl.DateTimeFormat('en-US', {
      timeZone: tz || 'Asia/Kolkata',
      hour: 'numeric',
      hourCycle: 'h23',
    });
    return parseInt(formatter.format(now), 10);
  } catch {
    const formatter = new Intl.DateTimeFormat('en-US', {
      timeZone: 'Asia/Kolkata',
      hour: 'numeric',
      hourCycle: 'h23',
    });
    return parseInt(formatter.format(now), 10);
  }
}

/**
 * Checks whether current time in timezone falls within allowed calling hours window.
 */
export function isWithinCallingHours(startHour: number = 10, endHour: number = 19, tz: string = 'Asia/Kolkata'): boolean {
  const currentHour = getHourInTimezone(tz);
  return currentHour >= startHour && currentHour < endHour;
}

/**
 * Calculates delay in seconds until the next calling window begins.
 */
export function getSecondsUntilCallingWindow(tz: string = 'Asia/Kolkata', startHour: number = 10, now: Date = new Date()): number {
  const currentHour = getHourInTimezone(tz, now);
  let hoursUntil = (startHour - currentHour + 24) % 24;
  if (hoursUntil === 0) hoursUntil = 24; // If currently passed window, delay until tomorrow
  return Math.max(60, hoursUntil * 3600);
}

/**
 * Checks compliance for an outbound call attempt.
 */
export async function checkCallCompliance(
  db: D1Database,
  params: {
    businessId: string;
    leadId: string;
    campaignId?: string;
    hoursStart?: number;
    hoursEnd?: number;
    timezone?: string;
    /** Dev/test only (see allowAnyCallingHours): skip the TRAI 09:00-21:00 clamp. */
    skipTraiClamp?: boolean;
    /** Injectable clock for tests. */
    now?: Date;
    /**
     * HMAC key for the platform-wide /stop list (globalDncSecret(env)). Every dial path must pass
     * it. null = no usable key: fail closed (nothing is dialled). Omitted = list not checked
     * (unit tests of the other rules only).
     */
    globalDncSecret?: string | null;
  }
): Promise<ComplianceCheckResult> {
  const storedStart = params.hoursStart ?? 10;
  const storedEnd = params.hoursEnd ?? 19;
  // Stored values may predate validation (or be edited directly); the TRAI window always wins.
  const { start: hoursStart, end: hoursEnd } = params.skipTraiClamp
    ? { start: storedStart, end: storedEnd }
    : clampToTraiWindow(storedStart, storedEnd);
  const tz = params.timezone || 'Asia/Kolkata';
  const now = params.now ?? new Date();

  // 1. Check Calling Hours in lead timezone (default Asia/Kolkata)
  const currentHour = getHourInTimezone(tz, now);
  if (currentHour < hoursStart || currentHour >= hoursEnd) {
    const delay = getSecondsUntilCallingWindow(tz, hoursStart, now);
    return {
      allowed: false,
      reason: 'outside_hours',
      reschedule: true,
      rescheduleDelaySeconds: delay,
    };
  }

  // 2. Fetch Lead DNC status
  const lead = await db.prepare(
    'SELECT do_not_call, consent, phone FROM leads WHERE id = ? AND business_id = ?'
  ).bind(params.leadId, params.businessId).first<{ do_not_call: number; consent: string; phone: string }>();

  if (!lead || lead.do_not_call === 1 || lead.consent === 'opt_out') {
    return {
      allowed: false,
      reason: 'do_not_call',
      reschedule: false,
    };
  }

  // 2b. Platform-wide opt-out list (public /stop page): blocks every business.
  if (params.globalDncSecret !== undefined) {
    if (params.globalDncSecret === null) {
      console.error(JSON.stringify({ msg: 'global_dnc_secret_missing', businessId: params.businessId }));
      return { allowed: false, reason: 'do_not_call', reschedule: false };
    }
    if (await isInGlobalDnc(db, params.globalDncSecret, lead.phone)) {
      return { allowed: false, reason: 'do_not_call', reschedule: false };
    }
  }

  // 3. Max Attempts per day check (max 3 calls per day). A dial the provider rejected
  // never rang the lead, so it doesn't count.
  const callsToday = await db.prepare(
    `SELECT COUNT(*) as cnt FROM calls
     WHERE lead_id = ? AND business_id = ? AND started_at > datetime('now', '-1 day')
       AND NOT (status = 'failed' AND interaction_id IS NULL)`
  ).bind(params.leadId, params.businessId).first<{ cnt: number }>();

  if (callsToday && callsToday.cnt >= 3) {
    return {
      allowed: false,
      reason: 'max_daily_attempts',
      reschedule: true,
      rescheduleDelaySeconds: 24 * 3600, // Try tomorrow
    };
  }

  // 3b. Platform-wide frequency cap: at most PLATFORM_MAX_BUSINESSES_PER_PHONE distinct businesses
  // may ring the same number in a rolling 24h, whoever the lead "belongs" to.
  const otherBusinesses = await db.prepare(
    `SELECT COUNT(DISTINCT business_id) AS cnt FROM calls
     WHERE lead_phone = ? AND business_id != ? AND started_at > datetime('now', '-1 day')
       AND NOT (status = 'failed' AND interaction_id IS NULL)`
  ).bind(lead.phone, params.businessId).first<{ cnt: number }>();
  if ((otherBusinesses?.cnt ?? 0) >= PLATFORM_MAX_BUSINESSES_PER_PHONE) {
    return { allowed: false, reason: 'platform_frequency_cap', reschedule: true, rescheduleDelaySeconds: 24 * 3600 };
  }

  // 3c. Campaign calls: one call per business per number per rolling 24h (any earlier call today,
  // manual or campaign, counts). No-answer retries therefore wait for the next day.
  if (params.campaignId) {
    const businessToday = await db.prepare(
      `SELECT COUNT(*) AS cnt FROM calls
       WHERE lead_phone = ? AND business_id = ? AND started_at > datetime('now', '-1 day')
         AND NOT (status = 'failed' AND interaction_id IS NULL)`
    ).bind(lead.phone, params.businessId).first<{ cnt: number }>();
    if ((businessToday?.cnt ?? 0) >= 1) {
      return { allowed: false, reason: 'platform_frequency_cap', reschedule: true, rescheduleDelaySeconds: 24 * 3600 };
    }
  }

  // 4. Max Attempts per campaign check (max 3 attempts per campaign)
  if (params.campaignId) {
    const campAttempts = await db.prepare(
      `SELECT attempts FROM campaign_leads WHERE campaign_id = ? AND lead_id = ?`
    ).bind(params.campaignId, params.leadId).first<{ attempts: number }>();

    if (campAttempts && campAttempts.attempts >= 3) {
      return {
        allowed: false,
        reason: 'max_campaign_attempts',
        reschedule: false,
      };
    }
  }

  return { allowed: true };
}

export const OPT_OUT_PATTERNS: RegExp[] = [
  // English
  /\b(do ?n[o']?t|never)\s+(call|phone|contact|ring)\s+(me|again|this number)\b/,
  /\bstop\s+(calling|contacting|messaging)\b/,
  /\b(remove|delete|take)\s+(my|this)\s+number\b/,
  /\bremove me from (your|the) list\b/,
  /\b(unsubscribe|opt ?out|block (my|this) number|report (you|this) (as )?spam)\b/,
  // Hinglish (romanised)
  /\b(call|phone|fon)\s+(mat|na|nahi|nai)\s+(karo|karna|kijiye|karein|karo na)\b/,
  /\b(dobara|phir se|fir se|wapas)\s+(call|phone)\s+(mat|na|nahi)\b/,
  /\b(mujhe|humein|hame)\s+(call|phone)\s+(mat|na|nahi)\b/,
  /\bnumber\s+(hata|hatao|hata do|delete kar do)\b/,
  /\b(band karo|bandh karo)\s+(call|calling|phone)\b/,
  // Hindi (Devanagari)
  /(कॉल|काल|फोन|फ़ोन)\s*(मत|ना|नहीं)\s*(करो|करना|करें|कीजिए)/,
  /(दोबारा|फिर से)\s*(कॉल|फोन|फ़ोन)\s*(मत|ना|नहीं)/,
  /नंबर\s*(हटा|हटाओ|हटा दो|डिलीट)/,
];

export function normalizeTranscript(s: string): string {
  return s.normalize('NFKC').toLowerCase().replace(/[’‘`]/g, "'").replace(/[^\p{L}\p{M}\p{N}'\s]/gu, ' ').replace(/\s+/g, ' ').trim();
}

/**
 * Checks if the caller or call output indicates an opt-out request ("don't call me").
 */
export function isOptOutRequest(payload: any): boolean {
  if (!payload) return false;
  const intent = String(payload.intent ?? payload.output_variables?.intent ?? '').toLowerCase();
  const next = String(payload.next_action ?? payload.output_variables?.next_action ?? '').toLowerCase();
  if (['opt_out', 'dnc', 'do_not_call', 'unsubscribe'].includes(intent)) return true;
  if (['opt_out', 'dnc', 'do_not_call'].includes(next)) return true;

  const t = payload.transcript;
  // Only inspect what the CUSTOMER said, not the agent (avoid "you can say stop calling anytime" false positives)
  const text = Array.isArray(t)
    ? t.filter((x: any) => !['agent', 'assistant', 'bot'].includes(String(x?.role ?? x?.speaker ?? '').toLowerCase()))
        .map((x: any) => x?.text ?? x?.content ?? x?.message ?? '').join(' ')
    : typeof t === 'string' ? t : '';
  const norm = normalizeTranscript(text);
  return OPT_OUT_PATTERNS.some((re) => re.test(norm));
}
