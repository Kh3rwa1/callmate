import { describe, it, expect, beforeAll, afterEach, vi } from 'vitest';
import { env } from 'cloudflare:test';
import { migrateTestDb } from './setup-db';
import worker from '../src/index';
import { signJWT } from '../src/auth';
import { processCampaignJob, dialSarvam, sarvamWebhookToken } from '../src/services/campaign_queue';
import {
  buildDisclosureOverrides,
  disclosureEnabled,
  disclosureMessage,
  safeSpokenName,
  DISCLOSURE_NAME_MAX,
} from '../src/services/disclosure';
import {
  addToGlobalDnc,
  canonicalPhone,
  globalDncSecret,
  isInGlobalDnc,
  phoneHash,
} from '../src/services/global_dnc';
import {
  callerIdsAreDltSeries,
  checkCallCompliance,
  warnIfCallerIdsNotDlt,
  PLATFORM_MAX_BUSINESSES_PER_PHONE,
} from '../src/services/compliance';
import {
  recordConsentEvent,
  recordConsentEventsForLeads,
  hashIp,
  clientIp,
  CONSENT_TEXT_VERSIONS,
} from '../src/services/consent';
import {
  retentionDays,
  runRetention,
  runComplianceCron,
  DEFAULT_RETENTION_DAYS,
  MIN_RETENTION_DAYS,
  RETENTION_BATCH,
} from '../src/services/retention';
import { encryptAtRest } from '../src/utils/crypto_data';
import { privacyPage, legalVars } from '../src/routes/legal';
import { stopPage, STOP_RATE_LIMIT } from '../src/routes/stop';

const jwtSecret = 'test-jwt-signing-secret-key-32chars-min-length';
const bizId = 'biz_reg';
const userId = 'usr_reg';
const ownerPhone = '919830055555';
const otherBizId = 'biz_reg_other';
let token: string;
let otherToken: string;

const live = (extra: Record<string, unknown> = {}) => ({
  ...env, SARVAM_API_KEY: 'live-key', SARVAM_ORG_ID: 'o', SARVAM_WORKSPACE_ID: 'w', SARVAM_ADMISSIONS_APP_ID: 'a', ...extra,
}) as any;

/** Captures the body Sarvam would receive; answers 200. */
function captureDial(): { body: () => any; calls: () => number } {
  let body: any = null;
  let n = 0;
  vi.spyOn(globalThis, 'fetch').mockImplementation(async (_u: any, init: any) => {
    n++;
    body = JSON.parse(init.body);
    return new Response(JSON.stringify({ attempt_id: `att_${crypto.randomUUID()}` }), { status: 200 });
  });
  return { body: () => body, calls: () => n };
}

let seq = 0;
function uniquePhone(): string {
  return `91700${String(Date.now() % 100000).padStart(5, '0')}${String(++seq).padStart(2, '0')}`;
}

async function seedLead(opts: { business?: string; phone?: string; consent?: string; name?: string } = {}): Promise<{ id: string; phone: string }> {
  const id = `lead_reg_${++seq}_${crypto.randomUUID().slice(0, 6)}`;
  const phone = opts.phone ?? uniquePhone();
  await env.DB.prepare(
    `INSERT INTO leads (id, business_id, name, phone, interest, status, consent) VALUES (?, ?, ?, ?, 'Admissions', 'new', ?)`
  ).bind(id, opts.business ?? bizId, opts.name ?? 'Asha Rani', phone, opts.consent ?? 'explicit_opt_in').run();
  return { id, phone };
}

