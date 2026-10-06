import { Hono } from 'hono';
import { Env, AuthUser } from '../types';
import { signJWT, verifyJWT, getJwtSecret, authMiddleware } from '../auth';

const authApp = new Hono<{ Bindings: Env; Variables: { user: AuthUser } }>();

// Helper to normalize phone numbers (e.g. 919830012345)
function normalizePhone(p: string): string {
  const digits = p.replace(/\D/g, '');
  if (digits.length === 10) return `91${digits}`;
  if (digits.length === 11 && digits.startsWith('0')) return `91${digits.slice(1)}`;
  if (digits.startsWith('91') && digits.length === 12) return digits;
  return digits;
}

// POST /auth/register
authApp.post('/register', async (c) => {
  const body: any = await c.req.json().catch(() => ({}));
  const rawPhone = body.phone?.trim();
  const businessName = body.business_name?.trim();

  if (!rawPhone || !businessName) {
    return c.json({ message: 'Phone and business name are required.', code: 'invalid_request' }, 400);
  }

  const phone = normalizePhone(rawPhone);
  const secret = getJwtSecret(c);

  // Check if user already exists
  const existingUser = await c.env.DB.prepare('SELECT * FROM users WHERE phone = ?').bind(phone).first<{ id: string; business_id: string }>();

  let userId: string;
  let businessId: string;

  if (existingUser) {
    userId = existingUser.id;
    businessId = existingUser.business_id;
  } else {
    userId = `usr_${crypto.randomUUID().slice(0, 12)}`;
    businessId = `biz_${crypto.randomUUID().slice(0, 12)}`;
    const agentId = `agent_${crypto.randomUUID().slice(0, 12)}`;
    const usageId = `usage_${crypto.randomUUID().slice(0, 12)}`;

    // Create Business, Agent, User, and default Usage
    await c.env.DB.batch([
      c.env.DB.prepare(
        `INSERT INTO businesses (id, name, category, created_at, updated_at) VALUES (?, ?, 'other', datetime('now'), datetime('now'))`
      ).bind(businessId, businessName),
      c.env.DB.prepare(
        `INSERT INTO agents (id, business_id, name, role, status, template_id, role_kind, skills, capabilities, calling_hours_start, calling_hours_end, voice, created_at, updated_at)
         VALUES (?, ?, 'Maya', 'Sales Assistant', 'active', 'generic_sales_v1', 'sales', '["sales", "bookAppointments"]', '["Calling", "Lead Qualification", "Follow-up", "Customer Questions"]', 10, 19, 'Friendly Female (Hindi/English)', datetime('now'), datetime('now'))`
      ).bind(agentId, businessId),
      c.env.DB.prepare(
        `INSERT INTO users (id, phone, business_id, created_at) VALUES (?, ?, ?, datetime('now'))`
      ).bind(userId, phone, businessId),
      c.env.DB.prepare(
        `INSERT INTO usage (id, business_id, plan_name, included_minutes, renews_at, price_inr, minutes_used, calls_made, rate_per_minute_inr)
         VALUES (?, ?, 'Founding Plan', 1000, datetime('now', '+30 days'), 4999, 0, 0, 6)`
      ).bind(usageId, businessId),
    ]);
  }

  const accessToken = await signJWT({ sub: userId, phone, business_id: businessId, type: 'access' }, secret, 3600 * 24); // 24 hours
  const refreshToken = await signJWT({ sub: userId, phone, business_id: businessId, type: 'refresh' }, secret, 3600 * 24 * 30); // 30 days

  // Store refresh token in D1
  const expiresAt = new Date(Date.now() + 30 * 24 * 3600 * 1000).toISOString();
  await c.env.DB.prepare(
    'INSERT OR REPLACE INTO refresh_tokens (token, user_id, expires_at) VALUES (?, ?, ?)'
  ).bind(refreshToken, userId, expiresAt).run();

  return c.json({ access_token: accessToken, refresh_token: refreshToken });
});

// POST /auth/login
authApp.post('/login', async (c) => {
  const body: any = await c.req.json().catch(() => ({}));
  const rawPhone = body.phone?.trim();
  const otp = body.otp?.trim();

  if (!rawPhone || !otp) {
    return c.json({ message: 'Phone and OTP are required.', code: 'invalid_request' }, 400);
  }

  const phone = normalizePhone(rawPhone);
  const secret = getJwtSecret(c);

  // In production, integrate with SMS gateway (Twilio, Gupshup, Exotel)
  // For sandbox/dev verification, allow valid 4-6 digit numeric OTP
  if (otp.length < 4 || !/^\d+$/.test(otp)) {
    return c.json({ message: 'Invalid verification code.', code: 'invalid_otp' }, 400);
  }

  let user = await c.env.DB.prepare('SELECT * FROM users WHERE phone = ?').bind(phone).first<{ id: string; business_id: string }>();

  // If user doesn't exist yet, auto-provision account
  if (!user) {
    const userId = `usr_${crypto.randomUUID().slice(0, 12)}`;
    const businessId = `biz_${crypto.randomUUID().slice(0, 12)}`;
    const agentId = `agent_${crypto.randomUUID().slice(0, 12)}`;
    const usageId = `usage_${crypto.randomUUID().slice(0, 12)}`;

    await c.env.DB.batch([
      c.env.DB.prepare(
        `INSERT INTO businesses (id, name, category, created_at, updated_at) VALUES (?, 'My Business', 'other', datetime('now'), datetime('now'))`
      ).bind(businessId),
      c.env.DB.prepare(
        `INSERT INTO agents (id, business_id, name, role, status, template_id, role_kind, skills, capabilities, calling_hours_start, calling_hours_end, voice, created_at, updated_at)
         VALUES (?, ?, 'Maya', 'Sales Assistant', 'active', 'generic_sales_v1', 'sales', '["sales", "bookAppointments"]', '["Calling", "Lead Qualification", "Follow-up", "Customer Questions"]', 10, 19, 'Friendly Female (Hindi/English)', datetime('now'), datetime('now'))`
      ).bind(agentId, businessId),
      c.env.DB.prepare(
        `INSERT INTO users (id, phone, business_id, created_at) VALUES (?, ?, ?, datetime('now'))`
      ).bind(userId, phone, businessId),
      c.env.DB.prepare(
        `INSERT INTO usage (id, business_id, plan_name, included_minutes, renews_at, price_inr, minutes_used, calls_made, rate_per_minute_inr)
         VALUES (?, ?, 'Founding Plan', 1000, datetime('now', '+30 days'), 4999, 0, 0, 6)`
      ).bind(usageId, businessId),
    ]);

    user = { id: userId, business_id: businessId };
  }

  const accessToken = await signJWT({ sub: user.id, phone, business_id: user.business_id, type: 'access' }, secret, 3600 * 24);
  const refreshToken = await signJWT({ sub: user.id, phone, business_id: user.business_id, type: 'refresh' }, secret, 3600 * 24 * 30);

  const expiresAt = new Date(Date.now() + 30 * 24 * 3600 * 1000).toISOString();
  await c.env.DB.prepare(
    'INSERT OR REPLACE INTO refresh_tokens (token, user_id, expires_at) VALUES (?, ?, ?)'
  ).bind(refreshToken, user.id, expiresAt).run();

  return c.json({ access_token: accessToken, refresh_token: refreshToken });
});

