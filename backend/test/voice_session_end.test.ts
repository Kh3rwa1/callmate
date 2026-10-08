import { describe, it, expect, beforeAll } from 'vitest';
import { env } from 'cloudflare:test';
import { migrateTestDb } from './setup-db';
import app from '../src/index';
import { signJWT } from '../src/auth';

describe('voice test-session lifecycle', () => {
  const secret = 'test-jwt-signing-secret-key-32chars-min-length';
  const otpPepper = 'test-otp-pepper-secret-32chars-min-length';
  const bizId = 'biz_vs_end';
  const userId = 'usr_vs_end';
  const phone = '919876543299';
  let token: string;

  const call = (path: string, auth = token, extraEnv: Record<string, string> = {}) =>
    app.fetch(
      new Request(`http://localhost${path}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${auth}` },
      }),
      { ...env, JWT_SIGNING_KEY: secret, OTP_PEPPER: otpPepper, ...extraEnv },
    );

  beforeAll(async () => {
    await migrateTestDb();
    await env.DB.batch([
      env.DB.prepare("INSERT OR REPLACE INTO businesses (id, name, category) VALUES (?, 'End Test Academy', 'coaching')").bind(bizId),
      env.DB.prepare('INSERT OR REPLACE INTO users (id, phone, business_id) VALUES (?, ?, ?)').bind(userId, phone, bizId),
    ]);
    token = await signJWT({ sub: userId, phone, business_id: bizId, type: 'access' }, secret, 3600);
  });

  it('ending sessions frees the concurrent-session cap', async () => {
    // Fill the cap of 5, ending each one: a sixth must still be allowed.
    for (let i = 0; i < 6; i++) {
      const res = await call('/voice/test-session');
      expect(res.status).toBe(200);
      const { session_id } = (await res.json()) as any;
      expect(session_id).toMatch(/^vsess_/);
      expect((await call(`/voice/test-session/${session_id}/end`)).status).toBe(200);
    }
    const row = await env.DB.prepare(
      "SELECT COUNT(*) AS cnt FROM voice_sessions WHERE business_id = ? AND status = 'active'",
    ).bind(bizId).first<{ cnt: number }>();
    expect(row?.cnt).toBe(0);
  });

  it("cannot end another business's session", async () => {
    await env.DB.batch([
      env.DB.prepare("INSERT OR REPLACE INTO businesses (id, name, category) VALUES ('biz_vs_other', 'Other', 'coaching')"),
      env.DB.prepare("INSERT OR REPLACE INTO users (id, phone, business_id) VALUES ('usr_vs_other', '919876543298', 'biz_vs_other')"),
      env.DB.prepare(
        "INSERT INTO voice_sessions (id, business_id, user_id, status, started_at) VALUES ('vsess_other', 'biz_vs_other', 'usr_vs_other', 'active', datetime('now'))",
      ),
    ]);
    expect((await call('/voice/test-session/vsess_other/end')).status).toBe(200);
    const row = await env.DB.prepare("SELECT status FROM voice_sessions WHERE id = 'vsess_other'").first<{ status: string }>();
    expect(row?.status).toBe('active');
  });

  describe('VOICE_UNLIMITED_EMAILS', () => {
    const qaBiz = 'biz_vs_qa';
    const qaUser = 'usr_vs_qa';
    let qaToken: string;

    beforeAll(async () => {
      await env.DB.batch([
        env.DB.prepare("INSERT OR REPLACE INTO businesses (id, name, category) VALUES (?, 'QA', 'coaching')").bind(qaBiz),
        env.DB.prepare("INSERT OR REPLACE INTO users (id, phone, business_id, email) VALUES (?, '919876543297', ?, 'QA.Tester@Example.com')").bind(qaUser, qaBiz),
      ]);
      qaToken = await signJWT({ sub: qaUser, phone: '919876543297', business_id: qaBiz, type: 'access' }, secret, 3600);
    });

    it('enforces the cap of 5 for accounts not on the list', async () => {
      const others = { VOICE_UNLIMITED_EMAILS: 'someone@else.com' };
      for (let i = 0; i < 5; i++) expect((await call('/voice/test-session', qaToken, others)).status).toBe(200);
      expect((await call('/voice/test-session', qaToken, others)).status).toBe(429);
    });

    it('lets a listed email (case-insensitive) past the cap', async () => {
      const listed = { VOICE_UNLIMITED_EMAILS: 'a@b.com, qa.tester@example.com' };
      for (let i = 0; i < 3; i++) expect((await call('/voice/test-session', qaToken, listed)).status).toBe(200);
    });
  });
});
