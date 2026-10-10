/**
 * Public speed-to-lead endpoints (no owner auth):
 *   GET  /f/:slug             hosted enquiry form, branded with the business name
 *   POST /f/:slug             form submit -> lead (consent 'explicit_opt_in', source 'form') + instant AI call
 *   POST /hooks/leads/:slug   JSON webhook, `Authorization: Bearer <token>` -> same, source 'webhook'
 *
 * Pages are in English, Hindi or Bengali (?lang, else the employee's first language, else
 * Accept-Language; services/page_lang.ts), with small language links.
 * The form page runs no script and loads nothing external (strict CSP, like routes/legal.ts).
 * Spam: hidden honeypot field, per-IP and per-form rate limits, phone validation, 24h phone dedupe.
 */
import { ensureReferralCode, referralLink } from '../services/referrals';
import { hashIp, formConsentTextVersion } from '../services/consent';
import { PageLang, resolvePageLang, businessPageLang, languageSwitcher, withLang } from '../services/page_lang';
import { FORM_STRINGS } from '../services/public_page_strings';
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

function shell(title: string, body: string, poweredHref = '/get', lang: PageLang = 'en'): string {
  const t = FORM_STRINGS[lang];
  return `<!doctype html>
<html lang="${lang}">
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
  body { margin: 0; background: var(--bg); color: var(--ink); font: 16px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Noto Sans", "Noto Sans Devanagari", "Noto Sans Bengali", sans-serif; }
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
  .langs { color: var(--soft); font-size: 0.9rem; text-align: right; margin: 0 0 12px; }
  .langs a { color: var(--accent); padding: 4px 2px; }
  footer { color: var(--soft); font-size: 0.85rem; margin-top: 20px; text-align: center; }
  footer a { color: var(--soft); }
</style>
</head>
<body>
<main>
${body}
<footer><a href="${escapeHtml(poweredHref)}">${t.poweredBy}</a> · <a href="/legal/privacy">${t.privacy}</a></footer>
</main>
</body>
</html>`;
}

/** The consent sentence shown next to the checkbox, in the page language (plain text, not escaped). */
export function consentText(business: string, lang: PageLang = 'en'): string {
  return FORM_STRINGS[lang].consent(business);
}

export interface FormValues { name?: string; phone?: string; interest?: string; consent?: boolean }

export function formPage(business: string, slug: string, values: FormValues = {}, error?: string, poweredHref?: string, lang: PageLang = 'en'): string {
  const t = FORM_STRINGS[lang];
  const b = escapeHtml(business);
  const v = (s?: string) => escapeHtml(s ?? '');
  const path = `/f/${slug}`;
  return shell(`${t.enquireTitle} · ${b}`, `
${languageSwitcher(path, lang, t.languageLabel)}
<div class="card">
  <h1>${b}</h1>
  <p class="lede">${t.lede}</p>
  ${error ? `<p class="error" role="alert">${escapeHtml(error)}</p>` : ''}
  <form method="post" action="${escapeHtml(withLang(path, lang))}" accept-charset="utf-8">
    <label for="name">${t.nameLabel}</label>
    <input id="name" name="name" type="text" autocomplete="name" maxlength="${LEAD_NAME_MAX}" required value="${v(values.name)}">
    <label for="phone">${t.phoneLabel}</label>
    <input id="phone" name="phone" type="tel" inputmode="tel" autocomplete="tel" maxlength="20" required value="${v(values.phone ?? '+91 ')}">
    <label for="interest">${t.interestLabel} <span class="opt">${t.optional}</span></label>
    <textarea id="interest" name="interest" maxlength="${LEAD_INTEREST_MAX}">${v(values.interest)}</textarea>
    <div class="hp" aria-hidden="true">
      <label for="${HONEYPOT_FIELD}">${t.honeypotLabel}</label>
      <input id="${HONEYPOT_FIELD}" name="${HONEYPOT_FIELD}" type="text" tabindex="-1" autocomplete="off">
    </div>
    <label class="consent"><input type="checkbox" name="consent" value="yes" required${values.consent ? ' checked' : ''}><span>${escapeHtml(consentText(business, lang))}</span></label>
    <button type="submit">${t.submit}</button>
  </form>
</div>`, poweredHref, lang);
}

export function thankYouPage(business: string, name: string, autoCall: boolean, poweredHref?: string, lang: PageLang = 'en'): string {
  const t = FORM_STRINGS[lang];
  const b = escapeHtml(business);
  const first = escapeHtml(name.trim().split(/\s+/)[0] || '');
  return shell(`${t.thankYouTitle} · ${b}`, `
<div class="card">
  <h1>${t.thankYou(first)}</h1>
  <p class="lede">${autoCall ? t.willCall(b) : t.willContact(b)}</p>
</div>`, poweredHref, lang);
}

/** Plain message page. With `switcherPath`, also shows the language links for that path. */
export function messagePage(title: string, message: string, lang: PageLang = 'en', switcherPath?: string): string {
  return shell(escapeHtml(title), `
${switcherPath ? languageSwitcher(switcherPath, lang, FORM_STRINGS[lang].languageLabel) : ''}
<div class="card">
  <h1>${escapeHtml(title)}</h1>
  <p class="lede">${escapeHtml(message)}</p>
</div>`, undefined, lang);
}

