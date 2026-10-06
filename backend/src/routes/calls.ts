import { Hono } from 'hono';
import { Env, AuthUser } from '../types';

const callsApp = new Hono<{ Bindings: Env; Variables: { user: AuthUser } }>();

function formatCall(row: any) {
  if (!row) return null;

  let leadScoreObj: any = null;
  if (row.score !== null && row.score !== undefined) {
    leadScoreObj = {
      value: row.score,
      temperature: row.temperature || 'cold',
      intent: row.intent || 'unknown',
      positive_signals: row.positive_signals ? JSON.parse(row.positive_signals) : [],
      concerns: row.objections ? JSON.parse(row.objections) : [],
    };
  }

  let transcriptObj: any = { lines: [] };
  if (row.transcript) {
    try {
      const parsed = JSON.parse(row.transcript);
      if (Array.isArray(parsed)) {
        transcriptObj = { lines: parsed };
      } else {
        transcriptObj = parsed;
      }
    } catch {
      transcriptObj = { lines: [] };
    }
  }

  return {
    id: row.id,
    lead_id: row.lead_id,
    lead_name: row.lead_name,
    lead_phone: row.lead_phone,
    status: row.status,
    duration_seconds: row.duration_seconds || 0,
    recording_url: row.recording_url,
    transcript: transcriptObj,
    lead_score: leadScoreObj,
    summary: row.summary,
    next_action: row.next_action || 'none',
    follow_up_id: row.follow_up_id,
    callback_at: row.callback_at,
    interaction_id: row.interaction_id,
    started_at: row.started_at,
    completed_at: row.completed_at,
  };
}

// GET /calls
callsApp.get('/calls', async (c) => {
  const user = c.get('user');
  const filter = c.req.query('filter') || 'all';
  const leadId = c.req.query('lead_id');
  const cursor = parseInt(c.req.query('cursor') || '0', 10);
  const limit = Math.min(parseInt(c.req.query('limit') || '20', 10), 100);

  let sql = 'SELECT * FROM calls WHERE business_id = ?';
  const params: any[] = [user.business_id];

  if (leadId) {
    sql += ' AND lead_id = ?';
    params.push(leadId);
  }

  if (filter === 'connected') {
    sql += " AND status = 'completed'";
  } else if (filter === 'noAnswer') {
    sql += " AND status IN ('no_answer', 'busy', 'failed')";
  } else if (filter === 'hot') {
    sql += " AND temperature = 'hot'";
  }

  sql += ' ORDER BY started_at DESC LIMIT ? OFFSET ?';
  params.push(limit + 1, cursor);

  const { results } = await c.env.DB.prepare(sql).bind(...params).all<any>();
  const hasMore = results.length > limit;
  const items = (hasMore ? results.slice(0, limit) : results).map(formatCall);

  if (leadId) {
    return c.json(items);
  }

  return c.json({
    items,
    has_more: hasMore,
    next_cursor: hasMore ? String(cursor + limit) : null,
  });
});

// GET /calls/:id
callsApp.get('/calls/:id', async (c) => {
  const user = c.get('user');
  const id = c.req.param('id');
  const row = await c.env.DB.prepare('SELECT * FROM calls WHERE id = ? AND business_id = ?').bind(id, user.business_id).first();
  if (!row) return c.json({ message: 'Call not found.', code: 'not_found' }, 404);
  return c.json(formatCall(row));
});

export { callsApp };
