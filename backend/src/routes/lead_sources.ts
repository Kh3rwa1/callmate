/**
 * Owner APIs for speed-to-lead capture sources (hosted enquiry form, webhook, and the Google Ads /
 * IndiaMART / Meta Lead Ads integrations). Scoped to the caller's business. Secrets are returned
 * once, on creation: only their hash (or, for secrets the server must use, an encrypted copy) is kept.
 */
import { Hono } from 'hono';
import { Env, AuthUser } from '../types';
import { parseJsonBody, createLeadSourceSchema, patchLeadSourceSchema } from '../schemas/validation';
import { formatLeadSource, newWebhookToken, randomToken, sha256Hex, SLUG_LENGTH } from '../services/lead_capture';
import {
  encryptConfig, IntegrationNotConfiguredError, newGoogleAdsKey, newIndiaMartPushToken, newMetaVerifyToken,
} from '../services/lead_integrations';

const leadSourcesApp = new Hono<{ Bindings: Env; Variables: { user: AuthUser } }>();

/** Active sources of each non-form kind a business may hold at once (a form is one per business). */
export const MAX_ACTIVE_WEBHOOKS = 5;

const SELECT_SOURCE = `SELECT s.*, (SELECT COUNT(*) FROM leads l WHERE l.lead_source_id = s.id AND l.business_id = s.business_id) AS leads_count
  FROM lead_sources s`;

function baseUrl(c: any): string {
  return c.env.PUBLIC_API_BASE_URL || new URL(c.req.url).origin;
}

async function activeSource(db: D1Database, businessId: string, id: string) {
  return db.prepare(`${SELECT_SOURCE} WHERE s.id = ? AND s.business_id = ? AND s.revoked_at IS NULL`)
    .bind(id, businessId).first<any>();
}

// GET /lead-sources: active sources, oldest first (the form first in practice).
leadSourcesApp.get('/lead-sources', async (c) => {
  const user = c.get('user');
  const { results } = await c.env.DB.prepare(
    `${SELECT_SOURCE} WHERE s.business_id = ? AND s.revoked_at IS NULL ORDER BY s.created_at ASC, s.id ASC`
  ).bind(user.business_id).all<any>();
  const base = baseUrl(c);
  return c.json({ items: (results ?? []).map((r) => formatLeadSource(r, base)) });
});

// POST /lead-sources {kind, auto_call?, ...integration secrets}
// form: idempotent, returns the business's active form if it has one (200) or a new one (201).
// Everything else is always new (201) and carries `token`, shown once (only its SHA-256 is kept):
//   webhook     bearer token
//   google_ads  the key to paste into the Google Ads lead form (also sent as `google_key`)
//   indiamart   push-listener token; `push_url` is the full URL to paste into IndiaMART's Push API
//   meta        the verify token for the Meta app's webhook settings (also sent as `verify_token`)
// IndiaMART's CRM key and Meta's app secret / page token are stored encrypted and never returned.
leadSourcesApp.post('/lead-sources', async (c) => {
  const user = c.get('user');
  const parsed = await parseJsonBody(c, createLeadSourceSchema);
  if (!parsed.success) return parsed.response;
  const body = parsed.data;
  const { kind } = body;
  const autoCall = body.auto_call === false ? 0 : 1;
  const base = baseUrl(c);

  if (kind === 'form') {
    const existing = await c.env.DB.prepare(
      `${SELECT_SOURCE} WHERE s.business_id = ? AND s.kind = 'form' AND s.revoked_at IS NULL ORDER BY s.created_at ASC LIMIT 1`
    ).bind(user.business_id).first<any>();
    if (existing) return c.json(formatLeadSource(existing, base), 200);
  } else {
    const count = await c.env.DB.prepare(
      `SELECT COUNT(*) AS cnt FROM lead_sources WHERE business_id = ? AND kind = ? AND revoked_at IS NULL`
    ).bind(user.business_id, kind).first<{ cnt: number }>();
    if ((count?.cnt ?? 0) >= MAX_ACTIVE_WEBHOOKS) {
      return c.json({
        message: `You can have at most ${MAX_ACTIVE_WEBHOOKS} connections of this kind. Turn one off first.`,
        code: 'too_many_sources',
      }, 409);
    }
  }

  let token: string | null = null;
  let config: string | null = null;
  try {
    switch (body.kind) {
      case 'webhook': token = newWebhookToken(); break;
      case 'google_ads': token = newGoogleAdsKey(); break;
      case 'indiamart':
        token = newIndiaMartPushToken();
        config = await encryptConfig(c.env, { crm_key: body.crm_key });
        break;
      case 'meta':
        token = newMetaVerifyToken();
        config = await encryptConfig(c.env, { app_secret: body.app_secret, page_access_token: body.page_access_token });
        break;
    }
  } catch (err) {
    if (err instanceof IntegrationNotConfiguredError) {
      return c.json({ message: 'Integrations are not configured on the server yet.', code: 'not_configured' }, 503);
    }
    throw err;
  }

  const id = `lsrc_${crypto.randomUUID().slice(0, 12)}`;
  const slug = randomToken(SLUG_LENGTH);
  const secretHash = token ? await sha256Hex(token) : null;
  await c.env.DB.prepare(
    `INSERT INTO lead_sources (id, business_id, kind, public_slug, secret_hash, auto_call, config_encrypted, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, datetime('now'))`
  ).bind(id, user.business_id, kind, slug, secretHash, autoCall, config).run();

  const created = formatLeadSource(await activeSource(c.env.DB, user.business_id, id), base);
  return c.json({
    ...created,
    ...(token ? { token } : {}),
    ...(kind === 'google_ads' ? { google_key: token } : {}),
    ...(kind === 'indiamart' ? { push_url: `${created.url}?key=${token}` } : {}),
    ...(kind === 'meta' ? { verify_token: token } : {}),
  }, 201);
});

// PATCH /lead-sources/:id {auto_call}
leadSourcesApp.patch('/lead-sources/:id', async (c) => {
  const user = c.get('user');
  const id = c.req.param('id');
  const parsed = await parseJsonBody(c, patchLeadSourceSchema);
  if (!parsed.success) return parsed.response;
  const res = await c.env.DB.prepare(
    'UPDATE lead_sources SET auto_call = ? WHERE id = ? AND business_id = ? AND revoked_at IS NULL'
  ).bind(parsed.data.auto_call ? 1 : 0, id, user.business_id).run();
  if ((res.meta?.changes ?? 0) === 0) return c.json({ message: 'Lead source not found.', code: 'not_found' }, 404);
  return c.json(formatLeadSource(await activeSource(c.env.DB, user.business_id, id), baseUrl(c)));
});

// POST /lead-sources/:id/revoke: the link / token stops working at once (404 / 401).
leadSourcesApp.post('/lead-sources/:id/revoke', async (c) => {
  const user = c.get('user');
  const id = c.req.param('id');
  const res = await c.env.DB.prepare(
    `UPDATE lead_sources SET revoked_at = datetime('now') WHERE id = ? AND business_id = ? AND revoked_at IS NULL`
  ).bind(id, user.business_id).run();
  if ((res.meta?.changes ?? 0) === 0) return c.json({ message: 'Lead source not found.', code: 'not_found' }, 404);
  return c.json({ success: true });
});

export { leadSourcesApp };
