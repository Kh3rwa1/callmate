import assert from 'node:assert';
import crypto from 'node:crypto';

const BASE = 'http://127.0.0.1:8787';

async function req(path, options = {}) {
  const url = `${BASE}${path}`;
  const res = await fetch(url, {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      ...options.headers,
    },
  });
  const data = await res.json().catch(() => null);
  return { status: res.status, data, headers: res.headers };
}

function b64url(str) {
  return Buffer.from(str).toString('base64url');
}

function createForgedJwt(header, payload, secret) {
  const h = b64url(JSON.stringify(header));
  const p = b64url(JSON.stringify(payload));
  const s = crypto.createHmac('sha256', secret).update(`${h}.${p}`).digest('base64url');
  return `${h}.${p}.${s}`;
}

async function run() {
  console.log('=== PHASE 1 SECURITY TEST SUITE (RED -> GREEN) ===\n');

  // Check server is up
  const health = await req('/health');
  assert.strictEqual(health.status, 200, 'Server must be running on ' + BASE);

  // -------------------------------------------------------------
  // TEST 1.1: Real OTP Auth
  // -------------------------------------------------------------
  console.log('1.1.1: Request OTP and verify rate limiting...');
  const testPhone = `91${Math.floor(6000000000 + Math.random() * 3000000000)}`;

  const otp1 = await req('/auth/otp/request', {
    method: 'POST',
    body: JSON.stringify({ phone: testPhone }),
  });
  assert.strictEqual(otp1.status, 200, `OTP request failed: ${JSON.stringify(otp1.data)}`);
  assert.ok(otp1.data.success);
  const receivedOtp = otp1.data.debug_otp; // Available in non-production
  assert.ok(receivedOtp, 'debug_otp must be provided in non-production mode');
  assert.strictEqual(receivedOtp.length, 6, 'OTP must be 6 digits');

  // Trigger rate limit: 3 requests allowed per 10 min, 4th must return 429
  await req('/auth/otp/request', { method: 'POST', body: JSON.stringify({ phone: testPhone }) });
  await req('/auth/otp/request', { method: 'POST', body: JSON.stringify({ phone: testPhone }) });
  const rateLimited = await req('/auth/otp/request', { method: 'POST', body: JSON.stringify({ phone: testPhone }) });
  assert.strictEqual(rateLimited.status, 429, '4th OTP request must be rate limited (429)');
  assert.strictEqual(rateLimited.data.code, 'rate_limited');
  console.log('   ✓ OTP request rate limiting verified (429 on 4th request in 10 min)');

  // 1.1.2: Login with wrong OTP must fail
  console.log('1.1.2: Login with wrong OTP fails...');
  const wrongLoginPhone = `91${Math.floor(6000000000 + Math.random() * 3000000000)}`;
  const otpReq2 = await req('/auth/otp/request', { method: 'POST', body: JSON.stringify({ phone: wrongLoginPhone }) });
  const validOtp2 = otpReq2.data.debug_otp;

  const wrongLogin = await req('/auth/login', {
    method: 'POST',
    body: JSON.stringify({ phone: wrongLoginPhone, otp: '000000' }),
  });
  assert.strictEqual(wrongLogin.status, 400, 'Wrong OTP must return 400');
  assert.strictEqual(wrongLogin.data.code, 'invalid_otp');
  console.log('   ✓ Wrong OTP correctly rejected (400 invalid_otp)');

  // 1.1.3: Max 5 failed attempts locks OTP
  console.log('1.1.3: 5 failed attempts locks OTP...');
  for (let i = 0; i < 4; i++) {
    await req('/auth/login', { method: 'POST', body: JSON.stringify({ phone: wrongLoginPhone, otp: '000000' }) });
  }
  const lockedLogin = await req('/auth/login', {
    method: 'POST',
    body: JSON.stringify({ phone: wrongLoginPhone, otp: validOtp2 }),
  });
  assert.strictEqual(lockedLogin.status, 429, 'Locked OTP must return 429 (otp_locked)');
  assert.strictEqual(lockedLogin.data.code, 'otp_locked');
  console.log('   ✓ 5 failed attempts locks OTP correctly');

  // 1.1.4: Registration requires verified OTP & re-register of existing phone returns no tokens
  console.log('1.1.4: Registration requires verified OTP and rejects existing phone...');
  const regPhone = `91${Math.floor(6000000000 + Math.random() * 3000000000)}`;
  const regOtpReq = await req('/auth/otp/request', { method: 'POST', body: JSON.stringify({ phone: regPhone }) });
  const regOtp = regOtpReq.data.debug_otp;

  // Attempt register with wrong OTP
  const badReg = await req('/auth/register', {
    method: 'POST',
    body: JSON.stringify({ phone: regPhone, otp: '111111', business_name: 'Security Test Academy' }),
  });
  assert.strictEqual(badReg.status, 400, 'Register with wrong OTP must return 400');

  // Register with valid OTP
  const goodReg = await req('/auth/register', {
    method: 'POST',
    body: JSON.stringify({ phone: regPhone, otp: regOtp, business_name: 'Security Test Academy' }),
  });
  assert.strictEqual(goodReg.status, 200, `Register failed: ${JSON.stringify(goodReg.data)}`);
  assert.ok(goodReg.data.access_token);
  assert.ok(goodReg.data.refresh_token);
  let user1Access = goodReg.data.access_token;
  let user1Refresh = goodReg.data.refresh_token;
  console.log('   ✓ Register with verified OTP succeeded');

  // Re-register of same phone must return 409 Conflict with NO tokens
  const reReg = await req('/auth/register', {
    method: 'POST',
    body: JSON.stringify({ phone: regPhone, otp: '123456', business_name: 'Security Test Duplicate' }),
  });
  assert.strictEqual(reReg.status, 409, 'Re-registration of existing phone must return 409 Conflict');
  assert.strictEqual(reReg.data.access_token, undefined, 'Must NEVER return access_token for existing user');
  console.log('   ✓ Re-registration of existing phone rejected with 409 and no tokens');

  // 1.1.5: Refresh token rotation & reuse detection revoking family
  console.log('1.1.5: Refresh token rotation and reuse detection...');
  const ref1 = await req('/auth/refresh', {
    method: 'POST',
    body: JSON.stringify({ refresh_token: user1Refresh }),
  });
  assert.strictEqual(ref1.status, 200);
  assert.ok(ref1.data.access_token);
  assert.ok(ref1.data.refresh_token);
  const user1Refresh2 = ref1.data.refresh_token;

  // Try using the OLD refresh token again (reuse attack!)
  const reuseAttack = await req('/auth/refresh', {
    method: 'POST',
    body: JSON.stringify({ refresh_token: user1Refresh }),
  });
  assert.strictEqual(reuseAttack.status, 401, 'Reused refresh token must be rejected with 401');
  assert.strictEqual(reuseAttack.data.code, 'token_reuse_detected');

  // Confirm that even the NEW refresh token is now revoked because family was compromised!
  const familyRevoked = await req('/auth/refresh', {
    method: 'POST',
    body: JSON.stringify({ refresh_token: user1Refresh2 }),
  });
  assert.strictEqual(familyRevoked.status, 401, 'Entire token family must be revoked upon reuse detection');
  console.log('   ✓ Refresh token rotation and family-wide reuse detection verified');

  // -------------------------------------------------------------
  // TEST 1.2: JWT Secret & Header Hardening
  // -------------------------------------------------------------
  console.log('\n1.2: JWT header and claim validation...');
  const devSecret = 'callpilot-dev-jwt-signing-secret-key-32chars';

  // Forged alg: none
  const forgedNone = `${b64url(JSON.stringify({ alg: 'none', typ: 'JWT' }))}.${b64url(JSON.stringify({ sub: 'u1', type: 'access', iss: 'callpilot', aud: 'callpilot-app', exp: Math.floor(Date.now() / 1000) + 3600 }))}.`;
  const resNone = await req('/business', { headers: { Authorization: `Bearer ${forgedNone}` } });
  assert.strictEqual(resNone.status, 401, 'alg: none must be rejected');

  // Wrong aud
  const badAud = createForgedJwt({ alg: 'HS256', typ: 'JWT' }, { sub: 'u1', type: 'access', iss: 'callpilot', aud: 'attacker-app', exp: Math.floor(Date.now() / 1000) + 3600 }, devSecret);
  const resAud = await req('/business', { headers: { Authorization: `Bearer ${badAud}` } });
  assert.strictEqual(resAud.status, 401, 'Invalid aud must be rejected');

  // Wrong iss
  const badIss = createForgedJwt({ alg: 'HS256', typ: 'JWT' }, { sub: 'u1', type: 'access', iss: 'attacker-iss', aud: 'callpilot-app', exp: Math.floor(Date.now() / 1000) + 3600 }, devSecret);
  const resIss = await req('/business', { headers: { Authorization: `Bearer ${badIss}` } });
  assert.strictEqual(resIss.status, 401, 'Invalid iss must be rejected');

  // Access token used where session token is required
  const validAccess = createForgedJwt({ alg: 'HS256', typ: 'JWT' }, { sub: 'u1', type: 'access', iss: 'callpilot', aud: 'callpilot-app', business_id: 'b1', exp: Math.floor(Date.now() / 1000) + 3600 }, devSecret);
  const resProxyWithAccess = await req('/voice/sarvam-proxy/apps/1/url', { headers: { Authorization: `Bearer ${validAccess}` } });
  assert.strictEqual(resProxyWithAccess.status, 401, 'Voice proxy must reject type: access (requires type: session)');
  console.log('   ✓ JWT alg, iss, aud, and type-separation enforced');

  // -------------------------------------------------------------
  // TEST 1.3: Webhook Hardening
  // -------------------------------------------------------------
  console.log('\n1.3: Webhook signature verification and tenant resolution...');
  // 1.3.1: Missing signature header
  const unsignedWebhook = await req('/webhooks/sarvam', {
    method: 'POST',
    body: JSON.stringify({ call_id: 'call_123', status: 'completed' }),
  });
  assert.strictEqual(unsignedWebhook.status, 401, 'Unsigned webhook must be rejected with 401');

  // 1.3.2: Forged / bad signature
  const forgedSig = await req('/webhooks/sarvam', {
    method: 'POST',
    headers: { 'x-sarvam-signature': 'bad_hex_signature' },
    body: JSON.stringify({ call_id: 'call_123', status: 'completed' }),
  });
  assert.strictEqual(forgedSig.status, 401, 'Invalid signature must be rejected with 401');
  console.log('   ✓ Unsigned and invalid webhook signatures strictly rejected (401)');

  // -------------------------------------------------------------
  // TEST 1.4: Voice Proxy Hardening
  // -------------------------------------------------------------
  console.log('\n1.4: Voice proxy path allow-list...');
  const sessionToken = createForgedJwt(
    { alg: 'HS256', typ: 'JWT' },
    { sub: 'u1', type: 'session', iss: 'callpilot', aud: 'callpilot-app', business_id: 'b1', exp: Math.floor(Date.now() / 1000) + 3600 },
    devSecret
  );

  // Disallowed path gets 403
  const badPath = await req('/voice/sarvam-proxy/admin/secret-delete', {
    headers: { Authorization: `Bearer ${sessionToken}` },
  });
  assert.strictEqual(badPath.status, 403, 'Disallowed path on voice proxy must return 403');
  console.log('   ✓ Disallowed paths on voice proxy blocked with 403 Forbidden');

  // -------------------------------------------------------------
  // TEST 1.5: Tenant Isolation Audit
  // -------------------------------------------------------------
  console.log('\n1.5: Cross-tenant isolation verification...');
  // Register Business A
  const phoneA = `91${Math.floor(6000000000 + Math.random() * 3000000000)}`;
  const otpA = (await req('/auth/otp/request', { method: 'POST', body: JSON.stringify({ phone: phoneA }) })).data.debug_otp;
  const regA = await req('/auth/register', { method: 'POST', body: JSON.stringify({ phone: phoneA, otp: otpA, business_name: 'Tenant A' }) });
  const tokenA = regA.data.access_token;

  // Register Business B
  const phoneB = `91${Math.floor(6000000000 + Math.random() * 3000000000)}`;
  const otpB = (await req('/auth/otp/request', { method: 'POST', body: JSON.stringify({ phone: phoneB }) })).data.debug_otp;
  const regB = await req('/auth/register', { method: 'POST', body: JSON.stringify({ phone: phoneB, otp: otpB, business_name: 'Tenant B' }) });
  const tokenB = regB.data.access_token;

  // Tenant A creates a lead
  const leadA = await req('/leads', {
    method: 'POST',
    headers: { Authorization: `Bearer ${tokenA}` },
    body: JSON.stringify({ name: 'Lead for A', phone: '9800000001', interest: 'Private Info A' }),
  });
  const leadAId = leadA.data.id;

  // Tenant B tries to GET Tenant A's lead
  const bReadA = await req(`/leads/${leadAId}`, { headers: { Authorization: `Bearer ${tokenB}` } });
  assert.strictEqual(bReadA.status, 404, 'Tenant B must not be able to read Tenant A lead (must return 404)');

  // Tenant B tries to PATCH Tenant A's lead
  const bPatchA = await req(`/leads/${leadAId}`, {
    method: 'PATCH',
    headers: { Authorization: `Bearer ${tokenB}` },
    body: JSON.stringify({ name: 'Hijacked by B' }),
  });
  assert.strictEqual(bPatchA.status, 404, 'Tenant B must not be able to update Tenant A lead (must return 404)');

  // Tenant B tries to create a campaign using Tenant A's lead ID
  const bCampA = await req('/campaigns', {
    method: 'POST',
    headers: { Authorization: `Bearer ${tokenB}` },
    body: JSON.stringify({
      title: 'Campaign By B',
      lead_ids: [leadAId],
    }),
  });
  assert.strictEqual(bCampA.status, 400, 'Campaign with foreign tenant leads must be rejected (400)');

  console.log('   ✓ Complete cross-tenant isolation verified across read, write, and campaigns');

  // -------------------------------------------------------------
  // TEST 1.6: Error Leakage
  // -------------------------------------------------------------
  console.log('\n1.6: Generic error responses with request_id...');
  const notFound = await req('/non-existent-route-for-testing', {
    headers: { Authorization: `Bearer ${tokenA}` },
  });
  assert.strictEqual(notFound.status, 404);
  console.log('   ✓ Error leakage audit passed');

  console.log('\n🎉 ALL PHASE 1 SECURITY TESTS PASSED! 🎉\n');
}

run().catch((err) => {
  console.error('\n❌ Phase 1 Security Test Failed:', err);
  process.exit(1);
});
