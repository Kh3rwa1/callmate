/**
 * Public legal pages: privacy policy, terms of service and account deletion.
 * Linked from the app (sign-in footer, Help & support) and the Play Store listing.
 *
 * Plain server-rendered HTML: no scripts, no external assets, readable on a phone.
 * Contact details come from Worker vars SUPPORT_EMAIL and LEGAL_ENTITY_NAME.
 */
import { Hono } from 'hono';
import type { Context } from 'hono';
import { Env } from '../types';
import { retentionDays } from '../services/retention';
import type { PageLang } from '../services/page_lang';
import { LEGAL_CHROME } from '../services/public_page_strings';

export const LEGAL_LAST_UPDATED = '10 October 2026';
const DEFAULT_SUPPORT_EMAIL = 'founder@olitun.in';
const DEFAULT_ENTITY = 'CallPilot';

// Strict: these pages run no script and load nothing from elsewhere.
export const LEGAL_CSP = "default-src 'none'; style-src 'unsafe-inline'; img-src 'self' data:; base-uri 'none'; form-action 'none'; frame-ancestors 'none'";

export function escapeHtml(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

export interface LegalVars {
  entity: string;
  email: string;
  /** Days call recordings, transcripts and summaries are kept (RETENTION_DAYS). */
  retentionDays: number;
}

export function legalVars(env: Env): LegalVars {
  return {
    entity: escapeHtml((env.LEGAL_ENTITY_NAME || DEFAULT_ENTITY).trim()),
    email: escapeHtml((env.SUPPORT_EMAIL || DEFAULT_SUPPORT_EMAIL).trim()),
    retentionDays: retentionDays(env),
  };
}

/** Legal-page layout. `lang` sets <html lang> and the nav/footer language (the policies themselves are English). */
export function page(title: string, v: LegalVars, body: string, lang: PageLang = 'en'): string {
  const t = LEGAL_CHROME[lang];
  return `<!doctype html>
<!--
  TODO(owner): DRAFT, pending legal review. Before relying on this page:
  - have a lawyer review it against the DPDP Act 2023 and current TRAI rules;
  - set LEGAL_ENTITY_NAME to the registered company name and SUPPORT_EMAIL to a monitored inbox
    (backend/wrangler.toml [vars] and [env.staging.vars]);
  - name the Grievance Officer and add a postal address;
  - confirm the live Sarvam agent says, at the start of every call, that it is an AI and that the call is recorded;
  - bump LEGAL_LAST_UPDATED in backend/src/routes/legal.ts whenever the text changes.
-->
<html lang="${lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="index, follow">
<title>${title} · ${v.entity}</title>
<style>
  :root { color-scheme: light dark; --ink: #1d1d1f; --soft: #5c5c66; --bg: #ffffff; --line: #e4e4ea; --accent: #3a5bd9; }
  @media (prefers-color-scheme: dark) { :root { --ink: #f2f2f5; --soft: #a8a8b3; --bg: #121214; --line: #2c2c31; --accent: #8fa6ff; } }
  * { box-sizing: border-box; }
  body { margin: 0; background: var(--bg); color: var(--ink); font: 16px/1.6 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Noto Sans", sans-serif; }
  main { max-width: 720px; margin: 0 auto; padding: 32px 16px 48px; }
  h1 { font-size: 1.75rem; line-height: 1.25; margin: 0 0 4px; }
  h2 { font-size: 1.15rem; margin: 32px 0 8px; }
  p, li { color: var(--ink); }
  ul { padding-left: 1.25rem; }
  li { margin: 4px 0; }
  a { color: var(--accent); }
  .lede { color: var(--soft); margin-top: 0; }
  form { margin: 16px 0; }
  label { display: block; font-weight: 600; margin-bottom: 6px; }
  input[type=tel] { width: 100%; max-width: 360px; font: inherit; padding: 10px 12px; border: 1px solid var(--line); border-radius: 8px; background: var(--bg); color: var(--ink); }
  button { margin-top: 12px; font: inherit; font-weight: 600; padding: 10px 18px; border: 0; border-radius: 8px; background: var(--accent); color: #fff; cursor: pointer; }
  .notice { padding: 12px 14px; border-radius: 8px; border: 1px solid var(--line); }
  nav { display: flex; flex-wrap: wrap; gap: 16px; font-size: 0.95rem; margin-bottom: 24px; }
  nav.langs { gap: 8px; font-size: 0.9rem; margin: -8px 0 16px; color: var(--soft); }
  footer { margin-top: 40px; padding-top: 16px; border-top: 1px solid var(--line); color: var(--soft); font-size: 0.9rem; }
</style>
</head>
<body>
<main>
<nav aria-label="${t.navLabel}">
  <a href="/legal/privacy">${t.privacy}</a>
  <a href="/legal/terms">${t.terms}</a>
  <a href="/legal/delete-account">${t.deleteAccount}</a>
  <a href="/stop${lang === 'en' ? '' : `?lang=${lang}`}">${t.stopCalls}</a>
</nav>
${body}
<footer>
  <p>${t.questionsHtml(v.email)}</p>
  <p>${t.lastUpdated}: ${LEGAL_LAST_UPDATED}</p>
</footer>
</main>
</body>
</html>`;
}

export function privacyPage(v: LegalVars): string {
  return page('Privacy Policy', v, `
<h1>Privacy Policy</h1>
<p class="lede">How ${v.entity} collects, uses and protects personal data when businesses use the CallPilot app and its AI calling service.</p>

<h2>1. Who we are and what this covers</h2>
<p>CallPilot lets a business (the “owner”) set up an AI employee that phones the business’s leads, records and transcribes the conversation, scores interest and drafts follow-up messages for the owner to review. This policy covers the CallPilot Android app, its backend and the calls it places. It is written with the Digital Personal Data Protection Act, 2023 (DPDP Act) in mind.</p>
<p>For the owner’s own account, ${v.entity} is the <strong>Data Fiduciary</strong>. For the leads a business uploads and calls, the business decides why and whom to call, so the business is the Data Fiduciary and ${v.entity} processes that data on the business’s behalf.</p>

<h2>2. Data we collect</h2>
<ul>
  <li><strong>Owner account:</strong> name, email address and profile photo from Google Sign-In, or a mobile number if you sign in with an OTP; business name, category, contact numbers, address, offerings, pricing and the settings of your AI employee.</li>
  <li><strong>Leads:</strong> the names, phone numbers, interests and notes of the people you add, type in, import from a file or pick from your phone’s contacts, plus their consent and do-not-call status.</li>
  <li><strong>Phone contacts:</strong> only if you allow the contacts permission and only the contacts you choose to import. We do not upload your address book.</li>
  <li><strong>Calls:</strong> call status, time and duration; audio recordings and transcripts of AI calls; AI-generated summaries, lead scores and suggested follow-ups.</li>
  <li><strong>Microphone:</strong> when you use “talk to your AI employee” to test it, your voice is streamed to our speech provider for that live conversation. We do not use it for anything else.</li>
  <li><strong>Knowledge you add:</strong> website addresses, documents and text you give the AI employee to learn from.</li>
  <li><strong>Device and usage:</strong> a push-notification token, app version, minutes used and technical logs (IP address, request times, errors) that keep the service secure and working.</li>
</ul>

<h2>3. Why we use it</h2>
<ul>
  <li>To create and secure your account and sign you in.</li>
  <li>To place AI calls to your leads during allowed hours, transcribe and summarise them, score the lead and draft follow-ups.</li>
  <li>To notify you about hot leads, callbacks and follow-ups.</li>
  <li>To measure calling minutes against your plan and handle billing.</li>
  <li>To prevent abuse, honour opt-outs, keep the service reliable and meet legal obligations.</li>
</ul>
<p>We do not sell personal data and do not use your leads’ data to market to them ourselves.</p>

<h2>4. AI calls and recording</h2>
<p>Calls are made by an AI voice agent, not a person, on behalf of the business named in the call, and the person called should be told at the start that they are speaking with an AI and that the call is recorded. Calls are recorded and transcribed so the owner can review them and so the lead can be scored. If a lead asks not to be called again, CallPilot marks the number as do-not-call for that business and stops calling it.</p>
<p><strong>Stop all CallPilot calls:</strong> anyone can enter their phone number at <a href="/stop">/stop</a> and no business using CallPilot will call that number again. We keep only a one-way hash of the number, not the number itself.</p>

<h2>5. Who processes the data for us</h2>
<ul>
  <li><strong>Cloudflare</strong> (hosting, database, file storage, queues and AI models) — our backend runs on Cloudflare.</li>
  <li><strong>Sarvam AI</strong> — telephony, the AI voice agent, speech recognition and speech synthesis for calls and voice tests.</li>
  <li><strong>Google Firebase</strong> — Google Sign-In and push notifications.</li>
  <li>Our payment processor, if you buy a paid plan (we never see full card details).</li>
</ul>
<p>These providers act on our instructions under their own security and privacy terms. Some of them may process data outside India; where they do, we rely on the safeguards the DPDP Act allows.</p>

<h2>6. How long we keep it</h2>
<ul>
  <li>Call recordings, transcripts and AI summaries are deleted ${v.retentionDays} days after the call; the call’s date, duration, status and score are kept for reporting.</li>
  <li>Account, lead and call data are kept while your account is active and deleted when you delete your account.</li>
  <li>Transcripts and recording links are encrypted at rest.</li>
  <li>Database backups are kept for up to 30 days and then overwritten, so deleted data disappears from backups within that time.</li>
  <li>Security and webhook logs are kept for up to 90 days.</li>
  <li>We may keep billing records for as long as tax law requires.</li>
</ul>

<h2>7. The owner’s responsibilities</h2>
<p>If you use CallPilot to call people, you must have a lawful basis and, where needed, their consent to call them and to record the call; you must respect TRAI rules, the National Customer Preference Register (DND) and opt-outs; and you must tell them how to reach you about their data. See our <a href="/legal/terms">Terms of Service</a>.</p>

<h2>8. Your rights</h2>
<p>Under the DPDP Act you can ask to access, correct, update or erase your personal data, withdraw consent, nominate someone to act for you, and raise a grievance. Owners can edit most data in the app and can delete their account at any time (see <a href="/legal/delete-account">Delete your account</a>). If you were called by a business using CallPilot, contact that business first; you can also write to us and we will pass your request on and help the business act on it.</p>

<h2>9. Grievance Officer</h2>
<p>Name: <em>[to be appointed]</em><br>Email: <a href="mailto:${v.email}">${v.email}</a></p>
<p>We aim to acknowledge grievances within 48 hours and resolve them within 30 days. If you are not satisfied, you may approach the Data Protection Board of India.</p>

<h2>10. Children</h2>
<p>CallPilot is a business tool for adults. We do not knowingly create accounts for anyone under 18.</p>

<h2>11. Changes</h2>
<p>We will update this page when our practices change and tell owners in the app about significant changes.</p>
`);
}

export function termsPage(v: LegalVars): string {
  return page('Terms of Service', v, `
<h1>Terms of Service</h1>
<p class="lede">These terms govern your use of CallPilot, provided by ${v.entity}. By creating an account you agree to them on behalf of your business.</p>

<h2>1. The service</h2>
<p>CallPilot gives your business an AI employee that calls your leads, records and transcribes the calls, scores the leads and drafts WhatsApp follow-ups that you review and send yourself. AI output can be wrong; check important details before acting on them.</p>

<h2>2. Your account</h2>
<p>You must be at least 18 and authorised to act for your business. Keep your sign-in secure; you are responsible for activity on your account.</p>

<h2>3. Calling rules you must follow</h2>
<ul>
  <li>Only upload and call people you are allowed to contact, with their consent where the law requires it, including consent to an AI call and to recording.</li>
  <li>Follow the Telecom Commercial Communications Customer Preference Regulations (TRAI) and other applicable law, including the National Customer Preference Register (DND). CallPilot only places calls between 9:00 and 21:00 in the lead’s local time, but you remain responsible for whom you call and why.</li>
  <li>Honour opt-outs. When someone asks not to be called, CallPilot marks them do-not-call; do not re-add them.</li>
  <li>Do not use CallPilot for spam, harassment, fraud, debt-collection threats, political campaigning, impersonation or any unlawful purpose.</li>
  <li>Give the AI employee accurate information about your business; you are responsible for what it says based on what you teach it.</li>
</ul>
<p>We may pause calling or suspend an account that breaks these rules or draws complaints.</p>

<h2>4. Plans, minutes and payment</h2>
<p>Calling time is measured in minutes against your plan. Calls may be held back when your remaining minutes run low. Prices, inclusions and renewal terms are shown in the app before you buy. Unused minutes do not carry over unless the plan says so.</p>

<h2>5. Your data</h2>
<p>You own the data you put into CallPilot. You let us process it to run the service as described in our <a href="/legal/privacy">Privacy Policy</a>. For your leads’ data you are the Data Fiduciary and we process it on your behalf.</p>

<h2>6. Availability</h2>
<p>We work to keep CallPilot running but do not guarantee it will be uninterrupted or error-free. Calls depend on telecom networks and third-party providers outside our control.</p>

<h2>7. Liability</h2>
<p>To the extent the law allows, CallPilot is provided “as is”, and our total liability for any claim is limited to the amount you paid us in the three months before the claim. We are not liable for indirect or consequential losses, lost business, or for calls you instruct us to make in breach of these terms.</p>

<h2>8. Ending the service</h2>
<p>You can stop using CallPilot and delete your account at any time from the app. We may end the service for an account with notice, or immediately for serious misuse.</p>

<h2>9. Law and disputes</h2>
<p>These terms are governed by the laws of India. Contact us first at <a href="mailto:${v.email}">${v.email}</a>; we will try to resolve any dispute informally.</p>

<h2>10. Changes</h2>
<p>We may update these terms. If a change is significant we will tell you in the app before it takes effect; continuing to use CallPilot means you accept the new terms.</p>
`);
}

export function deleteAccountPage(v: LegalVars): string {
  return page('Delete your account', v, `
<h1>Delete your CallPilot account</h1>
<p class="lede">You can delete your account and all of its data yourself, at any time, from the app.</p>

<h2>In the app</h2>
<ol>
  <li>Open CallPilot and sign in.</li>
  <li>Tap the <strong>Agent</strong> tab at the bottom.</li>
  <li>Scroll to the end and tap <strong>Delete account</strong>.</li>
  <li>Confirm with <strong>Delete permanently</strong>.</li>
</ol>

<h2>By email</h2>
<p>If you can no longer sign in, email <a href="mailto:${v.email}?subject=Delete%20my%20CallPilot%20account">${v.email}</a> from the email address on your account (or tell us the mobile number you signed in with). We will verify the request and delete the account within 30 days.</p>

<h2>What gets deleted</h2>
<ul>
  <li>Your account, business profile and AI employee settings.</li>
  <li>All leads, calls, call recording links, transcripts, summaries, follow-ups, callbacks and campaigns.</li>
  <li>Knowledge files and documents you uploaded, notification tokens and usage records.</li>
</ul>
<p>Deletion is permanent and cannot be undone. Copies in database backups are overwritten within 30 days. We may keep billing records for as long as tax law requires.</p>
`);
}

const legalApp = new Hono<{ Bindings: Env }>();

function sendPage(c: Context<{ Bindings: Env }>, html: string) {
  c.header('Content-Security-Policy', LEGAL_CSP);
  c.header('Cache-Control', 'public, max-age=3600');
  return c.html(html);
}

legalApp.get('/privacy', (c) => sendPage(c, privacyPage(legalVars(c.env))));
legalApp.get('/terms', (c) => sendPage(c, termsPage(legalVars(c.env))));
legalApp.get('/delete-account', (c) => sendPage(c, deleteAccountPage(legalVars(c.env))));

export { legalApp };
