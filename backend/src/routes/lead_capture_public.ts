/**
 * Public speed-to-lead endpoints (no owner auth):
 *   GET  /f/:slug             hosted enquiry form, branded with the business name
 *   POST /f/:slug             form submit -> lead (consent 'explicit_opt_in', source 'form') + instant AI call
 *   POST /hooks/leads/:slug   JSON webhook, `Authorization: Bearer <token>` -> same, source 'webhook'
 *
 * The form page runs no script and loads nothing external (strict CSP, like routes/legal.ts).
 * Spam: hidden honeypot field, per-IP and per-form rate limits, phone validation, 24h phone dedupe.
 */
import { Hono } from 'hono';
import type { Context } from 'hono';
import { Env } from '../types';
import { escapeHtml } from './legal';
import { hitRateLimit } from '../utils/rate_limit';
import { leadWebhookSchema, parseData, LEAD_NAME_MAX, LEAD_INTEREST_MAX } from '../schemas/validation';
import { captureLead, findActiveSource, sha256Hex, verifyWebhookToken, LeadSourceRow } from '../services/lead_capture';

// No script at all; the form may only post back to this origin.
export const FORM_CSP = "default-src 'none'; style-src 'unsafe-inline'; img-src 'self' data:; base-uri 'none'; form-action 'self'; frame-ancestors 'none'";

/** Rate limits (sliding windows, utils/rate_limit.ts). */
export const FORM_LIMIT_PER_IP = { limit: 5, windowSeconds: 600 };
export const FORM_LIMIT_PER_SLUG = { limit: 300, windowSeconds: 3600 };
export const HOOK_LIMIT_PER_IP = { limit: 300, windowSeconds: 3600 };
export const HOOK_LIMIT_PER_SLUG = { limit: 600, windowSeconds: 3600 };

/** Hidden field real people never fill. */
export const HONEYPOT_FIELD = 'company_website';
const MAX_FORM_BYTES = 8 * 1024;

const leadCapturePublicApp = new Hono<{ Bindings: Env }>();

function clientIp(c: Context): string {
  return c.req.header('cf-connecting-ip') || c.req.header('x-real-ip') || 'unknown';
}

/** Rate-limit buckets never hold a raw IP. */
async function ipKey(c: Context): Promise<string> {
  return (await sha256Hex(`lead-capture:${clientIp(c)}`)).slice(0, 24);
}

function waitUntilOf(c: Context): ((p: Promise<unknown>) => void) | undefined {
  try {
    const ctx = c.executionCtx;
    return (p) => ctx.waitUntil(p);
  } catch {
    return undefined;
  }
}

async function businessName(db: D1Database, businessId: string): Promise<string | null> {
  const row = await db.prepare('SELECT name FROM businesses WHERE id = ?').bind(businessId).first<{ name: string }>();
  return row?.name ?? null;
}

// ------------------------------------------------------------------ HTML