async function seedCampaign(leadId: string): Promise<string> {
  const campId = `cmp_reg_${++seq}_${crypto.randomUUID().slice(0, 6)}`;
  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO campaigns (id, business_id, purpose, status, total_leads, calling_hours_start, calling_hours_end)
       VALUES (?, ?, 'reg', 'running', 1, 0, 24)`
    ).bind(campId, bizId),
    env.DB.prepare(`INSERT INTO campaign_leads (campaign_id, lead_id, status) VALUES (?, ?, 'queued')`).bind(campId, leadId),
  ]);
  return campId;
}

async function seedCall(
  business: string, phone: string, opts: { status?: string; interactionId?: string | null; ago?: string; leadId?: string } = {},
): Promise<{ callId: string; leadId: string }> {
  const lead = opts.leadId ? { id: opts.leadId } : await seedLead({ business, phone });
  const id = `call_reg_${crypto.randomUUID().slice(0, 10)}`;
  await env.DB.prepare(
    `INSERT INTO calls (id, business_id, lead_id, lead_name, lead_phone, status, interaction_id, started_at)
     VALUES (?, ?, ?, 'x', ?, ?, ?, datetime('now', ?))`
  ).bind(
    id, business, lead.id, phone, opts.status ?? 'completed',
    opts.interactionId === undefined ? `int_${id}` : opts.interactionId, opts.ago ?? '-1 hours',
  ).run();
  return { callId: id, leadId: lead.id };
}

const req = (path: string, init: RequestInit = {}, t: string = token) => new Request(`http://localhost${path}`, {
  ...init,
  headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${t}`, 'cf-connecting-ip': '203.0.113.7', ...(init.headers ?? {}) },
});

const manualDial = (targetEnv: any, leadId: string) => worker.fetch(req(`/leads/${leadId}/call`, { method: 'POST', body: '{}' }), targetEnv);

const campaignDial = (targetEnv: any, campId: string, leadId: string) => processCampaignJob(targetEnv, {
  campaign_id: campId, lead_id: leadId, business_id: bizId, idempotency_key: 'k', attempts: 0,
});

async function consentEvents(leadId: string) {
  const { results } = await env.DB.prepare('SELECT * FROM consent_events WHERE lead_id = ? ORDER BY rowid').bind(leadId).all<any>();
  return results ?? [];
}

beforeAll(async () => {
  await migrateTestDb();
  const extraBiz = Array.from({ length: PLATFORM_MAX_BUSINESSES_PER_PHONE + 1 }, (_, i) =>
    env.DB.prepare("INSERT OR REPLACE INTO businesses (id, name) VALUES (?, 'Other')").bind(`biz_reg_x${i}`));
  await env.DB.batch([
    env.DB.prepare("INSERT OR REPLACE INTO businesses (id, name) VALUES (?, 'Bright Future Academy')").bind(bizId),
    env.DB.prepare("INSERT OR REPLACE INTO businesses (id, name) VALUES (?, 'Other Biz')").bind(otherBizId),
    ...extraBiz,
    env.DB.prepare('INSERT OR REPLACE INTO users (id, phone, business_id) VALUES (?, ?, ?)').bind(userId, ownerPhone, bizId),
    env.DB.prepare("INSERT OR REPLACE INTO users (id, phone, business_id) VALUES ('usr_reg_other', '919830055556', ?)").bind(otherBizId),
    env.DB.prepare(
      `INSERT OR REPLACE INTO agents (id, business_id, name, role, status, calling_hours_start, calling_hours_end, voice, languages)
       VALUES ('agt_reg', ?, 'Arjun', 'Counselor', 'active', 0, 24, 'Friendly · Male', '["Hindi","English"]')`
    ).bind(bizId),
    env.DB.prepare("INSERT OR REPLACE INTO usage (id, business_id, included_minutes, minutes_used) VALUES ('usg_reg', ?, 100000, 0)").bind(bizId),
  ]);
  token = await signJWT({ sub: userId, phone: ownerPhone, business_id: bizId, type: 'access' }, jwtSecret, 3600);
  otherToken = await signJWT({ sub: 'usr_reg_other', phone: '919830055556', business_id: otherBizId, type: 'access' }, jwtSecret, 3600);
});

afterEach(() => {
  vi.restoreAllMocks();
});

// ---------------------------------------------------------------- 1. disclosure

describe('AI + recording disclosure (app_overrides)', () => {
  it('is off unless SARVAM_DISCLOSURE_OVERRIDE is exactly true', () => {
    expect(disclosureEnabled({})).toBe(false);
    expect(disclosureEnabled({ SARVAM_DISCLOSURE_OVERRIDE: 'false' })).toBe(false);
    expect(disclosureEnabled({ SARVAM_DISCLOSURE_OVERRIDE: '1' })).toBe(false);
    expect(disclosureEnabled({ SARVAM_DISCLOSURE_OVERRIDE: ' TRUE ' })).toBe(true);
    expect(buildDisclosureOverrides({}, { lead: { name: 'Asha' } })).toBeUndefined();
  });

  it('sanitises and trims names', () => {
    expect(safeSpokenName('  {{lead_name}} <b>Asha</b>\n\tRani  ', 'x')).toBe('lead_name bAsha/b Rani');
    expect(safeSpokenName('', 'fallback')).toBe('fallback');
    expect(safeSpokenName(null, 'fb')).toBe('fb');
    expect(safeSpokenName('a\u0000b​c', 'x')).toBe('a b c');
    const long = 'Shree Ganesh Coaching Institute And Career Academy Of Excellence Pvt Ltd';
    const out = safeSpokenName(long, 'x');
    expect(out.length).toBeLessThanOrEqual(DISCLOSURE_NAME_MAX);
    expect(long.startsWith(out)).toBe(true);
    expect(out.endsWith(' ')).toBe(false);
    // No space to cut at: hard cut.
    expect(safeSpokenName('x'.repeat(100), 'y')).toHaveLength(DISCLOSURE_NAME_MAX);
  });

  it('writes the disclosure in English, Hindi and Bengali', () => {
    const names = { lead: 'Asha', agent: 'Arjun', business: 'Bright Future' };
    expect(disclosureMessage('en', names)).toBe(
      'Hello Asha, this is Arjun, an AI assistant calling from Bright Future about your enquiry. '
      + 'This call may be recorded for quality. Is this a good time to talk?');
    const hi = disclosureMessage('hi', names);
    expect(hi).toContain('AI सहायक');
    expect(hi).toContain('रिकॉर्ड');
    expect(hi).toContain('Bright Future');
    const bn = disclosureMessage('bn', names);
    expect(bn).toContain('AI সহকারী');
    expect(bn).toContain('রেকর্ড');
    // Missing names fall back without leaving gaps.
    expect(disclosureMessage('en', {})).toBe(
      'Hello, this is Assistant, an AI assistant calling from our team about your enquiry. '
      + 'This call may be recorded for quality. Is this a good time to talk?');
    expect(disclosureMessage('hi', {})).toMatch(/^नमस्ते, मैं सहायक हूँ, हमारी टीम/);
    expect(disclosureMessage('bn', {})).toMatch(/^নমস্কার, আমি সহকারী, আমাদের টিম/);
  });

  it('picks the language from the employee\'s first language and speaks only the lead\'s first name', () => {
    const on = { SARVAM_DISCLOSURE_OVERRIDE: 'true' };
    const hi = buildDisclosureOverrides(on, { agent: { name: 'Arjun', languages: '["Hindi","English"]' }, business: { name: 'B' }, lead: { name: 'Asha Rani' } });
    expect(hi?.initial_language_name).toBe('Hindi');
    expect(hi?.initial_bot_message).toMatch(/^नमस्ते Asha,/);
    expect(buildDisclosureOverrides(on, { agent: { languages: ['Bengali'] }, lead: { name: 'A' } })?.initial_language_name).toBe('Bengali');
    expect(buildDisclosureOverrides(on, { agent: null, lead: { name: '' } })).toEqual({
      initial_language_name: 'English',
      initial_bot_message: disclosureMessage('en', {}),
    });
  });

  it('manual dial sends no app_overrides by default', async () => {
    const cap = captureDial();
    const res = await manualDial(live(), (await seedLead()).id);
    expect(res.status).toBe(200);
    expect(cap.body().app_config).not.toHaveProperty('app_overrides');
  });

  it('manual and campaign dials send the disclosure when enabled', async () => {
    const e = live({ SARVAM_DISCLOSURE_OVERRIDE: 'true' });
    const cap = captureDial();
    const res = await manualDial(e, (await seedLead({ name: 'Asha <Rani>' })).id);
    expect(res.status).toBe(200);
    const ov = cap.body().app_config.app_overrides;
    expect(ov.initial_language_name).toBe('Hindi');
    expect(ov.initial_bot_message).toContain('Bright Future Academy');
    expect(ov.initial_bot_message).toContain('Arjun');
    expect(ov.initial_bot_message).not.toContain('<');

    const lead = await seedLead();
    const campId = await seedCampaign(lead.id);
    expect((await campaignDial(e, campId, lead.id)).success).toBe(true);
    expect(cap.body().app_config.app_overrides.initial_language_name).toBe('Hindi');
    expect(cap.body().app_config.agent_variables).toBeDefined();
  });

  it('dialSarvam passes app_overrides through untouched', async () => {
    const cap = captureDial();
    const overrides = { initial_bot_message: 'hi', initial_language_name: 'English' as const };
    const r = await dialSarvam(live(), { callId: 'c1', phone: '919800000001', agentVariables: {}, appOverrides: overrides });
    expect(r.ok).toBe(true);
    expect(cap.body().app_config.app_overrides).toEqual(overrides);
  });
});

// ---------------------------------------------------------------- 2. /stop + global DNC

describe('public /stop page and global do-not-call list', () => {
  const post = (body: string, ip = '198.51.100.1', targetEnv: any = env) => worker.fetch(new Request('http://localhost/stop', {
    method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'cf-connecting-ip': ip }, body,
  }), targetEnv);

  it('canonicalises phone numbers like stored leads', () => {
    expect(canonicalPhone('98765 43210')).toBe('919876543210');
    expect(canonicalPhone('+91 98765-43210')).toBe('919876543210');
    expect(canonicalPhone('09876543210')).toBe('919876543210');
    expect(canonicalPhone('0091 9876543210')).toBe('919876543210');
    expect(canonicalPhone('4155550123')).toBe('914155550123');
    expect(canonicalPhone('12345')).toBeNull();
    expect(canonicalPhone(undefined)).toBeNull();
  });

  it('hashes with OTP_PEPPER, falling back to ENCRYPTION_KEY', async () => {
    expect(globalDncSecret({ OTP_PEPPER: 'p'.repeat(20) })).toBe('p'.repeat(20));
    expect(globalDncSecret({ ENCRYPTION_KEY: 'e'.repeat(20) })).toBe('e'.repeat(20));
    expect(globalDncSecret({ OTP_PEPPER: 'short' })).toBeNull();
    const a = await phoneHash('k'.repeat(20), '9876543210');
    expect(a).toBe(await phoneHash('k'.repeat(20), '+91 98765 43210'));
    expect(a).not.toContain('9876543210');
    expect(await phoneHash('k'.repeat(20), '1')).toBeNull();
    expect(await addToGlobalDnc(env.DB, 'k'.repeat(20), 'bad', 'admin')).toBe(false);
    expect(await isInGlobalDnc(env.DB, 'k'.repeat(20), 'bad')).toBe(false);
  });

  it('GET renders a script-free form under a strict CSP', async () => {
    const res = await worker.fetch(new Request('http://localhost/stop'), env);
    expect(res.status).toBe(200);
    const csp = res.headers.get('Content-Security-Policy')!;
    expect(csp).toContain("default-src 'none'");
    expect(csp).toContain("form-action 'self'");
    expect(res.headers.get('Cache-Control')).toBe('no-store');
    const html = await res.text();
    expect(html).toContain('<form method="post" action="/stop">');
    expect(html).not.toMatch(/<script/i);
  });

  it('POST with an invalid number re-shows the form (escaped)', async () => {
    const res = await post('phone=%3Cscript%3E1', '198.51.100.2');
    expect(res.status).toBe(400);
    const html = await res.text();
    expect(html).toContain('valid mobile number');
    expect(html).toContain('&lt;script&gt;1');
    expect(html).not.toContain('<script>1');
    expect((await post('', '198.51.100.2')).status).toBe(400);
  });

  it('POST adds the number and every business stops calling it', async () => {
    const phone = uniquePhone();
    const res = await post(`phone=${encodeURIComponent('+' + phone)}`, '198.51.100.3');
    expect(res.status).toBe(200);
    expect(await res.text()).toContain('Done.');
    expect(await isInGlobalDnc(env.DB, globalDncSecret(env)!, phone)).toBe(true);
    const stored = await env.DB.prepare('SELECT source FROM global_dnc WHERE phone_hash = ?')
      .bind(await phoneHash(globalDncSecret(env)!, phone)).first<any>();
    expect(stored.source).toBe('web');
    // Idempotent
    expect((await post(`phone=${phone}`, '198.51.100.3')).status).toBe(200);

    // Manual dial: blocked.
    const lead = await seedLead({ phone });
    const fetchSpy = vi.spyOn(globalThis, 'fetch');
    const blocked = await manualDial(live(), lead.id);
    expect(blocked.status).toBe(409);
    expect(((await blocked.json()) as any).code).toBe('do_not_call');
    // Campaign dial: skipped as DNC.
    const campId = await seedCampaign(lead.id);
    const r = await campaignDial(live(), campId, lead.id);
    expect(r.reason).toBe('do_not_call');
    const cl = await env.DB.prepare('SELECT status FROM campaign_leads WHERE campaign_id = ?').bind(campId).first<any>();
    expect(cl.status).toBe('skipped_dnc');
    expect(fetchSpy).not.toHaveBeenCalled();
    // Another business with the same number is blocked too.
    const other = await seedLead({ business: otherBizId, phone });
    const c = await checkCallCompliance(env.DB, {
      businessId: otherBizId, leadId: other.id, hoursStart: 0, hoursEnd: 24, skipTraiClamp: true, globalDncSecret: globalDncSecret(env),
    });
    expect(c).toMatchObject({ allowed: false, reason: 'do_not_call' });
  });

  it('fails closed when no hashing key is configured', async () => {
    const lead = await seedLead();
    const c = await checkCallCompliance(env.DB, {
      businessId: bizId, leadId: lead.id, hoursStart: 0, hoursEnd: 24, skipTraiClamp: true, globalDncSecret: null,
    });
    expect(c).toMatchObject({ allowed: false, reason: 'do_not_call' });
    const res = await post('phone=9876543210', '198.51.100.9', { ...env, OTP_PEPPER: '', ENCRYPTION_KEY: '' });
    expect(res.status).toBe(503);
    expect(await res.text()).toContain('temporarily unavailable');
  });

  it('rate limits submissions per IP', async () => {
    const ip = '198.51.100.77';
    for (let i = 0; i < STOP_RATE_LIMIT; i++) expect((await post('phone=1', ip)).status).toBe(400);
    const res = await post('phone=9876543210', ip);
    expect(res.status).toBe(429);
    expect(res.headers.get('Retry-After')).toBe('3600');
    expect(await res.text()).toContain('Too many requests');
    // Bucket keyed by a hash, never the raw IP.
    const raw = await env.DB.prepare('SELECT COUNT(*) AS n FROM rate_limits WHERE bucket LIKE ?').bind(`%${ip}%`).first<any>();
    expect(raw.n).toBe(0);
  });

  it('privacy policy links /stop and states the retention period', () => {
    const html = privacyPage(legalVars({ ...env, RETENTION_DAYS: '90' } as any));
    expect(html).toContain('href="/stop"');
    expect(html).toContain('deleted 90 days after the call');
    expect(stopPage(legalVars(env as any), { kind: 'form' })).toContain('1909');
  });
});

// ---------------------------------------------------------------- 3. platform frequency cap

describe('platform-wide frequency cap', () => {
  it(`blocks a ${PLATFORM_MAX_BUSINESSES_PER_PHONE + 1}th business within 24h`, async () => {
    const phone = uniquePhone();
    const seeded = [];
    for (let i = 0; i < PLATFORM_MAX_BUSINESSES_PER_PHONE; i++) seeded.push(await seedCall(`biz_reg_x${i}`, phone));
    const lead = await seedLead({ phone });
    const fetchSpy = vi.spyOn(globalThis, 'fetch');
    const res = await manualDial(live(), lead.id);
    expect(res.status).toBe(409);
    const body = (await res.json()) as any;
    expect(body.code).toBe('platform_frequency_cap');
    expect(body.message).toContain('several businesses');
    expect(fetchSpy).not.toHaveBeenCalled();

    // One of the businesses that already called may still call (it is one of the 3).
    const c = await checkCallCompliance(env.DB, { businessId: 'biz_reg_x0', leadId: seeded[0].leadId, hoursStart: 0, hoursEnd: 24, skipTraiClamp: true });
    expect(c.allowed).toBe(true);
  });

  it('ignores provider-rejected dials and calls older than 24h', async () => {
    const phone = uniquePhone();
    await seedCall('biz_reg_x0', phone, { status: 'failed', interactionId: null });
    await seedCall('biz_reg_x1', phone, { ago: '-25 hours' });
    await seedCall('biz_reg_x2', phone);
    await seedCall('biz_reg_x3', phone);
    const lead = await seedLead({ phone });
    const c = await checkCallCompliance(env.DB, { businessId: bizId, leadId: lead.id, hoursStart: 0, hoursEnd: 24, skipTraiClamp: true });
    expect(c.allowed).toBe(true);
  });

  it('campaign calls: one per business per number per day, then rescheduled', async () => {
    const lead = await seedLead();
    await seedCall(bizId, lead.phone, { leadId: lead.id });
    const campId = await seedCampaign(lead.id);
    const fetchSpy = vi.spyOn(globalThis, 'fetch');
    const r = await campaignDial(live(), campId, lead.id);
    expect(r).toMatchObject({ success: false, retry: true, reason: 'platform_frequency_cap' });
    const cl = await env.DB.prepare('SELECT status FROM campaign_leads WHERE campaign_id = ?').bind(campId).first<any>();
    expect(cl.status).toBe('rescheduled');
    expect(fetchSpy).not.toHaveBeenCalled();

    // A manual call is not subject to the per-business campaign cap.
    const c = await checkCallCompliance(env.DB, { businessId: bizId, leadId: lead.id, hoursStart: 0, hoursEnd: 24, skipTraiClamp: true });
    expect(c.allowed).toBe(true);
  });
});

// ---------------------------------------------------------------- 4. consent evidence

describe('consent evidence trail', () => {
  it('POST /leads records a manual event with a hashed IP', async () => {
    const res = await worker.fetch(req('/leads', { method: 'POST', body: JSON.stringify({ name: 'Ravi', phone: uniquePhone().slice(2), consent: 'inquiry' }) }), env);
    expect(res.status).toBe(200);
    const lead = (await res.json()) as any;
    const ev = await consentEvents(lead.id);
    expect(ev).toHaveLength(1);
    expect(ev[0]).toMatchObject({ business_id: bizId, consent_value: 'inquiry', source: 'manual', text_version: CONSENT_TEXT_VERSIONS.manual });
    expect(ev[0].ip_hash).toMatch(/^[0-9a-f]{64}$/);
    expect(ev[0].ip_hash).not.toContain('203.0.113.7');
  });

  it('PATCH records consent and do-not-call changes only', async () => {
    const lead = await seedLead({ consent: 'unknown' });
    const patch = (body: any) => worker.fetch(req(`/leads/${lead.id}`, { method: 'PATCH', body: JSON.stringify(body) }), env);
    expect((await patch({ name: 'Renamed' })).status).toBe(200);
    expect(await consentEvents(lead.id)).toHaveLength(0);
    expect((await patch({ consent: 'explicit_opt_in', do_not_call: true })).status).toBe(200);
    expect((await consentEvents(lead.id)).map((e) => e.consent_value)).toEqual(['explicit_opt_in', 'do_not_call']);
    expect((await patch({ do_not_call: false })).status).toBe(200);
    expect((await consentEvents(lead.id)).map((e) => e.consent_value).at(-1)).toBe('do_not_call_removed');
  });

  it('import records one import_attestation event per inserted lead', async () => {
    const existing = await seedLead();
    const fresh = uniquePhone();
    const res = await worker.fetch(req('/leads/import', {
      method: 'POST',
      body: JSON.stringify({ leads: [
        { name: 'New', phone: fresh, consent: 'existing_customer' },
        { name: 'Dup', phone: existing.phone },
      ] }),
    }), env);
    expect(((await res.json()) as any).imported).toBe(1);
    const lead = await env.DB.prepare('SELECT id FROM leads WHERE business_id = ? AND phone = ?').bind(bizId, fresh).first<any>();
    const ev = await consentEvents(lead.id);
    expect(ev).toHaveLength(1);
    expect(ev[0]).toMatchObject({ source: 'import_attestation', consent_value: 'existing_customer', text_version: CONSENT_TEXT_VERSIONS.import });
    expect(await consentEvents(existing.id)).toHaveLength(0);
  });

  it('campaign start with attestation records owner_attested for unknown-consent leads', async () => {
    const unknown = await seedLead({ consent: 'unknown' });
    const known = await seedLead({ consent: 'inquiry' });
    const campId = `cmp_reg_att_${crypto.randomUUID().slice(0, 6)}`;
    await env.DB.batch([
      env.DB.prepare(`INSERT INTO campaigns (id, business_id, purpose, status, total_leads, calling_hours_start, calling_hours_end) VALUES (?, ?, 'att', 'draft', 2, 0, 24)`).bind(campId, bizId),
      env.DB.prepare(`INSERT INTO campaign_leads (campaign_id, lead_id, status) VALUES (?, ?, 'pending')`).bind(campId, unknown.id),
      env.DB.prepare(`INSERT INTO campaign_leads (campaign_id, lead_id, status) VALUES (?, ?, 'pending')`).bind(campId, known.id),
    ]);
    const res = await worker.fetch(req(`/campaigns/${campId}/start`, { method: 'POST', body: JSON.stringify({ consent_attestation: true }) }), { ...env, CAMPAIGN_QUEUE: { sendBatch: async () => {}, send: async () => {} } } as any);
    expect(res.status).toBe(200);
    expect(await consentEvents(unknown.id)).toEqual([expect.objectContaining({
      consent_value: 'owner_attested', source: 'import_attestation', text_version: CONSENT_TEXT_VERSIONS.campaignAttestation,
    })]);
    expect(await consentEvents(known.id)).toHaveLength(0);
  });

  it('in-call opt-out records an in_call_opt_out event and stays per business', async () => {
    const lead = await seedLead();
    const callId = `call_reg_opt_${crypto.randomUUID().slice(0, 6)}`;
    await env.DB.prepare(
      `INSERT INTO calls (id, business_id, lead_id, lead_name, lead_phone, status, interaction_id) VALUES (?, ?, ?, 'x', ?, 'calling', ?)`
    ).bind(callId, bizId, lead.id, lead.phone, `int_${callId}`).run();
    const tok = await sarvamWebhookToken(env.SARVAM_WEBHOOK_SECRET!, callId);
    const res = await worker.fetch(new Request(`http://localhost/webhooks/sarvam?call_id=${callId}&token=${tok}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        status: 'completed', duration_seconds: 42, recording_url: 'https://rec.example/a.mp3',
        transcript: [{ role: 'user', text: "Please don't call me again" }],
      }),
    }), env);
    expect(res.status).toBe(200);
    expect(await consentEvents(lead.id)).toEqual([expect.objectContaining({ consent_value: 'opt_out', source: 'in_call_opt_out' })]);
    expect(await isInGlobalDnc(env.DB, globalDncSecret(env)!, lead.phone)).toBe(false);

    // Recording URL is encrypted at rest and decrypted for the owner.
    const row = await env.DB.prepare('SELECT recording_url FROM calls WHERE id = ?').bind(callId).first<any>();
    expect(row.recording_url).toMatch(/^enc:v1:/);
    const call = (await (await worker.fetch(req(`/calls/${callId}`), env)).json()) as any;
    expect(call.recording_url).toBe('https://rec.example/a.mp3');
  });

  it('GET /leads/:id/consent-history is business scoped and newest first', async () => {
    const lead = await seedLead();
    await recordConsentEvent(env.DB, { businessId: bizId, leadId: lead.id, consentValue: 'inquiry', source: 'form', textVersion: 'form-v1' });
    await recordConsentEvent(env.DB, { businessId: bizId, leadId: lead.id, consentValue: 'opt_out', source: 'webhook', textVersion: 'wh-v1', ipHash: 'h' });
    // Wrong business: nothing written.
    await recordConsentEvent(env.DB, { businessId: otherBizId, leadId: lead.id, consentValue: 'x', source: 'manual', textVersion: 'v' });
    const res = await worker.fetch(req(`/leads/${lead.id}/consent-history`), env);
    expect(res.status).toBe(200);
    const items = ((await res.json()) as any).items;
    expect(items.map((i: any) => i.consent_value)).toEqual(['opt_out', 'inquiry']);
    expect(items[0]).not.toHaveProperty('ip_hash');
    expect((await worker.fetch(req(`/leads/${lead.id}/consent-history`, {}, otherToken), env)).status).toBe(404);
    expect((await worker.fetch(req('/leads/nope/consent-history'), env)).status).toBe(404);
  });

  it('deleting a lead deletes its consent events', async () => {
    const lead = await seedLead();
    await recordConsentEventsForLeads(env.DB, bizId, [lead.id], { source: 'manual', textVersion: 'v' });
    expect(await consentEvents(lead.id)).toHaveLength(1);
    expect((await worker.fetch(req(`/leads/${lead.id}`, { method: 'DELETE' }), env)).status).toBe(200);
    expect(await consentEvents(lead.id)).toHaveLength(0);
  });

  it('hashIp / clientIp helpers', async () => {
    expect(await hashIp(env as any, null)).toBeNull();
    expect(await hashIp({ OTP_PEPPER: '' }, '1.2.3.4')).toBeNull();
    expect(await hashIp(env as any, '1.2.3.4')).toBe(await hashIp(env as any, '1.2.3.4'));
    const fake = (h: Record<string, string>) => ({ req: { header: (n: string) => h[n] } });
    expect(clientIp(fake({ 'x-forwarded-for': '9.9.9.9, 10.0.0.1' }))).toBe('9.9.9.9');
    expect(clientIp(fake({}))).toBeNull();
  });
});

