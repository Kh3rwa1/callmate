/**
 * Public endpoints for lead integrations (no owner auth; each verifies its provider):
 *   POST /hooks/google-ads/:slug      Google Ads lead form webhook (`google_key` in the body)
 *   POST /hooks/indiamart/:slug?key=  IndiaMART Lead Manager Push API (token in the URL)
 *   GET  /hooks/meta/:slug            Meta webhook verification (hub.challenge)
 *   POST /hooks/meta/:slug            Meta leadgen events (X-Hub-Signature-256 with the app secret)
 *
 * Every lead goes through captureExternalLead → captureLead (consent event + instant AI call with
 * every dial guard). Unknown, revoked and wrong-secret requests all look the same (401 / 403).
 */
import { Hono } from 'hono';
import type { Context } from 'hono';
import { Env } from '../types';
import { hitRateLimit } from '../utils/rate_limit';
import { findActiveSource, sha256Hex, verifyWebhookToken, type LeadSourceRow } from '../services/lead_capture';
import {
  captureExternalLead, fetchMetaLead, indiaMartRecords, mapGoogleAdsLead, mapIndiaMartRecord, mapMetaLead,
  metaLeadgenIds, readConfig, releaseExternalId, claimExternalId, setSourceError, verifyMetaSignature,
} from '../services/lead_integrations';

/** Same budgets as the generic lead webhook (routes/lead_capture_public.ts). */
export const INTEGRATION_LIMIT_PER_IP = { limit: 600, windowSeconds: 3600 };
export const INTEGRATION_LIMIT_PER_SLUG = { limit: 600, windowSeconds: 3600 };
/** Provider payloads are small; anything bigger is not a lead. */
export const MAX_INTEGRATION_BODY_BYTES = 64 * 1024;

const leadIntegrationsPublicApp = new Hono<{ Bindings: Env }>();

function clientIp(c: Context): string {
  return c.req.header('cf-connecting-ip') || c.req.header('x-real-ip') || 'unknown';
}

function waitUntilOf(c: Context): ((p: Promise<unknown>) => void) | undefined {
  try {
    const ctx = c.executionCtx;
    return (p) => ctx.waitUntil(p);
  } catch {
    return undefined;
  }
}

/** Per-IP then (after auth) per-source sliding windows. Returns a 429 response or null. */
async function limited(c: Context<{ Bindings: Env }>, bucket: string, cfg: { limit: number; windowSeconds: number }): Promise<Response | null> {
  const r = await hitRateLimit(c.env.DB, bucket, cfg.limit, cfg.windowSeconds);
  if (r.allowed) return null;
  c.header('Retry-After', String(r.retryAfter));
  return c.json({ message: 'Too many requests.', code: 'rate_limited' }, 429);
}

async function ipLimited(c: Context<{ Bindings: Env }>, kind: string): Promise<Response | null> {
  const ipKey = (await sha256Hex(`lead-integration:${clientIp(c)}`)).slice(0, 24);
  return limited(c, `leadint:${kind}:ip:${ipKey}`, INTEGRATION_LIMIT_PER_IP);
}

async function readBody(c: Context): Promise<string | null> {
  const declared = Number(c.req.header('content-length') ?? '0');
  if (declared > MAX_INTEGRATION_BODY_BYTES) return null;
  const text = await c.req.text();
  return text.length > MAX_INTEGRATION_BODY_BYTES ? null : text;
}

function parseJson(text: string): any {
  try {
    return JSON.parse(text);
  } catch {
    return undefined;
  }
}

// ------------------------------------------------------------------ Google Ads

// Google: 200 {} = accepted, 4xx = permanent (not retried), 5xx = retried.
leadIntegrationsPublicApp.post('/hooks/google-ads/:slug', async (c) => {
  const tooMany = await ipLimited(c, 'google');
  if (tooMany) return tooMany;

  const text = await readBody(c);
  if (text === null) return c.json({ message: 'Payload too large.' }, 413);
  const payload = parseJson(text);
  if (!payload || typeof payload !== 'object') return c.json({ message: 'Malformed JSON payload.' }, 400);

  const source = await findActiveSource(c.env.DB, c.req.param('slug') ?? '', 'google_ads');
  const key = typeof payload.google_key === 'string' ? payload.google_key.trim() : null;
  if (!source || !(await verifyWebhookToken(key, source.secret_hash))) {
    return c.json({ message: 'Invalid google_key or unknown webhook URL.' }, 401);
  }
  const slugLimit = await limited(c, `leadint:${source.public_slug}`, INTEGRATION_LIMIT_PER_SLUG);
  if (slugLimit) return slugLimit;

  // "Send test data" from Google Ads: the key works, nothing is created and nobody is called.
  if (payload.is_test === true) return c.json({});

  const mapped = mapGoogleAdsLead(payload);
  if (!mapped) return c.json({ message: 'The lead has no phone number. Add a phone question to the lead form.' }, 400);

  const result = await captureExternalLead(c.env, source, mapped.externalId, mapped.input, {
    fallbackBaseUrl: new URL(c.req.url).origin, waitUntil: waitUntilOf(c),
  });
  if (result.status === 'invalid_phone') return c.json({ message: 'Invalid phone number.' }, 400);
  return c.json({});
});

