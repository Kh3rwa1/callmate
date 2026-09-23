export const FOLLOW_UP_TYPES = ["whatsapp", "call", "payment", "reminder"] as const
export type FollowUpType = (typeof FOLLOW_UP_TYPES)[number]

export type FollowUpStatus = "pending" | "done" | "skipped"

export const FOLLOW_UP_TYPE_META: Record<
  FollowUpType,
  { label: string; tone: "green" | "blue" | "amber" | "purple" | "coral" | "neutral" }
> = {
  whatsapp: { label: "WhatsApp", tone: "green" },
  call: { label: "Call", tone: "blue" },
  payment: { label: "Payment", tone: "amber" },
  reminder: { label: "Reminder", tone: "purple" },
}

export type FollowUp = {
  id: string
  contactId: string
  dateTime: string
  type: FollowUpType
  status: FollowUpStatus
  message: string
}
