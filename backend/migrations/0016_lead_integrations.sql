-- Migration 0016: lead integrations. Google Ads lead forms, IndiaMART Lead Manager and Meta
-- (Facebook / Instagram) Lead Ads become lead_sources kinds feeding the same speed-to-lead
-- pipeline (services/lead_capture.ts captureLead, services/lead_integrations.ts).
--
-- SQLite cannot change a CHECK constraint in place, so lead_sources and consent_events are
-- rebuilt with the wider value lists (copy, drop, rename). Nothing references either table by
-- foreign key. Statements contain no semicolons inside literals or comments (the test harness
-- splits on them).

CREATE TABLE IF NOT EXISTS lead_sources_v2 (
  id              TEXT PRIMARY KEY,
  business_id     TEXT NOT NULL,
  kind            TEXT NOT NULL CHECK (kind IN ('form', 'webhook', 'google_ads', 'indiamart', 'meta')),
  public_slug     TEXT NOT NULL UNIQUE,
  -- SHA-256 (hex) of the secret shown once: webhook bearer token, Google Ads key, IndiaMART push
  -- token or Meta verify token. Never the secret itself.
  secret_hash     TEXT,
  auto_call       INTEGER NOT NULL DEFAULT 1,
  created_at      TEXT NOT NULL DEFAULT (datetime('now')),
  revoked_at      TEXT,
  -- Integration secrets the server must use later (IndiaMART CRM key, Meta app secret and page
  -- token) as JSON, AES-256-GCM encrypted with ENCRYPTION_KEY (utils/crypto_data.ts). Never returned.
  config_encrypted TEXT,
  -- IndiaMART pull bookkeeping: last claim time (rate limit: one pull per 5 min), end of the
  -- last successful window (ISO UTC), and a back-off time after IndiaMART blocks the key.
  last_pulled_at  TEXT,
  last_cursor     TEXT,
  next_pull_at    TEXT,
  -- Last integration problem the owner should fix (e.g. 'invalid_key'), cleared on success.
  last_error      TEXT,
  FOREIGN KEY(business_id) REFERENCES businesses(id) ON DELETE CASCADE
);

INSERT INTO lead_sources_v2 (id, business_id, kind, public_slug, secret_hash, auto_call, created_at, revoked_at)
  SELECT id, business_id, kind, public_slug, secret_hash, auto_call, created_at, revoked_at FROM lead_sources;

DROP TABLE lead_sources;
ALTER TABLE lead_sources_v2 RENAME TO lead_sources;
CREATE INDEX IF NOT EXISTS idx_lead_sources_business ON lead_sources(business_id, revoked_at);
CREATE INDEX IF NOT EXISTS idx_lead_sources_kind ON lead_sources(kind, revoked_at);

CREATE TABLE IF NOT EXISTS consent_events_v2 (
  id            TEXT PRIMARY KEY,
  business_id   TEXT NOT NULL,
  lead_id       TEXT NOT NULL,
  consent_value TEXT NOT NULL,
  source        TEXT NOT NULL CHECK (source IN ('form', 'webhook', 'import_attestation', 'manual', 'in_call_opt_out',
                                                'google_ads', 'indiamart', 'meta_lead_ads')),
  text_version  TEXT NOT NULL,
  ip_hash       TEXT,
  created_at    TEXT NOT NULL DEFAULT (datetime('now'))
);

INSERT INTO consent_events_v2 (id, business_id, lead_id, consent_value, source, text_version, ip_hash, created_at)
  SELECT id, business_id, lead_id, consent_value, source, text_version, ip_hash, created_at FROM consent_events ORDER BY rowid;

DROP TABLE consent_events;
ALTER TABLE consent_events_v2 RENAME TO consent_events;
CREATE INDEX IF NOT EXISTS idx_consent_events_lead ON consent_events(business_id, lead_id, created_at);

-- Provider lead ids already turned into leads (Google lead_id, IndiaMART UNIQUE_QUERY_ID, Meta
-- leadgen_id): providers redeliver and IndiaMART pull windows overlap, so each id is claimed once.
CREATE TABLE IF NOT EXISTS lead_external_ids (
  business_id    TEXT NOT NULL,
  kind           TEXT NOT NULL,
  external_id    TEXT NOT NULL,
  lead_source_id TEXT NOT NULL,
  lead_id        TEXT,
  created_at     TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (business_id, kind, external_id)
);
CREATE INDEX IF NOT EXISTS idx_lead_external_ids_created ON lead_external_ids(created_at);
