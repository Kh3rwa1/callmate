import { Hono } from 'hono';
import { Env, AuthUser } from '../types';

const leadsApp = new Hono<{ Bindings: Env; Variables: { user: AuthUser } }>();

function formatLead(row: any) {
  if (!row) return null;
  const scoreObj = row.score !== null && row.score !== undefined ? {
    value: row.score,
    temperature: row.temperature || (row.score >= 75 ? 'hot' : (row.score >= 45 ? 'warm' : 'cold')),
    intent: row.score >= 70 ? 'interested' : 'exploring',
    positive_signals: [],
    concerns: [],
  } : null;

  return {
    id: row.id,
    name: row.name,
    phone: row.phone,
    interest: row.interest,
    source: row.source,
    status: row.status,
    temperature: row.temperature,
    score: scoreObj,
    summary: row.summary,
    objections: row.objections ? JSON.parse(row.objections) : [],
    next_action: row.next_action,
    callback_at: row.callback_at,
    attributes: row.attributes ? JSON.parse(row.attributes) : {},
    created_at: row.created_at,
    updated_at: row.updated_at,
  };
}

function normalizePhone(p: string): string | null {
  const digits = p.replace(/\D/g, '');
  if (digits.length === 10) return `91${digits}`;
  if (digits.length === 11 && digits.startsWith('0')) return `91${digits.slice(1)}`;
  if (digits.startsWith('91') && digits.length === 12) return digits;
  if (digits.length >= 8 && digits.length <= 15) return digits;
  return null;
}

// GET /leads
leadsApp.get('/leads', async (c) => {
  const user = c.get('user');
  const filter = c.req.query('filter') || 'all';
  const q = c.req.query('q')?.toLowerCase()?.trim();
  const cursor = parseInt(c.req.query('cursor') || '0', 10);
  const limit = Math.min(parseInt(c.req.query('limit') || '20', 10), 1000);
  const fields = c.req.query('fields');

  let sql = 'SELECT * FROM leads WHERE business_id = ?';
  const params: any[] = [user.business_id];

  if (filter === 'new') {
    sql += " AND status = 'new'";
  } else if (filter === 'called') {
    sql += " AND status != 'new'";
  } else if (filter === 'hot') {
    sql += " AND temperature = 'hot'";
  } else if (filter === 'warm') {
    sql += " AND temperature = 'warm'";
  } else if (filter === 'callback') {
    sql += " AND callback_at IS NOT NULL";
  }

  if (q) {
    sql += ' AND (LOWER(name) LIKE ? OR phone LIKE ? OR LOWER(interest) LIKE ?)';
    params.push(`%${q}%`, `%${q}%`, `%${q}%`);
  }

  // Prioritize hot leads, then newest
  sql += " ORDER BY CASE WHEN temperature = 'hot' THEN 0 WHEN temperature = 'warm' THEN 1 ELSE 2 END, created_at DESC";
  sql += ' LIMIT ? OFFSET ?';
  params.push(limit + 1, cursor);

  const { results } = await c.env.DB.prepare(sql).bind(...params).all<any>();
  const hasMore = results.length > limit;
  const items = (hasMore ? results.slice(0, limit) : results).map(formatLead);

  if (fields) {
    return c.json(items);
  }

  return c.json({
    items,
    has_more: hasMore,
    next_cursor: hasMore ? String(cursor + limit) : null,
  });
});

// POST /leads
leadsApp.post('/leads', async (c) => {
  const user = c.get('user');
  const body = await c.req.json<any>().catch(() => ({}));

  const name = body.name?.trim();
  const rawPhone = body.phone?.trim();
  if (!name || !rawPhone) {
    return c.json({ message: 'Name and phone are required.', code: 'invalid_request' }, 400);
  }

  const phone = normalizePhone(rawPhone);
  if (!phone) {
    return c.json({ message: 'Invalid phone number.', code: 'invalid_phone' }, 400);
  }

  const id = `lead_${crypto.randomUUID().slice(0, 12)}`;
  const interest = body.interest || body.course_interest || null;
  const source = body.source || 'Manual entry';
  const attributes = JSON.stringify(body.attributes || {});

  await c.env.DB.prepare(
    `INSERT INTO leads (id, business_id, name, phone, interest, source, status, attributes, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, 'new', ?, datetime('now'), datetime('now'))`
  ).bind(id, user.business_id, name, phone, interest, source, attributes).run();

  const created = await c.env.DB.prepare('SELECT * FROM leads WHERE id = ? AND business_id = ?').bind(id, user.business_id).first();
  return c.json(formatLead(created));
});

