import { describe, it, expect, beforeAll, afterEach, vi } from 'vitest';
import { env } from 'cloudflare:test';
import { migrateTestDb } from './setup-db';
import app from '../src/index';
import { signJWT } from '../src/auth';
import {
  processInstantCallJob,
  handleInstantCallMessages,
  captureLead,
  sqliteNow,
  verifyWebhookToken,
  sha256Hex,
  randomToken,
  enquiryNoticeText,
  INSTANT_CALL_KIND,
  type InstantCallMessage,
  type LeadSourceRow,
} from '../src/services/lead_capture';
import { formPage, FORM_CSP, HONEYPOT_FIELD, FORM_LIMIT_PER_IP } from '../src/routes/lead_capture_public';
import { placeLeadCall } from '../src/services/dial';
import { addToGlobalDnc, globalDncSecret } from '../src/services/global_dnc';

const SECRET = 'test-jwt-signing-secret-key-32chars-min-length';

describe('Speed-to-lead: capture sources, public form, webhook, instant call', () => {
  const bizA = 'biz_stl_a';
  const bizB = 'biz_stl_b';
  let tokenA: string;
  let tokenB: string;
  let ipCounter = 0;

  /** Captures queue sends instead of dispatching them. */
  function queueEnv(base: any = env) {
    const sent: { body: any; opts?: any }[] = [];
    const e = { ...base, CAMPAIGN_QUEUE: { send: async (body: any, opts?: any) => { sent.push({ body, opts }); }, sendBatch: async () => {} } } as any;
    return { e, sent };
  }

  const authed = (path: string, token: string, method = 'GET', body?: any) =>
    app.fetch(new Request(`http://localhost${path}`, {
      method,
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
      body: body ? JSON.stringify(body) : undefined,
    }), env);

  const freshIp = () => `10.0.${Math.floor(++ipCounter / 250)}.${ipCounter % 250}`;

  const postForm = (slug: string, fields: Record<string, string>, e: any = env, ip = freshIp()) =>
    app.fetch(new Request(`http://localhost/f/${slug}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'cf-connecting-ip': ip },
      body: new URLSearchParams(fields).toString(),
    }), e);

  const postHook = (slug: string, token: string | null, body: any, e: any = env) =>
    app.fetch(new Request(`http://localhost/hooks/leads/${slug}`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'cf-connecting-ip': freshIp(),
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
      body: JSON.stringify(body),
    }), e);

  async function createSource(token: string, kind: 'form' | 'webhook', autoCall = true) {
    const res = await authed('/lead-sources', token, 'POST', { kind, auto_call: autoCall });
    return { res, body: (await res.json()) as any };
  }

  async function seedSource(businessId: string, kind: 'form' | 'webhook', autoCall = 1): Promise<LeadSourceRow> {
    const id = `lsrc_t_${randomToken(8)}`;
    const slug = randomToken(12);
    await env.DB.prepare(
      `INSERT INTO lead_sources (id, business_id, kind, public_slug, auto_call) VALUES (?, ?, ?, ?, ?)`
    ).bind(id, businessId, kind, slug, autoCall).run();
    return (await env.DB.prepare('SELECT * FROM lead_sources WHERE id = ?').bind(id).first()) as any;
  }

  async function seedLead(businessId: string, phone: string, sourceId: string | null, extra = '') {
    const id = `lead_t_${randomToken(8)}`;
    await env.DB.prepare(
      `INSERT INTO leads (id, business_id, name, phone, status, consent, lead_source_id ${extra ? ', do_not_call' : ''})
       VALUES (?, ?, 'Asha Rao', ?, 'new', 'explicit_opt_in', ? ${extra ? ', 1' : ''})`
    ).bind(id, businessId, phone, sourceId).run();
    return id;
  }

  function job(businessId: string, leadId: string, sourceId: string, over: Partial<InstantCallMessage> = {}): InstantCallMessage {
    return {
      kind: INSTANT_CALL_KIND, business_id: businessId, lead_id: leadId, lead_source_id: sourceId,
      idempotency_key: `instant:${leadId}`, attempts: 0, enqueued_at: sqliteNow(new Date(Date.now() - 1000)), ...over,
    };
  }

  beforeAll(async () => {
    await migrateTestDb();
    await env.DB.batch([
      env.DB.prepare("INSERT OR REPLACE INTO businesses (id, name, category) VALUES (?, 'Asha <Coaching> & \"Co\"', 'education')").bind(bizA),
      env.DB.prepare("INSERT OR REPLACE INTO users (id, phone, business_id) VALUES ('usr_stl_a', '919830070001', ?)").bind(bizA),
      env.DB.prepare("INSERT OR REPLACE INTO agents (id, business_id, name, role, status, calling_hours_start, calling_hours_end) VALUES ('agt_stl_a', ?, 'Maya', 'Counselor', 'active', 0, 24)").bind(bizA),
      env.DB.prepare("INSERT OR REPLACE INTO usage (id, business_id, plan_name, included_minutes, minutes_used) VALUES ('usg_stl_a', ?, 'Founding', 1000, 0)").bind(bizA),
      env.DB.prepare("INSERT OR REPLACE INTO businesses (id, name, category) VALUES (?, 'Other Clinic', 'healthcare')").bind(bizB),
      env.DB.prepare("INSERT OR REPLACE INTO users (id, phone, business_id) VALUES ('usr_stl_b', '919830070002', ?)").bind(bizB),
      env.DB.prepare("INSERT OR REPLACE INTO agents (id, business_id, name, role, status, calling_hours_start, calling_hours_end) VALUES ('agt_stl_b', ?, 'Riya', 'Receptionist', 'active', 0, 24)").bind(bizB),
      env.DB.prepare("INSERT OR REPLACE INTO usage (id, business_id, plan_name, included_minutes, minutes_used) VALUES ('usg_stl_b', ?, 'Founding', 1000, 0)").bind(bizB),
    ]);
    tokenA = await signJWT({ sub: 'usr_stl_a', phone: '919830070001', business_id: bizA, type: 'access' }, SECRET, 3600);
    tokenB = await signJWT({ sub: 'usr_stl_b', phone: '919830070002', business_id: bizB, type: 'access' }, SECRET, 3600);
  });

  afterEach(() => vi.restoreAllMocks());

  // ------------------------------------------------------------ owner APIs
  describe('owner APIs', () => {
    it('creates one form per business (idempotent) and lists it with its public URL', async () => {
      const first = await createSource(tokenA, 'form');
      expect(first.res.status).toBe(201);
      expect(first.body.kind).toBe('form');
      expect(first.body.slug).toMatch(/^[A-Za-z0-9]{12}$/);
      expect(first.body.url).toBe(`http://localhost/f/${first.body.slug}`);
      expect(first.body.auto_call).toBe(true);
      expect(first.body.token).toBeUndefined();
      expect(JSON.stringify(first.body)).not.toContain('secret_hash');

      const again = await createSource(tokenA, 'form');
      expect(again.res.status).toBe(200);
      expect(again.body.id).toBe(first.body.id);

      const list = await authed('/lead-sources', tokenA);
      const items = ((await list.json()) as any).items;
      expect(items.map((i: any) => i.id)).toContain(first.body.id);
    });

    it('creates a webhook, returns its token once and stores only the hash', async () => {
      const { res, body } = await createSource(tokenA, 'webhook');
      expect(res.status).toBe(201);
      expect(body.token).toMatch(/^cplh_[A-Za-z0-9]{40}$/);
      expect(body.url).toBe(`http://localhost/hooks/leads/${body.slug}`);
      const row = await env.DB.prepare('SELECT secret_hash FROM lead_sources WHERE id = ?').bind(body.id).first<any>();
      expect(row.secret_hash).toBe(await sha256Hex(body.token));
      expect(row.secret_hash).not.toContain(body.token);

      const list = (await (await authed('/lead-sources', tokenA)).json()) as any;
      expect(list.items.find((i: any) => i.id === body.id).token).toBeUndefined();
    });

    it('caps active webhooks per business', async () => {
      const biz = 'biz_stl_cap';
      await env.DB.prepare("INSERT OR REPLACE INTO businesses (id, name) VALUES (?, 'Cap')").bind(biz).run();
      await env.DB.prepare("INSERT OR REPLACE INTO users (id, phone, business_id) VALUES ('usr_cap', '919830070009', ?)").bind(biz).run();
      const tok = await signJWT({ sub: 'usr_cap', phone: '919830070009', business_id: biz, type: 'access' }, SECRET, 3600);
      for (let i = 0; i < 5; i++) expect((await createSource(tok, 'webhook')).res.status).toBe(201);
      const sixth = await createSource(tok, 'webhook');
      expect(sixth.res.status).toBe(409);
      expect(sixth.body.code).toBe('too_many_sources');
    });

    it('PATCH toggles auto_call; revoke hides it', async () => {
      const { body } = await createSource(tokenA, 'webhook');
      const patched = await authed(`/lead-sources/${body.id}`, tokenA, 'PATCH', { auto_call: false });
      expect(patched.status).toBe(200);
      expect(((await patched.json()) as any).auto_call).toBe(false);

      const bad = await authed(`/lead-sources/${body.id}`, tokenA, 'PATCH', { auto_call: null });
      expect(bad.status).toBe(400);

      const revoked = await authed(`/lead-sources/${body.id}/revoke`, tokenA, 'POST');
      expect(revoked.status).toBe(200);
      const list = (await (await authed('/lead-sources', tokenA)).json()) as any;
      expect(list.items.some((i: any) => i.id === body.id)).toBe(false);
      expect((await authed(`/lead-sources/${body.id}/revoke`, tokenA, 'POST')).status).toBe(404);
      expect((await authed(`/lead-sources/${body.id}`, tokenA, 'PATCH', { auto_call: true })).status).toBe(404);
    });

    it("never shows or changes another business's sources", async () => {
      const { body } = await createSource(tokenA, 'webhook');
      const listB = (await (await authed('/lead-sources', tokenB)).json()) as any;
      expect(listB.items.some((i: any) => i.id === body.id)).toBe(false);
      expect((await authed(`/lead-sources/${body.id}`, tokenB, 'PATCH', { auto_call: false })).status).toBe(404);
      expect((await authed(`/lead-sources/${body.id}/revoke`, tokenB, 'POST')).status).toBe(404);
      const row = await env.DB.prepare('SELECT auto_call, revoked_at FROM lead_sources WHERE id = ?').bind(body.id).first<any>();
      expect(row.auto_call).toBe(1);
      expect(row.revoked_at).toBeNull();
    });

    it('requires auth', async () => {
      const res = await app.fetch(new Request('http://localhost/lead-sources'), env);
      expect(res.status).toBe(401);
    });
  });

  // ------------------------------------------------------------ hosted form
  describe('hosted form', () => {
    it('renders a branded, escaped form with a strict CSP and no scripts', async () => {
      const src = await seedSource(bizA, 'form');
      const res = await app.fetch(new Request(`http://localhost/f/${src.public_slug}`), env);
      expect(res.status).toBe(200);
      expect(res.headers.get('content-security-policy')).toBe(FORM_CSP);
      expect(FORM_CSP).toContain("default-src 'none'");
      expect(FORM_CSP).toContain("form-action 'self'");
      expect(res.headers.get('cache-control')).toBe('no-store');
      const html = await res.text();
      expect(html).toContain('Asha &lt;Coaching&gt; &amp; &quot;Co&quot;');
      expect(html).not.toContain('<Coaching>');
      expect(html).not.toMatch(/<script/i);
      expect(html).toContain('name="consent"');
      expect(html).toContain(`name="${HONEYPOT_FIELD}"`);
      expect(html).toContain('value="+91 "');
      expect(html).toContain('may be an automated AI call');
      // Growth loop: the footer links to the landing page with this business's referral code.
      const biz = await env.DB.prepare('SELECT referral_code FROM businesses WHERE id = ?').bind(bizA).first<any>();
      expect(biz.referral_code).toMatch(/^[2-9A-HJKMNP-Z]{6}$/);
      expect(html).toContain(`href="/get?ref=${biz.referral_code}">Powered by CallPilot</a>`);
    });

    it('escapes values echoed back into the form', () => {
      const html = formPage('Biz', 'abcdefghijkl', { name: '"><script>alert(1)</script>' }, '<b>x</b>');
      expect(html).not.toContain('<script>');
      expect(html).toContain('&quot;&gt;&lt;script&gt;');
      expect(html).toContain('&lt;b&gt;x&lt;/b&gt;');
    });

    it('404s unknown, malformed and revoked slugs', async () => {
      expect((await app.fetch(new Request('http://localhost/f/nosuchslug123'), env)).status).toBe(404);
      expect((await app.fetch(new Request('http://localhost/f/bad-slug!'), env)).status).toBe(404);
      const src = await seedSource(bizA, 'form');
      await env.DB.prepare("UPDATE lead_sources SET revoked_at = datetime('now') WHERE id = ?").bind(src.id).run();
      expect((await app.fetch(new Request(`http://localhost/f/${src.public_slug}`), env)).status).toBe(404);
      expect((await postForm(src.public_slug, { name: 'A', phone: '9830011111', consent: 'yes' })).status).toBe(404);
    });

    it('creates an opted-in form lead and enqueues an instant call', async () => {
      const src = await seedSource(bizA, 'form');
      const { e, sent } = queueEnv();
      const res = await postForm(src.public_slug, { name: 'Ravi Kumar', phone: '+91 98300 22222', interest: 'NEET', consent: 'yes' }, e);
      expect(res.status).toBe(200);
      expect(await res.text()).toContain('Thank you, Ravi');
      const lead = await env.DB.prepare('SELECT * FROM leads WHERE business_id = ? AND phone = ?').bind(bizA, '919830022222').first<any>();
      expect(lead.source).toBe('form');
      expect(lead.consent).toBe('explicit_opt_in');
      expect(lead.lead_source_id).toBe(src.id);
      expect(lead.interest).toBe('NEET');
      expect(sent).toHaveLength(1);
      expect(sent[0].body).toMatchObject({ kind: 'instant_call', lead_id: lead.id, business_id: bizA, lead_source_id: src.id, attempts: 0 });
      expect(sent[0].opts).toBeUndefined();
    });

    it('records a form consent event for the new lead', async () => {
      const src = await seedSource(bizA, 'form');
      const { e } = queueEnv();
      await postForm(src.public_slug, { name: 'Consent Kumar', phone: '+91 98111 90002', consent: 'yes' }, e);
      const lead = await env.DB.prepare('SELECT id FROM leads WHERE business_id = ? AND phone = ?').bind(bizA, '919811190002').first<any>();
      const ev = await env.DB.prepare('SELECT * FROM consent_events WHERE lead_id = ?').bind(lead.id).first<any>();
      expect(ev).toMatchObject({ business_id: bizA, consent_value: 'explicit_opt_in', source: 'form', text_version: 'enquiry-form-2026-10' });
    });

    it('the shared dial path (instant call, manual call, test call) honours the public /stop list', async () => {
      const secret = globalDncSecret(env as any)!;
      await addToGlobalDnc(env.DB, secret, '919811190001', 'web');
      const leadId = await seedLead(bizA, '919811190001', null);
      const out = await placeLeadCall({ ...env, DEV_ALLOW_ANY_CALLING_HOURS: 'true' } as any, { businessId: bizA, leadId });
      expect(out).toMatchObject({ ok: false, code: 'blocked', reason: 'do_not_call' });
    });

    it('requires consent, a name and a valid phone', async () => {
      const src = await seedSource(bizA, 'form');
      const noConsent = await postForm(src.public_slug, { name: 'No Consent', phone: '9830033333' });
      expect(noConsent.status).toBe(400);
      expect(await noConsent.text()).toContain('tick the box');
      expect((await postForm(src.public_slug, { name: '', phone: '9830033333', consent: 'yes' })).status).toBe(400);
      expect((await postForm(src.public_slug, { name: 'Bad Phone', phone: '+91 ', consent: 'yes' })).status).toBe(400);
      expect((await postForm(src.public_slug, { name: 'Bad Phone', phone: '12345678901234567', consent: 'yes' })).status).toBe(400);
      const n = await env.DB.prepare('SELECT COUNT(*) AS n FROM leads WHERE lead_source_id = ?').bind(src.id).first<any>();
      expect(n.n).toBe(0);
    });

    it('honeypot: shows the thank-you page but creates nothing', async () => {
      const src = await seedSource(bizA, 'form');
      const { e, sent } = queueEnv();
      const res = await postForm(src.public_slug, { name: 'Bot', phone: '9830044444', consent: 'yes', [HONEYPOT_FIELD]: 'http://spam' }, e);
      expect(res.status).toBe(200);
      expect(await res.text()).toContain('Thank you');
      expect(await env.DB.prepare('SELECT id FROM leads WHERE phone = ?').bind('919830044444').first()).toBeNull();
      expect(sent).toHaveLength(0);
    });

    it('rate-limits submissions per IP', async () => {
      const src = await seedSource(bizA, 'form');
      const ip = '203.0.113.7';
      for (let i = 0; i < FORM_LIMIT_PER_IP.limit; i++) {
        const r = await postForm(src.public_slug, { name: `P${i}`, phone: `98300555${String(i).padStart(2, '0')}`, consent: 'yes' }, queueEnv().e, ip);
        expect(r.status).toBe(200);
      }
      const blocked = await postForm(src.public_slug, { name: 'Late', phone: '9830055599', consent: 'yes' }, queueEnv().e, ip);
      expect(blocked.status).toBe(429);
      expect(blocked.headers.get('retry-after')).toBeTruthy();
      // Raw IPs are never stored in rate-limit buckets.
      const raw = await env.DB.prepare('SELECT COUNT(*) AS n FROM rate_limits WHERE bucket LIKE ?').bind(`%${ip}%`).first<any>();
      expect(raw.n).toBe(0);
    });

    it('dedupes the same phone within 24h: no duplicate lead, no second call', async () => {
      const src = await seedSource(bizA, 'form');
      const { e, sent } = queueEnv();
      await postForm(src.public_slug, { name: 'Dup One', phone: '9830066666', consent: 'yes' }, e);
      const second = await postForm(src.public_slug, { name: 'Dup Two', phone: '09830066666', consent: 'yes' }, e);
      expect(second.status).toBe(200);
      expect(await second.text()).toContain('Thank you');
      const n = await env.DB.prepare('SELECT COUNT(*) AS n FROM leads WHERE business_id = ? AND phone = ?').bind(bizA, '919811190001').first<any>();
      expect(n.n).toBe(1);
      expect(sent).toHaveLength(1);
    });

    it('a repeat enquiry after 24h refreshes the lead and calls again, keeping an opt-out', async () => {
      const src = await seedSource(bizA, 'form');
      const leadId = await seedLead(bizA, '919830077777', null);
      await env.DB.prepare("UPDATE leads SET created_at = datetime('now', '-3 days'), consent = 'unknown' WHERE id = ?").bind(leadId).run();
      const { e, sent } = queueEnv();
      const r = await captureLead(e, src, { name: 'Asha', phone: '9830077777', interest: 'JEE' });
      expect(r).toMatchObject({ status: 'updated', leadId });
      const row = await env.DB.prepare('SELECT consent, interest, lead_source_id, last_enquiry_at FROM leads WHERE id = ?').bind(leadId).first<any>();
      expect(row).toMatchObject({ consent: 'explicit_opt_in', interest: 'JEE', lead_source_id: src.id });
      expect(row.last_enquiry_at).toBeTruthy();
      expect(sent).toHaveLength(1);

      const optedOut = await seedLead(bizA, '919830077778', null);
      await env.DB.prepare("UPDATE leads SET created_at = datetime('now', '-3 days'), consent = 'opt_out' WHERE id = ?").bind(optedOut).run();
      await captureLead(e, src, { name: 'Asha', phone: '9830077778' });
      expect((await env.DB.prepare('SELECT consent FROM leads WHERE id = ?').bind(optedOut).first<any>()).consent).toBe('opt_out');
      // The consent history must show the value actually kept, not the form's opt-in.
      const ev = await env.DB.prepare('SELECT consent_value FROM consent_events WHERE lead_id = ? ORDER BY created_at DESC').bind(optedOut).first<any>();
      expect(ev.consent_value).toBe('opt_out');
    });

    it('auto-call off: lead is created, owner is notified, nothing is enqueued', async () => {
      const src = await seedSource(bizA, 'form', 0);
      const { e, sent } = queueEnv();
      const res = await postForm(src.public_slug, { name: 'Manual Mina', phone: '9830088888', consent: 'yes' }, e);
      expect(await res.text()).toContain('will get in touch soon');
      expect(sent).toHaveLength(0);
      const lead = await env.DB.prepare('SELECT id FROM leads WHERE phone = ?').bind('919830088888').first<any>();
      const notif = await env.DB.prepare("SELECT * FROM notifications WHERE business_id = ? AND type = 'new_lead' AND route = ?").bind(bizA, `/leads/${lead.id}`).first<any>();
      expect(notif.title).toBe('New enquiry from Manual');
    });
  });

  // ------------------------------------------------------------ webhook
  describe('webhook', () => {
    it('401 for a missing/wrong token, unknown slug or revoked source', async () => {
      const { body } = await createSource(tokenA, 'webhook');
      const payload = { name: 'Web Lead', phone: '9830099991', consent: true };
      expect((await postHook(body.slug, null, payload)).status).toBe(401);
      expect((await postHook(body.slug, 'cplh_wrong', payload)).status).toBe(401);
      expect((await postHook('unknownslug12', body.token, payload)).status).toBe(401);
      await authed(`/lead-sources/${body.id}/revoke`, tokenA, 'POST');
      expect((await postHook(body.slug, body.token, payload)).status).toBe(401);
      expect(await env.DB.prepare('SELECT id FROM leads WHERE phone = ?').bind('919830099991').first()).toBeNull();
    });

    it('a form slug is not a webhook (and vice versa)', async () => {
      const form = await seedSource(bizA, 'form');
      expect((await postHook(form.public_slug, 'anything', { name: 'X', phone: '9830099990', consent: true })).status).toBe(401);
      const hook = await createSource(tokenA, 'webhook');
      expect((await app.fetch(new Request(`http://localhost/f/${hook.body.slug}`), env)).status).toBe(404);
    });

    it('requires consent: true and validates the body', async () => {
      const { body } = await createSource(tokenA, 'webhook');
      const noConsent = await postHook(body.slug, body.token, { name: 'Web', phone: '9830099992' });
      expect(noConsent.status).toBe(400);
      expect(((await noConsent.json()) as any).code).toBe('validation_error');
      expect((await postHook(body.slug, body.token, { name: 'Web', phone: '9830099992', consent: 'yes' })).status).toBe(400);
      expect((await postHook(body.slug, body.token, { name: 'Web', phone: '12', consent: true })).status).toBe(400);
      const badPhone = await postHook(body.slug, body.token, { name: 'Web', phone: '12345678901234567', consent: true });
      expect(badPhone.status).toBe(400);
    });

    it('201 {lead_id} with source webhook; duplicate within 24h is 200 and not re-called', async () => {
      const { body } = await createSource(tokenA, 'webhook');
      const { e, sent } = queueEnv();
      const first = await postHook(body.slug, body.token, { name: 'Web Lead', phone: '+919830099993', interest: 'Boards', consent: true }, e);
      expect(first.status).toBe(201);
      const created = (await first.json()) as any;
      expect(created).toMatchObject({ status: 'created', auto_call: true });
      const lead = await env.DB.prepare('SELECT * FROM leads WHERE id = ?').bind(created.lead_id).first<any>();
      expect(lead).toMatchObject({ business_id: bizA, source: 'webhook', consent: 'explicit_opt_in', phone: '919830099993' });
      expect(sent).toHaveLength(1);

      const dup = await postHook(body.slug, body.token, { name: 'Web Lead', phone: '9830099993', consent: true }, e);
      expect(dup.status).toBe(200);
      expect((await dup.json()) as any).toMatchObject({ lead_id: created.lead_id, status: 'duplicate', auto_call: false });
      expect(sent).toHaveLength(1);
    });

    it('token check is constant-time over the hash', async () => {
      const h = await sha256Hex('cplh_abc');
      expect(await verifyWebhookToken('cplh_abc', h)).toBe(true);
      expect(await verifyWebhookToken('cplh_abd', h)).toBe(false);
      expect(await verifyWebhookToken(undefined, h)).toBe(false);
      expect(await verifyWebhookToken('cplh_abc', null)).toBe(false);
    });
  });

  // ------------------------------------------------------------ instant call
  describe('instant call job', () => {
    it('mock mode places the call like a manual dial and tells the owner', async () => {
      const src = await seedSource(bizA, 'form');
      const leadId = await seedLead(bizA, '919830010001', src.id);
      const r = await processInstantCallJob(env as any, job(bizA, leadId, src.id));
      expect(r).toEqual({ action: 'ack', reason: 'mock_dial' });
      const call = await env.DB.prepare('SELECT * FROM calls WHERE lead_id = ?').bind(leadId).first<any>();
      expect(call).toMatchObject({ business_id: bizA, status: 'calling', lead_phone: '919830010001' });
      expect((await env.DB.prepare('SELECT status FROM leads WHERE id = ?').bind(leadId).first<any>()).status).toBe('calling');
      const notif = await env.DB.prepare("SELECT body FROM notifications WHERE route = ? AND type = 'new_lead'").bind(`/leads/${leadId}`).first<any>();
      expect(notif.body).toContain('calling them now');

      // Redelivery of the same message does not dial twice.
      expect((await processInstantCallJob(env as any, job(bizA, leadId, src.id))).reason).toBe('already_called');
    });

    it('real mode dials Sarvam with the same agent variables as a manual call', async () => {
      const src = await seedSource(bizA, 'form');
      const leadId = await seedLead(bizA, '919830010002', src.id);
      const realEnv = {
        ...env, SARVAM_API_KEY: 'real-key', SARVAM_ORG_ID: 'org', SARVAM_WORKSPACE_ID: 'ws', SARVAM_ADMISSIONS_APP_ID: 'app',
        PUBLIC_API_BASE_URL: 'https://api.example.test',
      } as any;
      let sentBody: any;
      vi.spyOn(globalThis, 'fetch').mockImplementation(async (_u: any, init: any) => {
        sentBody = JSON.parse(init.body);
        return new Response(JSON.stringify({ attempt_id: 'att_instant' }), { status: 200 });
      });
      const r = await processInstantCallJob(realEnv, job(bizA, leadId, src.id));
      expect(r.reason).toBe('called');
      expect(sentBody.user_config.user_phone_number).toBe('+919830010002');
      expect(sentBody.app_config.agent_variables).toMatchObject({ lead_id: leadId, lead_name: 'Asha Rao', campaign_id: '', agent_name: 'Maya' });
      expect(sentBody.webhook_config.url).toContain('https://api.example.test/webhooks/sarvam?call_id=');
      const call = await env.DB.prepare('SELECT interaction_id FROM calls WHERE lead_id = ?').bind(leadId).first<any>();
      expect(call.interaction_id).toBe('att_instant');
    });

    it('outside calling hours: delays until the window (≤12h hops) and does not dial', async () => {
      const src = await seedSource(bizA, 'form');
      const leadId = await seedLead(bizA, '919830010003', src.id);
      const strictEnv = { ...env, DEV_ALLOW_ANY_CALLING_HOURS: 'false' } as any;
      // 23:30 IST = 18:00 UTC: TRAI clamp makes the 0-24 window 9-21, so the next window is ~10h away.
      const late = new Date('2026-10-10T18:00:00Z');
      const r = await processInstantCallJob(strictEnv, job(bizA, leadId, src.id), { now: late });
      expect(r.action).toBe('requeue');
      expect(r.reason).toBe('outside_hours');
      expect(r.delaySeconds).toBeGreaterThan(3600);
      expect(r.delaySeconds).toBeLessThanOrEqual(12 * 3600);
      expect(r.message?.notified).toBe(true);
      expect(await env.DB.prepare('SELECT id FROM calls WHERE lead_id = ?').bind(leadId).first()).toBeNull();
      const notif = await env.DB.prepare("SELECT body FROM notifications WHERE route = ?").bind(`/leads/${leadId}`).first<any>();
      expect(notif.body).toContain('when calling hours start');

      // The chained message does not notify again.
      const before = await env.DB.prepare('SELECT COUNT(*) AS n FROM notifications WHERE route = ?').bind(`/leads/${leadId}`).first<any>();
      await processInstantCallJob(strictEnv, r.message!, { now: late });
      const after = await env.DB.prepare('SELECT COUNT(*) AS n FROM notifications WHERE route = ?').bind(`/leads/${leadId}`).first<any>();
      expect(after.n).toBe(before.n);
    });

    it('consumer re-sends a delayed message (not message.retry) and acks', async () => {
      const src = await seedSource(bizA, 'form');
      const leadId = await seedLead(bizA, '919830010004', src.id);
      const { e, sent } = queueEnv({ ...env, DEV_ALLOW_ANY_CALLING_HOURS: 'false' });
      const body = job(bizA, leadId, src.id);
      const ack = vi.fn();
      const retry = vi.fn();
      // Make it outside hours regardless of the real clock: the agent's window is empty.
      await env.DB.prepare('UPDATE agents SET calling_hours_start = 21, calling_hours_end = 21 WHERE business_id = ?').bind(bizA).run();
      try {
        await handleInstantCallMessages([{ body, ack, retry } as any], e);
      } finally {
        await env.DB.prepare('UPDATE agents SET calling_hours_start = 0, calling_hours_end = 24 WHERE business_id = ?').bind(bizA).run();
      }
      expect(ack).toHaveBeenCalled();
      expect(retry).not.toHaveBeenCalled();
      expect(sent).toHaveLength(1);
      expect(sent[0].opts.delaySeconds).toBeGreaterThan(0);
      expect(sent[0].opts.delaySeconds).toBeLessThanOrEqual(12 * 3600);
    });

    it('skips do-not-call leads and tells the owner', async () => {
      const src = await seedSource(bizA, 'form');
      const leadId = await seedLead(bizA, '919830010005', src.id, 'dnc');
      const r = await processInstantCallJob(env as any, job(bizA, leadId, src.id));
      expect(r).toEqual({ action: 'ack', reason: 'do_not_call' });
      expect(await env.DB.prepare('SELECT id FROM calls WHERE lead_id = ?').bind(leadId).first()).toBeNull();
      const notif = await env.DB.prepare("SELECT body FROM notifications WHERE route = ?").bind(`/leads/${leadId}`).first<any>();
      expect(notif.body).toContain('do-not-call');
    });

    it('no minutes headroom: no call, owner told to add minutes', async () => {
      const biz = 'biz_stl_nomin';
      await env.DB.batch([
        env.DB.prepare("INSERT OR REPLACE INTO businesses (id, name) VALUES (?, 'No Minutes')").bind(biz),
        env.DB.prepare("INSERT OR REPLACE INTO agents (id, business_id, name, role, calling_hours_start, calling_hours_end) VALUES ('agt_nomin', ?, 'A', 'B', 0, 24)").bind(biz),
        env.DB.prepare("INSERT OR REPLACE INTO usage (id, business_id, plan_name, included_minutes, minutes_used) VALUES ('usg_nomin', ?, 'Trial', 30, 28)").bind(biz),
      ]);
      const src = await seedSource(biz, 'form');
      const leadId = await seedLead(biz, '919830010006', src.id);
      const r = await processInstantCallJob(env as any, job(biz, leadId, src.id));
      expect(r).toEqual({ action: 'ack', reason: 'exhausted_minutes' });
      expect(await env.DB.prepare('SELECT id FROM calls WHERE lead_id = ?').bind(leadId).first()).toBeNull();
      const notif = await env.DB.prepare("SELECT body FROM notifications WHERE route = ?").bind(`/leads/${leadId}`).first<any>();
      expect(notif.body).toContain('add calling minutes');
    });

    it('concurrency cap: waits and retries shortly', async () => {
      const biz = 'biz_stl_busy';
      await env.DB.batch([
        env.DB.prepare("INSERT OR REPLACE INTO businesses (id, name) VALUES (?, 'Busy')").bind(biz),
        env.DB.prepare("INSERT OR REPLACE INTO agents (id, business_id, name, role, calling_hours_start, calling_hours_end) VALUES ('agt_busy', ?, 'A', 'B', 0, 24)").bind(biz),
        env.DB.prepare("INSERT OR REPLACE INTO leads (id, business_id, name, phone) VALUES ('x', ?, 'x', '919830010099')").bind(biz),
        ...[1, 2, 3, 4, 5].map((i) => env.DB.prepare(
          `INSERT OR REPLACE INTO calls (id, business_id, lead_id, lead_name, lead_phone, status, started_at) VALUES (?, ?, 'x', 'x', 'x', 'calling', datetime('now'))`
        ).bind(`call_busy_${i}`, biz)),
      ]);
      const src = await seedSource(biz, 'form');
      const leadId = await seedLead(biz, '919830010007', src.id);
      const r = await processInstantCallJob(env as any, job(biz, leadId, src.id));
      expect(r.action).toBe('requeue');
      expect(r.reason).toBe('concurrency_limit');
      expect(r.delaySeconds).toBeLessThanOrEqual(30);
    });

    it('auto-call switched off or source revoked before the job runs: no call', async () => {
      const src = await seedSource(bizA, 'form');
      const leadId = await seedLead(bizA, '919830010008', src.id);
      await env.DB.prepare('UPDATE lead_sources SET auto_call = 0 WHERE id = ?').bind(src.id).run();
      expect((await processInstantCallJob(env as any, job(bizA, leadId, src.id))).reason).toBe('auto_call_off');
      await env.DB.prepare("UPDATE lead_sources SET auto_call = 1, revoked_at = datetime('now') WHERE id = ?").bind(src.id).run();
      expect((await processInstantCallJob(env as any, job(bizA, leadId, src.id))).reason).toBe('auto_call_off');
      expect(await env.DB.prepare('SELECT id FROM calls WHERE lead_id = ?').bind(leadId).first()).toBeNull();
    });

    it('retryable dial failures retry with backoff; terminal ones stop', async () => {
      const src = await seedSource(bizA, 'form');
      const leadId = await seedLead(bizA, '919830010009', src.id);
      const realEnv = { ...env, SARVAM_API_KEY: 'real-key', SARVAM_ORG_ID: 'org', SARVAM_WORKSPACE_ID: 'ws', SARVAM_ADMISSIONS_APP_ID: 'app' } as any;
      vi.spyOn(globalThis, 'fetch').mockImplementation(async () => new Response('busy', { status: 503 }));
      const r1 = await processInstantCallJob(realEnv, job(bizA, leadId, src.id));
      expect(r1.action).toBe('requeue');
      expect(r1.message?.attempts).toBe(1);
      // The failed dial (never rang) doesn't count as "already called".
      const r2 = await processInstantCallJob(realEnv, r1.message!);
      expect(r2.action).toBe('requeue');
      const r3 = await processInstantCallJob(realEnv, r2.message!);
      expect(r3.action).toBe('ack');
      expect(r3.reason).toContain('dial_failed_terminal');
    });

    it('the queue entrypoint routes instant_call messages to the instant handler', async () => {
      const src = await seedSource(bizA, 'form');
      const leadId = await seedLead(bizA, '919830010010', src.id);
      const ack = vi.fn();
      const retry = vi.fn();
      const worker = app as any;
      await worker.queue({ queue: 'callpilot-campaign-dispatch', messages: [{ body: job(bizA, leadId, src.id), ack, retry }] }, env);
      expect(ack).toHaveBeenCalled();
      expect(await env.DB.prepare('SELECT id FROM calls WHERE lead_id = ?').bind(leadId).first()).not.toBeNull();
    });

    it('notification copy', () => {
      expect(enquiryNoticeText('calling', 'Ravi Kumar')).toEqual({ title: 'New enquiry from Ravi', body: 'Your AI employee is calling them now.' });
    });
  });
});