function shell(title: string, body: string): string {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<meta name="referrer" content="no-referrer">
<title>${title}</title>
<style>
  :root { color-scheme: light dark; --ink: #1d1d1f; --soft: #5c5c66; --bg: #f6f6f9; --card: #ffffff; --line: #dcdce3; --accent: #3a5bd9; --on-accent: #ffffff; --error: #b3261e; --error-bg: #fdecea; }
  @media (prefers-color-scheme: dark) { :root { --ink: #f2f2f5; --soft: #a8a8b3; --bg: #121214; --card: #1c1c20; --line: #34343b; --accent: #8fa6ff; --on-accent: #0d1430; --error: #ffb4ab; --error-bg: #3a1714; } }
  * { box-sizing: border-box; }
  body { margin: 0; background: var(--bg); color: var(--ink); font: 16px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Noto Sans", sans-serif; }
  main { max-width: 480px; margin: 0 auto; padding: 24px 16px 40px; }
  .card { background: var(--card); border: 1px solid var(--line); border-radius: 16px; padding: 20px 16px; }
  h1 { font-size: 1.4rem; line-height: 1.3; margin: 0 0 4px; overflow-wrap: anywhere; }
  .lede { color: var(--soft); margin: 0 0 20px; }
  label { display: block; font-weight: 600; margin: 16px 0 6px; }
  .opt { color: var(--soft); font-weight: 400; }
  input[type=text], input[type=tel], textarea { width: 100%; font: inherit; color: var(--ink); background: transparent; border: 1px solid var(--line); border-radius: 10px; padding: 12px; }
  textarea { min-height: 88px; resize: vertical; }
  input:focus, textarea:focus { outline: 2px solid var(--accent); outline-offset: 1px; }
  .consent { display: flex; gap: 10px; align-items: flex-start; font-weight: 400; margin-top: 20px; }
  .consent input { width: 20px; height: 20px; margin: 2px 0 0; flex: none; accent-color: var(--accent); }
  button { width: 100%; margin-top: 22px; font: inherit; font-weight: 600; color: var(--on-accent); background: var(--accent); border: 0; border-radius: 12px; padding: 14px; cursor: pointer; }
  .error { color: var(--error); background: var(--error-bg); border-radius: 10px; padding: 10px 12px; margin: 0 0 8px; }
  .hp { position: absolute; left: -10000px; width: 1px; height: 1px; overflow: hidden; }
  footer { color: var(--soft); font-size: 0.85rem; margin-top: 20px; text-align: center; }
  footer a { color: var(--soft); }
</style>
</head>
<body>
<main>
${body}
<footer>Powered by CallPilot · <a href="/legal/privacy">Privacy</a></footer>
</main>
</body>
</html>`;
}

export function consentText(business: string): string {
  return `I agree to receive a call from ${business} about my enquiry (may be an automated AI call).`;
}

export interface FormValues { name?: string; phone?: string; interest?: string; consent?: boolean }

export function formPage(business: string, slug: string, values: FormValues = {}, error?: string): string {
  const b = escapeHtml(business);
  const v = (s?: string) => escapeHtml(s ?? '');
  return shell(`Enquire · ${b}`, `
<div class="card">
  <h1>${b}</h1>
  <p class="lede">Leave your details and we’ll call you back in about a minute.</p>
  ${error ? `<p class="error" role="alert">${escapeHtml(error)}</p>` : ''}
  <form method="post" action="/f/${escapeHtml(slug)}" accept-charset="utf-8">
    <label for="name">Your name</label>
    <input id="name" name="name" type="text" autocomplete="name" maxlength="${LEAD_NAME_MAX}" required value="${v(values.name)}">
    <label for="phone">Mobile number</label>
    <input id="phone" name="phone" type="tel" inputmode="tel" autocomplete="tel" maxlength="20" required value="${v(values.phone ?? '+91 ')}">
    <label for="interest">What are you interested in? <span class="opt">(optional)</span></label>
    <textarea id="interest" name="interest" maxlength="${LEAD_INTEREST_MAX}">${v(values.interest)}</textarea>
    <div class="hp" aria-hidden="true">
      <label for="${HONEYPOT_FIELD}">Leave this empty</label>
      <input id="${HONEYPOT_FIELD}" name="${HONEYPOT_FIELD}" type="text" tabindex="-1" autocomplete="off">
    </div>
    <label class="consent"><input type="checkbox" name="consent" value="yes" required${values.consent ? ' checked' : ''}><span>${escapeHtml(consentText(business))}</span></label>
    <button type="submit">Request a call</button>
  </form>
</div>`);
}

export function thankYouPage(business: string, name: string, autoCall: boolean): string {
  const b = escapeHtml(business);
  const first = escapeHtml(name.trim().split(/\s+/)[0] || '');
  return shell(`Thank you · ${b}`, `
<div class="card">
  <h1>Thank you${first ? `, ${first}` : ''}!</h1>
  <p class="lede">${autoCall
    ? `${b} will call you in about a minute, or when their calling hours start. The call may be from an AI assistant.`
    : `${b} has your enquiry and will get in touch soon.`}</p>
</div>`);
}

export function messagePage(title: string, message: string): string {
  return shell(escapeHtml(title), `
<div class="card">
  <h1>${escapeHtml(title)}</h1>
  <p class="lede">${escapeHtml(message)}</p>
</div>`);
}

function sendHtml(c: Context, html: string, status: 200 | 400 | 404 | 413 | 429 = 200) {
  c.header('Content-Security-Policy', FORM_CSP);
  c.header('Cache-Control', 'no-store');
  c.header('X-Robots-Tag', 'noindex, nofollow');
  return c.html(html, status);
}

const NOT_FOUND_TITLE = 'Form not available';
const NOT_FOUND_MESSAGE = 'This enquiry form is no longer available. Please contact the business directly.';

async function formContext(c: Context<{ Bindings: Env }>): Promise<{ source: LeadSourceRow; business: string } | null> {
  const source = await findActiveSource(c.env.DB, c.req.param('slug') ?? '', 'form');
  if (!source) return null;
  const business = await businessName(c.env.DB, source.business_id);
  return business ? { source, business } : null;
}

// ------------------------------------------------------------------ form

leadCapturePublicApp.get('/f/:slug', async (c) => {
  const ctx = await formContext(c);
  if (!ctx) return sendHtml(c, messagePage(NOT_FOUND_TITLE, NOT_FOUND_MESSAGE), 404);
  return sendHtml(c, formPage(ctx.business, ctx.source.public_slug));
});

leadCapturePublicApp.post('/f/:slug', async (c) => {
  const ctx = await formContext(c);
  if (!ctx) return sendHtml(c, messagePage(NOT_FOUND_TITLE, NOT_FOUND_MESSAGE), 404);
  const { source, business } = ctx;

  if (Number(c.req.header('content-length') ?? 0) > MAX_FORM_BYTES) {
    return sendHtml(c, messagePage('Too long', 'Please shorten your message and try again.'), 413);
  }

  const ip = await ipKey(c);
  const perIp = await hitRateLimit(c.env.DB, `leadform:${source.public_slug}:ip:${ip}`, FORM_LIMIT_PER_IP.limit, FORM_LIMIT_PER_IP.windowSeconds);
  const perSlug = perIp.allowed
    ? await hitRateLimit(c.env.DB, `leadform:${source.public_slug}`, FORM_LIMIT_PER_SLUG.limit, FORM_LIMIT_PER_SLUG.windowSeconds)
    : perIp;
  if (!perIp.allowed || !perSlug.allowed) {
    c.header('Retry-After', String(perIp.allowed ? perSlug.retryAfter : perIp.retryAfter));
    return sendHtml(c, messagePage('Please wait', 'Too many enquiries were sent from here. Please try again in a few minutes.'), 429);
  }

  let body: Record<string, unknown>;
  try {
    body = await c.req.parseBody();
  } catch {
    body = {};
  }
  const str = (k: string) => (typeof body[k] === 'string' ? (body[k] as string) : '');
  const values: FormValues = {
    name: str('name').trim().slice(0, LEAD_NAME_MAX),
    phone: str('phone').trim().slice(0, 20),
    interest: str('interest').trim().slice(0, LEAD_INTEREST_MAX),
    consent: ['yes', 'on', 'true', '1'].includes(str('consent').toLowerCase()),
  };

  // Bots fill every field: pretend it worked, create nothing.
  if (str(HONEYPOT_FIELD).trim() !== '') {
    return sendHtml(c, thankYouPage(business, values.name ?? '', source.auto_call === 1));
  }

  const invalid = (msg: string) => sendHtml(c, formPage(business, source.public_slug, values, msg), 400);
  if (!values.name) return invalid('Please enter your name.');
  if (!values.phone || values.phone.replace(/\D/g, '').length < 8) return invalid('Please enter a valid mobile number.');
  if (!values.consent) return invalid('Please tick the box to agree to receive a call.');

  const result = await captureLead(c.env, source, {
    name: values.name, phone: values.phone, interest: values.interest || null,
  }, { fallbackBaseUrl: new URL(c.req.url).origin, waitUntil: waitUntilOf(c) });
  if (result.status === 'invalid_phone') return invalid('Please enter a valid mobile number.');

  // Duplicates get the same page: never reveal whether a number is already known.
  return sendHtml(c, thankYouPage(business, values.name, source.auto_call === 1));
});

// ------------------------------------------------------------------ webhook

leadCapturePublicApp.post('/hooks/leads/:slug', async (c) => {
  const unauthorized = () => c.json({ message: 'Invalid or revoked webhook token.', code: 'unauthorized' }, 401);

  const ipLimit = await hitRateLimit(c.env.DB, `leadhook:ip:${await ipKey(c)}`, HOOK_LIMIT_PER_IP.limit, HOOK_LIMIT_PER_IP.windowSeconds);
  if (!ipLimit.allowed) {
    c.header('Retry-After', String(ipLimit.retryAfter));
    return c.json({ message: 'Too many requests.', code: 'rate_limited' }, 429);
  }

  const source = await findActiveSource(c.env.DB, c.req.param('slug') ?? '', 'webhook');
  const token = c.req.header('authorization')?.replace(/^Bearer\s+/i, '').trim();
  // Unknown and revoked slugs look the same as a wrong token.
  if (!source || !(await verifyWebhookToken(token, source.secret_hash))) return unauthorized();

  const slugLimit = await hitRateLimit(c.env.DB, `leadhook:${source.public_slug}`, HOOK_LIMIT_PER_SLUG.limit, HOOK_LIMIT_PER_SLUG.windowSeconds);
  if (!slugLimit.allowed) {
    c.header('Retry-After', String(slugLimit.retryAfter));
    return c.json({ message: 'Too many requests.', code: 'rate_limited' }, 429);
  }

  let raw: unknown;
  try {
    raw = await c.req.json();
  } catch {
    return c.json({ message: 'Malformed JSON payload.', code: 'invalid_json' }, 400);
  }
  const parsed = parseData(c, leadWebhookSchema, raw);
  if (!parsed.success) return parsed.response;

  const result = await captureLead(c.env, source, {
    name: parsed.data.name, phone: parsed.data.phone, interest: parsed.data.interest ?? null,
  }, { fallbackBaseUrl: new URL(c.req.url).origin, waitUntil: waitUntilOf(c) });

  if (result.status === 'invalid_phone') {
    return c.json({ message: 'Invalid phone number format.', code: 'invalid_phone' }, 400);
  }
  return c.json({
    lead_id: result.leadId,
    status: result.status,
    auto_call: result.autoCall && result.status !== 'duplicate',
  }, result.status === 'created' ? 201 : 200);
});

export { leadCapturePublicApp };
