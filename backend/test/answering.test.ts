import { describe, it, expect, beforeAll, afterEach, vi } from 'vitest';
import { env } from 'cloudflare:test';
import { migrateTestDb } from './setup-db';
import app from '../src/index';
import { signJWT } from '../src/auth';
import { dialSarvam } from '../src/services/campaign_queue';
import {
  callerIdFor, e164, inboundHookToken, inboundWebhookToken, poolEntries, poolNumbers, restoreNumberIfEntitled, runBusinessNumberCron,
  NUMBER_HOLD_DAYS,
} from '../src/services/business_numbers';
import { collectAlertFindings } from '../src/services/alerts';
import { inboundGreeting } from '../src/services/disclosure';

const jwtSecret = 'test-jwt-signing-secret-key-32chars-min-length';
const bizId = 'biz_answer';
const otherBiz = 'biz_answer_other';
const trialBiz = 'biz_answer_trial';
const HOOK_SECRET = 'hook-secret-for-tests-0123456789';
let token: string;
let otherToken: string;
let trialToken: string;

/** Live (non-mock) Sarvam config with a three-number pool; fetch is stubbed per test. */
const live = (extra: Record<string, unknown> = {}) => ({
  ...env,
  SARVAM_API_KEY: 'live-key', SARVAM_ORG_ID: 'org', SARVAM_WORKSPACE_ID: 'ws', SARVAM_CONNECTION_ID: 'conn',
  SARVAM_ADMISSIONS_APP_ID: 'outbound-agent', SARVAM_INBOUND_APP_ID: 'CallPilot-Receptionist', SARVAM_INBOUND_APP_VERSION: '1',
  SARVAM_BUSINESS_NUMBERS: '+917971440001, 07971440002, +917971440003', INBOUND_HOOK_SECRET: HOOK_SECRET,
  PUBLIC_API_BASE_URL: 'https://api.example',
  ...extra,
}) as any;

