import { describe, it, expect, beforeAll, afterEach, vi } from 'vitest';
import { env } from 'cloudflare:test';
import { migrateTestDb } from './setup-db';
import app from '../src/index';
import { signJWT } from '../src/auth';
import { e164, inboundWebhookToken, poolNumbers } from '../src/services/answering';
import { inboundGreeting } from '../src/services/disclosure';

const jwtSecret = 'test-jwt-signing-secret-key-32chars-min-length';
const bizId = 'biz_answer';
const otherBiz = 'biz_answer_other';
const HOOK_SECRET = 'hook-secret-for-tests-0123456789';
let token: string;
let otherToken: string;

/** Live (non-mock) Sarvam config with a two-number pool; fetch is stubbed per test. */
const live = (extra: Record<string, unknown> = {}) => ({
  ...env,
  SARVAM_API_KEY: 'live-key', SARVAM_ORG_ID: 'org', SARVAM_WORKSPACE_ID: 'ws', SARVAM_CONNECTION_ID: 'conn',
  SARVAM_INBOUND_APP_ID: 'CallPilot-Receptionist', SARVAM_INBOUND_APP_VERSION: '1',
  SARVAM_INBOUND_NUMBERS: '+917971440001, 07971440002', INBOUND_HOOK_SECRET: HOOK_SECRET,
  PUBLIC_API_BASE_URL: 'https://api.example',
  ...extra,
}) as any;

