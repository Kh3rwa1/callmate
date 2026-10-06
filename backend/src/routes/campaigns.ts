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

  // Tenant isolation: verify EVERY lead_id belongs to user.business_id
  if (leadIds.length > 0) {
    const placeholders = leadIds.map(() => '?').join(',');
    const check = await c.env.DB.prepare(
      `SELECT COUNT(*) as cnt FROM leads WHERE business_id = ? AND id IN (${placeholders})`
    ).bind(user.business_id, ...leadIds).first<{ cnt: number }>();

    if (!check || check.cnt !== leadIds.length) {
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

  await c.env.DB.prepare(
    `UPDATE campaigns SET status = 'running', started_at = datetime('now') WHERE id = ? AND business_id = ?`
  ).bind(id, user.business_id).run();

  // Fetch campaign leads with strict tenant isolation: AND l.business_id = ?
  const campaignLeads = await c.env.DB.prepare(`
    SELECT l.* FROM campaign_leads cl
    JOIN leads l ON cl.lead_id = l.id
    WHERE cl.campaign_id = ? AND l.business_id = ?
  `).bind(id, user.business_id).all<any>();

  const sarvamApiKey = c.env.SARVAM_API_KEY;
  const orgId = c.env.SARVAM_ORG_ID || 'org_callpilot';
  const workspaceId = c.env.SARVAM_WORKSPACE_ID || 'ws_callpilot';
  const appId = c.env.SARVAM_ADMISSIONS_APP_ID || 'app_callpilot_voice';

  if (sarvamApiKey && !sarvamApiKey.startsWith('mock-')) {
    const business = await c.env.DB.prepare('SELECT * FROM businesses WHERE id = ?').bind(user.business_id).first<any>();
    const agent = await c.env.DB.prepare('SELECT * FROM agents WHERE business_id = ?').bind(user.business_id).first<any>();
    const url = new URL(c.req.url);
    const webhookUrl = `${url.origin}/webhooks/sarvam`;

    for (const lead of campaignLeads.results) {
      const callId = `call_${crypto.randomUUID().slice(0, 12)}`;

      // Insert active call record
      await c.env.DB.prepare(`
        INSERT INTO calls (id, business_id, lead_id, lead_name, lead_phone, status, started_at)
        VALUES (?, ?, ?, ?, ?, 'calling', datetime('now'))
      `).bind(callId, user.business_id, lead.id, lead.name, lead.phone).run();

      await c.env.DB.prepare(`UPDATE leads SET status = 'calling', updated_at = datetime('now') WHERE id = ? AND business_id = ?`).bind(lead.id, user.business_id).run();

      try {
        const sarvamRes = await fetch(`https://apps.sarvam.ai/api/outbounds/v1/orgs/${orgId}/workspaces/${workspaceId}/outbounds`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'X-API-Key': sarvamApiKey,
          },
          body: JSON.stringify({
            app_config: { app_id: appId },
            user_config: { phone_number: lead.phone },
            agent_variables: {
              call_id: callId,
              campaign_id: id,
              lead_id: lead.id,
              lead_name: lead.name,
              business_name: business?.name || 'CallPilot Business',
              agent_name: agent?.name || 'Riya',
              agent_role: agent?.role || 'Assistant',
              course_interest: lead.course_interest || lead.interest || '',
            },
            webhook_config: {
              webhook_url: webhookUrl,
            },
          }),
        });

        const resData = await sarvamRes.json().catch(() => null) as any;
        if (resData?.interaction_id || resData?.id || resData?.attempt_id) {
          const interactionId = resData.interaction_id || resData.id || resData.attempt_id;
          await c.env.DB.prepare('UPDATE calls SET interaction_id = ? WHERE id = ? AND business_id = ?').bind(interactionId, callId, user.business_id).run();
        }
      } catch (err: any) {
        console.error(`[Sarvam Campaign Outbound Error] Lead ${lead.id}:`, err?.message || err);
      }
    }
  }

  const updated = await c.env.DB.prepare('SELECT * FROM campaigns WHERE id = ? AND business_id = ?').bind(id, user.business_id).first();
  return c.json(formatCampaign(updated));
});

// POST /campaigns/:id/stop
campaignsApp.post('/campaigns/:id/stop', async (c) => {
  const user = c.get('user');
  const id = c.req.param('id');

  await c.env.DB.prepare(
    `UPDATE campaigns SET status = 'paused', completed_at = datetime('now') WHERE id = ? AND business_id = ?`
  ).bind(id, user.business_id).run();

  const updated = await c.env.DB.prepare('SELECT * FROM campaigns WHERE id = ? AND business_id = ?').bind(id, user.business_id).first();
  return c.json(formatCampaign(updated));
});

export { campaignsApp };
