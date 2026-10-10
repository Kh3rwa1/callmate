/**
 * Public landing page: GET /get (GET / stays the JSON health/info response).
 *
 * Fast, mobile-first, server-rendered HTML: no scripts, no external assets, strict CSP.
 * Pricing is read from the plan catalogue (services/plans.ts) so it never drifts.
 * ?ref=<code> (a referral code) is carried into the Play Store install referrer as
 * utm_campaign, which the app reads on first launch and sends with signup.
 */
import { Hono } from 'hono';
import { Env } from '../types';
import { escapeHtml } from './legal';
import { getPlan, PAID_PLAN_IDS, Plan, priceWithGst } from '../services/plans';
import { normalizeReferralCode, referralBonusMinutes } from '../services/referrals';

export const PLAY_PACKAGE_ID = 'com.callpilot.app';

/** Play Store link whose install referrer carries the landing source and referral code. */
export function playStoreUrl(ref: string | null): string {
  const referrer = `utm_source=landing&utm_campaign=${ref ?? 'none'}`;
  return `https://play.google.com/store/apps/details?id=${PLAY_PACKAGE_ID}&referrer=${encodeURIComponent(referrer)}`;
}

/** Only an absolute https URL is accepted; returns it with its origin (for media-src), else null. */
export function demoAudio(env: Pick<Env, 'DEMO_AUDIO_URL'>): { url: string; origin: string } | null {
  const raw = env.DEMO_AUDIO_URL?.trim();
  if (!raw) return null;
  try {
    const u = new URL(raw);
    if (u.protocol !== 'https:') return null;
    return { url: u.toString(), origin: u.origin };
  } catch {
    return null;
  }
}

export function landingCsp(audioOrigin: string | null): string {
  return [
    "default-src 'none'",
    "style-src 'unsafe-inline'",
    "img-src 'self' data:",
    ...(audioOrigin ? [`media-src ${audioOrigin}`] : []),
    "base-uri 'none'",
    "form-action 'none'",
    "frame-ancestors 'none'",
  ].join('; ');
}

const inr = (n: number) => `₹${n.toLocaleString('en-IN')}`;

// Prices are shown the way checkout charges them: base + GST, with the total spelled out.
function planCard(p: Plan, perMonth: boolean, env: Env): string {
  const gst = p.priceInr > 0 ? priceWithGst(p.priceInr, env) : null;
  const price = gst
    ? `${inr(gst.base_inr)} <small>+ GST${perMonth ? ' /month' : ''}</small>`
    : 'Free';
  const total = gst ? `<p class="total">${inr(gst.total_inr)} including GST</p>` : '';
  return `<div class="plan"><h3>${escapeHtml(p.name)}</h3><p class="price">${price}</p>${total}`
    + `<p>${p.includedMinutes.toLocaleString('en-IN')} call minutes${perMonth && p.priceInr > 0 ? ' every month' : ''}</p></div>`;
}

