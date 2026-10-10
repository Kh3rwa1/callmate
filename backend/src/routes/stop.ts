/**
 * Public opt-out page: GET/POST /stop.
 *
 * Anyone can enter a phone number to stop calls from EVERY business on CallPilot (global_dnc).
 * Same look and rules as the legal pages: server-rendered HTML, no scripts, strict CSP (the form
 * may only post back here). Rate limited per IP. The response never says whether the number was
 * already on the list.
 */
import { Hono } from 'hono';
import type { Context } from 'hono';
import { Env } from '../types';
import { page, legalVars, escapeHtml, LegalVars } from './legal';
import { hitRateLimit } from '../utils/rate_limit';
import { addToGlobalDnc, canonicalPhone, globalDncSecret } from '../services/global_dnc';
import { hashIp, clientIp } from '../services/consent';

/** Like LEGAL_CSP, but the form may post to this origin. */
export const STOP_CSP = "default-src 'none'; style-src 'unsafe-inline'; img-src 'self' data:; base-uri 'none'; form-action 'self'; frame-ancestors 'none'";

/** Submissions per IP per hour. */
export const STOP_RATE_LIMIT = 10;
const STOP_RATE_WINDOW_SECONDS = 3600;
const MAX_PHONE_INPUT = 32;

type StopState = { kind: 'form'; error?: string; value?: string } | { kind: 'done' } | { kind: 'limited' } | { kind: 'unavailable' };

export function stopPage(v: LegalVars, state: StopState): string {
  let body: string;
  if (state.kind === 'done') {
    body = `<p class="notice" role="status"><strong>Done.</strong> This number is on the CallPilot do-not-call list. No business using CallPilot will place AI calls to it from now on. Calls already in progress may still finish.</p>
<p>If a business keeps calling you, write to <a href="mailto:${v.email}">${v.email}</a> with the business name and the time of the call.</p>`;
  } else if (state.kind === 'limited') {
    body = `<p class="notice" role="alert">Too many requests from your connection. Please try again in an hour, or email <a href="mailto:${v.email}">${v.email}</a>.</p>`;
  } else if (state.kind === 'unavailable') {
    body = `<p class="notice" role="alert">This page is temporarily unavailable. Please email <a href="mailto:${v.email}">${v.email}</a> with your number and we will add it for you.</p>`;
  } else {
    body = `${state.error ? `<p class="notice" role="alert">${escapeHtml(state.error)}</p>` : ''}
<form method="post" action="/stop">
  <label for="phone">Your mobile number</label>
  <input id="phone" name="phone" type="tel" inputmode="tel" autocomplete="tel" maxlength="${MAX_PHONE_INPUT}" required placeholder="98765 43210" value="${escapeHtml(state.value ?? '')}">
  <button type="submit">Stop calls to this number</button>
</form>
<p>Indian numbers can be entered with or without +91. We store only a one-way hash of the number, used for nothing except blocking calls.</p>`;
  }
  return page('Stop calls to my number', v, `
<h1>Stop AI calls to my number</h1>
<p class="lede">CallPilot is a service that businesses use to make AI phone calls to people who asked about their products. Enter your number below and <strong>no business using CallPilot</strong> will call it again.</p>
${body}
<h2>Other ways to stop calls</h2>
<ul>
  <li>During a call, say “don’t call me again”; that business will stop calling you.</li>
  <li>Register on the National Customer Preference Register (DND) by sending <strong>START 0</strong> to 1909, or through your mobile operator’s app.</li>
</ul>
<p>See our <a href="/legal/privacy">Privacy Policy</a> for how we handle personal data.</p>
`);
}

function send(c: Context<{ Bindings: Env }>, html: string, status: 200 | 400 | 429 | 503 = 200) {
  c.header('Content-Security-Policy', STOP_CSP);
  c.header('Cache-Control', 'no-store');
  c.header('X-Robots-Tag', 'noindex');
  return c.html(html, status);
}

const stopApp = new Hono<{ Bindings: Env }>();

stopApp.get('/', (c) => send(c, stopPage(legalVars(c.env), { kind: 'form' })));

stopApp.post('/', async (c) => {
  const v = legalVars(c.env);
  const secret = globalDncSecret(c.env);
  if (!secret) {
    console.error(JSON.stringify({ msg: 'global_dnc_secret_missing', where: 'stop_page' }));
    return send(c, stopPage(v, { kind: 'unavailable' }), 503);
  }

  // Rate limit before parsing: bucket keyed by a hash of the IP, never the IP itself.
  const ipKey = (await hashIp(c.env, clientIp(c))) ?? 'unknown';
  const limit = await hitRateLimit(c.env.DB, `stop:ip:${ipKey}`, STOP_RATE_LIMIT, STOP_RATE_WINDOW_SECONDS);
  if (!limit.allowed) {
    c.header('Retry-After', String(limit.retryAfter));
    return send(c, stopPage(v, { kind: 'limited' }), 429);
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
    return send(c, stopPage(v, { kind: 'form', error: 'Please enter a valid mobile number, e.g. 98765 43210.', value: raw }), 400);
  }
  await addToGlobalDnc(c.env.DB, secret, raw, 'web');
  console.log(JSON.stringify({ msg: 'global_dnc_added', source: 'web' }));
  return send(c, stopPage(v, { kind: 'done' }));
});

export { stopApp };
