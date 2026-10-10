import { Hono } from 'hono';
import { Env, AuthUser } from '../types';
import { signJWT, verifyJWT, getJwtSecret, authMiddleware } from '../auth';
import { getSmsProvider } from '../sms';
import { parseJsonBody, otpRequestSchema, registerSchema, loginSchema, refreshSchema, googleSignInSchema } from '../schemas/validation';
import { verifyFirebaseIdToken } from '../services/firebase_auth';
import { requireSecret, isDevEnv } from '../utils/secrets';
import { deleteR2Prefix } from '../utils/r2';
import { hitRateLimit } from '../utils/rate_limit';
import { timingSafeEqual } from '../utils/compare';
import { recordReferral, referralDeletionStatements } from '../services/referrals';
import { claimTrialMinutes, rememberTrialIdentities, anonymisedBusinessId, getPlan, RATE_PER_MINUTE_INR } from '../services/plans';

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

export const MAX_OTP_ATTEMPTS = 5;

function clientIpOf(c: any): string {
  return c.req.header('cf-connecting-ip') || c.req.header('x-forwarded-for') || '127.0.0.1';
}

/** Per-IP limiter for OTP verification endpoints (login/register), on top of the per-code attempt cap. */
async function verifyIpLimited(c: any): Promise<Response | null> {
  const limit = isDevEnv(c.env) ? 1000 : 20;
  const { allowed, retryAfter } = await hitRateLimit(c.env.DB, `auth:verify:ip:${clientIpOf(c)}`, limit, 600);
  if (allowed) return null;
  c.header('Retry-After', String(retryAfter));
  return c.json({ message: 'Too many attempts from your network. Please wait a few minutes.', code: 'rate_limited' }, 429);
}

/**
 * Verifies an OTP without a check-then-act race: the attempt is CLAIMED atomically first
 * (attempts < MAX and not expired), and only a claimed attempt is compared. Concurrent guesses
 * can therefore never exceed MAX_OTP_ATTEMPTS. On success the code is consumed exactly once.
 */
