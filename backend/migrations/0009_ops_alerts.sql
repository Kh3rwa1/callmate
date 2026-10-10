-- 0009: ops alerting (services/alerts.ts)

-- One row per alert type: when it was last sent, so each type alerts at most once per hour.
CREATE TABLE IF NOT EXISTS alert_state (
  alert_type   TEXT PRIMARY KEY,
  last_sent_at TEXT NOT NULL,
  last_count   INTEGER NOT NULL DEFAULT 0
);

-- Operational events nothing else records: dead-lettered queue messages, rejected webhooks.
CREATE TABLE IF NOT EXISTS ops_events (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  kind       TEXT NOT NULL,
  detail     TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_ops_events_kind_created ON ops_events(kind, created_at);
