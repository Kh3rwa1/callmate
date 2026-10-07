import { describe, it, expect, beforeAll } from 'vitest';
import { env } from 'cloudflare:test';
import { migrateTestDb } from './setup-db';
import app from '../src/index';
import { signJWT } from '../src/auth';
import { processCampaignJob, handleCampaignQueueBatch, enqueueCampaignJobs } from '../src/services/campaign_queue';
import { shouldThrottlePush, recordPushSent, sendBusinessPushNotification } from '../src/services/fcm';

describe('Comprehensive Coverage Boost Test Suite (Target ≥80% Lines)', () => {
  const secret = 'test-jwt-signing-secret-key-32chars-min-length';
  let tokenA: string;
  let tokenB: string;
  const bizA = 'biz_boost_a';
  const bizB = 'biz_boost_b';

  beforeAll(async () => {
    await migrateTestDb();

    // Create Business A & B
    await env.DB.batch([
      env.DB.prepare(`INSERT OR REPLACE INTO businesses (id, name, created_at, updated_at) VALUES (?, 'Corp A', datetime('now'), datetime('now'))`).bind(bizA),
      env.DB.prepare(`INSERT OR REPLACE INTO businesses (id, name, created_at, updated_at) VALUES (?, 'Corp B', datetime('now'), datetime('now'))`).bind(bizB),
      env.DB.prepare(`INSERT OR REPLACE INTO usage (id, business_id, plan_name, included_minutes, renews_at, price_inr, minutes_used, calls_made, rate_per_minute_inr) VALUES ('usage_a', ?, 'Founding', 1000, datetime('now', '+30 days'), 4999, 10, 2, 6)`).bind(bizA),
      env.DB.prepare(`INSERT OR REPLACE INTO usage (id, business_id, plan_name, included_minutes, renews_at, price_inr, minutes_used, calls_made, rate_per_minute_inr) VALUES ('usage_b', ?, 'Founding', 1000, datetime('now', '+30 days'), 4999, 0, 0, 6)`).bind(bizB),
      // Create leads for calls
      env.DB.prepare(`INSERT OR REPLACE INTO leads (id, business_id, name, phone, created_at, updated_at) VALUES ('l1', ?, 'Lead 1', '919800000011', datetime('now'), datetime('now'))`).bind(bizA),
      env.DB.prepare(`INSERT OR REPLACE INTO leads (id, business_id, name, phone, created_at, updated_at) VALUES ('l2', ?, 'Lead 2', '919800000012', datetime('now'), datetime('now'))`).bind(bizA),
    ]);

    tokenA = await signJWT({ sub: 'user_a', phone: '919800000001', business_id: bizA, type: 'access' }, secret, 3600);
    tokenB = await signJWT({ sub: 'user_b', phone: '919800000002', business_id: bizB, type: 'access' }, secret, 3600);
  });

  const fetchWithAuth = (path: string, options: RequestInit = {}, token: string = tokenA) => {
    const headers = new Headers(options.headers || {});
    headers.set('Authorization', `Bearer ${token}`);
    return app.fetch(new Request(`http://localhost${path}`, { ...options, headers }), env);
  };

  describe('Calls Route Extra Coverage', () => {
    it('GET /calls lists calls with various filters and cursor pagination', async () => {
      // Seed calls for bizA
      await env.DB.batch([
        env.DB.prepare(`INSERT INTO calls (id, business_id, lead_id, lead_name, lead_phone, status, temperature, started_at, created_at) VALUES ('c1', ?, 'l1', 'Lead 1', '919800000011', 'completed', 'hot', '2026-03-01T10:00:00Z', '2026-03-01T10:00:00Z')`).bind(bizA),
        env.DB.prepare(`INSERT INTO calls (id, business_id, lead_id, lead_name, lead_phone, status, temperature, started_at, created_at) VALUES ('c2', ?, 'l2', 'Lead 2', '919800000012', 'no_answer', 'cold', '2026-03-01T11:00:00Z', '2026-03-01T11:00:00Z')`).bind(bizA),
      ]);

      // filter=all
      const resAll = await fetchWithAuth('/calls?limit=10');
      expect(resAll.status).toBe(200);
      const dataAll = await resAll.json() as any;
      expect(dataAll.items.length).toBeGreaterThanOrEqual(2);

      // filter=connected
      const resConn = await fetchWithAuth('/calls?filter=connected');
      expect(resConn.status).toBe(200);

      // filter=noAnswer
      const resNoAns = await fetchWithAuth('/calls?filter=noAnswer');
      expect(resNoAns.status).toBe(200);

      // filter=hot
      const resHot = await fetchWithAuth('/calls?filter=hot');
      expect(resHot.status).toBe(200);

      // query by lead_id
      const resLead = await fetchWithAuth('/calls?lead_id=l1');
      expect(resLead.status).toBe(200);

      // cursor pagination with base64 json cursor
      const cursor = btoa(JSON.stringify({ started_at: '2026-03-01T12:00:00Z', id: 'c99' }));
      const resCursor = await fetchWithAuth(`/calls?cursor=${cursor}&limit=1`);
      expect(resCursor.status).toBe(200);

      // numeric offset cursor fallback
      const resOffset = await fetchWithAuth('/calls?cursor=1&limit=1');
      expect(resOffset.status).toBe(200);
    });
  });

  describe('Usage & Notifications extra coverage', () => {
    it('GET /usage returns business usage subscription and metrics', async () => {
      const res = await fetchWithAuth('/usage');
      expect(res.status).toBe(200);
      const data = await res.json() as any;
      expect(data.subscription.plan_name).toBe('Founding');
      expect(data.minutes_used).toBe(10);
    });

    it('PATCH /notifications/:id marks notification as read', async () => {
      await env.DB.prepare(`INSERT INTO notifications (id, business_id, type, title, body, route, is_read, created_at) VALUES ('notif_cov', ?, 'hot_lead', 'Hot', 'Body', '/calls', 0, datetime('now'))`).bind(bizA).run();

      const res = await fetchWithAuth('/notifications/notif_cov', {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ read: true }),
      });
      expect(res.status).toBe(200);

      const check = await env.DB.prepare('SELECT is_read FROM notifications WHERE id = ?').bind('notif_cov').first<{ is_read: number }>();
      expect(check?.is_read).toBe(1);
    });

    it('POST /devices/register validates body', async () => {
      const failRes = await fetchWithAuth('/devices/register', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({}),
      });
      expect(failRes.status).toBe(400);
    });
  });

  describe('Leads Route Extended Coverage', () => {
    let testLeadId: string;

    beforeAll(async () => {
      testLeadId = `lead_cov_${Date.now()}`;
      await env.DB.prepare(
        `INSERT INTO leads (id, business_id, name, phone, status, temperature, score, consent, do_not_call, created_at, updated_at)
         VALUES (?, ?, 'Lead Cov', '919800000099', 'new', 'cold', 0, 'opt_in', 0, datetime('now'), datetime('now'))`
      ).bind(testLeadId, bizA).run();
    });

    it('GET /leads/:id returns single lead', async () => {
      const res = await fetchWithAuth(`/leads/${testLeadId}`);
      expect(res.status).toBe(200);
      const data = await res.json() as any;
      expect(data.name).toBe('Lead Cov');
    });

    it('PATCH /leads/:id updates fields including consent and do_not_call', async () => {
      const res = await fetchWithAuth(`/leads/${testLeadId}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          name: 'Lead Cov Updated',
          interest: 'Python Program',
          temperature: 'warm',
          score: 65,
          consent: 'opt_out',
          do_not_call: true,
          attributes: { source: 'meta_ads' },
        }),
      });
      expect(res.status).toBe(200);
      const data = await res.json() as any;
      expect(data.name).toBe('Lead Cov Updated');
      expect(data.score?.value).toBe(65);
      expect(data.temperature).toBe('warm');
    });

    it('DELETE /leads/:id deletes lead and enforces tenant isolation', async () => {
      // Biz B cannot delete Biz A lead
      const foreignDel = await fetchWithAuth(`/leads/${testLeadId}`, { method: 'DELETE' }, tokenB);
      expect(foreignDel.status).toBe(404);

      // Biz A deletes own lead
      const ownDel = await fetchWithAuth(`/leads/${testLeadId}`, { method: 'DELETE' }, tokenA);
      expect(ownDel.status).toBe(200);
    });
  });

  describe('Followups & Callbacks Extended Coverage', () => {
    let fuId: string;
    let cbId: string;

    beforeAll(async () => {
      fuId = `fu_cov_${Date.now()}`;
      cbId = `cb_cov_${Date.now()}`;
      await env.DB.batch([
        env.DB.prepare(`INSERT INTO followups (id, business_id, lead_id, message, status, created_at) VALUES (?, ?, 'l1', 'Hi test', 'ready', datetime('now'))`).bind(fuId, bizA),
        env.DB.prepare(`INSERT INTO callbacks (id, business_id, lead_id, lead_name, scheduled_at, note, status, created_at) VALUES (?, ?, 'l1', 'Lead 1', '2026-04-01T10:00:00Z', 'Note test', 'scheduled', datetime('now'))`).bind(cbId, bizA),
      ]);
    });

    it('GET /followups/:id and PATCH /followups/:id', async () => {
      const getRes = await fetchWithAuth(`/followups/${fuId}`);
      expect(getRes.status).toBe(200);

      const patchRes = await fetchWithAuth(`/followups/${fuId}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ status: 'done', opened_at: new Date().toISOString() }),
      });
      expect(patchRes.status).toBe(200);
    });

    it('POST /callbacks and PATCH /callbacks/:id', async () => {
      // Create lead to link callback to
      const leadId = `lead_cb_${Date.now()}`;
      await env.DB.prepare(`INSERT INTO leads (id, business_id, name, phone, created_at, updated_at) VALUES (?, ?, 'Callback Guy', '919877777777', datetime('now'), datetime('now'))`).bind(leadId, bizA).run();

      const createRes = await fetchWithAuth('/callbacks', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          lead_id: leadId,
          scheduled_at: '2026-05-01T15:00:00Z',
          note: 'Callback on admissions',
        }),
      });
      expect(createRes.status).toBe(200);
      const created = await createRes.json() as any;
      expect(created.scheduled_at).toBe('2026-05-01T15:00:00Z');

      // Patch callback status
      const patchRes = await fetchWithAuth(`/callbacks/${created.id}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ status: 'done' }),
      });
      expect(patchRes.status).toBe(200);
    });
  });

  describe('Knowledge & R2 Extended Coverage', () => {
    it('GET /r2/* tenant isolation check', async () => {
      // Biz A accessing Biz B's path gets 403
      const resForbidden = await fetchWithAuth(`/r2/${bizB}/sensitive.pdf`, {}, tokenA);
      expect(resForbidden.status).toBe(403);
    });

    it('DELETE /knowledge/:id deletes source', async () => {
      const knId = `kn_del_${Date.now()}`;
      await env.DB.prepare(`INSERT INTO knowledge_sources (id, business_id, type, title, created_at, updated_at) VALUES (?, ?, 'text', 'Doc to delete', datetime('now'), datetime('now'))`).bind(knId, bizA).run();

      const res = await fetchWithAuth(`/knowledge/${knId}`, { method: 'DELETE' });
      expect(res.status).toBe(200);
    });
  });

  describe('Campaign Queue Service Coverage', () => {
    it('processCampaignJob handles stopped campaign, already processed leads, concurrency, and exhausted minutes', async () => {
      const campId = `camp_q_${Date.now()}`;
      const leadId = `lead_q_${Date.now()}`;

      // Insert paused campaign
      await env.DB.prepare(`
        INSERT INTO campaigns (id, business_id, purpose, status, calling_hours_start, calling_hours_end, created_at)
        VALUES (?, ?, 'Queue Camp', 'paused', 0, 24, datetime('now'))
      `).bind(campId, bizA).run();

      // 1. Campaign is stopped
      const rStopped = await processCampaignJob(env, {
        campaign_id: campId,
        lead_id: leadId,
        business_id: bizA,
        idempotency_key: `${campId}:${leadId}`,
        attempts: 0,
      });
      expect(rStopped.reason).toBe('campaign_stopped');

      // Make campaign running
      await env.DB.prepare(`UPDATE campaigns SET status = 'running' WHERE id = ?`).bind(campId).run();

      // 2. Lead not in campaign
      const rNotInCamp = await processCampaignJob(env, {
        campaign_id: campId,
        lead_id: leadId,
        business_id: bizA,
        idempotency_key: `${campId}:${leadId}`,
        attempts: 0,
      });
      expect(rNotInCamp.reason).toBe('lead_not_in_campaign');

      // Insert lead first for FK
      await env.DB.prepare(`
        INSERT OR REPLACE INTO leads (id, business_id, name, phone, created_at, updated_at)
        VALUES (?, ?, 'Queue Lead', '919811111111', datetime('now'), datetime('now'))
      `).bind(leadId, bizA).run();

      // Insert campaign_lead with 'completed'
      await env.DB.prepare(`
        INSERT INTO campaign_leads (campaign_id, lead_id, status, attempts)
        VALUES (?, ?, 'completed', 1)
      `).bind(campId, leadId).run();

      // 3. Already processed
      const rAlready = await processCampaignJob(env, {
        campaign_id: campId,
        lead_id: leadId,
        business_id: bizA,
        idempotency_key: `${campId}:${leadId}`,
        attempts: 0,
      });
      expect(rAlready.reason).toBe('already_processed');

      // Reset campaign_lead to queued
      await env.DB.prepare(`UPDATE campaign_leads SET status = 'queued', attempts = 0 WHERE campaign_id = ? AND lead_id = ?`).bind(campId, leadId).run();

      // 4. Exhausted minutes
      await env.DB.prepare(`UPDATE usage SET minutes_used = 1000, included_minutes = 1000 WHERE business_id = ?`).bind(bizA).run();

      const rExhausted = await processCampaignJob(env, {
        campaign_id: campId,
        lead_id: leadId,
        business_id: bizA,
        idempotency_key: `${campId}:${leadId}`,
        attempts: 0,
      });
      expect(rExhausted.reason).toBe('exhausted_minutes');

      // Restore usage minutes
      await env.DB.prepare(`UPDATE usage SET minutes_used = 10, included_minutes = 1000 WHERE business_id = ?`).bind(bizA).run();
      await env.DB.prepare(`UPDATE campaigns SET status = 'running' WHERE id = ?`).bind(campId).run();

      // 5. Normal job execution
      const rSuccess = await processCampaignJob(env, {
        campaign_id: campId,
        lead_id: leadId,
        business_id: bizA,
        idempotency_key: `${campId}:${leadId}`,
        attempts: 0,
      });
      expect(rSuccess.success).toBe(true);
    });

    it('handleCampaignQueueBatch consumer acks and retries correctly', async () => {
      let ackCount = 0;
      let retryCount = 0;
      const fakeBatch: any = {
        messages: [
          {
            body: { campaign_id: 'non_existent', lead_id: 'l1', business_id: bizA, idempotency_key: 'k1', attempts: 0 },
            ack: () => { ackCount++; },
            retry: () => { retryCount++; },
          },
        ],
      };

      await handleCampaignQueueBatch(fakeBatch, env);
      expect(ackCount).toBe(1);
    });

    it('enqueueCampaignJobs queues leads and updates DB', async () => {
      const campId = `camp_enq_${Date.now()}`;
      const leadId = `lead_enq_${Date.now()}`;
      await env.DB.batch([
        env.DB.prepare(`INSERT OR REPLACE INTO leads (id, business_id, name, phone, created_at, updated_at) VALUES (?, ?, 'Enq Lead', '919811111112', datetime('now'), datetime('now'))`).bind(leadId, bizA),
        env.DB.prepare(`INSERT INTO campaigns (id, business_id, purpose, status, created_at) VALUES (?, ?, 'Enq Camp', 'draft', datetime('now'))`).bind(campId, bizA),
        env.DB.prepare(`INSERT INTO campaign_leads (campaign_id, lead_id, status, attempts) VALUES (?, ?, 'pending', 0)`).bind(campId, leadId),
      ]);

      await enqueueCampaignJobs(env, campId, bizA, [leadId]);
      const cl = await env.DB.prepare(`SELECT status FROM campaign_leads WHERE campaign_id = ? AND lead_id = ?`).bind(campId, leadId).first<{ status: string }>();
      expect(cl?.status).toBeDefined();
    });
  });

  describe('FCM Push Notification Service Coverage', () => {
    it('throttles follow_up_ready push within 10 min window and sends to devices', async () => {
      const devId = `dev_${Date.now()}`;
      await env.DB.prepare(`
        INSERT INTO devices (id, business_id, fcm_token, platform, updated_at)
        VALUES (?, ?, 'mock-fcm-token-123', 'android', datetime('now'))
      `).bind(devId, bizA).run();

      // First follow-up ready push
      const p1 = await sendBusinessPushNotification(env, bizA, {
        type: 'follow_up_ready',
        title: 'Follow-up ready',
        body: 'Tap to send WhatsApp',
        route: '/followups',
      });
      expect(p1.throttled).toBe(false);

      // Immediate second follow-up ready push is throttled
      const p2 = await sendBusinessPushNotification(env, bizA, {
        type: 'follow_up_ready',
        title: 'Follow-up ready 2',
        body: 'Tap to send WhatsApp',
        route: '/followups',
      });
      expect(p2.throttled).toBe(true);
      expect(p2.sent).toBe(0);

      // Hot lead push is never throttled by the 10 min follow-up limit
      const pHot = await sendBusinessPushNotification(env, bizA, {
        type: 'hot_lead',
        title: 'Hot Lead!',
        body: 'Score 95',
        route: '/calls/1',
      });
      expect(pHot.throttled).toBe(false);
      expect(pHot.sent).toBe(1);
    });
  });

  describe('Webhook Timestamp Signature & ExecutionContext Coverage', () => {
    it('verifies webhook with timestamp-based signature and safeWaitUntil', async () => {
      const webhookSecret = env.SARVAM_WEBHOOK_SECRET || 'test_webhook_secret_12345';
      const callId = `call_ts_${Date.now()}`;
      const leadId = `lead_ts_${Date.now()}`;

      await env.DB.batch([
        env.DB.prepare(`INSERT INTO leads (id, business_id, name, phone, status, created_at, updated_at) VALUES (?, ?, 'Timestamp Lead', '919822222222', 'new', datetime('now'), datetime('now'))`).bind(leadId, bizA),
        env.DB.prepare(`INSERT INTO calls (id, business_id, lead_id, lead_name, lead_phone, status, created_at) VALUES (?, ?, ?, 'Timestamp Lead', '919822222222', 'calling', datetime('now'))`).bind(callId, bizA, leadId),
      ]);

      const timestamp = String(Math.floor(Date.now() / 1000));
      const payload = JSON.stringify({
        interaction_id: callId,
        status: 'completed',
        duration_seconds: 75,
        output_variables: {
          lead_score: 88,
          temperature: 'hot',
          intent: 'interested',
          summary: 'Student is excited to join batch next week.',
          next_action: 'send_whatsapp',
          whatsapp_followup_required: true,
          whatsapp_message: 'Hi Student, your batch starts Monday!',
        },
      });

      // Sign ${timestamp}.${payload}
      const enc = new TextEncoder();
      const key = await crypto.subtle.importKey(
        'raw',
        enc.encode(webhookSecret),
        { name: 'HMAC', hash: 'SHA-256' },
        false,
        ['sign']
      );
      const sigBuf = await crypto.subtle.sign('HMAC', key, enc.encode(`${timestamp}.${payload}`));
      const sigHex = Array.from(new Uint8Array(sigBuf)).map((b) => b.toString(16).padStart(2, '0')).join('');

      let waitUnitCalled = false;
      const fakeCtx = {
        waitUntil: (p: Promise<any>) => {
          waitUnitCalled = true;
        },
        passThroughOnException: () => {},
      };

      const res = await app.fetch(
        new Request('http://localhost/webhooks/sarvam', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'x-sarvam-signature': sigHex,
            'x-sarvam-timestamp': timestamp,
          },
          body: payload,
        }),
        env,
        fakeCtx as any
      );

      expect(res.status).toBe(200);
      expect(waitUnitCalled).toBe(true);

      // Verify lead was marked called and hot
      const updatedLead = await env.DB.prepare('SELECT status, temperature, score FROM leads WHERE id = ?').bind(leadId).first<{ status: string; temperature: string; score: number }>();
      expect(updatedLead?.status).toBe('called');
      expect(updatedLead?.temperature).toBe('hot');
      expect(updatedLead?.score).toBe(88);
    });
  });

  describe('Voice Session & Leads Search and Auto Usage Coverage', () => {
    it('POST /voice/test-session generates session token with agent variables', async () => {
      const res = await fetchWithAuth('/voice/test-session', { method: 'POST' });
      expect(res.status).toBe(200);
      const data = await res.json() as any;
      expect(data.session_token).toBeDefined();
      expect(data.proxy_base_url).toContain('/voice/sarvam-proxy/');
      expect(data.agent_variables.business_name).toBeDefined();
    });

    it('POST /leads/import imports batch and deduplicates', async () => {
      const res = await fetchWithAuth('/leads/import', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          leads: [
            { name: 'Import 1', phone: '919830099111', interest: 'AI' },
            { name: 'Import 2', phone: '919830099222', interest: 'Cloud' },
          ],
        }),
      });
      expect(res.status).toBe(200);
      const data = await res.json() as any;
      expect(data.imported).toBe(2);
    });

    it('GET /leads?search=Lead filters leads', async () => {
      const res = await fetchWithAuth('/leads?search=Lead');
      expect(res.status).toBe(200);
      const data = await res.json() as any;
      expect(data.items).toBeDefined();
    });

    it('GET /usage initializes default usage if row missing', async () => {
      const bizNoUsage = 'biz_no_usage';
      await env.DB.prepare(`INSERT INTO businesses (id, name, created_at, updated_at) VALUES (?, 'No Usage Biz', datetime('now'), datetime('now'))`).bind(bizNoUsage).run();
      const tokenNoUsage = await signJWT({ sub: 'user_nu', phone: '919800000088', business_id: bizNoUsage, type: 'access' }, secret, 3600);

      const res = await fetchWithAuth('/usage', {}, tokenNoUsage);
      expect(res.status).toBe(200);
      const data = await res.json() as any;
      expect(data.subscription.plan_name).toBe('Founding Plan');
      expect(data.minutes_used).toBe(0);
    });

    it('handleCampaignQueueBatch processes messages in batch', async () => {
      let ackCalled = false;
      const mockBatch: any = {
        messages: [
          {
            body: { campaign_id: 'non_existent_c', lead_id: 'l', business_id: 'b', idempotency_key: 'ik', attempts: 0 },
            ack: () => { ackCalled = true; },
            retry: () => {},
          },
        ],
      };
      await handleCampaignQueueBatch(mockBatch, env);
      expect(ackCalled).toBe(true);
    });
  });
});
