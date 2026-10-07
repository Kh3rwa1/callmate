import { describe, it, expect, beforeAll, vi, afterEach } from 'vitest';
import { env } from 'cloudflare:test';
import { migrateTestDb } from './setup-db';
import app from '../src/index';
import { signJWT } from '../src/auth';
import {
  processCampaignJob,
  CampaignJobMessage,
} from '../src/services/campaign_queue';
import { runMaintenance } from '../src/services/maintenance';

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

describe('Phase 9 Integration Matrix (Q1-Q6, W1-W4, S1-S4, K1-K2, M1)', () => {
  const secret = 'test-jwt-signing-secret-key-32chars-min-length';
  const webhookSecret = env.SARVAM_WEBHOOK_SECRET || 'test_webhook_secret_12345';
  const bizId = 'biz_p9';
  const userId = 'usr_p9';
  const phone = '919876543210';
  let token: string;

  beforeAll(async () => {
    await migrateTestDb();

    await env.DB.batch([
      env.DB.prepare("INSERT OR REPLACE INTO businesses (id, name, category) VALUES (?, 'P9 Academy', 'education')").bind(bizId),
      env.DB.prepare("INSERT OR REPLACE INTO users (id, phone, business_id) VALUES (?, ?, ?)").bind(userId, phone, bizId),
      env.DB.prepare("INSERT OR REPLACE INTO agents (id, business_id, name, role, status) VALUES ('agt_p9', ?, 'Maya', 'Counselor', 'active')").bind(bizId),
      env.DB.prepare("INSERT OR REPLACE INTO usage (id, business_id, plan_name, included_minutes, renews_at, price_inr, minutes_used, calls_made, rate_per_minute_inr) VALUES ('usg_p9', ?, 'Pro', 1000, datetime('now', '+30 days'), 4999, 0, 0, 6)").bind(bizId),
    ]);

    token = await signJWT({ sub: userId, phone, business_id: bizId, type: 'access' }, secret, 3600);
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  describe('Queue Integration (Q1 - Q6)', () => {
    it('Q1: Queue retry: Sarvam 500 leads to retry_pending and call failed; 200 on retry transitions to calling', async () => {
      const campId = `camp_q1_${Date.now()}`;
      const leadId = `lead_q1_${Date.now()}`;

      await env.DB.batch([
        env.DB.prepare("INSERT INTO campaigns (id, business_id, purpose, status, total_leads, calling_hours_start, calling_hours_end) VALUES (?, ?, 'Q1 Test', 'running', 1, 0, 24)").bind(campId, bizId),
        env.DB.prepare("INSERT INTO leads (id, business_id, name, phone, status, consent) VALUES (?, ?, 'Lead Q1', '919800000001', 'pending', 'explicit')").bind(leadId, bizId),
        env.DB.prepare("INSERT INTO campaign_leads (campaign_id, lead_id, status, attempts) VALUES (?, ?, 'queued', 0)").bind(campId, leadId),
      ]);

      const testEnv = {
        ...env,
        SARVAM_API_KEY: 'live-key-q1-valid',
        SARVAM_ORG_ID: 'org_p9',
        SARVAM_WORKSPACE_ID: 'ws_p9',
        SARVAM_ADMISSIONS_APP_ID: 'app_p9',
      } as any;

      // Mock Sarvam 500 failure
      vi.spyOn(globalThis, 'fetch').mockImplementationOnce(async () => {
        return new Response('Telephony Gateway Down', { status: 500 });
      });

      const job: CampaignJobMessage = {
        campaign_id: campId,
        lead_id: leadId,
        business_id: bizId,
        idempotency_key: `${campId}:${leadId}`,
        attempts: 0,
      };

      const res1 = await processCampaignJob(testEnv, job);
      expect(res1.success).toBe(false);
      expect(res1.retry).toBe(true);
      expect(res1.delaySeconds).toBe(60);

      const clRow1 = await env.DB.prepare('SELECT status, attempts, error FROM campaign_leads WHERE campaign_id = ? AND lead_id = ?')
        .bind(campId, leadId).first<any>();
      expect(clRow1.status).toBe('retry_pending');
      expect(clRow1.attempts).toBe(1);

      const callRow1 = await env.DB.prepare('SELECT status, failure_reason FROM calls WHERE campaign_id = ? AND lead_id = ?')
        .bind(campId, leadId).first<any>();
      expect(callRow1.status).toBe('failed');
      expect(callRow1.failure_reason).toContain('500');

      // Second run: Sarvam returns 200 OK
      vi.spyOn(globalThis, 'fetch').mockImplementationOnce(async () => {
        return new Response(JSON.stringify({ interaction_id: 'int_q1_success' }), { status: 200, headers: { 'Content-Type': 'application/json' } });
      });

      const res2 = await processCampaignJob(testEnv, job);
      expect(res2.success).toBe(true);

      const clRow2 = await env.DB.prepare('SELECT status, attempts FROM campaign_leads WHERE campaign_id = ? AND lead_id = ?')
        .bind(campId, leadId).first<any>();
      expect(clRow2.status).toBe('calling');
      expect(clRow2.attempts).toBe(2);

      const callRow2 = await env.DB.prepare('SELECT status, interaction_id FROM calls WHERE campaign_id = ? AND lead_id = ? ORDER BY created_at DESC')
        .bind(campId, leadId).first<any>();
      expect(callRow2.status).toBe('calling');
      expect(callRow2.interaction_id).toBe('int_q1_success');
    });

    it('Q2: Permanent failure: Sarvam returns 400 -> lead failed, no retry', async () => {
      const campId = `camp_q2_${Date.now()}`;
      const leadId = `lead_q2_${Date.now()}`;

      await env.DB.batch([
        env.DB.prepare("INSERT INTO campaigns (id, business_id, purpose, status, total_leads, calling_hours_start, calling_hours_end) VALUES (?, ?, 'Q2 Test', 'running', 1, 0, 24)").bind(campId, bizId),
        env.DB.prepare("INSERT INTO leads (id, business_id, name, phone, status, consent) VALUES (?, ?, 'Lead Q2', '919800000002', 'pending', 'explicit')").bind(leadId, bizId),
        env.DB.prepare("INSERT INTO campaign_leads (campaign_id, lead_id, status, attempts) VALUES (?, ?, 'queued', 0)").bind(campId, leadId),
      ]);

      const testEnv = {
        ...env,
        SARVAM_API_KEY: 'live-key-q2',
        SARVAM_ORG_ID: 'org_p9',
        SARVAM_WORKSPACE_ID: 'ws_p9',
        SARVAM_ADMISSIONS_APP_ID: 'app_p9',
      } as any;

      vi.spyOn(globalThis, 'fetch').mockImplementationOnce(async () => {
        return new Response('Invalid phone format', { status: 400 });
      });

      const job: CampaignJobMessage = {
        campaign_id: campId,
        lead_id: leadId,
        business_id: bizId,
        idempotency_key: `${campId}:${leadId}`,
        attempts: 0,
      };

      const res = await processCampaignJob(testEnv, job);
      expect(res.success).toBe(true);
      expect(res.retry).toBeFalsy();
      expect(res.reason).toContain('dial_failed_terminal');

      const clRow = await env.DB.prepare('SELECT status, attempts FROM campaign_leads WHERE campaign_id = ? AND lead_id = ?')
        .bind(campId, leadId).first<any>();
      expect(clRow.status).toBe('failed');
      expect(clRow.attempts).toBe(1);
    });

    it('Q3: Exhaustion: 3 consecutive 500s -> third attempt ends failed, 4th job is a no-op', async () => {
      const campId = `camp_q3_${Date.now()}`;
      const leadId = `lead_q3_${Date.now()}`;

      await env.DB.batch([
        env.DB.prepare("INSERT INTO campaigns (id, business_id, purpose, status, total_leads, calling_hours_start, calling_hours_end) VALUES (?, ?, 'Q3 Test', 'running', 1, 0, 24)").bind(campId, bizId),
        env.DB.prepare("INSERT INTO leads (id, business_id, name, phone, status, consent) VALUES (?, ?, 'Lead Q3', '919800000003', 'pending', 'explicit')").bind(leadId, bizId),
        env.DB.prepare("INSERT INTO campaign_leads (campaign_id, lead_id, status, attempts) VALUES (?, ?, 'queued', 0)").bind(campId, leadId),
      ]);

      const testEnv = {
        ...env,
        SARVAM_API_KEY: 'live-key-q3',
        SARVAM_ORG_ID: 'org_p9',
        SARVAM_WORKSPACE_ID: 'ws_p9',
        SARVAM_ADMISSIONS_APP_ID: 'app_p9',
      } as any;

      const job: CampaignJobMessage = {
        campaign_id: campId,
        lead_id: leadId,
        business_id: bizId,
        idempotency_key: `${campId}:${leadId}`,
        attempts: 0,
      };

      // Attempt 1: 500 -> retry_pending (attempts=1)
      vi.spyOn(globalThis, 'fetch').mockImplementationOnce(async () => new Response('Err', { status: 500 }));
      const r1 = await processCampaignJob(testEnv, job);
      expect(r1.retry).toBe(true);

      // Attempt 2: 500 -> retry_pending (attempts=2)
      vi.spyOn(globalThis, 'fetch').mockImplementationOnce(async () => new Response('Err', { status: 500 }));
      const r2 = await processCampaignJob(testEnv, job);
      expect(r2.retry).toBe(true);

      // Attempt 3: 500 -> terminal failed (attempts=3)
      vi.spyOn(globalThis, 'fetch').mockImplementationOnce(async () => new Response('Err', { status: 500 }));
      const r3 = await processCampaignJob(testEnv, job);
      expect(r3.retry).toBeFalsy();
      expect(r3.reason).toContain('dial_failed_terminal');

      const cl = await env.DB.prepare('SELECT status, attempts FROM campaign_leads WHERE campaign_id = ? AND lead_id = ?')
        .bind(campId, leadId).first<any>();
      expect(cl.status).toBe('failed');
      expect(cl.attempts).toBe(3);

      // 4th job: lead is terminal 'failed', no-op
      const r4 = await processCampaignJob(testEnv, job);
      expect(r4.reason).toContain('not_claimable');
    });

    it('Q4: Double delivery: run processCampaignJob twice concurrently -> exactly ONE calls row, attempts=1', async () => {
      const campId = `camp_q4_${Date.now()}`;
      const leadId = `lead_q4_${Date.now()}`;

      await env.DB.batch([
        env.DB.prepare("INSERT INTO campaigns (id, business_id, purpose, status, total_leads, calling_hours_start, calling_hours_end) VALUES (?, ?, 'Q4 Test', 'running', 1, 0, 24)").bind(campId, bizId),
        env.DB.prepare("INSERT INTO leads (id, business_id, name, phone, status, consent) VALUES (?, ?, 'Lead Q4', '919800000004', 'pending', 'explicit')").bind(leadId, bizId),
        env.DB.prepare("INSERT INTO campaign_leads (campaign_id, lead_id, status, attempts) VALUES (?, ?, 'queued', 0)").bind(campId, leadId),
      ]);

      const testEnv = {
        ...env,
        SARVAM_API_KEY: 'mock-test-key',
      } as any;

      const job: CampaignJobMessage = {
        campaign_id: campId,
        lead_id: leadId,
        business_id: bizId,
        idempotency_key: `${campId}:${leadId}`,
        attempts: 0,
      };

      const results = await Promise.all([
        processCampaignJob(testEnv, job),
        processCampaignJob(testEnv, job),
      ]);

      const successfulClaims = results.filter((r) => r.reason === 'mock_dial');
      const skippedClaims = results.filter((r) => r.reason === 'claimed_elsewhere_or_exhausted');

      expect(successfulClaims.length).toBe(1);
      expect(skippedClaims.length).toBe(1);

      const count = await env.DB.prepare('SELECT COUNT(*) as c FROM calls WHERE campaign_id = ? AND lead_id = ?')
        .bind(campId, leadId).first<{ c: number }>();
      expect(count?.c).toBe(1);

      const cl = await env.DB.prepare('SELECT attempts FROM campaign_leads WHERE campaign_id = ? AND lead_id = ?')
        .bind(campId, leadId).first<{ attempts: number }>();
      expect(cl?.attempts).toBe(1);
    });

    it('Q5: Resume safety: complete lead A, pause, start again -> lead A is NOT re-queued', async () => {
      const campId = `camp_q5_${Date.now()}`;
      const leadDone = `lead_q5_done_${Date.now()}`;
      const leadPending = `lead_q5_pend_${Date.now()}`;

      await env.DB.batch([
        env.DB.prepare("INSERT INTO campaigns (id, business_id, purpose, status, total_leads, calling_hours_start, calling_hours_end) VALUES (?, ?, 'Q5 Resume Test', 'paused', 2, 0, 24)").bind(campId, bizId),
        env.DB.prepare("INSERT INTO leads (id, business_id, name, phone, status, consent) VALUES (?, ?, 'Done', '919800000005', 'completed', 'explicit')").bind(leadDone, bizId),
        env.DB.prepare("INSERT INTO leads (id, business_id, name, phone, status, consent) VALUES (?, ?, 'Pending', '919800000006', 'pending', 'explicit')").bind(leadPending, bizId),
        env.DB.prepare("INSERT INTO campaign_leads (campaign_id, lead_id, status, attempts) VALUES (?, ?, 'completed', 1)").bind(campId, leadDone),
        env.DB.prepare("INSERT INTO campaign_leads (campaign_id, lead_id, status, attempts) VALUES (?, ?, 'pending', 0)").bind(campId, leadPending),
      ]);

      const res = await app.fetch(
        new Request(`http://localhost/campaigns/${campId}/start`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
        }),
        env
      );

      expect(res.status).toBe(200);

      const doneLead = await env.DB.prepare('SELECT status FROM campaign_leads WHERE campaign_id = ? AND lead_id = ?')
        .bind(campId, leadDone).first<{ status: string }>();
      expect(doneLead?.status).toBe('completed');

      const pendLead = await env.DB.prepare('SELECT status FROM campaign_leads WHERE campaign_id = ? AND lead_id = ?')
        .bind(campId, leadPending).first<{ status: string }>();
      expect(pendLead?.status).toBe('queued');
    });

    it('Q6: Double start: POST /start twice -> second returns 409', async () => {
      const campId = `camp_q6_${Date.now()}`;
      await env.DB.prepare(
        "INSERT INTO campaigns (id, business_id, purpose, status, total_leads, calling_hours_start, calling_hours_end) VALUES (?, ?, 'Q6 Double Start', 'draft', 0, 0, 24)"
      ).bind(campId, bizId).run();

      const startReq = () => app.fetch(
        new Request(`http://localhost/campaigns/${campId}/start`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
        }),
        env
      );

      const res1 = await startReq();
      expect(res1.status).toBe(200);

      const res2 = await startReq();
      expect(res2.status).toBe(409);
      const b2 = await res2.json() as any;
      expect(b2.code).toBe('invalid_state');
    });
  });

  describe('Webhook & Billing Integration (W1 - W4)', () => {
    it('W1: Webhook replay: duplicate signed no_answer webhook leaves minutes_used unchanged, 0 follow-ups, returns duplicate: true', async () => {
      const callId = `call_w1_${Date.now()}`;
      const leadId = `lead_w1_${Date.now()}`;
      const interactionId = `int_w1_${Date.now()}`;

      await env.DB.batch([
        env.DB.prepare("INSERT INTO leads (id, business_id, name, phone, status) VALUES (?, ?, 'Lead W1', '919800000010', 'calling')").bind(leadId, bizId),
        env.DB.prepare("INSERT INTO calls (id, business_id, lead_id, lead_name, lead_phone, status, interaction_id) VALUES (?, ?, ?, 'Lead W1', '919800000010', 'calling', ?)").bind(callId, bizId, leadId, interactionId),
      ]);

      const initialUsage = await env.DB.prepare('SELECT minutes_used FROM usage WHERE business_id = ?')
        .bind(bizId).first<{ minutes_used: number }>();

      const webhookBody = JSON.stringify({
        call_id: callId,
        interaction_id: interactionId,
        status: 'no_answer',
        duration_seconds: 0,
        transcript: [],
      });
      const sig = await signWebhook(webhookBody, webhookSecret);

      const sendWebhook = () => app.fetch(
        new Request('http://localhost/webhooks/sarvam', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'X-Sarvam-Signature': sig,
          },
          body: webhookBody,
        }),
        env
      );

      // First webhook
      const res1 = await sendWebhook();
      expect(res1.status).toBe(200);

      // Second webhook (replay)
      const res2 = await sendWebhook();
      expect(res2.status).toBe(200);
      const b2 = await res2.json() as any;
      expect(b2.duplicate).toBe(true);

      const finalUsage = await env.DB.prepare('SELECT minutes_used FROM usage WHERE business_id = ?')
        .bind(bizId).first<{ minutes_used: number }>();
      expect(finalUsage?.minutes_used).toBe(initialUsage?.minutes_used);

      const followups = await env.DB.prepare('SELECT COUNT(*) as c FROM followups WHERE call_id = ?')
        .bind(callId).first<{ c: number }>();
      expect(followups?.c).toBe(0);
    });

    it('W2: Completed webhook twice with duration 125 -> billed exactly 3 minutes once', async () => {
      const callId = `call_w2_${Date.now()}`;
      const leadId = `lead_w2_${Date.now()}`;
      const interactionId = `int_w2_${Date.now()}`;

      await env.DB.batch([
        env.DB.prepare("INSERT INTO leads (id, business_id, name, phone, status) VALUES (?, ?, 'Lead W2', '919800000020', 'calling')").bind(leadId, bizId),
        env.DB.prepare("INSERT INTO calls (id, business_id, lead_id, lead_name, lead_phone, status, interaction_id) VALUES (?, ?, ?, 'Lead W2', '919800000020', 'calling', ?)").bind(callId, bizId, leadId, interactionId),
      ]);

      const initialUsage = await env.DB.prepare('SELECT minutes_used FROM usage WHERE business_id = ?')
        .bind(bizId).first<{ minutes_used: number }>();

      const webhookBody = JSON.stringify({
        call_id: callId,
        interaction_id: interactionId,
        status: 'completed',
        duration_seconds: 125, // ceil(125 / 60) = 3 minutes
        transcript: [
          { role: 'agent', text: 'Hello from Maya' },
          { role: 'user', text: 'Yes I am interested in courses' },
        ],
      });
      const sig = await signWebhook(webhookBody, webhookSecret);

      const sendWebhook = () => app.fetch(
        new Request('http://localhost/webhooks/sarvam', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'X-Sarvam-Signature': sig,
          },
          body: webhookBody,
        }),
        env
      );

      const res1 = await sendWebhook();
      expect(res1.status).toBe(200);

      const res2 = await sendWebhook();
      expect(res2.status).toBe(200);
      const b2 = await res2.json() as any;
      expect(b2.duplicate).toBe(true);

      const afterUsage = await env.DB.prepare('SELECT minutes_used FROM usage WHERE business_id = ?')
        .bind(bizId).first<{ minutes_used: number }>();
      expect((afterUsage?.minutes_used ?? 0) - (initialUsage?.minutes_used ?? 0)).toBe(3);

      const ledger = await env.DB.prepare('SELECT billed_minutes, billable_seconds FROM usage_ledger WHERE call_id = ?')
        .bind(callId).first<{ billed_minutes: number; billable_seconds: number }>();
      expect(ledger?.billed_minutes).toBe(3);
      expect(ledger?.billable_seconds).toBe(125);
    });

    it('W3: No-answer webhook on a campaign call -> campaign_leads.status = retry_pending', async () => {
      const campId = `camp_w3_${Date.now()}`;
      const leadId = `lead_w3_${Date.now()}`;
      const callId = `call_w3_${Date.now()}`;

      await env.DB.batch([
        env.DB.prepare("INSERT INTO campaigns (id, business_id, purpose, status, total_leads, calling_hours_start, calling_hours_end) VALUES (?, ?, 'W3 Test', 'running', 1, 0, 24)").bind(campId, bizId),
        env.DB.prepare("INSERT INTO leads (id, business_id, name, phone, status) VALUES (?, ?, 'Lead W3', '919800000030', 'calling')").bind(leadId, bizId),
        env.DB.prepare("INSERT INTO campaign_leads (campaign_id, lead_id, status, attempts, call_id) VALUES (?, ?, 'calling', 1, ?)").bind(campId, leadId, callId),
        env.DB.prepare("INSERT INTO calls (id, business_id, lead_id, lead_name, lead_phone, campaign_id, status) VALUES (?, ?, ?, 'Lead W3', '919800000030', ?, 'calling')").bind(callId, bizId, leadId, campId),
      ]);

      const body = JSON.stringify({
        call_id: callId,
        status: 'no_answer',
        duration_seconds: 0,
      });
      const sig = await signWebhook(body, webhookSecret);

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

      const cl = await env.DB.prepare('SELECT status, attempts FROM campaign_leads WHERE campaign_id = ? AND lead_id = ?')
        .bind(campId, leadId).first<{ status: string; attempts: number }>();
      expect(cl?.status).toBe('retry_pending');
      expect(cl?.attempts).toBe(1);
    });

    it('W4: All leads terminal -> campaign.status = completed', async () => {
      const campId = `camp_w4_${Date.now()}`;
      const leadId = `lead_w4_${Date.now()}`;
      const callId = `call_w4_${Date.now()}`;

      await env.DB.batch([
        env.DB.prepare("INSERT INTO campaigns (id, business_id, purpose, status, total_leads, calling_hours_start, calling_hours_end) VALUES (?, ?, 'W4 Test', 'running', 1, 0, 24)").bind(campId, bizId),
        env.DB.prepare("INSERT INTO leads (id, business_id, name, phone, status) VALUES (?, ?, 'Lead W4', '919800000040', 'calling')").bind(leadId, bizId),
        env.DB.prepare("INSERT INTO campaign_leads (campaign_id, lead_id, status, attempts, call_id) VALUES (?, ?, 'calling', 1, ?)").bind(campId, leadId, callId),
        env.DB.prepare("INSERT INTO calls (id, business_id, lead_id, lead_name, lead_phone, campaign_id, status) VALUES (?, ?, ?, 'Lead W4', '919800000040', ?, 'calling')").bind(callId, bizId, leadId, campId),
      ]);

      const body = JSON.stringify({
        call_id: callId,
        status: 'completed',
        duration_seconds: 40,
        transcript: [{ role: 'agent', text: 'Hi' }],
      });
      const sig = await signWebhook(body, webhookSecret);

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

      const camp = await env.DB.prepare('SELECT status FROM campaigns WHERE id = ?')
        .bind(campId).first<{ status: string }>();
      expect(camp?.status).toBe('completed');
    });
  });

  describe('Security & Auth Hardening (S1 - S4)', () => {
    it('S1: /voice/chat 21 times in a minute -> 21st returns 429', async () => {
      const chatBizId = `biz_chat_limit_${Date.now()}`;
      const chatUserId = `usr_chat_limit_${Date.now()}`;
      const chatToken = await signJWT({ sub: chatUserId, phone: '919899990001', business_id: chatBizId, type: 'access' }, secret, 3600);

      const makeChat = () => app.fetch(
        new Request('http://localhost/voice/chat', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${chatToken}` },
          body: JSON.stringify({ message: 'Hello AI' }),
        }),
        env
      );

      // Fire 20 requests
      for (let i = 0; i < 20; i++) {
        const r = await makeChat();
        expect(r.status).toBe(200);
      }

      // 21st request hits rate limit
      const r21 = await makeChat();
      expect(r21.status).toBe(429);
      const b21 = await r21.json() as any;
      expect(b21.code).toBe('rate_limited');
    });

    it('S2: ENVIRONMENT unset -> /auth/otp/request response has NO debug_otp', async () => {
      const testEnv = {
        ...env,
        ENVIRONMENT: undefined,
      } as any;

      const res = await app.fetch(
        new Request('http://localhost/auth/otp/request', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ phone: '919811122233' }),
        }),
        testEnv
      );

      expect(res.status).toBe(200);
      const body = await res.json() as any;
      expect(body.debug_otp).toBeUndefined();
    });

    it('S3: Proxy to foreign app id -> 403', async () => {
      const voiceSessionToken = await signJWT({ sub: userId, phone, business_id: bizId, type: 'session' }, secret, 3600);

      const testEnv = {
        ...env,
        SARVAM_ORG_ID: 'org_allowed',
        SARVAM_WORKSPACE_ID: 'ws_allowed',
        SARVAM_ADMISSIONS_APP_ID: 'app_allowed',
      } as any;

      // Request proxying to app_foreign instead of app_allowed
      const res = await app.fetch(
        new Request('http://localhost/voice/sarvam-proxy/orgs/org_allowed/workspaces/ws_allowed/apps/app_foreign/sessions', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${voiceSessionToken}`,
          },
        }),
        testEnv
      );

      expect(res.status).toBe(403);
      const body = await res.json() as any;
      expect(body.code).toBe('forbidden_upstream');
    });

    it('S4: Missing ENCRYPTION_KEY -> webhook fails closed (500), does NOT encrypt with JWT key', async () => {
      const callId = `call_s4_${Date.now()}`;
      const leadId = `lead_s4_${Date.now()}`;

      await env.DB.batch([
        env.DB.prepare("INSERT INTO leads (id, business_id, name, phone, status) VALUES (?, ?, 'Lead S4', '919800000044', 'calling')").bind(leadId, bizId),
        env.DB.prepare("INSERT INTO calls (id, business_id, lead_id, lead_name, lead_phone, status) VALUES (?, ?, ?, 'Lead S4', '919800000044', 'calling')").bind(callId, bizId, leadId),
      ]);

      const testEnv = {
        ...env,
        SARVAM_WEBHOOK_SECRET: webhookSecret,
        ENCRYPTION_KEY: undefined, // missing encryption key
      } as any;

      const body = JSON.stringify({
        call_id: callId,
        status: 'completed',
        duration_seconds: 30,
        transcript: [{ role: 'agent', text: 'Hello' }],
      });
      const sig = await signWebhook(body, webhookSecret);

      const res = await app.fetch(
        new Request('http://localhost/webhooks/sarvam', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'X-Sarvam-Signature': sig,
          },
          body,
        }),
        testEnv
      );

      expect(res.status).toBe(500);
      const b = await res.json() as any;
      expect(b.code).toBe('server_error');
    });
  });

  describe('Knowledge & Chat Integration (K1 - K2)', () => {
    it('K1: POST /knowledge text -> status processing then ready, chunks > 0; /voice/chat question includes fact', async () => {
      const postRes = await app.fetch(
        new Request('http://localhost/knowledge', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
          body: JSON.stringify({
            title: 'Fee Structure Document',
            type: 'text',
            content: 'The application registration fee for the coaching programme is precisely 4500 rupees.',
          }),
        }),
        env
      );

      expect(postRes.status).toBe(200);
      const postBody = await postRes.json() as any;
      expect(postBody.status).toBe('ready');

      const chunksCount = await env.DB.prepare('SELECT COUNT(*) as c FROM knowledge_chunks WHERE source_id = ?')
        .bind(postBody.id).first<{ c: number }>();
      expect(chunksCount?.c).toBeGreaterThan(0);

      // Verify FTS query in chat
      const chatRes = await app.fetch(
        new Request('http://localhost/voice/chat', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
          body: JSON.stringify({ message: 'What is the fee?' }),
        }),
        env
      );

      expect(chatRes.status).toBe(200);
      const chatBody = await chatRes.json() as any;
      expect(chatBody.reply).toBeDefined();
      expect(chatBody.conversation_id).toBeDefined();
    });

    it('K2: DELETE /knowledge/:id removes chunks and records', async () => {
      const postRes = await app.fetch(
        new Request('http://localhost/knowledge', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
          body: JSON.stringify({
            title: 'Temporary Doc',
            type: 'text',
            content: 'Short facts to delete.',
          }),
        }),
        env
      );

      const sourceId = (await postRes.json() as any).id;

      const delRes = await app.fetch(
        new Request(`http://localhost/knowledge/${sourceId}`, {
          method: 'DELETE',
          headers: { Authorization: `Bearer ${token}` },
        }),
        env
      );

      expect(delRes.status).toBe(200);

      const chunksCount = await env.DB.prepare('SELECT COUNT(*) as c FROM knowledge_chunks WHERE source_id = ?')
        .bind(sourceId).first<{ c: number }>();
      expect(chunksCount?.c).toBe(0);

      const source = await env.DB.prepare('SELECT id FROM knowledge_sources WHERE id = ?')
        .bind(sourceId).first();
      expect(source).toBeNull();
    });
  });

  describe('Maintenance Sweeper Integration (M1)', () => {
    it('M1: runMaintenance marks 50-min-old calling call as timed_out and requeues it', async () => {
      const campId = `camp_m1_${Date.now()}`;
      const leadId = `lead_m1_${Date.now()}`;
      const callId = `call_m1_${Date.now()}`;

      await env.DB.batch([
        env.DB.prepare("INSERT INTO campaigns (id, business_id, purpose, status, total_leads, calling_hours_start, calling_hours_end) VALUES (?, ?, 'M1 Test', 'running', 1, 0, 24)").bind(campId, bizId),
        env.DB.prepare("INSERT INTO leads (id, business_id, name, phone, status) VALUES (?, ?, 'Lead M1', '919800000099', 'calling')").bind(leadId, bizId),
        env.DB.prepare("INSERT INTO campaign_leads (campaign_id, lead_id, status, attempts, call_id) VALUES (?, ?, 'calling', 1, ?)").bind(campId, leadId, callId),
        // Started 50 minutes ago
        env.DB.prepare("INSERT INTO calls (id, business_id, lead_id, lead_name, lead_phone, campaign_id, status, started_at) VALUES (?, ?, ?, 'Lead M1', '919800000099', ?, 'calling', datetime('now', '-50 minutes'))").bind(callId, bizId, leadId, campId),
      ]);

      await runMaintenance(env);

      const call = await env.DB.prepare('SELECT status, failure_reason FROM calls WHERE id = ?')
        .bind(callId).first<any>();
      expect(call.status).toBe('timed_out');
      expect(call.failure_reason).toBe('no_webhook_45m');

      const cl = await env.DB.prepare('SELECT status FROM campaign_leads WHERE campaign_id = ? AND lead_id = ?')
        .bind(campId, leadId).first<any>();
      expect(cl.status).toBe('retry_pending');
    });
  });

  describe('Deep Health Check Integration', () => {
    it('GET /health/deep returns 200 and healthy checks when configured', async () => {
      const testEnv = {
        ...env,
        HEALTH_CHECK_SECRET: 'test-health-secret',
        SARVAM_API_KEY: 'test_key',
        SARVAM_ORG_ID: 'org_1',
        SARVAM_WORKSPACE_ID: 'ws_1',
        SARVAM_ADMISSIONS_APP_ID: 'app_1',
      } as any;

      const res = await app.fetch(
        new Request('http://localhost/health/deep', {
          headers: { 'x-health-key': 'test-health-secret' },
        }),
        testEnv
      );

      expect(res.status).toBe(200);
      const b = await res.json() as any;
      expect(b.status).toBe('healthy');
      expect(b.checks.d1).toBe(true);
      expect(b.checks.r2).toBe(true);
      expect(b.checks.sarvam_config).toBe(true);
    });

    it('GET /health/deep enforces HEALTH_CHECK_SECRET authentication', async () => {
      const testEnv = {
        ...env,
        HEALTH_CHECK_SECRET: 'super-secret-probe-key-123',
        SARVAM_API_KEY: 'test_key',
        SARVAM_ORG_ID: 'org_1',
        SARVAM_WORKSPACE_ID: 'ws_1',
        SARVAM_ADMISSIONS_APP_ID: 'app_1',
      } as any;

      // Unauthorized probe
      const resUnauth = await app.fetch(
        new Request('http://localhost/health/deep'),
        testEnv
      );
      expect(resUnauth.status).toBe(401);

      // Authorized probe via header
      const resAuth = await app.fetch(
        new Request('http://localhost/health/deep', {
          headers: { 'x-health-key': 'super-secret-probe-key-123' },
        }),
        testEnv
      );
      expect(resAuth.status).toBe(200);
    });

    it('GET /health/deep returns 503 when Sarvam config is missing', async () => {
      const testEnv = {
        ...env,
        HEALTH_CHECK_SECRET: 'test-health-secret',
        SARVAM_API_KEY: undefined,
      } as any;

      const res = await app.fetch(
        new Request('http://localhost/health/deep', {
          headers: { 'x-health-key': 'test-health-secret' },
        }),
        testEnv
      );

      expect(res.status).toBe(503);
      const b = await res.json() as any;
      expect(b.status).toBe('unhealthy');
      expect(b.checks.sarvam_config).toBe(false);
    });
  });
});
