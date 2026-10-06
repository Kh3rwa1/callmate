import { Hono } from 'hono';
import { Env, AuthUser } from '../types';
import { signJWT, verifyJWT, getJwtSecret } from '../auth';

const voiceApp = new Hono<{ Bindings: Env; Variables: { user: AuthUser } }>();

// POST /voice/test-session (Requires auth)
voiceApp.post('/test-session', async (c) => {
  const user = c.get('user');
  const secret = getJwtSecret(c);

  const business = await c.env.DB.prepare('SELECT * FROM businesses WHERE id = ?').bind(user.business_id).first<any>();
  const agent = await c.env.DB.prepare('SELECT * FROM agents WHERE business_id = ?').bind(user.business_id).first<any>();

  // Short-lived session token (valid for 1 hour) specifically for the voice proxy
  const sessionToken = await signJWT(
    { sub: user.id, phone: user.phone, business_id: user.business_id, type: 'session' },
    secret,
    3600
  );

  const url = new URL(c.req.url);
  const proxyBaseUrl = `${url.origin}/voice/sarvam-proxy/`;

  return c.json({
    session_token: sessionToken,
    org_id: c.env.SARVAM_ORG_ID || 'org_callpilot',
    workspace_id: c.env.SARVAM_WORKSPACE_ID || 'ws_callpilot',
    app_id: c.env.SARVAM_ADMISSIONS_APP_ID || 'app_callpilot_voice',
    version: '1.0',
    proxy_base_url: proxyBaseUrl,
    agent_variables: {
      business_name: business?.name || 'CallPilot Business',
      agent_name: agent?.name || 'Riya',
      agent_role: agent?.role || 'Assistant',
      mode: 'owner_test',
    },
    user_identifier: user.id,
  });
});

// POST /voice/chat (Requires auth)
// Interactive conversational endpoint for live voice test and browser sessions
voiceApp.post('/chat', async (c) => {
  const user = c.get('user');
  const body: any = await c.req.json().catch(() => ({}));
  const userMessage = (body.message || '').trim();

  if (!userMessage) {
    return c.json({ message: 'Message is required.', code: 'invalid_request' }, 400);
  }

  const business = await c.env.DB.prepare('SELECT * FROM businesses WHERE id = ?').bind(user.business_id).first<any>();
  const agent = await c.env.DB.prepare('SELECT * FROM agents WHERE business_id = ?').bind(user.business_id).first<any>();

  const agentName = agent?.name || 'Riya';
  const agentRole = agent?.role || 'Assistant';
  const businessName = business?.name || 'our business';
  const category = business?.category || 'business';

  const lower = userMessage.toLowerCase();
  let reply = '';

  if (/^(hi|hello|hey|namaste|good\s*(morning|afternoon|evening)|salaam)/i.test(lower)) {
    reply = `Namaste! I am ${agentName}, your ${agentRole} at ${businessName}. How can I help you today?`;
  } else if (/what\s*(do\s*you\s*do|is\s*your\s*role)|who\s*are\s*you/i.test(lower)) {
    reply = `I am ${agentName}, the ${agentRole} for ${businessName}. I speak with callers, answer inquiries, qualify their needs, and schedule follow-ups for your team.`;
  } else if (/fee|cost|price|pricing|charge|rate/i.test(lower)) {
    reply = `Our pricing and fees at ${businessName} depend on the specific program or service you choose. I can note down your requirements and have our team send the full details via WhatsApp!`;
  } else if (/book|schedule|appointment|visit|tour|meeting|call\s*back/i.test(lower)) {
    reply = `I would be happy to schedule that for you at ${businessName}! What date and time works best for you?`;
  } else if (/hour|time|when\s*(are\s*you\s*open|can\s*i\s*call)/i.test(lower)) {
    reply = `Our standard operational hours at ${businessName} are from 10:00 AM to 7:00 PM Monday through Saturday.`;
  } else if (/qualif|score|hot\s*lead|lead/i.test(lower)) {
    reply = `During calls, I evaluate each customer's interest, timeline, and budget. High-intent inquiries are instantly scored as Hot Leads, and I alert your team with the full audio transcript.`;
  } else if (/human|manager|owner|speak\s*to\s*(someone|person)/i.test(lower)) {
    reply = `Certainly! I will immediately flag this call and schedule a callback with our senior team member at ${businessName}.`;
  } else {
    reply = `Thank you for asking about that! At ${businessName}, as your ${agentRole}, I ensure all your questions are handled and our team gets back to you with exact details. Would you like me to note your contact information?`;
  }

  return c.json({
    reply,
    agent_name: agentName,
    agent_role: agentRole,
    business_name: businessName,
  });
});

