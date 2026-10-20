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
 * Sarvam's on-start hook can't see which number was dialled, so the agent answering a number has to
 * say which one it is. The ways a number gets into the pool:
 * - By itself (no deploy): with SARVAM_AUTO_NUMBERS on, the cron reads the numbers on the Sarvam
 *   connection and adds new ones no deployment uses (discoverSarvamNumbers, source 'auto').
 * - Ops page (no deploy): the operator adds a number bought in Sarvam on /ops/numbers (routes/ops.ts,
 *   source 'ops').
 *   Renting an 'auto' or 'ops' number claims a free agent from the receptionist pool
 *   (SARVAM_RECEPTIONIST_AGENTS, "<agent id>:<version>:<sha256 of its hook token>"), whose hook URL
 *   names the agent: /voice/inbound/start?agent=<id>&token=<token>. The row holding the agent is the
 *   number called. The agent stays with the number while it is held and goes back to the pool with it.
 * - Config (older): SARVAM_BUSINESS_NUMBERS entries "+917971443028=<agent id>:<version>", each number
 *   with its own agent whose hook URL names the number (?number=<it>); a bare number uses
 *   SARVAM_INBOUND_APP_ID.
 */
import { Env } from '../types';
import { isMockSarvam } from '../utils/secrets';
import { timingSafeEqual } from '../utils/compare';
import { hitRateLimit } from '../utils/rate_limit';
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
/**
 * 'config': listed in SARVAM_BUSINESS_NUMBERS. 'ops': added on the ops page. 'auto': found in Sarvam by
 * the cron. 'ops' and 'auto' numbers are answered by receptionist pool agents and behave the same.
 */
export type NumberSource = 'config' | 'ops' | 'auto';

