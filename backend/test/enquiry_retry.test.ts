import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { env } from 'cloudflare:test';
import { migrateTestDb } from './setup-db';
import { useIndianBusinessHours, useRealClock } from './clock';
import app from '../src/index';
import { sarvamWebhookToken } from '../src/services/campaign_queue';
import { RETRY_SPACING_SECONDS } from '../src/services/call_outcomes';
import { processInstantCallJob, type InstantCallMessage } from '../src/services/lead_capture';

const bizId = 'biz_retry';
let seq = 0;

/** Captures what the webhook puts on the dispatch queue. */
function queueEnv() {
  const sent: { body: InstantCallMessage; opts?: { delaySeconds?: number } }[] = [];
  const e = { ...env, CAMPAIGN_QUEUE: { send: async (body: any, opts?: any) => { sent.push({ body, opts }); }, sendBatch: async () => {} } } as any;
  return { e, sent };
}

/** D1 time on the faked clock: SQL datetime('now') is the real one, and after noon IST it is later. */
function minutesAgo(m: number): string {
  return new Date(Date.now() - m * 60_000).toISOString().slice(0, 19).replace('T', ' ');
}

async function seedEnquiry(opts: { autoCall?: number } = {}): Promise<{ leadId: string; sourceId: string }> {
  const n = ++seq;
  const sourceId = `lsrc_retry_${n}`;
  const leadId = `lead_retry_${n}`;
  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO lead_sources (id, business_id, kind, public_slug, auto_call) VALUES (?, ?, 'form', ?, ?)`
    ).bind(sourceId, bizId, `slug_retry_${n}_${crypto.randomUUID().slice(0, 6)}`, opts.autoCall ?? 1),
    env.DB.prepare(
      `INSERT INTO leads (id, business_id, name, phone, status, consent, lead_source_id, last_enquiry_at)
       VALUES (?, ?, 'Priya Das', ?, 'new', 'explicit_opt_in', ?, ?)`
    ).bind(leadId, bizId, `9198300900${String(n).padStart(2, '0')}`, sourceId, minutesAgo(10)),
  ]);
  return { leadId, sourceId };
}

async function seedCall(leadId: string, opts: { campaignId?: string } = {}): Promise<string> {
  const id = `call_retry_${++seq}`;
  await env.DB.prepare(
    `INSERT INTO calls (id, business_id, lead_id, lead_name, lead_phone, campaign_id, status, interaction_id, started_at)
     VALUES (?, ?, ?, 'Priya Das', '919830090000', ?, 'calling', ?, ?)`
  ).bind(id, bizId, leadId, opts.campaignId ?? null, `att_${id}`, minutesAgo(1)).run();
  return id;
}

async function webhook(e: any, callId: string, status: string, duration = 0) {
  const token = await sarvamWebhookToken(env.SARVAM_WEBHOOK_SECRET!, callId);
  return app.fetch(new Request(`http://localhost/webhooks/sarvam?call_id=${callId}&token=${token}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ attempt_id: `att_${callId}`, status, duration }),
  }), e);
}

beforeAll(async () => {
  useIndianBusinessHours();
  await migrateTestDb();
  await env.DB.batch([
    env.DB.prepare("INSERT OR REPLACE INTO businesses (id, name) VALUES (?, 'Das Tutorials')").bind(bizId),
    env.DB.prepare("INSERT OR REPLACE INTO users (id, phone, business_id) VALUES ('usr_retry', '919830099999', ?)").bind(bizId),
    env.DB.prepare(
      `INSERT OR REPLACE INTO agents (id, business_id, name, role, status, calling_hours_start, calling_hours_end)
       VALUES ('agt_retry', ?, 'Riya', 'Admissions', 'active', 9, 21)`
    ).bind(bizId),
    env.DB.prepare("INSERT OR REPLACE INTO usage (id, business_id, included_minutes, minutes_used) VALUES ('usg_retry', ?, 1000, 0)").bind(bizId),
  ]);
});

afterAll(useRealClock);

describe('speed-to-lead tries an unanswered enquiry again', () => {
  it('queues another try 3 hours after no answer, without telling the owner twice', async () => {
    const { leadId, sourceId } = await seedEnquiry();
    const callId = await seedCall(leadId);
    const { e, sent } = queueEnv();
    expect((await webhook(e, callId, 'no_answer')).status).toBe(200);
    expect(sent).toHaveLength(1);
    expect(sent[0].opts?.delaySeconds).toBe(RETRY_SPACING_SECONDS);
    expect(sent[0].body).toMatchObject({
      kind: 'instant_call', business_id: bizId, lead_id: leadId, lead_source_id: sourceId,
      idempotency_key: `instant-retry:${callId}`, attempts: 0, notified: true,
    });

    // The retry job dials through the normal guards.
    const out = await processInstantCallJob(e, sent[0].body);
    expect(out).toMatchObject({ action: 'ack', reason: 'mock_dial' });
  });

  it('busy is retried too; answered and voicemail calls are not', async () => {
    const busy = await seedEnquiry();
    const q1 = queueEnv();
    await webhook(q1.e, await seedCall(busy.leadId), 'busy');
    expect(q1.sent).toHaveLength(1);

    const answered = await seedEnquiry();
    const q2 = queueEnv();
    await webhook(q2.e, await seedCall(answered.leadId), 'completed', 75);
    expect(q2.sent).toHaveLength(0);

    const voicemail = await seedEnquiry();
    const q3 = queueEnv();
    await webhook(q3.e, await seedCall(voicemail.leadId), 'voicemail', 30);
    expect(q3.sent).toHaveLength(0);
  });

  it('stops after 3 calls since the enquiry', async () => {
    const { leadId } = await seedEnquiry();
    await seedCall(leadId);
    await seedCall(leadId);
    const third = await seedCall(leadId);
    const { e, sent } = queueEnv();
    await webhook(e, third, 'no_answer');
    expect(sent).toHaveLength(0);
  });

  it('not when auto-call is off, nor for campaign calls', async () => {
    const off = await seedEnquiry({ autoCall: 0 });
    const q1 = queueEnv();
    await webhook(q1.e, await seedCall(off.leadId), 'no_answer');
    expect(q1.sent).toHaveLength(0);

    const inCampaign = await seedEnquiry();
    await env.DB.prepare(
      `INSERT INTO campaigns (id, business_id, purpose, status, total_leads, calling_hours_start, calling_hours_end)
       VALUES ('cmp_retry', ?, 'retry', 'running', 1, 0, 24)`
    ).bind(bizId).run();
    const q2 = queueEnv();
    await webhook(q2.e, await seedCall(inCampaign.leadId, { campaignId: 'cmp_retry' }), 'no_answer');
    expect(q2.sent.filter((m) => m.body.kind === 'instant_call')).toHaveLength(0);
  });

  it('stands down when the owner called them in the meantime', async () => {
    const { leadId } = await seedEnquiry();
    const callId = await seedCall(leadId);
    const { e, sent } = queueEnv();
    await webhook(e, callId, 'no_answer');
    const retry = { ...sent[0].body, enqueued_at: '2000-01-01 00:00:00' };
    await seedCall(leadId); // the owner's own AI call after the retry was queued
    expect(await processInstantCallJob(e, retry)).toMatchObject({ action: 'ack', reason: 'already_called' });
  });
});
