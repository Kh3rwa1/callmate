import { describe, it, expect, beforeAll, beforeEach, afterEach, vi } from 'vitest';
import { env } from 'cloudflare:test';
import { migrateTestDb } from './setup-db';
import worker from '../src/index';
import { signJWT } from '../src/auth';
import { processCampaignJob } from '../src/services/campaign_queue';
import {
  allowedAgentVariables,
  buildCallAgentVariables,
  firstLanguageName,
  formatBusinessContext,
  BUSINESS_CONTEXT_MAX_CHARS,
  DEFAULT_AGENT_VARIABLES,
} from '../src/services/call_variables';
import {
  ALERT_THRESHOLDS,
  alertWebhookBody,
  collectAlertFindings,
  recordOpsEvent,
  runAlertChecks,
} from '../src/services/alerts';

const secret = 'test-jwt-signing-secret-key-32chars-min-length';
const bizId = 'biz_ctx_alerts';
const userId = 'usr_ctx_alerts';
const phone = '919830066666';
let token: string;

const DEFAULT_8 = [...DEFAULT_AGENT_VARIABLES].sort();
const live = (extra: Record<string, unknown> = {}) => ({
  ...env, SARVAM_API_KEY: 'live-key', SARVAM_ORG_ID: 'o', SARVAM_WORKSPACE_ID: 'w', SARVAM_ADMISSIONS_APP_ID: 'a', ...extra,
}) as any;

/** Captures the agent_variables Sarvam would receive; answers 200. */
function captureDial(): { vars: () => Record<string, string> } {
  let body: any = null;
  vi.spyOn(globalThis, 'fetch').mockImplementation(async (_u: any, init: any) => {
    body = JSON.parse(init.body);
    return new Response(JSON.stringify({ interaction_id: `int_${crypto.randomUUID()}` }), { status: 200 });
  });
  return { vars: () => body?.app_config?.agent_variables };
}

let seq = 0;
async function seedLead(): Promise<string> {
  const id = `lead_ctx_${++seq}_${Date.now()}`;
  await env.DB.prepare(
    `INSERT INTO leads (id, business_id, name, phone, interest, status, consent) VALUES (?, ?, 'Asha', ?, 'JEE coaching', 'new', 'explicit_opt_in')`
  ).bind(id, bizId, `91983${String(seq).padStart(7, '0')}`).run();
  return id;
}

async function seedCampaignLead(): Promise<{ campId: string; leadId: string }> {
  const campId = `cmp_ctx_${++seq}_${Date.now()}`;
  const leadId = await seedLead();
  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO campaigns (id, business_id, purpose, status, total_leads, calling_hours_start, calling_hours_end)
       VALUES (?, ?, 'ctx', 'running', 1, 0, 24)`
    ).bind(campId, bizId),
    env.DB.prepare(`INSERT INTO campaign_leads (campaign_id, lead_id, status) VALUES (?, ?, 'queued')`).bind(campId, leadId),
  ]);
  return { campId, leadId };
}

async function manualDial(targetEnv: any, leadId: string) {
  return worker.fetch(new Request(`http://localhost/leads/${leadId}/call`, {
    method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: '{}',
  }), targetEnv);
}

const campaignDial = (targetEnv: any, campId: string, leadId: string) => processCampaignJob(targetEnv, {
  campaign_id: campId, lead_id: leadId, business_id: bizId, idempotency_key: 'k', attempts: 0,
});

