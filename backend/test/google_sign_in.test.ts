import { describe, it, expect, beforeAll, afterEach, vi } from 'vitest';
import { env } from 'cloudflare:test';
import { migrateTestDb } from './setup-db';
import app from '../src/index';
import { resetFirebaseKeyCache } from '../src/services/firebase_auth';

const PROJECT = 'callpilot-test-project';
const KID = 'test-kid-1';

let privateKey: CryptoKey;
let publicJwk: JsonWebKey;
let otherPrivateKey: CryptoKey;

function b64url(data: Uint8Array | string): string {
  const bytes = typeof data === 'string' ? new TextEncoder().encode(data) : data;
  let bin = '';
  bytes.forEach((b) => (bin += String.fromCharCode(b)));
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

async function idToken(claims: Record<string, unknown>, opts: { key?: CryptoKey; kid?: string } = {}): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: 'RS256', kid: opts.kid ?? KID, typ: 'JWT' }));
  const payload = b64url(JSON.stringify({
    aud: PROJECT, iss: `https://securetoken.google.com/${PROJECT}`, sub: 'uid_alice',
    iat: now, exp: now + 3600, auth_time: now, email: 'alice@example.com', email_verified: true,
    firebase: { sign_in_provider: 'google.com' }, ...claims,
  }));
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', opts.key ?? privateKey, new TextEncoder().encode(`${header}.${payload}`));
  return `${header}.${payload}.${b64url(new Uint8Array(sig))}`;
}

const testEnv = () => ({ ...env, FIREBASE_PROJECT_ID: PROJECT }) as any;

function post(body: unknown, e = testEnv()) {
  return app.fetch(new Request('http://localhost/auth/google', {
    method: 'POST', headers: { 'Content-Type': 'application/json', 'CF-Connecting-IP': '203.0.113.9' }, body: JSON.stringify(body),
  }), e);
}

describe('POST /auth/google (Firebase ID token sign-in)', () => {
  beforeAll(async () => {
    await migrateTestDb();
    const pair = await crypto.subtle.generateKey(
      { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' }, true, ['sign', 'verify']
    ) as CryptoKeyPair;
    privateKey = pair.privateKey;
    publicJwk = await crypto.subtle.exportKey('jwk', pair.publicKey) as JsonWebKey;
    const other = await crypto.subtle.generateKey(
      { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' }, true, ['sign', 'verify']
    ) as CryptoKeyPair;
    otherPrivateKey = other.privateKey;
  });

  const mockJwks = () => vi.spyOn(globalThis, 'fetch').mockImplementation(async () =>
    new Response(JSON.stringify({ keys: [{ ...publicJwk, kid: KID, alg: 'RS256', use: 'sig' }] }), {
      status: 200, headers: { 'Cache-Control': 'public, max-age=3600' },
    }));

  afterEach(() => {
    vi.restoreAllMocks();
    resetFirebaseKeyCache();
  });

  it('asks a new Google user to finish registration', async () => {
    mockJwks();
    const res = await post({ id_token: await idToken({ sub: 'uid_new' }) });
    expect(res.status).toBe(404);
    expect(((await res.json()) as any).code).toBe('registration_required');
  });

  it('registers a new account, then signs the same Google user back in', async () => {
    mockJwks();
    const token = await idToken({ sub: 'uid_alice' });
    const reg = await post({ id_token: token, business_name: 'Alice Tutorials', phone: '98300 12121' });
    expect(reg.status).toBe(200);
    const regBody = (await reg.json()) as any;
    expect(regBody.access_token).toBeTruthy();
    expect(regBody.refresh_token).toBeTruthy();

    const user = await env.DB.prepare("SELECT phone, email, business_id FROM users WHERE firebase_uid = 'uid_alice'").first<any>();
    expect(user).toMatchObject({ phone: '919830012121', email: 'alice@example.com' });
    const agent = await env.DB.prepare('SELECT id FROM agents WHERE business_id = ?').bind(user.business_id).first();
    expect(agent).toBeTruthy();

    const again = await post({ id_token: token });
    expect(again.status).toBe(200);
    const me = await app.fetch(new Request('http://localhost/business', {
      headers: { Authorization: `Bearer ${((await again.json()) as any).access_token}` },
    }), testEnv());
    expect(me.status).not.toBe(401);
  });

  it('refuses to attach a Google account to a phone number another account owns', async () => {
    mockJwks();
    await env.DB.prepare("INSERT INTO users (id, phone, business_id) VALUES ('usr_phone_owner', '919830034343', 'biz_owner')").run();
    const res = await post({ id_token: await idToken({ sub: 'uid_mallory' }), business_name: 'X', phone: '9830034343' });
    expect(res.status).toBe(409);
    const owner = await env.DB.prepare("SELECT firebase_uid FROM users WHERE id = 'usr_phone_owner'").first<any>();
    expect(owner.firebase_uid).toBeNull();
  });

  it.each([
    ['wrong audience', { aud: 'some-other-project' }],
    ['wrong issuer', { iss: 'https://accounts.google.com' }],
    ['expired', { exp: Math.floor(Date.now() / 1000) - 3600 }],
    ['issued in the future', { iat: Math.floor(Date.now() / 1000) + 3600 }],
    ['empty subject', { sub: '' }],
  ])('rejects a token with %s', async (_label, claims) => {
    mockJwks();
    const res = await post({ id_token: await idToken(claims), business_name: 'X', phone: '9830056565' });
    expect(res.status).toBe(401);
  });

  it('rejects a token signed by a key Google did not publish', async () => {
    mockJwks();
    expect((await post({ id_token: await idToken({}, { key: otherPrivateKey }) })).status).toBe(401);
    expect((await post({ id_token: await idToken({}, { kid: 'unknown-kid' }) })).status).toBe(401);
  });

  it('returns 503 when Google signing keys cannot be fetched', async () => {
    vi.spyOn(globalThis, 'fetch').mockImplementation(async () => new Response('down', { status: 503 }));
    expect((await post({ id_token: await idToken({}) })).status).toBe(503);
  });

  it('rejects everything when FIREBASE_PROJECT_ID is not configured', async () => {
    mockJwks();
    const res = await post({ id_token: await idToken({}) }, { ...env, FIREBASE_PROJECT_ID: undefined } as any);
    expect(res.status).toBe(401);
  });
});