// ALL /voice/sarvam-proxy/*
// Secure proxy for Sarvam SDK runtime calls and WebSockets
voiceApp.all('/sarvam-proxy/*', async (c) => {
  // Validate session token in Authorization header
  const authHeader = c.req.header('Authorization');
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return c.json({ message: 'Missing session authorization for voice proxy.', code: 'unauthorized' }, 401);
  }

  const token = authHeader.substring(7).trim();
  const secret = getJwtSecret(c);
  const payload = await verifyJWT(token, secret);

  if (!payload) {
    return c.json({ message: 'Invalid or expired voice session token.', code: 'session_expired' }, 401);
  }

  const sarvamTargetBase = (c.env.SARVAM_PROXY_BASE || 'https://apps.sarvam.ai/api/app-runtime').replace(/\/$/, '');
  const reqUrl = new URL(c.req.url);
  const subPath = reqUrl.pathname.replace(/^\/voice\/sarvam-proxy\/?/, '/');
  const targetUrl = `${sarvamTargetBase}${subPath}${reqUrl.search}`;

  const forwardHeaders = new Headers(c.req.raw.headers);
  forwardHeaders.delete('Authorization');
  forwardHeaders.delete('Host');

  // Inject Sarvam API Key securely server-side
  const sarvamApiKey = c.env.SARVAM_API_KEY || '';
  if (sarvamApiKey) {
    forwardHeaders.set('X-API-Key', sarvamApiKey);
  }

  // Handle WebSocket upgrade or regular HTTP streaming request
  const isWebSocket = c.req.header('Upgrade')?.toLowerCase() === 'websocket';

  try {
    const response = await fetch(targetUrl, {
      method: c.req.method,
      headers: forwardHeaders,
      body: isWebSocket || c.req.method === 'GET' || c.req.method === 'HEAD' ? undefined : c.req.raw.body,
      // @ts-ignore Cloudflare Workers specific options
      cf: {
        cacheTtl: 0,
      },
    });

    return response;
  } catch (err: any) {
    console.error(`[Voice Proxy Error]: ${err?.message || err}`);
    return c.json({ message: 'Voice connection to Sarvam failed.', error: String(err) }, 502);
  }
});