beforeAll(async () => {
  await migrateTestDb();
  await env.DB.batch([
    env.DB.prepare(
      `INSERT OR REPLACE INTO businesses (id, name, category, address, offerings, pricing, opening_hours, location)
       VALUES (?, 'Bright Future Academy', 'coaching', 'MG Road', '["JEE Mains","NEET"]', 'Rs 40,000 per year', '9am-7pm Mon-Sat', 'Kolkata')`
    ).bind(bizId),
    env.DB.prepare('INSERT OR REPLACE INTO users (id, phone, business_id) VALUES (?, ?, ?)').bind(userId, phone, bizId),
    env.DB.prepare("INSERT OR REPLACE INTO leads (id, business_id, name, phone) VALUES ('lead_alert', ?, 'x', '910000000000')").bind(bizId),
    env.DB.prepare(
      `INSERT OR REPLACE INTO agents (id, business_id, name, role, status, calling_hours_start, calling_hours_end, voice, languages)
       VALUES ('agt_ctx', ?, 'Arjun', 'Counselor', 'active', 0, 24, 'Friendly · Male', '["Hindi","English"]')`
    ).bind(bizId),
    env.DB.prepare("INSERT OR REPLACE INTO usage (id, business_id, included_minutes, minutes_used) VALUES ('usg_ctx', ?, 100000, 0)").bind(bizId),
    env.DB.prepare(
      `INSERT OR REPLACE INTO knowledge_sources (id, business_id, type, title, status, content)
       VALUES ('ks_ctx', ?, 'text', 'Fees', 'ready', 'JEE batch starts June. Free demo class every Saturday.')`
    ).bind(bizId),
  ]);
  token = await signJWT({ sub: userId, phone, business_id: bizId, type: 'access' }, secret, 3600);
});

afterEach(() => {
  vi.restoreAllMocks();
});

describe('agent_variables allow-list', () => {
  it('defaults to exactly the 8 declared variables on a manual dial', async () => {
    const cap = captureDial();
    const res = await manualDial(live(), await seedLead());
    expect(res.status).toBe(200);
    expect(Object.keys(cap.vars()).sort()).toEqual(DEFAULT_8);
    expect(cap.vars()).toMatchObject({ lead_name: 'Asha', business_name: 'Bright Future Academy', agent_name: 'Arjun', interest: 'JEE coaching', campaign_id: '' });
    expect(Object.values(cap.vars()).every((v) => typeof v === 'string')).toBe(true);
  });

  it('defaults to exactly the 8 declared variables on a campaign dial', async () => {
    const cap = captureDial();
    const { campId, leadId } = await seedCampaignLead();
    expect((await campaignDial(live(), campId, leadId)).success).toBe(true);
    expect(Object.keys(cap.vars()).sort()).toEqual(DEFAULT_8);
    expect(cap.vars().campaign_id).toBe(campId);
  });

  it('sends allow-listed extras on both paths', async () => {
    const names = [...DEFAULT_AGENT_VARIABLES, 'speaker', 'gender', 'call_language', 'business_context'];
    const e = live({ SARVAM_AGENT_VARIABLES: names.join(', ') });

    const cap = captureDial();
    expect((await manualDial(e, await seedLead())).status).toBe(200);
    const manual = cap.vars();
    expect(Object.keys(manual).sort()).toEqual([...names].sort());
    expect(manual.gender).toBe('male');
    expect(manual.speaker).toBe('shubh_hi_customer');
    expect(manual.call_language).toBe('Hindi');
    expect(manual.business_context).toContain('Bright Future Academy');
    expect(manual.business_context).toContain('JEE Mains, NEET');
    expect(manual.business_context).toContain('Rs 40,000');
    expect(manual.business_context).toContain('Free demo class');

    const { campId, leadId } = await seedCampaignLead();
    await campaignDial(e, campId, leadId);
    expect(Object.keys(cap.vars()).sort()).toEqual([...names].sort());
  });

  it('ignores unknown names with a warning', () => {
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
    expect(allowedAgentVariables({ SARVAM_AGENT_VARIABLES: 'call_id,bogus, lead_name ,call_id' })).toEqual(['call_id', 'lead_name']);
    expect(warn).toHaveBeenCalledWith(expect.stringContaining('bogus'));
    expect(allowedAgentVariables({ SARVAM_AGENT_VARIABLES: ' ' })).toEqual([...DEFAULT_AGENT_VARIABLES]);
    expect(allowedAgentVariables({})).toEqual([...DEFAULT_AGENT_VARIABLES]);
  });

  it('only builds business_context when allowed, and uses passed knowledge', async () => {
    const prepare = vi.spyOn(env.DB, 'prepare');
    const base = { businessId: bizId, business: { name: 'B' }, agent: null, lead: { id: 'l', name: 'n' }, callId: 'c' };
    await buildCallAgentVariables(env as any, base);
    expect(prepare).not.toHaveBeenCalled();
    const v = await buildCallAgentVariables({ ...env, SARVAM_AGENT_VARIABLES: 'business_context' } as any, { ...base, knowledge: ['Custom fact'] });
    expect(Object.keys(v)).toEqual(['business_context']);
    expect(v.business_context).toContain('Custom fact');
  });

  it('truncates business_context', () => {
    const big = Array.from({ length: 20 }, (_, i) => `Fact ${i} `.repeat(60));
    const ctx = formatBusinessContext({ name: 'X', offerings: JSON.stringify(Array(200).fill('Course')) }, null, big);
    expect(ctx.length).toBeLessThanOrEqual(BUSINESS_CONTEXT_MAX_CHARS);
    expect(ctx.startsWith('Business: X')).toBe(true);
    expect(ctx.endsWith('…')).toBe(true);
  });

  it('call_language is the first language name', () => {
    expect(firstLanguageName('["Bengali","English"]')).toBe('Bengali');
    expect(firstLanguageName(['Hindi'])).toBe('Hindi');
    expect(firstLanguageName(null)).toBe('English');
    expect(firstLanguageName('Tamil')).toBe('Tamil');
  });
});

