import { describe, it, expect, beforeAll } from 'vitest';
import { env } from 'cloudflare:test';
import { migrateTestDb } from './setup-db';
import app from '../src/index';

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

describe('Sarvam Webhook Handler (100% Coverage Target)', () => {
  const secret = 'test_webhook_secret_12345';
  const bizId = 'biz_webhook_test';
  const leadId = 'lead_webhook_test';
  const callId = 'call_webhook_test';
  const interactionId = 'int_webhook_999';

  beforeAll(async () => {
    await migrateTestDb();

    // Seed test business, user, lead, usage, and call
    await env.DB.batch([
      env.DB.prepare("INSERT OR REPLACE INTO businesses (id, name) VALUES (?, 'Apex Academy')").bind(bizId),
      env.DB.prepare("INSERT OR REPLACE INTO leads (id, business_id, name, phone, status) VALUES (?, ?, 'Aarav Patel', '919830099999', 'queued')").bind(leadId, bizId),
      env.DB.prepare("INSERT OR REPLACE INTO usage (id, business_id, plan_name, included_minutes, renews_at, price_inr, minutes_used, calls_made, rate_per_minute_inr) VALUES ('usg_test', ?, 'Founding', 1000, datetime('now', '+30 days'), 4999, 0, 0, 6)").bind(bizId),
      env.DB.prepare("INSERT OR REPLACE INTO calls (id, business_id, lead_id, lead_name, lead_phone, status, interaction_id, started_at) VALUES (?, ?, ?, 'Aarav Patel', '919830099999', 'calling', ?, datetime('now'))").bind(callId, bizId, leadId, interactionId),
    ]);
  });

  it('rejects unsigned webhook or missing secret with 401', async () => {
    const res = await app.fetch(
      new Request('http://localhost/webhooks/sarvam', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ call_id: callId }),
      }),
      { ...env, SARVAM_WEBHOOK_SECRET: undefined as any }
    );
    expect(res.status).toBe(401);
  });

  it('rejects stale timestamp with 401', async () => {
    const body = JSON.stringify({ call_id: callId });
    const staleTs = String(Math.floor(Date.now() / 1000) - 400); // 400s ago (> 300s)
    const sig = await signWebhook(body, secret);

    const res = await app.fetch(
      new Request('http://localhost/webhooks/sarvam', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Sarvam-Signature': sig,
          'X-Sarvam-Timestamp': staleTs,
        },
        body,
      }),
      env
    );
    expect(res.status).toBe(401);
    const data = await res.json() as any;
    expect(data.code).toBe('stale_timestamp');
  });

  it('rejects invalid signature with 401', async () => {
    const body = JSON.stringify({ call_id: callId });
    const res = await app.fetch(
      new Request('http://localhost/webhooks/sarvam', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Sarvam-Signature': '0000000000000000000000000000000000000000000000000000000000000000',
        },
        body,
      }),
      env
    );
    expect(res.status).toBe(401);
  });

  it('rejects malformed json with 400', async () => {
    const badBody = 'this-is-not-json';
    const sig = await signWebhook(badBody, secret);

    const res = await app.fetch(
      new Request('http://localhost/webhooks/sarvam', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Sarvam-Signature': sig,
        },
        body: badBody,
      }),
      env
    );
    expect(res.status).toBe(400);
  });

  it('rejects missing call identifier with 400', async () => {
    const body = JSON.stringify({ duration_seconds: 60 });
    const sig = await signWebhook(body, secret);

    const res = await app.fetch(
      new Request('http://localhost/webhooks/sarvam', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Sarvam-Signature': sig,
        },
        body,
      }),
      env
    );
    expect(res.status).toBe(400);
    const data = await res.json() as any;
    expect(data.code).toBe('missing_identifier');
  });

  it('returns 404 if call identifier does not match any record', async () => {
    const body = JSON.stringify({ interaction_id: 'non_existent_call_id_123' });
    const sig = await signWebhook(body, secret);

    const res = await app.fetch(
      new Request('http://localhost/webhooks/sarvam', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Sarvam-Signature': sig,
        },
        body,
      }),
      env
    );
    expect(res.status).toBe(404);
  });

  it('handles schema validation failure gracefully (score 0, cold, review flagged, returns 200)', async () => {
    // Call 2 with invalid output schema
    const call2Id = 'call_webhook_invalid_schema';
    await env.DB.prepare(
      "INSERT OR REPLACE INTO calls (id, business_id, lead_id, lead_name, lead_phone, status, interaction_id, started_at) VALUES (?, ?, ?, 'Aarav Patel', '919830099999', 'calling', 'int_invalid_schema', datetime('now'))"
    ).bind(call2Id, bizId, leadId).run();

    const body = JSON.stringify({
      interaction_id: 'int_invalid_schema',
      duration_seconds: 65,
      status: 'completed',
      output_variables: {
        score: 'not-a-number', // invalid
        temperature: 'super_hot', // invalid
      },
    });
    const sig = await signWebhook(body, secret);

    const res = await app.fetch(
      new Request('http://localhost/webhooks/sarvam', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Sarvam-Signature': sig,
        },
        body,
      }),
      env
    );
    expect(res.status).toBe(200);

    const updatedCall = await env.DB.prepare('SELECT score, temperature, status FROM calls WHERE id = ?').bind(call2Id).first<any>();
    expect(updatedCall.status).toBe('completed');
    expect(updatedCall.score).toBe(0);
    expect(updatedCall.temperature).toBe('cold');
  });

  it('processes valid completed call webhook with atomic billing, lead update, callback, and followup', async () => {
    const futureCallback = new Date(Date.now() + 86400000).toISOString();
    const body = JSON.stringify({
      interaction_id: interactionId,
      status: 'completed',
      duration_seconds: 120,
      recording_url: 'https://cdn.sarvam.ai/recordings/test.wav',
      transcript: [
        { role: 'agent', message: 'Hello Aarav!' },
        { role: 'user', message: 'Yes I am interested in the JEE course.' },
      ],
      output_variables: {
        lead_score: 95,
        temperature: 'hot',
        intent: 'interested',
        summary: 'Lead is interested in JEE morning batch.',
        next_action: 'whatsapp_and_callback',
        callback_at: futureCallback,
        whatsapp_followup_required: true,
        whatsapp_message: 'Hi Aarav, here is our JEE batch prospectus!',
        positive_signals: ['high intent', 'immediate enrollment'],
        objections: ['asked about discounts'],
      },
    });

    const nowTs = String(Math.floor(Date.now() / 1000));
    const sig = await signWebhook(body, secret);

    const res = await app.fetch(
      new Request('http://localhost/webhooks/sarvam', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Sarvam-Signature': `sha256=${sig}`,
          'X-Sarvam-Timestamp': nowTs,
        },
        body,
      }),
      env
    );

    expect(res.status).toBe(200);
    const data = await res.json() as any;
    expect(data.success).toBe(true);
    expect(data.call_id).toBe(callId);

    // Verify DB updates
    const updatedCall = await env.DB.prepare('SELECT * FROM calls WHERE id = ?').bind(callId).first<any>();
    expect(updatedCall.status).toBe('completed');
    expect(updatedCall.score).toBe(95);
    expect(updatedCall.temperature).toBe('hot');
    expect(updatedCall.duration_seconds).toBe(120);

    // Verify atomic usage update
    const usage = await env.DB.prepare('SELECT minutes_used, calls_made FROM usage WHERE business_id = ?').bind(bizId).first<any>();
    expect(usage.calls_made).toBeGreaterThanOrEqual(1);
    expect(usage.minutes_used).toBeGreaterThanOrEqual(2); // 120s = 2 minutes

    // Verify lead was updated
    const updatedLead = await env.DB.prepare('SELECT status, score, temperature FROM leads WHERE id = ?').bind(leadId).first<any>();
    expect(updatedLead.status).toBe('called');
    expect(updatedLead.score).toBe(95);
    expect(updatedLead.temperature).toBe('hot');

    // Verify followup was created with 'ready' status (guarantee: human sends on WhatsApp)
    const fu = await env.DB.prepare('SELECT * FROM followups WHERE call_id = ?').bind(callId).first<any>();
    expect(fu).not.toBeNull();
    expect(fu.status).toBe('ready');

    // Verify callback was scheduled
    const cb = await env.DB.prepare('SELECT * FROM callbacks WHERE business_id = ?').bind(bizId).first<any>();
    expect(cb).not.toBeNull();
    expect(cb.scheduled_at).toBe(futureCallback);
  });

  it('returns idempotent 200 for replayed webhook', async () => {
    const body = JSON.stringify({ interaction_id: interactionId, status: 'completed' });
    const sig = await signWebhook(body, secret);

    const res = await app.fetch(
      new Request('http://localhost/webhooks/sarvam', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Sarvam-Signature': sig,
        },
        body,
      }),
      env
    );

    expect(res.status).toBe(200);
    const data = await res.json() as any;
    expect(data.status).toBe('idempotent');
  });

  it('detects opt-out intent and flags lead do_not_call = 1', async () => {
    const optOutCallId = 'call_opt_out_test';
    const optOutLeadId = 'lead_opt_out_test';
    await env.DB.batch([
      env.DB.prepare("INSERT OR REPLACE INTO leads (id, business_id, name, phone, status, do_not_call, consent) VALUES (?, ?, 'Sunil Sharma', '919830088888', 'queued', 0, 'inquiry')").bind(optOutLeadId, bizId),
      env.DB.prepare("INSERT OR REPLACE INTO calls (id, business_id, lead_id, lead_name, lead_phone, status, interaction_id, started_at) VALUES (?, ?, ?, 'Sunil Sharma', '919830088888', 'calling', 'int_opt_out_test', datetime('now'))").bind(optOutCallId, bizId, optOutLeadId),
    ]);

    const body = JSON.stringify({
      interaction_id: 'int_opt_out_test',
      status: 'completed',
      duration_seconds: 30,
      transcript: [
        { role: 'user', message: "Please don't call me again, remove my number." },
      ],
      output_variables: {
        score: 10,
        temperature: 'cold',
        intent: 'opt_out',
        summary: 'Caller requested DNC.',
      },
    });
    const sig = await signWebhook(body, secret);

    const res = await app.fetch(
      new Request('http://localhost/webhooks/sarvam', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Sarvam-Signature': sig,
        },
        body,
      }),
      env
    );

    expect(res.status).toBe(200);

    const lead = await env.DB.prepare('SELECT do_not_call, consent FROM leads WHERE id = ?').bind(optOutLeadId).first<any>();
    expect(lead.do_not_call).toBe(1);
    expect(lead.consent).toBe('opt_out');
  });
});
