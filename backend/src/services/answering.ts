/**
 * The AI answers calls the owner misses (inbound).
 *
 * Each business that turns it on gets one number from the pool we rent in Sarvam
 * (SARVAM_INBOUND_NUMBERS) and a Sarvam inbound deployment that routes calls on that number to the
 * receptionist agent (SARVAM_INBOUND_APP_ID / SARVAM_INBOUND_APP_VERSION). The owner forwards busy /
 * unanswered / unreachable calls from their own phone to the number (codes in the app).
 *
 *   call → agent on-start hook POST /voice/inbound/start → this business's name, employee, context
 *        → the agent talks → deployment webhook POST /webhooks/sarvam-inbound → lead + call row,
 *          then the same result handling as an outbound call (score, follow-up, billing, opt-out).
 *
 * A number stays with its business once assigned (turning answering off only pauses the deployment),
 * so a forwarding code the owner forgot to remove can never reach another business's AI.
 * Calls the person makes themselves are not unsolicited commercial communication, so TRAI's calling
 * hours and the 7-day enquiry window don't gate answering; the greeting still says it's an AI and the
 * call may be recorded.
 */
import { Env } from '../types';
import { isMockSarvam } from '../utils/secrets';
import { sarvamWebhookToken } from './campaign_queue';
import { callLang } from './voice_persona';
import { inboundGreeting } from './disclosure';
import { formatBusinessContext, firstLanguageName } from './call_variables';
import { topKnowledge } from './knowledge';
import { isPlanBlocked, minutesRemaining, MINUTE_BALANCE_COLUMNS, MinuteBalances } from './plans';

export interface AnsweringRow {
  phone: string;
  business_id: string | null;
  deployment_id: string | null;
  enabled: number;
}

/** "+917971440000" from anything with an Indian or international number in it; null if not a number. */
export function e164(raw: unknown): string | null {
  const digits = String(raw ?? '').replace(/\D/g, '');
  if (digits.length === 10) return `+91${digits}`;
  if (digits.length === 11 && digits.startsWith('0')) return `+91${digits.slice(1)}`;
  if (digits.length >= 11 && digits.length <= 15 && !digits.startsWith('0')) return `+${digits}`;
  return null;
}

/** The numbers rented for answering (SARVAM_INBOUND_NUMBERS), in E.164. */
export function poolNumbers(env: Pick<Env, 'SARVAM_INBOUND_NUMBERS'>): string[] {
  return [...new Set((env.SARVAM_INBOUND_NUMBERS || '').split(',').map(e164).filter((n): n is string => !!n))];
}

/** True when answering can be offered: the agent and at least one number are configured (or mock mode). */
export function answeringConfigured(env: Env): boolean {
  if (isMockSarvam(env)) return true;
  return !!(env.SARVAM_INBOUND_APP_ID && Number(env.SARVAM_INBOUND_APP_VERSION) > 0
    && env.SARVAM_ORG_ID && env.SARVAM_WORKSPACE_ID && env.SARVAM_CONNECTION_ID && poolNumbers(env).length);
}

export async function answeringFor(db: D1Database, businessId: string): Promise<AnsweringRow | null> {
  return db.prepare('SELECT phone, business_id, deployment_id, enabled FROM inbound_numbers WHERE business_id = ?')
    .bind(businessId).first<AnsweringRow>();
}

/** Webhook URL token for one answering number: HMAC(SARVAM_WEBHOOK_SECRET, "inbound:<number>"). */
export function inboundWebhookToken(secret: string, phone: string): Promise<string> {
  return sarvamWebhookToken(secret, `inbound:${phone}`);
}

/**
 * Gives the business a free pool number (once). Pool numbers missing from the table are added first.
 * Returns the business's number, or null when the pool is empty.
 */
export async function claimNumber(env: Env, businessId: string): Promise<string | null> {
  const existing = await answeringFor(env.DB, businessId);
  if (existing) return existing.phone;
  const pool = poolNumbers(env);
  if (isMockSarvam(env) && pool.length === 0) pool.push(`+9170000${String(Math.abs(hashCode(businessId)) % 100000).padStart(5, '0')}`);
  if (pool.length === 0) return null;
  await env.DB.batch(pool.map((p) => env.DB.prepare('INSERT OR IGNORE INTO inbound_numbers (phone) VALUES (?)').bind(p)));
  const placeholders = pool.map(() => '?').join(',');
  const claimed = await env.DB.prepare(
    `UPDATE inbound_numbers SET business_id = ?, assigned_at = datetime('now')
     WHERE phone = (SELECT phone FROM inbound_numbers WHERE business_id IS NULL AND phone IN (${placeholders}) ORDER BY phone LIMIT 1)
       AND business_id IS NULL
     RETURNING phone`
  ).bind(businessId, ...pool).first<{ phone: string }>();
  if (claimed) return claimed.phone;
  // Lost a race with a concurrent request from the same business, or the pool is used up.
  return (await answeringFor(env.DB, businessId))?.phone ?? null;
}

function hashCode(s: string): number {
  let h = 0;
  for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) | 0;
  return h;
}

const deploymentsUrl = (env: Env) =>
  `https://apps.sarvam.ai/api/app-authoring/v1/orgs/${env.SARVAM_ORG_ID}/workspaces/${env.SARVAM_WORKSPACE_ID}/deployments`;

export type DeploymentResult = { ok: true; deploymentId: string } | { ok: false; error: string };