const authed = (path: string, init: RequestInit = {}, t = token) => new Request(`http://localhost${path}`, {
  ...init, headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${t}` },
});

/** Records Sarvam API calls; answers deployments with an id and dials with an attempt id. */
function sarvamSpy() {
  const calls: { url: string; method: string; body: any }[] = [];
  vi.spyOn(globalThis, 'fetch').mockImplementation(async (u: any, init: any) => {
    calls.push({ url: String(u), method: init?.method ?? 'GET', body: init?.body ? JSON.parse(init.body) : null });
    return new Response(JSON.stringify({ deployment_id: `dep_${calls.length}`, attempt_id: `att_${calls.length}` }), { status: 200 });
  });
  return calls;
}

async function seedBusiness(id: string, name: string, plan: 'growth' | 'starter' | 'trial', phone: string) {
  await env.DB.batch([
    env.DB.prepare("INSERT OR REPLACE INTO businesses (id, name, category) VALUES (?, ?, 'education')").bind(id, name),
    env.DB.prepare('INSERT OR REPLACE INTO users (id, phone, business_id) VALUES (?, ?, ?)').bind(`usr_${id}`, phone, id),
    env.DB.prepare(
      `INSERT OR REPLACE INTO agents (id, business_id, name, role, status, calling_hours_start, calling_hours_end, voice, languages)
       VALUES (?, ?, 'Riya', 'Admissions Assistant', 'active', 0, 24, 'Warm · Female', '["Bengali","English"]')`
    ).bind(`agt_${id}`, id),
    env.DB.prepare(
      `INSERT OR REPLACE INTO usage (id, business_id, plan_id, plan_status, included_minutes, minutes_used, current_period_end)
       VALUES (?, ?, ?, ?, 2000, 0, datetime('now', '+20 days'))`
    ).bind(`usg_${id}`, id, plan, plan === 'trial' ? 'trial' : 'active'),
  ]);
  return signJWT({ sub: `usr_${id}`, phone, business_id: id, type: 'access' }, jwtSecret, 3600);
}

beforeAll(async () => {
  await migrateTestDb();
  token = await seedBusiness(bizId, 'Roy Coaching', 'growth', '919830044444');
  otherToken = await seedBusiness(otherBiz, 'Other Shop', 'starter', '919830044445');
  trialToken = await seedBusiness(trialBiz, 'Small Shop', 'trial', '919830044446');
  await env.DB.prepare(
    `INSERT OR REPLACE INTO leads (id, business_id, name, phone, status, consent, interest)
     VALUES ('lead_answer_known', ?, 'Mitali Sen', '919830044401', 'called', 'unknown', 'WBJEE')`
  ).bind(bizId).run();
});

afterEach(() => vi.restoreAllMocks());

describe('numbers and greetings', () => {
  it('normalises numbers to E.164 and reads the pool', () => {
    expect(e164('07971440002')).toBe('+917971440002');
    expect(e164('9830044401')).toBe('+919830044401');
    expect(e164('+91 79714 40001')).toBe('+917971440001');
    expect(e164('abc')).toBeNull();
    expect(poolNumbers(live())).toEqual(['+917971440001', '+917971440002', '+917971440003']);
  });

  it('greets as an AI either way; only missed calls say the team is busy', () => {
    const missed = inboundGreeting('en', { agent: 'Riya', business: 'Roy Coaching' }, 'missed');
    const all = inboundGreeting('en', { agent: 'Riya', business: 'Roy Coaching' }, 'all');
    for (const g of [missed, all]) {
      expect(g).toContain("you've reached Roy Coaching");
      expect(g).toContain('an AI assistant');
      expect(g).toContain('may be recorded');
    }
    expect(missed).toContain("can't come to the phone");
    expect(all).not.toContain("can't come to the phone");
  });
});

describe('renting a business number', () => {
  it('comes with every paid plan: a trial business sees no numbers and cannot rent one', async () => {
    const view = await (await app.fetch(authed('/business-number', {}, trialToken), live())).json() as any;
    expect(view).toMatchObject({ available: true, entitled: false, number: null, numbers_free: [], hold_days: NUMBER_HOLD_DAYS });
    const res = await app.fetch(authed('/business-number', { method: 'POST', body: JSON.stringify({ phone: '+917971440001' }) }, trialToken), live());
    expect(res.status).toBe(402);
    expect((await res.json() as any).code).toBe('not_entitled');
  });

  it('a Growth business picks a specific number; it gets a Sarvam deployment for it', async () => {
    const view = await (await app.fetch(authed('/business-number'), live())).json() as any;
    expect(view).toMatchObject({ entitled: true, number: null });
    expect(view.numbers_free).toEqual(['+917971440001', '+917971440002', '+917971440003']);

    const calls = sarvamSpy();
    // Not the first one: the owner chooses.
    const res = await app.fetch(authed('/business-number', { method: 'POST', body: JSON.stringify({ phone: '07971440002' }) }), live());
    expect(res.status).toBe(200);
    expect((await res.json() as any).number).toMatchObject({ phone: '+917971440002', status: 'active' });
    expect(calls).toHaveLength(1);
    expect(calls[0].url).toBe('https://apps.sarvam.ai/api/app-authoring/v1/orgs/org/workspaces/ws/deployments');
    expect(calls[0].body).toMatchObject({
      app_id: 'CallPilot-Receptionist', app_version: 1,
      connection_configs: [{ connection_id: 'conn', agent_phone_number: '+917971440002', phone_numbers: ['+917971440002'] }],
      webhook_config: { metadata: { business_id: bizId } },
    });
    const tok = await inboundWebhookToken(env.SARVAM_WEBHOOK_SECRET!, '+917971440002');
    expect(calls[0].body.webhook_config.url).toBe(`https://api.example/webhooks/sarvam-inbound?number=%2B917971440002&token=${tok}`);
  });

  it('is chosen once: no second number, and nobody else can take it', async () => {
    const again = await app.fetch(authed('/business-number', { method: 'POST', body: JSON.stringify({ phone: '+917971440003' }) }), live());
    expect(again.status).toBe(409);
    expect((await again.json() as any).code).toBe('already_has_number');

    const taken = await app.fetch(authed('/business-number', { method: 'POST', body: JSON.stringify({ phone: '+917971440002' }) }, otherToken), live());
    expect(taken.status).toBe(409);
    expect((await taken.json() as any).code).toBe('number_taken');
    // A number outside the pool can't be rented either.
    const outside = await app.fetch(authed('/business-number', { method: 'POST', body: JSON.stringify({ phone: '+919999999999' }) }, otherToken), live());
    expect((await outside.json() as any).code).toBe('number_taken');

    const otherView = await (await app.fetch(authed('/business-number', {}, otherToken), live())).json() as any;
    expect(otherView.entitled).toBe(true); // Starter is a paid plan: it gets one too
    expect(otherView.numbers_free).toEqual(['+917971440001', '+917971440003']);
  });

  it('a Sarvam failure gives the number back', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => {});
    vi.spyOn(globalThis, 'fetch').mockImplementation(async () => new Response('nope', { status: 422 }));
    const res = await app.fetch(authed('/business-number', { method: 'POST', body: JSON.stringify({ phone: '+917971440001' }) }, otherToken), live());
    expect(res.status).toBe(502);
    const otherView = await (await app.fetch(authed('/business-number', {}, otherToken), live())).json() as any;
    expect(otherView.number).toBeNull();
    expect(otherView.numbers_free).toContain('+917971440001');
  });

  it('every AI call of the business goes out from its number; others use the shared pool', async () => {
    expect(await callerIdFor(env.DB, bizId)).toBe('+917971440002');
    expect(await callerIdFor(env.DB, trialBiz)).toBeNull();
    const calls = sarvamSpy();
    await dialSarvam(live({ SARVAM_AGENT_PHONE_NUMBERS: '+917971443028' }), {
      callId: 'c1', phone: '919830000001', agentVariables: {}, callerId: await callerIdFor(env.DB, bizId),
    });
    await dialSarvam(live({ SARVAM_AGENT_PHONE_NUMBERS: '+917971443028' }), {
      callId: 'c2', phone: '919830000001', agentVariables: {}, callerId: null,
    });
    expect(calls.map((c) => c.body.app_config.connection_config.agent_phone_number)).toEqual(['+917971440002', '+917971443028']);
  });
});

