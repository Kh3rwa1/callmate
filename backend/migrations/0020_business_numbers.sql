-- Business numbers: every business on a plan that includes one (Growth) rents ONE fixed number from
-- the pool we rent in Sarvam. It is the caller ID of all its AI calls and the line its AI answers, so
-- customers always see and can call back the same number. The owner picks it once; it doesn't rotate.
--
-- status: 'free' (in the pool), 'active' (rented: Sarvam deployment live), 'held' (the plan lapsed or
-- was downgraded: deployment paused, the number waits for this business until held_until, then goes
-- back to the pool). forward_mode: how the owner's own phone forwards to it ('off', 'missed', 'all').
--
-- Replaces inbound_numbers (0019), which gave a number to whoever turned answering on.
CREATE TABLE IF NOT EXISTS business_numbers (
  phone         TEXT PRIMARY KEY,
  business_id   TEXT UNIQUE,
  deployment_id TEXT,
  status        TEXT NOT NULL DEFAULT 'free' CHECK (status IN ('free', 'active', 'held')),
  forward_mode  TEXT NOT NULL DEFAULT 'off' CHECK (forward_mode IN ('off', 'missed', 'all')),
  assigned_at   TEXT,
  held_until    TEXT,
  created_at    TEXT DEFAULT (datetime('now'))
);

INSERT OR IGNORE INTO business_numbers (phone, business_id, deployment_id, status, forward_mode, assigned_at, created_at)
  SELECT phone, business_id, deployment_id,
         CASE WHEN business_id IS NULL THEN 'free' ELSE 'active' END,
         CASE WHEN business_id IS NOT NULL AND enabled = 1 THEN answer_mode ELSE 'off' END,
         assigned_at, created_at
  FROM inbound_numbers;

DROP TABLE inbound_numbers;
CREATE INDEX IF NOT EXISTS idx_business_numbers_status ON business_numbers(status, held_until);
