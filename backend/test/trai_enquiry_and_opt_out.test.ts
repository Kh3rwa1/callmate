import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { env } from 'cloudflare:test';
import { migrateTestDb } from './setup-db';
import { useIndianBusinessHours, useRealClock } from './clock';
import worker from '../src/index';
import { signJWT } from '../src/auth';
import { processCampaignJob, sarvamWebhookToken } from '../src/services/campaign_queue';
import {
  checkCallCompliance,
  enquiryCallableUntil,
  isOptOutRequest,
  ENQUIRY_VALID_DAYS,
} from '../src/services/compliance';
import { CONSENT_TEXT_VERSIONS } from '../src/services/consent';

const jwtSecret = 'test-jwt-signing-secret-key-32chars-min-length';
const bizId = 'biz_trai7';
const userId = 'usr_trai7';
const ownerPhone = '919830077777';
let token: string;

let seq = 0;
async function seedLead(opts: { consent?: string; enquiryAgo?: string | null; createdAgo?: string } = {}): Promise<string> {
  const id = `lead_trai7_${++seq}_${crypto.randomUUID().slice(0, 6)}`;
  const phone = `91710${String(Date.now() % 100000).padStart(5, '0')}${String(seq).padStart(2, '0')}`;
  await env.DB.prepare(
    `INSERT INTO leads (id, business_id, name, phone, status, consent, last_enquiry_at, created_at)
     VALUES (?, ?, 'Mitali Sen', ?, 'new', ?,
             CASE WHEN ? IS NULL THEN NULL ELSE datetime('now', ?) END, datetime('now', ?))`
  ).bind(
    id, bizId, phone, opts.consent ?? 'explicit_opt_in',
    opts.enquiryAgo ?? null, opts.enquiryAgo ?? null, opts.createdAgo ?? '-1 minutes',
  ).run();
  return id;
}

