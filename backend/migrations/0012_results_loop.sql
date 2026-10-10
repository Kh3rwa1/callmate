-- 0012: results loop (daily hot-lead digest, results/ROI card, "hear your AI now" owner test call).

-- Owner settings (PATCH /business). digest_enabled: the 19:00 daily summary push (on by default).
-- avg_deal_value_inr: optional average sale value; NULL = not set (the results card asks for it).
ALTER TABLE businesses ADD COLUMN digest_enabled INTEGER NOT NULL DEFAULT 1;
ALTER TABLE businesses ADD COLUMN avg_deal_value_inr INTEGER;

-- The owner's own number, dialled by POST /agent/test-call. Excluded from the customer list,
-- stats, results, the digest and campaigns.
ALTER TABLE leads ADD COLUMN is_owner_test INTEGER NOT NULL DEFAULT 0;
CREATE INDEX IF NOT EXISTS idx_leads_owner_test ON leads(business_id, is_owner_test);

-- One daily digest per business per local date (services/digest.ts).
CREATE TABLE IF NOT EXISTS digest_log (
  business_id TEXT NOT NULL,
  date        TEXT NOT NULL,
  sent_at     TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (business_id, date)
);
