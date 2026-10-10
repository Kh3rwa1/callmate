import { describe, it, expect, beforeAll, afterEach, vi } from 'vitest';
import { env } from 'cloudflare:test';
import { migrateTestDb } from './setup-db';
import app from '../src/index';
import { signJWT } from '../src/auth';
import { randomToken, sha256Hex, formatLeadSource, consentSourceFor, leadSourcePath, type LeadSourceRow } from '../src/services/lead_capture';
import {
  indiaMartTime, mapIndiaMartRecord, mapGoogleAdsLead, mapMetaLead, metaLeadgenIds, indiaMartRecords,
  runIndiaMartPulls, pullIndiaMartSource, readConfig, encryptConfig, verifyMetaSignature, captureExternalLead,
  fetchMetaLead, metaGraphVersion, isIntegrationKind, IntegrationNotConfiguredError, INDIAMART_PULL_URL,
  DEFAULT_META_GRAPH_VERSION,
} from '../src/services/lead_integrations';
import { hmacHex } from '../src/services/plans';
import { CONSENT_TEXT_VERSIONS } from '../src/services/consent';

const SECRET = 'test-jwt-signing-secret-key-32chars-min-length';

describe('Lead integrations: Google Ads, IndiaMART, Meta Lead Ads', () => {
  const biz = 'biz_li_a';
  const bizOther = 'biz_li_b';
  let token: string;
  let tokenOther: string;
  let ip = 0;
  let phoneSeq = 0;

  const nextPhone = () => `+91 97${String(31000000 + ++phoneSeq).padStart(8, '0')}`;
  const digits = (p: string) => `91${p.replace(/\D/g, '').slice(-10)}`;

  function queueEnv(base: any = env) {
    const sent: { body: any; opts?: any }[] = [];
    const e = { ...base, CAMPAIGN_QUEUE: { send: async (body: any, opts?: any) => { sent.push({ body, opts }); }, sendBatch: async () => {} } } as any;
    return { e, sent };
  }

  const authed = (path: string, tok: string, method = 'GET', body?: any, e: any = env) =>
    app.fetch(new Request(`http://localhost${path}`, {
      method,
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${tok}` },
      body: body ? JSON.stringify(body) : undefined,
    }), e);

  const post = (path: string, body: string, headers: Record<string, string> = {}, e: any = env) =>
    app.fetch(new Request(`http://localhost${path}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'cf-connecting-ip': `10.9.${Math.floor(++ip / 250)}.${ip % 250}`, ...headers },
      body,
    }), e);

  async function create(body: any, tok = token, e: any = env) {
    // Stay under the per-kind cap: each test works with the newest source only.
    if (tok === token) {
      await env.DB.prepare("UPDATE lead_sources SET revoked_at = datetime('now') WHERE business_id = ? AND kind = ? AND revoked_at IS NULL")
        .bind(biz, body.kind).run();
    }
    const res = await authed('/lead-sources', tok, 'POST', body, e);
    return { res, body: (await res.json()) as any };
  }

  async function row(id: string): Promise<LeadSourceRow> {
    return (await env.DB.prepare('SELECT * FROM lead_sources WHERE id = ?').bind(id).first()) as any;
  }

  async function leadByPhone(phone: string, businessId = biz) {
    return env.DB.prepare('SELECT * FROM leads WHERE business_id = ? AND phone = ?').bind(businessId, digits(phone)).first<any>();
  }

  /** Routes global fetch by URL; anything else fails loudly. */
  function mockFetch(handler: (url: string) => Response | Promise<Response>) {
    const calls: string[] = [];
    vi.spyOn(globalThis, 'fetch').mockImplementation(async (input: any) => {
      const url = typeof input === 'string' ? input : input.url;
      calls.push(url);
      return handler(url);
    });
    return calls;
  }

  const json = (body: any, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });

  beforeAll(async () => {
    await migrateTestDb();
    await env.DB.batch([
      env.DB.prepare("INSERT OR REPLACE INTO businesses (id, name, category) VALUES (?, 'Sharma Steels', 'manufacturing')").bind(biz),
      env.DB.prepare("INSERT OR REPLACE INTO users (id, phone, business_id) VALUES ('usr_li_a', '919830080001', ?)").bind(biz),
      env.DB.prepare("INSERT OR REPLACE INTO agents (id, business_id, name, role, status, calling_hours_start, calling_hours_end) VALUES ('agt_li_a', ?, 'Maya', 'Sales', 'active', 0, 24)").bind(biz),
      env.DB.prepare("INSERT OR REPLACE INTO usage (id, business_id, plan_name, included_minutes, minutes_used) VALUES ('usg_li_a', ?, 'Founding', 1000, 0)").bind(biz),
      env.DB.prepare("INSERT OR REPLACE INTO businesses (id, name, category) VALUES (?, 'Other', 'retail')").bind(bizOther),
      env.DB.prepare("INSERT OR REPLACE INTO users (id, phone, business_id) VALUES ('usr_li_b', '919830080002', ?)").bind(bizOther),
    ]);
    token = await signJWT({ sub: 'usr_li_a', phone: '919830080001', business_id: biz, type: 'access' }, SECRET, 3600);
    tokenOther = await signJWT({ sub: 'usr_li_b', phone: '919830080002', business_id: bizOther, type: 'access' }, SECRET, 3600);
  });

  afterEach(() => vi.restoreAllMocks());

  // ------------------------------------------------------------ migration + helpers
  describe('schema and helpers', () => {
    it('lead_sources and consent_events accept the new kinds and sources', async () => {
      const id = `lsrc_m_${randomToken(6)}`;
      await env.DB.prepare("INSERT INTO lead_sources (id, business_id, kind, public_slug) VALUES (?, ?, 'meta', ?)").bind(id, biz, randomToken(12)).run();
      await expect(env.DB.prepare("INSERT INTO lead_sources (id, business_id, kind, public_slug) VALUES (?, ?, 'tiktok', ?)").bind(`${id}x`, biz, randomToken(12)).run()).rejects.toThrow();
      await env.DB.prepare("INSERT INTO consent_events (id, business_id, lead_id, consent_value, source, text_version) VALUES (?, ?, 'l', 'explicit_opt_in', 'meta_lead_ads', 'v')").bind(`ce_${id}`, biz).run();
      await expect(env.DB.prepare("INSERT INTO consent_events (id, business_id, lead_id, consent_value, source, text_version) VALUES (?, ?, 'l', 'x', 'carrier_pigeon', 'v')").bind(`ce2_${id}`, biz).run()).rejects.toThrow();
    });

    it('maps kinds to paths, consent sources and text versions', () => {
      expect(leadSourcePath('google_ads', 'abc')).toBe('/hooks/google-ads/abc');
      expect(leadSourcePath('indiamart', 'abc')).toBe('/hooks/indiamart/abc');
      expect(leadSourcePath('meta', 'abc')).toBe('/hooks/meta/abc');
      expect(consentSourceFor('meta')).toBe('meta_lead_ads');
      expect(consentSourceFor('google_ads')).toBe('google_ads');
      expect(CONSENT_TEXT_VERSIONS.google_ads).toBe('google-ads-lead-form-2026-10');
      expect(isIntegrationKind('indiamart')).toBe(true);
      expect(isIntegrationKind('form')).toBe(false);
      const out = formatLeadSource({ id: 'x', kind: 'indiamart', public_slug: 's', auto_call: 1, created_at: 'c', last_cursor: '2026-10-10T05:00:00.000Z', config_encrypted: 'enc:v1:a:b', secret_hash: 'h' }, 'https://api.test/');
      expect(out.url).toBe('https://api.test/hooks/indiamart/s');
      expect((out as any).last_synced_at).toBe('2026-10-10 05:00:00');
      expect(JSON.stringify(out)).not.toMatch(/enc:v1|secret_hash|"h"/);
    });

    it('formats IndiaMART times in IST', () => {
      expect(indiaMartTime(new Date('2022-01-01T03:30:00Z'))).toBe('01-Jan-202209:00:00');
      expect(indiaMartTime(new Date('2026-12-31T20:15:05Z'))).toBe('01-Jan-202701:45:05');
    });

    it('encrypts integration config and fails closed without a key', async () => {
      const enc = await encryptConfig(env as any, { crm_key: 'K123456789' });
      expect(enc.startsWith('enc:v1:')).toBe(true);
      expect(enc).not.toContain('K123456789');
      expect(await readConfig(env as any, { config_encrypted: enc })).toEqual({ crm_key: 'K123456789' });
      expect(await readConfig({ ENCRYPTION_KEY: 'another-key-another-key-another-key' } as any, { config_encrypted: enc })).toBeNull();
      expect(await readConfig(env as any, { config_encrypted: null })).toBeNull();
      expect(await readConfig(env as any, { config_encrypted: 'not json' })).toBeNull();
      await expect(encryptConfig({} as any, { crm_key: 'x' })).rejects.toBeInstanceOf(IntegrationNotConfiguredError);
    });

    it('validates the Graph API version override', () => {
      expect(metaGraphVersion({} as any)).toBe(DEFAULT_META_GRAPH_VERSION);
      expect(metaGraphVersion({ META_GRAPH_API_VERSION: 'v23.0' } as any)).toBe('v23.0');
      expect(metaGraphVersion({ META_GRAPH_API_VERSION: '../evil' } as any)).toBe(DEFAULT_META_GRAPH_VERSION);
    });
  });

  // ------------------------------------------------------------ owner APIs
  describe('owner APIs', () => {
    it('google_ads: returns the webhook URL and key once, stores only the hash', async () => {
      const { res, body } = await create({ kind: 'google_ads' });
      expect(res.status).toBe(201);
      expect(body.kind).toBe('google_ads');
      expect(body.url).toBe(`http://localhost/hooks/google-ads/${body.slug}`);
      expect(body.token).toMatch(/^cpga[A-Za-z0-9]{32}$/);
      expect(body.google_key).toBe(body.token);
      const r = await row(body.id);
      expect(r.secret_hash).toBe(await sha256Hex(body.token));
      expect(r.config_encrypted).toBeNull();
      const list = (await (await authed('/lead-sources', token)).json()) as any;
      const listed = list.items.find((i: any) => i.id === body.id);
      expect(listed.token).toBeUndefined();
      expect(listed.google_key).toBeUndefined();
      expect(listed.last_error).toBeNull();
    });

    it('indiamart: requires crm_key, stores it encrypted, never returns it', async () => {
      const missing = await create({ kind: 'indiamart' });
      expect(missing.res.status).toBe(400);
      expect(missing.body.code).toBe('validation_error');

      const crmKey = 'mRyxEbBs4HfGTfeq4XaN7lmGp1XNnzI=';
      const { res, body } = await create({ kind: 'indiamart', crm_key: ` ${crmKey} `, auto_call: false });
      expect(res.status).toBe(201);
      expect(body.auto_call).toBe(false);
      expect(body.token).toMatch(/^cpim[A-Za-z0-9]{32}$/);
      expect(body.push_url).toBe(`http://localhost/hooks/indiamart/${body.slug}?key=${body.token}`);
      expect(body.last_synced_at).toBeNull();
      expect(JSON.stringify(body)).not.toContain(crmKey);
      const r = await row(body.id);
      expect(r.config_encrypted!.startsWith('enc:v1:')).toBe(true);
      expect(r.config_encrypted).not.toContain(crmKey);
      expect(await readConfig(env as any, r)).toEqual({ crm_key: crmKey });
      const list = await (await authed('/lead-sources', token)).text();
      expect(list).not.toContain(crmKey);
      expect(list).not.toContain('enc:v1');
    });

    it('meta: validates secrets, stores them encrypted, returns the verify token once', async () => {
      const bad = await create({ kind: 'meta', app_secret: 'short', page_access_token: 'x' });
      expect(bad.res.status).toBe(400);
      const nul = await create({ kind: 'meta', app_secret: null, page_access_token: null });
      expect(nul.res.status).toBe(400);

      const appSecret = 'a1b2c3d4e5f60718293a4b5c6d7e8f90';
      const pageToken = 'EAAGm0PX4ZCpsBAKZCZBtestpagetoken1234567890';
      const { res, body } = await create({ kind: 'meta', app_secret: appSecret, page_access_token: pageToken });
      expect(res.status).toBe(201);
      expect(body.url).toBe(`http://localhost/hooks/meta/${body.slug}`);
      expect(body.verify_token).toMatch(/^cpmv[A-Za-z0-9]{32}$/);
      expect(body.token).toBe(body.verify_token);
      expect(JSON.stringify(body)).not.toContain(appSecret);
      expect(JSON.stringify(body)).not.toContain(pageToken);
      const r = await row(body.id);
      expect(r.config_encrypted).not.toContain(pageToken);
      expect(await readConfig(env as any, r)).toEqual({ app_secret: appSecret, page_access_token: pageToken });
      const list = await (await authed('/lead-sources', token)).text();
      expect(list).not.toContain(appSecret);
      expect(list).not.toContain(pageToken);
    });

    it('rejects unknown kinds and answers 503 when encryption is not configured', async () => {
      expect((await create({ kind: 'tiktok' })).res.status).toBe(400);
      const noKey = { ...env, ENCRYPTION_KEY: '' } as any;
      const { res, body } = await create({ kind: 'indiamart', crm_key: 'abcdefghijkl' }, token, noKey);
      expect(res.status).toBe(503);
      expect(body.code).toBe('not_configured');
    });

    it('caps each integration kind separately; PATCH and revoke work for every kind', async () => {
      const capBiz = 'biz_li_cap';
      await env.DB.prepare("INSERT OR REPLACE INTO businesses (id, name) VALUES (?, 'Cap')").bind(capBiz).run();
      await env.DB.prepare("INSERT OR REPLACE INTO users (id, phone, business_id) VALUES ('usr_li_cap', '919830080009', ?)").bind(capBiz).run();
      const tok = await signJWT({ sub: 'usr_li_cap', phone: '919830080009', business_id: capBiz, type: 'access' }, SECRET, 3600);
      for (let i = 0; i < 5; i++) expect((await create({ kind: 'google_ads' }, tok)).res.status).toBe(201);
      expect((await create({ kind: 'google_ads' }, tok)).res.status).toBe(409);
      const meta = await create({ kind: 'meta', app_secret: 'a1b2c3d4e5f60718293a4b5c6d7e8f90', page_access_token: 'EAAGtokentokentokentoken' }, tok);
      expect(meta.res.status).toBe(201);

      const patched = await authed(`/lead-sources/${meta.body.id}`, tok, 'PATCH', { auto_call: false });
      expect(patched.status).toBe(200);
      expect(((await patched.json()) as any).auto_call).toBe(false);
      expect((await authed(`/lead-sources/${meta.body.id}`, tokenOther, 'PATCH', { auto_call: true })).status).toBe(404);
      expect((await authed(`/lead-sources/${meta.body.id}/revoke`, tok, 'POST')).status).toBe(200);
      const verify = await app.fetch(new Request(`http://localhost/hooks/meta/${meta.body.slug}?hub.mode=subscribe&hub.verify_token=${meta.body.token}&hub.challenge=123`), env);
      expect(verify.status).toBe(403);
    });
  });

  // ------------------------------------------------------------ Google Ads
  describe('Google Ads lead form webhook', () => {
    const lead = (key: string, over: any = {}) => ({
      lead_id: `TeSter-${randomToken(10)}`,
      api_version: '1.0',
      form_id: 40000000000,
      campaign_id: 12345678901,
      google_key: key,
      is_test: false,
      gcl_id: 'gclid',
      user_column_data: [
        { column_name: 'Full Name', string_value: 'Ravi Kumar', column_id: 'FULL_NAME' },
        { column_name: 'User Phone', string_value: nextPhone(), column_id: 'PHONE_NUMBER' },
        { column_name: 'User Email', string_value: 'ravi@example.com', column_id: 'EMAIL' },
        { column_name: 'City', string_value: 'Kolkata', column_id: 'CITY' },
        { column_name: 'Which course are you interested in?', string_value: 'NEET 2027', column_id: 'EDUCATION_COURSE' },
        { string_value: 'Evening', column_id: 'PREFERRED_CONTACT_TIME' },
      ],
      ...over,
    });
    const phoneOf = (l: any) => l.user_column_data.find((c: any) => c.column_id === 'PHONE_NUMBER').string_value;

    it('maps columns (name, phone, email, extra answers) and needs a phone', () => {
      const m = mapGoogleAdsLead({
        lead_id: 'L1',
        user_column_data: [
          { column_id: 'FIRST_NAME', string_value: 'Asha' }, { column_id: 'LAST_NAME', string_value: 'Rao' },
          { column_id: 'WORK_PHONE', string_value: '+919830000001' }, { column_id: 'WORK_EMAIL', string_value: 'a@b.co' },
          { column_id: 'POSTAL_CODE', string_value: '700001' }, { column_id: 'SERVICE', string_value: 'Root canal' },
        ],
      })!;
      expect(m.externalId).toBe('L1');
      expect(m.input).toMatchObject({ name: 'Asha Rao', phone: '+919830000001', interest: 'Service: Root canal', attributes: { email: 'a@b.co' } });
      expect(mapGoogleAdsLead({ user_column_data: [{ column_id: 'FULL_NAME', string_value: 'No Phone' }] })).toBeNull();
      expect(mapGoogleAdsLead({ user_column_data: 'nope' as any })).toBeNull();
      expect(mapGoogleAdsLead({ user_column_data: [{ column_id: 'PHONE_NUMBER', string_value: '+919830000002' }] })!.input.name).toBe('Google Ads lead');
    });

    it('rejects a wrong key, an unknown slug and malformed JSON', async () => {
      const { body: src } = await create({ kind: 'google_ads' });
      expect((await post(`/hooks/google-ads/${src.slug}`, JSON.stringify(lead('wrong')))).status).toBe(401);
      expect((await post(`/hooks/google-ads/${src.slug}`, JSON.stringify({ ...lead(src.token), google_key: undefined }))).status).toBe(401);
      expect((await post('/hooks/google-ads/nosuchslug12', JSON.stringify(lead(src.token)))).status).toBe(401);
      expect((await post(`/hooks/google-ads/${src.slug}`, '{not json')).status).toBe(400);
      expect((await post(`/hooks/google-ads/${src.slug}`, 'x'.repeat(70 * 1024))).status).toBe(413);
    });

    it('acknowledges test leads without creating anything or calling', async () => {
      const { body: src } = await create({ kind: 'google_ads' });
      const { e, sent } = queueEnv();
      const l = lead(src.token, { is_test: true });
      const res = await post(`/hooks/google-ads/${src.slug}`, JSON.stringify(l), {}, e);
      expect(res.status).toBe(200);
      expect(await res.json()).toEqual({});
      expect(await leadByPhone(phoneOf(l))).toBeNull();
      expect(sent).toHaveLength(0);
    });

    it('creates an opted-in lead, records consent and enqueues the instant call', async () => {
      const { body: src } = await create({ kind: 'google_ads' });
      const { e, sent } = queueEnv();
      const l = lead(src.token);
      const res = await post(`/hooks/google-ads/${src.slug}`, JSON.stringify(l), {}, e);
      expect(res.status).toBe(200);
      expect(await res.json()).toEqual({});
      const created = await leadByPhone(phoneOf(l));
      expect(created).toMatchObject({ name: 'Ravi Kumar', source: 'google_ads', consent: 'explicit_opt_in', lead_source_id: src.id });
      expect(created.interest).toBe('Which course are you interested in?: NEET 2027; Preferred contact time: Evening');
      expect(JSON.parse(created.attributes)).toMatchObject({ email: 'ravi@example.com', city: 'Kolkata', google_campaign_id: '12345678901' });
      const ev = await env.DB.prepare('SELECT * FROM consent_events WHERE lead_id = ?').bind(created.id).first<any>();
      expect(ev).toMatchObject({ consent_value: 'explicit_opt_in', source: 'google_ads', text_version: 'google-ads-lead-form-2026-10' });
      expect(sent).toHaveLength(1);
      expect(sent[0].body).toMatchObject({ kind: 'instant_call', lead_id: created.id, lead_source_id: src.id });
      const ext = await env.DB.prepare("SELECT * FROM lead_external_ids WHERE kind = 'google_ads' AND external_id = ?").bind(l.lead_id).first<any>();
      expect(ext).toMatchObject({ business_id: biz, lead_source_id: src.id, lead_id: created.id });
    });

    it('dedupes redeliveries by Google lead_id (even with another phone)', async () => {
      const { body: src } = await create({ kind: 'google_ads' });
      const { e, sent } = queueEnv();
      const l = lead(src.token);
      expect((await post(`/hooks/google-ads/${src.slug}`, JSON.stringify(l), {}, e)).status).toBe(200);
      const again = { ...l, user_column_data: l.user_column_data.map((c: any) => (c.column_id === 'PHONE_NUMBER' ? { ...c, string_value: nextPhone() } : c)) };
      expect((await post(`/hooks/google-ads/${src.slug}`, JSON.stringify(again), {}, e)).status).toBe(200);
      expect(await leadByPhone(phoneOf(again))).toBeNull();
      expect(sent).toHaveLength(1);
    });

    it('auto_call off: lead created, no call enqueued', async () => {
      const { body: src } = await create({ kind: 'google_ads', auto_call: false });
      const { e, sent } = queueEnv();
      const l = lead(src.token);
      expect((await post(`/hooks/google-ads/${src.slug}`, JSON.stringify(l), {}, e)).status).toBe(200);
      expect(await leadByPhone(phoneOf(l))).not.toBeNull();
      expect(sent).toHaveLength(0);
    });

    it('400s leads without a usable phone (permanent for Google, not retried)', async () => {
      const { body: src } = await create({ kind: 'google_ads' });
      const noPhone = lead(src.token, { user_column_data: [{ column_id: 'FULL_NAME', string_value: 'X' }] });
      expect((await post(`/hooks/google-ads/${src.slug}`, JSON.stringify(noPhone))).status).toBe(400);
      const badPhone = lead(src.token, { user_column_data: [{ column_id: 'PHONE_NUMBER', string_value: '12' }] });
      const res = await post(`/hooks/google-ads/${src.slug}`, JSON.stringify(badPhone));
      expect(res.status).toBe(400);
      // The id stays claimed: a redelivery of the same bad lead is simply acknowledged.
      expect((await post(`/hooks/google-ads/${src.slug}`, JSON.stringify(badPhone))).status).toBe(200);
    });

    it('a revoked source stops accepting leads', async () => {
      const { body: src } = await create({ kind: 'google_ads' });
      await authed(`/lead-sources/${src.id}/revoke`, token, 'POST');
      expect((await post(`/hooks/google-ads/${src.slug}`, JSON.stringify(lead(src.token)))).status).toBe(401);
    });
  });

  // ------------------------------------------------------------ IndiaMART
  describe('IndiaMART', () => {
    const rec = (over: any = {}) => ({
      UNIQUE_QUERY_ID: String(600000000 + ++phoneSeq),
      QUERY_TYPE: 'W',
      QUERY_TIME: '2026-10-10 11:17:14',
      SENDER_NAME: 'Prabhat',
      SENDER_MOBILE: `+91-${digits(nextPhone()).slice(2)}`,
      SENDER_EMAIL: 'prabhat@example.com',
      SUBJECT: 'Requirement for Empty Mineral Water Bottle',
      SENDER_COMPANY: 'ABC Pvt Ltd.',
      SENDER_CITY: 'Noida',
      QUERY_PRODUCT_NAME: 'Mineral Water Bottle',
      QUERY_MESSAGE: 'Quantity: 100000 Piece\nProbable Order Value: Rs. 10 to 20 Lakh',
      ...over,
    });

    async function indiamartSource(opts: { autoCall?: boolean; createdAt?: string } = {}) {
      const { body } = await create({ kind: 'indiamart', crm_key: 'TESTCRMKEY1234567890', auto_call: opts.autoCall ?? true });
      if (opts.createdAt) await env.DB.prepare('UPDATE lead_sources SET created_at = ? WHERE id = ?').bind(opts.createdAt, body.id).run();
      return body;
    }

    /** Only this source is due: park every other IndiaMART source. */
    async function onlyDue(id: string) {
      await env.DB.prepare("UPDATE lead_sources SET next_pull_at = '2999-01-01 00:00:00' WHERE kind = 'indiamart' AND id != ?").bind(id).run();
    }

    it('maps records; skips catalog views and records without a mobile', () => {
      const m = mapIndiaMartRecord(rec({ UNIQUE_QUERY_ID: 621654886, SENDER_MOBILE: '', SENDER_MOBILE_ALT: '+91-8888888888' }))!;
      expect(m.externalId).toBe('621654886');
      expect(m.input.phone).toBe('+91-8888888888');
      expect(m.input.interest).toBe('Mineral Water Bottle; Quantity: 100000 Piece Probable Order Value: Rs. 10 to 20 Lakh');
      expect(m.input.attributes).toEqual({ email: 'prabhat@example.com', city: 'Noida', company: 'ABC Pvt Ltd.' });
      expect(mapIndiaMartRecord(rec({ QUERY_TYPE: 'BIZ' }))).toBeNull();
      expect(mapIndiaMartRecord(rec({ SENDER_MOBILE: '', SENDER_MOBILE_ALT: '' }))).toBeNull();
      expect(mapIndiaMartRecord(rec({ SENDER_NAME: '', QUERY_PRODUCT_NAME: '' }))!.input).toMatchObject({ name: 'IndiaMART Buyer', interest: expect.stringContaining('Requirement for') });
      expect(indiaMartRecords({ RESPONSE: [rec(), null] })).toHaveLength(1);
      expect(indiaMartRecords({ body: { RESPONSE: rec() } })).toHaveLength(1);
      expect(indiaMartRecords({})).toEqual([]);
    });

    it('pulls with the decrypted key and an IST window, creates leads once, respects the 5-minute limit', async () => {
      const src = await indiamartSource({ createdAt: '2026-10-10 04:00:00' });
      await onlyDue(src.id);
      const r1 = rec();
      const dup = { ...r1 };
      const calls = mockFetch(() => json({ CODE: 200, STATUS: 'SUCCESS', MESSAGE: '', TOTAL_RECORDS: 3, RESPONSE: [r1, dup, rec({ QUERY_TYPE: 'BIZ' })] }));
      const { e, sent } = queueEnv();
      const now = new Date('2026-10-10T05:00:00Z');

      const out = await runIndiaMartPulls(e, { now });
      expect(out).toEqual([{ sourceId: src.id, status: 'ok', captured: 1 }]);
      expect(calls).toHaveLength(1);
      const u = new URL(calls[0]);
      expect(`${u.origin}${u.pathname}`).toBe(INDIAMART_PULL_URL);
      expect(u.searchParams.get('glusr_crm_key')).toBe('TESTCRMKEY1234567890');
      expect(u.searchParams.get('start_time')).toBe('10-Oct-202609:25:00'); // created 04:00Z - 5 min, in IST
      expect(u.searchParams.get('end_time')).toBe('10-Oct-202610:30:00');

      const created = await leadByPhone(r1.SENDER_MOBILE);
      expect(created).toMatchObject({ source: 'indiamart', consent: 'explicit_opt_in', name: 'Prabhat', lead_source_id: src.id });
      const ev = await env.DB.prepare('SELECT * FROM consent_events WHERE lead_id = ?').bind(created.id).first<any>();
      expect(ev).toMatchObject({ source: 'indiamart', text_version: 'indiamart-enquiry-2026-10' });
      expect(sent).toHaveLength(1);
      expect(sent[0].body.lead_id).toBe(created.id);
      const after = await row(src.id);
      expect(after.last_cursor).toBe(now.toISOString());
      expect(after.last_pulled_at).toBe('2026-10-10 05:00:00');

      // Inside 5 minutes: nothing is fetched.
      expect(await runIndiaMartPulls(e, { now: new Date(now.getTime() + 4 * 60_000) })).toEqual([]);
      expect(calls).toHaveLength(1);

      // After 5 minutes: window starts 5 min before the previous end; the overlapping lead is not duplicated.
      const later = new Date(now.getTime() + 5 * 60_000);
      const out2 = await runIndiaMartPulls(e, { now: later });
      expect(out2[0]).toMatchObject({ status: 'ok', captured: 0 });
      expect(new URL(calls[1]).searchParams.get('start_time')).toBe('10-Oct-202610:25:00');
      expect(sent).toHaveLength(1);

      // GET /lead-sources shows the sync time.
      const list = (await (await authed('/lead-sources', token)).json()) as any;
      expect(list.items.find((i: any) => i.id === src.id).last_synced_at).toBe('2026-10-10 05:05:00');
    });

    it('caps the first window at 7 days', async () => {
      const src = await indiamartSource({ createdAt: '2026-01-01 00:00:00' });
      await onlyDue(src.id);
      const calls = mockFetch(() => json({ CODE: 204, STATUS: 'FAILURE', MESSAGE: 'There are no leads in the given time duration.', TOTAL_RECORDS: 0, RESPONSE: [] }));
      const now = new Date('2026-10-10T05:00:00Z');
      const out = await runIndiaMartPulls(env as any, { now });
      expect(out[0]).toMatchObject({ status: 'no_leads', captured: 0 });
      expect(new URL(calls[0]).searchParams.get('start_time')).toBe('03-Oct-202610:31:00');
      expect((await row(src.id)).last_cursor).toBe(now.toISOString());
    });

    it('backs off 15 minutes when IndiaMART blocks the key, 5 minutes on the soft limit', async () => {
      const src = await indiamartSource();
      await onlyDue(src.id);
      let reply: any = { CODE: 429, STATUS: 'FAILURE', MESSAGE: 'Too Many  Requests', APP_AUTH_FAILURE_CODE: 429 };
      const calls = mockFetch(() => json(reply));
      const t0 = new Date(Date.now() + 60_000);
      expect((await runIndiaMartPulls(env as any, { now: t0 }))[0].status).toBe('blocked');
      let r = await row(src.id);
      expect(r.last_error).toBe('rate_limited');
      expect(r.last_cursor).toBeNull();
      expect(await runIndiaMartPulls(env as any, { now: new Date(t0.getTime() + 6 * 60_000) })).toEqual([]);
      expect(calls).toHaveLength(1);

      reply = { CODE: 429, STATUS: 'FAILURE', MESSAGE: 'It is advised to hit this API once in every 5 minutes', TOTAL_RECORDS: 0, RESPONSE: [] };
      const t1 = new Date(t0.getTime() + 16 * 60_000);
      expect((await runIndiaMartPulls(env as any, { now: t1 }))[0].status).toBe('rate_limited');
      r = await row(src.id);
      expect(r.next_pull_at).toBeNull();
      expect(await runIndiaMartPulls(env as any, { now: new Date(t1.getTime() + 60_000) })).toEqual([]);

      reply = { CODE: 200, STATUS: 'SUCCESS', RESPONSE: [] };
      expect((await runIndiaMartPulls(env as any, { now: new Date(t1.getTime() + 5 * 60_000) }))[0].status).toBe('ok');
      expect((await row(src.id)).last_error).toBeNull();
    });

    it('records an invalid key once, notifies the owner and retries hourly', async () => {
      const src = await indiamartSource();
      await onlyDue(src.id);
      mockFetch(() => json({ CODE: 401, STATUS: 'FAILURE', MESSAGE: 'Pull API Key that you are using is incorrect.', TOTAL_RECORDS: 0, RESPONSE: [] }));
      const t0 = new Date(Date.now() + 60_000);
      expect((await runIndiaMartPulls(env as any, { now: t0 }))[0].status).toBe('invalid_key');
      const r = await row(src.id);
      expect(r.last_error).toBe('invalid_key');
      expect(r.next_pull_at).not.toBeNull();
      expect(await runIndiaMartPulls(env as any, { now: new Date(t0.getTime() + 30 * 60_000) })).toEqual([]);
      expect((await runIndiaMartPulls(env as any, { now: new Date(t0.getTime() + 61 * 60_000) }))[0].status).toBe('invalid_key');
      const notes = await env.DB.prepare("SELECT COUNT(*) AS n FROM notifications WHERE business_id = ? AND type = 'lead_source_error'").bind(biz).first<any>();
      expect(notes.n).toBe(1);
      const list = (await (await authed('/lead-sources', token)).json()) as any;
      expect(list.items.find((i: any) => i.id === src.id).last_error).toBe('invalid_key');
    });

    it('handles 400, 500, network errors and unreadable config without crashing', async () => {
      const src = await indiamartSource();
      const now = new Date('2026-10-10T08:00:00Z');
      const fresh = async () => {
        await env.DB.prepare('UPDATE lead_sources SET last_pulled_at = NULL, next_pull_at = NULL WHERE id = ?').bind(src.id).run();
        return row(src.id);
      };
      mockFetch(() => json({ CODE: 400, STATUS: 'FAILURE', MESSAGE: 'You can fetch the data for the last 365 days only.' }));
      expect((await pullIndiaMartSource(env as any, await fresh(), now)).status).toBe('bad_request');
      expect((await row(src.id)).last_cursor).toBe(now.toISOString());
      vi.restoreAllMocks();

      mockFetch(() => json({ CODE: 500, STATUS: 'FAILURE', MESSAGE: 'Some Error Occured' }));
      expect((await pullIndiaMartSource(env as any, await fresh(), now)).status).toBe('upstream_error');
      vi.restoreAllMocks();

      mockFetch(() => new Response('<html>down</html>', { status: 502 }));
      expect((await pullIndiaMartSource(env as any, await fresh(), now)).status).toBe('upstream_error');
      vi.restoreAllMocks();

      mockFetch(() => { throw new TypeError('network'); });
      expect((await pullIndiaMartSource(env as any, await fresh(), now)).status).toBe('upstream_error');
      expect((await row(src.id)).last_error).toBe('upstream_error');

      await env.DB.prepare('UPDATE lead_sources SET config_encrypted = NULL WHERE id = ?').bind(src.id).run();
      expect((await pullIndiaMartSource(env as any, await fresh(), now)).status).toBe('config_unreadable');
    });

    it('never pulls revoked sources and skips a source another run already claimed', async () => {
      const src = await indiamartSource();
      await onlyDue(src.id);
      await authed(`/lead-sources/${src.id}/revoke`, token, 'POST');
      const calls = mockFetch(() => json({ CODE: 204, RESPONSE: [] }));
      expect(await runIndiaMartPulls(env as any, { now: new Date(Date.now() + 60_000) })).toEqual([]);
      expect(calls).toHaveLength(0);

      // Claim race: the row is due when listed but claimed by someone else before our UPDATE.
      const src2 = await indiamartSource();
      await onlyDue(src2.id);
      const realPrepare = env.DB.prepare.bind(env.DB);
      vi.spyOn(env.DB, 'prepare').mockImplementation((sql: string) => {
        if (sql.startsWith('UPDATE lead_sources SET last_pulled_at')) {
          return realPrepare("UPDATE lead_sources SET last_pulled_at = ? WHERE id = ? AND 0 AND ? AND ?") as any;
        }
        return realPrepare(sql);
      });
      expect(await runIndiaMartPulls(env as any, { now: new Date(Date.now() + 60_000) })).toEqual([{ sourceId: src2.id, status: 'skipped' }]);
    });

    it('push webhook: token in the URL, one lead per UNIQUE_QUERY_ID, always 200 when verified', async () => {
      const src = await indiamartSource();
      const { e, sent } = queueEnv();
      const r1 = rec();
      const payload = JSON.stringify({ CODE: 200, STATUS: 'SUCCESS', RESPONSE: r1 });
      expect((await post(`/hooks/indiamart/${src.slug}?key=wrong`, payload, {}, e)).status).toBe(401);
      expect((await post(`/hooks/indiamart/${src.slug}`, payload, {}, e)).status).toBe(401);
      expect((await post(`/hooks/indiamart/${src.slug}?key=${src.token}`, 'nope', {}, e)).status).toBe(400);

      const ok = await post(`/hooks/indiamart/${src.slug}?key=${src.token}`, payload, {}, e);
      expect(ok.status).toBe(200);
      expect(await ok.json()).toMatchObject({ CODE: 200, captured: 1, skipped: 0 });
      expect(await leadByPhone(r1.SENDER_MOBILE)).toMatchObject({ source: 'indiamart' });
      expect(sent).toHaveLength(1);

      const again = await post(`/hooks/indiamart/${src.slug}?key=${src.token}`, payload, {}, e);
      expect(await again.json()).toMatchObject({ captured: 0, skipped: 1 });
      const biz = await post(`/hooks/indiamart/${src.slug}?key=${src.token}`, JSON.stringify({ RESPONSE: rec({ QUERY_TYPE: 'BIZ' }) }), {}, e);
      expect(await biz.json()).toMatchObject({ captured: 0, skipped: 1 });
      expect(sent).toHaveLength(1);
    });
  });

  // ------------------------------------------------------------ Meta Lead Ads
  describe('Meta Lead Ads', () => {
    const appSecret = 'f00dbabe0123456789abcdef01234567';
    const pageToken = 'EAAGpagetokenforthetests0123456789';

    async function metaSource(autoCall = true) {
      const { body } = await create({ kind: 'meta', app_secret: appSecret, page_access_token: pageToken, auto_call: autoCall });
      return body;
    }

    const event = (...ids: string[]) => JSON.stringify({
      object: 'page',
      entry: [{ id: '1234', time: 1700000000, changes: ids.map((id) => ({ field: 'leadgen', value: { leadgen_id: id, page_id: '1234', form_id: '55', created_time: 1700000000 } })) }],
    });
    const sign = async (body: string, secret = appSecret) => `sha256=${await hmacHex(secret, body)}`;
    const fields = (phone: string, extra: any[] = []) => ({
      id: 'x',
      created_time: '2026-10-10T05:00:00+0000',
      field_data: [
        { name: 'full_name', values: ['Meera Das'] },
        { name: 'phone_number', values: [phone] },
        { name: 'email', values: ['meera@example.com'] },
        ...extra,
      ],
    });

    it('verifies the webhook subscription with the verify token', async () => {
      const src = await metaSource();
      const url = (q: string) => app.fetch(new Request(`http://localhost/hooks/meta/${src.slug}?${q}`), env);
      const ok = await url(`hub.mode=subscribe&hub.verify_token=${src.token}&hub.challenge=1158201444`);
      expect(ok.status).toBe(200);
      expect(await ok.text()).toBe('1158201444');
      expect((await url('hub.mode=subscribe&hub.verify_token=wrong&hub.challenge=1')).status).toBe(403);
      expect((await url(`hub.mode=unsubscribe&hub.verify_token=${src.token}&hub.challenge=1`)).status).toBe(403);
      expect((await url(`hub.mode=subscribe&hub.verify_token=${src.token}&hub.challenge=%3Cscript%3E`)).status).toBe(400);
    });

    it('parses leadgen ids and maps field_data', () => {
      expect(metaLeadgenIds(JSON.parse(event('1', '2')))).toEqual(['1', '2']);
      expect(metaLeadgenIds({ entry: [{ changes: [{ field: 'feed', value: {} }] }] })).toEqual([]);
      expect(metaLeadgenIds(null)).toEqual([]);
      const m = mapMetaLead('L9', [
        { name: 'first_name', values: ['Meera'] }, { name: 'last_name', values: ['Das'] },
        { name: 'phone_number', values: ['+919830011111'] }, { name: 'which_course?', values: ['Spoken English'] },
        { name: 'zip_code', values: ['700001'] }, { name: 'city', values: ['Howrah'] },
      ])!;
      expect(m.input).toMatchObject({ name: 'Meera Das', phone: '+919830011111', interest: 'Which course?: Spoken English', attributes: { city: 'Howrah' } });
      expect(mapMetaLead('L', [{ name: 'full_name', values: ['x'] }])).toBeNull();
      expect(mapMetaLead('L', 'bad')).toBeNull();
    });

    it('rejects unsigned and wrongly signed events', async () => {
      const src = await metaSource();
      const body = event('999');
      const calls = mockFetch(() => json({}));
      expect((await post(`/hooks/meta/${src.slug}`, body)).status).toBe(401);
      expect((await post(`/hooks/meta/${src.slug}`, body, { 'X-Hub-Signature-256': await sign(body, 'some-other-secret') })).status).toBe(401);
      expect((await post(`/hooks/meta/${src.slug}`, body, { 'X-Hub-Signature-256': 'sha1=abc' })).status).toBe(401);
      expect((await post('/hooks/meta/nosuchslug12', body, { 'X-Hub-Signature-256': await sign(body) })).status).toBe(401);
      expect(calls).toHaveLength(0);
      expect(await verifyMetaSignature(appSecret, body, await sign(body))).toBe(true);
      expect(await verifyMetaSignature(appSecret, `${body} `, await sign(body))).toBe(false);
      expect(await verifyMetaSignature('', body, await sign(body))).toBe(false);
    });

    it('fetches the lead from the Graph API, creates it once, records consent and calls', async () => {
      const src = await metaSource();
      const phone = nextPhone();
      const leadgenId = `44${randomToken(6)}`;
      const calls = mockFetch((url) => (url.startsWith('https://graph.facebook.com/') ? json(fields(phone, [{ name: 'budget', values: ['5 lakh'] }])) : json({}, 404)));
      const { e, sent } = queueEnv();
      const body = event(leadgenId);
      const res = await post(`/hooks/meta/${src.slug}`, body, { 'X-Hub-Signature-256': await sign(body) }, e);
      expect(res.status).toBe(200);

      expect(calls).toHaveLength(1);
      const u = new URL(calls[0]);
      expect(u.pathname).toBe(`/v21.0/${leadgenId}`);
      expect(u.searchParams.get('access_token')).toBe(pageToken);
      expect(u.searchParams.get('appsecret_proof')).toBe(await hmacHex(appSecret, pageToken));

      const created = await leadByPhone(phone);
      expect(created).toMatchObject({ name: 'Meera Das', source: 'meta', consent: 'explicit_opt_in', interest: 'Budget: 5 lakh' });
      expect(JSON.parse(created.attributes)).toEqual({ email: 'meera@example.com' });
      const ev = await env.DB.prepare('SELECT * FROM consent_events WHERE lead_id = ?').bind(created.id).first<any>();
      expect(ev).toMatchObject({ source: 'meta_lead_ads', text_version: 'meta-lead-ads-2026-10' });
      expect(sent).toHaveLength(1);

      // Redelivery: no second Graph fetch, no second lead.
      expect((await post(`/hooks/meta/${src.slug}`, body, { 'X-Hub-Signature-256': await sign(body) }, e)).status).toBe(200);
      expect(calls).toHaveLength(1);
      expect(sent).toHaveLength(1);
    });

    it('transient Graph errors return 500 so Meta retries, and the retry works', async () => {
      const src = await metaSource();
      const phone = nextPhone();
      const leadgenId = `55${randomToken(6)}`;
      let fail = true;
      mockFetch(() => (fail ? json({ error: { message: 'busy', type: 'OAuthException', is_transient: true } }, 500) : json(fields(phone))));
      const body = event(leadgenId);
      expect((await post(`/hooks/meta/${src.slug}`, body, { 'X-Hub-Signature-256': await sign(body) })).status).toBe(500);
      expect(await leadByPhone(phone)).toBeNull();
      fail = false;
      expect((await post(`/hooks/meta/${src.slug}`, body, { 'X-Hub-Signature-256': await sign(body) })).status).toBe(200);
      expect(await leadByPhone(phone)).not.toBeNull();
    });

    it('a rejected page token is recorded for the owner and acknowledged', async () => {
      const src = await metaSource();
      mockFetch(() => json({ error: { message: 'Error validating access token', type: 'OAuthException', code: 190 } }, 400));
      const body = event(`66${randomToken(6)}`);
      expect((await post(`/hooks/meta/${src.slug}`, body, { 'X-Hub-Signature-256': await sign(body) })).status).toBe(200);
      expect((await row(src.id)).last_error).toBe('meta_token_invalid');
      const note = await env.DB.prepare("SELECT * FROM notifications WHERE business_id = ? AND type = 'lead_source_error' AND title LIKE 'Facebook%'").bind(biz).first<any>();
      expect(note.route).toBe('/leads/auto');

      // Fixed on Meta's side: the next lead clears the error.
      vi.restoreAllMocks();
      mockFetch(() => json(fields(nextPhone())));
      const body2 = event(`77${randomToken(6)}`);
      expect((await post(`/hooks/meta/${src.slug}`, body2, { 'X-Hub-Signature-256': await sign(body2) })).status).toBe(200);
      expect((await row(src.id)).last_error).toBeNull();
    });

    it('forms without a phone question create nothing; network failures are transient', async () => {
      const src = await metaSource();
      mockFetch(() => json({ id: 'x', field_data: [{ name: 'full_name', values: ['No Phone'] }] }));
      const body = event(`88${randomToken(6)}`);
      expect((await post(`/hooks/meta/${src.slug}`, body, { 'X-Hub-Signature-256': await sign(body) })).status).toBe(200);
      vi.restoreAllMocks();
      mockFetch(() => { throw new TypeError('network'); });
      expect(await fetchMetaLead(env as any, '1', { page_access_token: 't' })).toEqual({ ok: false, transient: true, error: 'network' });
    });

    it('captureExternalLead releases its claim when capture crashes', async () => {
      const src = await row((await metaSource()).id);
      const broken = { ...env, DB: env.DB } as any;
      const realPrepare = env.DB.prepare.bind(env.DB);
      vi.spyOn(env.DB, 'prepare').mockImplementation((sql: string) => {
        if (sql.includes('INSERT INTO leads')) throw new Error('db down');
        return realPrepare(sql);
      });
      await expect(captureExternalLead(broken, src, 'crash-1', { name: 'X', phone: nextPhone() })).rejects.toThrow('db down');
      vi.restoreAllMocks();
      const claim = await env.DB.prepare("SELECT 1 FROM lead_external_ids WHERE external_id = 'crash-1'").first();
      expect(claim).toBeNull();
      const { e } = queueEnv();
      expect((await captureExternalLead(e, src, 'crash-1', { name: 'X', phone: nextPhone() })).status).toBe('created');
      expect((await captureExternalLead(e, src, 'crash-1', { name: 'X', phone: nextPhone() })).status).toBe('already_seen');
    });
  });
});
