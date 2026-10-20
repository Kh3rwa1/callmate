import { describe, it, expect, beforeAll, afterEach, vi } from 'vitest';
import { env } from 'cloudflare:test';
import { migrateTestDb } from './setup-db';
import app from '../src/index';
import { signJWT } from '../src/auth';
import { discoverSarvamNumbers, runBusinessNumberCron } from '../src/services/business_numbers';
import { callerIdsAreDltSeries, poolCallerIds } from '../src/services/compliance';
import { runComplianceCron } from '../src/services/retention';

const jwtSecret = 'test-jwt-signing-secret-key-32chars-min-length';
const OPS_KEY = 'ops-key-for-discovery-tests-0123456789';

const NEW1 = '+917971460011';
const DEPLOYED = '+917971460012';
const NEW3 = '+917971460013';
const STAGING = '+917971443028';
const SHARED = '+917971442975';
const CONFIG = '+917971460001';
const KNOWN = '+917971460020';
const REMOVED = '+917971460030';

async function sha256(text: string): Promise<string> {
  const d = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
  return [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

let AGENTS = '';
let OPS_HASH = '';

/** Production-like: picks up numbers by itself, one config number, two pool agents. */
const live = (extra: Record<string, unknown> = {}) => ({
  ...env,
  SARVAM_API_KEY: 'live-key', SARVAM_ORG_ID: 'org', SARVAM_WORKSPACE_ID: 'ws', SARVAM_CONNECTION_ID: 'conn',
  SARVAM_INBOUND_APP_ID: '', SARVAM_AGENT_PHONE_NUMBERS: SHARED,
  SARVAM_BUSINESS_NUMBERS: `${CONFIG}=Config-Agent:1`,
  SARVAM_RECEPTIONIST_AGENTS: AGENTS,
  SARVAM_AUTO_NUMBERS: 'true', SARVAM_NUMBERS_EXCLUDE: STAGING,
  OPS_KEY_SHA256: OPS_HASH,
  PUBLIC_API_BASE_URL: 'https://api.example',
  ...extra,
}) as any;

const tokens: Record<string, string> = {};
async function seedBusiness(id: string, name: string, phone: string) {
  await env.DB.batch([
    env.DB.prepare("INSERT OR REPLACE INTO businesses (id, name, category) VALUES (?, ?, 'retail')").bind(id, name),
    env.DB.prepare('INSERT OR REPLACE INTO users (id, phone, business_id) VALUES (?, ?, ?)').bind(`usr_${id}`, phone, id),
    env.DB.prepare(
      `INSERT OR REPLACE INTO agents (id, business_id, name, role, status, calling_hours_start, calling_hours_end, voice, languages)
       VALUES (?, ?, 'Asha', 'Front Desk', 'active', 0, 24, 'Warm · Female', '["English"]')`
    ).bind(`agt_${id}`, id),
    env.DB.prepare(
      `INSERT OR REPLACE INTO usage (id, business_id, plan_id, plan_status, included_minutes, minutes_used, current_period_end)
       VALUES (?, ?, 'starter', 'active', 500, 0, datetime('now', '+20 days'))`
    ).bind(`usg_${id}`, id),
  ]);
  tokens[id] = await signJWT({ sub: `usr_${id}`, phone, business_id: id, type: 'access' }, jwtSecret, 3600);
}
const authed = (biz: string, path: string, init: RequestInit = {}) => new Request(`http://localhost${path}`, {
  ...init, headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${tokens[biz]}` },
});
const ops = (fields: Record<string, string>, e = live()) => app.fetch(new Request('http://localhost/ops/numbers', {
  method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'cf-connecting-ip': '203.0.113.20' },
  body: new URLSearchParams(fields).toString(),
}), e);
const row = (phone: string) => env.DB.prepare('SELECT business_id, status, source, agent_app_id FROM business_numbers WHERE phone = ?')
  .bind(phone).first<{ business_id: string | null; status: string; source: string; agent_app_id: string | null }>();

interface Seen { url: string; method: string; key: string | null }

/**
 * Sarvam as the cron sees it: the connection's numbers over two pages ({endpoints}, no total), one
 * deployment using DEPLOYED ({items, total}), and deployments created on POST.
 */
function sarvam(numbers: unknown[], over: { endpoints?: () => Response; deployments?: () => Response } = {}) {
  const seen: Seen[] = [];
  vi.spyOn(globalThis, 'fetch').mockImplementation(async (u: any, init: any) => {
    const url = new URL(String(u));
    const method = init?.method ?? 'GET';
    seen.push({ url: url.toString(), method, key: new Headers(init?.headers).get('X-API-Key') });
    if (url.pathname.endsWith('/endpoints')) {
      if (over.endpoints) return over.endpoints();
      const offset = Number(url.searchParams.get('offset'));
      return Response.json({ endpoints: numbers.slice(offset, offset + Number(url.searchParams.get('limit'))) });
    }
    if (url.pathname.endsWith('/deployments') && method === 'GET') {
      if (over.deployments) return over.deployments();
      return Response.json({
        items: [
          { name: 'Rais Auto Spa Inbound', connection_configs: [{ connection_id: 'conn', agent_phone_number: DEPLOYED, phone_numbers: [DEPLOYED] }] },
          { name: 'CallPilot 917971460020', connection_configs: [{ connection_id: 'conn', agent_phone_number: KNOWN }] },
        ],
        total: 2, limit: 100, offset: 0, next_page_uri: null,
      });
    }
    return Response.json({ deployment_id: `dep_${seen.length}` });
  });
  return seen;
}

/** 100 entries on the first page (padding without numbers), NEW3 alone on the second. */
const CONNECTION = [
  { phone_number: NEW1 }, { phone_number: DEPLOYED }, { phone_number: STAGING }, { phone_number: SHARED },
  { phone_number: CONFIG }, { phone_number: KNOWN }, { phone_number: REMOVED }, { phone_number: '+14155550100' },
  { name: 'no number' },
  ...Array.from({ length: 91 }, (_, i) => ({ id: `ep_${i}` })),
  { phone_number: NEW3 },
];

beforeAll(async () => {
  await migrateTestDb();
  AGENTS = [`Pool-A:1:${await sha256('tok-a')}`, `Pool-B:1:${await sha256('tok-b')}`].join(',');
  OPS_HASH = await sha256(OPS_KEY);
  await seedBusiness('biz_disc_wait', 'Das Hardware', '919830077001');
  await seedBusiness('biz_disc_pick', 'Pal Sweets', '919830077002');
  await seedBusiness('biz_disc_known', 'Roy Books', '919830077003');
  await seedBusiness('biz_disc_cfg', 'Kar Pharmacy', '919830077004');
  await env.DB.batch([
    // The config number is rented, so only new numbers can reach the waiting business.
    env.DB.prepare("INSERT INTO business_numbers (phone, business_id, status, deployment_id) VALUES (?, 'biz_disc_cfg', 'active', 'dep_cfg')").bind(CONFIG),
    // Already ours: rented by a business, so its deployment is ours too.
    env.DB.prepare("INSERT INTO business_numbers (phone, business_id, status, source, deployment_id) VALUES (?, 'biz_disc_known', 'active', 'ops', 'dep_known')").bind(KNOWN),
    env.DB.prepare('INSERT INTO removed_numbers (phone) VALUES (?)').bind(REMOVED),
    env.DB.prepare('INSERT INTO number_requests (business_id) VALUES (?)').bind('biz_disc_wait'),
  ]);
});

afterEach(() => vi.restoreAllMocks());

describe('numbers bought in Sarvam join the pool by themselves', () => {
  it('is off unless SARVAM_AUTO_NUMBERS is "true" (staging), and in mock mode', async () => {
    const spy = vi.spyOn(globalThis, 'fetch');
    expect((await runBusinessNumberCron(live({ SARVAM_AUTO_NUMBERS: '' }))).discovered).toBe(0);
    expect(await discoverSarvamNumbers(live({ SARVAM_AUTO_NUMBERS: 'false' }))).toBe(0);
    expect(await discoverSarvamNumbers(live({ SARVAM_API_KEY: 'sk_test_x' }))).toBe(0);
    expect(spy).not.toHaveBeenCalled();
  });

  it('logs once a day while Sarvam refuses the API key, and carries on', async () => {
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
    sarvam([], { endpoints: () => Response.json({ detail: 'Not authenticated' }, { status: 401 }) });
    const first = await runBusinessNumberCron(live());
    expect(first).toMatchObject({ discovered: 0, assigned: 0 });
    await runBusinessNumberCron(live());
    const lines = warn.mock.calls.map((c) => String(c[0])).filter((l) => l.includes('sarvam_numbers_api_unavailable'));
    expect(lines).toHaveLength(1);
    expect(JSON.parse(lines[0])).toEqual({ msg: 'sarvam_numbers_api_unavailable', list: 'endpoints', status: 401 });
    expect((await env.DB.prepare("SELECT COUNT(*) AS n FROM business_numbers WHERE source = 'auto'").first<{ n: number }>())?.n).toBe(0);
  });

  it('adds nothing when the deployments list (or a body) cannot be read', async () => {
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
    sarvam(CONNECTION, { deployments: () => new Response('<html>oops</html>', { status: 200 }) });
    expect(await discoverSarvamNumbers(live())).toBe(0);
    expect(warn.mock.calls.some((c) => String(c[0]).includes('"list":"deployments","status":"bad_body"'))).toBe(true);
    expect(await row(NEW1)).toBeNull();
  });

  it('adds new numbers no deployment uses, skips the rest, and a waiting business gets one in the same run', async () => {
    const log = vi.spyOn(console, 'log').mockImplementation(() => {});
    const seen = sarvam(CONNECTION);
    const r = await runBusinessNumberCron(live());
    expect(r).toMatchObject({ discovered: 2, assigned: 1 });

    const lists = seen.filter((s) => s.method === 'GET');
    expect(lists.map((s) => s.url)).toEqual([
      'https://apps.sarvam.ai/api/app-authoring/v1/orgs/org/workspaces/ws/connections/conn/endpoints?limit=100&offset=0',
      'https://apps.sarvam.ai/api/app-authoring/v1/orgs/org/workspaces/ws/connections/conn/endpoints?limit=100&offset=100',
      'https://apps.sarvam.ai/api/app-authoring/v1/orgs/org/workspaces/ws/deployments?limit=100&offset=0',
    ]);
    expect(lists.every((s) => s.key === 'live-key')).toBe(true);
    const summary = log.mock.calls.map((c) => String(c[0])).find((l) => l.includes('sarvam_numbers_discovered'))!;
    expect(JSON.parse(summary)).toEqual({ msg: 'sarvam_numbers_discovered', found: 8, added: 2, excluded: 2, known: 2, removed: 1, not_dlt: 0, deployed: 1 });

    // The longest-waiting business got the first new number, on a pool agent, and was told.
    expect(await row(NEW1)).toEqual({ business_id: 'biz_disc_wait', status: 'active', source: 'auto', agent_app_id: 'Pool-A' });
    const created = seen.find((s) => s.method === 'POST')!;
    expect(created.url).toBe('https://apps.sarvam.ai/api/app-authoring/v1/orgs/org/workspaces/ws/deployments');
    const note = await env.DB.prepare("SELECT title FROM notifications WHERE business_id = 'biz_disc_wait' AND type = 'business_number'").first<any>();
    expect(note?.title).toBe('Your business number is ready');
    expect(await row(NEW3)).toEqual({ business_id: null, status: 'free', source: 'auto', agent_app_id: null });
    for (const skipped of [DEPLOYED, STAGING, SHARED, REMOVED, '+14155550100']) expect(await row(skipped)).toBeNull();
    expect(await row(KNOWN)).toMatchObject({ source: 'ops', status: 'active', business_id: 'biz_disc_known' });

    // The next run changes nothing.
    vi.restoreAllMocks();
    vi.spyOn(console, 'log').mockImplementation(() => {});
    sarvam(CONNECTION);
    expect((await runBusinessNumberCron(live())).discovered).toBe(0);
    expect((await env.DB.prepare("SELECT COUNT(*) AS n FROM business_numbers WHERE source = 'auto'").first<{ n: number }>())?.n).toBe(2);
    // With nothing new on the connection, the deployments list isn't read at all.
    vi.restoreAllMocks();
    vi.spyOn(console, 'log').mockImplementation(() => {});
    const quiet = sarvam([{ phone_number: NEW1 }, { phone_number: STAGING }]);
    expect(await discoverSarvamNumbers(live())).toBe(0);
    expect(quiet.map((s) => new URL(s.url).pathname.split('/').pop())).toEqual(['endpoints']);
  });

  it('a found number is offered and rented like one added on the ops page', async () => {
    const view = await (await app.fetch(authed('biz_disc_pick', '/business-number'), live())).json() as any;
    expect(view.numbers_free).toEqual([NEW3]);
    const html = await (await ops({ key: OPS_KEY, action: 'list' })).text();
    expect(html).toContain('<td>+91 79714 60013</td><td>free</td><td>auto</td><td>no</td>');
    expect(html).toContain('Picking up numbers bought in Sarvam by itself: on');
  });

  it('a number removed on the ops page is not picked up again until it is added there', async () => {
    vi.spyOn(console, 'log').mockImplementation(() => {});
    const removed = await ops({ key: OPS_KEY, action: 'remove', number: NEW3 });
    expect(removed.status).toBe(200);
    expect(await removed.text()).toContain('it won’t be picked up again');
    expect(await env.DB.prepare('SELECT phone FROM removed_numbers WHERE phone = ?').bind(NEW3).first()).toBeTruthy();

    sarvam(CONNECTION);
    expect(await discoverSarvamNumbers(live())).toBe(0);
    expect(await row(NEW3)).toBeNull();

    vi.restoreAllMocks();
    const added = await ops({ key: OPS_KEY, action: 'add', number: NEW3 });
    expect(await added.text()).toContain('Added +91 79714 60013.');
    expect(await row(NEW3)).toMatchObject({ source: 'ops', status: 'free' });
    expect(await env.DB.prepare('SELECT phone FROM removed_numbers WHERE phone = ?').bind(NEW3).first()).toBeNull();
    // A failed removal (a rented number) leaves no reminder behind.
    expect((await ops({ key: OPS_KEY, action: 'remove', number: NEW1 })).status).toBe(400);
    expect(await env.DB.prepare('SELECT phone FROM removed_numbers WHERE phone = ?').bind(NEW1).first()).toBeNull();
  });
});

describe('TRAI 140/160-series caller IDs', () => {
  const dltOnly = { SARVAM_AGENT_PHONE_NUMBERS: '+911601234567', SARVAM_BUSINESS_NUMBERS: '' };

  it('numbers stored in D1 count in the DLT check, /health/deep and the production warning', async () => {
    expect(callerIdsAreDltSeries(dltOnly)).toBe(true);
    const pool = await poolCallerIds(env.DB);
    expect(pool.sort()).toEqual([NEW1, NEW3, KNOWN].sort()); // ops and auto rows, not the config one
    expect(callerIdsAreDltSeries(dltOnly, pool)).toBe(false);
    expect(callerIdsAreDltSeries(dltOnly, ['+911401234567'])).toBe(true);

    const deep = await app.fetch(new Request('http://localhost/health/deep', { headers: { 'x-health-key': 'hk' } }),
      live({ ...dltOnly, HEALTH_CHECK_SECRET: 'hk', SARVAM_ADMISSIONS_APP_ID: 'a' }));
    expect(((await deep.json()) as any).compliance.caller_ids_dlt_series).toBe(false);

    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
    await runComplianceCron(live({ ...dltOnly, ENVIRONMENT: 'production' }));
    const line = warn.mock.calls.map((c) => String(c[0])).find((l) => l.includes('caller_ids_not_dlt_series'))!;
    expect(JSON.parse(line).business_numbers_not_dlt).toBe(3);
  });

  it('the ops page adds a number outside the series with a warning, or refuses it with REQUIRE_DLT_CALLER_IDS', async () => {
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
    vi.spyOn(console, 'log').mockImplementation(() => {});
    const added = await ops({ key: OPS_KEY, action: 'add', number: '+917971460040' });
    expect(added.status).toBe(200);
    const html = await added.text();
    expect(html).toContain('Added +91 79714 60040.');
    expect(html).toContain('it is not a TRAI 140/160-series number');
    expect(html).toContain('Not TRAI 140/160-series: 5');
    expect(warn.mock.calls.some((c) => String(c[0]).includes('business_number_not_dlt_series'))).toBe(true);

    const strict = live({ REQUIRE_DLT_CALLER_IDS: 'true' });
    const refused = await ops({ key: OPS_KEY, action: 'add', number: '+917971460041' }, strict);
    expect(refused.status).toBe(400);
    expect(await refused.text()).toContain('Only TRAI 140/160-series numbers can be added');
    expect(await row('+917971460041')).toBeNull();
    const ok = await ops({ key: OPS_KEY, action: 'add', number: '+911401234567' }, strict);
    expect(ok.status).toBe(200);
    const okHtml = await ok.text();
    expect(okHtml).toContain('Added +91 14012 34567.');
    expect(okHtml).not.toContain('it is not a TRAI');
    expect(okHtml).toContain('(REQUIRE_DLT_CALLER_IDS: no more can be added)');
  });

  it('with REQUIRE_DLT_CALLER_IDS the cron skips numbers outside the series', async () => {
    const log = vi.spyOn(console, 'log').mockImplementation(() => {});
    sarvam([{ phone_number: '+917971460050' }, { phone_number: '+911601112223' }]);
    expect(await discoverSarvamNumbers(live({ REQUIRE_DLT_CALLER_IDS: 'true' }))).toBe(1);
    expect(await row('+917971460050')).toBeNull();
    expect(await row('+911601112223')).toMatchObject({ source: 'auto', status: 'free' });
    const summary = log.mock.calls.map((c) => String(c[0])).find((l) => l.includes('sarvam_numbers_discovered'))!;
    expect(JSON.parse(summary)).toMatchObject({ found: 2, added: 1, not_dlt: 1 });
  });
});
