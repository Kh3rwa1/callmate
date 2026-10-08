import { describe, it, expect, beforeAll } from 'vitest';
import { env } from 'cloudflare:test';
import { migrateTestDb } from './setup-db';
import app from '../src/index';
import { sarvamWebhookToken } from '../src/services/campaign_queue';

// Shape documented at docs.sarvam.ai/conversations/api/instant-outbound/webhook-payload (unsigned).
describe('Sarvam instant-outbound webhook (real payload, URL token auth)', () => {
  const bizId = 'biz_real_payload';
  const leadId = 'lead_real_payload';
  const callId = 'call_real_payload';
  const attemptId = '44b4f89d-252b-4585-ad2e-0ed5842cc6c5';

  beforeAll(async () => {
    await migrateTestDb();
    await env.DB.batch([
      env.DB.prepare("INSERT OR REPLACE INTO businesses (id, name) VALUES (?, 'Apex Academy')").bind(bizId),
      env.DB.prepare("INSERT OR REPLACE INTO leads (id, business_id, name, phone, status) VALUES (?, ?, 'Rahul Das', '919830011111', 'calling')").bind(leadId, bizId),
      env.DB.prepare("INSERT OR REPLACE INTO usage (id, business_id, plan_name, included_minutes, renews_at, price_inr, minutes_used, calls_made, rate_per_minute_inr) VALUES ('usg_real', ?, 'Founding', 1000, datetime('now', '+30 days'), 4999, 0, 0, 6)").bind(bizId),
      env.DB.prepare("INSERT OR REPLACE INTO calls (id, business_id, lead_id, lead_name, lead_phone, status, interaction_id, started_at) VALUES (?, ?, ?, 'Rahul Das', '919830011111', 'calling', ?, datetime('now'))").bind(callId, bizId, leadId, attemptId),
    ]);
  });

  const payload = {
    attempt_id: attemptId,
    status: 'connected',
    channel_info: { channel_type: 'v2v', channel_provider: 'vobiz', agent_phone_number: '+917971442975' },
    duration: 95.4,
    interaction_id: '20261008/abc',
    failure_reason: null,
    final_agent_variables: {
      call_id: callId, lead_name: 'Rahul Das',
      lead_score: '82', intent: 'interested', temperature: 'hot',
      summary: 'Rahul wants the NEET evening batch details.', next_action: 'send_whatsapp',
      whatsapp_followup_required: 'true', whatsapp_message: 'Hi Rahul, here are the details.', callback_at: '',
    },
    webhook_config: { url: 'https://x.test/webhooks/sarvam', metadata: { call_id: callId } },
    interaction_transcript: [{ role: 'agent', en_text: 'Hello Rahul' }, { role: 'user', en_text: 'Hi' }],
  };

  const post = (qs: string) => app.fetch(
    new Request(`http://localhost/webhooks/sarvam${qs}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload),
    }),
    env,
  );

  it('rejects a wrong token, and a valid token for a different call', async () => {
    expect((await post(`?call_id=${callId}&token=deadbeef`)).status).toBe(401);
    const other = await sarvamWebhookToken(env.SARVAM_WEBHOOK_SECRET!, 'call_other');
    expect((await post(`?call_id=${callId}&token=${other}`)).status).toBe(401);
  });

  it('accepts the documented payload and scores the lead from string-typed agent variables', async () => {
    const token = await sarvamWebhookToken(env.SARVAM_WEBHOOK_SECRET!, callId);
    const res = await post(`?call_id=${callId}&token=${token}`);
    expect(res.status).toBe(200);

    const call = await env.DB.prepare('SELECT status, score, temperature, intent, duration_seconds, follow_up_id FROM calls WHERE id = ?').bind(callId).first<any>();
    expect(call).toMatchObject({ status: 'completed', score: 82, temperature: 'hot', intent: 'interested' });
    expect(call.follow_up_id).toBeTruthy();
    const fu = await env.DB.prepare('SELECT message FROM followups WHERE id = ?').bind(call.follow_up_id).first<any>();
    expect(fu.message).toBe('Hi Rahul, here are the details.');
    const lead = await env.DB.prepare('SELECT status, score FROM leads WHERE id = ?').bind(leadId).first<any>();
    expect(lead).toMatchObject({ status: 'called', score: 82 });
  });
});
