/**
 * Business numbers: one fixed phone number per business, rented from the pool we rent in Sarvam
 * (SARVAM_BUSINESS_NUMBERS, ₹59 per number per 30 days). Included in every paid plan; not in the trial.
 *
 * - The owner picks a specific free number once; it never rotates or changes on its own.
 * - It is the caller ID of every AI call the business makes (dial.ts, campaign_queue.ts), so customers
 *   always see the same number, and it is the line the AI answers (a Sarvam inbound deployment), so
 *   calling it back reaches the business.
 * - If the plan lapses, the number is held for NUMBER_HOLD_DAYS (the
 *   deployment paused, calls go out from the shared pool) and comes back the moment the plan does.
 *   After that it returns to the pool for someone else.
 * - On request: with no free number, the business asks for one (number_requests). Numbers can only
 *   be bought in the Sarvam dashboard, so the operator is alerted (alerts.ts); the cron gives the next
 *   number added to the longest-waiting business and tells the owner.
 *
 * Each number is answered by its own Sarvam agent: the agent's on-start hook can't see which number
 * was dialled, so each number's agent calls /voice/inbound/start?number=<it>. SARVAM_BUSINESS_NUMBERS
 * entries are "+917971443028=<agent id>:<version>"; a bare number uses SARVAM_INBOUND_APP_ID.
 */
import { Env } from '../types';
import { isMockSarvam } from '../utils/secrets';
import { hmacHex, BUSINESS_NUMBER_PLANS } from './plans';
import { ownerLanguage } from './owner_text';
import { sendBusinessPushNotification } from './fcm';

export { BUSINESS_NUMBER_PLANS };

/** Days a lapsed business's number waits for it before going back to the pool. */
export const NUMBER_HOLD_DAYS = 30;
/** How many free numbers the picker shows. */
export const PICKER_SIZE = 12;

export type NumberStatus = 'free' | 'active' | 'held';
export type ForwardMode = 'off' | 'missed' | 'all';

export interface BusinessNumberRow {
  phone: string;
  business_id: string | null;
  deployment_id: string | null;
  status: NumberStatus;
  forward_mode: ForwardMode;
  assigned_at: string | null;
  held_until: string | null;
}

/** "+917971440000" from anything with an Indian or international number in it; null if not a number. */
export function e164(raw: unknown): string | null {
  const digits = String(raw ?? '').replace(/\D/g, '');
  if (digits.length === 10) return `+91${digits}`;
  if (digits.length === 11 && digits.startsWith('0')) return `+91${digits.slice(1)}`;
  if (digits.length >= 11 && digits.length <= 15 && !digits.startsWith('0')) return `+${digits}`;
  return null;
}

/** Demo numbers when developing without a pool (mock Sarvam only). */
const MOCK_POOL = Array.from({ length: 8 }, (_, i) => `+9179714400${String(i + 1).padStart(2, '0')}`);

type PoolEnv = Pick<Env, 'SARVAM_BUSINESS_NUMBERS' | 'SARVAM_INBOUND_APP_ID' | 'SARVAM_INBOUND_APP_VERSION' | 'ENVIRONMENT' | 'SARVAM_API_KEY'>;

/** One SARVAM_BUSINESS_NUMBERS entry: the number and the agent that answers it (null: none configured). */
export interface PoolEntry {
  phone: string;
  agent: { appId: string; version: number } | null;
}

/** SARVAM_BUSINESS_NUMBERS parsed: "+917971443028=<agent id>:<version>" or a bare number (default agent). */
export function poolEntries(env: PoolEnv): PoolEntry[] {
  const fallback = env.SARVAM_INBOUND_APP_ID && Number(env.SARVAM_INBOUND_APP_VERSION) > 0
    ? { appId: env.SARVAM_INBOUND_APP_ID, version: Number(env.SARVAM_INBOUND_APP_VERSION) } : null;
  const seen = new Set<string>();
  const entries: PoolEntry[] = [];
  for (const raw of (env.SARVAM_BUSINESS_NUMBERS || '').split(',')) {
    const [num, agentPart] = raw.split('=');
    const phone = e164(num);
    if (!phone || seen.has(phone)) continue;
    seen.add(phone);
    const m = /^\s*([^:\s]+):(\d+)\s*$/.exec(agentPart ?? '');
    entries.push({ phone, agent: m ? { appId: m[1], version: Number(m[2]) } : fallback });
  }
  if (entries.length === 0 && isMockSarvam(env)) {
    return MOCK_POOL.map((phone) => ({ phone, agent: { appId: 'mock-receptionist', version: 1 } }));
  }
  return entries;
}

