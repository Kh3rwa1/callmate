/**
 * The AI answers the business's calls (inbound), on its business number (services/business_numbers.ts).
 *
 * Customers who call the business number back reach the AI. The owner can also forward their own
 * phone to it: every call ('all'), only the ones they miss ('missed'), or none ('off') — codes in the
 * app; the backend only remembers the choice, which shapes the greeting.
 *
 *   call → agent on-start hook POST /voice/inbound/start → this business's name, employee, context
 *        → the agent talks → deployment webhook POST /webhooks/sarvam-inbound → lead + call row,
 *          then the same result handling as an outbound call (score, follow-up, billing, opt-out).
 *
 * Calls the person makes themselves are not unsolicited commercial communication, so TRAI's calling
 * hours and the 7-day enquiry window don't gate answering; the greeting still says it's an AI and the
 * call may be recorded.
 */
import { Env } from '../types';
import { callLang } from './voice_persona';
import { inboundGreeting } from './disclosure';
import { formatBusinessContext, firstLanguageName } from './call_variables';
import { topKnowledge } from './knowledge';
import { isPlanBlocked, minutesRemaining, MINUTE_BALANCE_COLUMNS, MinuteBalances } from './plans';
import { businessNumberFor, e164, ForwardMode, BusinessNumberRow } from './business_numbers';

/** Remembers how the owner's own phone forwards to the business number. Needs an active number. */
export async function setForwardMode(env: Env, businessId: string, mode: ForwardMode):
  Promise<{ ok: true; row: BusinessNumberRow } | { ok: false; code: 'no_business_number' }> {
  const row = await businessNumberFor(env.DB, businessId);
  if (!row || row.status !== 'active') return { ok: false, code: 'no_business_number' };
  await env.DB.prepare('UPDATE business_numbers SET forward_mode = ? WHERE phone = ?').bind(mode, row.phone).run();
  return { ok: true, row: { ...row, forward_mode: mode } };
}

/**
 * What the agent needs before it speaks (the on-start hook's reply, mapped into agent variables).
 * `called` = the number the person dialled. Unknown number: a neutral greeting, still disclosing AI.
 */
export async function inboundCallContext(env: Env, called: unknown, caller: unknown): Promise<Record<string, string>> {
  const phone = e164(called);
  const row = phone
    ? await env.DB.prepare('SELECT business_id, status, forward_mode FROM business_numbers WHERE phone = ?')
      .bind(phone).first<{ business_id: string | null; status: string; forward_mode: ForwardMode }>()
    : null;
  const businessId = row?.business_id;
  if (!row || !businessId) {
    return {
      business_name: '', agent_name: 'Assistant', agent_role: 'Assistant', business_context: '',
      call_language: 'English', caller_name: '', caller_known: 'no', can_talk: 'yes',
      greeting: inboundGreeting('en', {}),
    };
  }
  const [business, agent, usage] = await Promise.all([
    env.DB.prepare('SELECT * FROM businesses WHERE id = ?').bind(businessId).first<any>(),
    env.DB.prepare('SELECT * FROM agents WHERE business_id = ?').bind(businessId).first<any>(),
    env.DB.prepare(`SELECT ${MINUTE_BALANCE_COLUMNS} FROM usage WHERE business_id = ?`).bind(businessId).first<MinuteBalances>(),
  ]);
  const callerDigits = String(caller ?? '').replace(/\D/g, '');
  const lead = callerDigits
    ? await env.DB.prepare(
        `SELECT name, interest FROM leads WHERE business_id = ? AND phone IN (?, ?) AND is_owner_test = 0 LIMIT 1`
      ).bind(businessId, callerDigits, callerDigits.length === 10 ? `91${callerDigits}` : callerDigits).first<{ name: string; interest: string | null }>()
    : null;
  const knowledge = await topKnowledge(env, businessId, lead?.interest ?? null, 3).catch(() => []);
  const canTalk = row.status === 'active' && !(await isPlanBlocked(env.DB, businessId)) && (!usage || minutesRemaining(usage) > 0);
  // Everything forwarded: the AI is the front desk. Otherwise (missed calls, customers calling back)
  // it says the team can't come to the phone.
  const greetingMode = row.forward_mode === 'all' ? 'all' : 'missed';
  return {
    business_name: business?.name ?? '',
    agent_name: agent?.name ?? 'Assistant',
    agent_role: agent?.role ?? 'Assistant',
    business_context: formatBusinessContext(business, agent, knowledge),
    call_language: firstLanguageName(agent?.languages),
    caller_name: lead?.name && lead.name !== 'Caller' ? lead.name : '',
    caller_known: lead ? 'yes' : 'no',
    // 'no': out of minutes or plan unpaid — the agent takes a message and ends the call quickly.
    can_talk: canTalk ? 'yes' : 'no',
    answer_mode: greetingMode,
    greeting: inboundGreeting(callLang(agent?.languages), { agent: agent?.name, business: business?.name }, greetingMode),
  };
}
