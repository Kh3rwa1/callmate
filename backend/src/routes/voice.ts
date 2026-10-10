import { Hono, Context } from 'hono';
import { Env, AuthUser } from '../types';
import { signJWT, verifyJWT, getJwtSecret } from '../auth';
import { safeJsonParse } from '../utils/json';
import { encryptAtRest } from '../utils/crypto_data';
import { isOptOutRequest } from '../services/compliance';
import { consentEventStatement, CONSENT_TEXT_VERSIONS } from '../services/consent';
import { sendBusinessPushNotification } from '../services/fcm';
import { billableMinutes, claimWebhookEvent, releaseWebhookEvent, recordCallUsage } from '../services/billing';
import { MAX_DIAL_ATTEMPTS, requeueLead, maybeCompleteCampaign, sarvamWebhookToken } from '../services/campaign_queue';
import { isAllowedSarvamPath } from '../services/sarvam_proxy_guard';
import { hitRateLimit } from '../utils/rate_limit';
import { retrieveKnowledge } from '../services/knowledge';
import { buildSystemPrompt, loadHistory, saveTurn } from '../services/prompt';
import { requireSecret } from '../utils/secrets';
import { timingSafeEqual } from '../utils/compare';
import { jsonErrorHandler } from '../utils/errors';
import { VoiceGender, auraVoice, sarvamLanguageCode, sarvamSpeaker, voiceAgentVariables, voiceGender, voiceLang } from '../services/voice_persona';

const voiceApp = new Hono<{ Bindings: Env; Variables: { user: AuthUser } }>();
// voiceApp is also dispatched directly (voiceApp.fetch) for the proxy, bypassing the main app's onError.
voiceApp.onError(jsonErrorHandler);

/** Upper bound for proxied non-WebSocket Sarvam requests. */
export const VOICE_PROXY_TIMEOUT_MS = 30_000;

/** Sarvam call statuses that mean the call connected. */
const CONNECTED_STATUSES = ['completed', 'connected', 'answered', 'ended'];
/**
 * Sarvam statuses that mean the call is OVER without connecting. Anything else (ringing, initiated,
 * in_progress, queued, ...) is an intermediate event: acknowledged with 200 and no side effects.
 */
const TERMINAL_FAILURE_STATUSES = new Set([
  'no_answer', 'no-answer', 'not_answered', 'busy', 'failed', 'not_reached', 'unreachable',
  'cancelled', 'canceled', 'rejected', 'declined', 'timeout', 'error',
]);

/** QA accounts listed in the VOICE_UNLIMITED_EMAILS secret skip the session cap. */
async function isUnlimitedTester(env: Env, userId: string): Promise<boolean> {
  const allow = (env.VOICE_UNLIMITED_EMAILS || '')
    .split(',')
    .map((e) => e.trim().toLowerCase())
    .filter(Boolean);
  if (allow.length === 0) return false;
  const row = await env.DB.prepare('SELECT email FROM users WHERE id = ?').bind(userId).first<{ email: string | null }>();
  return !!row?.email && allow.includes(row.email.trim().toLowerCase());
}

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

  if (activeCount && activeCount.cnt >= 5 && !(await isUnlimitedTester(c.env, user.id))) {
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

  const agentName = agent?.name || 'Assistant';
  const businessName = business?.name || 'our business';
  const greetingText = `Hello, I'm ${agentName}, an AI assistant from ${businessName}. How can I assist you today?`;
  // The employee's own voice: a man named Arjun must not answer as a woman.
  // The app sends its language so the live call speaks it too.
  const reqBody: any = await c.req.json().catch(() => ({}));
  const gender = voiceGender(agent?.voice);
  const lang = voiceLang(reqBody?.lang);
  const greetingAudioBase64 = await synthesizeSpeech(c.env, greetingText, gender);

  return c.json({
    session_token: sessionToken,
    org_id: c.env.SARVAM_ORG_ID || '',
    workspace_id: c.env.SARVAM_WORKSPACE_ID || '',
    app_id: c.env.SARVAM_ADMISSIONS_APP_ID || '',
    version: '1.0',
    proxy_base_url: proxyBaseUrl,
    greeting_text: greetingText,
    greeting_audio_base64: greetingAudioBase64,
    agent_variables: {
      business_name: businessName,
      agent_name: agentName,
      agent_role: agent?.role || 'Assistant',
      ...voiceAgentVariables(agent, lang),
      mode: 'owner_test',
    },
    user_identifier: user.id,
    session_id: sessionId,
  });
});