const authed = (path: string, init: RequestInit = {}, t = token) => new Request(`http://localhost${path}`, {
  ...init, headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${t}` },
});

beforeAll(async () => {
  await migrateTestDb();
  await env.DB.batch([
    env.DB.prepare("INSERT OR REPLACE INTO businesses (id, name, category) VALUES (?, 'Roy Coaching', 'education')").bind(bizId),
    env.DB.prepare("INSERT OR REPLACE INTO businesses (id, name) VALUES (?, 'Other Shop')").bind(otherBiz),
    env.DB.prepare("INSERT OR REPLACE INTO users (id, phone, business_id) VALUES ('usr_answer', '919830044444', ?)").bind(bizId),
    env.DB.prepare("INSERT OR REPLACE INTO users (id, phone, business_id) VALUES ('usr_answer_o', '919830044445', ?)").bind(otherBiz),
    env.DB.prepare(
      `INSERT OR REPLACE INTO agents (id, business_id, name, role, status, calling_hours_start, calling_hours_end, voice, languages)
       VALUES ('agt_answer', ?, 'Riya', 'Admissions Assistant', 'active', 9, 21, 'Warm · Female', '["Bengali","English"]')`
    ).bind(bizId),
    env.DB.prepare("INSERT OR REPLACE INTO usage (id, business_id, plan_id, plan_status, included_minutes, minutes_used) VALUES ('usg_answer', ?, 'starter', 'active', 800, 0)").bind(bizId),
    env.DB.prepare(
      `INSERT OR REPLACE INTO leads (id, business_id, name, phone, status, consent, interest)
       VALUES ('lead_answer_known', ?, 'Mitali Sen', '919830044401', 'called', 'unknown', 'WBJEE')`
    ).bind(bizId),
  ]);
  token = await signJWT({ sub: 'usr_answer', phone: '919830044444', business_id: bizId, type: 'access' }, jwtSecret, 3600);
  otherToken = await signJWT({ sub: 'usr_answer_o', phone: '919830044445', business_id: otherBiz, type: 'access' }, jwtSecret, 3600);
});

afterEach(() => vi.restoreAllMocks());

describe('numbers', () => {
  it('normalises numbers to E.164 and reads the pool', () => {
    expect(e164('07971440002')).toBe('+917971440002');
    expect(e164('9830044401')).toBe('+919830044401');
    expect(e164('+91 79714 40001')).toBe('+917971440001');
    expect(e164('abc')).toBeNull();
    expect(poolNumbers(live())).toEqual(['+917971440001', '+917971440002']);
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

describe('turning answering on and off', () => {
  it('is unavailable until the agent and numbers are configured', async () => {
    const res = await app.fetch(authed('/agent/answering'), live({ SARVAM_INBOUND_APP_ID: '' }));
    expect(await res.json()).toEqual({ available: false, enabled: false, phone: null, mode: 'missed' });
    const on = await app.fetch(authed('/agent/answering', { method: 'POST', body: JSON.stringify({ enabled: true }) }), live({ SARVAM_INBOUND_APP_ID: '' }));
    expect(on.status).toBe(503);
  });

  it('gives the business a number and a Sarvam deployment; off pauses; on again resumes', async () => {
    const calls: { url: string; body: any; method: string }[] = [];
    vi.spyOn(globalThis, 'fetch').mockImplementation(async (u: any, init: any) => {
      calls.push({ url: String(u), body: init?.body ? JSON.parse(init.body) : null, method: init?.method });
      return new Response(JSON.stringify({ deployment_id: 'dep_123' }), { status: 200 });
    });
    const on = await app.fetch(authed('/agent/answering', { method: 'POST', body: JSON.stringify({ enabled: true }) }), live());
    expect(on.status).toBe(200);
    expect(await on.json()).toEqual({ available: true, enabled: true, phone: '+917971440001', mode: 'missed' });
    expect(calls).toHaveLength(1);
    expect(calls[0].url).toBe('https://apps.sarvam.ai/api/app-authoring/v1/orgs/org/workspaces/ws/deployments');
    expect(calls[0].body).toMatchObject({
      app_id: 'CallPilot-Receptionist', app_version: 1,
      connection_configs: [{ connection_id: 'conn', agent_phone_number: '+917971440001', phone_numbers: ['+917971440001'] }],
      webhook_config: { metadata: { business_id: bizId } },
    });
    const tok = await inboundWebhookToken(env.SARVAM_WEBHOOK_SECRET!, '+917971440001');
    expect(calls[0].body.webhook_config.url).toBe(`https://api.example/webhooks/sarvam-inbound?number=%2B917971440001&token=${tok}`);

    // Turning it on again changes nothing.
    await app.fetch(authed('/agent/answering', { method: 'POST', body: JSON.stringify({ enabled: true }) }), live());
    expect(calls).toHaveLength(1);

    const off = await app.fetch(authed('/agent/answering', { method: 'POST', body: JSON.stringify({ enabled: false }) }), live());
    expect(await off.json()).toEqual({ available: true, enabled: false, phone: '+917971440001', mode: 'missed' });
    expect(calls[1]).toMatchObject({ url: expect.stringContaining('/deployments/dep_123/status'), method: 'PUT', body: { action: 'pause' } });

    // On again, now for every call: resumes the deployment and remembers the choice.
    const all = await app.fetch(authed('/agent/answering', { method: 'POST', body: JSON.stringify({ enabled: true, mode: 'all' }) }), live());
    expect(calls[2]).toMatchObject({ method: 'PUT', body: { action: 'resume' } });
    expect(await all.json()).toMatchObject({ enabled: true, mode: 'all' });
    expect(await (await app.fetch(authed('/agent/answering'), live())).json()).toMatchObject({ mode: 'all' });
    const bad = await app.fetch(authed('/agent/answering', { method: 'POST', body: JSON.stringify({ enabled: true, mode: 'sometimes' }) }), live());
    expect(bad.status).toBe(400);
  });

  it("another business gets the next number, never this one's", async () => {
    vi.spyOn(globalThis, 'fetch').mockImplementation(async () => new Response(JSON.stringify({ deployment_id: 'dep_456' }), { status: 200 }));
    const res = await app.fetch(authed('/agent/answering', { method: 'POST', body: JSON.stringify({ enabled: true }) }, otherToken), live());
    expect((await res.json() as any).phone).toBe('+917971440002');
  });

  it('a Sarvam failure is reported and keeps the number for a retry', async () => {
    await env.DB.prepare("INSERT OR REPLACE INTO businesses (id, name) VALUES ('biz_answer_fail', 'F')").run();
    await env.DB.prepare("INSERT OR REPLACE INTO users (id, phone, business_id) VALUES ('usr_answer_f', '919830044446', 'biz_answer_fail')").run();
    const t = await signJWT({ sub: 'usr_answer_f', phone: '919830044446', business_id: 'biz_answer_fail', type: 'access' }, jwtSecret, 3600);
    vi.spyOn(console, 'error').mockImplementation(() => {});
    vi.spyOn(globalThis, 'fetch').mockImplementation(async () => new Response('nope', { status: 422 }));
    const res = await app.fetch(authed('/agent/answering', { method: 'POST', body: JSON.stringify({ enabled: true }) }, t),
      live({ SARVAM_INBOUND_NUMBERS: '+917971440001,+917971440002,+917971440003' }));
    expect(res.status).toBe(502);
    expect((await res.json() as any).code).toBe('sarvam_failed');
  });
});

