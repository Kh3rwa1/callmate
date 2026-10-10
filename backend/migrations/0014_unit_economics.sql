-- Migration 0014: unit economics (cost tracking), waste control and the extended plan catalogue.
-- Additive only.

-- Per-call billing + our cost. billed_minutes is what the owner was charged (0 for unanswered /
-- voicemail / < 10 s calls); cost_inr is what the call cost us (Sarvam + telephony), billed or not.
ALTER TABLE calls ADD COLUMN billed_minutes INTEGER;
ALTER TABLE calls ADD COLUMN cost_inr REAL;
-- Set once when the long-call watchdog has logged this call (so it is logged once, not every cron).
ALTER TABLE calls ADD COLUMN overrun_flagged_at TEXT;

-- The ledger survives account deletion (anonymised), so the margin report reads it, not calls.
-- duration_seconds = real call length (cost basis); billable_seconds stays the billed length.
ALTER TABLE usage_ledger ADD COLUMN duration_seconds INTEGER NOT NULL DEFAULT 0;
ALTER TABLE usage_ledger ADD COLUMN cost_inr REAL NOT NULL DEFAULT 0;
ALTER TABLE usage_ledger ADD COLUMN plan_id TEXT;
CREATE INDEX IF NOT EXISTS idx_usage_ledger_created ON usage_ledger(created_at);

-- Sarvam reported the number invalid / unreachable: campaigns skip it until the phone is edited.
ALTER TABLE leads ADD COLUMN phone_invalid INTEGER NOT NULL DEFAULT 0;

-- Annual plans: the cron re-grants annual_plan_id's monthly minutes each month until annual_until.
ALTER TABLE usage ADD COLUMN billing_cycle TEXT NOT NULL DEFAULT 'monthly';
ALTER TABLE usage ADD COLUMN annual_until TEXT;
ALTER TABLE usage ADD COLUMN annual_plan_id TEXT;
-- Minute balances (services/plans.ts minutesRemaining):
--   included_minutes = this period's plan grant (reset at every renewal / annual month)
--   topup_minutes    = top-up packs bought this period; expire at current_period_end (reset at renewal)
--   bonus_minutes    = referral / goodwill credit; never reset by renewal
-- minutes_used counts all consumption this period; plan minutes are used first, then top-ups,
-- then bonus. At renewal the part of minutes_used beyond plan + top-up is deducted from bonus.
ALTER TABLE usage ADD COLUMN topup_minutes INTEGER NOT NULL DEFAULT 0;
ALTER TABLE usage ADD COLUMN bonus_minutes INTEGER NOT NULL DEFAULT 0;

-- What a payment bought and its GST split. Legacy rows: kind 'plan', base/gst NULL (no GST charged).
ALTER TABLE payments ADD COLUMN kind TEXT NOT NULL DEFAULT 'plan';
ALTER TABLE payments ADD COLUMN base_paise INTEGER;
ALTER TABLE payments ADD COLUMN gst_paise INTEGER;
CREATE INDEX IF NOT EXISTS idx_payments_created ON payments(created_at);
