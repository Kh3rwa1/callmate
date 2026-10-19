import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { env } from 'cloudflare:test';
import { migrateTestDb } from './setup-db';
import { useIndianBusinessHours, useRealClock } from './clock';
import worker from '../src/index';
import { signJWT } from '../src/auth';
import {
  processCampaignJob,
  sarvamMaxConcurrentCalls,
  DEFAULT_SARVAM_MAX_CONCURRENT_CALLS,
} from '../src/services/campaign_queue';

const jwtSecret = 'test-jwt-signing-secret-key-32chars-min-length';
const bizId = 'biz_slots';
const otherBiz = 'biz_slots_other';
let token: string;
// Two Sarvam slots for the whole platform in this file.
const slotEnv = () => ({ ...env, SARVAM_MAX_CONCURRENT_CALLS: '2' }) as any;

beforeAll(async () => {
  useIndianBusinessHours();
  await migrateTestDb();
  await env.DB.batch([
    env.DB.prepare("INSERT OR REPLACE INTO businesses (id, name) VALUES (?, 'Das Gym')").bind(bizId),
    env.DB.prepare("INSERT OR REPLACE INTO businesses (id, name) VALUES (?, 'Other')").bind(otherBiz),
    env.DB.prepare("INSERT OR REPLACE INTO users (id, phone, business_id) VALUES ('usr_slots', '919830088888', ?)").bind(bizId),
    env.DB.prepare(
      `INSERT OR REPLACE INTO agents (id, business_id, name, role, status, calling_hours_start, calling_hours_end, voice, languages)
       VALUES ('agt_slots', ?, 'Maya', 'Sales', 'active', 9, 21, 'Warm · Female', '["Hindi"]')`
    ).bind(bizId),
    env.DB.prepare("INSERT OR REPLACE INTO usage (id, business_id, included_minutes, minutes_used) VALUES ('usg_slots', ?, 100000, 0)").bind(bizId),
    env.DB.prepare(
      `INSERT OR REPLACE INTO leads (id, business_id, name, phone, status, consent)
       VALUES ('lead_slots', ?, 'Rina Das', '919830088881', 'new', 'existing_customer')`
    ).bind(bizId),
    env.DB.prepare(
      `INSERT OR REPLACE INTO leads (id, business_id, name, phone, status, consent)
       VALUES ('lead_slots_other', ?, 'Amit Sen', '919830088889', 'calling', 'existing_customer')`
    ).bind(otherBiz),
    // Another business already has two calls on the line.
    ...[1, 2].map((i) => env.DB.prepare(
      `INSERT OR REPLACE INTO calls (id, business_id, lead_id, lead_name, lead_phone, status, started_at)
       VALUES (?, ?, 'lead_slots_other', 'Amit Sen', '919830088889', 'calling', datetime('now'))`
    ).bind(`call_slots_busy_${i}`, otherBiz)),
  ]);
  token = await signJWT({ sub: 'usr_slots', phone: '919830088888', business_id: bizId, type: 'access' }, jwtSecret, 3600);
});

afterAll(useRealClock);

describe("Sarvam's organisation-wide concurrent call limit", () => {
  it('defaults to the pay-as-you-go limit and reads SARVAM_MAX_CONCURRENT_CALLS', () => {
    expect(DEFAULT_SARVAM_MAX_CONCURRENT_CALLS).toBe(4);
    expect(sarvamMaxConcurrentCalls({})).toBe(4);
    expect(sarvamMaxConcurrentCalls({ SARVAM_MAX_CONCURRENT_CALLS: '10' })).toBe(10);
    expect(sarvamMaxConcurrentCalls({ SARVAM_MAX_CONCURRENT_CALLS: '0' })).toBe(4);
  });

  it("a manual call waits while other businesses' calls fill every slot", async () => {
    const call = () => worker.fetch(new Request(`http://localhost/leads/lead_slots/call`, {
      method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    }), slotEnv());
    const busy = await call();
    expect(busy.status).toBe(429);
    expect(((await busy.json()) as any).code).toBe('concurrency_limit');

    await env.DB.prepare("UPDATE calls SET status = 'completed' WHERE id = 'call_slots_busy_1'").run();
    expect((await call()).status).toBe(200);
  });

  it('a campaign dial is re-queued, not sent, while the slots are full', async () => {
    await env.DB.prepare("UPDATE calls SET status = 'calling' WHERE id = 'call_slots_busy_1'").run();
    await env.DB.batch([
      env.DB.prepare(
        `INSERT OR REPLACE INTO leads (id, business_id, name, phone, status, consent)
         VALUES ('lead_slots_c', ?, 'Joy Das', '919830088882', 'new', 'existing_customer')`
      ).bind(bizId),
      env.DB.prepare(
        `INSERT OR REPLACE INTO campaigns (id, business_id, purpose, status, total_leads, calling_hours_start, calling_hours_end)
         VALUES ('cmp_slots', ?, 'slots', 'running', 1, 0, 24)`
      ).bind(bizId),
      env.DB.prepare("INSERT OR REPLACE INTO campaign_leads (campaign_id, lead_id, status) VALUES ('cmp_slots', 'lead_slots_c', 'queued')"),
    ]);
    const out = await processCampaignJob(slotEnv(), {
      campaign_id: 'cmp_slots', lead_id: 'lead_slots_c', business_id: bizId, idempotency_key: 'k', attempts: 0,
    } as any);
    expect(out).toMatchObject({ success: false, requeue: true, reason: 'concurrency_limit' });
    const calls = await env.DB.prepare("SELECT COUNT(*) AS n FROM calls WHERE lead_id = 'lead_slots_c'").first<any>();
    expect(calls.n).toBe(0);
  });
});
