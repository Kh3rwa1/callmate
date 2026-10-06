import { Hono } from 'hono';
import { Env, AuthUser } from '../types';
import { safeJsonParse } from '../utils/json';
import { parseJsonBody, createLeadSchema, importLeadsSchema, patchLeadSchema } from '../schemas/validation';

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
    objections: safeJsonParse(row.objections, []),
    next_action: row.next_action,
    callback_at: row.callback_at,
    attributes: safeJsonParse(row.attributes, {}),
    do_not_call: row.do_not_call === 1,
    consent: row.consent || 'implicit_inquiry',
    timezone: row.timezone || 'Asia/Kolkata',
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
// Keyset cursor pagination on (created_at, id) with limit capped at 100
leadsApp.get('/leads', async (c) => {
  const user = c.get('user');
  const filter = c.req.query('filter') || 'all';
  const q = c.req.query('q')?.toLowerCase()?.trim();
  const rawCursor = c.req.query('cursor');
  // Cap limit strictly at 100
  const limit = Math.min(Math.max(1, parseInt(c.req.query('limit') || '20', 10)), 100);
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
  } else if (filter === 'dnc') {
    sql += " AND do_not_call = 1";
  }

  if (q) {
    sql += ' AND (LOWER(name) LIKE ? OR phone LIKE ? OR LOWER(interest) LIKE ?)';
    params.push(`%${q}%`, `%${q}%`, `%${q}%`);
  }

  // Parse keyset cursor (base64 encoded JSON { created_at, id })
  if (rawCursor) {
    try {
      const decoded = JSON.parse(atob(rawCursor));
      if (decoded.created_at && decoded.id) {
        sql += ' AND (created_at < ? OR (created_at = ? AND id < ?))';
        params.push(decoded.created_at, decoded.created_at, decoded.id);
      }
    } catch {
      // Legacy offset fallback if rawCursor is an integer
      const offset = parseInt(rawCursor, 10);
      if (!isNaN(offset) && offset > 0) {
        sql += ' ORDER BY created_at DESC, id DESC LIMIT ? OFFSET ?';
        params.push(limit + 1, offset);
        const { results } = await c.env.DB.prepare(sql).bind(...params).all<any>();
        const hasMore = results.length > limit;
        const items = (hasMore ? results.slice(0, limit) : results).map(formatLead);
        return c.json({
          items,
          has_more: hasMore,
          next_cursor: hasMore ? String(offset + limit) : null,
        });
      }
    }
  }

  sql += ' ORDER BY created_at DESC, id DESC LIMIT ?';
  params.push(limit + 1);

  const { results } = await c.env.DB.prepare(sql).bind(...params).all<any>();
  const hasMore = results.length > limit;
  const items = (hasMore ? results.slice(0, limit) : results).map(formatLead);

  if (fields) {
    return c.json(items);
  }

  let nextCursor: string | null = null;
  if (hasMore && items.length > 0) {
    const lastItem = items[items.length - 1];
    if (lastItem) {
      nextCursor = btoa(JSON.stringify({ created_at: lastItem.created_at, id: lastItem.id }));
    }
  }

  return c.json({
    items,
    has_more: hasMore,
    next_cursor: nextCursor,
  });
});

