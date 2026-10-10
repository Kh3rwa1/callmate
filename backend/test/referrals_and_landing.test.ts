import { describe, it, expect, beforeAll, afterEach, vi } from 'vitest';
import { env } from 'cloudflare:test';
import { migrateTestDb } from './setup-db';
import app from '../src/index';
import { getPlan } from '../src/services/plans';
import { resetFirebaseKeyCache } from '../src/services/firebase_auth';
import {
  normalizeReferralCode, generateReferralCode, referralBonusMinutes, poweredByFooterHtml, referralLink,
  onFirstPayment, recordReferral, REFERRAL_ALPHABET,
} from '../src/services/referrals';
import { playStoreUrl, landingCsp, demoAudio } from '../src/routes/landing';

const WEBHOOK_SECRET = 'rzp_webhook_test_secret_referrals';

async function hmacHex(secret: string, body: string): Promise<string> {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey('raw', enc.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const sig = await crypto.subtle.sign('HMAC', key, enc.encode(body));
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

function call(path: string, init: RequestInit = {}, e: any = env, token?: string) {
  const headers: Record<string, string> = { 'Content-Type': 'application/json', ...(init.headers as any) };
  if (token) headers.Authorization = `Bearer ${token}`;
  return app.fetch(new Request(`http://localhost${path}`, { ...init, headers }), e);
}

let phoneSeq = 0;
function nextPhone(): string {
  phoneSeq += 1;
  return `96${String(Math.floor(Math.random() * 1e6)).padStart(6, '0')}${String(phoneSeq).padStart(2, '0')}`;
}

async function register(phone: string, referralCode?: string | null) {
  const ip = `10.15.${Math.floor(Math.random() * 250)}.${Math.floor(Math.random() * 250)}`;
  const otpRes = await call('/auth/otp/request', { method: 'POST', body: JSON.stringify({ phone }), headers: { 'cf-connecting-ip': ip } });
  const { debug_otp } = (await otpRes.json()) as any;
  const body: any = { phone, otp: debug_otp, business_name: 'Referral Biz' };
  if (referralCode !== undefined) body.referral_code = referralCode;
  const reg = await call('/auth/register', { method: 'POST', body: JSON.stringify(body), headers: { 'cf-connecting-ip': ip } });
  expect(reg.status).toBe(200);
  const tokens = (await reg.json()) as any;
  const user = await env.DB.prepare('SELECT business_id FROM users WHERE phone = ?').bind(`91${phone}`).first<any>();
  return { token: tokens.access_token as string, businessId: user.business_id as string };
}

async function summary(token: string) {
  const res = await call('/referrals', {}, env, token);
  expect(res.status).toBe(200);
  return (await res.json()) as any;
}

async function includedMinutes(businessId: string): Promise<number> {
  const r = await env.DB.prepare('SELECT included_minutes FROM usage WHERE business_id = ?').bind(businessId).first<any>();
  return Number(r?.included_minutes);
}

async function pay(businessId: string, paymentId: string) {
  const amount = getPlan('starter', env as any).priceInr * 100;
  const body = JSON.stringify({
    event: 'payment_link.paid',
    payload: {
      payment_link: { entity: { id: 'plink_ref', amount, amount_paid: amount, currency: 'INR', notes: { business_id: businessId, plan_id: 'starter' } } },
      payment: { entity: { id: paymentId, amount, currency: 'INR', status: 'captured' } },
    },
  });
  const res = await call('/webhooks/razorpay', {
    method: 'POST', body, headers: { 'X-Razorpay-Signature': await hmacHex(WEBHOOK_SECRET, body) },
  }, { ...env, RAZORPAY_WEBHOOK_SECRET: WEBHOOK_SECRET });
  expect(res.status).toBe(200);
  return (await res.json()) as any;
}

describe('Referral program', () => {
  beforeAll(async () => {
    await migrateTestDb();
  });

  describe('codes', () => {
    it('generates short codes from the unambiguous alphabet', () => {
      for (let i = 0; i < 50; i++) {
        const code = generateReferralCode();
        expect(code).toMatch(/^[23456789ABCDEFGHJKMNPQRSTUVWXYZ]{6}$/);
      }
      expect(REFERRAL_ALPHABET).not.toMatch(/[01ILO]/);
    });

    it('normalizes case, spaces and dashes and rejects malformed codes', () => {
      expect(normalizeReferralCode('ab-c 234')).toBe('ABC234');
      expect(normalizeReferralCode('ABC23O')).toBeNull(); // O is not in the alphabet
      expect(normalizeReferralCode('<script>')).toBeNull();
      expect(normalizeReferralCode('ABC2345')).toBeNull();
      expect(normalizeReferralCode(42)).toBeNull();
    });

    it('bonus minutes come from REFERRAL_BONUS_MINUTES with a 200 fallback', () => {
      expect(referralBonusMinutes({})).toBe(200);
      expect(referralBonusMinutes({ REFERRAL_BONUS_MINUTES: '150' })).toBe(150);
      expect(referralBonusMinutes({ REFERRAL_BONUS_MINUTES: 'x' })).toBe(200);
    });

    it('builds the landing link and powered-by footer with the ref code', () => {
      expect(referralLink('ABC234', 'https://api.example.com/')).toBe('https://api.example.com/get?ref=ABC234');
      expect(referralLink(null)).toBe('/get');
      const footer = poweredByFooterHtml('abc234');
      expect(footer).toContain('href="/get?ref=ABC234"');
      expect(footer).toContain('Powered by CallPilot');
      expect(poweredByFooterHtml('"><script>x</script>')).not.toContain('<script>');
    });
  });

  it('GET /referrals requires auth', async () => {
    expect((await call('/referrals')).status).toBe(401);
  });

  it('gives each business a stable code and empty stats', async () => {
    const a = await register(nextPhone());
    const s1 = await summary(a.token);
    expect(s1.code).toMatch(/^[23456789ABCDEFGHJKMNPQRSTUVWXYZ]{6}$/);
    expect(s1.link).toBe(`http://localhost/get?ref=${s1.code}`);
    expect(s1).toMatchObject({ bonus_minutes: 200, signed_up: 0, rewarded: 0, minutes_earned: 0 });
    expect((await summary(a.token)).code).toBe(s1.code);
  });

  it('records a referral at OTP signup and rewards both businesses once on the first payment', async () => {
    const referrer = await register(nextPhone());
    const { code } = await summary(referrer.token);
    const referred = await register(nextPhone(), code.toLowerCase());

    const row = await env.DB.prepare('SELECT * FROM referrals WHERE referred_business_id = ?').bind(referred.businessId).first<any>();
    expect(row).toMatchObject({ referrer_business_id: referrer.businessId, code, status: 'signed_up' });
    expect((await summary(referrer.token))).toMatchObject({ signed_up: 1, rewarded: 0, minutes_earned: 0 });

    const referrerBefore = await includedMinutes(referrer.businessId);
    const first = await pay(referred.businessId, `pay_ref_${Date.now()}_1`);
    expect(first.applied).toBe(true);
    const plan = getPlan('starter', env as any);
    expect(await includedMinutes(referred.businessId)).toBe(plan.includedMinutes + 200);
    expect(await includedMinutes(referrer.businessId)).toBe(referrerBefore + 200);

    // Redelivery of the same payment and a second payment do not credit again.
    const paymentId = `pay_ref_${Date.now()}_2`;
    await pay(referred.businessId, paymentId);
    await pay(referred.businessId, paymentId);
    expect(await onFirstPayment(env as any, referred.businessId)).toBe(false);
    expect(await includedMinutes(referrer.businessId)).toBe(referrerBefore + 200);

    const credits = await env.DB.prepare('SELECT business_id, minutes FROM referral_credits WHERE referral_id = ?').bind(row.id).all<any>();
    expect(credits.results).toHaveLength(2);
    expect((await summary(referrer.token))).toMatchObject({ signed_up: 1, rewarded: 1, minutes_earned: 200 });
    expect((await summary(referred.token)).minutes_earned).toBe(200);
  });

  it('concurrent reward calls credit only once', async () => {
    const referrer = await register(nextPhone());
    const { code } = await summary(referrer.token);
    const referred = await register(nextPhone(), code);
    await env.DB.prepare(
      `INSERT INTO payments (id, razorpay_payment_id, business_id, plan_id, amount_paise, status, applied_at)
       VALUES (?, ?, ?, 'starter', 1, 'paid', datetime('now'))`
    ).bind(`pay_c_${Date.now()}`, `rzp_c_${Date.now()}`, referred.businessId).run();
    const before = await includedMinutes(referrer.businessId);
    const results = await Promise.all([1, 2, 3].map(() => onFirstPayment(env as any, referred.businessId)));
    expect(results.filter(Boolean)).toHaveLength(1);
    expect(await includedMinutes(referrer.businessId)).toBe(before + 200);
  });

  it('does not reward before a payment is applied', async () => {
    const referrer = await register(nextPhone());
    const { code } = await summary(referrer.token);
    const referred = await register(nextPhone(), code);
    expect(await onFirstPayment(env as any, referred.businessId)).toBe(false);
    expect((await summary(referrer.token)).rewarded).toBe(0);
  });

  it('ignores unknown, malformed, empty and null codes without breaking signup', async () => {
    for (const bad of ['ZZZZZZ', '!!', '', null]) {
      const r = await register(nextPhone(), bad);
      const row = await env.DB.prepare('SELECT 1 FROM referrals WHERE referred_business_id = ?').bind(r.businessId).first();
      expect(row).toBeNull();
    }
  });

  it('blocks self-referral (own business, same phone or same email as the referrer)', async () => {
    const phone = nextPhone();
    const referrer = await register(phone);
    const { code } = await summary(referrer.token);
    expect(await recordReferral(env as any, referrer.businessId, code, { phone: `91${phone}` })).toBe('self_referral');
    await env.DB.prepare('UPDATE users SET email = ? WHERE business_id = ?').bind('owner@example.com', referrer.businessId).run();
    expect(await recordReferral(env as any, 'biz_other_new', code, { phone: `+91 ${phone}` })).toBe('self_referral');
    expect(await recordReferral(env as any, 'biz_other_new', code, { phone: '919999999999', email: 'OWNER@example.com ' })).toBe('self_referral');
    const rows = await env.DB.prepare('SELECT COUNT(*) AS n FROM referrals WHERE referrer_business_id = ?').bind(referrer.businessId).first<any>();
    expect(rows.n).toBe(0);
  });

  it('refers a phone only once, even after account deletion and re-signup', async () => {
    const referrer = await register(nextPhone());
    const { code } = await summary(referrer.token);
    const phone = nextPhone();
    const first = await register(phone, code);
    expect((await summary(referrer.token)).signed_up).toBe(1);

    const del = await call('/auth/account', { method: 'DELETE' }, env, first.token);
    expect(del.status).toBe(200);
    // Ids are pseudonymised but the row is kept.
    const anon = await env.DB.prepare('SELECT referred_business_id FROM referrals WHERE referrer_business_id = ?').bind(referrer.businessId).first<any>();
    expect(anon.referred_business_id).toMatch(/^anon_/);

    const again = await register(phone, code);
    const row = await env.DB.prepare('SELECT 1 FROM referrals WHERE referred_business_id = ?').bind(again.businessId).first();
    expect(row).toBeNull();
    expect(await recordReferral(env as any, again.businessId, code, { phone: `91${phone}` })).toBe('already_referred');
  });
});

describe('Referral via Google signup', () => {
  const PROJECT = 'callpilot-test-project';
  const KID = 'ref-kid-1';
  let privateKey: CryptoKey;
  let publicJwk: JsonWebKey;

  const b64url = (data: Uint8Array | string) => {
    const bytes = typeof data === 'string' ? new TextEncoder().encode(data) : data;
    let bin = '';
    bytes.forEach((b) => (bin += String.fromCharCode(b)));
    return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  };
  async function idToken(sub: string, email: string) {
    const now = Math.floor(Date.now() / 1000);
    const header = b64url(JSON.stringify({ alg: 'RS256', kid: KID, typ: 'JWT' }));
    const payload = b64url(JSON.stringify({
      aud: PROJECT, iss: `https://securetoken.google.com/${PROJECT}`, sub, iat: now, exp: now + 3600, auth_time: now,
      email, email_verified: true, firebase: { sign_in_provider: 'google.com' },
    }));
    const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', privateKey, new TextEncoder().encode(`${header}.${payload}`));
    return `${header}.${payload}.${b64url(new Uint8Array(sig))}`;
  }

  beforeAll(async () => {
    await migrateTestDb();
    const pair = await crypto.subtle.generateKey(
      { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' }, true, ['sign', 'verify']
    ) as CryptoKeyPair;
    privateKey = pair.privateKey;
    publicJwk = await crypto.subtle.exportKey('jwk', pair.publicKey) as JsonWebKey;
  });

  afterEach(() => {
    vi.restoreAllMocks();
    resetFirebaseKeyCache();
  });

  it('accepts referral_code on /auth/google signup', async () => {
    const referrer = await register(nextPhone());
    const { code } = await summary(referrer.token);
    vi.spyOn(globalThis, 'fetch').mockImplementation(async () =>
      new Response(JSON.stringify({ keys: [{ ...publicJwk, kid: KID, alg: 'RS256', use: 'sig' }] }), { status: 200 }));
    const phone = nextPhone();
    const res = await app.fetch(new Request('http://localhost/auth/google', {
      method: 'POST', headers: { 'Content-Type': 'application/json', 'CF-Connecting-IP': '203.0.113.77' },
      body: JSON.stringify({ id_token: await idToken('uid_ref_g', 'gref@example.com'), business_name: 'G Biz', phone, referral_code: code }),
    }), { ...env, FIREBASE_PROJECT_ID: PROJECT } as any);
    expect(res.status).toBe(200);
    vi.restoreAllMocks();
    expect((await summary(referrer.token)).signed_up).toBe(1);
  });
});

describe('Landing page GET /get', () => {
  it('renders the page with pricing from the plan catalogue, strict CSP and no scripts', async () => {
    const res = await call('/get');
    expect(res.status).toBe(200);
    expect(res.headers.get('Content-Type')).toContain('text/html');
    const csp = res.headers.get('Content-Security-Policy') ?? '';
    expect(csp).toContain("default-src 'none'");
    expect(csp).not.toContain('script-src');
    expect(csp).not.toContain('media-src');
    const html = await res.text();
    expect(html).toContain('Every enquiry called back in 60 seconds — in Hindi, Bengali or English');
    expect(html).not.toMatch(/<script/i);
    expect(html).not.toMatch(/\son[a-z]+=/i);
    const starter = getPlan('starter', env as any);
    expect(html).toContain(`₹${starter.priceInr.toLocaleString('en-IN')}`);
    expect(html).toContain('/legal/privacy');
    expect(html).toContain(escapeAmp(playStoreUrl(null)));
    expect(html).not.toContain('<audio');
  });

  it('carries a valid ref into the Play Store referrer', async () => {
    const html = await (await call('/get?ref=abc234')).text();
    expect(playStoreUrl('ABC234')).toBe(
      'https://play.google.com/store/apps/details?id=com.callpilot.app&referrer=utm_source%3Dlanding%26utm_campaign%3DABC234');
    expect(html).toContain(escapeAmp(playStoreUrl('ABC234')));
    expect(html).toContain('<strong>ABC234</strong>');
  });

  it('drops a malicious ref instead of rendering it', async () => {
    const html = await (await call(`/get?ref=${encodeURIComponent('"><script>alert(1)</script>')}`)).text();
    expect(html).not.toContain('<script>');
    expect(html).not.toContain('alert(1)');
    expect(html).toContain('utm_campaign%3Dnone');
  });

  it('shows the demo player only for an https DEMO_AUDIO_URL and allows just that origin', async () => {
    const e = { ...env, DEMO_AUDIO_URL: 'https://cdn.example.com/demo.mp3' };
    const res = await call('/get', {}, e);
    expect(res.headers.get('Content-Security-Policy')).toContain('media-src https://cdn.example.com');
    expect(await res.text()).toContain('<audio controls preload="none" src="https://cdn.example.com/demo.mp3"');
    expect(demoAudio({ DEMO_AUDIO_URL: 'http://insecure.example.com/a.mp3' })).toBeNull();
    expect(demoAudio({ DEMO_AUDIO_URL: 'javascript:alert(1)' })).toBeNull();
    expect(landingCsp(null)).not.toContain('media-src');
  });

  it('keeps / and /health as JSON', async () => {
    expect(((await (await call('/health')).json()) as any).status).toBe('ok');
    expect(((await (await call('/')).json()) as any).service).toBe('CallPilot API');
  });
});

function escapeAmp(s: string) {
  return s.replace(/&/g, '&amp;');
}