/** The numbers that can be given to businesses: in the pool and answered by an agent. */
export function poolNumbers(env: PoolEnv): string[] {
  return poolEntries(env).filter((e) => e.agent).map((e) => e.phone);
}

/**
 * True when business numbers can be offered or requested: Sarvam is configured (or mock). The pool
 * may be empty; then paying businesses request one and the operator adds it.
 */
export function numbersConfigured(env: Env): boolean {
  if (isMockSarvam(env)) return true;
  return !!(env.SARVAM_API_KEY && env.SARVAM_ORG_ID && env.SARVAM_WORKSPACE_ID && env.SARVAM_CONNECTION_ID);
}

/** True when the business's current plan includes a number (an active paid plan). */
export async function numberEntitled(db: D1Database, businessId: string): Promise<boolean> {
  const u = await db.prepare('SELECT plan_id, plan_status FROM usage WHERE business_id = ?')
    .bind(businessId).first<{ plan_id: string | null; plan_status: string | null }>();
  return u?.plan_status === 'active' && (BUSINESS_NUMBER_PLANS as readonly string[]).includes(u.plan_id ?? '');
}

export async function businessNumberFor(db: D1Database, businessId: string): Promise<BusinessNumberRow | null> {
  return db.prepare('SELECT * FROM business_numbers WHERE business_id = ?').bind(businessId).first<BusinessNumberRow>();
}

/** The caller ID for a business's AI calls: its own number while rented, else null (shared pool). */
export async function callerIdFor(db: D1Database, businessId: string): Promise<string | null> {
  const row = await db.prepare("SELECT phone FROM business_numbers WHERE business_id = ? AND status = 'active'")
    .bind(businessId).first<{ phone: string }>();
  return row?.phone ?? null;
}

/** Adds pool numbers the table doesn't know yet. */
async function syncPool(env: Env): Promise<string[]> {
  const pool = poolNumbers(env);
  if (pool.length) {
    await env.DB.batch(pool.map((p) => env.DB.prepare("INSERT OR IGNORE INTO business_numbers (phone, status) VALUES (?, 'free')").bind(p)));
  }
  return pool;
}

/** Free numbers a business can pick from (pool order). */
export async function availableNumbers(env: Env, limit = PICKER_SIZE): Promise<string[]> {
  const pool = await syncPool(env);
  if (pool.length === 0) return [];
  const { results } = await env.DB.prepare(
    `SELECT phone FROM business_numbers WHERE status = 'free' AND business_id IS NULL
       AND phone IN (${pool.map(() => '?').join(',')}) ORDER BY phone LIMIT ?`
  ).bind(...pool, limit).all<{ phone: string }>();
  return (results ?? []).map((r) => r.phone);
}

// ------------------------------------------------------------------ Sarvam deployments

/**
 * On-start hook URL token for one number's agent: HMAC(INBOUND_HOOK_SECRET, "hook:<number>"). Sarvam
 * only attaches stored secrets to allow-listed URLs, so each agent's hook URL carries this instead
 * (scripts/hook_url.mjs prints it).
 */
export function inboundHookToken(secret: string, phone: string): Promise<string> {
  return hmacHex(secret, `hook:${phone}`);
}

/** Webhook URL token for one number: HMAC(SARVAM_WEBHOOK_SECRET, "inbound:<number>"). */
export function inboundWebhookToken(secret: string, phone: string): Promise<string> {
  // Same HMAC-SHA256 hex as the per-call token (campaign_queue.ts sarvamWebhookToken).
  return hmacHex(secret, `inbound:${phone}`);
}

const deploymentsUrl = (env: Env) =>
  `https://apps.sarvam.ai/api/app-authoring/v1/orgs/${env.SARVAM_ORG_ID}/workspaces/${env.SARVAM_WORKSPACE_ID}/deployments`;

export type DeploymentResult = { ok: true; deploymentId: string } | { ok: false; error: string };

