/**
 * Ops page: GET/POST /ops/numbers. The operator adds a phone number bought in the Sarvam dashboard
 * here, with no code change or deploy (docs/SARVAM_SETUP.md -> Business numbers); Sarvam has no API
 * that lists a connection's numbers, so this is the only way one joins the pool. Businesses waiting for
 * a number get it at once, otherwise it shows in the app's picker while a receptionist pool agent is
 * free to answer it. Free numbers added here can be removed again.
 *
 * Off (404) unless OPS_KEY_SHA256 is set. Every POST carries the key, checked against that hash in
 * constant time; a wrong key gets a generic 401 and a log line, and after OPS_MAX_FAILURES wrong keys
 * in an hour an IP gets 429. Shows numbers with their status and source, never which business has one.
 * Also lists built-in UPI payments waiting to be checked against the bank statement (services/upi.ts),
 * with Confirm (applies the plan) and Reject. Server-rendered HTML, no scripts, strict CSP, not cached
 * or indexed.
 */
import { Hono } from 'hono';
import type { Context } from 'hono';
import { Env } from '../types';
import { escapeHtml } from './legal';
import { timingSafeEqual } from '../utils/compare';
import { hitRateLimit } from '../utils/rate_limit';
import { clientIp, hashIp } from '../services/consent';
import { addOpsNumber, opsPoolView, OpsPoolView, removeOpsNumber } from '../services/business_numbers';
import { confirmUpiOrder, rejectUpiOrder, SubmittedUpiOrder, submittedUpiOrders, UpiPayee, upiPayee } from '../services/upi';

/** No scripts, nothing from elsewhere; the form may only post back here. */
export const OPS_CSP = "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'";

/** Wrong keys per IP per hour before the page answers 429. */
export const OPS_MAX_FAILURES = 10;
const OPS_FAILURE_WINDOW_SECONDS = 3600;
const MAX_INPUT = 200;

type Notice = { kind: 'ok' | 'error'; text: string };

