import { describe, it, expect, beforeAll, afterEach, vi } from 'vitest';
import { env } from 'cloudflare:test';
import { migrateTestDb } from './setup-db';
import app from '../src/index';
import { startedBeforeAssignment, syncInboundCalls } from '../src/routes/answering';
import { OPS_MAX_FAILURES } from '../src/routes/ops';
import { signJWT } from '../src/auth';
import {
  freeReceptionistAgents, inboundHookToken, inboundWebhookToken, receptionistAgents, rentNumber, runBusinessNumberCron,
  NUMBER_HOLD_DAYS,
} from '../src/services/business_numbers';
import { collectAlertFindings, runAlertChecks } from '../src/services/alerts';

const jwtSecret = 'test-jwt-signing-secret-key-32chars-min-length';
const HOOK_SECRET = 'hook-secret-for-tests-0123456789';
const OPS_KEY = 'ops-key-for-tests-correct-horse-battery';
/** A Sarvam analytics time (UTC, no zone) [sec] seconds from now. */
const analyticsTime = (sec: number) => new Date(Date.now() + sec * 1000).toISOString().slice(0, 19);

const CONFIG_NUM = '+917971450001';
const SHARED_NUM = '+917971442975';
const OPS1 = '+917971450011';
const OPS2 = '+917971450012';
const OPS3 = '+917971450013';
const OPS4 = '+917971450014';