describe("who answers: forwarding the owner's phone to the number", () => {
  it('needs a business number', async () => {
    const res = await app.fetch(authed('/agent/answering', { method: 'POST', body: JSON.stringify({ enabled: true, mode: 'all' }) }, trialToken), live());
    expect(res.status).toBe(409);
    expect((await res.json() as any).code).toBe('no_business_number');
    expect(await (await app.fetch(authed('/agent/answering', {}, trialToken), live())).json())
      .toMatchObject({ has_number: false, enabled: false, phone: null });
  });

  it('remembers the choice; the number stays live whatever is chosen', async () => {
    const calls = sarvamSpy();
    const all = await app.fetch(authed('/agent/answering', { method: 'POST', body: JSON.stringify({ enabled: true, mode: 'all' }) }), live());
    expect(await all.json()).toEqual({ available: true, has_number: true, enabled: true, phone: '+917971440002', mode: 'all' });
    const off = await app.fetch(authed('/agent/answering', { method: 'POST', body: JSON.stringify({ enabled: false }) }), live());
    expect(await off.json()).toMatchObject({ has_number: true, enabled: false, phone: '+917971440002' });
    // Customers calling the number back still reach the AI: nothing is paused at Sarvam.
    expect(calls).toHaveLength(0);
    await app.fetch(authed('/agent/answering', { method: 'POST', body: JSON.stringify({ enabled: true, mode: 'all' }) }), live());
  });
});

