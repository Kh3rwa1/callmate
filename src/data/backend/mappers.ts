import type { Call, CallOutcome, CallStatus } from "@/data/models/call"
import type { Campaign, CampaignPurpose, CampaignStatus } from "@/data/models/campaign"
import type { Contact, ContactStatus, TimelineEntry } from "@/data/models/contact"
import type { FollowUp } from "@/data/models/followUp"
import type { CallRow, CampaignRow, ContactRow, FollowUpRow, TimelineRow } from "@/data/backend/types"

/**
 * Backend rows (snake_case, database vocabulary) become the camelCase view models
 * the screens already render. The app's own outcome/status vocabulary is the
 * product language, so the provider's words never reach the interface.
 */

const OUTCOMES: CallOutcome[] = [
  "interested",
  "booked",
  "followUp",
  "recovered",
  "notInterested",
  "noResponse",
]

const CONTACT_STATUSES: ContactStatus[] = [
  "new",
  "calling",
  "followUp",
  "booked",
  "recovered",
  "noResponse",
  "notInterested",
]

const CALL_STATUSES: CallStatus[] = ["calling", "connected", "completed", "missed", "failed"]

const PURPOSES: CampaignPurpose[] = ["appointment", "newLead", "followUp", "payment", "other"]
const CAMPAIGN_STATUSES: CampaignStatus[] = ["draft", "running", "completed", "stopped"]

function oneOf<T extends string>(allowed: T[], value: string | null | undefined, fallback: T): T {
  return allowed.includes(value as T) ? (value as T) : fallback
}

export function mapOutcome(value: string | null | undefined): CallOutcome | null {
  if (!value) return null
  return OUTCOMES.includes(value as CallOutcome) ? (value as CallOutcome) : null
}

export function mapContact(row: ContactRow, timeline: TimelineRow[] = []): Contact {
  return {
    id: row.id,
    name: row.name,
    phone: row.phone,
    avatarColor: row.avatar_color,
    service: row.service,
    status: oneOf(CONTACT_STATUSES, row.status, "new"),
    lastCallAt: row.last_call_at,
    lastCallOutcome: row.last_call_outcome ?? undefined,
    nextFollowUpAt: row.next_follow_up_at,
    appointment: row.appointment
      ? {
          date: row.appointment.date,
          time: row.appointment.time,
          service: row.appointment.service,
          status: oneOf(["scheduled", "completed", "cancelled"], row.appointment.status, "scheduled"),
        }
      : null,
    tags: row.tags ?? [],
    notes: row.notes ?? "",
    recoveredAmount: row.recovered_amount ?? undefined,
    createdAt: row.created_at,
    timeline: timeline.map(mapTimeline),
  }
}

function mapTimeline(row: TimelineRow): TimelineEntry {
  return {
    id: row.id,
    label: row.label,
    detail: row.detail ?? undefined,
    at: row.at,
    kind: oneOf(
      ["call", "status", "message", "created", "appointment"],
      row.kind,
      "status"
    ),
  }
}

export function mapCall(row: CallRow): Call {
  return {
    id: row.id,
    contactId: row.contact_id,
    direction: row.direction === "inbound" ? "inbound" : "outbound",
    status: oneOf(CALL_STATUSES, row.status, "completed"),
    startedAt: row.started_at,
    endedAt: row.ended_at,
    duration: row.duration_seconds ?? 0,
    outcome: mapOutcome(row.outcome),
    summary: row.summary ?? "",
    insight: row.insight ?? "",
    campaignId: row.campaign_id ?? undefined,
  }
}

export function mapCampaign(row: CampaignRow, contactIds: string[] = []): Campaign {
  return {
    id: row.id,
    name: row.name,
    purpose: oneOf(PURPOSES, row.purpose, "other"),
    contactIds,
    startedAt: row.started_at ?? row.scheduled_for ?? new Date().toISOString(),
    endedAt: row.ended_at,
    status: oneOf(CAMPAIGN_STATUSES, row.status, "draft"),
    total: row.total,
    completed: row.completed,
    booked: row.booked,
    interested: row.interested,
    followUps: row.follow_ups,
    noAnswer: row.no_answer,
  }
}

export function mapFollowUp(row: FollowUpRow): FollowUp {
  return {
    id: row.id,
    contactId: row.contact_id,
    dateTime: row.date_time,
    type: oneOf(["call", "whatsapp", "reminder"], row.type, "call"),
    status: oneOf(["pending", "done"], row.status, "pending"),
    message: row.message ?? "",
  }
}
