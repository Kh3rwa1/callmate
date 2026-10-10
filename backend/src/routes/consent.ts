/** GET /leads/:id/consent-history: the lead's consent evidence trail, newest first. */
import { Hono } from 'hono';
import { Env, AuthUser } from '../types';

const consentApp = new Hono<{ Bindings: Env; Variables: { user: AuthUser } }>();

export const CONSENT_HISTORY_LIMIT = 100;

consentApp.get('/leads/:id/consent-history', async (c) => {
  const user = c.get('user');
  const leadId = c.req.param('id');
  const lead = await c.env.DB.prepare('SELECT id FROM leads WHERE id = ? AND business_id = ?')
    .bind(leadId, user.business_id).first();
  if (!lead) return c.json({ message: 'Lead not found.', code: 'not_found' }, 404);

  const { results } = await c.env.DB.prepare(
    `SELECT id, consent_value, source, text_version, created_at FROM consent_events
     WHERE business_id = ? AND lead_id = ?
     ORDER BY created_at DESC, rowid DESC LIMIT ?`
  ).bind(user.business_id, leadId, CONSENT_HISTORY_LIMIT).all<any>();

  // ip_hash is evidence for disputes, not something the app needs to show.
  return c.json({ items: results ?? [] });
});

export { consentApp };