describe('the number follows the plan', () => {
  it('a lapsed plan holds the number, paying again brings it back, and it is released after the hold', async () => {
    await env.DB.prepare("UPDATE usage SET plan_status = 'past_due' WHERE business_id = ?").bind(bizId).run();
    let calls = sarvamSpy();
    expect((await runBusinessNumberCron(live())).held).toBe(1);
    expect(calls).toEqual([expect.objectContaining({ method: 'PUT', body: { action: 'pause' } })]);
    let view = await (await app.fetch(authed('/business-number'), live())).json() as any;
    expect(view.number).toMatchObject({ phone: '+917971440002', status: 'held' });
    expect(await callerIdFor(env.DB, bizId)).toBeNull(); // calls go out from the shared pool meanwhile
    // Nobody else can rent it while it is held.
    const taken = await app.fetch(authed('/business-number', { method: 'POST', body: JSON.stringify({ phone: '+917971440002' }) }, otherToken), live());
    expect((await taken.json() as any).code).toBe('number_taken');

    // Paying again: the same number comes back.
    vi.restoreAllMocks();
    calls = sarvamSpy();
    await env.DB.prepare("UPDATE usage SET plan_status = 'active' WHERE business_id = ?").bind(bizId).run();
    expect(await restoreNumberIfEntitled(live(), bizId)).toBe(true);
    expect(calls).toEqual([expect.objectContaining({ method: 'PUT', body: { action: 'resume' } })]);
    expect(await callerIdFor(env.DB, bizId)).toBe('+917971440002');

    // Lapsed again and the hold ran out: back to the pool, deployment deleted.
    await env.DB.prepare("UPDATE usage SET plan_status = 'past_due' WHERE business_id = ?").bind(bizId).run();
    await runBusinessNumberCron(live());
    vi.restoreAllMocks();
    calls = sarvamSpy();
    const later = new Date(Date.now() + (NUMBER_HOLD_DAYS + 1) * 86400_000);
    expect((await runBusinessNumberCron(live(), later)).released).toBe(1);
    expect(calls).toEqual([expect.objectContaining({ method: 'DELETE' })]);
    view = await (await app.fetch(authed('/business-number'), live())).json() as any;
    expect(view.number).toBeNull();

    // Back on Growth and the same number rented again, for the inbound tests below.
    vi.restoreAllMocks();
    sarvamSpy();
    await env.DB.prepare("UPDATE usage SET plan_status = 'active' WHERE business_id = ?").bind(bizId).run();
    const back = await app.fetch(authed('/business-number', { method: 'POST', body: JSON.stringify({ phone: '+917971440002' }) }), live());
    expect(back.status).toBe(200);
    await app.fetch(authed('/agent/answering', { method: 'POST', body: JSON.stringify({ enabled: true, mode: 'all' }) }), live());
  });
});

describe('on-start hook', () => {
  const hook = (body: unknown, auth = HOOK_SECRET) => app.fetch(new Request('http://localhost/voice/inbound/start', {
    method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${auth}` }, body: JSON.stringify(body),
  }), live());

  it('needs the hook secret', async () => {
    expect((await hook({ called: '+917971440002' }, 'wrong')).status).toBe(401);
  });

  it("returns the business, its AI employee, the known caller and a greeting in the employee's language", async () => {
    const res = await hook({ called: '+917971440002', caller: '+919830044401', interaction_id: 'x' });
    expect(res.status).toBe(200);
    const v = await res.json() as any;
    expect(v).toMatchObject({
      business_name: 'Roy Coaching', agent_name: 'Riya', agent_role: 'Admissions Assistant',
      call_language: 'Bengali', caller_name: 'Mitali Sen', caller_known: 'yes', can_talk: 'yes', answer_mode: 'all',
    });
    expect(v.business_context).toContain('Business: Roy Coaching');
    expect(v.greeting).toContain('Roy Coaching');
    expect(v.greeting).toContain('AI');
  });

  it("each number's agent names its number in the hook URL, signed with that number's token", async () => {
    const at = (query: string) => app.fetch(new Request(`http://localhost/voice/inbound/start?${query}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ caller: '+919830044401', interaction_id: 'y' }),
    }), live());
    const token = await inboundHookToken(HOOK_SECRET, '+917971440002');
    const res = await at(`number=%2B917971440002&token=${token}`);
    expect(await res.json()).toMatchObject({ business_name: 'Roy Coaching', caller_name: 'Mitali Sen' });
    // Another number's token, or none, is refused.
    expect((await at(`number=%2B917971440001&token=${token}`)).status).toBe(401);
    expect((await at('number=%2B917971440002')).status).toBe(401);
  });

  it('an unknown number still gets a neutral greeting that says it is an AI', async () => {
    const v = await (await hook({ called: '+919999999999' })).json() as any;
    expect(v).toMatchObject({ business_name: '', caller_known: 'no', can_talk: 'yes' });
    expect(v.greeting).toContain('AI assistant');
  });
});

