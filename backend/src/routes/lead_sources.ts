/**
 * Owner APIs for speed-to-lead capture sources (hosted enquiry form, webhook). Scoped to the
 * caller's business. A webhook's bearer token is returned once, on creation; only its hash is kept.
 */
import { Hono } from 'hono';
import { Env, AuthUser } from '../types';
import { parseJsonBody, createLeadSourceSchema, patchLeadSourceSchema } from '../schemas/validation';
import { formatLeadSource, newWebhookToken, randomToken, sha256Hex, SLUG_LENGTH } from '../services/lead_capture';

const leadSourcesApp = new Hono<{ Bindings: Env; Variables: { user: AuthUser } }>();

/** Active webhooks a business may hold at once (a form is one per business). */
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

// POST /lead-sources {kind, auto_call?}
// form: idempotent, returns the business's active form if it has one (200) or a new one (201).
// webhook: always new (201), with `token` (shown once).
leadSourcesApp.post('/lead-sources', async (c) => {
  const user = c.get('user');
  const parsed = await parseJsonBody(c, createLeadSourceSchema);
  if (!parsed.success) return parsed.response;
  const { kind } = parsed.data;
  const autoCall = parsed.data.auto_call === false ? 0 : 1;
  const base = baseUrl(c);

  if (kind === 'form') {
    const existing = await c.env.DB.prepare(
      `${SELECT_SOURCE} WHERE s.business_id = ? AND s.kind = 'form' AND s.revoked_at IS NULL ORDER BY s.created_at ASC LIMIT 1`
    ).bind(user.business_id).first<any>();
    if (existing) return c.json(formatLeadSource(existing, base), 200);
  } else {
    const count = await c.env.DB.prepare(
      `SELECT COUNT(*) AS cnt FROM lead_sources WHERE business_id = ? AND kind = 'webhook' AND revoked_at IS NULL`
    ).bind(user.business_id).first<{ cnt: number }>();
    if ((count?.cnt ?? 0) >= MAX_ACTIVE_WEBHOOKS) {
      return c.json({
        message: `You can have at most ${MAX_ACTIVE_WEBHOOKS} webhooks. Revoke one first.`,
        code: 'too_many_sources',
      }, 409);
    }
  }

  const id = `lsrc_${crypto.randomUUID().slice(0, 12)}`;
  const slug = randomToken(SLUG_LENGTH);
  const token = kind === 'webhook' ? newWebhookToken() : null;
  const secretHash = token ? await sha256Hex(token) : null;
  await c.env.DB.prepare(
    `INSERT INTO lead_sources (id, business_id, kind, public_slug, secret_hash, auto_call, created_at)
     VALUES (?, ?, ?, ?, ?, ?, datetime('now'))`
  ).bind(id, user.business_id, kind, slug, secretHash, autoCall).run();

  const created = await activeSource(c.env.DB, user.business_id, id);
  return c.json({ ...formatLeadSource(created, base), ...(token ? { token } : {}) }, 201);
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
