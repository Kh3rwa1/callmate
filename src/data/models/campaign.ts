export const CAMPAIGN_PURPOSES = [
  "appointment",
  "newLead",
  "followUp",
  "payment",
  "other",
] as const
export type CampaignPurpose = (typeof CAMPAIGN_PURPOSES)[number]

export const CAMPAIGN_PURPOSE_LABELS: Record<CampaignPurpose, string> = {
  appointment: "Appointment",
  newLead: "New lead",
  followUp: "Follow-up",
  payment: "Payment",
  other: "Other",
}

export type CampaignStatus = "draft" | "running" | "completed" | "stopped"

export type Campaign = {
  id: string
  name: string
  purpose: CampaignPurpose
  contactIds: string[]
  startedAt: string
  endedAt: string | null
  status: CampaignStatus
  total: number
  completed: number
  booked: number
  interested: number
  followUps: number
  noAnswer: number
}

export type CampaignTiming = "now" | "scheduled"

export type CampaignDraft = {
  purpose: CampaignPurpose
  timing: CampaignTiming
  scheduledFor?: string
  contactIds: string[]
}
