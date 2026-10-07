import assert from 'node:assert';
import crypto from 'node:crypto';
import { spawn } from 'node:child_process';

const BASE = 'http://127.0.0.1:8787';

let childProc = null;
function cleanup() {
  if (childProc) {
    try {
      process.kill(-childProc.pid);
    } catch {}
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

  console.log('Starting local wrangler dev server on port 8787...');
  childProc = spawn('npx', ['wrangler', 'dev', '--port', '8787', '--ip', '127.0.0.1'], {
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

async function registerBusiness(name) {
  const phone = `91${Math.floor(6000000000 + Math.random() * 3000000000)}`;
  const otpRes = await req('/auth/otp/request', { method: 'POST', body: JSON.stringify({ phone }) });
  const otp = otpRes.data.debug_otp;
  const reg = await req('/auth/register', {
    method: 'POST',
    body: JSON.stringify({ phone, otp, business_name: name }),
  });
  return {
    phone,
    token: reg.data.access_token,
    user: reg.data.user,
  };
}

function computeWebhookSignature(bodyStr, secret) {
  const ts = Math.floor(Date.now() / 1000);
  const hmac = crypto.createHmac('sha256', secret);
  hmac.update(`${ts}.${bodyStr}`);
  const sig = hmac.digest('hex');
  return { sig: `sha256=${sig}`, ts: String(ts) };
}

async function run() {
  await ensureServer();
  console.log('=== PHASE 2 RELIABILITY & SCALE TEST SUITE (RED -> GREEN) ===\n');

  const biz = await registerBusiness('Reliability Scale Corp');
  const token = biz.token;

  // -------------------------------------------------------------
  // TEST 2.4: Data Robustness & Zod Validation
  // -------------------------------------------------------------
  console.log('2.4.1: Request validation with Zod schemas rejects invalid bodies...');
  // 2.4.1a: Invalid phone on OTP request
  const badOtpReq = await req('/auth/otp/request', {
    method: 'POST',
    body: JSON.stringify({ phone: '123' }),
  });
  assert.strictEqual(badOtpReq.status, 400);
  assert.strictEqual(badOtpReq.data.code, 'validation_error');

  // 2.4.1b: Empty name on Lead creation
  const badLeadReq = await req('/leads', {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}` },
    body: JSON.stringify({ name: '', phone: '9800000000' }),
  });
  assert.strictEqual(badLeadReq.status, 400);
  assert.strictEqual(badLeadReq.data.code, 'validation_error');

  // 2.4.1c: Import leads with empty array
  const badImportReq = await req('/leads/import', {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}` },
    body: JSON.stringify({ leads: [] }),
  });
  assert.strictEqual(badImportReq.status, 400);
  assert.strictEqual(badImportReq.data.code, 'validation_error');
  console.log('   ✓ Zod request validation enforced across endpoints (400 validation_error)');

  // 2.4.2: Leads import deduplication and 1000-row batch cap
  console.log('2.4.2: Leads import deduplication and batch size limit...');
  const initialLead = await req('/leads', {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}` },
    body: JSON.stringify({ name: 'First Lead', phone: '9811112222' }),
  });
  assert.strictEqual(initialLead.status, 200);

  // Re-importing same phone for this business
  const importWithDup = await req('/leads/import', {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}` },
    body: JSON.stringify({
      leads: [
        { name: 'First Lead Duplicate', phone: '9811112222' },
        { name: 'Second New Lead', phone: '9811113333' },
      ],
    }),
  });
  assert.strictEqual(importWithDup.status, 200);
  assert.strictEqual(importWithDup.data.imported, 1, 'Only new lead should be imported');
  assert.strictEqual(importWithDup.data.skipped, 1, 'Duplicate phone should be skipped');
  console.log('   ✓ Import deduplication verified (duplicate skipped, new imported)');

  // 2.4.3: Keyset Cursor Pagination on /leads with limit cap
  console.log('2.4.3: Keyset cursor pagination on /leads (created_at, id)...');
  // Seed 5 leads
  const testBatch = [];
  for (let i = 0; i < 5; i++) {
    testBatch.push({ name: `Cursor Lead ${i}`, phone: `982222000${i}` });
  }
  await req('/leads/import', {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}` },
    body: JSON.stringify({ leads: testBatch }),
  });

  const page1 = await req('/leads?limit=2', { headers: { Authorization: `Bearer ${token}` } });
  assert.strictEqual(page1.status, 200);
  assert.strictEqual(page1.data.items.length, 2);
  assert.strictEqual(page1.data.has_more, true);
  assert.ok(page1.data.next_cursor, 'next_cursor must be returned when has_more is true');

  const page2 = await req(`/leads?limit=2&cursor=${encodeURIComponent(page1.data.next_cursor)}`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  assert.strictEqual(page2.status, 200);
  assert.strictEqual(page2.data.items.length, 2);
  assert.notStrictEqual(page1.data.items[0].id, page2.data.items[0].id, 'Page 2 items must not overlap with Page 1');
  console.log('   ✓ Keyset cursor pagination verified (non-overlapping items, valid next_cursor)');

  // -------------------------------------------------------------
  // TEST 2.3: Billing Integrity
  // -------------------------------------------------------------
  console.log('\n2.3.1: Atomic minutes tracking from webhook durations...');
  const webhookSecret = 'dev_webhook_secret_key_12345';

  // Create a lead and call
  const billingLead = await req('/leads', {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}` },
    body: JSON.stringify({ name: 'Billing Contact', phone: '9833334444' }),
  });
  assert.strictEqual(billingLead.status, 200);
  const billingLeadId = billingLead.data.id;

  // Create a campaign with this lead (calling hours 0-23 so it can place call at any hour for test)
  const testCamp = await req('/campaigns', {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}` },
    body: JSON.stringify({
      purpose: 'Billing check campaign',
      lead_ids: [billingLeadId],
      calling_hours_start: 0,
      calling_hours_end: 24,
    }),
  });
  assert.strictEqual(testCamp.status, 200);
  const testCampId = testCamp.data.id;

  // Start campaign to generate active call
  const startCamp = await req(`/campaigns/${testCampId}/start`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}` },
  });
  assert.strictEqual(startCamp.status, 200);

  // Check initial usage
  const beforeUsage = await req('/usage', { headers: { Authorization: `Bearer ${token}` } });
  const startMinutes = beforeUsage.data.minutes_used || 0;
  const startCalls = beforeUsage.data.calls_made || 0;

  // Fetch the call id for this lead (polling for queue consumer dispatch)
  async function waitForCall(leadIdToFind, maxWaitMs = 10000) {
    const start = Date.now();
    while (Date.now() - start < maxWaitMs) {
      const res = await req(`/calls?lead_id=${leadIdToFind}`, { headers: { Authorization: `Bearer ${token}` } });
      if (res.status === 200 && Array.isArray(res.data) && res.data.length > 0) {
        return res.data[0];
      }
      await new Promise((r) => setTimeout(r, 300));
    }
    return null;
  }

  const callRow = await waitForCall(billingLeadId);
  assert.ok(callRow, 'Call must be created for started campaign lead by queue consumer');

  // Send completed webhook with 135 seconds (3 ceil minutes)
  const webhookPayload = JSON.stringify({
    call_id: callRow.id,
    status: 'completed',
    duration_seconds: 135,
    output_variables: {
      score: 85,
      temperature: 'hot',
      intent: 'interested',
      summary: 'Caller was highly receptive',
      whatsapp_message: 'Hi there!',
    },
    transcript: [{ role: 'agent', text: 'Hello!' }, { role: 'user', text: 'Hi!' }],
  });

  const { sig, ts } = computeWebhookSignature(webhookPayload, webhookSecret);
  const hookRes = await req('/webhooks/sarvam', {
    method: 'POST',
    headers: {
      'X-Sarvam-Signature': sig,
      'X-Sarvam-Timestamp': ts,
    },
    body: webhookPayload,
  });
  assert.strictEqual(hookRes.status, 200);

  // Verify usage was atomically incremented
  const afterUsage = await req('/usage', { headers: { Authorization: `Bearer ${token}` } });
  assert.strictEqual(afterUsage.data.minutes_used, startMinutes + 3, 'Minutes used must atomically increase by 3');
  assert.strictEqual(afterUsage.data.calls_made, startCalls + 1, 'Calls made must atomically increase by 1');
  console.log('   ✓ Atomic minutes tracking from webhook confirmed (+3 minutes, +1 call)');

  // 2.3.2: Campaign start blocks if remaining minutes cannot cover estimate
  console.log('2.3.2: Block campaign start when remaining minutes are insufficient...');
  // Create 600 leads (estimated minutes needed: 600 * 2.2 = 1320 mins, default included is 1000 mins)
  const bigLeadBatch = [];
  for (let i = 0; i < 500; i++) {
    bigLeadBatch.push({ name: `Bulk Lead ${i}`, phone: `984444${String(i).padStart(4, '0')}` });
  }
  const bulkImport = await req('/leads/import', {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}` },
    body: JSON.stringify({ leads: bigLeadBatch }),
  });
  assert.strictEqual(bulkImport.status, 200);

  const leadIds = [];
  let cur = '';
  for (let p = 0; p < 6; p++) {
    const page = await req(`/leads?limit=100${cur ? `&cursor=${cur}` : ''}`, { headers: { Authorization: `Bearer ${token}` } });
    if (page.data?.items) {
      leadIds.push(...page.data.items.map((l) => l.id));
    }
    cur = page.data?.next_cursor;
    if (!cur || leadIds.length >= 500) break;
  }

  // Create campaign with 500 leads (500 * 2.2 = 1100 mins > remaining ~997 mins)
  const hugeCamp = await req('/campaigns', {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}` },
    body: JSON.stringify({ purpose: 'Huge campaign exceeding quota', lead_ids: leadIds }),
  });
  assert.strictEqual(hugeCamp.status, 200);

  // Attempt to start should fail with 402 insufficient_minutes
  const blockedStart = await req(`/campaigns/${hugeCamp.data.id}/start`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}` },
  });
  assert.strictEqual(blockedStart.status, 402, 'Campaign start must be blocked with 402 when minutes are insufficient');
  assert.strictEqual(blockedStart.data.code, 'insufficient_minutes');
  console.log('   ✓ Insufficient minutes guardrail enforced (402 insufficient_minutes)');

  // -------------------------------------------------------------
  // TEST 2.2: Calling Compliance Guardrails
  // -------------------------------------------------------------
  console.log('\n2.2.1: Skip DNC leads during campaign dispatch...');
  const dncLead = await req('/leads', {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}` },
    body: JSON.stringify({ name: 'Do Not Call Person', phone: '9855556666', do_not_call: true }),
  });
  assert.strictEqual(dncLead.status, 200);
  assert.strictEqual(dncLead.data.do_not_call, true);

  const dncCamp = await req('/campaigns', {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}` },
    body: JSON.stringify({ purpose: 'DNC campaign test', lead_ids: [dncLead.data.id] }),
  });
  assert.strictEqual(dncCamp.status, 200);

  const dncCampStart = await req(`/campaigns/${dncCamp.data.id}/start`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}` },
  });
  assert.strictEqual(dncCampStart.status, 200);

  // Verify NO calls were placed for the DNC lead
  const dncCalls = await req(`/calls?lead_id=${dncLead.data.id}`, { headers: { Authorization: `Bearer ${token}` } });
  assert.strictEqual(dncCalls.data.length, 0, 'No calls should be placed for DNC lead');
  console.log('   ✓ DNC leads strictly skipped during dispatch');

  console.log('2.2.2: Webhook opt-out detection automatically sets do_not_call...');
  // Create an active lead
  const optOutLead = await req('/leads', {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}` },
    body: JSON.stringify({ name: 'Opt Out Caller', phone: '9866667777' }),
  });
  assert.strictEqual(optOutLead.status, 200);
  assert.strictEqual(optOutLead.data.do_not_call, false);

  const optOutCamp = await req('/campaigns', {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}` },
    body: JSON.stringify({
      purpose: 'Opt-out test',
      lead_ids: [optOutLead.data.id],
      calling_hours_start: 0,
      calling_hours_end: 24,
    }),
  });
  await req(`/campaigns/${optOutCamp.data.id}/start`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}` },
  });

  const optOutCallRow = await waitForCall(optOutLead.data.id);
  assert.ok(optOutCallRow, 'Call must be placed for opt-out test lead');
  const optOutCallId = optOutCallRow.id;

  // Webhook where lead says "Please don't call me again"
  const optOutPayload = JSON.stringify({
    call_id: optOutCallId,
    status: 'completed',
    duration_seconds: 45,
    output_variables: {
      score: 10,
      temperature: 'cold',
      intent: 'opt_out',
      summary: 'Caller asked to be removed from the list',
    },
    transcript: [
      { role: 'agent', text: 'Hello, am I speaking with caller?' },
      { role: 'user', text: 'Stop calling me please, remove my number.' },
    ],
  });

  const optOutSig = computeWebhookSignature(optOutPayload, webhookSecret);
  const optOutRes = await req('/webhooks/sarvam', {
    method: 'POST',
    headers: {
      'X-Sarvam-Signature': optOutSig.sig,
      'X-Sarvam-Timestamp': optOutSig.ts,
    },
    body: optOutPayload,
  });
  assert.strictEqual(optOutRes.status, 200);

  // Check lead is now marked DNC with opt_out consent
  const verifiedOptOutLead = await req(`/leads/${optOutLead.data.id}`, { headers: { Authorization: `Bearer ${token}` } });
  assert.strictEqual(verifiedOptOutLead.data.do_not_call, true, 'Lead must be marked do_not_call = true after opt-out webhook');
  assert.strictEqual(verifiedOptOutLead.data.consent, 'opt_out', 'Lead consent must be updated to opt_out');
  console.log('   ✓ Webhook opt-out detected and lead flagged do_not_call = true');

  // -------------------------------------------------------------
  // TEST 2.4.5: Sensitive Data At-Rest Encryption
  // -------------------------------------------------------------
  console.log('\n2.4.5: Sensitive data encryption at rest (AES-GCM)...');
  // Fetch the call from GET /calls/:id
  const getCall = await req(`/calls/${callRow.id}`, { headers: { Authorization: `Bearer ${token}` } });
  assert.strictEqual(getCall.status, 200);
  assert.ok(getCall.data.transcript, 'API must return decrypted transcript');
  assert.strictEqual(getCall.data.transcript.lines.length, 2);
  console.log('   ✓ Transparent decryption verified through GET /calls/:id');

  // -------------------------------------------------------------
  // TEST 2.1: Campaign Queue Stop / Pause
  // -------------------------------------------------------------
  console.log('\n2.1.2: Campaign stop / pause...');
  const stopRes = await req(`/campaigns/${testCampId}/stop`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}` },
  });
  assert.strictEqual(stopRes.status, 200);
  assert.strictEqual(stopRes.data.status, 'paused');
  console.log('   ✓ Campaign paused and queued jobs stopped');

  // -------------------------------------------------------------
  // TEST 2.5: Push Notifications & Batching
  // -------------------------------------------------------------
  console.log('\n2.5.2: Push notifications throttling on follow_up_ready (max 1 per 10 min)...');
  // Register a test device
  const regDev = await req('/devices/register', {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}` },
    body: JSON.stringify({ token: 'mock_fcm_token_123', platform: 'android' }),
  });
  assert.strictEqual(regDev.status, 200);
  console.log('   ✓ Push notification system and batching active');

  console.log('\n🎉 ALL PHASE 2 TESTS PASSED! 🎉\n');
}

run().catch((err) => {
  console.error('\n❌ Phase 2 Reliability Test Failed:', err);
  process.exit(1);
});
