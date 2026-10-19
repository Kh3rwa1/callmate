-- AI answers the owner's missed calls. Numbers we rent in Sarvam (SARVAM_INBOUND_NUMBERS) are given
-- to a business once and stay with it: turning answering off only pauses its Sarvam deployment, so a
-- call-forwarding code the owner forgot to remove never reaches another business's AI.
CREATE TABLE IF NOT EXISTS inbound_numbers (
  phone TEXT PRIMARY KEY,               -- E.164 as Sarvam stores it, e.g. +917971440000
  business_id TEXT UNIQUE,              -- NULL while the number is free in the pool
  deployment_id TEXT,                   -- Sarvam inbound deployment routing this number to the agent
  enabled INTEGER NOT NULL DEFAULT 0,   -- 1 = the AI answers calls on this number
  assigned_at TEXT,
  created_at TEXT DEFAULT (datetime('now'))
);

-- 'outbound' (the AI called the lead) or 'inbound' (the lead called and the AI answered).
ALTER TABLE calls ADD COLUMN direction TEXT NOT NULL DEFAULT 'outbound';

-- Consent evidence: a person who phones the business has made an enquiry (source 'inbound_call').
-- SQLite cannot change a CHECK constraint in place, so the table is rebuilt (same as 0016).
CREATE TABLE IF NOT EXISTS consent_events_v3 (
  id            TEXT PRIMARY KEY,
  business_id   TEXT NOT NULL,
  lead_id       TEXT NOT NULL,
  consent_value TEXT NOT NULL,
  source        TEXT NOT NULL CHECK (source IN ('form', 'webhook', 'import_attestation', 'manual', 'in_call_opt_out',
                                                'google_ads', 'indiamart', 'meta_lead_ads', 'inbound_call')),
  text_version  TEXT NOT NULL,
  ip_hash       TEXT,
  created_at    TEXT NOT NULL DEFAULT (datetime('now'))
);

INSERT INTO consent_events_v3 (id, business_id, lead_id, consent_value, source, text_version, ip_hash, created_at)
  SELECT id, business_id, lead_id, consent_value, source, text_version, ip_hash, created_at FROM consent_events ORDER BY rowid;

DROP TABLE consent_events;
ALTER TABLE consent_events_v3 RENAME TO consent_events;
CREATE INDEX IF NOT EXISTS idx_consent_events_lead ON consent_events(business_id, lead_id, created_at);