// POST /leads/import
leadsApp.post('/leads/import', async (c) => {
  const user = c.get('user');
  const body: any = await c.req.json().catch(() => ({}));
  const list = body.leads || [];

  if (!Array.isArray(list) || list.length === 0) {
    return c.json({ imported: 0, skipped: 0, errors: ['No leads provided.'] });
  }

  // Get existing phones for this tenant to dedupe
  const { results: existingRows } = await c.env.DB.prepare(
    'SELECT phone FROM leads WHERE business_id = ?'
  ).bind(user.business_id).all<{ phone: string }>();

  const existingPhones = new Set(existingRows.map((r) => r.phone));
  const seenInBatch = new Set<string>();

  const statements: D1PreparedStatement[] = [];
  let skipped = 0;
  const errors: string[] = [];

  for (let i = 0; i < list.length; i++) {
    const item = list[i];
    const name = item.name?.trim() || 'Lead';
    const rawPhone = item.phone?.trim() || '';
    const phone = normalizePhone(rawPhone);

    if (!phone) {
      skipped++;
      if (errors.length < 5) errors.push(`Row ${i + 1}: Invalid phone number`);
      continue;
    }

    if (existingPhones.has(phone) || seenInBatch.has(phone)) {
      skipped++;
      continue;
    }

    seenInBatch.add(phone);
    const id = `lead_${crypto.randomUUID().slice(0, 12)}`;
    const interest = item.interest || item.course_interest || null;
    const source = item.source || 'CSV Import';
    const attributes = JSON.stringify(item.attributes || {});

    statements.push(
      c.env.DB.prepare(
        `INSERT INTO leads (id, business_id, name, phone, interest, source, status, attributes, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, 'new', ?, datetime('now'), datetime('now'))`
      ).bind(id, user.business_id, name, phone, interest, source, attributes)
    );
  }

  // Batch insert into D1
  if (statements.length > 0) {
    // D1 batch supports up to 100 statements per call
    const chunkSize = 80;
    for (let i = 0; i < statements.length; i += chunkSize) {
      await c.env.DB.batch(statements.slice(i, i + chunkSize));
    }
  }

  return c.json({
    imported: statements.length,
    skipped,
    duplicates: skipped,
    errors,
  });
});

// GET /leads/:id
leadsApp.get('/leads/:id', async (c) => {
  const user = c.get('user');
  const id = c.req.param('id');
  const row = await c.env.DB.prepare('SELECT * FROM leads WHERE id = ? AND business_id = ?').bind(id, user.business_id).first();
  if (!row) return c.json({ message: 'Lead not found.', code: 'not_found' }, 404);
  return c.json(formatLead(row));
});

// PATCH /leads/:id
leadsApp.patch('/leads/:id', async (c) => {
  const user = c.get('user');
  const id = c.req.param('id');
  const body = await c.req.json<any>().catch(() => ({}));

  const existing = await c.env.DB.prepare('SELECT * FROM leads WHERE id = ? AND business_id = ?').bind(id, user.business_id).first<any>();
  if (!existing) return c.json({ message: 'Lead not found.', code: 'not_found' }, 404);

  const name = body.name !== undefined ? body.name : existing.name;
  const phone = body.phone !== undefined ? (normalizePhone(body.phone) || existing.phone) : existing.phone;
  const interest = body.interest !== undefined ? body.interest : existing.interest;
  const source = body.source !== undefined ? body.source : existing.source;
  const status = body.status !== undefined ? body.status : existing.status;
  const temperature = body.temperature !== undefined ? body.temperature : existing.temperature;
  const score = body.score !== undefined ? body.score : existing.score;
  const summary = body.summary !== undefined ? body.summary : existing.summary;
  const nextAction = body.next_action !== undefined ? body.next_action : existing.next_action;
  const callbackAt = body.callback_at !== undefined ? body.callback_at : existing.callback_at;
  const attributes = body.attributes !== undefined ? JSON.stringify(body.attributes) : existing.attributes;

  await c.env.DB.prepare(
    `UPDATE leads SET
      name = ?, phone = ?, interest = ?, source = ?, status = ?,
      temperature = ?, score = ?, summary = ?, next_action = ?,
      callback_at = ?, attributes = ?, updated_at = datetime('now')
     WHERE id = ? AND business_id = ?`
  ).bind(
    name, phone, interest, source, status,
    temperature, score, summary, nextAction,
    callbackAt, attributes, id, user.business_id
  ).run();

  const updated = await c.env.DB.prepare('SELECT * FROM leads WHERE id = ? AND business_id = ?').bind(id, user.business_id).first();
  return c.json(formatLead(updated));
});

// DELETE /leads/:id
leadsApp.delete('/leads/:id', async (c) => {
  const user = c.get('user');
  const id = c.req.param('id');
  const existing = await c.env.DB.prepare('SELECT id FROM leads WHERE id = ? AND business_id = ?').bind(id, user.business_id).first();
  if (!existing) return c.json({ message: 'Lead not found.', code: 'not_found' }, 404);
  await c.env.DB.prepare('DELETE FROM leads WHERE id = ? AND business_id = ?').bind(id, user.business_id).run();
  return c.json({ success: true });
});

export { leadsApp };