async function verifyOtp(c: any, phone: string, otp: string): Promise<Response | null> {
  const claimed = await c.env.DB.prepare(
    `UPDATE otp_codes SET attempts = attempts + 1
     WHERE phone = ? AND attempts < ? AND expires_at > ?
     RETURNING otp_hash`
  ).bind(phone, MAX_OTP_ATTEMPTS, new Date().toISOString()).first();

  if (!claimed) {
    const record = await c.env.DB.prepare('SELECT attempts, expires_at FROM otp_codes WHERE phone = ?').bind(phone).first();
    if (!record) {
      return c.json({ message: 'Please request a verification code first.', code: 'invalid_otp' }, 400);
    }
    if (record.attempts >= MAX_OTP_ATTEMPTS) {
      return c.json({ message: 'Too many failed attempts. Verification code locked. Request a new OTP.', code: 'otp_locked' }, 429);
    }
    return c.json({ message: 'Verification code has expired. Please request a new code.', code: 'otp_expired' }, 400);
  }

  const inputHash = await hashOtp(c.env, phone, otp);
  const isMockStaging = c.env.ENVIRONMENT === 'staging' && !(c.env as any).MSG91_AUTH_KEY && !(c.env as any).GUPSHUP_API_KEY && !(c.env as any).EXOTEL_SID;
  const isMatch = (isMockStaging && (otp === '123456' || otp === '000000')) ||
    timingSafeEqual(inputHash, claimed.otp_hash);
  if (!isMatch) {
    return c.json({ message: 'Invalid verification code.', code: 'invalid_otp' }, 400);
  }

  // Consume the code; only one concurrent correct submission can win.
  const consumed = await c.env.DB.prepare('DELETE FROM otp_codes WHERE phone = ? AND otp_hash = ?').bind(phone, claimed.otp_hash).run();
  if ((consumed.meta?.changes ?? 0) !== 1) {
    return c.json({ message: 'Verification code already used. Please request a new code.', code: 'invalid_otp' }, 400);
  }
  return null;
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

  const clientIp = clientIpOf(c);

  // Rate limit: D1 chosen because it is serverless, persistent across restarts,
  // globally consistent, and eliminates extra infrastructure/Durable Object costs.
  // Check-and-record is a single statement so concurrent requests cannot overshoot the limits.
  const phoneLimit = 3;
  const ipLimit = isDevEnv(c.env) ? 100 : 10;
  const slot = await c.env.DB.prepare(
    `INSERT INTO otp_rate_limits (id, phone, ip, created_at)
     SELECT ?, ?, ?, datetime('now')
     WHERE (SELECT COUNT(*) FROM otp_rate_limits WHERE phone = ? AND created_at > datetime('now', '-10 minutes')) < ?
       AND (SELECT COUNT(*) FROM otp_rate_limits WHERE ip = ? AND created_at > datetime('now', '-10 minutes')) < ?`
  ).bind(`rl_${crypto.randomUUID().slice(0, 12)}`, phone, clientIp, phone, phoneLimit, clientIp, ipLimit).run();

  if ((slot.meta?.changes ?? 0) === 0) {
    const phoneCount = await c.env.DB.prepare(
      `SELECT COUNT(*) as cnt FROM otp_rate_limits WHERE phone = ? AND created_at > datetime('now', '-10 minutes')`
    ).bind(phone).first<{ cnt: number }>();
    if ((phoneCount?.cnt ?? 0) >= phoneLimit) {
      return c.json({ message: 'Too many OTP requests for this number. Please wait 10 minutes.', code: 'rate_limited' }, 429);
    }
    return c.json({ message: 'Too many OTP requests from your network. Please wait.', code: 'rate_limited' }, 429);
  }

  // Generate cryptographically secure 6-digit OTP
  const randArr = new Uint32Array(1);
  crypto.getRandomValues(randArr);
  const otpCode = String((randArr[0] % 900000) + 100000); // 100000 - 999999
  const otpHash = await hashOtp(c.env, phone, otpCode);
  const expiresAt = new Date(Date.now() + 5 * 60 * 1000).toISOString(); // 5 minutes

  await c.env.DB.prepare(
    `INSERT OR REPLACE INTO otp_codes (phone, otp_hash, attempts, expires_at, created_at)
     VALUES (?, ?, 0, ?, datetime('now'))`
  ).bind(phone, otpHash, expiresAt).run();

  // Dispatch via SMS provider
  const smsProvider = getSmsProvider(c.env);
  let delivered = false;
  try {
    delivered = await smsProvider.sendOtp(phone, otpCode);
  } catch {
    delivered = false;
  }
  if (!delivered) {
    // Don't leave a code the user never received; they can retry immediately.
    await c.env.DB.prepare('DELETE FROM otp_codes WHERE phone = ? AND otp_hash = ?').bind(phone, otpHash).run();
    return c.json({ error: 'sms_send_failed', code: 'sms_send_failed', message: "Couldn't send the code. Try again." }, 502);
  }

  return c.json({
    success: true,
    message: 'Verification code sent.',
    ...(isDevEnv(c.env) ? { debug_otp: otpCode } : {}),
  });
});