/** Creates the Sarvam inbound deployment for one number; its webhook URL carries the number's token. */
export async function createDeployment(env: Env, businessId: string, phone: string, webhookBaseUrl: string): Promise<DeploymentResult> {
  if (isMockSarvam(env)) return { ok: true, deploymentId: `mock_dep_${phone.replace(/\D/g, '')}` };
  const secret = env.SARVAM_WEBHOOK_SECRET;
  const agent = poolEntries(env).find((e) => e.phone === phone)?.agent;
  const apiKey = env.SARVAM_API_KEY;
  if (!secret || !apiKey || !agent || !numbersConfigured(env)) return { ok: false, error: 'sarvam_not_configured' };
  const token = await inboundWebhookToken(secret, phone);
  const res = await fetch(deploymentsUrl(env), {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-API-Key': apiKey },
    body: JSON.stringify({
      name: `CallPilot ${phone.replace(/\D/g, '')}`.slice(0, 50),
      app_id: agent.appId,
      app_version: agent.version,
      // The reference types say agent_phone_number, its example phone_numbers: send both.
      connection_configs: [{ connection_id: env.SARVAM_CONNECTION_ID, agent_phone_number: phone, phone_numbers: [phone] }],
      description: `Business number of ${businessId}`.slice(0, 150),
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

/** Deletes a deployment (number going back to the pool). */
export async function deleteDeployment(env: Env, deploymentId: string): Promise<boolean> {
  if (isMockSarvam(env)) return true;
  if (!env.SARVAM_API_KEY) return false;
  const res = await fetch(`${deploymentsUrl(env)}/${encodeURIComponent(deploymentId)}`, {
    method: 'DELETE',
    headers: { 'X-API-Key': env.SARVAM_API_KEY },
  });
  if (!res.ok && res.status !== 404) {
    console.error(JSON.stringify({ msg: 'sarvam_deployment_delete_failed', deploymentId, status: res.status }));
  }
  return res.ok || res.status === 404;
}

// ------------------------------------------------------------------ rental lifecycle

export type RentResult =
  | { ok: true; row: BusinessNumberRow }
  | { ok: false; code: 'not_configured' | 'not_entitled' | 'already_has_number' | 'number_taken' | 'sarvam_failed'; error?: string };

/**
 * Rents [phone] to the business: it must be free and in the pool, the plan must include a number,
 * and the business must not have one already (a number is chosen once; support changes it).
 */
export async function rentNumber(env: Env, businessId: string, rawPhone: unknown, webhookBaseUrl: string): Promise<RentResult> {
  if (!numbersConfigured(env)) return { ok: false, code: 'not_configured' };
  if (!(await numberEntitled(env.DB, businessId))) return { ok: false, code: 'not_entitled' };
  if (await businessNumberFor(env.DB, businessId)) return { ok: false, code: 'already_has_number' };
  const phone = e164(rawPhone);
  const pool = await syncPool(env);
  if (!phone || !pool.includes(phone)) return { ok: false, code: 'number_taken' };

  // One statement: only a free number can be taken, by one business.
  const claimed = await env.DB.prepare(
    `UPDATE business_numbers SET business_id = ?, status = 'active', assigned_at = datetime('now'), held_until = NULL
     WHERE phone = ? AND status = 'free' AND business_id IS NULL
     RETURNING phone`
  ).bind(businessId, phone).first<{ phone: string }>().catch((err: any) => {
    // UNIQUE(business_id): a concurrent request from the same business won.
    if (/UNIQUE constraint failed/i.test(String(err?.message ?? err))) return null;
    throw err;
  });
  if (!claimed) {
    return (await businessNumberFor(env.DB, businessId))
      ? { ok: false, code: 'already_has_number' }
      : { ok: false, code: 'number_taken' };
  }

  const dep = await createDeployment(env, businessId, phone, webhookBaseUrl);
  if (!dep.ok) {
    // Give the number back so the owner can try again (or pick another).
    await env.DB.prepare("UPDATE business_numbers SET business_id = NULL, status = 'free', assigned_at = NULL WHERE phone = ?").bind(phone).run();
    console.error(JSON.stringify({ msg: 'sarvam_business_number_deployment_failed', businessId, error: dep.error }));
    return { ok: false, code: 'sarvam_failed', error: dep.error };
  }
  await env.DB.prepare('UPDATE business_numbers SET deployment_id = ? WHERE phone = ?').bind(dep.deploymentId, phone).run();
  return { ok: true, row: (await businessNumberFor(env.DB, businessId))! };
}

/** The plan is back (or upgraded): a held number goes live again. Returns true if one was restored. */
export async function restoreNumberIfEntitled(env: Env, businessId: string): Promise<boolean> {
  const row = await businessNumberFor(env.DB, businessId);
  if (!row || row.status !== 'held' || !(await numberEntitled(env.DB, businessId))) return false;
  if (row.deployment_id) await setDeploymentActive(env, row.deployment_id, true);
  await env.DB.prepare("UPDATE business_numbers SET status = 'active', held_until = NULL WHERE phone = ?").bind(row.phone).run();
  return true;
}

/**
 * Account deletion: the number leaves the business at once (no business id kept, its calls are no
 * longer recorded) and the next cron run deletes its Sarvam deployment and puts it back in the pool.
 * A waiting request goes too.
 */
export function businessNumberDeletionStatements(db: D1Database, businessId: string): D1PreparedStatement[] {
  return [
    db.prepare(
      "UPDATE business_numbers SET business_id = NULL, status = 'held', held_until = datetime('now') WHERE business_id = ?"
    ).bind(businessId),
    db.prepare('DELETE FROM number_requests WHERE business_id = ?').bind(businessId),
  ];
}

// ------------------------------------------------------------------ on request

export type RequestResult =
  | { ok: true }
  | { ok: false; code: 'not_configured' | 'not_entitled' | 'already_has_number' };

/** A paying business asks for a number while none is free. Idempotent. */
export async function requestNumber(env: Env, businessId: string): Promise<RequestResult> {
  if (!numbersConfigured(env)) return { ok: false, code: 'not_configured' };
  if (!(await numberEntitled(env.DB, businessId))) return { ok: false, code: 'not_entitled' };
  if (await businessNumberFor(env.DB, businessId)) return { ok: false, code: 'already_has_number' };
  await env.DB.prepare('INSERT OR IGNORE INTO number_requests (business_id) VALUES (?)').bind(businessId).run();
  console.log(JSON.stringify({ msg: 'business_number_requested', business_id: businessId }));
  return { ok: true };
}

export async function numberRequested(db: D1Database, businessId: string): Promise<boolean> {
  return !!(await db.prepare('SELECT 1 AS x FROM number_requests WHERE business_id = ?').bind(businessId).first());
}

const READY_TEXT = {
  en: { title: 'Your business number is ready', body: (n: string, a: string) => `${n} is yours now. ${a} calls customers from it and answers it.` },
  hi: { title: 'आपका बिज़नेस नंबर तैयार है', body: (n: string, a: string) => `${n} अब आपका है। ${a} इसी से ग्राहकों को कॉल करेगा और इसी पर जवाब देगा।` },
  bn: { title: 'আপনার ব্যবসার নম্বর তৈরি', body: (n: string, a: string) => `${n} এখন আপনার। ${a} এই নম্বর থেকে গ্রাহকদের ফোন করবে আর এতেই উত্তর দেবে।` },
} as const;

/** "+917971443028" → "+91 79714 43028", as the app shows it. */
function displayNumber(phone: string): string {
  const d = phone.replace(/^\+91/, '');
  return d.length === 10 ? `+91 ${d.slice(0, 5)} ${d.slice(5)}` : phone;
}

/**
 * Gives free numbers to waiting businesses, longest-waiting first, and tells each owner. Requests
 * of businesses that no longer pay, or already have a number, are dropped. Returns how many got one.
 */
export async function fulfilNumberRequests(env: Env): Promise<number> {
  const base = env.PUBLIC_API_BASE_URL;
  if (!base || !numbersConfigured(env)) return 0;
  const { results } = await env.DB.prepare('SELECT business_id FROM number_requests ORDER BY requested_at, business_id')
    .all<{ business_id: string }>();
  let assigned = 0;
  for (const { business_id: businessId } of results ?? []) {
    const drop = () => env.DB.prepare('DELETE FROM number_requests WHERE business_id = ?').bind(businessId).run();
    if ((await businessNumberFor(env.DB, businessId)) || !(await numberEntitled(env.DB, businessId))) {
      await drop();
      continue;
    }
    const [free] = await availableNumbers(env, 1);
    if (!free) break;
    const r = await rentNumber(env, businessId, free, base);
    if (!r.ok) {
      if (r.code === 'sarvam_failed') break; // retried next run
      continue;
    }
    await drop();
    assigned++;
    try {
      const [lang, agent] = await Promise.all([
        ownerLanguage(env, businessId),
        env.DB.prepare('SELECT name FROM agents WHERE business_id = ?').bind(businessId).first<{ name: string }>(),
      ]);
      const t = READY_TEXT[lang];
      const title = t.title;
      const body = t.body(displayNumber(free), agent?.name || 'Your AI');
      await env.DB.prepare(
        `INSERT INTO notifications (id, business_id, type, title, body, route, action_label, is_read, created_at)
         VALUES (?, ?, 'business_number', ?, ?, '/agent/number', ?, 0, datetime('now'))`
      ).bind(`notif_${crypto.randomUUID().slice(0, 12)}`, businessId, title, body,
        lang === 'hi' ? 'देखें' : lang === 'bn' ? 'দেখুন' : 'View').run();
      await sendBusinessPushNotification(env, businessId, { type: 'business_number', title, body, route: '/agent/number' });
    } catch (err: any) {
      console.error(JSON.stringify({ msg: 'business_number_ready_notify_failed', error: err?.message }));
    }
  }
  return assigned;
}

/**
 * Cron. Active numbers of businesses whose plan no longer includes one are held for NUMBER_HOLD_DAYS
 * (deployment paused; their calls go out from the shared pool). Holds that ran out go back to the pool.
 * Then gives free numbers to businesses that asked for one. Returns how many were held, released, assigned.
 */
export async function runBusinessNumberCron(env: Env, now = new Date()): Promise<{ held: number; released: number; assigned: number }> {
  const { results: lapsed } = await env.DB.prepare(
    `SELECT n.phone, n.business_id, n.deployment_id FROM business_numbers n
     LEFT JOIN usage u ON u.business_id = n.business_id
     WHERE n.status = 'active'
       AND NOT (COALESCE(u.plan_status, '') = 'active' AND COALESCE(u.plan_id, '') IN (${BUSINESS_NUMBER_PLANS.map(() => '?').join(',')}))`
  ).bind(...BUSINESS_NUMBER_PLANS).all<{ phone: string; business_id: string; deployment_id: string | null }>();
  const holdUntil = new Date(now.getTime() + NUMBER_HOLD_DAYS * 86400_000).toISOString().slice(0, 19).replace('T', ' ');
  for (const n of lapsed ?? []) {
    if (n.deployment_id) await setDeploymentActive(env, n.deployment_id, false);
    await env.DB.prepare("UPDATE business_numbers SET status = 'held', held_until = ? WHERE phone = ? AND status = 'active'")
      .bind(holdUntil, n.phone).run();
    console.log(JSON.stringify({ msg: 'business_number_held', business_id: n.business_id, until: holdUntil }));
  }

  const nowSql = now.toISOString().slice(0, 19).replace('T', ' ');
  const { results: expired } = await env.DB.prepare(
    "SELECT phone, business_id, deployment_id FROM business_numbers WHERE status = 'held' AND held_until <= ?"
  ).bind(nowSql).all<{ phone: string; business_id: string; deployment_id: string | null }>();
  let released = 0;
  for (const n of expired ?? []) {
    if (n.deployment_id && !(await deleteDeployment(env, n.deployment_id))) continue; // retried next run
    await env.DB.prepare(
      `UPDATE business_numbers SET business_id = NULL, deployment_id = NULL, status = 'free', forward_mode = 'off',
         assigned_at = NULL, held_until = NULL
       WHERE phone = ? AND status = 'held'`
    ).bind(n.phone).run();
    released++;
    console.log(JSON.stringify({ msg: 'business_number_released', business_id: n.business_id }));
  }
  // Numbers just released, or newly added to the pool, go to businesses that asked for one.
  const assigned = await fulfilNumberRequests(env);
  return { held: lapsed?.length ?? 0, released, assigned };
}
