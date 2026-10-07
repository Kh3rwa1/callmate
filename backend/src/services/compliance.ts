/**
 * Calling Compliance Guardrails (TRAI & Tenant Calling Rules)
 */

export interface ComplianceCheckResult {
  allowed: boolean;
  reason?: 'outside_hours' | 'do_not_call' | 'max_daily_attempts' | 'max_campaign_attempts';
  reschedule?: boolean;
  rescheduleDelaySeconds?: number;
}

/**
 * Returns current hour (0-23) in the target timezone.
 */
export function getHourInTimezone(tz: string = 'Asia/Kolkata'): number {
  try {
    const formatter = new Intl.DateTimeFormat('en-US', {
      timeZone: tz || 'Asia/Kolkata',
      hour: 'numeric',
      hourCycle: 'h23',
    });
    return parseInt(formatter.format(new Date()), 10);
  } catch {
    const formatter = new Intl.DateTimeFormat('en-US', {
      timeZone: 'Asia/Kolkata',
      hour: 'numeric',
      hourCycle: 'h23',
    });
    return parseInt(formatter.format(new Date()), 10);
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
export function getSecondsUntilCallingWindow(tz: string = 'Asia/Kolkata', startHour: number = 10): number {
  const currentHour = getHourInTimezone(tz);
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
  }
): Promise<ComplianceCheckResult> {
  const hoursStart = params.hoursStart ?? 10;
  const hoursEnd = params.hoursEnd ?? 19;
  const tz = params.timezone || 'Asia/Kolkata';

  // 1. Check Calling Hours in lead timezone (default Asia/Kolkata)
  const currentHour = getHourInTimezone(tz);
  if (currentHour < hoursStart || currentHour >= hoursEnd) {
    const delay = getSecondsUntilCallingWindow(tz, hoursStart);
    return {
      allowed: false,
      reason: 'outside_hours',
      reschedule: true,
      rescheduleDelaySeconds: delay,
    };
  }

  // 2. Fetch Lead DNC status
  const lead = await db.prepare(
    'SELECT do_not_call, consent FROM leads WHERE id = ? AND business_id = ?'
  ).bind(params.leadId, params.businessId).first<{ do_not_call: number; consent: string }>();

  if (!lead || lead.do_not_call === 1 || lead.consent === 'opt_out') {
    return {
      allowed: false,
      reason: 'do_not_call',
      reschedule: false,
    };
  }

  // 3. Max Attempts per day check (max 3 calls per day)
  const callsToday = await db.prepare(
    `SELECT COUNT(*) as cnt FROM calls
     WHERE lead_id = ? AND business_id = ? AND started_at > datetime('now', '-1 day')`
  ).bind(params.leadId, params.businessId).first<{ cnt: number }>();

  if (callsToday && callsToday.cnt >= 3) {
    return {
      allowed: false,
      reason: 'max_daily_attempts',
      reschedule: true,
      rescheduleDelaySeconds: 24 * 3600, // Try tomorrow
    };
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
