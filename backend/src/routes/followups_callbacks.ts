import { Hono } from 'hono';
import { Env, AuthUser } from '../types';

const fcApp = new Hono<{ Bindings: Env; Variables: { user: AuthUser } }>();

// ------------------------------------------------------------- Follow-ups
function formatFollowUp(row: any) {
  if (!row) return null;
  return {
    id: row.id,
    lead_id: row.lead_id,
    call_id: row.call_id,
    lead_name: row.lead_name || 'Customer',
    lead_phone: row.lead_phone || '',
    message: row.message,
    status: row.status,
    opened_at: row.opened_at,
    created_at: row.created_at,
  };
}

fcApp.get('/followups', async (c) => {
  const user = c.get('user');
  const status = c.req.query('status');
  const callId = c.req.query('call_id');

  let sql = `
    SELECT f.*, l.name as lead_name, l.phone as lead_phone
    FROM followups f
    LEFT JOIN leads l ON f.lead_id = l.id
    WHERE f.business_id = ?
  `;
  const params: any[] = [user.business_id];

  if (status) {
    sql += ' AND f.status = ?';
    params.push(status);
  }
  if (callId) {
    sql += ' AND f.call_id = ?';
    params.push(callId);
  }

  sql += ' ORDER BY f.created_at DESC';
  const { results } = await c.env.DB.prepare(sql).bind(...params).all<any>();
  return c.json(results.map(formatFollowUp));
});

fcApp.get('/followups/:id', async (c) => {
  const user = c.get('user');
  const id = c.req.param('id');
  const sql = `
    SELECT f.*, l.name as lead_name, l.phone as lead_phone
    FROM followups f
    LEFT JOIN leads l ON f.lead_id = l.id
    WHERE f.id = ? AND f.business_id = ?
  `;
  const row = await c.env.DB.prepare(sql).bind(id, user.business_id).first();
  if (!row) return c.json({ message: 'Follow-up not found.', code: 'not_found' }, 404);
  return c.json(formatFollowUp(row));
});

fcApp.patch('/followups/:id', async (c) => {
  const user = c.get('user');
  const id = c.req.param('id');
  const body = await c.req.json<any>().catch(() => ({}));

  const existing = await c.env.DB.prepare('SELECT * FROM followups WHERE id = ? AND business_id = ?').bind(id, user.business_id).first<any>();
  if (!existing) return c.json({ message: 'Follow-up not found.', code: 'not_found' }, 404);

  const message = body.message !== undefined ? body.message : existing.message;
  const status = body.status !== undefined ? body.status : existing.status;
  const openedAt = body.opened_at !== undefined ? body.opened_at : existing.opened_at;

  await c.env.DB.prepare(
    `UPDATE followups SET message = ?, status = ?, opened_at = ? WHERE id = ? AND business_id = ?`
  ).bind(message, status, openedAt, id, user.business_id).run();

  const sql = `
    SELECT f.*, l.name as lead_name, l.phone as lead_phone
    FROM followups f
    LEFT JOIN leads l ON f.lead_id = l.id
    WHERE f.id = ? AND f.business_id = ?
  `;
  const updated = await c.env.DB.prepare(sql).bind(id, user.business_id).first();
  return c.json(formatFollowUp(updated));
});

// ------------------------------------------------------------- Callbacks
function formatCallback(row: any) {
  if (!row) return null;
  return {
    id: row.id,
    lead_id: row.lead_id,
    lead_name: row.lead_name || 'Customer',
    lead_phone: row.lead_phone || '',
    scheduled_at: row.scheduled_at,
    note: row.note,
    status: row.status,
    created_at: row.created_at,
  };
}

fcApp.get('/callbacks', async (c) => {
  const user = c.get('user');
  const sql = `
    SELECT cb.*, l.phone as lead_phone
    FROM callbacks cb
    LEFT JOIN leads l ON cb.lead_id = l.id
    WHERE cb.business_id = ?
    ORDER BY cb.scheduled_at ASC
  `;
  const { results } = await c.env.DB.prepare(sql).bind(user.business_id).all<any>();
  return c.json(results.map(formatCallback));
});

fcApp.post('/callbacks', async (c) => {
  const user = c.get('user');
  const body = await c.req.json<any>().catch(() => ({}));

  const leadId = body.lead_id;
  const scheduledAt = body.scheduled_at || new Date().toISOString();
  const note = body.note || null;

  if (!leadId) return c.json({ message: 'lead_id is required.', code: 'invalid_request' }, 400);

  const lead = await c.env.DB.prepare('SELECT name, phone FROM leads WHERE id = ? AND business_id = ?').bind(leadId, user.business_id).first<any>();
  const leadName = lead?.name || 'Customer';

  const id = `cb_${crypto.randomUUID().slice(0, 12)}`;

  await c.env.DB.batch([
    c.env.DB.prepare(
      `INSERT INTO callbacks (id, business_id, lead_id, lead_name, scheduled_at, note, status, created_at)
       VALUES (?, ?, ?, ?, ?, ?, 'scheduled', datetime('now'))`
    ).bind(id, user.business_id, leadId, leadName, scheduledAt, note),
    c.env.DB.prepare('UPDATE leads SET callback_at = ? WHERE id = ?').bind(scheduledAt, leadId),
  ]);

  const created = await c.env.DB.prepare('SELECT * FROM callbacks WHERE id = ?').bind(id).first();
  return c.json(formatCallback({ ...created, lead_phone: lead?.phone }));
});

fcApp.patch('/callbacks/:id', async (c) => {
  const user = c.get('user');
  const id = c.req.param('id');
  const body = await c.req.json<any>().catch(() => ({}));

  const status = body.status || 'done';

  await c.env.DB.prepare(
    'UPDATE callbacks SET status = ? WHERE id = ? AND business_id = ?'
  ).bind(status, id, user.business_id).run();

  const sql = `
    SELECT cb.*, l.phone as lead_phone
    FROM callbacks cb
    LEFT JOIN leads l ON cb.lead_id = l.id
    WHERE cb.id = ? AND cb.business_id = ?
  `;
  const updated = await c.env.DB.prepare(sql).bind(id, user.business_id).first();
  return c.json(formatCallback(updated));
});

export { fcApp };
