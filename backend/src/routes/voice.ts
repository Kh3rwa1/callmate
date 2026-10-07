import { Hono, Context } from 'hono';
import { Env, AuthUser } from '../types';
import { signJWT, verifyJWT, getJwtSecret } from '../auth';
import { safeJsonParse } from '../utils/json';
import { encryptAtRest } from '../utils/crypto_data';
import { isOptOutRequest } from '../services/compliance';
import { sendBusinessPushNotification } from '../services/fcm';
import { billableMinutes, claimWebhookEvent, recordCallUsage } from '../services/billing';
import { MAX_DIAL_ATTEMPTS, requeueLead } from '../services/campaign_queue';

const voiceApp = new Hono<{ Bindings: Env; Variables: { user: AuthUser } }>();

// POST /voice/test-session (Requires auth)
voiceApp.post('/test-session', async (c) => {
  const user = c.get('user');
  const secret = getJwtSecret(c);

  const business = await c.env.DB.prepare('SELECT * FROM businesses WHERE id = ?').bind(user.business_id).first<any>();
  const agent = await c.env.DB.prepare('SELECT * FROM agents WHERE business_id = ?').bind(user.business_id).first<any>();

  // Check concurrent sessions cap: max 5 active sessions per business (active within last 1 hour)
  const activeCount = await c.env.DB.prepare(
    `SELECT COUNT(*) as cnt FROM voice_sessions
     WHERE business_id = ? AND status = 'active' AND started_at > datetime('now', '-1 hour')`
  ).bind(user.business_id).first<{ cnt: number }>();

  if (activeCount && activeCount.cnt >= 5) {
    return c.json({ message: 'Maximum concurrent voice sessions reached for your business.', code: 'session_limit_exceeded' }, 429);
  }

  const sessionId = `vsess_${crypto.randomUUID()}`;
  await c.env.DB.prepare(
    `INSERT INTO voice_sessions (id, business_id, user_id, status, started_at)
     VALUES (?, ?, ?, 'active', datetime('now'))`
  ).bind(sessionId, user.business_id, user.id).run();

  // Short-lived session token (valid for 1 hour) specifically for the voice proxy
  const sessionToken = await signJWT(
    { sub: user.id, phone: user.phone, business_id: user.business_id, type: 'session' },
    secret,
    3600
  );

  const url = new URL(c.req.url);
  const proxyBaseUrl = `${url.origin}/voice/sarvam-proxy/`;

  const agentName = agent?.name || 'Riya';
  const businessName = business?.name || 'CallPilot Business';
  const greetingText = `Hello, I am ${agentName} from ${businessName}. How can I assist you today?`;
  const greetingAudioBase64 = await synthesizeFemaleAudio(c.env, greetingText);

  return c.json({
    session_token: sessionToken,
    org_id: c.env.SARVAM_ORG_ID || 'org_callpilot',
    workspace_id: c.env.SARVAM_WORKSPACE_ID || 'ws_callpilot',
    app_id: c.env.SARVAM_ADMISSIONS_APP_ID || 'app_callpilot_voice',
    version: '1.0',
    proxy_base_url: proxyBaseUrl,
    greeting_text: greetingText,
    greeting_audio_base64: greetingAudioBase64,
    agent_variables: {
      business_name: businessName,
      agent_name: agentName,
      agent_role: agent?.role || 'Assistant',
      gender: 'female',
      voice: 'female',
      speaker: 'meera',
      tts_model: 'bulbul:v4-flash',
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

  const { reply, audioBase64 } = await generateAIReply(
    c.env,
    agentName,
    agentRole,
    businessName,
    userMessage
  );

  return c.json({
    reply,
    audio_base64: audioBase64,
    agent_name: agentName,
    agent_role: agentRole,
    business_name: businessName,
  });
});

function arrayBufferToBase64(buffer: ArrayBuffer): string {
  const bytes = new Uint8Array(buffer);
  const chunkSize = 8192;
  let binary = '';
  for (let i = 0; i < bytes.length; i += chunkSize) {
    const chunk = bytes.subarray(i, i + chunkSize);
    binary += String.fromCharCode.apply(null, chunk as any);
  }
  return btoa(binary);
}

async function synthesizeFemaleAudio(env: Env, text: string): Promise<string | undefined> {
  const cleanText = text.replace(/!+/g, '.').replace(/\s+/g, ' ').trim();
  if (!cleanText) return undefined;

  // 1. Try Sarvam Bulbul v4 (bulbul:v4-flash / bulbul:v4) if real key is configured
  const sarvamKey = env.SARVAM_API_KEY || '';
  if (sarvamKey && !sarvamKey.includes('mock')) {
    try {
      const v4Payload = {
        inputs: [cleanText],
        target_language_code: 'en-IN',
        speaker: 'meera',
        pace: 0.95,
        speech_sample_rate: 22050,
        enable_preprocessing: true,
        model: 'bulbul:v4-flash',
      };
      let ttsRes = await fetch('https://api.sarvam.ai/text-to-speech', {
        method: 'POST',
        headers: {
          'api-subscription-key': sarvamKey,
          'X-API-Key': sarvamKey,
          'Authorization': `Bearer ${sarvamKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(v4Payload),
      });

      // Fallback to bulbul:v4 research preview if v4-flash fails
      if (!ttsRes.ok) {
        ttsRes = await fetch('https://api.sarvam.ai/text-to-speech', {
          method: 'POST',
          headers: {
            'api-subscription-key': sarvamKey,
            'X-API-Key': sarvamKey,
            'Authorization': `Bearer ${sarvamKey}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({ ...v4Payload, model: 'bulbul:v4' }),
        });
      }

      if (ttsRes.ok) {
        const ttsData: any = await ttsRes.json();
        if (ttsData?.audios?.[0]) {
          return ttsData.audios[0];
        }
      }
    } catch (e) {
      console.warn('[Sarvam Bulbul v4 TTS Error]:', e);
    }
  }

  // 2. Try Cloudflare Workers AI TTS (Deepgram Aura 2 female executive voice 'luna')
  const cfToken = env.CF_AI_API_TOKEN || '';
  const cfAccount = env.CF_ACCOUNT_ID || '';
  if (cfToken && cfAccount) {
    try {
      const cfTtsRes = await fetch(
        `https://api.cloudflare.com/client/v4/accounts/${cfAccount}/ai/run/@cf/deepgram/aura-2-en`,
        {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${cfToken}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            text: cleanText,
            voice: 'luna',
          }),
        }
      );
      if (cfTtsRes.ok) {
        const audioBuffer = await cfTtsRes.arrayBuffer();
        return arrayBufferToBase64(audioBuffer);
      }
    } catch (e) {
      console.warn('[Cloudflare Workers AI TTS Error]:', e);
    }
  }

  return undefined;
}

async function generateAIReply(
  env: Env,
  agentName: string,
  agentRole: string,
  businessName: string,
  userMessage: string
): Promise<{ reply: string; audioBase64?: string }> {
  const systemPrompt = `You are ${agentName}, a polite, professional, and calm female admissions coordinator and AI assistant at ${businessName}.
You are speaking live on a phone call with a customer or applicant.
Tone & Persona Guidelines:
1. Speak in a calm, natural, polite, and warm female executive phone voice.
2. Keep your response to 1 or 2 concise, clear sentences.
3. Address the caller's specific question directly and accurately.
4. Never use exclamation marks. Do not sound theatrical, dramatic, or robotic.
5. If they ask about fees, admissions, courses, or scheduling, answer helpfully and offer to note their contact or schedule a callback.`;

  let replyText = '';

  // 1. Try Sarvam AI Chat if non-mock key is available
  const sarvamKey = env.SARVAM_API_KEY || '';
  if (sarvamKey && !sarvamKey.includes('mock')) {
    try {
      const sarvamRes = await fetch('https://api.sarvam.ai/v1/chat/completions', {
        method: 'POST',
        headers: {
          'api-subscription-key': sarvamKey,
          'X-API-Key': sarvamKey,
          'Authorization': `Bearer ${sarvamKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          model: 'sarvam-105b',
          messages: [
            { role: 'system', content: systemPrompt },
            { role: 'user', content: userMessage },
          ],
        }),
      });
      if (sarvamRes.ok) {
        const data: any = await sarvamRes.json();
        replyText = data?.choices?.[0]?.message?.content?.trim() || '';
      }
    } catch (e) {
      console.warn('[Sarvam Chat Error]:', e);
    }
  }

  // 2. Try Cloudflare Workers AI with verified credentials
  if (!replyText) {
    const cfToken = env.CF_AI_API_TOKEN || '';
    const cfAccount = env.CF_ACCOUNT_ID || '';
    if (cfToken && cfAccount) {
      try {
        const cfRes = await fetch(
          `https://api.cloudflare.com/client/v4/accounts/${cfAccount}/ai/v1/chat/completions`,
          {
            method: 'POST',
            headers: {
              Authorization: `Bearer ${cfToken}`,
              'Content-Type': 'application/json',
            },
            body: JSON.stringify({
              model: '@cf/meta/llama-3.3-70b-instruct-fp8-fast',
              messages: [
                { role: 'system', content: systemPrompt },
                { role: 'user', content: userMessage },
              ],
            }),
          }
        );
        if (cfRes.ok) {
          const data: any = await cfRes.json();
          replyText = data?.choices?.[0]?.message?.content?.trim() || '';
        }
      } catch (e) {
        console.warn('[Cloudflare AI Error]:', e);
      }
    } else if (env.AI) {
      try {
        const aiRes: any = await env.AI.run('@cf/meta/llama-3.3-70b-instruct-fp8-fast', {
          messages: [
            { role: 'system', content: systemPrompt },
            { role: 'user', content: userMessage },
          ],
        });
        replyText = aiRes?.response?.trim() || '';
      } catch (e) {
        console.warn('[Cloudflare AI Binding Error]:', e);
      }
    }
  }

  // 3. Fallback: Calm, grounded, non-dramatic sentences
  if (!replyText) {
    const lower = userMessage.toLowerCase();
    if (/^(hi|hello|hey|namaste|good\s*(morning|afternoon|evening)|salaam)/i.test(lower)) {
      replyText = `Hello, I am ${agentName} from ${businessName}. How can I assist you today?`;
    } else if (/what\s*(do\s*you\s*do|is\s*your\s*role)|who\s*are\s*you/i.test(lower)) {
      replyText = `I am ${agentName}, the ${agentRole} for ${businessName}. I answer caller questions, verify requirements, and coordinate follow-ups for our team.`;
    } else if (/fee|cost|price|pricing|charge|rate/i.test(lower)) {
      replyText = `Our fees depend on the specific program you are interested in. I can note your details and have our admissions office send you the breakdown.`;
    } else if (/book|schedule|appointment|visit|tour|meeting|call\s*back/i.test(lower)) {
      replyText = `I would be happy to schedule that for you. What day and time works best for you?`;
    } else if (/hour|time|when\s*(are\s*you\s*open|can\s*i\s*call)/i.test(lower)) {
      replyText = `Our team is available from 10:00 AM to 7:00 PM Monday through Saturday.`;
    } else if (/human|manager|owner|speak\s*to\s*(someone|person)/i.test(lower)) {
      replyText = `I will notify our senior team member and arrange a direct callback for you.`;
    } else {
      replyText = `Thank you for asking. I am noting your inquiry for our team at ${businessName}, and we will follow up with the exact details.`;
    }
  }

  // De-dramatize: replace exclamation marks with periods, remove dramatic punctuation
  replyText = replyText.replace(/!+/g, '.').replace(/\s+/g, ' ').trim();

  // 4. Synthesize natural female audio
  const audioBase64 = await synthesizeFemaleAudio(env, replyText);

  return { reply: replyText, audioBase64 };
}

// Helper: JSON Schema Validator for call_output.schema.json
function validateCallOutput(output: any): { valid: boolean; normalized: any } {
  if (!output || typeof output !== 'object') {
    return {
      valid: false,
      normalized: {
        score: 0,
        temperature: 'cold',
        intent: 'unknown',
        summary: 'Invalid output payload - flagged for review',
        next_action: 'human_followup',
        whatsapp_followup_required: false,
        flagged_for_review: true,
      },
    };
  }

  const validIntents = ['interested', 'exploring', 'not_interested', 'callback_requested', 'unknown'];
  const validTemps = ['hot', 'warm', 'cold'];
  const validNextActions = ['human_followup', 'send_whatsapp', 'whatsapp_and_callback', 'book_appointment', 'retry_call', 'none'];

  const rawScore = output.lead_score ?? output.qualification_score;
  const score = typeof rawScore === 'number' && Number.isInteger(rawScore) ? rawScore : null;
  const intent = output.intent;
  const temp = output.temperature || output.lead_temperature;
  const summary = output.summary;
  const nextAction = output.next_action;
  const waRequired = output.whatsapp_followup_required;

  const isValid =
    score !== null && score >= 0 && score <= 100 &&
    validIntents.includes(intent) &&
    validTemps.includes(temp) &&
    typeof summary === 'string' && summary.length <= 400 &&
    validNextActions.includes(nextAction) &&
    typeof waRequired === 'boolean';

  if (!isValid) {
    return {
      valid: false,
      normalized: {
        score: 0,
        temperature: 'cold',
        intent: 'unknown',
        summary: typeof summary === 'string' ? summary.slice(0, 400) : 'Invalid output - flagged for review',
        next_action: 'human_followup',
        whatsapp_followup_required: false,
        flagged_for_review: true,
      },
    };
  }

  return {
    valid: true,
    normalized: {
      score,
      temperature: temp,
      intent,
      summary,
      next_action: nextAction,
      whatsapp_followup_required: waRequired,
      flagged_for_review: false,
    },
  };
}

// Proxy handler for Sarvam SDK runtime calls
async function handleSarvamProxy(c: Context<{ Bindings: Env; Variables: { user: AuthUser } }>) {
  // 1. Only accept JWTs where type === 'session'
  const authHeader = c.req.header('Authorization');
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return c.json({ message: 'Missing session authorization for voice proxy.', code: 'unauthorized' }, 401);
  }

  const token = authHeader.substring(7).trim();
  const secret = getJwtSecret(c);
  const payload = await verifyJWT(token, secret, 'session');

  if (!payload || payload.type !== 'session') {
    return c.json({ message: 'Invalid or expired voice session token. Only session tokens permitted.', code: 'session_expired' }, 401);
  }

  // 2. Strict path allow-list: only Sarvam app-runtime paths SDK needs
  const reqUrl = new URL(c.req.url);
  const subPath = reqUrl.pathname.replace(/^\/(voice\/)?sarvam-proxy\/?/, '');

  const isAllowed =
    /^(api\/app-runtime\/)?orgs\/[a-zA-Z0-9_-]+\/workspaces\/[a-zA-Z0-9_-]+\/apps\/[a-zA-Z0-9_-]+\/url\/?$/.test(subPath) ||
    /^(api\/app-runtime\/)?(chat|ws|sessions)(\/[a-zA-Z0-9_-]+)*\/?$/.test(subPath);

  if (!isAllowed) {
    return c.json({ message: 'Forbidden proxy destination.', code: 'forbidden_path' }, 403);
  }

  // 3. Per-business rate limit (max 60 req/min)
  const countRow = await c.env.DB.prepare(
    `SELECT COUNT(*) as cnt FROM voice_proxy_rate_limits
     WHERE business_id = ? AND created_at > datetime('now', '-1 minute')`
  ).bind(payload.business_id).first<{ cnt: number }>();

  if (countRow && countRow.cnt >= 60) {
    return c.json({ message: 'Voice proxy rate limit exceeded.', code: 'rate_limited' }, 429);
  }

  await c.env.DB.prepare(
    `INSERT INTO voice_proxy_rate_limits (id, business_id, created_at) VALUES (?, ?, datetime('now'))`
  ).bind(crypto.randomUUID(), payload.business_id).run();

  // 4. Do not forward client headers blindly; build clean header set and inject X-API-Key
  const forwardHeaders = new Headers();
  forwardHeaders.set('Accept', c.req.header('Accept') || 'application/json');
  const contentType = c.req.header('Content-Type');
  if (contentType) forwardHeaders.set('Content-Type', contentType);
  const userAgent = c.req.header('User-Agent');
  if (userAgent) forwardHeaders.set('User-Agent', userAgent);

  const sarvamApiKey = c.env.SARVAM_API_KEY || '';
  if (sarvamApiKey) {
    forwardHeaders.set('X-API-Key', sarvamApiKey);
    forwardHeaders.set('api-subscription-key', sarvamApiKey);
  }

  const sarvamTargetBase = (c.env.SARVAM_PROXY_BASE || 'https://apps.sarvam.ai/api/app-runtime').replace(/\/$/, '');
  const cleanSubPath = subPath.startsWith('api/app-runtime/') ? subPath.replace('api/app-runtime/', '') : subPath;
  const targetUrl = `${sarvamTargetBase}/${cleanSubPath}${reqUrl.search}`;

  const isWebSocket = c.req.header('Upgrade')?.toLowerCase() === 'websocket';

  try {
    const response = await fetch(targetUrl, {
      method: c.req.method,
      headers: forwardHeaders,
      body: isWebSocket || c.req.method === 'GET' || c.req.method === 'HEAD' ? undefined : c.req.raw.body,
    });
    return response;
  } catch (err: any) {
    const reqId = crypto.randomUUID();
    console.error(`[Voice Proxy Error] [RequestID: ${reqId}]:`, err?.message || err);
    return c.json({ message: 'Voice connection to Sarvam failed.', request_id: reqId }, 502);
  }
}

// ALL /sarvam-proxy/* and /voice/sarvam-proxy/*
voiceApp.all('/sarvam-proxy/*', handleSarvamProxy);
voiceApp.all('/voice/sarvam-proxy/*', handleSarvamProxy);

// Webhook handler for Sarvam call completions
async function handleSarvamWebhook(c: Context<{ Bindings: Env; Variables: { user: AuthUser } }>) {
  const secret = c.env.SARVAM_WEBHOOK_SECRET;
  const signature = c.req.header('X-Sarvam-Signature') || c.req.header('X-Signature');

  // Signature verification is MANDATORY. Reject with 401 if header or secret is missing.
  if (!secret || !signature) {
    return c.json({ message: 'Unauthorized webhook call. Missing signature or secret.', code: 'unauthorized' }, 401);
  }

  // Reject stale timestamps (> 5 min)
  const timestampHeader = c.req.header('X-Sarvam-Timestamp') || c.req.header('X-Timestamp');
  if (timestampHeader) {
    const ts = parseInt(timestampHeader, 10);
    const now = Math.floor(Date.now() / 1000);
    if (isNaN(ts) || Math.abs(now - ts) > 300) {
      return c.json({ message: 'Webhook timestamp is stale or invalid.', code: 'stale_timestamp' }, 401);
    }
  }

  const rawBody = await c.req.text();
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    'raw',
    enc.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign']
  );

  const sigBuf = await crypto.subtle.sign('HMAC', key, enc.encode(rawBody));
  const hexSig = Array.from(new Uint8Array(sigBuf)).map((b) => b.toString(16).padStart(2, '0')).join('');

  // Constant-time compare
  const cleanSig = signature.replace(/^sha256=/, '').trim();
  let isValid = false;
  if (cleanSig.length === hexSig.length) {
    const a = enc.encode(cleanSig);
    const b = enc.encode(hexSig);
    let diff = 0;
    for (let i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    isValid = (diff === 0);
  }

  if (!isValid && timestampHeader) {
    const altBuf = await crypto.subtle.sign('HMAC', key, enc.encode(`${timestampHeader}.${rawBody}`));
    const altHex = Array.from(new Uint8Array(altBuf)).map((b) => b.toString(16).padStart(2, '0')).join('');
    if (cleanSig.length === altHex.length) {
      const a = enc.encode(cleanSig);
      const b = enc.encode(altHex);
      let diff = 0;
      for (let i = 0; i < a.length; i++) {
        diff |= a[i] ^ b[i];
      }
      isValid = (diff === 0);
    }
  }

  if (!isValid) {
    return c.json({ message: 'Invalid webhook signature.', code: 'invalid_signature' }, 401);
  }

  let data: any;
  try {
    data = JSON.parse(rawBody);
  } catch {
    return c.json({ message: 'Malformed JSON payload.', code: 'malformed_json' }, 400);
  }

  const rawId = data.interaction_id || data.call_id || data.agent_variables?.call_id;
  if (!rawId) {
    return c.json({ message: 'Missing call or interaction identifier.', code: 'missing_identifier' }, 400);
  }

  // Never trust business_id or lead_id from the payload.
  // Resolve call through interaction_id or call_id against our own calls table:
  const call = await c.env.DB.prepare(
    `SELECT * FROM calls WHERE id = ? OR interaction_id = ?`
  ).bind(rawId, rawId).first<any>();

  if (!call) {
    return c.json({ message: 'Call not found.', code: 'call_not_found' }, 404);
  }

  // Derive business_id and lead_id strictly from our DB row
  const businessId = call.business_id;
  const leadId = call.lead_id;
  const callId = call.id;

  // 2. Right after resolving callId + businessId, claim webhook event (idempotency)
  const rawStatus = String(data.status || data.call_status || '').toLowerCase().trim();
  const finalStatus = ['completed', 'connected', 'answered', 'ended'].includes(rawStatus)
    ? 'completed'
    : (rawStatus || 'no_answer');

  const firstTime = await claimWebhookEvent(c.env.DB, `sarvam:${callId}:${finalStatus}`);
  if (!firstTime) {
    return c.json({ success: true, duplicate: true, status: 'idempotent', message: 'Already processed.' }, 200);
  }

  // Validate payload against schema: if invalid: score 0, temperature cold, flag for review, return 200
  const rawOutput = data.output_variables || data.extracted_variables || data.extracted_data || data;
  const validation = validateCallOutput(rawOutput);
  const norm = validation.normalized;

  const lead = await c.env.DB.prepare('SELECT name, phone FROM leads WHERE id = ? AND business_id = ?').bind(leadId, businessId).first<any>();
  const leadName = lead?.name || call.lead_name || 'Customer';

  // 3. Billing calculation
  const bill = billableMinutes(finalStatus, data.duration_seconds ?? data.duration);
  await recordCallUsage(c.env, businessId, callId, bill.minutes, bill.seconds);
  if (bill.flagged) {
    console.warn(JSON.stringify({ msg: 'call_duration_missing_flagged', callId, businessId, finalStatus }));
  }

  let callStatus = bill.flagged ? 'flagged_for_review' : finalStatus;
  const durationSeconds = bill.seconds;

  const objections = JSON.stringify(data.output_variables?.objections || []);
  const positiveSignals = JSON.stringify(data.output_variables?.positive_signals || []);
  const transcript = JSON.stringify(data.transcript || []);
  const callbackAt = data.output_variables?.callback_at || null;

  let followUpId: string | null = null;
  const statements: D1PreparedStatement[] = [];

  const encSecret = c.env.ENCRYPTION_KEY || c.env.JWT_SIGNING_KEY;
  const encryptedTranscript = await encryptAtRest(transcript, encSecret);
  const encryptedRawMetadata = await encryptAtRest(rawBody, encSecret);

  // 2.2: Opt-out detection from caller responses/intents
  const optOutRequested = isOptOutRequest(data);
  if (optOutRequested) {
    statements.push(
      c.env.DB.prepare(
        `UPDATE leads SET do_not_call = 1, consent = 'opt_out', updated_at = datetime('now') WHERE id = ? AND business_id = ?`
      ).bind(leadId, businessId)
    );
  }

  // 4. Only create FollowUp when finalStatus is a connected status
  const isConnected = ['completed', 'connected', 'answered', 'ended'].includes(finalStatus);
  if (isConnected && (norm.whatsapp_followup_required || data.output_variables?.whatsapp_message)) {
    followUpId = `fu_${crypto.randomUUID().slice(0, 12)}`;
    const msg = data.output_variables?.whatsapp_message || `Hi ${leadName.split(' ')[0]} 👋 Thanks for speaking with us!`;
    statements.push(
      c.env.DB.prepare(
        `INSERT INTO followups (id, business_id, lead_id, call_id, message, status, created_at)
         VALUES (?, ?, ?, ?, ?, 'ready', datetime('now'))`
      ).bind(followUpId, businessId, leadId, callId, msg)
    );
  }

  // Update Call with encrypted transcript, raw_metadata, and AND business_id = ?
  statements.push(
    c.env.DB.prepare(
      `UPDATE calls SET
        status = ?, duration_seconds = ?, recording_url = ?, transcript = ?, raw_metadata = ?,
        score = ?, temperature = ?, intent = ?, summary = ?, objections = ?,
        positive_signals = ?, next_action = ?, follow_up_id = ?, callback_at = ?,
        completed_at = datetime('now')
       WHERE id = ? AND business_id = ?`
    ).bind(
      callStatus, durationSeconds, data.recording_url || null, encryptedTranscript, encryptedRawMetadata,
      norm.score, norm.temperature, norm.intent, norm.summary, objections,
      positiveSignals, norm.next_action, followUpId, callbackAt,
      callId, businessId
    )
  );

  // Update Lead with AND business_id = ?
  statements.push(
    c.env.DB.prepare(
      `UPDATE leads SET
        status = 'called', temperature = ?, score = ?, summary = ?,
        objections = ?, next_action = ?, callback_at = ?, updated_at = datetime('now')
       WHERE id = ? AND business_id = ?`
    ).bind(norm.temperature, norm.score, norm.summary, objections, norm.next_action, callbackAt, leadId, businessId)
  );

  // Create Callback if scheduled
  if (callbackAt) {
    const callbackId = `cb_${crypto.randomUUID().slice(0, 12)}`;
    statements.push(
      c.env.DB.prepare(
        `INSERT INTO callbacks (id, business_id, lead_id, lead_name, scheduled_at, note, status, created_at)
         VALUES (?, ?, ?, ?, ?, ?, 'scheduled', datetime('now'))`
      ).bind(callbackId, businessId, leadId, leadName, callbackAt, `Callback requested: ${norm.summary}`)
    );
  }

  // Create Notification for Hot Lead
  if (norm.temperature === 'hot') {
    const notifId = `notif_${crypto.randomUUID().slice(0, 12)}`;
    statements.push(
      c.env.DB.prepare(
        `INSERT INTO notifications (id, business_id, type, title, body, route, action_label, is_read, created_at)
         VALUES (?, ?, 'hot_lead', '🔥 Hot lead', ?, ?, 'View Result', 0, datetime('now'))`
      ).bind(
        notifId, businessId,
        `${leadName} is very interested (${norm.score}/100)`,
        `/calls/${callId}/result`
      )
    );
  }

  await c.env.DB.batch(statements);

  // 5. Close the campaign loop
  const cl = await c.env.DB.prepare(
    'SELECT campaign_id, lead_id, attempts FROM campaign_leads WHERE call_id = ? OR (campaign_id = ? AND lead_id = ?)'
  ).bind(callId, call.campaign_id ?? '', leadId).first<any>();

  if (cl) {
    const connected = bill.minutes > 0 || ['completed', 'connected', 'answered'].includes(finalStatus);
    const next = connected ? 'completed' : (cl.attempts >= MAX_DIAL_ATTEMPTS ? 'failed' : 'retry_pending');
    await c.env.DB.batch([
      c.env.DB.prepare('UPDATE campaign_leads SET status = ? WHERE call_id = ? OR (campaign_id = ? AND lead_id = ?)').bind(next, callId, cl.campaign_id, cl.lead_id),
      c.env.DB.prepare(`UPDATE campaigns SET
          completed_leads = completed_leads + ?,
          connected_leads = connected_leads + ?,
          hot_leads  = hot_leads  + ?,
          warm_leads = warm_leads + ?
        WHERE id = ? AND business_id = ?`)
        .bind(next !== 'retry_pending' ? 1 : 0, connected ? 1 : 0, norm.temperature === 'hot' ? 1 : 0, norm.temperature === 'warm' ? 1 : 0, cl.campaign_id, businessId),
    ]);

    if (next === 'retry_pending') {
      await requeueLead(c.env, cl.campaign_id, businessId, cl.lead_id, 2 * 60 * 60); // retry no-answers after 2h
    }

    // 6. Check whether the campaign is finished
    const unfinished = await c.env.DB.prepare(
      `SELECT COUNT(*) AS cnt FROM campaign_leads
       WHERE campaign_id = ? AND status IN ('pending', 'queued', 'calling', 'retry_pending', 'rescheduled')`
    ).bind(cl.campaign_id).first<{ cnt: number }>();

    if ((unfinished?.cnt ?? 0) === 0) {
      await c.env.DB.prepare(
        `UPDATE campaigns SET status = 'completed', completed_at = datetime('now') WHERE id = ? AND business_id = ?`
      ).bind(cl.campaign_id, businessId).run();
    }
  }

  // 2.5: Push Notifications (FCM data-messages)
  const safeWaitUntil = (promise: Promise<any>) => {
    try {
      if (c.executionCtx) {
        c.executionCtx.waitUntil(promise);
        return;
      }
    } catch {}
    promise.catch((e) => console.error('[Push Notification Error]:', e));
  };

  if (norm.temperature === 'hot') {
    safeWaitUntil(
      sendBusinessPushNotification(c.env, businessId, {
        type: 'hot_lead',
        title: '🔥 Hot Lead Alert',
        body: `${leadName} is very interested (${norm.score}/100)`,
        route: `/leads/${leadId}`,
      })
    );
  }

  if (callbackAt) {
    safeWaitUntil(
      sendBusinessPushNotification(c.env, businessId, {
        type: 'callback',
        title: 'Callback Scheduled',
        body: `Callback scheduled with ${leadName}`,
        route: `/callbacks`,
      })
    );
  }

  if (followUpId) {
    // Batched to max 1 per 10 min
    safeWaitUntil(
      sendBusinessPushNotification(c.env, businessId, {
        type: 'follow_up_ready',
        title: '💬 Follow-up Ready',
        body: `Follow-up message ready for ${leadName}`,
        route: `/followups/${followUpId}`,
      })
    );
  }

  return c.json({
    success: true,
    call_id: callId,
    status: validation.valid ? 'processed' : 'flagged_for_review',
    temperature: norm.temperature,
    score: norm.score,
  }, 200);
}

// POST /webhooks/sarvam
voiceApp.post('/webhooks/sarvam', handleSarvamWebhook);

export { voiceApp, handleSarvamWebhook };

