import assert from 'node:assert';
import crypto from 'node:crypto';
import fs from 'node:fs';
import { spawn, execFileSync } from 'node:child_process';

const BASE = 'http://127.0.0.1:8787';
let childProc = null;

function cleanup() {
  if (childProc && !childProc.killed) {
    try {
      if (childProc.pid) {
        process.kill(-childProc.pid, 'SIGTERM');
      }
    } catch {
      try {
        childProc.kill('SIGTERM');
      } catch {}
    }
    childProc = null;
  }
}

process.on('exit', cleanup);
process.on('SIGINT', () => { cleanup(); process.exit(1); });
process.on('SIGTERM', () => { cleanup(); process.exit(1); });

async function ensureServer() {
  try {
    const res = await fetch(`${BASE}/health`);
    if (res.ok) {
      console.log('Using running server at ' + BASE);
      return;
    }
  } catch {}

  if (!fs.existsSync('.dev.vars')) {
    fs.writeFileSync('.dev.vars', [
      'ENVIRONMENT=development',
      'JWT_SIGNING_KEY=test-jwt-signing-secret-key-32chars-min-length',
      'SARVAM_WEBHOOK_SECRET=dev_webhook_secret_key_12345',
      'SARVAM_API_KEY=sk_test_mock_sarvam_api_key',
      'OTP_PEPPER=local-e2e-otp-pepper-secret-32chars-min',
      'ENCRYPTION_KEY=local-e2e-encryption-key-32chars-min',
      'DEV_ALLOW_ANY_CALLING_HOURS=true',
    ].join('\n'));
  }

  console.log('Starting local wrangler dev server on port 8787...');
  childProc = spawn('npx', [
    'wrangler', 'dev',
    // No remote bindings (e.g. Workers AI): E2E must run without Cloudflare credentials.
    '--local',
    '--port', '8787',
    '--ip', '127.0.0.1',
    '--var', 'ENVIRONMENT:development',
    '--var', 'JWT_SIGNING_KEY:test-jwt-signing-secret-key-32chars-min-length',
    '--var', 'SARVAM_WEBHOOK_SECRET:dev_webhook_secret_key_12345',
    '--var', 'SARVAM_API_KEY:sk_test_mock_sarvam_api_key',
    '--var', 'DEV_ALLOW_ANY_CALLING_HOURS:true',
  ], {
    stdio: 'ignore',
    detached: true,
  });

  const start = Date.now();
  while (Date.now() - start < 30000) {
    try {
      const res = await fetch(`${BASE}/health`);
      if (res.ok) {
        console.log('✓ Wrangler dev server is ready.');
        return;
      }
    } catch {}
    await new Promise((r) => setTimeout(r, 1000));
  }
  throw new Error('Timed out waiting for wrangler dev server to become healthy');
}

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

