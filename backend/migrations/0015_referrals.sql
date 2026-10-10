-- Migration 0015: referral program (customers bring customers).
--
-- businesses.referral_code: short, unambiguous code, generated lazily (GET /referrals).
-- referrals: one row per referred business (referred_business_id UNIQUE). Rewarded once, on the
--   referred business's first applied payment (services/referrals.ts onFirstPayment).
--   referred_identity_hash is the HMAC'd phone identity (same hashing as trial_grants), so the same
--   phone can't be referred twice, even after deleting the account and signing up again.
--   reward_nonce makes the reward batch apply at most once (only the run that flipped the status matches).
-- referral_credits: ledger of bonus minutes granted (one row per business per referral).
-- On account deletion, business ids in both tables are replaced by the anon_ pseudonym.

ALTER TABLE businesses ADD COLUMN referral_code TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS idx_businesses_referral_code ON businesses(referral_code);

CREATE TABLE IF NOT EXISTS referrals (
  id                     TEXT PRIMARY KEY,
  referrer_business_id   TEXT NOT NULL,
  referred_business_id   TEXT NOT NULL UNIQUE,
  code                   TEXT NOT NULL,
  status                 TEXT NOT NULL DEFAULT 'signed_up' CHECK (status IN ('signed_up', 'rewarded')),
  referred_identity_hash TEXT,
  reward_nonce           TEXT,
  created_at             TEXT NOT NULL DEFAULT (datetime('now')),
  rewarded_at            TEXT
);
CREATE INDEX IF NOT EXISTS idx_referrals_referrer ON referrals(referrer_business_id, status);
CREATE UNIQUE INDEX IF NOT EXISTS idx_referrals_identity ON referrals(referred_identity_hash);

CREATE TABLE IF NOT EXISTS referral_credits (
  id          TEXT PRIMARY KEY,
  referral_id TEXT NOT NULL,
  business_id TEXT NOT NULL,
  minutes     INTEGER NOT NULL,
  created_at  TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE (referral_id, business_id)
);
CREATE INDEX IF NOT EXISTS idx_referral_credits_business ON referral_credits(business_id);