describe('on-start hook', () => {
  const hook = (body: unknown, auth = HOOK_SECRET) => app.fetch(new Request('http://localhost/voice/inbound/start', {
    method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${auth}` }, body: JSON.stringify(body),
  }), live());

  it('needs the hook secret', async () => {
    expect((await hook({ called: '+917971440001' }, 'wrong')).status).toBe(401);
  });

  it("returns the business, its AI employee, the known caller and a greeting in the employee's language", async () => {
    const res = await hook({ called: '+917971440001', caller: '+919830044401', interaction_id: 'x' });
    expect(res.status).toBe(200);
    const v = await res.json() as any;
    expect(v).toMatchObject({
      business_name: 'Roy Coaching', agent_name: 'Riya', agent_role: 'Admissions Assistant',
      call_language: 'Bengali', caller_name: 'Mitali Sen', caller_known: 'yes',
    });
    expect(v.business_context).toContain('Business: Roy Coaching');
    expect(v.greeting).toContain('Roy Coaching');
    expect(v.greeting).toContain('AI');
    // Every call goes to the AI (set in the previous block): no "the team can't come to the phone".
    expect(v.answer_mode).toBe('all');
    expect(v.greeting).not.toContain("can't come to the phone");
  });

  it('an unknown number still gets a neutral greeting that says it is an AI', async () => {
    const v = await (await hook({ called: '+919999999999' })).json() as any;
    expect(v).toMatchObject({ business_name: '', caller_known: 'no', can_talk: 'yes' });
    expect(v.greeting).toContain('AI assistant');
  });
});

describe('after an answered call', () => {
  const payload = (over: Record<string, unknown> = {}) => ({
    app_id: 'CallPilot-Receptionist', app_version: 1, deployment_id: 'dep_123',
    interaction_id: `20261019/${crypto.randomUUID()}`,
    user_phone_number: '+919830055501', agent_phone_number: '+917971440001',
    duration: 84.2, start_datetime: '2026-10-19T08:00:00Z',
    output_agent_variables: {
      caller_name: 'Arjun Das', lead_score: '81', intent: 'interested', temperature: 'hot',
      summary: 'Arjun wants the JEE weekend batch and asked about fees.', next_action: 'send_whatsapp',
      whatsapp_followup_required: 'true', whatsapp_message: 'Hi Arjun, here are the weekend batch details.',
    },
    interaction_transcript: [{ role: 'agent', en_text: 'Hello, you have reached Roy Coaching.' }, { role: 'user', en_text: 'Weekend batch fees?' }],
    ...over,
  });
  const post = async (body: any, number = '+917971440001', tok?: string) => app.fetch(new Request(
    `http://localhost/webhooks/sarvam-inbound?number=${encodeURIComponent(number)}&token=${tok ?? await inboundWebhookToken(env.SARVAM_WEBHOOK_SECRET!, number)}`,
    { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) },
  ), env);

  it('rejects a wrong token or a payload for another number', async () => {
    expect((await post(payload(), '+917971440001', 'deadbeef')).status).toBe(401);
    expect((await post(payload({ agent_phone_number: '+917971440002' }))).status).toBe(400);
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

    // The app sees it as an inbound call.
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
