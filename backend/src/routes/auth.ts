import { Hono } from 'hono';
import { Env, AuthUser } from '../types';
import { signJWT, verifyJWT, getJwtSecret, authMiddleware } from '../auth';
import { getSmsProvider } from '../sms';
import { parseJsonBody, otpRequestSchema, registerSchema, loginSchema, refreshSchema } from '../schemas/validation';
import { requireSecret, isDevEnv } from '../utils/secrets';
import { deleteR2Prefix } from '../utils/r2';

const authApp = new Hono<{ Bindings: Env; Variables: { user: AuthUser } }>();

// Helper to normalize phone numbers (e.g. 919830012345)
function normalizePhone(p: string): string {
  const digits = p.replace(/\D/g, '');
  if (digits.length === 10) return `91${digits}`;
  if (digits.length === 11 && digits.startsWith('0')) return `91${digits.slice(1)}`;
  if (digits.startsWith('91') && digits.length === 12) return digits;
  return digits;
}

async function sha256(text: string): Promise<string> {
  const enc = new TextEncoder();
  const hash = await crypto.subtle.digest('SHA-256', enc.encode(text));
  return Array.from(new Uint8Array(hash))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

async function hashOtp(env: Env, phone: string, code: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    'raw', new TextEncoder().encode(requireSecret(env, 'OTP_PEPPER')),
    { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']
  );
  const sig = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(`${phone}:${code}`));
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

// POST /auth/otp/request
// Rate limited: max 3 per 10min per phone, max 10 per 10min per IP
authApp.post('/otp/request', async (c) => {
  const parsed = await parseJsonBody(c, otpRequestSchema);
  if (!parsed.success) {
    return parsed.response;
  }
  const rawPhone = parsed.data.phone.trim();

  if (!rawPhone) {
    return c.json({ message: 'Phone number is required.', code: 'invalid_request' }, 400);
  }

  const phone = normalizePhone(rawPhone);
  if (phone.length < 10) {
    return c.json({ message: 'Invalid phone number format.', code: 'invalid_phone' }, 400);
  }

  const clientIp = c.req.header('cf-connecting-ip') || c.req.header('x-forwarded-for') || '127.0.0.1';

  // Rate limit check: D1 chosen because it is serverless, persistent across restarts,
  // globally consistent, and eliminates extra infrastructure/Durable Object costs.
  const phoneCount = await c.env.DB.prepare(
    `SELECT COUNT(*) as cnt FROM otp_rate_limits WHERE phone = ? AND created_at > datetime('now', '-10 minutes')`
  ).bind(phone).first<{ cnt: number }>();

  if (phoneCount && phoneCount.cnt >= 3) {
    return c.json({ message: 'Too many OTP requests for this number. Please wait 10 minutes.', code: 'rate_limited' }, 429);
  }

  const ipLimit = isDevEnv(c.env) ? 100 : 10;
  const ipCount = await c.env.DB.prepare(
    `SELECT COUNT(*) as cnt FROM otp_rate_limits WHERE ip = ? AND created_at > datetime('now', '-10 minutes')`
  ).bind(clientIp).first<{ cnt: number }>();

  if (ipCount && ipCount.cnt >= ipLimit) {
    return c.json({ message: 'Too many OTP requests from your network. Please wait.', code: 'rate_limited' }, 429);
  }

  // Generate cryptographically secure 6-digit OTP
  const randArr = new Uint32Array(1);
  crypto.getRandomValues(randArr);
  const otpCode = String((randArr[0] % 900000) + 100000); // 100000 - 999999
  const otpHash = await hashOtp(c.env, phone, otpCode);
  const expiresAt = new Date(Date.now() + 5 * 60 * 1000).toISOString(); // 5 minutes

  // Record OTP code and rate limit entry
  await c.env.DB.batch([
    c.env.DB.prepare(
      `INSERT OR REPLACE INTO otp_codes (phone, otp_hash, attempts, expires_at, created_at)
       VALUES (?, ?, 0, ?, datetime('now'))`
    ).bind(phone, otpHash, expiresAt),
    c.env.DB.prepare(
      `INSERT INTO otp_rate_limits (id, phone, ip, created_at) VALUES (?, ?, ?, datetime('now'))`
    ).bind(`rl_${crypto.randomUUID().slice(0, 12)}`, phone, clientIp),
  ]);

  // Dispatch via SMS provider
  const smsProvider = getSmsProvider(c.env);
  await smsProvider.sendOtp(phone, otpCode);

  return c.json({
    success: true,
    message: 'Verification code sent.',
    ...(isDevEnv(c.env) ? { debug_otp: otpCode } : {}),
  });
});

// POST /auth/register
// NEVER returns tokens for an existing phone. Requires verified OTP.
authApp.post('/register', async (c) => {
  const parsed = await parseJsonBody(c, registerSchema);
  if (!parsed.success) {
    return parsed.response;
  }
  const body = parsed.data;
  const rawPhone = body.phone.trim();
  const businessName = body.business_name.trim();
  const otp = body.otp.trim();

  const phone = normalizePhone(rawPhone);

  // 1. Conflict check: NEVER return tokens for an existing phone
  const existingUser = await c.env.DB.prepare('SELECT id FROM users WHERE phone = ?').bind(phone).first();
  if (existingUser) {
    return c.json({ message: 'An account with this phone number already exists. Please log in.', code: 'user_exists' }, 409);
  }

  // 2. Verify OTP
  const record = await c.env.DB.prepare('SELECT * FROM otp_codes WHERE phone = ?').bind(phone).first<{
    phone: string;
    otp_hash: string;
    attempts: number;
    expires_at: string;
  }>();

  if (!record) {
    return c.json({ message: 'Please request a verification code first.', code: 'invalid_otp' }, 400);
  }

  if (record.attempts >= 5) {
    return c.json({ message: 'Too many failed attempts. Verification code locked.', code: 'otp_locked' }, 429);
  }

  if (new Date(record.expires_at).getTime() < Date.now()) {
    return c.json({ message: 'Verification code has expired. Please request a new code.', code: 'otp_expired' }, 400);
  }

  const inputHash = await hashOtp(c.env, phone, otp);
  if (inputHash !== record.otp_hash) {
    await c.env.DB.prepare('UPDATE otp_codes SET attempts = attempts + 1 WHERE phone = ?').bind(phone).run();
    return c.json({ message: 'Invalid verification code.', code: 'invalid_otp' }, 400);
  }

  // Valid OTP: delete OTP record
  await c.env.DB.prepare('DELETE FROM otp_codes WHERE phone = ?').bind(phone).run();

  const secret = getJwtSecret(c);
  const userId = `usr_${crypto.randomUUID().slice(0, 12)}`;
  const businessId = `biz_${crypto.randomUUID().slice(0, 12)}`;
  const agentId = `agent_${crypto.randomUUID().slice(0, 12)}`;
  const usageId = `usage_${crypto.randomUUID().slice(0, 12)}`;
  const familyId = `fam_${crypto.randomUUID().slice(0, 12)}`;

  // Provision Business, Agent, User, and default Usage
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

  const accessToken = await signJWT({ sub: userId, phone, business_id: businessId, type: 'access' }, secret, 3600 * 24);
  const refreshToken = await signJWT({ sub: userId, phone, business_id: businessId, type: 'refresh' }, secret, 3600 * 24 * 30);
  const refreshHash = await sha256(refreshToken);
  const expiresAt = new Date(Date.now() + 30 * 24 * 3600 * 1000).toISOString();

  await c.env.DB.prepare(
    `INSERT INTO refresh_tokens_v2 (token_hash, user_id, family_id, is_revoked, expires_at, created_at)
     VALUES (?, ?, ?, 0, ?, datetime('now'))`
  ).bind(refreshHash, userId, familyId, expiresAt).run();

  return c.json({ access_token: accessToken, refresh_token: refreshToken });
});

// POST /auth/login
// Verifies OTP hash, enforces max 5 attempts, deletes OTP on success
authApp.post('/login', async (c) => {
  const parsed = await parseJsonBody(c, loginSchema);
  if (!parsed.success) {
    return parsed.response;
  }
  const body = parsed.data;
  const rawPhone = body.phone.trim();
  const otp = body.otp.trim();

  const phone = normalizePhone(rawPhone);

  const record = await c.env.DB.prepare('SELECT * FROM otp_codes WHERE phone = ?').bind(phone).first<{
    phone: string;
    otp_hash: string;
    attempts: number;
    expires_at: string;
  }>();

  if (!record) {
    return c.json({ message: 'Please request a verification code first.', code: 'invalid_otp' }, 400);
  }

  if (record.attempts >= 5) {
    return c.json({ message: 'Too many failed attempts. Verification code locked. Request a new OTP.', code: 'otp_locked' }, 429);
  }

  if (new Date(record.expires_at).getTime() < Date.now()) {
    return c.json({ message: 'Verification code has expired. Please request a new code.', code: 'otp_expired' }, 400);
  }

  const inputHash = await hashOtp(c.env, phone, otp);
  if (inputHash !== record.otp_hash) {
    await c.env.DB.prepare('UPDATE otp_codes SET attempts = attempts + 1 WHERE phone = ?').bind(phone).run();
    return c.json({ message: 'Invalid verification code.', code: 'invalid_otp' }, 400);
  }

  // Delete OTP on success
  await c.env.DB.prepare('DELETE FROM otp_codes WHERE phone = ?').bind(phone).run();

  const user = await c.env.DB.prepare('SELECT * FROM users WHERE phone = ?').bind(phone).first<{ id: string; business_id: string }>();
  if (!user) {
    return c.json({ message: 'Account not found. Please register first.', code: 'user_not_found' }, 404);
  }

  const secret = getJwtSecret(c);
  const familyId = `fam_${crypto.randomUUID().slice(0, 12)}`;

  const accessToken = await signJWT({ sub: user.id, phone, business_id: user.business_id, type: 'access' }, secret, 3600 * 24);
  const refreshToken = await signJWT({ sub: user.id, phone, business_id: user.business_id, type: 'refresh' }, secret, 3600 * 24 * 30);
  const refreshHash = await sha256(refreshToken);
  const expiresAt = new Date(Date.now() + 30 * 24 * 3600 * 1000).toISOString();

  await c.env.DB.prepare(
    `INSERT INTO refresh_tokens_v2 (token_hash, user_id, family_id, is_revoked, expires_at, created_at)
     VALUES (?, ?, ?, 0, ?, datetime('now'))`
  ).bind(refreshHash, user.id, familyId, expiresAt).run();

  return c.json({ access_token: accessToken, refresh_token: refreshToken });
});

// POST /auth/refresh
// Token rotation and family reuse detection
authApp.post('/refresh', async (c) => {
  const parsed = await parseJsonBody(c, refreshSchema);
  if (!parsed.success) {
    return parsed.response;
  }
  const token = parsed.data.refresh_token.trim();

  const secret = getJwtSecret(c);
  const payload = await verifyJWT(token, secret, 'refresh');

  if (!payload) {
    return c.json({ message: 'Invalid or expired refresh token.', code: 'invalid_token' }, 401);
  }

  const tokenHash = await sha256(token);

  // Check refresh token in D1
  const record = await c.env.DB.prepare('SELECT * FROM refresh_tokens_v2 WHERE token_hash = ?').bind(tokenHash).first<{
    token_hash: string;
    user_id: string;
    family_id: string;
    is_revoked: number;
    expires_at: string;
  }>();

  if (!record) {
    return c.json({ message: 'Token has been revoked or is invalid.', code: 'revoked_token' }, 401);
  }

  // Detect reuse: if token already revoked, revoke every token for user family
  if (record.is_revoked === 1) {
    await c.env.DB.prepare('UPDATE refresh_tokens_v2 SET is_revoked = 1 WHERE user_id = ?').bind(payload.sub).run();
    return c.json({ message: 'Refresh token reuse detected. All sessions revoked for security.', code: 'token_reuse_detected' }, 401);
  }

  if (new Date(record.expires_at).getTime() < Date.now()) {
    return c.json({ message: 'Refresh token has expired.', code: 'token_expired' }, 401);
  }

  // Mark current token revoked (single use)
  await c.env.DB.prepare('UPDATE refresh_tokens_v2 SET is_revoked = 1 WHERE token_hash = ?').bind(tokenHash).run();

  // Issue new access token and rotated refresh token within the same family
  const newAccessToken = await signJWT({ sub: payload.sub, phone: payload.phone, business_id: payload.business_id, type: 'access' }, secret, 3600 * 24);
  const newRefreshToken = await signJWT({ sub: payload.sub, phone: payload.phone, business_id: payload.business_id, type: 'refresh' }, secret, 3600 * 24 * 30);
  const newHash = await sha256(newRefreshToken);
  const expiresAt = new Date(Date.now() + 30 * 24 * 3600 * 1000).toISOString();

  await c.env.DB.prepare(
    `INSERT INTO refresh_tokens_v2 (token_hash, user_id, family_id, is_revoked, expires_at, created_at)
     VALUES (?, ?, ?, 0, ?, datetime('now'))`
  ).bind(newHash, payload.sub, record.family_id, expiresAt).run();

  return c.json({ access_token: newAccessToken, refresh_token: newRefreshToken });
});

// POST /auth/logout
authApp.post('/logout', async (c) => {
  const body: any = await c.req.json().catch(() => ({}));
  if (body.refresh_token) {
    const hash = await sha256(body.refresh_token.trim());
    await c.env.DB.prepare('UPDATE refresh_tokens_v2 SET is_revoked = 1 WHERE token_hash = ?').bind(hash).run();
  }
  return c.json({ success: true });
});

// DELETE /auth/account (Apple App Store Guideline 5.1.1(v) compliance)
authApp.delete('/account', authMiddleware, async (c) => {
  const user = c.get('user');
  const businessId = user.business_id;

  // 1. Delete all R2 storage objects under business prefix
  await deleteR2Prefix(c.env.KNOWLEDGE_BUCKET, `${businessId}/`);

  // 2. Delete from optional / future tables if present (Phase 6 RAG & chat)
  const optionalTables = ['chat_messages', 'knowledge_chunks', 'knowledge_fts'];
  for (const tbl of optionalTables) {
    try {
      const exists = await c.env.DB.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name = ?").bind(tbl).first();
      if (exists) {
        await c.env.DB.prepare(`DELETE FROM ${tbl} WHERE business_id = ?`).bind(businessId).run().catch(() => {});
      }
    } catch {}
  }

  // 3. Delete all business data and user account
  await c.env.DB.batch([
    c.env.DB.prepare('DELETE FROM refresh_tokens_v2 WHERE user_id = ?').bind(user.id),
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
    c.env.DB.prepare('DELETE FROM usage_ledger WHERE business_id = ?').bind(businessId),
    c.env.DB.prepare('DELETE FROM voice_sessions WHERE business_id = ?').bind(businessId),
    c.env.DB.prepare("DELETE FROM rate_limits WHERE bucket LIKE ?").bind(`chat:biz:${businessId}%`),
    c.env.DB.prepare('DELETE FROM agents WHERE business_id = ?').bind(businessId),
    c.env.DB.prepare('DELETE FROM businesses WHERE id = ?').bind(businessId),
    c.env.DB.prepare('DELETE FROM users WHERE id = ?').bind(user.id),
  ]);

  return c.json({ success: true, message: 'Account and associated data permanently deleted.' });
});

export { authApp };