const req = (path: string, init: RequestInit = {}) => new Request(`http://localhost${path}`, {
  ...init,
  headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}`, 'cf-connecting-ip': '203.0.113.9' },
});

const manualCall = (leadId: string, body?: unknown) =>
  worker.fetch(req(`/leads/${leadId}/call`, { method: 'POST', body: body === undefined ? undefined : JSON.stringify(body) }), env);

beforeAll(async () => {
  useIndianBusinessHours();
  await migrateTestDb();
  await env.DB.batch([
    env.DB.prepare("INSERT OR REPLACE INTO businesses (id, name) VALUES (?, 'Sen Tutorials')").bind(bizId),
    env.DB.prepare('INSERT OR REPLACE INTO users (id, phone, business_id) VALUES (?, ?, ?)').bind(userId, ownerPhone, bizId),
    env.DB.prepare(
      `INSERT OR REPLACE INTO agents (id, business_id, name, role, status, calling_hours_start, calling_hours_end, voice, languages)
       VALUES ('agt_trai7', ?, 'Riya', 'Admissions', 'active', 9, 21, 'Warm · Female', '["Bengali","English"]')`
    ).bind(bizId),
    env.DB.prepare("INSERT OR REPLACE INTO usage (id, business_id, included_minutes, minutes_used) VALUES ('usg_trai7', ?, 100000, 0)").bind(bizId),
  ]);
  token = await signJWT({ sub: userId, phone: ownerPhone, business_id: bizId, type: 'access' }, jwtSecret, 3600);
});

afterAll(useRealClock);

describe('in-call opt-out on the real Sarvam payload', () => {
  it("reads final_agent_variables and interaction_transcript[].en_text", () => {
    expect(isOptOutRequest({ final_agent_variables: { intent: 'opt_out' } })).toBe(true);
    expect(isOptOutRequest({ final_agent_variables: { intent: 'interested', next_action: 'do_not_call' } })).toBe(true);
    expect(isOptOutRequest({
      interaction_transcript: [
        { role: 'agent', en_text: 'Hello, this is Riya from Sen Tutorials.' },
        { role: 'user', en_text: "Please don't call me again." },
      ],
    })).toBe(true);
  });

  it("ignores the agent's own words", () => {
    expect(isOptOutRequest({
      interaction_transcript: [
        { role: 'agent', en_text: 'You can say stop calling at any time.' },
        { role: 'user', en_text: 'Tell me the fees.' },
      ],
    })).toBe(false);
  });

  it('understands Bengali, in script and romanised', () => {
    expect(isOptOutRequest({ transcript: [{ role: 'user', text: 'আর কল করবেন না' }] })).toBe(true);
    expect(isOptOutRequest({ transcript: [{ role: 'user', text: 'আমার নম্বর মুছে দিন' }] })).toBe(true);
    expect(isOptOutRequest({ transcript: [{ role: 'user', text: 'ar call korben na' }] })).toBe(true);
    expect(isOptOutRequest({ transcript: [{ role: 'user', text: 'কাল বিকেলে কল করবেন' }] })).toBe(false);
  });

  it('marks the lead do-not-call and drafts no WhatsApp, even when the agent wrote one', async () => {
    const leadId = await seedLead();
    const callId = `call_trai7_${crypto.randomUUID().slice(0, 8)}`;
    await env.DB.prepare(
      `INSERT INTO calls (id, business_id, lead_id, lead_name, lead_phone, status, interaction_id, started_at)
       VALUES (?, ?, ?, 'Mitali Sen', '919800000000', 'calling', ?, datetime('now'))`
    ).bind(callId, bizId, leadId, `att_${callId}`).run();
    const tok = await sarvamWebhookToken(env.SARVAM_WEBHOOK_SECRET!, callId);
    const res = await worker.fetch(new Request(`http://localhost/webhooks/sarvam?call_id=${callId}&token=${tok}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        attempt_id: `att_${callId}`, status: 'connected', duration: 31.2,
        final_agent_variables: {
          call_id: callId, lead_score: '5', intent: 'not_interested', temperature: 'cold',
          summary: 'Asked not to be called.', next_action: 'none',
          whatsapp_followup_required: 'true', whatsapp_message: 'Hi Mitali, here are our batches.',
        },
        interaction_transcript: [
          { role: 'agent', en_text: 'Hello Mitali, this is Riya.' },
          { role: 'user', en_text: 'Stop calling me.' },
        ],
      }),
    }), env);
    expect(res.status).toBe(200);
    const lead = await env.DB.prepare('SELECT do_not_call, consent FROM leads WHERE id = ?').bind(leadId).first<any>();
    expect(lead).toEqual({ do_not_call: 1, consent: 'opt_out' });
    const call = await env.DB.prepare('SELECT follow_up_id FROM calls WHERE id = ?').bind(callId).first<any>();
    expect(call.follow_up_id).toBeNull();
    const drafts = await env.DB.prepare('SELECT COUNT(*) AS n FROM followups WHERE lead_id = ?').bind(leadId).first<any>();
    expect(drafts.n).toBe(0);
  });
});