function sendHtml(c: Context, html: string, status: 200 | 400 | 404 | 413 | 429 = 200, lang: PageLang = 'en') {
  c.header('Content-Security-Policy', FORM_CSP);
  c.header('Cache-Control', 'no-store');
  c.header('X-Robots-Tag', 'noindex, nofollow');
  c.header('Content-Language', lang);
  c.header('Vary', 'Accept-Language');
  return c.html(html, status);
}

/** "Powered by CallPilot" link carrying the business's referral code; plain landing link on any error. */
async function poweredHrefFor(env: Env, businessId: string): Promise<string> {
  try {
    return referralLink(await ensureReferralCode(env, businessId));
  } catch {
    return referralLink(null);
  }
}

/** The business's default page language: its AI employee's first language, if we render it. */
async function businessDefaultLang(db: D1Database, businessId: string): Promise<PageLang | null> {
  const row = await db.prepare('SELECT languages FROM agents WHERE business_id = ? ORDER BY created_at LIMIT 1')
    .bind(businessId).first<{ languages: string | null }>();
  return businessPageLang(row?.languages);
}

interface FormContext { source: LeadSourceRow; business: string; lang: PageLang }

/** The active form, its business and the page language; `lang` alone when the form is not available. */
async function formContext(c: Context<{ Bindings: Env }>): Promise<FormContext | { lang: PageLang }> {
  const fallback = () => resolvePageLang({ query: c.req.query('lang'), acceptLanguage: c.req.header('accept-language') });
  const source = await findActiveSource(c.env.DB, c.req.param('slug') ?? '', 'form');
  if (!source) return { lang: fallback() };
  const business = await businessName(c.env.DB, source.business_id);
  if (!business) return { lang: fallback() };
  const lang = resolvePageLang({
    query: c.req.query('lang'),
    businessDefault: await businessDefaultLang(c.env.DB, source.business_id),
    acceptLanguage: c.req.header('accept-language'),
  });
  return { source, business, lang };
}

function notFound(c: Context, lang: PageLang) {
  const t = FORM_STRINGS[lang];
  // Language links only when the slug looks like one of ours (never echo arbitrary paths).
  const slug = c.req.param('slug') ?? '';
  const path = /^[A-Za-z0-9]{8,64}$/.test(slug) ? `/f/${slug}` : undefined;
  return sendHtml(c, messagePage(t.notFoundTitle, t.notFoundMessage, lang, path), 404, lang);
}

// ------------------------------------------------------------------ form

leadCapturePublicApp.get('/f/:slug', async (c) => {
  const ctx = await formContext(c);
  if (!('source' in ctx)) return notFound(c, ctx.lang);
  return sendHtml(c, formPage(ctx.business, ctx.source.public_slug, {}, undefined, await poweredHrefFor(c.env, ctx.source.business_id), ctx.lang), 200, ctx.lang);
});

leadCapturePublicApp.post('/f/:slug', async (c) => {
  const ctx = await formContext(c);
  if (!('source' in ctx)) return notFound(c, ctx.lang);
  const { source, business, lang } = ctx;
  const t = FORM_STRINGS[lang];

  if (Number(c.req.header('content-length') ?? 0) > MAX_FORM_BYTES) {
    return sendHtml(c, messagePage(t.tooLongTitle, t.tooLongMessage, lang), 413, lang);
  }

  const ip = await ipKey(c);
  const perIp = await hitRateLimit(c.env.DB, `leadform:${source.public_slug}:ip:${ip}`, FORM_LIMIT_PER_IP.limit, FORM_LIMIT_PER_IP.windowSeconds);
  const perSlug = perIp.allowed
    ? await hitRateLimit(c.env.DB, `leadform:${source.public_slug}`, FORM_LIMIT_PER_SLUG.limit, FORM_LIMIT_PER_SLUG.windowSeconds)
    : perIp;
  if (!perIp.allowed || !perSlug.allowed) {
    c.header('Retry-After', String(perIp.allowed ? perSlug.retryAfter : perIp.retryAfter));
    return sendHtml(c, messagePage(t.waitTitle, t.waitMessage, lang), 429, lang);
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
    return sendHtml(c, thankYouPage(business, values.name ?? '', source.auto_call === 1, undefined, lang), 200, lang);
  }

  const invalid = (msg: string) => sendHtml(c, formPage(business, source.public_slug, values, msg, undefined, lang), 400, lang);
  if (!values.name) return invalid(t.errName);
  if (!values.phone || values.phone.replace(/\D/g, '').length < 8) return invalid(t.errPhone);
  if (!values.consent) return invalid(t.errConsent);

  const result = await captureLead(c.env, source, {
    name: values.name, phone: values.phone, interest: values.interest || null,
  }, {
    fallbackBaseUrl: new URL(c.req.url).origin,
    waitUntil: waitUntilOf(c),
    ipHash: await hashIp(c.env, clientIp(c) === 'unknown' ? null : clientIp(c)),
    // Evidence names the wording the person saw: the consent sentence in this page's language.
    consentTextVersion: formConsentTextVersion(lang),
  });
  if (result.status === 'invalid_phone') return invalid(t.errPhone);

  // Duplicates get the same page: never reveal whether a number is already known.
  return sendHtml(c, thankYouPage(business, values.name, source.auto_call === 1, await poweredHrefFor(c.env, source.business_id), lang), 200, lang);
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
