-- Business numbers on request: a paying business that asks for a number while none is free waits
-- here. Numbers can only be bought in the Sarvam dashboard, so the cron alerts the operator, and when
-- a number is added to SARVAM_BUSINESS_NUMBERS it goes to the longest-waiting business automatically.
CREATE TABLE IF NOT EXISTS number_requests (
  business_id  TEXT PRIMARY KEY,
  requested_at TEXT NOT NULL DEFAULT (datetime('now'))
);
