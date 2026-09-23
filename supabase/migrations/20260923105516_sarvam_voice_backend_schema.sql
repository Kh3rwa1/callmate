/*
# Sarvam voice backend — multi-tenant schema

## Why this migration exists
CALLMATE AI is a web front end for a voice-agent product. Until now every screen
read from in-memory mock data. This migration adds the real backend store that
the app talks to, so that call/campaign state survives reloads and is driven by
the real Sarvam Voice Agents platform instead of a timer.

## Architecture / security model (read this first)
The browser NEVER talks to these tables directly. It calls our own backend API
(a Supabase Edge Function). That function holds the `SARVAM_API_KEY` and the
service-role key, enforces `organization_id` scoping on every query, and is the
only thing that can read or write here.

Because the browser has no direct database access, every table below has Row
Level Security ENABLED with NO permissive policy for `anon` or `authenticated`.
That is deny-by-default: anon-key requests see zero rows and can write nothing.
This is stronger than granting anon broad access, and it is deliberate — the
voice provider credentials must never be reachable from the client.

Multi-tenant isolation is enforced in two places:
1. Every tenant-owned table carries `organization_id`, and the backend filters on
   it for every read and write.
2. RLS leaves the whole schema unreachable from the client regardless.

## 1. New tables

### organizations
The tenant. Holds the Sarvam workspace identifiers for that tenant.
- `id` (text, primary key) — our organization id, e.g. "org_demo"
- `name` (text, not null) — display name
- `sarvam_org_id` (text) — Sarvam organization id from the dashboard URL
- `sarvam_workspace_id` (text) — Sarvam workspace id from the dashboard URL
- `sarvam_deployment_id` (text) — the deployed agent id used for calls
- `sarvam_app_version` (integer, default 1) — agent version to run
- `voice_mode` (text, default 'mock') — 'mock' uses local simulation, 'sarvam' calls the real API
- `created_at` (timestamptz)

### ai_agents
The business's AI employee configuration, one row per organization. The
customer-facing settings map onto provider configuration; no provider-internal
fields are exposed to the client.
- `organization_id` (text, primary key, references organizations)
- `name`, `language`, `voice`, `call_style` (text)
- `working_hours_start`, `working_hours_end` (text, "HH:MM")
- `follow_up_enabled` (boolean)
- `follow_up_delay_days` (integer)
- `greeting` (text) — first thing the agent says
- `inbound_enabled` (boolean)
- `updated_at` (timestamptz)

### phone_numbers
The business's inbound number connected to the agent.
- `id` (text, primary key)
- `organization_id` (text, references organizations)
- `number` (text, not null)
- `connection_id` (text) — Sarvam connection (telephony) id used on outbound calls
- `inbound_enabled` (boolean)
- `callback_on_missed` (boolean)
- `ring_before_pickup` (integer)
- `status` (text) — 'connected' | 'pending'
- `created_at` (timestamptz)

### contacts
The customer book. `status` is our own enum and is derived from the provider's
structured outcome, never guessed from transcript text alone.
- `id` (text, primary key)
- `organization_id` (text, references organizations)
- `name`, `phone`, `avatar_color`, `service` (text)
- `status` (text) — new | calling | followUp | booked | recovered | noResponse | notInterested
- `last_call_at` (timestamptz, null)
- `last_call_outcome` (text, null)
- `next_follow_up_at` (timestamptz, null)
- `appointment` (jsonb, null) — { date, time, service, status }
- `tags` (text[]), `notes` (text)
- `recovered_amount` (numeric, null)
- `source` (text) — 'manual' | 'campaign' | 'inbound'
- `created_at` (timestamptz)

### contact_timeline
Append-only history shown on the customer screen.
- `id` (text, primary key), `organization_id`, `contact_id` (references contacts)
- `label`, `detail` (text), `kind` (text), `at` (timestamptz)

### campaigns
An outbound calling round. `sarvam_campaign_id` links to the provider's campaign.
- `id` (text, primary key), `organization_id` (references organizations)
- `name`, `purpose`, `status` (text) — draft | running | completed | stopped
- `sarvam_campaign_id` (text, null)
- `scheduled_for` (timestamptz, null)
- `started_at`, `ended_at` (timestamptz, null)
- counters: `total`, `completed`, `booked`, `interested`, `follow_ups`, `no_answer` (integer)
- `created_at` (timestamptz)

### campaign_contacts
Which customers belong to a campaign, and their per-campaign state.
- `campaign_id` (text, references campaigns), `contact_id` (text, references contacts)
- `organization_id` (text)
- `status` (text) — pending | calling | completed
- primary key (campaign_id, contact_id)

### calls
One row per call attempt, inbound or outbound.
- `id` (text, primary key), `organization_id` (references organizations)
- `contact_id` (text, references contacts), `campaign_id` (text, null)
- `direction` (text) — inbound | outbound
- `status` (text) — calling | connected | completed | missed | failed
- `outcome` (text, null) — our normalised outcome
- `started_at` (timestamptz), `ended_at` (timestamptz, null)
- `duration_seconds` (integer, default 0)
- `summary`, `insight` (text)
- `sarvam_attempt_id` (text, null, unique-ish) — provider attempt id
- `sarvam_call_id` (text, null) — provider call id
- `deployment_id` (text, null), `agent_version` (integer, null)
- `agent_variables` (jsonb, null) — raw structured fields returned by the agent
- `metadata` (jsonb, null)
- `created_at` (timestamptz)

### call_transcripts
Transcript turns, stored separately so the main call list never loads them.
- `id` (text, primary key), `organization_id`, `call_id` (references calls)
- `seq` (integer), `speaker` (text) — ai | customer, `text` (text), `at` (timestamptz)

### follow_ups
The follow-up queue created from call outcomes.
- `id` (text, primary key), `organization_id`, `contact_id` (references contacts)
- `date_time` (timestamptz), `type` (text) — call | whatsapp | reminder
- `status` (text) — pending | done
- `message` (text), `created_at` (timestamptz)

### webhook_events
Every inbound provider webhook, kept for idempotency and audit. The unique key
on `provider_event_id` is what makes replay safe: a redelivered event is
recognised and ignored rather than applied twice.
- `id` (text, primary key), `organization_id` (text, null)
- `provider` (text, default 'sarvam'), `event_type` (text)
- `provider_event_id` (text, unique) — attempt id or delivery id
- `signature_valid` (boolean)
- `payload` (jsonb), `status` (text) — received | processed | ignored | failed
- `error` (text, null), `received_at`, `processed_at` (timestamptz)

### org_usage
Per-organization usage and plan state, used for the usage screen and for
refusing calls when credits run out.
- `organization_id` (text, primary key, references organizations)
- `minutes_used` (numeric, default 0), `calls_made` (integer, default 0)
- `plan_name` (text), `price_per_month` (numeric), `renews_at` (date)
- `cycle_started_at` (date), `credits_remaining` (numeric)
- `updated_at` (timestamptz)

## 2. Modified tables
None. This is the first schema migration.

## 3. Security changes
- RLS is ENABLED on all eleven tables.
- No policies are granted to `anon` or `authenticated`. All access goes through
  the backend Edge Function using the service role, which enforces
  `organization_id` scoping itself. See the security model note above.

## 4. Notes
1. No destructive statements — this migration only creates.
2. Every statement is idempotent (`IF NOT EXISTS`), so a lost response can be
   retried safely with the same filename.
3. Text ids are used deliberately: the app and the provider both use
   human-readable ids for seeds and provider identifiers.
*/