// POST /voice/test-session/:id/end (Requires auth)
// Frees the session's slot in the concurrent-session cap when the call ends.
voiceApp.post('/test-session/:id/end', async (c) => {
  const user = c.get('user');
  await c.env.DB.prepare(
    `UPDATE voice_sessions SET status = 'ended', ended_at = datetime('now')
     WHERE id = ? AND business_id = ? AND status = 'active'`
  ).bind(c.req.param('id'), user.business_id).run();
  return c.json({ ok: true });
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

  const perUser = await hitRateLimit(c.env.DB, `chat:user:${user.id}`, 20, 60);         // 20 msgs/min
  const perBiz  = await hitRateLimit(c.env.DB, `chat:biz:${user.business_id}`, 300, 86400); // 300/day
  if (!perUser.allowed || !perBiz.allowed) {
    c.header('Retry-After', String(Math.max(perUser.retryAfter, perBiz.retryAfter)));
    return c.json({ message: 'Slow down a little, try again shortly.', code: 'rate_limited' }, 429);
  }
  if (userMessage.length > 1000) return c.json({ message: 'Message too long.', code: 'invalid_request' }, 400);

  const conversationId = (body.conversation_id && typeof body.conversation_id === 'string' && body.conversation_id.trim())
    ? body.conversation_id.trim()
    : `conv_${crypto.randomUUID()}`;

  const business = await c.env.DB.prepare('SELECT * FROM businesses WHERE id = ?').bind(user.business_id).first<any>();
  const agent = await c.env.DB.prepare('SELECT * FROM agents WHERE business_id = ?').bind(user.business_id).first<any>();

  const agentName = agent?.name || 'Assistant';
  const agentRole = agent?.role || 'Assistant';
  const businessName = business?.name || 'our business';
  const category = business?.category || 'business';

  const knowledge = await retrieveKnowledge(c.env, user.business_id, userMessage, 5);
  const systemPrompt = buildSystemPrompt({
    agentName,
    agentRole,
    businessName,
    category,
    knowledge,
  });

  const history = await loadHistory(c.env.DB, user.business_id, conversationId, 10);

  const { reply, audioBase64 } = await generateAIReply(
    c.env,
    systemPrompt,
    history,
    userMessage,
    agentName,
    agentRole,
    businessName,
    knowledge,
    voiceGender(agent?.voice)
  );

  await saveTurn(c.env.DB, user.business_id, conversationId, userMessage, reply);

  return c.json({
    reply,
    audio_base64: audioBase64,
    conversation_id: conversationId,
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

/** Speaks English [text] (greetings, chat replies) in the employee's voice. */
async function synthesizeSpeech(env: Env, text: string, gender: VoiceGender): Promise<string | undefined> {
  const cleanText = text.replace(/!+/g, '.').replace(/\s+/g, ' ').trim();
  if (!cleanText) return undefined;

  // 1. Try Sarvam Bulbul v4 (bulbul:v4-flash / bulbul:v4) if real key is configured
  const sarvamKey = env.SARVAM_API_KEY || '';
  if (sarvamKey && !sarvamKey.includes('mock')) {
    try {
      const v4Payload = {
        inputs: [cleanText],
        target_language_code: sarvamLanguageCode('en'),
        speaker: sarvamSpeaker(gender, 'en'),
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
        signal: AbortSignal.timeout(6000),
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
          signal: AbortSignal.timeout(6000),
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

  // 2. Try Cloudflare Workers AI TTS (Deepgram Aura 2: 'luna' or 'orion')
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
            voice: auraVoice(gender),
          }),
          signal: AbortSignal.timeout(6000),
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
  systemPrompt: string,
  history: Array<{ role: 'user' | 'assistant'; content: string }>,
  userMessage: string,
  agentName: string,
  agentRole: string,
  businessName: string,
  knowledge?: string[],
  gender: VoiceGender = 'female'
): Promise<{ reply: string; audioBase64?: string }> {
  let replyText = '';

  const messages = [
    { role: 'system', content: systemPrompt },
    ...history,
    { role: 'user', content: userMessage },
  ];

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
          messages,
        }),
        signal: AbortSignal.timeout(8000),
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
              messages,
            }),
            signal: AbortSignal.timeout(8000),
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
          messages,
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
    if (knowledge && knowledge.length > 0 && !/^(hi|hello|hey|namaste|good\s*(morning|afternoon|evening)|salaam)/i.test(lower)) {
      const firstChunk = (knowledge[0] || '').trim();
      const match = firstChunk.match(/^.*?[.?!](\s|$)/);
      const firstSentence = match ? match[0].trim() : firstChunk;
      replyText = firstSentence || firstChunk;
    } else if (/^(hi|hello|hey|namaste|good\s*(morning|afternoon|evening)|salaam)/i.test(lower)) {
      replyText = `Hello, I am ${agentName} from ${businessName}. How can I assist you today?`;
    } else if (/what\s*(do\s*you\s*do|is\s*your\s*role)|who\s*are\s*you/i.test(lower)) {
      replyText = `I am ${agentName}, the ${agentRole} for ${businessName}. I answer caller questions, verify requirements, and coordinate follow-ups for our team.`;
    } else if (/fee|cost|price|pricing|charge|rate/i.test(lower)) {
      replyText = `Our fees depend on the specific program or service. Let me check with the team and get back to you with the details.`;
    } else if (/book|schedule|appointment|visit|tour|meeting|call\s*back/i.test(lower)) {
      replyText = `I would be happy to schedule that for you. What day and time works best for you?`;
    } else if (/hour|time|when\s*(are\s*you\s*open|can\s*i\s*call)/i.test(lower)) {
      replyText = `Let me check with the team and get back to you with our schedule.`;
    } else if (/human|manager|owner|speak\s*to\s*(someone|person)/i.test(lower)) {
      replyText = `I will notify our team and arrange a callback for you.`;
    } else {
      replyText = `Thank you for asking. Let me check with the team and get back to you with the details.`;
    }
  }

  // De-dramatize: replace exclamation marks with periods, remove dramatic punctuation
  replyText = replyText.replace(/!+/g, '.').replace(/\s+/g, ' ').trim();

  // 4. Speak it in the employee's voice
  const audioBase64 = await synthesizeSpeech(env, replyText, gender);

  return { reply: replyText, audioBase64 };
}