export interface BusinessNumberRow {
  phone: string;
  business_id: string | null;
  deployment_id: string | null;
  status: NumberStatus;
  forward_mode: ForwardMode;
  assigned_at: string | null;
  held_until: string | null;
  /** The receptionist pool agent answering an ops number while it is rented or held. */
  agent_app_id?: string | null;
  agent_version?: number | null;
  source?: NumberSource;
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

/** A committed Sarvam agent version. */
export interface AgentRef {
  appId: string;
  version: number;
}

/** One SARVAM_BUSINESS_NUMBERS entry: the number and the agent that answers it (null: none configured). */
export interface PoolEntry {
  phone: string;
  agent: AgentRef | null;
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

/** The SARVAM_BUSINESS_NUMBERS numbers that can be given to businesses: answered by an agent. */
export function poolNumbers(env: PoolEnv): string[] {
  return poolEntries(env).filter((e) => e.agent).map((e) => e.phone);
}

// ------------------------------------------------------------------ receptionist pool

/** One SARVAM_RECEPTIONIST_AGENTS entry: a receptionist whose hook URL names itself, not a number. */
export interface ReceptionistAgent extends AgentRef {
  /** SHA-256 hex of the token in the agent's hook URL. */
  tokenSha256: string;
}

/**
 * SARVAM_RECEPTIONIST_AGENTS parsed: "<agent id>:<version>:<sha256 hex of its hook token>", comma
 * separated. Malformed and repeated entries are skipped (the ops page counts them).
 */
export function receptionistAgents(env: Pick<Env, 'SARVAM_RECEPTIONIST_AGENTS'>): ReceptionistAgent[] {
  const seen = new Set<string>();
  const agents: ReceptionistAgent[] = [];
  for (const raw of (env.SARVAM_RECEPTIONIST_AGENTS || '').split(',')) {
    const m = /^\s*([^:\s]+):(\d+):([0-9a-fA-F]{64})\s*$/.exec(raw);
    if (!m || Number(m[2]) < 1 || seen.has(m[1])) continue;
    seen.add(m[1]);
    agents.push({ appId: m[1], version: Number(m[2]), tokenSha256: m[3].toLowerCase() });
  }
  return agents;
}

type ReceptionistEnv = PoolEnv & Pick<Env, 'DB' | 'SARVAM_RECEPTIONIST_AGENTS'>;

/**
 * Pool agents free to answer a number: no row holds them. An agent that is also a
 * SARVAM_BUSINESS_NUMBERS agent is never handed out (it already answers that number).
 */
export async function freeReceptionistAgents(env: ReceptionistEnv): Promise<ReceptionistAgent[]> {
  const agents = receptionistAgents(env);
  if (agents.length === 0) return [];
  const { results } = await env.DB.prepare('SELECT agent_app_id FROM business_numbers WHERE agent_app_id IS NOT NULL')
    .all<{ agent_app_id: string }>();
  const taken = new Set((results ?? []).map((r) => r.agent_app_id));
  for (const e of poolEntries(env)) if (e.agent) taken.add(e.agent.appId);
  return agents.filter((a) => !taken.has(a.appId));
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

/** True when [token] is the hook token of pool agent [appId] (constant-time on the hashes). */
export async function receptionistTokenValid(env: Pick<Env, 'SARVAM_RECEPTIONIST_AGENTS'>, appId: string, token: string): Promise<boolean> {
  const agent = receptionistAgents(env).find((a) => a.appId === appId);
  if (!agent || !token) return false;
  return timingSafeEqual(await sha256Hex(token), agent.tokenSha256);
}

/** The rented (active or held) number a pool agent answers; null when it holds none. */
export async function numberOfReceptionist(db: D1Database, appId: string): Promise<string | null> {
  const row = await db.prepare('SELECT phone FROM business_numbers WHERE agent_app_id = ? AND business_id IS NOT NULL')
    .bind(appId).first<{ phone: string }>();
  return row?.phone ?? null;
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

/**
 * Free numbers a business can pick from: SARVAM_BUSINESS_NUMBERS numbers, and numbers found in Sarvam
 * or added on the ops page while a receptionist agent is free to answer one.
 */
export async function availableNumbers(env: Env, limit = PICKER_SIZE): Promise<string[]> {
  const pool = await syncPool(env);
  const poolAgentFree = (await freeReceptionistAgents(env)).length > 0;
  if (pool.length === 0 && !poolAgentFree) return [];
  const inConfig = pool.length ? `phone IN (${pool.map(() => '?').join(',')})` : '0';
  const { results } = await env.DB.prepare(
    `SELECT phone FROM business_numbers WHERE status = 'free' AND business_id IS NULL
       AND ((source = 'config' AND ${inConfig}) OR (source IN ('ops', 'auto') AND ?)) ORDER BY phone LIMIT ?`
  ).bind(...pool, poolAgentFree ? 1 : 0, limit).all<{ phone: string }>();
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

/**
 * Creates the Sarvam inbound deployment routing one number to [agent] (its SARVAM_BUSINESS_NUMBERS
 * agent, or the pool agent claimed for it); its webhook URL carries the number's token.
 */
export async function createDeployment(
  env: Env, businessId: string, phone: string, webhookBaseUrl: string, agent: AgentRef | null,
): Promise<DeploymentResult> {
  if (isMockSarvam(env)) return { ok: true, deploymentId: `mock_dep_${phone.replace(/\D/g, '')}` };
  const secret = env.SARVAM_WEBHOOK_SECRET;
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

type Claim = 'claimed' | 'not_free' | 'agent_taken';

/**
 * One statement: only a free number can be taken, by one business, together with the pool agent that
 * will answer it (null for a SARVAM_BUSINESS_NUMBERS number). 'agent_taken': another row holds it.
 */
async function claimNumber(db: D1Database, businessId: string, phone: string, poolAgent: AgentRef | null): Promise<Claim> {
  try {
    const row = await db.prepare(
      `UPDATE business_numbers SET business_id = ?, status = 'active', assigned_at = datetime('now'), held_until = NULL,
         agent_app_id = ?, agent_version = ?
       WHERE phone = ? AND status = 'free' AND business_id IS NULL
       RETURNING phone`
    ).bind(businessId, poolAgent?.appId ?? null, poolAgent?.version ?? null, phone).first<{ phone: string }>();
    return row ? 'claimed' : 'not_free';
  } catch (err: any) {
    const message = String(err?.message ?? err);
    if (!/UNIQUE constraint failed/i.test(message)) throw err;
    // UNIQUE(agent_app_id): a concurrent rental claimed this agent first.
    // UNIQUE(business_id): a concurrent request from the same business won.
    return /agent_app_id/.test(message) ? 'agent_taken' : 'not_free';
  }
}

/**
 * Rents [phone] to the business: it must be free and in the pool, the plan must include a number,
 * and the business must not have one already (a number is chosen once; support changes it). A number
 * found in Sarvam or added on the ops page takes a free receptionist pool agent with it; with none free
 * it can't be taken.
 */
export async function rentNumber(env: Env, businessId: string, rawPhone: unknown, webhookBaseUrl: string): Promise<RentResult> {
  if (!numbersConfigured(env)) return { ok: false, code: 'not_configured' };
  if (!(await numberEntitled(env.DB, businessId))) return { ok: false, code: 'not_entitled' };
  if (await businessNumberFor(env.DB, businessId)) return { ok: false, code: 'already_has_number' };
  const phone = e164(rawPhone);
  await syncPool(env);
  const row = phone
    ? await env.DB.prepare('SELECT source FROM business_numbers WHERE phone = ?').bind(phone).first<{ source: NumberSource }>()
    : null;
  if (!phone || !row) return { ok: false, code: 'number_taken' };

  let agent: AgentRef | null = null;
  let claim: Claim;
  if (row.source !== 'config') {
    // The free pool agents in order: when a concurrent rental claims one first, the next.
    claim = 'agent_taken';
    for (const a of await freeReceptionistAgents(env)) {
      claim = await claimNumber(env.DB, businessId, phone, a);
      if (claim !== 'agent_taken') {
        agent = { appId: a.appId, version: a.version };
        break;
      }
    }
    if (claim === 'agent_taken') {
      // The picker stops offering ops numbers; the ops alert asks for more agents.
      console.error(JSON.stringify({ msg: 'receptionist_pool_exhausted', business_id: businessId }));
      return { ok: false, code: 'number_taken' };
    }
  } else {
    // Not (or no longer) in SARVAM_BUSINESS_NUMBERS, or no agent answers it: can't be rented.
    agent = poolEntries(env).find((e) => e.phone === phone)?.agent ?? null;
    if (!agent) return { ok: false, code: 'number_taken' };
    claim = await claimNumber(env.DB, businessId, phone, null);
  }
  if (claim !== 'claimed') {
    return (await businessNumberFor(env.DB, businessId))
      ? { ok: false, code: 'already_has_number' }
      : { ok: false, code: 'number_taken' };
  }

  const dep = await createDeployment(env, businessId, phone, webhookBaseUrl, agent);
  if (!dep.ok) {
    // Give the number (and its pool agent) back so the owner can try again (or pick another).
    await env.DB.prepare(
      `UPDATE business_numbers SET business_id = NULL, status = 'free', assigned_at = NULL, agent_app_id = NULL, agent_version = NULL
       WHERE phone = ?`
    ).bind(phone).run();
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
 * A pool agent stays on the row until then, because that deployment still routes the number to it
 * (meanwhile its hook gets the neutral greeting), and is freed with the number. A waiting request
 * goes too.
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
 * (deployment paused, pool agent kept; their calls go out from the shared pool). Holds that ran out go
 * back to the pool: deployment deleted, pool agent freed. Numbers bought in Sarvam since the last run
 * join the pool (SARVAM_AUTO_NUMBERS). Then gives free numbers to businesses that asked for one.
 * Returns how many were held, released, discovered and assigned.
 */
export async function runBusinessNumberCron(env: Env, now = new Date()):
  Promise<{ held: number; released: number; discovered: number; assigned: number }> {
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
         assigned_at = NULL, held_until = NULL, agent_app_id = NULL, agent_version = NULL
       WHERE phone = ? AND status = 'held'`
    ).bind(n.phone).run();
    released++;
    console.log(JSON.stringify({ msg: 'business_number_released', business_id: n.business_id }));
  }
  const discovered = await discoverSarvamNumbers(env).catch((err: any) => {
    console.error(JSON.stringify({ msg: 'sarvam_numbers_discovery_failed', error: err?.message }));
    return 0;
  });
  // Numbers just released, or newly added to the pool, go to businesses that asked for one.
  const assigned = await fulfilNumberRequests(env);
  return { held: lapsed?.length ?? 0, released, discovered, assigned };
}

// ------------------------------------------------------------------ numbers bought in Sarvam, found by the cron

const SARVAM_PAGE_SIZE = 100;
const SARVAM_MAX_PAGES = 20;

type SarvamList = { ok: true; items: any[] } | { ok: false; status: number | 'network' | 'bad_body' };

/** Every page of a Sarvam list (limit/offset; the items in `items`, `endpoints`, `deployments` or `data`). */
async function sarvamListAll(url: string, apiKey: string): Promise<SarvamList> {
  const items: any[] = [];
  for (let page = 0; page < SARVAM_MAX_PAGES; page++) {
    const u = new URL(url);
    u.searchParams.set('limit', String(SARVAM_PAGE_SIZE));
    u.searchParams.set('offset', String(items.length));
    const res = await fetch(u.toString(), { headers: { 'X-API-Key': apiKey } }).catch(() => null);
    if (!res) return { ok: false, status: 'network' };
    if (!res.ok) return { ok: false, status: res.status };
    const body = await res.json<any>().catch(() => undefined);
    const list: any[] | undefined = Array.isArray(body)
      ? body
      : [body?.items, body?.endpoints, body?.deployments, body?.data].find(Array.isArray);
    if (!list) return { ok: false, status: 'bad_body' };
    items.push(...list);
    const total = Number(body?.total);
    const more = Number.isFinite(total) && !Array.isArray(body) ? items.length < total : list.length >= SARVAM_PAGE_SIZE;
    if (!more || list.length === 0) break;
  }
  return { ok: true, items };
}

/** Every phone number anywhere in a Sarvam object (any field whose name has "phone"), as E.164. */
function phonesIn(value: unknown, out: Set<string>, depth = 0): Set<string> {
  if (depth > 5 || !value || typeof value !== 'object') return out;
  for (const [k, v] of Object.entries(value)) {
    if (/phone/i.test(k)) {
      for (const p of Array.isArray(v) ? v : [v]) {
        const n = typeof p === 'string' ? e164(p) : null;
        if (n) out.add(n);
      }
    }
    phonesIn(v, out, depth + 1);
  }
  return out;
}

const csvNumbers = (raw: string | undefined) => (raw || '').split(',').map(e164).filter((n): n is string => !!n);

/**
 * Cron, with SARVAM_AUTO_NUMBERS = 'true': adds every Indian number on the Sarvam connection
 * (SARVAM_CONNECTION_ID) that we don't know yet to the pool, free, as source 'auto', so a number bought
 * in the dashboard reaches businesses with no other step. Never added: SARVAM_NUMBERS_EXCLUDE,
 * SARVAM_AGENT_PHONE_NUMBERS, SARVAM_BUSINESS_NUMBERS, numbers the operator removed on the ops page
 * (removed_numbers), and numbers any Sarvam deployment uses (another agent answers them). Sarvam's
 * numbers route isn't in its public API; while it refuses the API key, this logs
 * sarvam_numbers_api_unavailable once a day and adds nothing. Never throws. Returns how many it added.
 */
export async function discoverSarvamNumbers(env: Env): Promise<number> {
  const apiKey = env.SARVAM_API_KEY;
  if (env.SARVAM_AUTO_NUMBERS !== 'true' || isMockSarvam(env) || !apiKey || !numbersConfigured(env)) return 0;
  const base = `https://apps.sarvam.ai/api/app-authoring/v1/orgs/${env.SARVAM_ORG_ID}/workspaces/${env.SARVAM_WORKSPACE_ID}`;
  const unavailable = async (list: string, status: number | string) => {
    // Once a day, not every 10 minutes, while Sarvam keeps refusing.
    const { allowed } = await hitRateLimit(env.DB, `log:sarvam_numbers_api_unavailable:${list}`, 1, 86400);
    if (allowed) console.warn(JSON.stringify({ msg: 'sarvam_numbers_api_unavailable', list, status }));
    return 0;
  };

  const endpoints = await sarvamListAll(`${base}/connections/${encodeURIComponent(env.SARVAM_CONNECTION_ID!)}/endpoints`, apiKey);
  if (!endpoints.ok) return unavailable('endpoints', endpoints.status);
  const found = new Set<string>();
  for (const it of endpoints.items) {
    const n = e164(it?.phone_number ?? it?.phone ?? it?.number);
    if (n && /^\+91\d{10}$/.test(n)) found.add(n);
  }

  const excluded = new Set([
    ...csvNumbers(env.SARVAM_NUMBERS_EXCLUDE), ...csvNumbers(env.SARVAM_AGENT_PHONE_NUMBERS), ...poolEntries(env).map((e) => e.phone),
  ]);
  const [{ results: known }, { results: removed }] = await Promise.all([
    env.DB.prepare('SELECT phone FROM business_numbers').all<{ phone: string }>(),
    env.DB.prepare('SELECT phone FROM removed_numbers').all<{ phone: string }>(),
  ]);
  const knownSet = new Set((known ?? []).map((r) => r.phone));
  const removedSet = new Set((removed ?? []).map((r) => r.phone));
  const counts = { found: found.size, added: 0, excluded: 0, known: 0, removed: 0, deployed: 0 };
  const candidates: string[] = [];
  for (const n of found) {
    if (knownSet.has(n)) counts.known++;
    else if (excluded.has(n)) counts.excluded++;
    else if (removedSet.has(n)) counts.removed++;
    else candidates.push(n);
  }

  if (candidates.length) {
    // A number some deployment uses is answered by another agent (another product, or the other environment).
    const deployments = await sarvamListAll(`${base}/deployments`, apiKey);
    if (!deployments.ok) return unavailable('deployments', deployments.status);
    const deployed = new Set<string>();
    for (const d of deployments.items) phonesIn(d, deployed);
    for (const n of candidates) {
      if (deployed.has(n)) {
        counts.deployed++;
        continue;
      }
      const r = await env.DB.prepare(
        "INSERT INTO business_numbers (phone, status, source) VALUES (?, 'free', 'auto') ON CONFLICT(phone) DO NOTHING"
      ).bind(n).run();
      if ((r.meta?.changes ?? 0) > 0) {
        counts.added++;
        console.log(JSON.stringify({ msg: 'business_number_added', phone: n, source: 'auto' }));
      }
    }
  }
  console.log(JSON.stringify({ msg: 'sarvam_numbers_discovered', ...counts }));
  return counts.added;
}

// ------------------------------------------------------------------ ops page (routes/ops.ts)

export interface OpsPoolView {
  /** Every number in the pool. `listed`: a config number still in SARVAM_BUSINESS_NUMBERS (others: always). */
  numbers: { phone: string; status: NumberStatus; source: NumberSource; listed: boolean; agent: boolean }[];
  agentsTotal: number;
  agentsFree: number;
  /** SARVAM_RECEPTIONIST_AGENTS entries skipped as malformed or repeated. */
  agentsIgnored: number;
  /** Businesses waiting for a number. */
  waiting: number;
  /** SARVAM_AUTO_NUMBERS: the cron picks up numbers bought in Sarvam. */
  autoNumbers: boolean;
}

/**
 * What the ops page shows: each number's status, source and whether an agent answers it, and how
 * many pool agents are free. Never which business has a number.
 */
export async function opsPoolView(env: Env): Promise<OpsPoolView> {
  await syncPool(env);
  const config = new Map(poolEntries(env).map((e) => [e.phone, e]));
  const [{ results }, free, waiting] = await Promise.all([
    env.DB.prepare('SELECT phone, status, source, agent_app_id FROM business_numbers ORDER BY phone')
      .all<{ phone: string; status: NumberStatus; source: NumberSource; agent_app_id: string | null }>(),
    freeReceptionistAgents(env),
    env.DB.prepare('SELECT COUNT(*) AS n FROM number_requests').first<{ n: number }>(),
  ]);
  const agentsTotal = receptionistAgents(env).length;
  const entries = (env.SARVAM_RECEPTIONIST_AGENTS || '').split(',').filter((s) => s.trim()).length;
  return {
    numbers: (results ?? []).map((r) => {
      const entry = r.source === 'config' ? config.get(r.phone) : undefined;
      return {
        phone: r.phone,
        status: r.status,
        source: r.source,
        listed: r.source !== 'config' || !!entry,
        agent: r.source !== 'config' ? !!r.agent_app_id : !!entry?.agent,
      };
    }),
    agentsTotal,
    agentsFree: free.length,
    agentsIgnored: entries - agentsTotal,
    waiting: waiting?.n ?? 0,
    autoNumbers: env.SARVAM_AUTO_NUMBERS === 'true',
  };
}

export type OpsAddResult =
  | { ok: true; phone: string; added: boolean; assigned: number }
  | { ok: false; code: 'invalid' | 'shared_caller_id' | 'in_config' | 'in_use' };

/**
 * Ops page: a number bought in the Sarvam dashboard joins the pool, free (adding it twice, or one the
 * cron found already, changes nothing), and businesses waiting for a number get one at once. Indian
 * numbers only, never a shared caller ID (SARVAM_AGENT_PHONE_NUMBERS) or a SARVAM_BUSINESS_NUMBERS
 * number. Adding a number removed earlier lets the cron pick it up again.
 */
export async function addOpsNumber(env: Env, raw: unknown): Promise<OpsAddResult> {
  const phone = e164(raw);
  if (!phone || !/^\+91\d{10}$/.test(phone)) return { ok: false, code: 'invalid' };
  if (csvNumbers(env.SARVAM_AGENT_PHONE_NUMBERS).includes(phone)) return { ok: false, code: 'shared_caller_id' };
  if (poolEntries(env).some((e) => e.phone === phone)) return { ok: false, code: 'in_config' };
  const [, inserted] = await env.DB.batch([
    env.DB.prepare('DELETE FROM removed_numbers WHERE phone = ?').bind(phone),
    env.DB.prepare("INSERT INTO business_numbers (phone, status, source) VALUES (?, 'free', 'ops') ON CONFLICT(phone) DO NOTHING").bind(phone),
  ]);
  let added = (inserted.meta?.changes ?? 0) > 0;
  if (!added) {
    // Known already. A number dropped from SARVAM_BUSINESS_NUMBERS becomes an ops number once it is free.
    const converted = await env.DB.prepare(
      "UPDATE business_numbers SET source = 'ops' WHERE phone = ? AND source = 'config' AND status = 'free' AND business_id IS NULL"
    ).bind(phone).run();
    added = (converted.meta?.changes ?? 0) > 0;
    if (!added) {
      const row = await env.DB.prepare('SELECT source FROM business_numbers WHERE phone = ?').bind(phone).first<{ source: NumberSource }>();
      if (!row || row.source === 'config') return { ok: false, code: 'in_use' };
    }
  }
  if (added) console.log(JSON.stringify({ msg: 'business_number_added', phone, source: 'ops' }));
  const assigned = await fulfilNumberRequests(env);
  return { ok: true, phone, added, assigned };
}

export type OpsRemoveResult =
  | { ok: true; phone: string }
  | { ok: false; code: 'invalid' | 'not_found' | 'in_config' | 'in_use' };

/**
 * Ops page: takes a free, unassigned number found by the cron or added there out of the pool (before
 * releasing it in Sarvam). It is remembered in removed_numbers so the cron doesn't add it back.
 */
export async function removeOpsNumber(env: Env, raw: unknown): Promise<OpsRemoveResult> {
  const phone = e164(raw);
  if (!phone) return { ok: false, code: 'invalid' };
  const removable = `phone = ? AND source IN ('ops', 'auto') AND status = 'free' AND business_id IS NULL
    AND agent_app_id IS NULL AND deployment_id IS NULL`;
  // One transaction: the reminder is written only if the number really goes.
  const [, del] = await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO removed_numbers (phone) SELECT ? WHERE EXISTS (SELECT 1 FROM business_numbers WHERE ${removable})
       ON CONFLICT(phone) DO UPDATE SET removed_at = datetime('now')`
    ).bind(phone, phone),
    env.DB.prepare(`DELETE FROM business_numbers WHERE ${removable}`).bind(phone),
  ]);
  if ((del.meta?.changes ?? 0) > 0) {
    console.log(JSON.stringify({ msg: 'business_number_removed', phone }));
    return { ok: true, phone };
  }
  const row = await env.DB.prepare('SELECT source FROM business_numbers WHERE phone = ?').bind(phone).first<{ source: NumberSource }>();
  if (!row) return { ok: false, code: 'not_found' };
  return { ok: false, code: row.source === 'config' ? 'in_config' : 'in_use' };
}
