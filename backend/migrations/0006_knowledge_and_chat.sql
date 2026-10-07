-- 0006_knowledge_and_chat.sql: Chunking, FTS5 search & multi-turn chat messages

CREATE TABLE IF NOT EXISTS knowledge_chunks (
  id          TEXT PRIMARY KEY,
  business_id TEXT NOT NULL,
  source_id   TEXT NOT NULL,
  chunk_index INTEGER NOT NULL,
  content     TEXT NOT NULL,
  FOREIGN KEY(source_id) REFERENCES knowledge_sources(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_kchunks_biz ON knowledge_chunks(business_id);

-- Full-text search (SQLite FTS5 on Cloudflare D1)
CREATE VIRTUAL TABLE IF NOT EXISTS knowledge_fts USING fts5(
  content, business_id UNINDEXED, source_id UNINDEXED, chunk_id UNINDEXED
);

CREATE TABLE IF NOT EXISTS chat_messages (
  id              TEXT PRIMARY KEY,
  conversation_id TEXT NOT NULL,
  business_id     TEXT NOT NULL,
  role            TEXT NOT NULL CHECK (role IN ('user','assistant')),
  content         TEXT NOT NULL,
  created_at      TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_chat_conv ON chat_messages(conversation_id, created_at);