async function run() {
  await ensureServer();
  console.log('--- Starting Cloudflare Worker E2E Tests ---');

  // 1. Health check
  console.log('1. Health check...');
  const health = await req('/health');
  assert.strictEqual(health.status, 200);
  assert.strictEqual(health.data.status, 'ok');
  console.log('   ✓ Health check passed');

  // 2. Auth: Register
  console.log('2. Auth Register...');
  const testPhone = `98${Math.floor(10000000 + Math.random() * 90000000)}`;
  const otpReq = await req('/auth/otp/request', {
    method: 'POST',
    body: JSON.stringify({ phone: testPhone }),
  });
  assert.strictEqual(otpReq.status, 200, `OTP request failed: ${JSON.stringify(otpReq.data)}`);
  const otp = otpReq.data.debug_otp;

  const reg = await req('/auth/register', {
    method: 'POST',
    body: JSON.stringify({
      phone: testPhone,
      otp,
      business_name: 'Apex Academy Test',
    }),
  });
  assert.strictEqual(reg.status, 200, `Register failed: ${JSON.stringify(reg.data)}`);
  assert.ok(reg.data.access_token, 'Missing access_token');
  assert.ok(reg.data.refresh_token, 'Missing refresh_token');
  let accessToken = reg.data.access_token;
  let refreshToken = reg.data.refresh_token;
  console.log('   ✓ Register passed with verified OTP (issued JWTs)');

  // 3. Auth: Refresh
  console.log('3. Auth Refresh...');
  const ref = await req('/auth/refresh', {
    method: 'POST',
    body: JSON.stringify({ refresh_token: refreshToken }),
  });
  assert.strictEqual(ref.status, 200, `Refresh failed: ${JSON.stringify(ref.data)}`);
  assert.ok(ref.data.access_token);
  assert.ok(ref.data.refresh_token);
  accessToken = ref.data.access_token;
  refreshToken = ref.data.refresh_token;
  console.log('   ✓ Refresh token rotated successfully');

  const authHeader = { Authorization: `Bearer ${accessToken}` };

  // 4. Business & Agent
  console.log('4. Business & Agent GET/PATCH...');
  const biz = await req('/business', { headers: authHeader });
  assert.strictEqual(biz.status, 200);
  assert.strictEqual(biz.data.name, 'Apex Academy Test');

  const patchBiz = await req('/business', {
    method: 'PATCH',
    headers: authHeader,
    body: JSON.stringify({ name: 'Apex Premier Academy' }),
  });
  assert.strictEqual(patchBiz.status, 200);
  assert.strictEqual(patchBiz.data.name, 'Apex Premier Academy');

  const agent = await req('/agent', { headers: authHeader });
  assert.strictEqual(agent.status, 200);
  assert.ok(agent.data.name);
  console.log(`   ✓ Business name updated to "${patchBiz.data.name}", agent is "${agent.data.name}"`);

  // 5. Leads: Create and Import
  console.log('5. Leads Create & Import...');
  const singleLead = await req('/leads', {
    method: 'POST',
    headers: authHeader,
    body: JSON.stringify({
      name: 'Rohan Sharma',
      phone: '9876543210',
      interest: 'Class 12 Physics',
      source: 'Website',
    }),
  });
  assert.strictEqual(singleLead.status, 200);
  assert.strictEqual(singleLead.data.name, 'Rohan Sharma');

  const importLeads = await req('/leads/import', {
    method: 'POST',
    headers: authHeader,
    body: JSON.stringify({
      leads: [
        { name: 'Pooja Verma', phone: '9876543211', interest: 'Class 11 Chemistry' },
        { name: 'Rohan Duplicate', phone: '9876543210', interest: 'Repeat Phone' }, // Should dedupe
        { name: 'Amit Kumar', phone: '9876543212', interest: 'NEET Foundation' },
      ],
    }),
  });
  assert.strictEqual(importLeads.status, 200);
  assert.strictEqual(importLeads.data.imported, 2);
  assert.strictEqual(importLeads.data.skipped, 1);
  console.log(`   ✓ Import deduplication verified: ${importLeads.data.imported} imported, ${importLeads.data.skipped} duplicates skipped`);

  // 6. Leads: List
  console.log('6. Leads List...');
  const leadsList = await req('/leads', { headers: authHeader });
  assert.strictEqual(leadsList.status, 200);
  assert.ok(leadsList.data.items.length >= 3);
  console.log(`   ✓ Found ${leadsList.data.items.length} leads in business`);

  // 7. Dashboard Today
  console.log('7. Dashboard Today...');
  const dash = await req('/dashboard/today', { headers: authHeader });
  assert.strictEqual(dash.status, 200);
  assert.strictEqual(dash.data.leads, leadsList.data.items.length);
  console.log(`   ✓ Dashboard metrics verified: leads=${dash.data.leads}`);

  // 8. Device Registration
  console.log('8. Device registration...');
  const devReg = await req('/devices/register', {
    method: 'POST',
    headers: authHeader,
    body: JSON.stringify({ token: 'test-fcm-token-12345', platform: 'android' }),
  });
  assert.strictEqual(devReg.status, 200);
  assert.strictEqual(devReg.data.registered, true);
  console.log('   ✓ Device registered');

  // 9. Voice Test Session
  console.log('9. Voice test session...');
  const voiceSess = await req('/voice/test-session', {
    method: 'POST',
    headers: authHeader,
  });
  assert.strictEqual(voiceSess.status, 200);
  assert.ok(voiceSess.data.session_token);
  assert.ok(voiceSess.data.proxy_base_url.includes('/voice/sarvam-proxy'));
  console.log(`   ✓ Voice session token generated, proxy=${voiceSess.data.proxy_base_url}`);

  // 9b. Trigger Outbound Lead Call via Sarvam
  console.log('9b. Trigger Lead Call via Sarvam Outbound...');
  // TRAI: the API only accepts calling hours inside 09:00-21:00.
  const tooWide = await req('/agent', {
    method: 'PATCH',
    headers: authHeader,
    body: JSON.stringify({ calling_hours_start: 0, calling_hours_end: 24 }),
  });
  assert.strictEqual(tooWide.status, 400);
  const traiHours = await req('/agent', {
    method: 'PATCH',
    headers: authHeader,
    body: JSON.stringify({ calling_hours_start: 9, calling_hours_end: 21 }),
  });
  assert.strictEqual(traiHours.status, 200);
  // So this run does not depend on the time of day, open the stored window all day directly in
  // the local D1 (the API refuses it) and run the server with DEV_ALLOW_ANY_CALLING_HOURS, which
  // skips the TRAI clamp in development only.
  execFileSync('npx', [
    'wrangler', 'd1', 'execute', 'callpilot-db', '--local',
    '--command', `UPDATE agents SET calling_hours_start = 0, calling_hours_end = 24 WHERE id = '${traiHours.data.id}'`,
  ], { stdio: 'ignore' });
  const triggerRes = await req(`/leads/${singleLead.data.id}/call`, {
    method: 'POST',
    headers: authHeader,
  });
  assert.strictEqual(triggerRes.status, 200);
  assert.ok(triggerRes.data.call?.id);
  assert.strictEqual(triggerRes.data.call?.status, 'calling');
  const triggeredCallId = triggerRes.data.call.id;
  console.log(`   ✓ Lead call initiated in DB with id=${triggeredCallId}, status=calling`);

  // 10. Sarvam Webhook with HMAC signature
  console.log('10. Sarvam completed call webhook...');
  const webhookSecret = 'dev_webhook_secret_key_12345';
  const webhookBody = JSON.stringify({
    call_id: triggeredCallId,
    lead_id: singleLead.data.id,
    duration_seconds: 145,
    status: 'completed',
    transcript: [
      { speaker: 'agent', text: 'Hello, am I speaking with Rohan?' },
      { speaker: 'user', text: 'Yes, Rohan here. I need Class 12 Physics tuition.' },
      { speaker: 'agent', text: 'Great! Our evening batches start next Monday. Can our academic head call you at 4 PM tomorrow?' },
      { speaker: 'user', text: 'Yes, please arrange that call.' },
    ],
    output_variables: {
      lead_score: 92,
      intent: 'interested',
      temperature: 'hot',
      summary: 'Rohan is eager to join Class 12 Physics evening batch. Agreed to counselor callback tomorrow at 4 PM.',
      next_action: 'whatsapp_and_callback',
      callback_at: new Date(Date.now() + 86400000).toISOString(),
      whatsapp_followup_required: true,
      whatsapp_message: 'Hi Rohan, thanks for speaking with Apex Academy! Counselor callback is scheduled for tomorrow at 4 PM.',
    },
  });

  const signature = crypto.createHmac('sha256', webhookSecret).update(webhookBody).digest('hex');
  const whRes = await req('/webhooks/sarvam', {
    method: 'POST',
    headers: { 'x-sarvam-signature': signature },
    body: webhookBody,
  });
  assert.strictEqual(whRes.status, 200, `Webhook failed: ${JSON.stringify(whRes.data)}`);
  assert.strictEqual(whRes.data.success, true);
  console.log(`   ✓ Webhook processed: lead updated to temperature=${whRes.data.temperature}, score=${whRes.data.score}`);

  // 11. Verify lead update & follow-up created
  console.log('11. Verify lead status after webhook...');
  const updatedLead = await req(`/leads/${singleLead.data.id}`, { headers: authHeader });
  assert.strictEqual(updatedLead.status, 200);
  assert.strictEqual(updatedLead.data.temperature, 'hot');
  assert.strictEqual(updatedLead.data.score.value, 92);
  console.log('   ✓ Lead was updated with AI analysis and hot temperature');

  // 11b. Speed-to-lead: hosted form + webhook enquiry is AI-called via the queue within seconds
  console.log('11b. Speed-to-lead (form + webhook -> instant call)...');
  const form = await req('/lead-sources', { method: 'POST', headers: authHeader, body: JSON.stringify({ kind: 'form' }) });
  assert.strictEqual(form.status, 201);
  const formPage = await fetch(`${BASE}/f/${form.data.slug}`);
  assert.strictEqual(formPage.status, 200);
  assert.ok((formPage.headers.get('content-security-policy') || '').includes("default-src 'none'"));
  const hook = await req('/lead-sources', { method: 'POST', headers: authHeader, body: JSON.stringify({ kind: 'webhook' }) });
  assert.strictEqual(hook.status, 201);
  assert.ok(hook.data.token);
  const badHook = await req(`/hooks/leads/${hook.data.slug}`, {
    method: 'POST', headers: { Authorization: 'Bearer wrong' },
    body: JSON.stringify({ name: 'Web Enquiry', phone: '9830077123', consent: true }),
  });
  assert.strictEqual(badHook.status, 401);
  const hookLead = await req(`/hooks/leads/${hook.data.slug}`, {
    method: 'POST', headers: { Authorization: `Bearer ${hook.data.token}` },
    body: JSON.stringify({ name: 'Web Enquiry', phone: '9830077123', interest: 'Demo', consent: true }),
  });
  assert.strictEqual(hookLead.status, 201, JSON.stringify(hookLead.data));
  let instantCall = null;
  for (let i = 0; i < 30 && !instantCall; i++) {
    const calls = await req(`/calls?lead_id=${hookLead.data.lead_id}`, { headers: authHeader });
    instantCall = Array.isArray(calls.data) ? calls.data[0] : null;
    if (!instantCall) await new Promise((r) => setTimeout(r, 1000));
  }
  assert.ok(instantCall, 'webhook enquiry was not called within 30s');
  assert.strictEqual(instantCall.status, 'calling');
  console.log('   ✓ Webhook enquiry created and AI-called via the queue');

  // 11c. Lead integrations: Google Ads lead form webhook (test lead ignored, real lead captured once)
  console.log('11c. Google Ads lead form webhook...');
  const gads = await req('/lead-sources', { method: 'POST', headers: authHeader, body: JSON.stringify({ kind: 'google_ads' }) });
  assert.strictEqual(gads.status, 201, JSON.stringify(gads.data));
  assert.ok(gads.data.google_key);
  const gadsLead = (isTest) => JSON.stringify({
    lead_id: 'e2e-gads-lead-1', google_key: gads.data.google_key, is_test: isTest, campaign_id: 1,
    user_column_data: [
      { column_id: 'FULL_NAME', string_value: 'Ads Enquiry' },
      { column_id: 'PHONE_NUMBER', string_value: '+919830077124' },
    ],
  });
  const gadsTest = await req(`/hooks/google-ads/${gads.data.slug}`, { method: 'POST', body: gadsLead(true) });
  assert.strictEqual(gadsTest.status, 200);
  const gadsReal = await req(`/hooks/google-ads/${gads.data.slug}`, { method: 'POST', body: gadsLead(false) });
  assert.strictEqual(gadsReal.status, 200, JSON.stringify(gadsReal.data));
  const gadsAgain = await req(`/hooks/google-ads/${gads.data.slug}`, { method: 'POST', body: gadsLead(false) });
  assert.strictEqual(gadsAgain.status, 200);
  const gadsBad = await req(`/hooks/google-ads/${gads.data.slug}`, { method: 'POST', body: gadsLead(false).replace(gads.data.google_key, 'wrong') });
  assert.strictEqual(gadsBad.status, 401);
  const sourcesAfter = await req('/lead-sources', { headers: authHeader });
  const gadsListed = sourcesAfter.data.items.find((s) => s.id === gads.data.id);
  assert.strictEqual(gadsListed.leads_count, 1);
  assert.strictEqual(gadsListed.google_key, undefined);
  console.log('   ✓ Google Ads lead captured once; test lead ignored; key never listed');

  // 12. Account Deletion (Apple App Store Guideline 5.1.1(v))
  console.log('12. Account Deletion...');
  const delAcc = await req('/auth/account', {
    method: 'DELETE',
    headers: authHeader,
  });
  assert.strictEqual(delAcc.status, 200);
  assert.strictEqual(delAcc.data.success, true);
  console.log('   ✓ Account permanently deleted');

  // 13. Verify old token is now invalid / user deleted
  console.log('13. Verify access revoked after account deletion...');
  const bizAfterDel = await req('/business', { headers: authHeader });
  assert.strictEqual(bizAfterDel.status, 401, `Deleted account token still works: ${bizAfterDel.status}`);
  assert.strictEqual(bizAfterDel.data.code, 'account_not_found');
  console.log('   ✓ Access token rejected after account deletion (401)');

  console.log('\n🎉 ALL CLOUDFLARE BACKEND TESTS PASSED SUCCESSFULLY! 🎉\n');
}

run()
  .catch((err) => {
    console.error('\n❌ Test failure:', err);
    cleanup();
    process.exit(1);
  })
  .finally(() => {
    cleanup();
    process.exit(0);
  });
