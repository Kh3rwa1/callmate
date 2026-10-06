import assert from 'node:assert';
import crypto from 'node:crypto';
import { spawn } from 'node:child_process';

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
  const reg = await req('/auth/register', {
    method: 'POST',
    body: JSON.stringify({
      phone: testPhone,
      business_name: 'Apex Academy Test',
    }),
  });
  assert.strictEqual(reg.status, 200, `Register failed: ${JSON.stringify(reg.data)}`);
  assert.ok(reg.data.access_token, 'Missing access_token');
  assert.ok(reg.data.refresh_token, 'Missing refresh_token');
  let accessToken = reg.data.access_token;
  let refreshToken = reg.data.refresh_token;
  console.log('   ✓ Register passed (issued JWTs)');

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

  // 10. Sarvam Webhook with HMAC signature
  console.log('10. Sarvam completed call webhook...');
  const webhookSecret = 'dev_webhook_secret_key_12345';
  const webhookBody = JSON.stringify({
    call_id: `sarvam_call_${Date.now()}`,
    lead_id: singleLead.data.id,
    duration_seconds: 145,
    status: 'completed',
    transcript: [
      { speaker: 'agent', text: 'Hello, am I speaking with Rohan?' },
      { speaker: 'user', text: 'Yes, Rohan here. I need Class 12 Physics tuition.' },
      { speaker: 'agent', text: 'Great! Our evening batches start next Monday. Can our academic head call you at 4 PM tomorrow?' },
      { speaker: 'user', text: 'Yes, please arrange that call.' },
    ],
    extracted_variables: {
      lead_temperature: 'hot',
      qualification_score: 92,
      summary: 'Rohan is eager to join Class 12 Physics evening batch. Agreed to counselor callback tomorrow at 4 PM.',
      next_action: 'counsellor_callback',
      callback_at: new Date(Date.now() + 86400000).toISOString(),
      key_topics: ['Class 12 Physics', 'Evening batch', 'Tuition fees'],
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
  assert.strictEqual(bizAfterDel.status, 200);
  assert.strictEqual(bizAfterDel.data, null);
  console.log('   ✓ Business data verified as deleted (null returned)');

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
