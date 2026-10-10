/**
 * Public opt-out page: GET/POST /stop.
 *
 * Anyone can enter a phone number to stop calls from EVERY business on CallPilot (global_dnc).
 * Same look and rules as the legal pages: server-rendered HTML, no scripts, strict CSP (the form
 * may only post back here). English, Hindi or Bengali (?lang, else Accept-Language). Rate limited per IP. The response never says whether the number was
 * already on the list.
 */
import { Hono } from 'hono';
import type { Context } from 'hono';
import { Env } from '../types';
import { page, legalVars, escapeHtml, LegalVars } from './legal';
import { hitRateLimit } from '../utils/rate_limit';
import { addToGlobalDnc, canonicalPhone, globalDncSecret } from '../services/global_dnc';
import { hashIp, clientIp } from '../services/consent';
import { PageLang, resolvePageLang, withLang, languageSwitcher } from '../services/page_lang';
import { STOP_STRINGS } from '../services/public_page_strings';

/** Like LEGAL_CSP, but the form may post to this origin. */
export const STOP_CSP = "default-src 'none'; style-src 'unsafe-inline'; img-src 'self' data:; base-uri 'none'; form-action 'self'; frame-ancestors 'none'";

/** Submissions per IP per hour. */
export const STOP_RATE_LIMIT = 10;
const STOP_RATE_WINDOW_SECONDS = 3600;
const MAX_PHONE_INPUT = 32;

type StopState = { kind: 'form'; error?: string; value?: string } | { kind: 'done' } | { kind: 'limited' } | { kind: 'unavailable' };

/** The opt-out page in `lang` (English by default). The form posts back with the same language. */
export function stopPage(v: LegalVars, state: StopState, lang: PageLang = 'en'): string {
  const t = STOP_STRINGS[lang];
  let body: string;
  if (state.kind === 'done') {
    body = t.doneHtml(v.email);
  } else if (state.kind === 'limited') {
    body = `<p class="notice" role="alert">${t.limitedHtml(v.email)}</p>`;
  } else if (state.kind === 'unavailable') {
    body = `<p class="notice" role="alert">${t.unavailableHtml(v.email)}</p>`;
  } else {
    body = `${state.error ? `<p class="notice" role="alert">${escapeHtml(state.error)}</p>` : ''}
<form method="post" action="${withLang('/stop', lang)}">
  <label for="phone">${t.phoneLabel}</label>
  <input id="phone" name="phone" type="tel" inputmode="tel" autocomplete="tel" maxlength="${MAX_PHONE_INPUT}" required placeholder="98765 43210" value="${escapeHtml(state.value ?? '')}">
  <button type="submit">${t.submit}</button>
</form>
<p>${t.hint}</p>`;
  }
  return page(t.title, v, `
${languageSwitcher('/stop', lang, t.languageLabel)}
<h1>${t.heading}</h1>
<p class="lede">${t.ledeHtml}</p>
${body}
<h2>${t.otherWays}</h2>
<ul>
  <li>${t.inCallTip}</li>
  <li>${t.dndTipHtml}</li>
</ul>
<p>${t.privacyHtml}</p>
`, lang);
}

/** ?lang, then the browser's Accept-Language, then English (no business default on this page). */
export function stopLang(c: Context): PageLang {
  return resolvePageLang({ query: c.req.query('lang'), acceptLanguage: c.req.header('accept-language') });
}

function send(c: Context<{ Bindings: Env }>, html: string, status: 200 | 400 | 429 | 503 = 200, lang: PageLang = 'en') {
  c.header('Content-Security-Policy', STOP_CSP);
  c.header('Content-Language', lang);
  c.header('Vary', 'Accept-Language');
  c.header('Cache-Control', 'no-store');
  c.header('X-Robots-Tag', 'noindex');
  return c.html(html, status);
}

const stopApp = new Hono<{ Bindings: Env }>();

stopApp.get('/', (c) => {
  const lang = stopLang(c);
  return send(c, stopPage(legalVars(c.env), { kind: 'form' }, lang), 200, lang);
});

stopApp.post('/', async (c) => {
  const v = legalVars(c.env);
  const lang = stopLang(c);
  const secret = globalDncSecret(c.env);
  if (!secret) {
    console.error(JSON.stringify({ msg: 'global_dnc_secret_missing', where: 'stop_page' }));
    return send(c, stopPage(v, { kind: 'unavailable' }, lang), 503, lang);
  }

  // Rate limit before parsing: bucket keyed by a hash of the IP, never the IP itself.
  const ipKey = (await hashIp(c.env, clientIp(c))) ?? 'unknown';
  const limit = await hitRateLimit(c.env.DB, `stop:ip:${ipKey}`, STOP_RATE_LIMIT, STOP_RATE_WINDOW_SECONDS);
  if (!limit.allowed) {
    c.header('Retry-After', String(limit.retryAfter));
    return send(c, stopPage(v, { kind: 'limited' }, lang), 429, lang);
  }

  let raw = '';
  try {
    const form = await c.req.parseBody();
    raw = typeof form.phone === 'string' ? form.phone : '';
  } catch {
    raw = '';
  }
  raw = raw.slice(0, MAX_PHONE_INPUT);
  if (!canonicalPhone(raw)) {
    return send(c, stopPage(v, { kind: 'form', error: STOP_STRINGS[lang].errPhone, value: raw }, lang), 400, lang);
  }
  await addToGlobalDnc(c.env.DB, secret, raw, 'web');
  console.log(JSON.stringify({ msg: 'global_dnc_added', source: 'web' }));
  return send(c, stopPage(v, { kind: 'done' }, lang), 200, lang);
});

export { stopApp };
