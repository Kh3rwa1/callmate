/**
 * The AI answers calls the owner misses (services/answering.ts).
 *
 * Owner (signed in):
 *   GET  /agent/answering          → { available, enabled, phone }
 *   POST /agent/answering {enabled} → turn on (number + Sarvam deployment) / off (pause)
 * Sarvam (public):
 *   POST /voice/inbound/start      → on-start hook: business name, employee, context, greeting
 *   POST /webhooks/sarvam-inbound  → after the call: lead + call row, then the outbound result handling
 */
import { Hono, Context } from 'hono';
import { z } from 'zod';
import { Env, AuthUser } from '../types';
import { parseJsonBody } from '../schemas/validation';
import { timingSafeEqual } from '../utils/compare';
import { normalizePhone } from '../utils/phone';
import { sarvamWebhookToken } from '../services/campaign_queue';
import {
  answeringConfigured, answeringFor, e164, inboundCallContext, inboundWebhookToken, setAnswering,
} from '../services/answering';
import { consentEventStatement, CONSENT_TEXT_VERSIONS } from '../services/consent';
import { ownerLanguage } from '../services/owner_text';
import { sendBusinessPushNotification } from '../services/fcm';
import { voiceApp } from './voice';

type AuthedEnv = { Bindings: Env; Variables: { user: AuthUser } };

// ------------------------------------------------------------- owner

export const answeringApp = new Hono<AuthedEnv>();

function answeringView(env: Env, row: { phone: string; enabled: number } | null) {
  return { available: answeringConfigured(env), enabled: row?.enabled === 1, phone: row?.phone ?? null };
}

answeringApp.get('/agent/answering', async (c) => {
  const user = c.get('user');
  return c.json(answeringView(c.env, await answeringFor(c.env.DB, user.business_id)));
});

const setAnsweringSchema = z.object({ enabled: z.boolean() });

answeringApp.post('/agent/answering', async (c) => {
  const user = c.get('user');
  const parsed = await parseJsonBody(c, setAnsweringSchema);
  if (!parsed.success) return parsed.response;
  const base = c.env.PUBLIC_API_BASE_URL || new URL(c.req.url).origin;
  const r = await setAnswering(c.env, user.business_id, parsed.data.enabled, base);
  if (!r.ok) {
    const body = {
      not_configured: { message: 'Call answering is not available yet.', status: 503 },
      no_numbers: { message: 'No answering numbers are free right now. Try again later.', status: 503 },
      sarvam_failed: { message: 'Could not set up call answering. Try again in a minute.', status: 502 },
    }[r.code];
    return c.json({ message: body.message, code: r.code }, body.status as 502 | 503);
  }
  return c.json(answeringView(c.env, r.row));
});

// ------------------------------------------------------------- Sarvam

export const answeringPublicApp = new Hono<{ Bindings: Env }>();

/**
 * On-start hook (an API tool with "When should this tool run?" = on_start on the receptionist agent).
 * Body: { "called": <the number dialled>, "caller": <User Identifier>, "interaction_id": <Interaction ID> }
 * (also accepts Sarvam's agent_phone_number / user_phone_number). Bearer INBOUND_HOOK_SECRET.
 * Always answers 200 with variables, so a lookup problem never leaves the caller in silence.
 */
answeringPublicApp.post('/voice/inbound/start', async (c) => {
  const secret = c.env.INBOUND_HOOK_SECRET;
  const auth = (c.req.header('authorization') || '').replace(/^Bearer\s+/i, '');
  if (!secret || !auth || !timingSafeEqual(auth, secret)) {
    return c.json({ message: 'Unauthorized.', code: 'unauthorized' }, 401);
  }
  const body = await c.req.json<any>().catch(() => ({}));
  const called = body?.called ?? body?.agent_phone_number ?? body?.to;
  const caller = body?.caller ?? body?.user_phone_number ?? body?.user_identifier ?? body?.from;
  return c.json(await inboundCallContext(c.env, called, caller));
});

