import { describe, it, expect, vi } from 'vitest';
import { signJWT, verifyJWT, getJwtSecret, authMiddleware } from '../src/auth';

const dbStub = (row: any) => ({
  prepare: () => ({ bind: () => ({ first: async () => row }) }),
});

describe('Auth Unit Tests (100% Coverage Target)', () => {
  const secret = 'test-jwt-signing-secret-key-32chars-min-length';

  it('signs and verifies access tokens with correct claims', async () => {
    const payload = { sub: 'usr_1', phone: '919830012345', business_id: 'biz_1', type: 'access' as const };
    const token = await signJWT(payload, secret, 3600);
    expect(typeof token).toBe('string');

    const verified = await verifyJWT(token, secret, 'access');
    expect(verified).not.toBeNull();
    expect(verified?.sub).toBe('usr_1');
    expect(verified?.iss).toBe('callpilot');
    expect(verified?.aud).toBe('callpilot-app');
    expect(verified?.type).toBe('access');
  });

  it('rejects access token when refresh token is expected', async () => {
    const payload = { sub: 'usr_1', phone: '919830012345', business_id: 'biz_1', type: 'access' as const };
    const token = await signJWT(payload, secret, 3600);

    const verified = await verifyJWT(token, secret, 'refresh');
    expect(verified).toBeNull();
  });

  it('rejects tampered token', async () => {
    const payload = { sub: 'usr_1', phone: '919830012345', business_id: 'biz_1', type: 'access' as const };
    const token = await signJWT(payload, secret, 3600);
    const tampered = token.slice(0, -5) + 'abcde';

    const verified = await verifyJWT(tampered, secret);
    expect(verified).toBeNull();
  });

  it('rejects token with invalid structure or parts', async () => {
    expect(await verifyJWT('not-a-valid-jwt', secret)).toBeNull();
    expect(await verifyJWT('part1.part2', secret)).toBeNull();
    expect(await verifyJWT('part1.part2.part3.part4', secret)).toBeNull();
  });

  it('rejects expired token', async () => {
    const payload = { sub: 'usr_1', phone: '919830012345', business_id: 'biz_1', type: 'access' as const };
    const token = await signJWT(payload, secret, -10); // expired 10 seconds ago
    expect(await verifyJWT(token, secret)).toBeNull();
  });

  it('rejects token with invalid algorithm or issuer/audience', async () => {
    // Manually forge invalid alg
    const invalidHeader = btoa(JSON.stringify({ alg: 'none', typ: 'JWT' }));
    const invalidPayload = btoa(JSON.stringify({ iss: 'fake', aud: 'fake', exp: Math.floor(Date.now() / 1000) + 100 }));
    expect(await verifyJWT(`${invalidHeader}.${invalidPayload}.fake_sig`, secret)).toBeNull();
  });

  it('getJwtSecret throws if secret is missing or under 32 chars', () => {
    expect(() => getJwtSecret({ env: {} } as any)).toThrow('JWT_SIGNING_KEY is missing');
    expect(() => getJwtSecret({ env: { JWT_SIGNING_KEY: 'short' } } as any)).toThrow('shorter than 32 characters');
    expect(getJwtSecret({ env: { JWT_SIGNING_KEY: secret } } as any)).toBe(secret);
  });

  it('authMiddleware rejects missing or invalid authorization header', async () => {
    let status = 0;
    let jsonBody: any = null;
    const cMissing: any = {
      req: { header: () => undefined },
      json: (data: any, s: number) => { jsonBody = data; status = s; return data; },
    };
    await authMiddleware(cMissing, async () => {});
    expect(status).toBe(401);
    expect(jsonBody.code).toBe('unauthorized');

    const cBasic: any = {
      req: { header: () => 'Basic 12345' },
      json: (data: any, s: number) => { jsonBody = data; status = s; return data; },
    };
    await authMiddleware(cBasic, async () => {});
    expect(status).toBe(401);
  });

  it('authMiddleware rejects invalid or expired token', async () => {
    let status = 0;
    let jsonBody: any = null;
    const cInvalid: any = {
      req: { header: () => 'Bearer invalid.jwt.token' },
      env: { JWT_SIGNING_KEY: secret },
      json: (data: any, s: number) => { jsonBody = data; status = s; return data; },
    };
    await authMiddleware(cInvalid, async () => {});
    expect(status).toBe(401);
    expect(jsonBody.code).toBe('token_expired');
  });

  it('authMiddleware passes and sets context user for valid access token', async () => {
    const payload = { sub: 'usr_1', phone: '919830012345', business_id: 'biz_1', type: 'access' as const };
    const token = await signJWT(payload, secret, 3600);

    const store: Record<string, any> = {};
    let nextCalled = false;
    const cValid: any = {
      req: { header: () => `Bearer ${token}` },
      env: { JWT_SIGNING_KEY: secret, DB: dbStub({ ok: 1 }) },
      set: (k: string, v: any) => { store[k] = v; },
    };
    await authMiddleware(cValid, async () => { nextCalled = true; });

    expect(nextCalled).toBe(true);
    expect(store.user).toEqual({ id: 'usr_1', phone: '919830012345', business_id: 'biz_1' });
  });

  it('authMiddleware rejects a valid token whose user account was deleted', async () => {
    const token = await signJWT({ sub: 'usr_gone', phone: '919830012345', business_id: 'biz_1', type: 'access' }, secret, 3600);
    let status = 0;
    let jsonBody: any = null;
    let nextCalled = false;
    const cGone: any = {
      req: { header: () => `Bearer ${token}` },
      env: { JWT_SIGNING_KEY: secret, DB: dbStub(null) },
      json: (data: any, s: number) => { jsonBody = data; status = s; return data; },
    };
    await authMiddleware(cGone, async () => { nextCalled = true; });
    expect(nextCalled).toBe(false);
    expect(status).toBe(401);
    expect(jsonBody.code).toBe('account_not_found');
  });

  it('rejects signed token when iss or aud is invalid', async () => {
    // Generate valid signature but invalid iss
    const enc = new TextEncoder();
    const key = await crypto.subtle.importKey(
      'raw',
      enc.encode(secret),
      { name: 'HMAC', hash: 'SHA-256' },
      false,
      ['sign']
    );
    const headerPart = btoa(JSON.stringify({ alg: 'HS256', typ: 'JWT' })).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
    const payloadPart = btoa(JSON.stringify({
      sub: 'usr_1',
      phone: '919830012345',
      business_id: 'biz_1',
      type: 'access',
      iss: 'wrong-issuer',
      aud: 'callpilot-app',
      exp: Math.floor(Date.now() / 1000) + 3600,
    })).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
    const dataToSign = enc.encode(`${headerPart}.${payloadPart}`);
    const sig = await crypto.subtle.sign('HMAC', key, dataToSign);
    const sigPart = btoa(String.fromCharCode(...new Uint8Array(sig))).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');

    const token = `${headerPart}.${payloadPart}.${sigPart}`;
    const verified = await verifyJWT(token, secret);
    expect(verified).toBeNull();
  });
});
