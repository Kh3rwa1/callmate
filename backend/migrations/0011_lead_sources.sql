-- Migration 0011: speed-to-lead. Per-business lead capture (hosted enquiry form + webhook) that
-- AI-calls each new enquiry within about a minute (services/lead_capture.ts).

CREATE TABLE IF NOT EXISTS lead_sources (
  id          TEXT PRIMARY KEY,
  business_id TEXT NOT NULL,
  kind        TEXT NOT NULL CHECK (kind IN ('form', 'webhook')),
  -- Random, unguessable path segment: /f/<slug> (form) or /hooks/leads/<slug> (webhook).
  public_slug TEXT NOT NULL UNIQUE,
  -- Webhooks only: SHA-256 (hex) of the bearer token. The token is shown once and never stored.
  secret_hash TEXT,
  auto_call   INTEGER NOT NULL DEFAULT 1,
  created_at  TEXT NOT NULL DEFAULT (datetime('now')),
  revoked_at  TEXT,
  FOREIGN KEY(business_id) REFERENCES businesses(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_lead_sources_business ON lead_sources(business_id, revoked_at);

-- leads.source already exists (0001: 'Manual entry', 'CSV Import', ...). Captured leads use
-- 'form' or 'webhook', and remember which source they came through and when they last enquired
-- (a repeat enquiry within 24h is a duplicate: no new lead and no second call).
ALTER TABLE leads ADD COLUMN lead_source_id TEXT;
ALTER TABLE leads ADD COLUMN last_enquiry_at TEXT;
CREATE INDEX IF NOT EXISTS idx_leads_lead_source ON leads(lead_source_id);
