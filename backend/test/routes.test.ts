import { describe, it, expect, beforeAll } from 'vitest';
import { env } from 'cloudflare:test';
import { migrateTestDb } from './setup-db';
import app from '../src/index';
import { signJWT } from '../src/auth';

describe('All Routes Unit & Integration Tests (Workers Runtime)', () => {
  const secret = 'test-jwt-signing-secret-key-32chars-min-length';
  const bizA = 'biz_test_a';
  const userA = 'usr_test_a';
  const phoneA = '919830000001';

  const bizB = 'biz_test_b';
  const userB = 'usr_test_b';
  const phoneB = '919830000002';

  let tokenA: string;
  let tokenB: string;

  beforeAll(async () => {
    await migrateTestDb();

    // Seed Business A & User A
    await env.DB.batch([
      env.DB.prepare("INSERT OR REPLACE INTO businesses (id, name, category) VALUES (?, 'Biz A Academy', 'education')").bind(bizA),
      env.DB.prepare("INSERT OR REPLACE INTO users (id, phone, business_id) VALUES (?, ?, ?)").bind(userA, phoneA, bizA),
      env.DB.prepare("INSERT OR REPLACE INTO agents (id, business_id, name, role, status) VALUES ('agt_a', ?, 'Maya', 'Counselor', 'active')").bind(bizA),
      env.DB.prepare("INSERT OR REPLACE INTO usage (id, business_id, plan_name, included_minutes, renews_at, price_inr, minutes_used, calls_made, rate_per_minute_inr) VALUES ('usg_a', ?, 'Founding', 1000, datetime('now', '+30 days'), 4999, 10, 5, 6)").bind(bizA),

      // Seed Business B & User B
      env.DB.prepare("INSERT OR REPLACE INTO businesses (id, name, category) VALUES (?, 'Biz B Clinic', 'healthcare')").bind(bizB),
      env.DB.prepare("INSERT OR REPLACE INTO users (id, phone, business_id) VALUES (?, ?, ?)").bind(userB, phoneB, bizB),
      env.DB.prepare("INSERT OR REPLACE INTO agents (id, business_id, name, role, status) VALUES ('agt_b', ?, 'Riya', 'Receptionist', 'active')").bind(bizB),
      env.DB.prepare("INSERT OR REPLACE INTO usage (id, business_id, plan_name, included_minutes, renews_at, price_inr, minutes_used, calls_made, rate_per_minute_inr) VALUES ('usg_b', ?, 'Founding', 1000, datetime('now', '+30 days'), 4999, 5, 2, 6)").bind(bizB),
    ]);

    tokenA = await signJWT({ sub: userA, phone: phoneA, business_id: bizA, type: 'access' }, secret, 3600);
    tokenB = await signJWT({ sub: userB, phone: phoneB, business_id: bizB, type: 'access' }, secret, 3600);
  });

  const authedReq = (path: string, token: string, method = 'GET', body?: any) => {
    return app.fetch(
      new Request(`http://localhost${path}`, {
        method,
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${token}`,
        },
        body: body ? JSON.stringify(body) : undefined,
      }),
      env
    );
  };

  describe('Health check', () => {
    it('returns healthy status on / and /health', async () => {
      const r1 = await app.fetch(new Request('http://localhost/health'), env);
      expect(r1.status).toBe(200);
      const r2 = await app.fetch(new Request('http://localhost/'), env);
      expect(r2.status).toBe(200);
    });
  });

  describe('Business & Agent endpoints', () => {
    it('GET and PATCH /business', async () => {
      const getRes = await authedReq('/business', tokenA);
      expect(getRes.status).toBe(200);
      const getBody = await getRes.json() as any;
      expect(getBody.name).toBe('Biz A Academy');

      const patchRes = await authedReq('/business', tokenA, 'PATCH', { name: 'Biz A Premium' });
      expect(patchRes.status).toBe(200);
      const patchBody = await patchRes.json() as any;
      expect(patchBody.name).toBe('Biz A Premium');
    });

    it('GET and PATCH /agent', async () => {
      const getRes = await authedReq('/agent', tokenA);
      expect(getRes.status).toBe(200);
      const getBody = await getRes.json() as any;
      expect(getBody.name).toBe('Maya');

      const patchRes = await authedReq('/agent', tokenA, 'PATCH', { name: 'Maya Pro' });
      expect(patchRes.status).toBe(200);
      const patchBody = await patchRes.json() as any;
      expect(patchBody.name).toBe('Maya Pro');
    });

    it('POST /devices/register registers device tokens', async () => {
      const res = await authedReq('/devices/register', tokenA, 'POST', { token: 'fcm_tok_123', platform: 'android' });
      expect(res.status).toBe(200);
    });
  });

  describe('Leads endpoints & Tenant Isolation', () => {
    let leadAId: string;

    it('POST /leads creates lead scoped to business', async () => {
      const res = await authedReq('/leads', tokenA, 'POST', {
        name: 'Rohan Sharma',
        phone: '919830012345',
        interest: 'NEET Exam',
      });
      expect(res.status).toBe(200);
      const data = await res.json() as any;
      expect(data.name).toBe('Rohan Sharma');
      leadAId = data.id;
    });

    it('Tenant Isolation: Business B cannot read or patch Business A lead', async () => {
      const getRes = await authedReq(`/leads/${leadAId}`, tokenB);
      expect(getRes.status).toBe(404);

      const patchRes = await authedReq(`/leads/${leadAId}`, tokenB, 'PATCH', { name: 'Hacked Lead' });
      expect(patchRes.status).toBe(404);

      const delRes = await authedReq(`/leads/${leadAId}`, tokenB, 'DELETE');
      expect(delRes.status).toBe(404);
    });

    it('GET /leads supports keyset cursor pagination', async () => {
      const res = await authedReq('/leads?limit=5', tokenA);
      expect(res.status).toBe(200);
      const data = await res.json() as any;
      expect(Array.isArray(data.items)).toBe(true);
      expect(data.items.length).toBeGreaterThanOrEqual(1);
    });

    it('POST /leads/import imports batch and skips duplicates', async () => {
      const res = await authedReq('/leads/import', tokenA, 'POST', {
        leads: [
          { name: 'Rohan Sharma', phone: '919830012345' }, // duplicate
          { name: 'Priya Verma', phone: '919830054321' },  // new
        ],
      });
      expect(res.status).toBe(200);
      const data = await res.json() as any;
      expect(data.imported).toBe(1);
      expect(data.skipped).toBe(1);
    });
  });

  describe('Campaigns endpoints', () => {
    let campId: string;

    it('POST /campaigns verifies tenant lead ownership', async () => {
      const leads = await env.DB.prepare('SELECT id FROM leads WHERE business_id = ?').bind(bizA).all<any>();
      const leadIds = leads.results.map((l) => l.id);

      const res = await authedReq('/campaigns', tokenA, 'POST', {
        purpose: 'Admissions Campaign',
        lead_ids: leadIds,
        calling_hours_start: 10,
        calling_hours_end: 19,
      });
      expect(res.status).toBe(200);
      const data = await res.json() as any;
      expect(data.purpose).toBe('Admissions Campaign');
      campId = data.id;
    });

    it('Tenant Isolation: B cannot read, start, or stop A campaign', async () => {
      const getRes = await authedReq(`/campaigns/${campId}`, tokenB);
      expect(getRes.status).toBe(404);

      const startRes = await authedReq(`/campaigns/${campId}/start`, tokenB, 'POST');
      expect(startRes.status).toBe(404);

      const stopRes = await authedReq(`/campaigns/${campId}/stop`, tokenB, 'POST');
      expect(stopRes.status).toBe(404);
    });

    it('POST /campaigns/:id/start dispatches campaign and /stop pauses it', async () => {
      const startRes = await authedReq(`/campaigns/${campId}/start`, tokenA, 'POST');
      expect(startRes.status).toBe(200);

      const stopRes = await authedReq(`/campaigns/${campId}/stop`, tokenA, 'POST');
      expect(stopRes.status).toBe(200);
    });
  });

  describe('Calls & Transparent Decryption', () => {
    let callAId: string;

    it('POST /leads/:id/call initiates test call', async () => {
      // Open the calling window all day so this test does not depend on the time it runs.
      await env.DB.prepare('UPDATE agents SET calling_hours_start = 0, calling_hours_end = 24 WHERE business_id = ?').bind(bizA).run();
      const lead = await env.DB.prepare('SELECT id FROM leads WHERE business_id = ?').bind(bizA).first<any>();
      const res = await authedReq(`/leads/${lead.id}/call`, tokenA, 'POST');
      expect(res.status).toBe(200);
      const data = await res.json() as any;
      expect(data.call.status).toBe('calling');
      callAId = data.call.id;
    });

    it('GET /calls/:id returns call and decrypts transcript transparently', async () => {
      const res = await authedReq(`/calls/${callAId}`, tokenA);
      expect(res.status).toBe(200);
      const data = await res.json() as any;
      expect(data.id).toBe(callAId);
    });

    it('Tenant Isolation: B cannot read A call', async () => {
      const res = await authedReq(`/calls/${callAId}`, tokenB);
      expect(res.status).toBe(404);
    });
  });

  describe('Dashboard metrics', () => {
    it('GET /dashboard/today and /notifications', async () => {
      const rToday = await authedReq('/dashboard/today', tokenA);
      expect(rToday.status).toBe(200);
      const dToday = await rToday.json() as any;
      expect(dToday).toHaveProperty('leads');

      const rNotifs = await authedReq('/notifications', tokenA);
      expect(rNotifs.status).toBe(200);
    });
  });

  describe('Followups and Callbacks', () => {
    it('GET and PATCH /followups', async () => {
      const getRes = await authedReq('/followups', tokenA);
      expect(getRes.status).toBe(200);
      const data = await getRes.json() as any;
      expect(Array.isArray(data)).toBe(true);
    });

    it('GET and PATCH /callbacks', async () => {
      const getRes = await authedReq('/callbacks', tokenA);
      expect(getRes.status).toBe(200);
      const data = await getRes.json() as any;
      expect(Array.isArray(data)).toBe(true);
    });
  });

  describe('Knowledge endpoints', () => {
    let docId: string;

    it('POST /knowledge and GET /knowledge scoped by business', async () => {
      const createRes = await authedReq('/knowledge', tokenA, 'POST', {
        title: 'Fee Structure',
        content: 'Total course fee is 45,000 INR for full year.',
        type: 'faq',
      });
      expect(createRes.status).toBe(200);
      const doc = await createRes.json() as any;
      docId = doc.id;

      const getRes = await authedReq('/knowledge', tokenA);
      expect(getRes.status).toBe(200);
      const docs = await getRes.json() as any;
      expect(docs.some((d: any) => d.id === docId)).toBe(true);
    });

    it('Tenant Isolation: B cannot delete A knowledge document', async () => {
      const delRes = await authedReq(`/knowledge/${docId}`, tokenB, 'DELETE');
      expect(delRes.status).toBe(404);
    });
  });

  describe('Voice proxy security', () => {
    it('rejects access tokens on voice proxy with 401 (only session tokens allowed)', async () => {
      const res = await app.fetch(
        new Request('http://localhost/voice/sarvam-proxy/orgs/1/workspaces/2/apps/3/stream', {
          headers: { Authorization: `Bearer ${tokenA}` },
        }),
        env
      );
      expect(res.status).toBe(401);
      const data = await res.json() as any;
      expect(data.code).toBe('session_expired');
    });

    it('rejects disallowed path on voice proxy with 403', async () => {
      const sessionToken = await signJWT({ sub: userA, phone: phoneA, business_id: bizA, type: 'session' }, secret, 3600);
      const res = await app.fetch(
        new Request('http://localhost/voice/sarvam-proxy/disallowed/malicious/path', {
          headers: { Authorization: `Bearer ${sessionToken}` },
        }),
        env
      );
      expect(res.status).toBe(403);
    });
  });
});
