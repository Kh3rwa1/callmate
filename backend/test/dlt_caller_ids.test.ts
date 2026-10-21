import { describe, it, expect, beforeAll, afterEach, vi } from 'vitest';
import { env } from 'cloudflare:test';
import { migrateTestDb } from './setup-db';
import app from '../src/index';
import { callerIdsAreDltSeries, poolCallerIds } from '../src/services/compliance';
import { runComplianceCron } from '../src/services/retention';

const OPS_KEY = 'ops-key-for-dlt-tests-0123456789';

const OPS1 = '+917971460011';
const OPS2 = '+917971460013';
const OPS3 = '+917971460020';
const SHARED = '+917971442975';
const CONFIG = '+917971460001';

async function sha256(text: string): Promise<string> {
  const d = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
  return [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

let AGENTS = '';
let OPS_HASH = '';

/** Production-like: one config number, two pool agents, the ops page on. */
const live = (extra: Record<string, unknown> = {}) => ({
  ...env,
  SARVAM_API_KEY: 'live-key', SARVAM_ORG_ID: 'org', SARVAM_WORKSPACE_ID: 'ws', SARVAM_CONNECTION_ID: 'conn',
  SARVAM_INBOUND_APP_ID: '', SARVAM_AGENT_PHONE_NUMBERS: SHARED,
  SARVAM_BUSINESS_NUMBERS: `${CONFIG}=Config-Agent:1`,
  SARVAM_RECEPTIONIST_AGENTS: AGENTS,
  OPS_KEY_SHA256: OPS_HASH,
  PUBLIC_API_BASE_URL: 'https://api.example',
  ...extra,
}) as any;

const ops = (fields: Record<string, string>, e = live()) => app.fetch(new Request('http://localhost/ops/numbers', {
  method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'cf-connecting-ip': '203.0.113.20' },
  body: new URLSearchParams(fields).toString(),
}), e);
const row = (phone: string) => env.DB.prepare('SELECT business_id, status, source, agent_app_id FROM business_numbers WHERE phone = ?')
  .bind(phone).first<{ business_id: string | null; status: string; source: string; agent_app_id: string | null }>();

beforeAll(async () => {
  await migrateTestDb();
  AGENTS = [`Pool-A:1:${await sha256('tok-a')}`, `Pool-B:1:${await sha256('tok-b')}`].join(',');
  OPS_HASH = await sha256(OPS_KEY);
  await env.DB.batch([
    env.DB.prepare("INSERT INTO business_numbers (phone, status) VALUES (?, 'free')").bind(CONFIG),
    ...[OPS1, OPS2, OPS3].map((p) => env.DB.prepare("INSERT INTO business_numbers (phone, status, source) VALUES (?, 'free', 'ops')").bind(p)),
  ]);
});

afterEach(() => vi.restoreAllMocks());

describe('TRAI 140/160-series caller IDs', () => {
  const dltOnly = { SARVAM_AGENT_PHONE_NUMBERS: '+911601234567', SARVAM_BUSINESS_NUMBERS: '' };

  it('numbers stored in D1 count in the DLT check, /health/deep and the production warning', async () => {
    expect(callerIdsAreDltSeries(dltOnly)).toBe(true);
    const pool = await poolCallerIds(env.DB);
    expect(pool.sort()).toEqual([OPS1, OPS2, OPS3].sort()); // ops rows, not the config one
    expect(callerIdsAreDltSeries(dltOnly, pool)).toBe(false);
    expect(callerIdsAreDltSeries(dltOnly, ['+911401234567'])).toBe(true);

    const deep = await app.fetch(new Request('http://localhost/health/deep', { headers: { 'x-health-key': 'hk' } }),
      live({ ...dltOnly, HEALTH_CHECK_SECRET: 'hk', SARVAM_ADMISSIONS_APP_ID: 'a' }));
    expect(((await deep.json()) as any).compliance.caller_ids_dlt_series).toBe(false);

    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
    await runComplianceCron(live({ ...dltOnly, ENVIRONMENT: 'production' }));
    const line = warn.mock.calls.map((c) => String(c[0])).find((l) => l.includes('caller_ids_not_dlt_series'))!;
    expect(JSON.parse(line).business_numbers_not_dlt).toBe(3);
  });

  it('the ops page adds a number outside the series with a warning, or refuses it with REQUIRE_DLT_CALLER_IDS', async () => {
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
    vi.spyOn(console, 'log').mockImplementation(() => {});
    const added = await ops({ key: OPS_KEY, action: 'add', number: '+917971460040' });
    expect(added.status).toBe(200);
    const html = await added.text();
    expect(html).toContain('Added +91 79714 60040.');
    expect(html).toContain('it is not a TRAI 140/160-series number');
    expect(html).toContain('Not TRAI 140/160-series: 5');
    expect(warn.mock.calls.some((c) => String(c[0]).includes('business_number_not_dlt_series'))).toBe(true);

    const strict = live({ REQUIRE_DLT_CALLER_IDS: 'true' });
    const refused = await ops({ key: OPS_KEY, action: 'add', number: '+917971460041' }, strict);
    expect(refused.status).toBe(400);
    expect(await refused.text()).toContain('Only TRAI 140/160-series numbers can be added');
    expect(await row('+917971460041')).toBeNull();
    const ok = await ops({ key: OPS_KEY, action: 'add', number: '+911401234567' }, strict);
    expect(ok.status).toBe(200);
    const okHtml = await ok.text();
    expect(okHtml).toContain('Added +91 14012 34567.');
    expect(okHtml).not.toContain('it is not a TRAI');
    expect(okHtml).toContain('(REQUIRE_DLT_CALLER_IDS: no more can be added)');
  });
});