// ---------------------------------------------------------------- 5. retention

describe('retention', () => {
  it('parses RETENTION_DAYS with a safe default and floor', () => {
    expect(retentionDays({})).toBe(DEFAULT_RETENTION_DAYS);
    expect(retentionDays({ RETENTION_DAYS: 'abc' })).toBe(DEFAULT_RETENTION_DAYS);
    expect(retentionDays({ RETENTION_DAYS: '-5' })).toBe(DEFAULT_RETENTION_DAYS);
    expect(retentionDays({ RETENTION_DAYS: '1' })).toBe(MIN_RETENTION_DAYS);
    expect(retentionDays({ RETENTION_DAYS: '90' })).toBe(90);
  });

  it('clears content of old calls only, keeping metadata and score', async () => {
    const lead = await seedLead();
    const ins = (id: string, ago: string) => env.DB.prepare(
      `INSERT INTO calls (id, business_id, lead_id, lead_name, lead_phone, status, duration_seconds, recording_url, transcript, summary, raw_metadata, score, started_at)
       VALUES (?, ?, ?, 'x', ?, 'completed', 61, 'enc:v1:a:b', 'enc:v1:c:d', 'Wants a demo', '{}', 80, datetime('now', ?))`
    ).bind(id, bizId, lead.id, lead.phone, ago).run();
    const oldId = `call_reg_old_${crypto.randomUUID().slice(0, 6)}`;
    const newId = `call_reg_new_${crypto.randomUUID().slice(0, 6)}`;
    await ins(oldId, '-200 days');
    await ins(newId, '-10 days');
    expect(await runRetention(env as any)).toBeGreaterThanOrEqual(1);
    const old = await env.DB.prepare('SELECT * FROM calls WHERE id = ?').bind(oldId).first<any>();
    expect(old).toMatchObject({ transcript: null, recording_url: null, summary: null, raw_metadata: null, score: 80, duration_seconds: 61, status: 'completed' });
    const fresh = await env.DB.prepare('SELECT * FROM calls WHERE id = ?').bind(newId).first<any>();
    expect(fresh.summary).toBe('Wants a demo');
    // Nothing left to clear on a second run; a shorter window clears the newer call.
    expect(await runRetention(env as any)).toBe(0);
    expect(await runRetention({ ...env, RETENTION_DAYS: '7' } as any)).toBe(1);

    // The API still renders a cleared call.
    const call = (await (await worker.fetch(req(`/calls/${oldId}`), env)).json()) as any;
    expect(call.transcript).toEqual({ lines: [] });
    expect(call.recording_url).toBeNull();
  });

  it('works in batches of RETENTION_BATCH', async () => {
    let captured: any[] = [];
    const db = { prepare: () => ({ bind: (...a: any[]) => { captured = a; return { run: async () => ({ meta: { changes: RETENTION_BATCH } }) }; } }) };
    expect(await runRetention({ DB: db as any, RETENTION_DAYS: '30' })).toBe(RETENTION_BATCH);
    expect(captured).toEqual(['-30 days', RETENTION_BATCH]);
  });

  it('reads legacy plaintext recording URLs and encrypted ones', async () => {
    const lead = await seedLead();
    const plainId = `call_reg_plain_${crypto.randomUUID().slice(0, 6)}`;
    const encId = `call_reg_enc_${crypto.randomUUID().slice(0, 6)}`;
    await env.DB.batch([
      env.DB.prepare(`INSERT INTO calls (id, business_id, lead_id, lead_name, lead_phone, status, recording_url) VALUES (?, ?, ?, 'x', ?, 'completed', 'https://legacy/r.mp3')`).bind(plainId, bizId, lead.id, lead.phone),
      env.DB.prepare(`INSERT INTO calls (id, business_id, lead_id, lead_name, lead_phone, status, recording_url) VALUES (?, ?, ?, 'x', ?, 'completed', ?)`)
        .bind(encId, bizId, lead.id, lead.phone, await encryptAtRest('https://new/r.mp3', env.ENCRYPTION_KEY)),
    ]);
    const get = async (id: string) => ((await (await worker.fetch(req(`/calls/${id}`), env)).json()) as any).recording_url;
    expect(await get(plainId)).toBe('https://legacy/r.mp3');
    expect(await get(encId)).toBe('https://new/r.mp3');
  });
});