async function sha256(text: string): Promise<string> {
  const d = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
  return [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

const tok = (agent: string) => `hook-token-of-${agent}-0123456789abcdef`;
const agentEntry = async (agent: string, version = 1) => `${agent}:${version}:${await sha256(tok(agent))}`;

let AGENTS_AB = '';
let AGENTS_ABC = '';
let AGENTS_ABCD = '';
let AGENTS_ABCDE = '';
let OPS_HASH = '';

/** Live (non-mock) Sarvam config: one config number with its own agent, two pool agents, the ops page on. */
const live = (extra: Record<string, unknown> = {}) => ({
  ...env,
  SARVAM_API_KEY: 'live-key', SARVAM_ORG_ID: 'org', SARVAM_WORKSPACE_ID: 'ws', SARVAM_CONNECTION_ID: 'conn',
  SARVAM_ADMISSIONS_APP_ID: 'outbound-agent', SARVAM_INBOUND_APP_ID: '', SARVAM_INBOUND_APP_VERSION: '',
  SARVAM_AGENT_PHONE_NUMBERS: SHARED_NUM,
  SARVAM_BUSINESS_NUMBERS: `${CONFIG_NUM}=Config-Agent:2`,
  SARVAM_RECEPTIONIST_AGENTS: AGENTS_AB,
  INBOUND_HOOK_SECRET: HOOK_SECRET,
  OPS_KEY_SHA256: OPS_HASH,
  PUBLIC_API_BASE_URL: 'https://api.example',
  ...extra,
}) as any;

const tokens: Record<string, string> = {};
const authed = (biz: string, path: string, init: RequestInit = {}) => new Request(`http://localhost${path}`, {
  ...init, headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${tokens[biz]}` },
});
const rent = (biz: string, phone: string, e = live()) =>
  app.fetch(authed(biz, '/business-number', { method: 'POST', body: JSON.stringify({ phone }) }), e);
const view = async (biz: string, e = live()) => (await app.fetch(authed(biz, '/business-number'), e)).json() as Promise<any>;

/** POST to the ops page as a form. */
const ops = (fields: Record<string, string>, e = live(), ip = '203.0.113.7') => app.fetch(new Request('http://localhost/ops/numbers', {
  method: 'POST',
  headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'cf-connecting-ip': ip },
  body: new URLSearchParams(fields).toString(),
}), e);

const hook = (query: string, body: unknown = { caller: '+919830066601' }, e = live()) =>
  app.fetch(new Request(`http://localhost/voice/inbound/start?${query}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body),
  }), e);
const agentHook = (agent: string, token = tok(agent), body?: unknown, e?: any) =>
  hook(`agent=${encodeURIComponent(agent)}&token=${encodeURIComponent(token)}`, body, e);

/** Records Sarvam API calls; answers deployments with an id. */
function sarvamSpy() {
  const calls: { url: string; method: string; body: any }[] = [];
  vi.spyOn(globalThis, 'fetch').mockImplementation(async (u: any, init: any) => {
    calls.push({ url: String(u), method: init?.method ?? 'GET', body: init?.body ? JSON.parse(init.body) : null });
    return new Response(JSON.stringify({ deployment_id: `dep_${calls.length}` }), { status: 200 });
  });
  return calls;
}

const row = (phone: string) => env.DB.prepare('SELECT business_id, status, source, agent_app_id, agent_version FROM business_numbers WHERE phone = ?')
  .bind(phone).first<{ business_id: string | null; status: string; source: string; agent_app_id: string | null; agent_version: number | null }>();

async function seedBusiness(id: string, name: string, plan: 'growth' | 'starter' | 'trial', phone: string) {
  await env.DB.batch([
    env.DB.prepare("INSERT OR REPLACE INTO businesses (id, name, category) VALUES (?, ?, 'education')").bind(id, name),
    env.DB.prepare('INSERT OR REPLACE INTO users (id, phone, business_id) VALUES (?, ?, ?)').bind(`usr_${id}`, phone, id),
    env.DB.prepare(
      `INSERT OR REPLACE INTO agents (id, business_id, name, role, status, calling_hours_start, calling_hours_end, voice, languages)
       VALUES (?, ?, 'Riya', 'Front Desk', 'active', 0, 24, 'Warm · Female', '["English"]')`
    ).bind(`agt_${id}`, id),
    env.DB.prepare(
      `INSERT OR REPLACE INTO usage (id, business_id, plan_id, plan_status, included_minutes, minutes_used, current_period_end)
       VALUES (?, ?, ?, ?, 2000, 0, datetime('now', '+20 days'))`
    ).bind(`usg_${id}`, id, plan, plan === 'trial' ? 'trial' : 'active'),
  ]);
  tokens[id] = await signJWT({ sub: `usr_${id}`, phone, business_id: id, type: 'access' }, jwtSecret, 3600);
}

beforeAll(async () => {
  await migrateTestDb();
  AGENTS_AB = [await agentEntry('Pool-A', 3), await agentEntry('Pool-B')].join(',');
  AGENTS_ABC = `${AGENTS_AB},${await agentEntry('Pool-C')}`;
  AGENTS_ABCD = `${AGENTS_ABC},${await agentEntry('Pool-D')}`;
  AGENTS_ABCDE = `${AGENTS_ABCD},${await agentEntry('Pool-E')}`;
  OPS_HASH = await sha256(OPS_KEY);
  await seedBusiness('biz_pool_config', 'Config Bakery', 'growth', '919830066001');
  await seedBusiness('biz_pool_wait', 'Sen Tailors', 'starter', '919830066002');
  await seedBusiness('biz_pool_pick', 'Pick Opticals', 'growth', '919830066003');
  await seedBusiness('biz_pool_late', 'Late Florist', 'starter', '919830066004');
  await seedBusiness('biz_pool_race', 'Race Motors', 'starter', '919830066005');
});

afterEach(() => vi.restoreAllMocks());

describe('the receptionist pool setting', () => {
  it('reads "<agent id>:<version>:<sha256 of its token>" entries and skips malformed or repeated ones', async () => {
    const h = await sha256('t');
    const agents = receptionistAgents({
      SARVAM_RECEPTIONIST_AGENTS: ` Pool-A:3:${h.toUpperCase()} , Pool-B:1:${h}, Pool-A:4:${h}, bad, Pool-C:0:${h}, Pool-D:1:abc, :1:${h}`,
    });
    expect(agents).toEqual([
      { appId: 'Pool-A', version: 3, tokenSha256: h },
      { appId: 'Pool-B', version: 1, tokenSha256: h },
    ]);
    expect(receptionistAgents({})).toEqual([]);
  });
});

describe('ops page', () => {
  it('does not exist until OPS_KEY_SHA256 is set', async () => {
    const off = live({ OPS_KEY_SHA256: '' });
    const get = await app.fetch(new Request('http://localhost/ops/numbers'), off);
    expect(get.status).toBe(404);
    expect(await get.json()).toEqual({ message: 'Endpoint /ops/numbers not found.', code: 'not_found' });
    expect((await ops({ key: OPS_KEY, action: 'list' }, off)).status).toBe(404);
    // A malformed hash keeps it off too.
    expect((await app.fetch(new Request('http://localhost/ops/numbers'), live({ OPS_KEY_SHA256: 'not-a-hash' }))).status).toBe(404);
  });

  it('GET shows only the form, uncached, unindexed and script-free', async () => {
    const res = await app.fetch(new Request('http://localhost/ops/numbers'), live());
    expect(res.status).toBe(200);
    expect(res.headers.get('Cache-Control')).toBe('no-store');
    expect(res.headers.get('X-Robots-Tag')).toContain('noindex');
    const csp = res.headers.get('Content-Security-Policy')!;
    expect(csp).toContain("default-src 'none'");
    expect(csp).toContain("form-action 'self'");
    expect(csp).not.toContain('script-src');
    const html = await res.text();
    expect(html).toContain('type="password"');
    expect(html).toContain('name="number"');
    expect(html).not.toContain('<script');
    expect(html).not.toContain('<table');
  });

  it('a wrong key gets a generic 401 and a log line; too many from one IP get 429', async () => {
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
    const bad = await ops({ key: 'guess', action: 'list' }, live(), '198.51.100.9');
    expect(bad.status).toBe(401);
    const html = await bad.text();
    expect(html).toContain('Not allowed.');
    expect(html).not.toContain('<table');
    expect(warn.mock.calls.some((c) => String(c[0]).includes('ops_page_unauthorized'))).toBe(true);
    expect((await ops({ action: 'list' }, live(), '198.51.100.9')).status).toBe(401);

    for (let i = 2; i < OPS_MAX_FAILURES; i++) await ops({ key: `guess${i}`, action: 'list' }, live(), '198.51.100.9');
    const limited = await ops({ key: OPS_KEY, action: 'list' }, live(), '198.51.100.9');
    expect(limited.status).toBe(429);
    // Another IP with the right key is unaffected.
    expect((await ops({ key: OPS_KEY, action: 'list' }, live(), '198.51.100.10')).status).toBe(200);
  });
});

describe('numbers added on the ops page, each answered by a pool agent', () => {
  it('a SARVAM_BUSINESS_NUMBERS number works as before, on its own agent', async () => {
    const calls = sarvamSpy();
    const res = await rent('biz_pool_config', CONFIG_NUM);
    expect(res.status).toBe(200);
    expect(calls[0].body).toMatchObject({ app_id: 'Config-Agent', app_version: 2 });
    expect(await row(CONFIG_NUM)).toMatchObject({ business_id: 'biz_pool_config', source: 'config', agent_app_id: null });
  });

  it('adding a number gives it to a waiting business at once, with the first free pool agent', async () => {
    const asked = await app.fetch(authed('biz_pool_wait', '/business-number/request', { method: 'POST' }), live());
    expect(await asked.json()).toMatchObject({ requested: true, numbers_free: [] });

    const calls = sarvamSpy();
    const res = await ops({ key: OPS_KEY, action: 'add', number: '079714 50011' });
    expect(res.status).toBe(200);
    expect(res.headers.get('Cache-Control')).toBe('no-store');
    const html = await res.text();
    expect(html).toContain('Added +91 79714 50011. 1 waiting business got a number.');
    expect(calls).toHaveLength(1);
    expect(calls[0].body).toMatchObject({
      app_id: 'Pool-A', app_version: 3,
      connection_configs: [{ connection_id: 'conn', agent_phone_number: OPS1, phone_numbers: [OPS1] }],
      webhook_config: { metadata: { business_id: 'biz_pool_wait' } },
    });
    const t = await inboundWebhookToken(env.SARVAM_WEBHOOK_SECRET!, OPS1);
    expect(calls[0].body.webhook_config.url).toBe(`https://api.example/webhooks/sarvam-inbound?number=%2B917971450011&token=${t}`);
    expect(await row(OPS1)).toMatchObject({ business_id: 'biz_pool_wait', status: 'active', source: 'ops', agent_app_id: 'Pool-A', agent_version: 3 });
    expect(await view('biz_pool_wait')).toMatchObject({ number: { phone: OPS1, status: 'active' }, requested: false });
    const note = await env.DB.prepare("SELECT title FROM notifications WHERE business_id = 'biz_pool_wait' AND type = 'business_number'").first<any>();
    expect(note?.title).toBe('Your business number is ready');
  });

  it('adding is idempotent and refuses numbers that are not ours to add', async () => {
    const again = await ops({ key: OPS_KEY, action: 'add', number: OPS1 });
    expect(again.status).toBe(200);
    expect(await again.text()).toContain('+91 79714 50011 is in the pool already. 0 waiting businesses got a number.');
    for (const [number, text] of [
      ['12345', 'Enter an Indian number'],
      ['+14155550100', 'Enter an Indian number'],
      [SHARED_NUM, 'shared caller ID'],
      [CONFIG_NUM, 'in SARVAM_BUSINESS_NUMBERS already'],
    ]) {
      const res = await ops({ key: OPS_KEY, action: 'add', number });
      expect(res.status).toBe(400);
      expect(await res.text()).toContain(text);
    }
    const n = await env.DB.prepare('SELECT COUNT(*) AS n FROM business_numbers').first<{ n: number }>();
    expect(n?.n).toBe(2);
  });

  it('lists each number with status, source and agent, never which business has it', async () => {
    const res = await ops({ key: OPS_KEY, action: 'list' });
    expect(res.status).toBe(200);
    const html = await res.text();
    expect(html).toContain('<td>+91 79714 50011</td><td>active</td><td>ops</td><td>yes</td>');
    expect(html).toContain('<td>+91 79714 50001</td><td>active</td><td>config</td><td>yes</td>');
    expect(html).toContain('Receptionist agents free: 1 of 2');
    expect(html).toContain('Businesses waiting for a number: 0');
    for (const secret of ['Sen Tailors', 'biz_pool_wait', 'Config Bakery', 'biz_pool_config', 'Pool-A']) {
      expect(html).not.toContain(secret);
    }
    // The key goes back into its masked field for the next action.
    expect(html).toContain(`type="password" autocomplete="current-password" maxlength="200" required value="${OPS_KEY}"`);
    // Counts malformed SARVAM_RECEPTIONIST_AGENTS entries.
    const broken = await ops({ key: OPS_KEY, action: 'list' }, live({ SARVAM_RECEPTIONIST_AGENTS: `${AGENTS_AB},oops` }));
    expect(await broken.text()).toContain('entries ignored (malformed or repeated): 1');
    const none = await ops({ key: OPS_KEY, action: 'list' }, live({ SARVAM_RECEPTIONIST_AGENTS: '' }));
    expect(await none.text()).toContain('none configured (SARVAM_RECEPTIONIST_AGENTS)');
  });

  it('the picker offers ops numbers while an agent is free; renting one claims that agent', async () => {
    for (const number of [OPS2, OPS3]) {
      expect((await ops({ key: OPS_KEY, action: 'add', number })).status).toBe(200);
    }
    expect((await view('biz_pool_pick')).numbers_free).toEqual([OPS2, OPS3]);
    const calls = sarvamSpy();
    const res = await rent('biz_pool_pick', OPS3);
    expect(res.status).toBe(200);
    expect(calls[0].body).toMatchObject({ app_id: 'Pool-B', app_version: 1, connection_configs: [{ agent_phone_number: OPS3 }] });
    expect(await row(OPS3)).toMatchObject({ business_id: 'biz_pool_pick', agent_app_id: 'Pool-B', agent_version: 1 });
  });

  it('with every pool agent taken, ops numbers are not offered and cannot be rented', async () => {
    expect(await freeReceptionistAgents(live())).toEqual([]);
    expect((await view('biz_pool_late')).numbers_free).toEqual([]);
    const err = vi.spyOn(console, 'error').mockImplementation(() => {});
    const res = await rent('biz_pool_late', OPS2);
    expect(res.status).toBe(409);
    expect((await res.json() as any).code).toBe('number_taken');
    expect(err.mock.calls.some((c) => String(c[0]).includes('receptionist_pool_exhausted'))).toBe(true);
    expect(await row(OPS2)).toMatchObject({ business_id: null, status: 'free', agent_app_id: null });
    // The operator is told to make more agents.
    const finding = (await collectAlertFindings(live())).find((f) => f.type === 'receptionist_agents_low');
    expect(finding).toMatchObject({ count: 0 });
    expect(finding!.text).toContain('SARVAM_RECEPTIONIST_AGENTS');
  });

  it('a Sarvam failure gives the number and its agent back', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => {});
    vi.spyOn(globalThis, 'fetch').mockImplementation(async () => new Response('nope', { status: 422 }));
    const withC = live({ SARVAM_RECEPTIONIST_AGENTS: AGENTS_ABC });
    expect((await view('biz_pool_late', withC)).numbers_free).toEqual([OPS2]);
    const res = await rent('biz_pool_late', OPS2, withC);
    expect(res.status).toBe(502);
    expect(await row(OPS2)).toEqual({ business_id: null, status: 'free', source: 'ops', agent_app_id: null, agent_version: null });
    expect((await freeReceptionistAgents(withC)).map((a) => a.appId)).toEqual(['Pool-C']);
  });

  it('two rentals at once never share an agent; the database refuses a second holder', async () => {
    const withCD = live({ SARVAM_RECEPTIONIST_AGENTS: AGENTS_ABCD });
    expect((await ops({ key: OPS_KEY, action: 'add', number: OPS4 }, withCD)).status).toBe(200);
    sarvamSpy();
    const [a, b] = await Promise.all([
      rentNumber(withCD, 'biz_pool_late', OPS2, 'https://api.example'),
      rentNumber(withCD, 'biz_pool_race', OPS4, 'https://api.example'),
    ]);
    expect(a.ok && b.ok).toBe(true);
    const held = [(await row(OPS2))!.agent_app_id, (await row(OPS4))!.agent_app_id].sort();
    expect(held).toEqual(['Pool-C', 'Pool-D']);
    await expect(env.DB.prepare("UPDATE business_numbers SET agent_app_id = 'Pool-A' WHERE phone = ?").bind(OPS2).run())
      .rejects.toThrow(/UNIQUE constraint failed.*agent_app_id/);
  });
});

