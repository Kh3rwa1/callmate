import { Hono } from 'hono';
import { Env, AuthUser } from '../types';
import { safeJsonParse } from '../utils/json';
import { parseJsonBody, createCampaignSchema } from '../schemas/validation';
import { enqueueCampaignJobs, maybeCompleteCampaign } from '../services/campaign_queue';
import { parseLimit, MAX_LIST_LIMIT } from '../utils/pagination';
import { isPlanBlocked, PLAN_BLOCKED_BODY } from '../services/plans';

const campaignsApp = new Hono<{ Bindings: Env; Variables: { user: AuthUser } }>();

function formatCampaign(row: any) {
  if (!row) return null;
  return {
    id: row.id,
    purpose: row.purpose,
    calling_hours_start: row.calling_hours_start,
    calling_hours_end: row.calling_hours_end,
    options: safeJsonParse(row.options, {}),
    status: row.status,
    stats: {
      total: row.total_leads || 0,
      completed: row.completed_leads || 0,
      connected: row.connected_leads || 0,
      hot: row.hot_leads || 0,
      warm: row.warm_leads || 0,
    },
    cost_inr: row.cost_inr || 0,
    started_at: row.started_at,
    completed_at: row.completed_at,
    attested_by: row.attested_by || null,
    attested_at: row.attested_at || null,
  };
}

// GET /campaigns
campaignsApp.get('/campaigns', async (c) => {
  const user = c.get('user');
  const status = c.req.query('status');

  let sql = 'SELECT * FROM campaigns WHERE business_id = ?';
  const params: any[] = [user.business_id];

  if (status) {
    sql += ' AND status = ?';
    params.push(status);
  }

  sql += ' ORDER BY created_at DESC LIMIT ?';
  params.push(parseLimit(c.req.query('limit'), MAX_LIST_LIMIT, MAX_LIST_LIMIT));
  const { results } = await c.env.DB.prepare(sql).bind(...params).all<any>();
  return c.json(results.map(formatCampaign));
});

// GET /campaigns/:id
campaignsApp.get('/campaigns/:id', async (c) => {
  const user = c.get('user');
  const id = c.req.param('id');
  const row = await c.env.DB.prepare('SELECT * FROM campaigns WHERE id = ? AND business_id = ?').bind(id, user.business_id).first();
  if (!row) return c.json({ message: 'Campaign not found.', code: 'not_found' }, 404);
  return c.json(formatCampaign(row));
});

// POST /campaigns
campaignsApp.post('/campaigns', async (c) => {
  const user = c.get('user');
  const parsed = await parseJsonBody(c, createCampaignSchema);
  if (!parsed.success) {
    return parsed.response;
  }
  const body = parsed.data;

  const leadIds: string[] = body.lead_ids || [];
  const purpose = body.purpose || body.title || 'Call new leads and qualify interest';
  const hoursStart = body.calling_hours_start ?? 10;
  const hoursEnd = body.calling_hours_end ?? 19;
  const options = JSON.stringify(body.options || {});

  // Tenant isolation: verify EVERY lead_id belongs to user.business_id
  if (leadIds.length > 0) {
    let validCount = 0;
    const chunkSize = 80;
    for (let i = 0; i < leadIds.length; i += chunkSize) {
      const slice = leadIds.slice(i, i + chunkSize);
      const placeholders = slice.map(() => '?').join(',');
      const check = await c.env.DB.prepare(
        `SELECT COUNT(*) as cnt FROM leads WHERE business_id = ? AND id IN (${placeholders})`
      ).bind(user.business_id, ...slice).first<{ cnt: number }>();
      validCount += check?.cnt || 0;
    }

    if (validCount !== leadIds.length) {
      return c.json({ message: 'One or more leads do not belong to your business.', code: 'foreign_lead_forbidden' }, 400);
    }
  }

  const id = `cmp_${crypto.randomUUID().slice(0, 12)}`;
  const totalLeads = leadIds.length;
  // Estimate cost: leadCount * 0.68 * 2.2 * 6 INR
  const costInr = Math.round(totalLeads * 0.68 * 2.2 * 6);

  await c.env.DB.prepare(
    `INSERT INTO campaigns (id, business_id, purpose, calling_hours_start, calling_hours_end, options, status, total_leads, cost_inr, created_at)
     VALUES (?, ?, ?, ?, ?, ?, 'draft', ?, ?, datetime('now'))`
  ).bind(id, user.business_id, purpose, hoursStart, hoursEnd, options, totalLeads, costInr).run();

  // Link leads
  if (leadIds.length > 0) {
    const statements = leadIds.map((lid) =>
      c.env.DB.prepare('INSERT INTO campaign_leads (campaign_id, lead_id, status) VALUES (?, ?, \'pending\')').bind(id, lid)
    );
    const chunkSize = 80;
    for (let i = 0; i < statements.length; i += chunkSize) {
      await c.env.DB.batch(statements.slice(i, i + chunkSize));
    }
  }

  const created = await c.env.DB.prepare('SELECT * FROM campaigns WHERE id = ? AND business_id = ?').bind(id, user.business_id).first();
  return c.json(formatCampaign(created));
});