// POST /auth/refresh
authApp.post('/refresh', async (c) => {
  const body: any = await c.req.json().catch(() => ({}));
  const token = body.refresh_token?.trim();

  if (!token) {
    return c.json({ message: 'Refresh token is required.', code: 'invalid_request' }, 400);
  }

  const secret = getJwtSecret(c);
  const payload = await verifyJWT(token, secret);

  if (!payload || payload.type !== 'refresh') {
    return c.json({ message: 'Invalid or expired refresh token.', code: 'invalid_token' }, 401);
  }

  // Check token exists in D1 database
  const record = await c.env.DB.prepare('SELECT * FROM refresh_tokens WHERE token = ?').bind(token).first();
  if (!record) {
    return c.json({ message: 'Token has been revoked.', code: 'revoked_token' }, 401);
  }

  // Issue new access token
  const newAccessToken = await signJWT({ sub: payload.sub, phone: payload.phone, business_id: payload.business_id, type: 'access' }, secret, 3600 * 24);
  const newRefreshToken = await signJWT({ sub: payload.sub, phone: payload.phone, business_id: payload.business_id, type: 'refresh' }, secret, 3600 * 24 * 30);

  // Rotate refresh token
  const expiresAt = new Date(Date.now() + 30 * 24 * 3600 * 1000).toISOString();
  await c.env.DB.batch([
    c.env.DB.prepare('DELETE FROM refresh_tokens WHERE token = ?').bind(token),
    c.env.DB.prepare('INSERT INTO refresh_tokens (token, user_id, expires_at) VALUES (?, ?, ?)').bind(newRefreshToken, payload.sub, expiresAt),
  ]);

  return c.json({ access_token: newAccessToken, refresh_token: newRefreshToken });
});

// POST /auth/logout
authApp.post('/logout', async (c) => {
  const body: any = await c.req.json().catch(() => ({}));
  if (body.refresh_token) {
    await c.env.DB.prepare('DELETE FROM refresh_tokens WHERE token = ?').bind(body.refresh_token).run();
  }
  return c.json({ success: true });
});

// DELETE /auth/account (Apple App Store Guideline 5.1.1(v) compliance)
authApp.delete('/account', authMiddleware, async (c) => {
  const user = c.get('user');
  const businessId = user.business_id;

  // Delete all business data and user account
  await c.env.DB.batch([
    c.env.DB.prepare('DELETE FROM refresh_tokens WHERE user_id = ?').bind(user.id),
    c.env.DB.prepare('DELETE FROM campaign_leads WHERE campaign_id IN (SELECT id FROM campaigns WHERE business_id = ?)').bind(businessId),
    c.env.DB.prepare('DELETE FROM campaigns WHERE business_id = ?').bind(businessId),
    c.env.DB.prepare('DELETE FROM callbacks WHERE business_id = ?').bind(businessId),
    c.env.DB.prepare('DELETE FROM followups WHERE business_id = ?').bind(businessId),
    c.env.DB.prepare('DELETE FROM calls WHERE business_id = ?').bind(businessId),
    c.env.DB.prepare('DELETE FROM leads WHERE business_id = ?').bind(businessId),
    c.env.DB.prepare('DELETE FROM knowledge_sources WHERE business_id = ?').bind(businessId),
    c.env.DB.prepare('DELETE FROM devices WHERE business_id = ?').bind(businessId),
    c.env.DB.prepare('DELETE FROM notifications WHERE business_id = ?').bind(businessId),
    c.env.DB.prepare('DELETE FROM usage WHERE business_id = ?').bind(businessId),
    c.env.DB.prepare('DELETE FROM agents WHERE business_id = ?').bind(businessId),
    c.env.DB.prepare('DELETE FROM businesses WHERE id = ?').bind(businessId),
    c.env.DB.prepare('DELETE FROM users WHERE id = ?').bind(user.id),
  ]);

  return c.json({ success: true, message: 'Account and associated data permanently deleted.' });
});

export { authApp };