describe('on-start hook of a pool agent', () => {
  it("answers for the business whose number the agent holds, whatever number the body names", async () => {
    const res = await agentHook('Pool-A', tok('Pool-A'), { caller: '+919830066601', called: CONFIG_NUM });
    expect(res.status).toBe(200);
    const v = await res.json() as any;
    expect(v).toMatchObject({ business_name: 'Sen Tailors', agent_name: 'Riya', can_talk: 'yes' });
    expect(v.greeting).toContain('Sen Tailors');
    // INBOUND_HOOK_SECRET isn't needed for pool agents.
    const noSecret = await agentHook('Pool-B', tok('Pool-B'), undefined, live({ INBOUND_HOOK_SECRET: '' }));
    expect(await noSecret.json()).toMatchObject({ business_name: 'Pick Opticals' });
  });

  it('refuses a wrong token, another agent’s token and an unknown agent', async () => {
    expect((await agentHook('Pool-A', 'wrong')).status).toBe(401);
    expect((await agentHook('Pool-A', '')).status).toBe(401);
    expect((await agentHook('Pool-A', tok('Pool-B'))).status).toBe(401);
    expect((await agentHook('Pool-Z', tok('Pool-Z'))).status).toBe(401);
  });

  it('an agent holding no number still answers with a neutral greeting that says it is an AI', async () => {
    const res = await agentHook('Pool-E', tok('Pool-E'), undefined, live({ SARVAM_RECEPTIONIST_AGENTS: AGENTS_ABCDE }));
    expect(res.status).toBe(200);
    const v = await res.json() as any;
    expect(v).toMatchObject({ business_name: '', caller_known: 'no', can_talk: 'yes' });
    expect(v.greeting).toContain('AI assistant');
  });

  it('the per-number token and the bearer secret still work', async () => {
    const t = await inboundHookToken(HOOK_SECRET, CONFIG_NUM);
    expect(await (await hook(`number=${encodeURIComponent(CONFIG_NUM)}&token=${t}`)).json()).toMatchObject({ business_name: 'Config Bakery' });
    const bearer = await app.fetch(new Request('http://localhost/voice/inbound/start', {
      method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${HOOK_SECRET}` },
      body: JSON.stringify({ called: CONFIG_NUM }),
    }), live());
    expect(await bearer.json()).toMatchObject({ business_name: 'Config Bakery' });
  });
});

describe('when the webhook never comes', () => {
  it("the cron also reads the calls of each active number's pool agent", async () => {
    const asked: string[] = [];
    vi.spyOn(globalThis, 'fetch').mockImplementation(async (u: any) => {
      const url = String(u);
      asked.push(url);
      if (!url.includes('/api/analytics/v1/')) return new Response('{}', { status: 200 });
      const items = url.includes('/Pool-C/') || url.includes('/Pool-D/') ? [{
        interaction_id: '20261020/pool-sync-1', user_contact: '+919830066699', bot_contact_identifier: OPS2,
        duration_in_seconds: 30, start_datetime: analyticsTime(0), end_datetime: analyticsTime(30),
        agent_variables: { lead_score: 60, intent: 'interested', summary: 'Asked about bouquets.', caller_name: 'Rina' },
        translate_transcript: [{ role: 'user', text: 'Bouquets?' }],
      }, {
        // An hour old: answered for whoever had the number before this business rented it.
        interaction_id: '20261020/pool-sync-old', user_contact: '+919830066698', bot_contact_identifier: OPS2,
        duration_in_seconds: 20, start_datetime: analyticsTime(-3600), end_datetime: analyticsTime(-3580),
        agent_variables: { summary: 'Asked for the previous shop.', caller_name: 'Old Caller' },
      }] : [];
      return new Response(JSON.stringify({ items }), { status: 200 });
    });
    const withCD = live({ SARVAM_RECEPTIONIST_AGENTS: AGENTS_ABCD });
    expect(await syncInboundCalls(withCD)).toBe(1);
    const apps = asked.filter((u) => u.includes('/api/analytics/v1/')).map((u) => new URL(u).pathname.split('/')[6]).sort();
    expect(apps).toEqual(['Config-Agent', 'Pool-A', 'Pool-B', 'Pool-C', 'Pool-D']);
    const call = await env.DB.prepare("SELECT business_id, direction FROM calls WHERE interaction_id = '20261020/pool-sync-1'").first<any>();
    expect(call).toEqual({ business_id: 'biz_pool_late', direction: 'inbound' });
    expect(await env.DB.prepare("SELECT id FROM calls WHERE interaction_id = '20261020/pool-sync-old'").first()).toBeNull();
  });
});

describe('a number rented again never gets the calls of its previous business', () => {
  const post = async (startedAt: string, interactionId: string) => app.fetch(new Request(
    `http://localhost/webhooks/sarvam-inbound?number=${encodeURIComponent(OPS4)}&token=${await inboundWebhookToken(env.SARVAM_WEBHOOK_SECRET!, OPS4)}`,
    {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        interaction_id: interactionId, user_phone_number: '+919830066677', agent_phone_number: OPS4, duration: 25,
        start_datetime: startedAt, output_agent_variables: { summary: 'Wanted a test drive.', caller_name: 'Kabir' },
      }),
    },
  ), env);

  it('a late webhook for a call before the rental is acknowledged and recorded nowhere', async () => {
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
    const old = await post(new Date(Date.now() - 3600_000).toISOString(), '20261020/late-old');
    expect(old.status).toBe(200);
    expect(await old.json()).toEqual({ success: true, ignored: true, reason: 'before_assignment' });
    expect(warn.mock.calls.some((c) => String(c[0]).includes('inbound_call_before_assignment'))).toBe(true);
    expect(await env.DB.prepare("SELECT id FROM calls WHERE interaction_id = '20261020/late-old'").first()).toBeNull();
    expect(await env.DB.prepare("SELECT id FROM leads WHERE phone = '919830066677'").first()).toBeNull();

    const fresh = await post(new Date().toISOString(), '20261020/late-new');
    expect(fresh.status).toBe(200);
    const call = await env.DB.prepare("SELECT business_id FROM calls WHERE interaction_id = '20261020/late-new'").first<any>();
    expect(call?.business_id).toBe('biz_pool_race');
  });

  it('only a known start before the known rental time counts', () => {
    expect(startedBeforeAssignment('2026-10-20T10:00:00', '2026-10-20 10:00:01')).toBe(true);
    expect(startedBeforeAssignment('2026-10-20T10:00:01Z', '2026-10-20 10:00:01')).toBe(false);
    expect(startedBeforeAssignment('2026-10-20T15:30:00+05:30', '2026-10-20 10:00:01')).toBe(true);
    expect(startedBeforeAssignment(undefined, '2026-10-20 10:00:01')).toBe(false);
    expect(startedBeforeAssignment('garbage', '2026-10-20 10:00:01')).toBe(false);
    expect(startedBeforeAssignment('2026-10-20T10:00:00Z', null)).toBe(false);
  });
});

describe('the pool agent follows the number', () => {
  it('stays while the number is held and is freed with it', async () => {
    await env.DB.prepare("UPDATE usage SET plan_status = 'past_due' WHERE business_id = 'biz_pool_wait'").run();
    sarvamSpy();
    await runBusinessNumberCron(live());
    expect(await row(OPS1)).toMatchObject({ status: 'held', business_id: 'biz_pool_wait', agent_app_id: 'Pool-A' });
    // Its deployment is paused, but a call that still gets through hears the business, taking a message.
    expect(await (await agentHook('Pool-A')).json()).toMatchObject({ business_name: 'Sen Tailors', can_talk: 'no' });
    expect((await freeReceptionistAgents(live())).map((a) => a.appId)).toEqual([]);

    const later = new Date(Date.now() + (NUMBER_HOLD_DAYS + 1) * 86400_000);
    expect((await runBusinessNumberCron(live(), later)).released).toBe(1);
    expect(await row(OPS1)).toEqual({ business_id: null, status: 'free', source: 'ops', agent_app_id: null, agent_version: null });
    expect((await freeReceptionistAgents(live())).map((a) => a.appId)).toEqual(['Pool-A']);
    expect(await (await agentHook('Pool-A')).json()).toMatchObject({ business_name: '' });
  });

  it('remove takes only a free number added on the ops page', async () => {
    for (const [number, text] of [
      [OPS3, 'only a free number can be removed'],
      [CONFIG_NUM, 'remove it there'],
      ['+917971459999', 'not in the pool'],
      ['', 'Enter the number to remove'],
    ]) {
      const res = await ops({ key: OPS_KEY, action: 'remove', number });
      expect(res.status).toBe(400);
      expect(await res.text()).toContain(text);
    }
    const res = await ops({ key: OPS_KEY, action: 'remove', number: OPS1 });
    expect(res.status).toBe(200);
    expect(await res.text()).toContain('Removed +91 79714 50011;');
    expect(await row(OPS1)).toBeNull();
  });

  it('account deletion keeps the agent until the cron deletes the deployment, then frees it', async () => {
    sarvamSpy();
    const del = await app.fetch(authed('biz_pool_pick', '/auth/account', { method: 'DELETE' }), live());
    expect(del.status).toBe(200);
    expect(await row(OPS3)).toMatchObject({ business_id: null, status: 'held', agent_app_id: 'Pool-B' });
    expect(await (await agentHook('Pool-B')).json()).toMatchObject({ business_name: '' });
    expect((await freeReceptionistAgents(live())).map((a) => a.appId)).toEqual(['Pool-A']);

    vi.restoreAllMocks();
    const calls = sarvamSpy();
    expect((await runBusinessNumberCron(live())).released).toBe(1);
    expect(calls).toEqual([expect.objectContaining({ method: 'DELETE' })]);
    expect(await row(OPS3)).toMatchObject({ status: 'free', agent_app_id: null });
    expect((await freeReceptionistAgents(live())).map((a) => a.appId)).toEqual(['Pool-A', 'Pool-B']);
  });
});

describe('receptionist pool alert', () => {
  it('fires once a day while one agent or none is free, and not without a pool', async () => {
    const findings = async (agents: string) =>
      (await collectAlertFindings(live({ SARVAM_RECEPTIONIST_AGENTS: agents }))).filter((f) => f.type === 'receptionist_agents_low');
    expect(await findings('')).toEqual([]);
    expect(await findings(AGENTS_ABCD)).toEqual([]); // A and B free
    const lone = AGENTS_ABCD.split(',').filter((e) => !e.startsWith('Pool-B:')).join(',');
    expect(await findings(lone)).toEqual([expect.objectContaining({ count: 1 })]);

    const err = vi.spyOn(console, 'error').mockImplementation(() => {});
    const e = live({ SARVAM_RECEPTIONIST_AGENTS: lone, ALERT_WEBHOOK_URL: '' });
    expect((await runAlertChecks(e)).map((f) => f.type)).toContain('receptionist_agents_low');
    expect((await runAlertChecks(e)).map((f) => f.type)).not.toContain('receptionist_agents_low');
    expect(err.mock.calls.some((c) => String(c[0]).includes('receptionist_agents_low'))).toBe(true);
  });
});