// ------------------------------------------------------------------ IndiaMART push

leadIntegrationsPublicApp.post('/hooks/indiamart/:slug', async (c) => {
  const tooMany = await ipLimited(c, 'indiamart');
  if (tooMany) return tooMany;

  const source = await findActiveSource(c.env.DB, c.req.param('slug') ?? '', 'indiamart');
  if (!source || !(await verifyWebhookToken(c.req.query('key'), source.secret_hash))) {
    return c.json({ message: 'Invalid or revoked IndiaMART listener URL.', code: 'unauthorized' }, 401);
  }
  const slugLimit = await limited(c, `leadint:${source.public_slug}`, INTEGRATION_LIMIT_PER_SLUG);
  if (slugLimit) return slugLimit;

  const text = await readBody(c);
  if (text === null) return c.json({ message: 'Payload too large.', code: 'payload_too_large' }, 413);
  const payload = parseJson(text);
  if (!payload || typeof payload !== 'object') return c.json({ message: 'Malformed JSON payload.', code: 'invalid_json' }, 400);

  let captured = 0;
  let skipped = 0;
  for (const rec of indiaMartRecords(payload)) {
    const mapped = mapIndiaMartRecord(rec);
    if (!mapped) {
      skipped++;
      continue;
    }
    const r = await captureExternalLead(c.env, source, mapped.externalId, mapped.input, {
      fallbackBaseUrl: new URL(c.req.url).origin, waitUntil: waitUntilOf(c),
    });
    if (r.status === 'created' || r.status === 'updated') captured++;
    else skipped++;
  }
  // Always 200 for a verified push: IndiaMART deactivates listeners that keep failing.
  return c.json({ CODE: 200, STATUS: 'SUCCESS', captured, skipped });
});

// ------------------------------------------------------------------ Meta Lead Ads

leadIntegrationsPublicApp.get('/hooks/meta/:slug', async (c) => {
  const tooMany = await ipLimited(c, 'meta');
  if (tooMany) return tooMany;
  const source = await findActiveSource(c.env.DB, c.req.param('slug') ?? '', 'meta');
  const mode = c.req.query('hub.mode');
  const challenge = c.req.query('hub.challenge') ?? '';
  if (!source || mode !== 'subscribe' || !(await verifyWebhookToken(c.req.query('hub.verify_token'), source.secret_hash))) {
    return c.text('Forbidden', 403);
  }
  // Echo only what Meta sends (a number), never arbitrary markup.
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(challenge)) return c.text('Bad challenge', 400);
  return c.text(challenge, 200);
});

leadIntegrationsPublicApp.post('/hooks/meta/:slug', async (c) => {
  const tooMany = await ipLimited(c, 'meta');
  if (tooMany) return tooMany;

  const text = await readBody(c);
  if (text === null) return c.json({ message: 'Payload too large.' }, 413);
  const source = await findActiveSource(c.env.DB, c.req.param('slug') ?? '', 'meta');
  const cfg = source ? await readConfig(c.env, source) : null;
  if (!source || !cfg?.app_secret || !(await verifyMetaSignature(cfg.app_secret, text, c.req.header('x-hub-signature-256')))) {
    return c.json({ message: 'Invalid signature.', code: 'invalid_signature' }, 401);
  }
  const slugLimit = await limited(c, `leadint:${source.public_slug}`, INTEGRATION_LIMIT_PER_SLUG);
  if (slugLimit) return slugLimit;

  const payload = parseJson(text);
  if (!payload || typeof payload !== 'object') return c.json({ message: 'Malformed JSON payload.', code: 'invalid_json' }, 400);

  let retry = false;
  for (const leadgenId of metaLeadgenIds(payload)) {
    if (!(await handleMetaLead(c, source, leadgenId, cfg))) retry = true;
  }
  // 500 makes Meta redeliver later; the claimed-once ids keep that from duplicating leads.
  if (retry) return c.json({ message: 'Temporary problem fetching a lead. Please retry.' }, 500);
  return c.json({ success: true });
});

/** False = transient failure (Meta should redeliver). Permanent failures are recorded and dropped. */
async function handleMetaLead(c: Context<{ Bindings: Env }>, source: LeadSourceRow, leadgenId: string, cfg: { page_access_token?: string; app_secret?: string }): Promise<boolean> {
  const id = leadgenId.slice(0, 200);
  if (!(await claimExternalId(c.env.DB, source, id))) return true;
  const fetched = await fetchMetaLead(c.env, id, cfg);
  if (!fetched.ok) {
    await releaseExternalId(c.env.DB, source, id);
    if (fetched.transient) return false;
    // e.g. OAuthException: the page token expired or lacks leads_retrieval. The owner must reconnect.
    await setSourceError(c.env, source, 'meta_token_invalid');
    return true;
  }
  const mapped = mapMetaLead(id, fetched.fieldData);
  if (!mapped) return true; // no phone question on the form: nothing to call (the claim stays)
  await captureExternalLead(c.env, source, id, mapped.input, {
    fallbackBaseUrl: new URL(c.req.url).origin, waitUntil: waitUntilOf(c), alreadyClaimed: true,
  });
  if (source.last_error) await setSourceError(c.env, source, null);
  return true;
}

export { leadIntegrationsPublicApp };