function layout(body: string): string {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>CallPilot ops</title>
<style>
  :root { color-scheme: light dark; --ink: #1d1d1f; --soft: #5c5c66; --bg: #ffffff; --line: #e4e4ea; --accent: #3a5bd9; --ok: #1f7a3d; --bad: #b3261e; }
  @media (prefers-color-scheme: dark) { :root { --ink: #f2f2f5; --soft: #a8a8b3; --bg: #121214; --line: #2c2c31; --accent: #8fa6ff; --ok: #6fd08c; --bad: #ff8a80; } }
  * { box-sizing: border-box; }
  body { margin: 0; background: var(--bg); color: var(--ink); font: 16px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Noto Sans", sans-serif; }
  main { max-width: 640px; margin: 0 auto; padding: 24px 16px 48px; }
  h1 { font-size: 1.5rem; margin: 0 0 4px; }
  h2 { font-size: 1.1rem; margin: 28px 0 8px; }
  .lede, .hint { color: var(--soft); }
  label { display: block; font-weight: 600; margin: 14px 0 6px; }
  input { width: 100%; font: inherit; padding: 10px 12px; border: 1px solid var(--line); border-radius: 8px; background: var(--bg); color: var(--ink); }
  .actions { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 16px; }
  button { font: inherit; font-weight: 600; padding: 10px 16px; border: 1px solid var(--accent); border-radius: 8px; background: var(--accent); color: #fff; cursor: pointer; }
  button.secondary { background: transparent; color: var(--accent); }
  .notice { padding: 12px 14px; border-radius: 8px; border: 1px solid var(--line); margin: 16px 0; }
  .notice.ok { border-color: var(--ok); }
  .notice.error { border-color: var(--bad); }
  .stats { padding-left: 1.25rem; }
  .table { overflow-x: auto; }
  table { width: 100%; border-collapse: collapse; font-size: 0.95rem; }
  th, td { text-align: left; padding: 8px 6px; border-bottom: 1px solid var(--line); white-space: nowrap; }
  th { color: var(--soft); font-weight: 600; }
</style>
</head>
<body>
<main>
<h1>Business numbers</h1>
<p class="lede">Add a number bought in Sarvam (Deploy → Phone Numbers → Buy). No deploy needed.</p>
${body}
</main>
</body>
</html>`;
}

function form(key = ''): string {
  return `<form id="ops" method="post" action="/ops/numbers">
  <label for="key">Ops key</label>
  <input id="key" name="key" type="password" autocomplete="current-password" maxlength="${MAX_INPUT}" required value="${escapeHtml(key)}">
  <label for="number">Number</label>
  <input id="number" name="number" type="tel" inputmode="tel" autocomplete="off" maxlength="32" placeholder="+91 79714 43028">
  <div class="actions">
    <button type="submit" name="action" value="add">Add number</button>
    <button type="submit" name="action" value="list" class="secondary">Show pool &amp; payments</button>
    <button type="submit" name="action" value="remove" class="secondary">Remove number</button>
  </div>
</form>`;
}

/** "+917971443028" → "+91 79714 43028". */
function displayNumber(phone: string): string {
  const d = phone.replace(/^\+91/, '');
  return d.length === 10 ? `+91 ${d.slice(0, 5)} ${d.slice(5)}` : phone;
}

function poolHtml(v: OpsPoolView): string {
  const free = v.numbers.filter((n) => n.status === 'free' && n.listed).length;
  const agents = v.agentsTotal
    ? `${v.agentsFree} of ${v.agentsTotal}${v.agentsFree <= 1 ? ' (add more: docs/SARVAM_SETUP.md → Receptionist pool)' : ''}`
    : 'none configured (SARVAM_RECEPTIONIST_AGENTS), so numbers added here can’t be given out yet';
  const rows = v.numbers.map((n) => `<tr><td>${escapeHtml(displayNumber(n.phone))}</td><td>${n.status}</td>`
    + `<td>${n.source}${n.listed ? '' : ' (unlisted)'}</td><td>${n.agent ? 'yes' : 'no'}</td></tr>`).join('\n');
  return `<h2>Pool</h2>
<ul class="stats">
  <li>Free numbers: ${free}</li>
  <li>Receptionist agents free: ${agents}</li>
  ${v.agentsIgnored > 0 ? `<li>SARVAM_RECEPTIONIST_AGENTS entries ignored (malformed or repeated): ${v.agentsIgnored}</li>` : ''}
  <li>Businesses waiting for a number: ${v.waiting}</li>
  <li>Not TRAI 140/160-series: ${v.numbers.filter((n) => !n.dlt).length}${v.dltRequired
    ? ' (REQUIRE_DLT_CALLER_IDS: no more can be added)' : ''}</li>
</ul>
${v.numbers.length ? `<div class="table"><table>
<thead><tr><th>Number</th><th>Status</th><th>Source</th><th>Agent</th></tr></thead>
<tbody>
${rows}
</tbody>
</table></div>` : '<p>No numbers yet.</p>'}
<p class="hint">Free: waiting for a business. Active: a business’s number. Held: its plan lapsed, kept for it for 30 days.
Source: ops = added here, config = SARVAM_BUSINESS_NUMBERS. An ops number gets a receptionist agent when a
business takes it.</p>`;
}

/** UPI payments the owners say they made, oldest first; each row's buttons submit the key form above. */
function upiHtml(payee: UpiPayee | null, orders: SubmittedUpiOrder[]): string {
  const rows = orders.map((o) => `<tr><td>${escapeHtml(o.reference)}</td><td>₹${o.total_inr.toLocaleString('en-IN')}</td>`
    + `<td>${escapeHtml(o.utr)}</td><td>${escapeHtml(o.plan_name)}</td><td>${escapeHtml(o.submitted_at)} UTC</td>`
    + `<td><button type="submit" form="ops" name="action" value="upi_confirm:${escapeHtml(o.id)}">Confirm</button> `
    + `<button type="submit" form="ops" name="action" value="upi_reject:${escapeHtml(o.id)}" class="secondary">Reject</button></td></tr>`)
    .join('\n');
  return `<h2>UPI payments to confirm</h2>
<p class="hint">Payments go to: ${payee ? escapeHtml(payee.vpa) : 'off (UPI_PAYEE_VPA is not set)'}</p>
${orders.length ? `<div class="table"><table>
<thead><tr><th>Reference</th><th>Amount</th><th>UTR</th><th>Plan</th><th>Entered</th><th></th></tr></thead>
<tbody>
${rows}
</tbody>
</table></div>` : '<p>None waiting.</p>'}
<p class="hint">Find the UTR and amount in your bank statement or UPI app; the payer's note says CallPilot and the
reference. Confirm starts the plan and tells the owner. Reject asks the owner to check the UTR and enter it again.</p>`;
}

function send(c: Context<{ Bindings: Env }>, html: string, status: 200 | 400 | 401 | 429 = 200) {
  c.header('Content-Security-Policy', OPS_CSP);
  c.header('Cache-Control', 'no-store');
  c.header('X-Robots-Tag', 'noindex, nofollow');
  c.header('Referrer-Policy', 'no-referrer');
  return c.html(html, status);
}

/** Same answer as any unknown path, so the page doesn't exist until it is configured. */
const notFound = (c: Context<{ Bindings: Env }>) =>
  c.json({ message: `Endpoint ${c.req.path} not found.`, code: 'not_found' }, 404);

/** The configured key hash, or null when the page is off. */
function keyHash(env: Env): string | null {
  const h = (env.OPS_KEY_SHA256 || '').trim().toLowerCase();
  return /^[0-9a-f]{64}$/.test(h) ? h : null;
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

const ADD_ERRORS = {
  invalid: 'Enter an Indian number: +91 and 10 digits.',
  not_dlt: 'Only TRAI 140/160-series numbers can be added (REQUIRE_DLT_CALLER_IDS is on).',
  shared_caller_id: 'That is a shared caller ID (SARVAM_AGENT_PHONE_NUMBERS); it can’t be a business number.',
  in_config: 'That number is in SARVAM_BUSINESS_NUMBERS already.',
  in_use: 'That number is already in use.',
} as const;

const REMOVE_ERRORS = {
  invalid: 'Enter the number to remove.',
  not_found: 'That number is not in the pool.',
  in_config: 'That number comes from SARVAM_BUSINESS_NUMBERS; remove it there.',
  in_use: 'That number is active or held; only a free number can be removed.',
} as const;

const UPI_ERRORS = {
  not_found: 'That payment is not in the list.',
  already_decided: 'That payment was already confirmed or rejected.',
} as const;

export const opsApp = new Hono<{ Bindings: Env }>();

opsApp.get('/numbers', (c) => {
  if (!keyHash(c.env)) return notFound(c);
  return send(c, layout(form()));
});

opsApp.post('/numbers', async (c) => {
  const expected = keyHash(c.env);
  if (!expected) return notFound(c);

  // Wrong keys are counted per IP (a hash of it, never the IP itself).
  const bucket = `ops:fail:${(await hashIp(c.env, clientIp(c))) ?? 'unknown'}`;
  const failures = await c.env.DB.prepare(
    "SELECT COUNT(*) AS n FROM rate_limits WHERE bucket = ? AND created_at > datetime('now', ?)"
  ).bind(bucket, `-${OPS_FAILURE_WINDOW_SECONDS} seconds`).first<{ n: number }>();
  if ((failures?.n ?? 0) >= OPS_MAX_FAILURES) {
    c.header('Retry-After', String(OPS_FAILURE_WINDOW_SECONDS));
    return send(c, layout('<p class="notice error" role="alert">Too many attempts. Try again later.</p>'), 429);
  }

  let fields: Record<string, unknown> = {};
  try {
    fields = await c.req.parseBody();
  } catch {
    fields = {};
  }
  const str = (v: unknown) => (typeof v === 'string' ? v.slice(0, MAX_INPUT) : '');
  const key = str(fields.key);
  if (!key || !timingSafeEqual(await sha256Hex(key), expected)) {
    await hitRateLimit(c.env.DB, bucket, OPS_MAX_FAILURES, OPS_FAILURE_WINDOW_SECONDS);
    console.warn(JSON.stringify({ msg: 'ops_page_unauthorized' }));
    return send(c, layout(`<p class="notice error" role="alert">Not allowed.</p>\n${form()}`), 401);
  }

  const action = str(fields.action) || 'list';
  const number = str(fields.number);
  let notice: Notice | null = null;
  let status: 200 | 400 = 200;
  if (action === 'add') {
    const r = await addOpsNumber(c.env, number);
    if (r.ok) {
      const what = r.added ? `Added ${displayNumber(r.phone)}.` : `${displayNumber(r.phone)} is in the pool already.`;
      const given = r.assigned === 1 ? '1 waiting business got a number.' : `${r.assigned} waiting businesses got a number.`;
      const dlt = r.dlt ? '' : ' Note: it is not a TRAI 140/160-series number, which commercial calls need (COMPLIANCE.md).';
      notice = { kind: 'ok', text: `${what} ${given}${dlt}` };
    } else {
      notice = { kind: 'error', text: ADD_ERRORS[r.code] };
      status = 400;
    }
  } else if (action === 'remove') {
    const r = await removeOpsNumber(c.env, number);
    if (r.ok) {
      notice = {
        kind: 'ok',
        text: `Removed ${displayNumber(r.phone)}. Release it in Sarvam if you no longer want to pay for it.`,
      };
    } else {
      notice = { kind: 'error', text: REMOVE_ERRORS[r.code] };
      status = 400;
    }
  } else if (action.startsWith('upi_confirm:') || action.startsWith('upi_reject:')) {
    const [verb, orderId] = action.split(':');
    const r = verb === 'upi_confirm' ? await confirmUpiOrder(c.env, orderId) : await rejectUpiOrder(c.env, orderId);
    if (!r.ok) {
      notice = { kind: 'error', text: UPI_ERRORS[r.code] };
      status = 400;
    } else if (verb === 'upi_reject') {
      notice = { kind: 'ok', text: `Rejected ${r.reference}; the owner was asked to check the UTR.` };
    } else {
      notice = r.applied
        ? { kind: 'ok', text: `Confirmed ${r.reference}. The plan is active and the owner was told.` }
        : { kind: 'error', text: `Confirmed ${r.reference}, but it is extra minutes for a plan that is no longer active: credit them by hand.` };
    }
  } else if (action !== 'list') {
    notice = { kind: 'error', text: 'Unknown action.' };
    status = 400;
  }

  const view = await opsPoolView(c.env);
  const upi = upiHtml(upiPayee(c.env), await submittedUpiOrders(c.env));
  const noticeHtml = notice
    ? `<p class="notice ${notice.kind}" role="${notice.kind === 'error' ? 'alert' : 'status'}">${escapeHtml(notice.text)}</p>\n`
    : '';
  // The key is put back in its (masked) field so the operator can add the next number.
  return send(c, layout(`${noticeHtml}${form(key)}\n${upi}\n${poolHtml(view)}`), status);
});