// POST /webhooks/sarvam
// Public webhook endpoint for Sarvam call completions (HMAC signature verified)
voiceApp.post('/webhooks/sarvam', async (c) => {
  const secret = c.env.SARVAM_WEBHOOK_SECRET;
  const rawBody = await c.req.text();

  // Signature verification if secret configured
  const signature = c.req.header('X-Sarvam-Signature') || c.req.header('X-Signature');
  if (secret && signature) {
    const enc = new TextEncoder();
    const key = await crypto.subtle.importKey(
      'raw',
      enc.encode(secret),
      { name: 'HMAC', hash: 'SHA-256' },
      false,
      ['verify']
    );
    const valid = await crypto.subtle.verify(
      'HMAC',
      key,
      new Uint8Array(signature.match(/.{1,2}/g)?.map((byte) => parseInt(byte, 16)) || []),
      enc.encode(rawBody)
    );
    if (!valid) {
      return c.json({ message: 'Invalid webhook signature.' }, 403);
    }
  }

  let data: any;
  try {
    data = JSON.parse(rawBody);
  } catch {
    return c.json({ message: 'Malformed JSON payload.' }, 400);
  }

  const interactionId = data.interaction_id || data.call_id || `int_${crypto.randomUUID().slice(0, 8)}`;
  const explicitCallId = data.call_id || data.agent_variables?.call_id;

  // Check idempotency / existing call in D1
  const existingCall = explicitCallId
    ? await c.env.DB.prepare('SELECT id, status FROM calls WHERE id = ?').bind(explicitCallId).first<any>()
    : await c.env.DB.prepare('SELECT id, status FROM calls WHERE interaction_id = ?').bind(interactionId).first<any>();

  if (existingCall && existingCall.status === 'completed') {
    return c.json({ message: 'Already processed.', status: 'idempotent' }, 200);
  }

  const leadId = data.lead_id || data.agent_variables?.lead_id;
  let lead: any = null;
  if (leadId) {
    lead = await c.env.DB.prepare('SELECT * FROM leads WHERE id = ?').bind(leadId).first<any>();
  }

  const businessId = data.business_id || data.agent_variables?.business_id || lead?.business_id;

  if (!businessId || !leadId) {
    return c.json({ message: 'Missing lead_id or business_id in payload.' }, 400);
  }

  const leadName = lead?.name || data.lead_name || 'Customer';
  const leadPhone = lead?.phone || data.lead_phone || '';

  // Extract structured AI output variables produced by Sarvam agent
  const out = data.output_variables || data.extracted_variables || data.extracted_data || {};
  const rawScore = typeof out.lead_score === 'number' ? out.lead_score : (typeof out.qualification_score === 'number' ? out.qualification_score : null);
  const score = rawScore !== null ? Math.max(0, Math.min(100, Math.round(rawScore))) : 0;
  const rawTemp = out.temperature || out.lead_temperature;
  const temperature = rawTemp === 'hot' || score >= 75 ? 'hot' : (rawTemp === 'warm' || score >= 45 ? 'warm' : 'cold');
  const intent = out.intent || (score >= 70 ? 'interested' : 'exploring');
  const summary = out.summary || data.summary || 'Call completed.';
  const nextAction = out.next_action || 'none';
  const durationSeconds = data.duration_seconds || data.duration || 60;
  const callStatus = data.status === 'completed' || data.call_status === 'completed' ? 'completed' : 'no_answer';

  const objections = JSON.stringify(out.objections || []);
  const positiveSignals = JSON.stringify(out.positive_signals || []);
  const transcript = JSON.stringify(data.transcript || []);
  const callbackAt = out.callback_at || null;

  const callId = existingCall?.id || explicitCallId || `call_${crypto.randomUUID().slice(0, 12)}`;
  let followUpId: string | null = null;

  const statements: D1PreparedStatement[] = [];

  // 1. Create FollowUp if required
  if (out.whatsapp_followup_required || out.whatsapp_message) {
    followUpId = `fu_${crypto.randomUUID().slice(0, 12)}`;
    const msg = out.whatsapp_message || `Hi ${leadName.split(' ')[0]} 👋 Thanks for speaking with us!`;
    statements.push(
      c.env.DB.prepare(
        `INSERT INTO followups (id, business_id, lead_id, call_id, message, status, created_at)
         VALUES (?, ?, ?, ?, ?, 'ready', datetime('now'))`
      ).bind(followUpId, businessId, leadId, callId, msg)
    );
  }

  // 2. Insert or Update Call
  if (existingCall) {
    statements.push(
      c.env.DB.prepare(
        `UPDATE calls SET
          status = ?, duration_seconds = ?, recording_url = ?, transcript = ?,
          score = ?, temperature = ?, intent = ?, summary = ?, objections = ?,
          positive_signals = ?, next_action = ?, follow_up_id = ?, callback_at = ?,
          interaction_id = ?, completed_at = datetime('now')
         WHERE id = ?`
      ).bind(
        callStatus, durationSeconds, data.recording_url || null, transcript,
        score, temperature, intent, summary, objections,
        positiveSignals, nextAction, followUpId, callbackAt, interactionId,
        callId
      )
    );
  } else {
    statements.push(
      c.env.DB.prepare(
        `INSERT INTO calls (
          id, business_id, lead_id, lead_name, lead_phone, status, duration_seconds,
          recording_url, transcript, score, temperature, intent, summary, objections,
          positive_signals, next_action, follow_up_id, callback_at, interaction_id,
          started_at, completed_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now', '-' || ? || ' seconds'), datetime('now'))`
      ).bind(
        callId, businessId, leadId, leadName, leadPhone, callStatus, durationSeconds,
        data.recording_url || null, transcript, score, temperature, intent, summary,
        objections, positiveSignals, nextAction, followUpId, callbackAt, interactionId,
        durationSeconds
      )
    );
  }

  // 3. Update Lead
  statements.push(
    c.env.DB.prepare(
      `UPDATE leads SET
        status = 'called', temperature = ?, score = ?, summary = ?,
        objections = ?, next_action = ?, callback_at = ?, updated_at = datetime('now')
       WHERE id = ?`
    ).bind(temperature, score, summary, objections, nextAction, callbackAt, leadId)
  );

  // 4. Create Callback if scheduled
  if (callbackAt) {
    const callbackId = `cb_${crypto.randomUUID().slice(0, 12)}`;
    statements.push(
      c.env.DB.prepare(
        `INSERT INTO callbacks (id, business_id, lead_id, lead_name, scheduled_at, note, status, created_at)
         VALUES (?, ?, ?, ?, ?, ?, 'scheduled', datetime('now'))`
      ).bind(callbackId, businessId, leadId, leadName, callbackAt, `Callback requested from call: ${summary}`)
    );
  }

  // 5. Create Notification for Hot Lead
  if (temperature === 'hot') {
    const notifId = `notif_${crypto.randomUUID().slice(0, 12)}`;
    statements.push(
      c.env.DB.prepare(
        `INSERT INTO notifications (id, business_id, type, title, body, route, action_label, is_read, created_at)
         VALUES (?, ?, 'hot_lead', '🔥 Hot lead', ?, ?, 'View Result', 0, datetime('now'))`
      ).bind(
        notifId, businessId,
        `${leadName} is very interested (${score}/100)`,
        `/calls/${callId}/result`
      )
    );
  }

  // Execute in D1 batch
  await c.env.DB.batch(statements);

  return c.json({ success: true, call_id: callId, status: 'processed', temperature, score });
});

export { voiceApp };
