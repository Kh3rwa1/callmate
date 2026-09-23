export const CALL_STATUSES = ["calling", "connected", "completed", "missed", "failed"] as const
export type CallStatus = (typeof CALL_STATUSES)[number]

export const CALL_OUTCOMES = [
  "interested",
  "booked",
  "followUp",
  "recovered",
  "notInterested",
  "noResponse",
] as const
export type CallOutcome = (typeof CALL_OUTCOMES)[number]

export const CALL_STATUS_META: Record<
  CallStatus,
  { label: string; tone: "green" | "blue" | "amber" | "purple" | "coral" | "neutral" }
> = {
  calling: { label: "Calling", tone: "blue" },
  connected: { label: "Connected", tone: "green" },
  completed: { label: "Completed", tone: "neutral" },
  missed: { label: "Missed", tone: "coral" },
  failed: { label: "Failed", tone: "coral" },
}

export const CALL_OUTCOME_META: Record<
  CallOutcome,
  { label: string; tone: "green" | "blue" | "amber" | "purple" | "coral" | "neutral" }
> = {
  interested: { label: "Interested", tone: "purple" },
  booked: { label: "Appointment booked", tone: "green" },
  followUp: { label: "Follow-up needed", tone: "amber" },
  recovered: { label: "Payment recovered", tone: "green" },
  notInterested: { label: "Not interested", tone: "neutral" },
  noResponse: { label: "No answer", tone: "coral" },
}

export type Call = {
  id: string
  contactId: string
  direction: "inbound" | "outbound"
  status: CallStatus
  startedAt: string
  endedAt: string | null
  duration: number
  outcome: CallOutcome | null
  summary: string
  insight: string
  campaignId?: string
}

export type CallFilter = "all" | "active" | "completed" | "missed"
