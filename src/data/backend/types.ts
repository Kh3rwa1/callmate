/**
 * Shapes returned by our backend. They mirror the database columns, which are
 * snake_case; the mappers next to this file convert them into the camelCase view
 * models the screens already use.
 */

export type ContactRow = {
  id: string
  organization_id: string
  name: string
  phone: string
  avatar_color: string
  service: string
  status: string
  last_call_at: string | null
  last_call_outcome: string | null
  next_follow_up_at: string | null
  appointment: { date: string; time: string; service: string; status: string } | null
  tags: string[]
  notes: string
  recovered_amount: number | null
  source: string
  created_at: string
}

export type CallRow = {
  id: string
  organization_id: string
  contact_id: string
  campaign_id: string | null
  direction: string
  status: string
  outcome: string | null
  started_at: string
  ended_at: string | null
  duration_seconds: number
  summary: string
  insight: string
  sarvam_attempt_id: string | null
  deployment_id: string | null
  agent_version: number | null
  agent_variables: Record<string, unknown> | null
}

export type CampaignRow = {
  id: string
  organization_id: string
  name: string
  purpose: string
  status: string
  sarvam_campaign_id: string | null
  scheduled_for: string | null
  started_at: string | null
  ended_at: string | null
  total: number
  completed: number
  booked: number
  interested: number
  follow_ups: number
  no_answer: number
}

export type FollowUpRow = {
  id: string
  organization_id: string
  contact_id: string
  date_time: string
  type: string
  status: string
  message: string
}

export type TimelineRow = {
  id: string
  contact_id: string
  label: string
  detail: string | null
  kind: string
  at: string
}

export type PhoneNumberRow = {
  id: string
  organization_id: string
  number: string
  connection_id: string | null
  inbound_enabled: boolean
  callback_on_missed: boolean
  ring_before_pickup: number
  status: string
}

export type AgentRow = {
  organization_id: string
  name: string
  language: string
  voice: string
  call_style: string
  working_hours_start: string
  working_hours_end: string
  follow_up_enabled: boolean
  follow_up_delay_days: number
  greeting: string | null
  inbound_enabled: boolean
}

export type UsageRow = {
  organization_id: string
  minutes_used: number
  calls_made: number
  plan_name: string
  price_per_month: number
  renews_at: string | null
  cycle_started_at: string | null
  credits_remaining: number
}

export type BootstrapPayload = {
  organization: { id: string; name: string; voiceMode: string }
  phoneNumber: PhoneNumberRow | null
  agent: AgentRow | null
  usage: UsageRow | null
  contacts: ContactRow[]
  calls: CallRow[]
  followUps: FollowUpRow[]
  campaigns: CampaignRow[]
  campaignContacts: Record<string, string[]>
  timeline: Record<string, TimelineRow[]>
}

export type PhoneNumbersPayload = { phoneNumber: PhoneNumberRow | null; providerNumbers: unknown[] }
export type AgentPayload = { agent: AgentRow | null; phoneNumber?: PhoneNumberRow | null }
export type TranscriptPayload = {
  callId: string
  summary: string
  outcome: string | null
  duration: number
  turns: Array<{ id: string; seq: number; speaker: string; text: string; at: string }>
}
