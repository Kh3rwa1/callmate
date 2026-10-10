/**
 * Waste control: which unanswered outcomes are worth another dial, and which mean the number
 * itself is bad.
 *
 * Retry policy (campaigns): a lead gets at most MAX_DIAL_ATTEMPTS (3) dials = the first call plus
 * 2 retries, and only after `busy` / `no_answer`-like outcomes, each retry at least
 * RETRY_SPACING_SECONDS (3 h) later. failed / rejected / voicemail / invalid numbers are not retried:
 * the same outcome is likely and every retry that reaches voicemail costs us Sarvam + telephony.
 */

/** Minimum gap before a campaign re-dials a busy / unanswered lead. */
export const RETRY_SPACING_SECONDS = 3 * 60 * 60;

/** Terminal statuses where another attempt later in the day has a real chance to connect. */
export const RETRYABLE_OUTCOMES = new Set(['no_answer', 'no-answer', 'not_answered', 'busy', 'timeout']);

export function isRetryableOutcome(status: string | null | undefined): boolean {
  return RETRYABLE_OUTCOMES.has(String(status ?? '').toLowerCase().trim());
}

/** Statuses that mean the number cannot be reached at all. */
const INVALID_NUMBER_STATUSES = new Set(['invalid_number', 'invalid', 'not_reachable', 'unreachable', 'number_unreachable']);

/**
 * Sarvam's `failure_reason` is free text prefixed by the telephony provider, e.g.
 * "exotel: Invalid phone number". These patterns mean the number is wrong or unreachable.
 */
const INVALID_NUMBER_REASON = /invalid (phone |mobile )?number|not a valid (phone |mobile )?number|number (does not|doesn't) exist|unallocated|not in service|out of service|no longer in service|wrong number|unreachable|not reachable/i;

/** True when the webhook says this lead's phone number is invalid / unreachable. */
export function isInvalidNumberOutcome(status: string | null | undefined, failureReason: unknown): boolean {
  if (INVALID_NUMBER_STATUSES.has(String(status ?? '').toLowerCase().trim())) return true;
  return typeof failureReason === 'string' && INVALID_NUMBER_REASON.test(failureReason);
}