// POST /leads
leadsApp.post('/leads', async (c) => {
  const user = c.get('user');
  const parsed = await parseJsonBody(c, createLeadSchema);
  if (!parsed.success) {
    return parsed.response;
  }
  const body = parsed.data;

  const phone = normalizePhone(body.phone);
  if (!phone) {
    return c.json({ message: 'Invalid phone number format.', code: 'invalid_phone' }, 400);
  }

  // Deduplication check for this business
  const existing = await c.env.DB.prepare(
    'SELECT id FROM leads WHERE business_id = ? AND phone = ?'
  ).bind(user.business_id, phone).first<{ id: string }>();

  if (existing) {
    return c.json({
      message: 'A lead with this phone number already exists for your business.',
      code: 'lead_phone_exists',
      existing_id: existing.id,
    }, 409);
  }

  const id = `lead_${crypto.randomUUID().slice(0, 12)}`;
  const interest = body.interest || body.course_interest || null;
  const source = body.source || 'Manual entry';
  const attributes = JSON.stringify(body.attributes || {});
  const doNotCall = body.do_not_call ? 1 : 0;
  const consent = body.consent || 'implicit_inquiry';
  const timezone = body.timezone || 'Asia/Kolkata';

  await c.env.DB.prepare(
    `INSERT INTO leads (id, business_id, name, phone, interest, source, status, attributes, do_not_call, consent, timezone, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, 'new', ?, ?, ?, ?, datetime('now'), datetime('now'))`
  ).bind(id, user.business_id, body.name.trim(), phone, interest, source, attributes, doNotCall, consent, timezone).run();

  const created = await c.env.DB.prepare('SELECT * FROM leads WHERE id = ? AND business_id = ?').bind(id, user.business_id).first();
  return c.json(formatLead(created));
});

// POST /leads/import
// Cap batch at 1000 rows, deduplicate against database & in-batch
leadsApp.post('/leads/import', async (c) => {
  const user = c.get('user');
  const parsed = await parseJsonBody(c, importLeadsSchema);
  if (!parsed.success) {
    return parsed.response;
  }
  const list = parsed.data.leads;

  // Retrieve existing phones for this business to dedupe
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
    const name = item.name.trim();
    const phone = normalizePhone(item.phone);

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
    const doNotCall = item.do_not_call ? 1 : 0;
    const consent = item.consent || 'implicit_inquiry';

    statements.push(
      c.env.DB.prepare(
        `INSERT INTO leads (id, business_id, name, phone, interest, source, status, attributes, do_not_call, consent, timezone, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, 'new', ?, ?, ?, 'Asia/Kolkata', datetime('now'), datetime('now'))`
      ).bind(id, user.business_id, name, phone, interest, source, attributes, doNotCall, consent)
    );
  }

  // Batch insert into D1
  if (statements.length > 0) {
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
  const parsed = await parseJsonBody(c, patchLeadSchema);
  if (!parsed.success) {
    return parsed.response;
  }
  const body = parsed.data;

  const existing = await c.env.DB.prepare('SELECT * FROM leads WHERE id = ? AND business_id = ?').bind(id, user.business_id).first<any>();
  if (!existing) return c.json({ message: 'Lead not found.', code: 'not_found' }, 404);

  const name = body.name !== undefined ? body.name.trim() : existing.name;
  const phone = body.phone !== undefined ? (normalizePhone(body.phone) || existing.phone) : existing.phone;
  const interest = body.interest !== undefined ? body.interest : existing.interest;
  const status = body.status !== undefined ? body.status : existing.status;
  const temperature = body.temperature !== undefined ? body.temperature : existing.temperature;
  const score = body.score !== undefined ? body.score : existing.score;
  const summary = body.summary !== undefined ? body.summary : existing.summary;
  const nextAction = body.next_action !== undefined ? body.next_action : existing.next_action;
  const callbackAt = body.callback_at !== undefined ? body.callback_at : existing.callback_at;
  const attributes = body.attributes !== undefined ? JSON.stringify(body.attributes) : existing.attributes;
  const doNotCall = body.do_not_call !== undefined ? (body.do_not_call ? 1 : 0) : existing.do_not_call;
  const consent = body.consent !== undefined ? body.consent : existing.consent;
  const timezone = body.timezone !== undefined ? body.timezone : existing.timezone;

  await c.env.DB.prepare(
    `UPDATE leads SET
      name = ?, phone = ?, interest = ?, status = ?,
      temperature = ?, score = ?, summary = ?, next_action = ?,
      callback_at = ?, attributes = ?, do_not_call = ?, consent = ?,
      timezone = ?, updated_at = datetime('now')
     WHERE id = ? AND business_id = ?`
  ).bind(
    name, phone, interest, status,
    temperature, score, summary, nextAction,
    callbackAt, attributes, doNotCall, consent,
    timezone, id, user.business_id
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