describe('TRAI 7-day enquiry window', () => {
  it('dates enquiry-based leads and leaves other bases alone', () => {
    const until = enquiryCallableUntil({ consent: 'explicit_opt_in', last_enquiry_at: '2026-10-01 10:00:00' });
    expect(until?.toISOString()).toBe('2026-10-08T10:00:00.000Z');
    expect(ENQUIRY_VALID_DAYS).toBe(7);
    // Marked 'inquiry' by the owner: dated from when the lead was added.
    expect(enquiryCallableUntil({ consent: 'inquiry', created_at: '2026-10-01 10:00:00' })?.toISOString())
      .toBe('2026-10-08T10:00:00.000Z');
    expect(enquiryCallableUntil({ consent: 'implicit_inquiry', created_at: '2026-10-01 10:00:00' })).not.toBeNull();
    expect(enquiryCallableUntil({ consent: 'existing_customer', last_enquiry_at: '2026-10-01 10:00:00' })).toBeNull();
    expect(enquiryCallableUntil({ consent: 'unknown', created_at: '2026-10-01 10:00:00' })).toBeNull();
    expect(enquiryCallableUntil({ consent: 'explicit_opt_in', created_at: '2026-10-01 10:00:00' })).toBeNull();
  });

  it('blocks a call 8 days after the enquiry, allows one after 6', async () => {
    const check = (leadId: string) => checkCallCompliance(env.DB, {
      businessId: bizId, leadId, hoursStart: 0, hoursEnd: 24, skipTraiClamp: true,
    });
    expect(await check(await seedLead({ enquiryAgo: '-8 days' })))
      .toEqual({ allowed: false, reason: 'enquiry_expired', reschedule: false });
    expect((await check(await seedLead({ enquiryAgo: '-6 days' }))).allowed).toBe(true);
    expect((await check(await seedLead({ consent: 'inquiry', createdAgo: '-9 days' }))).reason).toBe('enquiry_expired');
    expect((await check(await seedLead({ consent: 'existing_customer', enquiryAgo: '-30 days' }))).allowed).toBe(true);
  });

  it('refuses the manual call and shows the end of the window on the lead', async () => {
    const expired = await seedLead({ enquiryAgo: '-8 days' });
    const res = await manualCall(expired);
    expect(res.status).toBe(409);
    expect(((await res.json()) as any).code).toBe('enquiry_expired');

    const fresh = await seedLead({ enquiryAgo: '-1 days' });
    const lead = (await (await worker.fetch(req(`/leads/${fresh}`), env)).json()) as any;
    expect(lead.enquiry_expires_at).toMatch(/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/);
    const unknown = await seedLead({ consent: 'unknown' });
    expect(((await (await worker.fetch(req(`/leads/${unknown}`), env)).json()) as any).enquiry_expires_at).toBeNull();
  });

  it('campaigns skip an expired lead as skipped_expired', async () => {
    const leadId = await seedLead({ enquiryAgo: '-10 days' });
    const campId = `cmp_trai7_${crypto.randomUUID().slice(0, 6)}`;
    await env.DB.batch([
      env.DB.prepare(
        `INSERT INTO campaigns (id, business_id, purpose, status, total_leads, calling_hours_start, calling_hours_end)
         VALUES (?, ?, 'trai7', 'running', 1, 0, 24)`
      ).bind(campId, bizId),
      env.DB.prepare(`INSERT INTO campaign_leads (campaign_id, lead_id, status) VALUES (?, ?, 'queued')`).bind(campId, leadId),
    ]);
    const out = await processCampaignJob(env as any, {
      campaign_id: campId, lead_id: leadId, business_id: bizId, idempotency_key: 'k', attempts: 0,
    } as any);
    expect(out.reason).toBe('enquiry_expired');
    const row = await env.DB.prepare('SELECT status FROM campaign_leads WHERE campaign_id = ? AND lead_id = ?')
      .bind(campId, leadId).first<any>();
    expect(row.status).toBe('skipped_expired');
    const camp = await env.DB.prepare('SELECT status FROM campaigns WHERE id = ?').bind(campId).first<any>();
    expect(camp.status).toBe('completed');
  });
});

describe('"Call now" on a lead with unknown consent', () => {
  it("needs the owner's confirmation and records it", async () => {
    const leadId = await seedLead({ consent: 'unknown' });
    const refused = await manualCall(leadId);
    expect(refused.status).toBe(409);
    expect(((await refused.json()) as any).code).toBe('consent_required');
    const calls = await env.DB.prepare('SELECT COUNT(*) AS n FROM calls WHERE lead_id = ?').bind(leadId).first<any>();
    expect(calls.n).toBe(0);

    const ok = await manualCall(leadId, { consent_attestation: true });
    expect(ok.status).toBe(200);
    const { results } = await env.DB.prepare('SELECT * FROM consent_events WHERE lead_id = ?').bind(leadId).all<any>();
    expect(results).toEqual([expect.objectContaining({
      consent_value: 'owner_attested', source: 'import_attestation', text_version: CONSENT_TEXT_VERSIONS.callAttestation,
    })]);
    expect(results[0].ip_hash).toBeTruthy();
  });

  it('calls leads with a known basis without asking', async () => {
    const res = await manualCall(await seedLead({ consent: 'explicit_opt_in', enquiryAgo: '-2 hours' }));
    expect(res.status).toBe(200);
  });
});
