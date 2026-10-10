-- Migration 0013: regulatory hardening (TRAI TCCCPR + DPDP Act 2023).

-- Platform-wide do-not-call list fed by the public /stop page. Holds only an HMAC of the phone
-- digits (OTP_PEPPER, falling back to ENCRYPTION_KEY), never the number itself. Not tied to a
-- business: a number here is never dialled by any CallPilot business.
CREATE TABLE IF NOT EXISTS global_dnc (
  phone_hash TEXT PRIMARY KEY,
  source     TEXT NOT NULL CHECK (source IN ('web', 'call', 'admin')),
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Evidence trail of every consent change on a lead (who/what set it, under which text version).
CREATE TABLE IF NOT EXISTS consent_events (
  id            TEXT PRIMARY KEY,
  business_id   TEXT NOT NULL,
  lead_id       TEXT NOT NULL,
  consent_value TEXT NOT NULL,
  source        TEXT NOT NULL CHECK (source IN ('form', 'webhook', 'import_attestation', 'manual', 'in_call_opt_out')),
  text_version  TEXT NOT NULL,
  ip_hash       TEXT,
  created_at    TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_consent_events_lead ON consent_events(business_id, lead_id, created_at);

-- Cross-business frequency cap looks calls up by phone number.
CREATE INDEX IF NOT EXISTS idx_calls_lead_phone_started ON calls(lead_phone, started_at);
-- Retention sweep finds old calls by start time.
CREATE INDEX IF NOT EXISTS idx_calls_started ON calls(started_at);