/** Creates business, default agent, user and usage rows for a new account. Returns the user id. */
async function provisionAccount(
  env: Env, phone: string, businessName: string, identity?: { firebaseUid: string; email: string | null }
): Promise<{ userId: string; businessId: string }> {
  const userId = `usr_${crypto.randomUUID().slice(0, 12)}`;
  const businessId = `biz_${crypto.randomUUID().slice(0, 12)}`;
  const agentId = `agent_${crypto.randomUUID().slice(0, 12)}`;
  const usageId = `usage_${crypto.randomUUID().slice(0, 12)}`;
  // A phone/email that already had a trial (e.g. deleted account, signing up again) gets 0 minutes.
  const trialMinutes = await claimTrialMinutes(env, { phone, email: identity?.email ?? null });
  const trial = getPlan('trial', env);

  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO businesses (id, name, category, created_at, updated_at) VALUES (?, ?, 'other', datetime('now'), datetime('now'))`
    ).bind(businessId, businessName),
    env.DB.prepare(
      `INSERT INTO agents (id, business_id, name, role, status, template_id, role_kind, skills, capabilities, calling_hours_start, calling_hours_end, voice, created_at, updated_at)
       VALUES (?, ?, 'Maya', 'Sales Assistant', 'active', 'generic_sales_v1', 'sales', '["sales", "bookAppointments"]', '["Calling", "Lead Qualification", "Follow-up", "Customer Questions"]', 10, 19, 'Friendly Female (Hindi/English)', datetime('now'), datetime('now'))`
    ).bind(agentId, businessId),
    env.DB.prepare(
      `INSERT INTO users (id, phone, business_id, firebase_uid, email, created_at) VALUES (?, ?, ?, ?, ?, datetime('now'))`
    ).bind(userId, phone, businessId, identity?.firebaseUid ?? null, identity?.email ?? null),
    env.DB.prepare(
      `INSERT INTO usage (id, business_id, plan_id, plan_status, current_period_end, plan_name, included_minutes, renews_at, price_inr, minutes_used, calls_made, rate_per_minute_inr)
       VALUES (?, ?, 'trial', 'trial', NULL, ?, ?, datetime('now'), 0, 0, 0, ?)`
    ).bind(usageId, businessId, trial.name, trialMinutes, RATE_PER_MINUTE_INR),
  ]);
  return { userId, businessId };
}

/** Issues an access token and a new refresh-token family. */
async function issueSession(c: any, userId: string, phone: string, businessId: string) {
  const secret = getJwtSecret(c);
  const familyId = `fam_${crypto.randomUUID().slice(0, 12)}`;
  const accessToken = await signJWT({ sub: userId, phone, business_id: businessId, type: 'access' }, secret, 3600 * 24);
  const refreshToken = await signJWT({ sub: userId, phone, business_id: businessId, type: 'refresh' }, secret, 3600 * 24 * 30);
  const refreshHash = await sha256(refreshToken);
  const expiresAt = new Date(Date.now() + 30 * 24 * 3600 * 1000).toISOString();
  await c.env.DB.prepare(
    `INSERT INTO refresh_tokens_v2 (token_hash, user_id, family_id, is_revoked, expires_at, created_at)
     VALUES (?, ?, ?, 0, ?, datetime('now'))`
  ).bind(refreshHash, userId, familyId, expiresAt).run();
  return { access_token: accessToken, refresh_token: refreshToken };
}

// POST /auth/google
// Firebase (Google) sign-in. Existing account: tokens. New account: needs business_name + phone
// (the business contact number; not OTP-verified, so it can never claim an existing phone account).
authApp.post('/google', async (c) => {
  const parsed = await parseJsonBody(c, googleSignInSchema);
  if (!parsed.success) {
    return parsed.response;
  }
  const limited = await verifyIpLimited(c);
  if (limited) return limited;
  const body = parsed.data;

  let identity;
  try {
    identity = await verifyFirebaseIdToken(body.id_token.trim(), c.env.FIREBASE_PROJECT_ID || '');
  } catch (err: any) {
    console.error(JSON.stringify({ msg: 'firebase_jwks_unavailable', error: String(err?.message ?? err) }));
    return c.json({ message: 'Sign-in is temporarily unavailable. Please try again.', code: 'auth_unavailable' }, 503);
  }
  if (!identity) {
    return c.json({ message: 'Google sign-in could not be verified. Please try again.', code: 'invalid_token' }, 401);
  }

  const existing = await c.env.DB.prepare('SELECT id, phone, business_id FROM users WHERE firebase_uid = ?')
    .bind(identity.uid).first<{ id: string; phone: string; business_id: string }>();
  if (existing) {
    return c.json(await issueSession(c, existing.id, existing.phone, existing.business_id));
  }

  if (!body.business_name?.trim() || !body.phone?.trim()) {
    return c.json({ message: 'Tell us your business name and phone number to finish signing up.', code: 'registration_required' }, 404);
  }
  const phone = normalizePhone(body.phone.trim());
  if (phone.length < 10 || phone.length > 15) {
    return c.json({ message: 'Please enter a valid phone number.', code: 'invalid_phone' }, 400);
  }
  const phoneTaken = await c.env.DB.prepare('SELECT id FROM users WHERE phone = ?').bind(phone).first();
  if (phoneTaken) {
    return c.json({ message: 'This phone number is already used by another account.', code: 'phone_in_use' }, 409);
  }

  const { userId, businessId } = await provisionAccount(c.env, phone, body.business_name.trim(), { firebaseUid: identity.uid, email: identity.email });
  await recordReferral(c.env, businessId, body.referral_code, { phone, email: identity.email });
  return c.json(await issueSession(c, userId, phone, businessId));
});

// POST /auth/register
// NEVER returns tokens for an existing phone. Requires verified OTP.
authApp.post('/register', async (c) => {
  const parsed = await parseJsonBody(c, registerSchema);
  if (!parsed.success) {
    return parsed.response;
  }
  const limited = await verifyIpLimited(c);
  if (limited) return limited;
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

  // 2. Verify OTP (atomic attempt claim; consumes the code on success)
  const otpError = await verifyOtp(c, phone, otp);
  if (otpError) return otpError;

  const { userId, businessId } = await provisionAccount(c.env, phone, businessName);
  await recordReferral(c.env, businessId, body.referral_code, { phone });
  return c.json(await issueSession(c, userId, phone, businessId));
});

// POST /auth/login
// Verifies OTP hash, enforces max 5 attempts, deletes OTP on success
authApp.post('/login', async (c) => {
  const parsed = await parseJsonBody(c, loginSchema);
  if (!parsed.success) {
    return parsed.response;
  }
  const limited = await verifyIpLimited(c);
  if (limited) return limited;
  const body = parsed.data;
  const rawPhone = body.phone.trim();
  const otp = body.otp.trim();

  const phone = normalizePhone(rawPhone);

  // Atomic attempt claim; consumes the code on success
  const otpError = await verifyOtp(c, phone, otp);
  if (otpError) return otpError;

  const user = await c.env.DB.prepare('SELECT * FROM users WHERE phone = ?').bind(phone).first<{ id: string; business_id: string }>();
  if (!user) {
    return c.json({ message: 'Account not found. Please register first.', code: 'user_not_found' }, 404);
  }

  return c.json(await issueSession(c, user.id, phone, user.business_id));
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

  // Mark current token revoked (single use). Conditional so two concurrent refreshes cannot both
  // rotate the same token: the loser is treated exactly like reuse.
  const rotated = await c.env.DB.prepare(
    'UPDATE refresh_tokens_v2 SET is_revoked = 1 WHERE token_hash = ? AND is_revoked = 0'
  ).bind(tokenHash).run();
  if ((rotated.meta?.changes ?? 0) !== 1) {
    await c.env.DB.prepare('UPDATE refresh_tokens_v2 SET is_revoked = 1 WHERE user_id = ?').bind(payload.sub).run();
    return c.json({ message: 'Refresh token reuse detected. All sessions revoked for security.', code: 'token_reuse_detected' }, 401);
  }

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
  const optionalTables = ['chat_messages', 'knowledge_chunks', 'knowledge_fts', 'lead_sources'];
  for (const tbl of optionalTables) {
    try {
      const exists = await c.env.DB.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name = ?").bind(tbl).first();
      if (exists) {
        await c.env.DB.prepare(`DELETE FROM ${tbl} WHERE business_id = ?`).bind(businessId).run().catch(() => {});
      }
    } catch {}
  }

  // 3. Billing records are retained for invoices/GST but anonymised: PII nulled, business_id
  //    replaced by a stable pseudonym. Trial identities are remembered so a re-signup gets no new trial.
  const account = await c.env.DB.prepare('SELECT phone, email FROM users WHERE id = ?')
    .bind(user.id).first<{ phone: string | null; email: string | null }>();
  const anonId = await anonymisedBusinessId(c.env, businessId);
  const rememberTrial = await rememberTrialIdentities(c.env, { phone: account?.phone ?? user.phone, email: account?.email ?? null });

  // 4. Delete all business data and user account
  await c.env.DB.batch([
    ...rememberTrial,
    c.env.DB.prepare('UPDATE usage_ledger SET business_id = ? WHERE business_id = ?').bind(anonId, businessId),
    ...referralDeletionStatements(c.env, businessId, anonId),
    c.env.DB.prepare(
      `UPDATE payments SET business_id = ?, contact_email = NULL, contact_phone = NULL, anonymized_at = datetime('now')
       WHERE business_id = ?`
    ).bind(anonId, businessId),
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
    c.env.DB.prepare('DELETE FROM voice_sessions WHERE business_id = ?').bind(businessId),
    c.env.DB.prepare("DELETE FROM rate_limits WHERE bucket LIKE ?").bind(`chat:biz:${businessId}%`),
    c.env.DB.prepare("DELETE FROM rate_limits WHERE bucket LIKE ?").bind(`chat:user:${user.id}%`),
    c.env.DB.prepare("DELETE FROM rate_limits WHERE bucket LIKE ?").bind(`knowledge:biz:${businessId}%`),
    c.env.DB.prepare('DELETE FROM push_rate_limits WHERE business_id = ?').bind(businessId),
    c.env.DB.prepare('DELETE FROM otp_codes WHERE phone = ?').bind(user.phone),
    c.env.DB.prepare('DELETE FROM otp_rate_limits WHERE phone = ?').bind(user.phone),
    c.env.DB.prepare('DELETE FROM agents WHERE business_id = ?').bind(businessId),
    c.env.DB.prepare('DELETE FROM businesses WHERE id = ?').bind(businessId),
    c.env.DB.prepare('DELETE FROM users WHERE id = ?').bind(user.id),
  ]);

  return c.json({ success: true, message: 'Account and associated data permanently deleted.' });
});

export { authApp };
