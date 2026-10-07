import { Hono } from 'hono';
import { Env, AuthUser } from '../types';
import { safeJsonParse } from '../utils/json';
import { decryptAtRest } from '../utils/crypto_data';

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
  const secret = c.env.ENCRYPTION_KEY || c.env.JWT_SIGNING_KEY;

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
  const secret = c.env.ENCRYPTION_KEY || c.env.JWT_SIGNING_KEY;
  const row = await c.env.DB.prepare('SELECT * FROM calls WHERE id = ? AND business_id = ?').bind(id, user.business_id).first();
  if (!row) return c.json({ message: 'Call not found.', code: 'not_found' }, 404);
  return c.json(await formatCall(row, secret));
});

// POST /leads/:id/call (or trigger a call for lead)
callsApp.post('/leads/:id/call', async (c) => {
  const user = c.get('user');
  const leadId = c.req.param('id');
  const secret = c.env.ENCRYPTION_KEY || c.env.JWT_SIGNING_KEY;

  const lead = await c.env.DB.prepare('SELECT * FROM leads WHERE id = ? AND business_id = ?').bind(leadId, user.business_id).first<any>();
  if (!lead) return c.json({ message: 'Lead not found.', code: 'not_found' }, 404);

  const business = await c.env.DB.prepare('SELECT * FROM businesses WHERE id = ?').bind(user.business_id).first<any>();
  const agent = await c.env.DB.prepare('SELECT * FROM agents WHERE business_id = ?').bind(user.business_id).first<any>();

  const callId = `call_${crypto.randomUUID().slice(0, 12)}`;

  // Record active call in D1
  await c.env.DB.prepare(`
    INSERT INTO calls (id, business_id, lead_id, lead_name, lead_phone, status, started_at, created_at)
    VALUES (?, ?, ?, ?, ?, 'calling', datetime('now'), datetime('now'))
  `).bind(callId, user.business_id, lead.id, lead.name, lead.phone).run();

  await c.env.DB.prepare(`
    UPDATE leads SET status = 'calling', updated_at = datetime('now') WHERE id = ? AND business_id = ?
  `).bind(leadId, user.business_id).run();

  // Trigger real Sarvam Outbound Call via API
  const sarvamApiKey = c.env.SARVAM_API_KEY;
  const orgId = c.env.SARVAM_ORG_ID;
  const workspaceId = c.env.SARVAM_WORKSPACE_ID;
  const appId = c.env.SARVAM_ADMISSIONS_APP_ID;

  let sarvamResult: any = null;
  if (sarvamApiKey && !sarvamApiKey.startsWith('mock-') && orgId && workspaceId && appId) {
    try {
      const url = new URL(c.req.url);
      const webhookUrl = `${url.origin}/webhooks/sarvam`;

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

      sarvamResult = await sarvamRes.json().catch(() => null);
      if (sarvamResult?.interaction_id || sarvamResult?.id || sarvamResult?.attempt_id) {
        const interactionId = sarvamResult.interaction_id || sarvamResult.id || sarvamResult.attempt_id;
        await c.env.DB.prepare('UPDATE calls SET interaction_id = ? WHERE id = ? AND business_id = ?').bind(interactionId, callId, user.business_id).run();
      }
    } catch (err: any) {
      console.error('[Sarvam Outbound Call Error]:', err?.message || err);
    }
  }

  const created = await c.env.DB.prepare('SELECT * FROM calls WHERE id = ? AND business_id = ?').bind(callId, user.business_id).first();
  return c.json({
    call: await formatCall(created, secret),
    sarvam_dispatched: !!sarvamResult,
    sarvam_response: sarvamResult,
  });
});

export { callsApp };
