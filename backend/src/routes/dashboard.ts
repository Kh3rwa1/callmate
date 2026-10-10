import { Hono } from 'hono';
import { Env, AuthUser } from '../types';
import { billingView, getPlan, RATE_PER_MINUTE_INR } from '../services/plans';

// Calls to the owner's own test lead (POST /agent/test-call) are not results.
const NOT_OWNER_TEST = 'lead_id NOT IN (SELECT id FROM leads WHERE business_id = ? AND is_owner_test = 1)';

const dashApp = new Hono<{ Bindings: Env; Variables: { user: AuthUser } }>();

// GET /dashboard/today
dashApp.get('/dashboard/today', async (c) => {
  const user = c.get('user');

  // Query counts from D1
  const leadsCount = await c.env.DB.prepare('SELECT COUNT(*) as count FROM leads WHERE business_id = ? AND is_owner_test = 0').bind(user.business_id).first<{ count: number }>();
  const newLeadsCount = await c.env.DB.prepare("SELECT COUNT(*) as count FROM leads WHERE business_id = ? AND is_owner_test = 0 AND status = 'new'").bind(user.business_id).first<{ count: number }>();
  const hotLeadsCount = await c.env.DB.prepare("SELECT COUNT(*) as count FROM leads WHERE business_id = ? AND is_owner_test = 0 AND temperature = 'hot'").bind(user.business_id).first<{ count: number }>();
  const interestedCount = await c.env.DB.prepare("SELECT COUNT(*) as count FROM leads WHERE business_id = ? AND is_owner_test = 0 AND (temperature = 'hot' OR temperature = 'warm')").bind(user.business_id).first<{ count: number }>();

  const callsTodayCount = await c.env.DB.prepare(
    `SELECT COUNT(*) as count FROM calls WHERE business_id = ? AND date(started_at) = date('now') AND ${NOT_OWNER_TEST}`
  ).bind(user.business_id, user.business_id).first<{ count: number }>();

  const connectedCallsCount = await c.env.DB.prepare(
    `SELECT COUNT(*) as count FROM calls WHERE business_id = ? AND status = 'completed' AND date(started_at) = date('now') AND ${NOT_OWNER_TEST}`
  ).bind(user.business_id, user.business_id).first<{ count: number }>();

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
    // Usage rows are created at signup (with the trial grant). A missing row must not mint
    // free minutes, so it is backfilled as a trial with 0 minutes; the owner can buy a plan.
    const id = `usage_${crypto.randomUUID().slice(0, 12)}`;
    await c.env.DB.prepare(
      `INSERT OR IGNORE INTO usage (id, business_id, plan_id, plan_status, plan_name, included_minutes, renews_at, price_inr, minutes_used, calls_made, rate_per_minute_inr)
       VALUES (?, ?, 'trial', 'trial', ?, 0, datetime('now'), 0, 0, 0, ?)`
    ).bind(id, user.business_id, getPlan('trial', c.env).name, RATE_PER_MINUTE_INR).run();
    row = await c.env.DB.prepare('SELECT * FROM usage WHERE business_id = ?').bind(user.business_id).first<any>();
  }

  const billing = billingView(row, c.env);
  return c.json({
    subscription: {
      plan_name: row.plan_name,
      included_minutes: row.included_minutes,
      renews_at: row.renews_at,
      price_inr: row.price_inr,
      plan_id: billing.plan_id,
      plan_status: billing.plan_status,
      current_period_end: billing.current_period_end,
      billing_cycle: billing.billing_cycle,
      annual_until: billing.annual_until,
      topup_minutes: billing.topup_minutes,
      bonus_minutes: billing.bonus_minutes,
    },
    // plan + top-up + bonus - used (services/plans.ts minutesRemaining).
    minutes_remaining: billing.minutes_left,
    checkout_plan: billing.checkout_plan,
    plans: billing.plans,
    topups: billing.topups,
    can_buy_topup: billing.can_buy_topup,
    gst_rate: billing.gst_rate,
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

async function upsertDevice(db: D1Database, businessId: string, token: string, platform: string = 'unknown') {
  const existing = await db.prepare(
    'SELECT id FROM devices WHERE business_id = ? AND fcm_token = ?'
  ).bind(businessId, token).first<{ id: string }>();

  if (existing) {
    await db.prepare(
      `UPDATE devices SET platform = ?, updated_at = datetime('now') WHERE id = ?`
    ).bind(platform, existing.id).run();
  } else {
    const id = `dev_${crypto.randomUUID().slice(0, 12)}`;
    await db.prepare(
      `INSERT INTO devices (id, business_id, fcm_token, platform, updated_at)
       VALUES (?, ?, ?, ?, datetime('now'))`
    ).bind(id, businessId, token, platform).run();
  }
}

async function handleDeviceRegistration(c: any) {
  const user = c.get('user');
  const body: any = await c.req.json().catch(() => ({}));

  if (!body.token) {
    return c.json({ message: 'Token is required.', code: 'invalid_request' }, 400);
  }

  await upsertDevice(c.env.DB, user.business_id, body.token, body.platform || 'unknown');
  return c.json({ registered: true });
}

// POST /devices and POST /devices/register
dashApp.post('/devices', handleDeviceRegistration);
dashApp.post('/devices/register', handleDeviceRegistration);

// DELETE /devices/:token
dashApp.delete('/devices/:token', async (c) => {
  const user = c.get('user');
  const token = c.req.param('token');
  await c.env.DB.prepare(
    'DELETE FROM devices WHERE business_id = ? AND fcm_token = ?'
  ).bind(user.business_id, token).run();

  return c.json({ deleted: true });
});

export { dashApp };
