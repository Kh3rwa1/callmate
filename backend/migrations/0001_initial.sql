-- CallPilot Cloudflare D1 Database Schema (v1)

CREATE TABLE IF NOT EXISTS users (
    id TEXT PRIMARY KEY,
    phone TEXT NOT NULL UNIQUE,
    business_id TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS refresh_tokens (
    token TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    expires_at TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS businesses (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    category TEXT NOT NULL DEFAULT 'other',
    address TEXT,
    offerings TEXT, -- JSON array of strings
    pricing TEXT,
    opening_hours TEXT,
    location TEXT,
    whatsapp_number TEXT,
    human_number TEXT,
    owner_name TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS agents (
    id TEXT PRIMARY KEY,
    business_id TEXT NOT NULL,
    name TEXT NOT NULL,
    role TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active',
    template_id TEXT NOT NULL DEFAULT 'generic_sales_v1',
    role_kind TEXT NOT NULL DEFAULT 'sales',
    skills TEXT NOT NULL DEFAULT '[]', -- JSON array of strings
    languages TEXT NOT NULL DEFAULT '["English", "Hindi"]', -- JSON array
    goal TEXT NOT NULL DEFAULT '',
    formality REAL NOT NULL DEFAULT 0.35,
    capabilities TEXT NOT NULL DEFAULT '[]', -- JSON array
    calling_hours_start INTEGER NOT NULL DEFAULT 10,
    calling_hours_end INTEGER NOT NULL DEFAULT 19,
    transfer_number TEXT,
    voice TEXT NOT NULL DEFAULT 'Friendly Female (Hindi/English)',
    calls_today INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY(business_id) REFERENCES businesses(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS knowledge_sources (
    id TEXT PRIMARY KEY,
    business_id TEXT NOT NULL,
    type TEXT NOT NULL, -- pdf, website, faq, businessInfo, text
    title TEXT NOT NULL,
    detail TEXT,
    status TEXT NOT NULL DEFAULT 'ready', -- uploading, processing, ready, failed
    progress REAL NOT NULL DEFAULT 1.0,
    content TEXT,
    file_url TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY(business_id) REFERENCES businesses(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS leads (
    id TEXT PRIMARY KEY,
    business_id TEXT NOT NULL,
    name TEXT NOT NULL,
    phone TEXT NOT NULL,
    interest TEXT,
    source TEXT DEFAULT 'Manual entry',
    status TEXT NOT NULL DEFAULT 'new', -- new, called, interested, hot, warm, cold, lost
    temperature TEXT, -- hot, warm, cold
    score INTEGER,
    summary TEXT,
    objections TEXT DEFAULT '[]', -- JSON array
    next_action TEXT DEFAULT 'none',
    callback_at TEXT,
    attributes TEXT DEFAULT '{}', -- JSON object
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY(business_id) REFERENCES businesses(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_leads_business ON leads(business_id);
CREATE INDEX IF NOT EXISTS idx_leads_phone ON leads(phone);
CREATE INDEX IF NOT EXISTS idx_leads_temperature ON leads(temperature);
CREATE INDEX IF NOT EXISTS idx_leads_status ON leads(status);

CREATE TABLE IF NOT EXISTS calls (
    id TEXT PRIMARY KEY,
    business_id TEXT NOT NULL,
    lead_id TEXT NOT NULL,
    lead_name TEXT NOT NULL,
    lead_phone TEXT NOT NULL,
    status TEXT NOT NULL, -- completed, no_answer, busy, failed
    duration_seconds INTEGER NOT NULL DEFAULT 0,
    recording_url TEXT,
    transcript TEXT DEFAULT '[]', -- JSON array of VoiceTranscriptEntry
    score INTEGER,
    temperature TEXT,
    intent TEXT,
    summary TEXT,
    objections TEXT DEFAULT '[]', -- JSON array
    positive_signals TEXT DEFAULT '[]', -- JSON array
    next_action TEXT DEFAULT 'none',
    follow_up_id TEXT,
    callback_at TEXT,
    interaction_id TEXT UNIQUE,
    started_at TEXT NOT NULL DEFAULT (datetime('now')),
    completed_at TEXT,
    FOREIGN KEY(business_id) REFERENCES businesses(id) ON DELETE CASCADE,
    FOREIGN KEY(lead_id) REFERENCES leads(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_calls_business ON calls(business_id);
CREATE INDEX IF NOT EXISTS idx_calls_lead ON calls(lead_id);
CREATE INDEX IF NOT EXISTS idx_calls_interaction ON calls(interaction_id);

CREATE TABLE IF NOT EXISTS campaigns (
    id TEXT PRIMARY KEY,
    business_id TEXT NOT NULL,
    purpose TEXT NOT NULL,
    calling_hours_start INTEGER NOT NULL DEFAULT 10,
    calling_hours_end INTEGER NOT NULL DEFAULT 19,
    options TEXT NOT NULL DEFAULT '{}', -- JSON object
    status TEXT NOT NULL DEFAULT 'draft', -- draft, running, paused, completed
    total_leads INTEGER NOT NULL DEFAULT 0,
    completed_leads INTEGER NOT NULL DEFAULT 0,
    connected_leads INTEGER NOT NULL DEFAULT 0,
    hot_leads INTEGER NOT NULL DEFAULT 0,
    warm_leads INTEGER NOT NULL DEFAULT 0,
    cost_inr INTEGER NOT NULL DEFAULT 0,
    started_at TEXT,
    completed_at TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY(business_id) REFERENCES businesses(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_campaigns_business ON campaigns(business_id);
CREATE INDEX IF NOT EXISTS idx_campaigns_status ON campaigns(status);

CREATE TABLE IF NOT EXISTS campaign_leads (
    campaign_id TEXT NOT NULL,
    lead_id TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending', -- pending, calling, completed, failed
    PRIMARY KEY(campaign_id, lead_id),
    FOREIGN KEY(campaign_id) REFERENCES campaigns(id) ON DELETE CASCADE,
    FOREIGN KEY(lead_id) REFERENCES leads(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS followups (
    id TEXT PRIMARY KEY,
    business_id TEXT NOT NULL,
    lead_id TEXT NOT NULL,
    call_id TEXT,
    message TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'ready', -- ready, opened, done, dismissed
    opened_at TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY(business_id) REFERENCES businesses(id) ON DELETE CASCADE,
    FOREIGN KEY(lead_id) REFERENCES leads(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_followups_business ON followups(business_id);
CREATE INDEX IF NOT EXISTS idx_followups_status ON followups(status);

CREATE TABLE IF NOT EXISTS callbacks (
    id TEXT PRIMARY KEY,
    business_id TEXT NOT NULL,
    lead_id TEXT NOT NULL,
    lead_name TEXT NOT NULL,
    scheduled_at TEXT NOT NULL,
    note TEXT,
    status TEXT NOT NULL DEFAULT 'scheduled', -- scheduled, done
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY(business_id) REFERENCES businesses(id) ON DELETE CASCADE,
    FOREIGN KEY(lead_id) REFERENCES leads(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_callbacks_business ON callbacks(business_id);
CREATE INDEX IF NOT EXISTS idx_callbacks_status ON callbacks(status);

CREATE TABLE IF NOT EXISTS notifications (
    id TEXT PRIMARY KEY,
    business_id TEXT NOT NULL,
    type TEXT NOT NULL, -- hot_lead, follow_up_ready, callback, campaign
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    route TEXT NOT NULL,
    action_label TEXT NOT NULL DEFAULT 'View',
    is_read INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY(business_id) REFERENCES businesses(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_notifications_business ON notifications(business_id);

CREATE TABLE IF NOT EXISTS devices (
    id TEXT PRIMARY KEY,
    business_id TEXT NOT NULL,
    fcm_token TEXT NOT NULL,
    platform TEXT NOT NULL DEFAULT 'unknown',
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY(business_id) REFERENCES businesses(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS usage (
    id TEXT PRIMARY KEY,
    business_id TEXT NOT NULL UNIQUE,
    plan_name TEXT NOT NULL DEFAULT 'Founding Plan',
    included_minutes INTEGER NOT NULL DEFAULT 1000,
    renews_at TEXT NOT NULL DEFAULT (datetime('now', '+30 days')),
    price_inr INTEGER NOT NULL DEFAULT 4999,
    minutes_used INTEGER NOT NULL DEFAULT 0,
    calls_made INTEGER NOT NULL DEFAULT 0,
    rate_per_minute_inr INTEGER NOT NULL DEFAULT 6,
    FOREIGN KEY(business_id) REFERENCES businesses(id) ON DELETE CASCADE
);
