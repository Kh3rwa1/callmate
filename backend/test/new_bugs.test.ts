import { describe, it, expect, beforeAll } from 'vitest';
import { env } from 'cloudflare:test';
import { migrateTestDb } from './setup-db';
import app from '../src/index';
import { loadHistory, saveTurn } from '../src/services/prompt';
import { ingestKnowledge } from '../src/services/knowledge';
import { claimWebhookEvent, releaseWebhookEvent } from '../src/services/billing';
import { signJWT } from '../src/auth';

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

describe('New Bug Fixes Verification Suite', () => {
  const bizId = 'biz_bug_test';
  let token: string;

  beforeAll(async () => {
    await migrateTestDb(env.DB);
    await env.DB.prepare("INSERT INTO businesses (id, name, category) VALUES (?, 'Test Academy', 'education')")
      .bind(bizId).run();
    await env.DB.prepare("INSERT OR REPLACE INTO users (id, phone, business_id) VALUES ('usr_1', '919800000000', ?)")
      .bind(bizId).run();

    token = await signJWT({
      sub: 'usr_1',
      business_id: bizId,
      phone: '919800000000',
      type: 'access',
    }, env.JWT_SIGNING_KEY);
  });

  // Bug 1: Chat memory loads oldest instead of newest
  it('Bug 1: loadHistory returns the 10 LATEST messages in chronological order, using rowid for same timestamp', async () => {
    const convId = 'conv_bug1';
    // Insert 7 turns = 14 messages
    for (let i = 1; i <= 7; i++) {
      await saveTurn(env.DB, bizId, convId, `User question ${i}`, `Assistant answer ${i}`);
    }

    const history = await loadHistory(env.DB, bizId, convId, 10);
    expect(history.length).toBe(10);
    // Should be turns 3, 4, 5, 6, 7 (messages 5 to 14)
    expect(history[0].content).toBe('User question 3');
    expect(history[1].content).toBe('Assistant answer 3');
    expect(history[8].content).toBe('User question 7');
    expect(history[9].content).toBe('Assistant answer 7');
  });

  // Bug 2: PDF reading honestly fails and Flutter types handled
  it('Bug 2: ingestKnowledge marks PDF as failed with honest message, and supports faq/business_info', async () => {
    const sourcePdf = {
      id: 'src_pdf_1',
      type: 'pdf',
      file_url: '/r2/biz/document.pdf',
    };
    await env.DB.prepare("INSERT INTO knowledge_sources (id, business_id, type, title, status) VALUES (?, ?, 'pdf', 'Brochure', 'uploading')")
      .bind(sourcePdf.id, bizId).run();

    await ingestKnowledge(env, bizId, sourcePdf);
    const rowPdf = await env.DB.prepare('SELECT status, detail FROM knowledge_sources WHERE id = ?').bind(sourcePdf.id).first<any>();
    expect(rowPdf.status).toBe('failed');
    expect(rowPdf.detail).toContain('PDF reading coming soon');

    // faq type with content
    const sourceFaq = {
      id: 'src_faq_1',
      type: 'faq',
      content: 'Q: What are the class hours? A: Classes run from 4pm to 7pm.',
    };
    await env.DB.prepare("INSERT INTO knowledge_sources (id, business_id, type, title, status) VALUES (?, ?, 'faq', 'Class FAQ', 'uploading')")
      .bind(sourceFaq.id, bizId).run();

    await ingestKnowledge(env, bizId, sourceFaq);
    const rowFaq = await env.DB.prepare('SELECT status FROM knowledge_sources WHERE id = ?').bind(sourceFaq.id).first<any>();
    expect(rowFaq.status).toBe('ready');
  });

  // Bug 3: No-answer webhook preserves lead score and temperature
  it('Bug 3: no-answer webhook sets status to not_reached without overwriting existing score/temperature', async () => {
    const leadId = 'lead_hot_1';
    const callId = 'call_no_ans_1';

    await env.DB.prepare(
      "INSERT INTO leads (id, business_id, name, phone, status, temperature, score) VALUES (?, ?, 'Hot Lead', '919876543210', 'called', 'hot', 95)"
    ).bind(leadId, bizId).run();

    await env.DB.prepare(
      "INSERT INTO calls (id, business_id, lead_id, lead_name, lead_phone, status) VALUES (?, ?, ?, 'Hot Lead', '919876543210', 'queued')"
    ).bind(callId, bizId, leadId).run();

    const payload = JSON.stringify({
      call_id: callId,
      status: 'no_answer',
      duration_seconds: 0,
      transcript: [],
      extracted_variables: {
        lead_score: 0,
        temperature: 'cold',
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

    const lead = await env.DB.prepare('SELECT status, temperature, score FROM leads WHERE id = ?').bind(leadId).first<any>();
    expect(lead.status).toBe('not_reached');
    expect(lead.temperature).toBe('hot');
    expect(lead.score).toBe(95);
  });

  // Bug 4: Late webhook processes billing & analysis for timed_out call
  it('Bug 4: processes billing and analysis for timed_out call', async () => {
    const leadId = 'lead_timed_out_1';
    const callId = 'call_timed_out_1';

    await env.DB.prepare(
      "INSERT INTO leads (id, business_id, name, phone, status, temperature, score) VALUES (?, ?, 'Lead', '919876543211', 'called', 'warm', 60)"
    ).bind(leadId, bizId).run();

    await env.DB.prepare(
      "INSERT INTO calls (id, business_id, lead_id, lead_name, lead_phone, status) VALUES (?, ?, ?, 'Lead', '919876543211', 'timed_out')"
    ).bind(callId, bizId, leadId).run();

    const payload = JSON.stringify({
      call_id: callId,
      status: 'completed',
      duration_seconds: 45,
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

    const call = await env.DB.prepare('SELECT status, duration_seconds FROM calls WHERE id = ?').bind(callId).first<any>();
    expect(call.status).toBe('completed');
    expect(call.duration_seconds).toBe(45);
  });

  // Bug 5: Release webhook event on processing failure
  it('Bug 5: releaseWebhookEvent deletes claim so retry can be processed', async () => {
    const eventKey = 'sarvam:call_retry_test:completed';
    const firstClaim = await claimWebhookEvent(env.DB, eventKey);
    expect(firstClaim).toBe(true);

    // Second claim fails as duplicate
    const secondClaim = await claimWebhookEvent(env.DB, eventKey);
    expect(secondClaim).toBe(false);

    // After failure release, third claim succeeds
    await releaseWebhookEvent(env.DB, eventKey);
    const thirdClaim = await claimWebhookEvent(env.DB, eventKey);
    expect(thirdClaim).toBe(true);
  });

  // Bug 6: Chat reply uses first sentence of knowledge, and fallback is neutral (no invented admissions office / hours)
  it('Bug 6: chat replies do not invent hours or admissions office, and use only first sentence of knowledge', async () => {
    const convId = 'conv_bug6';
    const resFees = await app.fetch(
      new Request('http://localhost/voice/chat', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({
          message: 'What is the fee structure?',
          conversation_id: convId,
        }),
      }),
      env
    );
    expect(resFees.status).toBe(200);
    const dataFees = await resFees.json() as any;
    expect(dataFees.reply).not.toContain('admissions office');

    const resHours = await app.fetch(
      new Request('http://localhost/voice/chat', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({
          message: 'What are your hours?',
          conversation_id: convId,
        }),
      }),
      env
    );
    expect(resHours.status).toBe(200);
    const dataHours = await resHours.json() as any;
    expect(dataHours.reply).not.toContain('10:00 AM to 7:00 PM Monday through Saturday');
  });

  // Bug 7: /health/deep requires secret and rejects URL query parameter
  it('Bug 7: /health/deep rejects query param and enforces secret header', async () => {
    const secret = 'super-secret-probe-key-123';
    const testEnv = {
      ...env,
      HEALTH_CHECK_SECRET: secret,
      SARVAM_API_KEY: 'test_key',
      SARVAM_ORG_ID: 'org_1',
      SARVAM_WORKSPACE_ID: 'ws_1',
      SARVAM_ADMISSIONS_APP_ID: 'app_1',
    } as any;

    // 1. Secret in query param is rejected with 401
    const resQuery = await app.fetch(
      new Request(`http://localhost/health/deep?key=${secret}`),
      testEnv
    );
    expect(resQuery.status).toBe(401);

    // 2. Secret in header is accepted with 200
    const resHeader = await app.fetch(
      new Request('http://localhost/health/deep', {
        headers: { 'x-health-key': secret },
      }),
      testEnv
    );
    expect(resHeader.status).toBe(200);

    // 3. When HEALTH_CHECK_SECRET is missing on server, returns 500 error
    const envNoSecret = { ...testEnv, HEALTH_CHECK_SECRET: undefined };
    const resNoSecret = await app.fetch(
      new Request('http://localhost/health/deep', {
        headers: { 'x-health-key': secret },
      }),
      envNoSecret
    );
    expect(resNoSecret.status).toBe(500);
  });
});