export function landingPage(env: Env, rawRef: string | undefined): string {
  const ref = normalizeReferralCode(rawRef);
  const play = escapeHtml(playStoreUrl(ref));
  const trial = getPlan('trial', env);
  const paid = PAID_PLAN_IDS.map((id) => getPlan(id, env));
  const audio = demoAudio(env);
  const bonus = referralBonusMinutes(env);

  const refNote = ref
    ? `<p class="note">Invited by a CallPilot customer: referral code <strong>${escapeHtml(ref)}</strong> is applied when you install from this page${bonus > 0 ? `, and you both get ${bonus} bonus minutes after your first payment` : ''}.</p>`
    : '';
  const demo = audio
    ? `<section aria-labelledby="demo"><h2 id="demo">Hear a real call</h2>
<audio controls preload="none" src="${escapeHtml(audio.url)}">Your browser can't play this recording.</audio></section>`
    : '';

  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="description" content="CallPilot calls back every enquiry in 60 seconds, in Hindi, Bengali or English, qualifies the lead and drafts your WhatsApp follow-up.">
<title>CallPilot · AI that calls back every enquiry</title>
<style>
  :root { color-scheme: light dark; --ink: #17171a; --soft: #5c5c66; --bg: #ffffff; --card: #f5f6fa; --line: #e4e4ea; --accent: #3a5bd9; --on-accent: #ffffff; }
  @media (prefers-color-scheme: dark) { :root { --ink: #f2f2f5; --soft: #a8a8b3; --bg: #111113; --card: #1c1c20; --line: #2c2c31; --accent: #8fa6ff; --on-accent: #0d1330; } }
  * { box-sizing: border-box; }
  body { margin: 0; background: var(--bg); color: var(--ink); font: 16px/1.55 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Noto Sans", sans-serif; }
  main { max-width: 760px; margin: 0 auto; padding: 32px 16px 48px; }
  h1 { font-size: clamp(1.7rem, 6vw, 2.5rem); line-height: 1.15; margin: 0 0 12px; letter-spacing: -0.01em; }
  h2 { font-size: 1.3rem; margin: 40px 0 12px; }
  h3 { font-size: 1.05rem; margin: 0 0 4px; }
  p { margin: 0 0 12px; }
  a { color: var(--accent); }
  .lede { color: var(--soft); font-size: 1.1rem; }
  .cta { display: inline-block; margin: 8px 0 4px; padding: 14px 22px; border-radius: 12px; background: var(--accent); color: var(--on-accent); font-weight: 600; text-decoration: none; }
  .fine { color: var(--soft); font-size: 0.9rem; }
  .note { background: var(--card); border: 1px solid var(--line); border-radius: 12px; padding: 12px 14px; }
  .grid { display: grid; gap: 12px; grid-template-columns: 1fr; }
  @media (min-width: 640px) { .grid { grid-template-columns: repeat(3, 1fr); } }
  .card, .plan { background: var(--card); border: 1px solid var(--line); border-radius: 14px; padding: 16px; }
  .card p, .plan p { color: var(--soft); margin: 0; }
  .price { font-size: 1.5rem; font-weight: 700; color: var(--ink) !important; margin: 4px 0 !important; }
  .price small { font-size: 0.9rem; font-weight: 500; color: var(--soft); }
  .total { font-size: 0.9rem; color: var(--soft); margin: 0 0 6px !important; }
  ol { padding-left: 1.25rem; } ol li { margin: 6px 0; }
  audio { width: 100%; }
  details { border-bottom: 1px solid var(--line); padding: 12px 0; }
  summary { cursor: pointer; font-weight: 600; }
  details p { margin: 8px 0 0; color: var(--soft); }
  footer { margin-top: 40px; padding-top: 16px; border-top: 1px solid var(--line); color: var(--soft); font-size: 0.9rem; display: flex; flex-wrap: wrap; gap: 16px; }
</style>
</head>
<body>
<main>
<h1>Every enquiry called back in 60 seconds — in Hindi, Bengali or English</h1>
<p class="lede">CallPilot is an AI calling employee for your business. It calls new leads, answers their questions, finds out who is serious, and drafts the WhatsApp follow-up for you to send.</p>
${refNote}
<a class="cta" href="${play}">Get CallPilot on Google Play</a>
<p class="fine">Android app. ${trial.includedMinutes > 0 ? `${trial.includedMinutes} free minutes to try, no card needed.` : 'Start with a free trial.'}</p>

<section aria-labelledby="why"><h2 id="why">Why businesses use it</h2>
<div class="grid">
  <div class="card"><h3>Never miss a lead</h3><p>Leads that hear back in the first minutes convert far better. Your AI employee calls every one, even at 9 pm.</p></div>
  <div class="card"><h3>Speaks your customer's language</h3><p>Natural Hindi, Bengali and English, with the details of your courses, products and prices you teach it.</p></div>
  <div class="card"><h3>You stay in control</h3><p>See who is hot, read every call, and send the drafted WhatsApp reply yourself with one tap. Nothing is sent without you.</p></div>
</div></section>

<section aria-labelledby="how"><h2 id="how">How it works</h2>
<ol>
  <li><strong>Hire your AI employee.</strong> Pick a role and teach it about your business in a few minutes.</li>
  <li><strong>Add your leads.</strong> Type them in, import a list, or let enquiries arrive from your form.</li>
  <li><strong>It calls and reports back.</strong> Each call is scored hot, warm or cold with a summary and a ready WhatsApp follow-up.</li>
</ol></section>

${demo}

<section aria-labelledby="pricing"><h2 id="pricing">Simple pricing</h2>
<div class="grid">
${planCard(trial, false, env)}
${paid.map((p) => planCard(p, true, env)).join('\n')}
</div>
<p class="fine">Prices in Indian rupees, plus 18% GST. Pay monthly, or yearly and get 2 months free, in the app. Plans never renew automatically.</p></section>

<section aria-labelledby="faq"><h2 id="faq">Questions</h2>
<details><summary>Is it legal to call my leads with AI?</summary><p>CallPilot calls only between 9 am and 9 pm, skips anyone marked "do not call", and only calls people who enquired with you or agreed to be contacted. You confirm consent before a campaign starts.</p></details>
<details><summary>Does it say it's an AI?</summary><p>Yes. Every call starts by saying it is an AI assistant calling on behalf of your business and that the call is recorded.</p></details>
<details><summary>Is my data safe?</summary><p>Call recordings and transcripts are encrypted, your data is never sold, and you can delete your account and data from the app at any time. Read our <a href="/legal/privacy">privacy policy</a>.</p></details>
</section>

<p><a class="cta" href="${play}">Install CallPilot</a></p>
<footer><a href="/legal/privacy">Privacy</a><a href="/legal/terms">Terms</a><a href="/legal/delete-account">Delete your account</a></footer>
</main>
</body>
</html>`;
}

const landingApp = new Hono<{ Bindings: Env }>();

landingApp.get('/', (c) => {
  c.header('Content-Security-Policy', landingCsp(demoAudio(c.env)?.origin ?? null));
  c.header('Cache-Control', 'public, max-age=300');
  return c.html(landingPage(c.env, c.req.query('ref')));
});

export { landingApp };