// ---------------------------------------------------------------- 6. DLT caller IDs

describe('DLT 140/160 caller-ID check', () => {
  it('accepts only +91140 / +91160 numbers', () => {
    expect(callerIdsAreDltSeries({ SARVAM_AGENT_PHONE_NUMBERS: '+911401234567, +91 160 123 4567' })).toBe(true);
    expect(callerIdsAreDltSeries({ SARVAM_AGENT_PHONE_NUMBERS: '+911401234567,+917971442975' })).toBe(false);
    expect(callerIdsAreDltSeries({ SARVAM_AGENT_PHONE_NUMBERS: '911401234567' })).toBe(false);
    expect(callerIdsAreDltSeries({ SARVAM_AGENT_PHONE_NUMBERS: '' })).toBe(false);
    expect(callerIdsAreDltSeries({})).toBe(false);
  });

  it('warns only in production', () => {
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
    expect(warnIfCallerIdsNotDlt({ ENVIRONMENT: 'staging', SARVAM_AGENT_PHONE_NUMBERS: '+917971442975' })).toBe(false);
    expect(warnIfCallerIdsNotDlt({ ENVIRONMENT: 'production', SARVAM_AGENT_PHONE_NUMBERS: '+911401234567' })).toBe(false);
    expect(warn).not.toHaveBeenCalled();
    expect(warnIfCallerIdsNotDlt({ ENVIRONMENT: 'production', SARVAM_AGENT_PHONE_NUMBERS: '+917971442975' })).toBe(true);
    expect(warn).toHaveBeenCalledTimes(1);
    expect(String(warn.mock.calls[0][0])).toContain('caller_ids_not_dlt_series');
  });

  it('cron runs the DLT warning once and retention', async () => {
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
    await runComplianceCron({ ...env, ENVIRONMENT: 'production', SARVAM_AGENT_PHONE_NUMBERS: '+917971442975' } as any);
    expect(warn.mock.calls.filter((c) => String(c[0]).includes('caller_ids_not_dlt_series'))).toHaveLength(1);
  });

  it('scheduled() runs the compliance cron', async () => {
    const waits: Promise<unknown>[] = [];
    await worker.scheduled({} as any, env as any, { waitUntil: (p: Promise<unknown>) => waits.push(p) } as any);
    expect(waits.length).toBe(5); // maintenance, billing renewals, alerts, compliance, daily digest
    await Promise.allSettled(waits);
  });

  it('/health/deep reports caller_ids_dlt_series and the disclosure flag', async () => {
    const probe = (extra: Record<string, unknown>) => worker.fetch(new Request('http://localhost/health/deep', { headers: { 'x-health-key': 'hk' } }),
      { ...env, HEALTH_CHECK_SECRET: 'hk', SARVAM_ORG_ID: 'o', SARVAM_WORKSPACE_ID: 'w', SARVAM_ADMISSIONS_APP_ID: 'a', ...extra } as any);
    const bad = (await (await probe({ SARVAM_AGENT_PHONE_NUMBERS: '+917971442975' })).json()) as any;
    expect(bad.compliance).toEqual({ caller_ids_dlt_series: false, disclosure_override: false });
    const good = (await (await probe({ SARVAM_AGENT_PHONE_NUMBERS: '+911601234567', SARVAM_DISCLOSURE_OVERRIDE: 'true' })).json()) as any;
    expect(good.compliance).toEqual({ caller_ids_dlt_series: true, disclosure_override: true });
  });
});
