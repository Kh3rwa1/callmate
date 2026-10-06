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

  if (!lead || lead.do_not_call === 1) {
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

/**
 * Checks if the caller or call output indicates an opt-out request ("don't call me").
 */
export function isOptOutRequest(payload: any): boolean {
  if (!payload) return false;
  
  // Explicit intent
  const intent = String(payload.intent || payload.output_variables?.intent || '').toLowerCase();
  if (intent === 'opt_out' || intent === 'dnc' || intent === 'do_not_call' || intent === 'unsubscribe') {
    return true;
  }

  // Next action
  const nextAction = String(payload.next_action || payload.output_variables?.next_action || '').toLowerCase();
  if (nextAction === 'opt_out' || nextAction === 'do_not_call' || nextAction === 'dnc') {
    return true;
  }

  // Transcript inspection
  const transcript = payload.transcript || [];
  let transcriptText = '';
  if (Array.isArray(transcript)) {
    transcriptText = transcript.map((t: any) => t?.text || t?.content || '').join(' ').toLowerCase();
  } else if (typeof transcript === 'string') {
    transcriptText = transcript.toLowerCase();
  }

  const optOutPhrases = [
    'don\'t call me',
    'dont call me',
    'stop calling',
    'do not call',
    'remove my number',
    'remove me from your list',
    'wrong number don\'t call',
    'block my number',
    'spam report',
    'never call again',
  ];

  return optOutPhrases.some((phrase) => transcriptText.includes(phrase));
}
