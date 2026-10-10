-- Migration 0009: plans, free trial, Razorpay payments.
--
-- Existing usage rows default to plan_id='starter', plan_status='active' with their current
-- included_minutes/minutes_used, and current_period_end NULL. NULL means "never expires via the
-- cron", so no account that exists today (e.g. on staging) loses access. Their period starts on
-- their first verified payment. New signups are inserted explicitly as plan_id='trial'.

ALTER TABLE usage ADD COLUMN plan_id TEXT NOT NULL DEFAULT 'starter';
ALTER TABLE usage ADD COLUMN plan_status TEXT NOT NULL DEFAULT 'active';
ALTER TABLE usage ADD COLUMN current_period_end TEXT;

CREATE INDEX IF NOT EXISTS idx_usage_plan_status_period ON usage(plan_status, current_period_end);

-- One row per identity (HMAC of phone digits / lower-cased email; never the raw value) that has
-- ever received a trial. Survives account deletion so a re-signup gets 0 trial minutes.
CREATE TABLE IF NOT EXISTS trial_grants (
  identity_hash TEXT PRIMARY KEY,
  minutes       INTEGER NOT NULL DEFAULT 0,
  created_at    TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Verified Razorpay payments (the invoice record). razorpay_payment_id UNIQUE makes webhook
-- processing idempotent. Rows are kept on account deletion with PII nulled and business_id
-- replaced by a stable pseudonym (anonymized_at set).
CREATE TABLE IF NOT EXISTS payments (
  id                       TEXT PRIMARY KEY,
  razorpay_payment_id      TEXT NOT NULL UNIQUE,
  razorpay_payment_link_id TEXT,
  business_id              TEXT NOT NULL,
  plan_id                  TEXT NOT NULL,
  amount_paise             INTEGER NOT NULL,
  currency                 TEXT NOT NULL DEFAULT 'INR',
  status                   TEXT NOT NULL,
  contact_email            TEXT,
  contact_phone            TEXT,
  period_end               TEXT,
  applied_at               TEXT,
  anonymized_at            TEXT,
  created_at               TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_payments_business ON payments(business_id, created_at);
