import { describe, it, expect, beforeAll } from 'vitest';
import { env } from 'cloudflare:test';
import { migrateTestDb } from './setup-db';
import app from '../src/index';
import {
  billableMinutes,
  claimWebhookEvent,
  recordCallUsage,
} from '../src/services/billing';

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

describe('Phase 2 Webhook Idempotency & Billing Integrity Tests', () => {
  const secret = 'test_webhook_secret_12345';
  const bizId = 'biz_bill_test';
  const leadId = 'lead_bill_test';
  const campId = 'cmp_bill_test';

  beforeAll(async () => {
    await migrateTestDb();

    await env.DB.batch([
      env.DB.prepare("INSERT OR REPLACE INTO businesses (id, name) VALUES (?, 'Billing Academy')").bind(bizId),
      env.DB.prepare("INSERT OR REPLACE INTO leads (id, business_id, name, phone, status) VALUES (?, ?, 'Rohit Sharma', '919830009988', 'new')").bind(leadId, bizId),
      env.DB.prepare("INSERT OR REPLACE INTO usage (id, business_id, plan_name, included_minutes, renews_at, price_inr, minutes_used, calls_made, rate_per_minute_inr) VALUES ('usg_bill', ?, 'Founding', 1000, datetime('now', '+30 days'), 4999, 0, 0, 6)").bind(bizId),
      env.DB.prepare("INSERT OR REPLACE INTO campaigns (id, business_id, purpose, status, total_leads, completed_leads, connected_leads, created_at) VALUES (?, ?, 'Billing Campaign', 'running', 1, 0, 0, datetime('now'))").bind(campId, bizId),
    ]);
  });

  describe('billableMinutes pure function', () => {
    it('charges 0 for unanswered calls regardless of duration', () => {
      expect(billableMinutes('no_answer', 120)).toEqual({ minutes: 0, seconds: 0, flagged: false });
      expect(billableMinutes('busy', 60)).toEqual({ minutes: 0, seconds: 0, flagged: false });
      expect(billableMinutes('failed', 45)).toEqual({ minutes: 0, seconds: 0, flagged: false });
    });

    it('charges 0 and flags missing or negative duration on connected call', () => {
      expect(billableMinutes('completed', null)).toEqual({ minutes: 0, seconds: 0, flagged: true });
      expect(billableMinutes('connected', undefined)).toEqual({ minutes: 0, seconds: 0, flagged: true });
      expect(billableMinutes('completed', -10)).toEqual({ minutes: 0, seconds: 0, flagged: true });
    });

    it('accurately computes ceil minutes for valid connected calls', () => {
      expect(billableMinutes('completed', 0)).toEqual({ minutes: 0, seconds: 0, flagged: false });
      // Connected calls under 10 s are free for the owner (MIN_BILLABLE_SECONDS).
      expect(billableMinutes('completed', 1)).toEqual({ minutes: 0, seconds: 1, flagged: false });
      expect(billableMinutes('completed', 9.9)).toEqual({ minutes: 0, seconds: 9, flagged: false });
      expect(billableMinutes('completed', 10)).toEqual({ minutes: 1, seconds: 10, flagged: false });
      expect(billableMinutes('completed', 60)).toEqual({ minutes: 1, seconds: 60, flagged: false });
      expect(billableMinutes('completed', 61)).toEqual({ minutes: 2, seconds: 61, flagged: false });
      expect(billableMinutes('answered', 125.7)).toEqual({ minutes: 3, seconds: 125, flagged: false });
    });
  });

  describe('claimWebhookEvent', () => {
    it('claims an event on first attempt and rejects duplicate replay', async () => {
      const key = `test_ev_${Date.now()}`;
      const first = await claimWebhookEvent(env.DB, key, 'sarvam');
      expect(first).toBe(true);

      const second = await claimWebhookEvent(env.DB, key, 'sarvam');
      expect(second).toBe(false);
    });
  });

  describe('recordCallUsage ledger idempotency', () => {
    it('records usage at most once and handles duration upgrades without double billing', async () => {
      const cId = `call_ledger_${Date.now()}`;
      const delta1 = await recordCallUsage(env, bizId, cId, 2, 120);
      expect(delta1).toBe(2);

      // Replaying identical usage results in delta 0
      const delta2 = await recordCallUsage(env, bizId, cId, 2, 120);
      expect(delta2).toBe(0);

      // If duration increases, only the delta is billed
      const delta3 = await recordCallUsage(env, bizId, cId, 3, 180);
      expect(delta3).toBe(1);

      // If lower duration is reported later, delta is 0
      const delta4 = await recordCallUsage(env, bizId, cId, 1, 60);
      expect(delta4).toBe(0);
    });
  });

  describe('handleSarvamWebhook wiring', () => {
    it('does not create follow-ups for no_answer call even if message is in payload', async () => {
      const callNoAnswer = `call_no_ans_${Date.now()}`;
      await env.DB.prepare(
        `INSERT INTO calls (id, business_id, lead_id, lead_name, lead_phone, status, started_at)
         VALUES (?, ?, ?, 'No Answer Lead', '919830001234', 'calling', datetime('now'))`
      ).bind(callNoAnswer, bizId, leadId).run();

      const body = JSON.stringify({
        call_id: callNoAnswer,
        status: 'no_answer',
        duration_seconds: 0,
        output_variables: {
          whatsapp_followup_required: true,
          whatsapp_message: 'Hi, sorry we missed you!',
        },
      });
      const sig = await signWebhook(body, secret);

      const res = await app.fetch(
        new Request('http://localhost/webhooks/sarvam', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'X-Sarvam-Signature': `sha256=${sig}`,
            'X-Sarvam-Timestamp': String(Math.floor(Date.now() / 1000)),
          },
          body,
        }),
        env
      );

      expect(res.status).toBe(200);

      // Verify no follow-up row was created
      const fu = await env.DB.prepare('SELECT * FROM followups WHERE call_id = ?').bind(callNoAnswer).first();
      expect(fu).toBeNull();
    });

    it('closes the campaign loop: updates campaign_leads, bumps campaign metrics, and marks campaign completed', async () => {
      const testCampId = `camp_loop_${Date.now()}`;
      const testLeadId = `lead_loop_${Date.now()}`;
      const testCallId = `call_loop_${Date.now()}`;

      await env.DB.batch([
        env.DB.prepare(`INSERT INTO campaigns (id, business_id, purpose, status, total_leads, completed_leads, connected_leads, hot_leads, created_at)
                        VALUES (?, ?, 'Loop Camp', 'running', 1, 0, 0, 0, datetime('now'))`).bind(testCampId, bizId),
        env.DB.prepare(`INSERT INTO leads (id, business_id, name, phone, status, created_at, updated_at)
                        VALUES (?, ?, 'Loop Lead', '919830007777', 'calling', datetime('now'), datetime('now'))`).bind(testLeadId, bizId),
        env.DB.prepare(`INSERT INTO campaign_leads (campaign_id, lead_id, call_id, status, attempts)
                        VALUES (?, ?, ?, 'calling', 1)`).bind(testCampId, testLeadId, testCallId),
        env.DB.prepare(`INSERT INTO calls (id, business_id, lead_id, lead_name, lead_phone, campaign_id, status, started_at)
                        VALUES (?, ?, ?, 'Loop Lead', '919830007777', ?, 'calling', datetime('now'))`).bind(testCallId, bizId, testLeadId, testCampId),
      ]);

      const body = JSON.stringify({
        call_id: testCallId,
        status: 'completed',
        duration_seconds: 90,
        output_variables: {
          lead_score: 90,
          temperature: 'hot',
          intent: 'interested',
          summary: 'Student is ready to join batch next week.',
          next_action: 'send_whatsapp',
          whatsapp_followup_required: true,
        },
      });
      const sig = await signWebhook(body, secret);

      const res = await app.fetch(
        new Request('http://localhost/webhooks/sarvam', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'X-Sarvam-Signature': `sha256=${sig}`,
            'X-Sarvam-Timestamp': String(Math.floor(Date.now() / 1000)),
          },
          body,
        }),
        env
      );

      expect(res.status).toBe(200);

      // Verify campaign_leads is marked completed
      const cl = await env.DB.prepare('SELECT status FROM campaign_leads WHERE call_id = ?').bind(testCallId).first<{ status: string }>();
      expect(cl?.status).toBe('completed');

      // Verify campaign metrics updated and campaign marked completed
      const camp = await env.DB.prepare('SELECT status, completed_leads, connected_leads, hot_leads, completed_at FROM campaigns WHERE id = ?')
        .bind(testCampId)
        .first<{ status: string; completed_leads: number; connected_leads: number; hot_leads: number; completed_at: string }>();

      expect(camp?.completed_leads).toBe(1);
      expect(camp?.connected_leads).toBe(1);
      expect(camp?.hot_leads).toBe(1);
      expect(camp?.status).toBe('completed');
      expect(camp?.completed_at).toBeDefined();
    });
  });
});