// POST /campaigns/:id/start
campaignsApp.post('/campaigns/:id/start', async (c) => {
  const user = c.get('user');
  const id = c.req.param('id');

  const existing = await c.env.DB.prepare('SELECT * FROM campaigns WHERE id = ? AND business_id = ?').bind(id, user.business_id).first<any>();
  if (!existing) return c.json({ message: 'Campaign not found.', code: 'not_found' }, 404);

  // 2.3: Billing integrity check
  // Compute estimated minutes needed: total_leads * 2.2
  const totalLeads = existing.total_leads || 0;
  const estimatedMinutes = Math.max(1, Math.ceil(totalLeads * 2.2));

  if (await isPlanBlocked(c.env.DB, user.business_id)) return c.json(PLAN_BLOCKED_BODY, 402);
  const usage = await c.env.DB.prepare(
    'SELECT included_minutes, minutes_used FROM usage WHERE business_id = ?'
  ).bind(user.business_id).first<{ included_minutes: number; minutes_used: number }>();

  if (usage) {
    const remainingMinutes = Math.max(0, (usage.included_minutes || 0) - (usage.minutes_used || 0));
    if (remainingMinutes < estimatedMinutes) {
      return c.json({
        message: `Insufficient minutes remaining on your plan. Required estimate: ${estimatedMinutes} min, Remaining: ${remainingMinutes} min. Please top up your plan.`,
        code: 'insufficient_minutes',
        required_minutes: estimatedMinutes,
        remaining_minutes: remainingMinutes,
      }, 402);
    }
  }

  let consentAttestation = false;
  try {
    const rawBody = await c.req.json().catch(() => ({}));
    if (rawBody && typeof rawBody === 'object' && rawBody.consent_attestation === true) {
      consentAttestation = true;
    }
  } catch {
    // optional body
  }

  // Atomic transition: only draft/paused campaigns can start (prevents double-start)
  const started = await c.env.DB.prepare(
    `UPDATE campaigns
     SET status = 'running',
         started_at = COALESCE(started_at, datetime('now')),
         attested_by = CASE WHEN ? = 1 THEN ? ELSE attested_by END,
         attested_at = CASE WHEN ? = 1 THEN datetime('now') ELSE attested_at END
     WHERE id = ? AND business_id = ? AND status IN ('draft','paused')`
  ).bind(consentAttestation ? 1 : 0, user.id, consentAttestation ? 1 : 0, id, user.business_id).run();
  if ((started.meta?.changes ?? 0) === 0) {
    return c.json({ message: 'Campaign is already running or finished.', code: 'invalid_state' }, 409);
  }

  const { results } = await c.env.DB.prepare(`
    SELECT l.id, l.do_not_call, l.consent, cl.status AS cl_status
    FROM campaign_leads cl JOIN leads l ON cl.lead_id = l.id
    WHERE cl.campaign_id = ? AND l.business_id = ?
  `).bind(id, user.business_id).all<{ id: string; do_not_call: number; consent: string; cl_status: string }>();

  const toQueue: string[] = [];
  const skipStmts: D1PreparedStatement[] = [];
  for (const l of results ?? []) {
    if (l.do_not_call === 1 || l.consent === 'opt_out') {
      skipStmts.push(c.env.DB.prepare(`UPDATE campaign_leads SET status = 'skipped_dnc' WHERE campaign_id = ? AND lead_id = ?`).bind(id, l.id));
    } else if (l.consent === 'unknown' && !consentAttestation) {
      skipStmts.push(c.env.DB.prepare(`UPDATE campaign_leads SET status = 'skipped_no_consent' WHERE campaign_id = ? AND lead_id = ?`).bind(id, l.id));
    } else if (['pending', 'rescheduled', 'retry_pending'].includes(l.cl_status)) {
      toQueue.push(l.id); // completed / failed / calling leads are never re-dialled
    }
  }
  for (let i = 0; i < skipStmts.length; i += 80) await c.env.DB.batch(skipStmts.slice(i, i + 80));
  const queued = toQueue.length
    ? await enqueueCampaignJobs(c.env, id, user.business_id, toQueue, new URL(c.req.url).origin)
    : 0;
  // Every lead skipped (DNC / no consent / already done): nothing will ever finish it otherwise.
  if (queued === 0) await maybeCompleteCampaign(c.env.DB, id);

  const updated = await c.env.DB.prepare('SELECT * FROM campaigns WHERE id = ? AND business_id = ?').bind(id, user.business_id).first();
  return c.json(formatCampaign(updated));
});

// POST /campaigns/:id/stop
campaignsApp.post('/campaigns/:id/stop', async (c) => {
  const user = c.get('user');
  const id = c.req.param('id');

  const existing = await c.env.DB.prepare('SELECT id FROM campaigns WHERE id = ? AND business_id = ?').bind(id, user.business_id).first();
  if (!existing) return c.json({ message: 'Campaign not found.', code: 'not_found' }, 404);

  await c.env.DB.prepare(
    `UPDATE campaigns SET status = 'paused', completed_at = datetime('now') WHERE id = ? AND business_id = ?`
  ).bind(id, user.business_id).run();

  // Stop queued leads
  await c.env.DB.prepare(
    `UPDATE campaign_leads SET status = 'pending' WHERE campaign_id = ? AND status = 'queued'`
  ).bind(id).run();

  const updated = await c.env.DB.prepare('SELECT * FROM campaigns WHERE id = ? AND business_id = ?').bind(id, user.business_id).first();
  return c.json(formatCampaign(updated));
});

export { campaignsApp };