CREATE TABLE IF NOT EXISTS organizations (
  id text PRIMARY KEY,
  name text NOT NULL,
  sarvam_org_id text,
  sarvam_workspace_id text,
  sarvam_deployment_id text,
  sarvam_app_version integer NOT NULL DEFAULT 1,
  voice_mode text NOT NULL DEFAULT 'mock',
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS ai_agents (
  organization_id text PRIMARY KEY REFERENCES organizations(id) ON DELETE CASCADE,
  name text NOT NULL,
  language text NOT NULL,
  voice text NOT NULL,
  call_style text NOT NULL,
  working_hours_start text NOT NULL DEFAULT '09:00',
  working_hours_end text NOT NULL DEFAULT '19:00',
  follow_up_enabled boolean NOT NULL DEFAULT true,
  follow_up_delay_days integer NOT NULL DEFAULT 1,
  greeting text,
  inbound_enabled boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS phone_numbers (
  id text PRIMARY KEY,
  organization_id text NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  number text NOT NULL,
  connection_id text,
  inbound_enabled boolean NOT NULL DEFAULT true,
  callback_on_missed boolean NOT NULL DEFAULT true,
  ring_before_pickup integer NOT NULL DEFAULT 3,
  status text NOT NULL DEFAULT 'connected',
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS contacts (
  id text PRIMARY KEY,
  organization_id text NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  name text NOT NULL,
  phone text NOT NULL,
  avatar_color text NOT NULL DEFAULT '#18C97A',
  service text NOT NULL DEFAULT 'Enquiry',
  status text NOT NULL DEFAULT 'new',
  last_call_at timestamptz,
  last_call_outcome text,
  next_follow_up_at timestamptz,
  appointment jsonb,
  tags text[] NOT NULL DEFAULT '{}',
  notes text NOT NULL DEFAULT '',
  recovered_amount numeric,
  source text NOT NULL DEFAULT 'manual',
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS contact_timeline (
  id text PRIMARY KEY,
  organization_id text NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  contact_id text NOT NULL REFERENCES contacts(id) ON DELETE CASCADE,
  label text NOT NULL,
  detail text,
  kind text NOT NULL DEFAULT 'status',
  at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS campaigns (
  id text PRIMARY KEY,
  organization_id text NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  name text NOT NULL,
  purpose text NOT NULL DEFAULT 'other',
  status text NOT NULL DEFAULT 'draft',
  sarvam_campaign_id text,
  scheduled_for timestamptz,
  started_at timestamptz,
  ended_at timestamptz,
  total integer NOT NULL DEFAULT 0,
  completed integer NOT NULL DEFAULT 0,
  booked integer NOT NULL DEFAULT 0,
  interested integer NOT NULL DEFAULT 0,
  follow_ups integer NOT NULL DEFAULT 0,
  no_answer integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS campaign_contacts (
  campaign_id text NOT NULL REFERENCES campaigns(id) ON DELETE CASCADE,
  contact_id text NOT NULL REFERENCES contacts(id) ON DELETE CASCADE,
  organization_id text NOT NULL,
  status text NOT NULL DEFAULT 'pending',
  PRIMARY KEY (campaign_id, contact_id)
);

CREATE TABLE IF NOT EXISTS calls (
  id text PRIMARY KEY,
  organization_id text NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  contact_id text NOT NULL REFERENCES contacts(id) ON DELETE CASCADE,
  campaign_id text,
  direction text NOT NULL DEFAULT 'outbound',
  status text NOT NULL DEFAULT 'calling',
  outcome text,
  started_at timestamptz NOT NULL DEFAULT now(),
  ended_at timestamptz,
  duration_seconds integer NOT NULL DEFAULT 0,
  summary text NOT NULL DEFAULT '',
  insight text NOT NULL DEFAULT '',
  sarvam_attempt_id text,
  sarvam_call_id text,
  deployment_id text,
  agent_version integer,
  agent_variables jsonb,
  metadata jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS call_transcripts (
  id text PRIMARY KEY,
  organization_id text NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  call_id text NOT NULL REFERENCES calls(id) ON DELETE CASCADE,
  seq integer NOT NULL DEFAULT 0,
  speaker text NOT NULL,
  text text NOT NULL,
  at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS follow_ups (
  id text PRIMARY KEY,
  organization_id text NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  contact_id text NOT NULL REFERENCES contacts(id) ON DELETE CASCADE,
  date_time timestamptz NOT NULL,
  type text NOT NULL DEFAULT 'call',
  status text NOT NULL DEFAULT 'pending',
  message text NOT NULL DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS webhook_events (
  id text PRIMARY KEY,
  organization_id text,
  provider text NOT NULL DEFAULT 'sarvam',
  event_type text NOT NULL,
  provider_event_id text UNIQUE,
  signature_valid boolean NOT NULL DEFAULT false,
  payload jsonb NOT NULL,
  status text NOT NULL DEFAULT 'received',
  error text,
  received_at timestamptz NOT NULL DEFAULT now(),
  processed_at timestamptz
);

CREATE TABLE IF NOT EXISTS org_usage (
  organization_id text PRIMARY KEY REFERENCES organizations(id) ON DELETE CASCADE,
  minutes_used numeric NOT NULL DEFAULT 0,
  calls_made integer NOT NULL DEFAULT 0,
  plan_name text NOT NULL DEFAULT 'Growth',
  price_per_month numeric NOT NULL DEFAULT 2999,
  renews_at date,
  cycle_started_at date,
  credits_remaining numeric NOT NULL DEFAULT 500,
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Indexes for the lookups the backend performs on every request.
CREATE INDEX IF NOT EXISTS contacts_org_idx ON contacts (organization_id, created_at DESC);
CREATE INDEX IF NOT EXISTS contacts_org_status_idx ON contacts (organization_id, status);
CREATE INDEX IF NOT EXISTS contact_timeline_contact_idx ON contact_timeline (contact_id, at DESC);
CREATE INDEX IF NOT EXISTS calls_org_idx ON calls (organization_id, started_at DESC);
CREATE INDEX IF NOT EXISTS calls_contact_idx ON calls (contact_id, started_at DESC);
CREATE INDEX IF NOT EXISTS calls_campaign_idx ON calls (campaign_id);
CREATE UNIQUE INDEX IF NOT EXISTS calls_attempt_idx ON calls (sarvam_attempt_id) WHERE sarvam_attempt_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS transcripts_call_idx ON call_transcripts (call_id, seq);
CREATE INDEX IF NOT EXISTS followups_org_idx ON follow_ups (organization_id, date_time);
CREATE INDEX IF NOT EXISTS campaigns_org_idx ON campaigns (organization_id, created_at DESC);
CREATE INDEX IF NOT EXISTS phone_numbers_org_idx ON phone_numbers (organization_id);
CREATE INDEX IF NOT EXISTS webhook_events_org_idx ON webhook_events (organization_id, received_at DESC);

ALTER TABLE organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_agents ENABLE ROW LEVEL SECURITY;
ALTER TABLE phone_numbers ENABLE ROW LEVEL SECURITY;
ALTER TABLE contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE contact_timeline ENABLE ROW LEVEL SECURITY;
ALTER TABLE campaigns ENABLE ROW LEVEL SECURITY;
ALTER TABLE campaign_contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE calls ENABLE ROW LEVEL SECURITY;
ALTER TABLE call_transcripts ENABLE ROW LEVEL SECURITY;
ALTER TABLE follow_ups ENABLE ROW LEVEL SECURITY;
ALTER TABLE webhook_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE org_usage ENABLE ROW LEVEL SECURITY;