/** Creates the Sarvam inbound deployment for one number; its webhook URL carries the number's token. */
export async function createDeployment(env: Env, businessId: string, phone: string, webhookBaseUrl: string): Promise<DeploymentResult> {
  if (isMockSarvam(env)) return { ok: true, deploymentId: `mock_dep_${phone.replace(/\D/g, '')}` };
  const secret = env.SARVAM_WEBHOOK_SECRET;
  if (!secret || !env.SARVAM_API_KEY || !answeringConfigured(env)) return { ok: false, error: 'sarvam_not_configured' };
  const token = await inboundWebhookToken(secret, phone);
  const res = await fetch(deploymentsUrl(env), {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-API-Key': env.SARVAM_API_KEY },
    body: JSON.stringify({
      name: `CallPilot answering ${phone.replace(/\D/g, '')}`.slice(0, 50),
      app_id: env.SARVAM_INBOUND_APP_ID,
      app_version: Number(env.SARVAM_INBOUND_APP_VERSION),
      // The reference types say agent_phone_number, its example phone_numbers: send both.
      connection_configs: [{ connection_id: env.SARVAM_CONNECTION_ID, agent_phone_number: phone, phone_numbers: [phone] }],
      description: `Answers missed calls for business ${businessId}`.slice(0, 150),
      webhook_config: {
        url: `${webhookBaseUrl}/webhooks/sarvam-inbound?number=${encodeURIComponent(phone)}&token=${token}`,
        metadata: { business_id: businessId },
      },
    }),
  });
  if (!res.ok) return { ok: false, error: `sarvam_http_${res.status}: ${(await res.text()).slice(0, 200)}` };
  const body = await res.json<any>().catch(() => ({}));
  return body?.deployment_id ? { ok: true, deploymentId: String(body.deployment_id) } : { ok: false, error: 'sarvam_no_deployment_id' };
}

/** Pauses or resumes a deployment. */
export async function setDeploymentActive(env: Env, deploymentId: string, active: boolean): Promise<boolean> {
  if (isMockSarvam(env)) return true;
  if (!env.SARVAM_API_KEY) return false;
  const res = await fetch(`${deploymentsUrl(env)}/${encodeURIComponent(deploymentId)}/status`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json', 'X-API-Key': env.SARVAM_API_KEY },
    body: JSON.stringify({ action: active ? 'resume' : 'pause' }),
  });
  if (!res.ok) console.error(JSON.stringify({ msg: 'sarvam_deployment_status_failed', deploymentId, status: res.status }));
  return res.ok;
}

/**
 * Turns answering on or off for a business. On: a number (claimed once), a deployment (created once),
 * resumed. Off: the deployment is paused; the number stays with the business.
 */
export async function setAnswering(env: Env, businessId: string, enabled: boolean, webhookBaseUrl: string):
  Promise<{ ok: true; row: AnsweringRow | null } | { ok: false; code: 'not_configured' | 'no_numbers' | 'sarvam_failed'; error?: string }> {
  if (!enabled) {
    const row = await answeringFor(env.DB, businessId);
    if (!row) return { ok: true, row: null };
    if (row.deployment_id && row.enabled === 1 && !(await setDeploymentActive(env, row.deployment_id, false))) {
      return { ok: false, code: 'sarvam_failed' };
    }
    await env.DB.prepare('UPDATE inbound_numbers SET enabled = 0 WHERE phone = ?').bind(row.phone).run();
    return { ok: true, row: { ...row, enabled: 0 } };
  }

  if (!answeringConfigured(env)) return { ok: false, code: 'not_configured' };
  const phone = await claimNumber(env, businessId);
  if (!phone) return { ok: false, code: 'no_numbers' };
  let row = (await answeringFor(env.DB, businessId))!;
  if (!row.deployment_id) {
    const dep = await createDeployment(env, businessId, phone, webhookBaseUrl);
    if (!dep.ok) {
      console.error(JSON.stringify({ msg: 'sarvam_inbound_deployment_failed', businessId, error: dep.error }));
      return { ok: false, code: 'sarvam_failed', error: dep.error };
    }
    await env.DB.prepare('UPDATE inbound_numbers SET deployment_id = ?, enabled = 1 WHERE phone = ?').bind(dep.deploymentId, phone).run();
  } else if (row.enabled !== 1) {
    if (!(await setDeploymentActive(env, row.deployment_id, true))) return { ok: false, code: 'sarvam_failed' };
    await env.DB.prepare('UPDATE inbound_numbers SET enabled = 1 WHERE phone = ?').bind(phone).run();
  }
  row = (await answeringFor(env.DB, businessId))!;
  return { ok: true, row };
}

/**
 * What the agent needs before it speaks (the on-start hook's reply, mapped into agent variables).
 * `called` = the number the person dialled. Unknown number: a neutral greeting, still disclosing AI.
 */
export async function inboundCallContext(env: Env, called: unknown, caller: unknown): Promise<Record<string, string>> {
  const phone = e164(called);
  const row = phone
    ? await env.DB.prepare('SELECT business_id, enabled FROM inbound_numbers WHERE phone = ?').bind(phone).first<{ business_id: string | null; enabled: number }>()
    : null;
  const businessId = row?.business_id;
  if (!businessId) {
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
  const canTalk = row.enabled === 1 && !(await isPlanBlocked(env.DB, businessId)) && (!usage || minutesRemaining(usage) > 0);
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
    greeting: inboundGreeting(callLang(agent?.languages), { agent: agent?.name, business: business?.name }),
  };
}
