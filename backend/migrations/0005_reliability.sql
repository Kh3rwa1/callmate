-- 0005: queue reliability, webhook idempotency, billing ledger, generic rate limits

ALTER TABLE campaign_leads ADD COLUMN call_id TEXT;
ALTER TABLE calls ADD COLUMN campaign_id TEXT;
ALTER TABLE calls ADD COLUMN failure_reason TEXT;

CREATE INDEX IF NOT EXISTS idx_campaign_leads_call_id ON campaign_leads(call_id);
CREATE INDEX IF NOT EXISTS idx_calls_status_started ON calls(status, started_at);

-- Webhook idempotency: one row per processed event
CREATE TABLE IF NOT EXISTS webhook_events (
  event_key   TEXT PRIMARY KEY,
  source      TEXT NOT NULL,
  received_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Billing ledger: at most one billable row per call
CREATE TABLE IF NOT EXISTS usage_ledger (
  call_id          TEXT PRIMARY KEY,
  business_id      TEXT NOT NULL,
  billable_seconds INTEGER NOT NULL DEFAULT 0,
  billed_minutes   INTEGER NOT NULL DEFAULT 0,
  created_at       TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at       TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_usage_ledger_business ON usage_ledger(business_id);

-- Generic rate-limit buckets (chat, knowledge ingest, etc.)
CREATE TABLE IF NOT EXISTS rate_limits (
  id         TEXT PRIMARY KEY,
  bucket     TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_rate_limits_bucket_created ON rate_limits(bucket, created_at);
