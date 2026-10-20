-- Business numbers without a deploy. A number bought in Sarvam joins the pool on its own (the cron
-- reads the connection's numbers when SARVAM_AUTO_NUMBERS is on, source 'auto') or when the operator
-- adds it on the ops page (/ops/numbers, source 'ops'). When a business rents such a number, a free
-- agent from the pre-made receptionist pool (SARVAM_RECEPTIONIST_AGENTS) is claimed onto the row and
-- its deployment is created with that agent. The pool agent's on-start hook URL names the agent, not
-- the number, so the row holding the agent tells /voice/inbound/start which number was called. The
-- agent stays on the row while the number is held and is cleared when the number goes back to the pool.
--
-- source: 'config' = listed in SARVAM_BUSINESS_NUMBERS (its agent is configured there, not stored
-- here), 'ops' = added on the ops page, 'auto' = found in Sarvam by the cron ('auto' and 'ops' behave
-- the same).
ALTER TABLE business_numbers ADD COLUMN agent_app_id TEXT;
ALTER TABLE business_numbers ADD COLUMN agent_version INTEGER;
ALTER TABLE business_numbers ADD COLUMN source TEXT NOT NULL DEFAULT 'config' CHECK (source IN ('config', 'ops', 'auto'));

-- One agent never answers two numbers: claiming an agent another row holds fails.
CREATE UNIQUE INDEX IF NOT EXISTS idx_business_numbers_agent ON business_numbers(agent_app_id) WHERE agent_app_id IS NOT NULL;

-- Numbers the operator took out of the pool on the ops page: the cron never picks them up again.
-- Adding one on the ops page again clears it.
CREATE TABLE IF NOT EXISTS removed_numbers (
  phone      TEXT PRIMARY KEY,
  removed_at TEXT NOT NULL DEFAULT (datetime('now'))
);
