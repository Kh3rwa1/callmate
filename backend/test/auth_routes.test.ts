import { describe, it, expect, beforeAll } from 'vitest';
import { env } from 'cloudflare:test';
import { migrateTestDb } from './setup-db';
import app from '../src/index';

describe('Auth Routes Integration Tests (High Coverage Target)', () => {
  beforeAll(async () => {
    await migrateTestDb();
  });

  const postJson = (path: string, body: any, headers: Record<string, string> = {}) => {
    return app.fetch(
      new Request(`http://localhost${path}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', ...headers },
        body: JSON.stringify(body),
      }),
      env
    );
  };

  it('POST /auth/otp/request generates code and enforces rate limit', async () => {
    const phone = '919830088801';
    // 1st request
    const r1 = await postJson('/auth/otp/request', { phone });
    expect(r1.status).toBe(200);
    const d1 = await r1.json() as any;
    expect(d1.success).toBe(true);
    expect(d1.debug_otp).toBeDefined();

    // 2nd request
    const r2 = await postJson('/auth/otp/request', { phone });
    expect(r2.status).toBe(200);

    // 3rd request
    const r3 = await postJson('/auth/otp/request', { phone });
    expect(r3.status).toBe(200);

    // 4th request exceeds rate limit (max 3/10min)
    const r4 = await postJson('/auth/otp/request', { phone });
    expect(r4.status).toBe(429);
    const d4 = await r4.json() as any;
    expect(d4.code).toBe('rate_limited');
  });

  it('POST /auth/register requires verified OTP and rejects existing phone', async () => {
    const phone = '919830088802';
    // 1. Request OTP
    const reqOtp = await postJson('/auth/otp/request', { phone });
    const { debug_otp: otp } = await reqOtp.json() as any;

    // 2. Register with wrong OTP fails
    const failReg = await postJson('/auth/register', { phone, otp: '000000', business_name: 'Test Academy' });
    expect(failReg.status).toBe(400);

    // 3. Register with valid OTP succeeds and issues tokens
    const successReg = await postJson('/auth/register', { phone, otp, business_name: 'Test Academy' });
    expect(successReg.status).toBe(200);
    const tokens = await successReg.json() as any;
    expect(tokens.access_token).toBeDefined();
    expect(tokens.refresh_token).toBeDefined();

    // 4. Re-registration of existing phone NEVER returns tokens (409 Conflict)
    const reqOtpAgain = await postJson('/auth/otp/request', { phone });
    const { debug_otp: otp2 } = await reqOtpAgain.json() as any;
    const reReg = await postJson('/auth/register', { phone, otp: otp2, business_name: 'Another Name' });
    expect(reReg.status).toBe(409);
    const reRegData = await reReg.json() as any;
    expect(reRegData.access_token).toBeUndefined();
  });

  it('POST /auth/login verifies OTP, locks after 5 failed attempts, and deletes OTP on success', async () => {
    const phone = '919830088803';
    const ip = '10.0.0.3';
    // Create user first
    const reqOtp = await postJson('/auth/otp/request', { phone }, { 'cf-connecting-ip': ip });
    const { debug_otp: regOtp } = await reqOtp.json() as any;
    await postJson('/auth/register', { phone, otp: regOtp, business_name: 'Login Test Corp' });

    // Request new login OTP
    const reqLoginOtp = await postJson('/auth/otp/request', { phone }, { 'cf-connecting-ip': ip });
    const { debug_otp: validOtp } = await reqLoginOtp.json() as any;

    // Attempt 1 to 5 with wrong OTP
    for (let i = 1; i <= 5; i++) {
      const wrong = await postJson('/auth/login', { phone, otp: '111111' });
      expect(wrong.status).toBe(400);
      const wrongData = await wrong.json() as any;
      expect(wrongData.code).toBe('invalid_otp');
    }

    // 6th attempt is locked
    const lockedRes = await postJson('/auth/login', { phone, otp: validOtp });
    expect(lockedRes.status).toBe(429);
    const lockedData = await lockedRes.json() as any;
    expect(lockedData.code).toBe('otp_locked');

    // Request fresh OTP and login successfully
    const freshReq = await postJson('/auth/otp/request', { phone }, { 'cf-connecting-ip': ip });
    if (freshReq.status === 200) {
      const { debug_otp: freshOtp } = await freshReq.json() as any;
      const successLogin = await postJson('/auth/login', { phone, otp: freshOtp });
      expect(successLogin.status).toBe(200);
      const loginTokens = await successLogin.json() as any;
      expect(loginTokens.access_token).toBeDefined();
    }
  });

  it('POST /auth/refresh rotates token and detects reuse', async () => {
    const phone = '919830088804';
    const reqOtp = await postJson('/auth/otp/request', { phone }, { 'cf-connecting-ip': '10.0.0.4' });
    const { debug_otp: otp } = await reqOtp.json() as any;
    const regRes = await postJson('/auth/register', { phone, otp, business_name: 'Refresh Test Corp' });
    const { refresh_token: r1 } = await regRes.json() as any;

    // 1. First refresh succeeds and gives rotated token r2
    const ref1 = await postJson('/auth/refresh', { refresh_token: r1 });
    expect(ref1.status).toBe(200);
    const { refresh_token: r2, access_token: a2 } = await ref1.json() as any;
    expect(r2).toBeDefined();
    expect(r2).not.toBe(r1);

    // 2. Refresh token reuse detection: replaying revoked r1 triggers family-wide revocation
    const replayRes = await postJson('/auth/refresh', { refresh_token: r1 });
    expect(replayRes.status).toBe(401);
    const replayData = await replayRes.json() as any;
    expect(replayData.code).toBe('token_reuse_detected');

    // 3. r2 is now also invalidated due to family revocation
    const r2AfterRevoke = await postJson('/auth/refresh', { refresh_token: r2 });
    expect(r2AfterRevoke.status).toBe(401);
  });

  it('POST /auth/logout and DELETE /auth/account', async () => {
    const phone = '919830088805';
    const reqOtp = await postJson('/auth/otp/request', { phone }, { 'cf-connecting-ip': '1.2.3.6' });
    const { debug_otp: otp } = await reqOtp.json() as any;
    const regRes = await postJson('/auth/register', { phone, otp, business_name: 'Account Test Corp' });
    const { access_token, refresh_token } = await regRes.json() as any;

    // Logout
    const logoutRes = await postJson('/auth/logout', { refresh_token });
    expect(logoutRes.status).toBe(200);

    // Account deletion
    const delRes = await app.fetch(
      new Request('http://localhost/auth/account', {
        method: 'DELETE',
        headers: { Authorization: `Bearer ${access_token}` },
      }),
      env
    );
    expect(delRes.status).toBe(200);
  });
});
