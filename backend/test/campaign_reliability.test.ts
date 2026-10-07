import { describe, it, expect, beforeAll, vi } from 'vitest';
import { env } from 'cloudflare:test';
import { migrateTestDb } from './setup-db';
import app from '../src/index';
import { signJWT } from '../src/auth';
import {
  processCampaignJob,
  enqueueCampaignJobs,
  CLAIMABLE_STATUSES,
  MAX_DIAL_ATTEMPTS,
} from '../src/services/campaign_queue';

describe('Phase 1 Campaign Queue Reliability Bug Reproductions', () => {
  const secret = 'test-jwt-signing-secret-key-32chars-min-length';
  const bizId = 'biz_queue_rel';
  const userId = 'usr_queue_rel';
  const phone = '919830009999';
  let token: string;

  beforeAll(async () => {
    await migrateTestDb();

    await env.DB.batch([
      env.DB.prepare("INSERT OR REPLACE INTO businesses (id, name, category) VALUES (?, 'Rel Academy', 'education')").bind(bizId),
      env.DB.prepare("INSERT OR REPLACE INTO users (id, phone, business_id) VALUES (?, ?, ?)").bind(userId, phone, bizId),
      env.DB.prepare("INSERT OR REPLACE INTO agents (id, business_id, name, role, status) VALUES ('agt_rel', ?, 'Maya', 'Counselor', 'active')").bind(bizId),
      env.DB.prepare("INSERT OR REPLACE INTO usage (id, business_id, plan_name, included_minutes, renews_at, price_inr, minutes_used, calls_made, rate_per_minute_inr) VALUES ('usg_rel', ?, 'Founding', 1000, datetime('now', '+30 days'), 4999, 0, 0, 6)").bind(bizId),
    ]);

    token = await signJWT({ sub: userId, phone, business_id: bizId, type: 'access' }, secret, 3600);
  });

  it('prevents double-start on running campaign (returns 409 invalid_state)', async () => {
    const campId = `camp_double_${Date.now()}`;
    await env.DB.prepare(
      `INSERT INTO campaigns (id, business_id, purpose, status, total_leads, created_at)
       VALUES (?, ?, 'Double Start Test', 'running', 1, datetime('now'))`
    ).bind(campId, bizId).run();

    const res = await app.fetch(
      new Request(`http://localhost/campaigns/${campId}/start`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${token}`,
        },
      }),
      env
    );

    expect(res.status).toBe(409);
    const body = (await res.json()) as any;
    expect(body.code).toBe('invalid_state');
  });

  it('resuming a paused campaign never re-dials completed or failed leads', async () => {
    const campId = `camp_resume_${Date.now()}`;
    const leadDone = `lead_done_${Date.now()}`;
    const leadPending = `lead_pend_${Date.now()}`;

    await env.DB.batch([
      env.DB.prepare(`INSERT INTO campaigns (id, business_id, purpose, status, total_leads, created_at) VALUES (?, ?, 'Resume Test', 'paused', 2, datetime('now'))`).bind(campId, bizId),
      env.DB.prepare(`INSERT INTO leads (id, business_id, name, phone, status, created_at, updated_at) VALUES (?, ?, 'Done Lead', '919830001111', 'called', datetime('now'), datetime('now'))`).bind(leadDone, bizId),
      env.DB.prepare(`INSERT INTO leads (id, business_id, name, phone, status, created_at, updated_at) VALUES (?, ?, 'Pending Lead', '919830002222', 'new', datetime('now'), datetime('now'))`).bind(leadPending, bizId),
      env.DB.prepare(`INSERT INTO campaign_leads (campaign_id, lead_id, status, attempts) VALUES (?, ?, 'completed', 1)`).bind(campId, leadDone),
      env.DB.prepare(`INSERT INTO campaign_leads (campaign_id, lead_id, status, attempts) VALUES (?, ?, 'pending', 0)`).bind(campId, leadPending),
    ]);

    const res = await app.fetch(
      new Request(`http://localhost/campaigns/${campId}/start`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${token}`,
        },
      }),
      env
    );

    expect(res.status).toBe(200);

    // Completed lead must remain 'completed' and not changed to queued or calling
    const clDone = await env.DB.prepare('SELECT status, attempts FROM campaign_leads WHERE campaign_id = ? AND lead_id = ?')
      .bind(campId, leadDone)
      .first<{ status: string; attempts: number }>();
    expect(clDone?.status).toBe('completed');
  });

  it('enqueueCampaignJobs only enqueues claimable leads (never completed leads)', async () => {
    const campId = `camp_enq_test_${Date.now()}`;
    const leadCompleted = `lead_comp_${Date.now()}`;
    const leadPending = `lead_pen_${Date.now()}`;

    await env.DB.batch([
      env.DB.prepare(`INSERT INTO campaigns (id, business_id, purpose, status, created_at) VALUES (?, ?, 'Enq Test', 'running', datetime('now'))`).bind(campId, bizId),
      env.DB.prepare(`INSERT INTO leads (id, business_id, name, phone, created_at, updated_at) VALUES (?, ?, 'Comp', '919830003333', datetime('now'), datetime('now'))`).bind(leadCompleted, bizId),
      env.DB.prepare(`INSERT INTO leads (id, business_id, name, phone, created_at, updated_at) VALUES (?, ?, 'Pend', '919830004444', datetime('now'), datetime('now'))`).bind(leadPending, bizId),
      env.DB.prepare(`INSERT INTO campaign_leads (campaign_id, lead_id, status, attempts) VALUES (?, ?, 'completed', 1)`).bind(campId, leadCompleted),
      env.DB.prepare(`INSERT INTO campaign_leads (campaign_id, lead_id, status, attempts) VALUES (?, ?, 'pending', 0)`).bind(campId, leadPending),
    ]);

    const queuedCount = await enqueueCampaignJobs(env, campId, bizId, [leadCompleted, leadPending]);
    expect(queuedCount).toBe(1); // Only pending lead was queued

    const clComp = await env.DB.prepare('SELECT status FROM campaign_leads WHERE campaign_id = ? AND lead_id = ?')
      .bind(campId, leadCompleted)
      .first<{ status: string }>();
    expect(clComp?.status).toBe('completed');
  });

  it('failed dial marks calls row as failed with failure_reason and transitions campaign_lead to retry_pending', async () => {
    const campId = `camp_dial_fail_${Date.now()}`;
    const leadId = `lead_dial_fail_${Date.now()}`;

    await env.DB.batch([
      env.DB.prepare(`INSERT INTO campaigns (id, business_id, purpose, status, created_at) VALUES (?, ?, 'Fail Dial Test', 'running', datetime('now'))`).bind(campId, bizId),
      env.DB.prepare(`INSERT INTO leads (id, business_id, name, phone, created_at, updated_at) VALUES (?, ?, 'Fail Lead', '919830005555', datetime('now'), datetime('now'))`).bind(leadId, bizId),
      env.DB.prepare(`INSERT INTO campaign_leads (campaign_id, lead_id, status, attempts) VALUES (?, ?, 'queued', 0)`).bind(campId, leadId),
    ]);

    // Mock fetch to simulate Sarvam 500 error
    const originalFetch = globalThis.fetch;
    globalThis.fetch = vi.fn().mockResolvedValue(new Response(JSON.stringify({ error: 'Internal Server Error' }), { status: 500 })) as any;

    try {
      const customEnv = {
        ...env,
        SARVAM_API_KEY: 'sk_live_real_key_for_test',
        SARVAM_ORG_ID: 'org_test',
        SARVAM_WORKSPACE_ID: 'ws_test',
        SARVAM_ADMISSIONS_APP_ID: 'app_test',
      };

      const result = await processCampaignJob(customEnv, {
        campaign_id: campId,
        lead_id: leadId,
        business_id: bizId,
        idempotency_key: `${campId}:${leadId}`,
        attempts: 0,
      });

      // Dial failed with 500, retryable!
      expect(result.success).toBe(false);
      expect(result.retry).toBe(true);

      // Check campaign_leads state
      const cl = await env.DB.prepare('SELECT status, attempts, error, call_id FROM campaign_leads WHERE campaign_id = ? AND lead_id = ?')
        .bind(campId, leadId)
        .first<{ status: string; attempts: number; error: string; call_id: string }>();
      expect(cl?.status).toBe('retry_pending');
      expect(cl?.attempts).toBe(1);
      expect(cl?.call_id).toBeDefined();

      // Check calls row: must be failed, NOT stuck in calling
      const call = await env.DB.prepare('SELECT status, failure_reason, campaign_id FROM calls WHERE id = ?')
        .bind(cl?.call_id)
        .first<{ status: string; failure_reason: string; campaign_id: string }>();
      expect(call?.status).toBe('failed');
      expect(call?.failure_reason).toContain('sarvam_http_500');
      expect(call?.campaign_id).toBe(campId);

      // Verify that on retry, the lead in retry_pending can be claimed and processed again (not rejected as already_processed)
      const retryResult = await processCampaignJob(customEnv, {
        campaign_id: campId,
        lead_id: leadId,
        business_id: bizId,
        idempotency_key: `${campId}:${leadId}:2`,
        attempts: 1,
      });
      // Second attempt was also processed (not blocked by 'already_processed')
      const cl2 = await env.DB.prepare('SELECT attempts FROM campaign_leads WHERE campaign_id = ? AND lead_id = ?')
        .bind(campId, leadId)
        .first<{ attempts: number }>();
      expect(cl2?.attempts).toBe(2);
    } finally {
      globalThis.fetch = originalFetch;
    }
  });
});
