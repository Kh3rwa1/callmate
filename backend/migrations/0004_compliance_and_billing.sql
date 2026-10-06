-- Migration 0004: Calling Compliance, Billing Integrity, and Performance Indexes

-- 1. Add compliance and timezone columns to leads table
ALTER TABLE leads ADD COLUMN do_not_call INTEGER NOT NULL DEFAULT 0;
ALTER TABLE leads ADD COLUMN consent TEXT DEFAULT 'implicit_inquiry';
ALTER TABLE leads ADD COLUMN timezone TEXT DEFAULT 'Asia/Kolkata';

-- 2. Add raw_metadata and created_at columns to calls table
ALTER TABLE calls ADD COLUMN raw_metadata TEXT;
ALTER TABLE calls ADD COLUMN created_at TEXT;
UPDATE calls SET created_at = COALESCE(started_at, datetime('now')) WHERE created_at IS NULL;

-- 3. Add attempt tracking to campaign_leads
ALTER TABLE campaign_leads ADD COLUMN attempts INTEGER NOT NULL DEFAULT 0;
ALTER TABLE campaign_leads ADD COLUMN last_attempt_at TEXT;
ALTER TABLE campaign_leads ADD COLUMN error TEXT;

-- 4. Unique index on (business_id, phone) for import dedupe & tenant isolation
CREATE UNIQUE INDEX IF NOT EXISTS idx_leads_business_phone ON leads(business_id, phone);

-- 5. Missing indexes from Phase 2 requirements
CREATE INDEX IF NOT EXISTS idx_calls_business_created ON calls(business_id, created_at);
CREATE INDEX IF NOT EXISTS idx_calls_lead_created ON calls(lead_id, created_at);
CREATE UNIQUE INDEX IF NOT EXISTS idx_calls_interaction_unique ON calls(interaction_id);
CREATE INDEX IF NOT EXISTS idx_followups_biz_status ON followups(business_id, status);

-- 6. Keyset pagination index for leads (created_at DESC, id DESC)
CREATE INDEX IF NOT EXISTS idx_leads_keyset ON leads(business_id, created_at, id);

-- 7. Push rate limits for batching follow-up pushes (max 1 per 10 min)
CREATE TABLE IF NOT EXISTS push_rate_limits (
    id TEXT PRIMARY KEY,
    business_id TEXT NOT NULL,
    type TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_push_rate_limits_biz_type ON push_rate_limits(business_id, type, created_at);
