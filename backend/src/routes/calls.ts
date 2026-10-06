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

// POST /leads/:id/call (or trigger a call for lead)
callsApp.post('/leads/:id/call', async (c) => {
  const user = c.get('user');
  const leadId = c.req.param('id');

  const lead = await c.env.DB.prepare('SELECT * FROM leads WHERE id = ? AND business_id = ?').bind(leadId, user.business_id).first<any>();
  if (!lead) return c.json({ message: 'Lead not found.', code: 'not_found' }, 404);

  const business = await c.env.DB.prepare('SELECT * FROM businesses WHERE id = ?').bind(user.business_id).first<any>();
  const agent = await c.env.DB.prepare('SELECT * FROM agents WHERE business_id = ?').bind(user.business_id).first<any>();

  const callId = `call_${crypto.randomUUID().slice(0, 12)}`;

  // Record active call in D1
  await c.env.DB.prepare(`
    INSERT INTO calls (id, business_id, lead_id, lead_name, lead_phone, status, started_at)
    VALUES (?, ?, ?, ?, ?, 'calling', datetime('now'))
  `).bind(callId, user.business_id, lead.id, lead.name, lead.phone).run();

  await c.env.DB.prepare(`
    UPDATE leads SET status = 'calling', updated_at = datetime('now') WHERE id = ? AND business_id = ?
  `).bind(leadId, user.business_id).run();

  // Trigger real Sarvam Outbound Call via API
  const sarvamApiKey = c.env.SARVAM_API_KEY;
  const orgId = c.env.SARVAM_ORG_ID || 'org_callpilot';
  const workspaceId = c.env.SARVAM_WORKSPACE_ID || 'ws_callpilot';
  const appId = c.env.SARVAM_ADMISSIONS_APP_ID || 'app_callpilot_voice';

  let sarvamResult: any = null;
  if (sarvamApiKey && !sarvamApiKey.startsWith('mock-')) {
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
    call: formatCall(created),
    sarvam_dispatched: !!sarvamResult,
    sarvam_response: sarvamResult,
  });
});

export { callsApp };

