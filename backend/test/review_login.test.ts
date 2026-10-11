import { describe, it, expect, beforeAll } from 'vitest';
import { env } from 'cloudflare:test';
import { migrateTestDb } from './setup-db';
import app from '../src/index';
import { reviewLoginCode } from '../src/routes/auth';

describe('Play review demo login', () => {
  beforeAll(async () => {
    await migrateTestDb();
  });

  // Production-like env: no debug_otp, and an SMS provider that must never be called.
  const reviewEnv = {
    ...env,
    ENVIRONMENT: 'production',
    REVIEW_LOGIN_PHONE: '+91 99999 00001',
    REVIEW_LOGIN_OTP: '424242',
  } as any;

  const postJson = (path: string, body: any) =>
    app.fetch(
      new Request(`http://localhost${path}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      }),
      reviewEnv
    );

  it('matches only the configured phone, and only with a 6-digit code', () => {
    expect(reviewLoginCode(reviewEnv, '919999900001')).toBe('424242');
    expect(reviewLoginCode(reviewEnv, '919999900002')).toBeNull();
    expect(reviewLoginCode({ ...reviewEnv, REVIEW_LOGIN_OTP: '1234' }, '919999900001')).toBeNull();
    expect(reviewLoginCode({ ...reviewEnv, REVIEW_LOGIN_OTP: undefined }, '919999900001')).toBeNull();
  });

  it('registers and signs in with the fixed code, without SMS', async () => {
    const phone = '9999900001';
    const req = await postJson('/auth/otp/request', { phone });
    expect(req.status).toBe(200);
    expect(((await req.json()) as any).debug_otp).toBeUndefined();

    const wrong = await postJson('/auth/register', { phone, otp: '111111', business_name: 'Review Co' });
    expect(wrong.status).toBe(400);

    const reg = await postJson('/auth/register', { phone, otp: '424242', business_name: 'Review Co' });
    expect(reg.status).toBe(200);
    expect(((await reg.json()) as any).access_token).toBeDefined();

    await postJson('/auth/otp/request', { phone });
    const login = await postJson('/auth/login', { phone, otp: '424242' });
    expect(login.status).toBe(200);
  });
});
