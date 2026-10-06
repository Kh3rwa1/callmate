import { Hono } from 'hono';
import { Env, AuthUser } from '../types';

const campaignsApp = new Hono<{ Bindings: Env; Variables: { user: AuthUser } }>();

function formatCampaign(row: any) {
  if (!row) return null;
  return {
    id: row.id,
    purpose: row.purpose,
    calling_hours_start: row.calling_hours_start,
    calling_hours_end: row.calling_hours_end,
    options: row.options ? JSON.parse(row.options) : {},
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

  sql += ' ORDER BY created_at DESC';
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
  const body = await c.req.json<any>().catch(() => ({}));

  const leadIds: string[] = body.lead_ids || [];
  const purpose = body.purpose || 'Call new leads and qualify interest';
  const hoursStart = body.calling_hours_start ?? 10;
  const hoursEnd = body.calling_hours_end ?? 19;
  const options = JSON.stringify(body.options || {});

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

  const created = await c.env.DB.prepare('SELECT * FROM campaigns WHERE id = ?').bind(id).first();
  return c.json(formatCampaign(created));
});

// POST /campaigns/:id/start
campaignsApp.post('/campaigns/:id/start', async (c) => {
  const user = c.get('user');
  const id = c.req.param('id');

  const existing = await c.env.DB.prepare('SELECT * FROM campaigns WHERE id = ? AND business_id = ?').bind(id, user.business_id).first<any>();
  if (!existing) return c.json({ message: 'Campaign not found.', code: 'not_found' }, 404);

  // In production with Sarvam API key:
  // Trigger Sarvam Outbound Campaign API or schedule queue
  if (c.env.SARVAM_API_KEY && c.env.SARVAM_WORKSPACE_ID) {
    // If real Sarvam credentials present, can trigger Sarvam Campaign API
    console.log(`[Sarvam] Initiating outbound campaign ${id} for tenant ${user.business_id}`);
  }

  await c.env.DB.prepare(
    `UPDATE campaigns SET status = 'running', started_at = datetime('now') WHERE id = ?`
  ).bind(id).run();

  const updated = await c.env.DB.prepare('SELECT * FROM campaigns WHERE id = ?').bind(id).first();
  return c.json(formatCampaign(updated));
});

// POST /campaigns/:id/stop
campaignsApp.post('/campaigns/:id/stop', async (c) => {
  const user = c.get('user');
  const id = c.req.param('id');

  await c.env.DB.prepare(
    `UPDATE campaigns SET status = 'paused', completed_at = datetime('now') WHERE id = ? AND business_id = ?`
  ).bind(id, user.business_id).run();

  const updated = await c.env.DB.prepare('SELECT * FROM campaigns WHERE id = ?').bind(id).first();
  return c.json(formatCampaign(updated));
});

export { campaignsApp };
