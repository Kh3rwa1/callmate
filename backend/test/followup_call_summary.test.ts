import { describe, it, expect, beforeAll } from 'vitest';
import { env } from 'cloudflare:test';
import { migrateTestDb } from './setup-db';
import worker from '../src/index';
import { signJWT } from '../src/auth';

const jwtSecret = 'test-jwt-signing-secret-key-32chars-min-length';
const bizId = 'biz_fusum';
let token: string;

const get = (path: string) => worker.fetch(new Request(`http://localhost${path}`, {
  headers: { Authorization: `Bearer ${token}` },
}), env);

beforeAll(async () => {
  await migrateTestDb();
  await env.DB.batch([
    env.DB.prepare("INSERT OR REPLACE INTO businesses (id, name) VALUES (?, 'Roy Classes')").bind(bizId),
    env.DB.prepare("INSERT OR REPLACE INTO users (id, phone, business_id) VALUES ('usr_fusum', '919830066666', ?)").bind(bizId),
    env.DB.prepare("INSERT OR REPLACE INTO leads (id, business_id, name, phone, status) VALUES ('lead_fusum', ?, 'Laboni Roy', '919830066661', 'called')").bind(bizId),
    env.DB.prepare(
      `INSERT OR REPLACE INTO calls (id, business_id, lead_id, lead_name, lead_phone, status, score, temperature, summary, started_at)
       VALUES ('call_fusum', ?, 'lead_fusum', 'Laboni Roy', '919830066661', 'completed', 84, 'hot',
               'Laboni wants the JEE Advanced evening batch and asked about fees.', datetime('now'))`
    ).bind(bizId),
    env.DB.prepare(
      `INSERT OR REPLACE INTO followups (id, business_id, lead_id, call_id, message, status, created_at)
       VALUES ('fu_fusum', ?, 'lead_fusum', 'call_fusum', 'Hi Laboni, here are the details.', 'ready', datetime('now'))`
    ).bind(bizId),
    env.DB.prepare(
      `INSERT OR REPLACE INTO followups (id, business_id, lead_id, call_id, message, status, created_at)
       VALUES ('fu_fusum_nocall', ?, 'lead_fusum', NULL, 'Hi Laboni!', 'ready', datetime('now', '-1 minute'))`
    ).bind(bizId),
  ]);
  token = await signJWT({ sub: 'usr_fusum', phone: '919830066666', business_id: bizId, type: 'access' }, jwtSecret, 3600);
});

describe('follow-ups carry the summary and score of their call', () => {
  it('in the list and the single follow-up', async () => {
    const list = (await (await get('/followups?status=ready')).json()) as any;
    const items = Array.isArray(list) ? list : list.items;
    const withCall = items.find((f: any) => f.id === 'fu_fusum');
    expect(withCall).toMatchObject({
      call_summary: 'Laboni wants the JEE Advanced evening batch and asked about fees.',
      score_value: 84,
      lead_name: 'Laboni Roy',
    });
    expect(items.find((f: any) => f.id === 'fu_fusum_nocall')).toMatchObject({ call_summary: null, score_value: null });

    const one = (await (await get('/followups/fu_fusum')).json()) as any;
    expect(one.call_summary).toBe(withCall.call_summary);
  });
});