describe('after an answered call', () => {
  const payload = (over: Record<string, unknown> = {}) => ({
    app_id: 'CallPilot-Receptionist', app_version: 1, deployment_id: 'dep_x',
    interaction_id: `20261019/${crypto.randomUUID()}`,
    user_phone_number: '+919830055501', agent_phone_number: '+917971440002',
    duration: 84.2, start_datetime: '2026-10-19T08:00:00Z',
    output_agent_variables: {
      caller_name: 'Arjun Das', lead_score: '81', intent: 'interested', temperature: 'hot',
      summary: 'Arjun wants the JEE weekend batch and asked about fees.', next_action: 'send_whatsapp',
      whatsapp_followup_required: 'true', whatsapp_message: 'Hi Arjun, here are the weekend batch details.',
    },
    interaction_transcript: [{ role: 'agent', en_text: 'Hello, you have reached Roy Coaching.' }, { role: 'user', en_text: 'Weekend batch fees?' }],
    ...over,
  });
  const post = async (body: any, number = '+917971440002', tok?: string) => app.fetch(new Request(
    `http://localhost/webhooks/sarvam-inbound?number=${encodeURIComponent(number)}&token=${tok ?? await inboundWebhookToken(env.SARVAM_WEBHOOK_SECRET!, number)}`,
    { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) },
  ), env);

  it('rejects a wrong token or a payload for another number', async () => {
    expect((await post(payload(), '+917971440002', 'deadbeef')).status).toBe(401);
    expect((await post(payload({ agent_phone_number: '+917971440003' }))).status).toBe(400);
  });

  it('creates the lead and an inbound call, scores it, drafts the WhatsApp and tells the owner', async () => {
    const body = payload();
    const res = await post(body);
    expect(res.status).toBe(200);
    const out = await res.json() as any;
    expect(out.direction).toBe('inbound');

    const lead = await env.DB.prepare("SELECT * FROM leads WHERE business_id = ? AND phone = '919830055501'").bind(bizId).first<any>();
    expect(lead).toMatchObject({ name: 'Arjun Das', source: 'inbound_call', consent: 'inquiry', temperature: 'hot', score: 81 });
    expect(lead.last_enquiry_at).toBeTruthy();
    const call = await env.DB.prepare('SELECT * FROM calls WHERE id = ?').bind(out.call_id).first<any>();
    expect(call).toMatchObject({ direction: 'inbound', status: 'completed', score: 81, interaction_id: body.interaction_id });
    expect(call.follow_up_id).toBeTruthy();
    const ev = await env.DB.prepare("SELECT source, consent_value FROM consent_events WHERE lead_id = ?").bind(lead.id).first<any>();
    expect(ev).toEqual({ source: 'inbound_call', consent_value: 'inquiry' });
    const n = await env.DB.prepare("SELECT title, body, route FROM notifications WHERE business_id = ? AND type = 'inbound_call' ORDER BY created_at DESC").bind(bizId).first<any>();
    expect(n).toMatchObject({ title: 'Your AI answered Arjun Das', route: `/calls/${out.call_id}/result` });

    const seen = await (await app.fetch(authed(`/calls/${out.call_id}`), env)).json() as any;
    expect(seen.direction).toBe('inbound');

    // A redelivery records nothing twice.
    const again = await post(body);
    expect((await again.json() as any).call_id).toBe(out.call_id);
    const count = await env.DB.prepare("SELECT COUNT(*) AS n FROM calls WHERE interaction_id = ?").bind(body.interaction_id).first<any>();
    expect(count.n).toBe(1);
    const notes = await env.DB.prepare("SELECT COUNT(*) AS n FROM notifications WHERE business_id = ? AND type = 'inbound_call'").bind(bizId).first<any>();
    expect(notes.n).toBe(1);
  });

  it('a known customer keeps their name and an opt-out on the call is honoured', async () => {
    const res = await post(payload({
      user_phone_number: '+919830044401',
      output_agent_variables: { caller_name: 'Someone Else', intent: 'opt_out', summary: 'Asked not to be called.' },
    }));
    expect(res.status).toBe(200);
    const lead = await env.DB.prepare("SELECT name, consent, do_not_call FROM leads WHERE id = 'lead_answer_known'").first<any>();
    expect(lead).toEqual({ name: 'Mitali Sen', consent: 'opt_out', do_not_call: 1 });
  });

  it('a withheld number is acknowledged without a lead', async () => {
    const res = await post(payload({ user_phone_number: '' }));
    expect(await res.json()).toMatchObject({ ignored: true, reason: 'no_caller' });
  });
});