// Helper: JSON Schema Validator for call_output.schema.json
/**
 * Sarvam agent variables arrive as strings ("87", "true") and empty strings for unset values;
 * coerce them to the types the call output schema expects.
 */
function normalizeAgentOutput(output: any): any {
  if (!output || typeof output !== 'object') return output;
  const out: any = { ...output };
  for (const k of Object.keys(out)) if (out[k] === '') out[k] = null;
  if (typeof out.lead_score === 'string' && /^\d+$/.test(out.lead_score.trim())) out.lead_score = parseInt(out.lead_score, 10);
  if (typeof out.lead_score === 'number' && !Number.isInteger(out.lead_score)) out.lead_score = Math.round(out.lead_score);
  if (typeof out.whatsapp_followup_required === 'string') {
    const v = out.whatsapp_followup_required.trim().toLowerCase();
    if (v === 'true' || v === 'false') out.whatsapp_followup_required = v === 'true';
  }
  for (const k of ['objections', 'positive_signals']) {
    if (typeof out[k] === 'string') {
      try { const v = JSON.parse(out[k]); if (Array.isArray(v)) out[k] = v; } catch { out[k] = out[k].split(/[;\n]/).map((x: string) => x.trim()).filter(Boolean); }
    }
  }
  return out;
}

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

  const validIntents = ['interested', 'exploring', 'not_interested', 'callback_requested', 'unknown', 'opt_out'];
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

  // 2. Strict path allow-list: only allow proxying to our org/workspace/app
  const reqUrl = new URL(c.req.url);
  const subPath = reqUrl.pathname.replace(/^\/(voice\/)?sarvam-proxy\/?/, '');

  if (!isAllowedSarvamPath(subPath, c.env)) {
    return c.json({ message: 'Forbidden proxy destination.', code: 'forbidden_upstream' }, 403);
  }

  // 3. Per-business rate limit (max 60 req/min)
  const slot = await c.env.DB.prepare(
    `INSERT INTO voice_proxy_rate_limits (id, business_id, created_at)
     SELECT ?, ?, datetime('now')
     WHERE (SELECT COUNT(*) FROM voice_proxy_rate_limits
            WHERE business_id = ? AND created_at > datetime('now', '-1 minute')) < 60`
  ).bind(crypto.randomUUID(), payload.business_id, payload.business_id).run();

  if ((slot.meta?.changes ?? 0) === 0) {
    return c.json({ message: 'Voice proxy rate limit exceeded.', code: 'rate_limited' }, 429);
  }

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
      signal: isWebSocket ? undefined : AbortSignal.timeout(VOICE_PROXY_TIMEOUT_MS),
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
  if (!secret) {
    return c.json({ message: 'Unauthorized webhook call. Missing signature or secret.', code: 'unauthorized' }, 401);
  }
  const rawBody = await c.req.text();

  // Sarvam does not sign webhooks: each dial's webhook URL carries call_id + HMAC(secret, call_id).
  // A signed body (X-Sarvam-Signature) is still accepted for senders that do sign.
  const urlCallId = c.req.query('call_id');
  const urlToken = c.req.query('token');
  const signature = c.req.header('X-Sarvam-Signature') || c.req.header('X-Signature');
  let isValid = false;

  if (urlCallId && urlToken) {
    isValid = timingSafeEqual(urlToken, await sarvamWebhookToken(secret, urlCallId));
  } else if (signature) {
    // Reject stale timestamps (> 5 min)
    const timestampHeader = c.req.header('X-Sarvam-Timestamp') || c.req.header('X-Timestamp');
    if (timestampHeader) {
      const ts = parseInt(timestampHeader, 10);
      const now = Math.floor(Date.now() / 1000);
      if (isNaN(ts) || Math.abs(now - ts) > 300) {
        return c.json({ message: 'Webhook timestamp is stale or invalid.', code: 'stale_timestamp' }, 401);
      }
    }
    const enc = new TextEncoder();
    const key = await crypto.subtle.importKey('raw', enc.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
    const toHex = (buf: ArrayBuffer) => Array.from(new Uint8Array(buf)).map((b) => b.toString(16).padStart(2, '0')).join('');
    const cleanSig = signature.replace(/^sha256=/, '').trim();
    isValid = timingSafeEqual(cleanSig, toHex(await crypto.subtle.sign('HMAC', key, enc.encode(rawBody))));
    if (!isValid && timestampHeader) {
      isValid = timingSafeEqual(cleanSig, toHex(await crypto.subtle.sign('HMAC', key, enc.encode(`${timestampHeader}.${rawBody}`))));
    }
  } else {
    return c.json({ message: 'Unauthorized webhook call. Missing signature or secret.', code: 'unauthorized' }, 401);
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

  // A URL token authorises exactly one call, so it also decides which call this is.
  const rawId = urlCallId || data.webhook_config?.metadata?.call_id || data.call_id
    || data.agent_variables?.call_id || data.attempt_id || data.interaction_id;
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
  // Missing status keeps the legacy meaning (no answer). Unknown / intermediate statuses are not terminal.
  if (rawStatus && !CONNECTED_STATUSES.includes(rawStatus) && !TERMINAL_FAILURE_STATUSES.has(rawStatus)) {
    return c.json({ success: true, ignored: true, status: 'non_terminal', message: 'Intermediate call status ignored.' }, 200);
  }
  const finalStatus = CONNECTED_STATUSES.includes(rawStatus)
    ? 'completed'
    : (rawStatus || 'no_answer');

  const eventKey = `sarvam:${callId}:${finalStatus}`;
  const firstTime = await claimWebhookEvent(c.env.DB, eventKey);
  if (!firstTime) {
    return c.json({ success: true, duplicate: true, status: 'idempotent', message: 'Already processed.' }, 200);
  }

  try {
    // Validate payload against schema: if invalid: score 0, temperature cold, flag for review, return 200
    const rawOutput = normalizeAgentOutput(data.output_variables || data.output_agent_variables || data.final_agent_variables
      || data.extracted_variables || data.extracted_data || data);
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

    const outputVars = rawOutput && typeof rawOutput === 'object' ? rawOutput : {};
    const objections = JSON.stringify(outputVars.objections || []);
    const positiveSignals = JSON.stringify(outputVars.positive_signals || []);
    const transcript = JSON.stringify(data.transcript || data.interaction_transcript || []);
    const callbackAt = outputVars.callback_at || null;

    let followUpId: string | null = null;
    const statements: D1PreparedStatement[] = [];

    const encSecret = requireSecret(c.env, 'ENCRYPTION_KEY', 32);
    const encryptedTranscript = await encryptAtRest(transcript, encSecret);
    const encryptedRawMetadata = await encryptAtRest(rawBody, encSecret);
    // Recording links are bearer URLs to the call audio: encrypted at rest like the transcript.
    const encryptedRecordingUrl = await encryptAtRest(data.recording_url || null, encSecret);

    // 2.2: Opt-out detection from caller responses/intents
    const optOutRequested = isOptOutRequest(data);
    if (optOutRequested) {
      statements.push(
        c.env.DB.prepare(
          `UPDATE leads SET do_not_call = 1, consent = 'opt_out', updated_at = datetime('now') WHERE id = ? AND business_id = ?`
        ).bind(leadId, businessId),
        // Opt-outs stay per business (this lead only); the public /stop page covers every business.
        consentEventStatement(c.env.DB, {
          businessId, leadId, consentValue: 'opt_out', source: 'in_call_opt_out',
          textVersion: CONSENT_TEXT_VERSIONS.inCallOptOut,
        }),
      );
    }

    // 4. Only create FollowUp when finalStatus is a connected status
    const isConnected = ['completed', 'connected', 'answered', 'ended'].includes(finalStatus);
    if (isConnected && (norm.whatsapp_followup_required || outputVars.whatsapp_message)) {
      followUpId = `fu_${crypto.randomUUID().slice(0, 12)}`;
      const msg = outputVars.whatsapp_message || `Hi ${leadName.split(' ')[0]} 👋 Thanks for speaking with us!`;
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
        callStatus, durationSeconds, encryptedRecordingUrl, encryptedTranscript, encryptedRawMetadata,
        norm.score, norm.temperature, norm.intent, norm.summary, objections,
        positiveSignals, norm.next_action, followUpId, callbackAt,
        callId, businessId
      )
    );

    // Update Lead with AND business_id = ?
    // Bug 3: Only update score/temperature on connected calls; otherwise update status = 'not_reached'
    if (isConnected) {
      statements.push(
        c.env.DB.prepare(
          `UPDATE leads SET
            status = 'called', temperature = ?, score = ?, summary = ?,
            objections = ?, next_action = ?, callback_at = ?, updated_at = datetime('now')
           WHERE id = ? AND business_id = ?`
        ).bind(norm.temperature, norm.score, norm.summary, objections, norm.next_action, callbackAt, leadId, businessId)
      );
    } else {
      statements.push(
        c.env.DB.prepare(
          `UPDATE leads SET
            status = 'not_reached', updated_at = datetime('now')
           WHERE id = ? AND business_id = ?`
        ).bind(leadId, businessId)
      );
    }

    // Create Callback if scheduled
    if (isConnected && callbackAt) {
      const callbackId = `cb_${crypto.randomUUID().slice(0, 12)}`;
      statements.push(
        c.env.DB.prepare(
          `INSERT INTO callbacks (id, business_id, lead_id, lead_name, scheduled_at, note, status, created_at)
           VALUES (?, ?, ?, ?, ?, ?, 'scheduled', datetime('now'))`
        ).bind(callbackId, businessId, leadId, leadName, callbackAt, `Callback requested: ${norm.summary}`)
      );
    }

    // Create Notification for Hot Lead
    if (isConnected && norm.temperature === 'hot') {
      const notifId = `notif_${crypto.randomUUID().slice(0, 12)}`;
      statements.push(
        c.env.DB.prepare(
          `INSERT INTO notifications (id, business_id, type, title, body, route, action_label, is_read, created_at)
           VALUES (?, ?, 'hot_lead', 'Hot Lead Alert', ?, ?, 'View Result', 0, datetime('now'))`
        ).bind(
          notifId, businessId,
          `${leadName} is very interested (${norm.score}/100)`,
          `/calls/${callId}/result`
        )
      );
    }

    await c.env.DB.batch(statements);

    // 5. Close the campaign loop
    const webhookOrigin = new URL(c.req.url).origin;
    if (call.status === 'timed_out') {
      // Late webhook after the sweeper gave up on this call. If the lead was set to retry but the call
      // actually connected, it is done: record it (the queued retry will find it completed and ack).
      const connectedLate = bill.minutes > 0 || isConnected;
      if (connectedLate) {
        const cl = await c.env.DB.prepare(
          `UPDATE campaign_leads SET status = 'completed' WHERE call_id = ? AND status = 'retry_pending'
           RETURNING campaign_id`
        ).bind(callId).first<{ campaign_id: string }>();
        if (cl) {
          await c.env.DB.prepare(`UPDATE campaigns SET
              completed_leads = completed_leads + 1,
              connected_leads = connected_leads + 1,
              hot_leads  = hot_leads  + ?,
              warm_leads = warm_leads + ?
            WHERE id = ? AND business_id = ?`)
            .bind(norm.temperature === 'hot' ? 1 : 0, norm.temperature === 'warm' ? 1 : 0, cl.campaign_id, businessId).run();
          await maybeCompleteCampaign(c.env.DB, cl.campaign_id);
        }
      }
    } else {
      const cl = await c.env.DB.prepare(
        'SELECT campaign_id, lead_id, attempts, status FROM campaign_leads WHERE call_id = ?'
      ).bind(callId).first<any>();

      if (cl && cl.status === 'calling') {
        const connected = bill.minutes > 0 || ['completed', 'connected', 'answered'].includes(finalStatus);
        const next = connected ? 'completed' : (cl.attempts >= MAX_DIAL_ATTEMPTS ? 'failed' : 'retry_pending');
        await c.env.DB.batch([
          c.env.DB.prepare('UPDATE campaign_leads SET status = ? WHERE call_id = ?').bind(next, callId),
          c.env.DB.prepare(`UPDATE campaigns SET
              completed_leads = completed_leads + ?,
              connected_leads = connected_leads + ?,
              hot_leads  = hot_leads  + ?,
              warm_leads = warm_leads + ?
            WHERE id = ? AND business_id = ?`)
            .bind(next !== 'retry_pending' ? 1 : 0, connected ? 1 : 0, (isConnected && norm.temperature === 'hot') ? 1 : 0, (isConnected && norm.temperature === 'warm') ? 1 : 0, cl.campaign_id, businessId),
        ]);

        if (next === 'retry_pending') {
          await requeueLead(c.env, cl.campaign_id, businessId, cl.lead_id, 2 * 60 * 60, webhookOrigin); // retry no-answers after 2h
        }

        // 6. Check whether the campaign is finished
        await maybeCompleteCampaign(c.env.DB, cl.campaign_id);
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

    if (isConnected && norm.temperature === 'hot') {
      safeWaitUntil(
        sendBusinessPushNotification(c.env, businessId, {
          type: 'hot_lead',
          title: 'Hot Lead Alert',
          body: `${leadName} is very interested (${norm.score}/100)`,
          route: `/leads/${leadId}`,
        })
      );
    }

    if (isConnected && callbackAt) {
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
          title: 'Follow-up Ready',
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
  } catch (err) {
    await releaseWebhookEvent(c.env.DB, eventKey);
    throw err;
  }
}

// POST /webhooks/sarvam
voiceApp.post('/webhooks/sarvam', handleSarvamWebhook);

export { voiceApp, handleSarvamWebhook };

