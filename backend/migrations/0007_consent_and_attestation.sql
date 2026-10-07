-- Migration 0007: Consent and attestation tracking for campaigns
ALTER TABLE campaigns ADD COLUMN attested_by TEXT;
ALTER TABLE campaigns ADD COLUMN attested_at TEXT;
