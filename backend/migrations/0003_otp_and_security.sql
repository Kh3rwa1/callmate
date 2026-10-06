-- Migration 0003: Real OTP Auth, Refresh Token Rotation, and Voice Proxy Security

-- 1. Real OTP Codes storage (SHA-256 hash, attempt counting, 5-minute expiry)
CREATE TABLE IF NOT EXISTS otp_codes (
    phone TEXT PRIMARY KEY,
    otp_hash TEXT NOT NULL,
    attempts INTEGER NOT NULL DEFAULT 0,
    expires_at TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- 2. OTP Rate Limiting per phone (3 per 10 min) and per IP (10 per 10 min)
CREATE TABLE IF NOT EXISTS otp_rate_limits (
    id TEXT PRIMARY KEY,
    phone TEXT NOT NULL,
    ip TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_otp_rate_limits_phone_created ON otp_rate_limits(phone, created_at);
CREATE INDEX IF NOT EXISTS idx_otp_rate_limits_ip_created ON otp_rate_limits(ip, created_at);

-- 3. Hardened Refresh Tokens (Token hash storage, single-use rotation, reuse detection)
CREATE TABLE IF NOT EXISTS refresh_tokens_v2 (
    token_hash TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    family_id TEXT NOT NULL,
    is_revoked INTEGER NOT NULL DEFAULT 0,
    expires_at TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_v2_family ON refresh_tokens_v2(family_id);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_v2_user ON refresh_tokens_v2(user_id);

-- 4. Voice Proxy Concurrent Sessions and Rate Limiting
CREATE TABLE IF NOT EXISTS voice_sessions (
    id TEXT PRIMARY KEY,
    business_id TEXT NOT NULL,
    user_id TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active',
    started_at TEXT NOT NULL DEFAULT (datetime('now')),
    ended_at TEXT,
    FOREIGN KEY(business_id) REFERENCES businesses(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_voice_sessions_biz_status ON voice_sessions(business_id, status);

CREATE TABLE IF NOT EXISTS voice_proxy_rate_limits (
    id TEXT PRIMARY KEY,
    business_id TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_voice_proxy_biz_created ON voice_proxy_rate_limits(business_id, created_at);