describe('account deletion', () => {
  it("releases the business's number: its deployment is deleted and the number goes back to the pool", async () => {
    sarvamSpy();
    const rent = await app.fetch(authed('/business-number', { method: 'POST', body: JSON.stringify({ phone: '+917971440003' }) }, otherToken), live());
    expect(rent.status).toBe(200);
    const del = await app.fetch(authed('/auth/account', { method: 'DELETE' }, otherToken), live());
    expect(del.status).toBe(200);
    const row = await env.DB.prepare('SELECT business_id, status FROM business_numbers WHERE phone = ?')
      .bind('+917971440003').first<{ business_id: string | null; status: string }>();
    expect(row).toEqual({ business_id: null, status: 'held' });

    vi.restoreAllMocks();
    const calls = sarvamSpy();
    expect((await runBusinessNumberCron(live())).released).toBe(1);
    expect(calls).toEqual([expect.objectContaining({ method: 'DELETE' })]);
    const view = await (await app.fetch(authed('/business-number'), live())).json() as any;
    expect(view.number.phone).toBe('+917971440002'); // the other business keeps its own
    const free = await env.DB.prepare("SELECT status FROM business_numbers WHERE phone = '+917971440003'").first<{ status: string }>();
    expect(free?.status).toBe('free');
  });
});

describe('numbers on request, each answered by its own agent', () => {
  const reqBiz = 'biz_answer_request';
  let reqToken: string;
  beforeAll(async () => {
    reqToken = await seedBusiness(reqBiz, 'Sen Tailors', 'starter', '919830044447');
  });

  it("reads each number's agent; a number with no agent is not offered", () => {
    const pool = live({ SARVAM_BUSINESS_NUMBERS: '+917971440009=CallPilot-Recep-9:2, 07971440010, junk', SARVAM_INBOUND_APP_ID: '' });
    expect(poolEntries(pool)).toEqual([
      { phone: '+917971440009', agent: { appId: 'CallPilot-Recep-9', version: 2 } },
      { phone: '+917971440010', agent: null },
    ]);
    expect(poolNumbers(pool)).toEqual(['+917971440009']);
    // A bare number falls back to SARVAM_INBOUND_APP_ID.
    expect(poolEntries(live({ SARVAM_BUSINESS_NUMBERS: '07971440010' }))[0].agent)
      .toEqual({ appId: 'CallPilot-Receptionist', version: 1 });
  });

  it('none free: a paying business asks for one, a trial one cannot, and the operator is alerted', async () => {
    const empty = live({ SARVAM_BUSINESS_NUMBERS: '' });
    const view = await (await app.fetch(authed('/business-number', {}, reqToken), empty)).json() as any;
    expect(view).toMatchObject({ available: true, entitled: true, number: null, numbers_free: [], requested: false });

    const asked = await app.fetch(authed('/business-number/request', { method: 'POST' }, reqToken), empty);
    expect(asked.status).toBe(200);
    expect(await asked.json()).toMatchObject({ requested: true, number: null });
    // Asking twice is fine.
    expect((await app.fetch(authed('/business-number/request', { method: 'POST' }, reqToken), empty)).status).toBe(200);
    const trial = await app.fetch(authed('/business-number/request', { method: 'POST' }, trialToken), empty);
    expect(trial.status).toBe(402);

    const findings = await collectAlertFindings(env);
    expect(findings.find((f) => f.type === 'business_numbers_requested')).toMatchObject({ count: 1 });
  });

  it('the next number added goes to them on its own agent, and the owner is told', async () => {
    const calls = sarvamSpy();
    const added = live({ SARVAM_BUSINESS_NUMBERS: '+917971440009=CallPilot-Recep-9:2' });
    expect((await runBusinessNumberCron(added)).assigned).toBe(1);
    expect(calls).toHaveLength(1);
    expect(calls[0].body).toMatchObject({
      app_id: 'CallPilot-Recep-9', app_version: 2,
      connection_configs: [{ agent_phone_number: '+917971440009' }],
      webhook_config: { metadata: { business_id: reqBiz } },
    });
    const view = await (await app.fetch(authed('/business-number', {}, reqToken), added)).json() as any;
    expect(view).toMatchObject({ number: { phone: '+917971440009', status: 'active' }, requested: false });
    const note = await env.DB.prepare("SELECT title, body, route FROM notifications WHERE business_id = ? AND type = 'business_number'")
      .bind(reqBiz).first<{ title: string; body: string; route: string }>();
    expect(note).toEqual({
      title: 'Your business number is ready',
      body: '+91 79714 40009 is yours now. Riya calls customers from it and answers it.',
      route: '/agent/number',
    });
    expect((await collectAlertFindings(env)).find((f) => f.type === 'business_numbers_requested')).toBeUndefined();
  });
});
