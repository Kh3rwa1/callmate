import { Hono } from 'hono';
import { Env, AuthUser } from '../types';

const dashApp = new Hono<{ Bindings: Env; Variables: { user: AuthUser } }>();

// GET /dashboard/today
dashApp.get('/dashboard/today', async (c) => {
  const user = c.get('user');

  // Query counts from D1
  const leadsCount = await c.env.DB.prepare('SELECT COUNT(*) as count FROM leads WHERE business_id = ?').bind(user.business_id).first<{ count: number }>();
  const newLeadsCount = await c.env.DB.prepare("SELECT COUNT(*) as count FROM leads WHERE business_id = ? AND status = 'new'").bind(user.business_id).first<{ count: number }>();
  const hotLeadsCount = await c.env.DB.prepare("SELECT COUNT(*) as count FROM leads WHERE business_id = ? AND temperature = 'hot'").bind(user.business_id).first<{ count: number }>();
  const interestedCount = await c.env.DB.prepare("SELECT COUNT(*) as count FROM leads WHERE business_id = ? AND (temperature = 'hot' OR temperature = 'warm')").bind(user.business_id).first<{ count: number }>();

  const callsTodayCount = await c.env.DB.prepare(
    "SELECT COUNT(*) as count FROM calls WHERE business_id = ? AND date(started_at) = date('now')"
  ).bind(user.business_id).first<{ count: number }>();

  const connectedCallsCount = await c.env.DB.prepare(
    "SELECT COUNT(*) as count FROM calls WHERE business_id = ? AND status = 'completed' AND date(started_at) = date('now')"
  ).bind(user.business_id).first<{ count: number }>();

  const followupsReadyCount = await c.env.DB.prepare(
    "SELECT COUNT(*) as count FROM followups WHERE business_id = ? AND status = 'ready'"
  ).bind(user.business_id).first<{ count: number }>();

  const callbacksTodayCount = await c.env.DB.prepare(
    "SELECT COUNT(*) as count FROM callbacks WHERE business_id = ? AND status = 'scheduled' AND date(scheduled_at) = date('now')"
  ).bind(user.business_id).first<{ count: number }>();

  // Fetch recent activity items from latest calls, callbacks, or followups
  const { results: recentCalls } = await c.env.DB.prepare(
    `SELECT id, lead_name, temperature, status, started_at
     FROM calls WHERE business_id = ?
     ORDER BY started_at DESC LIMIT 5`
  ).bind(user.business_id).all<any>();

  const activity = recentCalls.map((rc) => {
    let emoji = '📞';
    let text = `Called ${rc.lead_name}`;
    if (rc.temperature === 'hot') {
      emoji = '🔥';
      text = `${rc.lead_name} scored as hot lead`;
    } else if (rc.status !== 'completed') {
      emoji = '⏳';
      text = `${rc.lead_name} was unreachable`;
    }
    return {
      emoji,
      text,
      at: rc.started_at,
      route: `/calls/${rc.id}`,
    };
  });

  return c.json({
    leads: leadsCount?.count || 0,
    connected: connectedCallsCount?.count || 0,
    interested: interestedCount?.count || 0,
    hot: hotLeadsCount?.count || 0,
    calls_today: callsTodayCount?.count || 0,
    followups_ready: followupsReadyCount?.count || 0,
    callbacks_today: callbacksTodayCount?.count || 0,
    new_leads_ready: newLeadsCount?.count || 0,
    activity,
  });
});

// GET /usage
dashApp.get('/usage', async (c) => {
  const user = c.get('user');
  let row = await c.env.DB.prepare('SELECT * FROM usage WHERE business_id = ?').bind(user.business_id).first<any>();

  if (!row) {
    const id = `usage_${crypto.randomUUID().slice(0, 12)}`;
    await c.env.DB.prepare(
      `INSERT INTO usage (id, business_id, plan_name, included_minutes, renews_at, price_inr, minutes_used, calls_made, rate_per_minute_inr)
       VALUES (?, ?, 'Founding Plan', 1000, datetime('now', '+30 days'), 4999, 0, 0, 6)`
    ).bind(id, user.business_id).run();
    row = await c.env.DB.prepare('SELECT * FROM usage WHERE id = ? AND business_id = ?').bind(id, user.business_id).first<any>();
  }

  return c.json({
    subscription: {
      plan_name: row.plan_name,
      included_minutes: row.included_minutes,
      renews_at: row.renews_at,
      price_inr: row.price_inr,
    },
    minutes_used: row.minutes_used || 0,
    calls_made: row.calls_made || 0,
    rate_per_minute_inr: row.rate_per_minute_inr || 6,
  });
});

// GET /notifications
dashApp.get('/notifications', async (c) => {
  const user = c.get('user');
  const { results } = await c.env.DB.prepare(
    'SELECT * FROM notifications WHERE business_id = ? ORDER BY created_at DESC LIMIT 50'
  ).bind(user.business_id).all<any>();

  const items = results.map((n) => ({
    id: n.id,
    type: n.type,
    title: n.title,
    body: n.body,
    route: n.route,
    action_label: n.action_label,
    created_at: n.created_at,
    read: Boolean(n.is_read),
  }));

  return c.json(items);
});

// PATCH /notifications/:id
dashApp.patch('/notifications/:id', async (c) => {
  const user = c.get('user');
  const id = c.req.param('id');
  const body = await c.req.json<any>().catch(() => ({}));
  const isRead = body.read === true ? 1 : 0;

  await c.env.DB.prepare(
    'UPDATE notifications SET is_read = ? WHERE id = ? AND business_id = ?'
  ).bind(isRead, id, user.business_id).run();

  return c.json({ success: true });
});

// POST /devices/register
dashApp.post('/devices/register', async (c) => {
  const user = c.get('user');
  const body: any = await c.req.json().catch(() => ({}));

  if (!body.token) {
    return c.json({ message: 'Token is required.', code: 'invalid_request' }, 400);
  }

  const id = `dev_${crypto.randomUUID().slice(0, 12)}`;
  await c.env.DB.prepare(
    `INSERT OR REPLACE INTO devices (id, business_id, fcm_token, platform, updated_at)
     VALUES (?, ?, ?, ?, datetime('now'))`
  ).bind(id, user.business_id, body.token, body.platform || 'unknown').run();

  return c.json({ registered: true });
});

export { dashApp };
