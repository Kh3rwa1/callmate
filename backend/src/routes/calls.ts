import { Hono } from 'hono';
import { Env, AuthUser } from '../types';
import { safeJsonParse } from '../utils/json';
import { decryptAtRest, maskPhone } from '../utils/crypto_data';
import { requireSecret, isMockSarvam } from '../utils/secrets';
import { checkCallCompliance } from '../services/compliance';
import { dialSarvam, MAX_CONCURRENT_CALLS_PER_BUSINESS } from '../services/campaign_queue';

const callsApp = new Hono<{ Bindings: Env; Variables: { user: AuthUser } }>();

async function formatCall(row: any, secret?: string) {
  if (!row) return null;

  let leadScoreObj: any = null;
  if (row.score !== null && row.score !== undefined) {
    leadScoreObj = {
      value: row.score,
      temperature: row.temperature || 'cold',
      intent: row.intent || 'unknown',
      positive_signals: safeJsonParse(row.positive_signals, []),
      concerns: safeJsonParse(row.objections, []),
    };
  }

  let transcriptObj: any = { lines: [] };
  if (row.transcript) {
    try {
      const decrypted = await decryptAtRest(row.transcript, secret);
      const parsed = safeJsonParse(decrypted, []);
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
    created_at: row.created_at,
  };
}

// GET /calls
callsApp.get('/calls', async (c) => {
  const user = c.get('user');
  const filter = c.req.query('filter') || 'all';
  const leadId = c.req.query('lead_id');
  const rawCursor = c.req.query('cursor');
  const limit = Math.min(Math.max(1, parseInt(c.req.query('limit') || '20', 10)), 100);
  const secret = requireSecret(c.env, 'ENCRYPTION_KEY');

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

  if (rawCursor) {
    try {
      const decoded = JSON.parse(atob(rawCursor));
      if (decoded.started_at && decoded.id) {
        sql += ' AND (started_at < ? OR (started_at = ? AND id < ?))';
        params.push(decoded.started_at, decoded.started_at, decoded.id);
      }
    } catch {
      const offset = parseInt(rawCursor, 10);
      if (!isNaN(offset) && offset > 0) {
        sql += ' ORDER BY started_at DESC, id DESC LIMIT ? OFFSET ?';
        params.push(limit + 1, offset);
        const { results } = await c.env.DB.prepare(sql).bind(...params).all<any>();
        const hasMore = results.length > limit;
        const items = await Promise.all((hasMore ? results.slice(0, limit) : results).map((r) => formatCall(r, secret)));
        return c.json({
          items,
          has_more: hasMore,
          next_cursor: hasMore ? String(offset + limit) : null,
        });
      }
    }
  }

  sql += ' ORDER BY started_at DESC, id DESC LIMIT ?';
  params.push(limit + 1);

  const { results } = await c.env.DB.prepare(sql).bind(...params).all<any>();
  const hasMore = results.length > limit;
  const sliced = hasMore ? results.slice(0, limit) : results;
  const items = await Promise.all(sliced.map((r) => formatCall(r, secret)));

  if (leadId) {
    return c.json(items);
  }

  let nextCursor: string | null = null;
  if (hasMore && items.length > 0) {
    const lastItem = items[items.length - 1];
    nextCursor = btoa(JSON.stringify({ started_at: lastItem?.started_at, id: lastItem?.id }));
  }

  return c.json({
    items,
    has_more: hasMore,
    next_cursor: nextCursor,
  });
});

// GET /calls/:id
callsApp.get('/calls/:id', async (c) => {
  const user = c.get('user');
  const id = c.req.param('id');
  const secret = requireSecret(c.env, 'ENCRYPTION_KEY');
  const row = await c.env.DB.prepare('SELECT * FROM calls WHERE id = ? AND business_id = ?').bind(id, user.business_id).first();
  if (!row) return c.json({ message: 'Call not found.', code: 'not_found' }, 404);
  return c.json(await formatCall(row, secret));
});

// POST /leads/:id/call: manual single call. Same guardrails as campaign dispatch.
const BLOCKED_CALL_MESSAGES: Record<string, string> = {
  outside_hours: 'This lead can only be called during calling hours.',
  do_not_call: 'This lead has opted out of calls.',
  max_daily_attempts: 'This lead has already been called 3 times today.',
};

callsApp.post('/leads/:id/call', async (c) => {
  const user = c.get('user');
  const leadId = c.req.param('id');
  const secret = requireSecret(c.env, 'ENCRYPTION_KEY');

  const lead = await c.env.DB.prepare('SELECT * FROM leads WHERE id = ? AND business_id = ?').bind(leadId, user.business_id).first<any>();
  if (!lead) return c.json({ message: 'Lead not found.', code: 'not_found' }, 404);

  const agent = await c.env.DB.prepare('SELECT * FROM agents WHERE business_id = ?').bind(user.business_id).first<any>();

  const compliance = await checkCallCompliance(c.env.DB, {
    businessId: user.business_id,
    leadId,
    hoursStart: agent?.calling_hours_start,
    hoursEnd: agent?.calling_hours_end,
    timezone: lead.timezone || 'Asia/Kolkata',
  });
  if (!compliance.allowed) {
    return c.json({
      message: BLOCKED_CALL_MESSAGES[compliance.reason!] ?? 'This call is not allowed right now.',
      code: compliance.reason,
    }, 409);
  }

  const active = await c.env.DB.prepare(
    `SELECT COUNT(*) AS cnt FROM calls
     WHERE business_id = ? AND status = 'calling' AND started_at > datetime('now', '-20 minutes')`
  ).bind(user.business_id).first<{ cnt: number }>();
  if ((active?.cnt ?? 0) >= MAX_CONCURRENT_CALLS_PER_BUSINESS) {
    return c.json({ message: 'Too many calls in progress. Try again in a minute.', code: 'concurrency_limit' }, 429);
  }

  const usage = await c.env.DB.prepare('SELECT included_minutes, minutes_used FROM usage WHERE business_id = ?')
    .bind(user.business_id).first<{ included_minutes: number; minutes_used: number }>();
  if (usage && usage.included_minutes - usage.minutes_used <= 0) {
    return c.json({ message: 'You have used all included calling minutes.', code: 'exhausted_minutes' }, 402);
  }

  const business = await c.env.DB.prepare('SELECT name FROM businesses WHERE id = ?').bind(user.business_id).first<any>();
  const callId = `call_${crypto.randomUUID().slice(0, 12)}`;

  await c.env.DB.prepare(`
    INSERT INTO calls (id, business_id, lead_id, lead_name, lead_phone, status, started_at, created_at)
    VALUES (?, ?, ?, ?, ?, 'calling', datetime('now'), datetime('now'))
  `).bind(callId, user.business_id, lead.id, lead.name, lead.phone).run();

  const markLeadCalling = c.env.DB.prepare(
    `UPDATE leads SET status = 'calling', updated_at = datetime('now') WHERE id = ? AND business_id = ?`
  ).bind(leadId, user.business_id);

  let dispatched = false;
  if (isMockSarvam(c.env)) {
    // Dev/test: the mock webhook or maintenance sweeper completes the call.
    await markLeadCalling.run();
  } else {
    const dial = await dialSarvam(c.env, {
      app_config: { app_id: c.env.SARVAM_ADMISSIONS_APP_ID },
      user_config: { phone_number: lead.phone },
      agent_variables: {
        call_id: callId,
        lead_id: lead.id,
        lead_name: lead.name,
        business_name: business?.name ?? 'our business',
        agent_name: agent?.name ?? 'Riya',
        agent_role: agent?.role ?? 'Assistant',
        interest: lead.interest ?? lead.course_interest ?? '',
      },
      webhook_config: { webhook_url: `${new URL(c.req.url).origin}/webhooks/sarvam` },
    });

    if (dial.ok) {
      dispatched = true;
      await c.env.DB.batch([
        c.env.DB.prepare('UPDATE calls SET interaction_id = ? WHERE id = ? AND business_id = ?')
          .bind(dial.interactionId, callId, user.business_id),
        markLeadCalling,
      ]);
    } else {
      console.error(JSON.stringify({ msg: 'sarvam_manual_dial_failed', lead: maskPhone(lead.phone), error: dial.error }));
      await c.env.DB.prepare(`UPDATE calls SET status = 'failed', failure_reason = ? WHERE id = ? AND business_id = ?`)
        .bind(dial.error, callId, user.business_id).run();
      return c.json({
        message: dial.retryable ? 'The calling service is busy. Please try again shortly.' : 'The call could not be placed.',
        code: 'dial_failed',
      }, dial.retryable ? 503 : 502);
    }
  }

  const created = await c.env.DB.prepare('SELECT * FROM calls WHERE id = ? AND business_id = ?').bind(callId, user.business_id).first();
  return c.json({
    call: await formatCall(created, secret),
    sarvam_dispatched: dispatched,
  });
});

export { callsApp };
