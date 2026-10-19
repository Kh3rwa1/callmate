import { describe, it, expect, beforeAll, afterEach, vi } from 'vitest';
import { env } from 'cloudflare:test';
import { migrateTestDb } from './setup-db';
import app from '../src/index';
import { signJWT } from '../src/auth';

const jwtSecret = 'test-jwt-signing-secret-key-32chars-min-length';

/** A live (non-mock) Sarvam config with the AI + recording disclosure on; fetch is stubbed. */
const live = () => ({
  ...env, SARVAM_API_KEY: 'live-key', SARVAM_ORG_ID: 'o', SARVAM_WORKSPACE_ID: 'w', SARVAM_ADMISSIONS_APP_ID: 'a',
  SARVAM_DISCLOSURE_OVERRIDE: 'true',
}) as any;

async function owner(id: string, phone: string, ownerName: string | null) {
  await env.DB.batch([
    env.DB.prepare("INSERT OR REPLACE INTO businesses (id, name, owner_name) VALUES (?, 'Sen Tutorials', ?)").bind(id, ownerName),
    env.DB.prepare('INSERT OR REPLACE INTO users (id, phone, business_id) VALUES (?, ?, ?)').bind(`usr_${id}`, phone, id),
    env.DB.prepare(
      `INSERT OR REPLACE INTO agents (id, business_id, name, role, status, calling_hours_start, calling_hours_end, languages)
       VALUES (?, ?, 'Riya', 'Admissions', 'active', 10, 19, '["English"]')`
    ).bind(`agt_${id}`, id),
    env.DB.prepare("INSERT OR REPLACE INTO usage (id, business_id, included_minutes, minutes_used) VALUES (?, ?, 800, 0)").bind(`usg_${id}`, id),
  ]);
  return signJWT({ sub: `usr_${id}`, phone, business_id: id, type: 'access' }, jwtSecret, 3600);
}

async function greetingFor(token: string, phone: string): Promise<string> {
  let body: any = null;
  vi.spyOn(globalThis, 'fetch').mockImplementation(async (_u: any, init: any) => {
    body = JSON.parse(init.body);
    return new Response(JSON.stringify({ attempt_id: `att_${crypto.randomUUID()}` }), { status: 200 });
  });
  const res = await app.fetch(new Request('http://localhost/agent/test-call', {
    method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ phone }),
  }), live());
  expect(res.status).toBe(200);
  return body.app_config.app_overrides.initial_bot_message;
}

beforeAll(migrateTestDb);
afterEach(() => vi.restoreAllMocks());

describe("the owner's test call greeting", () => {
  it('does not call the owner "Owner" when their name is not on file', async () => {
    const token = await owner('biz_greet_noname', '919830011201', null);
    const greeting = await greetingFor(token, '9830011201');
    expect(greeting.startsWith("Hello, I'm calling from Sen Tutorials")).toBe(true);
    expect(greeting).not.toContain('Owner');
    expect(greeting).toContain('an AI assistant');
  });

  it("uses the owner's first name when it is on file", async () => {
    const token = await owner('biz_greet_named', '919830011202', 'Arjun Das');
    expect(await greetingFor(token, '9830011202')).toMatch(/^Hello Arjun, I'm calling from Sen Tutorials/);
  });
});
