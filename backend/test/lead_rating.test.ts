import { describe, it, expect, beforeAll } from 'vitest';
import { env } from 'cloudflare:test';
import { migrateTestDb } from './setup-db';
import app from '../src/index';
import { sarvamWebhookToken } from '../src/services/campaign_queue';
import { keepsLeadRating } from '../src/services/call_outcomes';

// A lead's rating must only change on a real answer. Real staging case (2026-10-10): a hot lead
// (score 90, "wants to start tomorrow") was buried as cold by a 4 s call with invalid output and then
// a short inconclusive call, so the owner no longer saw them under "ready to buy".

const BIZ = 'biz_rating';

async function seedLead(id: string, temperature: string | null, score: number | null) {
  await env.DB.prepare(
    `INSERT OR REPLACE INTO leads (id, business_id, name, phone, status, consent, temperature, score, summary)
     VALUES (?, ?, 'Asha', ?, 'called', 'explicit_opt_in', ?, ?, ?)`
  ).bind(id, BIZ, `91981119${id.slice(-4)}`, temperature, score, temperature ? 'Wants to start tomorrow' : null).run();
}

async function seedCall(callId: string, leadId: string) {
  await env.DB.prepare(
    `INSERT OR REPLACE INTO calls (id, business_id, lead_id, lead_name, lead_phone, status, started_at)
     VALUES (?, ?, ?, 'Asha', '919811190000', 'calling', datetime('now'))`
  ).bind(callId, BIZ, leadId).run();
}

async function postResult(callId: string, output: Record<string, unknown>, duration = 40) {
  const token = await sarvamWebhookToken(env.SARVAM_WEBHOOK_SECRET!, callId);
  const res = await app.fetch(new Request(`http://localhost/webhooks/sarvam?call_id=${callId}&token=${token}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ status: 'completed', duration_seconds: duration, output_variables: output }),
  }), env);
  expect(res.status).toBe(200);
}

const lead = (id: string) =>
  env.DB.prepare('SELECT temperature, score, summary, status FROM leads WHERE id = ?').bind(id).first<any>();
const call = (id: string) =>
  env.DB.prepare('SELECT temperature, score, summary FROM calls WHERE id = ?').bind(id).first<any>();

const valid = (o: Record<string, unknown>) => ({
  lead_score: 20, temperature: 'cold', intent: 'unknown', summary: 'Busy, asked to call later.',
  next_action: 'retry_call', whatsapp_followup_required: false, ...o,
});

describe('lead rating after a call', () => {
  beforeAll(async () => {
    await migrateTestDb();
    await env.DB.prepare("INSERT OR REPLACE INTO businesses (id, name) VALUES (?, 'Rating Biz')").bind(BIZ).run();
  });

  it('keepsLeadRating rules', () => {
    expect(keepsLeadRating(false, { intent: 'interested', temperature: 'hot' }, 'cold')).toBe(true); // invalid output
    expect(keepsLeadRating(true, { intent: 'unknown', temperature: 'cold' }, 'hot')).toBe(true); // inconclusive downgrade
    expect(keepsLeadRating(true, { intent: 'unknown', temperature: 'cold' }, 'warm')).toBe(true);
    expect(keepsLeadRating(true, { intent: 'unknown', temperature: 'hot' }, 'warm')).toBe(false); // upgrade is fine
    expect(keepsLeadRating(true, { intent: 'unknown', temperature: 'cold' }, null)).toBe(false); // first rating
    expect(keepsLeadRating(true, { intent: 'not_interested', temperature: 'cold' }, 'hot')).toBe(false); // clear answer
    expect(keepsLeadRating(true, { intent: 'opt_out', temperature: 'cold' }, 'hot')).toBe(false);
  });

  it('an invalid (flagged) output never changes the lead', async () => {
    await seedLead('lead_r_0001', 'hot', 90);
    await seedCall('call_r_0001', 'lead_r_0001');
    await postResult('call_r_0001', { lead_score: 'not-a-number', temperature: 'super_hot' }, 4);
    expect(await call('call_r_0001')).toMatchObject({ temperature: 'cold', score: 0 });
    expect(await lead('lead_r_0001')).toMatchObject({ temperature: 'hot', score: 90, summary: 'Wants to start tomorrow', status: 'called' });
  });

  it('an inconclusive call does not bury a hot lead', async () => {
    await seedLead('lead_r_0002', 'hot', 90);
    await seedCall('call_r_0002', 'lead_r_0002');
    await postResult('call_r_0002', valid({}));
    expect(await call('call_r_0002')).toMatchObject({ temperature: 'cold', score: 20 });
    expect(await lead('lead_r_0002')).toMatchObject({ temperature: 'hot', score: 90, summary: 'Wants to start tomorrow' });
  });

  it('a clear "not interested" still downgrades the lead', async () => {
    await seedLead('lead_r_0003', 'hot', 90);
    await seedCall('call_r_0003', 'lead_r_0003');
    await postResult('call_r_0003', valid({ intent: 'not_interested', lead_score: 10, summary: 'Joined another institute.' }));
    expect(await lead('lead_r_0003')).toMatchObject({ temperature: 'cold', score: 10, summary: 'Joined another institute.' });
  });

  it('a better result upgrades the lead, and the first rating is always written', async () => {
    await seedLead('lead_r_0004', 'warm', 55);
    await seedCall('call_r_0004', 'lead_r_0004');
    await postResult('call_r_0004', valid({ intent: 'interested', temperature: 'hot', lead_score: 92, summary: 'Will pay tomorrow.' }));
    expect(await lead('lead_r_0004')).toMatchObject({ temperature: 'hot', score: 92 });

    await seedLead('lead_r_0005', null, null);
    await seedCall('call_r_0005', 'lead_r_0005');
    await postResult('call_r_0005', valid({}));
    expect(await lead('lead_r_0005')).toMatchObject({ temperature: 'cold', score: 20 });
  });
});
