export const CONTACT_STATUSES = [
  "new",
  "calling",
  "followUp",
  "booked",
  "recovered",
  "noResponse",
  "notInterested",
] as const

export type ContactStatus = (typeof CONTACT_STATUSES)[number]

export const CONTACT_STATUS_META: Record<
  ContactStatus,
  { label: string; short: string; tone: "green" | "blue" | "amber" | "purple" | "coral" | "neutral" }
> = {
  new: { label: "New", short: "New", tone: "neutral" },
  calling: { label: "Calling", short: "Calling", tone: "blue" },
  followUp: { label: "Follow up", short: "Follow up", tone: "amber" },
  booked: { label: "Booked", short: "Booked", tone: "green" },
  recovered: { label: "Recovered", short: "Recovered", tone: "green" },
  noResponse: { label: "No answer", short: "No answer", tone: "coral" },
  notInterested: { label: "Not interested", short: "Not interested", tone: "neutral" },
}

export type AppointmentStatus = "scheduled" | "completed" | "cancelled"

export type Appointment = {
  date: string
  time: string
  service: string
  status: AppointmentStatus
}

export type TimelineEntry = {
  id: string
  label: string
  detail?: string
  at: string
  kind: "call" | "status" | "message" | "created" | "appointment"
}

export type Contact = {
  id: string
  name: string
  phone: string
  avatarColor: string
  service: string
  status: ContactStatus
  lastCallAt: string | null
  lastCallOutcome?: string
  nextFollowUpAt: string | null
  appointment: Appointment | null
  tags: string[]
  notes: string
  recoveredAmount?: number
  createdAt: string
  timeline: TimelineEntry[]
}
