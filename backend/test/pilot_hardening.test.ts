import { describe, it, expect, beforeAll } from 'vitest';
import { env } from 'cloudflare:test';
import { migrateTestDb } from './setup-db';
import app from '../src/index';
import { runMaintenance } from '../src/services/maintenance';
import { ingestKnowledge } from '../src/services/knowledge';

async function signWebhook(body: string, secret: string): Promise<string> {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    'raw',
    enc.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign']
  );
  const sig = await crypto.subtle.sign('HMAC', key, enc.encode(body));
  return Array.from(new Uint8Array(sig)).map((b) => b.toString(16).padStart(2, '0')).join('');
}

describe('Pilot Hardening Requirements', () => {
  const bizId = 'biz_pilot_test';

  beforeAll(async () => {
    await migrateTestDb(env.DB);
    await env.DB.prepare("INSERT INTO businesses (id, name, category) VALUES (?, 'Pilot Academy', 'education')")
      .bind(bizId).run();
  });

  // 1a. Sweeper threshold at 45 minutes
  it('1a. Sweeper keeps 25m calls in calling, but times out 50m calls', async () => {
    const leadId = 'lead_sweep_1';
    await env.DB.prepare(
      "INSERT INTO leads (id, business_id, name, phone) VALUES (?, ?, 'Sweep Lead', '919876543200')"
    ).bind(leadId, bizId).run();

    const call25m = 'call_sweep_25m';
    const call50m = 'call_sweep_50m';

    await env.DB.prepare(
      "INSERT INTO calls (id, business_id, lead_id, lead_name, lead_phone, status, started_at) VALUES (?, ?, ?, 'Lead 25m', '919876543201', 'calling', datetime('now', '-25 minutes'))"
    ).bind(call25m, bizId, leadId).run();

    await env.DB.prepare(
      "INSERT INTO calls (id, business_id, lead_id, lead_name, lead_phone, status, started_at) VALUES (?, ?, ?, 'Lead 50m', '919876543202', 'calling', datetime('now', '-50 minutes'))"
    ).bind(call50m, bizId, leadId).run();

    await runMaintenance(env);

    const row25m = await env.DB.prepare('SELECT status FROM calls WHERE id = ?').bind(call25m).first<any>();
    expect(row25m.status).toBe('calling');

    const row50m = await env.DB.prepare('SELECT status, failure_reason FROM calls WHERE id = ?').bind(call50m).first<any>();
    expect(row50m.status).toBe('timed_out');
    expect(row50m.failure_reason).toBe('no_webhook_45m');
  });

  // 1b. Late webhooks process billing & analysis; a CONNECTED late call completes a retry_pending lead
  it('1b. Late connected webhook for timed_out call bills, analyzes and completes the retry_pending lead', async () => {
    const campId = 'camp_late_1';
    const leadId = 'lead_late_1';
    const callId = 'call_late_1';

    await env.DB.prepare(
      "INSERT INTO campaigns (id, business_id, purpose, status, completed_leads, connected_leads) VALUES (?, ?, 'Late Camp', 'running', 0, 0)"
    ).bind(campId, bizId).run();

    await env.DB.prepare(
      "INSERT INTO leads (id, business_id, name, phone, status, temperature, score) VALUES (?, ?, 'Late Caller', '919876543203', 'calling', 'cold', 10)"
    ).bind(leadId, bizId).run();

    await env.DB.prepare(
      "INSERT INTO campaign_leads (campaign_id, lead_id, call_id, status, attempts) VALUES (?, ?, ?, 'retry_pending', 1)"
    ).bind(campId, leadId, callId).run();

    await env.DB.prepare(
      "INSERT INTO calls (id, business_id, lead_id, campaign_id, lead_name, lead_phone, status) VALUES (?, ?, ?, ?, 'Late Caller', '919876543203', 'timed_out')"
    ).bind(callId, bizId, leadId, campId).run();

    const payload = JSON.stringify({
      call_id: callId,
      status: 'completed',
      duration_seconds: 1500, // 25 minutes
      transcript: [{ role: 'agent', content: 'Hello' }],
      extracted_variables: {
        lead_score: 92,
        temperature: 'hot',
        summary: 'Excellent 25-minute consultation',
        intent: 'interested',
        next_action: 'book_appointment',
        whatsapp_followup_required: false,
      },
    });

    const hex = await signWebhook(payload, env.SARVAM_WEBHOOK_SECRET);

    const res = await app.fetch(
      new Request('http://localhost/webhooks/sarvam', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Sarvam-Signature': hex,
        },
        body: payload,
      }),
      env
    );
    expect(res.status).toBe(200);

    // Call MUST be updated with completed, duration, score
    const call = await env.DB.prepare('SELECT status, duration_seconds, score, temperature FROM calls WHERE id = ?').bind(callId).first<any>();
    expect(call.status).toBe('completed');
    expect(call.duration_seconds).toBe(1500);
    expect(call.score).toBe(92);
    expect(call.temperature).toBe('hot');

    // Lead MUST be updated
    const lead = await env.DB.prepare('SELECT status, score, temperature FROM leads WHERE id = ?').bind(leadId).first<any>();
    expect(lead.status).toBe('called');
    expect(lead.score).toBe(92);
    expect(lead.temperature).toBe('hot');

    // Usage ledger MUST record 25 minutes
    const usage = await env.DB.prepare('SELECT billed_minutes, billable_seconds FROM usage_ledger WHERE call_id = ?').bind(callId).first<any>();
    expect(usage.billed_minutes).toBe(25);
    expect(usage.billable_seconds).toBe(1500);

    // The call connected, so the lead the sweeper parked in retry_pending is now done (no re-dial)
    const cl = await env.DB.prepare('SELECT status FROM campaign_leads WHERE call_id = ?').bind(callId).first<any>();
    expect(cl.status).toBe('completed');

    // Campaign stats count it once, and the (single-lead) campaign completes
    const camp = await env.DB.prepare('SELECT completed_leads, connected_leads, hot_leads, status FROM campaigns WHERE id = ?').bind(campId).first<any>();
    expect(camp.completed_leads).toBe(1);
    expect(camp.connected_leads).toBe(1);
    expect(camp.hot_leads).toBe(1);
    expect(camp.status).toBe('completed');
  });

  // 2. Campaign stats not counted twice when Sarvam sends no_answer then completed
  it('2. Campaign stats not counted twice when Sarvam sends no_answer then completed', async () => {
    const campId = 'camp_double_count';
    const leadId = 'lead_double_count';
    const callId = 'call_double_count';

    await env.DB.prepare(
      "INSERT INTO campaigns (id, business_id, purpose, status, completed_leads, connected_leads, hot_leads) VALUES (?, ?, 'Double Count Camp', 'running', 0, 0, 0)"
    ).bind(campId, bizId).run();

    await env.DB.prepare(
      "INSERT INTO leads (id, business_id, name, phone, status, temperature, score) VALUES (?, ?, 'Double Lead', '919876543204', 'calling', 'cold', 0)"
    ).bind(leadId, bizId).run();

    await env.DB.prepare(
      "INSERT INTO campaign_leads (campaign_id, lead_id, call_id, status, attempts) VALUES (?, ?, ?, 'calling', 1)"
    ).bind(campId, leadId, callId).run();

    await env.DB.prepare(
      "INSERT INTO calls (id, business_id, lead_id, campaign_id, lead_name, lead_phone, status) VALUES (?, ?, ?, ?, 'Double Lead', '919876543204', 'calling')"
    ).bind(callId, bizId, leadId, campId).run();

    // 1st webhook: no_answer
    const payloadNoAnswer = JSON.stringify({
      call_id: callId,
      status: 'no_answer',
      duration_seconds: 0,
    });
    const hex1 = await signWebhook(payloadNoAnswer, env.SARVAM_WEBHOOK_SECRET);
    const res1 = await app.fetch(
      new Request('http://localhost/webhooks/sarvam', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-Sarvam-Signature': hex1 },
        body: payloadNoAnswer,
      }),
      env
    );
    expect(res1.status).toBe(200);

    const clAfter1 = await env.DB.prepare('SELECT status FROM campaign_leads WHERE call_id = ?').bind(callId).first<any>();
    expect(clAfter1.status).toBe('retry_pending');

    const campAfter1 = await env.DB.prepare('SELECT completed_leads, connected_leads FROM campaigns WHERE id = ?').bind(campId).first<any>();
    expect(campAfter1.completed_leads).toBe(0);
    expect(campAfter1.connected_leads).toBe(0);

    // 2nd webhook: completed (status differs, so event key is different)
    const payloadCompleted = JSON.stringify({
      call_id: callId,
      status: 'completed',
      duration_seconds: 60,
      extracted_variables: {
        lead_score: 95,
        temperature: 'hot',
        summary: 'Connected after initial signal',
        intent: 'interested',
        next_action: 'human_followup',
        whatsapp_followup_required: false,
      },
    });
    const hex2 = await signWebhook(payloadCompleted, env.SARVAM_WEBHOOK_SECRET);
    const res2 = await app.fetch(
      new Request('http://localhost/webhooks/sarvam', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-Sarvam-Signature': hex2 },
        body: payloadCompleted,
      }),
      env
    );
    expect(res2.status).toBe(200);

    // Campaign stats must NOT count twice because campaign_leads was already retry_pending
    const campAfter2 = await env.DB.prepare('SELECT completed_leads, connected_leads, hot_leads FROM campaigns WHERE id = ?').bind(campId).first<any>();
    expect(campAfter2.completed_leads).toBe(0);
    expect(campAfter2.connected_leads).toBe(0);
    expect(campAfter2.hot_leads).toBe(0);
  });

  // 3. Hot-lead notification row has no leading space
  it('3. Hot-lead notification row in DB is titled Hot Lead Alert (no leading space)', async () => {
    const leadId = 'lead_hot_notif';
    const callId = 'call_hot_notif';

    await env.DB.prepare(
      "INSERT INTO leads (id, business_id, name, phone, status, temperature, score) VALUES (?, ?, 'Hot Lead Notif', '919876543205', 'calling', 'warm', 50)"
    ).bind(leadId, bizId).run();

    await env.DB.prepare(
      "INSERT INTO calls (id, business_id, lead_id, lead_name, lead_phone, status) VALUES (?, ?, ?, 'Hot Lead Notif', '919876543205', 'calling')"
    ).bind(callId, bizId, leadId).run();

    const payload = JSON.stringify({
      call_id: callId,
      status: 'completed',
      duration_seconds: 120,
      extracted_variables: {
        lead_score: 98,
        temperature: 'hot',
        summary: 'Very interested in joining immediately',
        intent: 'interested',
        next_action: 'human_followup',
        whatsapp_followup_required: false,
      },
    });
    const hex = await signWebhook(payload, env.SARVAM_WEBHOOK_SECRET);
    const res = await app.fetch(
      new Request('http://localhost/webhooks/sarvam', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-Sarvam-Signature': hex },
        body: payload,
      }),
      env
    );
    expect(res.status).toBe(200);

    const notif = await env.DB.prepare(
      "SELECT title FROM notifications WHERE business_id = ? AND type = 'hot_lead' ORDER BY created_at DESC LIMIT 1"
    ).bind(bizId).first<any>();

    expect(notif).toBeDefined();
    expect(notif.title).toBe('Hot Lead Alert');
    expect(notif.title.startsWith(' ')).toBe(false);
  });

  // 4. Knowledge setStatus and chunk deletes isolate by business_id
  it('4. Knowledge setStatus and chunk deletion are strictly isolated by business_id', async () => {
    const bizA = 'biz_k_a';
    const bizB = 'biz_k_b';
    const srcId = 'src_cross_biz_1';

    await env.DB.prepare("INSERT INTO businesses (id, name, category) VALUES (?, 'Biz A', 'education')").bind(bizA).run();
    await env.DB.prepare("INSERT INTO businesses (id, name, category) VALUES (?, 'Biz B', 'education')").bind(bizB).run();

    // Insert source for Biz B
    await env.DB.prepare(
      "INSERT INTO knowledge_sources (id, business_id, type, title, status) VALUES (?, ?, 'faq', 'Biz B FAQ', 'uploading')"
    ).bind(srcId, bizB).run();

    // Biz A attempts to ingest with the same source ID
    await ingestKnowledge(env, bizA, {
      id: srcId,
      type: 'faq',
      content: 'Biz A secret content that should not overwrite Biz B',
    });

    // Biz B's row must still have status 'uploading' because Biz A cannot update it
    const rowB = await env.DB.prepare('SELECT status FROM knowledge_sources WHERE id = ? AND business_id = ?').bind(srcId, bizB).first<any>();
    expect(rowB.status).toBe('uploading');
  });
});