describe('ops alerts', () => {
  beforeEach(async () => {
    await env.DB.batch([
      env.DB.prepare('DELETE FROM alert_state'),
      env.DB.prepare('DELETE FROM ops_events'),
      env.DB.prepare("DELETE FROM calls WHERE business_id = ?").bind(bizId),
    ]);
  });

  async function insertCall(status: string, reason: string | null, startedAgo = '-5 minutes') {
    const id = `call_al_${++seq}`;
    await env.DB.prepare(
      `INSERT INTO calls (id, business_id, lead_id, lead_name, lead_phone, status, failure_reason, started_at)
       VALUES (?, ?, 'lead_alert', 'x', 'x', ?, ?, datetime('now', ?))`
    ).bind(id, bizId, status, reason, startedAgo).run();
  }

  it('is a no-op when nothing is wrong', async () => {
    const err = vi.spyOn(console, 'error').mockImplementation(() => {});
    const fetchSpy = vi.spyOn(globalThis, 'fetch');
    await insertCall('failed', 'sarvam_http_422: x');
    expect(await runAlertChecks({ ...env, ALERT_WEBHOOK_URL: 'https://hooks.slack.test/x' } as any)).toEqual([]);
    expect(fetchSpy).not.toHaveBeenCalled();
    expect(err).not.toHaveBeenCalled();
  });

  it('alerts on Sarvam dial failures once per hour, to the webhook and the log', async () => {
    for (let i = 0; i < ALERT_THRESHOLDS.sarvam_dial_failures; i++) {
      await insertCall('failed', 'sarvam_http_422: Agent variables gender not found');
    }
    await insertCall('failed', 'other_reason');
    await insertCall('failed', 'sarvam_http_500', '-3 hours'); // outside the window
    const err = vi.spyOn(console, 'error').mockImplementation(() => {});
    const posts: any[] = [];
    vi.spyOn(globalThis, 'fetch').mockImplementation(async (url: any, init: any) => {
      posts.push({ url: String(url), body: JSON.parse(init.body) });
      return new Response('ok');
    });
    const e = { ...env, ALERT_WEBHOOK_URL: 'https://hooks.slack.test/x', ENVIRONMENT: 'staging' } as any;

    const sent = await runAlertChecks(e);
    expect(sent.map((s) => s.type)).toEqual(['sarvam_dial_failures']);
    expect(sent[0].count).toBe(ALERT_THRESHOLDS.sarvam_dial_failures);
    expect(posts).toHaveLength(1);
    expect(posts[0].body.text).toContain('Agent variables gender not found');
    const log = JSON.parse(err.mock.calls.find((c) => String(c[0]).includes('ops_alert'))![0] as string);
    expect(log).toMatchObject({ msg: 'ops_alert', type: 'sarvam_dial_failures', env: 'staging' });

    // Second run within the hour: deduped.
    expect(await runAlertChecks(e)).toEqual([]);
    expect(posts).toHaveLength(1);

    // An hour later it can fire again.
    await env.DB.prepare("UPDATE alert_state SET last_sent_at = datetime('now', '-61 minutes')").run();
    expect((await runAlertChecks(e)).map((s) => s.type)).toEqual(['sarvam_dial_failures']);
  });

  it('logs ops_alert even without a webhook URL', async () => {
    for (let i = 0; i < ALERT_THRESHOLDS.stuck_calls; i++) await insertCall(i ? 'timed_out' : 'calling', null, '-50 minutes');
    const err = vi.spyOn(console, 'error').mockImplementation(() => {});
    const fetchSpy = vi.spyOn(globalThis, 'fetch');
    const sent = await runAlertChecks(env as any);
    expect(sent.map((s) => s.type)).toEqual(['stuck_calls']);
    expect(fetchSpy).not.toHaveBeenCalled();
    expect(err.mock.calls.some((c) => String(c[0]).includes('"msg":"ops_alert"'))).toBe(true);
  });

  it('records dead letters from the DLQ consumer and alerts on them', async () => {
    const ack = vi.fn();
    await worker.queue!({ queue: 'callpilot-campaign-dlq', messages: [{ body: { campaign_id: 'cmp_none', lead_id: 'lead_none', idempotency_key: 'cmp_none:lead_none' }, ack, retry: vi.fn() }] } as any, env as any);
    expect(ack).toHaveBeenCalled();
    const findings = await collectAlertFindings(env);
    expect(findings.map((f) => f.type)).toEqual(['queue_dead_letters']);
    expect(findings[0].text).toContain('cmp_none:lead_none');
  });

  it('records rejected Sarvam webhooks and alerts over the threshold', async () => {
    const res = await worker.fetch(new Request('http://localhost/webhooks/sarvam?call_id=call_x&token=bad', {
      method: 'POST', body: '{}', headers: { 'Content-Type': 'application/json' },
    }), env as any);
    expect(res.status).toBe(401);
    expect((await env.DB.prepare("SELECT COUNT(*) AS n FROM ops_events WHERE kind = 'webhook_auth_failure'").first<any>()).n).toBe(1);
    expect(await collectAlertFindings(env)).toEqual([]);
    for (let i = 1; i < ALERT_THRESHOLDS.webhook_auth_failures; i++) await recordOpsEvent(env.DB, 'webhook_auth_failure', 'x');
    expect((await collectAlertFindings(env)).map((f) => f.type)).toEqual(['webhook_auth_failures']);
  });

  it('uses the body shape each chat service expects', () => {
    expect(alertWebhookBody('https://hooks.slack.com/services/x', 'hi')).toEqual({ text: 'hi' });
    expect(alertWebhookBody('https://chat.googleapis.com/v1/spaces/x/messages', 'hi')).toEqual({ text: 'hi' });
    expect(alertWebhookBody('https://discord.com/api/webhooks/1/x', 'hi')).toEqual({ content: 'hi' });
  });

  it('never throws, even if a webhook post fails', async () => {
    for (let i = 0; i < ALERT_THRESHOLDS.sarvam_dial_failures; i++) await insertCall('failed', 'sarvam_network: timeout');
    vi.spyOn(console, 'error').mockImplementation(() => {});
    vi.spyOn(globalThis, 'fetch').mockRejectedValue(new Error('down'));
    const sent = await runAlertChecks({ ...env, ALERT_WEBHOOK_URL: 'https://hooks.slack.test/x' } as any);
    expect(sent).toHaveLength(1);
  });
});

describe('/health/deep', () => {
  it('reports which Sarvam settings are present and the agent_variables sent', async () => {
    const res = await worker.fetch(new Request('http://localhost/health/deep', { headers: { 'x-health-key': 'hk' } }),
      { ...env, HEALTH_CHECK_SECRET: 'hk', SARVAM_ORG_ID: 'o', SARVAM_WORKSPACE_ID: '' } as any);
    const b = (await res.json()) as any;
    expect(b.checks.d1).toBe(true);
    expect(b.sarvam.SARVAM_ORG_ID).toBe(true);
    expect(b.sarvam.SARVAM_WORKSPACE_ID).toBe(false);
    expect(JSON.stringify(b)).not.toContain('sk_test_mock_key');
    expect(b.agent_variables).toEqual([...DEFAULT_AGENT_VARIABLES]);
  });
});
