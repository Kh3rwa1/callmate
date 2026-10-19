/**
 * Business numbers and the AI answering them (services/business_numbers.ts, services/answering.ts).
 *
 * Owner (signed in):
 *   GET  /business-number          → { available, entitled, number, numbers_free, requested }
 *   POST /business-number {phone}  → rent that free number (paid plans; chosen once)
 *   POST /business-number/request  → none free: ask for one; it arrives when the operator adds one
 *   GET  /agent/answering          → { available, enabled, phone, mode, has_number }
 *   POST /agent/answering {enabled, mode} → how the owner's own phone forwards to the business number
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
import { inboundCallContext, setForwardMode } from '../services/answering';
import {
  availableNumbers, BusinessNumberRow, businessNumberFor, e164, inboundWebhookToken, numberEntitled,
  numberRequested, numbersConfigured, rentNumber, requestNumber, NUMBER_HOLD_DAYS,
} from '../services/business_numbers';
import { consentEventStatement, CONSENT_TEXT_VERSIONS } from '../services/consent';
import { ownerLanguage } from '../services/owner_text';
import { sendBusinessPushNotification } from '../services/fcm';
import { voiceApp } from './voice';

type AuthedEnv = { Bindings: Env; Variables: { user: AuthUser } };

// ------------------------------------------------------------- owner

export const answeringApp = new Hono<AuthedEnv>();

function numberView(row: BusinessNumberRow | null) {
  return row && row.status !== 'free'
    ? { phone: row.phone, status: row.status, held_until: row.held_until, since: row.assigned_at }
    : null;
}

async function businessNumberView(env: Env, businessId: string) {
  const [row, entitled, requested] = await Promise.all([
    businessNumberFor(env.DB, businessId),
    numberEntitled(env.DB, businessId),
    numberRequested(env.DB, businessId),
  ]);
  const available = numbersConfigured(env);
  return {
    available,
    entitled,
    hold_days: NUMBER_HOLD_DAYS,
    number: numberView(row),
    // The picker: only for a business that may rent one and doesn't have one yet.
    numbers_free: available && entitled && !row ? await availableNumbers(env) : [],
    // Asked for one while none was free; it arrives on its own.
    requested: !row && requested,
  };
}

answeringApp.get('/business-number', async (c) => c.json(await businessNumberView(c.env, c.get('user').business_id)));

answeringApp.post('/business-number/request', async (c) => {
  const user = c.get('user');
  const r = await requestNumber(c.env, user.business_id);
  if (!r.ok) {
    const body = {
      not_configured: { message: 'Business numbers are not available yet.', status: 503 },
      not_entitled: { message: 'A business number comes with a paid plan.', status: 402 },
      already_has_number: { message: 'Your business already has a number.', status: 409 },
    }[r.code];
    return c.json({ message: body.message, code: r.code }, body.status as 402 | 409 | 503);
  }
  return c.json(await businessNumberView(c.env, user.business_id));
});

const rentSchema = z.object({ phone: z.string().min(8).max(20) });

answeringApp.post('/business-number', async (c) => {
  const user = c.get('user');
  const parsed = await parseJsonBody(c, rentSchema);
  if (!parsed.success) return parsed.response;
  const base = c.env.PUBLIC_API_BASE_URL || new URL(c.req.url).origin;
  const r = await rentNumber(c.env, user.business_id, parsed.data.phone, base);
  if (!r.ok) {
    const body = {
      not_configured: { message: 'Business numbers are not available yet.', status: 503 },
      not_entitled: { message: 'A business number comes with a paid plan.', status: 402 },
      already_has_number: { message: 'Your business already has a number.', status: 409 },
      number_taken: { message: 'That number was just taken. Pick another one.', status: 409 },
      sarvam_failed: { message: 'Could not set up the number. Try again in a minute.', status: 502 },
    }[r.code];
    return c.json({ message: body.message, code: r.code }, body.status as 402 | 409 | 502 | 503);
  }
  return c.json({ number: numberView(r.row) });
});

function answeringView(env: Env, row: BusinessNumberRow | null) {
  const active = row?.status === 'active';
  return {
    available: numbersConfigured(env),
    has_number: active,
    enabled: active && row!.forward_mode !== 'off',
    phone: active ? row!.phone : null,
    mode: row?.forward_mode === 'all' ? 'all' : 'missed',
  };
}

answeringApp.get('/agent/answering', async (c) => {
  const user = c.get('user');
  return c.json(answeringView(c.env, await businessNumberFor(c.env.DB, user.business_id)));
});

const setAnsweringSchema = z.object({ enabled: z.boolean(), mode: z.enum(['all', 'missed']).optional() });

answeringApp.post('/agent/answering', async (c) => {
  const user = c.get('user');
  const parsed = await parseJsonBody(c, setAnsweringSchema);
  if (!parsed.success) return parsed.response;
  const mode = parsed.data.enabled ? (parsed.data.mode ?? 'missed') : 'off';
  const r = await setForwardMode(c.env, user.business_id, mode);
  if (!r.ok) {
    return c.json({ message: 'Get your business number first.', code: 'no_business_number' }, 409);
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
  // Each number's agent names its number in the hook URL (the hook can't see the dialled number).
  const called = c.req.query('number') ?? body?.called ?? body?.agent_phone_number ?? body?.to;
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
  const row = await c.env.DB.prepare('SELECT business_id FROM business_numbers WHERE phone = ?')
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