/** "2026-09-01T18:44:15Z" → "2026-09-01 18:44:15" (D1's UTC format); now when missing or bad. */
function sqlTime(iso: unknown): string {
  const t = typeof iso === 'string' ? Date.parse(iso) : NaN;
  return (Number.isNaN(t) ? new Date() : new Date(t)).toISOString().slice(0, 19).replace('T', ' ');
}

/**
 * Deployment webhook after an answered call. The URL carries the number and
 * HMAC(SARVAM_WEBHOOK_SECRET, "inbound:<number>"), so it authenticates the number, and the number
 * decides the business. The caller becomes (or refreshes) a lead whose basis is their own enquiry;
 * the call is recorded as an inbound call and handed to the outbound result handling.
 */
answeringPublicApp.post('/webhooks/sarvam-inbound', async (c: Context<{ Bindings: Env }>) => {
  const secret = c.env.SARVAM_WEBHOOK_SECRET;
  const number = e164(c.req.query('number'));
  const token = c.req.query('token') || '';
  if (!secret || !number || !timingSafeEqual(token, await inboundWebhookToken(secret, number))) {
    return c.json({ message: 'Invalid webhook token.', code: 'invalid_signature' }, 401);
  }
  const rawBody = await c.req.text();
  let data: any;
  try {
    data = JSON.parse(rawBody);
  } catch {
    return c.json({ message: 'Malformed JSON payload.', code: 'malformed_json' }, 400);
  }
  const dialled = e164(data.agent_phone_number);
  if (dialled && dialled !== number) {
    return c.json({ message: 'Payload is for another number.', code: 'number_mismatch' }, 400);
  }
  const row = await c.env.DB.prepare('SELECT business_id FROM inbound_numbers WHERE phone = ?')
    .bind(number).first<{ business_id: string | null }>();
  const businessId = row?.business_id;
  if (!businessId) return c.json({ message: 'Number is not assigned.', code: 'not_assigned' }, 404);

  const interactionId = String(data.interaction_id || '');
  const callerPhone = normalizePhone(String(data.user_phone_number || ''));
  if (!interactionId || !callerPhone) {
    // Withheld numbers can't become a lead; nothing to record against.
    console.warn(JSON.stringify({ msg: 'inbound_call_without_caller', businessId, interactionId }));
    return c.json({ success: true, ignored: true, reason: 'no_caller' }, 200);
  }

  const vars = data.output_agent_variables || data.final_agent_variables || {};
  const spokenName = typeof vars.caller_name === 'string' ? vars.caller_name.trim().slice(0, 100) : '';

  // A redelivered webhook finds the call it already created and goes through the (idempotent) handler.
  let call = await c.env.DB.prepare('SELECT id, lead_id FROM calls WHERE interaction_id = ? AND business_id = ?')
    .bind(interactionId, businessId).first<{ id: string; lead_id: string }>();
  if (!call) {
    let lead = await c.env.DB.prepare('SELECT id, name FROM leads WHERE business_id = ? AND phone = ?')
      .bind(businessId, callerPhone).first<{ id: string; name: string }>();
    const stmts: D1PreparedStatement[] = [];
    if (lead) {
      // Calling the business is a fresh enquiry. Never overrides an opt-out or do-not-call.
      stmts.push(c.env.DB.prepare(
        `UPDATE leads SET last_enquiry_at = datetime('now'),
           consent = CASE WHEN consent = 'unknown' THEN 'inquiry' ELSE consent END,
           name = CASE WHEN name = 'Caller' AND ? != '' THEN ? ELSE name END,
           updated_at = datetime('now')
         WHERE id = ? AND business_id = ?`
      ).bind(spokenName, spokenName, lead.id, businessId));
    } else {
      lead = { id: `lead_${crypto.randomUUID().slice(0, 12)}`, name: spokenName || 'Caller' };
      stmts.push(c.env.DB.prepare(
        `INSERT INTO leads (id, business_id, name, phone, source, status, consent, timezone, last_enquiry_at, created_at, updated_at)
         VALUES (?, ?, ?, ?, 'inbound_call', 'new', 'inquiry', 'Asia/Kolkata', datetime('now'), datetime('now'), datetime('now'))`
      ).bind(lead.id, businessId, lead.name, callerPhone));
    }
    stmts.push(consentEventStatement(c.env.DB, {
      businessId, leadId: lead.id, consentValue: 'inquiry', source: 'inbound_call',
      textVersion: CONSENT_TEXT_VERSIONS.inbound_call,
    }));
    const callId = `call_${crypto.randomUUID().slice(0, 12)}`;
    stmts.push(c.env.DB.prepare(
      `INSERT INTO calls (id, business_id, lead_id, lead_name, lead_phone, status, interaction_id, direction, started_at, created_at)
       VALUES (?, ?, ?, ?, ?, 'calling', ?, 'inbound', ?, datetime('now'))`
    ).bind(callId, businessId, lead.id, spokenName || lead.name, callerPhone, interactionId, sqlTime(data.start_datetime)));
    try {
      await c.env.DB.batch(stmts);
    } catch (err: any) {
      // A concurrent delivery of the same call won the insert: use its row.
      if (!/UNIQUE constraint failed/i.test(String(err?.message ?? err))) throw err;
    }
    call = await c.env.DB.prepare('SELECT id, lead_id FROM calls WHERE interaction_id = ? AND business_id = ?')
      .bind(interactionId, businessId).first<{ id: string; lead_id: string }>();
    if (!call) throw new Error('inbound_call_row_missing');
  }

  // Same scoring, transcript, billing, opt-out, follow-up and callback handling as an outbound call.
  // An answered call has no status in this payload: any talk time means it connected.
  const duration = Number(data.duration ?? 0);
  const forwarded = { ...data, status: duration > 0 ? 'connected' : 'no_answer' };
  let ctx: any;
  try { ctx = c.executionCtx; } catch {}
  const res = await voiceApp.fetch(new Request(
    `http://internal/webhooks/sarvam?call_id=${call.id}&token=${await sarvamWebhookToken(secret, call.id)}`,
    { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(forwarded) },
  ), c.env, ctx);
  const result = await res.json<any>().catch(() => ({}));

  // Tell the owner once per call (a duplicate delivery stops at the handler's idempotency claim).
  if (res.ok && !result?.duplicate) {
    const done = await c.env.DB.prepare('SELECT lead_name, summary FROM calls WHERE id = ?').bind(call.id).first<{ lead_name: string; summary: string | null }>();
    const lang = await ownerLanguage(c.env, businessId);
    const name = done?.lead_name && done.lead_name !== 'Caller' ? done.lead_name : `+${callerPhone}`;
    const title = lang === 'hi' ? `AI ने ${name} की कॉल उठाई` : lang === 'bn' ? `AI ${name}-এর কল ধরেছে` : `Your AI answered ${name}`;
    const body = (done?.summary || '').slice(0, 160)
      || (lang === 'hi' ? 'कॉल का नतीजा देखें।' : lang === 'bn' ? 'কলের ফলাফল দেখুন।' : 'See what they wanted.');
    const route = `/calls/${call.id}/result`;
    await c.env.DB.prepare(
      `INSERT INTO notifications (id, business_id, type, title, body, route, action_label, is_read, created_at)
       VALUES (?, ?, 'inbound_call', ?, ?, ?, ?, 0, datetime('now'))`
    ).bind(`notif_${crypto.randomUUID().slice(0, 12)}`, businessId, title, body, route,
      lang === 'hi' ? 'देखें' : lang === 'bn' ? 'দেখুন' : 'View').run();
    const push = sendBusinessPushNotification(c.env, businessId, { type: 'inbound_call', title, body, route })
      .catch((err) => console.error(JSON.stringify({ msg: 'inbound_push_failed', error: err?.message })));
    if (ctx) ctx.waitUntil(push);
    else await push;
  }
  return c.json({ ...result, call_id: call.id, direction: 'inbound' }, res.status as 200);
});
